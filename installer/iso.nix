# The install key (phase 5.9 bis): an ISO written on a USB key, loaded in
# memory (the key may be pulled at the end).
{
  lib,
  modulesPath,
  systems,
  version,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./.
  ];

  image.baseName = lib.mkForce "charpentier-x250-${version}";
  isoImage.volumeID = "CHARPENTIER";
  isoImage.appendToMenuLabel = "";
  # The X250's systems, one per keyboard, already built: nothing to download.
  isoImage.storeContents = lib.attrValues systems;
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  boot.kernelParams = lib.mkBefore [ "copytoram" ];
}
