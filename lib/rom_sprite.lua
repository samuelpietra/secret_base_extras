-- An overworld sprite read from the player's imported ROM, the way a person
-- of the game is drawn, served to the furniture art as RomTileset serves a
-- metatile: each standing frame cut into two 16x16 halves, a "mid" naming
-- one, and palette slots that color() turns into the frame's colours.
--
-- The engine's prepared cache holds each sprite as <id>.meta (size, frame
-- count and the 16-colour palette, src/import/gba/ow_extract.lua encodeMeta)
-- and <id>.rgba (every frame baked to RGBA, which the engine's cache reader
-- hands out inflated, src/import/CacheBlob.lua decode).  The palette is
-- applied here again, from the pixels' colours back to the slots, so a sprite
-- can be painted in other colours of the ROM: `colors` replaces palette
-- entries with entries of other sprites' palettes.

return function(Lib)
  local RomSprite = {}

  local CELL = 16
  local ROOT = "data/generated/gba/ow/"
  local META_PALETTE = 23 -- byte where the 16 BGR555 colours start (format 2+)
  local FLIP = 1024

  local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end

  local function readMeta(cache, id)
    local meta = cache:read(ROOT .. id .. ".meta")
    if type(meta) ~= "string" or meta:sub(1, 4) ~= "SVOW" or meta:byte(5) < 2 then
      return nil, ("sprite %s has no palette in the cache"):format(tostring(id))
    end
    local palette = {}
    for slot = 0, 15 do palette[slot] = u16(meta, META_PALETTE + slot * 2) end
    return { width = u16(meta, 9), height = u16(meta, 11), frames = u16(meta, 13), palette = palette }
  end

  local Sprite = {}
  Sprite.__index = Sprite

  -- The mid of a frame's upper (half 0) or lower (half 1) 16 rows, mirrored
  -- when flip is set, as the game draws a person facing right.
  function RomSprite.mid(frame, half, flip)
    return (flip and FLIP or 0) + frame * 2 + half
  end

  -- colors: { [slot] = { spriteId, slot } }, or nil for the sprite's own.
  function RomSprite.load(cache, id, colors)
    local meta, why = readMeta(cache, id)
    if not meta then return nil, why end
    if meta.width ~= CELL or meta.height ~= 2 * CELL then
      return nil, ("sprite %s is not a 16x32 person"):format(tostring(id))
    end
    local raw = cache:read(ROOT .. id .. ".rgba")
    if type(raw) ~= "string" or #raw < meta.width * meta.height * meta.frames * 4 then
      return nil, ("sprite %s has no pixels in the cache"):format(tostring(id))
    end
    local slotOf = {}
    for slot = 1, 15 do
      local r, g, b = Lib.RomTileset.rgb(meta.palette[slot])
      local key = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256 + math.floor(b * 255 + 0.5)
      slotOf[key] = slotOf[key] or slot
    end
    local frames = {}
    for frame = 0, meta.frames - 1 do
      local slots = {}
      for i = 0, CELL * 2 * CELL - 1 do
        local at = (frame * CELL * 2 * CELL + i) * 4 + 1
        local r, g, b, a = raw:byte(at, at + 3)
        slots[i] = a == 0 and 0 or (slotOf[r * 65536 + g * 256 + b] or 0)
      end
      frames[frame] = slots
    end
    local palette = {}
    for slot = 0, 15 do palette[slot] = meta.palette[slot] end
    for slot, from in pairs(colors or {}) do
      local other, otherWhy = readMeta(cache, from[1])
      if not other then return nil, otherWhy end
      palette[slot] = other.palette[from[2]]
    end
    return setmetatable({ frames = frames, palette = palette }, Sprite)
  end

  local EMPTY = {}
  for i = 1, CELL * CELL do EMPTY[i] = 0 end

  -- 256 palette slots, 0 transparent, row-major; a person has no top layer.
  function Sprite:layer(mid, which)
    if which ~= 0 then return EMPTY end
    local flip = mid >= FLIP
    local frame, half = math.floor((mid % FLIP) / 2), mid % 2
    local slots = self.frames[frame]
    local out = {}
    for y = 0, CELL - 1 do
      for x = 0, CELL - 1 do
        local sourceX = flip and (CELL - 1 - x) or x
        out[y * CELL + x + 1] = slots and slots[(half * CELL + y) * CELL + sourceX] or 0
      end
    end
    return out
  end

  function Sprite:color(slot)
    return Lib.RomTileset.rgb(self.palette[slot] or 0)
  end

  function Sprite:layerType()
    return Lib.RomTileset.LAYER.NORMAL
  end

  return RomSprite
end
