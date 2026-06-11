#!/usr/bin/env python3
"""
Generates all macOS distribution assets for Mick Jigger from MJ.png.

Outputs:
  MickJigger/Assets.xcassets/AppIcon.appiconset/  — 7 PNG sizes + Contents.json
  MickJigger/Assets.xcassets/menubar_*.imageset/  — 4 PDF vector template images
"""

import os
import json
from PIL import Image
import Quartz.CoreGraphics as CG

SRC = "/Users/dmirtyisme/Documents/Claude/Projects/L3RA WEBSITE/MJ.png"
PROJ = "/Users/dmirtyisme/Documents/Claude/Projects/mick-jigger/MickJigger"
XCASSETS = os.path.join(PROJ, "Assets.xcassets")

# ── helpers ───────────────────────────────────────────────────────────────────

def pdf_context(path: str, size: float):
    pb = path.encode("utf-8")
    url = CG.CFURLCreateFromFileSystemRepresentation(None, pb, len(pb), False)
    return CG.CGPDFContextCreateWithURL(url, CG.CGRectMake(0, 0, size, size), None)


# ── 1. App Icon ───────────────────────────────────────────────────────────────

ICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]

def generate_app_icons():
    out_dir = os.path.join(XCASSETS, "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")

    for size in ICON_SIZES:
        img = src.resize((size, size), Image.LANCZOS)
        dest = os.path.join(out_dir, f"icon_{size}.png")
        img.save(dest, "PNG")
        print(f"  icon_{size}.png")

    # Contents.json — one entry per (pt, scale) combination macOS expects.
    images = [
        {"filename": "icon_16.png",   "idiom": "mac", "scale": "1x", "size": "16x16"},
        {"filename": "icon_32.png",   "idiom": "mac", "scale": "2x", "size": "16x16"},
        {"filename": "icon_32.png",   "idiom": "mac", "scale": "1x", "size": "32x32"},
        {"filename": "icon_64.png",   "idiom": "mac", "scale": "2x", "size": "32x32"},
        {"filename": "icon_128.png",  "idiom": "mac", "scale": "1x", "size": "128x128"},
        {"filename": "icon_256.png",  "idiom": "mac", "scale": "2x", "size": "128x128"},
        {"filename": "icon_256.png",  "idiom": "mac", "scale": "1x", "size": "256x256"},
        {"filename": "icon_512.png",  "idiom": "mac", "scale": "2x", "size": "256x256"},
        {"filename": "icon_512.png",  "idiom": "mac", "scale": "1x", "size": "512x512"},
        {"filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
    ]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(out_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print("  Contents.json")


# ── 2. Menu bar PDF template images ──────────────────────────────────────────
#
# Each PDF is a 22×22 pt canvas drawn in black — Template Image mode lets
# macOS invert/tint for light and dark menu bars automatically.
#
# Mouse geometry on a 22×22 grid (pt):
#   body oval:          (3, 2, 16, 18)     ← x, y, w, h
#   button divider:     horizontal at y=8  (inside oval, bottom-half = scroll area)
#   scroll wheel:       (9, 9, 4, 5)
#   monitoring badge:   circle at (17, 3.5, 4, 4)

S = 22.0   # canvas size (pt)

def draw_mouse(ctx, filled=False, badge_rgb=None):
    """Draw a minimal mouse icon into an already-started PDF page."""

    body = CG.CGRectMake(3, 2, 16, 18)
    lw_outer = 1.4
    lw_inner = 0.9

    if filled:
        # Solid body
        CG.CGContextSetRGBFillColor(ctx, 0, 0, 0, 1)
        CG.CGContextFillEllipseInRect(ctx, body)

        # White button-divider line (clipped to oval)
        CG.CGContextSaveGState(ctx)
        CG.CGContextAddEllipseInRect(ctx, body)
        CG.CGContextClip(ctx)
        CG.CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1)
        CG.CGContextSetLineWidth(ctx, lw_inner)
        CG.CGContextMoveToPoint(ctx, 3, 10)
        CG.CGContextAddLineToPoint(ctx, 19, 10)
        CG.CGContextStrokePath(ctx)
        CG.CGContextRestoreGState(ctx)

        # White scroll wheel punch-out
        CG.CGContextSetRGBFillColor(ctx, 1, 1, 1, 1)
        CG.CGContextFillRect(ctx, CG.CGRectMake(9.5, 11, 3, 5))

    else:
        # Outline body
        CG.CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1)
        CG.CGContextSetLineWidth(ctx, lw_outer)
        CG.CGContextStrokeEllipseInRect(ctx, body)

        # Button-divider line, clipped to oval
        CG.CGContextSaveGState(ctx)
        CG.CGContextAddEllipseInRect(ctx, body)
        CG.CGContextClip(ctx)
        CG.CGContextSetLineWidth(ctx, lw_inner)
        CG.CGContextMoveToPoint(ctx, 3, 10)
        CG.CGContextAddLineToPoint(ctx, 19, 10)
        CG.CGContextStrokePath(ctx)
        # Scroll-wheel outline rect
        CG.CGContextSetLineWidth(ctx, lw_inner)
        CG.CGContextStrokeRect(ctx, CG.CGRectMake(9.5, 11, 3, 5))
        CG.CGContextRestoreGState(ctx)

    # Optional badge dot (for monitoring state)
    if badge_rgb:
        r, g, b = badge_rgb
        CG.CGContextSetRGBFillColor(ctx, r, g, b, 1)
        CG.CGContextFillEllipseInRect(ctx, CG.CGRectMake(16.5, 3, 4, 4))


def generate_menubar_pdfs():
    variants = [
        ("menubar_inactive",    False, None),
        ("menubar_monitoring",  False, (0.0, 0.0, 0.0)),   # dot drawn black; macOS tints
        ("menubar_active",      True,  None),
        ("menubar_active_auto", True,  None),
    ]
    for name, filled, badge in variants:
        out_dir = os.path.join(XCASSETS, f"{name}.imageset")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, f"{name}.pdf")

        ctx = pdf_context(path, S)
        CG.CGContextBeginPage(ctx, None)
        draw_mouse(ctx, filled=filled, badge_rgb=badge)
        CG.CGContextEndPage(ctx)
        CG.CGPDFContextClose(ctx)

        # Contents.json — single PDF covers all densities; Template rendering
        # intent enables light/dark menu bar tinting.
        contents = {
            "images": [{
                "filename": f"{name}.pdf",
                "idiom": "universal",
                "scale": "1x"
            }],
            "info": {"author": "xcode", "version": 1},
            "properties": {
                "rendering-intent": "template",
                "preserves-vector-representation": True
            }
        }
        with open(os.path.join(out_dir, "Contents.json"), "w") as f:
            json.dump(contents, f, indent=2)
        print(f"  {name}.pdf  ({os.path.getsize(path)} bytes)")


# ── 3. Root Contents.json ─────────────────────────────────────────────────────

def write_root_contents():
    path = os.path.join(XCASSETS, "Contents.json")
    with open(path, "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("App icons:")
    generate_app_icons()
    print("\nMenu bar PDFs:")
    generate_menubar_pdfs()
    write_root_contents()
    print("\nAll assets written to:", XCASSETS)
