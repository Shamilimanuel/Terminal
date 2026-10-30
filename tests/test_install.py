"""Tests for the installer's pure parts (no real settings or profile are touched): the Windows Terminal merge and the
PowerShell profile block. Run with:  python tests\\run_all.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import install

original = {
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "keybindings": [{"id": "Terminal.CopyToClipboard", "keys": "ctrl+c"}],
    "profiles": {"defaults": {"fontSize": 12}, "list": [
        {"commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell"},
        {"commandline": "%SystemRoot%\\System32\\cmd.exe", "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}", "name": "Command Prompt"}]},
    "schemes": [{"name": "Mine"}],
}
snapshot = json.dumps(original, sort_keys=True)

merged = install.merge_settings(original)
assert json.dumps(original, sort_keys=True) == snapshot, "the merge must not change what it was given"
assert [p["name"] for p in merged["profiles"]["list"]] == ["Windows PowerShell", "Command Prompt", "PowerShell Administrator"]
admin = merged["profiles"]["list"][-1]
assert admin["elevate"] is True and admin["colorScheme"] == "Rune Admin" and "powershell.exe" in admin["commandline"]
assert [s["name"] for s in merged["schemes"]] == ["Mine", "Rune", "Rune Admin"], "your own schemes stay"
assert merged["profiles"]["defaults"]["colorScheme"] == "Rune" and merged["profiles"]["defaults"]["fontSize"] == 12, "other defaults stay"
assert merged["profiles"]["defaults"]["opacity"] == 78 and merged["profiles"]["defaults"]["useAcrylic"] is True
assert merged["keybindings"][:len(original["keybindings"])] == original["keybindings"] and merged["defaultProfile"] == original["defaultProfile"], "your own keys stay"
quake = [k for k in merged["keybindings"] if k["id"] == install.QUAKE_ID]
assert len(quake) == 1 and quake[0]["keys"] == "win+sc(41)", "the drop-down terminal key is added once"
summon = [a for a in merged["actions"] if a["id"] == install.QUAKE_ID]
assert len(summon) == 1 and summon[0]["command"]["action"] == "globalSummon" and summon[0]["command"]["name"] == "_quake"
assert install.merge_settings(merged) == merged, "running it twice changes nothing more"
assert merged["initialCols"] == 120 and merged["initialRows"] == 38
sharp = install.merge_settings(original, sharp=True)["profiles"]["defaults"]
assert sharp["useAcrylic"] is False and sharp["opacity"] < 100, "--sharp: see-through without the blur"
assert install.merge_settings(install.merge_settings(original, sharp=True))["profiles"]["defaults"]["useAcrylic"] is True, "a plain apply goes back to the blur"
assert set(install.SCHEME) >= {"name", "background", "foreground", "black", "brightWhite", "cursorColor"}
print("settings merge OK")

# the live command list: with modules=True both PowerShell entries start through cmd with our modules folder first
wrapped = install.merge_settings(original, modules=True)
entries = {p["name"]: p["commandline"] for p in wrapped["profiles"]["list"]}
for name in ("Windows PowerShell", "PowerShell Administrator"):
    assert entries[name].startswith("%SystemRoot%\\System32\\cmd.exe /d /s /c ") and install.MODULE_MARK in entries[name], entries[name]
    assert entries[name].endswith('powershell.exe"'), entries[name]
assert entries["Command Prompt"] == "%SystemRoot%\\System32\\cmd.exe", "other profiles are never wrapped"
assert install.merge_settings(wrapped, modules=True) == wrapped, "no double wrapping"
assert install.merge_settings(wrapped, modules=False) == install.merge_settings(original), "modules=False puts the plain start command back"
plain_command = original["profiles"]["list"][0]["commandline"]
assert install.without_modules(install.with_modules(plain_command)) == plain_command
assert install.with_modules("%SystemRoot%\\System32\\cmd.exe") == "%SystemRoot%\\System32\\cmd.exe"
assert install.merge_settings(original)["profiles"]["list"][0]["commandline"] == plain_command, "without the module the start command is untouched"
print("module path start OK")

# the PowerShell profile block
start = install.MARK_START
assert install.remove_block(install.add_block("")) == "", "add then remove leaves an empty profile empty"
mine = "Set-Alias ll Get-ChildItem\n"
added = install.add_block(mine)
assert mine.strip() in added and start in added and added.count(start) == 1
assert install.add_block(added) == added, "adding twice does not repeat the block"
assert install.remove_block(added).strip() == mine.strip(), "your own lines come back untouched"
assert "custom-profile.ps1" in install.profile_block()
print("profile block OK")

# every PowerShell file keeps its byte-order mark, or Windows PowerShell 5.1 misreads the special characters
for path in sorted((Path(__file__).resolve().parent.parent / "profile").glob("*.ps1")):
    assert path.read_bytes().startswith(b"\xef\xbb\xbf"), f"{path.name} needs the mark (run tools\\fix_bom.py)"
print("byte-order marks OK")
print("install tests passed")
