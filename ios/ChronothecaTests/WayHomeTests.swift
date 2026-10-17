import XCTest
@testable import Chronotheca

/// Дорога домой: один поворот на всё расстояние.
///
/// Правило простое: поворот один и не длиннее обычного, а сумма шагов ровно
/// равна расстоянию — иначе человек окажется не дома. Что вернулись
/// издалека, видно по толщине листа, а не по числу поворотов (P178).
final class WayHomeTests: XCTestCase {

    func testДомаДорогиНет() {
        XCTAssertEqual(wayHome(0), [])
    }

    func testСоседнийДеньОдинПоворот() {
        XCTAssertEqual(wayHome(1), [1])
        XCTAssertEqual(wayHome(-1), [-1])
    }

    func testДальнийДеньТожеОдинПоворот() {
        XCTAssertEqual(wayHome(2), [2])
        XCTAssertEqual(wayHome(-40), [-40])
    }

    func testПоворотВсегдаОдин() {
        for расстояние in [3, 7, 10, 40, 365, -3, -7, -10, -40, -365] {
            XCTAssertEqual(wayHome(расстояние).count, 1,
                           "расстояние \(расстояние)")
        }
    }

    func testСуммаШаговРавнаРасстоянию() {
        // Главная проверка: иначе человек окажется не дома.
        for расстояние in (-400...400) {
            XCTAssertEqual(wayHome(расстояние).reduce(0, +), расстояние,
                           "расстояние \(расстояние)")
        }
    }

    func testВсеШагиВОднуСторону() {
        for расстояние in [10, 40, 365, -10, -40, -365] {
            let знак = расстояние > 0 ? 1 : -1
            for шаг in wayHome(расстояние) {
                XCTAssertEqual(шаг > 0 ? 1 : -1, знак,
                               "шаг \(шаг) идёт не в ту сторону")
            }
        }
    }

    func testПустыхШаговНет() {
        for расстояние in (-50...50) {
            XCTAssertFalse(wayHome(расстояние).contains(0))
        }
    }

    func testДорогаОтДняКСегодня() {
        let вчера = Calendar.current.date(byAdding: .day, value: -1,
                                          to: DayStore.today())!
        XCTAssertEqual(DayPages.wayHome(from: вчера), [1])
        XCTAssertEqual(DayPages.wayHome(from: DayStore.today()), [])
    }

    /// Вихрь: соседний день — один лист, дальше — от двух до пяти, и чем
    /// дальше, тем больше (P266).
    func testВихрьОтДвухДоПятиЛистов() {
        XCTAssertEqual(whirlLeaves(0), 0)
        XCTAssertEqual(whirlLeaves(1), 1)
        XCTAssertEqual(whirlLeaves(-1), 1)
        var прежде = 1
        for расстояние in 2...400 {
            let листов = whirlLeaves(расстояние)
            XCTAssertTrue((2...5).contains(листов), "расстояние \(расстояние)")
            XCTAssertGreaterThanOrEqual(листов, прежде)
            XCTAssertEqual(whirlLeaves(-расстояние), листов)
            прежде = листов
        }
    }
}
