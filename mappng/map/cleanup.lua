-- Live editor cleanup, not sourcehold-style section zeroing. Normal 1.41 only.
-- Native teardown owns footprint, owner and linked-record bookkeeping.
local M = {}
M.WALL_MASK = 0x00410B00 -- mask cleared by spawnEraserTileEffect
M.BINDINGS = {
  building = {0x421990, 0x748B5655},
  tree = {0x4F2070, 0x7C8B5756},
  rock = {0x4F2220, 0x24748B56},
  wall = {0x4F9F00, 0x748B5655},
}

-- Kept separate from FFI so ordering and fail-closed behavior are testable.
function M.execute(adapter)
  adapter.preflight() -- read-only; must finish before the first deletion
  for _, kind in ipairs({'building', 'tree', 'rock'}) do
    for id = 1, adapter.capacity[kind] - 1 do
      -- Deleting a linked building can already have deleted a later record.
      if adapter.active(kind, id) then adapter.remove(kind, id) end
    end
  end
  for tile = 0, adapter.tileCount - 1 do
    if adapter.wall(tile) then adapter.removeWall(tile) end
  end
  adapter.verify()
end

function M.prepare(core, ffi, view)
  assert(view.build == 'Crusader 1.41' and view.base == 0x1A93208,
    'map-png: cleanup is only supported on Crusader 1.41')
  local native = {}
  for name, spec in pairs(M.BINDINGS) do
    assert((core.readInteger(spec[1]) & 0xFFFFFFFF) == spec[2],
      'map-png: unrecognized native cleanup function: ' .. name)
    native[name] = ffi.cast(name == 'wall'
      and 'void (__thiscall *)(void *, int, int)'
      or 'void (__thiscall *)(void *, int)', spec[1])
  end
  local bases = {building=0xF98520, tree=0xF2CC38, rock=0xF2CC38}
  local records = {
    building={offset=0x14, stride=0x32C, active=0xD0},
    tree={offset=0x1C, stride=0x9C, active=0x44},
    rock={offset=0x4C2F8, stride=0x20, active=0xC},
  }
  local a = {capacity={building=2000, tree=2000, rock=4000}, tileCount=80400}
  local function short(address) return core.readSmallInteger(address) end
  local function record(kind, id)
    local r = records[kind]
    return bases[kind] + r.offset + id * r.stride
  end
  function a.active(kind, id) return short(record(kind, id) + records[kind].active) ~= 0 end
  local buildings = ffi.cast('uint16_t *', view.base + 0x2029B0)
  local landscape = ffi.cast('uint16_t *', view.base + 0x1DB590)
  local units = ffi.cast('uint16_t *', view.base + 0x23D7E0)
  local misc = ffi.cast('uint16_t *', view.base + 0x301C80)
  -- Native destroyEntitiesOnTile schedules decorations (types 10..15) for
  -- deletion and clears their display flag. Eraser effects expire normally.
  function a.wall(tile)
    return (view.layers.logic1[tile] & M.WALL_MASK) ~= 0 or (misc[tile] & 0x1000) ~= 0
  end
  local unitStates = {}
  function a.preflight()
    -- updateBuildings (0x422E20) periodically resets this high-water mark to
    -- zero, then raises it to highest active ID + 1. It is NOT allocation size:
    -- an empty map changes from the initial 2000 to 0 after entering map view.
    local buildingScanLimit = core.readInteger(0xF98528)
    assert(buildingScanLimit >= 0 and buildingScanLimit <= a.capacity.building,
      'map-png: invalid building scan limit: ' .. tostring(buildingScanLimit))
    for kind, count in pairs(a.capacity) do
      assert(not a.active(kind, 0), 'map-png: occupied sentinel record')
      for id = 1, count - 1 do
        if kind == 'building' and buildingScanLimit == 0 then
          assert(not a.active(kind, id),
            'map-png: zero building scan limit with active record ' .. id)
        end
        if a.active(kind, id) and kind ~= 'building' then
          local offset = kind == 'tree' and 0x68 or 4
          local tile = core.readInteger(record(kind, id) + offset)
          assert(tile >= 0 and tile < a.tileCount, 'map-png: invalid landscape tile')
        end
      end
    end
    for tile = 0, a.tileCount - 1 do
      assert(buildings[tile] < 2000, 'map-png: invalid building reference')
      -- Native wall erasure returns early on unit-occupied tiles. Never hide
      -- units temporarily or use the full brush (which marks units deleted).
      assert(not (a.wall(tile) and units[tile] ~= 0),
        'map-png: move units off structures/walls before importing')
    end
    for id = 0, 2499 do
      unitStates[id] = short(0x1387F38 + 0x614 + id * 0x490 + 0x8C)
    end
  end
  function a.remove(kind, id) native[kind](ffi.cast('void *', bases[kind]), id) end
  function a.removeWall(tile) native.wall(ffi.cast('void *', view.base), 0, tile) end
  function a.verify()
    for kind, count in pairs(a.capacity) do
      for id = 1, count - 1 do
        assert(not a.active(kind, id), 'map-png: native cleanup left an active ' .. kind)
      end
    end
    for tile = 0, a.tileCount - 1 do
      assert(buildings[tile] == 0 and landscape[tile] == 0 and not a.wall(tile),
        'map-png: native cleanup left an object footprint; PNG was not applied')
    end
    for id = 0, 2499 do
      assert(unitStates[id] == short(0x1387F38 + 0x614 + id * 0x490 + 0x8C),
        'map-png: unexpected unit-state change; PNG was not applied')
    end
  end
  -- Validate before handing control to the destructive phase.
  a.preflight()
  return function() M.execute(a) end
end
return M
