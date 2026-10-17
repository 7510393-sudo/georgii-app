import XCTest
@testable import Chronotheca

/// Перенос архива — самое опасное место в приложении: здесь можно потерять
/// написанное. Поэтому проверяется не «получилось ли», а «что стало с
/// каждым файлом»: ни один не должен пропасть ни при каком исходе.
final class TransferTests: XCTestCase {

    private var откуда: URL!
    private var куда: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        откуда = временная("откуда")
        куда = временная("куда")
    }

    override func tearDown() {
        try? fm.removeItem(at: откуда)
        try? fm.removeItem(at: куда)
        super.tearDown()
    }

    private func временная(_ имя: String) -> URL {
        let url = fm.temporaryDirectory
            .appendingPathComponent("\(имя)-\(UUID().uuidString)")
        for folder in Vault.Folder.allCases {
            try? fm.createDirectory(at: url.appendingPathComponent(folder.rawValue),
                                    withIntermediateDirectories: true)
        }
        return url
    }

    @discardableResult
    private func запись(_ корень: URL, _ дата: String, _ текст: String,
                        _ folder: Vault.Folder = .diary) -> URL {
        let url = корень
            .appendingPathComponent(folder.rawValue)
            .appendingPathComponent(String(дата.prefix(4)))
            .appendingPathComponent(дата + ".md")
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? Data(текст.utf8).write(to: url)
        return url
    }

    private func текст(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Опись

    func testСчитаютсяТолькоЗаписи() {
        запись(откуда, "2026-09-21", "вчера")
        запись(откуда, "2026-09-22", "сегодня")
        запись(откуда, "2026-09-22", "план", .planner)
        XCTAssertEqual(Transfer.records(in: откуда), 3)
    }

    func testСлужебноеНеПереносится() {
        try? Data("{}".utf8).write(
            to: откуда.appendingPathComponent(Vault.markerPath))
        запись(откуда, "2026-09-22", "текст")
        let список = Transfer.contents(of: откуда)
        XCTAssertEqual(список.count, 1)
        XCTAssertFalse(список.contains { $0.contains(Vault.Folder.service.rawValue) },
                       "метка архива у новой папки своя")
    }

    /// Не скачанный из iCloud файл лежит невидимой заглушкой — его тоже
    /// переносить, а не оставлять молча на старом месте (P426).
    func testЗаглушкаICloudВходитВОпись() {
        let папка = откуда.appendingPathComponent("Diary/2026")
        try? fm.createDirectory(at: папка, withIntermediateDirectories: true)
        try? Data().write(to: папка.appendingPathComponent(".2026-09-20.md.icloud"))
        try? Data().write(to: папка.appendingPathComponent(".DS_Store"))
        запись(откуда, "2026-09-22", "текст")
        XCTAssertEqual(Transfer.contents(of: откуда),
                       ["Diary/2026/2026-09-20.md", "Diary/2026/2026-09-22.md"])
        XCTAssertEqual(Transfer.records(in: откуда), 2)
    }

    /// Список повторяющихся дел переезжает вместе с записями (P427).
    func testСписокПовторовПереезжает() {
        let список = откуда.appendingPathComponent("System/" + Repeats.fileName)
        try? Data("[]".utf8).write(to: список)
        запись(откуда, "2026-09-22", "план", .planner)
        Transfer.move(Transfer.contents(of: откуда), from: откуда, to: куда)
        XCTAssertTrue(fm.fileExists(atPath: куда.appendingPathComponent("System/" + Repeats.fileName).path))
        XCTAssertFalse(fm.fileExists(atPath: список.path))
    }

    /// На новом месте за то же число — не скачанный файл: прочитать его
    /// нечем, писать поверх нельзя. Остаются оба (P426, P182).
    func testПоверхНеСкачанногоНеПишется() {
        let мой = запись(откуда, "2026-09-22", "мой текст")
        let папка = куда.appendingPathComponent("Diary/2026")
        try? fm.createDirectory(at: папка, withIntermediateDirectories: true)
        try? Data().write(to: папка.appendingPathComponent(".2026-09-22.md.icloud"))
        let отчёт = Transfer.move(Transfer.contents(of: откуда), from: откуда, to: куда)
        XCTAssertEqual(отчёт.kept, 1)
        XCTAssertEqual(текст(мой), "мой текст")
        XCTAssertFalse(fm.fileExists(atPath: папка.appendingPathComponent("2026-09-22.md").path))
    }

    // MARK: - Перенос

    func testЗаписиПереезжаютИИсчезаютСпрежнегоМеста() {
        запись(откуда, "2026-09-21", "вчера")
        запись(откуда, "2026-09-22", "сегодня")

        let отчёт = Transfer.move(Transfer.contents(of: откуда),
                                  from: откуда, to: куда)

        XCTAssertEqual(отчёт.moved, 2)
        XCTAssertEqual(отчёт.kept, 0)
        XCTAssertEqual(отчёт.failed, 0)
        XCTAssertEqual(Transfer.records(in: куда), 2)
        XCTAssertEqual(Transfer.records(in: откуда), 0,
                       "перенос — это перенос, а не копия")
        XCTAssertEqual(текст(куда.appendingPathComponent("Diary/2026/2026-09-22.md")),
                       "сегодня")
    }

    func testЧужаяЗаписьЗаТоЖеЧислоНеПерезаписывается() {
        запись(откуда, "2026-09-22", "то, что было записано раньше")
        запись(куда, "2026-09-22", "то, что записано здесь")

        let отчёт = Transfer.move(Transfer.contents(of: откуда),
                                  from: откуда, to: куда)

        XCTAssertEqual(отчёт.moved, 0)
        XCTAssertEqual(отчёт.kept, 1, "приложение не решает, какая запись важнее")
        XCTAssertEqual(текст(куда.appendingPathComponent("Diary/2026/2026-09-22.md")),
                       "то, что записано здесь", "на месте — нетронутая запись")
        XCTAssertEqual(текст(откуда.appendingPathComponent("Diary/2026/2026-09-22.md")),
                       "то, что было записано раньше", "прежняя тоже цела")
    }

    func testПовторныйПереносДоводитДоКонца() {
        // Так выглядит оборвавшийся перенос: копия уже легла, исходник ещё
        // не убран. Запуск заново должен прибрать лишнее, а не спасовать.
        запись(откуда, "2026-09-22", "одна и та же запись")
        запись(куда, "2026-09-22", "одна и та же запись")

        let отчёт = Transfer.move(Transfer.contents(of: откуда),
                                  from: откуда, to: куда)

        XCTAssertEqual(отчёт.moved, 1)
        XCTAssertEqual(отчёт.kept, 0, "одинаковые записи — это не спор")
        XCTAssertEqual(Transfer.records(in: откуда), 0)
        XCTAssertEqual(Transfer.records(in: куда), 1)
    }

    func testНиОдинФайлНеПропадает() {
        // Главная проверка: что бы ни случилось с каждым файлом, он остаётся
        // хотя бы в одном месте.
        запись(откуда, "2026-09-20", "переедет")
        запись(откуда, "2026-09-21", "поспорит")
        запись(куда, "2026-09-21", "уже здесь")
        запись(откуда, "2026-09-22", "одинаковая")
        запись(куда, "2026-09-22", "одинаковая")

        Transfer.move(Transfer.contents(of: откуда), from: откуда, to: куда)

        for дата in ["2026-09-20", "2026-09-21", "2026-09-22"] {
            let путь = "Diary/2026/\(дата).md"
            let есть = fm.fileExists(atPath: куда.appendingPathComponent(путь).path)
                || fm.fileExists(atPath: откуда.appendingPathComponent(путь).path)
            XCTAssertTrue(есть, "запись за \(дата) пропала")
        }
    }

    func testХодСчитаетсяПоФайлам() {
        запись(откуда, "2026-09-20", "раз")
        запись(откуда, "2026-09-21", "два")
        запись(откуда, "2026-09-22", "три")

        var шаги: [Int] = []
        Transfer.move(Transfer.contents(of: откуда), from: откуда, to: куда) {
            шаги.append($0)
        }
        XCTAssertEqual(шаги, [1, 2, 3])
    }

    func testВложенияПереезжаютВместеСЗаписями() {
        let фото = откуда
            .appendingPathComponent(Vault.Folder.photos.rawValue)
            .appendingPathComponent("2026")
        try? fm.createDirectory(at: фото, withIntermediateDirectories: true)
        try? Data([0xFF, 0xD8, 0xFF]).write(to: фото.appendingPathComponent("снимок.jpg"))
        запись(откуда, "2026-09-22", "текст")

        let отчёт = Transfer.move(Transfer.contents(of: откуда),
                                  from: откуда, to: куда)

        XCTAssertEqual(отчёт.moved, 2)
        XCTAssertTrue(fm.fileExists(atPath: куда
            .appendingPathComponent("Photos/2026/снимок.jpg").path))
    }

    /// Прежний архив с русскими именами папок, новый — с английскими
    /// (P353): записи ложатся в «Diary», а не в «Дневник» рядом с ним —
    /// иначе их бы не было видно.
    func testРусскиеПапкиЛожатсяВАнглийские() {
        let прежний = fm.temporaryDirectory.appendingPathComponent("прежний-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: прежний) }
        let день = прежний.appendingPathComponent("Дневник/2026/2026-09-22.md")
        try? fm.createDirectory(at: день.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("запись".utf8).write(to: день)

        let отчёт = Transfer.move(Transfer.contents(of: прежний), from: прежний, to: куда)

        XCTAssertEqual(отчёт.moved, 1)
        XCTAssertEqual(текст(куда.appendingPathComponent("Diary/2026/2026-09-22.md")), "запись")
        XCTAssertFalse(fm.fileExists(atPath: куда.appendingPathComponent("Дневник").path))
    }
}
