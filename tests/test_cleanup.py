import unittest
import lua_harness


class Cleanup(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.lua.execute("""
          events={}; calls=0; noRubble=7; unitState=2
          local function zeros() return setmetatable({}, {__index=function() return 0 end}) end
          live={height=zeros(),defaultHeight=zeros(),logic1=zeros(),logic2=zeros()}
          proposed={height=zeros(),defaultHeight=zeros(),logic1=zeros(),logic2=zeros()}
          active={['building:1']=true,['building:2']=true}
          adapter={objects={
              ['building:1']={kind='building',id=1,type=1,uid=101,tiles={1}},
              ['building:2']={kind='building',id=2,type=1,uid=102,tiles={2}}},
            capacity={building=3,tree=2,rock=2},tileCount=4,
            bases={building=100},buildings=zeros(),landscape=zeros(),units=zeros(),
            misc=zeros(),was=zeros(),damage=zeros()}
          adapter.active=function(kind,id) return active[kind..':'..id] end
          adapter.identity=function(kind,id) return 100+id end
          adapter.record=function(kind,id) return 1000+id*1000 end
          adapter.neighbours=function() return {} end
          adapter.wall=function() return false end
          package.loaded['mappng.map.objects']={WALL_MASK=0x00410B00,open=function() return adapter end}
          package.loaded['mappng.native']={resolve=function()
            return {base=100,functions={building=1,tree=2,rock=3,wall=4},
              noRubble=200,units=300,unitCapacity=2} end}
          ffi={cast=function(ctype,address)
            if ctype=='void *' then return address end
            return function(this,id)
              calls=calls+1; events[#events+1]='remove'..id
              assert(noRubble==1)
              active['building:'..id]=false
              if nativeFailure then error('native failure') end
              if changeUnit then unitState=3 end
              if leaveFootprint then adapter.buildings[1]=1 end
              if changeRetained then adapter.misc[2]=1 end
              noRubble=0
            end
          end}
          core={readSmallInteger=function() return unitState end,
            readInteger=function() return noRubble end,
            writeInteger=function(_,value) noRubble=value end,
            writeSmallInteger=function(_,value) assert(value==0) end}
          cleanup=require('mappng.map.cleanup')
          function prepare() return cleanup.prepare(core,ffi,{base=100,layers=live},proposed) end
        """)

    def test_only_conflicting_building_removed_and_rubble_cleared(self):
        self.lua.execute("""
          proposed.defaultHeight[1]=1
          adapter.misc[1]=0x6000; adapter.was[1]=8; adapter.damage[1]=9
          local remove=prepare(); assert(calls==0); remove()
          assert(calls==1 and not active['building:1'] and active['building:2'])
          assert(adapter.misc[1]==0 and adapter.was[1]==0 and adapter.damage[1]==0)
          assert(noRubble==7)
        """)

    def test_no_change_does_not_delete_anything(self):
        self.lua.execute("prepare()(); assert(calls==0)")

    def test_retained_occupancy_and_raised_height_are_masked(self):
        self.lua.execute("""
          live.height[2]=8; live.logic1[2]=0x8400; proposed.logic1[2]=0x8000
          prepare()(); assert(calls==0 and proposed.height[2]==8 and proposed.logic1[2]==0x8400)
        """)

    def test_siege_unit_conflict_aborts_before_mutation(self):
        self.lua.execute("""
          adapter.objects['building:1'].type=80; proposed.defaultHeight[1]=1
          assert(not pcall(prepare)); assert(calls==0)
        """)

    def test_native_failure_restores_rubble_switch(self):
        self.lua.execute("""
          proposed.defaultHeight[1]=1; nativeFailure=true
          local remove=prepare(); assert(not pcall(remove)); assert(noRubble==7)
        """)

    def test_unit_state_change_or_leftover_footprint_blocks_commit(self):
        for flag in ('changeUnit','leaveFootprint','changeRetained'):
            self.setUp()
            self.lua.execute(f"""
              proposed.defaultHeight[1]=1; {flag}=true
              local remove=prepare(); assert(not pcall(remove))
            """)

    def test_linked_native_cascade_can_remove_selected_later_record(self):
        self.lua.execute("""
          local a={capacity={building=3,tree=1,rock=1},tileCount=0}
          a.preflight=function() end
          a.active=function(_,id) return active['building:'..id] end
          a.remove=function(_,id) calls=calls+1; active['building:1']=false; active['building:2']=false end
          a.verify=function() end
          cleanup.execute(a,{remove={['building:1']=true,['building:2']=true}})
          assert(calls==1)
        """)

    def test_staging_required_no_whole_map_fallback(self):
        self.lua.execute("assert(not pcall(cleanup.prepare,core,ffi,{base=100,layers=live})); assert(calls==0)")

    def test_failed_preflight_never_deletes(self):
        self.lua.execute("""
          local a={preflight=function() error('occupied wall') end,
            remove=function() error('MUTATION') end}
          local ok,err=pcall(cleanup.execute,a,{remove={}})
          assert(not ok and tostring(err):find('occupied wall'))
        """)

    def test_no_full_eraser_or_unit_deletion(self):
        source=(lua_harness.ROOT/'mappng/map/cleanup.lua').read_text().lower()
        for forbidden in ('0x508ec0','0x5017c0','0x53e790','ffi.fill'):
            self.assertNotIn(forbidden,source)
