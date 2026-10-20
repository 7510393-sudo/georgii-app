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

/// Значки мест на карте. В файле — словом («дом»), на экране — рисунком
/// (P234), каждый своего цвета (P397).
enum Glyph {
    static let standard = "точка"

    /// По порядку — так они стоят в панели выбора. Восемь, список автора
    /// после 83-й (P397; прежде двенадцать — P335, P336, P338). `emoji` —
    /// «значок» на деле не имя системного рисунка, а символ юникода: флага
    /// с черепом в системном наборе нет, есть эмодзи «🏴‍☠️» (P336).
    static let all: [(name: String, symbol: String, emoji: Bool)] = [
        // Два ряда по семь (P404). Сверху — классические чёрно-белые,
        // снизу — придуманные автором цветные; в каждом ряду — от самых
        // частых к редким (P409).
        ("точка", "circle.fill", false),
        ("дом", "house.fill", false),
        ("кафе", "cup.and.saucer.fill", false),
        ("человек", "person.fill", false),
        ("ночлег", "bed.double.fill", false),
        ("кружок", "circle", false),
        ("невидимый", "rectangle.dashed", false),
        ("сердце", "heart.fill", false),
        ("природа", "tree.fill", false),
        ("звезда", "star.fill", false),
        ("вдохновение", "lightbulb.fill", false),
        ("огонь", "flame.fill", false),
        ("стрелка", "arrowshape.down.fill", false),
        ("пираты", "flag.fill", false),
    ]

    /// Значки без серой подложки (P398, P399, P404): рисунок с контуром
    /// прямо на карте. Стрелка, огонь и флаг нарисованы свои (P409).
    /// Сердце, ёлка, звезда и лампочка — тоже без подложки и кружка (P428).
    static let bare: Set<String> = ["стрелка", "огонь", "пираты",
                                    "сердце", "природа", "звезда", "вдохновение"]

    /// Звезда и лампочка — свой размер, на 10% меньше прежнего (P439).
    static let larger: Set<String> = ["звезда", "вдохновение"]

    /// «Невидимый» (P409): на карте нет значка — только плашка с названием,
    /// а без названия — со словом «Место».
    static let invisible = "невидимый"

    /// Свой цвет значка (P397, P399, P404): красные сердце и огонь, жёлтые
    /// звезда и лампочка, зелёная ёлка (её рисуем сами — `GlyphArt`).
    /// Остальные — белые с тёмным контуром.
    static let tint: [String: UIColor] = [
        "точка": .white,
        "сердце": UIColor(red: 0.93, green: 0.12, blue: 0.14, alpha: 1),
        "огонь": UIColor(red: 0.95, green: 0.1, blue: 0.08, alpha: 1),
        // Жёлтые — ярче (P428).
        "звезда": UIColor(red: 1.0, green: 0.90, blue: 0.08, alpha: 1),
        "вдохновение": UIColor(red: 1.0, green: 0.93, blue: 0.12, alpha: 1),
    ]

    /// «Пустой кружок»: отметка без заливки — одно белое кольцо, карта под
    /// ним видна насквозь (P397).
    static let hollow = "кружок"

    static func color(_ name: String) -> UIColor { tint[name] ?? .white }

    /// Обводка вокруг значка — контрастная к нему: у чёрного светлая, у
    /// прочих тёмная.
    static func halo(_ name: String) -> UIColor {
        name == "пираты" ? UIColor(white: 1, alpha: 0.95) : UIColor(white: 0.1, alpha: 0.9)
    }

    /// Прежние значки (P234, P335–P338): в панели выбора их больше нет, но
    /// места, которые ими уже отмечены, рисуются по-прежнему и при
    /// сохранении значок в файле не теряют (P340).
    private static let former: [String: String] = [
        "снимок": "camera.fill", "флаг": "flag.fill",
        // Рука с пальцем (P404) уступила место «невидимому» (P409).
        "указатель": "hand.point.down.fill",
        "здоровье": "cross.case.fill", "вокзал": "tram.fill", "покупки": "bag.fill",
        "хорошее место": "hand.thumbsup.fill", "плохое место": "hand.thumbsdown.fill",
        "личное": "lock.fill", "опасность": "exclamationmark.triangle.fill",
        // Призраков в системном наборе нет, как и пиратского черепа (P336).
        "призраки": "👻", "везение": "sparkles",
    ]

