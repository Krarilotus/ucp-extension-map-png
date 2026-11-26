--- mappng/png/init.lua
---
--- PNG read/write in the image shapes `mappng.map.height` and
--- `mappng.map.terrain` speak:
---
---   grayscale  { width, height, gray = <0-based 0..255> }
---   colour     { width, height, rgb  = <0-based packed 0xRRGGBB> }
---
--- Imports prefer raw PNG samples and fall back to GDI+'s 32bppARGB conversion.
--- Exports use GDI+. Alpha is ignored and exports are opaque.

local gdiplus = require("mappng.png.gdiplus")
local decode = require("mappng.png.decode")
local paths = require("mappng.paths")
local diamond = require("mappng.map.diamond")

local M = {}

local function check(status, what)
  if status ~= 0 then
    error(string.format("map-png: %s failed: %s", what, gdiplus.statusName(status)))
  end
end

local function readRaw(path, convert)
  local data = paths.readBinary(path, decode.FILE_LIMIT)
  return convert(decode.decodeBytes(data, diamond.SIZE))
end

local function readGdiplus(bound, path, kind, pixel)
  local ffi = bound.ffi
  local gdi = bound.gdiplus

  local bitmapOut = ffi.new("void *[1]")
  check(gdi.GdipCreateBitmapFromFile(gdiplus.widePath(bound, path), bitmapOut),
    string.format("opening %s", path))
  local bitmap = bitmapOut[0]

  local ok, result = pcall(function()
    local w = ffi.new("unsigned int[1]")
    local h = ffi.new("unsigned int[1]")
    check(gdi.GdipGetImageWidth(bitmap, w), "GdipGetImageWidth")
    check(gdi.GdipGetImageHeight(bitmap, h), "GdipGetImageHeight")

    local width, height = tonumber(w[0]), tonumber(h[0])
    assert(width == diamond.SIZE and height == diamond.SIZE,
      "map-png: expected a 400x400 PNG")

    local rect = ffi.new("GpRect[1]")
    rect[0].X, rect[0].Y = 0, 0
    rect[0].Width, rect[0].Height = width, height

    local data = ffi.new("BitmapData[1]")
    check(gdi.GdipBitmapLockBits(bitmap, rect, gdiplus.IMAGE_LOCK_MODE_READ,
      gdiplus.PIXEL_FORMAT_32BPP_ARGB, data), "GdipBitmapLockBits")

    local pixels = {}
    local okInner, err = pcall(function()
      local stride = tonumber(data[0].Stride)
      local scan0 = ffi.cast("unsigned char *", data[0].Scan0)
      -- A negative stride means the rows are stored bottom-up.
      for y = 0, height - 1 do
        -- Scan0 is the first logical row; Stride already carries direction.
        local row = y * stride
        local out = y * width
        for x = 0, width - 1 do
          local p = row + (x * 4)
          -- 32bppARGB is little-endian BGRA in memory.
          pixels[out + x] = pixel(scan0[p + 2], scan0[p + 1], scan0[p])
        end
      end
    end)
    gdi.GdipBitmapUnlockBits(bitmap, data)
    if not okInner then
      error(err, 0)
    end

    return { width = width, height = height, [kind] = pixels }
  end)

  gdi.GdipDisposeImage(bitmap)
  if not ok then
    error(result, 0)
  end
  return result
end

local function readImport(bound, path, convert, kind, pixel)
  local ok, image = pcall(readRaw, path, convert)
  if ok then return image end
  log(WARNING, string.format("own PNG reader failed (%s), using GDI+ for %s",
    tostring(image), path))
  return readGdiplus(bound, path, kind, pixel)
end

function M.readRGB(bound, path)
  return readImport(bound, path, decode.toRGB, "rgb", decode.pack)
end

function M.readGray(bound, path)
  return readImport(bound, path, decode.toGray, "gray", decode.luma)
end

--- Shared writer. `fetch(pixel)` returns r, g, b.
local function write(bound, path, width, height, fetch)
  local ffi = bound.ffi
  local gdi = bound.gdiplus

  local stride = width * 4
  local scan0 = ffi.new("unsigned char[?]", stride * height)

  for pixel = 0, (width * height) - 1 do
    local r, g, b = fetch(pixel)
    local p = pixel * 4
    scan0[p] = b
    scan0[p + 1] = g
    scan0[p + 2] = r
    scan0[p + 3] = 255
  end

  local bitmapOut = ffi.new("void *[1]")
  check(gdi.GdipCreateBitmapFromScan0(width, height, stride,
    gdiplus.PIXEL_FORMAT_32BPP_ARGB, scan0, bitmapOut), "GdipCreateBitmapFromScan0")
  local bitmap = bitmapOut[0]

  local ok, err = pcall(function()
    check(gdi.GdipSaveImageToFile(bitmap, gdiplus.widePath(bound, path),
      bound.pngEncoder, nil), string.format("writing %s", path))
  end)

  gdi.GdipDisposeImage(bitmap)
  if not ok then
    error(err, 0)
  end
end

--- Writes a grayscale image as an RGB PNG (r == g == b), matching what
--- `sourcehold memory map get height` produces.
function M.writeGray(bound, path, image)
  local gray = image.gray
  write(bound, path, image.width, image.height, function(pixel)
    local value = gray[pixel] or 0
    return value, value, value
  end)
end

--- Writes a colour image.
function M.writeRGB(bound, path, image)
  local rgb = image.rgb
  write(bound, path, image.width, image.height, function(pixel)
    local packed = rgb[pixel] or 0
    return (packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF
  end)
end

return M
