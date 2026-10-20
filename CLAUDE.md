# Secret Base Extras — working notes for Claude

A gen1recomp mod for Pokémon Emerald: an **EXTRA** category in the Secret
Base DECORATE menu with furniture the game has elsewhere (bed, Pokémon
Center PC, TV, two vending machines, Move Relearner and Deleter). The README
is the spec: what each piece does, where it may stand, how saves stay
vanilla.

Answer in the language the person is writing in. Everything committed —
code, comments, README, commit messages — is in English.

## How this mod is built

- `main.lua` wires the engine hooks; `lib/` holds the parts (README,
  *Layout*). A new piece starts as a recipe in `lib/furniture.lua`.
- Engine modules are reached through `engineModule` and changed only through
  `wrap`, so a missing engine function switches that part off and is logged.
- Art is composed at run time from the player's ROM (`lib/rom_tileset.lua`,
  `lib/rom_sprite.lua`); the mod ships metatile ids, pixel masks and palette
  swaps, never pixels. Recolours use colours already in the ROM's palettes.
- Saves are written vanilla-clean: decoration ids 121+ never reach the base's
  slots or the inventory; placed pieces live in
  `save.modData.secret_base_extras.placed` (`lib/save_compat.lua`). Keep it so:
  removing the mod must leave a loadable Emerald save.
- Pieces copied as-is behave exactly as the original. The stores and people
  differ where the maintainer chose (README); do not extend those
  differences unasked.
- Authored on purpose: the category name EXTRA, the piece names and
  descriptions. Everything else on screen is the ROM's.
- Known engine bugs reported upstream and left alone: the hidden cursor
  after PUT AWAY → YES, and Emerald's party-cancel value looping the Move
  Deleter. Not the mod's to fix.

## Vanilla first

The mod adds what the game lacks with the game's own pieces, so a player
cannot tell where the game ends and the mod begins.

- **No new pixels, sounds, music or fonts.** Graphics, text, sounds and rules
  come from the player's imported ROM or from the engine. A mod may ship data
  about the ROM's assets (which tiles, which pixels belong, which palette
  colours to swap), never the assets themselves.
- **Text comes from the ROM when the ROM has it.** Search the script cache
  (`RomText`) before writing a string; join the ROM's own words before
  authoring new ones. Authored text is the last resort, and it follows the
  game's style (capitals, `{PKMN}`, line lengths).
- **Behaviour copies the original.** A piece, screen or sound that exists in
  the game behaves as it does there: same script, same collision, same
  sound, same cursor rules. Departures are the maintainer's call, made
  explicitly, and recorded in the README.
- **Find the engine's own function first.** Before drawing, measuring or
  computing something, look for the engine module that already does it (the
  summary screen's badges, the list menu's arrows, the damage code's type
  chart) and call it.
- At a visual impasse — alignment, layout, which sprite or colour — render
  the options from the real ROM into an image and show it before building
  one.

## Scope

- Build what was asked. No option, setting, flag, fallback path or
  abstraction nobody asked for: a value the spec fixes is a constant.
- Something out of scope that seems useful is offered as a suggestion, not
  built.
- When reporting, audit additions against the request and say plainly which
  parts were not in it.

## Code

- Match the surrounding code: its names, comment density and idioms.
- Names say what a thing means in the game ("choosingCommand", "footprintTop"),
  not how it is computed.
- Comment only what reading the file cannot reveal: engine behaviour this
  relies on (cite the engine file or the pret source), or a rule this mod
  imposes and why. Never restate the next line.
- Reuse before adding: a second copy of a pattern becomes one helper; a
  table of data beats parallel branches.
- Leave no leftovers: unused locals, dead branches, debug prints, stale
  comments and helpers whose last caller went away are deleted in the same
  change.
- Engine access goes through the mod's own helpers and patterns (*How this
  mod is built*); a new kind of access follows them, or says in a comment
  why it cannot.

## Before saying it is done

Run `tests/run.sh` (see `tests/README.md`) and read every result. A fix comes
with a test that fails before it and passes after. The render test writes
`render.png`; look at it after any art change. Then hand the build over for
an in-game test, naming the cases to try.

## Releasing

Commit only when the maintainer says so, usually after playing the build.

- [Conventional Commits](https://www.conventionalcommits.org): `feat`, `fix`,
  `refactor`, `docs`, `chore`, with a scope when it carries signal.
- One SemVer tag per commit, `vMAJOR.MINOR.PATCH`: every commit is a build
  that gets installed, so `refactor`, `docs` and `chore` bump the patch too
  (README, *Versioning*). `manifest.json`'s `version` moves with the tag, in
  the same commit.
- End every commit message with the co-author trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the model in
  use).
- Update the README in the same commit when behaviour, requirements or
  layout change.
- `./package.sh` writes the install zip of the tagged release to
  `~/Desktop/secret_base_extras-v<version>.zip`, leaving out what
  `.gitattributes` marks `export-ignore` (tests and tooling).
