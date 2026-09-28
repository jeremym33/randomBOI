# RandomBOI – Unlock Randomizer

Mod pour **The Binding of Isaac: Repentance+** qui randomise les déblocages
d'objets, **sauf les objets nécessaires à la progression**.

Le mod choisit tout seul un moteur au démarrage :

| | Moteur **REPENTOGON** (recommandé) | Moteur **vanilla** (repli) |
|---|---|---|
| Prérequis | [REPENTOGON](https://github.com/TeamREPENTOGON/REPENTOGON/releases) ≥ 1.1 (compatible Repentance+) | aucun |
| Ce qui est randomisé | les **vrais succès** : le succès qui débloque X débloque un autre objet | une permutation de tous les objets du jeu |
| Objets dispo dès le départ | inchangés | randomisés aussi |
| Respect des pools | ✅ un objet n'apparaît que dans ses propres pools, avec ses poids | ❌ un objet peut apparaître hors de son pool |
| Annonce du déblocage | ✅ « Débloqué : Y (à la place de X) » à l'écran | ❌ |

`rboi status` dans la console indique le moteur utilisé.

## Moteur REPENTOGON

1. Chaque objet (et trinket) verrouillé par un succès est lu dans `items.xml` et
   `pocketitems.xml` (attribut `achievement`).
2. Une permutation, générée à partir d'une graine propre au slot de sauvegarde,
   associe chaque objet verrouillé X à un autre objet verrouillé f(X).
3. En jeu, **le succès de X débloque f(X) à la place de X**. X n'apparaîtra que
   si le succès associé à X par la permutation est obtenu.
4. Les tirages se font directement dans les pools du jeu
   (`ItemPool:PickCollectible`), avec les poids d'origine. Seul le critère
   « débloqué » change.
5. Quand un succès tombe, un message indique quel objet il débloque vraiment.

Votre sauvegarde n'est **jamais modifiée** : désactiver le mod (`rboi off` ou
dans le menu Mods) rend les déblocages d'origine.

## Moteur vanilla

Sans REPENTOGON, l'API ne donne accès ni aux succès ni au contenu des pools.
Chaque objet réellement débloqué X est alors remplacé par f(X) quand un pool
le tire. Vous avez autant d'objets accessibles que dans votre sauvegarde, mais
ce ne sont pas les mêmes.

## Réglages communs

- La permutation conserve la **qualité** (0 à 4) et la séparation **actif / passif**.
- Les **trinkets** sont aussi permutés (les versions dorées restent dorées).
- Le mod est désactivé pendant les **challenges** (objets imposés).

### Objets jamais randomisés (progression)

The Polaroid, The Negative, Key Piece 1 & 2, Knife Piece 1 & 2, Dad's Note, Red Key,
Broken Shovel (×2), Mom's Shovel, Dogma, ainsi que tout objet marqué `quest` par le jeu.
Breakfast est aussi exclu, car c'est l'objet de repli quand un pool est vide.

La liste (`PROGRESSION_COLLECTIBLES`) et les options (`CONFIG`) se trouvent dans
`scripts/randomboi/common.lua`.

## Installation

1. *(Recommandé)* Installer REPENTOGON :
   <https://github.com/TeamREPENTOGON/REPENTOGON/releases>
2. Copier ce dossier dans le dossier des mods du jeu, par exemple
   `…/steamapps/common/The Binding of Isaac Rebirth/mods/randomboi/`
   (il doit contenir directement `main.lua` et `metadata.xml`).
3. Lancer le jeu et activer **RandomBOI** dans le menu *Mods*.

## Commandes console

Ouvrir la console (touche `²` ou `~`) :

| Commande | Effet |
|---|---|
| `rboi status` | moteur, état du mod et graine |
| `rboi on` / `rboi off` | activer / désactiver |
| `rboi seed <nombre>` | fixer la graine |
| `rboi reroll` | nouvelle graine aléatoire |
| `rboi map <id>` | ce que donne le déblocage de l'objet `<id>` |
| `rboi who <id>` | quel succès donne accès à `<id>` et s'il est obtenu |
| `rboi unlocked` | nombre d'objets randomisés débloqués |

## Limites connues

- **REPENTOGON** : quand un joueur a Chaos, Sacred Orb ou TMTRAINER, le mod laisse
  le jeu tirer lui-même, pour garder leurs effets. Les objets verrouillés par la
  randomisation sont alors écartés, mais les objets verrouillés dans la
  sauvegarde et débloqués par le mod ne peuvent pas sortir.
- **REPENTOGON** : les rares transformations automatiques de GetCollectible (Bible,
  Magic Skin, Rosary) ne s'appliquent pas aux tirages faits par le mod.
- La page Collection du jeu affiche les déblocages d'origine.
- Les objets de départ des personnages ne sont pas modifiés.
- Les objets ajoutés par d'autres mods sont exclus par défaut (`includeModdedItems`).
