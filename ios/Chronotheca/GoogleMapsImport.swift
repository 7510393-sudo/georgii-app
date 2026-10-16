import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

/// Метки из Google Карт (P512): разовый перенос из файлов, которые человек
/// выгрузил сам, — «Выгрузка данных» Google (места с координатами, списки
/// «Сохранённые») и «Мои карты» (KML). Ничего не берётся с сайта и из чужих
/// аккаунтов; в Google приложение не ходит.
struct GoogleMapsFound {
    var name: String
    var note: String
    var latitude: Double?
    var longitude: Double?
}

enum GoogleMapsImport {

    struct Outcome {
        var added = 0
        var already = 0
        var missing: [String] = []
        /// Сколько файлов удалось прочитать.
        var files = 0
        /// Среди выбранного был архив — его надо распаковать в «Файлах».
        var zip = false
    }

    // MARK: - Разбор файлов

    static func parse(_ data: Data, ext: String) -> [GoogleMapsFound] {
        switch ext.lowercased() {
        case "json", "geojson": return parseJSON(data)
        case "kml": return KMLReader.read(data)
        case "csv": return parseCSV(data)
        default: return []
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// «Saved Places.json» из Выгрузки данных: набор GeoJSON.
    static func parseJSON(_ data: Data) -> [GoogleMapsFound] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var features: [[String: Any]] = []
        if let dict = root as? [String: Any] {
            features = dict["features"] as? [[String: Any]] ?? []
        } else if let list = root as? [[String: Any]] {
            features = list
        }
        return features.compactMap { feature -> GoogleMapsFound? in
            let props = feature["properties"] as? [String: Any] ?? feature
            let location = props["Location"] as? [String: Any] ?? props["location"] as? [String: Any] ?? [:]
            var name = props["Title"] as? String ?? props["title"] as? String ?? props["name"] as? String ?? ""
            if name.isEmpty { name = location["Business Name"] as? String ?? "" }
            if name.isEmpty { name = location["Address"] as? String ?? "" }
            let note = props["Comment"] as? String ?? props["Note"] as? String ?? ""
            var found = GoogleMapsFound(name: name, note: note, latitude: nil, longitude: nil)

            if let geometry = feature["geometry"] as? [String: Any],
               let c = (geometry["coordinates"] as? [NSNumber])?.map({ $0.doubleValue }),
               c.count >= 2, c[0] != 0 || c[1] != 0 {
                found.longitude = c[0]
                found.latitude = c[1]
            }
            if found.latitude == nil, let geo = location["Geo Coordinates"] as? [String: Any],
               let lat = number(geo["Latitude"]), let lon = number(geo["Longitude"]),
               lat != 0 || lon != 0 {
                found.latitude = lat
                found.longitude = lon
            }
            if found.latitude == nil {
                let url = props["Google Maps URL"] as? String ?? props["url"] as? String ?? ""
                if let c = coordinates(inURL: url) {
                    found.latitude = c.0
                    found.longitude = c.1
                }
            }
            if found.name.isEmpty && found.latitude == nil { return nil }
            return found
        }
    }

    /// Списки «Сохранённые»: таблица «Title, Note, URL, Comment». Координат в
    /// ней обычно нет — они берутся из ссылки, если они в ней есть.
    static func parseCSV(_ data: Data) -> [GoogleMapsFound] {
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        else { return [] }
        let rows = csvRows(raw.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let first = rows.first else { return [] }
        let header = first.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let title = column(["title", "name"]) else { return [] }
        let note = column(["note", "comment"])
        let url = column(["url"])
        return rows.dropFirst().compactMap { row -> GoogleMapsFound? in
            guard row.count > title else { return nil }
            let name = row[title].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var found = GoogleMapsFound(
                name: name,
                note: note.flatMap { $0 < row.count ? row[$0] : nil } ?? "",
                latitude: nil, longitude: nil)
            if let url, url < row.count, let c = coordinates(inURL: row[url]) {
                found.latitude = c.0
                found.longitude = c.1
            }
            return found
        }
    }

    /// Строки таблицы с кавычками: запятая и перевод строки внутри кавычек —
    /// часть значения.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        var i = 0
        chars.append("\n")
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" {
                if !(field.isEmpty && row.isEmpty) { row.append(field); rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    /// Координаты из ссылки Google Карт: `!3d…!4d…`, `@…,…`, `q=…,…`, `ll=…,…`.
    static func coordinates(inURL s: String) -> (Double, Double)? {
        let text = s.removingPercentEncoding ?? s
        let patterns = ["!3d(-?\\d+\\.\\d+)!4d(-?\\d+\\.\\d+)",
                        "@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)",
                        "[?&]q=(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)",
                        "[?&]ll=(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)"]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges == 3,
                  let a = Range(m.range(at: 1), in: text),
                  let b = Range(m.range(at: 2), in: text),
                  let lat = Double(text[a]), let lon = Double(text[b]),
                  (-90...90).contains(lat), (-180...180).contains(lon)
            else { continue }
            return (lat, lon)
        }
        return nil
    }

    // MARK: - Перенос

    /// Прочитать выбранное и записать места в папку «Места». Уже лежащее рядом
    /// (то же название и в 30 метрах) второй раз не пишется; чужие файлы не
    /// затираются никогда (`Places.save`).
    static func run(urls: [URL], vault: Vault) -> Outcome {
        var outcome = Outcome()
        var known = Places.all(in: vault)
        var files: [URL] = []

        for url in urls {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            var isFolder: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let inner as URL in walker { files.append(inner) }
                }
            } else {
                files.append(url)
            }
            // Читаем сразу, пока доступ открыт.
            for file in files where ["json", "geojson", "kml", "csv", "zip"].contains(file.pathExtension.lowercased()) {
                if file.pathExtension.lowercased() == "zip" { outcome.zip = true; continue }
                guard let data = try? Data(contentsOf: file) else { continue }
                outcome.files += 1
                for found in parse(data, ext: file.pathExtension) {
                    guard let lat = found.latitude, let lon = found.longitude else {
                        outcome.missing.append(found.name)
                        continue
                    }
                    let name = found.name.isEmpty ? T("Место", "Place") : found.name
                    let here = CLLocation(latitude: lat, longitude: lon)
                    let same = known.contains { place in
                        place.name.lowercased() == name.lowercased()
                            && CLLocation(latitude: place.latitude, longitude: place.longitude)
                                .distance(from: here) < 30
                    }
                    if same { outcome.already += 1; continue }
                    let place = Place(name: name,
                                      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                      text: found.note)
                    if let stored = Places.save(place, in: vault) {
                        known.append(stored)
                        outcome.added += 1
                    }
                }
            }
            files = []
        }
        return outcome
    }
}

