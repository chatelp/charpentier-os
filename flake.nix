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
    {
      self,
      nixpkgs,
      nixos-hardware,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # The X250's system, with the keyboard chosen at installation.
      x250 =
        keyboard:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs.charpentier = self.packages.${system}.charpentier;
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-x250
            ./nix/hosts/x250
            ./nix/hosts/x250/vm.nix
            { charpentier.keyboard = keyboard; }
          ];
        };
    in
    {
      nixosConfigurations = {
        x250 = x250 "azerty";
        x250-bepo = x250 "bepo";
        x250-qwerty = x250 "qwerty";
      };

      packages.${system} = {
        charpentier = pkgs.callPackage ./nix/charpentier.nix { };
        default = self.packages.${system}.charpentier;
        # The install key's image (phase 5.9 bis), written by scripts/flash-installer.sh.
        installer =
          (nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              version = self.packages.${system}.charpentier.version;
              systems = nixpkgs.lib.mapAttrs (_: s: s.config.system.build.toplevel) {
                azerty = self.nixosConfigurations.x250;
                bepo = self.nixosConfigurations.x250-bepo;
                qwerty = self.nixosConfigurations.x250-qwerty;
              };
            };
            modules = [ ./nix/installer ];
          }).config.system.build.isoImage;
      };
    };
}
