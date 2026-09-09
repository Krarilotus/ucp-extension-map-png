"""The button graphics must keep the geometry the layout code assumes.

Four 32px icons in a row is 128px, which is the minimap width; that is the only
reason the row lines up. A redraw that changes the size should fail here rather
than in the game.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "tools"))

import inspect_icons  # noqa: E402

import lua_harness  # noqa: E402


class TestIcons(unittest.TestCase):
    def test_all_four_are_present(self):
        for name in inspect_icons.EXPECTED:
            self.assertTrue((inspect_icons.ICONS / name).is_file(), name)

    def test_geometry(self):
        for name in inspect_icons.EXPECTED:
            info = inspect_icons.describe(inspect_icons.ICONS / name)
            self.assertEqual((info["width"], info["height"]), (32, 18), name)

    def test_opaque(self):
        """The icons carry their own bevel, so nothing renders underneath."""
        for name in inspect_icons.EXPECTED:
            info = inspect_icons.describe(inspect_icons.ICONS / name)
            self.assertFalse(info["has_alpha"], "%s gained transparency" % name)

    def test_layout_matches_the_icon_size(self):
        lua = lua_harness.runtime()
        screens = lua_harness.load(lua, "mappng.ui.screens")

        self.assertEqual(screens.ICON_WIDTH, 32)
        self.assertEqual(screens.ICON_HEIGHT, 18)
        # Four icons across must span the 128px minimap exactly.
        self.assertEqual(screens.ICON_WIDTH * 4, 128)

    def test_every_action_has_an_icon_and_a_label(self):
        lua = lua_harness.runtime()
        screens = lua_harness.load(lua, "mappng.ui.screens")
        icons = lua_harness.load(lua, "mappng.ui.icons")

        keys = [action["key"] for action in screens.ACTIONS.values()]
        self.assertEqual(len(keys), 4)
        self.assertEqual(sorted(keys), sorted(n[:-4] for n in inspect_icons.EXPECTED))

        for key in keys:
            self.assertIsNotNone(icons.ICON_FILES[key], key)
            self.assertIsNotNone(icons.LABELS[key], key)


if __name__ == "__main__":
    unittest.main()
