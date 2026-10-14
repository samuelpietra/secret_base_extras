# Secret Base Extras

A gen1recomp mod for Pokémon Emerald. Adds an **EXTRA** category to the Secret
Base **DECORATE** menu, holding furniture the game already has elsewhere and
that a Secret Base never offered:

| Item | From | What it does |
|---|---|---|
| **BED** | your bedroom | Rest in it to heal your party. You can walk onto the pillow and lie under the blanket. |
| **PC** | the Pokémon Centers | Item storage and the Pokémon boxes. Its screen lights up while in use. |
| **TV** | the NPC houses | Every show on air, like any TV in the game: it lights up and blinks when there is something new to watch and switches off once you have watched it. |

Each piece behaves exactly as its original does: same scripts, same collision,
same animation. They are placed, packed up and moved with the regular
DECORATE and PACK UP commands, and saved with your base.

## Requirements

| | |
|---|---|
| Game | Pokémon Emerald |
| Engine | gen1recomp 0.3.0 or newer (built against 0.3.85) |
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
eight vanilla categories. The three pieces are already in it: the mod gives
them to you, and gives back any you toss.

### Where each piece may stand

- On plain floor, never on another decoration, an object or yourself. Vanilla
  decorations may not be placed on this mod's furniture either.
- **BED** occupies one column (pillow and foot). Its frame reaches a few
  pixels into the cells beside it, so it can stand right against a wall.
- **PC** and **TV** occupy three cells: a top that you can walk behind, the
  set, which blocks, and a base you stand on to use them, facing up. They may
  stand in the middle of a room or against the north wall, with the top, or the
  top and the set, over the wall.

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
| `lib/atlas.lua` | Composes the furniture over the base's own floor into a tileset of the mod's own. |
| `lib/menu.lua` | The two DECORATE pictures the mod draws: the scrolling category list and the placement preview. |
| `lib/save_compat.lua` | Writes saves the game understands without the mod, and puts the furniture back on load. |
