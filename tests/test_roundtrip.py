"""game -> image -> game must be an identity for the default palette.

The layers are stood up as plain Lua tables, so this exercises the real
export/import code with no game and no FFI.
"""

import random
import unittest

import lua_harness

TILE_COUNT = 80400


class RoundTripBase(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.diamond = lua_harness.load(self.lua, "mappng.map.diamond")
        self.palette = lua_harness.load(self.lua, "mappng.map.palette")
        self.lookup = self.diamond.buildTileToPixel(400)

    def new_layer(self, values):
        """A 0-based Lua array holding `values`."""
        table = self.lua.eval("(function() return {} end)()")
        for index, value in enumerate(values):
            table[index] = value
        return table

    def read_layer(self, table):
        return [table[i] for i in range(TILE_COUNT)]


class TestHeightRoundTrip(RoundTripBase):
    def setUp(self):
        super().setUp()
        self.height = lua_harness.load(self.lua, "mappng.map.height")

    def test_identity(self):
        rng = random.Random(20260909)
        original = [rng.randrange(256) for _ in range(TILE_COUNT)]

        layers = self.lua.table(
            defaultHeight=self.new_layer(original),
            height=self.new_layer([0] * TILE_COUNT),
        )

        image = self.height.export(layers, self.lookup, 400)
        self.assertEqual(image.width, 400)
        self.assertEqual(image.height, 400)

        target = self.lua.table(
            defaultHeight=self.new_layer([0] * TILE_COUNT),
            height=self.new_layer([0] * TILE_COUNT),
        )
        self.height["import"](target, self.lookup, image, 400)

        self.assertEqual(self.read_layer(target["defaultHeight"]), original)
        # sourcehold writes the visual layer too; so do we.
        self.assertEqual(self.read_layer(target["height"]), original)

    def test_outside_the_diamond_is_black(self):
        layers = self.lua.table(
            defaultHeight=self.new_layer([255] * TILE_COUNT),
            height=self.new_layer([0] * TILE_COUNT),
        )
        image = self.height.export(layers, self.lookup, 400)

        # Row 0 holds only columns 199 and 200.
        self.assertEqual(image.gray[0], 0)
        self.assertEqual(image.gray[198], 0)
        self.assertEqual(image.gray[199], 255)
        self.assertEqual(image.gray[200], 255)
        self.assertEqual(image.gray[201], 0)

    def test_wrong_size_is_rejected(self):
        layers = self.lua.table(
            defaultHeight=self.new_layer([0] * TILE_COUNT),
            height=self.new_layer([0] * TILE_COUNT),
        )
        image = self.lua.table(width=200, height=200, gray=self.new_layer([0]))
        with self.assertRaises(Exception):
            self.height["import"](layers, self.lookup, image, 400)


class TestTerrainRoundTrip(RoundTripBase):
    def setUp(self):
        super().setUp()
        self.terrain = lua_harness.load(self.lua, "mappng.map.terrain")

    def synthetic_map(self, palette_name):
        """A map using one representative tile per terrain name."""
        resolved = self.palette.resolve(palette_name)
        logic1 = self.palette.logic1
        logic2 = self.palette.logic2

        names = [entry["name"] for entry in self.palette.logic1PaintOrder.values()]
        names += [entry["name"] for entry in self.palette.logic2PaintOrder.values()]
        names = [n for n in names if resolved["nameToColour"][n] is not None]

        l1, l2 = [], []
        for tile in range(TILE_COUNT):
            name = names[tile % len(names)]
            l1.append(logic1[name] or 0)
            l2.append(logic2[name] or 0)
        return resolved, l1, l2

    def test_identity_with_default_palette(self):
        resolved, l1, l2 = self.synthetic_map("mappng")

        layers = self.lua.table(
            logic1=self.new_layer(l1),
            logic2=self.new_layer(l2),
        )
        image = self.terrain.export(layers, self.lookup, resolved, 400)

        target = self.lua.table(
            logic1=self.new_layer(l1),  # import keeps borders from the live map
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        report = self.terrain["import"](target, self.lookup, image, resolved, 400)

        self.assertEqual(report["unknownColours"], 0)
        self.assertEqual(report["tilesWritten"], TILE_COUNT)
        self.assertEqual(self.read_layer(target["logic1"]), l1)
        self.assertEqual(self.read_layer(target["logic2"]), l2)

    def test_sourcehold_palette_loses_plateaus(self):
        """The known lossiness, asserted rather than assumed."""
        resolved, l1, l2 = self.synthetic_map("sourcehold")

        layers = self.lua.table(logic1=self.new_layer(l1), logic2=self.new_layer(l2))
        image = self.terrain.export(layers, self.lookup, resolved, 400)

        target = self.lua.table(
            logic1=self.new_layer(l1),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        self.terrain["import"](target, self.lookup, image, resolved, 400)

        after = self.read_layer(target["logic2"])
        plateau_high = self.palette.logic2["plateau_high"]
        plateau_medium = self.palette.logic2["plateau_medium"]
        # Both plateau levels and plain earth share #ae9467, so after a round
        # trip none of them survives as a plateau.
        self.assertNotIn(plateau_high, after)
        self.assertNotIn(plateau_medium, after)

    def test_borders_survive_import(self):
        resolved = self.palette.resolve("mappng")
        border = self.palette.logic1["border"]
        border_edge = self.palette.logic1["border_edge"]
        earth = self.palette.logic1["default_earth_or_texture"]

        l1 = [border if i % 3 == 0 else (border_edge if i % 3 == 1 else earth)
              for i in range(TILE_COUNT)]
        layers = self.lua.table(
            logic1=self.new_layer(l1),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        image = self.terrain.export(layers, self.lookup, resolved, 400)

        target = self.lua.table(
            logic1=self.new_layer(l1),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        self.terrain["import"](target, self.lookup, image, resolved, 400)

        after = self.read_layer(target["logic1"])
        for i in range(0, TILE_COUNT, 997):
            if i % 3 == 0:
                self.assertEqual(after[i] & border, border, "tile %d lost its border" % i)
            elif i % 3 == 1:
                self.assertEqual(after[i] & border_edge, border_edge, "tile %d" % i)

    def test_empty_tiles_stay_empty(self):
        resolved = self.palette.resolve("mappng")
        layers = self.lua.table(
            logic1=self.new_layer([0] * TILE_COUNT),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        image = self.terrain.export(layers, self.lookup, resolved, 400)

        target = self.lua.table(
            logic1=self.new_layer([0] * TILE_COUNT),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        self.terrain["import"](target, self.lookup, image, resolved, 400)

        self.assertEqual(set(self.read_layer(target["logic1"])), {0})

    def test_unknown_colours_are_reported(self):
        resolved = self.palette.resolve("mappng")
        layers = self.lua.table(
            logic1=self.new_layer([self.palette.logic1["default_earth_or_texture"]] * TILE_COUNT),
            logic2=self.new_layer([0] * TILE_COUNT),
        )
        image = self.terrain.export(layers, self.lookup, resolved, 400)
        image["rgb"][self.lookup[0]] = 0x123456
        image["rgb"][self.lookup[1]] = 0x123456

        report = self.terrain["import"](layers, self.lookup, image, resolved, 400)
        self.assertEqual(report["unknownColours"], 2)
        self.assertEqual(report["unknownSample"]["colour"], 0x123456)


if __name__ == "__main__":
    unittest.main()
