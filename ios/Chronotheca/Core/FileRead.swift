import Foundation

// Нижний слой (P970): чтение вложений через системного посредника (P973).

enum Attachment {

    /// Прочитать вложение через системного посредника — он дождётся, пока
    /// файл придёт из iCloud.
    static func read(_ url: URL) -> Data? {
        var data: Data?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                data = try? Data(contentsOf: real)
            }
        return data
    }

    /// Скачать вложение, если оно в iCloud, и вернуть путь к нему.
    static func fetch(_ url: URL) -> URL? {
        var ready: URL?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                ready = FileManager.default.fileExists(atPath: real.path) ? url : nil
            }
        return ready
    }
}
