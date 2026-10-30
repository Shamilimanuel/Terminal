"""Tests for the Sixel pictures: the encoder's output reads back as the same picture, and the pictures that ship look right.

Run with:  python tests\\run_all.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import make_sixel
import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent

# a small picture with a see-through background, two colours and a gradient
source = Image.new("RGBA", (40, 30), (0, 0, 0, 0))
draw = ImageDraw.Draw(source)
draw.rectangle([4, 4, 20, 14], fill=(255, 200, 40, 255))
draw.ellipse([22, 8, 36, 26], fill=(40, 200, 255, 255))
for x in range(5, 19):
    draw.line([(x, 18), (x, 24)], fill=(x * 12, 90, 255 - x * 10, 255))
text = make_sixel.encode(source, colors=32)
assert text.startswith("\x1bP0;1;0q\"1;1;40;30") and text.endswith("\x1b\\"), "framed as a Sixel picture of the right size"
assert text.count("\x1bP") == 1 and "\x1b" not in text[2:-2], "no stray control characters inside"
back = make_sixel.decode(text)
assert back.size == source.size
bad = 0
for y in range(30):
    for x in range(40):
        a, b = source.getpixel((x, y)), back.getpixel((x, y))
        if a[3] == 0:
            assert b[3] == 0, f"({x},{y}) was see-through and must stay see-through"
        elif b[3] == 0 or max(abs(a[i] - b[i]) for i in range(3)) > 40:
            bad += 1
assert bad <= 6, f"{bad} pixels came back with the wrong colour"
print("sixel round trip OK")

# the pictures that ship
for name, size in (("rune-280x280", (280, 280)), ("rune-360x360", (360, 360)), ("rune-440x440", (440, 440)),
                   ("elevated-280x356", (280, 356)), ("elevated-360x458", (360, 458)), ("elevated-440x560", (440, 560))):
    data = (root / "art" / f"{name}.six").read_text(encoding="ascii")
    assert data.startswith("\x1bP0;1;0q") and data.endswith("\x1b\\") and f'"1;1;{size[0]};{size[1]}' in data, name
    assert len(data) < 400_000, f"{name} is small enough to print in a blink"
picture = make_sixel.decode((root / "art" / "rune-360x360.six").read_text(encoding="ascii"))
covered = float((np.asarray(picture)[:, :, 3] > 0).mean())
assert 0.15 < covered < 0.9, f"the emblem fills part of its square, not none and not all ({covered:.2f})"
elevated = make_sixel.decode((root / "art" / "elevated-360x458.six").read_text(encoding="ascii"))
z = np.asarray(elevated).astype(int)
amber = int(((z[:, :, 3] > 0) & (z[:, :, 0] > 180) & (z[:, :, 0] - z[:, :, 2] > 60) & (z[:, :, 1] > 100)).sum())
assert amber > 4000, f"the sigil and the title are amber ({amber} amber pixels)"
print("shipped pictures OK")
print("sixel tests passed")
