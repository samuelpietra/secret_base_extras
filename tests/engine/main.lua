-- The data hooks on the real engine modules, with the imported ROM's
-- decoration table: the three decorations, the EXTRA list and count, the table
-- surviving a reload, and placement still going to the vanilla rule.
local E = os.getenv("SBE_ENGINE") .. "/"
local MOD = os.getenv("SBE_MOD") .. "/"
local DECORATIONS = os.getenv("SBE_INSTALL") .. "/emerald/data/generated/gba/decorations/decorations.lua"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then failures = failures + 1 end
end

local EXTRA = 8

function love.load()
  package.path = E .. "?.lua;" .. E .. "?/init.lua;" .. package.path
  local ok, err = pcall(function()
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    DecorInv.install(assert(loadstring(slurp(DECORATIONS)))())
    local entry = assert(loadstring(slurp(MOD .. "main.lua")))()
    entry({ path = "mods/secret_base_extras", read = function(_, rel) return slurp(MOD .. rel) end, events = { on = function() end } })

    for _, decoration in ipairs({ { 121, "HEALING BED", 5 }, { 122, "{PKMN} CENTER PC", 6 }, { 123, "STANDARD TV", 6 } }) do
      local info = DecorInv.info(decoration[1])
      check(info and info.name == decoration[2] and info.shape == decoration[3],
        ("decoration %d: %s, shape %d"):format(decoration[1], info and info.name or "missing", info and info.shape or -1))
    end
    check(require("src.core.game3.rse.tv").__secret_base_extras_originals ~= nil, "Tv.setScreens wrapped")
    for _, size in ipairs({ { 121, "bed", 1, 2 }, { 122, "PC", 1, 3 } }) do
      local width, height = Decor.dims(size[1])
      check(width == size[3] and height == size[4], ("the %s is %dx%d"):format(size[2], size[3], size[4]))
    end
    check(DecorInv.categoryName(EXTRA) == "EXTRA", "category 8 is EXTRA")
    check(Decor.isSprite(121) == false, "the bed is drawn from tiles, not as a sprite")

    local sess = { decorationInventory = {} }
    local inv = DecorInv.inventories(sess)
    check(#inv[EXTRA] == 10 and #inv[0] == 10, "the EXTRA list holds ten slots, as the vanilla DESK list does")
    check(DecorInv.add(121, sess) and DecorInv.add(122, sess), "the bed and the PC go into the EXTRA list")
    check(DecorInv.has(121, sess) and DecorInv.has(122, sess), "and are there")
    check(DecorInv.countInCategory(EXTRA, sess) == 2, "EXTRA counts its two pieces")
    check(DecorInv.count(sess) == 0, "the total leaves EXTRA out while the menu is closed")
    Decor.CATEGORY_COUNT = 9
    check(DecorInv.count(sess) == 2, "and takes it in while the DECORATE menu shows it")

    -- a decoration reset reloads the table: the mod's entries must come back
    DecorInv.install(assert(loadstring(slurp(DECORATIONS)))())
    check(DecorInv.info(121) and DecorInv.info(121).name == "HEALING BED", "the bed survives a reload of the table")

    -- no base is loaded here, so the vanilla rule stops at the base's
    -- manifest: reaching it is what shows the rule ran
    local grid = { behavior = function() return 0 end, objectAt = function() return nil end, metatileId = function() return nil end, metatile = function() return 0 end }
    local ran, vanillaErr = pcall(Decor.canPlace, grid, { x = 3, y = 3 }, 1)
    check(not ran and tostring(vanillaErr):find("secret_base/manifest.lua", 1, true) ~= nil,
      "a vanilla decoration still goes to the vanilla placement rule")
    check(Decor.canPlace(grid, { x = 3, y = 3 }, 121) == false, "the mod's piece cannot be placed outside a base")
  end)
  if not ok then print("FAIL " .. tostring(err)); failures = failures + 1 end
  print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
  love.event.quit()
end
