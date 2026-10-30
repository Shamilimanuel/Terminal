"""A tiny pretend terminal screen, for the tests: it follows the cursor moves the live banner uses, so a test can check
that an update rewrote only the lines it meant to and put the cursor back.

It understands: printable text, new line, ESC[row;colH (move), ESC[nA (up), ESC[K (erase to end of line), ESC[J (erase below),
ESC 7 / ESC 8 (save and restore the cursor) and colour codes (ESC[...m, ignored). It does not scroll.
"""
import re

CSI = re.compile(r"\x1b\[([0-9;]*)([A-Za-z])")


class Screen:
    def __init__(self, rows=200, columns=240):
        self.grid = [[" "] * columns for _ in range(rows)]
        self.rows, self.columns = rows, columns
        self.row = self.column = 0
        self.saved = (0, 0)

    def write(self, text):
        i = 0
        while i < len(text):
            char = text[i]
            if char == "\x1b":
                match = CSI.match(text, i)
                if match:
                    self.control(match.group(1), match.group(2))
                    i = match.end()
                    continue
                if text[i + 1:i + 2] == "P":                      # a picture (Sixel): everything up to ESC \ is data, not text
                    end = text.find("\x1b\\", i + 2)
                    i = len(text) if end < 0 else end + 2
                    continue
                if text[i + 1:i + 2] == "7":
                    self.saved = (self.row, self.column)
                elif text[i + 1:i + 2] == "8":
                    self.row, self.column = self.saved
                i += 2
                continue
            if char == "\n":
                self.row += 1
                self.column = 0
            elif char == "\r":
                self.column = 0
            else:
                if self.column < self.columns and self.row < self.rows:
                    self.grid[self.row][self.column] = char
                self.column += 1
            i += 1

    def control(self, params, final):
        numbers = [int(p) if p else 0 for p in params.split(";")] if params else []
        if final == "H":
            self.row = (numbers[0] if numbers and numbers[0] else 1) - 1
            self.column = (numbers[1] if len(numbers) > 1 and numbers[1] else 1) - 1
        elif final == "A":
            self.row = max(0, self.row - (numbers[0] if numbers and numbers[0] else 1))
        elif final == "K":
            for c in range(self.column, self.columns):
                self.grid[self.row][c] = " "
        elif final == "J":
            for c in range(self.column, self.columns):
                self.grid[self.row][c] = " "
            for r in range(self.row + 1, self.rows):
                self.grid[r] = [" "] * self.columns

    def line(self, row):
        return "".join(self.grid[row]).rstrip()

    def lines(self, count=None):
        last = max((r for r in range(self.rows) if self.line(r)), default=-1)
        return [self.line(r) for r in range(last + 1 if count is None else count)]
