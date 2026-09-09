--- mappng/map/tilemap.lua
---
--- Locates the live map layers in the game process and hands back typed views.
---
--- Two independent sources are used and cross-checked against each other:
---
--- 1. The map-section address table at `SECTION_TABLE_START`, an array of
---    16-byte `MapSectionAddress` records (`address, unknown, size,
---    compressed, sectionId`). This is what `sourcehold` walks from outside
---    the process. Data-driven, so it survives the game moving its
---    allocations around.
---
--- 2. The `TileMapState` singleton layout from OpenSHC
---    (`OpenSHC/Map/TileMapState.hpp`), which gives each layer a fixed offset
---    from a single base.
---
--- The two agree: `sourcehold` hardcodes `futureMapOrientation = 0x01FE7AA8`,
--- and OpenSHC puts `DAT_TileMapState` at `0x01A93208` with
--- `DAT_FutureMapOrientation` at `+0x5548A0` -- which is exactly `0x01FE7AA8`.
--- Deriving the base from the section table and asserting it matches every
--- layer offset means a version mismatch fails loudly instead of writing 80400
--- tiles into the wrong allocation.

local M = {}

-- Stronghold Crusader 1.41 (western). Same constants sourcehold uses in
-- `read_address_list_shc`.
M.SECTION_TABLE_START = 0x00B92A58
M.SECTION_TABLE_END = 0x00B93208
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

--- Reads the map-section address table.
---@param core table the UCP core API
---@return table sectionId -> { address = number, size = number }
function M.readSectionTable(core)
  local sections = {}
  local address = M.SECTION_TABLE_START
  while address < M.SECTION_TABLE_END do
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

--- Derives the TileMapState base from the section table and verifies that every
--- layer we care about lands where OpenSHC says it should.
---
---@param core table the UCP core API
---@return number base
function M.resolveBase(core)
  local sections = M.readSectionTable(core)

  local base
  for sectionId, spec in pairs(M.SECTIONS) do
    local section = sections[sectionId]
    if section == nil then
      error(string.format(
        "map-png: section %d is missing from the section table at 0x%X; "
        .. "this build of Stronghold Crusader is not supported",
        sectionId, M.SECTION_TABLE_START))
    end
    if section.size ~= spec.size then
      error(string.format(
        "map-png: section %d has size %d, expected %d",
        sectionId, section.size, spec.size))
    end

    local candidate = section.address - M.OFFSETS[spec.field]
    if base == nil then
      base = candidate
    elseif base ~= candidate then
      error(string.format(
        "map-png: section %d implies TileMapState base 0x%X but an earlier "
        .. "section implied 0x%X; refusing to write",
        sectionId, candidate, base))
    end
  end

  return base
end

--- Builds FFI views of the four layers plus the redraw flags.
---
---@param core table the UCP core API
---@param ffi table the cffi interface
---@return table view
function M.open(core, ffi)
  local base = M.resolveBase(core)

  local function at(field, ctype)
    return ffi.cast(ctype, base + M.OFFSETS[field])
  end

  return {
    base = base,
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
