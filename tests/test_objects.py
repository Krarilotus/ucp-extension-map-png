"""Exercise native footprint decoding without running native teardown."""
import unittest
import lua_harness


class Objects(unittest.TestCase):
    def setUp(self):
        self.lua=lua_harness.runtime()
        self.lua.execute('''
          local function zeros() return setmetatable({}, {__index=function() return 0 end}) end
          memory=zeros(); arrays={}; core={readInteger=function(a) return memory[a] end,
            readSmallInteger=function(a) return memory[a] end}
          ffi={cast=function(_,a) arrays[a]=arrays[a] or zeros(); return arrays[a] end}
          native={base=0x1000000,buildings=0x2000000,landscape=0x3000000,
            rowY=0x4000000,rows=0x5000000,shapes=0x6000000}
          view={base=native.base,layers={logic1=zeros()}}
          local pixels=require('mappng.map.diamond').buildTileToPixel()
          for tile,pixel in pairs(pixels) do
            local y=pixel//400; memory[native.rowY+tile*2]=y
            memory[native.rows+y*12]=tile-(pixel%400)
          end
          objects=require('mappng.map.objects')
          function open() return objects.open(core,ffi,view,native) end
          function building(id)
            local record=native.buildings+0x14+id*0x32C
            memory[native.buildings+8]=2
            memory[record+0xD0]=1; memory[record+0xD8]=id+100
            memory[record+0xD2]=1; memory[record+0xEE]=199; memory[record+0xF0]=199
            memory[record+0xF8]=2
            for i=0,3 do
              local entry=native.shapes+(2*169+i)*24
              memory[entry]=i%2; memory[entry+4]=i//2
            end
            return record
          end
        ''')

    def test_empty_map_zero_building_highwater_is_valid(self):
        self.lua.execute("assert(not next(open().objects))")

    def test_active_record_requires_nonzero_highwater(self):
        self.lua.execute("building(1); memory[native.buildings+8]=0; assert(not pcall(open))")

    def test_complete_footprint_not_just_occupancy_layer(self):
        self.lua.execute('''
          building(1); local a=open(); local b=a.objects['building:1']
          assert(#b.tiles==4 and b.uid==101 and b.type==1)
          assert(#a.neighbours(b.tiles[1])==4)
        ''')

    def test_dangling_occupancy_or_invalid_geometry_rejected(self):
        self.lua.execute('''
          ffi.cast('',native.base+0x2029B0)[0]=17
          assert(not pcall(open))
          arrays[native.base+0x2029B0][0]=0
          memory[native.rowY]=401; assert(not pcall(open))
        ''')

    def test_fields_and_owned_trees_join_building_footprint(self):
        self.lua.execute('''
          local b=building(1); memory[b+0xD2]=30
          for field=0,35 do memory[b+0x1C8+field*4]=field end
          view.layers.logic1[0]=0x04000000
          ffi.cast('',native.base+0x1DB590)[0]=1
          local tree=native.landscape+0x1C+0x9C
          memory[tree+0x44]=1; memory[tree+0x4C]=77
          memory[tree+0x62]=199; memory[tree+0x64]=0; memory[tree+0x6C]=1
          local a=open(); assert(#a.objects['building:1'].tiles==40)
          assert(a.objects['building:1'].links[1]=='tree:1' and a.objects['tree:1'].uid==77)
        ''')
