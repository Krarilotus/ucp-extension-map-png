"""Palette invariants.

The sourcehold palette is knowingly lossy; the mappng palette must not be.
These tests pin both properties so a future palette edit cannot quietly
reintroduce a collision into the default.
"""

import unittest

import lua_harness

# Straight from sourcehold/tool/memory/map/terrain/logics.py, so a copy-paste
# slip in the Lua port shows up here rather than as a corrupted map.
SOURCEHOLD_LOGIC1 = {
    "none": 0,
    "default_earth_or_texture": 0x8000,
    "ocean": 0x1,
    "plain1_and_farm": 0x4,
    "plain2_and_pitch": 0x8,
    "border": 0x10,
    "border_edge": 0x20,
    "rocks": 0x80,
    "moat_dug": 0x4000,
    "oasis_grass": 0x8000,
    "thick_scrub": 0x8000,
    "scrub": 0x8000,
    "driven_sand": 0x8000,
    "beach": 0x8000,
    "plateau_high": 0x8000,
    "plateau_medium": 0x8000,
    "earth_and_stones": 0x8000,
    "boulders": 0x20000,
    "pebbles": 0x40000,
    "iron": 0x80000,
    "river": 0x100000,
    "ford": 0x200000,
    "crenel_variation": 0x400000,
    "marsh": 0x20000000,
    "moat": 0x40000000,
    "oil": 0x80000000,
}

SOURCEHOLD_LOGIC2 = {
    "none": 0,
    "thick_scrub": 0x80,
    "driven_sand": 0x40,
    "beach": 0x20,
    "oasis_grass": 0x10,
    "plateau_high": 0x8,
    "plateau_medium": 0x4,
    "moat_undug": 0x3,
    "earth_and_stones": 0x2,
    "scrub": 0x1,
}


class TestPalette(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.palette = lua_harness.load(self.lua, "mappng.map.palette")

    def test_logic1_matches_sourcehold(self):
        for name, value in SOURCEHOLD_LOGIC1.items():
            self.assertEqual(self.palette.logic1[name], value, name)

    def test_logic2_matches_sourcehold(self):
        for name, value in SOURCEHOLD_LOGIC2.items():
            self.assertEqual(self.palette.logic2[name], value, name)

    def test_paint_order_covers_every_distinct_logic1_flag(self):
        painted = {entry["flag"] for entry in self.palette.logic1PaintOrder.values()}
        expected = {v for v in SOURCEHOLD_LOGIC1.values() if v != 0}
        self.assertEqual(painted, expected)

    def test_paint_order_covers_every_logic2_value_but_none(self):
        painted = {entry["value"] for entry in self.palette.logic2PaintOrder.values()}
        expected = {v for v in SOURCEHOLD_LOGIC2.values() if v != 0}
        self.assertEqual(painted, expected)

    def test_default_palette_is_lossless(self):
        resolved = self.palette.resolve(self.palette.DEFAULT_PALETTE)
        collisions = list(resolved["collisions"].values())
        self.assertEqual(
            collisions,
            [],
            "default palette must not share a colour between two terrain names",
        )

    def test_sourcehold_palette_collisions_are_the_known_ones(self):
        """Documents the lossiness rather than pretending it is not there."""
        resolved = self.palette.resolve("sourcehold")
        colours = sorted(c["colour"] for c in resolved["collisions"].values())
        self.assertEqual(colours, ["#0000ff", "#0000ff", "#ae9467", "#ae9467"])

        # And the tie-break is deterministic and sane: plain earth wins #ae9467
        # instead of the Python original's plateau_high.
        earth = resolved["nameToColour"]["default_earth_or_texture"]
        self.assertEqual(resolved["colourToName"][earth["key"]], "default_earth_or_texture")

    def test_every_painted_name_has_a_colour(self):
        for palette_name in ("mappng", "sourcehold"):
            resolved = self.palette.resolve(palette_name)
            for entry in self.palette.logic1PaintOrder.values():
                name = entry["name"]
                if name == "crenel_variation":
                    # sourcehold has no colour for it either; it paints black.
                    continue
                self.assertIsNotNone(
                    resolved["nameToColour"][name], "%s/%s" % (palette_name, name)
                )
            for entry in self.palette.logic2PaintOrder.values():
                self.assertIsNotNone(
                    resolved["nameToColour"][entry["name"]],
                    "%s/%s" % (palette_name, entry["name"]),
                )

    def test_hex_to_rgb(self):
        r, g, b = self.palette.hexToRGB("#ae9467")
        self.assertEqual((r, g, b), (0xAE, 0x94, 0x67))
        self.assertEqual(self.palette.packRGB(0xAE, 0x94, 0x67), 0xAE9467)


if __name__ == "__main__":
    unittest.main()
