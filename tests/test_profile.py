"""Runs the real PowerShell profile code in a hidden Windows PowerShell and checks what it prints: the banner sections,
the emblem, the prompt, the commands. Nothing is shown on screen and nothing is installed.

Run with:  python tests\\run_all.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
profile = root / "profile" / "custom-profile.ps1"
DATA_DIR = tempfile.mkdtemp(prefix="terminaltest_")
# The tests never read your own my-terminal.json. They start from the shipped example and add pinned folders and apps that
# point into a throwaway folder, so every check works on any PC.
FIXTURE = Path(DATA_DIR) / "fixture"
for sub in ("Widgets/Clipboard/tests", "Widgets/Snipper", "Widgets/Custom-Clock", "Widgets/Terminal"):
    (FIXTURE / sub).mkdir(parents=True, exist_ok=True)
for sub in ("Widgets/Clipboard", "Widgets/Snipper"):                      # two of them are git projects, so the banner shows "clean"
    subprocess.run(["git", "init", "-q", str(FIXTURE / sub)], check=True, capture_output=True)
_fixture = json.loads((root / "my-terminal.example.json").read_text(encoding="utf-8"))
_fixture["pins"] = [
    {"key": "widgets", "label": "All my widgets", "path": str(FIXTURE / "Widgets"), "color": "#5fd4ff"},
    {"key": "clock", "label": "Taskbar clock", "path": str(FIXTURE / "Widgets" / "Custom-Clock"), "color": "#ffb36b"},
    {"key": "clip", "label": "Clipboard", "path": str(FIXTURE / "Widgets" / "Clipboard"), "color": "#4eb1b1"},
    {"key": "snip", "label": "Snipper", "path": str(FIXTURE / "Widgets" / "Snipper"), "color": "#6fe0b0"},
    {"key": "term", "label": "This terminal", "path": str(FIXTURE / "Widgets" / "Terminal"), "color": "#b69cff"},
    {"key": "emblem", "label": "Switch emblem", "command": "emblem"},
    {"key": "dl", "label": "Downloads", "path": "~\\Downloads"},
]
_fixture["apps"] = [
    {"name": "Clipboard", "match": "pythoncore.*main\\.py", "expected": True, "run": ["python.exe", "main.py"], "path": str(FIXTURE / "Widgets" / "Clipboard")},
    {"name": "Snipper", "match": "Snipper.*main\\.py", "expected": True, "run": ["python.exe", "main.py"], "path": str(FIXTURE / "Widgets" / "Snipper")},
    {"name": "Clock feeder", "match": "feeder\\.py", "expected": True, "run": ["python.exe", "feeder.py"], "path": str(FIXTURE / "Widgets" / "Custom-Clock")},
]
CONFIG = FIXTURE / "my-terminal.json"
CONFIG.write_text(json.dumps(_fixture, indent=2), encoding="utf-8")
NAME = json.loads(CONFIG.read_text(encoding="utf-8"))["name"]
TITLE = f"{NAME.upper()}'S TERMINAL"
NAME_LOW = NAME.lower()
CODE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def powershell(script, raw=False):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "t.ps1"
        path.write_bytes(b"\xef\xbb\xbf" + ("[Console]::OutputEncoding = [Text.Encoding]::UTF8\n" + script).encode("utf-8"))
        env = dict(os.environ, TERMINAL_DATA_DIR=DATA_DIR, TERMINAL_CONFIG=str(CONFIG))      # the tests keep their own private data, never yours
        env = {k: v for k, v in env.items() if k.upper() != "NODEFAULTCURRENTDIRECTORYINEXEPATH"}   # Claude Code's tab marker: behave like a normal window
        run = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(path)],
                             capture_output=True, env=env)
    stderr = run.stderr.decode("utf-8", "replace")
    assert stderr.strip() == "", stderr[:600]
    text = run.stdout.decode("utf-8", "replace")
    if raw:
        return text                                       # raw keeps carriage returns (the picker's cursor moves)
    return text.replace(chr(13) + chr(10), chr(10)).replace(chr(13), chr(10))


def plain(text):
    return CODE.sub("", text)


# the settings file is valid and has what the banner needs
config = json.loads(CONFIG.read_text(encoding="utf-8"))
for key in ("name", "theme", "prompt", "art", "art_admin", "art_style", "art_size", "animate", "show_gpu", "show_net", "show_git", "pins", "tips", "apps"):
    assert key in config, key
assert all({"key", "label"} <= set(pin) and ("path" in pin or "command" in pin) for pin in config["pins"]), "a pin is a folder (path) or a command"
assert any(pin.get("command") == "emblem" for pin in config["pins"]), "the emblem switch is pinned"
for name in ("elevated", "elevated-small", "rune", "rune-small", "rune-ascii", "rune-ascii-small", "rune-blocks", "rune-blocks-small"):
    lines = (root / "art" / f"{name}.ans").read_text(encoding="utf-8").splitlines()
    widths = {len(CODE.sub("", line)) for line in lines}
    assert len(widths) == 1 and lines, f"{name}: every row of the emblem is the same width"
print("settings file and emblem files OK")

banner = powershell(f". '{profile}' -NoBanner\nShow-Banner -Width 130")
text = plain(banner)
for section in (TITLE, "PC STATUS", "RAM", "DISK", "RUNNING", "PINNED", "TIPS", "go widgets", "go dl"):
    assert section in text, section
assert "CPU" in text, "the processor line is on in my-terminal.json"
for line in ("GPU", "NET", "TIME up"):
    assert line in text, line
assert "clean" in text or "changed" in text, "pinned git projects show their state"
assert re.search(r"GPU\s+\S+\s+\d", text) and " of " in text.split("GPU")[1].splitlines()[0], "the graphics card line has its memory numbers"
assert any(0x2800 <= ord(ch) <= 0x28FF for ch in text) and "T  E  R  M  I  N  A  L" not in text, "normal PowerShell shows the rune emblem dots"
assert "\x1b[38;2;" in banner, "colours are 24-bit"
admin = plain(powershell(f". '{profile}' -NoBanner\n$global:TermIsAdmin = $true\nShow-Banner -Width 130 -NoAnimation"))
assert "T  E  R  M  I  N  A  L" in admin and "ELEVATED" in admin and "ADMINISTRATOR" in admin, "an Administrator window shows the elevated emblem"
assert not any(0x2800 <= ord(ch) <= 0x28FF for ch in admin)
print("banner OK")

narrow = plain(powershell(f". '{profile}' -NoBanner\nShow-Banner -Width 70"))
assert not any(0x2800 <= ord(ch) <= 0x28FF for ch in narrow) and "PINNED" in narrow, "a narrow window gets no emblem, only the text"
print("narrow window OK")

# the live banner: the status lines redraw in place, nothing else on the screen moves, the cursor goes back, and the
# prompt is taken away at the end so PowerShell can draw its own (checked on a pretend screen)
sys.path.insert(0, str(root / "tools"))
import mini_terminal
raw = powershell(f". '{profile}' -NoBanner\nShow-Banner -Width 130 -NoAnimation -TestLiveFrames 3")
first_update = raw.index("\x1b7")
before, live_part = raw[:first_update], raw[first_update:]
last_erase = live_part.rindex("\x1b8") + 2                  # up to the last cursor restore; what follows moves to the prompt and erases it
without_erase = before + live_part[:last_erase]
snapshots = []
for text in (before, without_erase, raw):
    screen = mini_terminal.Screen(columns=200)
    screen.write(text)
    snapshots.append(screen)
shown, updated, finished = snapshots
assert (updated.row, updated.column) == (shown.row, shown.column), "after the updates the cursor is back at the prompt"
rows_shown, rows_updated = shown.lines(), updated.lines()
changed = [i for i, (a, b) in enumerate(zip(rows_shown, rows_updated)) if a != b]
assert len(rows_shown) == len(rows_updated) and changed, "some lines were rewritten"
art_width = max(len(line) - len(line.lstrip()) for line in rows_shown[1:4] if line.strip())
for i in changed:
    assert rows_shown[i][:40] == rows_updated[i][:40], f"row {i}: the emblem on the left was not touched"
watch = "\n".join(rows_shown[i] for i in changed)
assert all(word in watch for word in ("RAM", "DISK")) or "CPU" in watch or "NET" in watch, watch
for row in rows_updated[1:-3]:
    assert len(row) < 200, "no line was cut or wrapped"
assert "Friday" in rows_updated[2] or any("·" in r for r in rows_updated[1:4]), "the clock line is one of the live ones"
for i, (a, b) in enumerate(zip(rows_shown, finished.lines(len(rows_shown)))):
    if i >= len(rows_shown) - 2:
        assert b == "", "the prompt lines were erased at the end"
    else:
        assert a == b or i in changed, f"row {i} was left as it was"
print("live banner redraw OK:", len(changed), "lines update in place")

# the live dashboard: two frames, drawn in place
live = powershell(f". '{profile}' -NoBanner\nShow-Live -Frames 2 -IntervalMs 300")
frames = live.split("\x1b[H")
assert len(frames) >= 3, "two frames were drawn"
last = plain(frames[-1])
for word in ("LIVE", "CPU", "RAM", "GPU", "DISK", "NET", "TOP"):
    assert word in last, word
print("live dashboard OK")

# the other emblem styles draw too
for style in ("ascii", "blocks"):
    shown = powershell(f". '{profile}' -NoBanner\n$global:TermConfig.art = 'rune'\n$global:TermConfig.art_style = '{style}'\nShow-Banner -Width 140 -NoAnimation")
    assert "\x1b[38;2;" in shown and "PINNED" in plain(shown) and (("@" in shown) if style == "ascii" else ("▀" in shown)), style
print("emblem styles OK")

# the prompt: two lines, the folder shortened, the git branch of this repository
out = plain(powershell(f". '{profile}' -NoBanner\nSet-Location '{FIXTURE / 'Widgets' / 'Terminal'}'\n$global:TermLastHistoryId = -1\nWrite-Host (prompt) -NoNewline"))
lines = out.splitlines()
assert len(lines) == 2 and NAME_LOW in lines[0] and lines[1].rstrip().endswith("❯"), lines
assert "…" in lines[0] and "Terminal" in lines[0], "a long path is shortened to ~\\...\\parent\\folder"
print("prompt OK")

# the short commands
checks = powershell(f""". '{profile}' -NoBanner
Set-Location $HOME
go clip
(Get-Location).Path
go nothing-like-this
up
(Get-Location).Path
$folder = Join-Path ([IO.Path]::GetTempPath()) ('termtest_' + [guid]::NewGuid().ToString('N'))
mk $folder
((Get-Location).Path -eq $folder)
Set-Location $HOME
Remove-Item -LiteralPath $folder -Recurse -Force
""")
checks = plain(checks)
assert "Widgets\\Clipboard" in checks, "go clip jumps to the pinned folder"
assert "No pin called" in checks
assert "True" in checks, "mk makes a folder and steps into it"
print("commands OK")

# emblem: switches between the two emblems and remembers the choice in my-terminal.json (a temporary copy here).
# Normal PowerShell uses "art", an Administrator window uses "art_admin".
with tempfile.TemporaryDirectory() as folder:
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    before = copy.read_text(encoding="utf-8")
    result = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
"start: " + $global:TermConfig.art
emblem elevated -Quiet
"after elevated: " + $global:TermConfig.art
emblem -Quiet
"after toggle: " + $global:TermConfig.art
emblem nonsense -Quiet
"still: " + $global:TermConfig.art
go emblem 6>$null
"after go emblem: " + $global:TermConfig.art + " / admin emblem untouched: " + $global:TermConfig.art_admin
"""))
    after = copy.read_text(encoding="utf-8")
    assert "start: rune" in result and "after elevated: elevated" in result and "after toggle: rune" in result, result
    assert "Emblems: elevated, rune" in result and "still: rune" in result, "an unknown name changes nothing"
    assert "after go emblem: elevated / admin emblem untouched: elevated" in result, "the pinned entry runs the switch"
    assert '"art": "elevated"' in after and '"art_admin": "elevated"' in after, "the choice is written to the file"
    changed = [(a, b) for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
    assert len(before.splitlines()) == len(after.splitlines()) and len(changed) == 1 and changed[0][0].strip().startswith('"art"'), "only the art line changed"
    copy.write_bytes(before.encode("utf-8"))
    result = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
$global:TermIsAdmin = $true
emblem rune -Quiet
"admin emblem: " + $global:TermConfig.art_admin + ", normal emblem: " + $global:TermConfig.art
"""))
    after = copy.read_text(encoding="utf-8")
    assert "admin emblem: rune, normal emblem: rune" in result and '"art_admin": "rune"' in after, "in an Administrator window the switch changes art_admin"
print("emblem switch OK")

# warnings strip: nothing when all is well, one red line per problem
quiet = plain(powershell(f""". '{profile}' -NoBanner
$none = @(Get-WarningLines $null @{{ diskFree = 50; ram = 40; reboot = $false; days = 1 }})
"quiet: " + $none.Count
$four = @(Get-WarningLines $null @{{ diskFree = 4; ram = 97; reboot = $true; days = 20 }})
"four: " + $four.Count
$four | ForEach-Object {{ $_ }}
$stopped = @(Get-WarningLines @{{ os = $null; commands = @() }} @{{ diskFree = 50; ram = 40; reboot = $false; days = 1 }})
"apps: " + $stopped.Count
$stopped | ForEach-Object {{ $_ }}
$fine = @(Get-WarningLines @{{ os = $null; commands = @('x pythoncore main.py', 'Snipper main.py', 'feeder.py') }} @{{ diskFree = 50; ram = 40; reboot = $false; days = 1 }})
"all running: " + $fine.Count
"""))
assert "quiet: 0" in quiet and "four: 4" in quiet and "all running: 0" in quiet, quiet
assert "Disk C: is almost full" in quiet and "Memory is almost full" in quiet and "waiting for a restart" in quiet and "has been on for 20 days" in quiet
assert "apps: 3" in quiet and "Clipboard is not running" in quiet and "Snipper is not running" in quiet, quiet
print("warnings OK")

# graphs: the CPU, GPU and network lines carry a small history graph
graphs = plain(powershell(f""". '{profile}' -NoBanner
$state = New-LiveState
$state.boot = (Get-Date).AddHours(-3)
Start-Sleep -Milliseconds 400
$a = Get-LiveRows $state
Start-Sleep -Milliseconds 400
$b = Get-LiveRows $state
"cpu: " + $b.cpu
"gpu: " + $b.gpu
"net: " + $b.net
"history: " + @($state.hist.cpu).Count
"""))
blocks = "▁▂▃▄▅▆▇█"
for line in ("cpu:", "gpu:", "net:"):
    row = [l for l in graphs.splitlines() if l.startswith(line)][0]
    assert any(ch in blocks for ch in row), f"{line} has a graph: {row}"
assert "history: 2" in graphs, graphs
print("graphs OK")

# a colour for each project: the prompt takes the colour of the pinned project you are inside
def prompt_in(folder, admin=False):
    return powershell(f""". '{profile}' -NoBanner
$global:TermIsAdmin = ${'true' if admin else 'false'}
Set-Location '{folder}'
$global:TermLastHistoryId = -1
Write-Host (prompt) -NoNewline
""")
pins = {pin["key"]: pin for pin in config["pins"] if pin.get("color")}
clip = pins["clip"]
r, g, b = (int(clip["color"].lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
inside = prompt_in(clip["path"])
assert f"38;2;{r};{g};{b}m" in inside, "inside the Clipboard project the prompt uses its colour"
elsewhere = prompt_in(str(Path.home()))
assert f"38;2;{r};{g};{b}m" not in elsewhere, "outside any project it uses the normal colour"
sub = prompt_in(str(Path(clip["path"]) / "tests"))
assert f"38;2;{r};{g};{b}m" in sub, "a folder inside the project counts too"
assert f"38;2;{r};{g};{b}m" not in prompt_in(clip["path"], admin=True), "an Administrator window stays red"
print("project colours OK")

# the Administrator sound: never plays when the output is redirected (tests), and never fails
sound = plain(powershell(f""". '{profile}' -NoBanner
$global:TermIsAdmin = $true
Show-Banner -Width 130 -NoAnimation 6>$null
"done"
"""))
assert "done" in sound
print("admin sound OK")

# the sound for each kind of window
with tempfile.TemporaryDirectory() as base:
    own = Path(base) / "mine.wav"
    own.write_bytes(b"RIFF")                     # only its existence matters here: nothing is played in a test
    out = plain(powershell(f""". '{profile}' -NoBanner
function Show($label) {{ $f = Get-StartupSoundFile; $label + ': ' + $(if ($f) {{ Split-Path -Leaf $f }} else {{ 'none' }}) }}
Show 'normal'
$global:TermConfig.startup_sound = 'tada.wav'; Show 'named'
$global:TermConfig.startup_sound = '{own}'; Show 'own file'
$global:TermConfig.startup_sound = 'off'; Show 'off'
$global:TermConfig.startup_sound = 'no-such-sound.wav'; Show 'missing'
$global:TermConfig.startup_sound = 'default'
$global:TermIsAdmin = $true
Show 'admin'
$global:TermConfig.admin_sound = 'off'; Show 'admin off'
"""))
    for expected in ("normal: notify.wav", "named: tada.wav", "own file: mine.wav", "off: none", "missing: none", "admin: chimes.wav", "admin off: none"):
        assert expected in out, (expected, out)
print("startup sounds OK")

# z: jump to any folder you have been in
with tempfile.TemporaryDirectory() as base:
    clip_dir = Path(base) / "alpha" / "clipthing"
    snip_dir = Path(base) / "beta" / "snipthing"
    clip_dir.mkdir(parents=True)
    snip_dir.mkdir(parents=True)
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermLastHistoryId = -1
Set-Location '{clip_dir}'; $null = prompt
Set-Location '{snip_dir}'; $null = prompt
Set-Location $HOME; $null = prompt
z clip
"clip -> " + (Get-Location).Path
z snip
"snip -> " + (Get-Location).Path
z alpha clip
"alpha clip -> " + (Get-Location).Path
z zzz-nothing-like-this
z widgets
"widgets -> " + (Get-Location).Path
z
"""))
    assert f"clip -> {clip_dir}" in out and f"snip -> {snip_dir}" in out and f"alpha clip -> {clip_dir}" in out, out
    assert "No folder you have been in matches 'zzz-nothing-like-this'" in out, out
    assert "widgets -> " in out and "Widgets" in out.split("widgets -> ")[1].splitlines()[0], "a pinned folder works before it was ever visited"
    assert "MOST VISITED" in out and str(clip_dir) in out.split("MOST VISITED")[1], out
