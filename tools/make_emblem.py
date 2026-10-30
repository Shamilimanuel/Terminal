"""Draws the original emblem and the title picture.

    python tools\\make_emblem.py       writes art\\rune-source.png (the rune-circle emblem, 512 x 512)
                                      and   art\\title-source.png    (small sigil + TERMINAL, 880 x 1120, amber for Administrator)

Needs Playwright (pip install playwright; playwright install chromium). Everything is drawn from plain geometry
(circles, lines, a hexagon and a letter T), so there is nothing here that belongs to anyone else.
Then run, in this order:
    python tools\\make_logo.py                      art\\elevated.ans, art\\elevated-small.ans  (text-art title, Administrator)
    python tools\\image_to_ansi.py art\\rune-source.png art\\rune.ans 56           (and the -small / -ascii / -blocks files)
    python tools\\make_sixel.py                     the real-picture (Sixel) files
"""
import math
from pathlib import Path

ART = Path(__file__).resolve().parent.parent / "art"

CYAN, ICE, DEEP = "#5fd4ff", "#dff3ff", "#2a9fd0"
AMBER, AMBER_HI, AMBER_DEEP = "#ffb36b", "#ffe2b8", "#e0782a"
CURSOR = "#ff8a3d"

# small geometric runes, each drawn in a 40 x 40 box (x across the ring, y outward); not letters of any real script
GLYPHS = [
    "M20 6 V34",                                              # bar
    "M10 10 L20 20 L30 10 M10 24 L20 34 L30 24",              # double chevron
    "M20 6 L33 20 L20 34 L7 20 Z",                            # diamond
    "M10 34 V18 M20 34 V6 M30 34 V25",                        # three rising bars
    "M20 22 V35 M20 21 m-8 -8 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0",   # ring on a stem
    "M9 8 L23 20 L9 32 M27 34 H36",                           # prompt: > and a cursor line
    "M13 6 H6 V34 H13 M27 6 H34 V34 H27",                     # square brackets
]
DOTS = [[(20, 4), (20, 36)], [], [(20, 20)], [], [], [], [(20, 20)]]
ORDER = [5, 3, 2, 1, 4, 6, 0, 3, 5, 1, 2, 4, 6, 0, 3, 1]   # 16 runes, never the same one twice in a row


def ring_runes(cx, cy, radius, size, count, stroke):
    parts = []
    for i in range(count):
        angle = 360.0 / count * i
        g = ORDER[i % len(ORDER)]
        scale = size / 40.0
        parts.append(f'<g transform="translate({cx} {cy}) rotate({angle}) translate(0 {-radius - size / 2}) scale({scale}) translate(-20 -20)">'
                     f'<path d="{GLYPHS[g]}" stroke-width="{stroke / scale:.2f}"/>'
                     + "".join(f'<circle cx="{x}" cy="{y}" r="{stroke / scale * 0.75:.2f}" fill="url(#cy)" stroke="none"/>' for x, y in DOTS[g])
                     + "</g>")
    return "".join(parts)


def ticks(cx, cy, r1, r2, count, skip_every):
    out = []
    for i in range(count):
        a = math.radians(360.0 / count * i)
        r_end = r2 + (6 if i % skip_every == 0 else 0)
        out.append(f"M{cx + r1 * math.sin(a):.1f} {cy - r1 * math.cos(a):.1f} L{cx + r_end * math.sin(a):.1f} {cy - r_end * math.cos(a):.1f}")
    return " ".join(out)


def hexagon(cx, cy, r, rotate=0):
    pts = [(cx + r * math.cos(math.radians(60 * k + rotate)), cy + r * math.sin(math.radians(60 * k + rotate))) for k in range(6)]
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"


def arc(cx, cy, r, start, end):
    a0, a1 = math.radians(start), math.radians(end)
    x0, y0 = cx + r * math.sin(a0), cy - r * math.cos(a0)
    x1, y1 = cx + r * math.sin(a1), cy - r * math.cos(a1)
    large = 1 if (end - start) % 360 > 180 else 0
    return f"M{x0:.1f} {y0:.1f} A{r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}"


