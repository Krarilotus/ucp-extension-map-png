"""The external probe must derive TileMapState the same way tilemap.lua does."""

import pathlib
import struct
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "tools"))

import probe_running_game as probe  # noqa: E402

BASE = 0x01A93208


def record(address, size, section_id):
    return struct.pack("<IIIhh", address, 0, size, 0, section_id)


def table(base=BASE, sizes=None, skew=None):
    """A synthetic section table laid out like Crusader 1.41."""
    sizes = sizes or {}
    skew = skew or {}
    data = record(0x12345678, 4, 1017)  # an unrelated section
    for section_id, (field, size) in probe.SECTIONS.items():
        address = base + probe.OFFSETS[field] + skew.get(section_id, 0)
        data += record(address, sizes.get(section_id, size), section_id)
    return data + record(0, 0, 0)  # padding records are skipped


class TestProbe(unittest.TestCase):
    def test_derives_the_openshc_base(self):
        base, problems = probe.derive_base(probe.parse_section_table(table()))
        self.assertEqual(problems, [])
        self.assertEqual(base, BASE)
        self.assertEqual(base, probe.EXPECTED_BASE)

    def test_sourcehold_redraw_address_agrees(self):
        """sourcehold hardcodes futureMapOrientation = 0x01FE7AA8."""
        self.assertEqual(BASE + probe.OFFSETS["futureMapOrientation"], 0x01FE7AA8)
        self.assertEqual(BASE + probe.OFFSETS["mapOrientation"], 0x01FE7AA4)

    def test_minimap_state_sits_directly_before_tilemap_state(self):
        """sizeof(MinimapViewState) is 0x61BF8 in OpenSHC."""
        self.assertEqual(BASE - probe.MINIMAP_VIEW_STATE, 0x61BF8)

    def test_inconsistent_layout_is_reported(self):
        _, problems = probe.derive_base(
            probe.parse_section_table(table(skew={1037: 4})))
        self.assertTrue(any("1037" in p for p in problems), problems)

    def test_wrong_size_is_reported(self):
        _, problems = probe.derive_base(
            probe.parse_section_table(table(sizes={1045: 40000})))
        self.assertTrue(any("1045" in p for p in problems), problems)

    def test_missing_section_is_reported(self):
        data = b"".join(
            record(BASE + probe.OFFSETS[field], size, sid)
            for sid, (field, size) in probe.SECTIONS.items() if sid != 1003)
        _, problems = probe.derive_base(probe.parse_section_table(data))
        self.assertIn("section 1003 missing", problems)


if __name__ == "__main__":
    unittest.main()
