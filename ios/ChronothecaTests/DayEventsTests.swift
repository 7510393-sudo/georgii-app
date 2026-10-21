import XCTest
import SwiftUI
@testable import Chronotheca

/// События Календаря в плане (P376): в файл попадают только отметки
/// человека, и приложение не путает их со своими делами.
final class DayEventsTests: XCTestCase {

    func testОтметкаЧитаетсяИПишетсяТойЖеСтрокой() {
        let line = "- [x] 10:00 Стоматолог (calendar #k3f9a2c1)"
        let mark = DayEvents.Mark.parse(line)
        XCTAssertEqual(mark?.key, "k3f9a2c1")
        XCTAssertEqual(mark?.done, true)
        XCTAssertEqual(mark?.hidden, false)
        XCTAssertEqual(mark?.time, "10:00")
        XCTAssertEqual(mark?.title, "Стоматолог")
        XCTAssertEqual(mark?.line, line)

        let hidden = "- [ ] Отпуск (calendar #ab12cd34 hidden)"
        XCTAssertEqual(DayEvents.Mark.parse(hidden)?.hidden, true)
        XCTAssertNil(DayEvents.Mark.parse(hidden)?.time)
        XCTAssertEqual(DayEvents.Mark.parse(hidden)?.line, hidden)
    }

    func testОтметкаНеСтановитсяДеломИОстаётсяВФайле() {
        let body = "- [ ] 09:00 Купить хлеб\n- [x] 10:00 Стоматолог (calendar #k3f9a2c1)"
        let rows = Plan.rows(from: body)
        XCTAssertEqual(rows.filter(\.isTask).count, 1, "отметка события — не наше дело")
        XCTAssertEqual(Plan.body(from: rows).trimmingCharacters(in: .newlines), body, "строка не теряется")
        XCTAssertEqual(DayEvents.marks(in: rows).first?.key, "k3f9a2c1")
    }

    func testСделанноеИУбранное() {
        let items = [
            DayEvents.Item(key: "aaaa1111", title: "Стоматолог", time: "10:00", bell: "09:45",
                           repeats: true, color: .red, start: Date()),
            DayEvents.Item(key: "bbbb2222", title: "Звонок", time: "12:00", bell: nil,
                           repeats: false, color: .blue, start: Date()),
        ]
        let marks = [
            DayEvents.Mark(key: "aaaa1111", done: true, time: "10:00", title: "Стоматолог"),
            DayEvents.Mark(key: "bbbb2222", hidden: true, time: "12:00", title: "Звонок"),
            DayEvents.Mark(key: "cccc3333", done: true, time: "08:00", title: "Уже удалено из Календаря"),
        ]
        let shown = DayEvents.shown(items, marks: marks)
        XCTAssertEqual(shown.map(\.key), ["aaaa1111", "cccc3333"])
        XCTAssertEqual(shown.first?.row.done, true)
        XCTAssertEqual(shown.first?.row.bell, "09:45")
        XCTAssertNotNil(shown.first?.row.repeats)
    }

    func testКлючПостоянныйИКороткий() {
        XCTAssertEqual(DayEvents.short("ABC-123"), DayEvents.short("ABC-123"))
        XCTAssertNotEqual(DayEvents.short("ABC-123"), DayEvents.short("ABC-124"))
        XCTAssertEqual(DayEvents.short("x").count, 8)
    }
}

/// P586: одно правило, куда встаёт вложение, — для переноса в тексте и из
/// ленты: голос под текстом своей строкой, к ряду вложений — в ряд, точка
/// и снимок вместе.
final class FileLineTests: XCTestCase {

    func testГолосПодФразойСвоейСтрокой() {
        let голос = "[Голос 1](Audio/2026/a.m4a)"
        XCTAssertEqual(DiaryEditor.putting(голос, at: 3, into: "Утром гуляли и пили чай").0,
                       "Утром гуляли и пили чай\n" + голос)
    }

    func testСнимокКТочкеВРяд() {
        let точка = "[Дом](geo:51.5,-0.1)"
        let снимок = "![](Photos/a.heic)"
        XCTAssertEqual(DiaryEditor.putting(снимок, at: 1, into: точка + "\nВечер").0,
                       точка + " " + снимок + "\nВечер")
    }

    func testСнимокНеВстаётВСтрокуСТочкойПосредиТекста() {
        let строка = "Были [Дом](geo:51.5,-0.1) вечером"
        let снимок = "![](Photos/a.heic)"
        XCTAssertEqual(DiaryEditor.putting(снимок, at: 2, into: строка).0,
                       строка + "\n" + снимок)
    }
}
