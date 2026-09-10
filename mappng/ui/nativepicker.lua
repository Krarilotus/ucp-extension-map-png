-- Crusader 1.41 PNG dialog. Uses native modal chrome, table stripes, filename
-- input and translated game strings; never calls the game's map save handlers.
local paths = require("mappng.paths")
local Picker = require("mappng.ui.picker")
local controls = require("mappng.ui.controls")
local artwork = require("mappng.ui.artwork")
local png = require("mappng.png")
local actions = require("mappng.actions")
local i18n = require("mappng.ui.i18n")
local layout = require("mappng.ui.pickerlayout")
local M = {}
local state = { anchors = {} }

local function guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not state.failed then
      state.failed = true
      log(ERROR, "map-png: PNG dialog: " .. tostring(err))
    end
  end
end

local function callback(ctype, fn)
  local value = state.ffi.cast(ctype, guard(fn))
  state.anchors[#state.anchors + 1] = value
  return value
end

local function nativeText(index)
  local r = state.game.Rendering
  return r.getTextStringInGroupAtOffset(r.textManager, 74, index)
end

local function text(value, x, y, size)
  local r = state.game.Rendering
  r.renderTextToScreenConst(r.textManager, value, x, y, 0, 0xCCFAFF, size or 18, false, 0)
end

local function boundedText(value, x, y, width)
  -- Native filename truncation; never shorten the model's actual path.
  local key = tostring(width) .. ":" .. value
  local buffer = state.textCache[key]
  if not buffer then
    buffer = state.ffi.new("char[?]", #value + 1)
    state.ffi.copy(buffer, value, #value)
    state.trimText(state.game.Rendering.textManager, buffer, width, 18)
    state.textCache[key] = buffer
  end
  text(buffer, x, y)
end

local function actionText()
  return paths.toGameText(i18n.action(state.model.mode, state.model.what))
end

local function refreshPreview(name)
  state.preview, state.previewError = nil, nil
  if state.model.mode == "import" and not name then return end
  if not name and state.exportPreview then state.preview = state.exportPreview; return end
  local ok, result = pcall(function()
    local image
    if name then image = png.readRGB(state.png, paths.resolve(state.model.folder, name))
    else image = actions.preview(state.model.what) end
    assert(image.width == 400 and image.height == 400, "map-png: expected a 400x400 PNG")
    return artwork.preview(image, 160, 160)
  end)
  if ok then
    state.preview = result
    if not name then state.exportPreview = result end
  else
    state.previewError = i18n.message("invalid")
    log(WARNING, "map-png: PNG preview: " .. tostring(result))
  end
end

local function setName(name)
  name = paths.toGameText(name)
  local input = state.input[0]
  assert(#name < 250, "filename too long for the game input")
  state.ffi.fill(input.text[2], 250, 0)
  state.ffi.copy(input.text[2], name, #name)
  input.length[2], input.cursor[2] = #name, #name
  state.lastInput = name
end

local function restoreInput()
  if state.savedInput then
    state.ffi.copy(state.input, state.savedInput, 4372)
    state.savedInput = nil
  end
end

function M.update()
  if state.active and state.modalStack[0] ~= state.id then
    local done = state.done
    state.active, state.done = false, nil
    restoreInput()
    if done then done(nil) end
  end
end

local function finish(name, notify)
  local done = state.done
  state.active, state.done = false, nil
  state.pop(state.menuInput)
  restoreInput()
  if done and notify ~= false then done(name) end
end

local function syncName()
  if state.model.mode == "export" then
    local name = state.ffi.string(state.input[0].text[2])
    if name ~= state.lastInput then
      state.model:edit(paths.fromGameText(name))
      state.lastInput = name
      state.status = nil
      refreshPreview(nil)
    end
  end
end

local function confirm()
  syncName()
  local name, status = state.model:confirm(paths.exists)
  state.status = status
  if name then
    if state.model.mode == "import" and state.previewError then
      state.status = "invalid_png"
      return
    end
    -- Keep the selection and filename available when conversion fails.
    local ok, accepted = pcall(state.done, name)
    if not ok or accepted == false then state.status = "invalid_png"; return end
    finish(nil, false)
  end
end

function M.initialize(ffi, game, manager, pngBound)
  state.png = pngBound
  if state.ready then return end
  state.ffi, state.game = ffi, game
  i18n.initialize(ffi, game)
  -- Fixed addresses are intentionally limited to the verified 1.41 build.
  -- Refuse mismatched code before constructing a menu or accessing globals.
  local function bind(address, prefix, ctype)
    assert((core.readInteger(address) & 0xFFFFFFFF) == prefix, "map-png: unsupported PNG dialog game code")
    return ffi.cast(ctype, address)
  end
  state.banner = bind(0x468FE0, 0x08244483, "void (__thiscall *)(void *,int,int,int,int)")
  state.inputRender = bind(0x4932E0, 0xED31ACA1, "void (__cdecl *)(int)")
  -- The remaining bindings are checked against the same normal-game image.
  state.rowBackground = bind(0x4692E0, 0x31A80D8B, "void (__thiscall *)(void *,int,int,int)")
  state.scrollRender = bind(0x492C60, 0x1024448B, "void (__cdecl *)(int,int,int,int,bool)")
  state.arrowRender = bind(0x469290, 0x04247C83, "void (__thiscall *)(void *,int,int)")
  state.trimText = bind(0x469F50, 0x0824448B, "void (__thiscall *)(void *,char *,int,int)")
  state.activate = bind(0x4916C0, 0x83F18B56, "void (__thiscall *)(void *,int)")
  state.pop = bind(0x493900, 0x8B64418B, "void (__thiscall *)(void *)")
  ffi.cdef([[
    typedef struct MapPngUserText {
      int index, changed, returned, enabled;
      int fonts[16], maximum[16], length[16], cursor[16], width[16];
      char text[16][250]; char pending[30]; char padding[2]; int pendingIndex;
    } MapPngUserText;
  ]])
  assert(ffi.sizeof("MapPngUserText") == 4372)
  state.input = ffi.cast("MapPngUserText *", 0x1652740)
  state.menuInput = ffi.cast("void *", 0x11265A8)
  state.modalStack = ffi.cast("int *", 0x1126604)
  state.id = manager.getAvailableModalMenuID(2080)
  local items = {}
  local function item(x, y, width, height, draw, click)
    local render = callback("void (__cdecl *)(int)", function()
      if not state.active then return end
      local r = game.Rendering
      controls.onMenuSurface(r, function() draw(r.ButtonState) end)
    end)
    local action = callback("void (__cdecl *)(int)", function()
      if state.active then click() end
    end)
    local number = ffi.tonumber or tonumber
    items[#items + 1] = controls.item({x=x, y=y, width=width, height=height},
      number(ffi.cast("unsigned long", render)), number(ffi.cast("unsigned long", action)))
  end
  item(28, 270, 264, 32, function(b)
    if state.model.mode == "export" then state.inputRender(0)
    elseif state.model.name ~= "" then boundedText(paths.toGameText(state.model.name), b.x + 8, b.y + 7, 248) end
  end, function() end)
  local function button(x, y, w, label, click)
    item(x, y, w, 28, function(b)
      game.Rendering.renderButtonBackground(game.Rendering.alphaAndButtonSurface, 0, 0)
      local value = label()
      if type(value) ~= "string" then value = state.ffi.string(value) end
      boundedText(value, b.x + 8, b.y + 6, w - 16)
    end, click)
  end
  button(28, 344, 264, function()
    return state.status == "overwrite" and nativeText(22) or actionText()
  end, confirm)
  button(28, 382, 264, function() return nativeText(17) end, function() finish(nil) end)
  item(layout.listX, layout.listY, layout.listWidth, layout.rowHeight, function(b)
    state.rowBackground(game.Rendering.pencilRenderCore, 0, 1, 0)
    text(nativeText(27), b.x + 8, b.y + 3)
  end, function() end)
  for row = 1, layout.pageSize do
    item(layout.listX, layout.rowsY + (row - 1) * layout.rowHeight, layout.listWidth, layout.rowHeight, function(b)
      local name = state.model.names[state.model.offset + row]
      state.rowBackground(game.Rendering.pencilRenderCore,
        name and name == state.model.name and 1 or 0, row, 0)
      if name then boundedText(paths.toGameText(name), b.x + 8, b.y + 3, layout.listWidth - 16) end
    end, function()
      local name = state.model:select(row)
      state.status = nil
      if name and state.model.mode == "export" then setName(name) end
      if name then refreshPreview(name) end
    end)
  end
  local scrollAction = callback("void (__cdecl *)(int,int,int *,int *,int *)",
    function(_, event, minimum, maximum, current)
      if state.model then state.model:nativeScroll(event, minimum, maximum, current) end
    end)
  local number = ffi.tonumber or tonumber
  local scrollbar = controls.item({x=layout.scrollX, y=layout.trackY,
    width=layout.scrollWidth, height=layout.trackHeight},
    number(ffi.cast("unsigned long", state.scrollRender)),
    number(ffi.cast("unsigned long", scrollAction)))
  scrollbar.menuItemType, scrollbar.menuItemRenderFunctionType = 6, 4
  items[#items + 1] = scrollbar
  for _, direction in ipairs({-1, 1}) do
    item(layout.scrollX, direction == -1 and layout.rowsY or layout.bottom - layout.rowHeight,
      layout.scrollWidth, layout.rowHeight, function()
        state.arrowRender(game.Rendering.pencilRenderCore, direction == -1 and 1 or 0, 0)
      end, function() state.model:scroll(direction) end)
  end
  items[#items + 1] = { menuItemType = 0x66 }
  -- cffi-lua does not accept LuaJIT's nested table array initializer here.
  -- Assign each struct separately, as the UI module's insertMenuItem does.
  state.items = ffi.new("MenuItem[?]", #items)
  for i, value in ipairs(items) do
    state.items[i - 1] = value
    if value.menuItemType ~= 0x66 then controls.verify(state.items[i - 1]) end
  end
  state.menu = ffi.new("Menu[1]")
  game.UI.Menu(state.menu, state.items)
  for i = 0, #items - 2 do state.items[i].menuPointer = state.menu end
  state.modal = ffi.new("struct MenuModal[1]")
  state.render = callback("void (__cdecl *)(int,int,int,int)", function(x, y, w, h)
    if not state.active then return end
    syncName()
    local r = game.Rendering
    controls.onMenuSurface(r, function()
      -- Own the content area: vanilla LoadMap paints the GAME'S cached map
      -- preview here, so reusing that renderer is incorrect for PNG selection.
      r.drawColorBox(r.pencilRenderCore, x + 6, y + 6, x + w - 6, y + h - 6, 0)
      controls.dialogHeading(r, state.banner, actionText(), x, y, w)
      r.drawBorderBox(r.pencilRenderCore, x + layout.listX - 1, y + layout.listY - 1,
        x + layout.scrollX + layout.scrollWidth, y + layout.bottom,
        r.Colors.pGreyishYellow[0])
      if state.preview then
        artwork.drawPreview(state.preview, r, x + 80, y + 86)
      else
        text(paths.toGameText(state.previewError or i18n.message("select")), x + 34, y + 154)
      end
      if state.status == "overwrite" then text(nativeText(30), x + 28, y + 316) end
      if state.status == "invalid_name" or state.status == "missing_file" then
        text(paths.toGameText(i18n.message(state.status == "invalid_name" and "name" or "select")), x + 28, y + 316)
      end
      if state.status == "invalid_png" then text(paths.toGameText(i18n.message("invalid")), x + 28, y + 316) end
    end)
    if state.input[0].returned ~= 0 then
      state.input[0].returned = 0
      -- Never let a held Return key accept an overwrite confirmation.
      if state.status ~= "overwrite" then confirm() end
    end
  end)
  game.UI.MenuModal(state.modal, state.id, -1, -1, layout.width, layout.height, 512, 0, state.render, state.menu)
  state.ready = true
end

function M.open(mode, what, folder, defaultName, done)
  assert(state.ready, "map-png: PNG picker is not initialized")
  if state.active then return end
  assert(state.modalStack[0] == 0, "map-png: another dialog is open")
  state.model = Picker.new(mode, what, folder, paths.listPngs(folder), defaultName)
  state.textCache = {}
  state.exportPreview = nil
  state.savedInput = state.ffi.new("unsigned char[4372]")
  state.ffi.copy(state.savedInput, state.input, 4372)
  state.activate(state.menuInput, state.id)
  state.input[0].index, state.input[0].changed = 2, 1
  state.input[0].returned, state.input[0].pendingIndex = 0, 0
  state.input[0].enabled = mode == "export" and 1 or 0
  state.input[0].fonts[2], state.input[0].maximum[2], state.input[0].width[2] = 18, 120, 234
  setName(state.model.name)
  refreshPreview(nil)
  state.done, state.status, state.active, state.failed = done, nil, true, false
end

function M.cancel()
  if state.active then finish(nil) end
  state.preview, state.exportPreview = nil, nil
end

return M
