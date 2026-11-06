"""Generates the TV Remote logo concepts and final artwork (pure geometry, no dependencies).

Run: python design/logo/build_logo.py
"""
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))
BODY = "#1A2030"
KEY = "#283044"
LED = "#F0B23E"
TEXT = "#E8EBF2"
C = 128.0  # canvas centre (256 x 256)


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def ring_segment(r_in, r_out, mid_deg, gap, half=45, cx=C, cy=C):
    """Annular quarter segment centred on mid_deg, bounded by straight cuts of constant width `gap`
    along the diagonals at mid±45°. SVG angles: 0° = right, +90° = down."""
    def cut_point(diag_deg, r, side):
        # Point on circle r lying on the line parallel to the diagonal, offset by gap/2 toward the segment.
        th = math.radians(diag_deg)
        u = (math.cos(th), math.sin(th))
        n = (-math.sin(th), math.cos(th))
        h = gap / 2 * side
        t = math.sqrt(r * r - h * h)
        return cx + t * u[0] + h * n[0], cy + t * u[1] + h * n[1]

    a0, a1 = mid_deg - half, mid_deg + half
    large = 1 if 2 * half > 180 else 0
    # Offset toward the inside of the segment: for the start diagonal, +normal; for the end, -normal.
    o0 = cut_point(a0, r_out, +1)
    o1 = cut_point(a1, r_out, -1)
    i1 = cut_point(a1, r_in, -1)
    i0 = cut_point(a0, r_in, +1)
    return (
        f"M{f(o0[0])} {f(o0[1])}"
        f"A{f(r_out)} {f(r_out)} 0 {large} 1 {f(o1[0])} {f(o1[1])}"
        f"L{f(i1[0])} {f(i1[1])}"
        f"A{f(r_in)} {f(r_in)} 0 {large} 0 {f(i0[0])} {f(i0[1])}Z"
    )


def circle(r, cx=C, cy=C):
    return f"M{f(cx - r)} {f(cy)}a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0Z"


def svg(body, title, bg=None):
    rect = f'<rect width="256" height="256" fill="{bg}"/>' if bg else ""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">'
        f"<title>{title}</title>{rect}{body}</svg>\n"
    )


def write(name, content):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    return path


# ---------- Concept A: Pressed key — four-key ring D-pad, right key lit, OK dot.
# Geometry: ring r 58..104, cuts 11 wide on the diagonals, OK dot r 34 (gap to ring = 24).
A_RIN, A_ROUT, A_GAP, A_DOT = 58, 104, 11, 34


def concept_a(lit=None, other="#000", dot="#000"):
    """v2: one key (right) splits from an unbroken 3/4 ring — a single pressed key, not four equal
    segments (v1 read as a life buoy in one colour)."""
    key = lit or other
    return (
        f'<path fill="{other}" d="{ring_segment(A_RIN, A_ROUT, 180, A_GAP, half=135)}"/>'
        f'<path fill="{key}" d="{ring_segment(A_RIN, A_ROUT, 0, A_GAP)}"/>'
        f'<path fill="{dot}" d="{circle(A_DOT)}"/>'
    )


def concept_a_v1(lit=None, other="#000", dot="#000"):
    parts = []
    for mid in (0, 90, 180, 270):
        color = lit if (lit and mid == 0) else other
        parts.append(f'<path fill="{color}" d="{ring_segment(A_RIN, A_ROUT, mid, A_GAP)}"/>')
    parts.append(f'<path fill="{dot}" d="{circle(A_DOT)}"/>')
    return "".join(parts)


# ---------- Concept B: Screen is the button — rounded screen frame, OK disc in the middle.
def concept_b(color="#000"):
    outer = "M40 52h176a28 28 0 0 1 28 28v96a28 28 0 0 1-28 28H40a28 28 0 0 1-28-28V80a28 28 0 0 1 28-28Z"
    inner = "M44 74h168a10 10 0 0 1 10 10v88a10 10 0 0 1-10 10H44a10 10 0 0 1-10-10V84a10 10 0 0 1 10-10Z"
    return f'<path fill="{color}" fill-rule="evenodd" d="{outer}{inner}"/><path fill="{color}" d="{circle(36)}"/>'


# ---------- Concept C: Standby — heavy ring with a standby LED dot inside, top-right.
def concept_c(color="#000", led="#000"):
    ring = circle(104) + circle(62)
    return (
        f'<path fill="{color}" fill-rule="evenodd" d="{ring}"/>'
        f'<path fill="{led}" d="{circle(16, C + 30, C - 30)}"/>'
    )


if __name__ == "__main__":
    os.makedirs(os.path.join(OUT, "concepts"), exist_ok=True)
    write("concepts/a-pressed-key-v1.svg", svg(concept_a_v1(), "TV Remote concept A v1"))
    write("concepts/a-pressed-key.svg", svg(concept_a(), "TV Remote concept A"))
    write("concepts/b-screen-button.svg", svg(concept_b(), "TV Remote concept B"))
    write("concepts/c-standby.svg", svg(concept_c(), "TV Remote concept C"))

    # Final artwork (concept A).
    write("tv-remote-symbol.svg", svg(concept_a(lit=LED, other=TEXT, dot=TEXT), "TV Remote"))
    write("tv-remote-symbol-black.svg", svg(concept_a(), "TV Remote (black)"))
    write("tv-remote-symbol-white.svg", svg(concept_a(other="#fff", dot="#fff"), "TV Remote (white)"))
    # App icon: full-bleed body colour, mark scaled to ~62% so it sits inside every platform mask.
    s = 0.62
    t = C * (1 - s)
    mark = f'<g transform="translate({f(t)} {f(t)}) scale({s})">{concept_a(lit=LED, other=TEXT, dot=TEXT)}</g>'
    write("app-icon.svg", svg(mark, "TV Remote app icon", bg=BODY))
    # Android adaptive foreground: transparent, full-size mark (the generator insets it).
    s2 = 0.72  # with the generator's 16% inset the mark spans ~40% of the 108dp canvas, ~60% of the visible mask
    t2 = C * (1 - s2)
    fg = f'<g transform="translate({f(t2)} {f(t2)}) scale({s2})">{concept_a(lit=LED, other=TEXT, dot=TEXT)}</g>'
    write("adaptive-foreground.svg", svg(fg, "TV Remote adaptive foreground"))
    # Android 13 themed (monochrome) icon layer.
    mono = f'<g transform="translate({f(t2)} {f(t2)}) scale({s2})">{concept_a()}</g>'
    write("adaptive-monochrome.svg", svg(mono, "TV Remote monochrome"))
    print("ok")
