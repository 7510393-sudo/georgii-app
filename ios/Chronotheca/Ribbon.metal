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

/// Лента находок поиска (P707, P712, P714, P715): искажает карточку так, будто
/// весь список — одна лента, которая плавно поворачивает вдаль. Каждая
/// карточка считает по той же формуле, поэтому края соседних совпадают.
///
/// Карточка уже сжата целиком — по ширине в `k` раз от середины, по высоте
/// в `q` раз от низа — и после шейдера сдвигается на `shift` (низ — на своё
/// место на ленте). Шейдер доводит перспективу: для точки итоговой картинки
/// возвращает, откуда взять цвет в сжатой. `size` — размер карточки, `top` —
/// её верх в системе списка (ноль — верх списка) до сдвига. Всё — в точках.
[[ stitchable ]] float2 ribbon(float2 position, float2 size, float top, float shift,
                               float bend, float horizon, float r, float f,
                               float k, float q, float roll) {
    float centre = size.x * 0.5;
    float half_ = size.x * 0.5;
    // Верх сжатой картинки: выше — прозрачно.
    float roof = size.y - size.y * q;
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
            return position;
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
    // За валиком лента уходит на изнанку (P715, `RibbonBack`): здесь пусто.
    if (c > roll) {
        return float2(position.x, min(position.y, roof - 1.0));
    }
    // Место в самой карточке, затем — в сжатой картинке.
    float sourceY = bend - c - top;
    if (sourceY < 0.0) {
        // Это место другой, дальней карточки: здесь пусто. Над сжатой
        // картинкой прозрачно — берём точку там, рядом.
        return float2(position.x, min(position.y, roof - 1.0));
    }
    float pressedY = size.y - (size.y - sourceY) * q;
    // Вне сжатой картинки по ширине — прозрачно, точка остаётся своей.
    if (abs(position.x - centre) > k * half_ + 2.0) {
        return position;
    }
    float pressedX = centre + (position.x - centre) * k / s;
    // За краем ленты — пусто: точка сразу за краем сжатой картинки.
    if (pressedX < centre - k * half_) { pressedX = centre - k * half_ - 2.0; }
    if (pressedX > centre + k * half_) { pressedX = centre + k * half_ + 2.0; }
    return float2(pressedX, pressedY);
}
