import SwiftUI
import UIKit

/// Записи за срок — одной книгой PDF (P296).
///
/// Обложка: чья книга, с какого по какое число, что внутри. Дальше каждый
/// день — с новой страницы: дата и день недели, погода, план (по желанию),
/// «Как прошло?», заголовок и запись; снимки из текста — на своих местах,
/// снимки полоски — в конце дня (по желанию). Точки — значком и названием;
/// голос и видео — пометкой: на бумаге их не проиграть.
///
/// Файл ложится в папку записей, в «PDF», под именем со сроком, и сразу
/// открывается окно «Поделиться». Существующий файл не затирается.
enum PDFBook {

    struct Options {
        var from: Date
        var to: Date
        var plan = true
        var photos = true
    }

    private struct Day {
        let date: Date
        let tasks: [PlanRow]
        let title: String
        let text: String
        let answers: [String: String]
        let strip: [String]
        let weather: String?

        var isEmpty: Bool {
            tasks.isEmpty && title.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && strip.isEmpty
        }
    }

    /// A4 в точках.
    static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let margin: CGFloat = 54
    private static var body: CGRect {
        CGRect(x: margin, y: margin, width: page.width - margin * 2,
               height: page.height - margin * 2 - 18)
    }

    /// Собрать книгу. Пустых дней в ней нет. Нет ни одного дня с записью —
    /// книги нет.
    static func make(_ o: Options, vault: Vault) -> URL? {
        let cal = Calendar.current
        var days: [Day] = []
        var date = cal.startOfDay(for: min(o.from, o.to))
        let end = cal.startOfDay(for: max(o.from, o.to))
        while date <= end {
            let day = read(date, vault: vault)
            if !day.isEmpty { days.append(day) }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        guard !days.isEmpty, let root = vault.root else { return nil }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title(o),
                               kCGPDFContextCreator as String: T("Graphomanus", "Graphomanus")]
        let data = UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { ctx in
            cover(o, days: days, ctx: ctx)
            for day in days {
                layOut(dayText(day, o: o, vault: vault), footer: Ru.longDate(day.date), ctx: ctx)
            }
        }

        let dir = root.appendingPathComponent("PDF")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = T("Graphomanus ", "Graphomanus ") + Vault.stamp(min(o.from, o.to)) + " — " + Vault.stamp(max(o.from, o.to))
        var url = dir.appendingPathComponent(name + ".pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(name + " (\(n)).pdf")
            n += 1
        }
        do { try data.write(to: url, options: .withoutOverwriting) } catch { return nil }
        return url
    }

    private static func title(_ o: Options) -> String {
        T("Graphomanus: ", "Graphomanus: ") + Ru.longDate(min(o.from, o.to)) + " — " + Ru.longDate(max(o.from, o.to))
    }

