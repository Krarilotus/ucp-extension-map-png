"""Row placement.

Position resolution has three tiers and the buttons must always end up
somewhere, because a row that silently fails to install is much harder to
debug in-game than one sitting in the wrong place.
"""

import unittest

import lua_harness


class TestScreens(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.screens = lua_harness.load(self.lua, "mappng.ui.screens")

    def test_falls_back_when_nothing_is_known(self):
        """No override, and no `core` global, so tier 3 must catch it."""
        origin = self.screens.resolveMinimap(self.screens.SCREENS[1])
        self.assertEqual(origin["source"], "fallback")
        self.assertIsNotNone(origin["x"])
        self.assertIsNotNone(origin["y"])

    def test_override_wins(self):
        screen = self.lua.table(name="t", menuID=17,
                                minimap=self.lua.table(x=336, y=232, height=128))
        origin = self.screens.resolveMinimap(screen)
        self.assertEqual(origin["source"], "override")
        self.assertEqual(origin["x"], 336)
        self.assertEqual(origin["y"], 232 + 128)

    def test_runtime_read_is_used_when_available(self):
        self.lua.execute("""
            core = { readInteger = function(address)
              local base = 0x01A31610
              local offsets = { [0x18] = 128, [0x1C] = 128, [0x28] = 336, [0x2C] = 232 }
              return offsets[address - base]
            end }
        """)
        origin = self.screens.resolveMinimap(self.screens.SCREENS[1])
        self.assertEqual(origin["source"], "MinimapViewState")
        self.assertEqual(origin["x"], 336)
        self.assertEqual(origin["y"], 232 + 128)

    def test_implausible_runtime_values_are_rejected(self):
        self.lua.execute("""
            core = { readInteger = function() return 99999 end }
        """)
        origin = self.screens.resolveMinimap(self.screens.SCREENS[1])
        self.assertEqual(origin["source"], "fallback")

    def test_icons_tile_left_to_right_without_gaps(self):
        screen = self.lua.table(name="t", menuID=17,
                                minimap=self.lua.table(x=336, y=232, height=128))
        xs = [self.screens.iconPosition(screen, i)["x"] for i in range(1, 5)]
        self.assertEqual(xs, [336, 368, 400, 432])
        # The row spans exactly the 128px preview width.
        self.assertEqual(xs[-1] + self.screens.ICON_WIDTH - xs[0], 128)

        ys = {self.screens.iconPosition(screen, i)["y"] for i in range(1, 5)}
        self.assertEqual(ys, {232 + 128})

    def test_both_target_menus_are_configured(self):
        ids = sorted(s["menuID"] for s in self.screens.SCREENS.values())
        self.assertEqual(ids, [17, 1002])
        self.assertIsNotNone(self.screens.screenByMenuID(17))
        self.assertIsNotNone(self.screens.screenByMenuID(1002))
        self.assertIsNone(self.screens.screenByMenuID(999))


if __name__ == "__main__":
    unittest.main()
