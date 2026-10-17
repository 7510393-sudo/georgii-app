import XCTest
@testable import Chronotheca

/// Облачко «…помнишь?» и его память о прочитанном.
///
/// Правило простое: позвало, его прочитали — оно уходит. Второй раз звать
/// к той же записи нечестно: человек уже откликнулся (решение P136).
final class RememberTests: XCTestCase {

    func testПрочитанныйДеньБольшеНеЗовёт() {
        let list = Remembered.adding("2026-09-22", to: "")
        XCTAssertTrue(Remembered.has("2026-09-22", in: list))
    }

    func testСоседнийДеньПозовётПоСвоему() {
        let list = Remembered.adding("2026-09-22", to: "")
        XCTAssertFalse(Remembered.has("2026-09-23", in: list))
    }

    func testПустойСписокНеПомнитНичего() {
        XCTAssertFalse(Remembered.has("2026-09-22", in: ""))
    }

    func testПовторнаяПометкаНеПлодитЗаписей() {
        var list = Remembered.adding("2026-09-22", to: "")
        list = Remembered.adding("2026-09-22", to: list)
        XCTAssertEqual(list, "2026-09-22")
    }

    func testСписокНеРастётБезКрая() {
        var list = ""
        for i in 1...450 {
            list = Remembered.adding(String(format: "2020-01-%03d", i), to: list)
        }
        XCTAssertEqual(list.split(separator: " ").count, 400)
        // Старое забывается первым, свежее остаётся.
        XCTAssertTrue(Remembered.has("2020-01-450", in: list))
        XCTAssertFalse(Remembered.has("2020-01-001", in: list))
    }
}
