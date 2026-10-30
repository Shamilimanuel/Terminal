"""A pretend terminal screen that keeps colours, and a picture of it.

Used by tools\\hidden_console.py (HC_PNG=folder) to show what the real terminal window looks like, with the colours and your font
(Cascadia Mono), without a window ever appearing on screen.

It understands: text, line feed (down, same column, as a real terminal), carriage return, ESC[row;colH, ESC[nA/B/C/D, ESC[nG, ESC[nX, ESC[K, ESC[J, ESC 7 / ESC 8, ESC[...m colours
(24-bit and the 8 basic ones, bold, reset), and ignores window titles and private modes. It does not scroll.
"""
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CSI = re.compile(r"\x1b\[([?>=!]?)([0-9;]*)([A-Za-z])")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)")
BASIC = {30: (12, 12, 12), 31: (197, 15, 31), 32: (19, 161, 14), 33: (193, 156, 0), 34: (0, 55, 218), 35: (136, 23, 152), 36: (58, 150, 221), 37: (204, 204, 204),
         90: (118, 118, 118), 91: (231, 72, 86), 92: (22, 198, 12), 93: (249, 241, 165), 94: (59, 120, 255), 95: (180, 0, 158), 96: (97, 214, 214), 97: (242, 242, 242)}


class VT:
    def __init__(self, columns=120, rows=45, background=(10, 18, 24), foreground=(223, 243, 255)):
        self.columns, self.rows = columns, rows
        self.default_fg, self.default_bg = foreground, background
        self.cells = [[(" ", None, None, False) for _ in range(columns)] for _ in range(rows)]
        self.row = self.column = 0
        self.saved = (0, 0)
        self.fg = self.bg = None
        self.bold = False

    def clear_from(self, row, column):
        for c in range(column, self.columns):
            self.cells[row][c] = (" ", None, None, False)

    def write(self, text):
        text = OSC.sub("", text)
        i = 0
        while i < len(text):
            char = text[i]
            if char == "\x1b":
                match = CSI.match(text, i)
                if match:
                    self.control(match.group(1), match.group(2), match.group(3))
                    i = match.end()
                    continue
                nxt = text[i + 1:i + 2]
                if nxt == "7":
                    self.saved = (self.row, self.column)
                elif nxt == "8":
                    self.row, self.column = self.saved
                i += 2
                continue
            if char == "\n":
                self.row = min(self.rows - 1, self.row + 1)      # a line feed moves down and keeps the column, as a real terminal does
            elif char == "\r":
                self.column = 0
            elif char >= " ":
                if 0 <= self.row < self.rows and 0 <= self.column < self.columns:
                    self.cells[self.row][self.column] = (char, self.fg, self.bg, self.bold)
                self.column += 1
            i += 1

    def control(self, private, params, final):
        if private:
            return
        numbers = [int(p) if p else 0 for p in params.split(";")] if params else []
        n = numbers[0] if numbers and numbers[0] else 1
        if final == "H":
            self.row = min(self.rows - 1, (numbers[0] if numbers and numbers[0] else 1) - 1)
            self.column = min(self.columns - 1, (numbers[1] if len(numbers) > 1 and numbers[1] else 1) - 1)
        elif final == "A":
            self.row = max(0, self.row - n)
        elif final == "B":
            self.row = min(self.rows - 1, self.row + n)
        elif final == "C":
            self.column = min(self.columns - 1, self.column + n)
        elif final == "D":
            self.column = max(0, self.column - n)
        elif final == "G":
            self.column = min(self.columns - 1, n - 1)
        elif final == "d":
            self.row = min(self.rows - 1, n - 1)
        elif final == "X":
            for c in range(self.column, min(self.columns, self.column + n)):
                self.cells[self.row][c] = (" ", None, None, False)
        elif final == "K":
            self.clear_from(self.row, self.column)
        elif final == "J":
            mode = numbers[0] if numbers else 0
            if mode == 2:
                for r in range(self.rows):
                    self.clear_from(r, 0)
            else:
                self.clear_from(self.row, self.column)
                for r in range(self.row + 1, self.rows):
                    self.clear_from(r, 0)
        elif final == "m":
            self.sgr(numbers or [0])

    def sgr(self, parts):
        i = 0
        while i < len(parts):
            p = parts[i]
            if p == 0:
                self.fg = self.bg = None
                self.bold = False
            elif p == 1:
                self.bold = True
            elif p in (38, 48) and parts[i + 1:i + 2] == [2] and len(parts) >= i + 5:
                color = tuple(parts[i + 2:i + 5])
                if p == 38:
                    self.fg = color
                else:
                    self.bg = color
                i += 4
            elif p in BASIC:
                self.fg = BASIC[p]
            elif p - 10 in BASIC and p >= 40:
                self.bg = BASIC[p - 10]
            elif p == 39:
                self.fg = None
            elif p == 49:
                self.bg = None
            i += 1

    def lines(self):
        last = max((r for r in range(self.rows) if any(c[0] != " " for c in self.cells[r])), default=-1)
        return ["".join(c[0] for c in self.cells[r]).rstrip() for r in range(last + 1)]


def _fonts(size):
    fonts = Path("C:/Windows/Fonts")
    main = ImageFont.truetype(str(fonts / "CascadiaMono.ttf"), size)
    bold = ImageFont.truetype(str(fonts / "CascadiaMono.ttf"), size)
    try:
        bold.set_variation_by_name("Bold")
    except Exception:
        pass
    fallback = ImageFont.truetype(str(fonts / "seguisym.ttf"), size)
    return main, bold, fallback


def render(vt, path, size=15):
    """Draws the screen as a PNG, the way Windows Terminal would (one cell per character, Cascadia Mono)."""
    main, bold, fallback = _fonts(size)
    cell_w = round(main.getlength("M"))
    cell_h = round(size * 1.3)
    image = Image.new("RGB", (cell_w * vt.columns + 20, cell_h * vt.rows + 20), vt.default_bg)
    draw = ImageDraw.Draw(image)
    for r, row in enumerate(vt.cells):
        for c, (char, fg, bg, is_bold) in enumerate(row):
            x, y = 10 + c * cell_w, 10 + r * cell_h
            if bg:
                draw.rectangle([x, y, x + cell_w - 1, y + cell_h - 1], fill=bg)
            if char == " ":
                continue
            font = bold if is_bold else main
            if main.getmask(char).getbbox() is None:
                font = fallback
            draw.text((x, y), char, font=font, fill=fg or vt.default_fg)
    image.save(path)
    return path
