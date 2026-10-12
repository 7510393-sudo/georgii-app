"""Значок «В»: листок с рваным краем на крафт-бумаге (P472).
Запуск: python3 docs/icons/значок-в.py [куда.png]  (нужны numpy, Pillow)."""
import sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

N, S = 1024, 2            # итог 1024, рисуем вдвое крупнее
W = N * S
rnd = random.Random(7)
np.random.seed(7)

def px(v): return int(v * W / 100)        # координаты как в эскизе: 0…100

# --- крафт: цвет, волокна, крапинки ---
base = np.zeros((W, W, 3), np.float32); base[:] = (203, 178, 140)
noise = np.random.rand(W // 4, W // 4).astype(np.float32)
fine = np.array(Image.fromarray((noise * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC), np.float32) / 255
fibers = np.random.rand(W // 3, W // 40).astype(np.float32)          # вытянутые волокна
big = Image.fromarray((fibers * 255).astype(np.uint8)).resize((W * 3 // 2, W * 3 // 2), Image.BICUBIC).rotate(14, resample=Image.BICUBIC)
o = W // 4
fib = np.array(big.crop((o, o, o + W, o + W)), np.float32) / 255
speck = (np.random.rand(W, W) > 0.9985).astype(np.float32)
speck = np.array(Image.fromarray((speck * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
tex = (fine - .5) * 22 + (fib - .5) * 26 - speck * 90
kraft = np.clip(base + tex[..., None], 0, 255)
yy, xx = np.mgrid[0:W, 0:W]
vig = 1 - 0.13 * (((xx - W / 2) ** 2 + (yy - W / 2) ** 2) / (W / 2) ** 2)   # края темнее
kraft = np.clip(kraft * vig[..., None], 0, 255)
img = Image.fromarray(kraft.astype(np.uint8)).convert("RGBA")

# --- листок ---
L, R, T, B = 24, 76, 15, 77
teeth = []
x = R
step = 3.7
while x > L:                                   # рваный низ: неровные зубцы
    teeth.append((x, B + rnd.uniform(-1.6, 2.6)))
    x -= step * rnd.uniform(.6, 1.4)
    teeth.append((x, B - rnd.uniform(1.0, 3.6)))
    x -= step * rnd.uniform(.5, 1.2)
teeth.append((L, B + rnd.uniform(0, 1.5)))
sheet = [(L, T), (R, T), (R, B)] + teeth
def scaled(pts, dx=0, dy=0): return [(px(a + dx), px(b + dy)) for a, b in pts]

layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
# тень
sh = Image.new("L", (W, W), 0)
ImageDraw.Draw(sh).polygon(scaled(sheet, 1.2, 2.4), fill=120)
sh = sh.filter(ImageFilter.GaussianBlur(px(1.8)))
shadow = Image.new("RGBA", (W, W), (60, 38, 16, 0)); shadow.putalpha(sh)
# сам листок: тёплый белый, чуть темнее у рваного края (волокна)
d.polygon(scaled(sheet), fill=(251, 243, 216, 255))
mask = Image.new("L", (W, W), 0); ImageDraw.Draw(mask).polygon(scaled(sheet), fill=255)
edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(px(1.4) | 1)))
rim = Image.new("RGBA", (W, W), (255, 252, 240, 255)); rim.putalpha(edge)
layer = Image.alpha_composite(layer, rim)
# клетка на листке — тонкая, как в плане
g = ImageDraw.Draw(layer)
for gx in range(L + 3, R, 6): g.line([(px(gx), px(T)), (px(gx), px(B - 4))], fill=(226, 198, 174, 70), width=S)
for gy in range(T + 3, B - 3, 6): g.line([(px(L), px(gy)), (px(R), px(gy))], fill=(226, 198, 174, 70), width=S)
# дело: квадратик с галочкой и строка
ink = (28, 33, 40, 255); blue = (47, 74, 107, 255); red = (176, 64, 58, 255)
g.rounded_rectangle([px(32), px(25), px(41), px(34)], radius=px(2), outline=ink, width=px(1.5))
g.line([(px(33.6), px(30.2)), (px(36), px(32.8)), (px(40.4), px(26.4))], fill=red, width=px(1.9), joint="curve")
for yy_, x1_ in ((27.0, 67), (32.2, 59)):          # две прямые строчки дела
    g.line([(px(46), px(yy_)), (px(x1_), px(yy_))], fill=ink, width=px(1.7))
# строки дневника — волнистые, синими чернилами
def wave(x0, y0, n, w=7.2, a=2.2):
    pts = []
    for i in range(int(n * 24) + 1):
        t = i / 24; pts.append((px(x0 + t * w), px(y0 - a * math.sin(t * math.pi * 2 / 1.0 * 0.5 * 2) * (1 if int(t) % 2 == 0 else 1))))
    return pts
PER = 9.0                                         # длина волны
for y0, k in [(46, 3), (57, 2), (68, 3)]:         # k волн: начало внизу, конец на подъёме вверх (не грустный смайлик)
    n = int((k + .5) * PER / .3)
    pts = [(px(32 + i * .3), px(y0 - 1.5 * math.sin(-math.pi / 2 + i * .3 / PER * math.pi * 2))) for i in range(n + 1)]
    g.line(pts, fill=blue, width=px(1.5), joint="curve")
    for p in (pts[0], pts[-1]): g.ellipse([p[0] - px(.75), p[1] - px(.75), p[0] + px(.75), p[1] + px(.75)], fill=blue)

sheet_img = Image.alpha_composite(shadow, layer)
sheet_img = sheet_img.rotate(5, resample=Image.BICUBIC, center=(W // 2, W // 2))   # лёгкий наклон
img = Image.alpha_composite(img, sheet_img)

PEN = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--pen=")), "")
if PEN:
    # Пишущий предмет: остриё — на конце последней строки, сам предмет уходит
    # за правый край листа. Рисуется в «листовых» координатах 0…100 и ложится
    # на сам лист, поэтому наклонён вместе с ним.
    import pen_shapes  # noqa: рядом лежит pen_shapes.py
    top = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    pen_shapes.draw(PEN, top, px, tip=(64.2, 66.6), angle=38)
    shadow = top.filter(ImageFilter.GaussianBlur(px(.9)))
    sh = Image.new("RGBA", (W, W), (60, 38, 16, 0)); sh.putalpha(shadow.getchannel("A").point(lambda a: int(a * .35)))
    sh = ImageChops.offset(sh, px(.8), px(1.4))
    both = Image.alpha_composite(sh, top).rotate(5, resample=Image.BICUBIC, center=(W // 2, W // 2))
    img = Image.alpha_composite(img, both)

out = next((a for a in sys.argv[1:] if not a.startswith("--")), "значок-в.png")
img.convert("RGB").resize((N, N), Image.LANCZOS).save(out)
