import Foundation
import CoreLocation
import SwiftUI
import UIKit

/// Место на своей карте человека.
///
/// Каждое место — обычный файл в папке «Места»: название и координаты в
/// шапке, ниже — что человек о нём написал. Карта целиком складывается из
/// этих файлов и переживёт приложение: файл откроется любым редактором,
/// а координаты — любыми картами (решение P207).
///
///     ---
///     name: Мой дом в Петербурге
///     place: 59.93863, 30.31413
///     icon: home
///     ---
///
///     Жил здесь с 2004 по 2011 год. Во дворе — липа.
struct Place: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var text: String = ""
    /// Значок на карте — словом, как он лежит в шапке файла (P234).
    var mark: String = Glyph.standard
    /// Имя файла, если место уже лежит в папке.
    var file: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, text: String = "", file: String? = nil) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.text = text
        self.file = file
    }

    /// Разобрать файл места. Без координат это не место — `nil`.
    init?(text: String, file: String) {
        let parsed = DayFile(text: text)
        guard let where_ = parsed.value("place").flatMap(Geo.parse) else { return nil }
        let fallback = (file as NSString).deletingPathExtension
        self.init(name: parsed.value("name") ?? fallback, coordinate: where_,
                  text: parsed.body, file: file)
        mark = parsed.value("icon").flatMap(Glyph.fromFile) ?? Glyph.standard
    }

    /// Файл места таким, каким он ляжет в папку.
    var fileText: String {
        var out = DayFile(body: text.trimmingCharacters(in: .whitespacesAndNewlines))
        out.set("name", name)
        out.set("place", Geo.text(coordinate))
        out.set("icon", Glyph.fileWord(mark))
        return out.text
    }

    /// Имя файла по названию: без знаков, которые не любят файловые
    /// системы. Название в шапке остаётся каким его написали.
    static func fileName(for name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let clean = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? T("Место", "Place") : clean) + ".md"
    }
}

/// Значок места на карте — один на всех: стрелка (P609; прежде
/// четырнадцать на выбор — P234–P409). В файле значок лежит словом; что
/// человек выбрал раньше, остаётся в файле нетронутым (P340), но рисуется
/// той же стрелкой.
enum Glyph {
    static let standard = "стрелка"

    /// Значок в файле — английским словом (P353): «личное» ложится как
    /// `private`. В коде — по-прежнему русским.
    private static let english: [String: String] = [
        "точка": "point", "дом": "home", "сердце": "heart", "флаг": "flag",
        "звезда": "star", "кафе": "cafe", "природа": "nature", "снимок": "photo",
        "здоровье": "health", "человек": "person", "вокзал": "station",
        "покупки": "shopping", "хорошее место": "good place",
        "плохое место": "bad place", "пираты": "pirates", "личное": "private",
        "опасность": "danger", "вдохновение": "inspiration", "призраки": "ghosts",
        "везение": "luck", "огонь": "fire", "кружок": "ring", "указатель": "pointer", "ночлег": "lodging", "стрелка": "arrow",
        "невидимый": "invisible",
    ]
    private static let russian: [String: String] =
        Dictionary(uniqueKeysWithValues: english.map { ($0.value, $0.key) })

    static func fileWord(_ name: String) -> String { english[name] ?? name }

    /// Слово из файла — английское или прежнее русское; незнакомое
    /// остаётся как есть: файл человека не правим (P340).
    static func fromFile(_ word: String) -> String? { russian[word] ?? word }
}

