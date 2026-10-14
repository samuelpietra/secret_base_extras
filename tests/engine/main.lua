local E = os.getenv("SBE_ENGINE") .. "/"
local MOD = os.getenv("SBE_MOD") .. "/"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
function love.load()
  package.path = E .. "?.lua;" .. E .. "?/init.lua;" .. package.path
  local ok, err = pcall(function()
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local Decor = require("src.core.game3.rse.decoration")
    DecorInv.install(assert(loadstring(slurp(os.getenv("SBE_INSTALL") .. "/emerald/data/generated/gba/decorations/decorations.lua")))())
    local entry = assert(loadstring(slurp(MOD .. "main.lua")))()
    entry({ path = "mods/secret_base_extras", read = function(_, rel) return slurp(MOD .. rel) end, events = { on = function() end } })
    local bed, pc = DecorInv.info(121), DecorInv.info(122)
    print("info", bed and bed.name, bed and bed.shape, pc and pc.name, pc and pc.shape, DecorInv.info(123) and DecorInv.info(123).name, DecorInv.info(123) and DecorInv.info(123).shape); print("tv setScreens wrapped", require("src.core.game3.rse.tv").__secret_base_extras_originals ~= nil)
    print("dims", Decor.dims(121)); print("dims", Decor.dims(122))
    print("categoryName", DecorInv.categoryName(8), "isSprite", Decor.isSprite(121))
    local sess = { decorationInventory = {} }
    local inv = DecorInv.inventories(sess)
    print("extra list", #inv[8], "vanilla desk", #inv[0])
    print("add", DecorInv.add(121, sess), DecorInv.add(122, sess), "has", DecorInv.has(121, sess), DecorInv.has(122, sess))
    print("countInCategory", DecorInv.countInCategory(8, sess), "count (menu closed)", DecorInv.count(sess))
    Decor.CATEGORY_COUNT = 9
    print("count (menu open)", DecorInv.count(sess))
    -- a decoration reset reloads the table: the mod's entries must come back
    DecorInv.install(assert(loadstring(slurp(os.getenv("SBE_INSTALL") .. "/emerald/data/generated/gba/decorations/decorations.lua")))())
    print("after reload", DecorInv.info(121) and DecorInv.info(121).name)
    -- vanilla canPlace still runs for vanilla decorations
    local grid = { behavior = function() return 0 end, objectAt = function() return nil end, metatileId = function() return nil end, metatile = function() return 0 end }
    print("vanilla canPlace", pcall(Decor.canPlace, grid, { x = 3, y = 3 }, 1))
    print("mod canPlace outside a base", Decor.canPlace(grid, { x = 3, y = 3 }, 121))
  end)
  print(ok and "done" or ("FAIL " .. tostring(err)))
  love.event.quit()
end
