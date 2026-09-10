--- Draw the supplied images through renderGM's native TGX renderer without
--- borrowing/replacing any existing GM slots. Pixels remain module-owned.
local M = {}
local screens = require("mappng.ui.screens")
local state = { images = {} }

-- Validate literal/transparent runs before passing module bytes to native code.
function M.validate(bytes, width, height)
  width, height = width or screens.ICON_WIDTH, height or screens.ICON_HEIGHT
  local position, x, y = 1, 0, 0
  while position <= #bytes do
    local token = bytes:byte(position)
    position = position + 1
    local kind, count = token & 0xE0, (token & 0x1F) + 1
    if kind == 0x80 then
      assert(x == width, "map-png: incomplete icon row")
      x, y = 0, y + 1
    else
      assert(y < height and (kind == 0 or kind == 0x20), "map-png: invalid icon run")
      x = x + count
      assert(x <= width, "map-png: icon run exceeds row")
      if kind == 0 then position = position + count * 2 end
      assert(position <= #bytes + 1, "map-png: truncated icon pixels")
    end
  end
  assert(y == height and x == 0, "map-png: incomplete icon")
end

function M.load(files)
  local ffi = modules.cffi:cffi()
  state.ffi = ffi
  -- SHC 1.41: 0x0044D3D0, verified from renderGM's interface-image branch.
  local address = core.AOBScan("55 8B EC 83 EC 28 53 56 57 89 4D E0 C7 45 F8 ? ? ? ? C7 45 EC ? ? ? ?")
  assert(address, "map-png: native interface image renderer was not found")
  state.draw = ffi.cast("void (__thiscall *)(void *, int, int, int, int, unsigned short *)", address)
  local formatAddress = core.AOBScan("81 3D ? ? ? ? 65 05 00 00 75 40")
  assert(formatAddress, "map-png: display pixel format was not found")
  local format = core.readInteger(core.readInteger(formatAddress + 2))
  state.rgb565 = format == 0x565
  local suffix = format == 0x565 and ".565.tgx" or ".555.tgx"
  local images = {}
  for key, path in pairs(files) do
    local file, err = io.open(path:gsub("%.png$", suffix), "rb")
    assert(file, err)
    local bytes = file:read("*all")
    file:close()
    M.validate(bytes)
    local buffer = ffi.new("unsigned char[?]", #bytes)
    ffi.copy(buffer, bytes, #bytes)
    images[key] = { buffer = buffer, pixels = ffi.cast("unsigned short *", buffer) }
  end
  state.images = images
  log(INFO, "map-png: loaded all four supplied button images (" .. suffix .. ")")
end

function M.draw(key, rendering, x, y)
  local image = assert(state.images[key], "map-png: missing artwork: " .. key)
  state.draw(rendering.textureRenderCore, x, y, screens.ICON_WIDTH, screens.ICON_HEIGHT, image.pixels)
end

function M.preview(image, maxWidth, maxHeight)
  local bytes, width, height = require("mappng.ui.preview").encode(image, maxWidth, maxHeight, state.rgb565)
  M.validate(bytes, width, height)
  local buffer = state.ffi.new("unsigned char[?]", #bytes)
  state.ffi.copy(buffer, bytes, #bytes)
  return { buffer = buffer, pixels = state.ffi.cast("unsigned short *", buffer), width = width, height = height }
end

function M.drawPreview(image, rendering, x, y)
  state.draw(rendering.textureRenderCore, x, y, image.width, image.height, image.pixels)
end

function M.unload() state.images = {} end
return M
