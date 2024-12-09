{
  description = "System flake for a Raspberry Pi 4 Model B";
  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      disko,
      flake-utils,
      nixos-hardware,
      nixpkgs,
      self,
    }:
    let
      for-dev = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          apps =
            builtins.mapAttrs
              (app: script: {
                program = "${pkgs.writeShellScriptBin app ''
                  #!${pkgs.bash}/bin/bash
                  set -eu
                  set -o pipefail

                  ${script}
                ''}/bin/${app}";
                type = "app";
              })
              {
                boot = ''
                  if [ "''${EUID}" -ne '0' ]
                  then
                    echo 'Please run as root'
                    exit 1
                  fi

                  set -x
                  mount /dev/disk/by-label/FIRMWARE /mnt
                  BOOTFS=/mnt FIRMWARE_RELEASE_STATUS=stable ${pkgs.raspberrypi-eeprom}/bin/rpi-eeprom-update -d -a

                  nixos-rebuild boot --flake .
                  reboot
                '';
                default = ''
                  ${pkgs.git}/bin/git fetch origin
                  ${pkgs.git}/bin/git reset --hard origin/main
                  nixos-rebuild switch --flake ${./.}
                  nix-collect-garbage -d
                  nix-store --optimise
                  nix store gc
                  nix store optimise
                  echo 'Connected to `'"$(iwgetid -r)"'`'
                '';
                flash-sd-card =
                  let
                    filename = "nixos-sd-image-25.05beta717074.d0797a04b81c-aarch64-linux.img";
                  in
                  ''
                    set +u
                    if [ -z "''${1}" ]
                    then
                      echo 'Requires an argument'
                      exit 1
                    fi
                    set -u

                    if [ ! -d .images ]
                    then
                      mkdir .images
                    fi

                    if [ -f '.images/${filename}' ]
                    then
                      echo 'Image already downloaded'
                    else
                      cd .images
                      if [ -f '${filename}.zst' ]
                      then
                        echo 'Compressed image already downloaded'
                      else
                        ${pkgs.wget}/bin/wget 'https://hydra.nixos.org/build/281309072/download/1/${filename}.zst' --show-progress
                        cp ${filename}.zst ${filename}.zst.backup
                      fi
                      ${pkgs.zstd}/bin/unzstd -d ${filename}.zst
                      cp ${filename} ${filename}.backup
                      cd ..
                    fi

                    echo 'Are you SURE you want to FULLY OVERWRITE `'"''${1}"'` with the contents of `./.images/${filename}`? (y/n)'
                    read yn
                    if [ "''${yn}" = "y" ]
                    then
                      set -x
                      diskutil unmountDisk "''${1}"
                      sudo ${pkgs.coreutils}/bin/dd if='${filename}' of="''${1}" bs=4096 conv=fsync status=progress
                    else
                      echo 'answered "'"''${yn}"'" (not "y"); exiting...'
                    fi
                  '';
              };
          devShells.default = pkgs.mkShell { };
        }
      );
      for-pi =
        let
          system = "aarch64-linux";
          pkgs = import nixpkgs { inherit system; };

          user = {
            name = "pi";
            password = "raspberry";
          };
          wlan-interface = "wlan0";
          host.name = "stonk";
          filesystem-format = "ext4"; # "btrfs"; # "bcachefs"; # "ext4";

          networks = {
            "The3Sturges" = "55145589";
            "Will Sturgeon" = "coffeecoffee";
            "sm-main" = "spectralwap99";
          };

          config = {

            boot = {
              kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
              initrd.availableKernelModules = [
                "xhci_pci"
                "usbhid"
                "usb_storage"
              ];
              loader = {
                grub.enable = false; # NOTE: FALSE!
                generic-extlinux-compatible.enable = true;
              };
              supportedFilesystems = [ filesystem-format ];
            };

            environment.systemPackages = with pkgs; [
              libraspberrypi
              raspberrypi-eeprom
              vim
            ];

            fileSystems = {
              "/" = {
                device = "/dev/disk/by-label/NIXOS_SD";
                fsType = filesystem-format;
                options = [ "noatime" ];
              };
            };

            hardware = {
              deviceTree = {
                enable = true;
                filter = "*rpi-4-*.dtb";
              };
              enableRedistributableFirmware = true;
              raspberry-pi."4" = {
                apply-overlays-dtmerge.enable = true;
                # fkms-3d.enable = true;
              };
            };

            networking = {
              hostName = host.name;
              wireless = {
                # NOTE: THIS REALLY MEANS `wpa_supplicant`
                enable = true;
                # networks."${ssid.name}".psk = ssid.password;
                networks = builtins.mapAttrs (_: psk: { inherit psk; }) networks;
                interfaces = [ wlan-interface ];
              };
            };

            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];

            programs = {
              direnv.enable = true;
              git.enable = true;
            };

            services = {
              openssh = {
                enable = true;
                ports = [ 22 ];
                settings = {
                  PasswordAuthentication = true;
                  UseDns = true;
                };
              };
            };

            system.stateVersion = "25.05";

            users = {
              mutableUsers = false;
              users."${user.name}" = {
                isNormalUser = true;
                password = user.password;
                extraGroups = [ "wheel" ];
              };
            };
          };

          pi-disk = {
            disko.devices.disk.main = {
              type = "disk";
              device = "mmcblk0";
              content = {
                type = "gpt";
                partitions = {
                  MBR = {
                    priority = 0;
                    size = "1M";
                    type = "EF02";
                  };
                  ESP = {
                    priority = 1;
                    size = "500M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                    };
                  };
                  root = {
                    priority = 2;
                    size = "100%";
                    content = {
                      type = "filesystem";
                      format = filesystem-format;
                      mountpoint = "/";
                    };
                  };
                };
              };
            };
          };

          configuration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              config
              disko.nixosModules.disko
              nixos-hardware.nixosModules.raspberry-pi-4
              pi-disk
            ];
          };

        in
        {
          nixosConfigurations = {
            nixos = configuration;
            "${host.name}" = configuration;
          };
        };
    in
    for-dev // for-pi;
}
