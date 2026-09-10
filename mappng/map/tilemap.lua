--- mappng/map/tilemap.lua
---
--- Locates the live map layers in the game process and hands back typed views.
---
--- Two independent sources are used and cross-checked against each other:
---
--- 1. The map-section address table, an array of 16-byte `MapSectionAddress`
---    records (`address, unknown, size, compressed, sectionId`). This is what
---    `sourcehold` walks from outside the process. The table is static data in
---    `.data`, so it can also be checked against the exe on disk -- see
---    tests/test_tilemap_binary.py.
---
--- 2. The `TileMapState` singleton layout from OpenSHC
---    (`OpenSHC/Map/TileMapState.hpp`), which gives each layer a fixed offset
---    from a single base.
---
--- The base is derived from the table and every layer offset must agree with
--- it. For Crusader 1.41 that lands on OpenSHC's `0x01A93208`, and sourcehold's
--- hardcoded `futureMapOrientation = 0x01FE7AA8` is exactly that base plus
--- `+0x5548A0`.
---
--- Crusader Extreme 1.41.1-E has the identical `TileMapState` layout, relocated
--- to `0x02526708`; its section table is a different address. Each known table
--- is tried in turn and accepted only if it passes the full cross-check, so
--- trying one on the wrong executable fails safe instead of writing 80400 tiles
--- into the wrong allocation.

local M = {}

-- Same constants sourcehold uses in read_address_list_shc / _shce.
M.SECTION_TABLES = {
  { name = "Crusader 1.41", start = 0x00B92A58, stop = 0x00B93208 },
  { name = "Crusader Extreme 1.41.1-E", start = 0x00B92BE8, stop = 0x00B93398 },
}
M.SECTION_RECORD_SIZE = 16

-- Offsets within TileMapState, from OpenSHC.
M.OFFSETS = {
  LogicLayer = 0x00165160,
  Logic2Layer = 0x001B3FE0,
  ChangedLayer = 0x001C7B80,
  HeightLayer = 0x0029FA30,
  DefaultHeightLayer = 0x002B3440,

  forceUpdateLogicalAndMiscDisplayLayers = 0x0055486C,
  forceUpdateTextureTilemap = 0x00554870,
  forceUpdateGFXLayers = 0x00554874,
  forceUpdateMacroLayerFlag = 0x00554878,
  mapOrientation = 0x0055489C,
  futureMapOrientation = 0x005548A0,
}

-- sectionId -> { offset into TileMapState, expected byte length }
M.SECTIONS = {
  [1003] = { field = "LogicLayer", size = 321600 },
  [1037] = { field = "Logic2Layer", size = 80400 },
  [1005] = { field = "HeightLayer", size = 80400 },
  [1045] = { field = "DefaultHeightLayer", size = 80400 },
}

--- OpenSHC puts `DAT_MinimapViewState` immediately before `DAT_TileMapState`:
--- `0x01A93208 - 0x01A31610` is exactly `sizeof(MinimapViewState)`.
M.MINIMAP_VIEW_STATE_SIZE = 0x00061BF8

--- Reads one map-section address table.
---@param core table the UCP core API
---@param start number first record
---@param stop number one past the last record
---@return table sectionId -> { address = number, size = number }
function M.readSectionTable(core, start, stop)
  local sections = {}
  local address = start
  while address < stop do
    local record = {
      address = core.readInteger(address),
      size = core.readInteger(address + 8),
      sectionId = core.readSmallInteger(address + 14),
    }
    if record.sectionId ~= 0 and record.address ~= 0 then
      sections[record.sectionId] = { address = record.address, size = record.size }
    end
    address = address + M.SECTION_RECORD_SIZE
  end
  return sections
end

--- Derives the base from one table, or explains why it cannot.
---@return number|nil base, string|nil problem
local function deriveBase(sections)
  local base
  for sectionId, spec in pairs(M.SECTIONS) do
    local section = sections[sectionId]
    if section == nil then
      return nil, string.format("section %d is missing", sectionId)
    end
    if section.size ~= spec.size then
      return nil, string.format("section %d has size %d, expected %d",
        sectionId, section.size, spec.size)
    end

    local candidate = section.address - M.OFFSETS[spec.field]
    if base == nil then
      base = candidate
    elseif base ~= candidate then
      return nil, string.format(
        "section %d implies base 0x%X but another section implied 0x%X",
        sectionId, candidate, base)
    end
  end
  return base, nil
end

--- Finds the TileMapState base by trying each known section table.
---
---@param core table the UCP core API
---@return number base, string build name of the table that matched
function M.resolveBase(core)
  local problems = {}

  for _, candidate in ipairs(M.SECTION_TABLES) do
    local ok, sections = pcall(M.readSectionTable, core, candidate.start, candidate.stop)
    if ok then
      local base, problem = deriveBase(sections)
      if base ~= nil then
        return base, candidate.name
      end
      problems[#problems + 1] = string.format("%s: %s", candidate.name, problem)
    else
      problems[#problems + 1] = string.format("%s: %s", candidate.name, tostring(sections))
    end
  end

  error("map-png: no known map-section table matches this executable; "
    .. "refusing to touch the map\n  " .. table.concat(problems, "\n  "))
end

--- Address of MinimapViewState for a given TileMapState base.
function M.minimapViewStateAddress(base)
  return base - M.MINIMAP_VIEW_STATE_SIZE
end

--- Builds FFI views of the four layers plus the redraw flags.
---
---@param core table the UCP core API
---@param ffi table the cffi interface
---@return table view
function M.open(core, ffi)
  local base, build = M.resolveBase(core)

  local function at(field, ctype)
    return ffi.cast(ctype, base + M.OFFSETS[field])
  end

  return {
    base = base,
    build = build,
    layers = {
      logic1 = at("LogicLayer", "int32_t *"),
      logic2 = at("Logic2Layer", "uint8_t *"),
      height = at("HeightLayer", "uint8_t *"),
      defaultHeight = at("DefaultHeightLayer", "uint8_t *"),
      changed = at("ChangedLayer", "uint8_t *"),
    },
    flags = {
      logicalAndMiscDisplay = at("forceUpdateLogicalAndMiscDisplayLayers", "int32_t *"),
      textureTilemap = at("forceUpdateTextureTilemap", "int32_t *"),
      gfxLayers = at("forceUpdateGFXLayers", "int32_t *"),
      macroLayer = at("forceUpdateMacroLayerFlag", "int32_t *"),
      mapOrientation = at("mapOrientation", "int32_t *"),
      futureMapOrientation = at("futureMapOrientation", "int32_t *"),
    },
  }
end

return M
