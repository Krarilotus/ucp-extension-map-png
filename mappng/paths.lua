--- mappng/paths.lua
---
--- Locates the game directory and the PNG folder inside it, creating the
--- latter if it is not there yet.
---
--- The folder is deliberately a sibling of `ucp/` rather than something inside
--- it: these are the user's own map PNGs, and a UCP reinstall should not touch
--- them.

local M = {}

local CDEF = [[
unsigned long __stdcall GetModuleFileNameA(void *hModule, char *lpFilename, unsigned long nSize);
int __stdcall CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);
unsigned long __stdcall GetLastError(void);
unsigned long __stdcall GetFileAttributesA(const char *lpFileName);
unsigned long __stdcall GetModuleFileNameW(void *module, wchar_t *filename, unsigned long capacity);
int __stdcall CreateDirectoryW(const wchar_t *path, void *security);
typedef struct MapPngFindData {
  unsigned long attributes;
  unsigned long times[6];
  unsigned long sizeHigh, sizeLow, reserved0, reserved1;
  wchar_t name[260];
  wchar_t alternateName[14];
} MapPngFindData;
void * __stdcall FindFirstFileW(const wchar_t *pattern, MapPngFindData *data);
int __stdcall FindNextFileW(void *handle, MapPngFindData *data);
int __stdcall FindClose(void *handle);
unsigned long __stdcall GetFileAttributesW(const wchar_t *path);
int __stdcall WideCharToMultiByte(unsigned int cp, unsigned long flags,
  const wchar_t *text, int length, char *out, int capacity, const char *replacement, int *used);
void * __stdcall CreateFileW(const wchar_t *path, unsigned long access, unsigned long share,
  void *security, unsigned long disposition, unsigned long flags, void *templateFile);
unsigned long __stdcall GetFileSize(void *file, unsigned long *high);
int __stdcall ReadFile(void *file, void *buffer, unsigned long size, unsigned long *read, void *overlapped);
int __stdcall CloseHandle(void *handle);
void * __stdcall ShellExecuteW(void *window, const wchar_t *operation,
  const wchar_t *file, const wchar_t *parameters, const wchar_t *directory, int show);
]]

local ERROR_ALREADY_EXISTS = 183
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10

M.DEFAULT_FOLDER = "mapping"

local state = {}

local function wide(path)
  return require("mappng.png.gdiplus").widePath(state, path)
end

local function multibyte(buffer, codepage)
  local ffi, kernel = state.ffi, state.kernel32
  local length = kernel.WideCharToMultiByte(codepage, 0, buffer, -1, nil, 0, nil, nil)
  assert(length > 0, "map-png: invalid file name encoding")
  local result = ffi.new("char[?]", length)
  assert(kernel.WideCharToMultiByte(codepage, 0, buffer, -1, result, length, nil, nil) > 0)
  return ffi.string(result)
end

-- Game text entry is ANSI; filesystem/PNG paths in the module are UTF-8.
function M.setGameCodepage(codepage) state.gameCodepage = codepage end
function M.toGameText(value) return multibyte(wide(value), state.gameCodepage or 0) end
function M.fromGameText(value)
  local ffi, kernel = state.ffi, state.kernel32
  local count = kernel.MultiByteToWideChar(state.gameCodepage or 0, 0, value, -1, nil, 0)
  assert(count > 0, "map-png: invalid input encoding")
  local buffer = ffi.new("wchar_t[?]", count)
  assert(kernel.MultiByteToWideChar(state.gameCodepage or 0, 0, value, -1, buffer, count) > 0)
  return multibyte(buffer, 65001)
end

function M.readBinary(path, limit)
  local ffi, kernel = state.ffi, state.kernel32
  local file = kernel.CreateFileW(wide(path), 0x80000000, 7, nil, 3, 128, nil)
  assert((ffi.tonumber or tonumber)(ffi.cast("unsigned long", file)) ~= 0xFFFFFFFF,
    "map-png: cannot read " .. path)
  local ok, result = pcall(function()
    local size = (ffi.tonumber or tonumber)(kernel.GetFileSize(file, nil))
    assert(size <= limit, "map-png: file exceeds reading limit")
    local buffer, read = ffi.new("unsigned char[?]", math.max(1, size)), ffi.new("unsigned long[1]")
    assert(kernel.ReadFile(file, buffer, size, read, nil) ~= 0 and read[0] == size,
      "map-png: incomplete file read")
    return ffi.string(buffer, size)
  end)
  kernel.CloseHandle(file)
  if not ok then error(result, 0) end
  return result
end

--- One-time FFI setup.
function M.initialize(ffi)
  ffi.cdef(CDEF)
  state.ffi = ffi
  state.kernel32 = ffi.load("kernel32")
