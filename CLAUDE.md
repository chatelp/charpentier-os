# CLAUDE.md : Charpentier OS

Le système installable du X250 pour l'app Charpentier (dépôt voisin `../charpentier-writer`, ses principes et son `CLAUDE.md` s'appliquent). Présentation, commandes et contrat avec l'app : [README.md](README.md). Plan : phases 5.9 et suivantes de `../charpentier-writer/docs/PLAN.md` (le plan reste dans l'app, le tableau d'avancement aussi).

## Façon de travailler
- Nix, scripts, commentaires en **anglais** ; ce que voit l'auteur (installateur, messages) en **français**, au ton de DESIGN §4.12.
- Commits petits, **Conventional Commits**. **Ne jamais pousser** sans demande explicite.
- Construire sur le ThinkPad de Pierre (Windows, WSL2 avec Nix, KVM), par `scripts/nix.sh`, qui y appelle Nix directement ; à défaut sur le Mac (même script : conteneur borné sous OrbStack, lent, et OrbStack n'y est plus installé). Jamais sur le prodesk2021 : c'est un serveur de production.
- Essayer la clé en machine virtuelle sur le ThinkPad : `scripts/try-installer.sh`. Ne jamais démarrer la clé sur le ThinkPad lui-même : elle effacerait son disque.
- Surveiller le disque (celui de WSL sur le ThinkPad, l'interne sur le Mac) : `scripts/nix.sh --clean` après une série de constructions si l'espace manque.
- L'app est prise sur GitHub (`github:chatelp/charpentier`, branche `main`) : l'OS ne voit que ce qui y est poussé ; une app pas encore poussée s'essaie par `--override-input charpentier path:../charpentier-writer`.
- Le contrat avec l'app (README, « Ce que l'app attend du système ») change avec elle : toute évolution d'un côté se reporte de l'autre, dans le même mouvement.
- L'auteur tape lui-même tout mot de passe ; aucune commande `sudo` lancée par l'agent.
- Avant de déclarer une phase faite : construite, essayée en machine virtuelle, et dire ce qui reste à vérifier sur le vrai X250.
