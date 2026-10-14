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
--   data       the two decorations and the category, in the engine's table;
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
  -- One map row in the engine's override keys (Field.setMetatile).
  local ROW = 1024

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

  local V = { mod = mod }
  local function libChunk(name)
    local rel = "lib/" .. name .. ".lua"
    local source = mod:read(rel)
    if not source then error(("%s: %s is missing"):format(MOD_ID, rel), 0) end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then error(("%s: %s did not compile: %s"):format(MOD_ID, rel, tostring(err)), 0) end
    return chunk()(V)
  end
  V.RomTileset = libChunk("rom_tileset")
  V.Furniture = libChunk("furniture")
  V.Atlas = libChunk("atlas")
  V.Menu = libChunk("menu")
  V.SaveCompat = libChunk("save_compat")

  local CATEGORY = V.Furniture.CATEGORY
  local PIECES = V.Furniture.PIECES
  local byDecorId = {}
  for _, piece in ipairs(PIECES) do byDecorId[piece.decorId] = piece end

  -- ------- the vanilla tilesets the furniture is drawn from, read once each

  local roms, romFailed = {}, false

  local function romFor(source)
    local rom = roms[source.mapDir]
    if rom then return rom end
    local Dataset = engineModule(ENGINE.dataset)
    local cache = Dataset and Dataset.cache and Dataset.cache()
    local why = "no dataset cache"
    if cache then rom, why = V.RomTileset.forMap(cache, source.mapDir, source.pretName) end
    if not rom then error(why, 0) end
    roms[source.mapDir] = rom
    return rom
  end

  -- Every piece's tileset, or false (logged once) when the cache lacks one.
  local function furnitureTilesets()
    if romFailed then return false end
    for _, piece in ipairs(PIECES) do
      local loaded, why = pcall(romFor, piece.source)
      if not loaded then
        romFailed = true
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
  local function ensureOwned(sess)
    local DecorInv = engineModule(ENGINE.decorInv)
    if not (sess and DecorInv) then return end
    for _, piece in ipairs(PIECES) do
      if not DecorInv.has(piece.decorId, sess) then DecorInv.add(piece.decorId, sess) end
    end
  end

  -- ------- where the furniture stands in the current base

  -- state.footprint[y * ROW + x] = { piece, row, col, x, y, floorMid, blocked }
  --   the cells pieces occupy: collision, the A button, overlap checks
  -- state.art[y * ROW + x] = { x, y, layers = { { owner, piece, row, col }, ... } }
  --   every art cell drawn there, footprint or overhang, in placement order
  -- state.placed[piece.id .. ":" .. left .. ":" .. top] = owner
  --   one token per placed piece, which its art entries carry
  local state = { active = false }
  local drawing = false
  -- lit[piece.id]: the piece shows its cellsOn art (a PC in use, a TV with a
  -- show on air).  ticks counts field draws, the clock of onAnim.
  local lit = {}
  local ticks = 0

  local function currentSession()
    local Runtime = engineModule(ENGINE.runtime)
    return Runtime and Runtime.getSession and Runtime.getSession() or nil
  end

  local function inOwnBase(sess)
    local SB, Rse = engineModule(ENGINE.secretBase), engineModule(ENGINE.rse)
    if not (sess and SB and Rse) then return false end
    local called, inBase = pcall(SB.curMapIsSecretBase, sess)
    return called and inBase and Rse.var("VAR_CURRENT_SECRET_BASE", sess) == OWN_BASE
  end

  local function invalidate(x, y)
    local FieldView = engineModule(ENGINE.fieldView)
    if FieldView and FieldView.invalidateCell then FieldView.invalidateCell(x, y) end
  end

  -- left/top is the footprint's top-left cell; decorations record the
  -- bottom-left.  fn(x, y, row, col) per footprint cell.
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

  local function placedKey(piece, left, top)
    return piece.id .. ":" .. left .. ":" .. top
  end

  local function addPiece(layout, piece, left, top)
    local Field = engineModule(ENGINE.field)
    local owner = {}
    state.placed[placedKey(piece, left, top)] = owner
    eachCell(piece, left, top, function(x, y, row, col)
      local c = { piece = piece, row = row, col = col, x = x, y = y,
        floorMid = layout:midAt(x, y), blocked = piece.blocked[row + 1][col + 1] }
      state.footprint[y * ROW + x] = c
      if c.blocked and Field then Field.setMetatile(x, y, c.floorMid, true) end
    end)
    eachArtCell(piece, left, top, function(x, y, row, col)
      local key = y * ROW + x
      state.art[key] = state.art[key] or { x = x, y = y, layers = {} }
      table.insert(state.art[key].layers, { owner = owner, piece = piece, row = row, col = col })
      invalidate(x, y)
    end)
    state.ts = nil
  end

  -- PACK UP finds pieces by footprint; the art they left in other cells goes
  -- with them.
  local function removePiece(piece, left, top)
    local owner = state.placed[placedKey(piece, left, top)]
    state.placed[placedKey(piece, left, top)] = nil
    eachCell(piece, left, top, function(x, y)
      state.footprint[y * ROW + x] = nil
    end)
    eachArtCell(piece, left, top, function(x, y)
      local key = y * ROW + x
      local cell = state.art[key]
      local list = cell and cell.layers or {}
      for i = #list, 1, -1 do
        if list[i].owner == owner then table.remove(list, i) end
      end
      if cell and #list == 0 then state.art[key] = nil end
      invalidate(x, y)
    end)
    state.ts = nil
  end

  -- ------- the save (lib/save_compat.lua)

  local function saveContext()
    local Decor, SB = engineModule(ENGINE.decoration), engineModule(ENGINE.secretBase)
    return {
      modId = MOD_ID, extraCategory = CATEGORY.index, maxDecorations = Decor.MAX_SECRET_BASE,
      pieceByDecorId = byDecorId, log = log,
      ownBase = function(session) return SB.base(session, OWN_BASE) end,
      decodePosition = Decor.decodePos, decorationSize = Decor.dims,
    }
  end

  local function restorePlaced(session)
    V.SaveCompat.restorePlaced(session, saveContext())
  end

  -- Runs after the engine has laid the base's own decorations out.  The
  -- collision overrides are cleared by every map load, which is why this runs
  -- on every load and not once.
  local function onBaseLoaded()
    lit = {}
    local sess = currentSession()
    restorePlaced(sess)
    ensureOwned(sess)
    if not inOwnBase(sess) or not furnitureTilesets() then
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
    state = { active = true, mapId = sess.map, def = def, layout = layout, pair = def.pair or layout.pair,
      footprint = {}, art = {}, placed = {} }
    local base = SB.base(sess, OWN_BASE)
    for i = 1, Decor.MAX_SECRET_BASE do
      local piece = byDecorId[tonumber(base.decorations[i])]
      if piece then
        local x, y = Decor.decodePos(base.decorationPositions[i])
        addPiece(layout, piece, x, y - piece.height + 1)
      end
    end
  end

  -- ------- where a piece may stand

  local function footprintOverlap(left, top, width, height)
    for y = top, top + height - 1 do
      for x = left, left + width - 1 do
        if state.footprint[y * ROW + x] then return true end
      end
    end
    return false
  end

  -- A cell holds a decoration when its override shows another metatile than
  -- the layout's own.  PACK UP leaves an override behind too, but one that
  -- restores the original metatile, and that cell is free again.
  local function decorated(layout, x, y)
    local ov = layout.overrides[y * ROW + x]
    if not ov then return false end
    local cell = layout.cells[y * layout.width + x + 1]
    return not cell or ov.mid ~= cell.mid
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
    local left, top = place.x, place.y - piece.height + 1
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
            or state.footprint[y * ROW + x] or decorated(layout, x, y) then
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
  local anims = {}
  local function animFor(piece)
    local anim = piece.art.onAnim
    if not anim then return nil end
    if anims[piece] ~= nil then return anims[piece] or nil end
    anims[piece] = false
    local Dataset = engineModule(ENGINE.dataset)
    local cache = Dataset and Dataset.cache and Dataset.cache()
    local root = "data/generated/gba/native/" .. anim.pair .. "/"
    local source = cache and cache:read(root .. "anim_manifest.lua")
    local chunk = type(source) == "string" and load(source, "@" .. root .. "anim_manifest.lua")
    local readOk, manifest = false, nil
    if chunk then readOk, manifest = pcall(chunk) end
    local bank
    for _, row in ipairs(readOk and type(manifest) == "table" and manifest.banks or {}) do
      if row.file == anim.file then bank = row break end
    end
    local mid = artMid(piece, anim.row, anim.col, true)
    local k
    for i, m in ipairs(bank and bank.mids or {}) do
      if m == mid then k = i break end
    end
    local blob = k and cache:read(root .. anim.file)
    if type(blob) == "string" and blob:byte(1) == 0x78 then
      local inflated, raw = pcall(love.data.decompress, "string", "zlib", blob)
      blob = inflated and raw or nil
    end
    local count, stride = bank and tonumber(bank.frames) or 0, bank and #bank.mids or 0
    if type(blob) ~= "string" or count < 1 or #blob < count * stride * 256 then
      log("%s: no %s animation, its screen will not blink", piece.id, anim.file)
      return nil
    end
    local frames = {}
    for f = 0, count - 1 do
      local base = (f * stride + k - 1) * 256
      local px = {}
      for i = 1, 256 do
        local v = blob:byte(base + i)
        px[i] = v % 16 == 0 and 0 or v
      end
      frames[f] = px
    end
    anims[piece] = { frames = frames, count = count, period = tonumber(bank.period) or 1 }
    return anims[piece]
  end

  local function animFrame(piece)
    local a = animFor(piece)
    return a and math.floor(ticks / a.period) % a.count or 0
  end

  -- A cell's picture is what the base shows there now (layout:midAt, which
  -- includes decorations) plus the art reaching into it, each piece on or off
  -- and, when animated, at the given frame.  The key names all of it, so a
  -- decoration placed under a piece's overhang, or a piece switching on, is
  -- a new key and recomposes on its own.
  local function cellPicture(x, y, frameOf)
    local mid = state.layout:midAt(x, y)
    local parts, layers = { tostring(mid) }, {}
    local cell = state.art[y * ROW + x]
    for _, a in ipairs(cell and cell.layers or {}) do
      local on = lit[a.piece.id] == true
      local m = artMid(a.piece, a.row, a.col, on)
      local anim = on and a.piece.art.onAnim
      local pixels
      local part = a.piece.id .. ":" .. a.row .. ":" .. a.col .. ":" .. m
      if anim and a.row == anim.row and a.col == anim.col then
        local loaded = animFor(a.piece)
        local f = frameOf(a.piece)
        pixels = loaded and loaded.frames[f]
        if pixels then part = part .. ":" .. f end
      end
      parts[#parts + 1] = part
      layers[#layers + 1] = { piece = a.piece, rom = romFor(a.piece.source), row = a.row, col = a.col, mid = m,
        pixels = pixels }
    end
    return table.concat(parts, ","), mid, layers
  end

  -- Composes every picture the base needs now, every animation frame of the
  -- pieces that are on, into this mod's pair.  Switching a piece on or off
  -- recomposes (redirect finds its key missing).
  local function rebuildAtlas()
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    local floorTs = NativeTileset and NativeTileset._pairs[state.pair]
    if not (floorTs and floorTs.imageData) then return false end
    local list, index = {}, {}
    local frameCount = 1
    for _, piece in ipairs(PIECES) do
      local a = lit[piece.id] and animFor(piece)
      if a then frameCount = math.max(frameCount, a.count) end
    end
    for _, cell in pairs(state.art) do
      for f = 0, frameCount - 1 do
        local id, mid, layers = cellPicture(cell.x, cell.y, function(piece)
          local a = animFor(piece)
          return a and f % a.count or 0
        end)
        if not index[id] then
          list[#list + 1] = { floorMid = mid, layers = layers }
          index[id] = #list
        end
      end
    end
    local built, ts, mids = pcall(V.Atlas.build, VIRTUAL_PAIR, floorTs, NativeTileset, list)
    if not built then
      log("could not compose the furniture: %s", tostring(ts))
      state.active = false
      return false
    end
    for id, i in pairs(index) do index[id] = mids[i] end
    state.ts, state.slotByKey = ts, index
    NativeTileset._pairs[VIRTUAL_PAIR] = ts
    return true
  end

  local function atlasLive()
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    return state.ts and state.ts.image and NativeTileset and NativeTileset._pairs[VIRTUAL_PAIR] == state.ts
  end

  -- The cell's mid in this mod's pair, or nil to let the engine draw it.
  local function redirect(wx, wy)
    if not (drawing and state.active and state.art[wy * ROW + wx]) then return nil end
    local Map = engineModule(ENGINE.map)
    if not (Map and Map.current == state.mapId) then return nil end
    local id = cellPicture(wx, wy, animFrame)
    local slot = atlasLive() and state.slotByKey[id]
    if slot then return slot end
    if not rebuildAtlas() then return nil end
    return state.slotByKey[id]
  end

  -- Switching a piece on or off redraws its art cells.
  local function setLit(piece, on)
    if (lit[piece.id] == true) == (on == true) then return end
    lit[piece.id] = on == true
    for _, cell in pairs(state.art or {}) do
      for _, a in ipairs(cell.layers) do
        if a.piece == piece then invalidate(cell.x, cell.y) break end
      end
    end
  end

  -- Each field draw advances the animation clock; when an animated piece
  -- that is on reaches a new frame, its animated cell is redrawn.
  local function tick()
    ticks = ticks + 1
    if not state.active then return end
    for _, c in pairs(state.footprint) do
      local anim = c.piece.art.onAnim
      -- once per piece: from its footprint's top-left cell to the art cell
      if anim and c.row == 0 and c.col == 0 and lit[c.piece.id] then
        local a = animFor(c.piece)
        if a and ticks % a.period == 0 then invalidate(c.x + c.piece.art.x + anim.col, c.y + anim.row) end
      end
    end
  end

  -- The placement preview: each piece's art alone, without floor, composed
  -- once.  slots[row][col] follow the art grid.
  local previews = {}
  local function previewFor(piece)
    if previews[piece] then return previews[piece] end
    local NativeTileset = engineModule(ENGINE.nativeTileset)
    local list, at = {}, {}
    eachArtCell(piece, 0, 0, function(_, _, row, col)
      list[#list + 1] = { layers = { { piece = piece, rom = romFor(piece.source), row = row, col = col,
        mid = artMid(piece, row, col, false) } } }
      at[#list] = { row = row, col = col }
    end)
    local ts, mids = V.Atlas.build(VIRTUAL_PAIR .. "_preview", false, NativeTileset, list)
    local slots = {}
    for i, p in ipairs(at) do
      slots[p.row + 1] = slots[p.row + 1] or {}
      slots[p.row + 1][p.col + 1] = mids[i]
    end
    previews[piece] = { ts = ts, slots = slots }
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
    local function engineDraw(D, helpers)
      if previous then return previous(D, helpers) end
      local opts = D._opts
      local mine = opts.draw
      opts.draw = nil
      local drawn, err = pcall(D.draw)
      opts.draw = mine
      if not drawn then error(err, 0) end
    end
    return function(D, helpers)
      local Decor = engineModule(ENGINE.decoration)
      if D.mode and D.mode.kind == "place" and byDecorId[D.mode.decor] then
        local piece = byDecorId[D.mode.decor]
        V.Menu.drawPlacing(D, screenModules(), piece, previewFor(piece))
        -- The message and the yes/no still come from the engine.
        local mode = D.mode
        D.mode = nil
        local drawn, err = pcall(engineDraw, D, helpers)
        D.mode = mode
        if not drawn then error(err, 0) end
        return
      end
      if not D.mode and D.view == "categories" and Decor.CATEGORY_COUNT > CATEGORY.index then
        return V.Menu.drawCategories(D, screenModules(), D._opts.text)
      end
      return engineDraw(D, helpers)
    end
  end

  -- ------- engine wraps
  --
  -- Each original is kept on the engine module under ORIGINALS, so loading
  -- this mod twice (a hot reload) wraps the engine's function, not our own.

  local ORIGINALS = "__" .. MOD_ID .. "_originals"

  local function wrap(module, name, make)
    if not (module and type(module[name]) == "function") then return false end
    local saved = rawget(module, ORIGINALS)
    if not saved then
      saved = {}
      module[ORIGINALS] = saved
    end
    saved[name] = saved[name] or module[name]
    module[name] = make(saved[name])
    return true
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
    local PcRse = engineModule(ENGINE.pcNatives)
    local Player = engineModule(ENGINE.player)
    if not (Decor and DecorInv) then return false end

    local ok = true

    -- --- data

    DecorInv.SIZES[CATEGORY.index] = CATEGORY.size
    ok = wrap(DecorInv, "data", function(original)
      return function(...) return addDecorations(original(...)) end
    end) and ok

    -- DecorInv.inventories fills in the eight vanilla lists; EXTRA's is added
    -- alongside, so every inventory function that takes a category works on it.
    ok = wrap(DecorInv, "inventories", function(original)
      return function(...)
        local inv = original(...)
        if type(inv) == "table" then
          local list = type(inv[CATEGORY.index]) == "table" and inv[CATEGORY.index] or {}
          for i = 1, CATEGORY.size do list[i] = tonumber(list[i]) or DecorInv.DECOR_NONE end
          inv[CATEGORY.index] = list
        end
        return inv
      end
    end) and ok

    -- DecorInv.CATEGORY_COUNT stays 8: the trader's menus and the save layout
    -- read it.  The DECORATE screen reads Decor.CATEGORY_COUNT, raised to 9
    -- while it is open from a PC and kept at 8 in the trader's mode, so mod
    -- furniture is never traded away.  Its "no decorations" check counts with
    -- DecorInv.count, which then has to include EXTRA.
    ok = wrap(DecorInv, "count", function(original)
      return function(sess, ...)
        local n = original(sess, ...)
        if Decor.CATEGORY_COUNT > CATEGORY.index then n = n + DecorInv.countInCategory(CATEGORY.index, sess) end
        return n
      end
    end) and ok

    -- --- the DECORATE screen

    ok = wrap(DecorUI, "open", function(original)
      return function(opts, ...)
        opts = opts or {}
        Decor.CATEGORY_COUNT = CATEGORY.index + 1
        ensureOwned(opts.session or currentSession())
        opts.text = screenText(opts.text)
        opts.draw = screenDraw(opts.draw)
        return original(opts, ...)
      end
    end) and ok

    ok = wrap(DecorUI, "openTrade", function(original)
      return function(...)
        Decor.CATEGORY_COUNT = CATEGORY.index
        return original(...)
      end
    end) and ok

    -- --- placing and packing up

    ok = wrap(Decor, "canPlace", function(original)
      return function(grid, place, decor, ...)
        local piece = byDecorId[tonumber(decor)]
        if piece then return canPlacePiece(grid, place, piece) end
        -- A vanilla decoration may not land on this mod's furniture either.
        local w, h = Decor.dims(decor)
        if state.active and footprintOverlap(place.x, place.y - h + 1, w, h) then return false end
        return original(grid, place, decor, ...)
      end
    end) and ok

    ok = wrap(Decor, "showOnMap", function(original)
      return function(grid, mapX, mapY, decor, ...)
        local piece = byDecorId[tonumber(decor)]
        if not piece then return original(grid, mapX, mapY, decor, ...) end
        if not (state.active and state.layout) then return false end
        addPiece(state.layout, piece, mapX, mapY - piece.height + 1)
        return true
      end
    end) and ok

    -- PACK UP: the engine restores the metatiles and frees the record; this
    -- drops the pieces from the drawing first, while the record still says
    -- where they were.
    ok = wrap(Decor, "clearNonSprites", function(original)
      return function(grid, ctx, marked, ...)
        for _, m in ipairs(marked or {}) do
          local piece = byDecorId[tonumber(ctx.items[m.idx])]
          if piece and state.active then
            local x, y = Decor.decodePos(ctx.pos[m.idx])
            removePiece(piece, x, y - piece.height + 1)
          end
        end
        return original(grid, ctx, marked, ...)
      end
    end) and ok

    -- --- graphics

    -- Map.worldMidAt also answers Collision.worldBehavior, so the redirect is
    -- only on while the field itself is being drawn.
    local function drawn(succeeded, ...)
      drawing = false
      if not succeeded then error((...), 0) end
      return ...
    end
    ok = wrap(FieldView, "draw", function(original)
      return function(...)
        drawing = true
        tick()
        return drawn(pcall(original, ...))
      end
    end) and ok

    ok = wrap(Map, "worldMidAt", function(original)
      return function(cx, cy, primaryDef)
        if primaryDef == state.def then
          local mid = redirect(cx, cy)
          if mid then return mid, VIRTUAL_PAIR end
        end
        return original(cx, cy, primaryDef)
      end
    end) and ok

    -- The worker-prepared route of the same lookup (field_view.lua addCell).
    ok = wrap(Plan, "cell", function(original)
      return function(plan, x, y)
        local mid = redirect(x, y)
        if mid then return mid, VIRTUAL_PAIR, false, false end
        return original(plan, x, y)
      end
    end) and ok

    -- Our pair has no file behind it; once trimmed it could not come back.
    ok = wrap(NativeTileset, "trim", function(original)
      return function(keep, ...)
        keep = keep or {}
        keep[VIRTUAL_PAIR] = true
        return original(keep, ...)
      end
    end) and ok

    -- --- loading the base

    ok = wrap(SB, "onMapLoad", function(original)
      return function(...)
        local result = original(...)
        local loaded, err = pcall(onBaseLoaded)
        if not loaded then
          state = { active = false }
          log("furniture disabled for this visit: %s", tostring(err))
        end
        return result
      end
    end) and ok

    -- --- using the furniture

    -- pokeemerald/src/field_control_avatar.c GetInteractedBackgroundEventScript
    -- is where the field asks.  A piece runs its script from any side, or, if
    -- fromBelow, only faced from below at its screen row, as the game's PCs
    -- and TVs are (their behaviours' "facing up" rule).
    ok = wrap(SB, "interactBg", function(original)
      return function(x, y, facing, elevation)
        local c = state.active and state.footprint[y * ROW + x]
        if c and inOwnBase(currentSession()) then
          local piece = c.piece
          if not piece.fromBelow or (c.row == piece.screenRow and (facing == "up" or facing == 2)) then
            return SB.startScript(piece.script)
          end
          return false
        end
        return original(x, y, facing, elevation)
      end
    end) and ok

    -- DoPCTurnOnEffect / DoPCTurnOffEffect write the Pokemon Center screen
    -- into the tile above the player.  On our PC, light its own screen.
    ok = wrap(PcRse, "setPcMetatile", function(original)
      return function(ctx, on)
        local c = state.active and Player and Player.facing == "up"
          and state.footprint[((tonumber(Player.cellY) or 0) - 1) * ROW + (tonumber(Player.cellX) or 0)]
        if c and c.piece == V.Furniture.PC then
          setLit(c.piece, on)
          return nil
        end
        return original(ctx, on)
      end
    end) and ok

    -- Every TV screen on the map switches through Tv.setScreens (on entering
    -- an indoor map with a show on air, off once it has been watched), which
    -- finds them by their TELEVISION behaviour.  This mod's TV has none, so
    -- it follows the same call.
    ok = wrap(engineModule(ENGINE.tv), "setScreens", function(original)
      return function(layout, behaviorAt, setMetatile, isTv, metatile, ...)
        local count = original(layout, behaviorAt, setMetatile, isTv, metatile, ...)
        if state.active and layout == state.layout then
          local TV = V.Furniture.TV
          setLit(TV, metatile == artMid(TV, TV.screenRow, 0, true))
        end
        return count
      end
    end) and ok

    return ok
  end

  if not install() then
    log("this engine version is missing a function the mod wraps; some parts may not work")
  end

  mod.events:on("save.writing", function(payload)
    local cleaned, err = pcall(function() V.SaveCompat.writeClean(payload.save, saveContext()) end)
    if not cleaned then log("save written with the mod's furniture in it: %s", tostring(err)) end
  end)
  mod.events:on("save.loaded", function(payload)
    local restored, err = pcall(restorePlaced, payload and payload.save)
    if not restored then log("could not put the furniture back: %s", tostring(err)) end
  end)
end
