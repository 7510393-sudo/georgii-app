import SwiftUI
import UniformTypeIdentifiers

/// Перенос из Diarium и Journey (P444): обе выгружают записи в JSON.
///
/// Journey кладёт в архив по файлу .json на запись и снимки рядом; Diarium —
/// один файл со всеми записями. Устройство их выгрузок Apple не описывает и
/// они меняются от версии к версии, поэтому разбор терпеливый: дата, текст,
/// заголовок, метки, место и снимки ищутся под всеми именами, под какими
/// их пишут дневники. HTML (Journey пишет записи им) становится обычным
/// текстом.
///
/// Правила те же, что у Day One (P378): поверх записанного не пишет — у
/// дня, где уже что-то есть, перенесённое встаёт в конец под строкой
/// «— Diarium —» или «— Journey —»; недокачанный день пропускается
/// (P182); повторный перенос ничего не удваивает.
enum JsonImport {

    typealias Entry = DayOneImport.Entry

    // MARK: - Разбор

    /// Записи из выгрузки: из папки — все файлы .json в ней и глубже; из
    /// файла — он сам. `app` — метка для отличия записей разных дневников.
    static func entries(at url: URL, app: String) throws -> [Entry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { throw DayOneImport.Failure.noEntries }
        var files: [URL] = []
        if isDir.boolValue {
            let walk = fm.enumerator(at: url, includingPropertiesForKeys: nil)
            while let next = walk?.nextObject() as? URL {
                if next.pathExtension.lowercased() == "json" { files.append(next) }
            }
        } else {
            files = [url]
        }
        var out: [Entry] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            out += entries(from: data, app: app)
        }
        guard !out.isEmpty else { throw DayOneImport.Failure.noEntries }
        return out.sorted { $0.date < $1.date }
    }

    /// Записи из одного файла: в нём массив записей, объект с массивом
    /// внутри или одна запись.
    static func entries(from data: Data, app: String) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return records(in: root).compactMap { entry($0, app: app) }
    }

    /// Все словари, похожие на запись: в них есть дата и текст.
    private static func records(in node: Any) -> [[String: Any]] {
        if let list = node as? [Any] { return list.flatMap { records(in: $0) } }
        guard let dict = node as? [String: Any] else { return [] }
        if date(in: dict) != nil, !text(in: dict).isEmpty { return [dict] }
        return dict.values.flatMap { value -> [[String: Any]] in
            value is [Any] || value is [String: Any] ? records(in: value) : []
        }
    }

    private static let dateKeys = ["date_journal", "dateJournal", "date", "datetime", "dateTime",
                                   "created", "creationDate", "createdAt", "created_at",
                                   "timestamp", "time", "day", "Date"]
    private static let titleKeys = ["heading", "title", "subject", "Title", "Heading"]
    private static let bodyKeys = ["text", "html", "body", "content", "entry", "note", "Text", "Content"]

    /// Когда сделана запись: число (секунды или миллисекунды) или строка.
    static func date(in e: [String: Any]) -> Date? {
        for key in dateKeys {
            guard let value = e[key] else { continue }
            if let n = value as? Double, n > 0 { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
            if let n = value as? Int, n > 0 {
                return Date(timeIntervalSince1970: n > 100_000_000_000 ? Double(n) / 1000 : Double(n))
            }
            if let s = value as? String, let d = parse(s) { return d }
        }
        return nil
    }

    static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
                        "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = pattern
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Заголовок и текст записи — обычным текстом.
    static func text(in e: [String: Any]) -> String {
        let title = titleKeys.compactMap { e[$0] as? String }.first.map(plain) ?? ""
        let body = bodyKeys.compactMap { e[$0] as? String }.first.map(plain) ?? ""
        let parts = [title, body].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Заголовок, повторённый первой строкой текста, — один раз.
        if parts.count == 2, parts[1].hasPrefix(parts[0]) { return parts[1] }
        return parts.joined(separator: "\n")
    }

    /// HTML — обычным текстом: абзацы и переносы строками, без тегов.
    static func plain(_ s: String) -> String {
        guard s.contains("<"), s.range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil
        else { return s }
        var t = s
        for (pattern, with) in [(#"(?i)<br\s*/?>"#, "\n"), (#"(?i)</(p|div|h[1-6]|li|blockquote)>"#, "\n"),
                                (#"(?i)<li[^>]*>"#, "• "), (#"<[^>]+>"#, "")] {
            t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                               ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        // Пустых строк подряд не больше одной.
        t = t.replacingOccurrences(of: #"\n[ \t]*\n([ \t]*\n)+"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entry(_ e: [String: Any], app: String) -> Entry? {
        guard let date = date(in: e) else { return nil }
        let body = text(in: e)
        guard !body.isEmpty else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ["timezone", "timeZone", "time_zone"].compactMap { e[$0] as? String }
            .compactMap(TimeZone.init(identifier:)).first ?? .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)

        // Метки: строки или словари с названием.
        let tagList = (e["tags"] as? [Any]) ?? (e["labels"] as? [Any]) ?? []
        let tags = tagList.compactMap { item -> String? in
            if let s = item as? String { return s }
            if let d = item as? [String: Any] { return (d["name"] ?? d["title"]) as? String }
            return nil
        }.filter { !$0.isEmpty }

        // Снимки: имена файлов или словари с именем.
        var media: [String: (folder: String, file: String)] = [:]
        for key in ["photos", "images", "attachments", "media", "pictures"] {
            for item in (e[key] as? [Any]) ?? [] {
                let name = (item as? String)
                    ?? ((item as? [String: Any]).flatMap { d in
                        (d["filename"] ?? d["fileName"] ?? d["file"] ?? d["name"] ?? d["path"]) as? String })
                guard let name, !name.isEmpty else { continue }
                let file = (name as NSString).lastPathComponent
                media[file] = (folder(for: file), file)
            }
        }

        var id = "\(Int(date.timeIntervalSince1970))-\(stableHash(body))"
        for key in ["id", "uuid", "ID", "guid"] {
            if let value = e[key] { id = "\(value)"; break }
        }
        return Entry(uuid: app + ":" + id, date: date, day: day, time: time, text: body,
                     tags: tags, place: place(in: e), media: media)
    }

    /// Один и тот же текст — одно и то же число при каждом запуске
    /// (`hashValue` от запуска к запуску разный): по нему повторный перенос
    /// узнаёт записи без своего номера.
    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h, radix: 36)
    }

    /// Место точкой, если у записи есть широта и долгота.
    private static func place(in e: [String: Any]) -> String? {
        let loc = (e["location"] as? [String: Any]) ?? e
        func number(_ keys: [String]) -> Double? {
            for k in keys {
                if let n = loc[k] as? Double { return n }
                if let s = loc[k] as? String, let n = Double(s) { return n }
            }
            return nil
        }
        // Journey пишет «нет места» огромным числом.
        guard let lat = number(["lat", "latitude", "Latitude"]),
              let lon = number(["lon", "lng", "long", "longitude", "Longitude"]),
              abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { return nil }
        let name = ((e["address"] as? String) ?? (loc["name"] as? String) ?? (loc["placeName"] as? String) ?? "")
            .replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "[", with: "(")
        return String(format: "[%@](geo:%.5f,%.5f)", name, lat, lon)
    }

    /// В какую папку архива ляжет файл — по его расширению.
    static func folder(for file: String) -> String {
        switch (file as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return "photos"
        case "mov", "mp4", "m4v": return "videos"
        case "m4a", "mp3", "aac", "wav", "caf": return "audios"
        default: return "pdfs"
        }
    }

    // MARK: - Перенос

    private static var doneURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("import-json.json")
    }

    private static func alreadyDone() -> Set<String> {
        guard let url = doneURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    private static func remember(_ done: Set<String>) {
        guard let url = doneURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(done.sorted()) { try? data.write(to: url, options: .atomic) }
    }

    /// Починить снимки уже перенесённой записи: тот же файл, что лёг в
    /// прошлый раз по имени, если он не открывается как картинка (P487).
    private static func repair(_ e: Entry, reader: DiariumReader, root: URL, tag: String,
                               report: inout DayOneImport.Report) {
        guard let date = Vault.date(from: e.day) else { return }
        let fm = FileManager.default
        for id in e.media.keys.sorted() {
            guard let m = e.media[id] else { continue }
            let ext = (m.file as NSString).pathExtension.lowercased() == "jpeg" ? "jpg"
                : (m.file as NSString).pathExtension.lowercased()
            guard ["jpg", "png", "heic", "gif", "webp"].contains(ext) else { continue }
            guard let source = reader.extract(m.file), UIImage(contentsOfFile: source.path) != nil else { continue }
            let stamp = Vault.stamp(date)
            let dir = Vault.folder(DayOneImport.kind(for: m.folder), in: root).appendingPathComponent(String(stamp.prefix(4)))
            let base = stamp + "_" + tag + "_" + String(source.deletingPathExtension().lastPathComponent.prefix(8))
            for n in 1..<10 {
                let target = dir.appendingPathComponent(n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)")
                guard fm.fileExists(atPath: target.path) else { break }
                if UIImage(contentsOfFile: target.path) == nil {
                    if (try? Data(contentsOf: source).write(to: target, options: .atomic)) != nil { report.fixed += 1 }
                    break
                }
            }
        }
    }

    /// Перенести выгрузку в архив — в стороне от главного потока; `step` —
    /// сколько дней из скольких пройдено.
    static func run(at url: URL, app: String, vault: Vault,
                    step: @escaping (Int, Int) -> Void) -> Result<DayOneImport.Report, DayOneImport.Failure> {
        // Архив Diarium — база SQLite: читается своим разбором (P476).
        var reader: DiariumReader?
        let list: [Entry]
        if app == "Diarium", DiariumReader.looksLikeDatabase(url) {
            do {
                let r = try DiariumReader(copying: url)
                list = try r.entries()
                reader = r
            } catch DiariumReader.Failure.problem(let why) {
                return .failure(.unreadable(why))
            } catch {
                return .failure(.unreadable(error.localizedDescription))
            }
        } else {
            do { list = try entries(at: url, app: app) } catch let f as DayOneImport.Failure { return .failure(f) } catch {
                return .failure(.unreadable(error.localizedDescription))
            }
        }
        guard let root = vault.root else { return .failure(.unreadable("—")) }
        var done = alreadyDone()
        var report = DayOneImport.Report()
        let fresh = list.filter { e in
            if done.contains(e.uuid) {
                report.again += 1
                // Тексты уже на месте, а снимки в прошлый раз могли лечь
                // испорченными (P487) — чиним только их.
                if let reader { repair(e, reader: reader, root: root, tag: app.lowercased().replacingOccurrences(of: " ", with: ""), report: &report) }
                return false
            }
            return true
        }
        // Файлы выгрузки по имени — где бы в папке они ни лежали.
        var files: [String: URL] = [:]
        if reader == nil {
            var isDir: ObjCBool = false
            let base = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                ? url : url.deletingLastPathComponent()
            let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            while let next = walk?.nextObject() as? URL {
                files[next.lastPathComponent.lowercased()] = next
            }
        }

        let byDay = Dictionary(grouping: fresh, by: \.day)
        let days = byDay.keys.sorted()
        let tag = app.lowercased().replacingOccurrences(of: " ", with: "")
        for (k, stamp) in days.enumerated() {
            defer { step(k + 1, days.count) }
            guard let date = Vault.date(from: stamp), let file = vault.file(.diary, for: date) else { continue }
            let entries = byDay[stamp] ?? []
            let was = Vault.reading(at: file)
            if was == .away {
                report.skipped += entries.count
                continue
            }
            var blocks: [String] = []
            for e in entries {
                blocks.append(DayOneImport.block(e) { id in
                    guard let m = e.media[id] else { return nil }
                    let found = reader != nil ? reader?.extract(m.file) : files[m.file.lowercased()]
                    guard let source = found,
                          let l = DayOneImport.copy(source, folder: m.folder, date: date, root: root, tag: tag)
                    else {
                        report.missing += 1
                        return nil
                    }
                    report.media += 1
                    return l
                })
            }
            var day = DayFile(text: was.text)
            let (text, photos) = Diary.split(day.body)
            var body = blocks.joined(separator: "\n\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = text + "\n\n— \(app) —\n\n" + body
            }
            if !photos.isEmpty { body += "\n\n" + photos.map(Diary.line).joined(separator: "\n") }
            day.body = body
            if day.value("date") == nil { day.set("date", stamp) }
            // Файл изменился, пока мы готовили запись, — не пишем (P182).
            guard Vault.reading(at: file, coordinated: false) == was else {
                report.skipped += entries.count
                continue
            }
            if Vault.write(day.text, to: file) == nil {
                report.days += 1
                report.entries += entries.count
                for e in entries { done.insert(e.uuid) }
            } else {
                report.skipped += entries.count
            }
        }
        remember(done)
        return .success(report)
    }
}

