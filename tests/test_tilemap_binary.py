"""Runs the real mappng/map/tilemap.lua against memory it will actually see.

The map-section tables are static data in the executables' `.data`, so a fake
`core` that reads from the exe file on disk gives tilemap.lua exactly the
bytes it gets in the running game. That checks the Lua code itself -- not a
Python re-implementation of it -- against the real binaries.

The binary-backed tests are skipped when no game folder is available, so CI
still runs. Point MAPPNG_GAME_DIR at a game folder to override the default.
"""

import os
import pathlib
import struct
import unittest

import lua_harness

GAME_DIR = pathlib.Path(os.environ.get(
    "MAPPNG_GAME_DIR", r"S:/Projects/Harness/test-builds/map-png-test"))

CRUSADER_BASE = 0x01A93208   # OpenSHC DAT_TileMapState
EXTREME_BASE = 0x02526708


class PEImage:
    """Just enough PE parsing to read initialised data by virtual address."""

    def __init__(self, path):
        self.data = path.read_bytes()
        e = struct.unpack_from("<I", self.data, 0x3C)[0]
        opt = e + 24
        image_base = struct.unpack_from("<I", self.data, opt + 28)[0]
        opt_size = struct.unpack_from("<H", self.data, e + 20)[0]
        count = struct.unpack_from("<H", self.data, e + 6)[0]
        self.sections = []
        for i in range(count):
            o = opt + opt_size + i * 40
            vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", self.data, o + 8)
            self.sections.append((image_base + va, vsize, rawsize, rawptr))

    def read(self, address, size):
        for va, vsize, rawsize, rawptr in self.sections:
            if va <= address < va + vsize:
                offset = address - va
                if offset + size > rawsize:
                    raise ValueError("0x%X is uninitialised data" % address)
                return self.data[rawptr + offset:rawptr + offset + size]
        raise ValueError("0x%X is outside the image" % address)


def fake_core(lua, reader):
    """A `core` whose reads are served by `reader(address, size) -> bytes`."""
    return lua.table(
        readInteger=lambda a: struct.unpack("<i", reader(int(a), 4))[0],
        readSmallInteger=lambda a: struct.unpack("<h", reader(int(a), 2))[0],
    )


class TestTilemapSynthetic(unittest.TestCase):
    """Always runs: a synthetic Crusader-shaped table."""

    def setUp(self):
        self.lua = lua_harness.runtime()
        self.tilemap = lua_harness.load(self.lua, "mappng.map.tilemap")

    def memory(self, base, table_start, broken=None):
        blob = {}

        def record(address, size, section_id):
            return struct.pack("<IIIhh", address, 0, size, 0, section_id)

        offsets = {1003: 0x00165160, 1037: 0x001B3FE0, 1005: 0x0029FA30, 1045: 0x002B3440}
        sizes = {1003: 321600, 1037: 80400, 1005: 80400, 1045: 80400}
        table = b"".join(
            record(base + offsets[sid] + (4 if sid == broken else 0), sizes[sid], sid)
            for sid in offsets)
        blob[table_start] = table

        def reader(address, size):
            for start, data in blob.items():
                if start <= address and address + size <= start + len(data):
                    return data[address - start:address - start + size]
            return b"\0" * size
        return reader

    def test_resolves_crusader(self):
        core = fake_core(self.lua, self.memory(CRUSADER_BASE, 0x00B92A58))
        base, build = self.tilemap.resolveBase(core)
        self.assertEqual(base, CRUSADER_BASE)
        self.assertEqual(build, "Crusader 1.41")

    def test_resolves_extreme_through_its_own_table(self):
        core = fake_core(self.lua, self.memory(EXTREME_BASE, 0x00B92BE8 + 0x700))
        base, build = self.tilemap.resolveBase(core)
        self.assertEqual(base, EXTREME_BASE)
        self.assertEqual(build, "Crusader Extreme 1.41.1-E")

    def test_refuses_an_inconsistent_layout(self):
        core = fake_core(self.lua, self.memory(CRUSADER_BASE, 0x00B92A58, broken=1037))
        with self.assertRaises(Exception) as caught:
            self.tilemap.resolveBase(core)
        self.assertIn("refusing to touch the map", str(caught.exception))

    def test_minimap_view_state_address(self):
        self.assertEqual(self.tilemap.minimapViewStateAddress(CRUSADER_BASE), 0x01A31610)


@unittest.skipUnless((GAME_DIR / "Stronghold Crusader.exe").is_file(),
                     "no game folder at %s" % GAME_DIR)
class TestTilemapAgainstBinaries(unittest.TestCase):
    def setUp(self):
        self.lua = lua_harness.runtime()
        self.tilemap = lua_harness.load(self.lua, "mappng.map.tilemap")

    def resolve(self, exe):
        image = PEImage(GAME_DIR / exe)
        return self.tilemap.resolveBase(fake_core(self.lua, image.read))

    def test_crusader_matches_openshc(self):
        base, build = self.resolve("Stronghold Crusader.exe")
        self.assertEqual(base, CRUSADER_BASE)
        self.assertEqual(build, "Crusader 1.41")

    def test_extreme_resolves_to_its_relocated_base(self):
        base, _ = self.resolve("Stronghold_Crusader_Extreme.exe")
        self.assertEqual(base, EXTREME_BASE)


if __name__ == "__main__":
    unittest.main()
