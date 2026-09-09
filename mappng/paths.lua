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
]]

local ERROR_ALREADY_EXISTS = 183
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10

M.DEFAULT_FOLDER = "mapping"

local state = {}

--- One-time FFI setup.
function M.initialize(ffi)
  ffi.cdef(CDEF)
  state.ffi = ffi
  state.kernel32 = ffi.load("kernel32")
end

--- Directory of the running executable, without a trailing separator.
function M.gameDirectory()
  local ffi = state.ffi
  local buffer = ffi.new("char[?]", 520)
  local length = state.kernel32.GetModuleFileNameA(nil, buffer, 520)
  if length == 0 then
    error("map-png: GetModuleFileNameA failed")
  end

  local full = ffi.string(buffer, length)
  local directory = full:match("^(.*)[\\/][^\\/]*$")
  if directory == nil then
    error(string.format("map-png: cannot derive a directory from %s", full))
  end
  return directory
end

local function isDirectory(path)
  local attributes = state.kernel32.GetFileAttributesA(path)
  if attributes == INVALID_FILE_ATTRIBUTES then
    return false
  end
  return (attributes & FILE_ATTRIBUTE_DIRECTORY) ~= 0
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

  if state.kernel32.CreateDirectoryA(path, nil) == 0 then
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
  if name:match("[\\/:]") or name:find("%.%.") then
    error(string.format("map-png: '%s' is not a usable file name", name))
  end

  extension = extension or ".png"
  if not name:lower():match("%.png$") then
    name = name .. extension
  end

  return folder .. "\\" .. name
end

return M