/// KML из «Моих карт»: у каждой метки название, описание и точка.
private final class KMLReader: NSObject, XMLParserDelegate {
    private var found: [GoogleMapsFound] = []
    private var path: [String] = []
    private var text = ""
    private var name = ""
    private var note = ""
    private var coords = ""

    static func read(_ data: Data) -> [GoogleMapsFound] {
        let reader = KMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.found
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        text = ""
        if elementName == "Placemark" { name = ""; note = ""; coords = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if path.contains("Placemark") {
            switch elementName {
            case "name":
                if path.count >= 2, path[path.count - 2] == "Placemark" {
                    name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "description":
                note = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            case "coordinates":
                if path.contains("Point") { coords = text }
            case "Placemark":
                var item = GoogleMapsFound(name: name, note: note, latitude: nil, longitude: nil)
                let first = coords.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first
                let parts = first.map { $0.split(separator: ",").map(String.init) } ?? []
                if parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]),
                   (-90...90).contains(lat), (-180...180).contains(lon) {
                    item.latitude = lat
                    item.longitude = lon
                }
                if !item.name.isEmpty || item.latitude != nil { found.append(item) }
            default:
                break
            }
        }
        if !path.isEmpty { path.removeLast() }
    }
}

/// Листок «Метки из Google Карт» в настройках.
struct GoogleMapsImportSheet: View {

    @EnvironmentObject private var vault: Vault
    @Environment(\.dismiss) private var dismiss

    @State private var choosing = false
    @State private var busy = false
    @State private var result: String?
    @State private var missing: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(T("Выгрузите свои места: takeout.google.com → «Карты (Ваши места)» и «Сохранённые» (или «Мои карты» как KML). Распакуйте архив в «Файлах», потом выберите файлы или папку здесь.",
                           "Export your places: takeout.google.com → “Maps (your places)” and “Saved” (or “My Maps” as KML). Unzip the archive in Files, then choose the files or the folder here."))
                        .font(Look.sans(15))
                        .foregroundStyle(Look.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        choosing = true
                    } label: {
                        Text(T("Выбрать файлы…", "Choose files…")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    if busy { ProgressView() }
                    if let result {
                        Text(result)
                            .font(Look.sans(14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !missing.isEmpty {
                        Text(missing.prefix(40).joined(separator: "\n"))
                            .font(Look.sans(13))
                            .foregroundStyle(Look.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(T("Места ложатся в вашу папку обычными файлами. Значки не переносятся: у всех будет обычный.",
                           "Places go into your folder as ordinary files. Icons are not carried over: all get the standard one."))
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .navigationTitle(T("Метки из Google Карт", "Places from Google Maps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Готово", "Done")) { dismiss() }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { picked in
                guard case .success(let urls) = picked else { return }
                start(urls)
            }
        }
    }

    private func start(_ urls: [URL]) {
        busy = true
        result = nil
        missing = []
        let vault = vault
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = GoogleMapsImport.run(urls: urls, vault: vault)
            DispatchQueue.main.async {
                busy = false
                missing = outcome.missing
                if outcome.files == 0 && outcome.zip {
                    result = T("Архив нужно сначала распаковать в «Файлах»: коснитесь его там.",
                               "Unzip the archive in Files first: tap it there.")
                } else if outcome.added + outcome.already + outcome.missing.count == 0 {
                    result = T("Не нашёл мест в этих файлах.", "No places found in these files.")
                } else {
                    var text = T("Перенесено мест: \(outcome.added).", "Places moved: \(outcome.added).")
                    if outcome.already > 0 {
                        text += T(" Уже были: \(outcome.already).", " Already there: \(outcome.already).")
                    }
                    if !outcome.missing.isEmpty {
                        text += T(" Без координат: \(outcome.missing.count).",
                                  " Without coordinates: \(outcome.missing.count).")
                    }
                    result = text
                }
            }
        }
    }
}
