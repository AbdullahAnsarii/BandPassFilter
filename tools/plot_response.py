#!/usr/bin/env python3
"""Plot the magnitude response of both filters straight from the Verilog.

The coefficients are read out of the `parameter signed [...] coeffN = ...`
lines in the RTL, so the picture can never drift away from what is actually
synthesised. Writes docs/response.svg. Pure standard library: no numpy, no
matplotlib -- run it with any Python 3.

    python3 tools/plot_response.py
"""

import cmath
import math
import os
import re

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (file, coefficient word length, fraction length, title)
FILTERS = [
    ("bandpass.v", 6, 5, "bandpass_filter  (bandpass.v)", "11 taps, serial, 1 multiplier"),
    ("firbandpass.v", 14, 15, "basicfir  (firbandpass.v)", "51 taps, fully parallel"),
]

W, H = 940, 400
PAD_L, PAD_R, PAD_T, PAD_B = 62, 26, 52, 54
DB_MIN, DB_MAX = -80.0, 10.0
INK, GRID, AXIS = "#24292f", "#e4e8ed", "#8b949e"
CURVE = ["#0969da", "#8250df"]


def read_coefficients(path, width, frac):
    """Pull the fixed-point coefficients out of a Verilog source file."""
    text = open(path).read()
    found = {}
    for m in re.finditer(r"parameter signed \[\d+:\d+\] coeff(\d+) = \d+'b([01]+)", text):
        index, bits = int(m.group(1)), m.group(2)
        value = int(bits, 2)
        if bits[0] == "1":                      # two's complement
            value -= 1 << width
        found[index] = value / (1 << frac)
    if not found:
        raise SystemExit("no coefficients found in " + path)
    return [found[i] for i in sorted(found)]


def response(h, points=1400):
    """Magnitude of H(e^jw) in dB, for w from 0 to pi."""
    out = []
    for i in range(points + 1):
        w = math.pi * i / points
        mag = abs(sum(c * cmath.exp(-1j * w * n) for n, c in enumerate(h)))
        out.append((i / points, 20 * math.log10(mag) if mag > 1e-12 else DB_MIN - 20))
    return out


def panel(x0, y0, w, h, curve, colour, title, subtitle):
    """One labelled axes box with the response drawn in it."""
    def px(f):
        return x0 + f * w
    def py(db):
        db = max(DB_MIN, min(DB_MAX, db))
        return y0 + h - (db - DB_MIN) / (DB_MAX - DB_MIN) * h

    parts = [
        f'<text x="{x0}" y="{y0 - 26}" font-size="14" font-weight="600" fill="{INK}" '
        f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">{title}</text>',
        f'<text x="{x0}" y="{y0 - 9}" font-size="11.5" fill="{AXIS}" '
        f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">{subtitle}</text>',
    ]

    for db in range(int(DB_MIN), int(DB_MAX) + 1, 10):        # horizontal grid
        y = py(db)
        parts.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x0 + w}" y2="{y:.1f}" stroke="{GRID}" stroke-width="1"/>')
        parts.append(
            f'<text x="{x0 - 8}" y="{y + 4:.1f}" font-size="10.5" fill="{AXIS}" text-anchor="end" '
            f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">{db}</text>')

    for i in range(6):                                        # vertical grid
        f = i / 5
        x = px(f)
        parts.append(f'<line x1="{x:.1f}" y1="{y0}" x2="{x:.1f}" y2="{y0 + h}" stroke="{GRID}" stroke-width="1"/>')
        parts.append(
            f'<text x="{x:.1f}" y="{y0 + h + 17}" font-size="10.5" fill="{AXIS}" text-anchor="middle" '
            f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">{f / 2:.2f}</text>')

    parts.append(f'<line x1="{x0}" y1="{py(0):.1f}" x2="{x0 + w}" y2="{py(0):.1f}" stroke="{AXIS}" '
                 f'stroke-width="1" stroke-dasharray="4 3"/>')

    pts = " ".join(f"{px(f):.1f},{py(db):.1f}" for f, db in curve)
    parts.append(f'<polyline points="{pts}" fill="none" stroke="{colour}" stroke-width="2" '
                 f'stroke-linejoin="round" stroke-linecap="round"/>')
    parts.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="none" stroke="{AXIS}" stroke-width="1"/>')

    peak_f, peak_db = max(curve, key=lambda t: t[1])
    parts.append(
        f'<text x="{x0 + w - 6}" y="{y0 + 16}" font-size="10.5" fill="{AXIS}" text-anchor="end" '
        f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">'
        f'peak {peak_db:+.1f} dB at {peak_f / 2:.3f} fs</text>')
    return "\n".join(parts)


def main():
    panel_w = (W - PAD_L - PAD_R - 46) / 2
    panel_h = H - PAD_T - PAD_B
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<rect width="{W}" height="{H}" fill="#ffffff"/>',
    ]
    for i, (name, width, frac, title, subtitle) in enumerate(FILTERS):
        h = read_coefficients(os.path.join(HERE, name), width, frac)
        x0 = PAD_L + i * (panel_w + 46)
        svg.append(panel(x0, PAD_T, panel_w, panel_h, response(h), CURVE[i], title, subtitle))
        print(f"{name}: {len(h)} taps, DC {sum(h):+.4f}, sum|h| {sum(abs(c) for c in h):.4f}")

    svg.append(
        f'<text x="{W / 2:.0f}" y="{H - 12}" font-size="11.5" fill="{AXIS}" text-anchor="middle" '
        f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">'
        f'normalised frequency (x sampling rate)</text>')
    svg.append(
        f'<text x="16" y="{H / 2:.0f}" font-size="11.5" fill="{AXIS}" text-anchor="middle" '
        f'transform="rotate(-90 16 {H / 2:.0f})" '
        f'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">magnitude (dB)</text>')
    svg.append("</svg>")

    out = os.path.join(HERE, "docs", "response.svg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write("\n".join(svg) + "\n")
    print("wrote", os.path.relpath(out, HERE))


if __name__ == "__main__":
    main()
