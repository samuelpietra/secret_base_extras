-- Reads a map's tileset pair straight from the ROM data the importer cached
-- under data/generated/gba/map_tree.  The render atlas (native/<pair>) bakes
-- each metatile's two layers into one picture, floor included; the raw data
-- keeps them apart, which is what lets furniture leave its floor behind.
--
-- Files are the ROM's own, already decompressed:
--   metatiles.bin   8 u16 tile refs per metatile, bottom layer then top
--   tiles.4bpp      32 bytes per 8x8 tile, low nibble is the left pixel
--   palettes.bin    16 palettes of 16 BGR555 colours
--   attributes.bin  u16 per metatile, layer type in bits 12-15

return function()
  local RomTileset = {}

  local ROOT = "data/generated/gba/map_tree/"
  -- pokeemerald/include/fieldmap.h
  local NUM_TILES_IN_PRIMARY = 512
  local NUM_METATILES_IN_PRIMARY = 0x200
  -- pokeemerald/include/fieldmap.h
  local NUM_PALS_IN_PRIMARY = 6
  -- pokeemerald/include/global.fieldmap.h (METATILE_ATTR_LAYER_SHIFT)
  local LAYER_SHIFT = 2 ^ 12

  -- pokeemerald/include/global.fieldmap.h (METATILE_LAYER_TYPE_*)
  RomTileset.LAYER = { NORMAL = 0, COVERED = 1, SPLIT = 2 }

  local function u16(s, i)
    return s:byte(i) + s:byte(i + 1) * 256
  end

  local function readAll(cache, dir)
    local files = {}
    for _, name in ipairs({ "tiles.4bpp", "metatiles.bin", "palettes.bin", "attributes.bin" }) do
      local blob = cache:read(ROOT .. "tilesets/" .. dir .. "/" .. name)
      if type(blob) ~= "string" then return nil, dir .. "/" .. name .. " is not in the cache" end
      files[name] = blob
    end
    return files
  end

  local Pair = {}
  Pair.__index = Pair

  -- Which ROM tilesets a map uses, from the header the importer wrote, so the
  -- ROM pointers never appear in this mod.
  function RomTileset.forMap(cache, mapDir, pretName)
    local header = cache:read(ROOT .. "maps/" .. mapDir .. "/header.json")
    if type(header) ~= "string" then return nil, "map header " .. mapDir .. " is not in the cache" end
    if not header:find('"pretName":"' .. pretName .. '"', 1, true) then
      return nil, "map header " .. mapDir .. " is not " .. pretName
    end
    local primaryDir = header:match('"primaryTileset":"(ts_%x+)"')
    local secondaryDir = header:match('"secondaryTileset":"(ts_%x+)"')
    if not (primaryDir and secondaryDir) then return nil, "map header " .. mapDir .. " names no tilesets" end
    local primary, why = readAll(cache, primaryDir)
    if not primary then return nil, why end
    local secondary
    secondary, why = readAll(cache, secondaryDir)
    if not secondary then return nil, why end
    return setmetatable({ primary = primary, secondary = secondary }, Pair)
  end

  local function half(self, mid)
    if mid < NUM_METATILES_IN_PRIMARY then return self.primary, mid end
    return self.secondary, mid - NUM_METATILES_IN_PRIMARY
  end

  function Pair:layerType(mid)
    local files, i = half(self, mid)
    return math.floor(u16(files["attributes.bin"], i * 2 + 1) / LAYER_SHIFT) % 16
  end

  -- A tile ref is the tile index, both flips and the palette in one u16.
  local function pixel(self, ref, x, y)
    local tile = ref % 1024
    local hflip = math.floor(ref / 1024) % 2 == 1
    local vflip = math.floor(ref / 2048) % 2 == 1
    local pal = math.floor(ref / 4096)
    if hflip then x = 7 - x end
    if vflip then y = 7 - y end
    local tiles, base = self.primary["tiles.4bpp"], tile
    if tile >= NUM_TILES_IN_PRIMARY then
      tiles, base = self.secondary["tiles.4bpp"], tile - NUM_TILES_IN_PRIMARY
    end
    local b = tiles:byte(base * 32 + y * 4 + math.floor(x / 2) + 1) or 0
    local c = (x % 2 == 1) and math.floor(b / 16) or b % 16
    if c == 0 then return 0 end
    return pal * 16 + c
  end

  -- One 16x16 layer (0 = bottom, 1 = top) as 256 palette slots, 0 meaning
  -- transparent, row-major.
  function Pair:layer(mid, which)
    local files, i = half(self, mid)
    local mt = files["metatiles.bin"]
    local out = {}
    for k = 0, 3 do
      local ref = u16(mt, i * 16 + (which * 4 + k) * 2 + 1)
      local ox, oy = (k % 2) * 8, math.floor(k / 2) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          out[(oy + y) * 16 + ox + x + 1] = pixel(self, ref, x, y)
        end
      end
    end
    return out
  end

  -- Palettes 0-5 come from the primary
  -- tileset, the rest from the secondary.  Rounding matches the engine's
  -- bgr555_to_rgb8 (src/import/gba/native_pack.lua) so a piece of furniture
  -- is the exact colour it is in its vanilla map.
  function Pair:color(slot)
    local pal = math.floor(slot / 16)
    local files = pal < NUM_PALS_IN_PRIMARY and self.primary or self.secondary
    local c = u16(files["palettes.bin"], slot * 2 + 1)
    local function channel(v) return math.floor(v * 255 / 31 + 0.5) / 255 end
    return channel(c % 32), channel(math.floor(c / 32) % 32), channel(math.floor(c / 1024) % 32)
  end

  return RomTileset
end
