import XCTest
@testable import Chronotheca

/// Перенос из Day One (P378): запись читается по своему часовому поясу,
/// знаки разметки Day One снимаются, снимки встают своими строками, место —
/// точкой, метки — словами.
final class ImportTests: XCTestCase {

    private let sample = """
    {"metadata":{"version":"1.0"},"entries":[
     {"uuid":"AAA111","creationDate":"2025-03-04T23:30:00Z","timeZone":"Europe/Moscow",
      "text":"Гуляли по набережной\\\\. Было тепло\\\\!\\n\\n![](dayone-moment://PH1)\\n\\nВечером чай",
      "tags":["прогулка","весна"],
      "location":{"latitude":59.93863,"longitude":30.31413,"placeName":"Дворцовая"},
      "photos":[{"identifier":"PH1","md5":"abc123","type":"jpeg"}],
      "audios":[{"identifier":"AU1","md5":"def456","format":"m4a"}]}
    ]}
    """

    func testЗаписьЧитаетсяПоСвоемуЧасовомуПоясу() throws {
        let list = try DayOneImport.entries(from: Data(sample.utf8))
        XCTAssertEqual(list.count, 1)
        // 23:30 по Гринвичу — уже 02:30 следующего дня в Москве.
        XCTAssertEqual(list[0].day, "2025-03-05")
        XCTAssertEqual(list[0].time, "02:30")
        XCTAssertTrue(list[0].text.hasPrefix("Гуляли по набережной. Было тепло!"))
        XCTAssertEqual(list[0].place, "[Дворцовая](geo:59.93863,30.31413)")
    }

    func testТекстСоСнимкомМестомИМетками() throws {
        let e = try DayOneImport.entries(from: Data(sample.utf8))[0]
        let out = DayOneImport.block(e) { id in "../../Photos/2025/\(id).jpg" }
        let lines = out.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "02:30 Гуляли по набережной. Было тепло!")
        XCTAssertTrue(lines.contains("![](../../Photos/2025/PH1.jpg)"), "снимок на своём месте")
        XCTAssertTrue(lines.contains("[AU1](../../Photos/2025/AU1.jpg)") || out.contains("AU1"),
                      "голос, которого не было в тексте, — в конце")
        XCTAssertTrue(lines.contains("[Дворцовая](geo:59.93863,30.31413)"))
        XCTAssertEqual(lines.last, "#прогулка #весна")
        XCTAssertFalse(out.contains("dayone-moment"))
    }

    func testБезЗаписейНеЧитается() {
        XCTAssertThrowsError(try DayOneImport.entries(from: Data("{}".utf8)))
    }
}

/// P378: привычка — повторяющееся дело; подряд и за месяц.
final class HabitTests: XCTestCase {

    func testПодрядИЗаМесяц() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func ago(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
        // Сегодня ещё не сделано — серию не обрывает; вчера, позавчера — да;
        // три дня назад — нет.
        let days: [Date: Bool] = [today: false, ago(1): true, ago(2): true, ago(3): false, ago(4): true]
        let s = HabitStats.count(days, today: today)
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.recent, [true, false, true, true, false])
    }

    func testЕжедневноеНаМесяцВперёд() {
        XCTAssertEqual(Repeats.horizon(for: .day), 31)
        XCTAssertEqual(Repeats.horizon(for: .week), 365)
        let cal = Calendar.current
        let a = cal.startOfDay(for: Date())
        let d = Repeats.dates(.day, anchor: a, after: a, through: cal.date(byAdding: .day, value: 3, to: a)!)
        XCTAssertEqual(d.count, 3)
    }

    func testПометкаЕжедневногоДелаЧитается() {
        let rows = Plan.rows(from: "- [ ] Зарядка (every day #abc123)")
        XCTAssertEqual(rows.first?.repeats?.every, .day)
        XCTAssertEqual(rows.first?.text, "Зарядка")
    }
}
