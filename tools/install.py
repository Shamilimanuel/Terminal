"""Puts my terminal into use, and takes it out again.

    python tools\\install.py            show what would change (changes nothing)
    python tools\\install.py --apply    do it (a backup of your Terminal settings is made first)
    python tools\\install.py --undo     put everything back the way it was
    python tools\\install.py --apply --sharp    the same, but no blur: a live wallpaper shows through crisp

It changes three things, all for your user only:
  1. Windows Terminal's settings.json: the Rune colours, see-through look, a window size that fits the banner,
     and a second profile called "PowerShell Administrator" (red tab, asks Windows for permission when it opens).
  2. Your PowerShell profile file: one block that loads this folder's profile\\custom-profile.ps1.
  3. Two Start Menu shortcuts with hotkeys: Ctrl+Alt+T (PowerShell) and Ctrl+Alt+Shift+T (Administrator).
  4. A drop-down terminal on Win + ` (the key under Esc), built into Windows Terminal.
  5. Only when the newer PSReadLine is installed (python tools\\install_psreadline.py --apply): the two PowerShell entries start
     PowerShell through a small cmd helper that puts %LOCALAPPDATA%\\Terminal\\modules first on the module path, so PowerShell loads
     the newer typing helper that shows the live list of commands. PowerShell started anywhere else is not touched.
"""
import copy
import json
import os
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
LOCAL = Path(os.environ.get("LOCALAPPDATA", ""))
SETTINGS = LOCAL / "Packages" / "Microsoft.WindowsTerminal_8wekyb3d8bbwe" / "LocalState" / "settings.json"
BACKUP_NAME = "settings.json.before-my-terminal"
MARK_START, MARK_END = "# >>> my terminal >>>", "# <<< my terminal <<<"
ADMIN_GUID = "{3f2a6c1e-8d4b-5e7a-9c10-5b6d7e8f9a01}"
SHORTCUTS = [("Terminal.lnk", "CTRL+ALT+T", "Windows PowerShell"),
             ("Terminal Administrator.lnk", "CTRL+ALT+SHIFT+T", "PowerShell Administrator")]

SCHEME = {
    "name": "Rune",
    "background": "#0a1218", "foreground": "#dff3ff", "cursorColor": "#5fd4ff", "selectionBackground": "#1b3a4a",
    "black": "#0f1d26", "red": "#ff6b81", "green": "#6fe0b0", "yellow": "#ffc857", "blue": "#5f9bff",
    "purple": "#b69cff", "cyan": "#5fd4ff", "white": "#cfe3ee",
    "brightBlack": "#4a6272", "brightRed": "#ff8fa0", "brightGreen": "#8ff0c8", "brightYellow": "#ffd98a",
    "brightBlue": "#8fb8ff", "brightPurple": "#cdb8ff", "brightCyan": "#8fe6ff", "brightWhite": "#ffffff",
}
ADMIN_SCHEME = dict(SCHEME, name="Rune Admin", cursorColor="#ff6b81", selectionBackground="#3a1f2a")
LOOK = {"colorScheme": "Rune", "opacity": 78, "useAcrylic": True, "padding": "12, 10",
        "font": {"face": "Cascadia Mono", "size": 11}}


# The drop-down terminal: Win + the key under Esc (` ~) slides a terminal down from the top of the screen, and again hides it.
QUAKE_ID = "User.quake"
QUAKE_ACTION = {"command": {"action": "globalSummon", "name": "_quake", "dropdownDuration": 150, "toggleVisibility": True,
                            "monitor": "toMouse", "desktop": "toCurrent"}, "id": QUAKE_ID}
QUAKE_KEY = {"id": QUAKE_ID, "keys": "win+sc(41)"}


MODULE_FOLDER = "%LOCALAPPDATA%\\Terminal\\modules"
MODULE_MARK = "set PSModulePath=" + MODULE_FOLDER


def with_modules(commandline):
    """The PowerShell start command, run through cmd so that our modules folder comes first on PowerShell's module path.
    (PowerShell loads its typing helper before any profile runs, so this has to be set before it starts.) Safe to run twice."""
    if MODULE_MARK in commandline or "powershell.exe" not in commandline.lower():
        return commandline
    return f'%SystemRoot%\\System32\\cmd.exe /d /s /c "{MODULE_MARK};%PSModulePath%&& {commandline}"'


def without_modules(commandline):
    """The plain PowerShell start command again."""
    if MODULE_MARK not in commandline:
        return commandline
    return commandline.split("&& ", 1)[1].rstrip('"')


def psreadline_installed():
    base = Path(os.environ.get("LOCALAPPDATA", "")) / "Terminal" / "modules" / "PSReadLine"
    return base.exists() and any((folder / "PSReadLine.psd1").exists() for folder in base.iterdir() if folder.is_dir())


