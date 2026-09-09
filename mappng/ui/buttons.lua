--- mappng/ui/buttons.lua
---
--- Creates the four menu items and attaches them to the target screens.
---
--- The mechanism is the one `extension-automarket` uses for its market button:
--- build a MenuItem with a cdecl render function and a cdecl action handler,
--- then hand it to `Menu:addMenuItem`, which grows the game's item array for us
--- rather than requiring a patch of the static arrays.
---
--- Callbacks from the main Lua state are supported: `modules.cffi` is a build of
--- cffi-lua, which implements LuaJIT-compatible callbacks (libffi closures) and
--- parses `__cdecl` as a real calling convention rather than ignoring it.
---
--- Note that automarket puts its equivalent callbacks in a LuaJIT state
--- instead. If these turn out to misbehave -- libffi closures are heavier than
--- LuaJIT's, and this render function runs every frame -- the fallback is to
--- move this file into a `ui/` subtree loaded with
--- `modules.ui:createMenuFromFile` and invoke the actions via `ui:sendEvent`,
--- which is the route automarket already proves works.
---
--- NOT YET VERIFIED IN GAME: the exact positions -- see mappng/ui/screens.lua.

local screens = require("mappng.ui.screens")
local icons = require("mappng.ui.icons")

local M = {}

-- NORMAL_ELEMENT (3) | PART_OF_INTERACTION_GROUP (0x02000000)
local MENU_ITEM_TYPE = 0x02000003
local RENDER_FUNCTION_TYPE_SIMPLE = 0x1

local state = { items = {}, callbacks = {} }

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

--- Builds the render callback for one action.
local function makeRender(ffi, game, action)
  local slot = nil
  local label = icons.LABELS[action.key]

  local render = ffi.cast("void (__cdecl *)(int)", function(_)
    local button = game.Rendering.ButtonState

    slot = slot or icons.slot(action.key)
    if slot ~= nil then
      game.Rendering.pDrawBufferChoiceValue[0] = 0
      game.Rendering.renderGM(game.Rendering.textureRenderCore,
        slot.gmID, slot.imageID, button.x, button.y)
      button.gmPictureIndex = slot.imageID
      game.Rendering.pDrawBufferChoiceValue[0] = 1
    else
      -- Fallback until the GM slots are assigned: draw the label so the button
      -- is still visible and clickable.
      game.Rendering.pDrawBufferChoiceValue[0] = 0
      game.Rendering.renderTextToScreenConst(game.Rendering.textManager,
        label, button.x, button.y + 4, 0, 0, 0x0E, 0, 0)
      game.Rendering.pDrawBufferChoiceValue[0] = 1
    end
  end)

  return anchor(render)
end

--- Builds the click callback for one action.
local function makeAction(ffi, action, onClick)
  local handler = ffi.cast("void (__cdecl *)(int)", function(_)
    local ok, err = pcall(onClick, action.mode, action.what)
    if not ok then
      log(ERROR, string.format("map-png: %s %s failed: %s",
        action.mode, action.what, tostring(err)))
    end
  end)

  return anchor(handler)
end

--- Attaches all four buttons to every target screen.
---
---@param ffi table the cffi interface
---@param game table the ui module's game bindings
---@param onClick fun(mode:string, what:string) invoked when a button is pressed
function M.install(ffi, game, onClick)
  local Menu = modules.ui:access().api.ui.Menu

  for _, screen in ipairs(screens.SCREENS) do
    local ok, err = pcall(function()
      local menu = Menu:fromID(screen.menuID)

      for index, action in ipairs(screens.ACTIONS) do
        local position = screens.iconPosition(screen, index)
        local render = makeRender(ffi, game, action)
        local handler = makeAction(ffi, action, onClick)

        -- Where addMenuItem is about to put this item. Recorded so the row can
        -- be moved later without a restart. The Menu object is stored rather
        -- than the item pointer, because reallocateMenuItems replaces the
        -- array wholesale.
        local itemIndex = menu.menuItemsIndex

        menu:addMenuItem({
          menuItemType = MENU_ITEM_TYPE,
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

      local origin = screens.resolveMinimap(screen)
      log(INFO, string.format(
        "map-png: added 4 buttons to menu %d (%s) at (%d,%d), position from %s",
        screen.menuID, screen.name, origin.x, origin.y, origin.source))
    end)

    if not ok then
      log(ERROR, string.format("map-png: could not add buttons to menu %d (%s): %s",
        screen.menuID, screen.name, tostring(err)))
    end
  end

  return #state.items
end

--- Moves an already-installed row to wherever `screens` now says it goes.
---
--- Called by `screens.setMinimap` / `screens.nudge`, so the position can be
--- dialled in with the editor screen open instead of one restart per guess.
---
---@param menuID number|nil all screens when omitted
---@return number how many buttons moved
function M.reposition(menuID)
  local moved = 0

  for _, entry in ipairs(state.items) do
    if menuID == nil or entry.screen.menuID == menuID then
      local position = screens.iconPosition(entry.screen, entry.actionIndex)
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
