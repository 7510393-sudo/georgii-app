import SwiftUI

/// Корзина дней (P295).
///
/// Убранный день не стирается: его файл переезжает в папку «Trash»
/// внутри папки записей — `Trash/ГГГГ-ММ-ДД/Diary/…` (до P353 — «Корзина»
/// и «Дневник»; их приложение понимает по-прежнему). Убирают вкладку,
/// которая сейчас открыта, — план и дневник по отдельности, не весь день
/// разом (P300). Их видно в «Файлах», их можно вернуть на место из настроек
/// или удалить навсегда. Снимки, голос и документы дня остаются в своих
/// папках: вернули день — ссылки на них снова работают.
enum Trash {


    struct Item: Identifiable {
        let stamp: String
        let date: Date
        let url: URL
        /// Первые слова записи или первое дело — чтобы узнать день.
        let preview: String
        /// Когда день убрали в корзину — от этого считаются 30 дней (P373).
        var deleted: Date?
        var id: String { stamp }

        /// Сколько дней осталось до того, как день сотрётся.
        func daysLeft(now: Date = Date()) -> Int {
            let from = deleted ?? Calendar.current.startOfDay(for: now)
            let gone = Calendar.current.date(byAdding: .day, value: Trash.days, to: from) ?? from
            return max(0, Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: now), to: gone).day ?? 0)
        }
    }

    /// Сколько лежит в корзине, прежде чем стереться (P373) — как файлы.
    static let days = 30
    /// Отметка дня удаления внутри папки дня в корзине.
    private static let markName = ".deleted"

    /// Обе стороны дня — для возврата, показа и удаления навсегда: там
    /// берётся то, что нашлось, какую вкладку тогда ни убирали (P300).
    static let allParts: [Vault.Folder] = [.planner, .diary]

    static func folder(_ vault: Vault) -> URL? {
        vault.root.map { Vault.trash(in: $0) }
    }

    /// Убрать в корзину только эти стороны дня. Уже лежит там такой же
    /// день — новый ляжет рядом под своим номером: ничего не затирается.
    @discardableResult
    static func put(_ date: Date, parts: [Vault.Folder], in vault: Vault) -> Bool {
        guard let base = folder(vault) else { return false }
        let stamp = Vault.stamp(date)
        let fm = FileManager.default
        var day = base.appendingPathComponent(stamp)
        var n = 2
        while fm.fileExists(atPath: day.path) {
            day = base.appendingPathComponent("\(stamp) (\(n))")
            n += 1
        }
        var moved = false
        for part in parts {
            guard let from = vault.file(part, for: date), fm.fileExists(atPath: from.path) else { continue }
            let dir = day.appendingPathComponent(part.rawValue)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if move(from, to: dir.appendingPathComponent(from.lastPathComponent)) { moved = true }
        }
        if moved { mark(day, Date()) }
        return moved
    }

    private static func mark(_ day: URL, _ date: Date) {
        try? Data(Vault.stamp(date).utf8).write(to: day.appendingPathComponent(markName))
    }

    private static func deletedOn(_ day: URL) -> Date? {
        guard let text = try? String(contentsOf: day.appendingPathComponent(markName), encoding: .utf8)
        else { return nil }
        return Vault.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Стереть дни, пролежавшие в корзине 30 дней, — при каждом
    /// возвращении в приложение (P373). Дни, убранные до этого правила,
    /// без отметки, получают её сегодня: их 30 дней начинаются сейчас, а не
    /// задним числом.
    static func purgeOld(_ vault: Vault, now: Date = Date()) {
        let limit = Calendar.current.date(byAdding: .day, value: -days,
                                          to: Calendar.current.startOfDay(for: now)) ?? now
        for item in items(in: vault) {
            guard let when = item.deleted else {
                mark(item.url, now)
                continue
            }
            if when <= limit { purge(item) }
        }
    }

    /// Что лежит в корзине — свежие дни сверху.
    static func items(in vault: Vault) -> [Item] {
        guard let base = folder(vault),
              let names = try? FileManager.default.contentsOfDirectory(atPath: base.path)
        else { return [] }
        return names.compactMap { name -> Item? in
            let stamp = String(name.prefix(10))
            guard let date = Vault.date(from: stamp) else { return nil }
            let url = base.appendingPathComponent(name)
            return Item(stamp: name, date: date, url: url, preview: preview(url, stamp: stamp),
                        deleted: deletedOn(url))
        }
        .sorted { $0.stamp > $1.stamp }
    }

    /// Вернуть день на место. На его месте уже новая запись — не трогаем
    /// ни ту, ни другую и говорим об этом (P182: чужое не затирается).
    static func restore(_ item: Item, in vault: Vault) -> Bool {
        let fm = FileManager.default
        var pairs: [(URL, URL)] = []
        for part in allParts {
            let from = Vault.folder(part, in: item.url)
                .appendingPathComponent(String(item.stamp.prefix(10)) + ".md")
            guard fm.fileExists(atPath: from.path) else { continue }
            guard let to = vault.file(part, for: item.date) else { return false }
            if fm.fileExists(atPath: to.path) { return false }
            pairs.append((from, to))
        }
        for (from, to) in pairs {
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard move(from, to: to) else { return false }
        }
        try? fm.removeItem(at: item.url)
        return true
    }

    /// Удалить навсегда.
    static func purge(_ item: Item) {
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: item.url, options: .forDeleting, error: &trouble) { real in
                try? FileManager.default.removeItem(at: real)
            }
        if FileManager.default.fileExists(atPath: item.url.path) {
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    private static func preview(_ day: URL, stamp: String) -> String {
        for part in [Vault.Folder.diary, .planner] {
            let file = Vault.folder(part, in: day).appendingPathComponent(stamp + ".md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let body = DayFile(text: text).body
            let words = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("![") }
            if let words { return String(words.prefix(80)) }
        }
        return T("Пустой день", "Empty day")
    }

    private static func move(_ from: URL, to: URL) -> Bool {
        var done = false
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: from, options: .forMoving,
                        writingItemAt: to, options: .forReplacing, error: &trouble) { a, b in
                done = (try? FileManager.default.moveItem(at: a, to: b)) != nil
            }
        if !done, FileManager.default.fileExists(atPath: from.path) {
            done = (try? FileManager.default.moveItem(at: from, to: to)) != nil
        }
        return done
    }
}

