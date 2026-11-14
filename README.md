# Charpentier OS

Le système du ThinkPad X250, machine d'écriture dédiée : NixOS, une session sway sans décor où l'app Charpentier occupe tout l'écran, et la clé USB qui l'installe. C'est l'étape 5 du plan de l'app ([`charpentier-writer/docs/PLAN.md`](../charpentier-writer/docs/PLAN.md), phases 5.9 et 5.9 bis) ; l'installateur suit [`docs/DESIGN.md` §4.12](../charpentier-writer/docs/DESIGN.md) « Installation ».

L'app vit dans son propre dépôt, [`chatelp/charpentier`](https://github.com/chatelp/charpentier) (`charpentier-writer` en local), qui construit aussi son paquet Nix (`nix/charpentier.nix`). Ce dépôt-ci la prend comme entrée du flake, sur GitHub, figée à un commit par `flake.lock`.

## Construire

Sur une machine x86_64 sous Linux avec Nix (le Yoga L13 de Pierre, sous WSL2), `scripts/nix.sh` appelle Nix directement. Sur le Mac, qui n'a pas Nix, il le lance dans le conteneur officiel `nixos/nix` sous [OrbStack](https://orbstack.dev) (x86_64, par Rosetta : lent). Jamais sur le prodesk2021.

```bash
scripts/nix.sh build .#charpentier                        # le paquet de l'app
scripts/nix.sh build .#nixosConfigurations.x250.config.system.build.toplevel
scripts/nix.sh --out dist/installer build .#installer     # l'image de la clé
scripts/try-installer.sh                                  # l'essayer en machine virtuelle (Linux, KVM)
scripts/try-plymouth.sh start                             # l'écran du mot de passe du disque, dans une fenêtre (WSLg)
nix run .#test-installer                                  # la clé essayée seule de bout en bout, sans fenêtre (OCR)
CHARPENTIER_TOKEN=… scripts/flash-installer.sh          # écrire la dernière image publiée sur une clé (depuis le Mac)
scripts/flash-installer.sh --local                        # ou celle construite ici
scripts/nix.sh flake update charpentier                   # passer au dernier commit de l'app
scripts/nix.sh --clean                                    # rendre le disque
```

Le cache Nix prend 10 à 15 Go au plus fort (le store, ou sur le Mac le volume Docker `charpentier-nix`). `--clean` le vide ; la construction suivante le retélécharge. Seule la branche `main` de l'app, poussée sur GitHub, est prise : pour essayer une app pas encore poussée, `--override-input charpentier path:<chemin de l'app>` (par exemple `path:../charpentier-writer`, si elle est clonée à côté).

`scripts/try-installer.sh` démarre l'image dans une machine virtuelle à la façon du X250 (UEFI, disque SATA vierge, la clé en USB, 4 Go), avec KVM si `/dev/kvm` est là ; `--disk` redémarre ensuite sur le disque installé. Ne jamais démarrer la clé sur la machine qui construit : elle effacerait son disque.

`nix run .#test-installer` fait la même chose sans personne au clavier : il lit l'écran par OCR et tape par le moniteur de QEMU (clavier azerty, disque effacé, mot de passe, copie, clé retirée, redémarrage, un mot de passe faux refusé puis le bon, l'écran « Bienvenue » de l'app). Les captures de chaque étape restent dans `dist/test-installer`. C'est l'essai que la CI fait sur chaque pull request.

## Mises à jour du X250

