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

return function(Lib)
  local Atlas = {}

  local CELL = 16
  local COLS = 16

  local function copyCell(target, slotX, slotY, source, sourceX, sourceY)
    for y = 0, CELL - 1 do
      for x = 0, CELL - 1 do
        local r, g, b, a = source:getPixel(sourceX + x, sourceY + y)
        if a > 0 then target:setPixel(slotX + x, slotY + y, r, g, b, a) end
      end
    end
  end

  local function paint(target, slotX, slotY, tileset, layer, keep)
    for i = 1, 256 do
      local slot = layer[i]
      if slot ~= 0 then
        local x, y = (i - 1) % CELL, math.floor((i - 1) / CELL)
        if not keep or keep(x, y) then
          local r, g, b = tileset:color(slot)
          target:setPixel(slotX + x, slotY + y, r, g, b, 1)
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
      local maskX = col * CELL + x - bottom.x
      local maskY = row * CELL + y - bottom.y
      local line = bottom.mask[maskY + 1]
      return line ~= nil and maskX >= 0 and line:sub(maskX + 1, maskX + 1) == "#"
    end
  end

  -- cells: list of { floorMid, layers = { { piece, tileset, row, col, mid, pixels }, ... } },
  -- row/col being the art cell of the piece.  pixels, when given, is an
  -- animation frame (256 palette slots) that stands in for the bottom layer.  Returns the pair table to
  -- register and each cell's mid in it, in the same order.  floorAtlas false
  -- composes the art alone, on a clear background, which is what the
  -- placement preview draws over the map.
  function Atlas.build(pairName, floorAtlas, NativeTileset, cells)
    local rows = math.max(1, math.ceil(#cells / COLS))
    local under = love.image.newImageData(COLS * CELL, rows * CELL)
    local over = love.image.newImageData(COLS * CELL, rows * CELL)
    local atlas = { pair = pairName, midToSlot = {}, cols = COLS, rows = rows, midCount = #cells,
      layered = true, quads = {}, overQuads = {}, slotPix = {} }
    local mids = {}
    for i, cell in ipairs(cells) do
      local slot = i - 1
      local slotX, slotY = (slot % COLS) * CELL, math.floor(slot / COLS) * CELL
      if floorAtlas then
        local floorSlot = NativeTileset.slotFor(floorAtlas, cell.floorMid)
        local floorX, floorY = (floorSlot % floorAtlas.cols) * CELL, math.floor(floorSlot / floorAtlas.cols) * CELL
        copyCell(under, slotX, slotY, floorAtlas.imageData, floorX, floorY)
        if floorAtlas.overImageData then copyCell(over, slotX, slotY, floorAtlas.overImageData, floorX, floorY) end
      end
      for _, layer in ipairs(cell.layers) do
        local tileset = layer.tileset
        paint(under, slotX, slotY, tileset, layer.pixels or tileset:layer(layer.mid, 0), bottomKeep(layer.piece, layer.row, layer.col))
        local top = tileset:layer(layer.mid, 1)
        local topOver = layer.piece.art.topOver and layer.piece.art.topOver[layer.row + 1][layer.col + 1]
        if not topOver and tileset:layerType(layer.mid) == Lib.RomTileset.LAYER.COVERED then
          paint(under, slotX, slotY, tileset, top)
        else
          paint(over, slotX, slotY, tileset, top)
        end
      end
      atlas.midToSlot[slot] = slot
      mids[i] = slot
    end
    atlas.imageData, atlas.overImageData = under, over
    atlas.image, atlas.overImage = love.graphics.newImage(under), love.graphics.newImage(over)
    atlas.image:setFilter("nearest", "nearest")
    atlas.overImage:setFilter("nearest", "nearest")
    return atlas, mids
  end

  return Atlas
end
