# RandomBOI – Unlock Randomizer

Mod pour **The Binding of Isaac: Repentance+** (fonctionne aussi sous Repentance) qui
randomise les déblocages d'objets, **sauf les objets nécessaires à la progression**.

## Fonctionnement

L'API Lua officielle ne permet pas de modifier les succès du fichier de sauvegarde.
Le mod applique donc une **permutation virtuelle** propre à chaque slot de sauvegarde :

> Chaque objet réellement débloqué **X** vous donne accès à un autre objet **f(X)**.

Quand un pool (salle au trésor, boss, shop, devil deal, reroll D6…) tire **X**, le mod
le remplace par **f(X)**. Vous avez donc exactement autant d'objets accessibles que
dans votre sauvegarde, mais ce ne sont pas les mêmes. Débloquer un nouvel objet
débloque en réalité un objet surprise. Les objets encore verrouillés dans votre
sauvegarde peuvent donc apparaître s'ils sont la cible d'un objet débloqué.

- La permutation est **déterministe** (graine sauvegardée par slot).
- Elle conserve la **qualité** (0 à 4) et la séparation **actif / passif** pour garder l'équilibre.
- Les **trinkets** sont aussi permutés (les versions dorées restent dorées).
- Pas de doublon dans une même partie : si l'objet cible a déjà été donné, le mod retire un autre objet.
- Désactivé pendant les **challenges** (objets imposés).

### Objets jamais randomisés (progression)

The Polaroid, The Negative, Key Piece 1 & 2, Knife Piece 1 & 2, Dad's Note, Red Key,
Broken Shovel (×2), Mom's Shovel, Dogma, ainsi que tout objet marqué `quest` par le jeu.
Breakfast est aussi exclu, car c'est l'objet de repli quand un pool est vide.

La liste se modifie en haut de `main.lua` (`PROGRESSION_COLLECTIBLES`), tout comme les
options (`CONFIG`).

## Installation

1. Copier ce dossier dans le dossier des mods du jeu, par exemple :
   `…/steamapps/common/The Binding of Isaac Rebirth/mods/randomboi/`
   (il doit contenir directement `main.lua` et `metadata.xml`).
2. Lancer le jeu, activer **RandomBOI** dans le menu *Mods*.

## Commandes console

Ouvrir la console (touche `²` ou `~`) :

| Commande | Effet |
|---|---|
| `rboi status` | état du mod et graine |
| `rboi on` / `rboi off` | activer / désactiver |
| `rboi seed <nombre>` | fixer la graine |
| `rboi reroll` | nouvelle graine aléatoire |
| `rboi map <id>` | ce que donne l'objet `<id>` |
| `rboi who <id>` | quel déblocage donne accès à `<id>` |
| `rboi unlocked` | nombre d'objets randomisés accessibles |

## Limites connues

- Les pools ne sont pas lisibles via l'API vanilla : un objet peut apparaître dans un
  pool qui n'est pas le sien (par exemple un objet du Devil Room dans une salle au trésor).
  La conservation de la qualité limite le déséquilibre.
- Les objets de départ des personnages ne sont pas modifiés.
- Les objets ajoutés par d'autres mods sont exclus par défaut (`includeModdedItems`).
