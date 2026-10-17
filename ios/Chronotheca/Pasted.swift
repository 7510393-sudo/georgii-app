import Foundation
import CoreLocation

/// Координаты из того, что человек вставил в поиск карты (P258).
///
/// Карты Google и Apple отдают место по-разному, и понимать надо все
/// виды, а не один наш:
/// - «51.500729, -0.124625» — как копирует булавку Google;
/// - «51.50073° N, 0.12462° W» — как копируют Карты Apple;
/// - «51°30'02.6"N 0°07'28.7"W» — градусы, минуты, секунды;
/// - ссылки: `maps.apple.com/?ll=…&q=…`, `google.com/maps/place/…/@…`,
///   `…!3d…!4d…`, `?q=…`;
/// - короткие ссылки `maps.app.goo.gl/…` и `maps.apple/p/…` — их
///   приходится открыть, чтобы узнать, куда они ведут.
enum Pasted {

    struct Found {
        var title: String?
        var at: CLLocationCoordinate2D
    }

    static func find(_ raw: String) -> Found? {
        // Невидимые знаки направления и неразрывные пробелы, которые
        // приносит буфер из чужих приложений, — прочь (P292).
        let cleaned = raw.unicodeScalars.filter {
            !["\u{200E}", "\u{200F}", "\u{202A}", "\u{202C}", "\u{2066}", "\u{2069}", "\u{FEFF}"]
                .contains(String($0))
        }.map(String.init).joined().replacingOccurrences(of: "\u{00A0}", with: " ")
        let text = cleaned.removingPercentEncoding ?? cleaned
        if let found = fromLink(text) { return found }
        if let at = hemispheres(text) { return Found(title: nil, at: at) }
        if let at = plain(text) { return Found(title: nil, at: at) }
        return nil
    }

    // MARK: - Ссылки

    private static let linkCoordinates = [
        // Google: точное место в данных ссылки.
        #"!3d(-?\d{1,3}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)"#,
        // Google: середина карты.
        #"@(-?\d{1,3}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)"#,
        // Google: «/maps/search/51.5,+-0.12», «/maps/place/…», «/maps/dir/…»
        // — так ведёт кнопка «Поделиться» в Google Картах (P292).
        #"/maps/(?:search|place|dir)/(?:[^/]*/)?\+?(-?\d{1,3}\.\d+)\s*,\s*\+?(-?\d{1,3}\.\d+)"#,
        // Apple и Google: параметры ссылки.
        #"[?&](?:ll|q|query|sll|daddr|saddr|destination|coordinate|center)=\s*(-?\d{1,3}(?:\.\d+)?)\s*[,+\s]\s*\+?(-?\d{1,3}(?:\.\d+)?)"#,
        // Страница, куда привела короткая ссылка.
        #"\x22?latitude\x22?\s*[:=]\s*\x22?(-?\d{1,3}\.\d+)[^0-9-]{1,40}\x22?longitude\x22?\s*[:=]\s*\x22?(-?\d{1,3}\.\d+)"#,
    ]

    private static func fromLink(_ text: String) -> Found? {
        for pattern in linkCoordinates {
            guard let g = groups(pattern, in: text), g.count == 2,
                  let at = coordinate(g[0], g[1]) else { continue }
            return Found(title: title(in: text), at: at)
        }
        return nil
    }

    /// Название места из ссылки, если оно там есть.
    private static func title(in text: String) -> String? {
        let candidates = [
            groups(#"/maps/place/([^/@?]+)"#, in: text)?.first,
            groups(#"[?&](?:q|name)=([^&]+)"#, in: text)?.first,
        ]
        for c in candidates.compactMap({ $0 }) {
            let t = c.replacingOccurrences(of: "+", with: " ")
                .trimmingCharacters(in: .whitespaces)
            // «q=51.5,-0.12» — это не название.
            if t.isEmpty || t.range(of: #"^[-\d.,\s°]+$"#, options: .regularExpression) != nil { continue }
            return t
        }
        return nil
    }

    // MARK: - Полушария: N/S/E/W и С/Ю/В/З

    private static let part = try! NSRegularExpression(pattern:
        #"(\d{1,3}(?:[.,]\d+)?)\s*°?\s*(?:(\d{1,2}(?:[.,]\d+)?)\s*['′’]\s*)?(?:(\d{1,2}(?:[.,]\d+)?)\s*(?:[\x22″”]|'')\s*)?([NSEWСЮВЗ])(?![A-ZА-Я])"#)

    private static func hemispheres(_ text: String) -> CLLocationCoordinate2D? {
        // По-русски Карты Apple пишут «51,50073° с. ш., 0,12462° з. д.».
        let t = text.uppercased()
            .replacingOccurrences(of: #"([СЮВЗ])\.?\s*[ШД]\.?"#, with: "$1",
                                  options: .regularExpression)
        let ns = t as NSString
        var lat: Double?
        var lon: Double?
        for m in part.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            func piece(_ i: Int) -> Double {
                let r = m.range(at: i)
                return r.location == NSNotFound ? 0 : number(ns.substring(with: r)) ?? 0
            }
            var value = piece(1) + piece(2) / 60 + piece(3) / 3600
            let side = ns.substring(with: m.range(at: 4))
            if "SWЮЗ".contains(side) { value = -value }
            if "NSСЮ".contains(side) { lat = lat ?? value } else { lon = lon ?? value }
        }
        guard let lat, let lon else { return nil }
        return valid(lat, lon)
    }

    // MARK: - Просто два числа

    private static func plain(_ text: String) -> CLLocationCoordinate2D? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        if t.lowercased().hasPrefix("geo:") { t.removeFirst(4) }
        // «51.5, -0.12», «51.5;-0.12», «51.5 -0.12».
        // Google Карты копируют и с плюсом: «51.500729,+-0.124625» (P292).
        if let g = groups(#"^\s*\+?(-?\d{1,3}(?:\.\d+)?)\s*[,;\s+]+\s*\+?(-?\d{1,3}(?:\.\d+)?)\s*$"#, in: t) {
            return coordinate(g[0], g[1])
        }
        // С запятой вместо точки: «51,5007 -0,1246», «51,5007; -0,1246».
        if let g = groups(#"^\s*(-?\d{1,3},\d+)\s*[;\s]\s*(-?\d{1,3},\d+)\s*$"#, in: t) {
            return coordinate(g[0], g[1])
        }
        return nil
    }

    // MARK: - Короткие ссылки

    /// Короткая ссылка, которую надо открыть, чтобы узнать место.
    static func shortLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let ns = text as NSString
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = m.url, let host = url.host?.lowercased() else { continue }
            if host.contains("goo.gl") || host.contains("maps.app") || host.hasPrefix("maps.apple")
                || host.contains("apple.co") || host.contains("google.") {
                return url
            }
        }
        return nil
    }

    /// Открыть ссылку и найти место там, куда она привела: сперва в самом
    /// адресе, потом на странице.
    static func resolve(_ url: URL, done: @escaping (Found?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var found = response?.url.flatMap { find($0.absoluteString) }
            if found == nil, let data {
                let page = String(decoding: data.prefix(600_000), as: UTF8.self)
                found = fromLink(page)
            }
            DispatchQueue.main.async { done(found) }
        }.resume()
    }

    // MARK: - Мелочи

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return (1..<m.numberOfRanges).map {
            let r = m.range(at: $0)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private static func coordinate(_ a: String, _ b: String) -> CLLocationCoordinate2D? {
        guard let lat = number(a), let lon = number(b) else { return nil }
        return valid(lat, lon)
    }

    private static func valid(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D? {
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
