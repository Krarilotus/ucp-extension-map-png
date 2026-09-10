--- mappng/ui/screens.lua
---
--- Which menu gets the buttons, and where the row sits.
---
--- Both of the target screens -- the singleplayer ("Einzelspieler") and the
--- multiplayer ("Mehrspieler") editor map screen -- are one menu:
--- `Menu_MapEditorProperties`, menu 17, at 0x00B97148. Its items switch with
--- the map type. (Menu 1002, `Menu_EditScenario`, is the scenario *event*
--- editor and has no map preview.)
---
--- Everything below was read out of Stronghold Crusader 1.41, not measured off
--- screenshots:
---
--- * The preview is drawn by `MenuView_MapEditorProperties_DoEveryFrame`
---   (0x0042E0D0, registered for menu 17 at 0x0059A490) through
---   `MinimapViewState::renderMinimapEditor(x, y, w, h)` (0x004B7530).
---
--- * Its centre is the menu origin plus (400, 240) in the singleplayer layout
---   and (600, 240) in the multiplayer layout, chosen by `[0x01FE9244]`.
---
--- * Its size follows the map size in `[0x01FE7C14]` (0 means 400):
---   160 -> 160x160, 200 -> 200x200, 300 -> 150x150, 400 -> 200x200.
---
--- * It is only drawn while `[0x01FE7CBC] == -1`. The buttons mirror that.
---
--- * Every MenuView prepare stores the same origin into the menu's own x/y
---   (`mov [menu+4], ecx` / `mov [menu+8], eax` next to the writes to
---   0x00F2B3A0 / 0x00F2B3A4), and the item render loop computes
---   ButtonX = menu.x + item.x, ButtonY = menu.y + item.y (0x004F4A26). So an
---   item placed at menu-local (x, y) lands in exactly the preview's frame at
---   any resolution -- no screen-coordinate arithmetic here.
---
--- The global names are ours; OpenSHC has none for them yet.
---
--- The row is four equal slots spanning the preview's width, each icon centred
--- in its slot, 8px below the preview. That reproduces the mockup: a strip
--- starting 3px under the preview, 28px tall, four segments across. The
--- icons are 32x18, which fits a slot at every map size.

local M = {}

M.ICON_WIDTH = 32
M.ICON_HEIGHT = 18

--- Below the preview's bottom edge: 3px to the mockup's strip, plus 5 to centre
--- an 18px icon in its 28px height.
M.ICON_GAP = 8

--- The four actions, in the order they appear left to right.
M.ACTIONS = {
  { key = "import_heightmap", mode = "import", what = "height" },
  { key = "export_heightmap", mode = "export", what = "height" },
  { key = "import_textures", mode = "import", what = "terrain" },
  { key = "export_textures", mode = "export", what = "terrain" },
}

--- The preview's geometry in menu-local coordinates, from 0x0042E0D0.
M.PREVIEW = {
  centreX = { sp = 400, mp = 600 },
  centreY = 240,
  halfBySize = { [160] = 80, [200] = 100, [300] = 75, [400] = 100 },
  defaultSize = 400,
}

--- Crusader 1.41 only. Read by `currentLayout` when `setGlobalsAvailable(true)`.
M.GLOBALS = {
  previewSuppressed = 0x01FE7CBC, -- the preview is drawn only while this is -1
  multiplayerLayout = 0x01FE9244, -- nonzero: multiplayer layout, centre x 600
  mapSize = 0x01FE7C14,           -- width of the square map; 0 means 400
}

M.SCREENS = {
  {
    name = "map-editor-properties",
    menuID = 17,
    -- A manual correction on top of the derived position, set live with
    -- setOffset / nudge. Expected to stay at zero.
    offset = { x = 0, y = 0 },
  },
}

local state = { globalsAvailable = false }

--- The globals above are only valid on the build they were read from.
--- init.lua enables them once tilemap.lua has confirmed Crusader 1.41.
function M.setGlobalsAvailable(available)
  state.globalsAvailable = available and true or false
end

local function readInteger(address)
  if not state.globalsAvailable or core == nil then
    return nil
  end
  local ok, value = pcall(core.readInteger, address)
  if ok then
    return value
  end
  return nil
end

function M.screenByMenuID(menuID)
  for _, screen in ipairs(M.SCREENS) do
    if screen.menuID == menuID then
      return screen
    end
  end
  return nil