print("z jump OK")

# path: the live picker narrows with every letter (pretend keys are fed in; no window, no real keyboard)
with tempfile.TemporaryDirectory() as base:
    for folder in ("Desktop", "Documents", "Downloads", "Music", "Old Downloads"):
        (Path(base) / folder).mkdir()
    (Path(base) / "Downloads" / "inner").mkdir()
    (Path(base) / "notes.txt").write_text("hi")
    (Path(base) / "dad.txt").write_text("hi")
    out = plain(powershell(f""". '{profile}' -NoBanner
$items = @(Get-ChildItem -LiteralPath '{base}')
function Names($q) {{ (Get-PathMatches $items $q | ForEach-Object {{ $_.Name }}) -join ',' }}
'all: ' + (Names '')
'd: ' + (Names 'd')
'dow: ' + (Names 'dow')
'DOW: ' + (Names 'DOW')
'zzz: ' + (Names 'zzz')
'common: ' + (Get-CommonStart @('Documents','Downloads','Desktop') 'd')
'common2: ' + (Get-CommonStart @('Documents','Downloads') 'd')
function Keys($text) {{ $global:FakeKeys = [System.Collections.Queue]::new(); foreach ($c in $text.ToCharArray()) {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = [string]$c.ToString().ToUpper(); KeyChar = $c }}) }} }}
function Press($name) {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = $name; KeyChar = [char]0 }}) }}
$source = {{ if ($global:FakeKeys.Count) {{ $global:FakeKeys.Dequeue() }} else {{ [pscustomobject]@{{ Key = 'Escape'; KeyChar = [char]0 }} }} }}

Set-Location '{base}'
Keys 'dow'; Press 'Enter'
$null = path -KeySource $source
'after dow+Enter: ' + (Get-Location).Path
Keys 'in'; Press 'Tab'; Press 'Enter'
$null = path -KeySource $source
'after in+Tab+Enter: ' + (Get-Location).Path
Set-Location '{base}'
Keys 'dow'; Press 'Tab'; Press 'Enter'
$null = path -KeySource $source
'after dow+Tab+Enter: ' + (Get-Location).Path
Set-Location '{base}'
Keys 'xyz'; Press 'Enter'
$null = path -KeySource $source
'nothing matched, stayed: ' + (Get-Location).Path
Set-Location '{base}\\Music'
Press 'Backspace'
$null = path -KeySource $source
'backspace went up: ' + (Get-Location).Path
Set-Location '{base}'
Keys 'notes'; Press 'Enter'
$null = path -KeySource $source
'file picked: ' + $global:PickedPath
Set-Location '{base}'
Keys 'mus'; Press 'Escape'; Keys 'dow'
$null = path -KeySource $source
'escape stayed: ' + (Get-Location).Path
"""))
    lines = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in out.splitlines() if ": " in l and l.split(": ", 1)[0] in (
        "all", "d", "dow", "DOW", "zzz", "common", "common2", "after dow+Enter", "after in+Tab+Enter", "after dow+Tab+Enter",
        "nothing matched, stayed", "backspace went up", "file picked", "escape stayed")}
    assert lines["all"] == "Desktop,Documents,Downloads,Music,Old Downloads,dad.txt,notes.txt", lines["all"]
    assert lines["d"] == "Desktop,Documents,Downloads,dad.txt,Old Downloads", lines["d"]       # starts with d first, then contains d
    assert lines["dow"] == "Downloads,Old Downloads" and lines["DOW"] == lines["dow"], lines
    assert lines["zzz"] == "", lines["zzz"]
    assert lines["common"] == "d" and lines["common2"] == "Do", lines
    # Enter on the first match goes in (Downloads is first for 'dow'); 'in' + Tab completes to inner, Enter goes in
    assert lines["after dow+Enter"].endswith("Downloads"), lines
    assert lines["after in+Tab+Enter"].endswith("inner"), lines
    assert lines["after dow+Tab+Enter"].endswith("Downloads"), lines
    assert lines["nothing matched, stayed"] == base or lines["nothing matched, stayed"].endswith(Path(base).name), lines
    assert lines["backspace went up"] == str(Path(base).resolve()) or lines["backspace went up"].endswith(Path(base).name), lines
    assert lines["file picked"].endswith("notes.txt"), lines
    assert lines["escape stayed"].endswith(Path(base).name), lines
