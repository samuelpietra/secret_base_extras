local MOD = os.getenv("SBE_MOD") .. "/"
local EM = os.getenv("SBE_INSTALL") .. "/emerald/"
local OUT = os.getenv("SBE_WORK") .. "/"
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
function love.load()
  local ok, err = pcall(function()
    -- run the real entry the way the game does, with a stand-in mod object
    local entry = assert(loadstring(slurp(MOD .. "main.lua"), "main.lua"))()
    local fakeMod = { path = "mods/secret_base_extras",
      read = function(_, rel) return slurp(MOD .. rel) end,
      events = { on = function() end } }
    entry(fakeMod)
    print("entry ran")
    local V = {}
    for _, n in ipairs({ "rom_tileset", "furniture", "atlas" }) do
      local chunk = assert(loadstring(slurp(MOD .. "lib/" .. n .. ".lua"), n))
      V[({ rom_tileset = "RomTileset", furniture = "Furniture", atlas = "Atlas" })[n]] = chunk()(V)
    end
    local cache = { read = function(_, rel) return slurp(EM .. rel) end }
    local function romOf(src) return assert(V.RomTileset.forMap(cache, src.mapDir, src.pretName)) end
    local floor = love.image.newImageData(16, 16)
    for y = 0, 15 do for x = 0, 15 do floor:setPixel(x, y, 0.55, 0.35, 0.3, 1) end end
    local floorTs = { imageData = floor, cols = 1 }
    local NT = { slotFor = function() return 0 end }
    love.graphics = { newImage = function() return { setFilter = function() end } end }
    local list, place = {}, {}
    -- footprint anchored at (ox, oy) top-left; art spills by art.x
    local function add(piece, grid, ox, oy)
      local rom = romOf(piece.source)
      for row, line in ipairs(grid) do for col, mid in ipairs(line) do
        list[#list + 1] = { floorMid = 0, layers = { { piece = piece, tileset = rom, row = row - 1, col = col - 1, mid = mid } } }
        place[#place + 1] = { ox + piece.art.x + col - 1, oy + (piece.art.y or 0) + row - 1 }
      end end
    end
    add(V.Furniture.BED, V.Furniture.BED.art.cells, 1, 1)
    add(V.Furniture.PC, V.Furniture.PC.art.cells, 3, 0)
    add(V.Furniture.PC, V.Furniture.PC.art.cellsOn, 5, 0)
    add(V.Furniture.TV, V.Furniture.TV.art.cells, 7, 0)
    add(V.Furniture.TV, V.Furniture.TV.art.cellsOn, 8, 0)
    add(V.Furniture.LEAGUE_STORE, V.Furniture.LEAGUE_STORE.art.cells, 11, 0)
    add(V.Furniture.VITAMIN_STORE, V.Furniture.VITAMIN_STORE.art.cells, 12, 0)
    -- the TV-on animation frames, as the mod reads them
    local blob = slurp(EM .. "data/generated/gba/native/building__generic_building/anim_building_tv_turned_on.idx")
    if blob:byte(1) == 0x78 then blob = love.data.decompress("string", "zlib", blob) end
    for f = 0, 1 do
      local px = {}
      for i = 1, 256 do local v = blob:byte(f * 256 + i); px[i] = v % 16 == 0 and 0 or v end
      list[#list + 1] = { floorMid = 0, layers = { { piece = V.Furniture.TV, tileset = romOf(V.Furniture.TV.source), row = 1, col = 0, mid = 3, pixels = px } } }
      place[#place + 1] = { 9 + f, 1 }
    end
    local ts, mids = V.Atlas.build("t", floorTs, NT, list)
    local out = love.image.newImageData(13 * 16, 4 * 16)
    for y = 0, 63 do for x = 0, 207 do out:setPixel(x, y, 0.55, 0.35, 0.3, 1) end end
    for i, p in ipairs(place) do
      local s = mids[i]
      for _, img in ipairs({ ts.imageData, ts.overImageData }) do
        for y = 0, 15 do for x = 0, 15 do
          local r, g, b, a = img:getPixel((s % 16) * 16 + x, math.floor(s / 16) * 16 + y)
          if a > 0 then out:setPixel(p[1] * 16 + x, p[2] * 16 + y, r, g, b, a) end
        end end
      end
    end
    local fd = out:encode("png")
    local f = io.open(OUT .. "render.png", "wb"); f:write(fd:getString()); f:close()
    print("OK slots", #list)
  end)
  if not ok then print("FAIL", err) end
  love.event.quit()
end
