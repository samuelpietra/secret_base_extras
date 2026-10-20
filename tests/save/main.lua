-- A round trip of your save through the save hooks: written before any load,
-- loaded after vanilla furniture took the place of one of the mod's pieces
-- while the mod was off, and written again.  Nothing is written to disk.
local E = os.getenv("SBE_ENGINE") .. "/"
local MOD = os.getenv("SBE_MOD") .. "/"
local SAVE = os.getenv("SBE_INSTALL") .. "/saves/emerald/slot1.lua"
local DECORATIONS = os.getenv("SBE_INSTALL") .. "/emerald/data/generated/gba/decorations/decorations.lua"
local function slurp(p) local f = io.open(p, "rb"); local s = f:read("*a"); f:close(); return s end

local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then failures = failures + 1 end
end

-- Emerald's own decorations end at 120 (DECOR_REGISTEEL_DOLL); the mod's start after.
local FIRST_MOD_DECOR = 121
local MAX_DECORATIONS = 16
local EXTRA = 8
local SMALL_DESK, SMALL_CHAIR = 1, 10

local function slots(base)
  local o = {}
  for i = 1, MAX_DECORATIONS do o[i] = (base.decorations[i] or 0) .. "@" .. (base.decorationPositions[i] or 0) end
  return table.concat(o, " ")
end
local function bucketOf(save)
  local b = save.modData and save.modData.secret_base_extras
  return b and b.placed or {}
end
local function entries(list)
  local o = {}
  for _, e in ipairs(list) do o[#o + 1] = e.decor .. "@" .. e.pos end
  table.sort(o)
  return table.concat(o, " ")
end
local function modPiecesIn(base)
  local o = {}
  for i = 1, MAX_DECORATIONS do
    if (base.decorations[i] or 0) >= FIRST_MOD_DECOR then o[#o + 1] = { decor = base.decorations[i], pos = base.decorationPositions[i] } end
  end
  return o
end

function love.load()
  package.path = E .. "?.lua;" .. E .. "?/init.lua;" .. package.path
  local ok, err = pcall(function()
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    DecorInv.install(assert(loadstring(slurp(DECORATIONS)))())
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

    -- 0. your save as it is now
    local s = assert(loadstring(slurp(SAVE)))()
    local carried = bucketOf(s)
    check(#carried > 0, "your save carries furniture of the mod (" .. entries(carried) .. "); place some in your base if not")
    check(#modPiecesIn(s.secretBases[1]) == 0, "your save's base holds none of the mod's ids")

    -- 1. a save written before any load ran: the furniture must survive
    local early = write(s)
    check(#modPiecesIn(early.secretBases[1]) == 0 and entries(bucketOf(early)) == entries(carried),
      "written before a load: the base stays clean and the furniture is kept")

    -- 2. mod off: the game loads the save as it is, and a SMALL DESK goes on
    -- the first piece's cell and a SMALL CHAIR elsewhere
    local base = s.secretBases[1]
    local free = {}
    for i = MAX_DECORATIONS, 1, -1 do if (base.decorations[i] or 0) == 0 then free[#free + 1] = i end end
    local under = carried[1]
    base.decorations[free[1]], base.decorationPositions[free[1]] = SMALL_DESK, under.pos
    base.decorations[free[2]], base.decorationPositions[free[2]] = SMALL_CHAIR, 3 * 16 + 4
    s.decorationInventory[0] = { SMALL_DESK, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    s.decorationInventory[1] = { SMALL_CHAIR, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local vanilla = slots(base)

    -- 3. mod on again: load
    handlers["save.loaded"]({ save = s })
    local restored = modPiecesIn(base)
    local back = {}
    for _, e in ipairs(restored) do back[e.decor .. "@" .. e.pos] = true end
    local wrongPlace = 0
    for _, e in ipairs(restored) do
      local recorded = false
      for _, c in ipairs(carried) do if c.decor == e.decor and c.pos == e.pos then recorded = true end end
      if not recorded then wrongPlace = wrongPlace + 1 end
    end
    check(#restored > 0 and wrongPlace == 0, "loaded: " .. #restored .. " pieces back, each where it was")
    check(not back[under.decor .. "@" .. under.pos], "the piece under the desk stays in the PC")
    local stillVanilla = true
    for i = 1, MAX_DECORATIONS do
      if (base.decorations[i] or 0) < FIRST_MOD_DECOR and (base.decorations[i] or 0) ~= 0 then
        stillVanilla = stillVanilla and vanilla:find(base.decorations[i] .. "@" .. base.decorationPositions[i], 1, true) ~= nil
      end
    end
    check(stillVanilla, "the vanilla furniture keeps its slots and places")
    check(#bucketOf(s) == 0, "the furniture is put back once")
    for _, e in ipairs(carried) do if not DecorInv.has(e.decor, s) then DecorInv.add(e.decor, s) end end
    local inBase, marked = Decor.inUse(s, EXTRA), true
    for i, d in ipairs(DecorInv.inventories(s)[EXTRA]) do
      if d ~= 0 then
        local placed = false
        for _, e in ipairs(restored) do if e.decor == d then placed = true end end
        marked = marked and (inBase[i] and true or false) == placed
      end
    end
    check(marked, "DECORATE's EXTRA list marks in the base exactly the pieces put back")

    -- 4. the next save is clean again
    local next = write(s)
    check(slots(next.secretBases[1]) == vanilla, "the next save's base holds only the vanilla furniture, as with the mod off")
    check(entries(bucketOf(next)) == entries(restored), "and carries the pieces in the base, and no others")
  end)
  if not ok then print("FAIL " .. tostring(err)); failures = failures + 1 end
  print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
  love.event.quit()
end
