--- Draw the supplied images through renderGM's native TGX renderer without
--- borrowing/replacing any existing GM slots. Pixels remain module-owned.
local M = {}
local state = { images = {} }

function M.load(files)
  local ffi = modules.cffi:cffi()
  -- SHC 1.41: 0x0044D3D0, verified from renderGM's interface-image branch.
  local address = core.AOBScan("55 8B EC 83 EC 28 53 56 57 89 4D E0 C7 45 F8 ? ? ? ? C7 45 EC ? ? ? ?")
  assert(address, "map-png: native interface image renderer was not found")
  state.draw = ffi.cast("void (__thiscall *)(void *, int, int, int, int, unsigned short *)", address)
  local formatAddress = core.AOBScan("81 3D ? ? ? ? 65 05 00 00 75 40")
  assert(formatAddress, "map-png: display pixel format was not found")
  local format = core.readInteger(core.readInteger(formatAddress + 2))
  local suffix = format == 0x565 and ".565.tgx" or ".555.tgx"
  local images = {}
  for key, path in pairs(files) do
    local file, err = io.open(path:gsub("%.png$", suffix), "rb")
    assert(file, err)
    local bytes = file:read("*all")
    file:close()
    assert(#bytes == 18 * 66, "map-png: invalid button image: " .. key)
    local buffer = ffi.new("unsigned char[?]", #bytes)
    ffi.copy(buffer, bytes, #bytes)
    images[key] = { buffer = buffer, pixels = ffi.cast("unsigned short *", buffer) }
  end
  state.images = images
  log(INFO, "map-png: loaded all four supplied button images (" .. suffix .. ")")
end

function M.draw(key, rendering, x, y)
  local image = assert(state.images[key], "map-png: missing artwork: " .. key)
  state.draw(rendering.textureRenderCore, x, y, 32, 18, image.pixels)
end

function M.unload() state.images = {} end
return M
