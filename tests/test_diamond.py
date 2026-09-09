"""The diamond <-> square mapping must agree with sourcehold-maps exactly.

`mappng/map/diamond.lua` builds the mapping with integer row arithmetic.
sourcehold-maps derives it from an inverse square root
(`TileLocationTranslator.SerializedTileIndex.to_serialized_tile_point`). This
test reimplements the sourcehold formula in plain Python -- no numpy, no
OpenCV -- and asserts the two agree for every one of the 80400 tiles.

If they ever diverge, PNGs written by this module stop lining up with PNGs
written by `sourcehold memory map get`, which is the whole point of the format.
"""

import math
import unittest

import lua_harness


def sourcehold_mapping(size=400):
    """Port of TileLocationTranslator, following the Python source literally."""
    n_serialized_tiles = 2 * ((size / 2) * ((size / 2) + 1))
    half = size // 2

    def point_to_index(i, j):
        if i < half:
            return (i * (i + 1)) + j
        return (n_serialized_tiles - ((size - i) * (size - i + 1))) + j

    mapping = {}
    for index in range(int(n_serialized_tiles)):
        if index < n_serialized_tiles / 2:
            i = math.floor(0.5 * ((math.sqrt((4 * index) + 1)) - 1))
        else:
            i = math.floor(
                size
                - (
                    0.5
                    * (
                        (
                            math.sqrt(
                                (4 * ((2 * ((size / 2) * ((size / 2) + 1))) - index)) + 1
                            )
                        )
                        - 1
                    )
                )
            )
        j = index - point_to_index(i, 0)
        # to_adjusted_serialized_tile_point
        j_adjusted = j + abs((half - 1 if i < half else half) - i)
        mapping[index] = int(i) * size + int(j_adjusted)

    return mapping


class TestDiamond(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.diamond = lua_harness.load(self.lua, "mappng.map.diamond")

    def test_matches_sourcehold(self):
        expected = sourcehold_mapping()
        actual = self.diamond.buildTileToPixel(400)

        self.assertEqual(len(expected), 80400)
        for tile, pixel in expected.items():
            self.assertEqual(actual[tile], pixel, "tile %d" % tile)

    def test_covers_every_tile_exactly_once(self):
        lookup = self.diamond.buildTileToPixel(400)

        seen = set()
        for tile in range(80400):
            pixel = lookup[tile]
            self.assertIsNotNone(pixel, "tile %d unmapped" % tile)
            self.assertNotIn(pixel, seen, "pixel %d claimed twice" % pixel)
            seen.add(pixel)

        self.assertEqual(len(seen), 80400)

    def test_diamond_shape(self):
        """Row widths grow to the full 400 at rows 199/200 and shrink back."""
        lookup = self.diamond.buildTileToPixel(400)

        columns_per_row = {}
        for tile in range(80400):
            pixel = lookup[tile]
            columns_per_row.setdefault(pixel // 400, []).append(pixel % 400)

        self.assertEqual(sorted(columns_per_row[0]), [199, 200])
        self.assertEqual(sorted(columns_per_row[399]), [199, 200])
        self.assertEqual(len(columns_per_row[199]), 400)
        self.assertEqual(len(columns_per_row[200]), 400)

        for row, columns in columns_per_row.items():
            width = 2 * (row + 1) if row < 200 else 2 * (400 - row)
            self.assertEqual(len(columns), width, "row %d" % row)
            # contiguous and centred
            self.assertEqual(sorted(columns), list(range(min(columns), min(columns) + width)))
            self.assertEqual(min(columns) + max(columns), 399, "row %d not centred" % row)

    def test_inverse_round_trips(self):
        forward = self.diamond.buildTileToPixel(400)
        inverse = self.diamond.buildPixelToTile(400)

        for tile in range(0, 80400, 97):
            self.assertEqual(inverse[forward[tile]], tile)

    def test_tile_count(self):
        self.assertEqual(self.diamond.tileCount(400), 80400)
        self.assertEqual(self.diamond.TILE_COUNT, 80400)


if __name__ == "__main__":
    unittest.main()