    private static func read(_ date: Date, vault: Vault) -> Day {
        let (rows, planPhotos) = Plan.splitPhotos(
            Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body))
        let file = DayFile(text: vault.read(.diary, for: date))
        let diary = Diary(body: file.body, known: rows.map(\.text))
        return Day(date: date,
                   tasks: rows.filter(\.isTask),
                   title: file.value("title") ?? "",
                   text: diary.text,
                   answers: diary.answers,
                   strip: diary.photos + planPhotos,
                   weather: file.value("weather"))
    }

    // MARK: - Обложка

    private static func cover(_ o: Options, days: [Day], ctx: UIGraphicsPDFRendererContext) {
        ctx.beginPage()
        let ink = UIColor(white: 0.12, alpha: 1)
        let soft = UIColor(white: 0.42, alpha: 1)
        func centered(_ s: String, _ font: UIFont, _ color: UIColor, y: CGFloat) -> CGFloat {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                        .paragraphStyle: style]
            let box = CGRect(x: margin, y: y, width: page.width - margin * 2, height: 400)
            let used = (s as NSString).boundingRect(with: box.size, options: .usesLineFragmentOrigin,
                                                    attributes: words, context: nil)
            (s as NSString).draw(with: box, options: .usesLineFragmentOrigin, attributes: words, context: nil)
            return y + ceil(used.height)
        }
        let serif = { (size: CGFloat) in UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size) }
        var y: CGFloat = 250
        y = centered(T("Graphomanus", "Graphomanus"), serif(40), ink, y: y) + 14
        y = centered(o.plan ? T("Дневник и план", "Diary and plan") : T("Дневник", "Diary"), serif(20), soft, y: y) + 46
        y = centered(T("с ", "from ") + Ru.longDate(min(o.from, o.to)), serif(22), ink, y: y) + 6
        y = centered(T("по ", "to ") + Ru.longDate(max(o.from, o.to)), serif(22), ink, y: y) + 40
        var photos = 0
        for day in days {
            photos += day.strip.filter { Diary.kind(of: $0) == .photo }.count + photoLines(day.text).count
        }
        var inside = T("Дней с записями: \(days.count)", "Days with entries: \(days.count)")
        if o.photos { inside += T(" · снимков: \(photos)", " · photos: \(photos)") }
        y = centered(inside, .systemFont(ofSize: 13), soft, y: y) + 6
        var what = [T("записи дневника", "diary entries")]
        if o.plan { what.append(T("дела плана", "plan tasks")) }
        if o.photos { what.append(T("фотографии", "photos")) }
        y = centered(T("Внутри: ", "Inside: ") + what.joined(separator: ", "), .systemFont(ofSize: 13), soft, y: y)
        _ = centered(T("Собрано ", "Made on ") + Ru.longDate(Date()), .systemFont(ofSize: 11), soft,
                     y: page.height - margin - 20)
    }

    private static func photoLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap { line in
            Diary.links(in: line).filter { Diary.kind(of: $0) == .photo }
        }
    }

    // MARK: - День

    private static func dayText(_ day: Day, o: Options, vault: Vault) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let serif = { (size: CGFloat) in UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size) }
        let ink = UIColor(white: 0.12, alpha: 1)
        let soft = UIColor(white: 0.45, alpha: 1)
        func add(_ s: String, _ font: UIFont, _ color: UIColor = ink, after: CGFloat = 6) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.lineSpacing = 2
            out.append(NSAttributedString(string: s + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        func image(_ link: String, width: CGFloat) -> NSAttributedString? {
            guard let url = vault.mediaURL(link, for: day.date),
                  let picture = Photo.load(url, side: 1400) else { return nil }
            let scale = min(width / picture.size.width, 360 / picture.size.height)
            let attachment = NSTextAttachment()
            attachment.image = picture
            attachment.bounds = CGRect(x: 0, y: 0, width: picture.size.width * scale,
                                       height: picture.size.height * scale)
            return NSAttributedString(attachment: attachment)
        }

        add(Ru.weekday(day.date).capitalized + ", " + Ru.longDate(day.date),
            serif(20).withWeight(.semibold), after: 4)
        if let weather = day.weather, Prefs.weatherOn {
            add(Prefs.weatherText(weather), .systemFont(ofSize: 11), soft, after: 14)
        } else {
            add("", .systemFont(ofSize: 4), after: 10)
        }

        if o.plan, !day.tasks.isEmpty {
            add(T("ПЛАН", "PLAN"), .systemFont(ofSize: 10, weight: .semibold), soft, after: 4)
            for task in day.tasks {
                let mark = task.done ? "☑" : "☐"
                let time = task.time.map { $0 + "  " } ?? ""
                add(mark + "  " + time + Geo.stripped(task.text), .systemFont(ofSize: 12.5), after: 3)
            }
            add("", .systemFont(ofSize: 6), after: 8)
        }

        let asked = day.answers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if !asked.isEmpty {
            add(T("КАК ПРОШЛО?", "HOW DID IT GO?"), .systemFont(ofSize: 10, weight: .semibold), soft, after: 4)
            for task in day.tasks where asked[task.text] != nil {
                // Снимки в ответе (P407) — картинками под строкой, голос и
                // файлы — словом, точки — без координат.
                let said = asked[task.text] ?? ""
                let shots = Diary.anywhere(in: said).filter { Diary.kind(of: $0.link) == .photo }
                var words = said as NSString
                for piece in shots.reversed() { words = words.replacingCharacters(in: piece.range, with: "") as NSString }
                let line = Geo.stripped(words as String)
                    .replacingOccurrences(of: #"\[([^\]\n]*)\]\((<[^>\n]+>|[^)\s]+)\)"#, with: "[$1]",
                                          options: .regularExpression)
                    .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                add(Geo.stripped(task.text) + ": " + line, serif(12.5), after: 3)
                if o.photos {
                    for piece in shots {
                        if let picture = image(piece.link, width: body.width) {
                            out.append(picture)
                            add("", .systemFont(ofSize: 6), after: 8)
                        }
                    }
                }
            }
            add("", .systemFont(ofSize: 6), after: 8)
        }

        if !day.title.isEmpty { add(Geo.stripped(day.title), serif(16).withWeight(.semibold), after: 8) }

        for line in day.text.components(separatedBy: .newlines) {
            // Одно вложение строкой или ряд снимков (P348) — каждый по
            // очереди.
            let links = Diary.links(in: line)
            if !links.isEmpty {
                for link in links {
                switch Diary.kind(of: link) {
                case .photo:
                    if o.photos, let picture = image(link, width: body.width) {
                        out.append(picture)
                        add("", .systemFont(ofSize: 6), after: 8)
                    } else if o.photos {
                        add(T("[снимок: ", "[photo: ") + link + "]", .systemFont(ofSize: 10), soft)
                    }
                case .video: add(T("[видео]", "[video]"), .systemFont(ofSize: 10), soft)
                case .audio: add(T("[голосовая запись]", "[voice note]"), .systemFont(ofSize: 10), soft)
                case .file:  add(T("[документ: ", "[document: ") + (link as NSString).lastPathComponent + "]",
                                 .systemFont(ofSize: 10), soft)
                }
                }
                continue
            }
            // Точки — значком и названием, без цифр координат.
            var shown = line
            for (range, point) in Geo.points(inText: line).reversed() {
                let label = "⌖ " + (point.title.isEmpty ? Geo.text(point.at) : point.title)
                shown = (shown as NSString).replacingCharacters(in: range, with: label)
            }
            add(shown, serif(12.5), after: 4)
        }

        if o.photos {
            let pictures = day.strip.filter { Diary.kind(of: $0) == .photo }
            if !pictures.isEmpty {
                add("", .systemFont(ofSize: 6), after: 6)
                let side = (body.width - 16) / 3
                for (i, link) in pictures.enumerated() {
                    guard let url = vault.mediaURL(link, for: day.date),
                          let picture = Photo.load(url, side: 600) else { continue }
                    let attachment = NSTextAttachment()
                    attachment.image = PhotoAttachment.square(picture, side: side)
                    attachment.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                    out.append(NSAttributedString(attachment: attachment))
                    out.append(NSAttributedString(string: i % 3 == 2 ? "\n" : "  "))
                }
            }
        }
        return out
    }

    /// Разложить день по страницам: он начинается с новой и занимает столько,
    /// сколько нужно.
    private static func layOut(_ text: NSAttributedString, footer: String,
                               ctx: UIGraphicsPDFRendererContext) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var done = 0
        var sheet = 1
        repeat {
            let container = NSTextContainer(size: body.size)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            ctx.beginPage()
            layout.drawBackground(forGlyphRange: range, at: body.origin)
            layout.drawGlyphs(forGlyphRange: range, at: body.origin)
            let foot = footer + (sheet > 1 ? " · \(sheet)" : "")
            (foot as NSString).draw(at: CGPoint(x: margin, y: page.height - margin + 8),
                                    withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                                     .foregroundColor: UIColor(white: 0.55, alpha: 1)])
            sheet += 1
            if range.length == 0 { break }
            done = NSMaxRange(range)
        } while done < layout.numberOfGlyphs
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        if let bold = fontDescriptor.withSymbolicTraits(.traitBold) { return UIFont(descriptor: bold, size: pointSize) }
        return self
    }
}

