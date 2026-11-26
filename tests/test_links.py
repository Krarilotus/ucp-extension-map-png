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
