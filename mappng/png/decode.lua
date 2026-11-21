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
--- Reads every PNG kind: grey, grey + alpha, RGB, RGBA, palette; bit depths
--- 1, 2, 4, 8 and 16; interlaced or not. Alpha is ignored.

local M = {}

local byte, char = string.byte, string.char
local floor = math.floor

---------------------------------------------------------------------------
-- Inflate (RFC 1950 / 1951), after zlib's "puff".

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
  offs[1] = 0
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    if len ~= 0 then
      symbol[offs[len]] = s
      offs[len] = offs[len] + 1
    end
  end
  return { count = count, symbol = symbol }
end

local function inflate(src)
  local pos = 1          -- next input byte
  local bitbuf, bitcnt = 0, 0
  local out, n = {}, 0   -- output bytes, 1-based

  local function bits(need)
    while bitcnt < need do
      local b = byte(src, pos)
      if not b then error("map-png: PNG image data ends early", 0) end
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

  local function codes(lit, dist)
    while true do
      local s = decode(lit)
      if s < 256 then
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
        if back > n then error("map-png: bad PNG image data (distance too far)", 0) end
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
  if not cmf or (cmf & 0x0F) ~= 8 or ((cmf << 8) | flg) % 31 ~= 0 then
    error("map-png: PNG image data is not zlib compressed", 0)
  end
  if flg & 0x20 ~= 0 then error("map-png: PNG uses a preset dictionary", 0) end
  pos = 3

  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      bitbuf, bitcnt = 0, 0
      local lo1, hi1, lo2, hi2 = byte(src, pos, pos + 3)
      if not hi2 then error("map-png: PNG image data ends early", 0) end
      local len = lo1 | (hi1 << 8)
      if len ~= (~(lo2 | (hi2 << 8)) & 0xFFFF) then
        error("map-png: bad PNG image data (stored block)", 0)
      end
      pos = pos + 4
      if pos + len - 1 > #src then error("map-png: PNG image data ends early", 0) end
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
        for s = 0, 29 do d[s] = 5 end
        fixedDist = huffman(d, 30)
      end
      codes(fixedLit, fixedDist)
    elseif kind == 2 then
      local nlen = bits(5) + 257
      local ndist = bits(5) + 1
      local ncode = bits(4) + 4
      local cl = {}
      for i = 0, 18 do cl[i] = 0 end
      for i = 1, ncode do cl[CL_ORDER[i]] = bits(3) end
      local clh = huffman(cl, 19)
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
      codes(huffman(litLengths, nlen), huffman(distLengths, ndist))
    else
      error("map-png: bad PNG image data (block type)", 0)
    end
  until last == 1

  return out, n
end

---------------------------------------------------------------------------
-- PNG

local SIGNATURE = "\137PNG\r\n\26\n"
local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }

local function u32(s, i)
  local a, b, c, d = byte(s, i, i + 3)
  return (a << 24) | (b << 16) | (c << 8) | d
end

local ADAM7 = {
  { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 }, { 2, 0, 4, 4 },
  { 0, 2, 2, 4 }, { 1, 0, 2, 2 }, { 0, 1, 1, 2 },
}

--- Decodes PNG file bytes.
---@param data string
---@return table image { width, height, channels, depth, colourType, palette,
---                      sample(x, y, c) -> raw value }
function M.decodeBytes(data)
  if data:sub(1, 8) ~= SIGNATURE then
    error("map-png: not a PNG file", 0)
  end

  local pos = 9
  local width, height, depth, colourType, interlace
  local palette
  local idat, nidat = {}, 0
  while pos + 7 <= #data do
    local len = u32(data, pos)
    local kind = data:sub(pos + 4, pos + 7)
    local body = data:sub(pos + 8, pos + 7 + len)
    if #body < len then error("map-png: PNG file ends early", 0) end
    if kind == "IHDR" then
      width, height = u32(body, 1), u32(body, 5)
      depth, colourType = byte(body, 9), byte(body, 10)
      interlace = byte(body, 13)
    elseif kind == "PLTE" then
      palette = {}
      for i = 0, (len // 3) - 1 do
        local r, g, b = byte(body, i * 3 + 1, i * 3 + 3)
        palette[i] = { r, g, b }
      end
    elseif kind == "IDAT" then
      nidat = nidat + 1
      idat[nidat] = body
    elseif kind == "IEND" then
      break
    end
    pos = pos + 12 + len
  end

  if not width then error("map-png: PNG has no IHDR", 0) end
  local channels = CHANNELS[colourType]
  if not channels then error("map-png: unknown PNG colour type " .. tostring(colourType), 0) end
  if colourType == 3 and not palette then error("map-png: palette PNG has no palette", 0) end
  assert(width > 0 and height > 0 and width * height <= 4194304,
    "map-png: PNG dimensions exceed the decoding limit")

  local raw = inflate(table.concat(idat))
  local bpp = math.max(1, (channels * depth) // 8) -- filter step in bytes

  -- samples[y][x * channels + c], all 0-based
  local rows = {}
  for y = 0, height - 1 do rows[y] = {} end

  local rp = 1 -- read position in raw (1-based)

  local function pass(x0, y0, dx, dy)
    local pw = (width - x0 + dx - 1) // dx
    local ph = (height - y0 + dy - 1) // dy
    if pw <= 0 or ph <= 0 then return end
    local rowBytes = (pw * channels * depth + 7) // 8
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

  if interlace == 1 then
    for _, p in ipairs(ADAM7) do pass(p[1], p[2], p[3], p[4]) end
  else
    pass(0, 0, 1, 1)
  end

  return {
    width = width, height = height, channels = channels, depth = depth,
    colourType = colourType, palette = palette, rows = rows,
  }
end

--- Turns a decoded PNG into a grey image for the height layer.
---
--- Grey pixels keep their stored value; colour pixels with r == g == b keep
--- that value; other colours use the usual brightness weights
--- (0.299 r + 0.587 g + 0.114 b). 16-bit and low bit-depth values are scaled
--- to 0..255. Alpha is ignored.
function M.toGray(png)
  local width, height, channels = png.width, png.height, png.channels
  local maxValue = (1 << png.depth) - 1
  local palette = png.palette
  local colourType = png.colourType

  local function scale(v)
    if maxValue == 255 then return v end
    return floor(v * 255 / maxValue + 0.5)
  end

  local function luma(r, g, b)
    if r == g and g == b then return r end
    return floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5)
  end

  local gray = {}
  for y = 0, height - 1 do
    local row = png.rows[y]
    local out = y * width
    for x = 0, width - 1 do
      local i = x * channels
      local value
      if colourType == 3 then
        local entry = palette[row[i]] or { 0, 0, 0 }
        value = luma(entry[1], entry[2], entry[3])
      elseif colourType == 0 or colourType == 4 then
        value = scale(row[i])
      else
        value = luma(scale(row[i]), scale(row[i + 1]), scale(row[i + 2]))
      end
      gray[out + x] = value
    end
  end
  return { width = width, height = height, gray = gray }
end

--- Reads a PNG file into { width, height, gray }.
---@param path string
function M.readGray(path)
  local file, err = io.open(path, "rb")
  if not file then error(string.format("map-png: cannot open %s: %s", path, tostring(err)), 0) end
  local data = file:read("a")
  file:close()
  return M.toGray(M.decodeBytes(data))
end

return M
