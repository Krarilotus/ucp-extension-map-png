--- mappng/ui/screens.lua
---
--- Which menus get the buttons, and where the row sits.
---
--- The two target screens, from `OpenSHC/src/OpenSHC/Globals/`:
---
---   Menu_MapEditorProperties  0x00B97148  MVT_MAP_EDITOR_PROPERTIES = 17
---   Menu_EditScenario         0x00B982D0  MVT_EDIT_SCENARIO         = 1002
---
--- Geometry, measured off the mockup: the map preview is square, and the strip
--- below it is divided into four equal segments spanning its full width. The
--- strip's height relative to the preview's is 41/296, and the icons are 32x18
--- -- so four icons across is 4*32 = 128, the preview is 128x128, and
--- 18/128 = 0.1406 matches the measured 0.1385 to within a pixel. The row
--- therefore sits flush under the preview with no gaps.
---
--- Position is resolved in three steps, most trusted first:
---   1. an override set by `setMinimap` (or filled into `SCREENS` below)
---   2. `MinimapViewState` read at runtime
---   3. `FALLBACK`, so the buttons always appear somewhere rather than not at all
---
--- Step 2 is a guess that still needs confirming: `renderMinimapPreview` takes
--- its screen position as arguments, so `MinimapViewState.x/y` may be the
--- in-game viewport rather than this preview's position on the editor menu.
--- That is what `probe()` and `setMinimap()` are for -- nudge it live, then
--- write the numbers into `SCREENS`.

local M = {}

M.ICON_WIDTH = 32
M.ICON_HEIGHT = 18

--- OpenSHC: DAT_MinimapViewState.
M.MINIMAP_VIEW_STATE = 0x01A31610
M.MINIMAP_OFFSETS = {
  width = 0x18,
  height = 0x1C,
  x = 0x28,
  y = 0x2C,
}

--- Used when nothing better is known, so the row is at least visible and
--- clickable and can be dragged into place with `setMinimap`.
M.FALLBACK = { x = 336, y = 260, height = 0 }

--- The four actions, in the order they appear left to right.
M.ACTIONS = {
  { key = "import_heightmap", mode = "import", what = "height" },
  { key = "export_heightmap", mode = "export", what = "height" },
  { key = "import_textures", mode = "import", what = "terrain" },
  { key = "export_textures", mode = "export", what = "terrain" },
}

M.SCREENS = {
  {
    name = "map-editor-properties",
    menuID = 17,
    -- Fill in once confirmed: { x = ..., y = ..., height = ... }
    minimap = nil,
  },
  {
    name = "edit-scenario",
    menuID = 1002,
    minimap = nil,
  },
}

function M.screenByMenuID(menuID)
  for _, screen in ipairs(M.SCREENS) do
    if screen.menuID == menuID then
      return screen
    end
  end
  return nil
end

--- Reads the live minimap geometry.
---@return table|nil { x, y, width, height }
function M.readMinimapViewState()
  if core == nil then
    return nil
  end

  local base = M.MINIMAP_VIEW_STATE
  local o = M.MINIMAP_OFFSETS

  local ok, geometry = pcall(function()
    return {
      x = core.readInteger(base + o.x),
      y = core.readInteger(base + o.y),
      width = core.readInteger(base + o.width),
      height = core.readInteger(base + o.height),
    }
  end)
  if not ok then
    return nil
  end

  -- Reject obvious nonsense rather than putting the buttons off-screen.
  if geometry.x < 0 or geometry.y < 0 or geometry.x > 800 or geometry.y > 600 then
    return nil
  end

  return geometry
end

--- Resolves the row origin for a screen: override, then runtime, then fallback.
---@return table { x, y, source }
function M.resolveMinimap(screen)
  if screen.minimap ~= nil and screen.minimap.x ~= nil then
    return {
      x = screen.minimap.x,
      y = screen.minimap.y + (screen.minimap.height or 0),
      source = "override",
    }
  end

  local live = M.readMinimapViewState()
  if live ~= nil then
    return { x = live.x, y = live.y + live.height, source = "MinimapViewState" }
  end

  return {
    x = M.FALLBACK.x,
    y = M.FALLBACK.y + M.FALLBACK.height,
    source = "fallback",
  }
end

--- Position of icon `index` (1..4) for a screen.
function M.iconPosition(screen, index)
  local origin = M.resolveMinimap(screen)
  return {
    x = origin.x + ((index - 1) * M.ICON_WIDTH),
    y = origin.y,
    source = origin.source,
  }
end

--- Sets the row position for a screen and moves the buttons immediately.
---
--- For dialling the position in without restarting. From the UCP console, with
--- the editor screen open:
---
---   local s = modules['map-png']:access().screens
---   s.setMinimap(17, 336, 232, 128)   -- minimap x, y, height
---
--- The buttons jump on the next frame. When it looks right, write the same
--- numbers into `SCREENS` above.
function M.setMinimap(menuID, x, y, height)
  local screen = M.screenByMenuID(menuID)
  if screen == nil then
    error(string.format("map-png: no screen with menu id %d", menuID))
  end

  screen.minimap = { x = x, y = y, height = height or 0 }

  local buttons = require("mappng.ui.buttons")
  buttons.reposition(menuID)

  log(INFO, string.format("map-png: menu %d row moved to (%d,%d)",
    menuID, x, y + (height or 0)))
  return screen.minimap
end

--- Nudges the current row by a delta, for fine adjustment.
function M.nudge(menuID, dx, dy)
  local screen = M.screenByMenuID(menuID)
  if screen == nil then
    error(string.format("map-png: no screen with menu id %d", menuID))
  end

  local origin = M.resolveMinimap(screen)
  return M.setMinimap(menuID, origin.x + (dx or 0), origin.y + (dy or 0), 0)
end

--- Logs everything needed to place the row. Run with the screen open.
function M.probe(menuID)
  local live = M.readMinimapViewState()
  if live == nil then
    log(INFO, "map-png: MinimapViewState holds no plausible screen position")
  else
    log(INFO, string.format("map-png: MinimapViewState x=%d y=%d w=%d h=%d",
      live.x, live.y, live.width, live.height))
  end

  if menuID ~= nil then
    local screen = M.screenByMenuID(menuID)
    if screen ~= nil then
      local origin = M.resolveMinimap(screen)
      log(INFO, string.format("map-png: menu %d row origin (%d,%d) from %s",
        menuID, origin.x, origin.y, origin.source))
    end
    M.dump(menuID)
  end
end

--- Prints every menu item of a live menu.
---
--- What to look for: the two round buttons under the minimap in the
--- screenshots. Their y gives the row's y, and the leftmost one's x lines up
--- with the preview's left edge.
function M.dump(menuID)
  local Menu = modules.ui:access().api.ui.Menu
  local menu = Menu:fromID(menuID)

  log(INFO, string.format("map-png: menu %d has %d items", menuID, menu.menuItemsCount))
  for i = 0, menu.menuItemsCount - 1 do
    local item = menu.menuItems[i]
    log(INFO, string.format(
      "  [%3d] type=0x%08X pos=(%d,%d) size=%dx%d renderType=%d gmData=%d param=%d",
      i,
      tonumber(item.menuItemType),
      tonumber(item.position.position.x),
      tonumber(item.position.position.y),
      tonumber(item.itemWidth),
      tonumber(item.itemHeight),
      tonumber(item.menuItemRenderFunctionType),
      tonumber(item.firstItemTypeData.gmDataIndex),
      tonumber(item.callbackParameter.parameter)))
  end
end

return M
