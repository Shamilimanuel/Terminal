"""Turns a picture into coloured terminal art (the left side of the banner).

    python tools\\image_to_ansi.py art\\rune-source.png art\\rune.ans 56            sharp (Braille dots, the default)
    python tools\\image_to_ansi.py art\\rune-source.png art\\rune-blocks.ans 56 blocks   chunky (half blocks)
    python tools\\image_to_ansi.py art\\rune-source.png art\\x.ans 56 braille 5fd4ff          repainted in one colour

columns   how wide the art is in text columns.
style     braille: every character holds 2x4 tiny dots, so 4 times the detail. blocks: every character holds 2 pixels.
          ascii: letters and symbols (. : - = + * # % @), the look of a classic ASCII-art logo.
tint      optional hex colour (no #) to repaint the glow in, instead of the picture's own colours.

Dark parts of the picture are left EMPTY (not painted black), so a see-through terminal shows your desktop through them.
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ESC = "\x1b"
EMPTY_BELOW = 30        # pixels darker than this (0-255) stay see-through
# which bit of a Braille character each dot is: (column, row) inside the 2 x 4 cell
DOT_BITS = {(0, 0): 0x01, (0, 1): 0x02, (0, 2): 0x04, (1, 0): 0x08, (1, 1): 0x10, (1, 2): 0x20, (0, 3): 0x40, (1, 3): 0x80}


FLAT = (77, 220, 163)      # the mint green of the flat picture


def is_cutout(image):
    """True for a picture with a real see-through background (flat colour, no glow)."""
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.getextrema()[0] < 250


def shrink(square, flat, size):
    """Makes the picture smaller. A glowing picture is thickened a little first (its thin lines would fade); a flat picture
    is shrunk as it is, so its thin lines and details stay true."""
    if not flat:
        square = square.filter(ImageFilter.MaxFilter(3))
    return square.resize(size, Image.LANCZOS)


def square_of_glow(image, margin=24):
    """The shape of the picture, centred in a black square (the see-through parts become black)."""
    if is_cutout(image):
        rgba = image.convert("RGBA")
        alpha = rgba.getchannel("A")
        image = Image.alpha_composite(Image.new("RGBA", rgba.size, (0, 0, 0, 255)), rgba).convert("RGB")
        glow = alpha.point(lambda v: 255 if v > 20 else 0)
    else:
        image = image.convert("RGB")
        glow = image.convert("L").point(lambda v: 255 if v > 40 else 0)
    left, top, right, bottom = glow.getbbox()
    side = max(right - left, bottom - top) + margin
    cx, cy = (left + right) // 2, (top + bottom) // 2
    box = (cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)
    square = Image.new("RGB", (side, side), (0, 0, 0))
    square.paste(image, (-box[0], -box[1]))
    return square


def contrast(rgb, tint=None, gain=1.15, flat=False):
    """Deepens the soft halo so the lines stand out, and optionally repaints in one colour.
    flat=True is for a flat-colour picture: how much of a spot the shape covers decides how bright it is (thin lines
    that were shrunk keep a good part of their brightness), and the colour is always the picture's own."""
    r, g, b = rgb
    level = max(r, g, b)
    if flat:
        coverage = min(1.0, (min(1.0, level / float(max(FLAT))) ** 0.8) * 1.5)
        base = FLAT
        if tint:
            base = tuple(int(tint[i:i + 2], 16) for i in (0, 2, 4))
        return tuple(int(c * coverage) for c in base)
    curve = max(0.0, (level - 70) / 185) ** 1.15
    scale = (curve * 255) / level if level else 0
    r, g, b = int(r * scale), int(g * scale), int(b * scale)
    level = max(r, g, b)
    if tint:
        t = [int(tint[i:i + 2], 16) for i in (0, 2, 4)]
        k = min(1.0, level / 255 * 1.35)
        return (int(t[0] * k), int(t[1] * k), int(t[2] * k))
    return (min(255, int(r * gain)), min(255, int(g * gain)), min(255, int(b * gain)))


# ---------- chunky: two pixels per character ----------

def prepare_blocks(image, columns, tint=None):
    flat = is_cutout(image)
    small = shrink(square_of_glow(image), flat, (columns, columns))
    out = Image.new("RGB", small.size)
    for y in range(small.height):
        for x in range(small.width):
            out.putpixel((x, y), contrast(small.getpixel((x, y)), tint, flat=flat))
    return out


