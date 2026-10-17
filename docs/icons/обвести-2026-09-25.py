"""Обводка эскиза 25 сентября: три значка разделов и облачко.

Эскиз — `эскиз-2026-09-25.png`. Каждый рисунок берётся по связным пятнам
чернил внутри своего прямоугольника; у облачка отдельно контур, лицо и
подпись, а пунктир вкладки под ним отброшен.
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

g = np.array(Image.open(ЗДЕСЬ / "эскиз-2026-09-25.png").convert("L"))
чернила = g < 140
пятна = measure.label(чернила, connectivity=2)
все = measure.regionprops(пятна)


def внутри(box, pad=12):
    x0, y0, x1, y1 = box
    return [p.label for p in все
            if p.bbox[1] >= x0 - pad and p.bbox[0] >= y0 - pad
            and p.bbox[3] <= x1 + pad and p.bbox[2] <= y1 + pad]


def маска(labels):
    return np.isin(пятна, labels)


def значок(имя, box):
    m = маска(внутри(box))
    x0, y0, x1, y1 = box
    m = m[y0 - 12:y1 + 12, x0 - 12:x1 + 12]
    paths, w, h = fit(contours(m, tol=1.0, min_area=20))
    (АКТИВЫ / f"{имя}.imageset" / f"{имя}.svg").write_text(svg(paths, w, h, side=100, colour="black"))


# Слева направо: календарь, сегодня (книга), поиск (микроскоп).
значок("календарь", (256, 1098, 573, 1479))
значок("сегодня", (878, 1106, 1479, 1501))
значок("поиск", (1772, 995, 2068, 1416))

# Облачко. Контур — самое большое пятно в его прямоугольнике; лицо —
# пятна правее подписи; подпись и пунктир вкладки не берутся.
ОБЛАКО = (706, 349, 1310, 683)
контур = max((p for p in все if p.label in внутри(ОБЛАКО)), key=lambda p: p.area).label
лицо = [p.label for p in все
        if p.label != контур and p.label in внутри(ОБЛАКО)
        and p.bbox[1] >= 1060 and p.bbox[2] <= 560]
x0, y0, x1, y1 = ОБЛАКО
вырез = (slice(y0, y1 + 1), slice(x0, x1 + 1))
перо = маска([контур] + лицо)[вырез]
# Низ облачка открыт: на эскизе его замыкает верхний край вкладки
# «Дневник», на который облачко опирается. Для заливки бумагой замыкаем
# по этому краю — строка 600 эскиза.
КРАЙ = 600
замкнутый = маска([контур])[вырез].copy()
замкнутый[КРАЙ - y0 - 1:КРАЙ - y0 + 2, :] = True
бумага = ndimage.binary_fill_holes(замкнутый)
# Черта торчит левее и правее облачка тонким усом — снимаем его.
бумага = ndimage.binary_opening(бумага, structure=np.ones((7, 7)))
бумага = measure.label(бумага, connectivity=1)
бумага = бумага == max(measure.regionprops(бумага), key=lambda r: r.area).label
w, h = x1 - x0 + 1, y1 - y0 + 1


def облачко(имя, m):
    paths = contours(m, tol=1.0, min_area=20)
    body = " ".join("M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in p) + "Z" for p in paths)
    (АКТИВЫ / f"{имя}.imageset" / f"{имя}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}"><path fill="black" fill-rule="evenodd" d="{body}"/></svg>')


облачко("облачко-перо", перо)
облачко("облачко-бумага", бумага)
print("облачко", w, h, "доля", round(w / h, 3), "край вкладки", round((КРАЙ - y0) / h, 3), "лицо", лицо)
