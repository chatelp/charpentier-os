# The X250 in a virtual machine (`nix build .#nixosConfigurations.x250.config.system.build.vm`):
# the same system, without the encrypted disk, at the X250's 1920 × 1080, to
# check on the build machine that it starts straight on the app.
{ lib, ... }:
{
  virtualisation.vmVariant = {
    boot.initrd.luks.devices = lib.mkForce { };
    virtualisation = {
      memorySize = 4096;
      cores = 2;
      resolution = {
        x = 1920;
        y = 1080;
      };
      qemu.options = [ "-vga none -device virtio-gpu-pci,xres=1920,yres=1080" ];
    };
  };
}
