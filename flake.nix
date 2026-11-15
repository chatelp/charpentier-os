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
    charpentier.url = "github:chatelp/charpentier/v0.1.0";
    charpentier.inputs.nixpkgs.follows = "nixpkgs";
    # The disk's layout for nixos-anywhere (development variant only).
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      charpentier,
      disko,
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
      # The development variant (phase 5.10 bis, hosts/x250/dev.nix): SSH by
      # key from the home network, the app's test mode. Its keys: the build
      # machine's, in hosts/x250/dev-keys.pub (one per line).
      lib = nixpkgs.lib;
      devKeys = ./hosts/x250/dev-keys.pub;
      x250-dev =
        keyboard:
        (x250 keyboard).extendModules {
          modules = [
            ./hosts/x250/dev.nix
            disko.nixosModules.disko
            ./hosts/x250/disko.nix
            {
              charpentier.dev.authorizedKeys = lib.optionals (builtins.pathExists devKeys) (
                lib.filter (l: l != "" && !lib.hasPrefix "#" l) (lib.splitString "\n" (builtins.readFile devKeys))
              );
            }
          ];
        };
      # An install key's image, for the given systems (one per keyboard),
      # named after them: charpentier-x250-<version>.iso, or -dev- for the
      # development key, never mistaken for the other when written.
      installerSystem =
        module: systems:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            version = app.version;
            systems = nixpkgs.lib.mapAttrs (_: s: s.config.system.build.toplevel) systems;
          };
          modules = [ module ];
        };
      installerOf =
        name: systems:
        (installerSystem {
          imports = [ ./installer/iso.nix ];
          image.baseName = lib.mkOverride 40 "${name}-${app.version}";
        } systems).config.system.build.isoImage;
      # The same installer from the network (phase 5.9 ter): bzImage, initrd
      # and cmdline, which the CI sends to the sync server for Pixiecore.
      netbootOf =
        systems:
        let
          inherit (installerSystem ./installer/netboot.nix systems) config;
          build = config.system.build;
        in
        nixpkgs.legacyPackages.${system}.runCommand "charpentier-x250-netboot-${app.version}" { } ''
          mkdir $out
          ln -s ${build.kernel}/${config.system.boot.loader.kernelFile} $out/bzImage
          ln -s ${build.netbootRamdisk}/initrd $out/initrd
          echo "init=${build.toplevel}/init ${toString config.boot.kernelParams}" > $out/cmdline
        '';
    in
    {
      nixosConfigurations = {
        x250 = x250 "azerty";
        x250-bepo = x250 "bepo";
        x250-qwerty = x250 "qwerty";
        # Never built nor published by CI (5.11): the build machine's only.
        x250-dev = x250-dev "azerty";
        x250-dev-bepo = x250-dev "bepo";
        x250-dev-qwerty = x250-dev "qwerty";
      };

      packages.${system} = {
        charpentier = app;
        # The install key's image (phase 5.9 bis), written by scripts/flash-installer.sh.
        installer = installerOf "charpentier-x250" {
          azerty = self.nixosConfigurations.x250;
          bepo = self.nixosConfigurations.x250-bepo;
          qwerty = self.nixosConfigurations.x250-qwerty;
        };
        # The same key with the development variant: the first installation
        # of a development X250 (or VM), by hand; never published.
        installer-dev = installerOf "charpentier-x250-dev" {
          azerty = self.nixosConfigurations.x250-dev;
          bepo = self.nixosConfigurations.x250-dev-bepo;
          qwerty = self.nixosConfigurations.x250-dev-qwerty;
        };
        netboot = netbootOf {
          azerty = self.nixosConfigurations.x250;
          bepo = self.nixosConfigurations.x250-bepo;
          qwerty = self.nixosConfigurations.x250-qwerty;
        };
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
