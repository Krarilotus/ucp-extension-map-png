--- mappng/map/diamond.lua
---
--- The game stores its tile layers as 80400 tiles in a diamond. A PNG is a
--- 400x400 square. This module builds the lookup between the two.
---
--- Port of `create_binary_matrix` / `TileLocationTranslator` from
--- sourcehold-maps (`sourcehold/world/`), but constructed with integer
--- arithmetic instead of the inverse-square-root formula, which is both faster
--- and free of the float rounding the Python version has to tolerate.
---
--- Row `i` of the diamond holds `2*(i+1)` tiles for `i < 200` and `2*(400-i)`
--- tiles for `i >= 200`, centred in the row. So row 0 and row 399 hold 2 tiles
--- each (columns 199 and 200) and rows 199 and 200 hold the full 400.

local M = {}

M.SIZE = 400
M.TILE_COUNT = 80400 -- SIZE * ((SIZE // 2) + 1)

--- Start index of diamond row `i` in the serialized tile array.
local function rowStart(i, size)
  local half = size // 2
  if i < half then
    return i * (i + 1)
  end
  local n = 2 * (half * (half + 1))
  return n - ((size - i) * (size - i + 1))
end

--- Number of tiles in diamond row `i`.
local function rowWidth(i, size)
  local half = size // 2
  if i < half then
    return 2 * (i + 1)
  end
  return 2 * (size - i)
end

--- Column of the first tile of row `i` in the square image.
local function rowOffset(i, size)
  local half = size // 2
  if i < half then
    return half - 1 - i
  end
  return i - half
end

--- Builds `serializedTileIndex -> squarePixelIndex` (both 0-based).
---
--- `squarePixelIndex` is `row * size + column`, i.e. the index into a row-major
--- `size x size` image. Every one of the TILE_COUNT entries is filled; pixels of
--- the square that fall outside the diamond simply never appear as a value.
---
---@param size number|nil defaults to 400
---@return table flat 0-based Lua table of length TILE_COUNT
function M.buildTileToPixel(size)
  size = size or M.SIZE

  local lookup = {}
  for i = 0, size - 1 do
    local start = rowStart(i, size)
    local width = rowWidth(i, size)
    local offset = rowOffset(i, size)
    local base = i * size
    for j = 0, width - 1 do
      lookup[start + j] = base + offset + j
    end
  end

  return lookup
end

--- Builds the inverse: `squarePixelIndex -> serializedTileIndex`, or nil for
--- pixels outside the diamond.
---
---@param size number|nil defaults to 400
---@return table flat 0-based Lua table of length size*size, holes outside the diamond
function M.buildPixelToTile(size)
  size = size or M.SIZE

  local forward = M.buildTileToPixel(size)
  local inverse = {}
  for tile, pixel in pairs(forward) do
    inverse[pixel] = tile
  end

  return inverse
end

--- Total number of serialized tiles for a given square width.
---@param size number|nil defaults to 400
function M.tileCount(size)
  size = size or M.SIZE
  local half = size // 2
  return 2 * (half * (half + 1))
end

-- exported for tests
M._rowStart = rowStart
M._rowWidth = rowWidth
M._rowOffset = rowOffset

return M
