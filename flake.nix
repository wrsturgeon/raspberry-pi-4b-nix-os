{
  description = "System flake for a Raspberry Pi 4 Model B";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      flake-utils,
      nix-filter,
      nixpkgs,
      self,
    }:
    (flake-utils.lib.eachDefaultSystem (
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

                  if [ -f '${filename}' ]
                  then
                    echo 'Image already downloaded'
                  else
                    if [ -f '${filename}.zst' ]
                    then
                      echo 'Compressed image already downloaded'
                    else
                      ${pkgs.wget}/bin/wget 'https://hydra.nixos.org/build/281309072/download/1/${filename}.zst' --show-progress
                      cp ${filename}.zst ${filename}.zst.backup
                    fi
                    ${pkgs.zstd}/bin/unzstd -d ${filename}.zst
                    cp ${filename} ${filename}.backup
                  fi

                  echo 'Are you SURE you want to FULLY OVERWRITE `'"''${1}"'` with the contents of `./${filename}`? (y/n)'
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
    ))
    // (
      let
        system = "aarch64-linux";
        pkgs = import nixpkgs { inherit system; };

        user = {
          name = "pi";
          password = "raspberry";
        };
        wlan-interface = "wlan0";
        host = {
          name = "stonk";
        };
        filesystem = "ext4"; # "btrfs"; # "bcachefs"; # "ext4";

        networks = {
          "The3Sturges" = "55145589";
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
              grub.enable = false;
              generic-extlinux-compatible.enable = true;
            };
            supportedFilesystems = [ filesystem ];
          };

          environment.systemPackages = with pkgs; [
            git
            vim
          ];

          fileSystems = {
            "/" = {
              device = "/dev/disk/by-label/NIXOS_SD";
              fsType = filesystem;
              options = [ "noatime" ];
            };
          };

          networking = {
            hostName = host.name;
            wireless = {
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

          programs.direnv.enable = true;

          services.openssh.enable = true;

          users = {
            mutableUsers = false;
            users."${user.name}" = {
              isNormalUser = true;
              password = user.password;
              extraGroups = [ "wheel" ];
            };
          };

          hardware.enableRedistributableFirmware = true;
          system.stateVersion = "25.05";

        };
        configuration = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ config ];
        };
      in
      {
        nixosConfigurations = {
          nixos = configuration;
          "${host.name}" = configuration;
        };
      }
    );
}
