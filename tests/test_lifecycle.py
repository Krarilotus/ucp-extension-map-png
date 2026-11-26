"""Real link model/lifecycle integration, with only native/IO boundaries stubbed."""
import unittest
import lua_harness


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.lua=lua_harness.runtime()
        self.lua.execute(r'''
          callbacks={}; installs=0; warnings={}; files={['h.png']=true,['t.png']=true}
          local function copy(t)
            if type(t)~='table' then return t end
            local r={}; for k,v in pairs(t) do r[k]=copy(v) end; return r
          end
          json={encode=function(_,v) return copy(v) end,decode=function(_,v) return copy(v) end}
          INFO=1; WARNING=2; log=function(_,text) warnings[#warnings+1]=text end
          package.loaded['mappng.paths']={
            resolve=function(folder,name) assert(not name:find('%.%.')); return name end,
            exists=function(name) return name:find('json') and sidecar~=nil or files[name] end,
            writeAtomic=function(_,data) if writeFail then error('disk failure') end; sidecar=data end,
            readBinary=function() return sidecar end,
            fromGameText=function(name) return name end,
            mapIdentity=function(name) if identityFail then error('identity failure') end; return name:match('%.map$') and name or nil end,
          }
          local sites={newMap=1,loadBegin=2,loadDone=3,saveBegin=4,saveDone=5}
          package.loaded['mappng.native']={resolve=function() return {hooks=sites,resource=10,resourceName=11} end}
          package.loaded['mappng.actions']={importLinked=function(names) imported=names end}
          core={detourCode=function(callback,address,span) callbacks[address]=callback; installs=installs+1 end}
          ffi={cast=function(kind,value) if value==11 then return function() return filename end end; return value end,
            string=function(value) return value end}
          lifecycle=require('mappng.lifecycle'); lifecycle.initialize(ffi,'mapping')
          function event(name)
            local r={eax=123}; assert(callbacks[sites[name]](r)==r)
          end
          function load(name) filename=name; event('loadBegin'); event('loadDone') end
          function save(name) filename=name; event('saveBegin'); event('saveDone') end
        ''')

    def test_save_as_and_map_load_do_not_cross_link(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); save('one.map')
          lifecycle.link('terrain','t.png'); save('two.map')
          load('three.map'); assert(not next(lifecycle.names()))
          load('one.map'); assert(lifecycle.names().height=='h.png')
          load('two.map'); assert(lifecycle.names().terrain=='t.png')
          assert(lifecycle.refresh() and imported.height=='h.png' and imported.terrain=='t.png')
        ''')

    def test_restart_restores_links_from_sidecar_not_map_bytes(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); save('one.map')
          package.loaded['mappng.lifecycle']=nil
          lifecycle=require('mappng.lifecycle'); lifecycle.initialize(ffi,'mapping')
          assert(not next(lifecycle.names())); load('one.map')
          assert(lifecycle.names().height=='h.png')
        ''')

    def test_missing_file_invalidates_without_partial_refresh(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); lifecycle.link('terrain','t.png'); save('one.map')
          files['h.png']=nil
          assert(not pcall(lifecycle.refresh)); assert(imported==nil)
          assert(lifecycle.names().height==nil and lifecycle.names().terrain=='t.png')
        ''')

    def test_new_map_and_incomplete_load_detach(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); save('one.map'); event('newMap')
          assert(not next(lifecycle.names())); load('one.map')
          filename='bad.map'; event('loadBegin'); assert(not next(lifecycle.names()))
          event('newMap'); event('loadDone'); assert(not next(lifecycle.names()))
        ''')

    def test_failure_cannot_leave_a_pending_old_identity(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); save('one.map')
          filename='one.map'; event('loadBegin')
          identityFail=true; event('loadBegin'); identityFail=false
          event('loadDone'); assert(not next(lifecycle.names()) and #warnings>0)
        ''')

    def test_disk_failure_never_unwinds_into_native_hook(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); writeFail=true; save('one.map')
          assert(#warnings>0 and not next(lifecycle.names()))
        ''')

    def test_reenable_does_not_duplicate_hooks_or_restore_stale_map(self):
        self.lua.execute('''
          lifecycle.link('height','h.png'); lifecycle.disable(); load('other.map')
          lifecycle.initialize(ffi,'mapping')
          assert(installs==5 and not next(lifecycle.names()))
        ''')
