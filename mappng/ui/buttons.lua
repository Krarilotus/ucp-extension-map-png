--- mappng/ui/buttons.lua
---
--- Creates the four menu items and attaches them to the target screen.
---
--- Two rules this file has to follow, both learned from a crash:
---
--- 1. Items go in with `Menu:insertMenuItem`, never `Menu:addMenuItem`.
---    `Menu:fromID` points the write index at the menu's LAST_ENTRY (0x66)
---    terminator, and `addMenuItem` writes over it. On a menu it had to
---    reallocate, the slots after the old terminator are zero-filled, not 0x66,
---    so the item list ends up with no terminator at all and the game walks
---    off the end of it. `insertMenuItem` shifts the terminator down instead.
---    This is also what `extension-automarket` does. `addMenuItem` is only safe
---    on menus built with `Menu:createMenu`, which pre-fills every slot with 0x66.
---
--- 2. The items are plain NORMAL_ELEMENT (3), with no interaction-group flag.
---    An item flagged PART_OF_INTERACTION_GROUP (0x02000000) uses the render and
---    action functions of its group's leader, and menu 17's last group is led
---    by MapEditorProperties_MainButtons -- which would then be called with our
---    parameters. The game's own standalone items with their own functions are
---    type 3: the lobby's minimap item (menu 20, [22]) and the scenario menu's
---    buttons (menu 1002, [16], [17]).
---
--- Positions are menu-local; see mappng/ui/screens.lua for why that stays
--- aligned with the preview at any resolution.
---
--- The preview moves and resizes with the map (singleplayer vs multiplayer
--- layout, 160/200/300/400 map size), so the render function re-checks the
--- layout every frame and moves the row when it changes. It also hides the row
--- whenever the game is not drawing the preview.
---
--- Callbacks from the main Lua state are supported: `modules.cffi` is a build of
--- cffi-lua, which implements LuaJIT-compatible callbacks (libffi closures) and
--- parses `__cdecl` as a real calling convention rather than ignoring it.

local screens = require("mappng.ui.screens")
local icons = require("mappng.ui.icons")

local M = {}

M.MENU_ITEM_TYPE = 0x3 -- NORMAL_ELEMENT, standalone
M.LAST_ENTRY = 0x66
local RENDER_FUNCTION_TYPE_SIMPLE = 0x1

local state = { items = {}, callbacks = {}, layoutKey = nil }

