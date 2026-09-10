-- Pure conversion of a decoded PNG (or export image) to a bounded native
-- preview. No reads from the game's minimap buffer and no map writes.
local M = {}
function M.encode(image, maxWidth, maxHeight, rgb565)
  assert(image.width > 0 and image.height > 0, "empty PNG preview")
  local scale = math.min(maxWidth / image.width, maxHeight / image.height, 1)
  local width = math.max(1, math.floor(image.width * scale))
  local height = math.max(1, math.floor(image.height * scale))
  local chunks = {}
  for y = 0, height - 1 do
    local sy = math.floor(y * image.height / height)
    local x = 0
    while x < width do
      local count = math.min(32, width - x)
      chunks[#chunks + 1] = string.char(count - 1)
      for offset = 0, count - 1 do
        local sx = math.floor((x + offset) * image.width / width)
        local index = sy * image.width + sx
        local pixel = image.rgb and image.rgb[index] or image.gray[index] * 0x010101
        local r, g, b = (pixel >> 16) & 255, (pixel >> 8) & 255, pixel & 255
        local native = ((r >> 3) << (rgb565 and 11 or 10))
          | ((g >> 3) << (rgb565 and 6 or 5)) | (b >> 3)
        chunks[#chunks + 1] = string.pack("<I2", native)
      end
      x = x + count
    end
    chunks[#chunks + 1] = string.char(128)
  end
  return table.concat(chunks), width, height
end
return M
