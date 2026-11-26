--- mappng/png/decode.lua
---
--- A small PNG decoder of its own, used for height maps.
---
--- Why not GDI+: GDI+ applies the file's gAMA / sRGB / iCCP chunks when it
--- converts to 32bppARGB, and treats 16-bit PNGs as linear light. Paint
--- programs write those chunks, so a pixel stored as 128 came back as some
--- other value and the terrain height was shifted. This decoder returns the
--- raw stored values and ignores every colour-management chunk.
---
--- Reads standard grayscale, grayscale + alpha, RGB, RGBA and indexed
--- heightmaps at their legal bit depths, including Adam7. Alpha is ignored.

local M = {}

local byte = string.byte
local floor = math.floor
local MAX_SIDE = require("mappng.map.diamond").SIZE
M.FILE_LIMIT = 8 * 1024 * 1024

---------------------------------------------------------------------------
-- Inflate (RFC 1950 / 1951), adapted to Lua from Mark Adler's puff.
-- See licenses/puff-zlib.txt for the original notice.

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- lengths: 0-based array of code lengths, n entries
local function huffman(lengths, n)
  local count, symbol, offs = {}, {}, {}
  for len = 0, 15 do count[len] = 0 end
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    count[len] = count[len] + 1
  end
  local remaining = 1
  for len = 1, 15 do
    remaining = 2 * remaining - count[len]
    assert(remaining >= 0, "map-png: oversubscribed PNG Huffman tree")
  end
  offs[1] = 0
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    if len ~= 0 then
      symbol[offs[len]] = s
      offs[len] = offs[len] + 1
    end
  end
  return { count = count, symbol = symbol }, remaining
end

