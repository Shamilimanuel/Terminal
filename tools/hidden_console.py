"""Runs PowerShell inside a hidden Windows pseudo-console (ConPTY), types keys into it and prints what the screen shows
after each key. Use it to check how something really behaves in a real console (the live command list, the path picker,
the prompt) without a window ever appearing on screen. The typed keys are never sent with Enter unless you ask for it
(the key name ENTER is not defined on purpose), and nothing is saved to your real history.

    python tools\\hidden_console.py <project folder> "<history lines separated by |>" "<keys separated by |>" [modpath|wrapped]

Keys: any text, or BACK TAB DOWN UP ESC F2 RIGHT, or WAIT (send nothing, just look again a moment later),
or CLICK <column> <row> / MOVE <column> <row> (the mouse; 1-based, as on the screen), or CLICKTEXT <words> / MOVETEXT <words> (the mouse, where those words are), or RESIZE <columns> <rows> (the window changes size).   modpath = start PowerShell with the Terminal modules folder first;
wrapped = start it with the exact command the installer gives Windows Terminal (checks the cmd helper too);
real = your real profile and welcome screen (sounds muted). Environment: HC_COLS, HC_ROWS (window size), HC_LINES (screen lines to show),
HC_INIT_EXTRA (PowerShell lines run after the profile, e.g. to pick a look), HC_PNG (a folder: saves a coloured picture of each screen).
Example: python tools\\hidden_console.py . "git status|git log|foo" "g|i|DOWN|ESC" wrapped
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / "tools"))
import screen_png

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class COORD(ctypes.Structure):
    _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR), ("lpTitle", wt.LPWSTR),
                ("dwX", wt.DWORD), ("dwY", wt.DWORD), ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
                ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD),
                ("dwFlags", wt.DWORD), ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
                ("lpReserved2", ctypes.c_void_p), ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE), ("hStdError", wt.HANDLE)]


class STARTUPINFOEXW(ctypes.Structure):
    _fields_ = [("StartupInfo", STARTUPINFOW), ("lpAttributeList", ctypes.c_void_p)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE), ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]


k32.CreatePipe.argtypes = [ctypes.POINTER(wt.HANDLE), ctypes.POINTER(wt.HANDLE), ctypes.c_void_p, wt.DWORD]
k32.CreatePseudoConsole.argtypes = [COORD, wt.HANDLE, wt.HANDLE, wt.DWORD, ctypes.POINTER(ctypes.c_void_p)]
k32.ClosePseudoConsole.argtypes = [ctypes.c_void_p]
k32.InitializeProcThreadAttributeList.argtypes = [ctypes.c_void_p, wt.DWORD, wt.DWORD, ctypes.POINTER(ctypes.c_size_t)]
k32.UpdateProcThreadAttribute.argtypes = [ctypes.c_void_p, wt.DWORD, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p]
k32.CreateProcessW.argtypes = [wt.LPCWSTR, wt.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wt.BOOL, wt.DWORD, ctypes.c_void_p, wt.LPCWSTR,
                               ctypes.POINTER(STARTUPINFOEXW), ctypes.POINTER(PROCESS_INFORMATION)]
k32.ReadFile.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.WriteFile.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
k32.ResizePseudoConsole.argtypes = [ctypes.c_void_p, COORD]

COLS, ROWS = int(os.environ.get("HC_COLS", "120")), int(os.environ.get("HC_ROWS", "45"))


class Pty:
    def __init__(self, command_line):
        in_read, in_write, out_read, out_write = wt.HANDLE(), wt.HANDLE(), wt.HANDLE(), wt.HANDLE()
        assert k32.CreatePipe(ctypes.byref(in_read), ctypes.byref(in_write), None, 0)
        assert k32.CreatePipe(ctypes.byref(out_read), ctypes.byref(out_write), None, 0)
        self.hpc = ctypes.c_void_p()
        hr = k32.CreatePseudoConsole(COORD(COLS, ROWS), in_read, out_write, 0, ctypes.byref(self.hpc))
        assert hr == 0, f"CreatePseudoConsole failed {hr}"
        size = ctypes.c_size_t()
        k32.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(size))
        self.attr = (ctypes.c_byte * size.value)()
        assert k32.InitializeProcThreadAttributeList(self.attr, 1, 0, ctypes.byref(size))
        assert k32.UpdateProcThreadAttribute(self.attr, 0, 0x00020016, self.hpc, ctypes.sizeof(ctypes.c_void_p), None, None)
        si = STARTUPINFOEXW()
        si.StartupInfo.cb = ctypes.sizeof(STARTUPINFOEXW)
        si.StartupInfo.dwFlags = 0x100                       # STARTF_USESTDHANDLES with empty handles: do not inherit my pipes, use the pseudo-console
        si.lpAttributeList = ctypes.cast(self.attr, ctypes.c_void_p)
        pi = PROCESS_INFORMATION()
        buffer = ctypes.create_unicode_buffer(command_line)
        ok = k32.CreateProcessW(None, buffer, None, None, False, 0x00080000, None, None, ctypes.byref(si), ctypes.byref(pi))
        assert ok, f"CreateProcess failed {ctypes.get_last_error()}"
        self.process = pi.hProcess
        self.in_write, self.out_read = in_write, out_read
        self.raw = bytearray()
        self.lock = threading.Lock()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        chunk = ctypes.create_string_buffer(65536)
        got = wt.DWORD()
        while k32.ReadFile(self.out_read, chunk, 65536, ctypes.byref(got), None) and got.value:
            with self.lock:
                self.raw += chunk.raw[:got.value]

    def send(self, text):
        data = text.encode("utf-8")
        written = wt.DWORD()
        k32.WriteFile(self.in_write, data, len(data), ctypes.byref(written), None)

    def text(self):
        with self.lock:
            return bytes(self.raw).decode("utf-8", "replace")

    def close(self):
        k32.TerminateProcess(self.process, 0)
        k32.ClosePseudoConsole(self.hpc)


def show(pty, label):
    screen = screen_png.VT(columns=COLS, rows=ROWS)
    screen.write(pty.text())
    lines = screen.lines()
    print(f"----- {label} ----- at {time.strftime('%H:%M:%S')}")
    print(chr(10).join(lines[-int(os.environ.get("HC_LINES", "14")):]))
    folder = os.environ.get("HC_PNG")                      # HC_PNG=folder saves a picture of every screen shown
    if folder:
        Path(folder).mkdir(parents=True, exist_ok=True)
        safe = "".join(c if c.isalnum() else "_" for c in label)
        path = screen_png.render(screen, Path(folder) / f"{safe}.png")
        print("picture:", path)


def main():
    work = Path(tempfile.mkdtemp(prefix="ptytry_"))
    init = work / "init.ps1"
    commands = [c for c in sys.argv[2].split("|")] if len(sys.argv) > 2 else ["git status", "git log", "gitk", "find-thing", "foo bar", "pull-all", "path"]
    history = work / "history.txt"
    history.write_text(chr(10).join(commands) + chr(10), encoding="utf-8")
    init.write_bytes(bytes([0xEF, 0xBB, 0xBF]) + (f""". '{ROOT / 'profile' / 'custom-profile.ps1'}' -NoBanner
