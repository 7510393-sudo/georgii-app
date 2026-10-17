import SwiftUI
import UIKit
import LocalAuthentication

/// Настройки, которые меняют раз и надолго (P249). Хранятся в самом
/// телефоне, не в папке записей: это привычки человека, а не его записи.
enum Prefs {
    static let lock = "prefs.lock"
    static let hide = "prefs.hide"
    static let theme = "prefs.theme"            // "system", "light", "dark"
    static let boundary = "prefs.boundary"      // час границы суток, 0…6
    static let startTab = "prefs.startTab"      // "last", "plan", "diary"
    static let lastTab = "prefs.lastTab"        // где был в прошлый раз (P402)
    static let navigator = "prefs.navigator"    // "apple", "google"
    static let quiet = "prefs.quiet"            // true — без звуков (P265)
    static let textSize = "prefs.textSize"      // −1…2, ступени размера (P274)
    static let font = "prefs.font"              // "georgia", "newyork", "system"
    // P290: погода, градусы, «Как прошло?», цвет календаря, неделя, сжатие.
    static let noWeather = "prefs.noWeather"    // true — погоды нет
    static let fahrenheit = "prefs.fahrenheit"  // true — градусы Фаренгейта
    static let noAsk = "prefs.noAsk"            // true — без «Как прошло?»
    static let calendarTint = "prefs.calendarTint" // "distance", "weekday", "none"
    static let sundayFirst = "prefs.sundayFirst"   // true — неделя с воскресенья
    static let squeeze = "prefs.squeeze"        // "original" — без сжатия, "high" — среднее (2560), "medium" — высокое (1600)
    static let videoSqueeze = "prefs.videoSqueeze" // "1080" — до 1080p (по умолчанию), "original" — без сжатия

    static var weatherOn: Bool { !UserDefaults.standard.bool(forKey: noWeather) }
    static var askOn: Bool { !UserDefaults.standard.bool(forKey: noAsk) }
    static var firstWeekday: Int { UserDefaults.standard.bool(forKey: sundayFirst) ? 1 : 2 }
    /// По умолчанию — среднее сжатие (P365): на экране не отличить от
    /// оригинала, а места в 5–6 раз меньше.
    static var squeezeKey: String { UserDefaults.standard.string(forKey: squeeze) ?? "high" }
    static var videoTo1080: Bool { (UserDefaults.standard.string(forKey: videoSqueeze) ?? "1080") == "1080" }

    /// Погода для показа: в файле она всегда в °C, показывается — как
    /// выбрано.
    static func weatherText(_ written: String) -> String {
        // Слова — на языке приложения, как бы их ни записали (P412).
        let stored = WeatherNote.shown(written)
        guard UserDefaults.standard.bool(forKey: fahrenheit) else { return stored }
        let ns = stored as NSString
        guard let re = try? NSRegularExpression(pattern: #"([+-]?\d+)°"#),
              let m = re.firstMatch(in: stored, range: NSRange(location: 0, length: ns.length)),
              let c = Int(ns.substring(with: m.range(at: 1)))
        else { return stored }
        let f = Int((Double(c) * 9 / 5 + 32).rounded())
        return ns.replacingCharacters(in: m.range, with: "\(f)°F")
    }

    /// Календарь с выбранным первым днём недели.
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        return cal
    }

    /// Ступени размера текста записей: мельче, обычный, крупнее, ещё крупнее.
    static var textSteps: [(name: String, scale: CGFloat)] {
        [(T("мельче", "smaller"), 0.92), (T("обычный", "normal"), 1),
         (T("крупнее", "larger"), 1.1), (T("ещё крупнее", "largest"), 1.2)]
    }

    static var textStep: Int {
        min(max(UserDefaults.standard.integer(forKey: textSize) + 1, 0), textSteps.count - 1)
    }

    /// Своя ступень записи и размер текста iPhone вместе (P465).
    static var textScale: CGFloat { textSteps[textStep].scale * Look.grow }

    /// С какой вкладки открывать (P249, P402): «где был» — та, что была
    /// открыта в прошлый раз; иначе — план или дневник.
    static var openingTab: Shell.Tab {
        let d = UserDefaults.standard
        let pick = d.string(forKey: startTab) ?? "plan"
        let name = pick == "last" ? (d.string(forKey: lastTab) ?? "plan") : pick
        return name == "diary" ? .diary : .plan
    }

    /// Шрифты записи дневника: названия для настроек.
    static var fonts: [(key: String, name: String)] {
        [("georgia", "Georgia"), ("newyork", "New York"), ("system", T("Без засечек", "Sans serif"))]
    }

    /// По умолчанию — New York (P465): засечный шрифт Apple тоньше Georgia
    /// и легче читается на крупных экранах. Georgia — по выбору.
    static var fontKey: String { UserDefaults.standard.string(forKey: font) ?? "newyork" }

    /// Шрифт записи для полей UIKit.
    static func serifUIFont(_ size: CGFloat) -> UIFont {
        switch fontKey {
        case "newyork":
            let plain = UIFont.systemFont(ofSize: size)
            return plain.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? plain
        case "system":
            return .systemFont(ofSize: size)
        default:
            return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        }
    }

    static var scheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: theme) {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// Граница суток из настроек — применить к расчёту «сегодня».
    static func applyBoundary() {
        // По умолчанию день начинается в полночь (P374; прежде в 4:00).
        let hour = UserDefaults.standard.object(forKey: boundary) as? Int ?? 0
        DayStore.boundaryHour = min(max(hour, 0), 6)
    }
}

/// Замок: пока он закрыт, страниц не видно (P249). Открывается Face ID,
/// Touch ID или кодом телефона — тем, что настроено в самом iPhone.
struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(Look.inkSoft)
            Text(T("Записи закрыты", "Entries are locked"))
                .font(Look.serif(20, weight: .semibold))
                .foregroundStyle(Look.ink)
            Button(action: unlock) {
                Text(T("Открыть", "Unlock"))
                    .font(Look.sans(16, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Look.accent.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.chrome.ignoresSafeArea())
        .onAppear(perform: unlock)
    }

    /// Спросить телефон, тот ли человек держит его в руках.
    static func check(reason: String, done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var trouble: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &trouble) else {
            return done(false)
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

/// Системное окно «поделиться» — поверх того, что сейчас на экране.
enum Share {
    static func present(_ items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let shown = top.presentedViewController { top = shown }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

/// Заголовок раздела на бумажке настроек.
struct StickerSection: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Look.sans(10.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Look.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// Высота клавиатуры над низом экрана. Нужна полоске вложений, которая
/// стоит над клавиатурой, пока та открыта (P253).
final class KeyboardWatch: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    /// Верхний край клавиатуры на экране; без клавиатуры — низ экрана.
    @Published private(set) var top: CGFloat = UIScreen.main.bounds.maxY
    private var watching: [NSObjectProtocol] = []

    init() {
        let centre = NotificationCenter.default
        watching.append(centre.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                           object: nil, queue: .main) { [weak self] note in
            self?.follow(note, hiding: false)
        })
        watching.append(centre.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                           object: nil, queue: .main) { [weak self] note in
            self?.follow(note, hiding: true)
        })
    }

    deinit { watching.forEach(NotificationCenter.default.removeObserver) }

    private func follow(_ note: Notification, hiding: Bool) {
        let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let screen = UIScreen.main.bounds
        let now = hiding ? 0 : max(0, screen.maxY - frame.minY)
        let time = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: time)) {
            height = now
            top = screen.maxY - now
        }
    }
}
