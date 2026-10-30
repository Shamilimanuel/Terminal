"""Puts the newer PSReadLine (the typing helper that shows the live list of commands) where the Terminal profile can load it.

    python tools\\install_psreadline.py            shows what it would do (nothing is downloaded)
    python tools\\install_psreadline.py --apply    downloads it, checks the fingerprint, unpacks it
    python tools\\install_psreadline.py --check    says whether it is installed
    python tools\\install_psreadline.py --undo     deletes it again

It only ever writes to %LOCALAPPDATA%\\Terminal\\modules\\PSReadLine. Windows itself, its own PSReadLine and your project folder are never touched. The download is the official package from powershellgallery.com (about 230 KB);
its SHA-512 fingerprint is compared with the one the Gallery publishes before anything is unpacked.
"""
import base64
import hashlib
import os
import re
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = "2.4.5"
PACKAGE_URL = f"https://www.powershellgallery.com/api/v2/package/PSReadLine/{VERSION}"
FEED_URL = f"https://www.powershellgallery.com/api/v2/FindPackagesById()?id='PSReadLine'&$filter=Version%20eq%20'{VERSION}'"
SKIP = {"_rels/.rels", "PSReadLine.nuspec", "[Content_Types].xml", ".signature.p7s"}


def modules_folder():
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return Path(base) / "Terminal" / "modules" / "PSReadLine"


def target_folder():
    return modules_folder() / VERSION


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "terminal-install"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def installed():
    return (target_folder() / "PSReadLine.psd1").exists()


def unpack(package_bytes, target):
    """Unpacks the module files (not the NuGet bookkeeping) and refuses any path that would land outside target."""
    target = Path(target).resolve()
    with tempfile.TemporaryDirectory() as folder:
        package = Path(folder) / "package.zip"
        package.write_bytes(package_bytes)
        with zipfile.ZipFile(package) as archive:
            wanted = []
            for name in archive.namelist():
                if name in SKIP or name.startswith("package/") or name.endswith("/"):
                    continue
                destination = (target / name).resolve()
                if target != destination and target not in destination.parents:
                    raise SystemExit(f"Stopped: the package holds an unsafe path ({name}). Nothing was installed.")
                wanted.append((name, destination))
            for name, destination in wanted:                  # every path is checked first, so a bad package leaves nothing behind
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(name))


def fingerprint_ok(package_bytes, published):
    return base64.b64encode(hashlib.sha512(package_bytes).digest()).decode("ascii") == published


def main(argv):
    if "--check" in argv:
        print(f"Installed: {target_folder()}" if installed() else "Not installed.")
        return 0
    if "--undo" in argv:
        if modules_folder().exists():
            shutil.rmtree(modules_folder())
            print(f"Deleted {modules_folder()}. Open a new terminal window.")
        else:
            print("Nothing to undo.")
        return 0
    if "--apply" not in argv:
        print(f"Would download PSReadLine {VERSION} from powershellgallery.com (about 230 KB),")
        print("compare its SHA-512 fingerprint with the Gallery's, and unpack it into:")
        print(f"  {target_folder()}")
        print("Add --apply to do it. Add --undo to remove it later.")
        return 0
    if installed():
        print(f"Already installed: {target_folder()}")
        return 0
    print("Downloading ...")
    package_bytes = fetch(PACKAGE_URL)
    feed = fetch(FEED_URL).decode("utf-8", "replace")
    found = re.search(r"<d:PackageHash[^>]*>([^<]+)</d:PackageHash>", feed)
    if not found:
        print("Stopped: could not read the Gallery's fingerprint, so the download cannot be checked. Nothing was installed.")
        return 1
    if not fingerprint_ok(package_bytes, found.group(1).strip()):
        print("Stopped: the fingerprint does not match. Nothing was installed.")
        return 1
    unpack(package_bytes, target_folder())
    print(f"Installed {VERSION} in {target_folder()}. Open a new terminal window (or type reload).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