    static let symbol: [String: String] = former.merging(all.map { ($0.name, $0.symbol) },
                                                         uniquingKeysWith: { _, new in new })
    private static let emojiNames: Set<String> = Set(all.filter(\.emoji).map(\.name)).union(["призраки"])

    /// Значок в файле — английским словом (P353): «личное» ложится как
    /// `private`. На экране и в коде — по-прежнему русским.
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

    /// Название значка на экране — на языке приложения (P355).
    static func shown(_ name: String) -> String { Lang.isRussian ? name : fileWord(name) }

    /// Слово из файла — английское или прежнее русское. Незнакомое — `nil`.
    static func fromFile(_ word: String) -> String? {
        let name = russian[word] ?? word
        return symbol[name] == nil ? nil : name
    }

    static func image(_ name: String) -> String { symbol[name] ?? "circle.fill" }
    /// Значок для `name` — не системный рисунок, а буквенный символ:
    /// рисовать нужно текстом, не `Image(systemName:)`.
    static func isEmoji(_ name: String) -> Bool { emojiNames.contains(name) }
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
        guard let folder = folder(vault),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { known = []; return [] }
        let list = names.filter { $0.hasSuffix(".md") }.sorted().compactMap { name -> Place? in
            let reading = Vault.reading(at: folder.appendingPathComponent(name))
            guard case .text(let text) = reading else { return nil }
            return Place(text: text, file: name)
        }
        known = list
        return list
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

/// Значок места для списков и панели выбора — тот же рисунок, что на
/// карте (P404): `GlyphArt`, а не своё подобие.
struct GlyphIcon: View {
    let name: String
    var size: CGFloat = 13

    var body: some View {
        Image(uiImage: GlyphArt.image(name))
            .resizable()
            .scaledToFit()
            .frame(width: size * 2, height: size * 2)
    }
}

/// Рисунок значка места (P404) — один для карты, списков и панели выбора.
/// Обычный значок — на полупрозрачной серой подложке с белым кольцом;
/// «голые» — без подложки, с контуром; пустой кружок — белое кольцо с
/// тёмной каймой снаружи и внутри; ёлка нарисована своя (системное
/// «дерево» похоже на взрыв); у пиратского флага — чёрный флагшток.
enum GlyphArt {

    static let cache = NSCache<NSString, UIImage>()

    /// Значок на прозрачном поле 26 × 26.
    static func image(_ mark: String) -> UIImage {
        if let ready = cache.object(forKey: mark as NSString) { return ready }
        let side = PlaceLabelSize.dot + 2
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            draw(mark, in: CGRect(x: 1, y: 1, width: PlaceLabelSize.dot, height: PlaceLabelSize.dot),
                 ctx: ctx.cgContext)
        }
        cache.setObject(out, forKey: mark as NSString)
        return out
    }