Le X250 ne reçoit que des versions numérotées (D-31, phase 5.11 du plan de l'app) :

1. Une release `vX.Y.Z` de l'app envoie ici un `repository_dispatch` `app-release`. `.github/workflows/app-release.yml` fait viser ce tag à l'entrée `charpentier` du flake, relance `nix flake lock` et ouvre la pull request « app vX.Y.Z », réglée pour se fusionner seule.
2. `.github/workflows/ci.yml`, sur chaque pull request : les trois systèmes, la clé, puis `nix run .#test-installer` en machine virtuelle avec KVM. C'est le seul accord que main demande.
3. `.github/workflows/publish.yml`, quand la pull request arrive sur main : les trois systèmes copiés, signés, dans le cache du serveur de synchronisation (`https://charpentier.chatel.pm/nix-cache`), puis le pointeur `/api/updates/latest` (version, notes, systèmes), puis, à part, l'image de la clé (`/api/installer/<version>`, que `scripts/flash-installer.sh` télécharge). Cloudflare, devant le serveur, refuse toute requête de plus de 100 Mo : `scripts/publish.py` n'envoie que les chemins qui manquent au cache, et en morceaux de 95 Mio au plus (en-têtes `X-Part` et `X-Checksum-SHA256`) ; les NAR partent avant leurs `.narinfo`. Un changement du seul système part par une release de ce dépôt, taguée `X.Y.Z-N` (la version de l'app, puis celle du système) ; les autres commits sur main ne partent pas.

À régler une fois, dans GitHub, par Pierre :

- Secrets de ce dépôt :
  - `CHARPENTIER_OS_BOT_TOKEN` : un jeton fin limité à `chatelp/charpentier-os`, droits Contents et Pull requests en écriture. `GITHUB_TOKEN` ne suffit pas : ce qu'il pousse ou fusionne ne déclenche ni la CI de la pull request ni la publication.
  - `CHARPENTIER_CACHE_TOKEN` : le jeton de la CI sur le serveur (`docker compose exec server node main.js create-ci-token github-actions`).
  - `NIX_SIGNING_KEY` : la clé secrète de signature `charpentier-x250-1`, faite sur le Yoga L13 sans être affichée, posée là et gardée en secours dans le gestionnaire de mots de passe de Pierre. Sa clé publique est `hosts/x250/cache-key.pub`, que le X250 lira à la phase 5.12.
- Réglages : « Allow auto-merge » ; une règle sur main qui demande une pull request et le check « systèmes, clé et essai en VM », sans approbation.
- Dans l'app : le jeton `CHARPENTIER_OS_DISPATCH` qui envoie le `repository_dispatch`.

## Contenu

- `flake.nix` : `nixosConfigurations.x250`, `x250-bepo`, `x250-qwerty` (le clavier choisi à l'installation), `packages.installer` (l'ISO).
- `hosts/x250/` : le système (démarrage, chiffrement LUKS, session, réseau, son, impression, autorisations) et `vm.nix` pour l'essayer en machine virtuelle.
- `hosts/x250/plymouth/` : l'écran du mot de passe du disque (DESIGN §4.12 « Verrouillage »). Plymouth, dans l'initrd sous systemd, avec un thème `script` : systemd-cryptsetup lui demande le mot de passe, il dessine avec une vraie police (JetBrains Mono, licence OFL jointe) et lit le clavier de la console, donc la disposition choisie à l'installation. Sans lui, l'invite serait le texte anglais de systemd. `scripts/try-plymouth.sh` l'essaie dans une fenêtre, sans machine virtuelle.
- `installer/` : l'image de la clé et `install.sh`, l'installateur en mode texte.
- `scripts/` : `nix.sh` (construire), `try-installer.sh` (essayer la clé en machine virtuelle), `test-installer.py` (l'essayer seule, `nix run .#test-installer`), `try-plymouth.sh` (l'écran du mot de passe, dans une fenêtre), `publish.py` (envoyer au serveur, en morceaux) et `flash-installer.sh` (écrire la clé depuis le Mac, l'image publiée ou `--local`).
- `.github/workflows/` : `app-release.yml`, `ci.yml` et `publish.yml`, les mises à jour du X250.

## Ce que l'app attend du système

C'est le contrat entre les deux dépôts : un changement d'un côté demande souvent le changement correspondant de l'autre. Côté app, il est lu par le service `System` (`packages/platform-desktop/src/main/system`) et par `apps/desktop/src/main/index.ts`.

- **Lancement** : `charpentier --appliance`, sous sway (Wayland, `NIXOS_OZONE_WL=1`), relancé s'il s'arrête. L'app est alors tout l'écran, sans barre de menus.
- **Verrou** : la session sway a un mode `locked`, où aucun raccourci de sway ne passe ; l'app y entre et en sort par `swaymsg mode locked|default`.
- **Clavier** : `/etc/charpentier/keyboard` contient `azerty`, `bepo` ou `qwerty`.
- **Outils**, dans le `PATH` de la session, utilisables par l'utilisateur `auteur` sans mot de passe (règles polkit) : `nmcli`, `bluetoothctl`, `brightnessctl`, `wpctl`, `timedatectl`, `swaymsg`, `swayidle`, `wlsunset`, `lsblk`, `udevadm`, `udisksctl`, `lpstat`, `lp`, `lspci`, `systemctl` (veille, redémarrage, arrêt).
- **Fichiers lus** : `/sys/class/power_supply`, `/sys/class/backlight`, `/sys/class/thermal`, `/sys/class/dmi/id/product_version`, `/sys/block`, `/proc/stat`, `/proc/cpuinfo`, `/proc/meminfo`, `/proc/uptime`.
- **Services** : NetworkManager, BlueZ, PipeWire, UPower, UDisks2, CUPS avec Avahi.
