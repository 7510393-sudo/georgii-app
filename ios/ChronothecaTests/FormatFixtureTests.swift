import XCTest
@testable import Chronotheca

/// Эталоны формата архива (P951, `docs/69`): маленький архив во всех видах
/// лежит в `Fixtures/Archive`, а здесь — что из него должно прочитаться.
///
/// Это обещание людям, чьи записи лежат в таком виде: эталон меняется
/// только вместе с решением в журнале. Вложения в конце записи и плана
/// проверяются только на то, что ни одно не пропало: их место на странице
/// ещё меняется (нижний ряд уходит в текст, P905).
final class FormatFixtureTests: XCTestCase {

    // MARK: - Чтение эталонов

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Archive")

    private func raw(_ path: String) throws -> String {
        let url = Self.root.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func file(_ path: String) throws -> DayFile {
        DayFile(text: try raw(path))
    }

    private func plan(_ day: String) throws -> [PlanRow] {
        Plan.rows(from: try file("Planner/2026/\(day).md").body)
    }

    /// Все ссылки на вложения в тексте — чтобы проверить, что ни одна не
    /// пропала при разборе.
    private func links(in text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let found = Diary.objects(in: line).filter { $0.point == nil }.map(\.link)
                + Diary.anywhere(in: line).map(\.link)
            for link in found where !out.contains(link) { out.append(link) }
        }
        return out
    }

    func testЭталоныНаМесте() throws {
        let all = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
        XCTAssertGreaterThanOrEqual(all.count, 20, "эталоны не найдены: \(Self.root.path)")
    }

    // MARK: - План

    func testПланПростыеДела() throws {
        let rows = try plan("2026-01-01")
        XCTAssertEqual(rows.filter(\.isTask).map(\.text),
                       ["Позвонить маме", "Купить хлеб", "Сделано большой буквой"])
        XCTAssertEqual(rows.filter(\.isTask).map(\.done), [false, true, true])
        // «[X]» читается и пишется строчной — больше ничего не меняется.
        let body = try file("Planner/2026/2026-01-01.md").body
        XCTAssertEqual(Plan.body(from: rows), body.replacingOccurrences(of: "[X]", with: "[x]"))
    }

