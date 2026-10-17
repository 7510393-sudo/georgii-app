import Foundation

/// Снимки, перенесённые из Diarium, лежали без расширения (P489): у
/// вложения в архиве нет имени с «.jpg», а приложение узнаёт снимок по
/// расширению — файл ложился в «Документы» и не открывался как картинка.
/// Сами байты были целы: с расширением JPEG телефон его открывает.
///
/// Здесь — расширение по первым байтам файла и починка уже перенесённого:
/// файл переименовывается, уходит в свою папку (снимки, видео, звук), а
/// ссылка в записи заменяется на верную.
enum DiariumFix {

    /// Расширения, по которым приложение узнаёт вложение.
    static let known: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp",
                                     "mov", "mp4", "m4v", "m4a", "mp3", "aac", "wav", "caf", "pdf"]

    /// Какое расширение у файла с такими первыми байтами.
    static func sniff(_ head: [UInt8]) -> String? {
        guard head.count >= 4 else { return nil }
        let first4 = Array(head[0..<4])
        func text(_ from: Int, _ to: Int) -> String? {
            guard head.count >= to else { return nil }
            return String(bytes: head[from..<to], encoding: .ascii)
        }
        if head[0] == 0xff, head[1] == 0xd8, head[2] == 0xff { return "jpg" }
        if first4 == [0x89, 0x50, 0x4e, 0x47] { return "png" }
        if text(0, 4) == "GIF8" { return "gif" }
        if text(0, 4) == "RIFF", text(8, 12) == "WEBP" { return "webp" }
        if text(0, 4) == "RIFF", text(8, 12) == "WAVE" { return "wav" }
        if text(0, 4) == "%PDF" { return "pdf" }
        if text(0, 3) == "ID3" { return "mp3" }
        if text(4, 8) == "ftyp", let brand = text(8, 12) {
            switch brand {
            case "heic", "heix", "hevc", "hevx", "mif1", "msf1": return "heic"
            case "qt  ": return "mov"
            case "M4A ", "M4B ": return "m4a"
            default: return "mp4"
            }
        }
        return nil
    }

    /// В какую папку архива идёт файл с таким расширением.
    static func folder(forExt ext: String) -> Vault.Folder {
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return .photos
        case "mov", "mp4", "m4v": return .videos
        case "m4a", "mp3", "aac", "wav", "caf": return .audio
        default: return .documents
        }
    }

    /// Починить всё перенесённое из Diarium: файлы с «_diarium_» в имени без
    /// знакомого расширения получают верное и переезжают в свою папку, ссылки
    /// в записях меняются следом. Возвращает, сколько файлов починено.
    static func run(root: URL) -> Int {
        let fm = FileManager.default
        var moved: [(old: String, new: String)] = []

        for kind in [Vault.Folder.documents, .photos, .videos, .audio] {
            let home = Vault.folder(kind, in: root)
            guard let walker = fm.enumerator(at: home, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            var found: [URL] = []
            while let next = walker.nextObject() as? URL {
                let isDir = (try? next.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir { continue }
                let name = next.lastPathComponent
                guard name.lowercased().contains("_diarium_"), !name.hasPrefix(".") else { continue }
                if known.contains(next.pathExtension.lowercased()) { continue }
                found.append(next)
            }
            for file in found {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                let head = (try? handle.read(upToCount: 32)) ?? Data()
                try? handle.close()
                guard let ext = sniff(Array(head)) else { continue }

                let year = file.deletingLastPathComponent().lastPathComponent
                let oldHome = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                var base = file.lastPathComponent
                if !file.pathExtension.isEmpty { base = (base as NSString).deletingPathExtension }
                while base.hasSuffix(".") { base.removeLast() }

                let newHome = folder(forExt: ext)
                let newHomeURL = Vault.folder(newHome, in: root)
                let dir = year.count == 4 ? newHomeURL.appendingPathComponent(year) : newHomeURL
                var target = dir.appendingPathComponent(base + "." + ext)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    target = dir.appendingPathComponent("\(base) \(n).\(ext)")
                    n += 1
                }
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try fm.moveItem(at: file, to: target)
                } catch { continue }
                let oldLink = "../../" + oldHome + "/" + year + "/" + file.lastPathComponent
                let newLink = "../../" + newHomeURL.lastPathComponent + "/" + (year.count == 4 ? year + "/" : "") + target.lastPathComponent
                moved.append((oldLink, newLink))
            }
        }
        guard !moved.isEmpty else { return 0 }
        rewriteLinks(moved, root: root)
        return moved.count
    }

    /// Заменить в записях дневника старые ссылки на новые.
    private static func rewriteLinks(_ moved: [(old: String, new: String)], root: URL) {
        let fm = FileManager.default
        let home = Vault.folder(.diary, in: root)
        guard let walker = fm.enumerator(at: home, includingPropertiesForKeys: nil) else { return }
        var days: [URL] = []
        while let next = walker.nextObject() as? URL {
            if next.pathExtension.lowercased() == "md" { days.append(next) }
        }
        for day in days {
            let was = Vault.reading(at: day)
            guard case .text(let text) = was else { continue }
            var out = text
            for m in moved where out.contains(m.old) {
                let pattern = "\\[[^\\]]*\\]\\(<?" + NSRegularExpression.escapedPattern(for: m.old) + ">?\\)"
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                let line = Diary.line(m.new)
                out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: line))
            }
            guard out != text else { continue }
            // Файл изменился, пока мы готовили запись, — не пишем (P182).
            guard Vault.reading(at: day, coordinated: false) == was else { continue }
            _ = Vault.write(out, to: day)
        }
    }
}
