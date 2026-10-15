# Secret Base Extras

A gen1recomp mod for Pokémon Emerald. Adds an **EXTRA** category to the Secret
Base **DECORATE** menu, holding furniture the game already has elsewhere and
that a Secret Base never offered:

| Item | From | What it does |
|---|---|---|
| **HEALING BED** | your bedroom | Rest in it to heal your party. You can walk onto the pillow and lie under the blanket. |
| **PKMN CENTER PC** | the Pokémon Centers | Item storage and the Pokémon boxes. Its screen lights up while in use. |
| **STANDARD TV** | the NPC houses | Every show on air, like any TV in the game: it lights up and blinks when there is something new to watch and switches off once you have watched it. |
| **BATTLE STORE** | the Lilycove Dept. Store rooftop | A vending machine selling what the Battle Frontier's clerk sells: ULTRA BALL, HYPER POTION, MAX POTION, FULL RESTORE, FULL HEAL, REVIVE, MAX REPEL, PROTEIN, CALCIUM, IRON, ZINC, CARBOS, HP UP. Red panel. |
| **HUNTING STORE** | the Lilycove Dept. Store rooftop | A vending machine selling what the Dept. Store 2F's left clerk sells, for catching: POKé BALL, GREAT BALL, ULTRA BALL, ESCAPE ROPE, FULL HEAL, ANTIDOTE, PARLYZ HEAL, BURN HEAL, ICE HEAL, AWAKENING, FLUFFY TAIL. Purple panel. |
| **MOVE RELEARNER** | Fallarbor Town | A person, drawn as a BLACK BELT in a navy kimono with blond hair. Teaches a Pokémon a move again for a HEART SCALE. |
| **MOVE DELETER** | Lilycove City | A person, drawn as a BLACK BELT with dark skin and black hair. Makes a Pokémon forget a move, HMs included. |

The HEALING BED, PKMN CENTER PC and STANDARD TV behave exactly as their
originals do: same scripts, same collision, same animation. The two stores are
the rooftop's vending machine, recoloured from its own palette so they tell
apart, and greet you as their clerk does ("Welcome! How may I serve you?")
before opening the same shop, with the same items and prices. The MOVE RELEARNER and MOVE DELETER are a
person of the game, the BLACK BELT, in other colours of the palettes the
game's people share, and say and do what their originals do. They are placed,
packed up and moved with the regular DECORATE and PACK UP commands, and saved
with your base.

## Requirements

| | |
|---|---|
| Game | Pokémon Emerald |
| Engine | gen1recomp 0.3.85 or newer (the version it was validated on) |
| Mod API | 2 |
| Permissions | `engine_internals` |

The mod reaches engine modules that are not on the Gen 3 mod facade list, so it
declares the `engine_internals` permission. The Mod Manager flags that with a
`!` badge reading *PATCHES ENGINE CODE*; it is expected.

The furniture is drawn from **your own imported ROM**: the mod ships which
metatiles to use and which pixels belong to the furniture, never the pixels
themselves.

## Installing

gen1recomp loads mods from a `mods` folder. On a portable install — one with a
`portable.txt` next to the application — that folder sits beside the app:

```
gen1recomp/
├── portable.txt
├── gen1recomp.app
└── mods/
    └── secret_base_extras/
        ├── main.lua
        ├── manifest.json
        └── lib/
```

1. Copy the `secret_base_extras` folder into `mods/`, keeping the folder name.
2. Start gen1recomp and open the Mod Manager.
3. Enable **Secret Base Extras** and accept the `engine_internals` prompt.
4. Load an Emerald save.

Mods are loaded when gen1recomp starts. After enabling or disabling the mod,
quit the game and start it again from gen1recomp; going back to the title
screen is not enough.

## Using it

At the PC in your own Secret Base, choose **DECORATION → DECORATE**. The
category list scrolls, like the Start menu does, to fit **EXTRA** after the
eight vanilla categories. The seven pieces are already in it: the mod gives
them to you, and gives back any you toss.

### Where each piece may stand

- On plain floor, never on another decoration, an object or yourself. Vanilla
  decorations may not be placed on this mod's furniture either.
- **HEALING BED** occupies one column (pillow and foot). Its frame reaches a few
  pixels into the cells beside it, so it can stand right against a wall.
- **PKMN CENTER PC** and **STANDARD TV** occupy three cells: a top that you
  can walk behind, the set, which blocks, and a base you stand on to use them,
  facing up. They may stand in the middle of a room or against the north wall,
  with the top, or the top and the set, over the wall.
- **BATTLE STORE** and **HUNTING STORE** occupy two cells, like a vanilla
  plant: the lower one blocks and you shop from the cell below it, facing up;
  the upper one you can walk behind. Their top cell may stand over the north
  wall.
- **MOVE RELEARNER** and **MOVE DELETER** stand like the game's people: their
  feet block and their head you can walk behind. Talk to them from any side;
  they turn to you and look down again when you are done. Their head may stand
  over the north wall.

## Saves, and removing the mod

Every save is written as if the mod were not installed. Your base's decoration
slots, the decoration inventory and the TV shows only ever hold vanilla
decorations; the furniture you placed is kept in the mod's own save data and
put back when the save is loaded with the mod.

So you can switch the mod off at any time: the game loads the save as an
ordinary Emerald save, with your vanilla decorations where you left them. When
you switch it back on, the furniture returns to its place. If a vanilla
decoration took that place in the meantime, the piece waits in the PC instead.

## Contributing

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org), with a scope when
it carries signal:

```
feat(extra): bed, PC and TV in an EXTRA decoration category
refactor(save): move save compatibility into its own module
```

Types in use: `feat`, `fix`, `refactor`, `docs`, `chore`.

### Versioning

[Semantic Versioning](https://semver.org), one release per commit, tagged
`vMAJOR.MINOR.PATCH`:

| Change | Bump |
|---|---|
| Incompatible change | major |
| Backward compatible functionality | minor |
| Backward compatible bug fix | patch |

**A local convention worth stating, because it departs from the spec:**
`refactor` and `docs` also bump the patch version here. SemVer versions
releases rather than commits, so a pure refactor normally waits for the next
release instead of earning a version of its own. In this repository every
commit is a build that gets installed and played, and two different builds must
never both claim the same version — otherwise there is no way to tell which one
is running.

Keep `manifest.json`'s `version` field in step with the tag.

### Code

- English only, in comments as well as identifiers.
- Names carry the meaning. A comment earns its place when it records something
  that reading this file cannot reveal: engine behaviour, or a rule this mod
  imposes. A comment that restates the next line does not.
- Engine modules are reached through `engineModule` and changed only through
  `wrap`, so a renamed or missing engine function switches that part of the mod
  off and is named in the log, instead of breaking the game.

### Layout

| File | What |
|---|---|
| `main.lua` | Wiring: the engine hooks, the furniture standing in the current base, placement rules, the A button. |
| `lib/furniture.lua` | The recipe of each piece: source map, metatiles, footprint, collision, script, animation. A new piece starts here. |
| `lib/rom_tileset.lua` | Reads a vanilla map's tilesets from the imported ROM data. |
| `lib/rom_sprite.lua` | Reads a person's overworld sprite from the imported ROM data, in the colours a piece gives it. |
| `lib/atlas.lua` | Composes the furniture over the base's own floor into a tileset of the mod's own. |
| `lib/menu.lua` | The two DECORATE pictures the mod draws: the scrolling category list and the placement preview. |
| `lib/save_compat.lua` | Writes saves the game understands without the mod, and puts the furniture back on load. |
| `tests/` | Offline tests, run with `tests/run.sh` (see `tests/README.md`). |
