import XCTest
@testable import Chronotheca

/// Перенос прежнего ряда вложений плана в дневник (P959) — на настоящих
/// файлах во временной папке. Упала проверка — перенос может испортить
/// запись, выпускать нельзя.
final class StripMoveTests: XCTestCase {

    private var root: URL!
    private let fm = FileManager.default
    private let stamp = "2026-03-14"

    override func setUp() {
        super.setUp()
        root = fm.temporaryDirectory.appendingPathComponent("перенос-\(UUID().uuidString)")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        Vault.brokenWrites = nil
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
        Vault.brokenWrites = nil
        super.tearDown()
    }

    private func url(_ folder: Vault.Folder, _ day: String? = nil) -> URL {
        let d = day ?? stamp
        return Vault.folder(folder, in: root)
            .appendingPathComponent(String(d.prefix(4)))
            .appendingPathComponent(d + ".md")
    }

    private func put(_ text: String, _ folder: Vault.Folder, _ day: String? = nil) {
        let u = url(folder, day)
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: u)
    }

    private func read(_ folder: Vault.Folder, _ day: String? = nil) -> String? {
        try? String(contentsOf: url(folder, day), encoding: .utf8)
    }

    private let plan = """
    ---
    date: 2026-03-14
    ---

    - [x] 09:00 Позвонить маме
    - [ ] Купить хлеб
          с отрубями
    ![](../../Photos/2026/под-делом.jpg)

    ![](../../Photos/2026/a.jpg)
    ![](../../Photos/2026/b.jpg)
    [голос](../../Audio/2026/c.m4a)

    """

    private let diary = """
    ---
    date: 2026-03-14
    title: Пятница
    ---

    ## How did it go?

    - Позвонить маме: поговорили час

    Утром было солнце.

    ![](../../Photos/2026/d.jpg)

    """

    func testMovesRowToDiaryEnd() {
        put(plan, .planner)
        put(diary, .diary)
        let report = StripMove.run(root: root)
        XCTAssertEqual(report.moved, 1)
        XCTAssertEqual(report.attachments, 3)
        XCTAssertTrue(report.waiting.isEmpty)

        // План: дела и снимок под делом на месте, ряда нет.
        let newPlan = read(.planner) ?? ""
        let rows = StripMove.split(Plan.rows(from: DayFile(text: newPlan).body))
        XCTAssertTrue(rows.photos.isEmpty, newPlan)
        XCTAssertTrue(newPlan.contains("![](../../Photos/2026/под-делом.jpg)"))
        XCTAssertTrue(newPlan.contains("      с отрубями"))
        XCTAssertFalse(newPlan.contains("a.jpg"))

        // Дневник: текст и ответ те же, вложения — прежнее и три перенесённых.
        let file = DayFile(text: read(.diary) ?? "")
        let d = Diary(body: file.body, known: ["Позвонить маме", "Купить хлеб"])
        XCTAssertEqual(file.value("title"), "Пятница")
        XCTAssertEqual(d.text, "Утром было солнце.")
        XCTAssertEqual(d.answers["Позвонить маме"], "поговорили час")
        XCTAssertEqual(d.photos, ["../../Photos/2026/d.jpg", "../../Photos/2026/a.jpg",
                                  "../../Photos/2026/b.jpg", "../../Audio/2026/c.m4a"])

        // Копии прежних текстов — байт в байт.
        let backup = Vault.folder(.service, in: root).appendingPathComponent(StripMove.backupName)
        XCTAssertEqual(try? String(contentsOf: backup.appendingPathComponent("Planner/2026/\(stamp).md"),
                                   encoding: .utf8), plan)
        XCTAssertEqual(try? String(contentsOf: backup.appendingPathComponent("Diary/2026/\(stamp).md"),
                                   encoding: .utf8), diary)
        XCTAssertTrue(StripMove.isDone(root: root))
    }

    func testSecondPassChangesNothing() {
        put(plan, .planner)
        put(diary, .diary)
        _ = StripMove.run(root: root)
        let p = read(.planner), d = read(.diary)
        let again = StripMove.run(root: root)
        XCTAssertEqual(again.moved, 0)
        XCTAssertEqual(read(.planner), p)
        XCTAssertEqual(read(.diary), d)
    }

    func testNoDiaryYet() {
        put(plan, .planner)
        _ = StripMove.run(root: root)
        let d = Diary(body: DayFile(text: read(.diary) ?? "").body)
        XCTAssertEqual(d.text, "")
        XCTAssertEqual(d.photos.count, 3)
    }

    func testLinksAlreadyInDiaryOnlyCutPlan() {
        // Прошлый проход оборвался после записи дневника.
        put(plan, .planner)
        put(diary + "\n![](../../Photos/2026/a.jpg) ![](../../Photos/2026/b.jpg) [c](../../Audio/2026/c.m4a)\n", .diary)
        let before = read(.diary)
        let report = StripMove.run(root: root)
        XCTAssertEqual(report.moved, 1)
        XCTAssertEqual(report.attachments, 0)
        XCTAssertEqual(read(.diary), before)
        XCTAssertFalse((read(.planner) ?? "").contains("a.jpg"))
    }

    func testPlanWithoutRowUntouched() {
        let only = "- [ ] Дело\n![](../../Photos/2026/под-делом.jpg)\n"
        put(only, .planner)
        let report = StripMove.run(root: root)
        XCTAssertEqual(report.moved, 0)
        XCTAssertEqual(read(.planner), only)
        XCTAssertNil(read(.diary))
    }

    func testFileInCloudWaits() {
        put(plan, .planner)
        let stub = url(.diary).deletingLastPathComponent()
            .appendingPathComponent("." + url(.diary).lastPathComponent + ".icloud")
        try? fm.createDirectory(at: stub.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("заглушка".utf8).write(to: stub)
        let report = StripMove.run(root: root)
        XCTAssertEqual(report.waiting[stamp], "in iCloud")
        XCTAssertEqual(read(.planner), plan)
        XCTAssertFalse(StripMove.isDone(root: root))
    }

    func testSkippedDayWaits() {
        put(plan, .planner)
        let report = StripMove.run(root: root, skip: { _ in "open on screen" })
        XCTAssertEqual(report.waiting[stamp], "open on screen")
        XCTAssertEqual(read(.planner), plan)
        XCTAssertNil(read(.diary))
    }

    func testFailedWriteLeavesPlan() {
        put(plan, .planner)
        put(diary, .diary)
        Vault.brokenWrites = "диск полон"
        let report = StripMove.run(root: root)
        XCTAssertEqual(report.moved, 0)
        XCTAssertEqual(read(.planner), plan)
        XCTAssertEqual(read(.diary), diary)
    }

    func testSecondVersionNotTouched() {
        let aside = stamp + Vault.asideMark + "10.00.00"
        let u = Vault.folder(.planner, in: root).appendingPathComponent("2026")
            .appendingPathComponent(aside + ".md")
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(plan.utf8).write(to: u)
        _ = StripMove.run(root: root)
        XCTAssertEqual(try? String(contentsOf: u, encoding: .utf8), plan)
    }

    func testDiaryAddingKeepsText() {
        let raw = "Строка\n\nЕщё строка\n"
        let out = StripMove.diaryAdding(["../../Photos/2026/a.jpg"], to: raw, known: [])
        XCTAssertEqual(out, "Строка\n\nЕщё строка\n\n![](../../Photos/2026/a.jpg)\n")
    }
}
