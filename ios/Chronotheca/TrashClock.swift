import Foundation

/// Часам телефона можно верить (P904, разбор `docs/67`, слабое место 3).
///
/// Корзина стирает то, что пролежало 30 дней, — по дате телефона. Сбилась
/// дата (перевели на месяц вперёд) — и корзина опустела бы разом. Поэтому
/// стираем, только когда время идёт ровно: с прошлого раза оно не пошло
/// назад и не прыгнуло больше чем на неделю. После скачка — в этот раз не
/// стираем: сбитую дату обычно поправляют за день, а кто правда не
/// открывал приложение месяц, потеряет лишь день отсрочки.
enum TrashClock {
    private static let key = "trash.clock"
    /// Ответ на этот запуск: обе корзины спрашивают подряд.
    private static var answer: (at: Date, steady: Bool)?

    /// Для проверок: забыть всё.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        answer = nil
    }

    static func steady(_ now: Date = Date()) -> Bool {
        if let answer, abs(now.timeIntervalSince(answer.at)) < 60 { return answer.steady }
        let d = UserDefaults.standard
        let last = d.double(forKey: key)
        d.set(now.timeIntervalSince1970, forKey: key)
        let gap = now.timeIntervalSince1970 - last
        let ok = last == 0 || (gap >= 0 && gap <= 7 * 86_400)
        answer = (now, ok)
        return ok
    }
}
