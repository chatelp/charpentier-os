{
  # Charpentier as an installable system: the X250, writing device (phases 5.9
  # and 5.9 bis of the app's docs/PLAN.md). The app comes from its own
  # repository, pinned to a commit by flake.lock; its package is built there
  # (nix/charpentier.nix). Built with scripts/nix.sh: the Mac has no Nix.
  description = "Charpentier OS : le système du X250 et sa clé d'installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    # The app: its main branch, pushed to GitHub. Moving to a newer app:
    # `scripts/nix.sh flake update charpentier`; an app not pushed yet:
    # `--override-input charpentier path:<the app's checkout>`.
    charpentier.url = "github:chatelp/charpentier";
    charpentier.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      charpentier,
      ...
    }:
    let
      system = "x86_64-linux";
      app = charpentier.packages.${system}.charpentier;
      # The X250's system, with the keyboard chosen at installation.
      x250 =
        keyboard:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs.charpentier = app;
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-x250
            ./hosts/x250
            ./hosts/x250/vm.nix
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
        charpentier = app;
        # The install key's image (phase 5.9 bis), written by scripts/flash-installer.sh.
        installer =
          (nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              version = app.version;
              systems = nixpkgs.lib.mapAttrs (_: s: s.config.system.build.toplevel) {
                azerty = self.nixosConfigurations.x250;
                bepo = self.nixosConfigurations.x250-bepo;
                qwerty = self.nixosConfigurations.x250-qwerty;
              };
            };
            modules = [ ./installer ];
          }).config.system.build.isoImage;
        default = self.packages.${system}.installer;
        # The install key tried from end to end in a virtual machine, by OCR
        # and the QEMU monitor (scripts/test-installer.py): here and in CI.
        test-installer =
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          pkgs.writeShellApplication {
            name = "test-installer";
            runtimeInputs = [
              pkgs.python3
              pkgs.imagemagick
              # French only (and English, which Tesseract requires), not its 1 Go of languages.
              (pkgs.tesseract.override {
                enableLanguages = [
                  "eng"
                  "fra"
                ];
              })
            ];
            # From the repository's root: it reads dist/installer, writes dist/test-installer.
            text = ''exec python3 scripts/test-installer.py "$@"'';
          };
      };
    };
}
