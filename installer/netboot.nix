# The installer from the network (phase 5.9 ter, D-32): the same installer,
# as a kernel, an initrd (the system in memory, about 2.5 Go) and their
# command line, which the sync server hands to Pixiecore for the X250's MAC
# only. No key to pull at the end.
{
  lib,
  modulesPath,
  systems,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/netboot/netboot-minimal.nix"
    ./.
  ];

  charpentier.installer.netboot = true;
  # The X250's systems, one per keyboard, already built: nothing to download.
  netboot.storeContents = lib.attrValues systems;
  netboot.squashfsCompression = "zstd -Xcompression-level 6";
}
