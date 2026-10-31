#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Лента: место на экране и ширина для точки ленты на `c` точек выше линии
/// изгиба (P712) — четверть цилиндра радиуса `r`, дальше плоскость к
/// горизонту, вид с расстояния `f`. Та же формула — `Search.curl`.
static float2 curl(float c, float bend, float horizon, float r, float f) {
    if (c <= 0.0) {
        return float2(bend - c, 1.0);
    }
    float arc = 1.5707963 * r;
    float h;
    float z;
    if (c < arc) {
        h = r * sin(c / r);
        z = r * (1.0 - cos(c / r));
    } else {
        h = r;
        z = r + (c - arc);
    }
    float s = f / (f + z);
    return float2(horizon + (bend - horizon - h) * s, s);
}

/// Лента находок поиска (P707, P712, P714, P715, P717): искажает карточку
/// так, будто весь список — одна лента, которая плавно поворачивает вдаль.
/// Каждая карточка считает по той же формуле, поэтому края соседних
/// совпадают.
///
/// После шейдера карточка сдвигается на `shift` (низ — на своё место на
/// ленте). Шейдер для точки итоговой картинки возвращает, откуда взять цвет
/// в самой карточке. `size` — размер карточки, `top` — её верх в системе
/// списка (ноль — верх списка) до сдвига, `vx` — куда сходится лента. Всё — в точках.
[[ stitchable ]] float2 ribbon(float2 position, float2 size, float top, float shift,
                               float bend, float horizon, float r, float f, float roll,
                               float vx) {
    float centre = size.x * 0.5;
    // Пусто: точка сразу за краем карточки сбоку — там прозрачно.
    float2 empty = float2(position.x < centre ? -4.0 : size.x + 4.0, position.y);
    // Где эта точка на экране, в системе списка.
    float y = top + shift + position.y;
    float c;
    float s;
    if (y >= bend) {
        c = bend - y;
        s = 1.0;
    } else {
        // Точка ленты, которая легла сюда: место на экране с высотой ленты
        // только убывает, ищем делением пополам.
        if (y <= curl(4000.0, bend, horizon, r, f).x) {
            return empty;
        }
        float lo = 0.0;
        float hi = 4000.0;
        for (int i = 0; i < 24; i++) {
            float mid = 0.5 * (lo + hi);
            if (curl(mid, bend, horizon, r, f).x > y) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        c = 0.5 * (lo + hi);
        s = curl(c, bend, horizon, r, f).y;
    }
    // За дальним концом лента уходит в петлю (`RibbonBack`): здесь пусто.
    if (c > roll) {
        return empty;
    }
    // Место в самой карточке.
    float sourceY = bend - c - top;
    if (sourceY < 0.0 || sourceY > size.y) {
        // Это место другой карточки: здесь пусто.
        return empty;
    }
    // Лента сходится не к середине, а к `vx` — левее (P717, по рисунку).
    float sourceX = vx + (position.x - vx) / s;
    // За краем ленты — пусто.
    if (sourceX < 0.0 || sourceX > size.x) {
        return empty;
    }
    return float2(sourceX, sourceY);
}
