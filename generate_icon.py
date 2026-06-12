#!/usr/bin/env python3
"""
generate_icon.py — Onyx app icon generator

Produces three 1024×1024 PNG variants required by iOS 18:
  AppIcon~light.png   — default / light mode
  AppIcon~dark.png    — dark mode
  AppIcon~tinted.png  — greyscale mask for user-tinted icons

Design: Neural Chat
  Deep indigo gradient background, white speech bubble, three teal
  neural nodes connected by lines, communicating "local on-device AI".

Run with:
  /opt/homebrew/bin/python3.13 generate_icon.py

Requires Pillow >= 10 and numpy >= 1.24.
"""

import json
import math
import os
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("Install Pillow and numpy: pip install pillow numpy")

SIZE   = 1024
ASSETS = os.path.join(os.path.dirname(__file__),
                      "Onyx", "Onyx",
                      "Assets.xcassets", "AppIcon.appiconset")

# ── Colour palette ────────────────────────────────────────────────────────────

TEAL        = (0x00, 0xD4, 0xFF, 255)
TEAL_GLOW   = (0x00, 0xD4, 0xFF, 153)   # 60 % opacity
WHITE       = (255, 255, 255, 255)
SHADOW      = (0,   0,   0,   89)       # black 35 %

GRAD_LIGHT_CENTRE = (0x1B, 0x0D, 0x55)
GRAD_LIGHT_EDGE   = (0x06, 0x02, 0x12)
GRAD_DARK_CENTRE  = (0x08, 0x02, 0x10)
GRAD_DARK_EDGE    = (0x02, 0x00, 0x08)

GREY_NODE = (200, 200, 200, 255)
GREY_LINE = (160, 160, 160, 255)

# ── Geometry ─────────────────────────────────────────────────────────────────

BUBBLE_X, BUBBLE_Y = 187, 152
BUBBLE_W, BUBBLE_H = 650, 560
BUBBLE_R            = 88
TAIL = [(282, 712), (382, 712), (302, 782)]

# Equilateral triangle of neural nodes, centred at (512, 420)
NODE_CX, NODE_CY = 512, 420
NODE_R_LAYOUT    = 138   # layout radius
NODE_RADIUS      = 24
LINE_W           = 8
GLOW_RADIUS      = 40

_a = [270, 30, 150]   # angles for top, bottom-right, bottom-left (degrees)
NODES = [
    (int(NODE_CX + NODE_R_LAYOUT * math.cos(math.radians(a))),
     int(NODE_CY + NODE_R_LAYOUT * math.sin(math.radians(a))))
    for a in _a
]

# ── Helpers ──────────────────────────────────────────────────────────────────

def radial_gradient(centre_rgb, edge_rgb):
    """Return a 1024×1024 RGBA numpy array with a radial gradient."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    cx, cy = SIZE / 2, SIZE / 2
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    max_dist = math.sqrt(2) * SIZE / 2
    t = np.clip(dist / max_dist, 0, 1)[..., np.newaxis]
    c = np.array(centre_rgb, dtype=float)
    e = np.array(edge_rgb,   dtype=float)
    rgb = (c * (1 - t) + e * t).astype(np.uint8)
    alpha = np.full((SIZE, SIZE, 1), 255, dtype=np.uint8)
    return np.concatenate([rgb, alpha], axis=2)


def rounded_rect_mask(x, y, w, h, r, size=SIZE):
    """Return a greyscale PIL Image with a filled rounded rectangle."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=255)
    return mask


