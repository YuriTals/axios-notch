#!/usr/bin/env python3
"""Draws Packaging/dmg-background.png: the light backdrop of the installer window (Finder draws
the icon names in dark grey whatever the appearance, so a dark one is unreadable), with an
arrow from the app to the Applications shortcut. 2x pixels with 144 dpi, so Finder shows it
sharp on Retina at the window's 660 x 400 points. The result is committed; run this only
when the artwork changes (needs Pillow)."""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H, S = 660, 400, 2

img = Image.new("RGB", (W * S, H * S))
px = img.load()
for y in range(H * S):                                  # soft vertical gradient, near-white
    v = int(246 - 22 * y / (H * S))
    for x in range(W * S):
        px[x, y] = (v, v, v + 1)
d = ImageDraw.Draw(img)

# Arrow between the two icon slots (app at x=165, Applications at x=495, both at y=190).
ax0, ax1, ay = 245 * S, 415 * S, 190 * S
d.line((ax0, ay, ax1 - 14 * S, ay), fill=(120, 124, 134), width=5 * S)
d.polygon([(ax1, ay), (ax1 - 24 * S, ay - 16 * S), (ax1 - 24 * S, ay + 16 * S)], fill=(120, 124, 134))

def font(size, bold=False):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"):
        if os.path.exists(path):
            try: return ImageFont.truetype(path, size * S)
            except OSError: pass
    return ImageFont.load_default()

def centered(text, y, size, fill):
    f = font(size)
    box = d.textbbox((0, 0), text, font=f)
    d.text(((W * S - (box[2] - box[0])) / 2, y * S), text, font=f, fill=fill)

centered("Arraste o Axios Notch para Aplicativos", 52, 17, (60, 62, 70))
centered("Drag Axios Notch to Applications", 80, 13, (118, 120, 130))

out = os.path.join(ROOT, "Packaging", "dmg-background.png")
img.save(out, dpi=(144, 144))
print("wrote", out)
