-- Read-only conflict planning. Native record discovery/teardown belongs to the
-- adapter, not this module. Every object must supply its COMPLETE footprint.
local M = {}
local suitability=require('mappng.map.suitability')

M.PROTECTED = { [10]=true, [40]=true, [41]=true, [42]=true, [43]=true,
  [44]=true, [51]=true, [55]=true, [71]=true, [72]=true, [73]=true }

-- objects: keyed by stable kind:id; {kind,type,owner,group,tiles={...}}.
-- neighbours(tile): iterable list of edge-adjacent tile IDs, supplied by the
-- verified map geometry adapter. Never infer adjacency from serialized tile+1.
function M.build(old, proposed, objects, tileCount, neighbours, placement)
  local result = { remove={}, keep={}, mask={} }
  local parents, groups, protectedAt = {}, {}, {}
  local function root(id)
    while parents[id] ~= id do
      parents[id] = parents[parents[id]]
      id = parents[id]
    end
    return id
  end
  local function join(a,b) parents[root(a)] = root(b) end
  for id, object in pairs(objects) do
    assert(object.kind and object.tiles and #object.tiles > 0,
      'map-png: missing complete object footprint: ' .. tostring(id))
    parents[id] = id
    local seen = {}
    for _, tile in ipairs(object.tiles) do
      assert(math.type(tile) == 'integer' and tile >= 0 and tile < tileCount,
        'map-png: invalid object footprint')
      assert(not seen[tile], 'map-png: duplicate footprint tile')
      seen[tile] = true
      if object.kind == 'building' and M.PROTECTED[object.type] then
        assert(object.owner ~= nil, 'map-png: missing protected structure owner')
        protectedAt[tile] = protectedAt[tile] or {}
        table.insert(protectedAt[tile], id)
      end
    end
    if suitability.conflict(old,proposed,object,placement and placement(object)) then result.remove[id]=true end
    if object.kind == 'building' and object.group and object.group ~= 0 then
      -- Native deletion uses this group globally, not per owner/type.
      if groups[object.group] then join(id, groups[object.group])
      else groups[object.group] = id end
    end
  end
  for id, object in pairs(objects) do
    for _, linked in ipairs(object.links or {}) do
      assert(objects[linked], 'map-png: dangling linked object')
      join(id, linked)
    end
  end
  for tile, ids in pairs(protectedAt) do
    local adjacent = assert(neighbours, 'map-png: protected structure geometry required')(tile)
    -- Also join overlapping protected footprints.
    local others = {tile}
    for _, neighbour in ipairs(adjacent) do others[#others+1] = neighbour end
    for _, a in ipairs(ids) do
      for _, neighbour in ipairs(others) do
        for _, b in ipairs(protectedAt[neighbour] or {}) do
          if objects[a].owner == objects[b].owner then join(a,b) end
        end
      end
    end
  end
  local changed
  repeat
    changed=false
    local removedGroups = {}
    for id in pairs(result.remove) do removedGroups[root(id)] = true end
    result.keep,result.mask={},{}
    for id, object in pairs(objects) do
      if removedGroups[root(id)] then result.remove[id] = true
      else
        result.keep[id] = true
        for _, tile in ipairs(object.tiles) do result.mask[tile] = true end
      end
    end
    for id in pairs(result.keep) do
      if suitability.edgeConflict(old,proposed,objects[id],result.mask,
        assert(neighbours,'map-png: terrain adjacency required')) then
        result.remove[id]=true; changed=true
      end
    end
  until not changed
  -- Overlapping retained/deleted objects are not safe for native teardown.
  -- Fail before mutation instead of silently removing a compatible neighbour.
  for id in pairs(result.remove) do
    for _, tile in ipairs(objects[id].tiles) do
      assert(not result.mask[tile], 'map-png: conflicting overlapping object footprints')
    end
  end
  return result
end

-- Preserve occupancy flags AND raised building/wall heights. Called before
-- cleanup, while all live values still represent the retained objects.
function M.mask(plan, old, proposed)
  for tile in pairs(plan.mask) do
    for _, field in ipairs({'height','defaultHeight','logic1','logic2'}) do
      if proposed[field] then proposed[field][tile] = old[field][tile] end
    end
  end
end

return M
