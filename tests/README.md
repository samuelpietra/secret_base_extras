# Offline tests

Most of this mod only runs inside the game. These tests catch what can be
caught before a build is installed and played. Run them all with:

```sh
tests/run.sh
```

`tests/ci.sh` runs `lint` alone, the one test that needs no ROM, with the
system's LÖVE; GitHub Actions runs it on every push and pull request, and
before every release. The others read the imported ROM or your save, which
never leave your machine, so `tests/run.sh` before every commit is what runs
them.

`tests/run.sh` needs the gen1recomp install this mod sits in (macOS, portable),
an imported Emerald ROM, and a save in `saves/emerald/slot1.lua`. The script
extracts the newest engine payload and a copy of the app's LÖVE into
`$TMPDIR/secret_base_extras-tests`.

| Test | Checks | Expected |
|---|---|---|
| `lint` | Every global each mod file reads or writes. A misspelt local shows up as an unexpected global. | `ok` for every file. |
| `render` | Composes the bed, both PCs, both TVs, the TV's two blink frames, the two stores and the two people (two facings each) from the imported ROM. | `OK slots 35`, and `render.png` in the work folder to look at. The warning about missing decoration modules is expected: the mod is loaded without the engine here. |
| `engine` | The data hooks on the real engine modules: the three decorations, the EXTRA list and count, the table surviving a reload. | Names and shapes as listed. `vanilla canPlace false ... manifest.lua is not in the cache` is expected: it shows the vanilla rule was called, without a base loaded. |
| `save` | A round trip of your save through the save hooks, with vanilla furniture put where the bed was while the mod was off. | Steps 1 and 4 hold no ids 121-123 in the base; step 3 puts back what fits and leaves the bed in the PC. |
| `integration` | The in-game paths on stand-ins for the wrapped engine modules: base load, collision, drawing, PC and TV screens, the TV blink, the A button, the stores' and people's scripts, people turning and turning back, placement rules, PUT AWAY aiming and PACK UP. | `ALL PASS`. |

`save` and `integration` describe your current save and a fixed test base
respectively; neither writes anything.