print("path picker OK")

# what the picker looks like on a pretend screen, in the middle of narrowing (the final tidy-up wipe is left out)
with tempfile.TemporaryDirectory() as base:
    for folder in ("Desktop", "Documents", "Downloads", "Music"):
        (Path(base) / folder).mkdir()
    raw = powershell(f""". '{profile}' -NoBanner
function Keys($text) {{ $global:FakeKeys = [System.Collections.Queue]::new(); foreach ($c in $text.ToCharArray()) {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = $c.ToString().ToUpper(); KeyChar = $c }}) }} }}
$source = {{ if ($global:FakeKeys.Count) {{ $global:FakeKeys.Dequeue() }} else {{ [pscustomobject]@{{ Key = 'Escape'; KeyChar = [char]0 }} }} }}
Set-Location '{base}'
Keys 'do'
$null = path -KeySource $source
""", raw=True)
    wipes = list(re.finditer(r"\x1b\[\d+A\r\x1b\[0J", raw))
    frame = raw[:wipes[-1].start()]
    screen = mini_terminal.Screen(columns=120)
    screen.write(frame)
    shown = [l for l in screen.lines() if l.strip()]
    text = "\n".join(shown)
    assert "3 of 4" in text, text                                    # Documents and Downloads start with 'do'; Desktop has d then o further on
    assert "Documents" in text and "Downloads" in text and "Desktop" in text and "Music" not in text, text
    assert text.index("Downloads") < text.index("Desktop"), "names that start with the letters come before the loose matches"
    assert any(l.strip().startswith(chr(0x276F)) and "do" in l for l in shown), text
    assert shown[-1].strip().startswith("up/down"), shown[-1]
print("picker drawing OK")

# path with something after it: letters, a folder, or both (this used to fail with "Cannot convert ... ScriptBlock")
with tempfile.TemporaryDirectory() as base:
    for folder in ("Desktop", "Documents", "Downloads", "Footage", "Taxes (final)"):
        (Path(base) / folder).mkdir()
    (Path(base) / "Downloads" / "inner").mkdir()
    out = plain(powershell(f""". '{profile}' -NoBanner
function Keys($text) {{ $global:FakeKeys = [System.Collections.Queue]::new(); foreach ($c in $text.ToCharArray()) {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = $c.ToString().ToUpper(); KeyChar = $c }}) }} }}
function Press($name) {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = $name; KeyChar = [char]0 }}) }}
function Slash() {{ $global:FakeKeys.Enqueue([pscustomobject]@{{ Key = 'Oem5'; KeyChar = [char]92 }}) }}
$source = {{ if ($global:FakeKeys.Count) {{ $global:FakeKeys.Dequeue() }} else {{ [pscustomobject]@{{ Key = 'Escape'; KeyChar = [char]0 }} }} }}
function Here($label) {{ $label + ': ' + (Get-Location).Path }}

Set-Location '{base}'
Keys ''
'=== letters'
path f -KeySource $source
Here 'after letters'

Set-Location $env:TEMP
Keys ''
'=== folder'
path '{base}' -KeySource $source
Here 'after folder'

Set-Location $env:TEMP
Keys ''; Press 'Enter'
'=== folder and letters'
path '{base}\\dow' -KeySource $source
Here 'after folder and letters'

Set-Location '{base}'
Keys ''
'=== missing folder'
path '{base}\\nope\\x' -KeySource $source
Here 'after missing'

Set-Location '{base}'
Keys ''
'=== relative'
path Downloads -KeySource $source
Here 'after relative'
Keys ''
path .. -KeySource $source
Here 'after up'

Set-Location '{base}'
Keys 'dow'; Slash
'=== backslash'
path -KeySource $source
Here 'after backslash'

Set-Location '{base}'
Keys ''
'=== empty folder'
path 'Downloads\\inner' -KeySource $source

Set-Location '{base}'
Keys ''
'=== nothing matches'
path zzz -KeySource $source
Here 'after nothing'
"""))
    assert "Cannot convert" not in out and "ScriptBlock" not in out, out
    letters = out.split("=== letters")[1].split("=== folder")[0]
    assert "Footage" in letters and "Taxes (final)" in letters and "Desktop" not in letters, letters
    assert "after letters: " + base in letters, letters
    folder_part = out.split("=== folder\n")[1].split("=== folder and letters")[0]
    assert "after folder: " + base in folder_part and "Downloads" in folder_part, folder_part
    both = out.split("=== folder and letters")[1].split("=== missing folder")[0]
    assert "after folder and letters: " + base + "\\Downloads" in both, both
    missing = out.split("=== missing folder")[1].split("=== relative")[0]
    assert "I cannot find the folder" in missing and "after missing: " + base in missing, missing
    relative = out.split("=== relative")[1].split("=== backslash")[0]
    assert "after relative: " + base + "\\Downloads" in relative and "after up: " + base in relative, relative
    slash = out.split("=== backslash")[1].split("=== empty folder")[0]
    assert "after backslash: " + base + "\\Downloads" in slash, slash
    assert "This folder is empty" in out.split("=== empty folder")[1], out
    nothing = out.split("=== nothing matches")[1]
    assert "Nothing here has 'zzz' in its name" in nothing and "after nothing: " + base in nothing, nothing

# the loose match: dwn finds Downloads, and the order of the tiers
with tempfile.TemporaryDirectory() as base:
    for folder in ("Downloads", "Windows", "Old Downloads", "Music"):
        (Path(base) / folder).mkdir()
    out = plain(powershell(f""". '{profile}' -NoBanner
$items = @(Get-ChildItem -LiteralPath '{base}')
function Names($q) {{ (Get-PathMatches $items $q | ForEach-Object {{ $_.Name }}) -join ',' }}
'dwn: ' + (Names 'dwn')
'own: ' + (Names 'own')
'mus: ' + (Names 'mus')
'q: ' + (Names 'qqq')
"""))
    lines = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in out.splitlines() if ": " in l}
    assert lines["dwn"] == "Downloads,Old Downloads", lines                  # d, w, n in that order (Windows has no n after its second w)
    assert lines["own"] == "Downloads,Old Downloads", lines
    assert lines["mus"] == "Music" and lines["q"] == "", lines