def merge_settings(data, sharp=False, modules=False):
    """Returns Windows Terminal settings with my look added. Safe to run twice; everything else is left alone.
    sharp=True turns the blur off: the window is plain see-through, so a live wallpaper (Wallpaper Engine) shows
    through without being blurred. modules=True makes the PowerShell entries start with our modules folder first (see with_modules);
    modules=False puts the plain start command back."""
    data = copy.deepcopy(data)
    data["schemes"] = [s for s in data.get("schemes", []) if s.get("name") not in ("Rune", "Rune Admin")] + [SCHEME, ADMIN_SCHEME]
    profiles = data.setdefault("profiles", {})
    defaults = profiles.setdefault("defaults", {})
    defaults.update(copy.deepcopy(LOOK))
    if sharp:
        defaults["useAcrylic"] = False
        defaults["opacity"] = 72
    data["actions"] = [a for a in data.get("actions", []) if a.get("id") != QUAKE_ID] + [copy.deepcopy(QUAKE_ACTION)]
    data["keybindings"] = [k for k in data.get("keybindings", []) if k.get("id") != QUAKE_ID] + [copy.deepcopy(QUAKE_KEY)]
    data["initialCols"] = 120      # wide and tall enough for the welcome screen
    data["initialRows"] = 38
    powershell = next((p for p in profiles.get("list", []) if "powershell.exe" in p.get("commandline", "").lower()), None)
    commandline = without_modules(powershell["commandline"]) if powershell else "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    profiles["list"] = [p for p in profiles.get("list", []) if p.get("guid") != ADMIN_GUID] + [{
        "guid": ADMIN_GUID, "name": "PowerShell Administrator", "commandline": commandline, "hidden": False,
        "elevate": True, "colorScheme": "Rune Admin", "tabColor": "#ff6b81"}]
    for entry in profiles["list"]:                       # the normal and the Administrator PowerShell entries
        if "powershell.exe" in entry.get("commandline", "").lower():
            entry["commandline"] = with_modules(without_modules(entry["commandline"])) if modules else without_modules(entry["commandline"])
    return data


def profile_block():
    script = PROJECT / "profile" / "custom-profile.ps1"
    return f'{MARK_START}\nif (Test-Path -LiteralPath "{script}") {{ . "{script}" }}\n{MARK_END}\n'


def add_block(text):
    """The PowerShell profile text with my block added (or refreshed)."""
    return remove_block(text).rstrip("\n") + ("\n\n" if text.strip() else "") + profile_block()


def remove_block(text):
    if MARK_START not in text:
        return text
    before, _, rest = text.partition(MARK_START)
    _, _, after = rest.partition(MARK_END)
    return (before.rstrip("\n") + "\n" + after.lstrip("\n")).lstrip("\n") if (before.strip() or after.strip()) else ""


def documents_folder():
    result = subprocess.run(["powershell", "-NoProfile", "-Command", "[Environment]::GetFolderPath('MyDocuments')"],
                            capture_output=True, text=True)
    return Path(result.stdout.strip())


def profile_path():
    return documents_folder() / "WindowsPowerShell" / "Microsoft.PowerShell_profile.ps1"


def shortcut_folder():
    return Path(os.environ["APPDATA"]) / "Microsoft" / "Windows" / "Start Menu" / "Programs"


def make_shortcut(path, hotkey, profile):
    wt = LOCAL / "Microsoft" / "WindowsApps" / "wt.exe"
    script = ("$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK); $s.TargetPath = $env:TARGET; "
              "$s.Arguments = $env:ARGS; $s.Hotkey = $env:KEYS; $s.Description = 'My terminal'; $s.Save()")
    env = dict(os.environ, LNK=str(path), TARGET=str(wt), ARGS=f'-p "{profile}"', KEYS=hotkey)
    subprocess.run(["powershell", "-NoProfile", "-Command", script], env=env, check=True, capture_output=True)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def apply():
    if not SETTINGS.exists():
        sys.exit(f"Windows Terminal settings not found at {SETTINGS}")
    backup = SETTINGS.with_name(BACKUP_NAME)
    if not backup.exists():
        backup.write_bytes(SETTINGS.read_bytes())
        print("backup of your settings:", backup)
    merged = merge_settings(read_json(SETTINGS), sharp="--sharp" in sys.argv, modules=psreadline_installed())
    json.loads(json.dumps(merged))                       # must be valid JSON before it is written
    SETTINGS.write_text(json.dumps(merged, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Windows Terminal settings updated")

    path = profile_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    old = path.read_text(encoding="utf-8-sig") if path.exists() else ""
    path.write_bytes(b"\xef\xbb\xbf" + add_block(old).encode("utf-8"))
    print("PowerShell profile updated:", path)

    for name, hotkey, profile in SHORTCUTS:
        make_shortcut(shortcut_folder() / name, hotkey, profile)
        print("shortcut:", name, hotkey)


def undo():
    backup = SETTINGS.with_name(BACKUP_NAME)
    if backup.exists():
        SETTINGS.write_bytes(backup.read_bytes())
        print("Windows Terminal settings restored from", backup)
    path = profile_path()
    if path.exists():
        text = remove_block(path.read_text(encoding="utf-8-sig"))
        if text.strip():
            path.write_bytes(b"\xef\xbb\xbf" + text.encode("utf-8"))
        else:
            path.unlink()
        print("PowerShell profile cleaned:", path)
    for name, _, _ in SHORTCUTS:
        (shortcut_folder() / name).unlink(missing_ok=True)
    print("shortcuts removed")


def dry_run():
    print("Nothing is changed. With --apply this would:")
    print(" - back up", SETTINGS)
    merged = merge_settings(read_json(SETTINGS), modules=psreadline_installed())
    print(" - add colour schemes:", [s["name"] for s in merged["schemes"]])
    print(" - set for every profile:", LOOK)
    print(" - add profile 'PowerShell Administrator' (elevated, red tab); profiles now:", [p["name"] for p in merged["profiles"]["list"]])
    if psreadline_installed():
        print(" - start the PowerShell entries through cmd with the Terminal modules folder first (the live command list):",
              [p["commandline"] for p in merged["profiles"]["list"] if "powershell.exe" in p.get("commandline", "").lower()])
    else:
        print(" - (the live command list is not installed; python tools\\install_psreadline.py --apply adds it)")
    print(" - add this block to", profile_path(), "\n" + profile_block())
    for name, hotkey, profile in SHORTCUTS:
        print(f" - Start Menu shortcut {name}: {hotkey} -> wt -p \"{profile}\"")


if __name__ == "__main__":
    if "--apply" in sys.argv:
        apply()
    elif "--undo" in sys.argv:
        undo()
    else:
        dry_run()
