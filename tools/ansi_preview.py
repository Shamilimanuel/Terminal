"""Draws coloured terminal text (what PowerShell prints) as a picture, so a banner can be checked without opening a terminal.

    python tools\\ansi_preview.py output.txt preview.png [background hex] [columns]

It understands the colour codes this project uses (24-bit foreground and background, bold, reset) and draws the half
blocks exactly, so what you see is what Windows Terminal draws.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CODE = re.compile(r"\x1b\[([0-9;]*)([A-Za-z])")


def parse(text):
    """Yields rows of (char, fg, bg, bold)."""
    rows = []
    for line in text.splitlines():
        fg = bg = None
        bold = False
        row, position = [], 0
        for match in CODE.finditer(line):
            for char in line[position:match.start()]:
                row.append((char, fg, bg, bold))
            position = match.end()
            if match.group(2) != "m":      # cursor moves and "erase to end of line" change nothing in a picture
                continue
            parts = [int(p) for p in match.group(1).split(";") if p != ""] or [0]
            i = 0
            while i < len(parts):
                p = parts[i]
                if p == 0:
                    fg = bg = None
                    bold = False
                elif p == 1:
                    bold = True
                elif p == 38 and parts[i + 1:i + 2] == [2]:
                    fg = tuple(parts[i + 2:i + 5])
                    i += 4
                elif p == 48 and parts[i + 1:i + 2] == [2]:
                    bg = tuple(parts[i + 2:i + 5])
                    i += 4
                i += 1
        for char in line[position:]:
            row.append((char, fg, bg, bold))
        rows.append(row)
    return rows


def draw(rows, background, columns=None, size=18):
    font = ImageFont.truetype("C:/Windows/Fonts/CascadiaMono.ttf", size)
    bold = ImageFont.truetype("C:/Windows/Fonts/CascadiaMono.ttf", size)
    try:
        font.set_variation_by_name("Regular")
        bold.set_variation_by_name("Bold")
    except Exception:
        pass
    cell_w = round(font.getlength("M"))
    cell_h = round(size * 1.35)
    width = (columns or max(len(r) for r in rows)) * cell_w + 36
    image = Image.new("RGB", (width, len(rows) * cell_h + 36), background)
    d = ImageDraw.Draw(image)
    for y, row in enumerate(rows):
        for x, (char, fg, bg, is_bold) in enumerate(row):
            left, top = 18 + x * cell_w, 18 + y * cell_h
            if "⠀" <= char <= "⣿":          # Braille dots: drawn as dots, the way a terminal font draws them
                mask = ord(char) - 0x2800
                bits = {(0, 0): 0x01, (0, 1): 0x02, (0, 2): 0x04, (1, 0): 0x08, (1, 1): 0x10, (1, 2): 0x20, (0, 3): 0x40, (1, 3): 0x80}
                radius = cell_w * 0.19
                for (dx, dy), bit in bits.items():
                    if mask & bit and fg:
                        cx, cy = left + cell_w * (0.28 + 0.44 * dx), top + cell_h * (0.14 + 0.24 * dy + 0.05)
                        d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=fg)
            elif char in "▀▄":
                half = cell_h // 2
                top_color, bottom_color = (fg, bg) if char == "▀" else (bg, fg)
                if top_color:
                    d.rectangle([left, top, left + cell_w - 1, top + half - 1], fill=top_color)
                if bottom_color:
                    d.rectangle([left, top + half, left + cell_w - 1, top + cell_h - 1], fill=bottom_color)
            else:
                if bg:
                    d.rectangle([left, top, left + cell_w - 1, top + cell_h - 1], fill=bg)
                if char != " ":
                    d.text((left, top + 2), char, font=bold if is_bold else font, fill=fg or (223, 243, 255))
    return image


if __name__ == "__main__":
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    background = "#" + (sys.argv[3] if len(sys.argv) > 3 else "0a1218").lstrip("#")
    columns = int(sys.argv[4]) if len(sys.argv) > 4 else None
    draw(parse(source.read_text(encoding="utf-8")), background, columns).save(target)
    print("saved", target)
