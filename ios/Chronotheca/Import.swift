import SwiftUI
import UniformTypeIdentifiers

/// Перенос записей из Day One (P378).
///
/// Day One отдаёт записи выгрузкой «JSON»: архив, в нём файл с записями и
/// папки `photos`, `videos`, `audios`, `pdfs`. Архив распаковывается одним
/// касанием в «Файлах»; человек выбирает получившуюся папку — и записи
/// ложатся обычными файлами по дням: текст с отметкой времени, место
/// точкой, метки словами, снимки, голос, видео и документы — в свои папки.
///
/// Перенос бесплатен всегда (M14). Поверх записанного он не пишет никогда:
/// у дня, где уже что-то есть, перенесённое встаёт в конец под строкой
/// «— Day One —»; день, который ещё не скачан из iCloud, пропускается
/// (P182). Повторный перенос той же выгрузки ничего не удваивает.
enum DayOneImport {

    struct Report: Equatable {
        var entries = 0
        var days = 0
        var media = 0
        /// Уже перенесённые раньше.
        var again = 0
        /// Дни, которые не скачаны из iCloud, — их записи не перенесены.
        var skipped = 0
        /// Снимки и файлы, которых не нашлось в выгрузке.
        var missing = 0
        /// Снимки, что в прошлый раз легли испорченными и теперь починены (P487).
        var fixed = 0
    }

    enum Failure: Error {
        case noEntries
        case unreadable(String)

        var text: String {
            switch self {
            case .noEntries:
                return T("В этой папке нет выгрузки Day One. Выберите папку, в которой лежит файл .json и папка photos.",
                         "There is no Day One export in this folder. Choose the folder with the .json file and the photos folder.")
            case .unreadable(let why):
                return T("Выгрузку не удалось прочитать: ", "The export could not be read: ") + why
            }
        }
    }

    /// Одна запись Day One, уже разобранная.
    struct Entry: Equatable {
        var uuid: String
        var date: Date
        /// День записи по её часовому поясу — ГГГГ-ММ-ДД.
        var day: String
        /// «08:12» по её часовому поясу.
        var time: String
        var text: String
        var tags: [String]
        var place: String?
        var media: [String: (folder: String, file: String)]

        static func == (a: Entry, b: Entry) -> Bool {
            a.uuid == b.uuid && a.text == b.text && a.day == b.day && a.time == b.time
        }
    }

    // MARK: - Разбор

