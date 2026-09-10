import unittest
import lua_harness


class ImportTransaction(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.lua.execute('''
          events={}; failConvert=false; failPreflight=false; failRemove=false
          local function event(s) events[#events+1]=s end
          local layers={height={[0]=7},defaultHeight={[0]=7},logic1={[0]=7},logic2={[0]=7}}
          live=layers
          package.loaded['mappng.map.diamond']={SIZE=1,TILE_COUNT=1,buildTileToPixel=function() return {[0]=0} end}
          package.loaded['mappng.map.palette']={resolve=function() return {} end}
          package.loaded['mappng.map.tilemap']={open=function() return {layers=layers} end}
          package.loaded['mappng.map.refresh']={invalidate=function() event('refresh') end}
          package.loaded['mappng.paths']={ensurePngFolder=function() return 'mapping' end,resolve=function(_,n) return n end}
          package.loaded['mappng.png']={readGray=function() event('decode'); return {} end,
            readRGB=function() event('decode'); return {} end}
          package.loaded['mappng.map.height']={import=function(s)
            event('convert'); s.height[0]=9; s.defaultHeight[0]=9
            if failConvert then error('bad PNG') end
          end}
          package.loaded['mappng.map.terrain']={import=function(s)
            event('convert'); s.logic1[0]=9; s.logic2[0]=9
            if failConvert then error('bad PNG') end
            return {unknownColours=0}
          end}
          package.loaded['mappng.map.cleanup']={prepare=function()
            event('preflight'); if failPreflight then error('occupied wall') end
            return function() event('remove'); if failRemove then error('remaining footprint') end end
          end}
          local ffi={new=function() return {} end,copy=function(dst,src) dst[0]=src[0] end}
          actions=require('mappng.actions')
          actions.initialize(ffi, {}, {})
        ''')

    def test_both_imports_clean_before_commit(self):
        for kind in ('Height', 'Terrain'):
            self.lua.execute("events={}; actions.import%s('test.png'); assert(table.concat(events,',')=='decode,convert,preflight,remove,refresh')" % kind)
        self.assertEqual(self.lua.globals().live.height[0], 9)
        self.assertEqual(self.lua.globals().live.logic1[0], 9)
        self.assertFalse(self.lua.globals().actions.undo('height'))

    def test_invalid_png_changes_nothing(self):
        for kind in ('Height', 'Terrain'):
            self.lua.execute("events={}; failConvert=true; assert(not pcall(actions.import%s,'bad.png')); assert(table.concat(events,',')=='decode,convert'); assert(live.height[0]==7 and live.logic1[0]==7)" % kind)

    def test_preflight_failure_changes_nothing(self):
        self.lua.execute("failPreflight=true; assert(not pcall(actions.importHeight,'test.png')); assert(table.concat(events,',')=='decode,convert,preflight'); assert(live.height[0]==7)")

    def test_cleanup_failure_does_not_commit_png_and_refreshes(self):
        self.lua.execute("failRemove=true; assert(not pcall(actions.importTerrain,'test.png')); assert(table.concat(events,',')=='decode,convert,preflight,remove,refresh'); assert(live.logic1[0]==7)")
