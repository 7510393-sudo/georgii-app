import Foundation
import SQLite3

/// Архив Diarium — файл «Diarium_ГГГГ-ММ-ДД» (`.diary`), его делает кнопка
/// «Архивировать дневник» (P476). Это обычная база SQLite: таблицы `Entries`
/// (запись: заголовок, текст — HTML, широта, долгота), `Tags` и `EntryTags`
/// (метки), `Media` (вложения: имя файла и сами байты). Название столбцов
/// и устройство даты Apple и сам Diarium не описывают, поэтому разбор
/// терпеливый: таблицы и столбцы ищутся по именам, дата — по столбцу даты
/// или по номеру записи (его отдают как .NET-тики, число секунд или
/// миллисекунд, или как ГГГГММДДччммсс). Не вышло — перенос ничего не пишет и
/// показывает, что нашёл, чтобы можно было разобраться.
///
/// Работает с копией базы во временной папке: чужой файл не трогается, а
/// SQLite не просит рядом свой журнал. Вложения достаёт по одному, когда
/// они понадобились.
final class DiariumReader {

    typealias Entry = DayOneImport.Entry

    enum Failure: Error {
        case notDatabase
        case problem(String)
    }

    private var db: OpaquePointer?
    private let workDir: URL
    private let copyURL: URL

