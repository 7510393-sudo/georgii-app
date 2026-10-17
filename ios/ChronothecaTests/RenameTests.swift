import XCTest
@testable import Chronotheca

/// Перевод имён папок на английский (P353). Главное — ни одна запись и ни
/// один снимок не должны потеряться, где бы перевод ни оборвался.
final class RenameTests: XCTestCase {

    private var корень: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        корень = fm.temporaryDirectory.appendingPathComponent("перевод-\(UUID().uuidString)")
        try? fm.createDirectory(at: корень, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: корень)
        super.tearDown()
    }

    private func положить(_ путь: String, _ текст: String) {
        let url = корень.appendingPathComponent(путь)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(текст.utf8).write(to: url)
    }

    private func прочитать(_ путь: String) -> String? {
        try? String(contentsOf: корень.appendingPathComponent(путь), encoding: .utf8)
    }

    func testПапкаНаходитсяПодЛюбымИменем() {
        XCTAssertEqual(Vault.folder(.diary, in: корень).lastPathComponent, "Diary",
                       "новый архив — английские имена")
        try? fm.createDirectory(at: корень.appendingPathComponent("Дневник"),
                                withIntermediateDirectories: true)
        XCTAssertEqual(Vault.folder(.diary, in: корень).lastPathComponent, "Дневник",
                       "прежний архив — папка там, где лежит")
        try? fm.createDirectory(at: корень.appendingPathComponent("Diary"),
                                withIntermediateDirectories: true)
        XCTAssertEqual(Vault.folder(.diary, in: корень).lastPathComponent, "Diary")
    }

    func testТекстЗаписиПереводитсяТолькоВСвоихМестах() {
        let было = """
        ---
        дата: 2026-09-30
        заголовок: Туман
        значок: личное
        ---

        ## Как прошло?

        - Позвонить: место: у окна
        ![](../../Фотографии/2026/a.jpg) ![](<../../Документы/2026/b c.pdf>)
        Слово «Фотографии» в тексте остаётся.
        """
        let стало = Rename.translate(было)
        XCTAssertTrue(стало.contains("date: 2026-09-30"))
        XCTAssertTrue(стало.contains("title: Туман"))
        XCTAssertTrue(стало.contains("icon: private"))
        XCTAssertTrue(стало.contains(Diary.heading))
        XCTAssertTrue(стало.contains("- Позвонить: место: у окна"), "тело записи не трогается")
        XCTAssertTrue(стало.contains("![](../../Photos/2026/a.jpg) ![](<../../Documents/2026/b c.pdf>)"))
        XCTAssertTrue(стало.contains("Слово «Фотографии» в тексте остаётся."))
        XCTAssertEqual(Rename.translate(стало), стало, "второй раз — ничего нового")
        // Прочитанное до и после — одно и то же.
        XCTAssertEqual(DayFile(text: стало).value("title"), DayFile(text: было).value("заголовок"))
        XCTAssertEqual(Diary(body: DayFile(text: стало).body).answers,
                       Diary(body: DayFile(text: было).body).answers)
    }

    func testАрхивПереводитсяИНичегоНеТеряется() {
        положить("Дневник/2026/2026-09-30.md", "---\nзаголовок: Туман\n---\n\n![](../../Фотографии/2026/a.jpg)\n")
        положить("Планировщик/2026/2026-09-30.md", "- [ ] дело\n")
        положить("Фотографии/2026/a.jpg", "снимок")
        положить("Места/Дача.md", "---\nназвание: Дача\nместо: 55, 37\nзначок: личное\n---\n")
        положить("Служебное/" + Vault.oldNoteName, Vault.oldNoteText)
        положить("Корзина/2026-09-01/Дневник/2026-09-01.md", "убранное")

        let отчёт = Rename.run(in: корень)

        XCTAssertTrue(отчёт.stuck.isEmpty)
        XCTAssertEqual(отчёт.skipped, 0)
        XCTAssertEqual(прочитать("Diary/2026/2026-09-30.md"),
                       "---\ntitle: Туман\n---\n\n![](../../Photos/2026/a.jpg)\n")
        XCTAssertEqual(прочитать("Planner/2026/2026-09-30.md"), "- [ ] дело\n")
        XCTAssertEqual(прочитать("Photos/2026/a.jpg"), "снимок")
        XCTAssertEqual(прочитать("Trash/2026-09-01/Дневник/2026-09-01.md"), "убранное")
        XCTAssertEqual(Place(text: прочитать("Places/Дача.md") ?? "", file: "Дача.md")?.mark, "личное")
        XCTAssertEqual(прочитать("System/" + Vault.noteName), Vault.noteText)
        for прежнее in ["Дневник", "Планировщик", "Фотографии", "Места", "Служебное", "Корзина"] {
            XCTAssertFalse(fm.fileExists(atPath: корень.appendingPathComponent(прежнее).path), прежнее)
        }
    }

    func testОборванныйПереводДоводитсяИЧужоеНеЗатирается() {
        // Прошлый раз «Photos» уже завели, а часть снимков осталась в
        // «Фотографиях»; одноимённый снимок — другой.
        положить("Photos/2026/a.jpg", "новый")
        положить("Фотографии/2026/a.jpg", "другой")
        положить("Фотографии/2026/b.jpg", "второй")

        let отчёт = Rename.run(in: корень)

        XCTAssertEqual(отчёт.kept, 1)
        XCTAssertEqual(прочитать("Photos/2026/a.jpg"), "новый")
        XCTAssertEqual(прочитать("Photos/2026/b.jpg"), "второй")
        XCTAssertEqual(прочитать("Фотографии/2026/a.jpg"), "другой", "ни один снимок не пропал")
    }

    func testСтараяСсылкаНаходитСнимокВПереведённойПапке() {
        let vault = Vault()
        vault.adopt(корень)
        vault.acceptProposal()
        defer { vault.forget() }
        guard let root = vault.root else { return XCTFail("нет папки") }
        let снимок = Vault.folder(.photos, in: root).appendingPathComponent("2026/снимок.jpg")
        try? fm.createDirectory(at: снимок.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: снимок)
        let прежняя = "../../Фотографии/2026/" + снимок.lastPathComponent
        let день = Date()
        XCTAssertEqual(vault.mediaURL(прежняя, for: день)?.standardizedFileURL.path,
                       снимок.standardizedFileURL.path)
    }
}
