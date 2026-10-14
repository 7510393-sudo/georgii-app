import XCTest
import SQLite3
@testable import Chronotheca

/// Архив Diarium — база SQLite (P476). Базу собираем сами по схеме, какой её
/// видно в самом файле: Entries, Tags, EntryTags, Media.
final class DiariumImportTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("diarium-\(UUID().uuidString).diary")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func make(_ statements: [String]) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        sqlite3_close(db)
    }

    /// 17 мая 2024, 08:12 по часам на стене, в тиках .NET.
    private let ticks: Int64 = 638_515_008_000_000_000 + (8 * 3600 + 12 * 60) * 10_000_000

    func testTicksBecomeWallClockDayAndTime() {
        let m = DiariumReader.moment(ticks)
        XCTAssertEqual(m?.day, "2024-05-17")
        XCTAssertEqual(m?.time, "08:12")
    }

    func testDigitsAndUnixDates() {
        XCTAssertEqual(DiariumReader.moment(20_240_517_081_230)?.day, "2024-05-17")
        XCTAssertEqual(DiariumReader.moment(20_240_517_081_230)?.time, "08:12")
        XCTAssertEqual(DiariumReader.moment(1_715_933_520)?.day.prefix(7), "2024-05")
        XCTAssertEqual(DiariumReader.moment(1_715_933_520_000)?.day.prefix(7), "2024-05")
        XCTAssertNil(DiariumReader.moment(42))
    }

    func testReadsTextTagsPlaceAndMedia() throws {
        make([
            "CREATE TABLE Entries(DiaryEntryId bigint primary key not null, Heading varchar not null, "
                + "Text varchar not null, Rating integer not null, Latitude float not null, Longitude float not null)",
            "CREATE TABLE Tags(DiaryTagId integer primary key autoincrement not null, Name varchar not null)",
            "CREATE TABLE EntryTags(DiaryEntryId bigint not null, DiaryTagId integer not null)",
            "CREATE TABLE Media(MediaId integer primary key autoincrement not null, DiaryEntryId bigint not null, "
                + "Type integer not null, Data blob, FileName varchar not null, \"Index\" integer not null)",
            "INSERT INTO Entries VALUES(\(ticks), 'Утро', '<p>Был в парке.</p><p>Тепло.</p>', 0, 51.5073, -0.1657)",
            "INSERT INTO Tags VALUES(1, 'прогулка')",
            "INSERT INTO EntryTags VALUES(\(ticks), 1)",
            "INSERT INTO Media VALUES(1, \(ticks), 0, x'ffd8ffe0', 'IMG_8898.jpg', 0)",
        ])
        let reader = try DiariumReader(copying: url)
        let list = try reader.entries()
        XCTAssertEqual(list.count, 1)
        let e = try XCTUnwrap(list.first)
        XCTAssertEqual(e.day, "2024-05-17")
        XCTAssertEqual(e.time, "08:12")
        XCTAssertTrue(e.text.contains("Был в парке."))
        XCTAssertFalse(e.text.contains("<p>"))
        XCTAssertEqual(e.tags, ["прогулка"])
        XCTAssertEqual(e.place, "[](geo:51.50730,-0.16570)")
        let media = try XCTUnwrap(e.media.values.first)
        XCTAssertEqual(media.folder, "photos")
        let file = try XCTUnwrap(reader.extract(media.file))
        XCTAssertEqual(try Data(contentsOf: file), Data([0xff, 0xd8, 0xff, 0xe0]))
    }

    func testDatabaseIsRecognisedByItsHeader() {
        make(["CREATE TABLE Entries(DiaryEntryId bigint, Text varchar)"])
        XCTAssertTrue(DiariumReader.looksLikeDatabase(url))
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("plain-\(UUID().uuidString).txt")
        try? Data("hello".utf8).write(to: plain)
        defer { try? FileManager.default.removeItem(at: plain) }
        XCTAssertFalse(DiariumReader.looksLikeDatabase(plain))
    }

    func testUnreadableDatesGiveAnExplanationInsteadOfWriting() {
        make([
            "CREATE TABLE Entries(DiaryEntryId bigint primary key not null, Text varchar not null)",
            "INSERT INTO Entries VALUES(7, 'текст')",
        ])
        XCTAssertThrowsError(try DiariumReader(copying: url).entries())
    }

    /// Вложения, записанные с лишним в начале, сжатые или текстом base64,
    /// приводятся к настоящему файлу (P487).
    func testAttachmentsAreNormalised() {
        let jpeg: [UInt8] = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]
        let plain = DiariumReader.normalized(Data(jpeg))
        XCTAssertEqual(Array(plain.0), jpeg)
        XCTAssertNil(plain.1)
        // Лишние байты впереди.
        let prefixed = DiariumReader.normalized(Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09] + jpeg))
        XCTAssertEqual(Array(prefixed.0), jpeg)
        // Base64-текст.
        let text = DiariumReader.normalized(Data(Data(jpeg + [UInt8](repeating: 0, count: 12)).base64EncodedString().utf8))
        XCTAssertEqual(Array(text.0.prefix(6)), jpeg)
        // Неизвестное — как есть и с заметкой.
        let odd = DiariumReader.normalized(Data([UInt8](repeating: 0x7f, count: 40)))
        XCTAssertNotNil(odd.1)
    }

    func testSniffFindsTheRealExtension() {
        XCTAssertEqual(DiariumFix.sniff([0xff, 0xd8, 0xff, 0xe1, 0, 0]), "jpg")
        XCTAssertEqual(DiariumFix.sniff([0x89, 0x50, 0x4e, 0x47, 0, 0]), "png")
        XCTAssertEqual(DiariumFix.sniff(Array("\0\0\0\u{18}ftypheic".utf8)), "heic")
        XCTAssertEqual(DiariumFix.sniff(Array("\0\0\0\u{18}ftypqt  ".utf8)), "mov")
        XCTAssertNil(DiariumFix.sniff([1, 2, 3, 4, 5, 6]))
    }

    /// Снимок, что лёг без расширения в «Документы», получает расширение,
    /// уходит в «Фотографии», а ссылка в записи меняется (P489).
    func testFixRenamesFilesAndRewritesLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fix-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let docs = root.appendingPathComponent("Documents/2024")
        let diary = root.appendingPathComponent("Diary/2024")
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try fm.createDirectory(at: diary, withIntermediateDirectories: true)
        try Data([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]).write(to: docs.appendingPathComponent("2024-05-17_diarium_IMG_8898."))
        let day = diary.appendingPathComponent("2024-05-17.md")
        try "08:12 Утро\n\n[IMG_8898](../../Documents/2024/2024-05-17_diarium_IMG_8898.)\n".write(to: day, atomically: true, encoding: .utf8)

        XCTAssertEqual(DiariumFix.run(root: root), 1)
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("Photos/2024/2024-05-17_diarium_IMG_8898.jpg").path))
        XCTAssertFalse(fm.fileExists(atPath: docs.appendingPathComponent("2024-05-17_diarium_IMG_8898.").path))
        let text = try String(contentsOf: day, encoding: .utf8)
        XCTAssertTrue(text.contains("![](../../Photos/2024/2024-05-17_diarium_IMG_8898.jpg)"))
        XCTAssertFalse(text.contains("Documents"))
        // Повторно чинить нечего.
        XCTAssertEqual(DiariumFix.run(root: root), 0)
    }
}
