"""Windows PowerShell 5.1 reads a .ps1 file as plain Windows text unless it starts with a "byte order mark".
Without it, characters like arrows show up as garbage. This adds the mark to every .ps1 in the project (safe to repeat).
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
for path in sorted(root.rglob("*.ps1")):
    data = path.read_bytes()
    if not data.startswith(b"\xef\xbb\xbf"):
        path.write_bytes(b"\xef\xbb\xbf" + data)
        print("added mark:", path.relative_to(root))
