import Foundation

/// Корзина файлов (P371): снимок, видео, голос или документ, удалённый «из
/// хранилища», не стирается сразу, а переезжает в `Trash/Files/ГГГГ-ММ-ДД/`
/// — день удаления — со своим путём внутри архива: `Photos/2026/…`. Там он
/// лежит 30 дней: его видно в «Настройки → Корзина» и в «Файлах», его
/// можно вернуть — файл встаёт на место, ссылка — на страницу своего дня.
/// Через 30 дней приложение стирает его само, как и обещано в окне
/// удаления.
///
/// Файл, на который ссылается ещё какая-нибудь запись или дело, в корзину
/// не идёт: со страницы убирается только ссылка, иначе в другом дне
/// осталась бы пустая рамка.
enum FileTrash {

    static let folderName = "Files"
    static let days = 30
    private static let indexName = "index.json"

    /// Откуда файл и куда вернуть ссылку.
    struct Entry: Codable, Equatable, Identifiable {
        /// Путь внутри архива: `Photos/2026/2026-10-02_09.15.30.heic`.
        var path: String
        /// Путь внутри папки дня в корзине — тот же, а если такой уже был,
        /// с номером.
        var stored: String
        /// День, на странице которого была ссылка: ГГГГ-ММ-ДД.
        var day: String
        /// "diary" или "plan".
        var tab: String
        /// Сама ссылка, как она стояла в файле дня.
        var link: String
        /// Когда удалили: ГГГГ-ММ-ДД — по нему считаются 30 дней.
        var deleted: String = ""
        var id: String { deleted + "/" + stored }
    }

    static func base(_ root: URL) -> URL {
        Vault.trash(in: root).appendingPathComponent(folderName)
    }

    // MARK: - Удалить

    enum Outcome: Equatable {
        /// Файл в корзине.
        case trashed
        /// Файл нужен ещё в другом дне — остался на месте.
        case stillUsed(String)
        /// Файла нет или его не удалось перенести — ничего не изменилось.
        case failed
    }

    /// Убрать файл по ссылке в корзину. Ссылка со страницы уже убрана.
    static func put(_ link: String, from day: Date, tab: String, vault: Vault) -> Outcome {
        guard let root = vault.root, let file = vault.mediaURL(link, for: day),
              FileManager.default.fileExists(atPath: file.path)
        else { return .failed }
        if let other = usedElsewhere(file.lastPathComponent, root: root) { return .stillUsed(other) }

        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        guard filePath.hasPrefix(rootPath + "/") else { return .failed }
        let rel = String(filePath.dropFirst(rootPath.count + 1))

        let stamp = Vault.stamp(Date())
        let dayFolder = base(root).appendingPathComponent(stamp)
        var target = dayFolder.appendingPathComponent(rel)
        let fm = FileManager.default
        var n = 2
        while fm.fileExists(atPath: target.path) {
            let name = (rel as NSString).deletingPathExtension + " \(n)"
            let ext = (rel as NSString).pathExtension
            target = dayFolder.appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
            n += 1
        }
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard move(file, to: target) else { return .failed }
        var list = index(dayFolder)
        let kept = String(target.path.dropFirst(dayFolder.path.count + 1))
        list.append(Entry(path: rel, stored: kept, day: Vault.stamp(day), tab: tab, link: link,
                          deleted: stamp))
        save(list, dayFolder)
        return .trashed
    }

    /// День, где ещё есть ссылка на этот файл, — или `nil`. Смотрятся все
    /// записи и планы, которые лежат на телефоне; не скачанные из iCloud
    /// прочесть нельзя — их файл и так переживёт 30 дней в корзине.
    static func usedElsewhere(_ name: String, root: URL) -> String? {
        let fm = FileManager.default
        for folder in [Vault.Folder.diary, .planner] {
            guard let walk = fm.enumerator(at: Vault.folder(folder, in: root),
                                           includingPropertiesForKeys: nil,
                                           options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in walk where url.pathExtension == "md" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if text.contains("/" + name + ")") || text.contains("/" + name + ">)") {
                    return url.deletingPathExtension().lastPathComponent
                }
            }
        }
        return nil
    }

    // MARK: - Что лежит

    static func items(_ vault: Vault) -> [Entry] {
        guard let root = vault.root,
              let names = try? FileManager.default.contentsOfDirectory(atPath: base(root).path)
        else { return [] }
        return names.sorted(by: >).flatMap { name -> [Entry] in
            index(base(root).appendingPathComponent(name)).map { e in
                var e = e
                if e.deleted.isEmpty { e.deleted = name }
                return e
            }
        }
    }