/// Координаты словами — так, как они лежат в файлах.
enum Geo {
    /// Для шапки файла: «59.93863, 30.31413».
    static func text(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    /// Для текста записи: «geo:59.93863,30.31413» — так пишут координаты
    /// ссылкой, и её понимают Карты (решение P165).
    static func line(_ c: CLLocationCoordinate2D) -> String {
        String(format: "geo:%.5f,%.5f", c.latitude, c.longitude)
    }

    /// Обратно: принимает и «59.9, 30.3», и «geo:59.9,30.3».
    static func parse(_ s: String) -> CLLocationCoordinate2D? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("geo:") { t.removeFirst(4) }
        let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Точка, записанная в текст дня: название и координаты (P213).
///
/// В файле — ссылкой, которую понимают редакторы разметки и Карты:
/// `[Дом в Петербурге](geo:59.93863,30.31413)`; без названия — просто
/// `geo:59.93863,30.31413`. На странице — кнопочка бледным цветом, как у
/// отметки времени; касание открывает карту на этой точке.
struct GeoPoint {
    var title: String
    var at: CLLocationCoordinate2D

    /// Надпись на кнопочке: название, затем координаты.
    var label: String { title.isEmpty ? Geo.text(at) : title + " · " + Geo.text(at) }
}

extension GeoPoint: Equatable {
    static func == (a: GeoPoint, b: GeoPoint) -> Bool {
        a.title == b.title && a.at.latitude == b.at.latitude && a.at.longitude == b.at.longitude
    }
}

extension Geo {

    private static let titled = try! NSRegularExpression(
        pattern: #"^\[([^\]]*)\]\((geo:[^)]+)\)$"#)

    /// Точка, если строка — только она: `geo:…` или `[название](geo:…)`.
    static func point(in line: String) -> GeoPoint? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("geo:") {
            return parse(t).map { GeoPoint(title: "", at: $0) }
        }
        let ns = t as NSString
        guard t.hasPrefix("["),
              let m = titled.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              let at = parse(ns.substring(with: m.range(at: 2)))
        else { return nil }
        let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return GeoPoint(title: title, at: at)
    }

    /// Точки посреди текста: `geo:…` и `[название](geo:…)` где угодно в
    /// строке, а не только строкой целиком (P256).
    private static let inline = try! NSRegularExpression(
        pattern: #"\[([^\]\n]*)\]\((geo:-?\d{1,3}(?:\.\d+)?,\s?-?\d{1,3}(?:\.\d+)?)\)|geo:-?\d{1,3}(?:\.\d+)?,\s?-?\d{1,3}(?:\.\d+)?"#)

    static func points(inText s: String) -> [(range: NSRange, point: GeoPoint)] {
        let ns = s as NSString
        return inline.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            if m.range(at: 2).location != NSNotFound {
                guard let at = parse(ns.substring(with: m.range(at: 2))) else { return nil }
                let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                return (m.range, GeoPoint(title: title, at: at))
            }
            guard let at = parse(ns.substring(with: m.range)) else { return nil }
            return (m.range, GeoPoint(title: "", at: at))
        }
    }

    /// Текст без точек — там, где кнопочку не нарисуешь: в подписи
    /// «Как прошло?» название дела без координат (P259).
    static func stripped(_ s: String) -> String {
        var out = s as NSString
        for (range, _) in points(inText: s).reversed() {
            out = out.replacingCharacters(in: range, with: "") as NSString
        }
        return (out as String)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Строка точки для файла.
    static func pointLine(_ p: GeoPoint) -> String {
        let title = p.title
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? line(p.at) : "[\(title)](\(line(p.at)))"
    }
}

/// Все места человека — чтение и запись папки «Места».
enum Places {

    static func folder(_ vault: Vault) -> URL? {
        vault.folder(.places)
    }

    static func all(in vault: Vault) -> [Place] {
        guard let folder = folder(vault) else { known = []; return [] }
        let list = read(folder)
        known = list
        return list
    }

    private static func read(_ folder: URL) -> [Place] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".md") }.sorted().compactMap { name -> Place? in
            let reading = Vault.reading(at: folder.appendingPathComponent(name))
            guard case .text(let text) = reading else { return nil }
            return Place(text: text, file: name)
        }
    }

    /// Прочитать места в стороне от экрана (P565) — при запуске.
    static func loadSoon(_ vault: Vault) {
        guard let folder = folder(vault) else { return }
        DispatchQueue.global(qos: .utility).async {
            let list = read(folder)
            DispatchQueue.main.async { known = list }
        }
    }

    /// Места, прочитанные в последний раз (P559): по ним подписывается
    /// точка в дневнике без названия. Подпись не хранится в записи — она
    /// считается заново при каждом показе: место переименовали — подпись
    /// новая, удалили — подписи нет.
    static var known: [Place] = []

    /// Подпись точки без названия (P559): «120 м до «Дом»» — до ближайшего
    /// своего места не дальше километра. Дальше — `nil`.
    static func caption(for at: CLLocationCoordinate2D) -> String? {
        let here = CLLocation(latitude: at.latitude, longitude: at.longitude)
        let near = known.map { place -> (Place, Double) in
            (place, here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)))
        }.min { $0.1 < $1.1 }
        guard let (place, meters) = near, meters <= 1000 else { return nil }
        let step: Double = meters < 100 ? 10 : 50
        let shown = String(Int(max(step, (meters / step).rounded() * step)))
        let name = place.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return T("\(shown) м до «\(name)»", "\(shown) m from “\(name)”")
    }

    /// Записать место. Файл с таким названием уже есть и он не этого
    /// места — к имени прибавляется номер: чужое не затирается никогда.
    /// Переименованное место переезжает в новый файл, старый убирается.
    @discardableResult
    static func save(_ place: Place, in vault: Vault) -> Place? {
        guard let folder = folder(vault) else { return nil }
        var stored = place
        var name = Place.fileName(for: place.name)
        if name != place.file {
            var n = 2
            let base = (name as NSString).deletingPathExtension
            while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                name = "\(base) \(n).md"
                n += 1
            }
        }
        guard Vault.write(place.fileText, to: folder.appendingPathComponent(name)) == nil
        else { return nil }
        if let old = place.file, old != name {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
        }
        stored.file = name
        known.removeAll { $0.file == place.file || $0.file == name }
        known.append(stored)
        return stored
    }

    static func delete(_ place: Place, in vault: Vault) {
        guard let folder = folder(vault), let file = place.file else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        known.removeAll { $0.file == file }
    }
}

/// Где человек сейчас. Спрашивает телефон один раз на каждую просьбу.
///
/// Разрешение просится только тогда, когда человек сам нажал на геоточку:
/// место без его жеста приложение не узнаёт никогда (A9).
final class Locator: NSObject, CLLocationManagerDelegate {

