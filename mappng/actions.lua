--- mappng/actions.lua
---
--- The four operations, tying the map layers, the PNG codec and the folder
--- together. This is the layer the buttons call.

local diamond = require("mappng.map.diamond")
local paletteModule = require("mappng.map.palette")
local tilemap = require("mappng.map.tilemap")
local refresh = require("mappng.map.refresh")
local height = require("mappng.map.height")
local terrain = require("mappng.map.terrain")
local png = require("mappng.png")
local paths = require("mappng.paths")

local M = {}

local state = {}

--- @param options table { paletteName, folder }
function M.initialize(ffi, gdiplusBound, options)
  state.ffi = ffi
  state.png = gdiplusBound
  state.lookup = diamond.buildTileToPixel(diamond.SIZE)
  state.palette = paletteModule.resolve(options.paletteName or paletteModule.DEFAULT_PALETTE)
  state.folder = paths.ensurePngFolder(options.folder)
  state.snapshots = {}
end

function M.folder()
  return state.folder
end

--- Opens a view of the live map, failing clearly if there is not one.
local function view()
  local ok, result = pcall(tilemap.open, core, state.ffi)
  if not ok then
    error(result, 0)
  end
  return result
end

--- Keeps one level of undo for an import.
local function snapshot(kind, layers)
  local ffi = state.ffi
  local saved = {}
  local fields = kind == "height" and { "defaultHeight", "height" } or { "logic1", "logic2" }
  for _, field in ipairs(fields) do
    local source = layers[field]
    local elementSize = ffi.sizeof(source[0])
    local copy = ffi.new("uint8_t[?]", diamond.TILE_COUNT * elementSize)
    ffi.copy(copy, source, diamond.TILE_COUNT * elementSize)
    saved[field] = { data = copy, bytes = diamond.TILE_COUNT * elementSize }
  end
  state.snapshots[kind] = saved
end

--- Restores the snapshot taken before the last import of `kind`.
function M.undo(kind)
  local saved = state.snapshots[kind]
  if saved == nil then
    return false
  end

  local layers = view().layers
  for field, entry in pairs(saved) do
    state.ffi.copy(layers[field], entry.data, entry.bytes)
  end
  refresh.invalidate(view())
  state.snapshots[kind] = nil
  return true
end

---@param name string bare file name, without a path
function M.exportHeight(name)
  local path = paths.resolve(state.folder, name)
  local image = height.export(view().layers, state.lookup, diamond.SIZE)
  png.writeGray(state.png, path, image)
  return path
end

function M.importHeight(name, options)
  options = options or {}
  local path = paths.resolve(state.folder, name)
  local image = png.readGray(state.png, path)

  local v = view()
  if options.snapshot then
    snapshot("height", v.layers)
  end
  height.import(v.layers, state.lookup, image, diamond.SIZE)
  refresh.invalidate(v, { changedLayer = true })

  return path
end

function M.exportTerrain(name)
  local path = paths.resolve(state.folder, name)
  local image = terrain.export(view().layers, state.lookup, state.palette, diamond.SIZE)
  png.writeRGB(state.png, path, image)
  return path
end

function M.importTerrain(name, options)
  options = options or {}
  local path = paths.resolve(state.folder, name)
  local image = png.readRGB(state.png, path)

  local v = view()
  if options.snapshot then
    snapshot("terrain", v.layers)
  end
  local report = terrain.import(v.layers, state.lookup, image, state.palette, diamond.SIZE)
  refresh.invalidate(v, { changedLayer = true })

  if report.unknownColours > 0 then
    log(WARNING, string.format(
      "map-png: %d pixel(s) in %s did not match any terrain colour and were left "
      .. "as empty ground; first at pixel %d, colour #%06X",
      report.unknownColours, path,
      report.unknownSample.pixel, report.unknownSample.colour))
  end

  return path, report
end

--- Dispatch used by the buttons.
---@param mode string "import" or "export"
---@param what string "height" or "terrain"
function M.run(mode, what, name, options)
  if mode == "export" and what == "height" then
    return M.exportHeight(name)
  elseif mode == "import" and what == "height" then
    return M.importHeight(name, options)
  elseif mode == "export" and what == "terrain" then
    return M.exportTerrain(name)
  elseif mode == "import" and what == "terrain" then
    return M.importTerrain(name, options)
  end
  error(string.format("map-png: unknown action %s/%s", tostring(mode), tostring(what)))
end

--- Default file name offered by the save dialog, following the
--- `<map>_height.png` / `<map>_tex.png` convention.
function M.defaultName(mapName, what)
  local base = (mapName ~= nil and mapName ~= "") and mapName or "map"
  base = base:gsub("[\\/:%*%?\"<>|]", "_")
  return base .. (what == "height" and "_height" or "_tex")
end

return M
