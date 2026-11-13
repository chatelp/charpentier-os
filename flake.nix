{
  # The X250, writing device (docs/PLAN.md phases 5.8 to 5.9 bis): the app's
  # package, the NixOS system and the install key. Built on a Linux machine
  # (scripts/nix-remote.sh): the Mac has no Nix.
  description = "Charpentier : l'app et le système du X250";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        charpentier = pkgs.callPackage ./nix/charpentier.nix { };
        default = self.packages.${system}.charpentier;
      };
    };
}
