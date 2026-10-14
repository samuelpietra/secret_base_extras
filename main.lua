-- Secret Base Extras (id: secret_base_extras)
--
-- Adds an EXTRA category to the Secret Base DECORATE menu holding furniture
-- the game has elsewhere: a bed (the bedroom one; resting in it heals the
-- party with the Weather Institute's bed script), a Pokemon Center PC (item
-- storage and the boxes) and a TV (the houses' one, with every show the
-- game's TVs have).  All are given to the player outright and are placed,
-- packed up and saved like any other decoration (lib/furniture.lua).
--
-- What the engine already does for every decoration, it does for these:
-- base.decorations / decorationPositions hold them, the cursor moves by their
-- shape, PACK UP finds and clears them.  This mod adds what a decoration
-- outside the vanilla table lacks:
--   data       its decorations and the category, in the engine's table;
--   menu       the ninth category, in a list that scrolls, and the placement
--              preview (lib/menu.lua);
--   placement  where each piece may stand (Decor.canPlace);
--   graphics   a tileset pair of this mod's own (lib/atlas.lua) and a redirect
--              of the furniture cells to it, only while the field is drawn;
--   collision  metatile overrides on the blocking cells, as decorations use;
--   A button   a wrap of SB.interactBg, which the field asks about every tile
--              the player faces in an RSE map;
--   the save   written as if this mod were not there (lib/save_compat.lua), so
--              removing the mod leaves a save the game fully understands.

return function(mod)
  local MOD_ID = "secret_base_extras"
  local VIRTUAL_PAIR = "mod__secret_base_extras"
  local OWN_BASE = 0
  -- Cells are keyed the way the engine keys metatile overrides
  -- (Field.setMetatile), so a key works on layout.overrides too.
  local MAP_ROW_STRIDE = 1024
  local function cellKey(x, y) return y * MAP_ROW_STRIDE + x end

  -- Decorations record the bottom-left cell of their footprint.
  local function footprintTop(bottomY, height) return bottomY - height + 1 end

  local ENGINE = {
    collision     = "src.core.game3.collision",
    constants     = "src.core.game3.constants",
    dataset       = "src.core.game3.dataset",
    decoration    = "src.core.game3.rse.decoration",
    decorInv      = "src.core.game3.rse.decoration_inventory",
    decorUI       = "src.ui.game3.rse.decoration",
    field         = "src.core.game3.field",
    fieldPlan     = "src.core.game3.field_plan",
    fieldView     = "src.core.game3.field_view",
    tv            = "src.core.game3.rse.tv",
    font          = "src.ui.game3.frlg_font",
    listMenu      = "src.ui.game3.list_menu",
    map           = "src.core.game3.map",
    nativeTileset = "src.core.game3.tileset_native",
    owSprites     = "src.core.game3.ow_sprites",
    pcNatives     = "src.core.game3.scripting.natives_pc_rse",
    player        = "src.core.game3.player",
    romText       = "src.core.game3.rom_text",
    rse           = "src.core.game3.rse.init",
    runtime       = "src.core.game3.runtime",
    secretBase    = "src.core.game3.rse.secret_base",
    window        = "src.ui.game3.window",
  }

  local function engineModule(path)
    local loaded, module = pcall(require, path)
    if not loaded or type(module) ~= "table" then return nil end
    return module
  end

  local function log(fmt, ...)
    print(("[%s] " .. fmt):format(MOD_ID, ...))
  end

  -- ------- mod-local modules

  local Lib = { mod = mod }
  local function libChunk(name)
    local rel = "lib/" .. name .. ".lua"
    local source = mod:read(rel)
    if not source then error(("%s: %s is missing"):format(MOD_ID, rel), 0) end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then error(("%s: %s did not compile: %s"):format(MOD_ID, rel, tostring(err)), 0) end
    return chunk()(Lib)
  end
  Lib.RomTileset = libChunk("rom_tileset")
  Lib.Furniture = libChunk("furniture")
  Lib.Atlas = libChunk("atlas")
  Lib.Menu = libChunk("menu")
  Lib.SaveCompat = libChunk("save_compat")

  local CATEGORY = Lib.Furniture.CATEGORY
  local PIECES = Lib.Furniture.PIECES
  local pieceByDecorId = {}
  for _, piece in ipairs(PIECES) do pieceByDecorId[piece.decorId] = piece end

  -- ------- the vanilla tilesets the furniture is drawn from, read once each

  local tilesetBySource, tilesetsUnavailable = {}, false

  local function datasetCache()
    local Dataset = engineModule(ENGINE.dataset)
    return Dataset and Dataset.cache and Dataset.cache() or nil
  end

  local function tilesetFor(source)
    local tileset = tilesetBySource[source.mapDir]
    if tileset then return tileset end
    local cache = datasetCache()
    local why = "no dataset cache"
    if cache then tileset, why = Lib.RomTileset.forMap(cache, source.mapDir, source.pretName) end
    if not tileset then error(why, 0) end
    tilesetBySource[source.mapDir] = tileset
    return tileset
  end

  -- Every piece's tileset, or false (logged once) when the cache lacks one.
  local function loadFurnitureTilesets()
    if tilesetsUnavailable then return false end
    for _, piece in ipairs(PIECES) do
      local loaded, why = pcall(tilesetFor, piece.source)
      if not loaded then
        tilesetsUnavailable = true
        log("furniture disabled: %s", tostring(why))
        return false
      end
    end
    return true
  end

  -- ------- the decorations and the category, in the engine's own tables

  -- DecorInv keeps its table in a local it reloads after a reset, so the
  -- entries are added each time it is handed out (see the DecorInv.data wrap).
  local function addDecorations(data)
    if type(data) ~= "table" or type(data.decorations) ~= "table" then return data end
    data.categoryNames = data.categoryNames or {}
    data.categoryNames[CATEGORY.index] = CATEGORY.name
    for _, piece in ipairs(PIECES) do
      if not data.decorations[piece.decorId] then
        data.decorations[piece.decorId] = {
          id = piece.decorId, category = CATEGORY.index, name = piece.name,
          description = piece.description, shape = piece.shape,
          -- pokeemerald/include/decoration.h DECORPERM_SOLID_FLOOR: placed on
          -- the map, not as an object event.  Where it may stand is this
          -- mod's own rule (canPlace below).
          permission = 0, price = 0,
        }
      end
    end
    return data
  end

  -- The player owns one of each, always: a piece that was tossed comes back
  -- on the next load.
  local function ensureOwned(session)
    local DecorInv = engineModule(ENGINE.decorInv)
    if not (session and DecorInv) then return end
    for _, piece in ipairs(PIECES) do
      if not DecorInv.has(piece.decorId, session) then DecorInv.add(piece.decorId, session) end
    end
  end

  -- ------- where the furniture stands in the current base

  -- state.footprint[cellKey(x, y)] = { piece, row, col, x, y, floorMid, blocked }
  --   the cells pieces occupy: collision, the A button, overlap checks
  -- state.art[cellKey(x, y)] = { x, y, layers = { { placement, piece, row, col }, ... } }
  --   every art cell drawn there, footprint or overhang, in placement order
  -- state.placements[piece.id .. ":" .. left .. ":" .. top] = placement
  --   one token per placed piece, which its art entries carry
  local state = { active = false }
  local drawingField = false
  -- switchedOn[piece.id]: the piece shows its cellsOn art (a PC in use, a TV with a
  -- show on air).  fieldDrawCount counts field draws, the clock of onAnim.
  local switchedOn = {}
  local fieldDrawCount = 0

  local function currentSession()
    local Runtime = engineModule(ENGINE.runtime)
    return Runtime and Runtime.getSession and Runtime.getSession() or nil
  end

  local function inOwnBase(session)
    local SB, Rse = engineModule(ENGINE.secretBase), engineModule(ENGINE.rse)
    if not (session and SB and Rse) then return false end
    local called, inBase = pcall(SB.curMapIsSecretBase, session)
    return called and inBase and Rse.var("VAR_CURRENT_SECRET_BASE", session) == OWN_BASE
  end

  local function invalidate(x, y)
    local FieldView = engineModule(ENGINE.fieldView)
    if FieldView and FieldView.invalidateCell then FieldView.invalidateCell(x, y) end
  end

  -- left/top is the footprint's top-left cell.  fn(x, y, row, col) per
  -- footprint cell.
  local function eachCell(piece, left, top, fn)
    for row = 0, piece.height - 1 do
      for col = 0, piece.width - 1 do
        fn(left + col, top + row, row, col)
      end
    end
  end

  -- fn(x, y, row, col) per art cell, row/col in the art grid.
  local function eachArtCell(piece, left, top, fn)
    for row, line in ipairs(piece.art.cells) do
      for col in ipairs(line) do
        fn(left + piece.art.x + col - 1, top + row - 1, row - 1, col - 1)
      end
    end
  end

  local function placementKey(piece, left, top)
    return piece.id .. ":" .. left .. ":" .. top
  end

  local function addPiece(layout, piece, left, top)
    local Field = engineModule(ENGINE.field)
    local placement = {}
    state.placements[placementKey(piece, left, top)] = placement
    eachCell(piece, left, top, function(x, y, row, col)
      local cell = { piece = piece, row = row, col = col, x = x, y = y,
        floorMid = layout:midAt(x, y), blocked = piece.blocked[row + 1][col + 1] }
      state.footprint[cellKey(x, y)] = cell
      if cell.blocked and Field then Field.setMetatile(x, y, cell.floorMid, true) end
    end)
    eachArtCell(piece, left, top, function(x, y, row, col)
      local key = cellKey(x, y)
      state.art[key] = state.art[key] or { x = x, y = y, layers = {} }
      table.insert(state.art[key].layers, { placement = placement, piece = piece, row = row, col = col })
      invalidate(x, y)
    end)
    state.atlas = nil
  end

  -- PACK UP finds pieces by footprint; the art they left in other cells goes
  -- with them.
  local function removePiece(piece, left, top)
    local placement = state.placements[placementKey(piece, left, top)]
    state.placements[placementKey(piece, left, top)] = nil
    eachCell(piece, left, top, function(x, y)
      state.footprint[cellKey(x, y)] = nil
    end)
    eachArtCell(piece, left, top, function(x, y)
      local key = cellKey(x, y)
      local cell = state.art[key]
      local list = cell and cell.layers or {}
      for i = #list, 1, -1 do
        if list[i].placement == placement then table.remove(list, i) end
      end
      if cell and #list == 0 then state.art[key] = nil end
      invalidate(x, y)
    end)
    state.atlas = nil
  end

  -- ------- the save (lib/save_compat.lua)

  local function saveContext()
    local Decor, SB = engineModule(ENGINE.decoration), engineModule(ENGINE.secretBase)
    return {
      modId = MOD_ID, extraCategory = CATEGORY.index, maxDecorations = Decor.MAX_SECRET_BASE,
      pieceByDecorId = pieceByDecorId, log = log,
      ownBase = function(session) return SB.base(session, OWN_BASE) end,
      decodePosition = Decor.decodePos, decorationSize = Decor.dims,
    }
  end

  local function restorePlaced(session)
    Lib.SaveCompat.restorePlaced(session, saveContext())
  end

  -- Runs after the engine has laid the base's own decorations out.  The
  -- collision overrides are cleared by every map load, which is why this runs
  -- on every load and not once.
  local function onBaseLoaded()
    switchedOn = {}
    local session = currentSession()
    restorePlaced(session)
    ensureOwned(session)
    if not inOwnBase(session) or not loadFurnitureTilesets() then
      state = { active = false }
      return
    end
    local Collision, SB, Decor = engineModule(ENGINE.collision), engineModule(ENGINE.secretBase),
      engineModule(ENGINE.decoration)
    local def = Collision and Collision._mapDef
    local layout = def and def.midLayout
    if not (layout and SB and Decor) then
      state = { active = false }
      return
    end
    state = { active = true, mapId = session.map, def = def, layout = layout, pair = def.pair or layout.pair,
      footprint = {}, art = {}, placements = {} }
    local base = SB.base(session, OWN_BASE)
    for i = 1, Decor.MAX_SECRET_BASE do
      local piece = pieceByDecorId[tonumber(base.decorations[i])]
      if piece then
        local x, y = Decor.decodePos(base.decorationPositions[i])
        addPiece(layout, piece, x, footprintTop(y, piece.height))
      end
    end
  end

  -- ------- where a piece may stand

  local function footprintOverlap(left, top, width, height)
    for y = top, top + height - 1 do
      for x = left, left + width - 1 do
        if state.footprint[cellKey(x, y)] then return true end
      end
    end
    return false
  end

  -- A cell holds a decoration when its override shows another metatile than
  -- the layout's own.  PACK UP leaves an override behind too, but one that
  -- restores the original metatile, and that cell is free again.
  local function decorated(layout, x, y)
    local override = layout.overrides[cellKey(x, y)]
    if not override then return false end
    local cell = layout.cells[y * layout.width + x + 1]
    return not cell or override.mid ~= cell.mid
  end

  -- Every footprint cell on plain floor (NORMAL behaviour, walkable, no
  -- decoration already there, no object), and no blocking cell where the
  -- player stands.  The top `wallRows` rows may stand on the north wall
  -- instead, and the rows above the lowest one that does are left unchecked:
  -- they only draw over the wall's top.  Art outside the footprint may fall
  -- anywhere.
  local function canPlacePiece(grid, place, piece)
    local Decor = engineModule(ENGINE.decoration)
    local layout = state.layout
    if not (state.active and layout and Decor) then return false end
    local left, top = place.x, footprintTop(place.y, piece.height)
    local function onWall(x, y)
      return x >= 0 and y >= 0 and x < layout.width and y < layout.height
        and Decor.isBeh(grid.behavior(x, y), "SECRET_BASE_NORTH_WALL")
    end
    for col = 0, piece.width - 1 do
      local x = left + col
      local wallRow = -1
      for row = (piece.wallRows or 0) - 1, 0, -1 do
        if onWall(x, top + row) then wallRow = row break end
      end
      for row = math.max(wallRow, 0), piece.height - 1 do
        local y = top + row
        if x < 0 or y < 0 or x >= layout.width or y >= layout.height
            or state.footprint[cellKey(x, y)] or decorated(layout, x, y) then
          return false
        end
        local blocked = piece.blocked[row + 1][col + 1]
        local object = grid.objectAt(x, y)
        if (object ~= nil and object ~= 0) or (blocked and (object == 0
            or (x == place.initialX and y == place.initialY))) then
          return false
        end
        if row ~= wallRow then
          local cell = layout:cellAt(x, y)
          if not (Decor.isBeh(grid.behavior(x, y), "NORMAL") and cell and cell.coll == 0) then return false end
        end
      end
    end
    return true
  end

  -- ------- graphics

  local function artMid(piece, row, col, on)
    local grid = (on and piece.art.cellsOn) or piece.art.cells
    return grid[row + 1][col + 1]
  end

  -- onAnim, read once per piece from the engine's prepared animation bank
  -- (src/core/game3/tileset_anim.lua).  The bank file holds, frame after
  -- frame, 256 bytes of palette slot (the tileset's own encoding, 0 meaning
  -- transparent) for each mid its manifest lists, so the cell's frames are
  -- found by the position of its mid in that list.
  local animations = {}
  local function animationFor(piece)
    local anim = piece.art.onAnim
    if not anim then return nil end
    if animations[piece] ~= nil then return animations[piece] or nil end
    animations[piece] = false
    local cache = datasetCache()
    local root = "data/generated/gba/native/" .. anim.pair .. "/"
    local source = cache and cache:read(root .. "anim_manifest.lua")
    local chunk = type(source) == "string" and load(source, "@" .. root .. "anim_manifest.lua")
    local readOk, manifest = false, nil
    if chunk then readOk, manifest = pcall(chunk) end
    local bank
    for _, bankRow in ipairs(readOk and type(manifest) == "table" and manifest.banks or {}) do
      if bankRow.file == anim.file then bank = bankRow break end
    end
    local mid = artMid(piece, anim.row, anim.col, true)
    local midIndex
    for i, m in ipairs(bank and bank.mids or {}) do
      if m == mid then midIndex = i break end
    end
    local blob = midIndex and cache:read(root .. anim.file)
    if type(blob) == "string" and blob:byte(1) == 0x78 then
      local inflated, raw = pcall(love.data.decompress, "string", "zlib", blob)
      blob = inflated and raw or nil
    end
    local count, midsPerFrame = bank and tonumber(bank.frames) or 0, bank and #bank.mids or 0
    if type(blob) ~= "string" or count < 1 or #blob < count * midsPerFrame * 256 then
      log("%s: no %s animation, its screen will not blink", piece.id, anim.file)
      return nil
    end
    local frames = {}
    for frame = 0, count - 1 do
      local base = (frame * midsPerFrame + midIndex - 1) * 256
      local pixels = {}
      for i = 1, 256 do
        local value = blob:byte(base + i)
        pixels[i] = value % 16 == 0 and 0 or value
      end
      frames[frame] = pixels
    end
    animations[piece] = { frames = frames, count = count, period = tonumber(bank.period) or 1 }
    return animations[piece]
  end

  local function animationFrame(piece)
    local animation = animationFor(piece)
    return animation and math.floor(fieldDrawCount / animation.period) % animation.count or 0
  end

  -- A cell's picture is what the base shows there now (layout:midAt, which
  -- includes decorations) plus the art reaching into it, each piece on or off
  -- and, when animated, at the given frame.  The key names all of it, so a
  -- decoration placed under a piece's overhang, or a piece switching on, is
  -- a new key and recomposes on its own.
  local function cellPicture(x, y, frameOf)
    local baseMid = state.layout:midAt(x, y)
    local parts, layers = { tostring(baseMid) }, {}
    local cell = state.art[cellKey(x, y)]
    for _, layer in ipairs(cell and cell.layers or {}) do
      local on = switchedOn[layer.piece.id] == true
      local layerMid = artMid(layer.piece, layer.row, layer.col, on)
      local onAnim = on and layer.piece.art.onAnim
      local pixels
      local part = layer.piece.id .. ":" .. layer.row .. ":" .. layer.col .. ":" .. layerMid
      if onAnim and layer.row == onAnim.row and layer.col == onAnim.col then
        local animation = animationFor(layer.piece)
        local frame = frameOf(layer.piece)
        pixels = animation and animation.frames[frame]
        if pixels then part = part .. ":" .. frame end
      end
      parts[#parts + 1] = part
      layers[#layers + 1] = { piece = layer.piece, tileset = tilesetFor(layer.piece.source), row = layer.row, col = layer.col, mid = layerMid,
        pixels = pixels }
    end
    return table.concat(parts, ","), baseMid, layers
  end

  -- Composes every picture the base needs now, every animation frame of the
  -- pieces that are on, into this mod's pair.  Switching a piece on or off
  -- recomposes (redirect finds its key missing).
  local function rebuildAtlas()
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    local floorAtlas = NativeTileset and NativeTileset._pairs[state.pair]
    if not (floorAtlas and floorAtlas.imageData) then return false end
    local list, index = {}, {}
    local frameCount = 1
    for _, piece in ipairs(PIECES) do
      local animation = switchedOn[piece.id] and animationFor(piece)
      if animation then frameCount = math.max(frameCount, animation.count) end
    end
    for _, cell in pairs(state.art) do
      for frame = 0, frameCount - 1 do
        local id, baseMid, layers = cellPicture(cell.x, cell.y, function(piece)
          local animation = animationFor(piece)
          return animation and frame % animation.count or 0
        end)
        if not index[id] then
          list[#list + 1] = { floorMid = baseMid, layers = layers }
          index[id] = #list
        end
      end
    end
    local built, atlas, mids = pcall(Lib.Atlas.build, VIRTUAL_PAIR, floorAtlas, NativeTileset, list)
    if not built then
      log("could not compose the furniture: %s", tostring(atlas))
      state.active = false
      return false
    end
    for id, i in pairs(index) do index[id] = mids[i] end
    state.atlas, state.slotByPicture = atlas, index
    NativeTileset._pairs[VIRTUAL_PAIR] = atlas
    return true
  end

  local function atlasLive()
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    return state.atlas and state.atlas.image and NativeTileset and NativeTileset._pairs[VIRTUAL_PAIR] == state.atlas
  end

  -- The cell's mid in this mod's pair, or nil to let the engine draw it.
  local function redirect(x, y)
    if not (drawingField and state.active and state.art[cellKey(x, y)]) then return nil end
    local Map = engineModule(ENGINE.map)
    if not (Map and Map.current == state.mapId) then return nil end
    local picture = cellPicture(x, y, animationFrame)
    local slot = atlasLive() and state.slotByPicture[picture]
    if slot then return slot end
    if not rebuildAtlas() then return nil end
    return state.slotByPicture[picture]
  end

  -- Switching a piece on or off redraws its art cells.
  local function setSwitchedOn(piece, on)
    if (switchedOn[piece.id] == true) == (on == true) then return end
    switchedOn[piece.id] = on == true
    for _, cell in pairs(state.art or {}) do
      for _, layer in ipairs(cell.layers) do
        if layer.piece == piece then invalidate(cell.x, cell.y) break end
      end
    end
  end

  -- Each field draw advances the animation clock; when an animated piece
  -- that is on reaches a new frame, its animated cell is redrawn.
  local function tick()
    fieldDrawCount = fieldDrawCount + 1
    if not state.active then return end
    for _, cell in pairs(state.footprint) do
      local onAnim = cell.piece.art.onAnim
      -- once per piece: from its footprint's top-left cell to the art cell
      if onAnim and cell.row == 0 and cell.col == 0 and switchedOn[cell.piece.id] then
        local animation = animationFor(cell.piece)
        if animation and fieldDrawCount % animation.period == 0 then invalidate(cell.x + cell.piece.art.x + onAnim.col, cell.y + onAnim.row) end
      end
    end
  end

  -- The placement preview: each piece's art alone, without floor, composed
  -- once.  slots[row][col] follow the art grid.
  local previews = {}
  local function previewFor(piece)
    if previews[piece] then return previews[piece] end
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    local list, artCells = {}, {}
    eachArtCell(piece, 0, 0, function(_, _, row, col)
      list[#list + 1] = { layers = { { piece = piece, tileset = tilesetFor(piece.source), row = row, col = col,
        mid = artMid(piece, row, col, false) } } }
      artCells[#list] = { row = row, col = col }
    end)
    local atlas, mids = Lib.Atlas.build(VIRTUAL_PAIR .. "_preview", false, NativeTileset, list)
    local slots = {}
    for i, artCell in ipairs(artCells) do
      slots[artCell.row + 1] = slots[artCell.row + 1] or {}
      slots[artCell.row + 1][artCell.col + 1] = mids[i]
    end
    previews[piece] = { atlas = atlas, slots = slots }
    return previews[piece]
  end

  -- ------- the DECORATE screen

  local function screenModules()
    return {
      Constants = engineModule(ENGINE.constants), Decor = engineModule(ENGINE.decoration),
      DecorInv = engineModule(ENGINE.decorInv), FrlgFont = engineModule(ENGINE.font),
      ListMenu = engineModule(ENGINE.listMenu), OwSprites = engineModule(ENGINE.owSprites),
      Window = engineModule(ENGINE.window),
    }
  end

  -- The screen names a category through a table indexed by category, which
  -- has no ninth entry, so it asks for the text of nil: that is EXTRA.
  local function screenText(previous)
    return function(key, vars)
      if key == nil then return CATEGORY.name end
      if previous then return previous(key, vars) end
      local RomText = engineModule(ENGINE.romText)
      return RomText.plain(key, vars and { stringVars = vars } or nil)
    end
  end

  -- The screen calls opts.draw instead of its own drawing when one is given.
  -- This one draws the two pictures it owns and hands everything else back,
  -- by drawing once more with opts.draw cleared.
  local function screenDraw(previous)
    local function engineDraw(screen, helpers)
      if previous then return previous(screen, helpers) end
      local opts = screen._opts
      local mine = opts.draw
      opts.draw = nil
      local drawn, err = pcall(screen.draw)
      opts.draw = mine
      if not drawn then error(err, 0) end
    end
    return function(screen, helpers)
      local Decor = engineModule(ENGINE.decoration)
      if screen.mode and screen.mode.kind == "place" and pieceByDecorId[screen.mode.decor] then
        local piece = pieceByDecorId[screen.mode.decor]
        Lib.Menu.drawPlacing(screen, screenModules(), piece, previewFor(piece))
        -- The message and the yes/no still come from the engine.
        local mode = screen.mode
        screen.mode = nil
        local drawn, err = pcall(engineDraw, screen, helpers)
        screen.mode = mode
        if not drawn then error(err, 0) end
        return
      end
      if not screen.mode and screen.view == "categories" and Decor.CATEGORY_COUNT > CATEGORY.index then
        return Lib.Menu.drawCategories(screen, screenModules(), screen._opts.text)
      end
      return engineDraw(screen, helpers)
    end
  end

  -- ------- engine wraps
  --
  -- Each original is kept on the engine module under ORIGINALS, so loading
  -- this mod twice (a hot reload) wraps the engine's function, not our own.

  local ORIGINALS = "__" .. MOD_ID .. "_originals"

  local missingHooks = {}

  local function wrap(module, name, make)
    if not (module and type(module[name]) == "function") then
      missingHooks[#missingHooks + 1] = name
      return
    end
    local saved = rawget(module, ORIGINALS)
    if not saved then
      saved = {}
      module[ORIGINALS] = saved
    end
    saved[name] = saved[name] or module[name]
    module[name] = make(saved[name])
  end

  local function install()
    local Decor = engineModule(ENGINE.decoration)
    local DecorInv = engineModule(ENGINE.decorInv)
    local DecorUI = engineModule(ENGINE.decorUI)
    local FieldView = engineModule(ENGINE.fieldView)
    local Map = engineModule(ENGINE.map)
    local Plan = engineModule(ENGINE.fieldPlan)
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    local SB = engineModule(ENGINE.secretBase)
    local PcNatives = engineModule(ENGINE.pcNatives)
    local Player = engineModule(ENGINE.player)
    if not (Decor and DecorInv) then
      missingHooks[#missingHooks + 1] = "decoration modules"
      return
    end

    -- --- data

    DecorInv.SIZES[CATEGORY.index] = CATEGORY.size
    wrap(DecorInv, "data", function(original)
      return function(...) return addDecorations(original(...)) end
    end)

    -- DecorInv.inventories fills in the eight vanilla lists; EXTRA's is added
    -- alongside, so every inventory function that takes a category works on it.
    wrap(DecorInv, "inventories", function(original)
      return function(...)
        local inventories = original(...)
        if type(inventories) == "table" then
          local list = type(inventories[CATEGORY.index]) == "table" and inventories[CATEGORY.index] or {}
          for i = 1, CATEGORY.size do list[i] = tonumber(list[i]) or DecorInv.DECOR_NONE end
          inventories[CATEGORY.index] = list
        end
        return inventories
      end
    end)

    -- DecorInv.CATEGORY_COUNT stays 8: the trader's menus and the save layout
    -- read it.  The DECORATE screen reads Decor.CATEGORY_COUNT, raised to 9
    -- while it is open from a PC and kept at 8 in the trader's mode, so mod
    -- furniture is never traded away.  Its "no decorations" check counts with
    -- DecorInv.count, which then has to include EXTRA.
    wrap(DecorInv, "count", function(original)
      return function(session, ...)
        local total = original(session, ...)
        if Decor.CATEGORY_COUNT > CATEGORY.index then total = total + DecorInv.countInCategory(CATEGORY.index, session) end
        return total
      end
    end)

    -- --- the DECORATE screen

    wrap(DecorUI, "open", function(original)
      return function(opts, ...)
        opts = opts or {}
        Decor.CATEGORY_COUNT = CATEGORY.index + 1
        ensureOwned(opts.session or currentSession())
        opts.text = screenText(opts.text)
        opts.draw = screenDraw(opts.draw)
        return original(opts, ...)
      end
    end)

    wrap(DecorUI, "openTrade", function(original)
      return function(...)
        Decor.CATEGORY_COUNT = CATEGORY.index
        return original(...)
      end
    end)

    -- --- placing and packing up

    wrap(Decor, "canPlace", function(original)
      return function(grid, place, decor, ...)
        local piece = pieceByDecorId[tonumber(decor)]
        if piece then return canPlacePiece(grid, place, piece) end
        -- A vanilla decoration may not land on this mod's furniture either.
        local width, height = Decor.dims(decor)
        if state.active and footprintOverlap(place.x, footprintTop(place.y, height), width, height) then return false end
        return original(grid, place, decor, ...)
      end
    end)

    wrap(Decor, "showOnMap", function(original)
      return function(grid, mapX, mapY, decor, ...)
        local piece = pieceByDecorId[tonumber(decor)]
        if not piece then return original(grid, mapX, mapY, decor, ...) end
        if not (state.active and state.layout) then return false end
        addPiece(state.layout, piece, mapX, footprintTop(mapY, piece.height))
        return true
      end
    end)

    -- PACK UP finds a decoration by its footprint.  A cursor on a cell only
    -- this mod's art reaches (the bed's frame in the next column) finds the
    -- piece too, unless a decoration's footprint is there.
    wrap(Decor, "markForRemoval", function(original)
      return function(grid, context, x, y, ...)
        local marked = original(grid, context, x, y, ...)
        if #marked > 0 or not state.active then return marked end
        local cell = state.art[cellKey(x, y)]
        for _, layer in ipairs(cell and cell.layers or {}) do
          local footprintLeft = x - layer.piece.art.x - layer.col
          local retried = original(grid, context, footprintLeft, y, ...)
          if #retried > 0 then return retried end
        end
        return marked
      end
    end)

    -- PACK UP: the engine restores the metatiles and frees the record; this
    -- drops the pieces from the drawing first, while the record still says
    -- where they were.
    wrap(Decor, "clearNonSprites", function(original)
      return function(grid, context, marked, ...)
        for _, mark in ipairs(marked or {}) do
          local piece = pieceByDecorId[tonumber(context.items[mark.idx])]
          if piece and state.active then
            local x, y = Decor.decodePos(context.pos[mark.idx])
            removePiece(piece, x, footprintTop(y, piece.height))
          end
        end
        return original(grid, context, marked, ...)
      end
    end)

    -- --- graphics

    -- Map.worldMidAt also answers Collision.worldBehavior, so the redirect is
    -- only on while the field itself is being drawn.
    local function drawn(succeeded, ...)
      drawingField = false
      if not succeeded then error((...), 0) end
      return ...
    end
    wrap(FieldView, "draw", function(original)
      return function(...)
        drawingField = true
        tick()
        return drawn(pcall(original, ...))
      end
    end)

    wrap(Map, "worldMidAt", function(original)
      return function(x, y, primaryDef)
        if primaryDef == state.def then
          local mid = redirect(x, y)
          if mid then return mid, VIRTUAL_PAIR end
        end
        return original(x, y, primaryDef)
      end
    end)

    -- The worker-prepared route of the same lookup (field_view.lua addCell).
    wrap(Plan, "cell", function(original)
      return function(plan, x, y)
        local mid = redirect(x, y)
        if mid then return mid, VIRTUAL_PAIR, false, false end
        return original(plan, x, y)
      end
    end)

    -- Our pair has no file behind it; once trimmed it could not come back.
    wrap(NativeTileset, "trim", function(original)
      return function(keep, ...)
        keep = keep or {}
        keep[VIRTUAL_PAIR] = true
        return original(keep, ...)
      end
    end)

    -- --- loading the base

    wrap(SB, "onMapLoad", function(original)
      return function(...)
        local result = original(...)
        local loaded, err = pcall(onBaseLoaded)
        if not loaded then
          state = { active = false }
          log("furniture disabled for this visit: %s", tostring(err))
        end
        return result
      end
    end)

    -- --- using the furniture

    -- pokeemerald/src/field_control_avatar.c GetInteractedBackgroundEventScript
    -- is where the field asks.  A piece runs its script from any side, or, if
    -- fromBelow, only faced from below at its screen row, as the game's PCs
    -- and TVs are (their behaviours' "facing up" rule).
    wrap(SB, "interactBg", function(original)
      return function(x, y, facing, elevation)
        local cell = state.active and state.footprint[cellKey(x, y)]
        if cell and inOwnBase(currentSession()) then
          local piece = cell.piece
          if not piece.fromBelow or (cell.row == piece.screenRow and (facing == "up" or facing == 2)) then
            return SB.startScript(piece.script)
          end
          return false
        end
        return original(x, y, facing, elevation)
      end
    end)

    -- DoPCTurnOnEffect / DoPCTurnOffEffect write the Pokemon Center screen
    -- into the tile above the player.  On our PC, light its own screen.
    wrap(PcNatives, "setPcMetatile", function(original)
      return function(scriptContext, on)
        local cell = state.active and Player and Player.facing == "up"
          and state.footprint[cellKey(tonumber(Player.cellX) or 0, (tonumber(Player.cellY) or 0) - 1)]
        if cell and cell.piece == Lib.Furniture.PC then
          setSwitchedOn(cell.piece, on)
          return nil
        end
        return original(scriptContext, on)
      end
    end)

    -- Every TV screen on the map switches through Tv.setScreens (on entering
    -- an indoor map with a show on air, off once it has been watched), which
    -- finds them by their TELEVISION behaviour.  This mod's TV has none, so
    -- it follows the same call.
    wrap(engineModule(ENGINE.tv), "setScreens", function(original)
      return function(layout, behaviorAt, setMetatile, isTv, metatile, ...)
        local count = original(layout, behaviorAt, setMetatile, isTv, metatile, ...)
        if state.active and layout == state.layout then
          local TV = Lib.Furniture.TV
          setSwitchedOn(TV, metatile == artMid(TV, TV.screenRow, 0, true))
        end
        return count
      end
    end)

  end

  install()
  if #missingHooks > 0 then
    log("this engine version lacks %s; those parts of the mod are off", table.concat(missingHooks, ", "))
  end

  mod.events:on("save.writing", function(payload)
    local cleaned, err = pcall(function() Lib.SaveCompat.writeClean(payload.save, saveContext()) end)
    if not cleaned then log("save written with the mod's furniture in it: %s", tostring(err)) end
  end)
  mod.events:on("save.loaded", function(payload)
    local restored, err = pcall(restorePlaced, payload and payload.save)
    if not restored then log("could not put the furniture back: %s", tostring(err)) end
  end)
end