    /// Записи из файлов .json в папке выгрузки.
    static func entries(in folder: URL) throws -> [Entry] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let jsons = names.filter { $0.lowercased().hasSuffix(".json") }
        guard !jsons.isEmpty else { throw Failure.noEntries }
        var out: [Entry] = []
        for name in jsons.sorted() {
            let data: Data
            do { data = try Data(contentsOf: folder.appendingPathComponent(name)) } catch {
                throw Failure.unreadable(error.localizedDescription)
            }
            out += try entries(from: data)
        }
        guard !out.isEmpty else { throw Failure.noEntries }
        return out.sorted { $0.date < $1.date }
    }

    static func entries(from data: Data) throws -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["entries"] as? [[String: Any]]
        else { throw Failure.noEntries }
        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return list.compactMap { e -> Entry? in
            guard let created = e["creationDate"] as? String,
                  let date = iso.date(from: created) ?? isoFraction.date(from: created)
            else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = (e["timeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)

            var media: [String: (folder: String, file: String)] = [:]
            for (key, folder) in [("photos", "photos"), ("videos", "videos"),
                                  ("audios", "audios"), ("pdfAttachments", "pdfs")] {
                for m in (e[key] as? [[String: Any]]) ?? [] {
                    guard let id = m["identifier"] as? String, let md5 = m["md5"] as? String else { continue }
                    let ext = (m["type"] as? String) ?? (m["format"] as? String) ?? ""
                    media[id] = (folder, ext.isEmpty ? md5 : md5 + "." + ext)
                }
            }
            var place: String?
            if let loc = e["location"] as? [String: Any],
               let lat = loc["latitude"] as? Double, let lon = loc["longitude"] as? Double {
                let name = ((loc["placeName"] as? String) ?? (loc["localityName"] as? String) ?? "")
                    .replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "[", with: "(")
                place = String(format: "[%@](geo:%.5f,%.5f)", name, lat, lon)
            }
            return Entry(uuid: (e["uuid"] as? String) ?? created,
                         date: date, day: day, time: time,
                         text: unescape((e["text"] as? String) ?? ""),
                         tags: (e["tags"] as? [String]) ?? [],
                         place: place, media: media)
        }
    }

    /// Day One прячет знаки разметки обратной чертой: «1\.», «\-». В
    /// записи человека их быть не должно.
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!>|~])"#, with: "$1",
                               options: .regularExpression)
    }

    /// Ссылки Day One на снимок или файл внутри текста:
    /// `![](dayone-moment://ID)`, `![](dayone-moment:/audio/ID)`.
    private static let moment = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(dayone-moment:/{1,2}(?:[A-Za-z]+/)?([A-Za-z0-9\-]+)\)"#)

    /// Текст записи для нашего файла: отметка времени, текст, где ссылки
    /// Day One заменены своими строками, место, метки, вложения, которых в
    /// тексте не было, — в конце. `link` кладёт вложение и даёт ссылку.
    static func block(_ e: Entry, link: (String) -> String?) -> String {
        var used = Set<String>()
        let ns = e.text as NSString
        var text = ""
        var from = 0
        for m in moment.matches(in: e.text, range: NSRange(location: 0, length: ns.length)) {
            text += ns.substring(with: NSRange(location: from, length: m.range.location - from))
            let id = ns.substring(with: m.range(at: 1))
            used.insert(id)
            if let l = link(id) { text += "\n" + Diary.line(l) + "\n" }
            from = NSMaxRange(m.range)
        }
        text += ns.substring(from: from)
        var lines = text.components(separatedBy: "\n")
        // Пустых строк подряд не больше одной.
        lines = lines.enumerated().filter { i, line in
            !(line.trimmingCharacters(in: .whitespaces).isEmpty && i > 0
              && lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty)
        }.map(\.element)
        var body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for id in e.media.keys.sorted() where !used.contains(id) {
            if let l = link(id) { body += (body.isEmpty ? "" : "\n") + Diary.line(l) }
        }
        var out = e.time + " " + body
        if let place = e.place { out += "\n" + place }
        if !e.tags.isEmpty {
            out += "\n" + e.tags.map { "#" + $0.replacingOccurrences(of: " ", with: "_") }.joined(separator: " ")
        }
        return out
    }

    // MARK: - Перенос

    private static var doneURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("import-dayone.json")
    }

    static func alreadyDone() -> Set<String> {
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

    /// Перенести выгрузку в архив. Работает в стороне от главного потока;
    /// `step` — сколько дней из скольких пройдено.
    static func run(folder: URL, vault: Vault, step: @escaping (Int, Int) -> Void) -> Result<Report, Failure> {
        let list: [Entry]
        do { list = try entries(in: folder) } catch let f as Failure { return .failure(f) } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        guard let root = vault.root else { return .failure(.unreadable("—")) }
        var done = alreadyDone()
        var report = Report()
        let fresh = list.filter { e in
            if done.contains(e.uuid) { report.again += 1; return false }
            return true
        }
        let byDay = Dictionary(grouping: fresh, by: \.day)
        let days = byDay.keys.sorted()
        // Где лежат файлы выгрузки: имя без расширения → файл.
        var files: [String: [String: URL]] = [:]
        for sub in ["photos", "videos", "audios", "pdfs"] {
            let dir = folder.appendingPathComponent(sub)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
                files[sub, default: [:]][(name as NSString).deletingPathExtension.lowercased()] =
                    dir.appendingPathComponent(name)
            }
        }

        for (k, stamp) in days.enumerated() {
            defer { step(k + 1, days.count) }
            guard let date = Vault.date(from: stamp), let url = vault.file(.diary, for: date) else { continue }
            let entries = byDay[stamp] ?? []
            let was = Vault.reading(at: url)
            if was == .away {
                report.skipped += entries.count
                continue
            }
            var blocks: [String] = []
            for e in entries {
                blocks.append(block(e) { id in
                    guard let m = e.media[id] else { return nil }
                    let key = (m.file as NSString).deletingPathExtension.lowercased()
                    guard let source = files[m.folder]?[key] else {
                        report.missing += 1
                        return nil
                    }
                    guard let l = copy(source, folder: m.folder, date: date, root: root) else {
                        report.missing += 1
                        return nil
                    }
                    report.media += 1
                    return l
                })
            }
            var file = DayFile(text: was.text)
            let text = file.body
            var body = blocks.joined(separator: "\n\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = text + "\n\n— Day One —\n\n" + body
            }
            file.body = body
            if file.value("date") == nil { file.set("date", stamp) }
            // Файл изменился, пока мы готовили запись, — не пишем (P182).
            guard Vault.reading(at: url, coordinated: false) == was else {
                report.skipped += entries.count
                continue
            }
            if Vault.write(file.text, to: url) == nil {
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

    static func kind(for folder: String) -> Vault.Folder {
        switch folder {
        case "photos": return .photos
        case "videos": return .videos
        case "audios": return .audio
        default: return .documents
        }
    }

    /// Положить файл выгрузки в свою папку архива — с датой дня в имени;
    /// чужое не затирается: занято имя — к нему номер.
    static func copy(_ source: URL, folder: String, date: Date, root: URL, tag: String = "dayone") -> String? {
        let kind = Self.kind(for: folder)
        let stamp = Vault.stamp(date)
        let year = String(stamp.prefix(4))
        let home = Vault.folder(kind, in: root)
        let dir = home.appendingPathComponent(year)
        let ext = source.pathExtension.lowercased() == "jpeg" ? "jpg" : source.pathExtension.lowercased()
        let base = stamp + "_" + tag + "_" + String(source.deletingPathExtension().lastPathComponent.prefix(8))
        var target = dir.appendingPathComponent(base + "." + ext)
        var n = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
        } catch {
            return nil
        }
        return "../../" + home.lastPathComponent + "/" + year + "/" + target.lastPathComponent
    }
}

/// Переход из другого приложения (P381): список дневников, откуда можно
/// перенести записи. Свой перенос — у Day One, Diarium и Journey (P444); у
/// остальных — через текст или Markdown (P439).
struct ImportSheet: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @Environment(\.dismiss) private var dismiss

    /// Только те, чей перенос проверен своими проверками (P602): Day One
    /// (P378), Diarium и Journey (P444). Прежде в списке стояли ещё
    /// четырнадцать названий, и все они вели в общий перенос текста — это
    /// обещание, которое не для всех выполнимо. Кто выгружает текст или
    /// Markdown — строкой выше, «Markdown и текст».
    static let apps = ["Day One", "Diarium", "Journey"]


    var body: some View {
        NavigationStack {
            List {
                // Из любого приложения, которое выгружает текст (P428).
                Section {
                    NavigationLink {
                        TextImportView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(T("Markdown и текст", "Markdown and text")).font(Look.sans(16))
                            Text("Obsidian, Bear, Notion, iA Writer…")
                                .font(Look.sans(12.5)).foregroundStyle(Look.inkFaint)
                        }
                    }
                }
                Section {
                    ForEach(Self.apps, id: \.self) { app in
                        NavigationLink {
                            if app == "Day One" {
                                DayOneImportView()
                            } else {
                                JsonImportView(app: app)
                            }
                        } label: {
                            HStack {
                                Text(app).font(Look.sans(16))
                                Spacer()
                            }
                        }
                    }
                } footer: {
                    Text(T("Записи переносятся обычными файлами по дням; в прежнем приложении ничего не "
                           + "пропадает. Перенос бесплатен всегда.",
                           "Entries arrive as ordinary files by day; nothing disappears from the other app. "
                           + "Importing is always free."))
                }
            }
            .navigationTitle(T("Переход из другого приложения", "Switch from another app"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { dismiss() }
                }
            }
        }
        .environmentObject(vault)
        .environmentObject(store)
    }
}

