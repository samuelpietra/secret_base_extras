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
--   art        the vanilla metatiles drawn for it, `x` columns left of the
--              footprint.  Art cells outside the footprint are drawn over
--              whatever stands there (floor, wall, another decoration) and
--              occupy nothing, so a piece can stand against a wall while its
--              edge pixels still reach into the neighbouring cell.
-- Grids are listed top row first.
-- `source` is the vanilla map whose tilesets the art is drawn from.
-- `bottom` says what to keep of each art cell's bottom layer: false drops it
-- all, `keep` chooses per cell, `mask` chooses per pixel.
-- `topOver` puts a cell's top layer over the player whatever its layer type.
-- `wallRows` is how many of the top rows may stand on the base's north wall;
-- rows above one that does hang over the wall's top and are not checked.
-- `cellsOn` is the art while the piece is switched on (a PC in use, a TV with
-- a show on air) and `onAnim` the tileset animation that plays then on the
-- art cell `row`/`col`: the bank `file` of tileset pair `pair`, whose
-- anim_manifest.lua gives its frames, period and where that cell's mid is.
-- `script` is what A runs on the piece: from any side, or with `fromBelow`
-- only facing up at row `screenRow`, as the game's own PCs and TVs ask.

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

  -- The bedroom's bottom layer draws the bed's frame over the floorboards in
  -- the same 8x8 tiles, so it carries this mask: '#' is bed, '.' is floor.
  -- It covers the 32x32 pixels the frame occupies, starting 8 pixels into the
  -- left art column.  The headboard panel inside the rails is drawn in the
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
  -- and the foot, which blocks.
  Furniture.BED = {
    id = "bed",
    decorId = 121,
    name = "BED",
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
      x = -1,
      cells = {
        { 0x283, 0x284, 0x285 },
        { 0x28B, 0x28C, 0x28D },
      },
      bottom = { mask = BED_FRAME, x = 8, y = 0 },
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
    name = "PC",
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
    name = "TV",
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

  Furniture.PIECES = { Furniture.BED, Furniture.PC, Furniture.TV }

  return Furniture
end