Set-PSReadLineOption -HistorySavePath '{history}'
Write-Host ('SUGGESTIONS=' + $global:TermSuggestions + ' PSReadLine=' + (Get-Module PSReadLine).Version)
{os.environ.get('HC_INIT_EXTRA', '')}
""").encode("utf-8"))
    os.environ.setdefault("TERMINAL_DATA_DIR", str(work / "data"))      # HC_DATA-style: keep one you set yourself, so the log can be read
    steps = [s for s in sys.argv[3].split("|")] if len(sys.argv) > 3 else ["g", "i", "t", " ", "BACK", "BACK", "BACK", "f", "TAB"]
    if len(sys.argv) > 4 and sys.argv[4] == "modpath":       # PowerShell is told about our folder before it starts
        os.environ["PSModulePath"] = os.environ["LOCALAPPDATA"] + chr(92) + "Terminal" + chr(92) + "modules;" + os.environ.get("PSModulePath", "")
    mode = sys.argv[4] if len(sys.argv) > 4 else ""
    if mode in ("wrapped", "real"):                          # the exact start command Windows Terminal would use, as the installer builds it
        sys.path.insert(0, str(ROOT / "tools"))
        import install
        plain = '%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File ' + str(init)
        if mode == "real":                                   # your real profile and welcome screen, with every sound and pop-up muted
            plain = '%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoLogo -NoExit'
            os.environ["TERMINAL_QUIET"] = "1"
        command = os.path.expandvars(install.with_modules(plain))
        print("start command:", command)
        pty = Pty(command)
    else:
        pty = Pty(f'powershell.exe -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "{init}"')
    try:
        if mode == "real":                                   # how long until the welcome screen is on screen
            began = time.time()
            while time.time() - began < 20 and "BUSIEST" not in pty.text() and "PC STATUS" not in pty.text():
                time.sleep(0.1)
            print(f"first picture after {time.time() - began:.1f} s")
            time.sleep(4)
        else:
            time.sleep(5)
        show(pty, "start")
        keys = {"BACK": "\x7f", "TAB": "\t", "DOWN": "\x1b[B", "UP": "\x1b[A", "ESC": "\x1b", "F2": "\x1bOQ", "RIGHT": "\x1b[C",
                "ENTER": "\r", "WAIT": ""}                   # ENTER runs what is typed: only use it for harmless commands
        for number, step in enumerate(steps, 1):
            if step.startswith("RESIZE "):                              # RESIZE <columns> <rows>: the window changes size, as when Windows Terminal maximises
                global COLS, ROWS
                COLS, ROWS = int(step.split()[1]), int(step.split()[2])
                k32.ResizePseudoConsole(pty.hpc, COORD(COLS, ROWS))
                pty.raw = bytearray()                                  # the screen is redrawn from here, so start the picture afresh
                time.sleep(2.5)
                step = "WAIT"
            if step.startswith(("CLICKTEXT ", "MOVETEXT ")):          # CLICKTEXT <words>: click where those words are on the screen now
                kind, words = step.split(" ", 1)
                now = screen_png.VT(columns=COLS, rows=ROWS)
                now.write(pty.text())
                found = [(r, "".join(cell[0] for cell in now.cells[r]).index(words)) for r in range(ROWS) if words in "".join(cell[0] for cell in now.cells[r])]
                assert found, f"{words!r} is not on the screen"
                row, column = found[0][0] + 1, found[0][1] + 2
                step = ("CLICK " if kind == "CLICKTEXT" else "MOVE ") + f"{column} {row}"
                print("(" + step + ")")
            if step.startswith(("CLICK ", "MOVE ")):                  # CLICK column row / MOVE column row (1-based, as on the screen)
                kind, column, row = step.split()
                if kind == "MOVE":
                    pty.send(f"[<35;{column};{row}M")
                else:
                    pty.send(f"[<0;{column};{row}M")
                    time.sleep(0.15)
                    pty.send(f"[<0;{column};{row}m")
            else:
                pty.send(keys.get(step, step))
            time.sleep(1.2)
            show(pty, f"{number} after {step!r}")
    finally:
        if os.environ.get("HC_SAVE"):                         # HC_SAVE=<file> keeps everything the console sent, for studying a problem
            Path(os.environ["HC_SAVE"]).write_text(pty.text(), encoding="utf-8")
        pty.close()


main()
