"""Encode icon pixels as TGX, preserving transparent holes and background."""
from pathlib import Path
import struct
from PIL import Image, ImageDraw

ICONS = Path(__file__).resolve().parents[1] / "resources" / "icons" / "isolated"
SOURCE = ICONS.parent / "creator-v2"
NAMES = ("import_heightmap", "export_heightmap", "import_textures", "export_textures")


def encode(image, rgb565=False):
    width, height = image.size
    pixels = image.convert("RGBA")
    out = bytearray()
    for y in range(height):
        x = 0
        while x < width:
            transparent = pixels.getpixel((x, y))[3] < 128
            end = x + 1
            while end < width and end - x < 32 and (pixels.getpixel((end, y))[3] < 128) == transparent:
                end += 1
            # Transparent runs advance the destination without painting it.
            out.append((0x20 if transparent else 0) | (end - x - 1))
            if not transparent:
                for column in range(x, end):
                    r, g, b, _ = pixels.getpixel((column, y))
                    value = ((r >> 3) << (11 if rgb565 else 10)) | ((g >> 3) << (6 if rgb565 else 5)) | (b >> 3)
                    out.extend(struct.pack("<H", value))
            x = end
        out.append(128)  # TGX newline
    return bytes(out)


if __name__ == "__main__":
    ICONS.mkdir(exist_ok=True)
    review = Image.new("RGB", (1000, 180), (35, 30, 25))
    draw = ImageDraw.Draw(review)
    for index, name in enumerate(NAMES):
        with Image.open(SOURCE / (name + ".png")) as original:
            # Creator-supplied alpha replaces the earlier inferred colour mask.
            # Crop transparent padding and replicate pixels at exactly 2x.
            image = original.crop((3, 3, 29, 14)).resize((52, 22), Image.Resampling.NEAREST)
            image.save(ICONS / (name + ".png"))
            for mode in (555, 565):
                target = ICONS / (name + ".%d.tgx" % mode)
                target.write_bytes(encode(image, mode == 565))
                print(target.name)
            # Review the native binary-alpha result, not a smoother PNG proxy.
            native = image.copy()
            native.putalpha(image.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
            x = index * 250 + 18
            draw.text((x, 10), name, fill="white")
            enlarged = native.resize((208, 88), Image.Resampling.NEAREST)
            review.paste(enlarged, (x, 36), enlarged)
            review.paste(native, (x + 75, 144), native)
    review.save(ICONS.parents[2] / "docs" / "artwork-review.png")
