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

/// Лента находок поиска (P707, P712): искажает карточку так, будто весь
/// список — одна лента, которая плавно поворачивает вдаль. Каждая карточка
/// считает по той же формуле, поэтому края соседних совпадают. Карточка уже
/// сдвинута на `shift` (низ — на своё место на ленте); шейдер получает точку
/// итоговой картинки и возвращает, откуда взять цвет в исходной.
///
/// `size` — размер карточки, `top` — её верх в системе списка (ноль — верх
/// списка) до сдвига. Всё — в точках.
[[ stitchable ]] float2 ribbon(float2 position, float2 size, float top, float shift,
                               float bend, float horizon, float r, float f) {
    // Где эта точка на экране, в системе списка.
    float y = top + shift + position.y;
    // Пусто: точка сразу над карточкой — там прозрачно, и недалеко.
    float2 none = float2(position.x, -2.0);
    float c;
    float s;
    if (y >= bend) {
        c = bend - y;
        s = 1.0;
    } else {
        // Точка ленты, которая легла сюда: место на экране с высотой ленты
        // только убывает, ищем делением пополам.
        float lo = 0.0;
        float hi = 4000.0;
        if (y <= curl(hi, bend, horizon, r, f).x) {
            return none;
        }
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
    float sourceY = bend - c - top;
    // Выше карточки — это уже другая, дальняя карточка: здесь пусто.
    if (sourceY < 0.0 || sourceY > size.y) {
        return none;
    }
    float centre = size.x * 0.5;
    float sourceX = centre + (position.x - centre) / s;
    // За краем ленты — пусто: точка за краем карточки дальше её тени, но не
    // дальше предела выборки.
    if (sourceX < 0.0) { sourceX = -12.0; }
    if (sourceX > size.x) { sourceX = size.x + 12.0; }
    return float2(sourceX, sourceY);
}