    static func url(of e: Entry, _ vault: Vault) -> URL? {
        vault.root.map { base($0).appendingPathComponent(e.deleted).appendingPathComponent(e.stored) }
    }

    /// Сколько дней осталось до того, как файл сотрётся.
    static func daysLeft(_ e: Entry, now: Date = Date()) -> Int {
        guard let d = Vault.date(from: e.deleted) else { return 0 }
        let gone = Calendar.current.date(byAdding: .day, value: days, to: d) ?? d
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                                      to: gone).day ?? 0)
    }

    // MARK: - Вернуть и стереть

    /// Вернуть файл на его место в архиве. Там уже лежит другой файл с тем
    /// же именем — ничего не трогаем (P182).
    static func restore(_ e: Entry, _ vault: Vault) -> Bool {
        guard let root = vault.root, let from = url(of: e, vault) else { return false }
        let to = root.appendingPathComponent(e.path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return false }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard move(from, to: to) else { return false }
        drop(e, root: root)
        return true
    }

    /// Вернуть ссылку на страницу дня: в конец полоски снимков. Файл дня
    /// перечитывается перед записью; изменили его в другом месте — не пишем.
    static func relink(_ e: Entry, _ vault: Vault) -> Bool {
        guard let date = Vault.date(from: e.day),
              let url = vault.file(e.tab == "plan" ? .planner : .diary, for: date)
        else { return false }
        let was = Vault.reading(at: url)
        if was == .away { return false }
        var file = DayFile(text: was.text)
        let body = file.body.trimmingCharacters(in: .newlines)
        if body.contains(e.link) { return true }
        let line = Diary.line(e.link)
        let lastIsPicture = body.components(separatedBy: "\n").last.map { Diary.picture(in: $0) != nil } ?? false
        file.body = body.isEmpty ? line : body + (lastIsPicture ? "\n" : "\n\n") + line
        if file.value("date") == nil { file.set("date", e.day) }
        guard Vault.reading(at: url, coordinated: false) == was else { return false }
        return Vault.write(file.text, to: url) == nil
    }

    /// Стереть навсегда.
    static func purge(_ e: Entry, _ vault: Vault) {
        guard let root = vault.root, let file = url(of: e, vault) else { return }
        remove(file)
        drop(e, root: root)
    }

    /// Стереть всё, что пролежало 30 дней, — при каждом возвращении в
    /// приложение.
    static func purgeOld(_ vault: Vault, now: Date = Date()) {
        guard let root = vault.root,
              let names = try? FileManager.default.contentsOfDirectory(atPath: base(root).path)
        else { return }
        let limit = Calendar.current.date(byAdding: .day, value: -days,
                                          to: Calendar.current.startOfDay(for: now)) ?? now
        for name in names {
            guard let d = Vault.date(from: String(name.prefix(10))), d <= limit else { continue }
            remove(base(root).appendingPathComponent(name))
        }
    }

    /// Файл, которого нет на месте, но который лежит в корзине, — чтобы
    /// ссылка, вернувшаяся «шагом назад», показывала снимок, а не пустоту.
    static func find(_ rel: String, root: URL) -> URL? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: base(root).path) else { return nil }
        for name in names.sorted(by: >) {
            let candidate = base(root).appendingPathComponent(name).appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: - Опись

    private static func index(_ folder: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(indexName)),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return list
    }

    private static func save(_ list: [Entry], _ folder: URL) {
        let coder = JSONEncoder()
        coder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? coder.encode(list) else { return }
        _ = Vault.write(data: data, to: folder.appendingPathComponent(indexName))
    }

    private static func drop(_ e: Entry, root: URL) {
        let folder = base(root).appendingPathComponent(e.deleted)
        let rest = index(folder).filter { $0.stored != e.stored }
        if rest.isEmpty { remove(folder) } else { save(rest, folder) }
    }

    private static func move(_ from: URL, to: URL) -> Bool {
        var done = false
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: from, options: .forMoving,
                        writingItemAt: to, options: .forReplacing, error: &trouble) { a, b in
                done = (try? FileManager.default.moveItem(at: a, to: b)) != nil
            }
        if !done, FileManager.default.fileExists(atPath: from.path),
           !FileManager.default.fileExists(atPath: to.path) {
            done = (try? FileManager.default.moveItem(at: from, to: to)) != nil
        }
        return done
    }

    private static func remove(_ url: URL) {
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: url, options: .forDeleting, error: &trouble) { real in
                try? FileManager.default.removeItem(at: real)
            }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