local function inflate(src, expected)
  assert(#src >= 6, "map-png: truncated zlib stream")
  local lastData = #src - 4
  local pos = 1          -- next input byte
  local bitbuf, bitcnt = 0, 0
  local out, n = {}, 0   -- output bytes, 1-based

  local function bits(need)
    while bitcnt < need do
      assert(pos <= lastData, "map-png: PNG image data ends early")
      local b = byte(src, pos)
      pos = pos + 1
      bitbuf = bitbuf | (b << bitcnt)
      bitcnt = bitcnt + 8
    end
    local v = bitbuf & ((1 << need) - 1)
    bitbuf = bitbuf >> need
    bitcnt = bitcnt - need
    return v
  end

  local function decode(h)
    local code, first, index = 0, 0, 0
    local count, symbol = h.count, h.symbol
    for len = 1, 15 do
      code = code | bits(1)
      local c = count[len]
      if code - c < first then
        return symbol[index + (code - first)]
      end
      index = index + c
      first = (first + c) << 1
      code = code << 1
    end
    error("map-png: bad PNG image data (Huffman code)", 0)
  end

  local fixedLit, fixedDist
  local window

  local function reserve(count)
    assert(n + count <= expected, "map-png: excess PNG image data")
  end

  local function codes(lit, dist)
    while true do
      local s = decode(lit)
      if s < 256 then
        reserve(1)
        n = n + 1
        out[n] = s
      elseif s == 256 then
        return
      else
        s = s - 257
        if s >= 29 then error("map-png: bad PNG image data (length)", 0) end
        local len = LEN_BASE[s + 1] + bits(LEN_EXTRA[s + 1])
        local d = decode(dist)
        if d >= 30 then error("map-png: bad PNG image data (distance)", 0) end
        local back = DIST_BASE[d + 1] + bits(DIST_EXTRA[d + 1])
        if back > n or back > window then error("map-png: bad PNG image data (distance too far)", 0) end
        reserve(len)
        local from = n - back
        for i = 1, len do
          out[n + i] = out[from + i]
        end
        n = n + len
      end
    end
  end

  -- zlib header
  local cmf, flg = byte(src, 1, 2)
  local cinfo = cmf >> 4
  if cinfo > 7 or (cmf & 0x0F) ~= 8 or ((cmf << 8) | flg) % 31 ~= 0 then
    error("map-png: PNG image data is not zlib compressed", 0)
  end
  if flg & 0x20 ~= 0 then error("map-png: PNG uses a preset dictionary", 0) end
  window = 1 << (cinfo + 8)
  pos = 3

  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      bitbuf, bitcnt = 0, 0
      local lo1, hi1, lo2, hi2 = byte(src, pos, pos + 3)
      if pos + 3 > lastData then error("map-png: PNG image data ends early", 0) end
      local len = lo1 | (hi1 << 8)
      if len ~= (~(lo2 | (hi2 << 8)) & 0xFFFF) then
        error("map-png: bad PNG image data (stored block)", 0)
      end
      pos = pos + 4
      if pos + len - 1 > lastData then error("map-png: PNG image data ends early", 0) end
      reserve(len)
      for i = 0, len - 1 do
        out[n + 1 + i] = byte(src, pos + i)
      end
      n = n + len
      pos = pos + len
    elseif kind == 1 then
      if not fixedLit then
        local l = {}
        for s = 0, 143 do l[s] = 8 end
        for s = 144, 255 do l[s] = 9 end
        for s = 256, 279 do l[s] = 7 end
        for s = 280, 287 do l[s] = 8 end
        fixedLit = huffman(l, 288)
        local d = {}
        for s = 0, 31 do d[s] = 5 end
        fixedDist = huffman(d, 32)
      end
      codes(fixedLit, fixedDist)
    elseif kind == 2 then
      local nlen = bits(5) + 257
      local ndist = bits(5) + 1
      assert(nlen <= 286, "map-png: invalid PNG literal count")
      local ncode = bits(4) + 4
      local cl = {}
      for i = 0, 18 do cl[i] = 0 end
      for i = 1, ncode do cl[CL_ORDER[i]] = bits(3) end
      local clh, unused = huffman(cl, 19)
      assert(unused == 0, "map-png: incomplete PNG code-length tree")
      local lengths, i = {}, 0
      while i < nlen + ndist do
        local s = decode(clh)
        if s < 16 then
          lengths[i] = s
          i = i + 1
        else
          local value, rep = 0, 0
          if s == 16 then
            if i == 0 then error("map-png: bad PNG image data (repeat)", 0) end
            value = lengths[i - 1]
            rep = 3 + bits(2)
          elseif s == 17 then
            rep = 3 + bits(3)
          else
            rep = 11 + bits(7)
          end
          if i + rep > nlen + ndist then error("map-png: bad PNG image data (lengths)", 0) end
          for _ = 1, rep do
            lengths[i] = value
            i = i + 1
          end
        end
      end
      local litLengths, distLengths = {}, {}
      for s = 0, nlen - 1 do litLengths[s] = lengths[s] end
      for s = 0, ndist - 1 do distLengths[s] = lengths[nlen + s] end
      assert(litLengths[256] ~= 0, "map-png: PNG block has no end code")
      local lit, litUnused = huffman(litLengths, nlen)
      local dist, distUnused = huffman(distLengths, ndist)
      assert(litUnused == 0 or lit.count[1] == 1 and litUnused == 16384,
        "map-png: incomplete PNG literal tree")
      assert(distUnused == 0 or distUnused == 32768 or dist.count[1] == 1 and distUnused == 16384,
        "map-png: incomplete PNG distance tree")
      codes(lit, dist)
    else
      error("map-png: bad PNG image data (block type)", 0)
    end
  until last == 1

  assert(pos == lastData + 1 and n == expected, "map-png: wrong PNG image data length")
  local a, b = 1, 0
  for i = 1, n do
    a = (a + out[i]) % 65521
    b = (b + a) % 65521
  end
  assert(string.unpack(">I4", src, pos) == ((b << 16) | a), "map-png: bad PNG Adler-32")
  return out
end

---------------------------------------------------------------------------
-- PNG

local SIGNATURE = "\137PNG\r\n\26\n"
local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }
local DEPTHS = {
  [0] = { [1] = true, [2] = true, [4] = true, [8] = true, [16] = true },
  [3] = { [1] = true, [2] = true, [4] = true, [8] = true },
}

local crcTable = {}
for value = 0, 255 do
  local crc = value
  for _ = 1, 8 do
    crc = (crc >> 1) ~ ((crc & 1) * 0xEDB88320)
  end
  crcTable[value] = crc
end

local function crc32(data, first, last)
  local crc = 0xFFFFFFFF
  for i = first, last do
    crc = (crc >> 8) ~ crcTable[(crc ~ byte(data, i)) & 255]
  end
  return crc ~ 0xFFFFFFFF
