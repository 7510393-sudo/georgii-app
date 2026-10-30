#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Лента находок поиска (P707): искажает карточку так, будто весь список —
/// одна лента, которая сгибается у `bend` (от верха списка) и ложится
/// плоскостью к горизонту на `horizon`. Каждая карточка считает по той же
/// формуле, поэтому края соседних совпадают. Шейдер получает точку итоговой
/// картинки и возвращает, откуда взять цвет в исходной.
///
/// `size` — размер карточки с прозрачным запасом снизу, `top` — верх
/// карточки в системе списка (ноль — верх списка), `vanish` — ширина ленты,
/// на которой она пропадает. Всё — в точках.
[[ stitchable ]] float2 ribbon(float2 position, float2 size, float top, float bend,
                               float horizon, float vanish) {
    float y = top + position.y;
    // Ниже изгиба картинка прежняя.
    if (y >= bend) {
        return position;
    }
    float span = bend - horizon;
    float t = (bend - y) / span;
    // Выше места, где лента сузилась до `vanish`, — пусто: там список закрыт
    // маской, что бы ни вернуть.
    if (t >= 1.0 - vanish * vanish) {
        return position;
    }
    // Ширина ленты на этой высоте: 1 у изгиба, меньше — к горизонту.
    float s = sqrt(1.0 - t);
    // Сколько точек ленты выше изгиба лежит в этом месте.
    float c = 2.0 * span * (1.0 / s - 1.0);
    float sourceY = bend - c - top;
    float centre = size.x * 0.5;
    float sourceX = centre + (position.x - centre) / s;
    // За краем ленты — пусто: берём точку сразу за краем карточки (там
    // прозрачно), не дальше предела выборки.
    if (sourceX < 0.0) { sourceX = -1.0; }
    if (sourceX > size.x) { sourceX = size.x + 1.0; }
    return float2(sourceX, sourceY);
}
