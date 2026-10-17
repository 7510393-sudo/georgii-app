"""Открытая страница и соседняя должны совпадать.

При повороте они сменяют друг друга, и всякое расхождение человек видит
как мерцание. Трижды оно возвращалось, и трижды я чинил не то, потому что
сличал по памяти. Теперь сличает сборка (решения P114, P130).
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    print("::warning::нечем сличать страницы: нет Pillow")
    sys.exit(0)

КОРЕНЬ = Path(__file__).resolve().parents[1]
ЖИВАЯ = КОРЕНЬ / "docs/screens/02-план.png"
СОСЕДСКАЯ = КОРЕНЬ / "docs/screens/13-соседская-роспись.png"
РАЗНИЦА = КОРЕНЬ / "docs/screens/14-расхождение.png"

# Порог на сглаживание: точка отличается на столько — ещё не расхождение.
ТЕРПИМОСТЬ = 8
# Столько точек прощается: на снимке бывают часы и заряд батареи.
ДОПУСК = 3000

try:
    a = Image.open(ЖИВАЯ).convert("RGB")
    b = Image.open(СОСЕДСКАЯ).convert("RGB")
except OSError as e:
    print(f"::warning::нечего сличать: {e}")
    sys.exit(0)

if a.size != b.size:
    print(f"::error::снимки разного размера: {a.size} и {b.size}")
    sys.exit(1)

разница = ImageChops.difference(a, b)
красный, зелёный, синий = разница.split()
наибольшее = ImageChops.lighter(ImageChops.lighter(красный, зелёный), синий)
столбики = наибольшее.histogram()

точек = sum(столбики[ТЕРПИМОСТЬ + 1:])
всего = a.size[0] * a.size[1]
if точек <= ДОПУСК:
    print(f"страницы совпадают: расходятся {точек} точек из {всего}")
    sys.exit(0)

худшее = max(i for i, n in enumerate(столбики) if n)
print(f"::error::открытая и соседняя страницы расходятся: {точек} точек из "
      f"{всего}, наибольшее расхождение {худшее}, область {разница.getbbox()}")
наибольшее.point(lambda v: min(255, v * 6)).save(РАЗНИЦА)
sys.exit(1)
