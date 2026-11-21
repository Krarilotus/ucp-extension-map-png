"""PNG height samples must survive import exactly and malformed files fail closed."""
import struct
import unittest
import zlib

from lua_harness import load, runtime


SIGNATURE = b'\x89PNG\r\n\x1a\n'
ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
         (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def chunk(kind, data=b''):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def png(width, height, depth, colour, raw, *, palette=b'', interlace=0, stream=None):
    header = struct.pack('>IIBBBBB', width, height, depth, colour, 0, 0, interlace)
    palette_chunk = chunk(b'PLTE', palette) if palette else b''
    stream = zlib.compress(raw) if stream is None else stream
    split = len(stream) // 2
    return (SIGNATURE + chunk(b'IHDR', header) + chunk(b'gAMA', struct.pack('>I', 45455))
            + palette_chunk + chunk(b'IDAT', stream[:split]) + chunk(b'IDAT', stream[split:])
            + chunk(b'IEND'))


class TestPngDecode(unittest.TestCase):
    def setUp(self):
        self.decoder = load(runtime(), 'mappng.png.decode')

    def assertGray(self, image, expected):
        values = self.decoder.toGray(self.decoder.decodeBytes(image))
        self.assertEqual([values.gray[i] for i in range(values.width * values.height)], expected)

    def test_every_legal_colour_type_and_depth(self):
        for depth in (1, 2, 4, 8, 16):
            maximum = (1 << depth) - 1
            packed = (maximum << (8 - depth)).to_bytes(1) if depth <= 8 else b'\xff\xff'
            self.assertGray(png(1, 1, depth, 0, b'\0' + packed), [255])
            if depth <= 8:
                indexed = (1 << (8 - depth)).to_bytes(1)
                self.assertGray(png(1, 1, depth, 3, b'\0' + indexed,
                                    palette=b'\0\0\0\xff\0\0'), [76])
        for depth, zero, full, gray in ((8, b'\0', b'\xff', b'\x80'),
                                        (16, b'\0\0', b'\xff\xff', b'\x80\x80')):
            self.assertGray(png(1, 1, depth, 2, b'\0' + full + zero + zero), [76])
            self.assertGray(png(1, 1, depth, 4, b'\0' + gray + zero), [128])
            self.assertGray(png(1, 1, depth, 6, b'\0' + zero + full + zero + zero), [150])

    def test_scanline_filters(self):
        raw = bytes([0, 10, 20, 1, 15, 10, 2, 5, 5, 3, 22, 20, 4, 5, 5])
        self.assertGray(png(2, 5, 8, 0, raw), [10, 20, 15, 25, 20, 30, 32, 51, 37, 56])

    def test_adam7_scatter(self):
        width, height = 11, 9
        pixels = list(range(width * height))
        raw = bytearray()
        for x0, y0, dx, dy in ADAM7:
            for y in range(y0, height, dy):
                raw.append(0)
                raw.extend(pixels[y * width + x] for x in range(x0, width, dx))
        self.assertGray(png(width, height, 8, 0, raw, interlace=1), pixels)

    def test_stored_fixed_and_dynamic_deflate(self):
        row = bytes(range(200)) + bytes(range(200))
        raw = (b'\0' + row) * 400
        fixed = zlib.compressobj(strategy=zlib.Z_FIXED)
        streams = (zlib.compress(raw, 0), fixed.compress(raw) + fixed.flush(), zlib.compress(raw))
        self.assertEqual([(stream[2] >> 1) & 3 for stream in streams], [0, 1, 2])
        for stream in streams:
            self.assertGray(png(400, 400, 8, 0, raw, stream=stream), list(row) * 400)

    def test_rejects_integrity_errors_and_excess_output(self):
        raw = b'\0\x80'
        valid = png(1, 1, 8, 0, raw)
        stream = zlib.compress(raw)
        for image, reason in (
            (valid[:-1] + b'\0', 'chunk CRC'),
            (valid[:-1], 'complete IEND'),
            (png(1, 1, 8, 0, raw, stream=stream[:-1] + bytes([stream[-1] ^ 1])), 'Adler-32'),
            (png(1, 1, 8, 0, raw, stream=stream + b'\0'), 'image data length'),
            (png(1, 1, 8, 0, b'\0' * 50000), 'excess PNG image data'),
            (png(1, 1, 4, 2, raw), 'colour type or bit depth'),
            (png(0xFFFFFFFF, 0xFFFFFFFF, 8, 0, raw), 'dimensions'),
            (png(1, 1, 8, 0, b'\x05\0'), 'bad PNG filter'),
        ):
            with self.subTest(reason=reason), self.assertRaisesRegex(Exception, reason):
                self.decoder.decodeBytes(image)
        with self.assertRaisesRegex(Exception, '400x400'):
            self.decoder.decodeBytes(valid, 400)
        with self.assertRaisesRegex(Exception, 'missing palette entry'):
            self.assertGray(png(1, 1, 8, 3, b'\0\x01', palette=b'\0\0\0'), [])
