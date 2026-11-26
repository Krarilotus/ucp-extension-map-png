-- Versioned, data-only per-map link state. The lifecycle adapter supplies a
-- verified saved-map identity; the persistence adapter handles atomic JSON IO.
-- Neither native .map files nor filenames typed into the PNG picker are keys.
local M = {}
local function copy(value) return {height=value.height, terrain=value.terrain} end

function M.new(storage, validName, exists)
  local records, current, key = {}, {}, nil
  local self = {}
  function self.restore(data)
    assert(type(data) == 'table' and data.version == 1 and type(data.maps) == 'table',
      'map-png: unsupported link file')
    local checked = {}
    for identity, names in pairs(data.maps) do
      assert(type(identity) == 'string' and #identity > 0 and #identity <= 4096,
        'map-png: invalid saved map identity')
      assert(type(names) == 'table', 'map-png: invalid linked PNG names')
      local entry = {}
      for _, kind in ipairs({'height','terrain'}) do
        local name = names[kind]
        if name ~= nil then
          assert(type(name) == 'string' and validName(name), 'map-png: invalid linked PNG name')
          entry[kind] = name
        end
      end
      checked[identity] = entry
    end
    records = checked -- malformed files never replace a previously valid index
    current = key and copy(records[key] or {}) or {}
  end
  local function persist()
    if key then records[key] = copy(current) end
    local maps = {}
    for identity, names in pairs(records) do maps[identity] = copy(names) end
    storage({version=1, maps=maps})
  end
  -- New unsaved maps use nil and never reuse the previous unsaved map's links.
  function self.open(identity)
    key = identity
    current = key and copy(records[key] or {}) or {}
    self.validate()
  end
  -- Call only after a native save succeeds. Save As transfers the current links
  -- while retaining the old map's independent entry.
  function self.saved(identity)
    assert(type(identity) == 'string' and identity ~= '', 'map-png: saved map identity required')
    key = identity
    persist()
  end
  function self.link(kind, name)
    assert(kind == 'height' or kind == 'terrain', 'map-png: invalid link layer')
    assert(type(name) == 'string' and validName(name), 'map-png: invalid linked PNG name')
    assert(exists(name), 'map-png: linked PNG is missing')
    current[kind] = name
    if key then persist() end
  end
  function self.validate()
    local missing = {}
    for _, kind in ipairs({'height','terrain'}) do
      local name = current[kind]
      if name and not exists(name) then
        missing[kind], current[kind] = name, nil
      end
    end
    if next(missing) and key then persist() end
    return missing
  end
  function self.names() return copy(current) end
  -- Do not silently run a partial refresh if one member disappeared. Invalidate
  -- it, notify through the caller, and allow a subsequent explicit refresh.
  function self.forRefresh()
    local missing = self.validate()
    if next(missing) then return nil, missing end
    return copy(current)
  end
  return self
end
return M
