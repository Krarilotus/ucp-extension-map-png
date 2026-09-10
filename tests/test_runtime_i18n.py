import pathlib
import struct
import unittest
import lua_harness


class TestRuntimeLanguage(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.lang = lua_harness.load(self.lua, "mappng.ui.i18n")

    def test_supported_languages_have_four_distinct_actions(self):
        self.assertEqual(set(self.lang.languages), {"en", "de", "fr", "ru", "hu", "tr", "ch", "es", "fa", "it", "pl"})
        for code, labels in self.lang.languages.items():
            self.assertEqual(len({labels[i] for i in range(2, 6)}), 4, code)
            self.assertTrue(all(labels[i] for i in range(2, 9)), code)
            self.assertTrue(self.lang.folderLabel(code), code)
            warning = self.lang.importWarning(code)
            self.assertEqual(len(warning), 2, code)
            self.assertTrue(warning[1] and warning[2], code)
            if code != "en":
                self.assertNotEqual(self.lang.folderLabel(code), "Open folder", code)

    def test_loaded_game_language_overrides_executable_translation_mismatch(self):
        self.assertEqual(self.lang.resolve("english", "German"), ("de", "loaded game text"))
        self.assertEqual(self.lang.resolve("german", "Russian"), ("ru", "loaded game text"))
        self.assertEqual(self.lang.resolve("SPANISH", None), ("es", "UCP game language"))
        self.assertEqual(self.lang.resolve("italian", "unknown"), ("it", "UCP game language"))
        self.assertEqual(self.lang.resolve(None, "pl-PL"), ("pl", "loaded game text"))
        self.assertEqual(self.lang.resolve(None, None), ("en", "English fallback"))

    def test_gui_and_windows_language_do_not_override_the_game(self):
        self.lua.execute("os.getenv=function() error('must not read launcher or host language') end")
        self.assertEqual(self.lang.resolve("english", "German")[0], "de")

    def test_initialization_uses_loaded_language_and_native_codepage(self):
        self.lua.execute('''
          os.getenv=function() error("must not read GUI or Windows locale") end
          data={version={getGameLanguage=function() return "english" end}}
          INFO, WARNING=1,2
          log=function() end
          local paths=require("mappng.paths")
          paths.setGameCodepage=function(value) selectedCodepage=value end
          testFfi={string=function(v) return v end, tonumber=tonumber,
            cast=function(kind, pointer)
              assert(kind=="int *" and pointer==123)
              return {[4]=1252}
            end}
          testGame={Rendering={textManager=123,
            getTextStringInGroupAtOffset=function(pointer, group, entry)
              assert(pointer==123 and group==6 and entry==0)
              return "German"
            end}}
        ''')
        self.lang.initialize(self.lua.globals().testFfi, self.lua.globals().testGame)
        self.assertEqual(self.lang.action("export", "height"), "Höhenkarte exportieren")
        self.assertEqual(self.lua.globals().selectedCodepage, 1252)

    def test_normalizes_framework_and_game_language_names(self):
        for name, code in {"American":"en", "German":"de", "French":"fr", "Russian":"ru",
                           "Hungarian":"hu", "Turkish":"tr", "Chinese":"ch", "SPANISH":"es",
                           "Persian":"fa", "Italian":"it", "Polish":"pl", "zh-CN":"ch"}.items():
            self.assertEqual(self.lang.normalize(name), code)

    def test_actual_local_game_text_if_available(self):
        path = pathlib.Path(r"S:\Projects\Harness\test-builds\map-png-test\cr.tex")
        if not path.exists():
            self.skipTest("local live-test game not installed")
        data = path.read_bytes()
        offset = 1040 + 2 * struct.unpack_from("<I", data, 6 * 4)[0]
        marker = data[offset:].decode("utf-16le").split("\0", 1)[0]
        self.assertEqual(self.lang.normalize(marker), "de")
