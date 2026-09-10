"""Row placement.

The geometry is read out of MenuView_MapEditorProperties_DoEveryFrame
(0x0042E0D0) in Crusader 1.41; these tests pin the arithmetic built on it.
"""

import unittest

import lua_harness

SUPPRESSED = 0x01FE7CBC
MULTIPLAYER = 0x01FE9244
MAP_SIZE = 0x01FE7C14


class TestScreens(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.screens = lua_harness.load(self.lua, "mappng.ui.screens")
        self.screen = self.screens.SCREENS[1]

    def game(self, suppressed=-1, multiplayer=0, size=400):
        """Stands up `core` so the three globals read as given."""
        values = {SUPPRESSED: suppressed, MULTIPLAYER: multiplayer, MAP_SIZE: size}
        self.lua.globals().core = self.lua.table(
            readInteger=lambda address: values.get(int(address), 0))
        self.screens.setGlobalsAvailable(True)

    def row(self, layout=None):
        return [self.screens.iconPosition(self.screen, i, layout) for i in range(1, 5)]

    def test_only_the_editor_map_screen_is_targeted(self):
        ids = [s["menuID"] for s in self.screens.SCREENS.values()]
        self.assertEqual(ids, [17])
        self.assertIsNone(self.screens.screenByMenuID(1002))

    def test_singleplayer_400(self):
        self.game(multiplayer=0, size=400)
        layout = self.screens.currentLayout()
        self.assertEqual((layout["variant"], layout["size"], layout["half"]), ("sp", 400, 100))
        self.assertEqual((layout["centreX"], layout["centreY"]), (400, 240))

        row = self.row(layout)
        self.assertEqual([p["x"] for p in row], [278, 342, 406, 470])
        self.assertEqual({p["y"] for p in row}, {348})

    def test_multiplayer_400_shifts_right_by_200(self):
        self.game(multiplayer=1, size=400)
        row = self.row()
        self.assertEqual([p["x"] for p in row], [478, 542, 606, 670])
        self.assertEqual({p["y"] for p in row}, {348})

    def test_row_follows_the_preview_size(self):
        """160 -> 160px, 200 -> 200px, 300 -> 150px, 400 -> 200px previews."""
        for size, half in ((160, 80), (200, 100), (300, 75), (400, 100)):
            with self.subTest(size=size):
                self.game(size=size)
                layout = self.screens.currentLayout()
                self.assertEqual(layout["half"], half)

                row = self.row(layout)
                left, right = 400 - 126, 400 + 126
                self.assertEqual({p["y"] for p in row}, {240 + half + 8})
                for p in row:
                    self.assertGreaterEqual(p["x"], left)
                    self.assertLessEqual(p["x"] + self.screens.ICON_WIDTH, right)
                for a, b in zip(row, row[1:]):
                    self.assertGreaterEqual(b["x"] - a["x"], self.screens.ICON_WIDTH,
                                            "icons overlap")

    def test_icons_are_centred_in_equal_slots(self):
        self.game(size=400)
        row = self.row()
        slot = 64
        for i, p in enumerate(row):
            slot_left = 274 + i * slot
            self.assertEqual(p["x"] - slot_left, (60 - self.screens.ICON_WIDTH) // 2)

    def test_map_size_zero_means_400(self):
        self.game(size=0)
        self.assertEqual(self.screens.currentLayout()["size"], 400)

    def test_hidden_mirrors_the_preview(self):
        self.game(suppressed=-1)
        self.assertFalse(self.screens.currentLayout()["hidden"])
        self.game(suppressed=0xFFFFFFFF)
        self.assertFalse(self.screens.currentLayout()["hidden"])
        self.game(suppressed=3)
        self.assertTrue(self.screens.currentLayout()["hidden"])

    def test_layout_key_changes_with_variant_and_size(self):
        self.game(multiplayer=0, size=400)
        sp = self.screens.currentLayout()["key"]
        self.game(multiplayer=1, size=400)
        mp = self.screens.currentLayout()["key"]
        self.game(multiplayer=1, size=300)
        mp300 = self.screens.currentLayout()["key"]
        self.assertEqual(len({sp, mp, mp300}), 3)

    def test_without_the_globals_it_assumes_singleplayer_400(self):
        """Other builds: nothing is read, and nothing is hidden."""
        self.lua.globals().core = self.lua.table(
            readInteger=lambda address: (_ for _ in ()).throw(AssertionError("read")))
        self.screens.setGlobalsAvailable(False)

        layout = self.screens.currentLayout()
        self.assertEqual(layout["source"], "default")
        self.assertEqual(layout["key"], "sp:400")
        self.assertFalse(layout["hidden"])

    def test_offset_is_applied_on_top(self):
        self.game(size=400)
        self.screen["offset"] = self.lua.table(x=3, y=-2)
        row = self.row()
        self.assertEqual([p["x"] for p in row], [281, 345, 409, 473])
        self.assertEqual({p["y"] for p in row}, {346})


if __name__ == "__main__":
    unittest.main()
