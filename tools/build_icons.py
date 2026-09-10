"""Convert the supplied PNGs to native TGX streams, without resizing/redrawing."""
from pathlib import Path
import struct
from PIL import Image

ICONS = Path(__file__).resolve().parents[1] / "resources" / "icons"
NAMES = ("import_heightmap", "export_heightmap", "import_textures", "export_textures")


def encode(image, rgb565=False):
    if image.size != (32, 18):
        raise ValueError("Expected the original 32x18 artwork")
    pixels = image.convert("RGB")
    out = bytearray()
    for y in range(18):
        out.append(31)  # TGX literal run: length minus one
        for x in range(32):
            r, g, b = pixels.getpixel((x, y))
            # Match the game's RGB555 -> RGB565 conversion.
            value = ((r >> 3) << (11 if rgb565 else 10)) | ((g >> 3) << (6 if rgb565 else 5)) | (b >> 3)
            out.extend(struct.pack("<H", value))
        out.append(128)  # TGX newline
    return bytes(out)


if __name__ == "__main__":
    for name in NAMES:
        with Image.open(ICONS / (name + ".png")) as image:
            for mode in (555, 565):
                target = ICONS / (name + ".%d.tgx" % mode)
                target.write_bytes(encode(image, mode == 565))
                print(target.name)