extension PhotoAttachment {
    /// Квадрат, обрезанный по середине, — для снимков полоски в PDF.
    static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }
}

/// Окно «PDF»: срок, что включить, — и собрать (P296).
struct PDFSheet: View {
    let vault: Vault
    let archive: Archive

    enum Span: String, CaseIterable, Identifiable {
        case month = "Этот месяц", last = "Прошлый месяц", year = "Этот год", all = "Всё", own = "Свой срок"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: return T("Этот месяц", "This month")
            case .last: return T("Прошлый месяц", "Last month")
            case .year: return T("Этот год", "This year")
            case .all: return T("Всё", "Everything")
            case .own: return T("Свой срок", "Custom")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var span: Span = .month
    @State private var from = Date()
    @State private var to = Date()
    @State private var plan = true
    @State private var photos = true
    @State private var working = false
    @State private var nothing = false
    /// Собранный файл: пока он не пуст, человек видит не кнопку «Собрать»,
    /// а готовый результат — где файл лежит, и «Поделиться» ещё раз, если
    /// системное окно не открылось само (решение P304).
    @State private var result: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section(T("Срок", "Period")) {
                    Picker(T("Срок", "Period"), selection: $span) {
                        ForEach(Span.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .disabled(result != nil)
                    if span == .own {
                        DatePicker(T("С", "From"), selection: $from, displayedComponents: .date)
                        DatePicker(T("По", "To"), selection: $to, displayedComponents: .date)
                    } else {
                        Text(Ru.longDate(range.0) + " — " + Ru.longDate(range.1))
                            .foregroundStyle(Look.inkSoft)
                    }
                }
                Section {
                    Toggle(T("Записи дневника", "Diary entries"), isOn: .constant(true)).disabled(true)
                    Toggle(T("Дела плана", "Plan tasks"), isOn: $plan).disabled(result != nil)
                    Toggle(T("Фотографии", "Photos"), isOn: $photos).disabled(result != nil)
                } header: {
                    Text(T("Что включить", "What to include"))
                } footer: {
                    // Дневник разбавляют серым не просто так — его нельзя
                    // отключить, он входит всегда; это стоит сказать, а не
                    // оставлять непонятным (P304).
                    Text(T("Записи дневника входят в книгу всегда; план и фотографии — по желанию.", "Diary entries are always in the book; the plan and photos are up to you."))
                }
                if let result {
                    Section {
                        Button(T("Поделиться", "Share")) { Share.present([result]) }
                    } footer: {
                        Text(T("Готово: «\(result.lastPathComponent)» лежит в папке записей, в «PDF».", "Done: “\(result.lastPathComponent)” is in your entries folder, in “PDF”."))
                    }
                } else {
                    Section {
                        Button {
                            build()
                        } label: {
                            HStack {
                                Text(working ? T("Собираю…", "Making…") : T("Собрать PDF", "Make PDF"))
                                if working { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(working)
                    } footer: {
                        Text(T("На обложке — срок и что внутри; каждый день с новой страницы. Файл ляжет в папку записей, в «PDF».", "The cover shows the period and what is inside; each day starts a new page. The file goes to your entries folder, in “PDF”."))
                    }
                }
            }
            .navigationTitle("PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? T("Отмена", "Cancel") : T("Готово", "Done")) { dismiss() }
                }
            }
            .alert(T("За этот срок записей нет", "No entries in this period"), isPresented: $nothing) {
                Button(T("Понятно", "OK")) { nothing = false }
            }
        }
    }

    private var range: (Date, Date) {
        let cal = Calendar.current
        let now = DayStore.today()
        switch span {
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (start, now)
        case .last:
            let thisStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let start = cal.date(byAdding: .month, value: -1, to: thisStart) ?? thisStart
            let end = cal.date(byAdding: .day, value: -1, to: thisStart) ?? thisStart
            return (start, end)
        case .year:
            let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return (start, now)
        case .all:
            let first = archive.days.values.map(\.date).min() ?? now
            return (first, now)
        case .own:
            return (from, to)
        }
    }

    private func build() {
        working = true
        let options = PDFBook.Options(from: range.0, to: range.1, plan: plan, photos: photos)
        let vault = vault
        DispatchQueue.global(qos: .userInitiated).async {
            let url = PDFBook.make(options, vault: vault)
            DispatchQueue.main.async {
                working = false
                guard let url else { nothing = true; return }
                Feel.done()
                // Лист не закрываем: закрыть и тут же открыть поверх него
                // системное окно «Поделиться» — гонка, из-за которой оно
                // иногда не появлялось вовсе, а куда лёг файл, было не
                // узнать (P304). Теперь лист остаётся, видно, где файл, и
                // «Поделиться» можно нажать ещё раз.
                result = url
                Share.present([url])
            }
        }
    }
}
