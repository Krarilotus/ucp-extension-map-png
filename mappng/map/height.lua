--- mappng/map/height.lua
---
--- Height layer <-> grayscale image.
---
--- Equivalent to `sourcehold memory map get/set height`, minus the external
--- process: `get_raw_height` reads section 1045 (`DefaultHeightLayer`) and
--- `set_raw_height` writes both 1045 and 1005 (`HeightLayer`).
---
--- Both functions take a `layers` table so they can be exercised against plain
--- Lua arrays in the tests and against FFI views of `TileMapState` in the game.
--- Every index is 0-based, matching the game's arrays.

local diamond = require("mappng.map.diamond")

local M = {}

--- Reads the height layer into a grayscale image.
---
---@param layers table needs `defaultHeight` (0-based, byte-valued)
---@param lookup table serialized tile index -> square pixel index
---@param size number|nil square width, defaults to 400
---@return table image { width, height, gray } with `gray` 0-based
function M.export(layers, lookup, size)
  size = size or diamond.SIZE

  local gray = {}
  for pixel = 0, (size * size) - 1 do
    gray[pixel] = 0 -- outside the diamond stays black, as in sourcehold
  end

  local defaultHeight = layers.defaultHeight
  for tile = 0, diamond.tileCount(size) - 1 do
    gray[lookup[tile]] = defaultHeight[tile]
  end

  return { width = size, height = size, gray = gray }
end

--- Writes a grayscale image into the height layers.
---
--- Pixels outside the diamond are ignored. Values are clamped to 0..255 rather
--- than wrapping, so a 16-bit source PNG that GDI+ handed back at a wider range
--- cannot silently corrupt the terrain.
---
---@param layers table needs `defaultHeight` and `height` (0-based, byte-valued)
---@param lookup table serialized tile index -> square pixel index
---@param image table { width, height, gray }
---@param size number|nil square width, defaults to 400
function M.import(layers, lookup, image, size)
  size = size or diamond.SIZE

  if image.width ~= size or image.height ~= size then
    error(string.format(
      "height map must be %dx%d, got %dx%d",
      size, size, image.width, image.height))
  end

  local gray = image.gray
  local defaultHeight = layers.defaultHeight
  local height = layers.height

  for tile = 0, diamond.tileCount(size) - 1 do
    local value = gray[lookup[tile]] or 0
    if value < 0 then
      value = 0
    elseif value > 255 then
      value = 255
    end
    defaultHeight[tile] = value
    height[tile] = value
  end
end

return M
