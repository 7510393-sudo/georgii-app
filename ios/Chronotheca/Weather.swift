import Foundation
import CoreLocation
import WeatherKit

/// Погода в момент записи — строкой в шапке файла дня: «погода: +12°, туман».
///
/// Берётся у Погоды Apple, когда человек сам отметил место: своих серверов
/// у приложения нет, а координаты уходят только в Apple (P198, P208).
/// Не вышло — запись без погоды, а причина видна в настройках под строкой
/// «Погода» (P354): молча — значит, не узнать, чего не хватает.
enum WeatherNote {

    /// Страница с условиями Погоды Apple — её требуется показывать там,
    /// где приложение показывает погоду.
    static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    static func now(at location: CLLocation) async -> Result<String, Error> {
        do {
            let weather = try await WeatherService.shared.weather(for: location, including: .current)
            let t = Int(weather.temperature.converted(to: .celsius).value.rounded())
            let degrees = (t > 0 ? "+" : "") + "\(t)°"
            return .success(degrees + ", " + words(weather.condition))
        } catch {
            return .failure(error)
        }
    }

    /// Почему Погода Apple не ответила — словами, и с кодом ошибки: по нему
    /// видно, где чинить (P354).
    static func explain(_ error: Error) -> String {
        let ns = error as NSError
        let code = "(" + ns.domain + " " + String(ns.code) + ")"
        // Самая частая беда: у знака приложения на developer.apple.com
        // включено право WeatherKit, но не включена служба WeatherKit —
        // это две разные галочки на двух вкладках.
        if ns.domain.contains("JWTAuthenticator") {
            return T("Apple не пускает приложение к погоде. На developer.apple.com → "
                + "Identifiers → com.kobiashvili.diary должна стоять галочка WeatherKit "
                + "и на вкладке Capabilities, и на вкладке App Services. ",
                "Apple does not let the app get the weather. On developer.apple.com → "
                + "Identifiers → com.kobiashvili.diary, WeatherKit must be ticked on both "
                + "the Capabilities and the App Services tabs. ") + code
        }
        return ns.localizedDescription + " " + code
    }

    /// Состояние неба на языке приложения (P355): система отвечает на
    /// языке телефона, а запись пишется на языке дневника.
    static func words(_ c: WeatherCondition) -> String {
        guard let pair = pair(c) else { return c.description.lowercased() }
        return T(pair.0, pair.1)
    }

    private static func pair(_ c: WeatherCondition) -> (String, String)? {
        switch c {
        case .clear: return pairs[0]
        case .mostlyClear: return pairs[1]
        case .partlyCloudy: return pairs[2]
        case .mostlyCloudy, .cloudy: return pairs[3]
        case .foggy: return pairs[4]
        case .haze, .smoky: return pairs[5]
        case .drizzle: return pairs[6]
        case .rain, .sunShowers: return pairs[7]
        case .heavyRain: return pairs[8]
        case .snow, .flurries, .sunFlurries: return pairs[9]
        case .heavySnow, .blizzard, .blowingSnow: return pairs[10]
        case .sleet, .freezingRain, .freezingDrizzle, .wintryMix: return pairs[11]
        case .hail: return pairs[12]
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms: return pairs[13]
        case .windy, .breezy: return pairs[14]
        case .hot: return pairs[15]
        case .frigid: return pairs[16]
        default: return nil
        }
    }

    /// Слова погоды по-русски и по-английски. По ним записанная погода
    /// показывается на языке приложения, на каком бы её ни записали (P412):
    /// записанное при английском «cloudy» по-русски видно как «облачно».
    static let pairs: [(String, String)] = [
        ("ясно", "clear"), ("почти ясно", "mostly clear"),
        ("переменная облачность", "partly cloudy"), ("облачно", "cloudy"),
        ("туман", "fog"), ("дымка", "haze"), ("морось", "drizzle"),
        ("дождь", "rain"), ("ливень", "heavy rain"), ("снег", "snow"),
        ("метель", "blizzard"), ("мокрый снег", "sleet"), ("град", "hail"),
        ("гроза", "thunderstorm"), ("ветрено", "windy"), ("жара", "hot"),
        ("мороз", "frigid"),
    ]

    /// Записанная погода — на языке приложения: «+12°, cloudy» →
    /// «+12°, облачно». Незнакомое слово остаётся как записано.
    static func shown(_ stored: String) -> String {
        guard let comma = stored.range(of: ", ") else { return stored }
        let word = String(stored[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
        let lower = word.lowercased()
        guard let pair = pairs.first(where: { lower == $0.0 || lower == $0.1
                                              || lower == T($0.0, $0.1).lowercased() })
        else { return stored }
        return String(stored[..<comma.upperBound]) + T(pair.0, pair.1)
    }
}
