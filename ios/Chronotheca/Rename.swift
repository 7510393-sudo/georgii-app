import Foundation

/// Перевод имён папок архива на английский (P353): «Дневник» → «Diary»,
/// «Фотографии» → «Photos» и так далее, ссылки в записях и ключи в шапке
/// файлов — следом.
///
/// Запускает человек, кнопкой в настройках: это его папка. Порядок такой,
/// чтобы обрыв на любом шаге ничего не стоил:
///
/// 1. Папки переименовываются целиком — файлы внутри не копируются и не
///    пересоздаются. Приложение находит каждую папку под любым из двух
///    имён, так что наполовину переименованный архив читается, как прежде.
/// 2. В записях правятся ссылки на снимки, видео, голос и документы. Файл
///    переписывается, только если он прочитан напрямую и не изменился с тех
///    пор, как его прочитали; не прочитался (ещё в iCloud) — пропускается.
///    Непоправленная ссылка всё равно работает: снимок ищется под обоими
///    именами папки (`Vault.mediaURL`).
///
/// Запустить можно снова — сделанное не повторяется, недоделанное
/// доделывается.
enum Rename {

    struct Report: Identifiable {
        let id = UUID()
        var folders = 0
        var files = 0
        /// Файлы, которые не прочитались или изменились в другом месте, —
        /// их ссылки остались прежними, но работают.
        var skipped = 0
        /// Одноимённые файлы в обеих папках, разные по содержанию: остались
        /// оба, в прежней папке.
        var kept = 0
        /// Папки, которые не удалось переименовать: они работают под
        /// прежним именем.
        var stuck: [String] = []
    }

    /// Папки верхнего уровня: прежнее имя → новое.
    static var pairs: [(ru: String, en: String)] {
        Vault.Folder.allCases.map { (ru: $0.russian, en: $0.rawValue) }
            + [(ru: Vault.trashRussian, en: Vault.trashName)]
    }

    /// Папки вложений — в записях на них ссылки.
    private static let media: [Vault.Folder] = [.photos, .videos, .audio, .documents]

    static func run(in root: URL, step: (Int, Int) -> Void = { _, _ in }) -> Report {
        var report = Report()
        let fm = FileManager.default

        // 1. Папки.
        for (ru, en) in pairs {
            let old = root.appendingPathComponent(ru)
            let new = root.appendingPathComponent(en)
            guard fm.fileExists(atPath: old.path) else { continue }
            if !fm.fileExists(atPath: new.path) {
                if move(old, to: new) { report.folders += 1 } else { report.stuck.append(ru) }
            } else {
                // Обе есть — прежний перевод оборвался или английскую
                // завели раньше. Файлы переезжают по одному, одноимённые
                // разные остаются где были.
                report.kept += merge(old, into: new)
                if isEmpty(old) { try? fm.removeItem(at: old) } else { report.stuck.append(ru) }
                report.folders += 1
            }
        }

        // 2. Записи: ссылки, ключи шапки, заголовок ответов.
        var files: [URL] = []
        for folder in [Vault.Folder.diary, .planner, .places] {
            files += markdown(in: Vault.folder(folder, in: root))
        }
        for (i, url) in files.enumerated() {
            defer { step(i + 1, files.count) }
            guard case .text(let was) = Vault.reading(at: url) else {
                report.skipped += 1
                continue
            }
            let now = translate(was)
            guard now != was else { continue }
            // Перед записью — ещё раз с диска: файл могли поправить на
            // другом устройстве, пока шла опись (P182, P183).
            guard let still = try? String(contentsOf: url, encoding: .utf8), still == was,
                  Vault.write(now, to: url) == nil
            else {
                report.skipped += 1
                continue
            }
            report.files += 1
        }

        // 3. Записка «что это за папка»: прежняя, если её не правили, —
        // на новую, двуязычную.
        let service = Vault.folder(.service, in: root)
        let oldNote = service.appendingPathComponent(Vault.oldNoteName)
        let note = service.appendingPathComponent(Vault.noteName)
        if let text = try? String(contentsOf: oldNote, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines)
               == Vault.oldNoteText.trimmingCharacters(in: .whitespacesAndNewlines),
           !fm.fileExists(atPath: note.path),
           Vault.write(Vault.noteText, to: note) == nil {
            try? fm.removeItem(at: oldNote)
        }
        return report
    }

    // MARK: - Текст файла

    /// Файл записи с английскими ключами шапки, ссылками на английские
    /// папки и английским заголовком ответов. Правятся только эти места,
    /// построчно; всё остальное остаётся байт в байт.
    static func translate(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var i = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == DayFile.fence {
            i = 1
            while i < lines.count {
                let line = lines[i]
                if line.trimmingCharacters(in: .whitespaces) == DayFile.fence { i += 1; break }
                lines[i] = translateKey(line)
                i += 1
            }
        }
        // Заголовок ответов — только первой строкой тела, как его и читают.
        var k = i
        while k < lines.count, lines[k].trimmingCharacters(in: .whitespaces).isEmpty { k += 1 }
        if k < lines.count, lines[k].trimmingCharacters(in: .whitespaces) == Diary.oldHeading {
            lines[k] = Diary.heading
        }
        var out = lines.joined(separator: "\n")
        for folder in media {
            for opening in ["](../../", "](<../../"] {
                out = out.replacingOccurrences(of: opening + folder.russian + "/",
                                               with: opening + folder.rawValue + "/")
            }
        }
        return out
    }

    /// «заголовок: Туман» → «title: Туман»; «значок: личное» → «icon: private».
    private static func translateKey(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard let english = DayFile.english[key] else { return line }
        var value = String(line[line.index(after: colon)...])
        if english == "icon" {
            let word = value.trimmingCharacters(in: .whitespaces)
            value = " " + Glyph.fileWord(word)
        }
        return english + ":" + value
    }

    // MARK: - Папки

    private static func markdown(in folder: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
    }

    /// Разложить содержимое прежней папки по новой. Возвращает, сколько
    /// файлов осталось на месте из-за одноимённых разных.
    private static func merge(_ old: URL, into new: URL) -> Int {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: old, includingPropertiesForKeys: [.isDirectoryKey])
        else { return 0 }
        let head = old.standardizedFileURL.path
        var kept = 0
        for case let url as URL in walk {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(head.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = new.appendingPathComponent(rel)
            if fm.fileExists(atPath: target.path) {
                if same(url, target) { try? fm.removeItem(at: url) } else { kept += 1 }
                continue
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if !move(url, to: target) { kept += 1 }
        }
        return kept
    }

    /// В папке не осталось ни одного файла — одни пустые подпапки.
    private static func isEmpty(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        else { return true }
        for case let url as URL in walk {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { return false }
        }
        return true
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        guard let da = try? Data(contentsOf: a), let db = try? Data(contentsOf: b) else { return false }
        return da == db
    }

    /// Переименовать через системного посредника — iCloud в эту минуту
    /// может сам работать с папкой; не вышло — напрямую, как в корзине.
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
}
