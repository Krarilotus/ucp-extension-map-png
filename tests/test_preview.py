import unittest
import lua_harness


class TestPreview(unittest.TestCase):
    def setUp(self):
        # Binary TGX is not UTF-8; keep Python-facing Lua strings as bytes.
        from lupa.lua54 import LuaRuntime
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        root = lua_harness.ROOT.as_posix()
        self.lua.execute(('package.path = "' + root + '/?.lua;' + root + '/?/init.lua;" .. package.path').encode())
        self.preview = self.lua.eval(b'(require("mappng.ui.preview"))')
        self.art = self.lua.eval(b'(require("mappng.ui.artwork"))')

    def test_preview_comes_from_png_pixels(self):
        image = self.lua.table_from({b"width": 2, b"height": 2,
            b"rgb": self.lua.table_from({0: 0xFF0000, 1: 0x00FF00, 2: 0x0000FF, 3: 0xFFFFFF})})
        stream, width, height = self.preview.encode(image, 160, 160, False)
        self.assertEqual((width, height), (2, 2))
        self.assertEqual(stream, b'\x01\x00\x7c\xe0\x03\x80\x01\x1f\x00\xff\x7f\x80')
        self.art.validate(stream, width, height)

    def test_large_preview_is_bounded_and_preserves_aspect(self):
        image = self.lua.eval(b'{width=400,height=400,gray=setmetatable({}, {__index=function() return 128 end})}')
        stream, width, height = self.preview.encode(image, 160, 160, True)
        self.assertEqual((width, height), (160, 160))
        self.art.validate(stream, width, height)
        self.assertLess(len(stream), 53000)

    def test_truncated_preview_is_rejected(self):
        with self.assertRaises(Exception):
            self.art.validate(b'\x01\x00', 2, 1)
