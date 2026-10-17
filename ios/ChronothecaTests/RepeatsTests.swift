import XCTest
@testable import Chronotheca

/// Повторяющиеся дела (P359): пометка в строке, дни повторов и запись в
/// файлы будущих дней — без порчи того, что там уже лежит.
final class RepeatsTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!
    private let cal = Calendar.current

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("повторы-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        vault = Vault()
        vault.adopt(folder)
        vault.acceptProposal()
    }

    override func tearDown() {
        vault.forget()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testПометкаСерииВСтрокеДела() {
        let line = "- [ ] 19:00 Вынести мусор (remind 18:30) (every week #k3f9a2)"
        let rows = Plan.rows(from: line)
        XCTAssertEqual(rows.first?.text, "Вынести мусор")
        XCTAssertEqual(rows.first?.bell, "18:30")
        XCTAssertEqual(rows.first?.repeats, Repeat(every: .week, series: "k3f9a2"))
        XCTAssertEqual(Plan.body(from: rows), line, "в файл ложится как было")
        XCTAssertNil(Plan.rows(from: "- [ ] Просто дело").first?.repeats)
    }

    func testДниПовторов() {
        let недели = Repeats.dates(.week, anchor: day(2026, 10, 1), after: day(2026, 10, 1),
                                   through: day(2026, 10, 31))
        XCTAssertEqual(недели, [day(2026, 10, 8), day(2026, 10, 15), day(2026, 10, 22), day(2026, 10, 29)])

        // 31-е в коротком месяце — последний его день, а дальше снова 31-е.
        let месяцы = Repeats.dates(.month, anchor: day(2026, 1, 31), after: day(2026, 1, 31),
                                   through: day(2026, 4, 30))
        XCTAssertEqual(месяцы, [day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30)])

        let годы = Repeats.dates(.year, anchor: day(2028, 2, 29), after: day(2028, 2, 29),
                                 through: day(2032, 3, 1))
        XCTAssertEqual(годы, [day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28), day(2032, 2, 29)])
    }

    func testПовторВписываетсяИЧужоеНеТрогается() {
        let завтра = cal.date(byAdding: .day, value: 1, to: DayStore.today())!
        // В файле завтрашнего дня уже есть своё — оно должно остаться.
        vault.write("- [ ] Своё дело\nЗаметка в конце", to: .planner, for: завтра)

        var s = Series(id: "abc123", every: "week", anchor: Vault.stamp(DayStore.today()),
                       until: Vault.stamp(DayStore.today()), time: "19:00", bell: nil,
                       text: "Вынести мусор", missed: nil)
        XCTAssertTrue(Repeats.put(s, on: завтра, vault: vault))
        XCTAssertTrue(Repeats.put(s, on: завтра, vault: vault), "второй раз — не дважды")
        let текст = vault.read(.planner, for: завтра)
        XCTAssertTrue(текст.contains("- [ ] Своё дело"))
        XCTAssertTrue(текст.contains("Заметка в конце"))
        XCTAssertEqual(текст.components(separatedBy: "#abc123").count - 1, 1)

        // Дописать на месяц: открытый день фоном не трогается.
        let через = cal.date(byAdding: .day, value: 7, to: DayStore.today())!
        Repeats.extend(&s, through: cal.date(byAdding: .day, value: 30, to: DayStore.today())!,
                       vault: vault, open: через)
        XCTAssertFalse(vault.read(.planner, for: через).contains("#abc123"), "открытый день не трогаем")
        XCTAssertEqual(s.missed, [Vault.stamp(через)])
        let потом = cal.date(byAdding: .day, value: 14, to: DayStore.today())!
        XCTAssertTrue(vault.read(.planner, for: потом).contains("19:00 Вынести мусор"))

        // Убрать повтор из одного дня — остальное в файле на месте.
        XCTAssertTrue(Repeats.edit("abc123", on: завтра, vault: vault) { rows, k in _ = rows.remove(at: k) })
        let после = vault.read(.planner, for: завтра)
        XCTAssertFalse(после.contains("#abc123"))
        XCTAssertTrue(после.contains("- [ ] Своё дело"))
    }
}
