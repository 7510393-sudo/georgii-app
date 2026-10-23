import SwiftUI
import UniformTypeIdentifiers

/// Резервная копия архива (P368): вторая папка с теми же записями, снимками
/// и видео — в другом месте, которое человек выбрал сам: флешка, Google
/// Диск, OneDrive, Dropbox.
///
/// Копия делается только кнопкой — приложение само ничего не копирует
/// (главный принцип: всё под рукой человека). Копируется только новое и
/// изменённое; в копии ничего не стирается, даже если в архиве запись
/// удалили, — так копия спасает и от собственной ошибки. Архив копия не
/// трогает: его только читают.
enum Backup {

    static let folderName = "Chronotheca Backup"

    private static let bookmarkKey = "backup.bookmark"
    private static let pathKey = "backup.path"
    private static let lastKey = "backup.last"
    private static let sizeKey = "backup.size"
    private static let sinceKey = "backup.since"
    private static let laterKey = "backup.later"

    // MARK: - Что помним

    /// Когда была последняя копия.
    static var last: Date? {
        let t = UserDefaults.standard.double(forKey: lastKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Сколько весил архив в день последней копии.
    static var sizeAtLast: Int64 { Int64(UserDefaults.standard.double(forKey: sizeKey)) }

    /// Куда копируем — для показа человеку.
    static var placeName: String? { UserDefaults.standard.string(forKey: pathKey) }

    /// Запомнить место копии. Папку человек выбрал в системном окне —
    /// доступ к ней сохраняется закладкой, как к самому архиву.
    static func choose(_ url: URL) -> String? {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else {
            return T("Система не дала запомнить эту папку.", "The system did not let the app remember this folder.")
        }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(Vault.friendly(url.path.removingPercentEncoding ?? url.path),
                                  forKey: pathKey)
        return nil
    }

    private static func place() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        if let url, stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Сколько свободно там, куда кладём копию (P428). `nil` — место не
    /// выбрано или система не ответила.
    static func freeSpace() -> Int64? {
        guard let url = place() else { return nil }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        if let important = v.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return v.volumeAvailableCapacity.map(Int64.init)
    }

    // MARK: - Где нельзя

    /// Почему в это место копию класть не стоит; `nil` — можно.
    static func trouble(with dest: URL, archive root: URL) -> String? {
        let a = root.standardizedFileURL.resolvingSymlinksInPath().path
        let b = dest.standardizedFileURL.resolvingSymlinksInPath().path
        if b == a || b.hasPrefix(a + "/") || a.hasPrefix(b + "/") {
            return T("Это та же папка, что и архив, или папка внутри него. Копия должна лежать в другом месте.",
                     "This is the archive folder itself or a folder inside it. The backup must be somewhere else.")
        }
        return nil
    }

    /// Архив и копия в одном iCloud: копия не защитит от беды с iCloud и
    /// займёт там вдвое больше места.
    /// Своя папка приложения в iCloud (P452) лежит рядом с iCloud Drive, а
    /// не внутри «com~apple~CloudDocs» — потому сверяем по «Mobile
    /// Documents», общему корню всего iCloud Drive (P575).
    static func sameCloud(_ dest: URL, archive root: URL) -> Bool {
        let cloud = "/Mobile Documents/"
        return dest.path.contains(cloud) && root.path.contains(cloud)
    }

    // MARK: - Пять ступеней (P375)
    //
    // 1. Место: можно ли туда писать — пробным файлом.
    // 2. Опись: все файлы архива; не скачанные из iCloud — скачать.
    //    Хватит ли места — до начала копирования.
    // 3. Копирование: только новое и изменённое; каждый файл пишется под
    //    временным именем, сверяется с оригиналом байт в байт и только
    //    потом получает своё имя.
    // 4. Проверка: папка копии читается заново и сверяется с описью.
    // 5. Опись в самой копии: «About this backup.txt» — её можно открыть и
    //    без приложения.
    // Архив только читается; в копии ничего не стирается.

    static let noteName = "About this backup.txt"
    private static let completeKey = "backup.complete"
    private static let missingKey = "backup.missing"

    /// Была ли последняя копия полной.
    static var lastComplete: Bool {
        UserDefaults.standard.object(forKey: completeKey) as? Bool ?? true
    }

    /// Копия полная и не старше месяца — строка в настройках обычная; нет
    /// — жёлтая (P375). Копии ещё не было — тоже жёлтая.
    static var healthy: Bool {
        guard let last else { return false }
        return lastComplete && Date().timeIntervalSince(last) < 31 * 86_400
    }

    /// Открытое место копии: доступ к папке держится, пока идут ступени.
    final class Session {
        let dest: URL
        let target: URL
        private let opened: Bool

        init(dest: URL, target: URL, opened: Bool) {
            self.dest = dest
            self.target = target
            self.opened = opened
        }

        func close() {
            if opened { dest.stopAccessingSecurityScopedResource() }
        }
    }

    /// Ступень 1. Место копии: есть ли оно, не в архиве ли, можно ли туда
    /// писать — пробный файл пишется, читается и стирается.
    static func openPlace(archive root: URL) -> Result<Session, BackupError> {
        guard let dest = place() else { return .failure(.noPlace) }
        let opened = dest.startAccessingSecurityScopedResource()
        let session = Session(dest: dest, target: dest.appendingPathComponent(folderName), opened: opened)
        if let t = trouble(with: dest, archive: root) {
            session.close()
            return .failure(.text(t))
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: session.target, withIntermediateDirectories: true)
            let probe = session.target.appendingPathComponent(".probe-" + UUID().uuidString)
            let sample = Data("chronotheca".utf8)
            try sample.write(to: probe)
            let back = try Data(contentsOf: probe)
            try? fm.removeItem(at: probe)
            guard back == sample else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            session.close()
            return .failure(.text(T("В это место не получается записать: ", "Cannot write to this place: ")
                                  + error.localizedDescription))
        }
        return .success(session)
    }

    /// Файл архива: где лежит, путь внутри архива, сколько весит.
    struct Item {
        let url: URL
        let rel: String
        let size: Int64
        let changed: Date?
    }

    struct Inventory {
        var items: [Item] = []
        /// Файлы, которые лежат только в iCloud, — на телефоне их нет.
        var away: [URL] = []
        var bytes: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    /// Ступень 2. Опись архива. Скрытые файлы и папки не берутся; файл,
    /// которого ещё нет на телефоне (в iCloud он виден заглушкой), — в
    /// `away`.
    static func inventory(_ root: URL) -> Inventory {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                                      .ubiquitousItemDownloadingStatusKey]
        var inv = Inventory()
        let head = root.standardizedFileURL.path
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return inv }
        for case let url as URL in walk {
            let name = url.lastPathComponent
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if name.hasPrefix(".") { walk.skipDescendants() }
                continue
            }
            if name.hasPrefix(".") {
                // Заглушка iCloud: «.снимок.heic.icloud» — это «снимок.heic».
                if name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    inv.away.append(url.deletingLastPathComponent().appendingPathComponent(real))
                }
                continue
            }
            if let status = v?.ubiquitousItemDownloadingStatus, status != .current {
                inv.away.append(url)
                continue
            }
            let rel = String(url.standardizedFileURL.path.dropFirst(head.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            inv.items.append(Item(url: url, rel: rel, size: Int64(v?.fileSize ?? 0),
                                  changed: v?.contentModificationDate))
        }
        return inv
    }