def draw_bubble(canvas: Image.Image, node_colour, line_colour, with_glow: bool):
    """Composite the speech bubble, connector lines, and neural nodes onto canvas."""

    # ── Shadow (soft drop shadow behind bubble) ──────────────────────────────
    if with_glow:
        shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow_layer)
        sd.rounded_rectangle(
            [BUBBLE_X, BUBBLE_Y + 8, BUBBLE_X + BUBBLE_W, BUBBLE_Y + BUBBLE_H + 8],
            radius=BUBBLE_R, fill=SHADOW
        )
        sd.polygon([(p[0], p[1] + 8) for p in TAIL], fill=SHADOW)
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=16))
        canvas = Image.alpha_composite(canvas, shadow_layer)

    # ── Bubble body ──────────────────────────────────────────────────────────
    bubble_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bubble_layer)
    bd.rounded_rectangle(
        [BUBBLE_X, BUBBLE_Y, BUBBLE_X + BUBBLE_W, BUBBLE_Y + BUBBLE_H],
        radius=BUBBLE_R, fill=WHITE
    )
    bd.polygon(TAIL, fill=WHITE)
    canvas = Image.alpha_composite(canvas, bubble_layer)

    # ── Node glow ────────────────────────────────────────────────────────────
    if with_glow:
        glow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_layer)
        gr = GLOW_RADIUS
        for nx, ny in NODES:
            gd.ellipse([nx - gr, ny - gr, nx + gr, ny + gr], fill=TEAL_GLOW)
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=12))
        canvas = Image.alpha_composite(canvas, glow_layer)

    # ── Connector lines ──────────────────────────────────────────────────────
    line_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line_layer)
    pairs = [(NODES[0], NODES[1]), (NODES[1], NODES[2]), (NODES[0], NODES[2])]
    for (ax, ay), (bx, by) in pairs:
        ld.line([(ax, ay), (bx, by)], fill=line_colour, width=LINE_W)
    canvas = Image.alpha_composite(canvas, line_layer)

    # ── Neural nodes ─────────────────────────────────────────────────────────
    node_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    nd = ImageDraw.Draw(node_layer)
    nr = NODE_RADIUS
    for nx, ny in NODES:
        nd.ellipse([nx - nr, ny - nr, nx + nr, ny + nr], fill=node_colour)
    canvas = Image.alpha_composite(canvas, node_layer)

    return canvas


# ── Variant builders ─────────────────────────────────────────────────────────

def make_light():
    arr = radial_gradient(GRAD_LIGHT_CENTRE, GRAD_LIGHT_EDGE)
    bg = Image.fromarray(arr, "RGBA")
    return draw_bubble(bg, TEAL, TEAL, with_glow=True)


def make_dark():
    arr = radial_gradient(GRAD_DARK_CENTRE, GRAD_DARK_EDGE)
    bg = Image.fromarray(arr, "RGBA")
    return draw_bubble(bg, TEAL, TEAL, with_glow=True)


def make_tinted():
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    return draw_bubble(bg, GREY_NODE, GREY_LINE, with_glow=False)


# ── Contents.json patcher ────────────────────────────────────────────────────

def patch_contents_json(folder):
    path = os.path.join(folder, "Contents.json")
    with open(path) as f:
        data = json.load(f)

    for img in data["images"]:
        appearances = img.get("appearances", [])
        if not appearances:
            img["filename"] = "AppIcon~light.png"
        else:
            val = appearances[0].get("value", "")
            if val == "dark":
                img["filename"] = "AppIcon~dark.png"
            elif val == "tinted":
                img["filename"] = "AppIcon~tinted.png"

    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("✓ Updated Contents.json")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(ASSETS, exist_ok=True)

    variants = [
        ("AppIcon~light.png",  make_light),
        ("AppIcon~dark.png",   make_dark),
        ("AppIcon~tinted.png", make_tinted),
    ]
    for filename, builder in variants:
        img = builder()
        # Convert to RGB for PNG output (no alpha channel in final icons;
        # iOS clips to the squircle shape itself).
        out = img.convert("RGB")
        dest = os.path.join(ASSETS, filename)
        out.save(dest, "PNG", optimize=False)
        print(f"✓ Wrote {filename}  ({out.size[0]}×{out.size[1]} px)")

    patch_contents_json(ASSETS)
    print("\nDone. Open Xcode → Assets.xcassets → AppIcon to verify.")


if __name__ == "__main__":
    main()
