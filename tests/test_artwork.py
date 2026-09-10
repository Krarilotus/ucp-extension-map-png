"""Original ZIP artwork and shipped native pixels must stay in agreement."""
import hashlib
import pathlib
import struct
import unittest
from PIL import Image
import lua_harness

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

    def test_native_streams_contain_every_original_pixel(self):
        for name in ORIGINALS:
            with Image.open(ICONS / (name + ".png")) as source:
                rgb = source.convert("RGB")
                for mode in (555, 565):
                    stream = (ICONS / (name + ".%d.tgx" % mode)).read_bytes()
                    self.assertEqual(len(stream), 1188)
                    for y in range(18):
                        row = stream[y*66:(y+1)*66]
                        self.assertEqual((row[0], row[-1]), (31, 128))
                        for x, pixel in enumerate(struct.unpack("<32H", row[1:-1])):
                            decoded = (pixel >> (11 if mode == 565 else 10),
                                       (pixel >> (6 if mode == 565 else 5)) & 31, pixel & 31)
                            self.assertEqual(decoded, tuple(v >> 3 for v in rgb.getpixel((x, y))))

    def test_native_button_bounds_fit_every_preview(self):
        lua = lua_harness.runtime()
        screens = lua_harness.load(lua, "mappng.ui.screens")
        screen = screens.SCREENS[1]
        for half in (75, 80, 100):
            layout = lua.table(half=half, centreX=600, centreY=240)
            previous_right = 600-half
            for i in range(1, 5):
                button = screens.buttonBounds(screen, i, layout)
                icon = screens.iconPosition(screen, i, layout)
                self.assertGreaterEqual(button.x, previous_right)
                self.assertLessEqual(button.x + button.width, 600+half)
                self.assertGreaterEqual(icon.x, button.x)
                self.assertLessEqual(icon.x + 32, button.x + button.width)
                self.assertEqual(button.y + (button.height-18)//2, icon.y)
                previous_right = button.x + button.width
