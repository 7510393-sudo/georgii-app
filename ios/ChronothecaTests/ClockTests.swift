import XCTest
@testable import Chronotheca

/// Откуда начинает крутиться ролик времени.
///
/// Мелочь, которая стоит человеку лишнего движения на каждом деле: если
/// ролик встаёт не там, его приходится докручивать всякий раз.
final class ClockTests: XCTestCase {

    private let cal = Calendar.current

    private func время(_ час: Int, _ минута: Int) -> Date {
        cal.date(bySettingHour: час, minute: минута, second: 0, of: Date())!
    }

    private func часы(_ date: Date) -> (Int, Int) {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? -1, c.minute ?? -1)
    }

    func testСледующийКруглыйЧас() {
        XCTAssertEqual(часы(Clock.nextHour(время(22, 49))).0, 23)
        XCTAssertEqual(часы(Clock.nextHour(время(22, 49))).1, 0)
    }

    func testРовноВЧасПредлагаетсяЭтотЖеЧас() {
        // В 23:00 предлагать полночь было бы странно: час ещё не начался.
        XCTAssertEqual(часы(Clock.nextHour(время(23, 0))).0, 23)
        XCTAssertEqual(часы(Clock.nextHour(время(23, 0))).1, 0)
    }

    func testПослеОдиннадцатиВечераПолночь() {
        XCTAssertEqual(часы(Clock.nextHour(время(23, 40))).0, 0)
        XCTAssertEqual(часы(Clock.nextHour(время(23, 40))).1, 0)
    }

    func testПервойМинутойСутокПредлагаетсяЧас() {
        XCTAssertEqual(часы(Clock.nextHour(время(0, 1))).0, 1)
    }

    func testПолночьЭтоПолночь() {
        XCTAssertEqual(часы(Clock.midnight(время(22, 49))).0, 0)
        XCTAssertEqual(часы(Clock.midnight(время(22, 49))).1, 0)
    }

    func testВремяТудаИОбратно() {
        XCTAssertEqual(Clock.text(время(9, 5)), "09:05")
        XCTAssertEqual(часы(Clock.date("09:05")!).0, 9)
        XCTAssertEqual(часы(Clock.date("09:05")!).1, 5)
        XCTAssertNil(Clock.date(nil))
        XCTAssertNil(Clock.date("не время"))
    }

    func testПодгонкаКШагуИдётВниз() {
        // Вниз, а не к ближайшему: назначенное на 14:37 дело безопаснее
        // сдвинуть на 14:35, чем на 14:40 — раньше можно, позже нельзя.
        XCTAssertEqual(часы(Clock.snap(время(14, 37))).1, 35)
        XCTAssertEqual(часы(Clock.snap(время(14, 39))).1, 35)
        XCTAssertEqual(часы(Clock.snap(время(14, 40))).1, 40)
        XCTAssertEqual(часы(Clock.snap(время(14, 3))).1, 0)
    }

    func testКруглоеВремяПодгонкойНеПортится() {
        for минута in [0, 5, 15, 30, 45] {
            XCTAssertEqual(часы(Clock.snap(время(9, минута))).1, минута)
        }
        XCTAssertEqual(часы(Clock.snap(время(9, 30))).0, 9)
    }

    func testГотовыеОтветыОстаютсяНаСетке() {
        // Время дела уже подогнано к шагу, значит и «за 10 минут», и «за
        // час» от него попадают на сетку сами.
        let дело = Clock.snap(время(14, 37))
        for сдвиг in [-600.0, -3600.0] {
            let итог = дело.addingTimeInterval(сдвиг)
            XCTAssertEqual(часы(итог).1 % 5, 0, "сдвиг \(сдвиг) увёл с сетки")
        }
    }

    func testЧасРовно() {
        XCTAssertEqual(часы(Clock.at(9, время(22, 49))).0, 9)
        XCTAssertEqual(часы(Clock.at(9, время(22, 49))).1, 0)
    }

    func testГотовыеОтветыОтсчитываютсяОтДела() {
        let дело = Clock.date("14:30")!
        XCTAssertEqual(часы(дело.addingTimeInterval(-600)).0, 14)
        XCTAssertEqual(часы(дело.addingTimeInterval(-600)).1, 20)
        XCTAssertEqual(часы(дело.addingTimeInterval(-3600)).0, 13)
        XCTAssertEqual(часы(дело.addingTimeInterval(-3600)).1, 30)
    }

    func testНапоминаниеЗаЧасДоДела() {
        // Ролик колокольчика встаёт за час до дела: напоминают заранее.
        let дело = Clock.date("23:00")!
        XCTAssertEqual(часы(дело.addingTimeInterval(-3600)).0, 22)
        XCTAssertEqual(часы(дело.addingTimeInterval(-3600)).1, 0)
    }
}
