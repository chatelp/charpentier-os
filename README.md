# Charpentier OS

Le système du ThinkPad X250, machine d'écriture dédiée : NixOS, une session sway sans décor où l'app Charpentier occupe tout l'écran, et la clé USB qui l'installe. C'est l'étape 5 du plan de l'app ([`charpentier-writer/docs/PLAN.md`](../charpentier-writer/docs/PLAN.md), phases 5.9 et 5.9 bis) ; l'installateur suit [`docs/DESIGN.md` §4.12](../charpentier-writer/docs/DESIGN.md) « Installation ».

L'app vit dans son propre dépôt, `charpentier-writer`, qui construit aussi son paquet Nix (`nix/charpentier.nix`). Ce dépôt-ci la prend comme entrée du flake, figée à un commit par `flake.lock`.

## Construire

Le Mac n'a pas Nix : tout passe par `scripts/nix.sh`, qui lance Nix dans le conteneur officiel `nixos/nix` sous [OrbStack](https://orbstack.dev) (x86_64, par Rosetta). Les deux dépôts doivent être voisins (`~/Dev/charpentier-writer`, `~/Dev/charpentier-os`), sinon `CHARPENTIER_APP=<chemin de l'app>`.

```bash
scripts/nix.sh build .#charpentier                        # le paquet de l'app
scripts/nix.sh build .#nixosConfigurations.x250.config.system.build.toplevel
scripts/nix.sh --out dist/installer build .#installer     # l'image de la clé
scripts/flash-installer.sh                                # l'écrire sur une clé
scripts/nix.sh flake update charpentier                   # passer au dernier commit de l'app
scripts/nix.sh --clean                                    # rendre le disque
```

Le cache Nix (volume Docker `charpentier-nix`) prend 10 à 15 Go au plus fort, sur le disque interne du Mac. `--clean` le supprime ; la construction suivante le retélécharge. Seule la branche `main` de l'app, commitée, est prise : pour essayer une app non commitée, `--override-input charpentier path:/src/charpentier-writer`.

## Contenu

- `flake.nix` : `nixosConfigurations.x250`, `x250-bepo`, `x250-qwerty` (le clavier choisi à l'installation), `packages.installer` (l'ISO).
- `hosts/x250/` : le système (démarrage, chiffrement LUKS, session, réseau, son, impression, autorisations) et `vm.nix` pour l'essayer en machine virtuelle.
- `installer/` : l'image de la clé et `install.sh`, l'installateur en mode texte.
- `scripts/` : `nix.sh` (construire) et `flash-installer.sh` (écrire la clé depuis le Mac).

## Ce que l'app attend du système

C'est le contrat entre les deux dépôts : un changement d'un côté demande souvent le changement correspondant de l'autre. Côté app, il est lu par le service `System` (`packages/platform-desktop/src/main/system`) et par `apps/desktop/src/main/index.ts`.

- **Lancement** : `charpentier --appliance`, sous sway (Wayland, `NIXOS_OZONE_WL=1`), relancé s'il s'arrête. L'app est alors tout l'écran, sans barre de menus.
- **Verrou** : la session sway a un mode `locked`, où aucun raccourci de sway ne passe ; l'app y entre et en sort par `swaymsg mode locked|default`.
- **Clavier** : `/etc/charpentier/keyboard` contient `azerty`, `bepo` ou `qwerty`.
- **Outils**, dans le `PATH` de la session, utilisables par l'utilisateur `auteur` sans mot de passe (règles polkit) : `nmcli`, `bluetoothctl`, `brightnessctl`, `wpctl`, `timedatectl`, `swaymsg`, `swayidle`, `wlsunset`, `lsblk`, `udevadm`, `udisksctl`, `lpstat`, `lp`, `lspci`, `systemctl` (veille, redémarrage, arrêt).
- **Fichiers lus** : `/sys/class/power_supply`, `/sys/class/backlight`, `/sys/class/thermal`, `/sys/class/dmi/id/product_version`, `/sys/block`, `/proc/stat`, `/proc/cpuinfo`, `/proc/meminfo`, `/proc/uptime`.
- **Services** : NetworkManager, BlueZ, PipeWire, UPower, UDisks2, CUPS avec Avahi.
