"""Reads the geometry of the button icons without needing Pillow.

Only the PNG header and the presence of a tRNS chunk are needed, so a ~30 line
parser beats a dependency.
"""

import pathlib
import struct

ICONS = pathlib.Path(__file__).resolve().parent.parent / "resources" / "icons"

EXPECTED = [
    "import_heightmap.png",
    "export_heightmap.png",
    "import_textures.png",
    "export_textures.png",
]


def describe(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path.name)

    width, height = struct.unpack(">II", data[16:24])
    bit_depth, colour_type = data[24], data[25]

    offset, chunks = 8, []
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunks.append(data[offset + 4:offset + 8].decode("ascii"))
        offset += 12 + length

    return {
        "name": path.name,
        "width": width,
        "height": height,
        "bit_depth": bit_depth,
        "colour_type": colour_type,
        "has_alpha": "tRNS" in chunks or colour_type in (4, 6),
    }


def main():
    for name in EXPECTED:
        info = describe(ICONS / name)
        print("{name:24} {width}x{height}  depth={bit_depth}  "
              "colourType={colour_type}  alpha={has_alpha}".format(**info))


if __name__ == "__main__":
    main()
