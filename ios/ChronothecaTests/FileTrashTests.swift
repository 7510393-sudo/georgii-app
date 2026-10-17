import XCTest
@testable import Chronotheca

/// Корзина файлов (P371): удалённый файл лежит там 30 дней, возвращается
/// на место и на страницу, нужный другому дню — не удаляется.
final class FileTrashTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        folder = fm.temporaryDirectory.appendingPathComponent("корзина-\(UUID().uuidString)")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        vault = Vault()
        vault.adopt(folder)
        vault.acceptProposal()
    }

    override func tearDown() {
        vault.forget()
        try? fm.removeItem(at: folder)
        super.tearDown()
    }

    private func photo(_ text: String = "снимок") -> String? {
        vault.addAttachment(Data(text.utf8), to: .photos, name: "2026-10-02_09.15.30.heic",
                            for: DayStore.today())
    }

    func testФайлУходитВКорзинуИВозвращаетсяНаСтраницу() {
        guard let link = photo(), let url = vault.mediaURL(link, for: DayStore.today())
        else { return XCTFail("снимок не лёг") }
        XCTAssertEqual(FileTrash.put(link, from: DayStore.today(), tab: "diary", vault: vault), .trashed)
        XCTAssertFalse(fm.fileExists(atPath: url.path), "на месте файла больше нет")
        XCTAssertEqual(vault.mediaURL(link, for: DayStore.today()).map { fm.fileExists(atPath: $0.path) }, true,
                       "по старой ссылке снимок виден из корзины")

        let entries = FileTrash.items(vault)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first.map { FileTrash.daysLeft($0) }, 30)
        guard let entry = entries.first else { return }
        XCTAssertTrue(FileTrash.restore(entry, vault))
        XCTAssertTrue(fm.fileExists(atPath: url.path), "файл вернулся на место")
        XCTAssertTrue(FileTrash.relink(entry, vault))
        XCTAssertTrue(vault.read(.diary, for: DayStore.today()).contains(Diary.line(link)),
                      "ссылка вернулась на страницу дня")
        XCTAssertTrue(FileTrash.items(vault).isEmpty)
    }

    func testНужныйДругомуДнюФайлНеУдаляется() {
        guard let link = photo() else { return XCTFail("снимок не лёг") }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: DayStore.today())!
        vault.write("Вчера\n\n" + Diary.line(link), to: .diary, for: yesterday)
        guard case .stillUsed = FileTrash.put(link, from: DayStore.today(), tab: "diary", vault: vault)
        else { return XCTFail("файл нужен вчерашнему дню — удалять нельзя") }
        XCTAssertTrue(FileTrash.items(vault).isEmpty)
    }

    func testЧерезТридцатьДнейСтирается() {
        guard let link = photo() else { return XCTFail("снимок не лёг") }
        XCTAssertEqual(FileTrash.put(link, from: DayStore.today(), tab: "plan", vault: vault), .trashed)
        FileTrash.purgeOld(vault, now: Date().addingTimeInterval(29 * 86_400))
        XCTAssertEqual(FileTrash.items(vault).count, 1, "29 дней — ещё лежит")
        FileTrash.purgeOld(vault, now: Date().addingTimeInterval(31 * 86_400))
        XCTAssertTrue(FileTrash.items(vault).isEmpty, "31 день — стёрт")
    }
}