--- Keeps a callback alive for the lifetime of the module.
---
--- The game calls these from its render loop long after `install` returns, so
--- letting one be collected is a crash. The LuaJIT states have a global
--- `registerObject` for this, but that is defined in the luajit module's
--- `common/code.lua` and does *not* exist in the framework's main Lua state,
--- which is where this file runs -- so we anchor them ourselves.
local function anchor(callback)
  state.callbacks[#state.callbacks + 1] = callback
  return callback
end

--- Moves the row when the game switches layout or map size.
---
--- Called from every icon's render function; the layout key makes it a no-op
--- except on the frame a change happens. The item positions it writes take
--- effect from the next frame, which is when the game next reads them.
local function followLayout()
  local layout = screens.currentLayout()
  if layout.key ~= state.layoutKey then
    state.layoutKey = layout.key
    M.reposition(nil, layout)
  end
  return layout
end

--- Builds the render callback for one action.
local function makeRender(ffi, game, action)
  local label = icons.LABELS[action.key]

  local render = ffi.cast("void (__cdecl *)(int)", function(_)
    local layout = followLayout()
    if layout.hidden then
      return -- the game is not drawing the preview, so no row under it either
    end

    local button = game.Rendering.ButtonState
    local slot = icons.slot(action.key)

    game.Rendering.pDrawBufferChoiceValue[0] = 0
    if slot ~= nil then
      game.Rendering.renderGM(game.Rendering.textureRenderCore,
        slot.gmID, slot.imageID, button.x, button.y)
      button.gmPictureIndex = slot.imageID
    else
      -- Fallback until the GM slots are assigned: draw the label so the button
      -- is still visible and clickable.
      game.Rendering.renderTextToScreenConst(game.Rendering.textManager,
        label, button.x, button.y + 4, 0, 0, 0x0E, 0, 0)
    end
    game.Rendering.pDrawBufferChoiceValue[0] = 1
  end)

  return anchor(render)
end

--- Builds the click callback for one action.
local function makeAction(ffi, action, onClick)
  local handler = ffi.cast("void (__cdecl *)(int)", function(_)
    if screens.currentLayout().hidden then
      return
    end

    local ok, err = pcall(onClick, action.mode, action.what)
    if not ok then
      log(ERROR, string.format("map-png: %s %s failed: %s",
        action.mode, action.what, tostring(err)))
    end
  end)

  return anchor(handler)
end

--- True if the menu's item list still ends in a LAST_ENTRY terminator at the
--- write index, which is where Menu:insertMenuItem keeps it.
function M.isTerminated(menu)
  return menu.menuItems[menu.menuItemsIndex].menuItemType == M.LAST_ENTRY
end

--- Attaches all four buttons to every target screen.
---
---@param ffi table the cffi interface
---@param game table the ui module's game bindings
---@param onClick fun(mode:string, what:string) invoked when a button is pressed
function M.install(ffi, game, onClick)
  local Menu = modules.ui:access().api.ui.Menu
  local layout = screens.currentLayout()
  state.layoutKey = layout.key

  for _, screen in ipairs(screens.SCREENS) do
    local ok, err = pcall(function()
      local menu = Menu:fromID(screen.menuID)
      if not M.isTerminated(menu) then
        error("the menu's item list is not terminated where expected; not touching it")
      end

      for index, action in ipairs(screens.ACTIONS) do
        local position = screens.iconPosition(screen, index, layout)
        local render = makeRender(ffi, game, action)
        local handler = makeAction(ffi, action, onClick)

        -- Insert just before the terminator, which shifts it down one slot.
        -- Later inserts land after this one, so the recorded index stays valid.
        -- The Menu object is kept rather than the item pointer, because
        -- reallocateMenuItems replaces the array wholesale.
        local itemIndex = menu.menuItemsIndex

        menu:insertMenuItem(itemIndex, {
          menuItemType = M.MENU_ITEM_TYPE,
          menuItemRenderFunctionType = RENDER_FUNCTION_TYPE_SIMPLE,
          position = { position = { x = position.x, y = position.y } },
          itemWidth = screens.ICON_WIDTH,
          itemHeight = screens.ICON_HEIGHT,
          callbackParameter = { parameter = index },
          menuItemRenderFunction = {
            address = tonumber(ffi.cast("unsigned long", render)),
          },
          menuItemActionHandler = {
            address = tonumber(ffi.cast("unsigned long", handler)),
          },
        })

        state.items[#state.items + 1] = {
          screen = screen,
          action = action.key,
          actionIndex = index,
          menu = menu,
          itemIndex = itemIndex,
        }
      end

      if not M.isTerminated(menu) then
        -- Should be impossible with insertMenuItem; if it happens the game will
        -- crash the next time it walks this menu, so say so loudly.
        error("the menu's item list lost its terminator after inserting the buttons")
      end

      local first = screens.iconPosition(screen, 1, layout)
      log(INFO, string.format(
        "map-png: added 4 buttons to menu %d (%s), first at menu-local (%d,%d), layout %s from %s",
        screen.menuID, screen.name, first.x, first.y, layout.key, layout.source))
    end)

    if not ok then
      log(ERROR, string.format("map-png: could not add buttons to menu %d (%s): %s",
        screen.menuID, screen.name, tostring(err)))
    end
  end

  return #state.items
end

--- Moves already-installed buttons to wherever `screens` now says they go.
---
---@param menuID number|nil all screens when omitted
---@param layout table|nil result of screens.currentLayout(); read fresh when omitted
---@return number how many buttons moved
function M.reposition(menuID, layout)
  layout = layout or screens.currentLayout()
  local moved = 0

  for _, entry in ipairs(state.items) do
    if menuID == nil or entry.screen.menuID == menuID then
      local position = screens.iconPosition(entry.screen, entry.actionIndex, layout)
      local item = entry.menu.menuItems[entry.itemIndex]
      item.position.position.x = position.x
      item.position.position.y = position.y
      moved = moved + 1
    end
  end

  return moved
end

--- The installed buttons, for inspection from the console.
function M.installed()
  return state.items
end

return M
