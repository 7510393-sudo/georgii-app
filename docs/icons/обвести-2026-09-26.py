"""Обводка эскизов 26 сентября: новое облачко с рукописной подписью и
поправленный микроскоп.

Облачко — `эскиз-2026-09-26-облачко.png`: контур, лицо и подпись «…а
помнишь?» обводятся вместе, от руки (решение P230); пунктир вкладки под
облачком отброшен — это всё, что ниже строки 600, кроме самого контура.
Микроскоп — `эскиз-2026-09-26-микроскоп.jpg`, целиком.

Запускать из корня хранилища; нужны numpy, Pillow, scipy, scikit-image.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

sys.path.insert(0, str(Path(__file__).parent))
from обводка import contours, fit, svg  # noqa: E402

ЗДЕСЬ = Path(__file__).parent
АКТИВЫ = ЗДЕСЬ.parents[1] / "ios/Chronotheca/Assets.xcassets"

# --- Микроскоп ---------------------------------------------------------
g = np.array(Image.open(ЗДЕСЬ / "эскиз-2026-09-26-микроскоп.jpg").convert("L"))
m = g < 140
paths, w, h = fit(contours(m, tol=1.0, min_area=20))
(АКТИВЫ / "поиск.imageset" / "поиск.svg").write_text(svg(paths, w, h, side=100, colour="black"))

# --- Облачко -----------------------------------------------------------
g = np.array(Image.open(ЗДЕСЬ / "эскиз-2026-09-26-облачко.png").convert("L"))
чернила = g < 140
пятна = measure.label(чернила, connectivity=2)
все = measure.regionprops(пятна)

# Контур облачка — самое большое пятно; по нему берётся рамка рисунка.
контур = max(все, key=lambda p: p.area)
y0, x0, y1, x1 = контур.bbox
# Пунктир вкладки лежит на строке ~605 и ниже; подпись и лицо — выше.
КРАЙ = 604
внутри = [p.label for p in все
          if p.label != контур.label
          and p.bbox[1] >= x0 and p.bbox[3] <= x1
          and p.bbox[0] >= y0 and p.bbox[2] < 600]
вырез = (slice(y0, y1), slice(x0, x1))
перо = np.isin(пятна, [контур.label] + внутри)[вырез]

# Низ облачка открыт слева от локтя: там его замыкает верхний край
# вкладки. Для заливки бумагой замыкаем по этому краю.
замкнутый = (пятна == контур.label)[вырез].copy()
замкнутый[КРАЙ - y0 - 1:КРАЙ - y0 + 2, 610 - x0:915 - x0] = True
бумага = ndimage.binary_fill_holes(замкнутый)
бумага = ndimage.binary_opening(бумага, structure=np.ones((7, 7)))
метки = measure.label(бумага, connectivity=1)
бумага = метки == max(measure.regionprops(метки), key=lambda r: r.area).label
w, h = x1 - x0, y1 - y0


def облачко(имя, маска):
    paths = contours(маска, tol=1.0, min_area=6)
    body = " ".join("M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in p) + "Z" for p in paths)
    (АКТИВЫ / f"{имя}.imageset" / f"{имя}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}"><path fill="black" fill-rule="evenodd" d="{body}"/></svg>')


облачко("облачко-перо", перо)
облачко("облачко-бумага", бумага)
print("облачко", w, h, "доля", round(w / h, 3), "край вкладки", round((КРАЙ - y0) / h, 3),
      "пятен подписи и лица", len(внутри), "заливка", int(бумага.sum()))

# --- Глобус для раздела «Карта» (P248) ----------------------------------
g = np.array(Image.open(ЗДЕСЬ / "эскиз-2026-09-26-глобус.jpg").convert("L"))
paths, w, h = fit(contours(g < 140, tol=1.0, min_area=20))
(АКТИВЫ / "карта.imageset" / "карта.svg").write_text(svg(paths, w, h, side=100, colour="black"))
