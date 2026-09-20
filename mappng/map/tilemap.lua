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
--- UCP discovers the section table and native map base independently by AoB.
--- Neither executable names nor a list of known addresses gate compatibility.
--- The four layer sizes/offsets must still agree with the discovered native ABI.

local M = {}

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
    if record.address == 0 then break end
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

--- Validate discovered sections against independently discovered native code.
---
---@param core table the UCP core API
---@return number base, string build name of the table that matched
function M.resolveBase(core)
  local native = require('mappng.native').resolve()
  -- The native reader bounds this list to 150 records; zero terminates it.
  local sections = M.readSectionTable(core, native.sections,
    native.sections + 150 * M.SECTION_RECORD_SIZE)
  local base, problem = deriveBase(sections)
  assert(base and base == native.base, 'map-png: refusing to touch the map: '
    .. (problem or 'native code and map sections disagree'))
  return base, 'AoB-validated Crusader layout'
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
