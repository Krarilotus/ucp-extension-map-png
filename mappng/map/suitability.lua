-- Terrain-only retention checks. Never invoke fresh-construction validators:
-- those reject the object's own occupancy/units and touch placement scratch state.
-- Building limits come from the native BuildingDefinedData tables (AoB-bound).
local M={CLIFF_DROP=20}
local function ground(old,proposed,tile)
  local h=proposed.defaultHeight and proposed.defaultHeight[tile] or old.defaultHeight[tile]
  -- Height exports contain building-raised surfaces, not just ground.
  return h==old.height[tile] and old.defaultHeight[tile] or h
end
M.ground=ground

function M.conflict(old,proposed,object,profile)
  local blocked=0xE03E4089 -- water, rocky ground, deposits, moat, marsh, pitch
  if object.kind=='building' then
    assert(profile,'map-png: missing native building terrain profile')
    -- Ground exclusions from isBuildingPlacementAllowedAtTile. Deposits are
    -- not generic blockers there; resource requirements are checked below.
    blocked=0x603000B1 -- sea, border, river, ford, rocky ground, marsh, moat
    if profile.rocky~=0 then blocked=blocked & ~0x80 end
    if profile.marsh~=0 then blocked=blocked & ~0x20000000 end
    if profile.moat~=0 then blocked=blocked & ~0x40000000 end
  elseif object.kind=='rock' then
    blocked=blocked & ~0x80 -- this flag belongs to the rock itself
  end
  local oldMin,oldMax,newMin,newMax=255,0,255,0
  local resource=object.type==5 and 0x80000 or
    ((object.type==20 or object.type==21) and 0x20000 or (object.type==6 and 0x80000000 or nil))
  local required=object.type==5 and 4 or ((object.type==20 or object.type==21) and 8 or 1)
  local oldResource,newResource=0,0
  for _,tile in ipairs(object.tiles) do
    local before=old.logic1[tile]
    local after=proposed.logic1 and proposed.logic1[tile] or before
    -- Removal of an obstacle is not a reason to delete an existing object.
    if (after & ~before & blocked)~=0 then return 'new terrain obstruction' end
    local oldMoat=(before&0x8000)~=0 and old.logic2[tile]==3
    local newMoat=(after&0x8000)~=0 and (proposed.logic2 or old.logic2)[tile]==3
    if newMoat and not oldMoat and not (profile and profile.moat~=0) then return 'new moat' end
    if object.kind=='building' and object.type>=30 and object.type<=33
      and (before&4)~=0 and (after&4)==0 then return 'lost fertile ground' end
    if resource then
      if (before&resource)~=0 then oldResource=oldResource+1 end
      if (after&resource)~=0 then newResource=newResource+1 end
    end
    local a,b=old.defaultHeight[tile],ground(old,proposed,tile)
    oldMin,oldMax=math.min(oldMin,a),math.max(oldMax,a)
    newMin,newMax=math.min(newMin,b),math.max(newMax,b)
  end
  if resource and newResource<math.min(required,oldResource) then return 'lost required resource' end
  if profile and proposed.defaultHeight then
    if newMax-newMin>math.max(profile.difference,oldMax-oldMin) then return 'uneven foundation' end
    if profile.limit>=0 then
      if newMax>math.max(profile.limit,oldMax) then return 'height limit' end
    elseif newMin<math.min(-profile.limit,oldMin) then return 'minimum height' end
  end
end

-- Evaluate the FINAL terrain: retained footprints are masked, removed ones are
-- not. Recheck after connected deletions; one deletion may expose another edge.
-- Eight neighbours include diagonal cliff edges, unlike group adjacency (four).
function M.edgeConflict(old,proposed,object,mask,neighbours)
  if not proposed.defaultHeight then return false end
  for _,tile in ipairs(object.tiles) do
    for _,adjacent in ipairs(neighbours(tile,true)) do
      local a=mask[tile] and old.defaultHeight[tile] or ground(old,proposed,tile)
      local b=mask[adjacent] and old.defaultHeight[adjacent] or ground(old,proposed,adjacent)
      local gap=math.abs(a-b)
      if gap>M.CLIFF_DROP and gap>math.abs(old.defaultHeight[tile]-old.defaultHeight[adjacent]) then
        return true
      end
    end
  end
  return false
end
return M
