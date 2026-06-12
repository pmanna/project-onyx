#!/usr/bin/env python3
"""
gen_icon.py — Generate Onyx app icon PNGs (1024×1024).

Usage (run from project root):
    python3 scripts/gen_icon.py

Outputs three files into Onyx/Onyx/Assets.xcassets/AppIcon.appiconset/:
    AppIcon~light.png   — dark obsidian bg, silver gem (light home screen)
    AppIcon~dark.png    — same design, slightly deeper bg (dark home screen)
    AppIcon~tinted.png  — greyscale version (iOS applies system tint on top)

Requires Pillow (pip install pillow). If Pillow is missing the script exits
with a clear error message.
"""

import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("ERROR: Pillow not found. Install it with:  pip install pillow")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Output path — relative to project root
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(
    PROJECT_ROOT,
    "Onyx", "Onyx", "Assets.xcassets",
    "AppIcon.appiconset"
)

SIZE = 1024
CORNER_RADIUS = int(SIZE * 0.22)   # matches iOS 17+ icon rounding

# ---------------------------------------------------------------------------
# Color palettes
# ---------------------------------------------------------------------------
LIGHT_BG   = (11,  11,  18,  255)   # deep obsidian #0B0B12
DARK_BG    = (7,   7,   12,  255)   # near-black   #07070C
TINTED_BG  = (30,  30,  30,  255)   # neutral dark for tinted variant

GEM_TOP    = (234, 235, 240, 255)   # bright silver highlight
GEM_MID    = (180, 182, 190, 255)   # mid silver
GEM_LOW    = (110, 112, 122, 255)   # shadowed silver

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    """Return an RGBA mask with a rounded-rect 'cookie-cutter'."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def gem_polygon(size: int, scale: float = 0.52):
    """
    Return list of (x, y) pixel coords for the Onyx gem silhouette.
    Matches DiamondShape in OnyxTheme.swift.

    Crown (top 42 % of height), pavilion (bottom 58 % to culet).
    """
    gem_size = size * scale
    ox = (size - gem_size) / 2  # offset to centre
    oy = (size - gem_size) / 2
    w, h = gem_size, gem_size

    pts = [
        (ox + w * 0.50, oy + h * 0.00),   # top apex
        (ox + w * 0.80, oy + h * 0.28),   # upper-right shoulder
        (ox + w * 1.00, oy + h * 0.42),   # right girdle
        (ox + w * 0.80, oy + h * 0.58),   # lower-right shoulder
        (ox + w * 0.50, oy + h * 1.00),   # bottom culet
        (ox + w * 0.20, oy + h * 0.58),   # lower-left shoulder
        (ox + w * 0.00, oy + h * 0.42),   # left girdle
        (ox + w * 0.20, oy + h * 0.28),   # upper-left shoulder
    ]
    # Table line endpoints (for stroke)
    table_left  = (ox + w * 0.20, oy + h * 0.42)
    table_right = (ox + w * 0.80, oy + h * 0.42)
    return pts, table_left, table_right


def draw_gem(img: Image.Image, palette: tuple, antialias: int = 4):
    """Draw the gem on `img` (RGBA, SIZE×SIZE) with optional supersampling."""
    aa = antialias
    big = SIZE * aa
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)

    pts, tl, tr = gem_polygon(big, scale=0.52)

    # Gradient simulation via three bands
    top_pts   = [pts[0], pts[1], pts[7]]  # crown top triangle
    mid_pts   = [pts[7], pts[1], pts[2], pts[6]]  # crown wings
    lower_pts = [pts[2], pts[3], pts[4], pts[5], pts[6]]  # pavilion

    d.polygon(top_pts,   fill=palette[0])
    d.polygon(mid_pts,   fill=palette[1])
    d.polygon(lower_pts, fill=palette[2])

    # Table line (same colour as mid band)
    d.line([tl, tr], fill=palette[1], width=aa * 2)

    # Outer outline — subtle, slightly lighter
    d.polygon(pts, outline=(200, 202, 210, 180), width=aa)

    gem = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    img.alpha_composite(gem)


def make_icon(bg_color: tuple, grayscale: bool = False) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # 1. Background with rounded corners
    bg = Image.new("RGBA", (SIZE, SIZE), bg_color)
    mask = rounded_rect_mask(SIZE, CORNER_RADIUS)
    img.paste(bg, mask=mask)

    # 2. Gem
    palette = (GEM_TOP, GEM_MID, GEM_LOW)
    draw_gem(img, palette)

    # 3. Greyscale pass for the tinted variant
    if grayscale:
        grey = img.convert("LA").convert("RGBA")
        img = grey

    return img


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    variants = [
        ("AppIcon~light.png",  LIGHT_BG,  False),
        ("AppIcon~dark.png",   DARK_BG,   False),
        ("AppIcon~tinted.png", TINTED_BG, True),
    ]

    for filename, bg, grey in variants:
        path = os.path.join(OUT_DIR, filename)
        icon = make_icon(bg, grayscale=grey)
        icon.save(path, "PNG", optimize=True)
        kb = os.path.getsize(path) // 1024
        print(f"  ✓  {filename}  ({kb} KB)  →  {path}")

    print("\nDone. Rebuild the Xcode project to pick up the new icons.")


if __name__ == "__main__":
    main()