end

local function u32(s, i)
  local a, b, c, d = byte(s, i, i + 3)
  return (a << 24) | (b << 16) | (c << 8) | d
end

local ADAM7 = {
  { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 }, { 2, 0, 4, 4 },
  { 0, 2, 2, 4 }, { 1, 0, 2, 2 }, { 0, 1, 1, 2 },
}
local NON_INTERLACED = { { 0, 0, 1, 1 } }

--- Decodes PNG file bytes.
---@param data string
---@param expectedSide number|nil required square heightmap size
---@return table image with 0-based rows of raw channel samples
function M.decodeBytes(data, expectedSide)
  assert(#data <= M.FILE_LIMIT, "map-png: file exceeds reading limit")
  if data:sub(1, 8) ~= SIGNATURE then
    error("map-png: not a PNG file", 0)
  end

  local pos = 9
  local width, height, depth, colourType, interlace
  local palette, sawIdat, idatClosed, ended
  local idat = {}
  while pos + 11 <= #data do
    local len = u32(data, pos)
    local kind = data:sub(pos + 4, pos + 7)
    local start, nextChunk = pos + 8, pos + 12 + len
    assert(nextChunk <= #data + 1, "map-png: PNG file ends early")
    assert(crc32(data, pos + 4, nextChunk - 5) == u32(data, nextChunk - 4),
      "map-png: bad PNG chunk CRC (" .. kind .. ")")
    assert(width or kind == "IHDR", "map-png: PNG must begin with IHDR")
    if sawIdat and kind ~= "IDAT" then idatClosed = true end
    if kind == "IHDR" then
      assert(not width and len == 13, "map-png: invalid PNG IHDR")
      width, height = u32(data, start), u32(data, start + 4)
      local compression, filter
      depth, colourType, compression, filter, interlace = byte(data, start + 8, start + 12)
      assert(compression == 0 and filter == 0 and (interlace == 0 or interlace == 1),
        "map-png: unsupported PNG encoding method")
      local depths = DEPTHS[colourType]
      assert(CHANNELS[colourType] and (depths and depths[depth] or not depths and (depth == 8 or depth == 16)),
        "map-png: invalid PNG colour type or bit depth")
      assert(width > 0 and height > 0 and width <= MAX_SIDE and height <= MAX_SIDE,
        "map-png: PNG dimensions exceed the decoding limit")
      if expectedSide then
        assert(width == expectedSide and height == expectedSide,
          ("map-png: expected a %dx%d PNG"):format(expectedSide, expectedSide))
      end
    elseif kind == "PLTE" then
      assert(not palette and not sawIdat and colourType ~= 0 and colourType ~= 4
        and len >= 3 and len <= 768 and len % 3 == 0
        and (colourType ~= 3 or len // 3 <= (1 << depth)), "map-png: invalid PNG palette")
      palette = {}
      for i = 0, (len // 3) - 1 do
        local r, g, b = byte(data, start + i * 3, start + i * 3 + 2)
        palette[i] = { r, g, b }
      end
    elseif kind == "IDAT" then
      assert(not idatClosed and (colourType ~= 3 or palette), "map-png: misplaced PNG IDAT")
      sawIdat = true
      if len > 0 then idat[#idat + 1] = data:sub(start, nextChunk - 5) end
    elseif kind == "IEND" then
      assert(len == 0 and #idat > 0 and nextChunk == #data + 1, "map-png: invalid PNG IEND")
      ended = true
      break
    else
      assert(kind:match("^[A-Za-z][A-Za-z][A-Z][A-Za-z]$") and kind:match("^[a-z]"),
        "map-png: unknown critical or invalid PNG chunk")
    end
    pos = nextChunk
  end
  assert(ended, "map-png: PNG has no complete IEND")

  local channels = CHANNELS[colourType]
  local passes = {}
  local expected = 0
  for _, pass in ipairs(interlace == 1 and ADAM7 or NON_INTERLACED) do
    local x, y, dx, dy = table.unpack(pass)
    local pw, ph = (width - x + dx - 1) // dx, (height - y + dy - 1) // dy
    if pw > 0 and ph > 0 then
      local rowBytes = (pw * channels * depth + 7) // 8
      expected = expected + (rowBytes + 1) * ph
      passes[#passes + 1] = { x, y, dx, dy, pw, ph, rowBytes }
    end
  end
  local raw = inflate(table.concat(idat), expected)
  local bpp = math.max(1, (channels * depth) // 8) -- filter step in bytes

  -- samples[y][x * channels + c], all 0-based
  local rows = {}
  for y = 0, height - 1 do rows[y] = {} end

  local rp = 1 -- read position in raw (1-based)

  local function pass(x0, y0, dx, dy, pw, ph, rowBytes)
    local prev = {}
    for i = 1, rowBytes do prev[i] = 0 end
    for py = 0, ph - 1 do
      local filter = raw[rp]
      if filter == nil then error("map-png: PNG image data ends early", 0) end
      rp = rp + 1
      local cur = {}
      for i = 1, rowBytes do
        local v = raw[rp + i - 1]
        if v == nil then error("map-png: PNG image data ends early", 0) end
        local a = i > bpp and cur[i - bpp] or 0
        local b = prev[i]
        if filter == 1 then
          v = v + a
        elseif filter == 2 then
          v = v + b
        elseif filter == 3 then
          v = v + ((a + b) >> 1)
        elseif filter == 4 then
          local c = i > bpp and prev[i - bpp] or 0
          local p = a + b - c
          local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
          if pa <= pb and pa <= pc then v = v + a
          elseif pb <= pc then v = v + b
          else v = v + c end
        elseif filter ~= 0 then
          error("map-png: bad PNG filter " .. tostring(filter), 0)
        end
        cur[i] = v & 0xFF
      end
      rp = rp + rowBytes

      local row = rows[y0 + py * dy]
      local count = pw * channels
      for k = 0, count - 1 do
        local v
        if depth == 8 then
          v = cur[k + 1]
        elseif depth == 16 then
          v = (cur[k * 2 + 1] << 8) | cur[k * 2 + 2]
        else
          local bit = k * depth
          local b = cur[(bit >> 3) + 1]
          v = (b >> (8 - depth - (bit & 7))) & ((1 << depth) - 1)
        end
        local px = k // channels
        row[(x0 + px * dx) * channels + (k % channels)] = v
      end
      prev = cur
    end
  end

  for _, dimensions in ipairs(passes) do pass(table.unpack(dimensions)) end

  return {
    width = width, height = height, channels = channels, depth = depth,
    colourType = colourType, palette = palette, rows = rows,
  }
end

--- Converts each pixel to 0..255 r, g, b and stores combine(r, g, b) in a
--- flat 0-based array. 16-bit and low bit-depth values are scaled. Alpha is
--- ignored.
local function convert(png, combine)
  local width, height, channels = png.width, png.height, png.channels
  local maxValue = (1 << png.depth) - 1
  local palette = png.palette
  local colourType = png.colourType

  local function scale(v)
    if maxValue == 255 then return v end
    return floor(v * 255 / maxValue + 0.5)
  end

  local result = {}
  for y = 0, height - 1 do
    local row = png.rows[y]
    local out = y * width
    for x = 0, width - 1 do
      local i = x * channels
      local r, g, b
      if colourType == 3 then
        local entry = assert(palette[row[i]], "map-png: PNG pixel uses a missing palette entry")
        r, g, b = entry[1], entry[2], entry[3]
      elseif colourType == 0 or colourType == 4 then
        r = scale(row[i])
        g, b = r, r
      else
        r, g, b = scale(row[i]), scale(row[i + 1]), scale(row[i + 2])
      end
      result[out + x] = combine(r, g, b)
    end
  end
  return result
end

local function luma(r, g, b)
  if r == g and g == b then return r end
  return floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5)
end

local function pack(r, g, b)
  return (r << 16) | (g << 8) | b
end

--- Turns a decoded PNG into a grey image for the height layer.
---
--- Grey pixels keep their stored value; colour pixels with r == g == b keep
--- that value; other colours use the usual brightness weights
--- (0.299 r + 0.587 g + 0.114 b).
function M.toGray(png)
  return { width = png.width, height = png.height, gray = convert(png, luma) }
end

--- Turns a decoded PNG into { width, height, rgb } with packed 0xRRGGBB.
function M.toRGB(png)
  return { width = png.width, height = png.height, rgb = convert(png, pack) }
end

return M
