# The X250's disk as installer/install.sh lays it out, for nixos-anywhere
# (phase 5.10 bis): a 1 Go EFI partition « demarrage » (FAT32, DEMARRAGE) and
# the rest in LUKS2, « charpentier », opened as « racine » (ext4, racine).
# The development variant only: it formats, the system's own fileSystems
# and LUKS settings (./default.nix) stay what mounts it.
{ config, lib, ... }:
{
  options.charpentier.dev.disk = lib.mkOption {
    type = lib.types.str;
    default = "/dev/sda";
    description = "The disk nixos-anywhere erases (the X250's SATA disk, or the VM's).";
  };

  config.disko = {
    enableConfig = false;
    devices.disk.x250 = {
      type = "disk";
      device = config.charpentier.dev.disk;
      content = {
        type = "gpt";
        partitions = {
          demarrage = {
            label = "demarrage";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [
                "-F"
                "32"
                "-n"
                "DEMARRAGE"
              ];
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          charpentier = {
            label = "charpentier";
            size = "100%";
            type = "8309";
            content = {
              type = "luks";
              name = "racine";
              # Given by nixos-anywhere (--disk-encryption-keys), never stored.
              passwordFile = "/tmp/disque.key";
              settings.allowDiscards = true;
              extraFormatArgs = [
                "--type"
                "luks2"
              ];
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = [
                  "-L"
                  "racine"
                ];
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
