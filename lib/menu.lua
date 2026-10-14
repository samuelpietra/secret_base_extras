-- The two pictures of the DECORATE screen (src/ui/game3/rse/decoration.lua)
-- this mod draws itself, through the screen's own opts.draw hook:
--   categories  the list grows past the eight vanilla entries, more than the
--               vanilla window holds, so it scrolls the way the Start menu
--               does (src/ui/game3/start_menu.lua): the same window and 16px
--               rows, the cursor kept in view, the list menu's arrows;
--   placing     the vanilla preview draws decoration metatiles from the base's
--               tileset, which this mod's furniture is not in.
-- Everything else stays the engine's.  The layout numbers follow the engine's
-- drawCategories and drawPlacing, which cite pokeemerald/src/decoration.c.

return function(Lib)
  local Menu = {}

  local ROW = 16
  -- The vanilla window shows eight categories and CANCEL.
  local VISIBLE = 9
  -- pokeemerald/src/decoration.c:58 (the screen's MENU_PLACE / MENU_TRADE)
  local MENU_PLACE, MENU_TRADE = 0, 2
  -- The vanilla category names, in the screen's own order.
  local CATEGORY_TEXT = { [0] = "gText_Desk", "gText_Chair", "gText_Plant", "gText_Ornament", "gText_Mat",
    "gText_Poster", "gText_Doll", "gText_Cushion" }

  local function rgba(bgr)
    bgr = tonumber(bgr) or 0
    return { (bgr % 32) / 31, (math.floor(bgr / 32) % 32) / 31, (math.floor(bgr / 1024) % 32) / 31, 1 }
  end

  -- pokeemerald/src/decoration.c:763
  local function menuColors(Decor, disabled)
    local palette = Decor.manifest().menuPalette or {}
    if disabled then return { fg = rgba(palette[5]), shadow = rgba(palette[6]) } end
    return { fg = rgba(palette[3]), shadow = rgba(palette[4]) }
  end

  -- pokeemerald/src/decoration.c:731: the bedroom takes only dolls and cushions.
  local function disabled(screen, Decor, cat)
    return screen.isPlayerRoom and screen.command == MENU_PLACE and cat ~= Decor.CAT.DOLL and cat ~= Decor.CAT.CUSHION
  end

  -- The cursor (screen.catCursor) is the screen's own and still runs over every
  -- category and CANCEL; only the window onto the list is this mod's.
  local function scrolled(screen, rows)
    local cursor = screen.catCursor or 0
    local scroll = screen.sbxCategoryScroll or 0
    if cursor < scroll then scroll = cursor end
    if cursor >= scroll + VISIBLE then scroll = cursor - VISIBLE + 1 end
    scroll = math.max(0, math.min(scroll, rows - VISIBLE))
    screen.sbxCategoryScroll = scroll
    return scroll
  end

  function Menu.drawCategories(screen, engine, text)
    local tpl = screen.WIN.categories
    engine.Window.stdFrame(tpl)
    engine.Window.fill(tpl, 1, 1, 1, 1)
    local ox, oy = tpl.left * 8, tpl.top * 8
    local session = screen._session
    local count = engine.Decor.CATEGORY_COUNT
    local rows = count + 1
    local scroll = scrolled(screen, rows)
    for r = 0, math.min(rows, VISIBLE) - 1 do
      local cat = scroll + r
      local y = oy + r * ROW + 1
      if cat == count then
        engine.Window.printPx(text(screen.command == MENU_TRADE and "gText_Exit" or "gText_Cancel"), ox + 8, y)
      else
        local colors = menuColors(engine.Decor, disabled(screen, engine.Decor, cat))
        local name = cat == Lib.Furniture.CATEGORY.index and Lib.Furniture.CATEGORY.name or text(CATEGORY_TEXT[cat])
        engine.FrlgFont.draw(name, ox + 8, y, { colors = colors })
        local filled = string.format("%2d/%2d", engine.DecorInv.countInCategory(cat, session), engine.DecorInv.SIZES[cat])
        engine.FrlgFont.draw(filled, ox + 104 - engine.FrlgFont.measure(filled), y, { colors = colors })
      end
    end
    engine.Window.cursorPx(ox, oy + 1 + ((screen.catCursor or 0) - scroll) * ROW)
    if rows > VISIBLE then
      engine.ListMenu.drawScrollArrows(tpl, scroll > 0, scroll + VISIBLE < rows, screen.frames)
    end
  end

  local function drawObject(engine, graphicsId, x, y)
    local sprite = engine.OwSprites.getDraw(graphicsId)
    local frameQuad = sprite and sprite.quads and sprite.quads[0]
    if not frameQuad then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite.image, frameQuad, x, y)
  end

  local function isFemale(session)
    local gender = session and session.gender
    return gender == 1 or gender == "female" or gender == "F" or gender == "girl"
  end

  local function avatarGfx(screen, engine)
    local session = screen._session
    if screen._opts and screen._opts.avatarGfx then return screen._opts.avatarGfx(session, isFemale(session)) end
    return engine.Constants.of("emerald"):require("event_objects",
      isFemale(session) and "OBJ_EVENT_GFX_MAY_DECORATING" or "OBJ_EVENT_GFX_BRENDAN_DECORATING")
  end

  local quads = setmetatable({}, { __mode = "k" })
  local function quad(image, slot)
    local byImage = quads[image]
    if not byImage then
      byImage = {}
      quads[image] = byImage
    end
    local frameQuad = byImage[slot]
    if not frameQuad then
      frameQuad = love.graphics.newQuad((slot % 16) * 16, math.floor(slot / 16) * 16, 16, 16, image:getDimensions())
      byImage[slot] = frameQuad
    end
    return frameQuad
  end

  -- Where the cursor cell (the footprint's bottom-left) is on screen.  The
  -- camera keeps the player's cell at (112, 72) and pans with the cursor
  -- (screen.mode.panX/panY), so at rest the cursor's offset from where it started,
  -- less the pan, places it.  The engine's own preview assumes that offset is
  -- zero, which the 1x3 shape breaks: it starts the cursor a row below the
  -- player (pokeemerald/src/decoration.c:1450).
  --
  -- A step moves the cursor at once and the pan over the next frames, so the
  -- offset is taken only at rest and held while a step is under way: the
  -- preview and the avatar stay put on screen while the map slides, as the
  -- engine's do.
  local function cursorScreen(mode)
    if not mode.dir or not mode.sbxOffset then
      mode.sbxOffset = { 16 * (mode.x - mode.initialX) - mode.panX, 16 * (mode.y - mode.initialY) - mode.panY }
    end
    return 112 + mode.sbxOffset[1], 72 + mode.sbxOffset[2]
  end

  -- preview: { ts, slots[row][col] } of the art grid, composed without floor.
  -- The decorating avatar stands right of the footprint, on its bottom row.
  function Menu.drawPlacing(screen, engine, piece, preview)
    local mode = screen.mode
    local cursorX, cursorY = cursorScreen(mode)
    if mode.solid or mode.blink < 15 then
      love.graphics.setColor(1, 1, 1, 1)
      for row, line in ipairs(piece.art.cells) do
        for col in ipairs(line) do
          local slot = preview.slots[row][col]
          local screenX = cursorX + (piece.art.x + col - 1) * 16
          local screenY = cursorY - (piece.height - row - (piece.art.y or 0)) * 16
          love.graphics.draw(preview.atlas.image, quad(preview.atlas.image, slot), screenX, screenY)
          love.graphics.draw(preview.atlas.overImage, quad(preview.atlas.overImage, slot), screenX, screenY)
        end
      end
    end
    drawObject(engine, avatarGfx(screen, engine), cursorX + 16 * piece.width, cursorY - 16)
  end

  return Menu
end
