# CLAUDE.md : Charpentier OS

Le système installable du X250 pour l'app Charpentier (dépôt voisin `../charpentier-writer`, ses principes et son `CLAUDE.md` s'appliquent). Présentation, commandes et contrat avec l'app : [README.md](README.md). Plan : phases 5.9 et suivantes de `../charpentier-writer/docs/PLAN.md` (le plan reste dans l'app, le tableau d'avancement aussi).

## Façon de travailler
- Nix, scripts, commentaires en **anglais** ; ce que voit l'auteur (installateur, messages) en **français**, au ton de DESIGN §4.12.
- Commits petits, **Conventional Commits**. **Ne jamais pousser** sans demande explicite.
- Construire uniquement sur le Mac, par `scripts/nix.sh` (OrbStack, conteneur borné). Jamais sur le prodesk2021 : c'est un serveur de production.
- Surveiller le disque interne (64 Go libres au départ) : `scripts/nix.sh --clean` après une série de constructions si l'espace manque.
- Le contrat avec l'app (README, « Ce que l'app attend du système ») change avec elle : toute évolution d'un côté se reporte de l'autre, dans le même mouvement.
- L'auteur tape lui-même tout mot de passe ; aucune commande `sudo` lancée par l'agent.
- Avant de déclarer une phase faite : construite ici, essayée en machine virtuelle si possible, et dire ce qui reste à vérifier sur le vrai X250.
