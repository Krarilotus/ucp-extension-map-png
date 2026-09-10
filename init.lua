--- map-png
---
--- Import and export the live Stronghold Crusader map as PNG files, from four
--- buttons under the minimap on the map editor screen.
---
--- This replaces shelling out to `sourcehold memory map get/set`: that tool has
--- to attach to the game from outside with pymem, which is why it needs Python,
--- numpy and OpenCV. Running inside the process, the same map layers are plain
--- pointer dereferences and PNG is handled by gdiplus.dll, which Windows already
--- ships. Nothing is bundled.

local gdiplus = require("mappng.png.gdiplus")
local paths = require("mappng.paths")
local actions = require("mappng.actions")
local tilemap = require("mappng.map.tilemap")
local screens = require("mappng.ui.screens")
local icons = require("mappng.ui.icons")
local buttons = require("mappng.ui.buttons")
local filedialog = require("mappng.ui.filedialog")

local mappng = {}

local state = {}

--- The build the button layout globals were read from.
local LAYOUT_BUILD = "Crusader 1.41"

--- Reads the current map name, for the default file name in the save dialog.
--- TODO(discovery): read it from MapPropertiesState instead of guessing.
local function currentMapName()
  return nil
end

--- Runs one of the four actions: ask for a name, then do the work.
local function onClick(mode, what)
  filedialog.pick(mode, what, currentMapName(), function(name)
    if name == nil then
      return
    end

    local ok, result = pcall(actions.run, mode, what, name, {
      snapshot = state.options.snapshotBeforeImport,
    })

    if ok then
      log(INFO, string.format("map-png: %s %s -> %s", mode, what, tostring(result)))
    else
      log(ERROR, string.format("map-png: %s %s failed: %s", mode, what, tostring(result)))
    end
    return ok, result
  end)
end

function mappng:enable(config)
  config = config or {}

  state.options = {
    folder = config["mapping-folder"] or paths.DEFAULT_FOLDER,
    paletteName = config["palette"] or "mappng",
    snapshotBeforeImport = config["snapshot-before-import"] ~= false,
  }

  ---@type CFFIInterface
  local ffi = modules.cffi:cffi()
  state.ffi = ffi

  paths.initialize(ffi)
  state.png = gdiplus.initialize(ffi)

  actions.initialize(ffi, state.png, state.options)
  log(INFO, string.format("map-png: using %s", actions.folder()))

  hooks.registerHookCallback("afterInit", function()
    -- The section table is static data, so this is valid from process start.
    local ok, base, build = pcall(tilemap.resolveBase, core)
    if ok then
      log(INFO, string.format("map-png: %s, TileMapState at 0x%X", build, base))
    else
      log(WARNING, string.format("map-png: map layers not found: %s", tostring(base)))
    end

    -- Do not install unusable controls or touch layout globals on another build.
    local layoutKnown = ok and build == LAYOUT_BUILD
    screens.setGlobalsAvailable(layoutKnown)
    if not layoutKnown then
      log(WARNING, "map-png: native PNG controls require " .. LAYOUT_BUILD)
      return
    end

    icons.load()

    local ui = modules.ui:access()
    if layoutKnown then filedialog.initialize(ffi, ui, state.png) end
    local game = ui.game
    local added = buttons.install(ffi, game, onClick)
    if added == 0 then
      log(WARNING, "map-png: no buttons were added; see the errors above")
    end
  end)
end

function mappng:disable()
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
