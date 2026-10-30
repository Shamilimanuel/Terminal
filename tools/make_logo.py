"""Draws the Administrator emblem in letters and symbols, in amber: a hexagon with a T in it, and the word TERMINAL under it.

    python tools\\make_logo.py                          writes art\\elevated.ans and art\\elevated-small.ans
    python tools\\make_logo.py --subtitle "ELEVATED"    the small line under the title ("" for none)
    python tools\\make_logo.py --above "SIGNED IN AS"   a small line above the big title (none by default)

The hexagon is built from / and \\ edges and _ lines, with : dots inside; the T is # and @, with a little = cursor beside its stem.
Colours run from light amber at the top to deep amber.
"""
import argparse
from pathlib import Path

ESC = "\x1b"
TOP, BOTTOM = (255, 226, 184), (224, 120, 42)
EDGE = (255, 240, 214)
DOT = (150, 98, 58)
CURSOR = (255, 107, 129)
TEXT_TOP, TEXT_BOTTOM = (255, 236, 205), (240, 160, 80)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def paint(char, colour):
    return f"{ESC}[38;2;{colour[0]};{colour[1]};{colour[2]}m{char}"


def hexagon(h, flat):
    """A flat-topped hexagon: h rows going out, h rows coming in, a flat line top and bottom. Returns (grid, T cells)."""
    width = flat + 2 * h
    rows = 2 * h + 2
    grid = [[None] * width for _ in range(rows)]
    for x in range(h, h + flat):
        grid[0][x] = ("_", "edge")
        grid[rows - 1][x] = ("_", "edge")
    for i in range(h):
        y = 1 + i
        left, right = h - 1 - i, width - h + i
        grid[y][left], grid[y][right] = ("/", "edge"), ("\\", "edge")
        grid[h + 1 + i][i] = ("\\", "edge")
        grid[h + 1 + i][width - 1 - i] = ("/", "edge")
    for y in range(1, rows - 1):                                     # dotted inside
        inside = [x for x in range(width) if grid[y][x] is not None and grid[y][x][1] == "edge"]
        if len(inside) >= 2:
            for x in range(inside[0] + 1, inside[-1]):
                if (x + y) % 2 == 0 and grid[y][x] is None:
                    grid[y][x] = (":", "dot")
    return grid


def put_t(grid, h):
    """Draws a T in the middle: a wide bar, a stem, and a cursor."""
    width, rows = len(grid[0]), len(grid)
    centre = width // 2
    bar_rows = 2 if h < 7 else 3
    bar_half = max(5, int(h * 1.1))
    stem_half = 1 if h < 7 else 2
    stem_rows = h - bar_rows + 1
    top = (rows - bar_rows - stem_rows) // 2
    for r in range(bar_rows):
        for x in range(centre - bar_half, centre + bar_half + 1):
            grid[top + r][x] = ("@" if r == 0 else "#", "t")
    for r in range(bar_rows, bar_rows + stem_rows):
        for x in range(centre - stem_half, centre + stem_half + 1):
            grid[top + r][x] = ("@" if x == centre else "%", "t")
    cursor_y = top + bar_rows + stem_rows - 1
    for x in range(centre + stem_half + 2, centre + stem_half + 2 + (4 if h >= 7 else 3)):
        grid[cursor_y][x] = ("=", "cursor")


def render(grid):
    lines = []
    rows = len(grid)
    for y, row in enumerate(grid):
        t = y / max(1, rows - 1)
        text = ""
        for cell in row:
            if cell is None:
                text += f"{ESC}[0m "
            else:
                char, kind = cell
                colour = {"edge": EDGE, "dot": DOT, "cursor": CURSOR}.get(kind) or mix(TOP, BOTTOM, t)
                text += paint(char, colour)
        lines.append(text + f"{ESC}[0m")
    return lines


def visible(line):
    out, i = 0, 0
    while i < len(line):
        if line[i] == "\x1b":
            while i < len(line) and line[i] != "m":
                i += 1
        else:
            out += 1
        i += 1
    return out


def centred(text, width, colour, bold=False):
    pad = max(0, (width - len(text)) // 2)
    return f"{ESC}[0m" + " " * pad + (f"{ESC}[1m" if bold else "") + (paint(text, colour) if text else "") + f"{ESC}[0m"


def build(h, flat, above, subtitle, title="TERMINAL"):
    grid = hexagon(h, flat)
    put_t(grid, h)
    lines = render(grid)
    width = visible(lines[0])
    out = list(lines)
    out.append("")
    if above:
        out.append(centred(above, width, (225, 180, 130)))
    out.append(centred("  ".join(title), width, TEXT_TOP, bold=True))
    if subtitle:
        out.append(centred(subtitle, width, (225, 180, 130)))
    return [line + " " * max(0, width - visible(line)) for line in out]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--above", default="")
    parser.add_argument("--subtitle", default="ELEVATED")
    arguments = parser.parse_args()
    folder = Path(__file__).resolve().parent.parent / "art"
    for name, h, flat in (("elevated.ans", 8, 21), ("elevated-small.ans", 5, 15)):
        lines = build(h, flat, arguments.above, arguments.subtitle)
        (folder / name).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{name}: {visible(lines[0])} columns x {len(lines)} rows")
