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
local cleanup = require("mappng.map.cleanup")

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

function M.preview(what)
  if what == "height" then return height.export(view().layers, state.lookup, diamond.SIZE) end
  assert(what == "terrain", "unknown preview layer")
  return terrain.export(view().layers, state.lookup, state.palette, diamond.SIZE)
end

--- Allocate typed staging buffers before touching live data.
local function stage(kind, layers)
  local ffi = state.ffi
  local saved = {}
  local fields = kind == "height" and { "defaultHeight", "height" } or { "logic1", "logic2" }
  for _, field in ipairs(fields) do
    local source = layers[field]
    -- Explicit, because indexing a layer yields a plain Lua number, which
    -- ffi.sizeof cannot size. LogicLayer is int32; the others are bytes.
    local elementSize = (field == "logic1") and 4 or 1
    local copy = ffi.new(field == 'logic1' and 'int32_t[?]' or 'uint8_t[?]', diamond.TILE_COUNT)
    ffi.copy(copy, source, diamond.TILE_COUNT * elementSize)
    saved[field] = { data = copy, bytes = diamond.TILE_COUNT * elementSize }
  end
  local staged = {}
  for field, entry in pairs(saved) do staged[field] = entry.data end
  return staged, saved
end

-- One transaction boundary for both imports: decode/convert before touching
-- live objects, native cleanup, verify, then commit only the selected layer.
local function importImages(images)
  local v = view()
  local staged, buffers, reports = {}, {}, {}
  for _, kind in ipairs({'height', 'terrain'}) do
    if images[kind] then
      local layers, allocated = stage(kind, v.layers)
      if kind == 'height' then height.import(layers, state.lookup, images[kind], diamond.SIZE)
      else reports.terrain = terrain.import(layers, state.lookup, images[kind], state.palette, diamond.SIZE) end
      for field, entry in pairs(allocated) do
        buffers[field], staged[field] = entry, entry.data
      end
    end
  end
  local remove = cleanup.prepare(core, state.ffi, v, staged)
  -- A layer-only undo cannot resurrect deleted objects safely.
  state.snapshots = {}
  local ok, err = pcall(remove)
  if ok then
    for field, entry in pairs(buffers) do state.ffi.copy(v.layers[field], entry.data, entry.bytes) end
  end
  refresh.invalidate(v, { changedLayer = true })
  if not ok then error(err, 0) end
  return reports
end

-- Decode ALL linked images before converting or deleting anything. Refresh and
-- the picker share this transaction; callers update links only after success.
function M.importLinked(names)
  assert(type(names) == 'table' and (names.height or names.terrain), 'map-png: no linked PNGs')
  local images, resolved = {}, {}
  for _, kind in ipairs({'height', 'terrain'}) do
    if names[kind] then
      local path = paths.resolve(state.folder, names[kind])
      resolved[kind] = path
      images[kind] = kind == 'height' and png.readGray(state.png, path) or png.readRGB(state.png, path)
    end
  end
  local reports = importImages(images)
  local report = reports.terrain
  if report and report.unknownColours > 0 then
    log(WARNING, string.format(
      'map-png: %d pixel(s) in %s did not match any terrain colour and were left '
      .. 'as empty ground; first at pixel %d, colour #%06X',
      report.unknownColours, resolved.terrain, report.unknownSample.pixel, report.unknownSample.colour))
  end
  return resolved, reports
end

--- Compatibility API: destructive imports invalidate layer-only snapshots.
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
  local resolved = M.importLinked({height=name})
  return resolved.height
end

function M.exportTerrain(name)
  local path = paths.resolve(state.folder, name)
  local image = terrain.export(view().layers, state.lookup, state.palette, diamond.SIZE)
  png.writeRGB(state.png, path, image)
  return path
end

function M.importTerrain(name, options)
  local resolved, reports = M.importLinked({terrain=name})
  return resolved.terrain, reports.terrain
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
