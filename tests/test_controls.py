"""ABI names from installed ui-1.0.1/ui/headers/latest/ui.h, not OpenSHC."""
import pathlib
import re
import unittest
import zipfile
import lua_harness

FIELDS = {"menuItemType", "position", "itemWidth", "itemHeight", "menuItemActionHandler",
          "callbackParameter", "menuItemRenderFunction", "firstItemTypeData",
          "menuItemRenderFunctionType", "field9_0x28", "textMessageLookupIndex",
          "ucId_0x30", "hovering", "clicked", "iconDeactivated_0x36", "field15_0x38",
          "field16_0x3a", "secondItemTypeData", "menuPointer"}


class TestControls(unittest.TestCase):
    def test_heading_matches_native_save_map_typography(self):
        lua = lua_harness.runtime()
        controls = lua_harness.load(lua, "mappng.ui.controls")
        calls = []
        rendering = lua.table(pencilRenderCore=123, textManager=456,
                              renderTextToScreenConst=lambda *args: calls.append(args))
        banners = []
        controls.dialogHeading(rendering, lambda *args: banners.append(args),
                               "Export Heightmap", 100, 200, 700)
        self.assertEqual(banners, [(123, 100, 200, 700, 64)])
        self.assertEqual(calls, [(456, "Export Heightmap", 450, 222, 1,
                                  0xC2F0EB, 15, False, 0)])

    def test_initializer_uses_only_real_abi_fields(self):
        lua = lua_harness.runtime()
        controls = lua_harness.load(lua, "mappng.ui.controls")
        item = controls.item(lua.table(x=20, y=30, width=60, height=32), 123, 456, 1)
        self.assertTrue(set(item).issubset(FIELDS))
        self.assertEqual(item.ucId_0x30, -1)
        controls.verify(item)
        item.ucId_0x30 = 0
        with self.assertRaises(Exception):
            controls.verify(item)

    def test_contract_matches_actual_installed_ui_header(self):
        package = pathlib.Path(r"S:\Projects\Harness\test-builds\map-png-test\ucp\modules\ui-1.0.1.zip")
        if not package.exists():
            self.skipTest("local UI package not installed")
        with zipfile.ZipFile(package) as archive:
            header = archive.read("ui/headers/latest/ui.h").decode()
        declaration = header.split("struct MenuItem {", 1)[1].split("};", 1)[0]
        found = set(re.findall(r"(\w+)\s*;", declaration))
        self.assertEqual(found, FIELDS)
