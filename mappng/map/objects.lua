-- Read-only native object/footprint adapter. Uses the game's initialized shape
-- table (the same data as getBuildingSizeIndexMappingData), without invoking a
-- placement probe or modifying its scratch globals.
local M = {}
M.records = {
  building={offset=0x14,stride=0x32C,active=0xD0,uid=0xD8},
  tree={offset=0x1C,stride=0x9C,active=0x44,uid=0x4C},
  rock={offset=0x4C2F8,stride=0x20,active=0xC,uid=8},
}
M.capacity={building=2000,tree=2000,rock=4000}
M.WALL_MASK=0x00410B00
function M.open(core, ffi, view, native)
  local a={objects={},capacity=M.capacity,tileCount=80400}
  local bases={building=native.buildings,tree=native.landscape,rock=native.landscape}
  a.bases=bases
  local function short(address) return core.readSmallInteger(address) & 0xFFFF end
  function a.record(kind,id)
    local r=M.records[kind]; return bases[kind]+r.offset+id*r.stride
  end
  function a.active(kind,id) return short(a.record(kind,id)+M.records[kind].active)~=0 end
  function a.identity(kind,id) return core.readInteger(a.record(kind,id)+M.records[kind].uid) end
  a.buildings=ffi.cast('uint16_t *',view.base+0x2029B0)
  a.landscape=ffi.cast('uint16_t *',view.base+0x1DB590)
  a.units=ffi.cast('uint16_t *',view.base+0x23D7E0)
  a.misc=ffi.cast('uint16_t *',view.base+0x301C80)
  a.was=ffi.cast('uint8_t *',view.base+0x229DD0)
  a.damage=ffi.cast('uint8_t *',view.base+0x3290A0)
  function a.wall(tile) return (view.layers.logic1[tile]&M.WALL_MASK)~=0 or (a.misc[tile]&0x1000)~=0 end
  local coordinates, at={},{}
  for tile=0,a.tileCount-1 do
    local y=short(native.rowY+tile*2)
    assert(y<400,'map-png: invalid tile row')
    local x=tile-core.readInteger(native.rows+y*12)
    assert(x>=0 and x<400,'map-png: invalid tile column')
    coordinates[tile]={x,y}; at[y*400+x]=tile
  end
  function a.neighbours(tile,diagonals)
    local p=coordinates[tile]; local list={}
    for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
      local x,y=p[1]+d[1],p[2]+d[2]
      local id=x>=0 and x<400 and y>=0 and y<400 and at[y*400+x]
      if id then list[#list+1]=id end
    end
    if diagonals then
      for _,d in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
        local x,y=p[1]+d[1],p[2]+d[2]
        local id=x>=0 and x<400 and y>=0 and y<400 and at[y*400+x]
        if id then list[#list+1]=id end
      end
    end
    return list
  end
  local profiles={}
  function a.placement(object)
    if object.kind~='building' then return nil end
    local id=object.type
    assert(id>=1 and id<110,'map-png: unsupported building type')
    if not profiles[id] then
      local function field(offset) return core.readInteger(native.placement+offset+id*4) end
      local p={limit=field(0x5DC),difference=field(0x794),rocky=field(0xB04),marsh=field(0xE74),moat=field(0x102C)}
      assert(math.abs(p.limit)<=255 and p.difference>=0 and p.difference<=255
        and p.rocky>=0 and p.rocky<=1 and p.marsh>=0 and p.marsh<=2 and p.moat>=0 and p.moat<=1,
        'map-png: unsupported building terrain rules')
      profiles[id]=p
    end
    return profiles[id]
  end
  local function add(object,tile)
    assert(coordinates[tile], 'map-png: invalid object tile')
    if not object.seen[tile] then object.seen[tile]=true; object.tiles[#object.tiles+1]=tile end
  end
  local function shape(object,x,y,size)
    assert(size>=1 and size<=13,'map-png: unsupported object footprint size')
    for i=0,size*size-1 do
      local entry=native.shapes+(size*169+i)*24
      local xx,yy=x+core.readInteger(entry),y+core.readInteger(entry+4)
      assert(xx>=0 and xx<400 and yy>=0 and yy<400,'map-png: object footprint outside map')
      add(object,at[yy*400+xx])
    end
  end
  local limit=core.readInteger(native.buildings+8)
  assert(limit>=0 and limit<=2000,'map-png: invalid building scan limit: '..limit)
  for kind,count in pairs(a.capacity) do
    assert(not a.active(kind,0),'map-png: occupied sentinel record')
    for id=1,count-1 do
      if a.active(kind,id) then
        assert(kind~='building' or limit~=0,'map-png: zero building scan limit with active record')
        local rec=a.record(kind,id)
        local object={kind=kind,id=id,uid=a.identity(kind,id),tiles={},seen={},links={}}
        a.objects[kind..':'..id]=object
        if kind=='building' then
          object.type=short(rec+0xD2); object.owner=short(rec+0xD6); object.group=core.readInteger(rec+0x2A8)
          local size=core.readInteger(rec+0xF8)
          shape(object,short(rec+0xEE),short(rec+0xF0),size)
          -- Farm fields are additional, individually referenced tiles; native
          -- teardown also removes apple trees on these tiles.
          local countFields=({[30]=36,[31]=24,[32]=8,[33]=27})[object.type] or 0
          for field=0,countFields-1 do
            local tile=core.readInteger(rec+0x1C8+field*4)
            add(object,tile)
            if (view.layers.logic1[tile]&0x04000000)~=0 and a.landscape[tile]~=0 then
              object.links[#object.links+1]='tree:'..tonumber(a.landscape[tile])
            end
          end
        else
          local tree=kind=='tree'
          add(object,core.readInteger(rec+(tree and 0x68 or 4)))
          shape(object,short(rec+(tree and 0x62 or 0x12)),short(rec+(tree and 0x64 or 0x14)),short(rec+(tree and 0x6C or 0x16)))
        end
      end
    end
  end
  for tile=0,a.tileCount-1 do
    local id=tonumber(a.buildings[tile])
    if id~=0 then
      local object=assert(a.objects['building:'..id],'map-png: dangling building reference')
      add(object,tile)
    elseif a.wall(tile) then
      a.objects['wall:'..tile]={kind='wall',id=tile,tiles={tile},seen={[tile]=true}}
    end
  end
  return a
end
return M