def sigil(cx, cy, scale, hi, mid, deep, cursor):
    """The rune-circle with a T at its heart. Drawn around (cx, cy); scale 1 = 512 px wide."""
    s = scale
    nodes = "".join(f'<circle cx="{cx + 160 * s * math.sin(math.radians(a)):.1f}" cy="{cy - 160 * s * math.cos(math.radians(a)):.1f}" r="{11 * s:.1f}" fill="{deep}" stroke="{hi}" stroke-width="{4 * s:.1f}"/>'
                    for a in (0, 120, 240))
    return f"""
  <g fill="none" stroke="url(#cy)" stroke-linecap="round" stroke-linejoin="round" filter="url(#glow)">
    <circle cx="{cx}" cy="{cy}" r="{236 * s}" stroke-width="{4 * s}" opacity=".9"/>
    <path d="{ticks(cx, cy, 222 * s, 214 * s, 96, 4)}" stroke-width="{3 * s}" opacity=".75"/>
    <circle cx="{cx}" cy="{cy}" r="{172 * s}" stroke-width="{4 * s}" opacity=".95"/>
    {ring_runes(cx, cy, 176 * s, 46 * s, 16, 7.5 * s)}
    <path d="{arc(cx, cy, 160 * s, 12, 108)} {arc(cx, cy, 160 * s, 132, 228)} {arc(cx, cy, 160 * s, 252, 348)}" stroke-width="{6 * s}" opacity="0"/>
    <circle cx="{cx}" cy="{cy}" r="{140 * s}" stroke-width="{3 * s}" opacity=".65" stroke-dasharray="{2 * s} {12 * s}"/>
    <path d="{hexagon(cx, cy, 118 * s, 30)}" stroke-width="{8 * s}"/>
    <path d="{hexagon(cx, cy, 96 * s, 30)}" stroke-width="{2.5 * s}" opacity=".6"/>
    <path d="M{cx - 62 * s} {cy - 44 * s} H{cx + 62 * s} M{cx} {cy - 44 * s} V{cy + 52 * s}" stroke-width="{26 * s}" stroke-linecap="butt"/>
    <path d="M{cx - 62 * s} {cy - 44 * s} H{cx + 62 * s} M{cx} {cy - 44 * s} V{cy + 52 * s}" stroke="{hi}" stroke-width="{7 * s}" stroke-linecap="butt" opacity=".85"/>
  </g>
  <g filter="url(#glow)">{nodes}
    <rect x="{cx + 24 * s}" y="{cy + 40 * s}" width="{34 * s}" height="{12 * s}" rx="{2 * s}" fill="{cursor}"/>
  </g>"""


def svg_wrap(width, height, body, mid, hi, deep):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<defs>
  <linearGradient id="cy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{hi}"/><stop offset=".45" stop-color="{mid}"/><stop offset="1" stop-color="{deep}"/></linearGradient>
  <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
    <feGaussianBlur in="SourceGraphic" stdDeviation="3.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>
<rect width="100%" height="100%" fill="#000"/>
{body}
</svg>"""


def emblem_svg():
    return svg_wrap(512, 512, sigil(256, 256, 1.0, ICE, CYAN, DEEP, CURSOR), CYAN, ICE, DEEP)


def title_svg():
    """Small amber sigil, then TERMINAL in wide-set capitals between two rules (this is the Administrator picture)."""
    w, h = 880, 1120
    body = sigil(440, 410, 0.92, AMBER_HI, AMBER, AMBER_DEEP, "#ff6b81")
    letters = "TERMINAL"
    return svg_wrap(w, h, body + f"""
  <g filter="url(#glow)" fill="url(#cy)" font-family="Bahnschrift, 'Segoe UI Semibold', 'Segoe UI', sans-serif" text-anchor="middle">
    <text x="453" y="850" font-size="112" font-weight="700" letter-spacing="26">{letters}</text>
  </g>
  <g filter="url(#glow)" stroke="url(#cy)" stroke-width="5" stroke-linecap="round">
    <path d="M150 918 H370 M510 918 H730" opacity=".85"/>
    <path d="M440 906 L452 918 L440 930 L428 918 Z" fill="{AMBER}"/>
  </g>
  <g fill="{AMBER_HI}" font-family="Bahnschrift, 'Segoe UI', sans-serif" text-anchor="middle" opacity=".8">
    <text x="448" y="985" font-size="38" letter-spacing="16">ELEVATED</text>
  </g>""", AMBER, AMBER_HI, AMBER_DEEP)


def render(svg_text, path, width, height):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.set_content(f"<style>html,body{{margin:0;background:#000}}</style>{svg_text}")
        page.screenshot(path=str(path))
        browser.close()


if __name__ == "__main__":
    ART.mkdir(exist_ok=True)
    render(emblem_svg(), ART / "rune-source.png", 512, 512)
    render(title_svg(), ART / "title-source.png", 880, 1120)
    (ART / "emblem.svg").write_text(emblem_svg(), encoding="utf-8")
    print("wrote rune-source.png, title-source.png, emblem.svg")
