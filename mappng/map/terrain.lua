--- mappng/map/terrain.lua
---
--- Terrain layers <-> colour image.
---
--- Equivalent to `sourcehold memory map get/set terrain`: logic1 is section
--- 1003 (`LogicLayer`, one int per tile) and logic2 is section 1037
--- (`Logic2Layer`, one byte per tile).
---
--- Export paints logic1 flags in a fixed order, later flags overwriting
--- earlier ones, then overlays logic2 values wherever logic1 has
--- `default_earth_or_texture` set. Import rebuilds logic1 from scratch, keeping
--- only the map borders from the live map, exactly as `set_terrain` does --
--- the border flags describe the playable area and are not something a user
--- should be able to repaint by hand.

local diamond = require("mappng.map.diamond")
local palette = require("mappng.map.palette")

local M = {}

local BLACK = palette.packRGB(0, 0, 0)

--- Reads the terrain layers into a colour image.
---
---@param layers table needs `logic1` (int) and `logic2` (byte), both 0-based
---@param lookup table serialized tile index -> square pixel index
---@param resolved table result of palette.resolve()
---@param size number|nil square width, defaults to 400
---@return table image { width, height, rgb } with `rgb` 0-based packed 0xRRGGBB
function M.export(layers, lookup, resolved, size)
  size = size or diamond.SIZE

  local rgb = {}
  for pixel = 0, (size * size) - 1 do
    rgb[pixel] = BLACK
  end

  local logic1, logic2 = layers.logic1, layers.logic2
  local tileCount = diamond.tileCount(size)

  -- Pass 1: logic1 flags, in paint order.
  for _, entry in ipairs(palette.logic1PaintOrder) do
    local colour = resolved.nameToColour[entry.name]
    local packed = colour and colour.key or BLACK
    local flag = entry.flag
    for tile = 0, tileCount - 1 do
      if (logic1[tile] & flag) ~= 0 then
        rgb[lookup[tile]] = packed
      end
    end
  end

  -- Pass 2: logic2, only where logic1 says "default earth or texture".
  local earth = palette.logic1.default_earth_or_texture
  for _, entry in ipairs(palette.logic2PaintOrder) do
    local colour = resolved.nameToColour[entry.name]
    local packed = colour and colour.key or BLACK
    local value = entry.value
    for tile = 0, tileCount - 1 do
      if (logic1[tile] & earth) ~= 0 and logic2[tile] == value then
        rgb[lookup[tile]] = packed
      end
    end
  end

  return { width = size, height = size, rgb = rgb }
end

--- Writes a colour image into the terrain layers.
---
--- Returns a report so the caller can tell the user what happened rather than
--- corrupting a map silently the way the Python original does.
---
---@param layers table needs `logic1` (int) and `logic2` (byte), both 0-based
---@param lookup table serialized tile index -> square pixel index
---@param image table { width, height, rgb }
---@param resolved table result of palette.resolve()
---@param size number|nil square width, defaults to 400
---@return table report { unknownColours, unknownSample, tilesWritten }
function M.import(layers, lookup, image, resolved, size)
  size = size or diamond.SIZE

  if image.width ~= size or image.height ~= size then
    error(string.format(
      "terrain map must be %dx%d, got %dx%d",
      size, size, image.width, image.height))
  end

  local logic1, logic2 = layers.logic1, layers.logic2
  local rgb = image.rgb
  local tileCount = diamond.tileCount(size)

  local border = palette.logic1.border
  local borderEdge = palette.logic1.border_edge
  local borderMask = border | borderEdge

  local unknownColours, unknownSample, tilesWritten = 0, nil, 0

  for tile = 0, tileCount - 1 do
    local existing = logic1[tile]

    -- Keep the map borders; a tile that was empty stays empty.
    local newLogic1, newLogic2
    if existing == 0 then
      newLogic1, newLogic2 = 0, 0
    else
      newLogic1, newLogic2 = existing & borderMask, 0
    end

    local packed = rgb[lookup[tile]]
    local name = resolved.colourToName[packed]
    if name ~= nil then
      newLogic1 = newLogic1 | (palette.logic1[name] or 0)
      newLogic2 = palette.logic2[name] or 0
    elseif packed ~= BLACK then
      unknownColours = unknownColours + 1
      if unknownSample == nil then
        unknownSample = { pixel = lookup[tile], colour = packed }
      end
    end

    logic1[tile] = newLogic1
    logic2[tile] = newLogic2
    tilesWritten = tilesWritten + 1
  end

  return {
    unknownColours = unknownColours,
    unknownSample = unknownSample,
    tilesWritten = tilesWritten,
  }
end

return M