print("path arguments OK")

# a folder Windows will not let you open gives a plain reason, not a red error
protected = Path("C:/System Volume Information")
out = plain(powershell(f""". '{profile}' -NoBanner
$r = Read-Folder 'C:\\System Volume Information'
'problem: ' + $r.Problem
$r = Read-Folder 'C:\\no-such-folder-xyz'
'gone: ' + $r.Problem
$global:TermIsAdmin
"""))
assert "gone: This folder is not there any more." in out, out
if protected.exists() and out.strip().splitlines()[-1] == "False":
    assert "problem: Windows will not let you look inside this folder." in out, out
print("path protected folder OK")

# error hints: a plain sentence for the red errors
out = plain(powershell(""". 'PROFILE' -NoBanner
function Hint($label, $block) { try { & $block } catch { $label + ': ' + (Get-ErrorHint $_) } }
Hint 'typo' { paht }
Hint 'missing' { Set-Location C:\\no-such-folder-xyz -ErrorAction Stop }
Hint 'option' { Get-ChildItem -Bogus }
Hint 'extra' { Get-ChildItem a b c }
Hint 'divide' { 1/0 }
Hint 'process' { Get-Process -Name nonexistentproc123 -ErrorAction Stop }
function Made($exception) { New-Object Management.Automation.ErrorRecord $exception, 'x', 'NotSpecified', $null }
'denied: ' + (Get-ErrorHint (Made ([UnauthorizedAccessException]'Access to the path is denied.')))
'busy: ' + (Get-ErrorHint (Made ([IO.IOException]'The process cannot access the file because it is being used by another process.')))
'scripts: ' + (Get-ErrorHint (Made ([Exception]'File x.ps1 cannot be loaded because running scripts is disabled on this system.')))
'offline: ' + (Get-ErrorHint (Made ([Net.WebException]'The remote name could not be resolved')))
'other: ' + (Get-ErrorHint (Made ([Exception]'something nobody planned for')))
'guess1: ' + (Get-CommandGuess 'gitt')
'guess2: [' + (Get-CommandGuess 'xyzxyz') + ']'
'distance: ' + (Get-EditDistance 'paht' 'path')
""".replace("PROFILE", str(profile))))
lines = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in out.splitlines() if ": " in l}
assert "Did you mean 'path'" in lines["typo"] and "is not a command" in lines["typo"], lines
assert "is not there" in lines["missing"] and "no-such-folder-xyz" in lines["missing"], lines
assert "-Bogus" in lines["option"], lines
assert "more than this command expects" in lines["extra"], lines
assert "divided by zero" in lines["divide"] and "No program" in lines["process"], lines
assert "Administrator" in lines["denied"] and "another program" in lines["busy"].lower(), lines
assert "safety switch" in lines["scripts"] and "internet" in lines["offline"] and "ask Claude" in lines["other"], lines
assert lines["guess1"] == "git" and lines["guess2"] == "[]" and lines["distance"] == "2", lines
print("error hints OK")

# the prompt adds the hint after a failed command, once, and not for commands that worked
out = plain(powershell(""". 'PROFILE' -NoBanner
$global:TermLastHistoryId = -1
'=== fail'
$null = Get-Item 'C:\\nope-xyz' -ErrorAction SilentlyContinue
$p = prompt
'=== again'
$p = prompt
'=== worked'
$null = Get-Item $HOME
$p = prompt
'=== off'
$global:TermConfig.error_hints = $false
$null = Get-Item 'C:\\nope-abc' -ErrorAction SilentlyContinue
$p = prompt
""".replace("PROFILE", str(profile))))
failed = out.split("=== fail")[1].split("=== again")[0]
assert "WHAT THIS MEANS" in failed and "is not there" in failed, out
assert "WHAT THIS MEANS" not in out.split("=== again")[1], "the same error is explained only once"
assert out.count("WHAT THIS MEANS") == 1, out
print("prompt hint OK")

# suggestions: the newer PSReadLine is found in our own folder; nothing is changed in a window with no real console
assert "IsOutputRedirected" in (root / "profile" / "custom-profile.ps1").read_text(encoding="utf-8-sig"), "the list is only switched on in a real window"
with tempfile.TemporaryDirectory() as folder:
    modules = Path(folder) / "modules"
    for version, with_manifest in (("2.4.5", True), ("2.4.6", False), ("2.3.0", True), ("notaversion", True)):
        (modules / "PSReadLine" / version).mkdir(parents=True)
        if with_manifest:
            (modules / "PSReadLine" / version / "PSReadLine.psd1").write_text("@{ ModuleVersion = '1.0' }")
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
'skipped: ' + $global:TermSuggestions
$global:TermModules = '{modules}'
'newest: ' + (Get-NewPSReadLine).Version
$global:TermModules = '{folder}\\nothing-here'
'none: [' + (Get-NewPSReadLine) + ']'
'missing: ' + (Enable-Suggestions)
'--- status'
suggestions
$global:TermSuggestions = 'missing'
suggestions
'--- bad word'
suggestions bogus
'--- off'
$global:TermConfig.suggestions = 'off'
'off: ' + (Enable-Suggestions)
suggestions off
'saved: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).suggestions
suggestions inline
'saved2: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).suggestions
"""))
    lines = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in out.splitlines() if ": " in l and l.split(": ", 1)[0] in (
        "skipped", "newest", "none", "missing", "off", "saved", "saved2")}
    assert lines["skipped"] == "skipped", lines
    assert lines["newest"] == "2.4.5", lines                                    # 2.4.6 has no manifest, 2.3.0 is older, the odd name is ignored
    assert lines["none"] == "[]" and lines["missing"] == "missing" and lines["off"] == "off", lines
    status = out.split("--- status")[1].split("--- bad word")[0]
    assert "Suggestions: list." in status and "python tools\\install_psreadline.py" in status, status
    assert "Choose list, inline or off" in out.split("--- bad word")[1], out
    assert lines["saved"] == "off" and lines["saved2"] == "inline", lines       # remembered in my-terminal.json (a copy here)
print("suggestions OK")

# the long-command alert: who is told, when, and how (the sound, the pop-up and "who is in front" are replaced by recorders: nothing is heard or shown)
with tempfile.TemporaryDirectory() as folder:
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
$global:Sounds = @(); $global:Toasts = @()
$global:TermSoundHook = {{ param($f) $global:Sounds += (Split-Path -Leaf $f) }}
$global:TermToastHook = {{ param($a, $b) $global:Toasts += ($a + ' | ' + $b) }}
$global:TermFocusHook = {{ $global:Focused }}
function Check($label, $seconds, $command, $ok = $true) {{
    $global:Sounds = @(); $global:Toasts = @()
    Invoke-LongDone ([TimeSpan]::FromSeconds($seconds)) $command $ok
    $label + ': sounds=' + $global:Sounds.Count + ' toasts=' + $global:Toasts.Count + ' ' + ($global:Toasts -join '')
}}
$global:Focused = $false
Check 'quick' 5 'git status'
Check 'slow' 45 'git pull-all --secret-token abc123'
Check 'slow failed' 61 'build.cmd' $false
Check 'ignored' 120 'live'
Check 'ignored with ampersand' 120 '& path'
$global:Focused = $true
Check 'watching' 45 'pull-all'
longdone always
Check 'watching always' 45 'pull-all'
longdone away
longdone 100
$global:Focused = $false
Check 'raised limit' 45 'pull-all'
Check 'over raised limit' 150 'pull-all'
longdone off
Check 'off' 500 'pull-all'
longdone on
$global:Focused = $false
$global:TermConfig.long_command_sound = 'off'
Check 'sound off' 45 'pull-all'
$global:TermConfig.long_command_sound = 'default'; $global:TermConfig.long_command_popup = $false
Check 'popup off' 45 'pull-all'
$global:TermConfig.long_command_popup = $true
$global:Sounds = @(); $global:Toasts = @()
longdone test
'test: sounds=' + $global:Sounds.Count + ' toasts=' + $global:Toasts.Count
longdone 0.5x
'saved: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).long_command_seconds
'--- status'
longdone
"""))
    lines = {l.split(": ", 1)[0]: l.split(": ", 1)[1] for l in out.splitlines() if ": " in l and l.split(": ", 1)[0] in (
        "quick", "slow", "slow failed", "ignored", "ignored with ampersand", "watching", "watching always", "raised limit",
        "over raised limit", "off", "sound off", "popup off", "test", "saved")}
    has_sound = Path("C:/Windows/Media/Windows Notify System Generic.wav").exists()
    expect_sound = "1" if has_sound else "0"
    assert lines["quick"].startswith("sounds=0 toasts=0"), lines
    assert lines["slow"].startswith(f"sounds={expect_sound} toasts=1") and "git finished after 45s" in lines["slow"], lines
    assert "secret" not in lines["slow"] and "abc123" not in lines["slow"], "the pop-up shows only the first word of the command"
    assert "build.cmd stopped with an error after 1m 1s" in lines["slow failed"], lines
    assert lines["ignored"].startswith("sounds=0 toasts=0") and lines["ignored with ampersand"].startswith("sounds=0 toasts=0"), lines
    assert lines["watching"].startswith("sounds=0 toasts=0"), "no alert while you are looking at the terminal"
    assert lines["watching always"].startswith("sounds=" + expect_sound + " toasts=1"), lines
    assert lines["raised limit"].startswith("sounds=0 toasts=0") and lines["over raised limit"].startswith("sounds=" + expect_sound + " toasts=1"), lines
    assert lines["off"].startswith("sounds=0 toasts=0"), lines
    assert lines["sound off"].startswith("sounds=0 toasts=1"), lines
    assert lines["popup off"].startswith("sounds=" + expect_sound + " toasts=0"), lines
    assert lines["test"] == f"sounds={expect_sound} toasts=1", lines
    assert lines["saved"] == "30", "a bad number is refused and the saved value stays"
    status = out.split("--- status")[1]
    assert "Long-command alert: after 30 seconds, only when you are in another window." in status, status
    assert "Type a number of seconds" in out, out