    /// Попросить iPhone скачать файлы из iCloud и подождать. `step` —
    /// сколько уже на телефоне из скольких. Возвращает те, что так и не
    /// пришли.
    static func fetch(_ away: [URL], wait: TimeInterval = 90,
                      step: (Int, Int) -> Void) -> [URL] {
        let fm = FileManager.default
        for url in away { try? fm.startDownloadingUbiquitousItem(at: url) }
        let start = Date()
        var left = away
        while !left.isEmpty {
            left = left.filter { url in
                var url = url
                url.removeAllCachedResourceValues()
                let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                return !(fm.fileExists(atPath: url.path) && (v?.ubiquitousItemDownloadingStatus ?? .current) == .current)
            }
            step(away.count - left.count, away.count)
            if left.isEmpty || Date().timeIntervalSince(start) > wait { break }
            Thread.sleep(forTimeInterval: 1)
        }
        return left
    }

    /// Что из описи надо копировать: в копии нет, другой размер или
    /// старее.
    static func toCopy(_ inv: Inventory, into target: URL) -> [Item] {
        inv.items.filter { item in
            let c = try? target.appendingPathComponent(item.rel)
                .resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let c, let size = c.fileSize, Int64(size) == item.size else { return true }
            guard let mine = item.changed, let theirs = c.contentModificationDate else { return false }
            return theirs < mine
        }
    }

    /// Хватит ли места: `nil` — хватит (или узнать нельзя), иначе — что
    /// сказать человеку.
    static func space(needed: Int64, at target: URL) -> String? {
        guard needed > 0,
              let v = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, free > 0
        else { return nil }
        let margin: Int64 = 50_000_000
        guard free < needed + margin else { return nil }
        let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        let n = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
        return T("Не хватает места: нужно \(n), свободно \(f). Ничего не скопировано.",
                 "Not enough space: \(n) needed, \(f) free. Nothing was copied.")
    }

