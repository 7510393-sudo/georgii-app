import Foundation

/// Страховка недописанного (P900, автор 12.11: «делать»).
///
/// Запись дня не дошла до папки — кончилось место, облако отказало, пропал
/// доступ. Прежде текст жил только на экране: закрыли приложение или ушли
/// на другой день — и он пропадал, а человеку об этом не говорилось
/// (`docs/67`, слабое место 1). Теперь, пока запись не проходит, текст дня
/// лежит здесь, внутри приложения. Дошёл до папки — отсюда стирается.
///
/// Это единственное место, где приложение держит у себя чужой текст, и
/// только на время сбоя: исключение из «приложение ничем не владеет»,
/// принятое автором.
enum Pending {

    struct Draft: Codable, Equatable {
        /// Папка архива, для которой писали.
        var root: String
        var folder: String
        /// День: ГГГГ-ММ-ДД.
        var stamp: String
        /// Что не записалось.
        var text: String
        /// Что лежало в файле, когда приложение его видело: по нему
        /// узнаётся, не изменили ли файл с тех пор в другом месте.
        var base: String
    }

    /// Для проверок — своя папка.
    static var home: URL?

    private static var dir: URL? {
        if let home { return home }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pending", isDirectory: true)
    }

    private static func url(_ folder: Vault.Folder, _ stamp: String) -> URL? {
        dir?.appendingPathComponent(folder.rawValue + "-" + stamp + ".json")
    }

    /// Есть ли хоть что-то — дешёвый вопрос на каждое чтение дня.
    static var any: Bool {
        guard let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return false }
        return names.contains { $0.hasSuffix(".json") }
    }

    @discardableResult
    static func keep(_ text: String, base: String, folder: Vault.Folder, date: Date, root: URL) -> Bool {
        guard let url = url(folder, Vault.stamp(date)) else { return false }
        let draft = Draft(root: root.standardizedFileURL.path, folder: folder.rawValue,
                          stamp: Vault.stamp(date), text: text, base: base)
        // Базу не переписываем: первая неудача помнит, каким файл видели.
        var kept = draft
        if let old = read(url), old.root == draft.root { kept.base = old.base }
        guard let data = try? JSONEncoder().encode(kept) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func drop(_ folder: Vault.Folder, date: Date) {
        guard let url = url(folder, Vault.stamp(date)) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Недописанное этого дня — для этой папки архива.
    static func draft(_ folder: Vault.Folder, date: Date, root: URL) -> Draft? {
        guard let url = url(folder, Vault.stamp(date)), let d = read(url),
              d.root == root.standardizedFileURL.path else { return nil }
        return d
    }

    /// Всё недописанное для этой папки архива.
    static func all(root: URL) -> [Draft] {
        guard let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        let path = root.standardizedFileURL.path
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { read(dir.appendingPathComponent($0)) }
            .filter { $0.root == path }
    }

    private static func read(_ url: URL) -> Draft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    /// Довести недописанное других дней до папки: при запуске и при
    /// возвращении в приложение. Правила те же, что у записи дня (P182,
    /// P183): не скачан — ждём; файл с тех пор не менялся — дописываем;
    /// изменили в другом месте — своё кладётся рядом, второй версией.
    /// Возвращает, сколько записей дошло.
    @discardableResult
    static func settle(_ vault: Vault, except open: Date? = nil) -> Int {
        guard let root = vault.root, any else { return 0 }
        var done = 0
        for d in all(root: root) {
            guard let folder = Vault.Folder(rawValue: d.folder), let date = Vault.date(from: d.stamp)
            else { continue }
            if let open, Vault.stamp(open) == d.stamp { continue }
            let now = vault.reading(folder, for: date)
            if now == .away { continue }
            if now.text == d.text {
                drop(folder, date: date)
            } else if now.text == d.base {
                guard let url = vault.file(folder, for: date), Vault.write(d.text, to: url) == nil
                else { continue }
                drop(folder, date: date)
                done += 1
            } else {
                guard vault.writeAside(d.text, folder: folder, for: date) != nil else { continue }
                drop(folder, date: date)
                done += 1
            }
        }
        return done
    }
}

/// Страховка вложений (P904): голос или снимок с камеры не лёг в папку —
/// прежде приложение говорило «не сохранилось» и стирало его. Теперь он
/// лежит здесь, пока папка не вернётся, и докладывается сам: файл — в свою
/// папку архива, ссылка — на страницу дня (по правилам P182–P183).
enum PendingMedia {

    struct Item: Codable, Equatable {
        var id: String
        var root: String
        var kind: String
        var name: String
        var stamp: String
        /// "diary" или "plan".
        var tab: String
        /// Файл уже в архиве, осталось поставить ссылку в день.
        var link: String?
    }

    static var home: URL?

    private static var dir: URL? {
        if let home { return home }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pending/Media", isDirectory: true)
    }

    static func items(root: URL) -> [Item] {
        guard let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        let path = root.standardizedFileURL.path
        return names.filter { $0.hasSuffix(".json") }.sorted()
            .compactMap { name -> Item? in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
                return try? JSONDecoder().decode(Item.self, from: data)
            }
            .filter { $0.root == path }
    }

    private static func write(_ item: Item) -> Bool {
        guard let dir, let data = try? JSONEncoder().encode(item) else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try? data.write(to: dir.appendingPathComponent(item.id + ".json"), options: .atomic)) != nil
    }

    private static func drop(_ item: Item) {
        guard let dir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.id + ".json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.id + ".bin"))
    }

    @discardableResult
    static func keep(_ data: Data, kind: Vault.Folder, name: String, date: Date, tab: String, root: URL) -> Bool {
        guard let dir else { return false }
        let item = Item(id: UUID().uuidString, root: root.standardizedFileURL.path, kind: kind.rawValue,
                        name: name, stamp: Vault.stamp(date), tab: tab, link: nil)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard (try? data.write(to: dir.appendingPathComponent(item.id + ".bin"), options: .atomic)) != nil
        else { return false }
        return write(item)
    }

    /// Доложить всё, что можно. `attach` — поставить ссылку на открытый
    /// день (его ведёт `DayStore`); другим дням ссылка дописывается в файл.
    /// Возвращает, сколько вложений дошло.
    @discardableResult
    static func settle(_ vault: Vault, open: Date, attach: (String, String) -> Void) -> Int {
        guard let root = vault.root, let dir else { return 0 }
        var done = 0
        for var item in items(root: root) {
            guard let kind = Vault.Folder(rawValue: item.kind), let date = Vault.date(from: item.stamp)
            else { continue }
            if item.link == nil {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(item.id + ".bin")) else {
                    drop(item)
                    continue
                }
                let link = kind == .photos ? vault.addPhoto(data, for: date)
                    : vault.addAttachment(data, to: kind, name: item.name, for: date)
                guard let link else { continue }
                // Файл в архиве — у себя больше не держим; ссылку помним.
                item.link = link
                _ = write(item)
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.id + ".bin"))
            }
            guard let link = item.link else { continue }
            if Vault.stamp(open) == item.stamp {
                attach(link, item.tab)
            } else {
                let entry = FileTrash.Entry(path: "", stored: "", day: item.stamp, tab: item.tab, link: link)
                guard FileTrash.relink(entry, vault) else { continue }
            }
            drop(item)
            done += 1
        }
        return done
    }
}