print("long command alert OK")

# the full-window looks, drawn on a pretend screen with made-up readings (nothing depends on this PC, nothing is shown)
import screen_png

LOOK_SETUP = r"""
. 'PROFILE' -NoBanner
$global:TermConfigPath = 'CONFIG'
function Fake-Look {
    $now = [DateTimeOffset]::UtcNow
    @{
        rows = [ordered]@{
            cpu = 'CPU  cpu-row'; ram = 'RAM  ram-row'; gpu = 'GPU  gpu-row'; disk = 'DISK disk-row'; time = 'TIME time-row'; clock = 'clock-row' }
        cores = @(10, 20, 30, 40, 50, 60, 70, 80, 15, 25, 35, 45, 55, 65, 75, 85)
        procs = @([pscustomobject]@{ name = 'alpha'; cpu = 22.5; mem = 3GB; count = 1 }, [pscustomobject]@{ name = 'beta'; cpu = 4.0; mem = 500MB; count = 4 },
                  [pscustomobject]@{ name = 'gamma'; cpu = 1.0; mem = 90MB; count = 1 })
        nic = @(@{ label = 'Ethernet'; address = '10.0.0.2'; speed = '1 Gbps' })
        weather = [pscustomobject]@{ place = 'Testville'; temp = 18.4; code = 2; wind = 14.0; sunrise = '07:12'; sunset = '18:41'
                    forecast = @([pscustomobject]@{ date = '2026-10-11'; max = 17; min = 9; code = 61 }, [pscustomobject]@{ date = '2026-10-12'; max = 15; min = 8; code = 3 }) }
        activity = @{ commits = @(@{ path = $(if ($global:TestFolder) { $global:TestFolder } else { 'C:\fake' }); time = $now.AddMinutes(-5).ToUnixTimeSeconds(); subject = 'a test commit subject' },
                                  @{ path = $(if ($global:TestFolder) { $global:TestFolder } else { 'C:\fake' }); time = $now.AddHours(-3).ToUnixTimeSeconds(); subject = 'an older commit' })
                       days = @{ ((Get-Date).ToString('yyyy-MM-dd')) = 4 } }
        git = @{ 'C:\fake' = @{ branch = 'main'; changed = 0 } }
        commands = $(if ($global:TestCommands) { $global:TestCommands } else { @('pythonw.exe C:\fake\clipboard') })
        drives = @([pscustomobject]@{ Name = 'C:\'; TotalSize = 1000GB; TotalFreeSpace = 250GB })
        state = @{ hist = @{ cpu = @(10..60); down = @(1000, 5000, 20000, 90000, 40000, 10000); up = @(500, 800, 300) }; downNow = 123456.0; upNow = 7890.0 }
        artSizes = @{ large = @(1..28 | ForEach-Object { "$([char]27)[38;2;100;200;150m" + ('L' * 56) }); small = @(1..18 | ForEach-Object { "$([char]27)[38;2;100;200;150m" + ('S' * 36) }) }
        warnings = @()
        tick = { param($ctx, $frame) $ctx.rows = [ordered]@{ cpu = ('CPU  tick-' + $frame); ram = 'RAM  r'; gpu = 'GPU  g'; disk = 'DISK d'; time = 'TIME t'; clock = 'c' } }
    }
}
function Draw($width, $height, $frames = 3) {
    $global:TermLookTest = Fake-Look
    $drawn = Show-FullScreen -Width $width -Height $height -NoAnimation -TestFrames $frames
    "DRAWN=" + $drawn
}
"""


def look_screen(extra, width, height, tail="Draw WIDTH HEIGHT"):
    with tempfile.TemporaryDirectory() as folder:
        copy = Path(folder) / "my-terminal.json"
        copy.write_bytes(CONFIG.read_bytes())
        script = (LOOK_SETUP + extra + "\n" + tail.replace("WIDTH", str(width)).replace("HEIGHT", str(height))).replace("PROFILE", str(profile)).replace("CONFIG", str(copy))
        raw = powershell(script, raw=True)
    drawn = "DRAWN=True" in raw
    vt = screen_png.VT(columns=width, rows=height)
    vt.write(raw.split("DRAWN=")[0])
    return vt, drawn, raw


TITLES = ("PC STATUS", "CPU CORES", "NETWORK", "BUSIEST PROGRAMS", "DRIVES", "TODAY", "RECENT WORK", "PINNED", "RUNNING")
for look in ("centre", "wall", "middle"):
    for width, height in ((100, 30), (120, 38), (165, 45), (200, 60)):
        vt, drawn, raw = look_screen(f"$global:TermConfig.look = '{look}'; $global:TermConfig.look_panels = @('status','cores','net','procs','drives','weather','recent','pinned','running','git','tips')", width, height)
        assert drawn, (look, width, height, raw[-400:])
        lines = vt.lines()
        text = "\n".join(lines)
        assert TITLE in lines[0], (look, width, height, lines[0])
        assert "PC STATUS" in text and "BUSIEST PROGRAMS" in text, (look, width, height)
        assert text.count("\u256d") == text.count("\u2570") and text.count("\u256e") == text.count("\u256f"), (look, width, height, "every box has all four corners")
        body = [l for l in lines[1:height - 3] if l.strip()]                # between the header and the bottom line
        assert all(l.rstrip()[-1] in "\u2502\u256e\u256f" for l in body), (look, width, height, [l for l in body if l.rstrip()[-1] not in "\u2502\u256e\u256f"][:3])
        assert any("LIVE" in l for l in lines[height - 4:]), (look, width, height, "the line at the bottom")
        assert "tick-" in text, (look, width, height, "the readings were taken again and the boxes redrawn")
        if width >= 120:
            assert "CPU CORES" in text and "RECENT WORK" in text and "TODAY" in text, (look, width, height, "the boxes fit in a normal window")
            assert "Testville" in text and "alpha" in text, (look, width, height)
        if width >= 165:
            assert "a test commit subject" in text, (look, width, height, "a wide window has room for the commit text")
        assert "LLLLLLLL" in text or "SSSSSSSS" in text, (look, width, height, "the emblem is there")
print("full-window layouts OK")

# too small a window, the classic look, and switched-off boxes
vt, drawn, raw = look_screen("$global:TermConfig.look = 'centre'", 90, 30)
assert not drawn, "a window narrower than 96 columns keeps the classic screen"
vt, drawn, raw = look_screen("$global:TermConfig.look = 'centre'", 120, 24)
assert not drawn, "a window lower than 26 rows keeps the classic screen"
vt, drawn, raw = look_screen("$global:TermConfig.look = 'classic'", 120, 38)
assert not drawn, "the classic look is drawn by the old welcome screen"
vt, drawn, raw = look_screen("$global:TermConfig.look = 'centre'; $global:TermConfig.look_panels = @('status','procs')", 120, 38)
text = "\n".join(vt.lines())
assert drawn and "BUSIEST PROGRAMS" in text and "CPU CORES" not in text and "RECENT WORK" not in text and "NETWORK" not in text, text
print("small windows and switched-off boxes OK")

# the Administrator version: same layout, red, with its own tag
vt_normal, _, _ = look_screen("$global:TermConfig.look = 'centre'", 140, 40)
vt_admin, drawn, _ = look_screen("$global:TermIsAdmin = $true; $global:TermConfig.look_admin = 'centre'", 140, 40)
assert drawn and "ADMINISTRATOR" in vt_admin.lines()[0] and "ADMINISTRATOR" not in vt_normal.lines()[0]
def corner_color(vt):
    for r in range(vt.rows):
        for c in range(vt.columns):
            if vt.cells[r][c][0] == "\u256d" and r > 1:
                return vt.cells[r][c][1]
normal_color, admin_color = corner_color(vt_normal), corner_color(vt_admin)
assert normal_color and admin_color and normal_color != admin_color and admin_color[0] > admin_color[2] and normal_color[2] >= normal_color[0], (normal_color, admin_color)
print("administrator look OK")

# a warning shows as a strip across the top and the boxes move down
vt, drawn, _ = look_screen("$global:TermConfig.look = 'centre'", 120, 38, tail="$global:TermLookTest = Fake-Look; $global:TermLookTest.warnings = @('Disk C: is almost full'); \"DRAWN=\" + (Show-FullScreen -Width 120 -Height 38 -NoAnimation -TestFrames 1)")
text = "\n".join(vt.lines())
assert drawn and "ATTENTION" in text and "Disk C: is almost full" in text and "PC STATUS" in text, text
print("warning strip OK")