    static func draw(_ mark: String, in circle: CGRect, ctx: CGContext) {
        if mark == Glyph.hollow { return ring(circle) }
        let bare = Glyph.bare.contains(mark)
        if !bare {
            // Подложка полупрозрачная: карта под отметкой видна (P361, P372).
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                          color: UIColor.black.withAlphaComponent(0.15).cgColor)
            UIColor(Look.inkSoft).withAlphaComponent(0.48).setFill()
            UIBezierPath(ovalIn: circle).fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        if Glyph.isEmoji(mark) { return emoji(mark, in: circle, bare: bare, ctx: ctx) }
        // Свои рисунки (P409): ни чужих значков, ни эмодзи — только то,
        // что нарисовано здесь.
        switch mark {
        // На 5% меньше прежнего (P431).
        case "природа": return tree(in: circle.insetBy(dx: 3.45, dy: 1.75))
        case "сердце": return heart(in: circle.insetBy(dx: 1.2, dy: 1.75))
        case "стрелка": return arrow(in: circle.insetBy(dx: 2, dy: 1))
        case "огонь": return fire(in: circle.insetBy(dx: 3, dy: 1))
        case "пираты": return pirates(in: circle)
        default: break
        }
        // «Невидимый» — та же точка, что первая, перечёркнутая косой чертой,
        // как номер сделанного дела (P418).
        let invisible = mark == Glyph.invisible
        guard let shape = UIImage(systemName: Glyph.image(invisible ? Glyph.standard : mark),
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: bare ? (Glyph.larger.contains(mark) ? 16 : 17) : 11,
                                                                                 weight: .semibold))
        else { return }
        let g = shape.size
        let at = CGRect(x: circle.midX - g.width / 2, y: circle.midY - g.height / 2,
                        width: g.width, height: g.height)
        // Контур (P372): тот же знак тёмным, сдвинутый во все стороны, —
        // сверху цветной.
        let outline = shape.withTintColor(Glyph.halo(mark), renderingMode: .alwaysOriginal)
        let step: CGFloat = bare ? 1.1 : 0.8
        for dx in [-step, 0, step] {
            for dy in [-step, 0, step] where dx != 0 || dy != 0 {
                outline.draw(in: at.offsetBy(dx: dx, dy: dy))
            }
        }
        shape.withTintColor(Glyph.color(mark), renderingMode: .alwaysOriginal).draw(in: at)
        if invisible {
            let strike = UIBezierPath()
            // Черта идёт из угла в угол квадрата, в который вписан кружок, —
            // выходит за его края, а не кончается внутри (P508).
            strike.move(to: CGPoint(x: circle.minX + 1.8, y: circle.maxY - 1.8))
            strike.addLine(to: CGPoint(x: circle.maxX - 1.8, y: circle.minY + 1.8))
            strike.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.9).setStroke()
            strike.lineWidth = 3.6
            strike.stroke()
            UIColor(Look.ink).setStroke()
            strike.lineWidth = 1.8
            strike.stroke()
        }
    }

    /// Пустой кружок: белое кольцо, тёмная кайма снаружи и внутри; внутри
    /// карта видна насквозь.
    private static func ring(_ circle: CGRect) {
        let white = UIBezierPath(ovalIn: circle.insetBy(dx: 2.2, dy: 2.2))
        white.lineWidth = 2.8
        UIColor.white.setStroke()
        white.stroke()
        UIColor(white: 0.1, alpha: 0.85).setStroke()
        let outer = UIBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 0.9
        outer.stroke()
        let inner = UIBezierPath(ovalIn: circle.insetBy(dx: 3.9, dy: 3.9))
        inner.lineWidth = 0.9
        inner.stroke()
    }

    /// Ёлка: три яруса и ствол, зелёная с тёмным контуром. Ярусы видны
    /// каждый: нижний рисуется первым, верхний ложится на него, и низ у
    /// каждого вогнут — ёлка, а не пирамида (P409). Основание на десятую
    /// уже прежнего.
    private static func tree(in r: CGRect) {
        let mid = r.midX
        // Ветки резкие (P428): острые концы ярусов, низ — зубцами, а не
        // дугой.
        func tier(_ top: CGFloat, _ base: CGFloat, _ half: CGFloat) -> UIBezierPath {
            let p = UIBezierPath()
            let y = r.minY + r.height * base
            let notch = r.minY + r.height * (base - 0.07)
            p.move(to: CGPoint(x: mid, y: r.minY + r.height * top))
            p.addLine(to: CGPoint(x: mid + r.width * half, y: y))
            p.addLine(to: CGPoint(x: mid + r.width * half * 0.5, y: notch))
            p.addLine(to: CGPoint(x: mid + r.width * half * 0.2, y: y - 0.5))
            p.addLine(to: CGPoint(x: mid, y: notch))
            p.addLine(to: CGPoint(x: mid - r.width * half * 0.2, y: y - 0.5))
            p.addLine(to: CGPoint(x: mid - r.width * half * 0.5, y: notch))
            p.addLine(to: CGPoint(x: mid - r.width * half, y: y))
            p.close()
            p.lineWidth = 1.3
            p.lineJoinStyle = .miter
            p.miterLimit = 8
            return p
        }
        let trunk = UIBezierPath(rect: CGRect(x: mid - 1.3, y: r.minY + r.height * 0.8,
                                              width: 2.6, height: r.height * 0.2))
        trunk.lineWidth = 1.5
        UIColor(white: 0.08, alpha: 0.9).setStroke()
        trunk.stroke()
        UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1).setFill()
        trunk.fill()
        let greens = [UIColor(red: 0.10, green: 0.55, blue: 0.20, alpha: 1),
                      UIColor(red: 0.13, green: 0.63, blue: 0.24, alpha: 1),
                      UIColor(red: 0.18, green: 0.72, blue: 0.29, alpha: 1)]
        let tiers = [tier(0.44, 0.88, 0.405), tier(0.21, 0.66, 0.31), tier(0, 0.42, 0.21)]
        for (p, green) in zip(tiers, greens) {
            UIColor(white: 0.08, alpha: 0.9).setStroke()
            p.stroke()
            green.setFill()
            p.fill()
        }
    }

    /// Сердце (P428, P431): плавное, как рисуют рукой, — два круглых
    /// «плеча», мягкая выемка сверху, бока сходятся к острию дугами, без
    /// прямых углов. Красное с тёмной каймой и бликом, без подложки.
    private static func heart(in r: CGRect) {
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
        let p = UIBezierPath()
        p.move(to: pt(0.5, 0.92))
        p.addCurve(to: pt(0.04, 0.38), controlPoint1: pt(0.36, 0.80), controlPoint2: pt(0.04, 0.62))
        p.addCurve(to: pt(0.28, 0.10), controlPoint1: pt(0.04, 0.22), controlPoint2: pt(0.14, 0.10))
        p.addCurve(to: pt(0.5, 0.24), controlPoint1: pt(0.39, 0.10), controlPoint2: pt(0.46, 0.16))
        p.addCurve(to: pt(0.72, 0.10), controlPoint1: pt(0.54, 0.16), controlPoint2: pt(0.61, 0.10))
        p.addCurve(to: pt(0.96, 0.38), controlPoint1: pt(0.86, 0.10), controlPoint2: pt(0.96, 0.22))
        p.addCurve(to: pt(0.5, 0.92), controlPoint1: pt(0.96, 0.62), controlPoint2: pt(0.64, 0.80))
        p.close()
        p.lineJoinStyle = .round
        p.lineWidth = 1.4
        UIColor(white: 0.1, alpha: 0.9).setStroke()
        p.stroke()
        Glyph.color("сердце").setFill()
        p.fill()
        // Блик на левом «плече».
        let shine = UIBezierPath(ovalIn: CGRect(x: r.minX + w * 0.17, y: r.minY + h * 0.19,
                                                width: w * 0.16, height: h * 0.11))
        UIColor.white.withAlphaComponent(0.5).setFill()
        shine.fill()
    }

    /// Стрелка вниз (P409): своя, на десятую уже системной и с острыми
    /// углами. Белая с тёмным контуром.
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

    /// Огонь (P409): свой — три языка один в другом, красный, оранжевый,
    /// жёлтый, с тонкой тёмной каймой, чтобы читался на карте.
    private static func fire(in r: CGRect) {
        func flame(_ k: CGFloat) -> UIBezierPath {
            // Точки — доли рамки; меньшие языки — тот же рисунок, сжатый к
            // середине низа.
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.midX + (r.minX + r.width * x - r.midX) * k,
                        y: r.maxY + (r.minY + r.height * y - r.maxY) * k)
            }
            let p = UIBezierPath()
            p.move(to: pt(0.50, 1.00))
            p.addCurve(to: pt(0.08, 0.58), controlPoint1: pt(0.20, 1.00), controlPoint2: pt(0.04, 0.80))
            p.addCurve(to: pt(0.24, 0.22), controlPoint1: pt(0.11, 0.42), controlPoint2: pt(0.20, 0.34))
            p.addCurve(to: pt(0.40, 0.44), controlPoint1: pt(0.30, 0.34), controlPoint2: pt(0.33, 0.42))
            p.addCurve(to: pt(0.62, 0.00), controlPoint1: pt(0.38, 0.24), controlPoint2: pt(0.48, 0.08))
            p.addCurve(to: pt(0.94, 0.62), controlPoint1: pt(0.62, 0.18), controlPoint2: pt(0.94, 0.34))
            p.addCurve(to: pt(0.50, 1.00), controlPoint1: pt(0.94, 0.86), controlPoint2: pt(0.76, 1.00))
            p.close()
            return p
        }
        let outer = flame(1)
        outer.lineWidth = 1.3
        outer.lineJoinStyle = .round
        UIColor(red: 0.42, green: 0.05, blue: 0.02, alpha: 0.85).setStroke()
        outer.stroke()
        UIColor(red: 0.93, green: 0.22, blue: 0.08, alpha: 1).setFill()
        outer.fill()
        UIColor(red: 1.0, green: 0.55, blue: 0.08, alpha: 1).setFill()
        flame(0.72).fill()
        UIColor(red: 1.0, green: 0.86, blue: 0.30, alpha: 1).setFill()
        flame(0.42).fill()
    }

    /// Пиратский флаг (P409): свой, а не эмодзи. Чёрное полотнище с белым
    /// черепом и костями; древко идёт ровно по краю полотнища и ниже —
    /// до самой точки места, ничего не торчит.
    private static func pirates(in r: CGRect) {
        let pole = r.minX + r.width * 0.2
        let right = r.maxX - 0.8
        let top = r.minY + r.height * 0.08, bottom = r.minY + r.height * 0.58
        let w = right - pole
        let cloth = UIBezierPath()
        cloth.move(to: CGPoint(x: pole, y: top))
        cloth.addCurve(to: CGPoint(x: right, y: top + 1),
                       controlPoint1: CGPoint(x: pole + w * 0.3, y: top - 2),
                       controlPoint2: CGPoint(x: pole + w * 0.6, y: top + 3))
        cloth.addLine(to: CGPoint(x: right, y: bottom + 1))
        cloth.addCurve(to: CGPoint(x: pole, y: bottom),
                       controlPoint1: CGPoint(x: pole + w * 0.6, y: bottom + 3),
                       controlPoint2: CGPoint(x: pole + w * 0.3, y: bottom - 2))
        cloth.close()
        cloth.lineWidth = 1.6
        cloth.lineJoinStyle = .round
        UIColor.white.withAlphaComponent(0.9).setStroke()
        cloth.stroke()
        UIColor(white: 0.06, alpha: 1).setFill()
        cloth.fill()
        // Череп и кости.
        let cx = pole + w * 0.52, cy = top + (bottom - top) * 0.36
        UIColor.white.setStroke()
        for (a, b) in [(CGPoint(x: cx - 3.4, y: cy + 2.4), CGPoint(x: cx + 3.4, y: cy + 5.2)),
                       (CGPoint(x: cx - 3.4, y: cy + 5.2), CGPoint(x: cx + 3.4, y: cy + 2.4))] {
            let bone = UIBezierPath()
            bone.move(to: a)
            bone.addLine(to: b)
            bone.lineWidth = 1.1
            bone.lineCapStyle = .round
            bone.stroke()
        }
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: cx - 2.3, y: cy - 2.6, width: 4.6, height: 4.4)).fill()
        UIBezierPath(rect: CGRect(x: cx - 1.3, y: cy + 1.2, width: 2.6, height: 1.3)).fill()
        UIColor(white: 0.06, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: cx - 1.5, y: cy - 1.1, width: 1.2, height: 1.2)).fill()
        UIBezierPath(ovalIn: CGRect(x: cx + 0.3, y: cy - 1.1, width: 1.2, height: 1.2)).fill()
        // Древко — поверх края полотнища, от верха до точки места.
        let staff = UIBezierPath()
        staff.move(to: CGPoint(x: pole, y: r.minY + 1.2))
        staff.addLine(to: CGPoint(x: pole, y: r.maxY))
        staff.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.9).setStroke()
        staff.lineWidth = 3.4
        staff.stroke()
        UIColor(white: 0.06, alpha: 1).setStroke()
        staff.lineWidth = 1.7
        staff.stroke()
    }


    /// Эмодзи-значок. Пиратский флаг — с чёрным флагштоком до самой
    /// точки места.
    private static func emoji(_ mark: String, in circle: CGRect, bare: Bool, ctx: CGContext) {
        let sign = Glyph.image(mark) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: bare ? 17 : 13)]
        let size = sign.size(withAttributes: attrs)
        let spot = CGPoint(x: circle.midX - size.width / 2 + (bare ? 2 : 0),
                           y: circle.midY - size.height / 2 - (bare ? 2 : 0))
        if mark == "пираты" {
            let x = spot.x + size.width * 0.16
            let pole = UIBezierPath()
            pole.move(to: CGPoint(x: x, y: spot.y + size.height * 0.12))
            pole.addLine(to: CGPoint(x: x, y: circle.maxY))
            pole.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.9).setStroke()
            pole.lineWidth = 3.6
            pole.stroke()
            UIColor.black.setStroke()
            pole.lineWidth = 1.8
            pole.stroke()
        }
        ctx.setShadow(offset: .zero, blur: bare ? 2 : 1.2,
                      color: (bare ? Glyph.halo(mark) : UIColor.black.withAlphaComponent(0.85)).cgColor)
        sign.draw(at: spot, withAttributes: attrs)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
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
}
