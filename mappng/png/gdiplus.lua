--- mappng/png/gdiplus.lua
---
--- FFI bindings for the GDI+ flat C API, used to read and write PNG files.
---
--- Why GDI+: `gdiplus.dll` ships with every supported Windows and is a plain
--- C export surface, so no COM plumbing, no bundled decoder, and nothing to
--- sign. The alternative was a native module using WIC, the way
--- `ucp_gmResourceModifier/loadImageAsInterfaceResource.cpp` does it -- that
--- stays the fallback if `ffi.load` turns out not to be reachable from the UCP
--- cffi module.
---
--- Both prerequisites are confirmed against the cffi module's source:
---   * `modules.cffi:cffi()` returns the raw cffi-lua table, not the reduced
---     `CFFIInterface` wrapper, so `load` and `string` are reachable.
---   * cffi-lua's parser maps `__stdcall` to `C_FUNC_STDCALL` rather than
---     discarding it, which matters because the game is 32-bit.
--- Not yet run against a real game process.

local M = {}

M.PIXEL_FORMAT_32BPP_ARGB = 0x0026200A
M.IMAGE_LOCK_MODE_READ = 1
M.IMAGE_LOCK_MODE_WRITE = 2
M.IMAGE_LOCK_MODE_USER_INPUT_BUF = 4

M.CP_UTF8 = 65001

local CDEF = [[
typedef unsigned long ULONG_PTR;

typedef struct GdiplusStartupInput {
  unsigned int GdiplusVersion;
  void *DebugEventCallback;
  int SuppressBackgroundThread;
  int SuppressExternalCodecs;
} GdiplusStartupInput;

typedef struct GpRect { int X, Y, Width, Height; } GpRect;

typedef struct BitmapData {
  unsigned int Width;
  unsigned int Height;
  int Stride;
  int PixelFormat;
  void *Scan0;
  ULONG_PTR Reserved;
} BitmapData;

typedef struct CLSID {
  unsigned long Data1;
  unsigned short Data2;
  unsigned short Data3;
  unsigned char Data4[8];
} CLSID;

int __stdcall GdiplusStartup(ULONG_PTR *token, const GdiplusStartupInput *input, void *output);
void __stdcall GdiplusShutdown(ULONG_PTR token);

int __stdcall GdipCreateBitmapFromFile(const wchar_t *filename, void **bitmap);
int __stdcall GdipCreateBitmapFromScan0(int width, int height, int stride, int format,
                                        unsigned char *scan0, void **bitmap);
int __stdcall GdipGetImageWidth(void *image, unsigned int *width);
int __stdcall GdipGetImageHeight(void *image, unsigned int *height);
int __stdcall GdipBitmapLockBits(void *bitmap, const GpRect *rect, unsigned int flags,
                                 int format, BitmapData *lockedBitmapData);
int __stdcall GdipBitmapUnlockBits(void *bitmap, BitmapData *lockedBitmapData);
int __stdcall GdipSaveImageToFile(void *image, const wchar_t *filename,
                                  const CLSID *clsidEncoder, const void *encoderParams);
int __stdcall GdipDisposeImage(void *image);

int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags,
                                  const char *lpMultiByteStr, int cbMultiByte,
                                  wchar_t *lpWideCharStr, int cchWideChar);
]]

--- Status codes worth naming; everything else is reported numerically.
local STATUS = {
  [0] = "Ok",
  [1] = "GenericError",
  [2] = "InvalidParameter",
  [3] = "OutOfMemory",
  [4] = "ObjectBusy",
  [5] = "InsufficientBuffer",
  [6] = "NotImplemented",
  [7] = "Win32Error",
  [8] = "WrongState",
  [9] = "Aborted",
  [10] = "FileNotFound",
  [11] = "ValueOverflow",
  [12] = "AccessDenied",
  [13] = "UnknownImageFormat",
  [18] = "PropertyNotFound",
  [20] = "GdiplusNotInitialized",
}

function M.statusName(status)
  return STATUS[status] or string.format("status %d", status)
end

--- Initialises the bindings. Call once, at module enable.
---
---@param ffi table the cffi interface
---@return table bound { gdiplus, kernel32, token, pngEncoder }
function M.initialize(ffi)
  ffi.cdef(CDEF)

  local gdiplus = ffi.load("gdiplus")
  local kernel32 = ffi.load("kernel32")

  local input = ffi.new("GdiplusStartupInput[1]")
  input[0].GdiplusVersion = 1
  input[0].DebugEventCallback = nil
  input[0].SuppressBackgroundThread = 0
  input[0].SuppressExternalCodecs = 0

  local token = ffi.new("ULONG_PTR[1]")
  local status = gdiplus.GdiplusStartup(token, input, nil)
  if status ~= 0 then
    error(string.format("map-png: GdiplusStartup failed: %s", M.statusName(status)))
  end

  -- {557CF406-1A04-11D3-9A73-0000F81EF32E}
  local pngEncoder = ffi.new("CLSID[1]")
  pngEncoder[0].Data1 = 0x557CF406
  pngEncoder[0].Data2 = 0x1A04
  pngEncoder[0].Data3 = 0x11D3
  local tail = { 0x9A, 0x73, 0x00, 0x00, 0xF8, 0x1E, 0xF3, 0x2E }
  for i = 1, 8 do
    pngEncoder[0].Data4[i - 1] = tail[i]
  end

  return {
    ffi = ffi,
    gdiplus = gdiplus,
    kernel32 = kernel32,
    token = token,
    pngEncoder = pngEncoder,
  }
end

--- Releases GDI+. Call at module disable.
function M.shutdown(bound)
  if bound and bound.token then
    bound.gdiplus.GdiplusShutdown(bound.token[0])
    bound.token = nil
  end
end

--- UTF-8 path -> a NUL-terminated wchar_t buffer.
function M.widePath(bound, path)
  local ffi = bound.ffi
  local needed = bound.kernel32.MultiByteToWideChar(M.CP_UTF8, 0, path, -1, nil, 0)
  if needed <= 0 then
    error(string.format("map-png: cannot convert path to UTF-16: %s", path))
  end
  local buffer = ffi.new("wchar_t[?]", needed)
  local written = bound.kernel32.MultiByteToWideChar(M.CP_UTF8, 0, path, -1, buffer, needed)
  if written <= 0 then
    error(string.format("map-png: cannot convert path to UTF-16: %s", path))
  end
  return buffer
end

return M