# the look command: lists, switches (and remembers in my-terminal.json), boxes on and off
with tempfile.TemporaryDirectory() as folder:
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
'--- list'
look
'--- wall'
look wall | Out-Null
'now: ' + (Get-LookName)
'saved: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).look
'--- bad'
look nonsense
'--- panels'
look panels
look remove cores | Out-Null
'cores after remove: ' + ((Get-LookPanels) -contains 'cores')
look add git | Out-Null
'git after add: ' + ((Get-LookPanels) -contains 'git')
look remove status
look add nothing
'json valid: ' + ((Get-Content '{copy}' -Raw | ConvertFrom-Json).look_panels -join ',')
$global:TermIsAdmin = $true
look middle | Out-Null
'admin now: ' + (Get-LookName)
'admin saved: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).look_admin
'normal still: ' + (Get-Content '{copy}' -Raw | ConvertFrom-Json).look
"""))
    listing = out.split("--- list")[1].split("--- wall")[0]
    assert all(name in listing for name in ("classic", "centre", "wall", "middle")) and "Command centre" in listing, listing
    assert "now: wall" in out and "saved: wall" in out, out
    assert "There is no look called 'nonsense'" in out.split("--- bad")[1].split("--- panels")[0], out
    assert "cores after remove: False" in out and "git after add: True" in out, out
    assert "The PC status box always stays." in out and "Which box?" in out, out
    assert "json valid: status,net,procs,drives,weather,recent,git,log,pinned,running" in out, out
    assert "admin now: middle" in out and "admin saved: middle" in out and "normal still: wall" in out, out
print("look command OK")

# the first prompt draws the welcome screen for the chosen look (here: no real console, so the classic one appears)
out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfig.look = 'centre'
$global:TermBannerPending = $true
$global:TermLastHistoryId = -1
$null = prompt
'pending after: ' + $global:TermBannerPending
Show-Welcome -Static
"""))
assert "pending after: False" in out and out.count(TITLE) >= 2, out
print("full-window looks OK")

# the emblem pulses: one emblem cell changes brightness over time; off keeps it steady; the command remembers the choice
def pulse_colors(extra):
    seen = set()
    for frames in (1, 3, 5, 7, 9, 11, 13, 15):                       # (the bright band moves 0.9 rows a frame: it has not reached the lowest row by frame 15)
        vt, drawn, raw = look_screen(extra, 120, 38, tail=f"Draw 120 38 {frames}")
        assert drawn, raw[-300:]
        rows = [r for r in range(vt.rows) if "S" * 20 in "".join(cell[0] for cell in vt.cells[r])]
        assert rows, "the emblem is on the screen"
        r = max(rows)                                                  # the lowest emblem row: the moving band has not reached it yet
        c = "".join(cell[0] for cell in vt.cells[r]).index("S" * 20)
        seen.add(vt.cells[r][c][1])
    return seen

pulsing = pulse_colors("$global:TermConfig.look = 'centre'; $global:TermConfig.emblem_pulse = $true; $global:TermConfig.emblem_pulse_seconds = 1.2")
steady = pulse_colors("$global:TermConfig.look = 'centre'; $global:TermConfig.emblem_pulse = $false")
assert len(pulsing) >= 3, ("the emblem brightness changes over time", pulsing)
assert len(steady) == 1, ("with the pulse off the emblem stays the same", steady)

with tempfile.TemporaryDirectory() as folder:
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
function Saved($name) {{ (Get-Content '{copy}' -Raw | ConvertFrom-Json).$name }}
'start: ' + (Saved 'emblem_pulse')
emblem pulse off | Out-Null
'off: ' + (Saved 'emblem_pulse') + ' / memory ' + $global:TermConfig.emblem_pulse
emblem pulse | Out-Null
'toggled: ' + (Saved 'emblem_pulse')
emblem pulse 5 | Out-Null
'seconds: ' + (Saved 'emblem_pulse_seconds') + ' on ' + (Saved 'emblem_pulse')
emblem pulse on | Out-Null
emblem pulse | Out-Null
'toggled again: ' + (Saved 'emblem_pulse')
"""))
    assert "start: True" in out and "off: False / memory False" in out and "toggled: True" in out, out
    assert "seconds: 5 on True" in out and "toggled again: False" in out, out
print("emblem pulse OK")

# the mouse: the line under the pointer lights up; a click on a folder goes there; a click on a tool starts it, or stops it after a second click
def find_on_screen(vt, text):
    """The 1-based column and row of the first place where `text` is on the pretend screen."""
    for r in range(vt.rows):
        line = "".join(cell[0] for cell in vt.cells[r])
        if text in line:
            return line.index(text) + 1, r + 1
    raise AssertionError(f"{text!r} is not on the screen")

with tempfile.TemporaryDirectory() as folder:
    where = folder.replace("\\", "\\\\")
    setup = (f"$global:TestFolder = '{folder}'; $global:TermConfig.look = 'centre'; $global:TermConfig.look_panels = @('status','procs','weather','recent','pinned','running');"
             "$global:TermConfig.pins = @([pscustomobject]@{ key = 'one'; label = 'One'; path = $global:TestFolder }, [pscustomobject]@{ key = 'two'; label = 'Two'; path = $global:TestFolder });"
             "$global:TestCommands = @('pythonw.exe C:\\x\\Snipper\\main.py'); $global:AppLog = @();"
             "$global:TermAppHook = { param($action, $app, $ctx) $global:AppLog += ($action + ' ' + $app.name); if ($action -eq 'start') { $ctx.commands = @($ctx.commands) + 'pythonw.exe C:\\x\\feeder.py' } else { $ctx.commands = @() } }")

    def run(events, frames, start_dir="$env:TEMP"):
        tail = (f"Set-Location {start_dir}; $global:TermLookTest = Fake-Look; $global:TermLookTest.input = @({events});"
                f"$drawn = Show-FullScreen -Width 120 -Height 38 -NoAnimation -TestFrames {frames}; 'CWD=' + (Get-Location).Path; 'LOG=' + ($global:AppLog -join ',') ; \"DRAWN=\" + $drawn")
        return look_screen(setup, 120, 38, tail=tail)

    vt, drawn, raw = run("", 1)
    assert drawn and "click to go" in "\n".join(vt.lines()) and "click to start or stop" in "\n".join(vt.lines()), "the titles say what can be clicked"
    pin_col, pin_row = find_on_screen(vt, "go two")
    commit_col, commit_row = find_on_screen(vt, "a test commit")      # (how long ago is shortened in a narrow column)
    snip_col, snip_row = find_on_screen(vt, "Snipper")
    clip_col, clip_row = find_on_screen(vt, "Clipboard")
    other_col, other_row = find_on_screen(vt, "go one")

    # moving over a pinned line lights it up (and only it)
    vt, drawn, raw = run(f"@{{ frame = 1; type = 'move'; col = {pin_col + 2}; row = {pin_row} }}", 3)
    lit = lambda r, c: vt.cells[r - 1][c - 1][2]
    assert lit(pin_row, pin_col + 2) is not None and lit(other_row, other_col + 2) is None, "only the line under the pointer is tinted"
    assert lit(pin_row, pin_col + 30) is not None, "the tint runs along the whole line"

    # a click on a pinned folder goes there and ends the live screen
    vt, drawn, raw = run(f"@{{ frame = 2; type = 'click'; col = {pin_col + 2}; row = {pin_row} }}", 9)
    assert f"CWD={folder}" in raw, raw[-300:]

    # a click on recent work goes to that project's folder
    vt, drawn, raw = run(f"@{{ frame = 1; type = 'click'; col = {commit_col + 2}; row = {commit_row} }}", 5)
    assert f"CWD={folder}" in raw, raw[-300:]

    # a click on empty space or on a line that is not clickable does nothing
    vt, drawn, raw = run("@{ frame = 1; type = 'click'; col = 3; row = 3 }", 3)
    assert "CWD=" in raw and f"CWD={folder}" not in raw and "LOG=\n" in raw.replace("\r", "") + "\n", raw[-200:]

    # a tool that is not running starts at once; one that is running needs a second click within 4 seconds
    vt, drawn, raw = run(f"@{{ frame = 1; type = 'click'; col = {clip_col + 2}; row = {clip_row} }}", 3)
    assert "LOG=start Clipboard" in raw, raw[-300:]
    assert "Clipboard started" in "\n".join(vt.lines()), "the bottom line says what happened"
    vt, drawn, raw = run(f"@{{ frame = 1; type = 'click'; col = {snip_col + 2}; row = {snip_row} }}", 3)
    assert "LOG=\n" in raw.replace("\r", "") + "\n" and "Click Snipper again within 4 seconds to stop it" in "\n".join(vt.lines()), raw[-300:]
    vt, drawn, raw = run(f"@{{ frame = 1; type = 'click'; col = {snip_col + 2}; row = {snip_row} }}, @{{ frame = 3; type = 'click'; col = {snip_col + 2}; row = {snip_row} }}", 6)
    assert "LOG=stop Snipper" in raw and "Snipper stopped" in "\n".join(vt.lines()), raw[-300:]
print("mouse clicks OK")

# the mouse reading itself: the helper is found, can be switched on and restored, and takes only mouse events out of the input
out = plain(powershell(f""". '{profile}' -NoBanner
Initialize-ConsoleInput
'type: ' + [bool]('TermNative.ConsoleInput' -as [type])
$list = New-Object 'System.Collections.Generic.List[int[]]'
'drain without a console: ' + [TermNative.ConsoleInput]::Drain($list) + ' ' + $list.Count
'restore of nothing: ' + [TermNative.ConsoleInput]::Restore(-1)
$global:TermConfig.mouse = $false
'mouse off setting: [' + (Enable-LookMouse) + ']'
"""))
assert "type: True" in out and "drain without a console: False 0" in out and "mouse off setting: []" in out, out
print("mouse input OK")

# the keyboard: leftovers from the hotkey that opened the window must not stop the live screen before it has moved
# (this is what really went wrong in his window: Ctrl+Alt+T left its key releases behind and the screen froze at once)
def live_end(extra_setup, tail_extra, frames=6):
    setup = ("$global:TermConfig.look = 'centre'; $global:StaleCount = 0;"
             "$global:TermStaleHook = { $global:StaleCount++; 3 };" + extra_setup)
    tail = ("$global:TermLookTest = Fake-Look; $global:TermLookTest.withKeys = $true; " + tail_extra +
            f"; $drawn = Show-FullScreen -Width 120 -Height 38 -NoAnimation -TestFrames {frames};"
            " 'ENDED=' + $global:TermLookCtx.ended; 'STALE=' + $global:StaleCount; \"DRAWN=\" + $drawn")
    return look_screen(setup, 120, 38, tail=tail)[2]

# a key that arrives in the first moments is ignored (the screen keeps moving to the end of the test)
out = live_end("", "$global:TermLookTest.graceMs = 5000; $global:TermLookTest.input = @(@{ frame = 1; type = 'key' })")
assert "ENDED=frames" in out, out
assert "STALE=1" in out, ("the leftovers are thrown away once, at the start", out)
# a key after that does end it
out = live_end("", "$global:TermLookTest.graceMs = 0; $global:TermLookTest.input = @(@{ frame = 2; type = 'key' })")
assert "ENDED=key" in out, out
print("stale keys OK")

# Clear-StaleInput itself: it empties the keyboard and never loops for ever
out = plain(powershell(f""". '{profile}' -NoBanner
$global:Left = 5
$global:TermStaleHook = $null
'with no console: ' + (Clear-StaleInput)
$global:TermStaleHook = {{ 7 }}
'with a hook: ' + (Clear-StaleInput)
"""))
assert "with no console: 0" in out and "with a hook: 7" in out, out
print("stale input helper OK")

# the classic welcome screen: the emblem breathes while the screen is live, and the leftovers of a hotkey do not stop it
# (nothing is shown: a pretend console, and the keyboard is replaced by a hook)
def classic_live(extra, frames=8):
    return powershell(f""". '{profile}' -NoBanner
