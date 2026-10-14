-- A tileset pair of this mod's own, registered beside the engine's so the
-- field renderer draws furniture cells like any other metatile: an under
-- picture below the player and an over picture above them.
--
-- Each cell is composed from what the base already shows there (its floor,
-- wall or decoration, read from the engine's loaded atlas) with the art of
-- every piece reaching into it on top, in placement order.  Which
-- layer goes where follows the source metatile's own layer type, as
-- pokeemerald's DrawMetatile does: the bottom layer is always below the
-- player, the top layer is above them unless the metatile is COVERED.

return function(V)
  local Atlas = {}

  local CELL = 16
  local COLS = 16

  local function copyCell(dst, dx, dy, src, sx, sy)
    for y = 0, CELL - 1 do
      for x = 0, CELL - 1 do
        local r, g, b, a = src:getPixel(sx + x, sy + y)
        if a > 0 then dst:setPixel(dx + x, dy + y, r, g, b, a) end
      end
    end
  end

  local function paint(dst, dx, dy, rom, layer, keep)
    for i = 1, 256 do
      local slot = layer[i]
      if slot ~= 0 then
        local x, y = (i - 1) % CELL, math.floor((i - 1) / CELL)
        if not keep or keep(x, y) then
          local r, g, b = rom:color(slot)
          dst:setPixel(dx + x, dy + y, r, g, b, 1)
        end
      end
    end
  end

  local function bottomKeep(piece, row, col)
    local bottom = piece.art.bottom
    if not bottom then return function() return false end end
    if bottom.keep then
      if bottom.keep[row + 1][col + 1] then return nil end
      return function() return false end
    end
    if not bottom.mask then return nil end
    return function(x, y)
      local mx = col * CELL + x - bottom.x
      local my = row * CELL + y - bottom.y
      local line = bottom.mask[my + 1]
      return line ~= nil and mx >= 0 and line:sub(mx + 1, mx + 1) == "#"
    end
  end

  -- cells: list of { floorMid, layers = { { piece, rom, row, col, mid, pixels }, ... } },
  -- row/col being the art cell of the piece.  pixels, when given, is an
  -- animation frame (256 palette slots) that stands in for the bottom layer.  Returns the pair table to
  -- register and each cell's mid in it, in the same order.  floorTs false
  -- composes the art alone, on a clear background, which is what the
  -- placement preview draws over the map.
  function Atlas.build(pairName, floorTs, NativeTileset, cells)
    local rows = math.max(1, math.ceil(#cells / COLS))
    local under = love.image.newImageData(COLS * CELL, rows * CELL)
    local over = love.image.newImageData(COLS * CELL, rows * CELL)
    local ts = { pair = pairName, midToSlot = {}, cols = COLS, rows = rows, midCount = #cells,
      layered = true, quads = {}, overQuads = {}, slotPix = {} }
    local mids = {}
    for i, c in ipairs(cells) do
      local slot = i - 1
      local dx, dy = (slot % COLS) * CELL, math.floor(slot / COLS) * CELL
      if floorTs then
        local floorSlot = NativeTileset.slotFor(floorTs, c.floorMid)
        local fx, fy = (floorSlot % floorTs.cols) * CELL, math.floor(floorSlot / floorTs.cols) * CELL
        copyCell(under, dx, dy, floorTs.imageData, fx, fy)
        if floorTs.overImageData then copyCell(over, dx, dy, floorTs.overImageData, fx, fy) end
      end
      for _, l in ipairs(c.layers) do
        local rom = l.rom
        paint(under, dx, dy, rom, l.pixels or rom:layer(l.mid, 0), bottomKeep(l.piece, l.row, l.col))
        local top = rom:layer(l.mid, 1)
        local topOver = l.piece.art.topOver and l.piece.art.topOver[l.row + 1][l.col + 1]
        if not topOver and rom:layerType(l.mid) == V.RomTileset.LAYER.COVERED then
          paint(under, dx, dy, rom, top)
        else
          paint(over, dx, dy, rom, top)
        end
      end
      ts.midToSlot[slot] = slot
      mids[i] = slot
    end
    ts.imageData, ts.overImageData = under, over
    ts.image, ts.overImage = love.graphics.newImage(under), love.graphics.newImage(over)
    ts.image:setFilter("nearest", "nearest")
    ts.overImage:setFilter("nearest", "nearest")
    return ts, mids
  end

  return Atlas
end