/// Окно переноса из Diarium или Journey: как выгрузить, выбрать, ход и итог.
struct JsonImportView: View {

    let app: String

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore

    @State private var choosing = false
    @State private var progress: (Int, Int)?
    @State private var result: String?
    @State private var problem: String?

    private var steps: [String] {
        if app == "Journey" {
            return [T("1. В Journey: настройки → данные → экспорт записей в ZIP. Сохраните архив в «Файлы».",
                      "1. In Journey: settings → data → export entries as ZIP. Save the archive to Files."),
                    T("2. В «Файлах» коснитесь архива — он распакуется в папку.",
                      "2. In Files, tap the archive — it unpacks into a folder."),
                    T("3. Здесь — «Выбрать выгрузку…» и эта папка.",
                      "3. Here — “Choose the export…” and that folder.")]
        }
        return [T("1. В Diarium: Настройки → «Архивировать дневник». Сохраните файл в «Файлы» (экспорт в JSON тоже годится).",
                  "1. In Diarium: Settings → “Archive diary”. Save the file to Files (a JSON export works too)."),
                T("2. Здесь — «Выбрать выгрузку…» и этот файл или папка с ним.",
                  "2. Here — “Choose the export…” and that file or its folder.")]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(T("Записи из \(app) лягут сюда обычными файлами по дням — со временем, метками, местом и снимками, если они есть в выгрузке. В \(app) при этом ничего не пропадает.",
                       "Your \(app) entries arrive here as ordinary files by day — with time, tags, place and photos if the export has them. Nothing disappears from \(app)."))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps, id: \.self) { Text($0) }
                }
                .font(Look.sans(14))
                .foregroundStyle(Look.inkSoft)
                Text(T("Поверх ваших записей ничего не пишется: если в дне уже что-то есть, перенесённое встанет в конец под строкой «— \(app) —». Повторный перенос ничего не удвоит.",
                       "Nothing is written over your entries: if a day already has something, the import goes at the end under “— \(app) —”. Importing again does not duplicate anything."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                Button {
                    choosing = true
                } label: {
                    Text(T("Выбрать выгрузку…", "Choose the export…")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(progress != nil)
                if let p = progress {
                    ProgressView(value: Double(p.0), total: Double(max(p.1, 1)))
                    Text(T("Дней: \(p.0) из \(p.1)", "Days: \(p.0) of \(p.1)"))
                        .font(Look.sans(13)).foregroundStyle(Look.inkSoft)
                }
                if let result {
                    Text(result).font(Look.sans(14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem {
                    Text(problem).font(Look.sans(14)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Выгрузка только текстом — тоже годится (P428).
                Text(T("Выгрузили текстом или Markdown — перенесите через «Markdown и текст» в начале списка.",
                       "Exported as text or Markdown? Import it via “Markdown and text” at the top of the list."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkFaint)
            }
            .font(Look.sans(15))
            .padding(20)
        }
        .navigationTitle(app)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(progress != nil)
        .fileImporter(isPresented: $choosing, allowedContentTypes: app == "Diarium" ? [.folder, .json, .data] : [.folder, .json]) { picked in
            guard case .success(let url) = picked else { return }
            start(url)
        }
    }

    private func start(_ url: URL) {
        problem = nil
        result = nil
        store.save()
        progress = (0, 0)
        let app = app
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            let outcome = JsonImport.run(at: url, app: app, vault: vault) { done, all in
                DispatchQueue.main.async { progress = (done, all) }
            }
            DispatchQueue.main.async {
                progress = nil
                switch outcome {
                case .failure(let f):
                    let none: Bool
                    if case .noEntries = f { none = true } else { none = false }
                    problem = none
                        ? T("В выгрузке не нашлось записей. Выберите файл .json из \(app) или папку с ним.",
                            "No entries found in the export. Choose the .json file from \(app) or its folder.")
                        : f.text
                case .success(let r):
                    Feel.done()
                    var text = T("Перенесено записей: \(r.entries), дней: \(r.days).",
                                 "Imported entries: \(r.entries), days: \(r.days).")
                    if r.media > 0 { text += T(" Снимков и файлов: \(r.media).", " Photos and files: \(r.media).") }
                    if r.again > 0 {
                        text += T(" Уже были перенесены раньше: \(r.again).", " Already imported before: \(r.again).")
                    }
                    if r.missing > 0 {
                        text += T(" Не нашлось в выгрузке файлов: \(r.missing).", " Files missing from the export: \(r.missing).")
                    }
                    if r.fixed > 0 {
                        text += T(" Снимков починено: \(r.fixed).", " Photos repaired: \(r.fixed).")
                    }
                    if let odd = DiariumReader.oddNote {
                        text += T(" Формат вложения не опознан, первые байты: \(odd).",
                                  " Attachment format not recognised, first bytes: \(odd).")
                        DiariumReader.oddNote = nil
                    }
                    if r.skipped > 0 {
                        text += T(" Не перенесены, потому что день ещё в iCloud: \(r.skipped) — повторите позже.",
                                  " Not imported because the day is still in iCloud: \(r.skipped) — try again later.")
                    }
                    result = text
                    store.load()
                }
            }
        }
    }
}
