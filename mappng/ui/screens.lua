--- mappng/ui/screens.lua
---
--- Which menus get the buttons, and where the row sits.
---
--- The two target screens, from `OpenSHC/src/OpenSHC/Globals/`:
---
---   Menu_MapEditorProperties  0x00B97148  MVT_MAP_EDITOR_PROPERTIES = 17
---   Menu_EditScenario         0x00B982D0  MVT_EDIT_SCENARIO         = 1002
---
--- The four icons are 32x18 each, so a row of four is exactly 128px -- the
--- width of the minimap preview. The row therefore sits flush under the
--- minimap with no gaps, which is what the black strip in the mockup is.
---
--- The minimap origin per screen is NOT YET KNOWN. `dump()` below prints every
--- menu item of a live menu so the two existing round buttons under the
--- minimap can be located and the row anchored to them. Fill in `minimap`
--- afterwards and delete this note.

local M = {}

M.ICON_WIDTH = 32
M.ICON_HEIGHT = 18

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
    -- TODO(discovery): minimap origin and height on this screen.
    minimap = { x = nil, y = nil, height = nil },
  },
  {
    name = "edit-scenario",
    menuID = 1002,
    -- TODO(discovery): minimap origin and height on this screen.
    minimap = { x = nil, y = nil, height = nil },
  },
}

--- Position of icon `index` (1..4) for a screen.
function M.iconPosition(screen, index)
  local minimap = screen.minimap
  if minimap.x == nil or minimap.y == nil or minimap.height == nil then
    error(string.format(
      "map-png: the minimap position for screen '%s' has not been filled in yet; "
      .. "run screens.dump(%d) in the UCP console and see mappng/ui/screens.lua",
      screen.name, screen.menuID))
  end

  return {
    x = minimap.x + ((index - 1) * M.ICON_WIDTH),
    y = minimap.y + minimap.height,
  }
end

--- Prints every menu item of a live menu, so the minimap anchor can be found.
---
--- Run from the UCP console while the screen is open:
---   require("mappng.ui.screens").dump(17)
---
--- What to look for: the two round buttons under the minimap in the
--- screenshots. Their `position` gives the row's y, and the leftmost one's x
--- lines up with the minimap's left edge.
function M.dump(menuID)
  local ui = modules.ui
  local Menu = ui:access().api.ui.Menu
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
