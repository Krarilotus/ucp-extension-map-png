-- File-selection state, kept independent of game memory and rendering.
local paths = require("mappng.paths")
local layout = require("mappng.ui.pickerlayout")
local M = {}

function M.new(mode, what, folder, names, defaultName)
  assert(mode == "import" or mode == "export", "invalid PNG operation")
  assert(what == "height" or what == "terrain", "invalid PNG layer")
  local self = { mode = mode, what = what, folder = folder, names = {},
    name = mode == "export" and defaultName or "", offset = 0, pageSize = layout.pageSize }
  for _, name in ipairs(names) do
    if name:lower():match("%.png$") and pcall(paths.resolve, folder, name) then
      self.names[#self.names + 1] = name
    end
  end
  table.sort(self.names, function(a, b)
    if a:lower() == b:lower() then return a < b end
    return a:lower() < b:lower()
  end)
  return setmetatable(self, { __index = M })
end

function M:select(row)
  local name = self.names[self.offset + row]
  if name then self.name, self.overwrite = name, nil end
  return name
end

function M:scroll(delta)
  self.offset = math.max(0, math.min(math.max(0, #self.names - self.pageSize), self.offset + delta))
end

-- Native scrollbar protocol, matching SaveLoadMap's handler at 0x492BA0.
-- Engine owns thumb geometry, dragging and page clicks; we own only PNG state.
function M:nativeScroll(event, minimum, maximum, current)
  if event == 1 then
    minimum[0], maximum[0], current[0] = 0, math.max(0, #self.names - self.pageSize), self.offset
  elseif event == 3 then
    self:scroll(current[0] - self.offset)
    current[0] = self.offset
  elseif event == 4 then current[0] = self.offset
  elseif event == 5 or event == 6 then
    self:scroll(event == 5 and -1 or 1)
    current[0] = self.offset
  elseif event == 7 then current[0] = self.pageSize - 1 end
end

function M:edit(name)
  if name ~= self.name then self.name, self.overwrite = name, nil end
end

-- Returns a name only after validation and explicit overwrite confirmation.
function M:confirm(exists)
  local ok, path = pcall(paths.resolve, self.folder, self.name)
  if not ok then return nil, "invalid_name" end
  if self.mode == "import" then
    if not exists(path) then return nil, "missing_file" end
  elseif exists(path) and self.overwrite ~= path then
    self.overwrite = path
    return nil, "overwrite"
  end
  return self.name
end

return M