    func testПланВремяНапоминаниеПовторПродолжение() throws {
        let rows = try plan("2026-01-02").filter(\.isTask)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].time, "09:00")
        XCTAssertEqual(rows[0].bell, "08:30")
        XCTAssertEqual(rows[0].text, "Позвонить в банк")
        XCTAssertEqual(rows[1].repeats, Repeat(every: .day, series: "k3f9"))
        XCTAssertTrue(rows[1].done)
        XCTAssertEqual(rows[2].bell, "17:30")
        XCTAssertEqual(rows[2].repeats, Repeat(every: .week, series: "ab12cd"))
        XCTAssertEqual(rows[2].text, "Бассейн")
        XCTAssertEqual(rows[3].text, "Встреча: обсудить отпуск")
        XCTAssertEqual(rows[4].details, ["Малая Бронная 12, второй этаж.",
                                         "Взять оригинал доверенности."])
        // Туда и обратно — байт в байт.
        let body = try file("Planner/2026/2026-01-02.md").body
        XCTAssertEqual(Plan.body(from: Plan.rows(from: body)), body)
    }

    func testПланОтметкиКалендаряИЧужиеСтроки() throws {
        let rows = try plan("2026-01-03")
        let marks = DayEvents.marks(in: rows)
        XCTAssertEqual(marks.map(\.key), ["ev12ab34", "ev99zz00"])
        XCTAssertEqual(marks[0].time, "10:00")
        XCTAssertTrue(marks[0].done)
        XCTAssertEqual(marks[0].title, "Стоматолог")
        XCTAssertTrue(marks[1].hidden)
        // Отметка события — не дело: строкой файла как есть.
        XCTAssertEqual(rows.filter(\.isTask).map(\.text), ["Написать письмо"])
        XCTAssertTrue(rows.contains { $0.verbatim == "## Утро" })
        XCTAssertTrue(rows.contains { $0.verbatim == "Заметка без отметки — просто строка." })
        let body = try file("Planner/2026/2026-01-03.md").body
        XCTAssertEqual(Plan.body(from: rows), body)
    }

    func testПланБезШапкиИНеДела() throws {
        let f = try file("Planner/2026/2026-01-04.md")
        XCTAssertTrue(f.meta.isEmpty)
        let rows = Plan.rows(from: f.body)
        let tasks = rows.filter(\.isTask)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertNil(tasks[0].time, "25:00 — не время")
        XCTAssertEqual(tasks[0].text, "25:00 Не время, а название")
        XCTAssertEqual(tasks[1].bell, "08:30", "прежнее «(напомнить …)» читается")
        XCTAssertNil(tasks[2].bell)
        XCTAssertEqual(tasks[2].text, "Дело со скобками (не напоминание)")
        XCTAssertEqual(rows.compactMap(\.verbatim),
                       ["- [] не дело: нет пробела в скобках", "* [ ] не дело: звёздочка"])
        // Обратно меняется только прежнее напоминание — на английское.
        XCTAssertEqual(Plan.body(from: rows),
                       f.body.replacingOccurrences(of: "(напомнить 08:30)", with: "(remind 08:30)"))
    }

    func testПланВложенияНеТеряются() throws {
        let body = try file("Planner/2026/2026-01-05.md").body
        let rows = Plan.rows(from: body)
        let split = Plan.splitPhotos(rows)
        let kept = links(in: Plan.body(from: split.rows, photos: split.photos))
        for link in links(in: body) {
            XCTAssertTrue(kept.contains(link), "пропало вложение \(link)")
        }
        XCTAssertEqual(rows.filter(\.isTask).map(\.text), ["Прогулка в парке", "Записать мысль"])
    }

    func testПланИзWindows() throws {
        let f = try file("Planner/2026/2026-01-06.md")
        XCTAssertEqual(f.value("date"), "2026-01-06")
        let rows = Plan.rows(from: f.body)
        XCTAssertEqual(rows.count, 2, "«\\r\\n» не даёт лишних пустых строк")
        XCTAssertEqual(rows[1].details, ["продолжение"])
        XCTAssertFalse(f.text.contains("\r"))
    }

    func testПланЧужаяШапкаОстаётся() throws {
        let text = try raw("Planner/2026/2026-01-07.md")
        let f = DayFile(text: text)
        XCTAssertEqual(f.value("tags"), "[работа, дом]")
        XCTAssertEqual(f.value("source"), "obsidian")
        XCTAssertEqual(f.text, text)
    }

    // MARK: - Дневник

    func testДневникПолнаяШапкаИОтветы() throws {
        let f = try file("Diary/2026/2026-01-01.md")
        XCTAssertEqual(f.value("title"), "Первый день года")
        XCTAssertNotNil(f.value("place").flatMap(Geo.parse))
        XCTAssertEqual(f.value("weather"), "+3 °C, snow")
        XCTAssertNotNil(f.value("edited").flatMap(DayStore.moment(from:)), "edited — yyyy-MM-ddTHH:mm")
        let known = try plan("2026-01-01").filter(\.isTask).map(\.text)
        let diary = Diary(body: f.body, known: known)
        XCTAssertEqual(diary.answers, ["Позвонить маме": "поговорили час", "Купить хлеб": "взял два"])
        XCTAssertTrue(diary.text.hasPrefix("08:15 Проснулся раньше будильника."))
        let kept = links(in: diary.text) + diary.photos
        for link in links(in: f.body) {
            XCTAssertTrue(kept.contains(link), "пропало вложение \(link)")
        }
    }

    func testДневникОтветыСДвоеточиями() throws {
        let known = try plan("2026-01-02").filter(\.isTask).map(\.text)
        let body = try file("Diary/2026/2026-01-02.md").body
        let diary = Diary(body: body, known: known)
        XCTAssertEqual(diary.answers["Позвонить в банк"], "дозвонился в 10:30")
        XCTAssertEqual(diary.answers["Встреча: обсудить отпуск"], "перенесли на март")
        // Дела с таким названием нет — по первому двоеточию.
        XCTAssertEqual(diary.answers["Название без дела в плане"], "ответ: с двоеточием")
        XCTAssertEqual(diary.text, "Текст дня.")
        // Туда и обратно ответы те же.
        let again = Diary(body: diary.body(order: known), known: known)
        XCTAssertEqual(again.answers, diary.answers)
        XCTAssertEqual(again.text, diary.text)
    }

    func testДневникБезШапкиЗаголовокНижеТекст() throws {
        let f = try file("Diary/2026/2026-01-03.md")
        XCTAssertTrue(f.meta.isEmpty)
        let diary = Diary(body: f.body)
        XCTAssertTrue(diary.answers.isEmpty, "заголовок ниже начала — текст человека")
        XCTAssertTrue(diary.text.contains("## How did it go?"))
        XCTAssertTrue(diary.text.contains("- это уже текст человека: не ответ"))
    }

    func testДневникГолосСсылкиТочки() throws {
        let body = try file("Diary/2026/2026-01-04.md").body
        let diary = Diary(body: body)
        let lines = diary.text.components(separatedBy: "\n")
        let voice = "[2026-01-04_10.00.00](../../Audio/2026/2026-01-04_10.00.00.m4a)"
        let at = try XCTUnwrap(lines.firstIndex(of: voice), "голос — своей строкой")
        XCTAssertEqual(lines[at + 1], "Расшифровка голоса — строкой под ссылкой.")
        XCTAssertEqual(Diary.picture(in: voice), "../../Audio/2026/2026-01-04_10.00.00.m4a")
        // Путь с пробелом — в угловых скобках, снимок посреди фразы.
        XCTAssertEqual(Diary.anywhere(in: diary.text).map(\.link),
                       ["../../Photos/2026/2026-01-04_11.00.00 2.heic"])
        // Ссылка на сайт — не вложение.
        XCTAssertNil(Diary.picture(in: "[Apple](https://apple.com)"))
        // Точки — с названием и без.
        XCTAssertNotNil(Diary.point(in: "[Дом](geo:51.50735,-0.12776)"))
        XCTAssertNotNil(Diary.point(in: "geo:48.85661,2.35222"))
        XCTAssertTrue(diary.photos.isEmpty, "строка с текстом — не ряд вложений")
    }

    func testДневникТолькоШапка() throws {
        let f = try file("Diary/2026/2026-01-05.md")
        XCTAssertEqual(f.value("title"), "Только шапка")
        XCTAssertEqual(f.body, "")
    }

    func testДневникНачинаетсяЧертой() throws {
        let f = try file("Diary/2026/2026-01-06.md")
        XCTAssertTrue(f.meta.isEmpty, "без второй черты шапки нет")
        XCTAssertTrue(f.body.contains("Файл начинается чертой разделителя: это не шапка."))
        XCTAssertTrue(f.body.contains("И здесь нет второй черты."))
        XCTAssertTrue(f.body.hasPrefix("---"))
    }

    func testДневникЧужойКлючШапки() throws {
        let text = try raw("Diary/2026/2026-01-07.md")
        let f = DayFile(text: text)
        XCTAssertEqual(f.value("mood"), "😊")
        XCTAssertEqual(f.text, text)
    }

    func testДневникИзWindows() throws {
        let f = try file("Diary/2026/2026-01-08.md")
        XCTAssertEqual(f.value("date"), "2026-01-08")
        XCTAssertEqual(f.body, "Запись из Windows.\nВторая строка.")
    }

    func testДневникВложенияВКонцеНеТеряются() throws {
        let body = try file("Diary/2026/2026-01-09.md").body
        let diary = Diary(body: body)
        let kept = links(in: diary.text) + diary.photos
        XCTAssertEqual(links(in: body).count, 3)
        for link in links(in: body) {
            XCTAssertTrue(kept.contains(link), "пропало вложение \(link)")
        }
        let again = Diary(body: diary.body(order: []))
        XCTAssertEqual(Set(links(in: again.text) + again.photos), Set(kept))
    }

    func testВтораяВерсияНеДень() {
        XCTAssertNil(Vault.date(from: "2026-01-03 — second version 10.15.00"))
        XCTAssertNotNil(Vault.date(from: "2026-01-03"))
    }

    // MARK: - Места

    func testМеста() throws {
        let home = try XCTUnwrap(Place(text: try raw("Places/Дом.md"), file: "Дом.md"))
        XCTAssertEqual(home.name, "Дом")
        XCTAssertEqual(home.latitude, 51.50735, accuracy: 0.000001)
        XCTAssertEqual(home.longitude, -0.12776, accuracy: 0.000001)
        XCTAssertEqual(home.text, "Заметка о месте.")
        XCTAssertEqual(home.mark, "дом", "значок в файле — английским словом")

        let old = try XCTUnwrap(Place(text: try raw("Places/Старое место.md"), file: "Старое место.md"))
        XCTAssertEqual(old.latitude, 48.85661, accuracy: 0.000001, "координаты и в виде geo:")
        XCTAssertEqual(old.mark, "дом", "прежнее русское слово значка читается")

        XCTAssertNil(Place(text: try raw("Places/Без координат.md"), file: "Без координат.md"),
                     "без координат — не место")
    }
}