/// Корзина в настройках: убранные дни — вернуть или удалить навсегда.
struct TrashSheet: View {
    let vault: Vault
    /// Записать открытый день до того, как в его файл вернётся ссылка.
    var save: () -> Void = {}
    let changed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [Trash.Item] = []
    @State private var files: [FileTrash.Entry] = []
    @State private var doomedFile: FileTrash.Entry?
    @State private var doomed: Trash.Item?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                if !files.isEmpty {
                    Section(T("Файлы — сотрутся через 30 дней", "Files — erased after 30 days")) {
                        ForEach(files) { entry in fileRow(entry) }
                    }
                }
                if items.isEmpty && files.isEmpty {
                    Text(T("Корзина пуста. День убирают в корзину из меню страницы — три точки. Всё в корзине хранится 30 дней, потом стирается.",
                           "The trash is empty. A day goes to the trash from the page menu — the three dots. Everything stays in the trash for 30 days, then it is erased."))
                        .font(Look.sans(14))
                        .foregroundStyle(Look.inkSoft)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Ru.weekday(item.date) + ", " + Ru.longDate(item.date))
                            .font(Look.sans(15, weight: .medium))
                        Text(item.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(2)
                        Text(T("сотрётся через \(item.daysLeft()) дн.", "erased in \(item.daysLeft()) days"))
                            .font(Look.sans(12.5))
                            .foregroundStyle(Look.inkSoft)
                        HStack(spacing: 18) {
                            Button(T("Вернуть", "Restore")) {
                                if Trash.restore(item, in: vault) {
                                    Feel.done()
                                    reload()
                                    changed()
                                } else {
                                    note = T("На место этого дня уже есть новая запись. Файл остался в корзине — перенесите нужное руками в «Файлах».",
                                         "There is already a new entry for this day. The file stayed in the trash — move what you need by hand in Files.")
                                }
                            }
                            Button(T("Удалить навсегда", "Delete forever"), role: .destructive) { doomed = item }
                        }
                        .buttonStyle(.borderless)
                        .font(Look.sans(14))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(T("Корзина", "Trash"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(T("Готово", "Done")) { dismiss() } }
            }
            .confirmationDialog(T("Удалить день навсегда?", "Delete the day forever?"), isPresented: Binding(
                get: { doomed != nil }, set: { if !$0 { doomed = nil } }), titleVisibility: .visible) {
                Button(T("Удалить навсегда", "Delete forever"), role: .destructive) {
                    if let doomed { Trash.purge(doomed) }
                    doomed = nil
                    reload()
                }
            } message: {
                Text(T("Файлы плана и дневника этого дня будут стёрты. Снимки и голос дня останутся в своих папках.",
                   "The plan and diary files of this day will be erased. Its photos and voice notes stay in their folders."))
            }
            .alert(T("Не вернулось", "Not restored"), isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
                Button(T("Понятно", "OK")) { note = nil }
            } message: {
                Text(note ?? "")
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        items = Trash.items(in: vault)
        files = FileTrash.items(vault)
    }

    /// Удалённый файл (P371): превью, откуда он и сколько ему осталось;
    /// «Вернуть» — на место и на страницу своего дня.
    private func fileRow(_ entry: FileTrash.Entry) -> some View {
        let url = FileTrash.url(of: entry, vault)
        let kind = Diary.kind(of: entry.path)
        let left = FileTrash.daysLeft(entry)
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if kind == .photo || kind == .video {
                    PhotoThumb(url: url, video: kind == .video)
                } else {
                    FileTile(icon: kind == .audio ? "waveform" : "doc.text",
                             label: (entry.path as NSString).pathExtension.lowercased())
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text((entry.path as NSString).lastPathComponent)
                    .font(Look.sans(14, weight: .medium))
                    .lineLimit(1)
                Text(dayName(entry.day) + " · "
                     + T("сотрётся через \(left) дн.", "erased in \(left) days"))
                    .font(Look.sans(12.5))
                    .foregroundStyle(Look.inkSoft)
                HStack(spacing: 18) {
                    Button(T("Вернуть", "Restore")) { restore(entry) }
                    Button(T("Удалить навсегда", "Delete forever"), role: .destructive) { doomedFile = entry }
                }
                .buttonStyle(.borderless)
                .font(Look.sans(14))
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(T("Удалить файл навсегда?", "Delete the file forever?"),
                            isPresented: Binding(get: { doomedFile == entry },
                                                 set: { if !$0 { doomedFile = nil } }),
                            titleVisibility: .visible) {
            Button(T("Удалить навсегда", "Delete forever"), role: .destructive) {
                FileTrash.purge(entry, vault)
                doomedFile = nil
                reload()
            }
        } message: {
            Text(T("Файл будет стёрт, вернуть его будет нельзя.", "The file will be erased and cannot be restored."))
        }
    }

    private func dayName(_ stamp: String) -> String {
        guard let date = Vault.date(from: stamp) else { return stamp }
        return Ru.longDate(date)
    }

    private func restore(_ entry: FileTrash.Entry) {
        save()
        guard FileTrash.restore(entry, vault) else {
            note = T("На месте этого файла уже лежит другой с тем же именем. Файл остался в корзине.",
                     "Another file with the same name is already in its place. The file stayed in the trash.")
            return
        }
        Feel.done()
        if !FileTrash.relink(entry, vault) {
            note = T("Файл вернулся в папку, но на страницу дня его поставить не вышло — день ещё в iCloud или изменился в другом месте. Добавьте его снова из «Файлов».",
                     "The file is back in its folder, but it could not be put back on the day’s page — the day is still in iCloud or was changed elsewhere. Add it again from Files.")
        }
        reload()
        changed()
    }
}
