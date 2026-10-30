"""Makes the "real picture" emblems: Sixel images, the picture format Windows Terminal (1.22 and newer) can show.

    python tools\\make_sixel.py            writes art\\rune-<width>x<height>.six and art\\elevated-<width>x<height>.six in a few sizes

A Sixel file is plain text: a palette, then the picture in strips six pixels tall. Dark pixels are left out (the terminal's
see-through window shows through), so the glow floats over your desktop. The banner picks the size that fits your font.
"""
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ESC = "\x1b"
DARK_BELOW = 26            # pixels darker than this (0-255) are left out of the picture
WIDTHS = (280, 360, 440)   # pixel widths made; the banner chooses by the size of your terminal's characters


# ---------- the encoder ----------

def encode(image, colors=64):
    """An RGBA or RGB picture as a Sixel string (DCS ... ST). Transparent and very dark pixels are not drawn."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    rgb = Image.alpha_composite(Image.new("RGBA", rgba.size, (0, 0, 0, 255)), rgba).convert("RGB")
    array = np.asarray(rgb)
    visible = (array.max(axis=2) >= DARK_BELOW) & (np.asarray(rgba)[:, :, 3] > 40)
    quantized = rgb.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    index = np.asarray(quantized).astype(np.int32)
    palette = quantized.getpalette()[: colors * 3]
    used = sorted(set(index[visible].tolist()))
    out = [f"{ESC}P0;1;0q\"1;1;{width};{height}"]
    for c in used:
        r, g, b = palette[c * 3: c * 3 + 3]
        out.append(f"#{c};2;{round(r * 100 / 255)};{round(g * 100 / 255)};{round(b * 100 / 255)}")
    weights = (1 << np.arange(6)).reshape(6, 1)
    for top in range(0, height, 6):
        band_index = index[top:top + 6]
        band_visible = visible[top:top + 6]
        rows = band_index.shape[0]
        colors_here = [c for c in used if np.any((band_index == c) & band_visible)]
        for n, c in enumerate(colors_here):
            bits = (((band_index == c) & band_visible).astype(np.int32) * weights[:rows]).sum(axis=0)
            out.append(f"#{c}" + _runs(bits))
            out.append("$" if n < len(colors_here) - 1 else "")
        out.append("-")
    out.append(f"{ESC}\\")
    return "".join(out)


def _runs(bits):
    """The six-pixel columns as characters, with repeats written as !<count><character>."""
    text, i, n = [], 0, len(bits)
    while i < n:
        j = i
        while j < n and bits[j] == bits[i]:
            j += 1
        char = chr(63 + int(bits[i]))
        count = j - i
        text.append(f"!{count}{char}" if count > 3 else char * count)
        i = j
    return "".join(text)


# ---------- a decoder, only to prove the encoder's output reads back as the same picture (used by the tests) ----------

def decode(data):
    """Reads Sixel written by encode() back into an RGBA picture."""
    body = data[data.index("q") + 1: data.rindex(ESC)]
    palette, x, y, color = {}, 0, 0, 0
    width = height = 0
    if body.startswith('"'):
        end = next(i for i, ch in enumerate(body) if ch in "#?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-$!" and i > 0)
        parts = [int(p) for p in body[1:end].split(";")]
        width, height = parts[2], parts[3]
        body = body[end:]
    picture = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = picture.load()
    i = 0
    while i < len(body):
        ch = body[i]
        if ch == "#":
            j = i + 1
            while j < len(body) and (body[j].isdigit() or body[j] == ";"):
                j += 1
            numbers = [int(p) for p in body[i + 1:j].split(";")]
            color = numbers[0]
            if len(numbers) >= 5:
                palette[color] = tuple(round(v * 255 / 100) for v in numbers[2:5])
            i = j
        elif ch == "!":
            j = i + 1
            while body[j].isdigit():
                j += 1
            count, char = int(body[i + 1:j]), body[j]
            _paint(pixels, palette[color], x, y, ord(char) - 63, count, width, height)
            x += count
            i = j + 1
        elif ch == "$":
            x = 0
            i += 1
        elif ch == "-":
            x, y = 0, y + 6
            i += 1
        else:
            _paint(pixels, palette.get(color, (0, 0, 0)), x, y, ord(ch) - 63, 1, width, height)
            x += 1
            i += 1
    return picture


def _paint(pixels, rgb, x, y, bits, count, width, height):
    for k in range(6):
        if bits & (1 << k) and y + k < height:
            for dx in range(count):
                if x + dx < width:
                    pixels[x + dx, y + k] = rgb + (255,)


# ---------- the pictures ----------

def glow_square(path):
    """The rune emblem picture cropped to its glowing part, centred in a black square."""
    rgba = Image.open(path).convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] < 250:                           # a cut-out picture: its see-through area decides the shape
        image = Image.alpha_composite(Image.new("RGBA", rgba.size, (0, 0, 0, 255)), rgba).convert("RGB")
        mask = alpha.point(lambda v: 255 if v > 20 else 0)
    else:
        image = rgba.convert("RGB")
        mask = image.convert("L").point(lambda v: 255 if v > 40 else 0)
    left, top, right, bottom = mask.getbbox()
    side = max(right - left, bottom - top) + 24
    cx, cy = (left + right) // 2, (top + bottom) // 2
    square = Image.new("RGB", (side, side), (0, 0, 0))
    square.paste(image, (-(cx - side // 2), -(cy - side // 2)))
    return square


def boost(image, gain=1.18):
    """A little more punch, so thin glowing lines survive being made smaller."""
    return image.point(lambda v: min(255, int(v * gain)))


def title_picture(width):
    """The Administrator picture (small sigil + TERMINAL), made by tools/make_emblem.py as art/title-source.png, at any width."""
    source = Image.open(Path(__file__).resolve().parent.parent / "art" / "title-source.png").convert("RGB")
    height = int(round(width * 560 / 440.0))
    return boost(source.resize((width, height), Image.LANCZOS), 1.1)


def main():
    folder = Path(__file__).resolve().parent.parent / "art"
    source = glow_square(folder / "rune-source.png")
    flat = Image.open(folder / "rune-source.png").convert("RGBA").getchannel("A").getextrema()[0] < 250
    for width in WIDTHS:
        for name, picture in (("rune", (source.resize((width, width), Image.LANCZOS) if flat else boost(source.resize((width, width), Image.LANCZOS)))), ("elevated", title_picture(width))):
            text = encode(picture, colors=96)
            target = folder / f"{name}-{picture.width}x{picture.height}.six"
            target.write_text(text, encoding="ascii")
            if "--previews" in sys.argv:                       # look at the pictures themselves (not kept in the project)
                picture.save(Path(tempfile.gettempdir()) / f"{name}-{picture.width}x{picture.height}-preview.png")
            print(f"{target.name}: {len(text) // 1024} KB")


if __name__ == "__main__":
    main()
