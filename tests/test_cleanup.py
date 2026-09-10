import unittest
import struct
import lua_harness
from test_tilemap_binary import PEImage, GAME_DIR


class Cleanup(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.module = lua_harness.load(self.lua, 'mappng.map.cleanup')
        self.lua.globals().cleanup = self.module

    def test_teardown_order_and_linked_duplicates(self):
        self.lua.execute('''
          local events, live = {}, {building={[1]=true,[2]=true},tree={[1]=true},rock={[1]=true}}
          local a={capacity={building=3,tree=2,rock=2},tileCount=2}
          a.preflight=function() events[#events+1]='preflight' end
          a.active=function(k,id) return live[k][id] end
          a.remove=function(k,id)
            events[#events+1]=k..id; live[k][id]=nil
            if k=='building' then live.building[2]=nil end
          end
          a.wall=function(t) return t==1 end
          a.removeWall=function(t) events[#events+1]='wall'..t end
          a.verify=function() events[#events+1]='verify' end
          cleanup.execute(a)
          assert(table.concat(events,',')=='preflight,building1,tree1,rock1,wall1,verify')
        ''')

    def test_failed_preflight_never_deletes(self):
        self.lua.execute('''
          local a={preflight=function() error('occupied wall') end,
            remove=function() error('MUTATION') end}
          local ok,err=pcall(cleanup.execute,a)
          assert(not ok and tostring(err):find('occupied wall'))
        ''')

    def test_empty_map_before_and_after_entering_map_view(self):
        self.lua.execute('''
          limit=2000; activeBuilding=false; deletes=0
          local zeros=setmetatable({}, {__index=function() return 0 end})
          local core={readInteger=function(addr)
            if addr==0xF98528 then return limit end
            for _,spec in pairs(cleanup.BINDINGS) do
              if addr==spec[1] then return spec[2] end
            end
            return 0
          end, readSmallInteger=function(addr)
            if activeBuilding and addr==0xF98520+0x14+0x32C+0xD0 then return 2 end
            return 0
          end}
          local ffi={cast=function(kind, addr)
            if kind:find('__thiscall',1,true) then
              return function() deletes=deletes+1 end
            end
            return zeros
          end}
          local view={build='Crusader 1.41',base=0x1A93208,layers={logic1=zeros}}
          cleanup.prepare(core,ffi,view)()
          limit=0 -- native updateBuildings on an empty map
          cleanup.prepare(core,ffi,view)()
          cleanup.prepare(core,ffi,view)() -- repeated import after returning
          assert(deletes==0)
          activeBuilding=true
          local ok,err=pcall(cleanup.prepare,core,ffi,view)
          assert(not ok and tostring(err):find('zero building scan limit'))
          assert(deletes==0)
          activeBuilding=false
          for _,bad in ipairs({-1,2001}) do
            limit=bad
            local ok,err=pcall(cleanup.prepare,core,ffi,view)
            assert(not ok and tostring(err):find('invalid building scan limit: '..bad,1,true))
          end
          assert(deletes==0)
        ''')

    def test_extreme_rejected_before_binding(self):
        self.lua.execute('''
          local ok,err=pcall(cleanup.prepare,{}, {}, {build='Crusader Extreme 1.41.1-E'})
          assert(not ok and tostring(err):find('only supported'))
        ''')

    @unittest.skipUnless((GAME_DIR / 'Stronghold Crusader.exe').exists(), 'game fixture absent')
    def test_native_function_guards_match_executable(self):
        pe = PEImage(GAME_DIR / 'Stronghold Crusader.exe')
        for _, binding in self.module.BINDINGS.items():
            self.assertEqual(struct.unpack('<I', pe.read(binding[1], 4))[0], binding[2])

    def test_shared_staging_precedes_cleanup_and_commit(self):
        source = (lua_harness.ROOT / 'mappng/actions.lua').read_text(encoding='utf-8')
        self.assertLess(source.index('height.import(staged'), source.index('cleanup.prepare'))
        self.assertLess(source.index('terrain.import(staged'), source.index('cleanup.prepare'))
        self.assertLess(source.index('pcall(remove)'), source.index('ffi.copy(v.layers'))
        self.assertIn("importImage('height', image)", source)
        self.assertIn("importImage('terrain', image)", source)

    def test_no_full_eraser_or_unit_deletion(self):
        source = (lua_harness.ROOT / 'mappng/map/cleanup.lua').read_text(encoding='utf-8').lower()
        for forbidden in ('0x508ec0', '0x5017c0', '0x53e790', 'ffi.fill'):
            self.assertNotIn(forbidden, source)
