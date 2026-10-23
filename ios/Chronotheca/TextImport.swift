import SwiftUI

/// Перенос из любого приложения, которое умеет выгружать записи текстом
/// или Markdown (P428): Obsidian, Diarly, Bear, Journey, Notion, iA Writer
/// и другие. Каждый файл — запись; день берётся из имени файла
/// («2024-05-17.md», «Запись 2024-05-17.txt»), иначе из первой строки, иначе
/// по дате изменения файла.
///
/// Правила те же, что у Day One (P378): поверх написанного не пишем — у
/// дня, где уже что-то есть, перенесённое встаёт в конец под строкой
/// «— Импорт —»; день, который ещё в iCloud, пропускается; повторный
/// перенос той же папки ничего не удваивает.
enum TextImport {

    struct Report: Equatable {
        var entries = 0
        var days = 0
        var again = 0
        var skipped = 0
    }

    struct Entry {
        let key: String
        let day: String
        let text: String
    }

    // MARK: - Разбор

    /// Все текстовые файлы папки и её подпапок.
    static func entries(in folder: URL) -> [Entry] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: folder,
                                       includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                       options: [.skipsHiddenFiles]) else { return [] }
        var out: [Entry] = []
        for case let url as URL in walk {
            let ext = url.pathExtension.lowercased()
            guard ["md", "markdown", "txt", "text"].contains(ext),
                  let data = try? Data(contentsOf: url),
                  let raw = String(data: data, encoding: .utf8) else { continue }
            let text = body(raw)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            let day = stamp(in: url.deletingPathExtension().lastPathComponent)
                ?? stamp(in: String(text.prefix(80)))
                ?? Vault.stamp(modified)
            let rel = url.path.replacingOccurrences(of: folder.path, with: "")
            out.append(Entry(key: rel + "|\(data.count)", day: day, text: text))
        }
        return out.sorted { $0.day < $1.day }
    }

    /// Текст без служебной шапки YAML («---» … «---»), какую пишут Obsidian
    /// и Diarly.
    static func body(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n"),
              let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex)
        else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Дата ГГГГ-ММ-ДД (или ГГГГ.ММ.ДД, ГГГГ_ММ_ДД) в строке.
    static func stamp(in s: String) -> String? {
        guard let r = s.range(of: #"(19|20)\d\d[-._](0[1-9]|1[0-2])[-._](0[1-9]|[12]\d|3[01])"#,
                              options: .regularExpression) else { return nil }
        let found = String(s[r])
        let digits = found.filter(\.isNumber)
        let out = "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
        return Vault.date(from: out) == nil ? nil : out
    }

    // MARK: - Перенос

    private static var doneURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("import-text.json")
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

    static func run(folder: URL, vault: Vault, step: @escaping (Int, Int) -> Void) -> Report? {
        let list = entries(in: folder)
        guard !list.isEmpty else { return nil }
        var done = alreadyDone()
        var report = Report()
        let fresh = list.filter { e in
            if done.contains(e.key) { report.again += 1; return false }
            return true
        }
        let byDay = Dictionary(grouping: fresh, by: \.day)
        let days = byDay.keys.sorted()
        for (k, stamp) in days.enumerated() {
            defer { step(k + 1, days.count) }
            guard let date = Vault.date(from: stamp), let url = vault.file(.diary, for: date) else { continue }
            let entries = byDay[stamp] ?? []
            let was = Vault.reading(at: url)
            if was == .away { report.skipped += entries.count; continue }
            var file = DayFile(text: was.text)
            let (text, photos) = Diary.split(file.body)
            var body = entries.map(\.text).joined(separator: "\n\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = text + "\n\n" + T("— Импорт —", "— Imported —") + "\n\n" + body
            }
            if !photos.isEmpty { body += "\n\n" + photos.map(Diary.line).joined(separator: "\n") }
            file.body = body
            if file.value("date") == nil { file.set("date", stamp) }
            guard Vault.reading(at: url, coordinated: false) == was else {
                report.skipped += entries.count
                continue
            }
            if Vault.write(file.text, to: url) == nil {
                report.days += 1
                report.entries += entries.count
                for e in entries { done.insert(e.key) }
            } else {
                report.skipped += entries.count
            }
        }
        remember(done)
        return report
    }
}

/// Окно переноса из текста и Markdown.
struct TextImportView: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore

    @State private var choosing = false
    @State private var progress: (Int, Int)?
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(T("Почти любой дневник умеет выгружать записи текстом или Markdown: Obsidian, Diarly, Bear, Journey, Notion, iA Writer. Выгрузите их в папку в «Файлах» и выберите её здесь.",
                       "Almost every journal can export entries as text or Markdown: Obsidian, Diarly, Bear, Journey, Notion, iA Writer. Export them to a folder in Files and choose it here."))
                Text(T("Каждый файл станет записью своего дня. День берётся из имени файла (например, «2024-05-17.md»), иначе — из первой строки, иначе — по дате файла.",
                       "Each file becomes an entry of its day. The day comes from the file name (for example “2024-05-17.md”), otherwise from the first line, otherwise from the file’s date."))
                    .font(Look.sans(14))
                    .foregroundStyle(Look.inkSoft)
                Text(T("Поверх ваших записей ничего не пишется: если в дне уже что-то есть, перенесённое встанет в конец под строкой «— Импорт —». Повторный перенос ничего не удвоит.",
                       "Nothing is written over your entries: if a day already has something, the import goes at the end under “— Imported —”. Importing again does not duplicate anything."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                Button {
                    choosing = true
                } label: {
                    Text(T("Выбрать папку с записями…", "Choose the folder with entries…")).frame(maxWidth: .infinity)
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
        .navigationTitle(T("Markdown и текст", "Markdown and text"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(progress != nil)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { picked in
            guard case .success(let url) = picked else { return }
            start(url)
        }
    }

    private func start(_ url: URL) {
        problem = nil
        result = nil
        store.save()
        progress = (0, 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            let outcome = TextImport.run(folder: url, vault: vault) { done, all in
                DispatchQueue.main.async { progress = (done, all) }
            }
            DispatchQueue.main.async {
                progress = nil
                guard let r = outcome else {
                    problem = T("В этой папке нет файлов .md или .txt.", "There are no .md or .txt files in this folder.")
                    return
                }
                Feel.done()
                var text = T("Перенесено записей: \(r.entries), дней: \(r.days).",
                             "Imported entries: \(r.entries), days: \(r.days).")
                if r.again > 0 {
                    text += T(" Уже были перенесены раньше: \(r.again).", " Already imported before: \(r.again).")
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