def blocks_to_ansi(pixels):
    lines = []
    for y in range(0, pixels.height - 1, 2):
        text = ""
        for x in range(pixels.width):
            top, bottom = pixels.getpixel((x, y)), pixels.getpixel((x, y + 1))
            top_on, bottom_on = max(top) >= EMPTY_BELOW, max(bottom) >= EMPTY_BELOW
            if top_on and bottom_on:
                text += f"{ESC}[38;2;{top[0]};{top[1]};{top[2]}m{ESC}[48;2;{bottom[0]};{bottom[1]};{bottom[2]}m▀"
            elif top_on:
                text += f"{ESC}[0m{ESC}[38;2;{top[0]};{top[1]};{top[2]}m▀"
            elif bottom_on:
                text += f"{ESC}[0m{ESC}[38;2;{bottom[0]};{bottom[1]};{bottom[2]}m▄"
            else:
                text += f"{ESC}[0m "
        lines.append(text + f"{ESC}[0m")
    return lines


# ---------- classic: letters and symbols, the look of an ASCII-art logo ----------

RAMP = " .:-=+*#%@"                 # from empty to solid


def ascii_to_ansi(image, columns, tint=None):
    """One character per picture column and one per TWO picture rows (characters are about twice as tall as wide)."""
    flat = is_cutout(image)
    small = shrink(square_of_glow(image), flat, (columns, columns))
    lines = []
    for y in range(0, small.height - 1, 2):
        text = ""
        for x in range(small.width):
            a, b = contrast(small.getpixel((x, y)), tint, flat=flat), contrast(small.getpixel((x, y + 1)), tint, flat=flat)
            colour = tuple((a[i] + b[i]) // 2 for i in range(3))
            level = max(colour) / 255
            if max(colour) < EMPTY_BELOW:
                text += f"{ESC}[0m "
            else:
                text += f"{ESC}[38;2;{colour[0]};{colour[1]};{colour[2]}m{RAMP[min(len(RAMP) - 1, int(level * 1.25 * (len(RAMP) - 1)))]}"
        lines.append(text + f"{ESC}[0m")
    return lines


# ---------- sharp: 2 x 4 dots per character ----------

def braille_cells(image, columns, tint=None):
    """Rows of cells; a cell is None (empty) or (dot mask 1-255, (r, g, b))."""
    width = columns * 2
    height = width - (width % 4)
    flat = is_cutout(image)
    small = shrink(square_of_glow(image), flat, (width, height))
    colours = [[contrast(small.getpixel((x, y)), tint, gain=1.25, flat=flat) for x in range(width)] for y in range(height)]
    level = [[min(1.0, max(colours[y][x]) / 255 * 1.45) for x in range(width)] for y in range(height)]   # bright areas become solid
    # Floyd-Steinberg: a soft glow becomes a loose scatter of dots, a bright line becomes solid dots
    for y in range(height):
        for x in range(width):
            old = level[y][x]
            new = 1.0 if old >= 0.5 else 0.0
            level[y][x] = new
            error = old - new
            for dx, dy, share in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    level[ny][nx] += error * share
    rows = []
    for cy in range(0, height, 4):
        row = []
        for cx in range(0, width, 2):
            mask, lit = 0, []
            for (dx, dy), bit in DOT_BITS.items():
                if level[cy + dy][cx + dx] >= 0.5 and max(colours[cy + dy][cx + dx]) >= EMPTY_BELOW:
                    mask |= bit
                    lit.append(colours[cy + dy][cx + dx])
            if mask:
                row.append((mask, tuple(sum(c[i] for c in lit) // len(lit) for i in range(3))))
            else:
                row.append(None)
        rows.append(row)
    return rows


def braille_to_ansi(rows):
    lines = []
    for row in rows:
        text = ""
        for cell in row:
            if cell is None:
                text += f"{ESC}[0m "
            else:
                mask, (r, g, b) = cell
                text += f"{ESC}[38;2;{r};{g};{b}m{chr(0x2800 + mask)}"
        lines.append(text + f"{ESC}[0m")
    return lines


def convert(source, columns, style="braille", tint=None):
    image = Image.open(source)
    if style == "blocks":
        return blocks_to_ansi(prepare_blocks(image, columns, tint))
    if style == "ascii":
        return ascii_to_ansi(image, columns, tint)
    return braille_to_ansi(braille_cells(image, columns, tint))


if __name__ == "__main__":
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    columns = int(sys.argv[3]) if len(sys.argv) > 3 else 46
    style = sys.argv[4] if len(sys.argv) > 4 else "braille"
    tint = sys.argv[5] if len(sys.argv) > 5 else None
    lines = convert(source, columns, style, tint)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{style}: {columns} columns x {len(lines)} rows -> {target}")
