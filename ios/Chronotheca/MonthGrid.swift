import Foundation

/// Сетка месяца: пустые клетки до первого числа, потом дни подряд.
///
/// Вынесено из вида и считается отдельно, потому что в первой же сборке
/// календарь потерял первую неделю сентября, а проверить это глазами по
/// снимку — единственное, что мне оставалось. Теперь проверяет тест.
enum MonthGrid {

    /// Клетки месяца. `nil` — пустое место перед первым числом.
    /// Неделя начинается с понедельника, как в русском календаре.
    /// `firstWeekday`: 2 — неделя с понедельника (как было всегда), 1 — с
    /// воскресенья (P290). Задаётся явно, а не берётся из календаря: у
    /// календаря телефона он зависит от страны.
    static func cells(of month: Date, calendar: Calendar = .current,
                      firstWeekday: Int = 2) -> [Date?] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
                    ?? month
        // Сколько пустых клеток до первого числа — от первого дня недели
        // календаря (P290).
        let lead = (calendar.component(.weekday, from: first) - firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: i, to: first))
        }
        return cells
    }
}
