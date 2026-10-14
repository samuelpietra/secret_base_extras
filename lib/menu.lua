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

return function(V)
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
    local pal = Decor.manifest().menuPalette or {}
    if disabled then return { fg = rgba(pal[5]), shadow = rgba(pal[6]) } end
    return { fg = rgba(pal[3]), shadow = rgba(pal[4]) }
  end

  -- pokeemerald/src/decoration.c:731: the bedroom takes only dolls and cushions.
  local function disabled(D, Decor, cat)
    return D.isPlayerRoom and D.command == MENU_PLACE and cat ~= Decor.CAT.DOLL and cat ~= Decor.CAT.CUSHION
  end

  -- The cursor (D.catCursor) is the screen's own and still runs over every
  -- category and CANCEL; only the window onto the list is this mod's.
  local function scrolled(D, rows)
    local cursor = D.catCursor or 0
    local scroll = D.sbxCategoryScroll or 0
    if cursor < scroll then scroll = cursor end
    if cursor >= scroll + VISIBLE then scroll = cursor - VISIBLE + 1 end
    scroll = math.max(0, math.min(scroll, rows - VISIBLE))
    D.sbxCategoryScroll = scroll
    return scroll
  end

  function Menu.drawCategories(D, E, text)
    local tpl = D.WIN.categories
    E.Window.stdFrame(tpl)
    E.Window.fill(tpl, 1, 1, 1, 1)
    local ox, oy = tpl.left * 8, tpl.top * 8
    local sess = D._session
    local count = E.Decor.CATEGORY_COUNT
    local rows = count + 1
    local scroll = scrolled(D, rows)
    for r = 0, math.min(rows, VISIBLE) - 1 do
      local cat = scroll + r
      local y = oy + r * ROW + 1
      if cat == count then
        E.Window.printPx(text(D.command == MENU_TRADE and "gText_Exit" or "gText_Cancel"), ox + 8, y)
      else
        local colors = menuColors(E.Decor, disabled(D, E.Decor, cat))
        local name = cat == V.Furniture.CATEGORY.index and V.Furniture.CATEGORY.name or text(CATEGORY_TEXT[cat])
        E.FrlgFont.draw(name, ox + 8, y, { colors = colors })
        local filled = string.format("%2d/%2d", E.DecorInv.countInCategory(cat, sess), E.DecorInv.SIZES[cat])
        E.FrlgFont.draw(filled, ox + 104 - E.FrlgFont.measure(filled), y, { colors = colors })
      end
    end
    E.Window.cursorPx(ox, oy + 1 + ((D.catCursor or 0) - scroll) * ROW)
    if rows > VISIBLE then
      E.ListMenu.drawScrollArrows(tpl, scroll > 0, scroll + VISIBLE < rows, D.frames)
    end
  end

  local function drawObject(E, gid, x, y)
    local spr = E.OwSprites.getDraw(gid)
    local q = spr and spr.quads and spr.quads[0]
    if not q then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(spr.image, q, x, y)
  end

  local function isFemale(sess)
    local g = sess and sess.gender
    return g == 1 or g == "female" or g == "F" or g == "girl"
  end

  local function avatarGfx(D, E)
    local sess = D._session
    if D._opts and D._opts.avatarGfx then return D._opts.avatarGfx(sess, isFemale(sess)) end
    return E.Constants.of("emerald"):require("event_objects",
      isFemale(sess) and "OBJ_EVENT_GFX_MAY_DECORATING" or "OBJ_EVENT_GFX_BRENDAN_DECORATING")
  end

  local quads = setmetatable({}, { __mode = "k" })
  local function quad(image, slot)
    local byImage = quads[image]
    if not byImage then
      byImage = {}
      quads[image] = byImage
    end
    local q = byImage[slot]
    if not q then
      q = love.graphics.newQuad((slot % 16) * 16, math.floor(slot / 16) * 16, 16, 16, image:getDimensions())
      byImage[slot] = q
    end
    return q
  end

  -- Where the cursor cell (the footprint's bottom-left) is on screen.  The
  -- camera keeps the player's cell at (112, 72) and pans with the cursor
  -- (D.mode.panX/panY), so at rest the cursor's offset from where it started,
  -- less the pan, places it.  The engine's own preview assumes that offset is
  -- zero, which the 1x3 shape breaks: it starts the cursor a row below the
  -- player (pokeemerald/src/decoration.c:1450).
  --
  -- A step moves the cursor at once and the pan over the next frames, so the
  -- offset is taken only at rest and held while a step is under way: the
  -- preview and the avatar stay put on screen while the map slides, as the
  -- engine's do.
  local function cursorScreen(m)
    if not m.dir or not m.sbxOffset then
      m.sbxOffset = { 16 * (m.x - m.initialX) - m.panX, 16 * (m.y - m.initialY) - m.panY }
    end
    return 112 + m.sbxOffset[1], 72 + m.sbxOffset[2]
  end

  -- preview: { ts, slots[row][col] } of the art grid, composed without floor.
  -- The decorating avatar stands right of the footprint, on its bottom row.
  function Menu.drawPlacing(D, E, piece, preview)
    local m = D.mode
    local cx, cy = cursorScreen(m)
    if m.solid or m.blink < 15 then
      love.graphics.setColor(1, 1, 1, 1)
      for row, line in ipairs(piece.art.cells) do
        for col in ipairs(line) do
          local slot = preview.slots[row][col]
          local px = cx + (piece.art.x + col - 1) * 16
          local py = cy - (piece.height - row) * 16
          love.graphics.draw(preview.ts.image, quad(preview.ts.image, slot), px, py)
          love.graphics.draw(preview.ts.overImage, quad(preview.ts.overImage, slot), px, py)
        end
      end
    end
    drawObject(E, avatarGfx(D, E), cx + 16 * piece.width, cy - 16)
  end

  return Menu
end