    /// Ступень 3. Скопировать один файл: под временным именем, сверить
    /// с оригиналом, потом дать своё имя. `false` — не вышло; прежняя
    /// копия файла, если была, осталась как была.
    static func copyOne(_ item: Item, into target: URL) -> Bool {
        let fm = FileManager.default
        let copy = target.appendingPathComponent(item.rel)
        let temp = copy.deletingLastPathComponent()
            .appendingPathComponent(".part-" + UUID().uuidString + "-" + copy.lastPathComponent)
        do {
            try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: item.url, to: temp)
            guard same(item.url, temp) else {
                try? fm.removeItem(at: temp)
                return false
            }
            if fm.fileExists(atPath: copy.path) {
                _ = try fm.replaceItemAt(copy, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: copy)
            }
            return true
        } catch {
            try? fm.removeItem(at: temp)
            return false
        }
    }

    /// Два файла одинаковы байт в байт.
    static func same(_ a: URL, _ b: URL) -> Bool {
        guard let x = try? FileHandle(forReadingFrom: a),
              let y = try? FileHandle(forReadingFrom: b) else { return false }
        defer {
            try? x.close()
            try? y.close()
        }
        let chunk = 1 << 20
        while true {
            let p = try? x.read(upToCount: chunk)
            let q = try? y.read(upToCount: chunk)
            if p != q { return false }
            if p == nil || p?.isEmpty == true { return true }
        }
    }

    /// Ступень 4. Сверить папку копии с описью: чего в ней нет или что
    /// другого размера.
    static func verify(_ inv: Inventory, in target: URL) -> [String] {
        inv.items.compactMap { item in
            let v = try? target.appendingPathComponent(item.rel).resourceValues(forKeys: [.fileSizeKey])
            guard let size = v?.fileSize, Int64(size) == item.size else { return item.rel }
            return nil
        }
    }

    /// Ступень 5. Опись в самой копии — простым текстом.
    @discardableResult
    static func writeNote(_ inv: Inventory, missing: [String], away: [URL], in target: URL,
                          device: String) -> Bool {
        let when = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        let bytes = ByteCountFormatter.string(fromByteCount: inv.bytes, countStyle: .file)
        let complete = missing.isEmpty && away.isEmpty
        var lines = [
            T("Резервная копия «Graphomanus»", "Graphomanus backup"),
            "",
            T("Когда: ", "When: ") + when,
            T("С какого устройства: ", "From: ") + device,
            T("Файлов: \(inv.items.count), \(bytes)", "Files: \(inv.items.count), \(bytes)"),
            complete ? T("Копия полная.", "The backup is complete.")
                     : T("Копия неполная — вот чего в ней нет:", "The backup is incomplete — these are missing:"),
        ]
        lines += (missing + away.map(\.lastPathComponent)).prefix(200).map { "  " + $0 }
        lines += [
            "",
            T("Записи — обычные файлы: дневник и план — текст (.md), снимки, голос и видео — как есть. "
              + "Их можно открыть любым приложением.",
              "Entries are ordinary files: diary and plan are text (.md); photos, voice and video are as they were. "
              + "Any app can open them."),
            T("Как вернуть: скопируйте эту папку на iPhone (в «Файлы») и в «Graphomanus» выберите её папкой "
              + "записей. В копии ничего не стирается: старые файлы остаются и после того, "
              + "как их удалили в приложении.",
              "To restore: copy this folder to your iPhone (in Files) and choose it in Graphomanus as the "
              + "folder for entries. Nothing is ever deleted from a backup: old files stay even after you "
              + "delete them in the app."),
        ]
        let text = lines.joined(separator: "\n") + "\n"
        return (try? Data(text.utf8).write(to: target.appendingPathComponent(noteName), options: .atomic)) != nil
    }

    // MARK: - Исчезнувшие файлы (P377)

    /// Опись прошлой копии — пути внутри архива. Лежит у приложения, а не в
    /// папке человека: это память приложения, а не запись.
    private static var listURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("backup-list.json")
    }

    static func previousList() -> [String] {
        guard let url = listURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    static func saveList(_ inv: Inventory, root: URL) {
        guard let url = listURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let all = inv.items.map(\.rel) + inv.away.map { rel($0, root: root) }
        if let data = try? JSONEncoder().encode(all.sorted()) { try? data.write(to: url, options: .atomic) }
    }

    static func rel(_ url: URL, root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Файлы, которые были в архиве при прошлой копии, а теперь их нет, —
    /// и не потому, что их убрали в корзину приложения. В копии они целы.
    static func vanished(_ inv: Inventory, previous: [String], root: URL, target: URL) -> [String] {
        let now = Set(inv.items.map(\.rel) + inv.away.map { rel($0, root: root) })
        let trash = Vault.trash(in: root).lastPathComponent
        let fm = FileManager.default
        return previous.filter { path in
            !now.contains(path)
                && path.split(separator: "/").first.map(String.init) != trash
                && FileTrash.find(path, root: root) == nil
                && fm.fileExists(atPath: target.appendingPathComponent(path).path)
        }
    }

    /// Вернуть файлы из копии в архив. Файл, который уже лежит на месте,
    /// не трогается (P182). Возвращает, сколько вернулось.
    static func bringBack(_ paths: [String], archive root: URL) -> Int {
        guard case .success(let session) = openPlace(archive: root) else { return 0 }
        defer { session.close() }
        let fm = FileManager.default
        var n = 0
        for path in paths {
            let from = session.target.appendingPathComponent(path)
            let to = root.appendingPathComponent(path)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.copyItem(at: from, to: to)) != nil { n += 1 }
        }
        return n
    }

    /// Запомнить копию: когда, сколько весил архив, полная ли.
    static func record(size: Int64, complete: Bool, missing: Int) {
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: lastKey)
        d.set(Double(size), forKey: sizeKey)
        d.set(complete, forKey: completeKey)
        d.set(missing, forKey: missingKey)
        d.removeObject(forKey: laterKey)
    }

    struct Report {
        var copied = 0
        var same = 0
        /// Файлы, которые ещё не скачаны из iCloud, — их не скопировать.
        var away = 0
        var failed = 0
        /// Чего нет в копии после проверки.
        var missing: [String] = []
        var complete: Bool { away == 0 && missing.isEmpty }
    }

    /// Все пять ступеней подряд, без ожидания iCloud, — для проверок.
    static func run(archive root: URL, size: Int64,
                    step: @escaping (Int, Int) -> Void) -> Result<Report, BackupError> {
        let session: Session
        switch openPlace(archive: root) {
        case .failure(let e): return .failure(e)
        case .success(let s): session = s
        }
        defer { session.close() }
        let inv = inventory(root)
        let todo = toCopy(inv, into: session.target)
        if let t = space(needed: todo.reduce(0) { $0 + $1.size }, at: session.target) {
            return .failure(.text(t))
        }
        var report = Report()
        report.away = inv.away.count
        report.same = inv.items.count - todo.count
        for (i, item) in todo.enumerated() {
            if copyOne(item, into: session.target) { report.copied += 1 } else { report.failed += 1 }
            step(i + 1, todo.count)
        }
        report.missing = verify(inv, in: session.target)
        writeNote(inv, missing: report.missing, away: inv.away, in: session.target, device: "test")
        record(size: size, complete: report.complete, missing: report.missing.count + report.away)
        saveList(inv, root: root)
        return .success(report)
    }

    enum BackupError: Error {
        case noPlace
        case text(String)

        var text: String {
            switch self {
            case .noPlace: return T("Сначала выберите, куда копировать.", "First choose where to copy.")
            case .text(let t): return t
            }
        }
    }

    // MARK: - Напоминание

    /// Сколько весит архив — вместе со снимками, голосом и видео.
    static func size(of root: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .isDirectoryKey]
        if let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in walk {
                guard let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
                total += Int64(v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static let gigabyte: Int64 = 1_000_000_000

    /// Пора ли напомнить — и что сказать. Два правила, что раньше (P368):
    /// с прошлой копии добавился гигабайт — или прошёл месяц, а архив за
    /// это время вырос. Нажали «Позже» — три дня не спрашиваем.
    static func reminder(size: Int64, now: Date = Date()) -> String? {
        let d = UserDefaults.standard
        if d.double(forKey: sinceKey) == 0 { d.set(now.timeIntervalSince1970, forKey: sinceKey) }
        let later = d.double(forKey: laterKey)
        if later > 0, now.timeIntervalSince1970 - later < 3 * 86_400 { return nil }
        let start = last ?? Date(timeIntervalSince1970: d.double(forKey: sinceKey))
        let grew = size - sizeAtLast
        let days = now.timeIntervalSince(start) / 86_400
        let bytes = ByteCountFormatter.string(fromByteCount: max(grew, 0), countStyle: .file)
        if grew >= gigabyte {
            return T("С прошлой копии добавилось \(bytes).", "\(bytes) added since the last backup.")
        }
        if days >= 30, grew > 0 {
            return last == nil
                ? T("Копии записей ещё нет — её можно сделать за несколько минут, на флешку или в другое облако, не в тот же iCloud.",
                    "There is no backup of your entries yet — it takes a few minutes, onto a USB stick or another cloud, not the same iCloud.")
                : T("Последней копии больше месяца; с тех пор добавилось \(bytes).",
                    "The last backup is over a month old; \(bytes) added since.")
        }
        return nil
    }

    /// Забыть всё о копиях — для проверок.
    static func reset() {
        for key in [bookmarkKey, pathKey, lastKey, sizeKey, sinceKey, laterKey, completeKey, missingKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if let url = listURL { try? FileManager.default.removeItem(at: url) }
    }

    static func later() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: laterKey)
    }

    /// «полная · 12 дн. назад · с тех пор +340 МБ» или «ещё ни разу».
    /// Строка под «Резервной копией» (P428): когда, сколько весила, куда
    /// легла последняя копия.
    static func detail(size: Int64?) -> String {
        var out = summary(size: size)
        guard last != nil else { return out }
        if sizeAtLast > 0 {
            out += " · " + ByteCountFormatter.string(fromByteCount: sizeAtLast, countStyle: .file)
        }
        if let placeName { out += "\n→ " + placeName }
        return out
    }

    static func summary(size: Int64?) -> String {
        guard let last else { return T("ещё ни разу", "never yet") }
        let days = Int(Date().timeIntervalSince(last) / 86_400)
        var out = lastComplete ? T("полная", "complete") : T("неполная", "incomplete")
        out += " · " + (days == 0 ? T("сегодня", "today") : T("\(days) дн. назад", "\(days) days ago"))
        if let size, size > sizeAtLast {
            out += T(" · с тех пор +", " · since then +")
                + ByteCountFormatter.string(fromByteCount: size - sizeAtLast, countStyle: .file)
        }
        return out
    }
}

