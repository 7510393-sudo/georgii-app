"""Обводка рисунка от руки в вектор.

Берёт чернила (тёмные пиксели), находит все границы — и внешние, и дырки —
и складывает их в один путь с правилом «чёт-нечет». Так рисунок остаётся
рисунком автора, а не моим пересказом.
"""
import numpy as np
from PIL import Image, ImageFilter
from skimage import measure


def ink(path, box=None, blur=1.2, thr=140, scale=1.0):
    im = Image.open(path).convert("L")
    if box:
        im = im.crop(box)
    if scale != 1.0:
        im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    im = im.filter(ImageFilter.GaussianBlur(blur))
    return (np.array(im) < thr)


def contours(mask, tol=1.1, min_area=25.0, pad=2):
    m = np.pad(mask.astype(float), pad)
    out = []
    for c in measure.find_contours(m, 0.5):
        c = measure.approximate_polygon(c, tolerance=tol)
        if len(c) < 4:
            continue
        y, x = c[:, 0] - pad, c[:, 1] - pad
        area = abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1))) / 2
        if area < min_area:
            continue
        out.append(np.column_stack([x, y]))
    return out


def svg(paths, w, h, side=100.0, colour="currentColor", margin=0.0):
    """Уложить пути в квадрат со стороной side, сохранив пропорции."""
    k = (side - 2 * margin) / max(w, h)
    dx = margin + (side - 2 * margin - w * k) / 2
    dy = margin + (side - 2 * margin - h * k) / 2
    d = []
    for p in paths:
        pts = [f"{x * k + dx:.2f} {y * k + dy:.2f}" for x, y in p]
        d.append("M" + "L".join(pts) + "Z")
    body = " ".join(d)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{side:.0f}" '
            f'height="{side:.0f}" viewBox="0 0 {side:.0f} {side:.0f}">'
            f'<path fill="{colour}" fill-rule="evenodd" d="{body}"/></svg>')


def fit(paths):
    """Прижать рисунок к началу координат и вернуть его размеры."""
    xs = np.concatenate([p[:, 0] for p in paths])
    ys = np.concatenate([p[:, 1] for p in paths])
    x0, y0 = xs.min(), ys.min()
    return [p - [x0, y0] for p in paths], xs.max() - x0, ys.max() - y0
