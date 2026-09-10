--- mappng/ui/buttons.lua
---
--- Creates the four menu items and attaches them to the target screen.
---
--- Rules this file has to follow, each learned from a crash:
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
--- 3. No Lua error may leave a callback. The game calls these from its own
---    render loop; an error unwinding through the game's C frames takes the
---    whole process down. Every callback body runs under xpcall, and failures
---    are logged (rate-limited) instead. The first few calls of each callback
---    also log step markers, so a hard crash below Lua still shows in ucp3.log
---    as the last step reached.
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

--- How many calls of each callback get step markers in the log.
M.TRACED_CALLS = 3
--- How many failures of each callback get logged.
M.LOGGED_FAILURES = 3

local traceback = (debug and debug.traceback) or function(err) return err end

local state = {
  items = {},
  callbacks = {},
  layoutKey = nil,
  calls = {},    -- callback key -> number of completed calls
  failures = {}, -- callback key -> number of failed calls
}

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

--- Logs a step marker during the first few calls of a callback.
local function trace(key, step)
  if (state.calls[key] or 0) < M.TRACED_CALLS then
    log(INFO, string.format("map-png: [%s #%d] %s", key, (state.calls[key] or 0) + 1, step))
  end
end

--- Wraps a callback body so no Lua error can unwind into the game.
local function guarded(key, body)
  return function(parameter)
    local ok, err = xpcall(body, traceback, parameter)
    state.calls[key] = (state.calls[key] or 0) + 1
    if not ok then
      local count = (state.failures[key] or 0) + 1
      state.failures[key] = count
      if count <= M.LOGGED_FAILURES then
        log(ERROR, string.format("map-png: %s failed (%d): %s", key, count, tostring(err)))
      end
    end
  end
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
  local key = "render " .. action.key
  local label = icons.LABELS[action.key]

  local render = ffi.cast("void (__cdecl *)(int)", guarded(key, function(_)
    trace(key, "entered")

    local layout = followLayout()
    if layout.hidden then
      trace(key, "preview hidden, not drawing")
      return -- the game is not drawing the preview, so no row under it either
    end

    local rendering = game.Rendering
    local button = rendering.ButtonState
    trace(key, string.format("button at (%d,%d), layout %s",
      tonumber(button.x), tonumber(button.y), layout.key))

    local previousSurface = rendering.pDrawBufferChoiceValue[0]
    -- Surface 0 does not draw. The same native renderer behind renderGM uses
    -- surface 1 for normal interface drawing and surface 2 for its backbuffer.
    rendering.pDrawBufferChoiceValue[0] = 1
    local ok, err = pcall(function()
      -- Vanilla button chrome uses ButtonState, including its interaction
      -- state. Only the picture inside is ours (no custom button skin).
      rendering.renderButtonBackground(rendering.alphaAndButtonSurface, 0, -1)
      local x = button.x + ((button.width - screens.ICON_WIDTH) // 2)
      local y = button.y + ((button.height - screens.ICON_HEIGHT) // 2)
      if icons.available() then
        trace(key, "drawing supplied PNG artwork")
        icons.draw(action.key, rendering, x, y)
      else
        trace(key, "calling renderTextToScreenConst")
        rendering.renderTextToScreenConst(rendering.textManager,
          label, x, y, 0, 0xB8EEFB, 0x0E, false, 0)
      end
    end)
    rendering.pDrawBufferChoiceValue[0] = previousSurface
    if not ok then error(err, 0) end

    trace(key, "done")
  end))

  return anchor(render)
end

--- Builds the click callback for one action.
local function makeAction(ffi, action, onClick)
  local key = "click " .. action.key

  local handler = ffi.cast("void (__cdecl *)(int)", guarded(key, function(_)
    trace(key, "entered")
    if screens.currentLayout().hidden then
      trace(key, "preview hidden, ignoring")
      return
    end

    onClick(action.mode, action.what)
    trace(key, "done")
  end))

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

      -- Build every callback and resolve its address before touching the menu.
      --
      -- The conversion must be ffi.tonumber. `modules.cffi` is cffi-lua on
      -- stock Lua 5.4, where the built-in tonumber cannot read a cdata and
      -- returns nil -- the item's function pointer then stays 0, and the game
      -- calls address 0 the first time the menu draws. That was the second
      -- in-game crash (fault offset 0x00000000). automarket gets away with plain
      -- tonumber only because its callbacks live in a LuaJIT state. The ui
      -- module itself uses `ffi.tonumber or tonumber` for the same reason.
      local toNumber = ffi.tonumber or tonumber
      local prepared = {}
      for index, action in ipairs(screens.ACTIONS) do
        local render = makeRender(ffi, game, action)
        local handler = makeAction(ffi, action, onClick)
        local renderAddress = toNumber(ffi.cast("unsigned long", render))
        local handlerAddress = toNumber(ffi.cast("unsigned long", handler))
        if not renderAddress or renderAddress == 0
          or not handlerAddress or handlerAddress == 0 then
          error(string.format(
            "no function address for %s (render=%s, click=%s); not touching the menu",
            action.key, tostring(renderAddress), tostring(handlerAddress)))
        end
        prepared[index] = { action = action, render = renderAddress, handler = handlerAddress }
      end

      for index, entry in ipairs(prepared) do
        local position = screens.buttonBounds(screen, index, layout)

        -- Insert just before the terminator, which shifts it down one slot.
        -- Later inserts land after this one, so the recorded index stays valid.
        -- The Menu object is kept rather than the item pointer, because
        -- reallocateMenuItems replaces the array wholesale.
        local itemIndex = menu.menuItemsIndex

        menu:insertMenuItem(itemIndex, {
          menuItemType = M.MENU_ITEM_TYPE,
          menuItemRenderFunctionType = RENDER_FUNCTION_TYPE_SIMPLE,
          position = { position = { x = position.x, y = position.y } },
          itemWidth = position.width,
          itemHeight = position.height,
          callbackParameter = { parameter = index },
          menuItemRenderFunction = { address = entry.render },
          menuItemActionHandler = { address = entry.handler },
        })

        state.items[#state.items + 1] = {
          screen = screen,
          action = entry.action.key,
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

      -- What the game will actually read, for comparing against a crash.
      for _, entry in ipairs(state.items) do
        if entry.screen == screen then
          local item = menu.menuItems[entry.itemIndex]
          log(INFO, string.format(
            "map-png: item [%d] type=0x%X pos=(%d,%d) size=%dx%d renderType=%d render=0x%X action=0x%X",
            entry.itemIndex, tonumber(item.menuItemType),
            tonumber(item.position.position.x), tonumber(item.position.position.y),
            tonumber(item.itemWidth), tonumber(item.itemHeight),
            tonumber(item.menuItemRenderFunctionType),
            tonumber(item.menuItemRenderFunction.address),
            tonumber(item.menuItemActionHandler.address)))
        end
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
      local position = screens.buttonBounds(entry.screen, entry.actionIndex, layout)
      local item = entry.menu.menuItems[entry.itemIndex]
      item.position.position.x = position.x
      item.position.position.y = position.y
      item.itemWidth = position.width
      item.itemHeight = position.height
      moved = moved + 1
    end
  end

  return moved
end

--- The installed buttons, for inspection from the console.
function M.installed()
  return state.items
end

--- Calls and failures per callback, for inspection from the console.
function M.stats()
  return { calls = state.calls, failures = state.failures }
end

return M