end

--- Directory of the running executable, without a trailing separator.
function M.gameDirectory()
  local ffi = state.ffi
  local buffer = ffi.new("wchar_t[?]", 520)
  local length = state.kernel32.GetModuleFileNameW(nil, buffer, 520)
  if length == 0 or length >= 520 then
    error("map-png: GetModuleFileNameA failed")
  end

  local full = multibyte(buffer, 65001)
  local directory = full:match("^(.*)[\\/][^\\/]*$")
  if directory == nil then
    error(string.format("map-png: cannot derive a directory from %s", full))
  end
  return directory
end

local function isDirectory(path)
  local attributes = state.kernel32.GetFileAttributesW(wide(path))
  if attributes == INVALID_FILE_ATTRIBUTES then
    return false
  end
  return (attributes & FILE_ATTRIBUTE_DIRECTORY) ~= 0
end

-- Open a verified directory with Windows' folder handler, without a shell command
-- string. Spaces/Unicode are passed as one wide path; no PNG is executed.
function M.openFolder(path)
  assert(isDirectory(path), "map-png: PNG folder does not exist")
  local ffi = state.ffi
  state.shell32 = state.shell32 or ffi.load("shell32")
  local result = state.shell32.ShellExecuteW(nil, wide("open"), wide(path), nil, nil, 1)
  local code = (ffi.tonumber or tonumber)(ffi.cast("long", result))
  assert(code > 32, "map-png: could not open PNG folder (" .. tostring(code) .. ")")
  return true
end

--- Ensures `<game>/<folder>/` exists and returns its absolute path.
---
--- Only a single, non-nested folder name is accepted. The value comes from
--- user options, and nothing downstream should be able to turn it into a path
--- that escapes the game directory.
---
---@param folder string|nil defaults to "mapping"
---@return string absolute path, without a trailing separator
function M.ensurePngFolder(folder)
  folder = folder or M.DEFAULT_FOLDER

  if folder == "" or folder:match("[\\/:]") or folder == "." or folder == ".." then
    error(string.format(
      "map-png: '%s' is not a usable folder name; it must be a single name "
      .. "directly inside the game directory", folder))
  end

  local path = M.gameDirectory() .. "\\" .. folder

  if isDirectory(path) then
    return path
  end

  if state.kernel32.CreateDirectoryW(wide(path), nil) == 0 then
    local err = state.kernel32.GetLastError()
    if err ~= ERROR_ALREADY_EXISTS then
      error(string.format("map-png: cannot create %s (error %d)", path, tonumber(err)))
    end
  end

  return path
end

--- Joins a folder and a bare file name, rejecting anything with a separator in
--- it. The file dialogs only ever hand us a name, never a path.
function M.resolve(folder, name, extension)
  if name == nil or name == "" then
    error("map-png: no file name given")
  end
  if name:match('[%z\1-\31\\/:*?"<>|]') or name:find("%.%.")
    or name:match("[ .]$") then
    error(string.format("map-png: '%s' is not a usable file name", name))
  end

  local stem = (name:match("^([^.]+)") or ""):upper()
  if stem == "" then error("map-png: no file name given") end
  if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL"
    or stem:match("^COM[1-9]$") or stem:match("^LPT[1-9]$") then
    error("map-png: reserved file name")
  end

  extension = extension or ".png"
  if not name:lower():match("%.png$") then
    name = name .. extension
  end

  return folder .. "\\" .. name
end

function M.exists(path)
  local attributes = state.kernel32.GetFileAttributesW(wide(path))
  return attributes ~= INVALID_FILE_ATTRIBUTES and (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0
end

function M.listPngs(folder)
  local ffi, kernel = state.ffi, state.kernel32
  local data = ffi.new("MapPngFindData[1]")
  local handle = kernel.FindFirstFileW(wide(folder .. "\\*.png"), data)
  if (ffi.tonumber or tonumber)(ffi.cast("unsigned long", handle)) == 0xFFFFFFFF then
    local code = (ffi.tonumber or tonumber)(kernel.GetLastError())
    if code == 2 or code == 18 then return {} end
    error("map-png: cannot list PNG folder (" .. code .. ")")
  end
  local names = {}
  local ok, err = pcall(function()
    repeat
      if (data[0].attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 then
        names[#names + 1] = multibyte(data[0].name, 65001)
      end
    until kernel.FindNextFileW(handle, data) == 0
    assert(kernel.GetLastError() == 18, "map-png: PNG folder enumeration failed")
  end)
  kernel.FindClose(handle)
  if not ok then error(err, 0) end
  return names
end

return M