end

--- What the game is drawing right now: which layout, which map size, whether
--- the preview is shown at all.
---@return table { variant, size, half, centreX, centreY, hidden, source, key }
function M.currentLayout()
  local suppressed = readInteger(M.GLOBALS.previewSuppressed)
  local multiplayer = readInteger(M.GLOBALS.multiplayerLayout)
  local size = readInteger(M.GLOBALS.mapSize)

  local variant = (multiplayer ~= nil and multiplayer ~= 0) and "mp" or "sp"
  if size == nil or size == 0 then
    size = M.PREVIEW.defaultSize
  end
  local half = M.PREVIEW.halfBySize[size]
    or M.PREVIEW.halfBySize[M.PREVIEW.defaultSize]

  local hidden = suppressed ~= nil and suppressed ~= -1 and suppressed ~= 0xFFFFFFFF

  return {
    variant = variant,
    size = size,
    half = half,
    centreX = M.PREVIEW.centreX[variant],
    centreY = M.PREVIEW.centreY,
    hidden = hidden,
    source = state.globalsAvailable and "game" or "default",
    key = string.format("%s:%d", variant, size),
  }
end

--- Menu-local position of icon `index` (1..4).
---@param layout table|nil result of currentLayout(); read fresh when omitted
function M.iconPosition(screen, index, layout)
  layout = layout or M.currentLayout()

  local slot = layout.half // 2
  local left = layout.centreX - layout.half
  local offset = screen.offset or { x = 0, y = 0 }

  return {
    x = left + ((index - 1) * slot) + ((slot - M.ICON_WIDTH) // 2) + offset.x,
    y = layout.centreY + layout.half + M.ICON_GAP + offset.y,
  }
end

--- Native button surround with the supplied 32x18 picture centred inside.
--- A two-pixel gap between buttons also fits the smallest (150px) preview.
function M.buttonBounds(screen, index, layout)
  layout = layout or M.currentLayout()
  local icon = M.iconPosition(screen, index, layout)
  local width, height = (layout.half // 2) - 2, 28
  return { x = icon.x - ((width - M.ICON_WIDTH) // 2),
    y = icon.y - ((height - M.ICON_HEIGHT) // 2), width = width, height = height }
end

--- Sets a manual correction for a screen and moves its buttons immediately.
---
--- From the UCP console, with the editor map screen open:
---
---   local s = modules['map-png']:access().screens
---   s.setOffset(17, 0, -2)
---
--- If a correction turns out to be needed, write it into `SCREENS` above --
--- and treat it as a sign that one of the facts in the header is wrong.
function M.setOffset(menuID, dx, dy)
  local screen = M.screenByMenuID(menuID)
  if screen == nil then
    error(string.format("map-png: no screen with menu id %d", menuID))
  end

  screen.offset = { x = dx or 0, y = dy or 0 }

  local buttons = require("mappng.ui.buttons")
  buttons.reposition(menuID)

  log(INFO, string.format("map-png: menu %d offset set to (%d,%d)",
    menuID, screen.offset.x, screen.offset.y))
  return screen.offset
end

--- Adds to the current correction, for fine adjustment.
function M.nudge(menuID, dx, dy)
  local screen = M.screenByMenuID(menuID)
  if screen == nil then
    error(string.format("map-png: no screen with menu id %d", menuID))
  end
  local offset = screen.offset or { x = 0, y = 0 }
  return M.setOffset(menuID, offset.x + (dx or 0), offset.y + (dy or 0))
end

--- Logs the live layout and where each icon goes. Run with the screen open.
function M.probe(menuID)
  menuID = menuID or 17
  local layout = M.currentLayout()
  log(INFO, string.format(
    "map-png: layout %s (from %s): preview %dx%d centred (%d,%d), %s",
    layout.key, layout.source, layout.half * 2, layout.half * 2,
    layout.centreX, layout.centreY, layout.hidden and "HIDDEN" or "shown"))

  local screen = M.screenByMenuID(menuID)
  if screen ~= nil then
    for index, action in ipairs(M.ACTIONS) do
      local p = M.iconPosition(screen, index, layout)
      log(INFO, string.format("  %-18s menu-local (%d,%d)", action.key, p.x, p.y))
    end
  end

  M.dump(menuID)
end

--- Prints every menu item of a live menu.
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
