--- mappng/ui/buttons.lua
---
--- Creates the four menu items and attaches them to the target screens.
---
--- The mechanism is the one `extension-automarket` uses for its market button:
--- build a MenuItem with a cdecl render function and a cdecl action handler,
--- then hand it to `Menu:addMenuItem`, which grows the game's item array for us
--- rather than requiring a patch of the static arrays.
---
--- NOT YET VERIFIED IN GAME:
---   * the exact positions -- see mappng/ui/screens.lua
---   * whether callbacks can be created from the framework's main Lua state via
---     `modules.cffi`, or whether these have to live in a LuaJIT state the way
---     automarket's do. If the latter, this file moves into a `ui/` subtree
---     loaded with `modules.ui:createMenuFromFile`, and the actions get invoked
---     through `ui:sendEvent`.

local screens = require("mappng.ui.screens")
local icons = require("mappng.ui.icons")

local M = {}

-- NORMAL_ELEMENT (3) | PART_OF_INTERACTION_GROUP (0x02000000)
local MENU_ITEM_TYPE = 0x02000003
local RENDER_FUNCTION_TYPE_SIMPLE = 0x1

local state = { items = {}, callbacks = {} }

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

  registerObject(render)
  return render
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

  registerObject(handler)
  return handler
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

        state.callbacks[#state.callbacks + 1] = render
        state.callbacks[#state.callbacks + 1] = handler

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

        state.items[#state.items + 1] = { screen = screen.name, action = action.key }
      end

      log(INFO, string.format("map-png: added 4 buttons to menu %d (%s)",
        screen.menuID, screen.name))
    end)

    if not ok then
      log(ERROR, string.format("map-png: could not add buttons to menu %d (%s): %s",
        screen.menuID, screen.name, tostring(err)))
    end
  end

  return #state.items
end

return M
