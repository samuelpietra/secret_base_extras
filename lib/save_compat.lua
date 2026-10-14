-- Saves written as if this mod were not installed.
--
-- The vanilla save structures never hold this mod's decoration ids, which the
-- game (or this engine without the mod, or a .sav export) knows nothing of.
-- The furniture placed in the own base travels in save.modData[modId].placed
-- instead (the bucket the engine keeps per mod, src/core/Game3.lua) and goes
-- back into the base's decoration slots when a save is loaded with the mod.
-- The EXTRA inventory list is not saved at all: the mod gives its pieces again
-- on load.

return function()
  local SaveCompat = {}

  -- src/core/game3/rse/tv.lua Tv.TVSHOW_SECRET_BASE_VISIT: the show lists the
  -- decorations the player put out.
  local SECRET_BASE_VISIT = 31

  local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
  end

  -- fn(x, y) per cell of a width x height footprint recorded, like every
  -- decoration, by its bottom-left cell.
  local function eachFootprintCell(x, bottomY, width, height, fn)
    for y = bottomY - height + 1, bottomY do
      for column = x, x + width - 1 do fn(column, y) end
    end
  end

  -- The table about to be written shares its subtables with the live
  -- session, so each field is replaced by a cleaned copy, never changed in
  -- place.  context: { modId, extraCategory, maxDecorations, pieceByDecorId }
  function SaveCompat.writeClean(save, context)
    local placed = {}
    local bases = save.secretBases
    local ownBase = type(bases) == "table" and bases[1]
    if type(ownBase) == "table" and type(ownBase.decorations) == "table" then
      local cleanBase = shallowCopy(ownBase)
      cleanBase.decorations, cleanBase.decorationPositions = {}, {}
      for slot = 1, context.maxDecorations do
        local decor = tonumber(ownBase.decorations[slot]) or 0
        local position = type(ownBase.decorationPositions) == "table"
          and tonumber(ownBase.decorationPositions[slot]) or 0
        if context.pieceByDecorId[decor] then
          placed[#placed + 1] = { decor = decor, pos = position }
          decor, position = 0, 0
        end
        cleanBase.decorations[slot], cleanBase.decorationPositions[slot] = decor, position
      end
      bases = shallowCopy(bases)
      bases[1] = cleanBase
      save.secretBases = bases
    end

    if type(save.decorationInventory) == "table" and save.decorationInventory[context.extraCategory] ~= nil then
      local inventory = shallowCopy(save.decorationInventory)
      inventory[context.extraCategory] = nil
      save.decorationInventory = inventory
    end

    if type(save.tvShows) == "table" then
      local cleanShows
      for index, show in pairs(save.tvShows) do
        if type(show) == "table" and tonumber(show.kind) == SECRET_BASE_VISIT and type(show.decorations) == "table" then
          local kept = {}
          for _, decor in ipairs(show.decorations) do
            if not context.pieceByDecorId[tonumber(decor)] then kept[#kept + 1] = decor end
          end
          if #kept ~= #show.decorations then
            cleanShows = cleanShows or shallowCopy(save.tvShows)
            local cleanShow = shallowCopy(show)
            cleanShow.decorations, cleanShow.numDecorations = kept, #kept
            cleanShows[index] = cleanShow
          end
        end
      end
      if cleanShows then save.tvShows = cleanShows end
    end

    local modData = shallowCopy(type(save.modData) == "table" and save.modData or {})
    local bucket = shallowCopy(type(modData[context.modId]) == "table" and modData[context.modId] or {})
    -- Pieces a loaded save carried that never made it back into the base
    -- (restorePlaced did not run) are kept, not dropped.
    local alreadyPlaced = {}
    for _, entry in ipairs(placed) do alreadyPlaced[entry.decor] = true end
    for _, entry in ipairs(type(bucket.placed) == "table" and bucket.placed or {}) do
      local decor = tonumber(entry.decor)
      if context.pieceByDecorId[decor] and not alreadyPlaced[decor] then placed[#placed + 1] = entry end
    end
    bucket.placed = #placed > 0 and placed or nil
    modData[context.modId] = bucket
    save.modData = modData
  end

  -- Puts the furniture a save carried back into the own base's decoration
  -- slots, once.  A piece whose cells a vanilla decoration took meanwhile
  -- (the mod was off) stays in the PC instead.
  -- context: { modId, maxDecorations, pieceByDecorId, ownBase(session),
  --            decodePosition(pos), decorationSize(decor), log(fmt, ...) }
  function SaveCompat.restorePlaced(session, context)
    local bucket = type(session) == "table" and type(session.modData) == "table" and session.modData[context.modId]
    if type(bucket) ~= "table" or type(bucket.placed) ~= "table" then return end
    local placed = bucket.placed
    bucket.placed = nil
    local base = context.ownBase(session)
    if type(base) ~= "table" or type(base.decorations) ~= "table" then return end
    if type(base.decorationPositions) ~= "table" then base.decorationPositions = {} end

    local taken = {}
    local function take(x, y) taken[x .. ":" .. y] = true end
    for slot = 1, context.maxDecorations do
      local decor = tonumber(base.decorations[slot]) or 0
      if decor ~= 0 then
        local x, y = context.decodePosition(base.decorationPositions[slot])
        local width, height = context.decorationSize(decor)
        eachFootprintCell(x, y, width, height, take)
      end
    end

    for _, entry in ipairs(placed) do
      local piece = context.pieceByDecorId[tonumber(entry.decor)]
      local x, y = context.decodePosition(entry.pos)
      local free = piece ~= nil
      if piece then
        eachFootprintCell(x, y, piece.width, piece.height, function(cx, cy)
          if taken[cx .. ":" .. cy] then free = false end
        end)
      end
      local emptySlot
      for slot = 1, context.maxDecorations do
        if (tonumber(base.decorations[slot]) or 0) == 0 then emptySlot = slot break end
      end
      if free and emptySlot then
        base.decorations[emptySlot] = piece.decorId
        base.decorationPositions[emptySlot] = tonumber(entry.pos) or 0
        eachFootprintCell(x, y, piece.width, piece.height, take)
      else
        context.log("%s at %s stays in the PC: its place is taken", tostring(entry.decor), tostring(entry.pos))
      end
    end
  end

  return SaveCompat
end
