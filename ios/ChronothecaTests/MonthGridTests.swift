import XCTest
@testable import Chronotheca

/// Сетка месяца. Проверка на конкретных месяцах: в первой сборке календарь
/// молча потерял первую неделю сентября, и заметить это можно было только
/// по снимку экрана. Такие вещи должен ловить тест.
final class MonthGridTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private func day(_ date: Date?) -> Int? {
        date.map { cal.component(.day, from: $0) }
    }

    func testСентябрь2026НачинаетсяСоВторника() {
        // 1 сентября 2026 — вторник, значит перед ним одна пустая клетка.
        let cells = MonthGrid.cells(of: month(2026, 9), calendar: cal)
        XCTAssertEqual(cells.count, 31, "1 пустая + 30 дней")
        XCTAssertNil(cells[0])
        XCTAssertEqual(day(cells[1]), 1)
        XCTAssertEqual(day(cells[7]), 7)
        XCTAssertEqual(day(cells[30]), 30)
    }

    func testМесяцНачинающийсяСПонедельникаБезПустыхКлеток() {
        // 1 июня 2026 — понедельник.
        let cells = MonthGrid.cells(of: month(2026, 6), calendar: cal)
        XCTAssertEqual(day(cells[0]), 1)
        XCTAssertEqual(cells.count, 30)
    }

    func testМесяцНачинающийсяСВоскресеньяДаётШестьПустыхКлеток() {
        // 1 февраля 2026 — воскресенье, последний столбец недели.
        let cells = MonthGrid.cells(of: month(2026, 2), calendar: cal)
        XCTAssertEqual(cells.prefix(6).filter { $0 == nil }.count, 6)
        XCTAssertEqual(day(cells[6]), 1)
        XCTAssertEqual(cells.count, 34, "6 пустых + 28 дней")
    }

    func testВисокосныйФевраль() {
        let cells = MonthGrid.cells(of: month(2028, 2), calendar: cal)
        XCTAssertEqual(cells.compactMap { $0 }.count, 29)
    }

    func testНиОдинДеньНеПотерян() {
        for m in 1...12 {
            let cells = MonthGrid.cells(of: month(2026, m), calendar: cal)
            let days = cells.compactMap { day($0) }
            XCTAssertEqual(days, Array(1...days.count), "месяц \(m): дни идут подряд с первого")
        }
    }
}