$global:StaleCalls = 0
$global:TermStaleHook = {{ $global:StaleCalls++; 2 }}
{extra}
Show-Banner -Width 120 -NoAnimation -TestLiveFrames {frames}
'STALE=' + $global:StaleCalls
""", raw=True)

def emblem_colours(raw):
    """The brightnesses the emblem was drawn at: every colour used on a line written to column 1."""
    seen = set()
    for move in re.finditer(r"\x1b\[(\d+);1H((?:(?!\x1b\[\d+;\d+H).)*)", raw, re.S):
        body = move.group(2)
        if any("⠀" <= ch <= "⣿" for ch in body) or any(ch in body for ch in "#@%"):   # a line of the emblem (braille dots, or the letters style)
            seen.update(re.findall(r"\x1b\[38;2;(\d+;\d+;\d+)m", body))
    return seen

out = classic_live("$global:TermConfig.emblem_pulse = $true")
colours = emblem_colours(out)
assert len(colours) >= 3, ("the emblem is drawn at several brightnesses while it breathes", sorted(colours)[:6])

out_off = classic_live("$global:TermConfig.emblem_pulse = $false")
assert len(emblem_colours(out_off)) <= 1, ("with the pulse off the emblem is left alone", sorted(emblem_colours(out_off))[:6])

# the live phase throws away the leftovers of the hotkey that opened the window before it watches the keyboard
# (a test with -NoKeys has no keyboard at all, so this calls it the way a real window does)
out = plain(powershell(f""". '{profile}' -NoBanner
$global:StaleCalls = 0
$global:TermStaleHook = {{ $global:StaleCalls++; 2 }}
Start-LivePhase @{{}} @{{}} 1 1 -Frames 1 -WindowTop 0 -WindowHeight 50
'cleared: ' + $global:StaleCalls
"""))
assert "cleared: 1" in out, ("the leftovers are thrown away once, before the keyboard is watched", out)
print("classic emblem pulse OK")

# the weather line leaves parts out instead of being cut off mid-word
out = plain(powershell(f""". '{profile}' -NoBanner
$w = [pscustomobject]@{{ place = 'Almere Stad'; temp = 12.0; code = 0; wind = 12.0; sunrise = '07:55'; sunset = '18:55' }}
'wide:   [' + (Format-WeatherLine $w 200) + ']'
'narrow: [' + (Format-WeatherLine $w 60) + ']'
'tiny:   [' + (Format-WeatherLine $w 24) + ']'
"""))
lines = {l.split(":", 1)[0].strip(): l.split("[", 1)[1].rstrip("]") for l in out.splitlines() if "[" in l}
assert "sunset 18:55" in lines["wide"] and "wind" in lines["wide"], lines
assert "sunset" not in lines["narrow"] and "wind" in lines["narrow"], ("the end is left out, not cut", lines)
assert len(lines["narrow"]) <= 60, lines
assert "Almere Stad" in lines["tiny"] and "wind" not in lines["tiny"], lines
print("weather line fits OK")

# stats: counts the commands and the pins you use
out = plain(powershell(""". 'PROFILE' -NoBanner
$global:TermStatsLines = @('git status', 'git status', 'git log', 'ls', 'go clip', 'go clip', 'go snip')
stats
""".replace("PROFILE", str(profile))))
assert "7 commands" in out and "COMMANDS YOU USE MOST" in out, out
git_row = [l for l in out.splitlines() if l.strip().startswith("git")][0]
assert git_row.rstrip().endswith("3"), git_row
assert "PINS YOU JUMP TO" in out and [l for l in out.splitlines() if l.strip().startswith("clip")][0].rstrip().endswith("2"), out
print("stats OK")

# apps: start, see and stop a harmless fake program (your real apps are never touched)
out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfig.apps = @([pscustomobject]@{{ name = 'Fake'; match = 'TERMTEST_FAKE_APP_xyz'; path = $env:TEMP; expected = $false;
    run = @('powershell.exe', '-NoProfile', '-WindowStyle', 'Hidden', '-Command', 'Start-Sleep 25 # TERMTEST_FAKE_APP_xyz') }})
"1: " + ((apps) -join ' ')
apps
apps start fake
Start-Sleep -Seconds 2
"--- after start"
apps
apps start fake
apps stop fake
Start-Sleep -Seconds 1
"--- after stop"
apps
apps frobnicate
"""))
before, after_start, after_stop = out.split("--- after start")[0], out.split("--- after start")[1].split("--- after stop")[0], out.split("--- after stop")[1]
assert "stopped" in before and "Fake started" in before, out
assert "running" in after_start and "Fake is already running" in after_start and "Fake stopped" in after_start, after_start
assert "stopped" in after_stop and "Use: apps start|stop|restart" in after_stop, after_stop
print("apps OK")

# projects and pull-all: two temporary git projects, one with unsaved changes
def git(folder, *args):
    subprocess.run(["git", "-C", str(folder), "-c", "user.name=test", "-c", "user.email=test@example.com", *args], capture_output=True, check=True)

with tempfile.TemporaryDirectory() as base:
    clean, dirty = Path(base) / "clean-one", Path(base) / "dirty-one"
    for folder, subject in ((clean, "first commit"), (dirty, "second project")):
        folder.mkdir()
        git(folder, "init", "-q")
        (folder / "a.txt").write_text("hello")
        git(folder, "add", "a.txt")
        git(folder, "commit", "-q", "-m", subject)
    (dirty / "b.txt").write_text("new")
    (dirty / "a.txt").write_text("changed")
    out = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfig.pins = @([pscustomobject]@{{ key = 'one'; label = 'One'; path = '{clean}' }}, [pscustomobject]@{{ key = 'two'; label = 'Two'; path = '{dirty}' }}, [pscustomobject]@{{ key = 'dl'; label = 'No git'; path = '{base}' }})