/// Окно переноса из Day One: как выгрузить, выбрать папку, ход и итог.
struct DayOneImportView: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore

    @State private var choosing = false
    @State private var progress: (Int, Int)?
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(T("Записи из Day One лягут сюда обычными файлами по дням — с временем, местом, "
                           + "метками, снимками, голосом и видео. Day One при этом ничего не теряет.",
                           "Your Day One entries arrive here as ordinary files by day — with time, place, tags, "
                           + "photos, voice and video. Nothing is taken out of Day One."))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("1. В Day One: Настройки → Импорт/экспорт → Экспорт → JSON. Сохраните архив в «Файлы».",
                               "1. In Day One: Settings → Import/Export → Export → JSON. Save the archive to Files."))
                        Text(T("2. В «Файлах» коснитесь архива — он распакуется в папку.",
                               "2. In Files, tap the archive — it unpacks into a folder."))
                        Text(T("3. Здесь — «Выбрать папку выгрузки» и эта папка.",
                               "3. Here — “Choose the export folder” and that folder."))
                    }
                    .font(Look.sans(14))
                    .foregroundStyle(Look.inkSoft)
                    Text(T("Поверх ваших записей ничего не пишется: если в дне уже что-то есть, перенесённое "
                           + "встанет в конец под строкой «— Day One —». Повторный перенос ничего не удвоит.",
                           "Nothing is written over your entries: if a day already has something, the import goes "
                           + "at the end under “— Day One —”. Importing again does not duplicate anything."))
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkSoft)
                    Button {
                        choosing = true
                    } label: {
                        Text(T("Выбрать папку выгрузки…", "Choose the export folder…")).frame(maxWidth: .infinity)
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
                }
                .font(Look.sans(15))
                .padding(20)
            }
            .navigationTitle("Day One")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(progress != nil)
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder, .zip]) { picked in
                guard case .success(let url) = picked else { return }
                start(url)
            }
        }
        .interactiveDismissDisabled(progress != nil)
    }

    private func start(_ url: URL) {
        problem = nil
        result = nil
        if url.pathExtension.lowercased() == "zip" {
            problem = T("Это сам архив. Коснитесь его в «Файлах» — он распакуется в папку — и выберите её.",
                        "This is the archive itself. Tap it in Files — it unpacks into a folder — and choose that.")
            return
        }
        store.save()
        progress = (0, 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            let outcome = DayOneImport.run(folder: url, vault: vault) { done, all in
                DispatchQueue.main.async { progress = (done, all) }
            }
            DispatchQueue.main.async {
                progress = nil
                switch outcome {
                case .failure(let f):
                    problem = f.text
                case .success(let r):
                    Feel.done()
                    var text = T("Перенесено записей: \(r.entries), дней: \(r.days), снимков и файлов: \(r.media).",
                                 "Imported entries: \(r.entries), days: \(r.days), photos and files: \(r.media).")
                    if r.again > 0 {
                        text += T(" Уже были перенесены раньше: \(r.again).", " Already imported before: \(r.again).")
                    }
                    if r.skipped > 0 {
                        text += T(" Не перенесены, потому что день ещё в iCloud: \(r.skipped) — повторите позже.",
                                  " Not imported because the day is still in iCloud: \(r.skipped) — try again later.")
                    }
                    if r.missing > 0 {
                        text += T(" Не нашлось в выгрузке файлов: \(r.missing).",
                                  " Files missing from the export: \(r.missing).")
                    }
                    result = text
                    store.load()
                }
            }
        }
    }
}
