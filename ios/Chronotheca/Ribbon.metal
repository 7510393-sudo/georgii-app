#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Лента находок поиска (P707): искажает картинку списка так, будто она
/// сгибается у `bend` (от верха списка) и ложится плоскостью к горизонту на
/// `horizon`. Шейдер получает точку итоговой картинки и возвращает, откуда
/// взять цвет в исходной.
///
/// `lift` — на сколько вид продолжается вверх за верх списка (запас ленты).
/// `size` — размер вида. Всё — в точках.
[[ stitchable ]] float2 ribbon(float2 position, float2 size, float lift, float bend, float horizon) {
    // Высота в системе списка: ноль — верх списка.
    float y = position.y - lift;
    // Ниже изгиба картинка прежняя.
    if (y >= bend) {
        return position;
    }
    float span = bend - horizon;
    float t = (bend - y) / span;
    // Ближе к горизонту, чем ширина четверть, не рисуем: запас ленты кончается.
    if (t >= 0.9375) {
        return float2(-10000.0, -10000.0);
    }
    // Ширина ленты на этой высоте (1 в начале изгиба, 0 на горизонте).
    float s = sqrt(1.0 - t);
    // Сколько точек ленты до изгиба лежит в этом месте.
    float c = 2.0 * span * (1.0 / s - 1.0);
    float sourceY = bend - c + lift;
    float centre = size.x * 0.5;
    float sourceX = centre + (position.x - centre) / s;
    return float2(sourceX, sourceY);
}