    /// Первые байты базы SQLite.
    static func looksLikeDatabase(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 15)) ?? Data()
        return String(data: head, encoding: .utf8) == "SQLite format 3"
    }

    init(copying url: URL) throws {
        let fm = FileManager.default
        workDir = fm.temporaryDirectory.appendingPathComponent("diarium-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        copyURL = workDir.appendingPathComponent("diary.sqlite")
        do { try fm.copyItem(at: url, to: copyURL) } catch {
            try? fm.removeItem(at: workDir)
            throw Failure.problem(error.localizedDescription)
        }
        guard sqlite3_open_v2(copyURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            try? fm.removeItem(at: workDir)
            throw Failure.notDatabase
        }
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Запросы

    private func query(_ sql: String, bind: Int64? = nil, each: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let st = statement else {
            let why = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw Failure.problem(why)
        }
        defer { sqlite3_finalize(st) }
        if let bind { sqlite3_bind_int64(st, 1, bind) }
        while sqlite3_step(st) == SQLITE_ROW { each(st) }
    }

    private static func text(_ st: OpaquePointer, _ i: Int32) -> String? {
        guard sqlite3_column_type(st, i) != SQLITE_NULL, let c = sqlite3_column_text(st, i) else { return nil }
        return String(cString: c)
    }

    private static func quoted(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func tables() throws -> [String] {
        var names: [String] = []
        try query("SELECT name FROM sqlite_master WHERE type = 'table'") { st in
            if let n = DiariumReader.text(st, 0) { names.append(n) }
        }
        return names
    }

    private func columns(of table: String) throws -> [String] {
        var names: [String] = []
        try query("PRAGMA table_info(\(DiariumReader.quoted(table)))") { st in
            if let n = DiariumReader.text(st, 1) { names.append(n) }
        }
        return names
    }

    /// Столбец по имени без учёта регистра.
    private static func pick(_ names: [String], _ wanted: [String]) -> String? {
        for w in wanted {
            if let hit = names.first(where: { $0.lowercased() == w.lowercased() }) { return hit }
        }
        return nil
    }

    // MARK: - Даты

    /// Когда сделана запись по числу из базы. Тики .NET, ГГГГММДДччммсс и
    /// им подобные — по часам на стене (без пояса); секунды и миллисекунды —
    /// по поясу телефона.
    static func moment(_ v: Int64) -> (date: Date, day: String, time: String)? {
        var cal = Calendar(identifier: .gregorian)
        var date: Date?
        if v > 600_000_000_000_000_000 {
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            date = Date(timeIntervalSince1970: Double(v - 621_355_968_000_000_000) / 10_000_000)
        } else if (19_000_000_000_000...22_000_000_000_000).contains(v)
                    || (190_000_000_000...220_000_000_000).contains(v)
                    || (19_000_000...22_000_000).contains(v) {
            let s = String(v)
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            var c = DateComponents()
            c.year = Int(s.prefix(4)); c.month = Int(s.dropFirst(4).prefix(2)); c.day = Int(s.dropFirst(6).prefix(2))
            c.hour = s.count >= 12 ? Int(s.dropFirst(8).prefix(2)) : 12
            c.minute = s.count >= 12 ? Int(s.dropFirst(10).prefix(2)) : 0
            c.second = s.count >= 14 ? Int(s.dropFirst(12).prefix(2)) : 0
            date = cal.date(from: c)
        } else if (900_000_000_000...4_200_000_000_000).contains(v) {
            date = Date(timeIntervalSince1970: Double(v) / 1000)
        } else if (100_000_000...4_200_000_000).contains(v) {
            date = Date(timeIntervalSince1970: Double(v))
        }
        guard let date else { return nil }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, (1990...2100).contains(y) else { return nil }
        return (date, String(format: "%04d-%02d-%02d", y, c.month ?? 0, c.day ?? 0),
                String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    // MARK: - Записи

    /// Все записи базы. Ничего не нашлось или дат не разобрать — ошибка со
    /// списком того, что в базе есть.
    func entries() throws -> [Entry] {
        let tableNames = try tables()
        guard let entriesTable = DiariumReader.pick(tableNames, ["Entries", "DiaryEntries", "Entry"]) else {
            throw Failure.problem("в базе нет таблицы записей; таблицы: " + tableNames.joined(separator: ", "))
        }
        let cols = try columns(of: entriesTable)
        guard let idCol = DiariumReader.pick(cols, ["DiaryEntryId", "EntryId", "Id"]) ?? cols.first else {
            throw Failure.problem("в таблице \(entriesTable) нет столбцов")
        }
        let dateCol = DiariumReader.pick(cols, ["Date", "DateTime", "Created", "CreatedAt", "CreationDate"])
        let headingCol = DiariumReader.pick(cols, ["Heading", "Title"])
        let textCol = DiariumReader.pick(cols, ["Text", "Content", "Body"])
        let latCol = DiariumReader.pick(cols, ["Latitude", "Lat"])
        let lonCol = DiariumReader.pick(cols, ["Longitude", "Lon", "Lng"])
        guard textCol != nil || headingCol != nil else {
            throw Failure.problem("в таблице \(entriesTable) нет текста; столбцы: " + cols.joined(separator: ", "))
        }

        // Метки и вложения — необязательные.
        var tagsOf: [String: [String]] = [:]
        if let link = DiariumReader.pick(tableNames, ["EntryTags"]), let tagTable = DiariumReader.pick(tableNames, ["Tags"]) {
            let linkCols = (try? columns(of: link)) ?? []
            let tagCols = (try? columns(of: tagTable)) ?? []
            let entryFK = DiariumReader.pick(linkCols, [idCol, "DiaryEntryId"])
            let tagFK = linkCols.first(where: { $0.lowercased().contains("tag") })
            let tagPK = tagFK.flatMap { fk in DiariumReader.pick(tagCols, [fk, "DiaryTagId", "TagId"]) } ?? tagCols.first
            let nameCol = DiariumReader.pick(tagCols, ["Name", "Title"])
            if let entryFK, let tagFK, let tagPK, let nameCol {
                try? query("SELECT l.\(DiariumReader.quoted(entryFK)), t.\(DiariumReader.quoted(nameCol)) FROM "
                           + "\(DiariumReader.quoted(link)) l JOIN \(DiariumReader.quoted(tagTable)) t "
                           + "ON t.\(DiariumReader.quoted(tagPK)) = l.\(DiariumReader.quoted(tagFK))") { st in
                    if let e = DiariumReader.text(st, 0), let n = DiariumReader.text(st, 1), !n.isEmpty {
                        tagsOf[e, default: []].append(n)
                    }
                }
            }
        }
        var mediaOf: [String: [(id: Int64, name: String)]] = [:]
        if let mediaTable = DiariumReader.pick(tableNames, ["Media", "Attachments"]) {
            let mCols = (try? columns(of: mediaTable)) ?? []
            if let entryFK = DiariumReader.pick(mCols, [idCol, "DiaryEntryId"]),
               let nameCol = DiariumReader.pick(mCols, ["FileName", "Name", "File"]) {
                let order = DiariumReader.pick(mCols, ["Index"]).map { " ORDER BY \(DiariumReader.quoted($0))" } ?? ""
                // Первые байты вложения — чтобы узнать настоящий вид файла, если
                // в имени нет расширения (P489).
                let head = DiariumReader.pick(mCols, ["Data", "Content", "Blob", "Bytes"])
                    .map { ", substr(\(DiariumReader.quoted($0)), 1, 32)" } ?? ""
                try? query("SELECT rowid, \(DiariumReader.quoted(entryFK)), \(DiariumReader.quoted(nameCol))" + head + " FROM "
                           + "\(DiariumReader.quoted(mediaTable))" + order) { st in
                    if let e = DiariumReader.text(st, 1), var n = DiariumReader.text(st, 2), !n.isEmpty {
                        if !DiariumFix.known.contains((n as NSString).pathExtension.lowercased()),
                           sqlite3_column_count(st) > 3, sqlite3_column_type(st, 3) == SQLITE_BLOB {
                            let len = Int(sqlite3_column_bytes(st, 3))
                            if len >= 4, let p = sqlite3_column_blob(st, 3) {
                                let bytes = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: len))
                                if let ext = DiariumFix.sniff(bytes) {
                                    while n.hasSuffix(".") { n.removeLast() }
                                    if !(n as NSString).pathExtension.isEmpty { n = (n as NSString).deletingPathExtension }
                                    n += "." + ext
                                }
                            }
                        }
                        mediaOf[e, default: []].append((sqlite3_column_int64(st, 0), n))
                    }
                }
            }
        }

        var select = [idCol]
        let at = { (c: String?) -> Int? in
            guard let c else { return nil }
            select.append(c)
            return select.count - 1
        }
        let dateAt = at(dateCol), headingAt = at(headingCol), textAt = at(textCol)
        let latAt = at(latCol), lonAt = at(lonCol)
        let sql = "SELECT " + select.map(DiariumReader.quoted).joined(separator: ", ")
            + " FROM \(DiariumReader.quoted(entriesTable)) ORDER BY \(DiariumReader.quoted(idCol))"

        var out: [Entry] = []
        var rows = 0
        var undated = 0
        var firstRaw = ""
        try query(sql) { st in
            rows += 1
            let key = DiariumReader.text(st, 0) ?? ""
            if rows == 1 { firstRaw = key + (dateAt.flatMap { DiariumReader.text(st, Int32($0)) }.map { " / " + $0 } ?? "") }

            // Когда: столбец даты, иначе — номер записи.
            var when: (date: Date, day: String, time: String)?
            if let d = dateAt {
                let i = Int32(d)
                if sqlite3_column_type(st, i) == SQLITE_INTEGER {
                    when = DiariumReader.moment(sqlite3_column_int64(st, i))
                } else if let s = DiariumReader.text(st, i) {
                    if let n = Int64(s) { when = DiariumReader.moment(n) }
                    else if let date = JsonImport.parse(s) {
                        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                        when = (date, String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                                String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
                    }
                }
            }
            if when == nil, sqlite3_column_type(st, 0) == SQLITE_INTEGER {
                when = DiariumReader.moment(sqlite3_column_int64(st, 0))
            }
            guard let when else { undated += 1; return }

            let heading = headingAt.flatMap { DiariumReader.text(st, Int32($0)) } ?? ""
            let body = textAt.flatMap { DiariumReader.text(st, Int32($0)) } ?? ""
            let words = JsonImport.text(in: ["Heading": heading, "Text": body])
            var media: [String: (folder: String, file: String)] = [:]
            for m in mediaOf[key] ?? [] {
                media["m\(m.id)"] = (JsonImport.folder(for: m.name), "\(m.id)|\(m.name)")
            }
            guard !words.isEmpty || !media.isEmpty else { return }

            var place: String?
            if let la = latAt, let lo = lonAt,
               sqlite3_column_type(st, Int32(la)) != SQLITE_NULL, sqlite3_column_type(st, Int32(lo)) != SQLITE_NULL {
                let lat = sqlite3_column_double(st, Int32(la)), lon = sqlite3_column_double(st, Int32(lo))
                if abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) {
                    place = String(format: "[](geo:%.5f,%.5f)", lat, lon)
                }
            }
            out.append(Entry(uuid: "Diarium:" + key, date: when.date, day: when.day, time: when.time,
                             text: words, tags: tagsOf[key] ?? [], place: place, media: media))
        }
        guard rows > 0 else {
            throw Failure.problem("таблица \(entriesTable) пуста")
        }
        guard !out.isEmpty else {
            throw Failure.problem("не удалось прочитать даты: записей \(rows), без даты \(undated); первая — \(firstRaw); "
                                  + "столбцы \(entriesTable): " + cols.joined(separator: ", "))
        }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: - Вложения

    /// Что нашли странного в вложениях: первые байты файла, который не
    /// похож ни на снимок, ни на звук, ни на видео (P487). Показывается
    /// в итоге переноса — по нему можно понять устройство архива.
    static var oddNote: String?

    private static func known(_ b: [UInt8], at o: Int = 0) -> Bool {
        guard b.count >= o + 4 else { return false }
        let h = Array(b[o..<(o + 4)])
        if h[0] == 0xff, h[1] == 0xd8, h[2] == 0xff { return true }           // JPEG
        if h == [0x89, 0x50, 0x4e, 0x47] { return true }                        // PNG
        if h == Array("GIF8".utf8) || h == Array("RIFF".utf8) { return true }  // GIF, WebP, WAV
        if h == Array("%PDF".utf8) || h == Array("OggS".utf8) || h == Array("fLaC".utf8) { return true }
        if h == [0x49, 0x49, 0x2a, 0x00] || h == [0x4d, 0x4d, 0x00, 0x2a] { return true } // TIFF
        if Array(h[0..<3]) == Array("ID3".utf8) { return true }                  // MP3
        if b.count >= o + 8, Array(b[(o + 4)..<(o + 8)]) == Array("ftyp".utf8) { return true } // HEIC, MP4, MOV, M4A
        return false
    }

    /// Привести вложение к настоящему файлу (P487): снять сжатие или
    /// base64, отрезать лишнее в начале. Не вышло — как есть, с заметкой.
    static func normalized(_ raw: Data) -> (Data, String?) {
        let head = Array(raw.prefix(512))
        if known(head) { return (raw, nil) }
        // Сжатое: gzip или zlib.
        func inflate(_ body: Data) -> Data? {
            guard let out = try? (body as NSData).decompressed(using: .zlib) else { return nil }
            return out as Data
        }
        if head.count > 18, head[0] == 0x1f, head[1] == 0x8b, head[2] == 8, head[3] == 0,
           let out = inflate(raw.subdata(in: 10..<(raw.count - 8))), known(Array(out.prefix(16))) {
            return (out, nil)
        }
        if head.count > 6, head[0] == 0x78, let out = inflate(raw.subdata(in: 2..<raw.count)),
           known(Array(out.prefix(16))) {
            return (out, nil)
        }
        // Текст base64.
        if head.allSatisfy({ ($0 >= 0x2b && $0 <= 0x7a) || $0 == 0x0a || $0 == 0x0d }),
           let s = String(data: raw, encoding: .ascii),
           let out = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           known(Array(out.prefix(16))) {
            return (out, nil)
        }
        // Лишнее в начале: ищем начало настоящего файла рядом.
        if head.count > 8 {
            for o in 1..<min(head.count - 4, 256) where known(head, at: o) {
                return (raw.subdata(in: o..<raw.count), nil)
            }
        }
        let hex = head.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        return (raw, hex)
    }

    /// Байты вложения — файлом во временной папке; `key` — «номер|имя».
    func extract(_ key: String) -> URL? {
        guard let bar = key.firstIndex(of: "|"), let id = Int64(key[..<bar]) else { return nil }
        let name = String(key[key.index(after: bar)...])
        let tableNames = (try? tables()) ?? []
        guard let table = DiariumReader.pick(tableNames, ["Media", "Attachments"]) else { return nil }
        let cols = (try? columns(of: table)) ?? []
        guard let dataCol = DiariumReader.pick(cols, ["Data", "Content", "Blob", "Bytes"]) else { return nil }
        var raw: Data?
        try? query("SELECT \(DiariumReader.quoted(dataCol)) FROM \(DiariumReader.quoted(table)) WHERE rowid = ?",
                   bind: id) { st in
            switch sqlite3_column_type(st, 0) {
            case SQLITE_BLOB:
                let n = Int(sqlite3_column_bytes(st, 0))
                if n > 0, let p = sqlite3_column_blob(st, 0) { raw = Data(bytes: p, count: n) }
            case SQLITE_TEXT:
                // Вложение, записанное текстом (base64).
                if let t = DiariumReader.text(st, 0) { raw = Data(t.utf8) }
            default: break
            }
        }
        guard let raw else { return nil }
        let (bytes, note) = DiariumReader.normalized(raw)
        if let note { DiariumReader.oddNote = note }
        let dir = workDir.appendingPathComponent("m\(id)")
        let file = dir.appendingPathComponent((name as NSString).lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try bytes.write(to: file)
        } catch { return nil }
        return file
    }
}