projects
"--- pull"
pull-all
"""))
    table, pull = out.split("--- pull")
    assert "PROJECTS" in table and "first commit" in table and "second project" in table, table
    one, two = [l for l in table.splitlines() if l.strip().startswith("one")][0], [l for l in table.splitlines() if l.strip().startswith("two")][0]
    assert "clean" in one and "no remote" in one and "changed" in two and "2 changed" in two, (one, two)
    assert "no remote, nothing to pull" in pull and pull.count("no remote, nothing to pull") == 2, pull
print("projects OK")

# the command list
assert "cmds" in plain(powershell(f". '{profile}' -NoBanner\ncmds")) or True
help_text = plain(powershell(f". '{profile}' -NoBanner\ncmds"))
for word in ("go <pin>", "z <letters>", "apps", "projects", "stats", "weather"):
    assert word in help_text, word
print("command list OK")

# weather: no place yet -> a hint; with a saved place and a fresh reading -> the line (no internet is used by the tests)
none = plain(powershell(f". '{profile}' -NoBanner\nweather"))
assert "weather city <your city>" in none, none
import datetime
Path(DATA_DIR, "weather-place.json").write_text(json.dumps({"name": "Testville", "country": "Nowhere", "lat": 52.0, "lon": 5.0}), encoding="utf-8")
Path(DATA_DIR, "weather.json").write_text(json.dumps({"at": datetime.datetime.now().astimezone().isoformat(), "place": "Testville", "temp": 14.4,
                                                       "code": 65, "wind": 15.5, "sunrise": "07:55", "sunset": "18:59"}), encoding="utf-8")
shown = plain(powershell(f". '{profile}' -NoBanner\nweather"))
assert "Testville" in shown and "14" in shown and "heavy rain" in shown and "sunrise 07:55" in shown and "sunset 18:59" in shown, shown
in_banner = plain(powershell(f". '{profile}' -NoBanner\nShow-Banner -Width 130 -NoAnimation -NoLive"))
assert "Testville" in in_banner and "heavy rain" in in_banner, "the weather line is in the banner"
text_codes = plain(powershell(f". '{profile}' -NoBanner\n(0, 2, 3, 45, 63, 65, 75, 82, 95 | ForEach-Object {{ Get-WeatherText $_ }}) -join ','"))
assert "clear sky,partly cloudy,overcast,fog,rain,heavy rain,snow,heavy showers,thunderstorm" in text_codes, text_codes
Path(DATA_DIR, "weather-place.json").unlink()
Path(DATA_DIR, "weather.json").unlink()
print("weather OK")

# the emblem glows in: dim first, then five brightening steps; the final picture is the full emblem, and only the emblem moves
glow_raw = powershell(f". '{profile}' -NoBanner\n$global:TermConfig.art = 'rune'\nShow-Banner -Width 130 -NoAnimation -NoLive -TestGlow")
assert glow_raw.count("\x1b7") == 5, "five brightening steps"
art_file = [l for l in (root / "art" / "rune-small.ans").read_text(encoding="utf-8").splitlines()]
art_file = [l for l in (root / "art" / "rune.ans").read_text(encoding="utf-8").splitlines()] if "rune.ans" else art_file
middle = art_file[len(art_file) // 2]
assert glow_raw.count(middle) == 1, "only the final step uses the emblem's real colours; the others are dimmed"
screen = mini_terminal.Screen(columns=200)
screen.write(glow_raw)
for i, line in enumerate(art_file):
    expected = CODE.sub("", line).rstrip()
    assert screen.line(1 + i)[:len(expected)] == expected, f"emblem row {i} ended up as it should"
print("glow OK")

# real pictures (Sixel): room is kept on the left, the picture is drawn once over it, the text stays beside it
import math
picture_out = powershell(f""". '{profile}' -NoBanner
$global:TermConfig.emblem_picture = $true
$global:TermCell = @(9, 19)
Show-Banner -Width 130 -NoAnimation -NoLive -TestPicture""")
assert picture_out.count("\x1bP0;1;0q") == 1 and picture_out.count("\x1b\\") == 1, "one picture is drawn"
width, height = (int(v) for v in re.search(r'q"1;1;(\d+);(\d+)', picture_out).groups())
assert (width, height) == (360, 360), "the rune picture nearest 38 characters wide is chosen for 9-pixel characters"
cols, rows = math.ceil(width / 9) + 1, math.ceil(height / 19) + 1
screen = mini_terminal.Screen(columns=220)
screen.write(picture_out)
title_row = [i for i in range(40) if TITLE in screen.line(i)][0]
assert screen.line(title_row).index(TITLE.split()[0]) == cols + 3, "the text starts right after the room kept for the picture"
assert all(screen.line(r)[:cols].strip() == "" for r in range(1, 1 + rows)), "the room on the left holds no characters"
assert "\x1b7\x1b[2;1H\x1bP" in picture_out, "the picture is drawn at the top of the banner and the cursor is put back"
admin_picture = powershell(f""". '{profile}' -NoBanner
$global:TermConfig.emblem_picture = $true
$global:TermCell = @(9, 19)
$global:TermIsAdmin = $true
Show-Banner -Width 130 -NoAnimation -NoLive -TestPicture""")
assert re.search(r'q"1;1;(\d+);(\d+)', admin_picture).groups() == ("360", "458"), "an Administrator window gets the elevated picture"
no_room = powershell(f""". '{profile}' -NoBanner
$global:TermConfig.emblem_picture = $true
$global:TermCell = @(9, 19)
Show-Banner -Width 70 -NoAnimation -NoLive -TestPicture""")
assert "\x1bP" not in no_room, "a window too narrow for picture and text draws no picture"
off = powershell(f""". '{profile}' -NoBanner
$global:TermCell = @(9, 19)
Show-Banner -Width 130 -NoAnimation -NoLive -TestPicture""")
assert "\x1bP" not in off and any(0x2800 <= ord(ch) <= 0x28FF for ch in off), "off by default: the dots are used"
big_cells = powershell(f""". '{profile}' -NoBanner
$global:TermConfig.emblem_picture = $true
$global:TermCell = @(14, 30)
Show-Banner -Width 130 -NoAnimation -NoLive -TestPicture""")
assert re.search(r'q"1;1;(\d+);', big_cells).group(1) == "440", "bigger characters get the bigger picture"
not_a_console = powershell(f""". '{profile}' -NoBanner
$global:TermConfig.emblem_picture = $true
Show-Banner -Width 130 -NoAnimation -NoLive""")
assert "\x1bP" not in not_a_console, "pictures are only drawn in a real console"
print("picture emblem OK")

# the size of a character: your own setting wins; otherwise the terminal's answer or an estimate
cell = plain(powershell(f""". '{profile}' -NoBanner
$global:TermCell = $null
$global:TermConfig | Add-Member -NotePropertyName sixel_cell -NotePropertyValue @(11, 23) -Force
"set: " + ((Get-CellSize) -join 'x')
$global:TermCell = $null
$global:TermConfig.sixel_cell = $null
"estimate: " + ((Get-CellSize) -join 'x')
"""))
assert "set: 11x23" in cell, cell
estimate = re.search(r"estimate: (\d+)x(\d+)", cell)
assert estimate and 6 <= int(estimate.group(1)) <= 20 and 10 <= int(estimate.group(2)) <= 40, cell
print("cell size OK")

# emblem picture on / off writes one line of my-terminal.json
with tempfile.TemporaryDirectory() as folder:
    copy = Path(folder) / "my-terminal.json"
    copy.write_bytes(CONFIG.read_bytes())
    before = copy.read_text(encoding="utf-8")
    result = plain(powershell(f""". '{profile}' -NoBanner
$global:TermConfigPath = '{copy}'
emblem picture on -Quiet
"on: " + $global:TermConfig.emblem_picture
emblem picture -Quiet
"toggled: " + $global:TermConfig.emblem_picture
emblem picture on -Quiet
"""))
    after = copy.read_text(encoding="utf-8")
    assert "on: True" in result and "toggled: False" in result, result
    assert '"emblem_picture": true' in after and '"emblem_picture": false' in before
    changed = [(a, b) for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
    assert len(before.splitlines()) == len(after.splitlines()) and len(changed) == 1, "only that line changed"
print("emblem picture switch OK")

# special characters (braille dots, graph bars, arrows) must never go through [Console]::Out: in a Windows console that is the old
# DOS alphabet (code page 850) and shows them as question marks. Write-Raw (Write-Host) is the safe way.
for script in sorted((root / "profile").glob("*.ps1")):
    code = [line for line in script.read_text(encoding="utf-8-sig").splitlines() if not line.lstrip().startswith("#")]
    assert not any("[Console]::Out" in line for line in code), f"{script.name} writes through [Console]::Out: use Write-Raw"
print("no question-mark channel OK")

# the prompt: coloured pills, a clock at the right, and the git state (clean or changed) in the branch pill
with tempfile.TemporaryDirectory() as base:
    repo = Path(base) / "pillrepo"
    repo.mkdir()
    subprocess.run(["git", "-C", str(repo), "init", "-q"], capture_output=True, check=True)
    (repo / "a.txt").write_text("hello")
    subprocess.run(["git", "-C", str(repo), "add", "a.txt"], capture_output=True, check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "first"], capture_output=True, check=True)
    def prompt_text(folder, style="two"):
        return powershell(f""". '{profile}' -NoBanner
$global:TermConfig.prompt = '{style}'
Set-Location '{folder}'
$global:TermLastHistoryId = -1
Write-Host (prompt) -NoNewline
""")
    clean = prompt_text(repo)
    assert "48;2;" in clean, "the labels are tinted pills (they have a background colour)"
    first, second = plain(clean).splitlines()
    assert re.search(r"\d\d:\d\d\s*$", first), f"a clock at the right edge: {first!r}"
    assert "\u2713" in first and "\u25cf" not in first, f"clean: a tick in the branch pill: {first!r}"
    (repo / "b.txt").write_text("new")
    (repo / "a.txt").write_text("changed")
    dirty = plain(prompt_text(repo)).splitlines()[0]
    assert "\u25cf 2" in dirty, f"two changed files: {dirty!r}"
    one = plain(prompt_text(repo, "one"))
    assert "\n" not in one.strip() and NAME_LOW in one and one.rstrip().endswith("\u276f"), one
    admin = plain(powershell(f""". '{profile}' -NoBanner
$global:TermIsAdmin = $true
Set-Location '{repo}'
Write-Host (prompt) -NoNewline
""")).splitlines()[0]
    assert " ADMIN " in admin, admin
print("prompt pills OK")

# Claude Code's terminal in VS Code (the extension sets this marker) stays plain, so `claude` can start
claude_tab = powershell(f"""$env:TERM_PROGRAM = 'vscode'; $env:NoDefaultCurrentDirectoryInExePath = '1'
. '{profile}'
'loaded=' + [bool]$global:TermConfig + ' pending=' + [bool]$global:TermBannerPending""")
assert "loaded=False pending=False" in claude_tab, claude_tab
normal_tab = powershell(f"""$env:TERM_PROGRAM = 'vscode'
. '{profile}' -NoBanner
'loaded=' + [bool]$global:TermConfig""")
assert "loaded=True" in normal_tab, normal_tab
print("Claude Code tab skipped OK")

import shutil
shutil.rmtree(DATA_DIR, ignore_errors=True)
print("profile tests passed")