/// Окно резервной копии: что это, куда, одна кнопка «Скопировать» и пять
/// ступеней — каждая своей строкой: идёт, прошла или не вышло и почему
/// (P375). Каждый шаг — нажатием человека, и перед ним сказано, что будет.
struct BackupSheet: View {

    @EnvironmentObject private var vault: Vault
    @Environment(\.dismiss) private var dismiss

    enum Stage: Equatable {
        case waiting
        case running(String)
        case done(String)
        case warn(String)
        case failed(String)
    }

    @State private var choosing = false
    @State private var placeName = Backup.placeName
    @State private var warning: String?
    @State private var problem: String?
    @State private var stages: [Stage] = Array(repeating: .waiting, count: 5)
    @State private var running = false
    /// Копия кончилась (P602): `true` — полная, `false` — неполная. Кнопка
    /// говорит, что вышло, — прежде после хода внизу оставалась простыня
    /// ступеней, а кнопка стояла как ни в чём не бывало.
    @State private var finished: Bool?
    /// Не все файлы пришли из iCloud — ждём ответа человека.
    @State private var pending: (Backup.Session, Backup.Inventory)?
    /// С прошлой копии этих файлов в архиве не стало (P377).
    @State private var vanished: [String] = []
    @State private var broughtBack: String?
    @State private var archiveSize: Int64?
    @State private var free: Int64?

