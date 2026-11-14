import XCTest
@testable import Chronotheca

/// Корзина дней (P295, P300): вкладку убирают по отдельности, возвращается
/// день целиком; на занятое место не возвращается — чужое не затирается.
final class TrashTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!

    override func setUp() {
        super.setUp()
        TrashClock.reset()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("корзина-\(UUID().uuidString)")
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

    private func write(_ text: String, _ part: Vault.Folder, _ date: Date) {
        let url = vault.file(part, for: date)!
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testДеньУходитИВозвращается() {
        let day = DayStore.today()
        write("Туман над полем.", .diary, day)
        write("- [ ] Отвезти документы", .planner, day)
        XCTAssertTrue(Trash.put(day, parts: Trash.allParts, in: vault))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.file(.diary, for: day)!.path))
        let items = Trash.items(in: vault)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.preview, "Туман над полем.")
        XCTAssertTrue(Trash.restore(items[0], in: vault))
        XCTAssertEqual(try? String(contentsOf: vault.file(.diary, for: day)!, encoding: .utf8),
                       "Туман над полем.")
        XCTAssertTrue(Trash.items(in: vault).isEmpty)
    }

    func testНаЗанятоеМестоНеВозвращается() {
        let day = DayStore.today()
        write("Старое.", .diary, day)
        Trash.put(day, parts: Trash.allParts, in: vault)
        write("Новое.", .diary, day)
        let item = Trash.items(in: vault)[0]
        XCTAssertFalse(Trash.restore(item, in: vault))
        XCTAssertEqual(try? String(contentsOf: vault.file(.diary, for: day)!, encoding: .utf8), "Новое.")
        XCTAssertEqual(Trash.items(in: vault).count, 1)
    }

    /// Всё в корзине — 30 дней, потом стирается (P373); дни без отметки
    /// (убранные до правила) получают её сейчас, а не стираются сразу.
    func testДеньСтираетсяЧерезТридцатьДней() {
        let day = DayStore.today()
        write("Туман.", .diary, day)
        XCTAssertTrue(Trash.put(day, parts: Trash.allParts, in: vault))
        XCTAssertEqual(Trash.items(in: vault).first?.daysLeft(), 30)
        Trash.purgeOld(vault, now: Date().addingTimeInterval(29 * 86_400))
        XCTAssertEqual(Trash.items(in: vault).count, 1, "29 дней — ещё лежит")
        Trash.purgeOld(vault, now: Date().addingTimeInterval(31 * 86_400))
        XCTAssertTrue(Trash.items(in: vault).isEmpty, "31 день — стёрт")
    }

    /// Убирают только открытую вкладку — другая остаётся на месте (P300).
    func testУбираетсяТолькоОднаВкладка() {
        let day = DayStore.today()
        write("Туман над полем.", .diary, day)
        write("- [ ] Отвезти документы", .planner, day)
        XCTAssertTrue(Trash.put(day, parts: [.diary], in: vault))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.file(.diary, for: day)!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.file(.planner, for: day)!.path))
        let items = Trash.items(in: vault)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(Trash.restore(items[0], in: vault))
        XCTAssertEqual(try? String(contentsOf: vault.file(.diary, for: day)!, encoding: .utf8),
                       "Туман над полем.")
    }

    /// Одна корзина (P954): день ложится в общую опись рядом с файлами, а
    /// не в свою папку; в списке файлов его нет.
    func testДеньЛожитсяВОбщуюКорзину() {
        let day = DayStore.today()
        write("Туман.", .diary, day)
        XCTAssertTrue(Trash.put(day, parts: Trash.allParts, in: vault))
        let entries = FileTrash.items(vault)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isDay)
        XCTAssertEqual(entries[0].path, "Diary/" + String(Vault.stamp(day).prefix(4)) + "/" + Vault.stamp(day) + ".md")
        let old = Vault.trash(in: vault.root!).appendingPathComponent(Vault.stamp(day))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "день лёг в прежнюю корзину")
    }

    /// Прежняя корзина дней (до P954) читается, возвращается и стирается.
    func testПрежняяКорзинаДнейЧитается() throws {
        let day = DayStore.today()
        let stamp = Vault.stamp(day)
        let old = Vault.trash(in: vault.root!).appendingPathComponent(stamp)
        let file = Vault.folder(.diary, in: old).appendingPathComponent(stamp + ".md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Прежний день.".write(to: file, atomically: true, encoding: .utf8)
        try stamp.write(to: old.appendingPathComponent(".deleted"), atomically: true, encoding: .utf8)

        let items = Trash.items(in: vault)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].preview, "Прежний день.")
        XCTAssertEqual(items[0].daysLeft(), 30)
        XCTAssertTrue(Trash.restore(items[0], in: vault))
        XCTAssertEqual(try? String(contentsOf: vault.file(.diary, for: day)!, encoding: .utf8), "Прежний день.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    /// Прежняя опись файлов (без поля `kind`) читается: файлы не пропадают.
    func testПрежняяОписьФайловЧитается() throws {
        let stamp = Vault.stamp(DayStore.today())
        let folder = FileTrash.base(vault.root!).appendingPathComponent(stamp)
        let stored = folder.appendingPathComponent("Photos/2026/old.heic")
        try FileManager.default.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: stored)
        let index = """
        [{"day":"\(stamp)","deleted":"\(stamp)","link":"../../Photos/2026/old.heic","path":"Photos/2026/old.heic","stored":"Photos/2026/old.heic","tab":"diary"}]
        """
        try index.write(to: folder.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        let entries = FileTrash.items(vault)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].isDay)
        XCTAssertTrue(Trash.items(in: vault).isEmpty, "файл показан днём")
    }

    /// PDF (P296): обложка и по странице на день; пустые дни пропущены;
    /// второй раз за тот же срок — новый файл рядом, первый цел.
    func testPDFОбложкаИДеньСНовойСтраницы() throws {
        let cal = Calendar.current
        let day = DayStore.today()
        let earlier = cal.date(byAdding: .day, value: -2, to: day)!
        write("Туман над полем.", .diary, day)
        write("- [ ] Отвезти документы", .planner, earlier)
        let first = try XCTUnwrap(PDFBook.make(.init(from: earlier, to: day), vault: vault))
        let pages = CGPDFDocument(first as CFURL)?.numberOfPages
        XCTAssertEqual(pages, 3)
        let second = try XCTUnwrap(PDFBook.make(.init(from: earlier, to: day), vault: vault))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        let empty = cal.date(byAdding: .day, value: -10, to: day)!
        XCTAssertNil(PDFBook.make(.init(from: empty, to: empty), vault: vault))
    }
}
