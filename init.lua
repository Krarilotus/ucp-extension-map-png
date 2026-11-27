--- map-png
---
--- Import and export the live Stronghold Crusader map as PNG files, with linked
--- refresh under the minimap on the map editor screen.
---
--- This replaces shelling out to `sourcehold memory map get/set`: that tool has
--- to attach to the game from outside with pymem, which is why it needs Python,
--- numpy and OpenCV. Running inside the process, the same map layers are plain
--- pointer dereferences and PNG is handled by gdiplus.dll, which Windows already
--- ships. Nothing is bundled.

local gdiplus = require("mappng.png.gdiplus")
local paths = require("mappng.paths")
local palette = require("mappng.map.palette")
local actions = require("mappng.actions")
local tilemap = require("mappng.map.tilemap")
local screens = require("mappng.ui.screens")
local icons = require("mappng.ui.icons")
local buttons = require("mappng.ui.buttons")
local filedialog = require("mappng.ui.filedialog")
local lifecycle = require('mappng.lifecycle')

local mappng = {}

local state = {}

--- Runs one of the four actions: ask for a name, then do the work.
local function onClick(mode, what)
  if mode=='refresh' then
    local ok,err=pcall(lifecycle.refresh)
    if not ok then log(ERROR,'refresh failed: '..tostring(err)) end
    return
  end
  filedialog.pick(mode, what, nil, function(name)
    if name == nil then
      return
    end

    local ok, result = pcall(actions.run, mode, what, name)

    if ok then
      if mode=='import' then lifecycle.link(what,name) end
      log(INFO, string.format("%s %s -> %s", mode, what, tostring(result)))
    else
      log(ERROR, string.format("%s %s failed: %s", mode, what, tostring(result)))
    end
    return ok, result
  end)
end

function mappng:enable(config)
  if config ~= nil and type(config) ~= "table" then
    log(ERROR, "Map PNG settings must be a table; using defaults.")
    config = nil
  end
  config = config or {}

  local folder = config["mapping-folder"]
  if folder ~= nil and not paths.isFolderName(folder) then
    log(type(folder) == "string" and WARNING or ERROR,
      "Invalid Map PNG mapping-folder; using " .. paths.DEFAULT_FOLDER .. ".")
    folder = nil
  end
  local paletteName = config.palette
  if paletteName ~= nil and (type(paletteName) ~= "string" or not palette.palettes[paletteName]) then
    log(type(paletteName) == "string" and WARNING or ERROR,
      "Invalid Map PNG palette; using " .. palette.DEFAULT_PALETTE .. ".")
    paletteName = nil
  end

  ---@type CFFIInterface
  local ffi
  local ready, reason = pcall(function()
    ffi = modules.cffi:cffi()
    paths.initialize(ffi)
    state.png = gdiplus.initialize(ffi)
    actions.initialize(ffi, state.png, {folder = folder, paletteName = paletteName})
    log(INFO, string.format("using %s", actions.folder()))
  end)
  if not ready then
    gdiplus.shutdown(state.png)
    state.png = nil
    log(ERROR, "PNG map editor controls are off: " .. tostring(reason))
    return
  end

  hooks.registerHookCallback("afterInit", function()
    local ready, game = pcall(function()
      local base, build = tilemap.resolveBase(core)
      icons.load()
      screens.configure(require('mappng.native').resolve().preview)
      local ui = modules.ui:access()
      filedialog.initialize(ffi, ui, state.png)
      log(INFO, string.format("%s, TileMapState at 0x%X", build, base))
      return ui.game
    end)
    if not ready then
      log(ERROR, "PNG map editor controls are off: " .. tostring(game))
      return
    end
    local linked, err = pcall(lifecycle.initialize, actions.folder())
    if not linked then
      log(ERROR, "Automatic refresh of linked PNG maps is off: " .. tostring(err))
    end
    local installed, added = pcall(buttons.install, ffi, game, onClick)
    if not installed then
      log(ERROR, "PNG map editor controls are off: " .. tostring(added))
    elseif added == 0 then
      log(WARNING, "no buttons were added; see the errors above")
    end
  end)
end

function mappng:disable()
  lifecycle.disable()
  buttons.disable()
  filedialog.cancel()
  icons.unload()
  gdiplus.shutdown(state.png)
  state.png = nil
end

--- Exposed so the operations can be driven from the UCP console before the UI
--- is finished, and for checking the button placement.
function mappng:access()
  return {
    actions = actions,
    screens = screens,
    buttons = buttons,
    icons = icons,
    filedialog = filedialog,
  }
end

return mappng, {
  proxy = {
    ignored = { "access" },
  },
}