    static let shared = Locator()

    private let manager = CLLocationManager()
    private var waiting: [(CLLocation?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current(_ done: @escaping (CLLocation?) -> Void) {
        waiting.append(done)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard !waiting.isEmpty else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        let all = waiting
        waiting = []
        all.forEach { $0(location) }
    }
}

/// Значок места для списков — тот же рисунок, что на карте (P404).
struct GlyphIcon: View {
    var size: CGFloat = 13

    var body: some View {
        Image(uiImage: GlyphArt.image)
            .resizable()
            .scaledToFit()
            .frame(width: size * 2, height: size * 2)
    }
}

/// Рисунок значка места: стрелка вниз, белая с тёмным контуром (P409,
/// единственная — P609).
enum GlyphArt {

    /// Значок на прозрачном поле 26 × 26.
    static let image: UIImage = {
        let side = PlaceLabelSize.dot + 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            draw(in: CGRect(x: 1, y: 1, width: PlaceLabelSize.dot, height: PlaceLabelSize.dot))
        }
    }()

    static func draw(in circle: CGRect) {
        arrow(in: circle.insetBy(dx: 2, dy: 1))
    }

    /// Своя стрелка, на десятую уже системной и с острыми углами.
    private static func arrow(in r: CGRect) {
        let mid = r.midX
        let shaft = r.width * 0.15, head = r.width * 0.36
        let top = r.minY + 1, waist = r.minY + r.height * 0.48, tip = r.maxY - 0.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: mid - shaft, y: top))
        p.addLine(to: CGPoint(x: mid + shaft, y: top))
        p.addLine(to: CGPoint(x: mid + shaft, y: waist))
        p.addLine(to: CGPoint(x: mid + head, y: waist))
        p.addLine(to: CGPoint(x: mid, y: tip))
        p.addLine(to: CGPoint(x: mid - head, y: waist))
        p.addLine(to: CGPoint(x: mid - shaft, y: waist))
        p.close()
        p.lineJoinStyle = .miter
        p.miterLimit = 6
        p.lineWidth = 2.4
        UIColor(white: 0.1, alpha: 0.9).setStroke()
        p.stroke()
        UIColor.white.setFill()
        p.fill()
    }
}

/// Размер кружка значка — общий для карты и списков.
enum PlaceLabelSize {
    static let dot: CGFloat = 24
}

extension Diary {

    private static let objectToken = try! NSRegularExpression(
        pattern: #"(!\[[^\]]*\]\((?:<[^>]*>|[^)\s]+)\))|(\[[^\]]*\]\((?:<[^>]*>|[^)\s]+)\))|(geo:-?\d+(?:\.\d+)?,\s?-?\d+(?:\.\d+)?)"#)

    /// Ряд вложений в одной строке (P560): снимки, видео, голос, файлы и
    /// точки вперемешку через пробел — `![](a.jpg) [голос](b.m4a) [Дом](geo:…)`.
    /// Пусто — в строке есть что-то, кроме них. `point` — у точки,
    /// `link` — путь к файлу у остальных.
    static func objects(in line: String) -> [(range: NSRange, link: String, point: GeoPoint?)] {
        guard line.contains("](") || line.contains("geo:") else { return [] }
        let ns = line as NSString
        var found: [(range: NSRange, link: String, point: GeoPoint?)] = []
        for m in objectToken.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: m.range)
            if m.range(at: 3).location != NSNotFound || token.contains("](geo:") {
                guard let point = Geo.point(in: token) else { return [] }
                found.append((range: m.range, link: token, point: point))
                continue
            }
            guard let open = token.range(of: "](") else { return [] }
            var link = String(token[open.upperBound...].dropLast())
            if link.hasPrefix("<"), link.hasSuffix(">") { link = String(link.dropFirst().dropLast()) }
            guard !link.contains("://"), !link.isEmpty else { return [] }
            found.append((range: m.range, link: link, point: nil))
        }
        guard !found.isEmpty else { return [] }
        let rest = NSMutableString(string: line)
        for piece in found.reversed() { rest.replaceCharacters(in: piece.range, with: "") }
        guard (rest as String).trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return found
    }

    /// Вложения, стоящие столбиком по одному в строке (так их клала прежняя
    /// лента, P615), — рядами по четыре, как кладутся новые. Только на
    /// экране: в файл ряды попадают вместе с первой правкой человека (P617).
    static func rows(_ text: String) -> String {
        guard text.contains("](") || text.contains("geo:") else { return text }
        var out: [String] = []
        var run: [String] = []
        func flush() {
            guard run.count > 1 else { out += run; run = []; return }
            var row: [String] = []
            for piece in run {
                row.append(piece)
                if row.count == 4 { out.append(row.joined(separator: " ")); row = [] }
            }
            if !row.isEmpty { out.append(row.joined(separator: " ")) }
            run = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if objects(in: trimmed).count == 1 { run.append(trimmed); continue }
            flush()
            out.append(line)
        }
        flush()
        return out.joined(separator: "\n")
    }
}
