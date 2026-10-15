-- The furniture this mod puts in a Secret Base: which vanilla metatiles each
-- piece is made of, which of its cells block, and which pixels of its bottom
-- layer belong to the furniture rather than the floor or wall it stood on.
--
-- This file is the recipe, never the picture: every pixel is read at run time
-- from the player's own imported ROM (lib/rom_tileset.lua).
--
-- Each piece is also a decoration: an id past the vanilla table, a name and
-- description for the DECORATE list, and the vanilla shape that matches its
-- footprint (pokeemerald/include/decoration.h DECORSHAPE_*), which is what the
-- engine's cursor, PACK UP and position encoding read.
--
-- A piece has a footprint and an art grid:
--   footprint  width x height cells the piece occupies: they block or not
--              (`blocked`), answer the A button, and no other decoration may
--              share them.  Like every decoration, a placed piece is recorded
--              by its footprint's bottom-left cell.
--   art        the vanilla metatiles drawn for it, `x` columns left of and
--              `y` rows above the footprint (0 when absent).  Art cells outside the footprint are drawn over
--              whatever stands there (floor, wall, another decoration) and
--              occupy nothing, so a piece can stand against a wall while its
--              edge pixels still reach into the neighbouring cell.
-- Grids are listed top row first.
-- `source` is the vanilla map whose tilesets the art is drawn from, or the
-- overworld sprite (`sprite`, lib/rom_sprite.lua) a person is drawn from,
-- with `colors` taken from other sprites' palettes.
-- `bottom` says what to keep of each art cell's bottom layer: false drops it
-- all, `keep` chooses per cell, `mask` chooses per pixel.
-- `topOver` puts a cell's top layer over the player whatever its layer type.
-- `over` puts a whole cell, both layers, over the player, so they pass
-- behind it.
-- `recolor` paints palette slots in other slots' colours, { [from] = to },
-- slots as RomTileset numbers them (palette * 16 + colour).
-- `wallRows` is how many of the top rows may stand on the base's north wall;
-- rows above one that does hang over the wall's top and are not checked.
-- `cellsOn` is the art while the piece is switched on (a PC in use, a TV with
-- a show on air) and `onAnim` the tileset animation that plays then on the
-- art cell `row`/`col`: the bank `file` of tileset pair `pair`, whose
-- anim_manifest.lua gives its frames, period and where that cell's mid is.
-- `facing` is a person's art for each way they look (down, up, left,
-- right); they look down and turn to whoever talks to them, as the game's
-- standing people do.
-- `script` is what A runs on the piece: from any side, or with `fromBelow`
-- only facing up at row `screenRow`, as the game's own PCs and TVs ask, or
-- from any side but only at row `talkRow`, as a person's feet.
-- `personScript` instead names a person's script (its key in the ROM's
-- scripts), which A runs as that person would, without them there.

