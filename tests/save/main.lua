local E = os.getenv("SBE_ENGINE") .. "/"
local MOD = os.getenv("SBE_MOD") .. "/"
local SAVE = os.getenv("SBE_INSTALL") .. "/saves/emerald/slot1.lua"
local function slurp(p) local f = io.open(p, "rb"); local s = f:read("*a"); f:close(); return s end
local function list(t, n) local o = {} for i = 1, n do o[i] = tostring(t[i]) end return table.concat(o, ",") end
local function bucket(t) local b = t.modData and t.modData.secret_base_extras; local p = {} for _, e in ipairs(b and b.placed or {}) do p[#p + 1] = e.decor .. "@" .. e.pos end return table.concat(p, " ") end
function love.load()
  package.path = E .. "?.lua;" .. E .. "?/init.lua;" .. package.path
  local ok, err = pcall(function()
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    DecorInv.install(assert(loadstring(slurp(os.getenv("SBE_INSTALL") .. "/emerald/data/generated/gba/decorations/decorations.lua")))())
    local handlers = {}
    local entry = assert(loadstring(slurp(MOD .. "main.lua")))()
    entry({ path = "mods/secret_base_extras", read = function(_, rel) return slurp(MOD .. rel) end,
      events = { on = function(_, name, fn) handlers[name] = fn end } })
    local function write(session)
      local save = { secretBases = session.secretBases, decorationInventory = session.decorationInventory,
        tvShows = session.tvShows, modData = session.modData }
      handlers["save.writing"]({ save = save })
      return save
    end
    local function show(label, t) print(label, list(t.secretBases[1].decorations, 6), list(t.secretBases[1].decorationPositions, 6), "| bucket:", bucket(t)) end

    -- 0. your save as it is now
    local s = assert(loadstring(slurp(SAVE)))()
    show("0 save on disk       ", s)
    -- 1. a save written before any load ran (the risk): the bucket must survive
    show("1 written, no load   ", write(s))
    -- 2. mod OFF: the game loads it as is and you put out vanilla furniture
    s.secretBases[1].decorations[3], s.secretBases[1].decorationPositions[3] = 1, 1 * 16 + 2  -- SMALL DESK on the bed's pillow (1,2)
    s.secretBases[1].decorations[4], s.secretBases[1].decorationPositions[4] = 10, 3 * 16 + 4 -- SMALL CHAIR on free floor (3,4)
    s.decorationInventory[0] = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    s.decorationInventory[1] = { 10, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    show("2 mod off, vanilla in", s)
    -- 3. mod ON again: load
    handlers["save.loaded"]({ save = s })
    for _, id in ipairs({ 121, 122, 123 }) do if not DecorInv.has(id, s) then DecorInv.add(id, s) end end
    show("3 loaded with the mod", s)
    local function state(cat)
      local inv = DecorInv.inventories(s)[cat]
      local inBase = Decor.inUse(s, cat)
      local out = {}
      for i, d in ipairs(inv) do if d ~= 0 then out[#out + 1] = d .. (inBase[i] and "=in base" or "=in PC") end end
      return table.concat(out, " ")
    end
    print("  DECORATE: DESK", state(0), "| CHAIR", state(1), "| EXTRA", state(8))
    -- 4. and the next save is clean again
    local w = write(s)
    show("4 next save          ", w)
  end)
  print(ok and "done" or ("FAIL " .. tostring(err)))
  love.event.quit()
end
