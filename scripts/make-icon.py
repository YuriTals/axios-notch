#!/usr/bin/env python3
"""Builds Packaging/AppIcon.icns from "Packaging/AxiosLogo.png": the white asterisk on a
dark macOS-style rounded square. Needs Pillow; the result is committed, so
this only has to be run when the artwork changes."""
import os, subprocess, shutil, tempfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024

logo = Image.open(os.path.join(ROOT, "Packaging", "AxiosLogo.png")).convert("L")
mask = logo.resize((int(SIZE * 0.58),) * 2, Image.LANCZOS)          # white strokes = opaque

# Icon body: ~82% of the canvas, like the system's own icons.
body = int(SIZE * 0.82); margin = (SIZE - body) // 2; radius = int(body * 0.225)
bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gradient = Image.new("RGB", (1, body))
for y in range(body):
    v = int(46 - 34 * y / body)                                       # soft dark gradient, top lighter
    gradient.putpixel((0, y), (v, v, v + 2))
gradient = gradient.resize((body, body))
shape = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(shape).rounded_rectangle((margin, margin, margin + body, margin + body), radius, fill=255)
bg.paste(gradient, (margin, margin), shape.crop((margin, margin, margin + body, margin + body)))

# Drop shadow under the body.
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 120), (0, 14), shape)
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
icon = Image.alpha_composite(shadow, bg)

# Hairline highlight on the edge, then the asterisk.
edge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(edge).rounded_rectangle((margin, margin, margin + body, margin + body), radius, outline=(255, 255, 255, 38), width=3)
icon = Image.alpha_composite(icon, edge)
mark = Image.new("RGBA", mask.size, (255, 255, 255, 255)); mark.putalpha(mask)
icon.alpha_composite(mark, ((SIZE - mask.size[0]) // 2, (SIZE - mask.size[1]) // 2))

work = tempfile.mkdtemp(suffix=".iconset")
for base in (16, 32, 128, 256, 512):
    icon.resize((base, base), Image.LANCZOS).save(os.path.join(work, f"icon_{base}x{base}.png"))
    icon.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(work, f"icon_{base}x{base}@2x.png"))
out = os.path.join(ROOT, "Packaging", "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", work, "-o", out], check=True)
icon.resize((512, 512), Image.LANCZOS).save("/tmp/axios-icon-preview.png")
shutil.rmtree(work)
print("wrote", out)
