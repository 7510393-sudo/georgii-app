import SwiftUI
import CoreText
import UIKit
import LocalAuthentication

/// Настройки, которые меняют раз и надолго (P249). Хранятся в самом
/// телефоне, не в папке записей: это привычки человека, а не его записи.
enum Prefs {
    static let lock = "prefs.lock"
    static let theme = "prefs.theme"            // "system", "light", "dark"
    static let boundary = "prefs.boundary"      // час границы суток, 0…6
    static let font = "prefs.font"              // "georgia", "newyork", "system"
    // P290: погода, «Как прошло?», цвет календаря. Градусы, неделя, часы, сжатие,
    // размер текста, шелест и навигатор — как в iPhone (P633).
    static let noWeather = "prefs.noWeather"    // true — погоды нет
    static let noAsk = "prefs.noAsk"            // true — без «Как прошло?»
    static let ownKeyboardOnly = "prefs.ownKeyboardOnly" // true — только клавиатура iPhone (P633)
    static let calendarTint = "prefs.calendarTint" // "distance", "weekday", "none"

    static var weatherOn: Bool { !UserDefaults.standard.bool(forKey: noWeather) }
    static var askOn: Bool { !UserDefaults.standard.bool(forKey: noAsk) }
    /// Первый день недели — как в iPhone (Основные → Язык и регион): с
    /// воскресенья или с понедельника; календарь знает только эти два (P633).
    static var firstWeekday: Int { Calendar.current.firstWeekday == 1 ? 1 : 2 }

    /// Погода для показа: в файле она всегда в °C, показывается — как
    /// выбрано.
    static func weatherText(_ written: String) -> String {
        // Слова — на языке приложения, как бы их ни записали (P412).
        let stored = WeatherNote.shown(written)
        // Градусы — как в iPhone: Фаренгейт там, где регион американский (P633).
        guard Locale.current.measurementSystem == .us else { return stored }
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

    /// Размер текста записей — размер текста iPhone (Настройки → Экран и
    /// яркость → Размер текста), своих ступеней нет (P633).
    static var textScale: CGFloat { Look.grow }


    /// Шрифты записи дневника: названия для настроек. К трём прежним — шесть
    /// из тех, какими пишут дневники (P602): два книжных и четыре от руки,
    /// все с кириллицей. Лежат в самом приложении (`Fonts/`, лицензия OFL).
    static var fonts: [(key: String, name: String)] {
        [("georgia", "Georgia"), ("newyork", "New York"), ("system", T("Без засечек", "Sans serif")),
         ("lora", "Lora"), ("garamond", "EB Garamond"),
         ("caveat", "Caveat"), ("neucha", "Neucha"), ("badscript", "Bad Script"), ("marck", "Marck Script")]
    }

    /// Свои шрифты: файл в приложении и во сколько крупнее его рисовать —
    /// рукописные при том же кегле мельче книжных.
    private static let bundled: [String: (file: String, scale: CGFloat)] = [
        "lora": ("Lora", 1.0), "garamond": ("EBGaramond", 1.08),
        "caveat": ("Caveat", 1.28), "neucha": ("Neucha", 1.12),
        "badscript": ("BadScript-Regular", 1.0), "marck": ("MarckScript-Regular", 1.18),
    ]

    /// Описания своих шрифтов — шрифт из файла берётся по ним, а не по имени
    /// внутри файла.
    private static let loaded: [String: CTFontDescriptor] = {
        var out: [String: CTFontDescriptor] = [:]
        for (key, font) in bundled {
            guard let url = Bundle.main.url(forResource: font.file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = all.first {
                out[key] = first
            }
        }
        return out
    }()

    /// Свой шрифт записи — или `nil`, если выбран встроенный в iPhone.
    static func bundledFont(_ size: CGFloat) -> UIFont? {
        guard let font = bundled[fontKey], let descriptor = loaded[fontKey] else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, size * font.scale, nil) as UIFont
    }

    /// По умолчанию — New York (P465): засечный шрифт Apple тоньше Georgia
    /// и легче читается на крупных экранах. Georgia — по выбору.
    static var fontKey: String { UserDefaults.standard.string(forKey: font) ?? "newyork" }

    /// Шрифт записи для полей UIKit.
    static func serifUIFont(_ size: CGFloat) -> UIFont {
        if let own = bundledFont(size) { return own }
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
