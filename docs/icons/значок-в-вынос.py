"""Значок «В» с выступающим карандашом (P478): плитка чуть меньше значка, а
карандаш выходит за её край — объём и необычный силуэт. Фон вокруг плитки
сплошной: значок iPhone не бывает прозрачным.
Запуск: python3 значок-в-вынос.py [куда.png] [--dark]   (нужны numpy, Pillow)"""
import os, sys, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageChops
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import pen_shapes

dark = "--dark" in sys.argv
out = next((a for a in sys.argv[1:] if not a.startswith("--")), "значок-в-вынос.png")
C = 2048                     # рисуем вдвое крупнее итога
INSET = 9                    # поле вокруг плитки, % от значка
tile_px = round(C * (100 - 2 * INSET) / 100)

# плитка: крафт, листок, строки — тем же сценарием, без карандаша
tmp = os.path.join(tempfile.mkdtemp(), "tile.png")
subprocess.run([sys.executable, os.path.join(here, "значок-в.py"), tmp],
               check=True, env={**os.environ, "ICON_N": str(tile_px // 2)})
tile = Image.open(tmp).convert("RGB").resize((tile_px, tile_px), Image.LANCZOS)

surround = (28, 33, 40) if dark else (244, 241, 234)
img = Image.new("RGBA", (C, C), surround + (255,))
off = round(C * INSET / 100)
radius = round(tile_px * 0.19)
mask = Image.new("L", (tile_px, tile_px), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile_px - 1, tile_px - 1], radius=radius, fill=255)

# тень плитки
sh = Image.new("L", (C, C), 0)
sh.paste(mask, (off + round(C * .004), off + round(C * .012)))
sh = sh.filter(ImageFilter.GaussianBlur(C * .012)).point(lambda a: int(a * (.55 if dark else .30)))
shadow = Image.new("RGBA", (C, C), (0, 0, 0, 0)); shadow.putalpha(sh)
img = Image.alpha_composite(img, shadow)
img.paste(tile, (off, off), mask)
ImageDraw.Draw(img).rounded_rectangle([off, off, off + tile_px - 1, off + tile_px - 1], radius=radius,
                                      outline=(150, 124, 86, 255), width=max(2, C // 500))

# карандаш: остриё — на конце последней строки, хвост — за краем плитки
px = lambda v: int(v * C / 100)
tip, tail = (62.8, 62.5), (96.5, 26.0)
import math
dx, dy = tail[0] - tip[0], tip[1] - tail[1]
angle = math.degrees(math.atan2(dy, dx))
k = math.hypot(dx, dy) / 37.5
pen = Image.new("RGBA", (C, C), (0, 0, 0, 0))
pen_shapes.draw("карандаш", pen, px, tip=tip, angle=angle, k=k)
a = pen.filter(ImageFilter.GaussianBlur(px(.9))).getchannel("A").point(lambda v: int(v * .38))
psh = Image.new("RGBA", (C, C), (40, 26, 10, 0)); psh.putalpha(a)
psh = ImageChops.offset(psh, px(.8), px(1.5))
img = Image.alpha_composite(img, psh)
img = Image.alpha_composite(img, pen)
img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(out)
