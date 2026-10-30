"""Tests for tools/install_psreadline.py: unpacking, the safety checks and the dry run. Nothing is downloaded and
your real %LOCALAPPDATA% is never touched (the tests point it at a throwaway folder)."""
import base64
import hashlib
import io
import os
import sys
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / "tools"))

with tempfile.TemporaryDirectory() as fake_local:
    os.environ["LOCALAPPDATA"] = fake_local
    import install_psreadline as tool

    assert str(tool.target_folder()).startswith(fake_local), "installs only below LOCALAPPDATA\\Terminal\\modules"
    assert tool.target_folder().parts[-4:] == ("Terminal", "modules", "PSReadLine", tool.VERSION), tool.target_folder()

    # a package like the real one: module files, the NuGet bookkeeping that must be left out, and a sub-folder
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("PSReadLine.psd1", "@{ ModuleVersion = '2.4.5' }")
        archive.writestr("PSReadLine.psm1", "# module")
        archive.writestr("netstd/Polyfiller.dll", "dll")
        archive.writestr("_rels/.rels", "x")
        archive.writestr("PSReadLine.nuspec", "x")
        archive.writestr("[Content_Types].xml", "x")
        archive.writestr("package/services/metadata/core-properties/a.psmdcp", "x")
        archive.writestr(".signature.p7s", "x")
    package = buffer.getvalue()

    assert not tool.installed()
    tool.unpack(package, tool.target_folder())
    assert tool.installed()
    names = sorted(str(p.relative_to(tool.target_folder())).replace("\\", "/") for p in tool.target_folder().rglob("*") if p.is_file())
    assert names == ["PSReadLine.psd1", "PSReadLine.psm1", "netstd/Polyfiller.dll"], names

    # a package that tries to write outside its folder is refused, and nothing from it is kept
    evil = io.BytesIO()
    with zipfile.ZipFile(evil, "w") as archive:
        archive.writestr("PSReadLine.psd1", "ok")
        archive.writestr("../outside.txt", "bad")
    attacked = Path(fake_local) / "attacked"
    try:
        tool.unpack(evil.getvalue(), attacked)
        raise AssertionError("an unsafe path was accepted")
    except SystemExit as stop:
        assert "unsafe path" in str(stop), stop
    assert not (Path(fake_local) / "outside.txt").exists() and not attacked.exists(), "a refused package leaves nothing behind"

    # the fingerprint check
    good = base64.b64encode(hashlib.sha512(package).digest()).decode("ascii")
    assert tool.fingerprint_ok(package, good)
    assert not tool.fingerprint_ok(package + b"x", good)

    # --check, the dry run and --undo
    assert tool.main(["--check"]) == 0
    assert tool.main([]) == 0, "the dry run only prints"
    assert tool.installed(), "the dry run changes nothing"
    assert tool.main(["--undo"]) == 0
    assert not tool.modules_folder().exists(), "undo removes the folder"
    assert tool.main(["--undo"]) == 0, "undo twice is fine"
print("psreadline installer OK")
print("psreadline tests passed")