return function()
  local Furniture = {}

  -- The category this mod adds after the eight vanilla ones, and how many
  -- items it holds (the vanilla ones hold 10 to 40).
  Furniture.CATEGORY = { index = 8, name = "EXTRA", size = 10 }

  -- Brendan's and May's bedrooms share one tileset, so either map would do.
  local BEDROOM = { mapDir = "1_1", pretName = "LittlerootTown_BrendansHouse_2F" }
  -- Every Pokemon Center shares the PC; Oldale's is the first one.
  local POKEMON_CENTER = { mapDir = "2_2", pretName = "OldaleTown_PokemonCenter_1F" }
  -- The houses' TV: the Building primary's set over a GenericBuilding stand.
  local HOUSE = { mapDir = "15_5", pretName = "SootopolisCity_House1" }
  -- The vending machines on the Lilycove Department Store's rooftop.
  local ROOFTOP = { mapDir = "13_21", pretName = "LilycoveCity_DepartmentStoreRooftop" }

  -- The bedroom's bottom layer draws the bed's frame over the floorboards in
  -- the same 8x8 tiles, so it carries this mask: '#' is bed, '.' is floor.
  -- It covers the 32x32 pixels the frame occupies, starting 8 pixels into the
  -- left art column and one art row down (the rail row above keeps none).  The headboard panel inside the rails is drawn in the
  -- floorboards' own colours, but it reads as part of the bed, so it is kept.
  local BED_FRAME = {
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....#######..####..#######.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....######################.....",
    ".....####..............####.....",
    "......##................##......",
    "................................",
    "................................",
    "................................",
  }

  -- LittlerootTown_BrendansHouse_2F's bed.  Its art spans three columns,
  -- but the side ones are floor with the frame's outer 3 pixels in them, so
  -- the footprint is the middle column alone: the pillow, which the player
  -- can walk onto to lie under the blanket (the top layer, drawn over them),
  -- and the foot, which blocks.  The headboard's top rail, its last two
  -- pixel rows, is the top layer of the row above the pillow, whose bottom
  -- layer is floor.
  Furniture.BED = {
    id = "bed",
    decorId = 121,
    name = "HEALING BED",
    description = "A comfy bed. Rest\nin it to heal your\nPOKéMON.",
    shape = 5, -- DECORSHAPE_1x2
    width = 1, height = 2,
    script = "Route119_WeatherInstitute_1F_EventScript_Bed",
    blocked = {
      { false },
      { true },
    },
    source = BEDROOM,
    art = {
      x = -1, y = -1,
      cells = {
        { 0x27B, 0x27C, 0x27D },
        { 0x283, 0x284, 0x285 },
        { 0x28B, 0x28C, 0x28D },
      },
      bottom = { mask = BED_FRAME, x = 8, y = 16 },
    },
  }

  -- The Pokemon Center PC, standing on the floor (OldaleTown_PokemonCenter_1F
  -- column 10).  It spans three cells:
  --   cap   the top of the case, top layer only (the bottom layer is the
  --         Center's wall); drawn over the player, who can walk behind it
  --   body  screen and keyboard, bottom layer, which carries no floor; the
  --         PC turn-on effect swaps it (METATILE_Building_PC_Off/_On)
  --   feet  the base, a COVERED top layer drawn under the player, who stands
  --         here to use the PC, as in a Center
  Furniture.PC = {
    id = "pc",
    decorId = 122,
    name = "{PKMN} CENTER PC", -- {PKMN}: the font's PK and MN glyphs
    description = "A POKéMON CENTER\nPC. Store items\nand POKéMON in it.",
    shape = 6, -- DECORSHAPE_1x3
    width = 1, height = 3,
    script = "EventScript_PC",
    fromBelow = true,
    screenRow = 1,
    blocked = {
      { false },
      { true },
      { false },
    },
    -- Against the north wall like the TV: the cap on it, as in a Center, or
    -- the set too, with only the feet on the floor.
    wallRows = 2,
    source = POKEMON_CENTER,
    art = {
      x = 0,
      cells = {
        { 0x20C },
        { 0x004 },
        { 0x224 },
      },
      cellsOn = {
        { 0x20C },
        { 0x005 },
        { 0x224 },
      },
      bottom = { keep = { { false }, { true }, { false } } },
    },
  }

  -- The TV of the houses (SootopolisCity_House1 column 7), laid out like the
  -- PC: cap over the player, set and screen blocking, stand to watch from.
  -- In the house the cap hangs on the wall and its top layer is COVERED;
  -- here the player can walk behind it, so it is drawn over them.  It
  -- answers EventScript_TV and switches on and off with every other TV
  -- (METATILE_Building_TV_Off/_On), blinking with the Building tileset's
  -- building_tv_turned_on animation, which every Building pair carries.
  Furniture.TV = {
    id = "tv",
    decorId = 123,
    name = "STANDARD TV", -- ORNAMENT already holds a TV, a ROUND TV and a CUTE TV
    description = "A TV to catch the\nlatest shows and\nthe news.",
    shape = 6, -- DECORSHAPE_1x3
    width = 1, height = 3,
    script = "EventScript_TV",
    fromBelow = true,
    screenRow = 1,
    blocked = {
      { false },
      { true },
      { false },
    },
    -- As in the houses: the cap on the wall (Sootopolis), or the set too, with
    -- only the stand on the floor (as in a Lilycove house).
    wallRows = 2,
    source = HOUSE,
    art = {
      x = 0,
      cells = {
        { 0x230 },
        { 0x002 },
        { 0x2B5 },
      },
      cellsOn = {
        { 0x230 },
        { 0x003 },
        { 0x2B5 },
      },
      bottom = { keep = { { false }, { true }, { false } } },
      topOver = { { true }, { false }, { false } },
      onAnim = { row = 1, col = 0, pair = "building__generic_building",
        file = "anim_building_tv_turned_on.idx" },
    },
  }

  -- A vending machine of LilycoveCity_DepartmentStoreRooftop (columns 9 and
  -- 10), selling what a clerk elsewhere sells.  Its two metatiles fill two
  -- cells exactly, bottom layer only and no floor in it, so it lines up with
  -- the base's decorations as it is.  The lower cell blocks and the player
  -- shops from the cell below it, facing up; the upper one, drawn over the
  -- player, lets them walk behind the machine (on the rooftop it stands on
  -- the wall).  The two machines differ in the colours of their panel, cans
  -- and labels: slots 117, 118 and 121 of the machine's palette 7, painted in
  -- other colours of that same palette.  A runs the clerk's own script
  -- ("Welcome! How may I serve you?", the mart, "Please come again!"): same
  -- items, same prices.
  local function vendingMachine(piece)
    piece.shape = 5 -- DECORSHAPE_1x2
    piece.width, piece.height = 1, 2
    piece.fromBelow, piece.screenRow = true, 1
    piece.blocked = { { false }, { true } }
    -- like a vanilla plant (BEHIND_FLOOR): the top row may stand on the wall
    piece.wallRows = 1
    piece.source = ROOFTOP
    piece.art.x = 0
    piece.art.cells = { { 0x26F }, { 0x277 } }
    piece.art.bottom = { keep = { { true }, { true } } }
    piece.art.over = { { true }, { false } }
    return piece
  end

  -- BattleFrontier_Mart_EventScript_Clerk's mart: ULTRA BALL, HYPER POTION,
  -- MAX POTION, FULL RESTORE, FULL HEAL, REVIVE, MAX REPEL and the six
  -- vitamins, the Pokemon League clerk's and the Department Store 3F left
  -- clerk's lists together.  Red panel, white cans, yellow labels.
  Furniture.BATTLE_STORE = vendingMachine({
    id = "battle_store",
    decorId = 124,
    name = "BATTLE STORE",
    description = "Sells what the\nBATTLE FRONTIER's\nclerk sells.",
    personScript = "g3:08267acc", -- BattleFrontier_Mart_EventScript_Clerk
    art = { recolor = { [117] = 120, [118] = 116, [121] = 123 } },
  })

  -- LilycoveCity_DepartmentStore_2F_EventScript_ClerkLeft's mart, what
  -- catching takes: POKé BALL, GREAT BALL, ULTRA BALL, ESCAPE ROPE, FULL
  -- HEAL, ANTIDOTE, PARLYZ HEAL, BURN HEAL, ICE HEAL, AWAKENING, FLUFFY TAIL.
  -- Purple panel, peach cans, yellow labels.
  Furniture.HUNTING_STORE = vendingMachine({
    id = "hunting_store",
    decorId = 125,
    name = "HUNTING STORE",
    description = "Sells BALLS and\nthe goods of\nLILYCOVE's 2F.",
    personScript = "g3:0821fb48", -- LilycoveCity_DepartmentStore_2F_EventScript_ClerkLeft
    art = { recolor = { [117] = 124, [118] = 125, [121] = 123 } },
  })

  -- A person of the game, drawn from the BLACK_BELT's overworld sprite
  -- (OBJ_EVENT_GFX_BLACK_BELT, 44) in other colours of the four palettes the
  -- game's people share (NPC 1-4: NINJA_BOY 5, TWIN 6, BLACK_BELT 44,
  -- LITTLE_BOY 11), standing as the game's standing people do: the feet
  -- cell blocks and is talked to from any side, the head cell is drawn over
  -- the player, who can walk behind them.  Their standing frames are 0
  -- (down), 1 (up) and 2 (left), mirrored for right.  A runs the person's own
  -- script, which opens by turning them to the player (applymovement), done
  -- here by drawing them facing the player instead.
  local BLACK_BELT = 44
  local TWIN, LITTLE_BOY = 6, 11
  local function frameCells(frame, flip)
    local top = (flip and 1024 or 0) + frame * 2 -- RomSprite.mid
    return { { top }, { top + 1 } }
  end
  local function person(piece)
    piece.shape = 5 -- DECORSHAPE_1x2
    piece.width, piece.height = 1, 2
    piece.talkRow = 1
    piece.blocked = { { false }, { true } }
    piece.wallRows = 1
    piece.art.x = 0
    piece.art.facing = { down = frameCells(0), up = frameCells(1), left = frameCells(2), right = frameCells(2, true) }
    piece.art.cells = piece.art.facing.down
    piece.art.bottom = { keep = { { true }, { true } } }
    piece.art.over = { { true }, { false } }
    return piece
  end

  -- FallarborTown_MoveRelearnersHouse_EventScript_MoveRelearner: a move
  -- back for a HEART SCALE.  Navy kimono and headband (NPC 4's blues, LITTLE
  -- BOY's palette), blond hair (NPC 2's yellows, TWIN's).
  Furniture.MOVE_RELEARNER = person({
    id = "move_relearner",
    decorId = 126,
    name = "MOVE RELEARNER",
    description = "Teaches a POKéMON\na move again for\na HEART SCALE.",
    personScript = "g3:08201383",
    source = { sprite = BLACK_BELT, colors = {
      [14] = { LITTLE_BOY, 5 }, [5] = { LITTLE_BOY, 6 }, [6] = { LITTLE_BOY, 6 }, [7] = { LITTLE_BOY, 7 },
      [11] = { TWIN, 5 }, [12] = { TWIN, 6 }, [13] = { TWIN, 7 },
    } },
    art = {},
  })

  -- LilycoveCity_MoveDeletersHouse_EventScript_MoveDeleter: makes a POKéMON
  -- forget a move, HMs too.  The BLACK_BELT's white kimono and green belt,
  -- dark skin (the browns of NPC 2 and 3) and black hair.
  Furniture.MOVE_DELETER = person({
    id = "move_deleter",
    decorId = 127,
    name = "MOVE DELETER",
    description = "Makes a POKéMON\nforget a move,\nHMs included.",
    personScript = "g3:0821ea0b",
    source = { sprite = BLACK_BELT, colors = {
      [1] = { TWIN, 11 }, [2] = { TWIN, 7 }, [3] = { BLACK_BELT, 13 }, [4] = { TWIN, 13 },
      [11] = { BLACK_BELT, 7 }, [12] = { TWIN, 13 }, [13] = { BLACK_BELT, 15 },
    } },
    art = {},
  })

  Furniture.PIECES = { Furniture.BED, Furniture.PC, Furniture.TV, Furniture.BATTLE_STORE, Furniture.HUNTING_STORE,
    Furniture.MOVE_RELEARNER, Furniture.MOVE_DELETER }

  return Furniture
end
