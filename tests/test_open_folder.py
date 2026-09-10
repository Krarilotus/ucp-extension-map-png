import unittest
import lua_harness


class TestOpenFolder(unittest.TestCase):
    def test_folder_handler_receives_one_unicode_path_without_shell_arguments(self):
        lua = lua_harness.runtime()
        lua.execute('''
          local gdiplus=require("mappng.png.gdiplus")
          gdiplus.widePath=function(_, value) return value end
          attributes, launchResult, launches=16, 33, 0
          local kernel={GetFileAttributesW=function() return attributes end}
          local shell={ShellExecuteW=function(window, operation, path, parameters, directory, show)
            assert(window==nil and operation=="open" and parameters==nil and directory==nil)
            assert(show==1)
            launchedPath=path; launches=launches+1
            return launchResult
          end}
          local ffi={cdef=function() end, tonumber=tonumber, cast=function(_, v) return v end,
            load=function(name)
              assert(name=="kernel32" or name=="shell32")
              return name=="kernel32" and kernel or shell
            end}
          require("mappng.paths").initialize(ffi)
        ''')
        paths = lua_harness.load(lua, "mappng.paths")
        folder = "C:\\Games\\Karten & Höhen\\mapping"
        self.assertTrue(paths.openFolder(folder))
        self.assertEqual(lua.globals().launchedPath, folder)
        lua.globals().launchResult = 31
        with self.assertRaises(Exception):
            paths.openFolder(folder)
        lua.globals().attributes = 0  # A file is not allowed, even if it exists.
        before = lua.globals().launches
        with self.assertRaises(Exception):
            paths.openFolder(folder)
        self.assertEqual(lua.globals().launches, before)
