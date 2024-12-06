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
    // {
      packages =
        let
          system = "aarch64";
          pkgs = import nixpkgs { inherit system; };
          config =
            let
              user = {
                name = "pi";
                password = "raspberry";
              };
              ssid = {
                name = "sm-main";
                password = "spectralwap99";
              };
              wlan-interface = "wlan0";
              host = {
                name = "myhostname";
              };
              filesystem = "bcachefs"; # "ext4";
            in
            {

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
                  networks."${ssid.name}".psk = ssid.password;
                  interfaces = [ wlan-interface ];
                };
              };

              environment.systemPackages = with pkgs; [ vim ];

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
        in
        {
          ${system}.nixosConfigurations.pi = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ config ];
          };
        };
    };
}
