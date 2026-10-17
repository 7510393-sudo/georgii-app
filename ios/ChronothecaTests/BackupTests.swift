import XCTest
@testable import Chronotheca

/// Резервная копия (P368): копирует новое и изменённое, ничего не стирает в
/// копии, не трогает архив и не ложится в сам архив.
final class BackupTests: XCTestCase {

    private var archive: URL!
    private var place: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        Backup.reset()
        let base = fm.temporaryDirectory.appendingPathComponent("копия-\(UUID().uuidString)")
        archive = base.appendingPathComponent("Chronotheca")
        place = base.appendingPathComponent("Флешка")
        try? fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try? fm.createDirectory(at: place, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Backup.reset()
        try? fm.removeItem(at: archive.deletingLastPathComponent())
        super.tearDown()
    }

    private func put(_ path: String, _ text: String) {
        let url = archive.appendingPathComponent(path)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    private func copied(_ path: String) -> String? {
        try? String(contentsOf: place.appendingPathComponent(Backup.folderName).appendingPathComponent(path),
                    encoding: .utf8)
    }

    private func run() -> Backup.Report? {
        if case .success(let r) = Backup.run(archive: archive, size: 10, step: { _, _ in }) { return r }
        return nil
    }

    func testКопируетсяНовоеИНичегоНеСтирается() {
        put("Diary/2026/2026-10-01.md", "туман")
        put("Photos/2026/a.heic", "снимок")
        XCTAssertNil(Backup.choose(place))
        XCTAssertEqual(run()?.copied, 2)
        XCTAssertEqual(copied("Diary/2026/2026-10-01.md"), "туман")

        XCTAssertEqual(run()?.copied, 0, "второй раз — копировать нечего")

        // Запись поправили, другую удалили — в копии свежая и прежняя целы.
        Thread.sleep(forTimeInterval: 1.1)
        put("Diary/2026/2026-10-01.md", "туман рассеялся")
        try? fm.removeItem(at: archive.appendingPathComponent("Photos/2026/a.heic"))
        XCTAssertEqual(run()?.copied, 1)
        XCTAssertEqual(copied("Diary/2026/2026-10-01.md"), "туман рассеялся")
        XCTAssertEqual(copied("Photos/2026/a.heic"), "снимок", "в копии ничего не стирается")
        XCTAssertEqual(try? String(contentsOf: archive.appendingPathComponent("Diary/2026/2026-10-01.md"),
                                   encoding: .utf8), "туман рассеялся", "архив не тронут")
        XCTAssertNotNil(Backup.last)
    }

    /// Пять ступеней (P375): копия сверяется с описью, в ней лежит опись
    /// для человека, временных и пробных файлов не остаётся.
    func testСверкаИОписьВКопии() {
        put("Diary/2026/2026-10-02.md", "ясно")
        put("Photos/2026/b.heic", "снимок")
        XCTAssertNil(Backup.choose(place))
        XCTAssertEqual(run()?.complete, true)
        XCTAssertTrue(Backup.lastComplete)
        let target = place.appendingPathComponent(Backup.folderName)
        let note = try? String(contentsOf: target.appendingPathComponent(Backup.noteName), encoding: .utf8)
        XCTAssertNotNil(note, "опись лежит в самой копии")

        let names = (fm.enumerator(atPath: target.path)?.allObjects as? [String]) ?? []
        XCTAssertFalse(names.contains { ($0 as NSString).lastPathComponent.hasPrefix(".") },
                       "ни временных, ни пробных файлов")

        // Файл в копии испортился — сверка это видит, следующая копия чинит.
        try? Data("x".utf8).write(to: target.appendingPathComponent("Photos/2026/b.heic"))
        XCTAssertEqual(Backup.verify(Backup.inventory(archive), in: target), ["Photos/2026/b.heic"])
        XCTAssertEqual(run()?.copied, 1)
        XCTAssertEqual(copied("Photos/2026/b.heic"), "снимок")
    }

    /// P377: файл пропал из архива не через корзину приложения — копия это
    /// замечает и возвращает его, ничего не перезаписывая.
    func testИсчезнувшееЗамечаетсяИВозвращается() {
        put("Diary/2026/2026-10-03.md", "дождь")
        put("Photos/2026/c.heic", "снимок")
        XCTAssertNil(Backup.choose(place))
        XCTAssertNotNil(run())
        try? fm.removeItem(at: archive.appendingPathComponent("Photos/2026/c.heic"))
        let target = place.appendingPathComponent(Backup.folderName)
        let gone = Backup.vanished(Backup.inventory(archive), previous: Backup.previousList(),
                                   root: archive, target: target)
        XCTAssertEqual(gone, ["Photos/2026/c.heic"])
        XCTAssertEqual(Backup.bringBack(gone, archive: archive), 1)
        XCTAssertEqual(try? String(contentsOf: archive.appendingPathComponent("Photos/2026/c.heic"),
                                   encoding: .utf8), "снимок")
        XCTAssertEqual(Backup.bringBack(gone, archive: archive), 0, "лежащий на месте файл не трогается")
    }

    func testФайлыСравниваютсяБайтВБайт() {
        put("a.txt", "один")
        put("b.txt", "один")
        put("c.txt", "одна")
        XCTAssertTrue(Backup.same(archive.appendingPathComponent("a.txt"), archive.appendingPathComponent("b.txt")))
        XCTAssertFalse(Backup.same(archive.appendingPathComponent("a.txt"), archive.appendingPathComponent("c.txt")))
    }

    func testВСамАрхивКопияНеЛожится() {
        XCTAssertNotNil(Backup.trouble(with: archive, archive: archive))
        XCTAssertNotNil(Backup.trouble(with: archive.appendingPathComponent("Diary"), archive: archive))
        XCTAssertNil(Backup.trouble(with: place, archive: archive))
    }

    func testБезМестаНеКопирует() {
        guard case .failure(.noPlace) = Backup.run(archive: archive, size: 0, step: { _, _ in })
        else { return XCTFail("без выбранного места копии быть не должно") }
    }

    func testНапоминаниеПоГигабайтуИПоМесяцу() {
        let now = Date()
        XCTAssertNil(Backup.reminder(size: 100, now: now), "в первый день — не спрашивать")
        XCTAssertNotNil(Backup.reminder(size: Backup.gigabyte + 1, now: now), "гигабайт — спросить")
        let month = now.addingTimeInterval(31 * 86_400)
        XCTAssertNotNil(Backup.reminder(size: 100, now: month), "месяц и архив вырос — спросить")
        Backup.later()
        XCTAssertNil(Backup.reminder(size: Backup.gigabyte * 2, now: Date()), "после «Позже» — три дня тихо")
    }
}