    private static var names: [String] {
        [T("Место копии", "Backup place"),
         T("Опись архива", "List of files"),
         T("Копирование", "Copying"),
         T("Проверка копии", "Checking the backup"),
         T("Опись в самой копии", "Note inside the backup")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(T("Копия — это вторая папка с теми же записями, снимками и видео, но в другом месте: "
                           + "на флешке или в другом облаке (Google Диск, OneDrive, Dropbox). Случится что-то "
                           + "с телефоном или iCloud — записи останутся там.",
                           "A backup is a second folder with the same entries, photos and videos, kept somewhere "
                           + "else: on a USB stick or in another cloud (Google Drive, OneDrive, Dropbox). If "
                           + "something happens to your phone or iCloud, your entries stay there."))
                    // Копия в том же iCloud — не копия (P575): удалённое там
                    // удалится на всех устройствах сразу.
                    Text(T("Копия в той же папке iCloud удалится вместе с записями — поэтому её лучше держать вне iCloud.",
                           "A backup in the same iCloud folder would be deleted together with your entries — so it is better kept outside iCloud."))
                        .foregroundStyle(Look.inkSoft)
                    Text(T("Копируется только новое и изменённое. В копии ничего не стирается, даже если "
                           + "запись удалили здесь. Сами записи копия не трогает.",
                           "Only new and changed files are copied. Nothing is ever deleted from the backup, "
                           + "even if you delete an entry here. Your entries themselves are left untouched."))
                        .foregroundStyle(Look.inkSoft)

                    // Что и куда — до копирования (P428): откуда, сколько
                    // весит архив, куда и сколько там свободно.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Что копируем", "What is copied")).font(Look.sans(13, weight: .semibold))
                        Text(vault.friendlyPath).font(Look.sans(13)).foregroundStyle(Look.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(T("Весь архив: ", "The whole archive: ")
                             + (archiveSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                                ?? T("считаю…", "counting…")))
                            .font(Look.sans(13)).foregroundStyle(Look.inkSoft)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Куда копировать", "Where to copy")).font(Look.sans(13, weight: .semibold))
                        Text(placeName ?? T("ещё не выбрано", "not chosen yet"))
                            .foregroundStyle(placeName == nil ? Look.inkFaint : Look.ink)
                        if placeName != nil, let free {
                            Text(T("Свободно там: ", "Free there: ")
                                 + ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                                .font(Look.sans(13))
                                .foregroundStyle(archiveSize.map { $0 > free } == true ? .red : Look.inkSoft)
                        }
                        Button(placeName == nil ? T("Выбрать место…", "Choose a place…")
                                                : T("Выбрать другое место…", "Choose another place…")) {
                            choosing = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(running)
                        if let warning {
                            Text(warning).font(Look.sans(13)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // После копирования — куда и сколько легло (P428).
                        Text(T("Последняя копия: ", "Last backup: ") + Backup.detail(size: nil))
                            .foregroundStyle(Look.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            copy()
                        } label: {
                            Text(running ? T("Копирую…", "Copying…")
                                 : finished == true ? T("✓ Скопировано", "✓ Copied")
                                 : finished == false ? T("Скопировано не всё — ещё раз", "Not everything was copied — again")
                                 : T("Скопировать сейчас", "Copy now"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(placeName == nil || running || finished == true)
                    }

                    if stages.contains(where: { $0 != .waiting }) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(0..<5, id: \.self) { i in row(i) }
                        }
                        .padding(12)
                        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let pending { question(pending.1.away.count) }
                    if !vanished.isEmpty || broughtBack != nil { vanishedNote }
                    if let problem {
                        Text(problem).font(Look.sans(14)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(Look.sans(15))
                .padding(20)
            }
            .navigationTitle(T("Резервная копия", "Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { dismiss() }.disabled(running)
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { picked in
                guard case .success(let url) = picked else { return }
                pick(url)
            }
        }
        .interactiveDismissDisabled(running)
        .onAppear(perform: measure)
        .onChange(of: placeName) { _, _ in
            finished = nil
            measure()
        }
        .onChange(of: running) { _, now in if !now { measure() } }
    }

    /// Объём архива и свободное место у копии — в стороне от экрана.
    private func measure() {
        let root = vault.root
        DispatchQueue.global(qos: .utility).async {
            let size = root.map(Backup.size(of:))
            let space = Backup.freeSpace()
            DispatchQueue.main.async {
                archiveSize = size
                free = space
            }
        }
    }

    // MARK: - Ступени на экране

    private func row(_ i: Int) -> some View {
        let stage = stages[i]
        return HStack(alignment: .top, spacing: 10) {
            Group {
                switch stage {
                case .waiting:
                    Image(systemName: "circle").foregroundStyle(Look.inkFaint)
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .warn:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .failed:
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 22, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(i + 1). " + Self.names[i])
                    .font(Look.sans(14, weight: .semibold))
                    .foregroundStyle(stage == .waiting ? Look.inkFaint : Look.ink)
                if let text = detail(stage) {
                    Text(text)
                        .font(Look.sans(13))
                        .foregroundStyle(color(stage))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func detail(_ s: Stage) -> String? {
        switch s {
        case .waiting: return nil
        case .running(let t), .done(let t), .warn(let t), .failed(let t): return t
        }
    }

    private func color(_ s: Stage) -> Color {
        switch s {
        case .warn: return .orange
        case .failed: return .red
        default: return Look.inkSoft
        }
    }

    /// Не все файлы пришли из iCloud: подождать ещё или копировать без них.
    private func question(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Файлов нет на телефоне — они только в iCloud: \(count). Без них копия будет неполной.",
                   "Files not on this phone — only in iCloud: \(count). Without them the backup will be incomplete."))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(T("Подождать ещё", "Wait longer")) { waitMore() }
                    .buttonStyle(.borderedProminent)
                Button(T("Копировать без них", "Copy without them")) { goOn() }
                    .buttonStyle(.bordered)
            }
            Button(T("Отменить", "Cancel"), role: .cancel) { cancel() }
                .font(Look.sans(14))
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    /// «С прошлой копии не стало файлов» — и кнопка вернуть их из копии.
    private var vanishedNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vanished.isEmpty {
                Text(T("С прошлой копии в записях не стало файлов: \(vanished.count). Если вы удаляли их сами — "
                       + "всё в порядке. Если нет — они целы в копии.",
                       "Since the last backup, files are gone from your entries: \(vanished.count). If you deleted "
                       + "them yourself, all is well. If not, they are safe in the backup."))
                    .fixedSize(horizontal: false, vertical: true)
                Text(vanished.prefix(5).joined(separator: "\n") + (vanished.count > 5 ? "\n…" : ""))
                    .font(Look.mono(11.5))
                    .foregroundStyle(Look.inkSoft)
                // Что произойдёт — словами до нажатия (P458).
                Text(T("«Вернуть из копии» положит эти файлы обратно в папку записей — туда, где они лежали. Ничего не удаляется и не заменяется: файл, который уже на месте, не трогается. Если файл вы удалили нарочно, просто не нажимайте.",
                       "“Bring them back” puts these files back into your entries folder, where they were. Nothing is deleted or replaced: a file already in place is left alone. If you deleted a file on purpose, just don’t tap."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(T("Вернуть из копии", "Bring them back from the backup")) { bringBack() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
            }
            if let broughtBack {
                Text(broughtBack).font(Look.sans(14, weight: .medium))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bringBack() {
        guard let root = vault.root else { return }
        let list = vanished
        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            let n = Backup.bringBack(list, archive: root)
            DispatchQueue.main.async {
                running = false
                vanished = []
                broughtBack = T("Возвращено файлов: \(n). Те, что уже лежали на месте, не тронуты.",
                                "Files brought back: \(n). Files already in place were left alone.")
                Feel.done()
            }
        }
    }

    // MARK: - Ход

    private func pick(_ url: URL) {
        problem = nil
        if let root = vault.root, let t = Backup.trouble(with: url, archive: root) {
            problem = t
            return
        }
        if let t = Backup.choose(url) {
            problem = t
            return
        }
        placeName = Backup.placeName
        stages = Array(repeating: .waiting, count: 5)
        warning = vault.root.map { Backup.sameCloud(url, archive: $0) } == true
            ? T("Это тот же iCloud, где лежат записи: от беды с iCloud такая копия не спасёт и займёт там "
                + "вдвое больше места. Лучше флешка или другое облако.",
                "This is the same iCloud your entries are in: such a backup will not help if something "
                + "happens to iCloud, and it takes twice the space there. A USB stick or another cloud is better.")
            : nil
    }

    private func set(_ i: Int, _ s: Stage) {
        DispatchQueue.main.async { stages[i] = s }
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func copy() {
        guard let root = vault.root else { return }
        problem = nil
        running = true
        finished = nil
        vanished = []
        broughtBack = nil
        stages = Array(repeating: .waiting, count: 5)
        DispatchQueue.global(qos: .userInitiated).async {
            set(0, .running(T("Проверяю, можно ли туда писать…", "Checking that the place can be written to…")))
            let session: Backup.Session
            switch Backup.openPlace(archive: root) {
            case .failure(let e):
                set(0, .failed(e.text))
                DispatchQueue.main.async { running = false }
                return
            case .success(let s):
                session = s
            }
            set(0, .done(Backup.placeName ?? ""))
            set(1, .running(T("Составляю опись…", "Listing the files…")))
            var inv = Backup.inventory(root)
            if !inv.away.isEmpty {
                fetch(inv.away)
                inv = Backup.inventory(root)
            }
            if inv.away.isEmpty {
                proceed(session, inv, root: root)
            } else {
                DispatchQueue.main.async { pending = (session, inv) }
            }
        }
    }

    /// Попросить iPhone скачать файлы из iCloud и подождать.
    private func fetch(_ away: [URL]) {
        _ = Backup.fetch(away) { got, all in
            set(1, .running(T("Скачиваю из iCloud: \(got) из \(all)", "Downloading from iCloud: \(got) of \(all)")))
        }
    }

    private func waitMore() {
        guard let p = pending, let root = vault.root else { return }
        let session = p.0
        pending = nil
        DispatchQueue.global(qos: .userInitiated).async {
            fetch(p.1.away)
            let fresh = Backup.inventory(root)
            if fresh.away.isEmpty {
                proceed(session, fresh, root: root)
            } else {
                DispatchQueue.main.async { pending = (session, fresh) }
            }
        }
    }

    private func goOn() {
        guard let p = pending, let root = vault.root else { return }
        pending = nil
        DispatchQueue.global(qos: .userInitiated).async { proceed(p.0, p.1, root: root) }
    }

    private func cancel() {
        pending?.0.close()
        pending = nil
        stages[1] = .warn(T("Отменено — ничего не скопировано.", "Cancelled — nothing was copied."))
        running = false
    }

    /// Ступени 2–5 после описи. Работает в стороне от главного потока.
    private func proceed(_ session: Backup.Session, _ inv: Backup.Inventory, root: URL) {
        defer { session.close() }
        let target = session.target
        let todo = Backup.toCopy(inv, into: target)
        let need = todo.reduce(0) { $0 + $1.size }
        if let t = Backup.space(needed: need, at: target) {
            set(1, .failed(t))
            DispatchQueue.main.async { running = false }
            return
        }
        var listed = T("Файлов: \(inv.items.count) · \(Self.bytes(inv.bytes))",
                       "Files: \(inv.items.count) · \(Self.bytes(inv.bytes))")
        if !inv.away.isEmpty {
            listed += T(" · только в iCloud, без них: \(inv.away.count)",
                        " · only in iCloud, left out: \(inv.away.count)")
        }
        set(1, inv.away.isEmpty ? .done(listed) : .warn(listed))
        let gone = Backup.vanished(inv, previous: Backup.previousList(), root: root, target: target)
        if !gone.isEmpty { DispatchQueue.main.async { vanished = gone } }

        // 3. Копирование.
        var failed: [String] = []
        var done: Int64 = 0
        let all = Self.bytes(need)
        for (i, item) in todo.enumerated() {
            if i % 5 == 0 {
                set(2, .running(T("Копирую: \(i) из \(todo.count) · \(Self.bytes(done)) из \(all)",
                                  "Copying: \(i) of \(todo.count) · \(Self.bytes(done)) of \(all)")))
            }
            if !Backup.copyOne(item, into: target) { failed.append(item.rel) }
            done += item.size
        }
        let copied = todo.count - failed.count
        let copiedText = todo.isEmpty
            ? T("Нового нет — копия и так свежая.", "Nothing new — the backup was already up to date.")
            : T("Скопировано и сверено байт в байт: \(copied) · \(all)",
                "Copied and checked byte for byte: \(copied) · \(all)")
        if failed.isEmpty {
            set(2, .done(copiedText))
        } else {
            set(2, .warn(copiedText + T(" · не скопировались: \(failed.count)", " · could not copy: \(failed.count)")))
        }

        // 4. Проверка.
        set(3, .running(T("Сверяю копию с описью…", "Comparing the backup with the list…")))
        let missing = Backup.verify(inv, in: target)
        let complete = missing.isEmpty && inv.away.isEmpty
        if complete {
            set(3, .done(T("Копия полная: \(inv.items.count) файлов, \(Self.bytes(inv.bytes))",
                           "The backup is complete: \(inv.items.count) files, \(Self.bytes(inv.bytes))")))
        } else {
            let names = (missing + inv.away.map(\.lastPathComponent)).prefix(5).joined(separator: ", ")
            set(3, .warn(T("Копия неполная: нет файлов — \(missing.count + inv.away.count): \(names)",
                           "The backup is incomplete: \(missing.count + inv.away.count) files missing: \(names)")))
        }

        // 5. Опись в копии.
        let device = DispatchQueue.main.sync { UIDevice.current.name }
        if Backup.writeNote(inv, missing: missing, away: inv.away, in: target, device: device) {
            set(4, .done(Backup.noteName + T(" — её можно открыть и без приложения.", " — it opens without the app.")))
        } else {
            set(4, .warn(T("Опись не записалась; сама копия цела.", "The note could not be written; the backup itself is fine.")))
        }

        Backup.record(size: Backup.size(of: root), complete: complete,
                      missing: missing.count + inv.away.count)
        // Опись этой копии — чтобы в следующий раз заметить исчезнувшее.
        // О тех, что исчезли сейчас, спрашиваем один раз: в копии они целы.
        Backup.saveList(inv, root: root)
        DispatchQueue.main.async {
            if complete { Feel.done() } else { Feel.light() }
            finished = complete
            running = false
        }
    }
}

/// Напоминание о копии (P368): при возвращении в приложение, не чаще раза в
/// три дня после «Позже». Окно с двумя кнопками — само ничего не копирует.
struct BackupReminder: ViewModifier {
    @EnvironmentObject private var vault: Vault
    @Environment(\.scenePhase) private var phase

    @State private var message: String?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, now in if now == .active { check() } }
            .onAppear(perform: check)
            .alert(T("Пора сделать резервную копию", "Time to make a backup"),
                   isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(T("Сделать копию", "Make a backup")) {
                    message = nil
                    showing = true
                }
                Button(T("Позже", "Later"), role: .cancel) {
                    Backup.later()
                    message = nil
                }
            } message: {
                Text((message ?? "") + T(" Копия ляжет туда, куда вы скажете; приложение само ничего не копирует.",
                                         " It goes wherever you choose; the app never copies anything by itself."))
            }
            .sheet(isPresented: $showing) { BackupSheet().environmentObject(vault) }
    }

    private func check() {
        guard !Vault.isPreview, let root = vault.root else { return }
        DispatchQueue.global(qos: .utility).async {
            let say = Backup.reminder(size: Backup.size(of: root))
            DispatchQueue.main.async { if let say { message = say } }
        }
    }
}
