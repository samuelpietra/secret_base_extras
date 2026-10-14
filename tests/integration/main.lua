-- Runs the mod's real entry on stand-ins for the engine modules it wraps, then
-- walks the in-game paths: base load, field draw, TV on/blink/off, PC screen,
-- A on the bed, PACK UP, placement rules.
local E = os.getenv("SBE_ENGINE") .. "/"
local MOD = os.getenv("SBE_MOD") .. "/"
local EM = os.getenv("SBE_INSTALL") .. "/emerald/"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
local failures = 0
local function check(label, cond, extra) print((cond and "PASS " or "FAIL ") .. label .. (extra and ("  " .. tostring(extra)) or "")) if not cond then failures = failures + 1 end end
function love.load()
  love.graphics = love.graphics or {}
  love.graphics.newImage = function(data) return { data = data, setFilter = function() end, getDimensions = function() return data:getDimensions() end } end
  package.path = E .. "?.lua;" .. package.path
  local ok, err = pcall(function()
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    DecorInv.install(assert(loadstring(slurp(EM .. "data/generated/gba/decorations/decorations.lua")))())
    -- layout: 14x14 tree base, row 1 north wall, rows 2+ floor
    local W, H = 14, 14
    local cells = {}
    for y = 0, H - 1 do for x = 0, W - 1 do
      local mid = (y == 1) and 0x202 or ((y >= 2 and x >= 1 and x <= 12) and 0x20A or 0x210)
      cells[y * W + x + 1] = { mid = mid, coll = mid == 0x20A and 0 or 7, elev = 3 }
    end end
    local layout = { width = W, height = H, cells = cells, overrides = {} }
    function layout:midAt(x, y) local o = self.overrides[y * 1024 + x]; if o then return o.mid end local c = self.cells[y * W + x + 1]; return c and c.mid or 0 end
    function layout:cellAt(x, y) return self.overrides[y * 1024 + x] or self.cells[y * W + x + 1] end
    local def = { id = "EM_SECRET_BASE_TREE4", pair = "secret_base__secret_base_tree", midLayout = layout }
    local session = { map = def.id, decorationInventory = {}, modData = {},
      secretBases = { { decorations = { 121, 122, 123, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        decorationPositions = { 3 * 16 + 3, 4 * 16 + 6, 7 * 16 + 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } } } }
    -- floor atlas of the base pair: every mid in slot 0, grey
    local floorImage = love.image.newImageData(16, 16)
    for y = 0, 15 do for x = 0, 15 do floorImage:setPixel(x, y, 0.5, 0.4, 0.3, 1) end end
    local invalidated, scripts, metatiles = {}, {}, {}
    local function fake(path, t) package.loaded[path] = t; return t end
    fake("src.core.game3.runtime", { getSession = function() return session end })
    fake("src.core.game3.rse.init", { var = function() return 0 end })
    fake("src.core.game3.collision", { _mapDef = def })
    fake("src.core.game3.field", { setMetatile = function(x, y, mid, imp) layout.overrides[y * 1024 + x] = { mid = mid, coll = imp and 7 or 0 }; metatiles[#metatiles + 1] = x .. "," .. y end })
    local SB = fake("src.core.game3.rse.secret_base", {
      base = function(s, i) return s.secretBases[i + 1] end, curMapIsSecretBase = function() return true end,
      onMapLoad = function() return true end, interactBg = function() return "vanilla" end,
      startScript = function(label) scripts[#scripts + 1] = label return true end,
      fieldGrid = function() return {} end })
    local plannedCell = {}
    local FieldView = fake("src.core.game3.field_view", {
      invalidateCell = function(x, y) invalidated[#invalidated + 1] = x .. "," .. y end,
      draw = function() local Plan = package.loaded["src.core.game3.field_plan"]
        for key, _ in pairs(plannedCell) do
          local mid, pair = Plan.cell({}, key[1], key[2])
          -- a slot only names a picture within the atlas it belongs to, so
          -- the picture is identified by its pixels
          local atlas = package.loaded["src.core.game3.tileset_native"]._pairs[pair]
          local signature = tostring(mid)
          if pair == "mod__secret_base_extras" and atlas then
            local parts = {}
            local sx, sy = (mid % atlas.cols) * 16, math.floor(mid / atlas.cols) * 16
            for _, data in ipairs({ atlas.imageData, atlas.overImageData }) do
              for y = 0, 15 do for x = 0, 15 do
                local r, g, b, a = data:getPixel(sx + x, sy + y)
                parts[#parts + 1] = string.format("%.2f%.2f%.2f%.0f", r, g, b, a)
              end end
            end
            signature = table.concat(parts)
          end
          plannedCell[key] = { signature, pair }
        end end })
    local Plan = fake("src.core.game3.field_plan", { cell = function() return 0x20A, def.pair, false, false end })
    local Map = fake("src.core.game3.map", { current = def.id, worldMidAt = function() return 0x20A, def.pair end })
    local NT = fake("src.core.game3.tileset_native", { _pairs = { [def.pair] = { imageData = floorImage, cols = 1, midToSlot = { [0x20A] = 0 } } },
      slotFor = function(ts, mid) return ts.midToSlot[mid] or 0 end, trim = function(keep) return keep end })
    local Player = fake("src.core.game3.player", { facing = "up", cellX = 4, cellY = 5 })
    local PcN = fake("src.core.game3.scripting.natives_pc_rse", { setPcMetatile = function() return "vanilla" end })
    local Tv = fake("src.core.game3.rse.tv", { setScreens = function() return 0 end })
    fake("src.ui.game3.rse.decoration", { open = function(o) return o end, openTrade = function() end, draw = function() end })
    fake("src.core.game3.dataset", { cache = function() return { read = function(_, rel) return slurp(EM .. rel) end } end })

    local handlers = {}
    local entry = assert(loadstring(slurp(MOD .. "main.lua")))()
    entry({ path = "mods/secret_base_extras", read = function(_, rel) return slurp(MOD .. rel) end,
      events = { on = function(_, name, fn) handlers[name] = fn end } })

    -- base load
    SB.onMapLoad()
    check("bed foot blocks", layout.overrides[3 * 1024 + 3] ~= nil and layout.overrides[3 * 1024 + 3].coll == 7)
    check("bed pillow walkable", layout.overrides[2 * 1024 + 3] == nil)
    check("inventory has the three pieces", DecorInv.has(121, session) and DecorInv.has(122, session) and DecorInv.has(123, session))
    -- field draw: the furniture cells come from the mod's pair
    local function draw(cellsToSample)
      for _, c in ipairs(cellsToSample) do plannedCell[c] = true end
      FieldView.draw()
    end
    -- Decor.encodePos is x * 16 + y, of the footprint's bottom-left cell
    local bedFoot, bedSide, pcScreen, tvScreen = { 3, 3 }, { 2, 3 }, { 4, 5 }, { 7, 8 }
    draw({ bedFoot, bedSide, pcScreen, tvScreen })
    check("bed foot redirected", plannedCell[bedFoot][2] == "mod__secret_base_extras", plannedCell[bedFoot][2])
    check("bed overhang redirected", plannedCell[bedSide][2] == "mod__secret_base_extras")
    check("atlas registered", NT._pairs["mod__secret_base_extras"] ~= nil)
    local pcOff = plannedCell[pcScreen][1]
    -- PC screen lights while in use
    Player.cellX, Player.cellY = 4, 6
    PcN.setPcMetatile({}, true)
    draw({ pcScreen })
    check("PC screen changes when on", plannedCell[pcScreen][1] ~= pcOff)
    PcN.setPcMetatile({}, false)
    draw({ pcScreen })
    check("PC screen back off", plannedCell[pcScreen][1] == pcOff)
    -- TV switches on with the game's screens and blinks
    draw({ tvScreen })
    local tvOff = plannedCell[tvScreen][1]
    Tv.setScreens(layout, nil, nil, nil, 3)
    local seen = {}
    for i = 1, 24 do draw({ tvScreen }); seen[plannedCell[tvScreen][1]] = true end
    local n = 0 for _ in pairs(seen) do n = n + 1 end
    check("TV on shows two alternating frames", n == 2 and not seen[tvOff], n)
    Tv.setScreens(layout, nil, nil, nil, 2)
    draw({ tvScreen })
    check("TV off again", plannedCell[tvScreen][1] == tvOff)
    -- A button
    SB.interactBg(3, 2, "left")
    check("A on bed runs the bed script", scripts[#scripts] == "Route119_WeatherInstitute_1F_EventScript_Bed", scripts[#scripts])
    SB.interactBg(4, 5, "up")
    check("A on PC screen from below runs the PC", scripts[#scripts] == "EventScript_PC")
    check("A on PC from the side does nothing", SB.interactBg(4, 5, "left") == false)
    check("A elsewhere falls through to the engine", SB.interactBg(9, 9, "up") == "vanilla")
    -- placement rules
    local MB = require("src.core.game3.mb")
    -- the engine hands out its own behaviour ids, not the ROM's
    local grid = { behavior = function(x, y) local m = layout:midAt(x, y)
        return m == 0x20A and MB.id("NORMAL") or (m == 0x202 and MB.id("SECRET_BASE_NORTH_WALL") or -1) end,
      objectAt = function() return nil end }
    check("TV may not overlap the PC", Decor.canPlace(grid, { x = 4, y = 6, initialX = 11, initialY = 11 }, 123) == false)
    check("TV fits on free floor", Decor.canPlace(grid, { x = 10, y = 6, initialX = 0, initialY = 0 }, 123) == true)
    check("TV set may stand on the north wall", Decor.canPlace(grid, { x = 10, y = 2, initialX = 0, initialY = 0 }, 123) == true)
    -- PUT AWAY aims: the bed's frame column selects the bed, plain floor nothing
    local ctxMarks = { items = session.secretBases[1].decorations, pos = session.secretBases[1].decorationPositions, size = 16 }
    local aim = { metatile = function() return 0 end, metatileId = function() return nil end }
    local function aimed(x, y) local m = Decor.markForRemoval(aim, ctxMarks, x, y); return m[1] and ctxMarks.items[m[1].idx] or nil end
    check("aiming at the bed's footprint finds it", aimed(3, 3) == 121)
    check("aiming at the bed's frame column finds it", aimed(2, 2) == 121 and aimed(4, 3) == 121, tostring(aimed(2, 2)) .. "," .. tostring(aimed(4, 3)))
    check("aiming at plain floor finds nothing", aimed(10, 10) == nil)
    -- PACK UP the bed
    Decor.clearNonSprites = Decor.clearNonSprites
    local ctx = { items = session.secretBases[1].decorations, pos = session.secretBases[1].decorationPositions }
    Decor.clearNonSprites({ restoreMetatile = function() end }, ctx, { { idx = 1, width = 1, height = 2 } })
    plannedCell[bedFoot], plannedCell[bedSide] = true, true
    FieldView.draw()
    check("packed-up bed no longer drawn by the mod", plannedCell[bedFoot][2] ~= "mod__secret_base_extras" and plannedCell[bedSide][2] ~= "mod__secret_base_extras")
  end)
  if not ok then print("ERROR " .. tostring(err)) failures = failures + 1 end
  print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
  love.event.quit()
end
