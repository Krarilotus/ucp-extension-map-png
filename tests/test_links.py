import unittest
import lua_harness


class LinkedPngs(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.lua.execute('''
          files={['height.png']=true,['terrain.png']=true}
          writes=0
          function fresh()
            return require('mappng.links').new(function(data) disk=data; writes=writes+1 end,
              function(name) return name:match('^[%w_-]+%.png$') ~= nil end,
              function(name) return files[name] == true end)
          end
          links=fresh(); links.open('maps/test.map')
        ''')

    def check(self, code):
        self.lua.execute(code)

    def test_both_links_survive_restart(self):
        self.check('''links.link('height','height.png'); links.link('terrain','terrain.png')
          links=fresh(); links.restore(disk); links.open('maps/test.map')
          assert(links.names().height=='height.png' and links.names().terrain=='terrain.png')''')

    def test_maps_and_new_unsaved_maps_are_isolated(self):
        self.check('''links.link('height','height.png'); links.open('maps/other.map')
          assert(next(links.names())==nil)
          links.open(nil); links.link('terrain','terrain.png'); links.open(nil)
          assert(next(links.names())==nil)
          links.open('maps/test.map'); assert(links.names().height=='height.png')''')

    def test_save_as_transfers_links_without_overwriting_original(self):
        self.check('''links.link('height','height.png'); links.saved('maps/copy.map')
          links.link('terrain','terrain.png'); links.open('maps/test.map')
          assert(links.names().height=='height.png' and links.names().terrain==nil)
          links.open('maps/copy.map'); assert(links.names().terrain=='terrain.png')''')

    def test_missing_image_invalidates_persistently_and_aborts_refresh(self):
        self.check('''links.link('height','height.png'); links.link('terrain','terrain.png')
          files['terrain.png']=nil
          local names,missing=links.forRefresh()
          assert(names==nil and missing.terrain=='terrain.png')
          assert(disk.maps['maps/test.map'].terrain==nil)
          files['terrain.png']=true
          assert(links.forRefresh().terrain==nil)''')

    def test_missing_image_at_restart_is_invalidated(self):
        self.check('''links.link('height','height.png'); files['height.png']=nil
          links=fresh(); links.restore(disk); links.open('maps/test.map')
          assert(next(links.names())==nil and disk.maps['maps/test.map'].height==nil)''')

    def test_untrusted_paths_and_schema_do_not_replace_valid_state(self):
        self.check('''links.link('height','height.png')
          assert(not pcall(links.restore,{version=2,maps={}}))
          assert(not pcall(links.restore,{version=1,maps={bad={height='../bad.png'}}}))
          assert(links.names().height=='height.png')''')

    def test_callers_cannot_mutate_stored_links(self):
        self.check('''links.link('height','height.png'); local names=links.names()
          names.height='other.png'; assert(links.names().height=='height.png')''')

    def test_unsaved_links_are_persisted_only_after_successful_save(self):
        self.check('''links.open(nil); links.link('height','height.png'); assert(writes==0)
          links.saved('maps/new.map'); assert(disk.maps['maps/new.map'].height=='height.png')''')


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
            exists=function(name) return files[name] end,
            fromGameText=function(name) return name end,
            mapIdentity=function(name) if identityFail then error('identity failure') end; return name:match('%.map$') and name or nil end,
          }
          local sites={newMap=1,loadBegin=2,loadDone=3,saveBegin=4,saveDone=5}
          package.loaded['mappng.native']={resolve=function() return {hooks=sites,resource=10,resourceName=11} end}
          package.loaded['mappng.actions']={importLinked=function(names) imported=names end}
          local staged
          userdata={interface=function() return {
            open=function(_,name,mode)
              if mode=='rb' then return sidecar and {read=function() return sidecar end,close=function() end} end
              return {write=function(_,data) if writeFail then return nil,'disk failure' end; staged=data; return true end,
                close=function() return true end}
            end,
            rename=function() sidecar=staged; return true end,
          } end}
          CallingConvention={THISCALL=1}
          core={
            detourCode=function(callback,address,span) callbacks[address]=callback; installs=installs+1 end,
            exposeCode=function() return function() return 12 end end,
            readByte=function(address) return (filename..'\0'):byte(address-11) end,
            readString=function(_,length) return filename:sub(1,length) end,
          }
          lifecycle=require('mappng.lifecycle'); lifecycle.initialize('mapping')
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
          lifecycle=require('mappng.lifecycle'); lifecycle.initialize('mapping')
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
          lifecycle.initialize('mapping')
          assert(installs==5 and not next(lifecycle.names()))
        ''')
