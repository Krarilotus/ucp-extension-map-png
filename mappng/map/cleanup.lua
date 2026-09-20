-- Selective native teardown; never clear whole record tables or erase units.
local objects = require('mappng.map.objects')
local planner = require('mappng.map.importplan')
local bindings = require('mappng.native')
local M = {WALL_MASK=objects.WALL_MASK}

function M.execute(adapter, plan)
  adapter.preflight(plan)
  for _, kind in ipairs({'building','tree','rock'}) do
    for id=1,adapter.capacity[kind]-1 do
      if plan.remove[kind..':'..id] and adapter.active(kind,id) then adapter.remove(kind,id) end
    end
  end
  for tile=0,adapter.tileCount-1 do
    if plan.remove['wall:'..tile] and adapter.wall(tile) then adapter.removeWall(tile) end
  end
  adapter.verify(plan)
end

function M.prepare(core, ffi, view, proposed)
  assert(proposed, 'map-png: staged import required for selective cleanup')
  local native=bindings.resolve()
  assert(view.base==native.base, 'map-png: inconsistent native map layout')
  local a=objects.open(core,ffi,view,native)
  local plan=planner.build(view.layers,proposed,a.objects,a.tileCount,a.neighbours,a.placement)
  local calls={}
  for name,address in pairs(native.functions) do
    calls[name]=ffi.cast(name=='wall' and 'void (__thiscall *)(void *, int, int)'
      or 'void (__thiscall *)(void *, int)',address)
  end
  local states, retainedTiles={},{}
  local function unitState(id) return core.readSmallInteger(native.units+0x614+id*0x490+0x8C) end
  function a.preflight(selection)
    for key in pairs(selection.remove) do
      local object=a.objects[key]
      -- Siege machines are unit-backed buildings; native teardown would remove
      -- their unit. Never delete a unit through the building interface.
      assert(object.kind~='building' or not (object.type==69 or
        (object.type>=80 and object.type<=90)), 'map-png: import conflicts with a siege unit')
      if object.kind=='wall' then
        assert(a.units[object.id]==0,'map-png: move units off conflicting walls before importing')
      else
        assert(a.active(object.kind,object.id) and a.identity(object.kind,object.id)==object.uid,
          'map-png: object changed during import planning')
      end
    end
    for id=0,native.unitCapacity-1 do states[id]=unitState(id) end
    for tile in pairs(selection.mask) do
      retainedTiles[tile]={a.buildings[tile],a.landscape[tile],a.misc[tile],a.was[tile],a.damage[tile]}
    end
  end
  local rubblePrepared=false
  function a.remove(kind,id)
    if kind~='building' then calls[kind](ffi.cast('void *',a.bases[kind]),id); return end
    -- Native destruction handles linked duplicates and resets its global switch.
    if not rubblePrepared then
      for key in pairs(plan.remove) do
        local object=a.objects[key]
        if object.kind=='building' and a.active('building',object.id) then
          core.writeSmallInteger(a.record('building',object.id)+0xC4,0)
        end
      end
      rubblePrepared=true
    end
    local saved=core.readInteger(native.noRubble)
    core.writeInteger(native.noRubble,1)
    local ok,err=pcall(calls.building,ffi.cast('void *',a.bases.building),id)
    core.writeInteger(native.noRubble,saved)
    if not ok then error(err,0) end
  end
  function a.removeWall(tile) calls.wall(ffi.cast('void *',view.base),0,tile) end
  function a.verify(selection)
    for tile,values in pairs(retainedTiles) do
      assert(a.buildings[tile]==values[1] and a.landscape[tile]==values[2]
        and a.misc[tile]==values[3] and a.was[tile]==values[4] and a.damage[tile]==values[5],
        'map-png: native cleanup changed a retained footprint; PNG not applied')
    end
    for key,object in pairs(a.objects) do
      if object.kind~='wall' then
        if selection.remove[key] then
          assert(not a.active(object.kind,object.id),'map-png: native cleanup left an active '..object.kind)
        else
          assert(a.active(object.kind,object.id) and a.identity(object.kind,object.id)==object.uid,
            'map-png: native cleanup changed a retained object; PNG not applied')
        end
      end
    end
    for key in pairs(selection.remove) do
      local object=a.objects[key]
      for _,tile in ipairs(object.tiles) do
        assert(a.buildings[tile]==0 and a.landscape[tile]==0 and not a.wall(tile),
          'map-png: native cleanup left an object footprint; PNG not applied')
        if object.kind=='building' then
          -- Clear ruins only on the erased footprint, never neighbouring ruins.
          a.misc[tile]=a.misc[tile]&0x9FFF
          a.was[tile]=0; a.damage[tile]=0
        end
      end
    end
    for id=0,native.unitCapacity-1 do
      assert(states[id]==unitState(id),'map-png: unexpected unit-state change; PNG not applied')
    end
  end
  a.preflight(plan)
  planner.mask(plan,view.layers,proposed)
  return function() M.execute(a,plan) end
end
return M
