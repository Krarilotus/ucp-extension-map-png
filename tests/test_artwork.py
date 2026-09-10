"""Original ZIP artwork and shipped native pixels must stay in agreement."""
import hashlib
import pathlib
import struct
import unittest
from PIL import Image
import lua_harness
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))

ICONS = pathlib.Path(__file__).resolve().parents[1] / "resources" / "icons"
ORIGINALS = {
    "import_heightmap": "eaa8bfd6905b597dcad616b527e4c4baf2acaf307f13f60ffd9ec23edffdecb6",
    "export_heightmap": "217ed3c80fc2c8bfc1ec8c42bfc2d7b8995d6ee4f6d57bb0eaa39f30c6a29aa5",
    "import_textures": "ce0d8bf8ab476a7c641c18903d6afc4f7c0d34efc7f5543e5ab34ae691bd7e8c",
    "export_textures": "cff150211671f833e8173ac67524e172125f92fb5f1b7c7a7f77a92485561c7b",
}


class TestArtwork(unittest.TestCase):
    def test_original_pngs_are_byte_identical_to_supplied_zip(self):
        for name, digest in ORIGINALS.items():
            self.assertEqual(hashlib.sha256((ICONS / (name + ".png")).read_bytes()).hexdigest(), digest)

    def test_runtime_glyphs_preserve_the_new_creators_pixels_and_alpha(self):
        for name in ORIGINALS:
            with Image.open(ICONS / "creator-v2" / (name + ".png")) as source:
                self.assertEqual(source.mode, "RGBA")
                self.assertEqual(source.getpixel((0, 0))[3], 0)
                expected = source.crop((3, 3, 29, 14)).resize((52, 22), Image.Resampling.NEAREST)
            with Image.open(ICONS / "isolated" / (name + ".png")) as actual:
                self.assertEqual(actual.tobytes(), expected.tobytes())

    def test_native_streams_preserve_transparent_pixels_and_white_glyphs(self):
        lua = lua_harness.runtime()
        artwork = lua_harness.load(lua, "mappng.ui.artwork")
        for name in ORIGINALS:
            with Image.open(ICONS / "isolated" / (name + ".png")) as source:
                for mode in (555, 565):
                    stream = (ICONS / "isolated" / (name + ".%d.tgx" % mode)).read_bytes()
                    artwork.validate(stream)
                    position, x, y, transparent = 0, 0, 0, 0
                    while position < len(stream):
                        token = stream[position]
                        position += 1
                        kind, count = token & 0xE0, (token & 31) + 1
                        if kind == 0x80:
                            self.assertEqual(x, 52)
                            x, y = 0, y + 1
                            continue
                        for _ in range(count):
                            rgba = source.getpixel((x, y))
                            if kind == 0x20:
                                transparent += 1
                                self.assertLess(rgba[3], 128)
                            else:
                                self.assertEqual(kind, 0)
                                self.assertGreaterEqual(rgba[3], 128)
                                pixel = struct.unpack_from("<H", stream, position)[0]
                                position += 2
                                decoded = (pixel >> (11 if mode == 565 else 10),
                                           (pixel >> (6 if mode == 565 else 5)) & 31, pixel & 31)
                                self.assertEqual(decoded, tuple(v >> 3 for v in rgba[:3]))
                            x += 1
                    self.assertEqual((x, y), (0, 22))
                    self.assertGreater(transparent, 500, "opaque button panel returned")

    def test_native_button_bounds_fit_every_preview(self):
        lua = lua_harness.runtime()
        screens = lua_harness.load(lua, "mappng.ui.screens")
        screen = screens.SCREENS[1]
        for half in (75, 80, 100):
            layout = lua.table(half=half, centreX=600, centreY=240)
            previous_right = 600-126
            for i in range(1, 5):
                button = screens.buttonBounds(screen, i, layout)
                icon = screens.iconPosition(screen, i, layout)
                self.assertGreaterEqual(button.x, previous_right)
                self.assertLessEqual(button.x + button.width, 600+126)
                self.assertGreaterEqual(icon.x, button.x)
                self.assertLessEqual(icon.x + 52, button.x + button.width)
                self.assertEqual(button.y + (button.height-22)//2, icon.y)
                previous_right = button.x + button.width
