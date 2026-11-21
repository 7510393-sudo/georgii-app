import SwiftUI
import CoreText
import UIKit
import LocalAuthentication

/// Настройки — продолжение (ключи — в `Core/Prefs.swift`, P970).
extension Prefs {

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


    /// Шрифты записи дневника — два (P680): с засечками (New York) и без.
    /// Прежние девять — Georgia, Lora, EB Garamond и четыре рукописных —
    /// убраны: ими почти никто не пользовался, а лежали они в приложении
    /// почти два мегабайта (отменяет P602).
    static var fonts: [(key: String, name: String)] {
        [("newyork", "New York"), ("system", "San Francisco"), ("comfortaa", "Comfortaa")]
    }

    /// Выбранный шрифт: Comfortaa, «без засечек» или New York. Прежний выбор
    /// любого из убранных шрифтов — тоже New York.
    static var fontKey: String {
        let stored = UserDefaults.standard.string(forKey: font)
        return stored == "system" || stored == "comfortaa" ? stored! : "newyork"
    }

    /// При запуске: выбор убранного шрифта переписывается на New York, чтобы
    /// в настройках стояла отметка у одного из трёх (P680); Comfortaa из
    /// файлов приложения подключается один раз (P689).
    /// При запуске (P997): гамма и старая бумага — один выбор из трёх.
    /// Шалфей и лаванда убраны — у кого были, тому абрикосовая; «без цвета»
    /// со старой бумагой — без бумаги: серый выбран нарочно.
    static func settleLook() {
        let d = UserDefaults.standard
        let tint = d.string(forKey: calendarTint)
        if let tint, !["distance", "none"].contains(tint) {
            d.set("distance", forKey: calendarTint)
        }
        if tint == "none", !d.bool(forKey: plainPast) {
            d.set(true, forKey: plainPast)
        }
    }

    static func settleFont() {
        let stored = UserDefaults.standard.string(forKey: font)
        if let stored, !["newyork", "system", "comfortaa"].contains(stored) {
            UserDefaults.standard.set("newyork", forKey: font)
        }
        for file in ["Comfortaa-Regular", "Comfortaa-Bold"] {
            if let url = Bundle.main.url(forResource: file, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Comfortaa шире и крупнее на вид, чем шрифты iPhone: тот же размер
    /// рисуется чуть меньше.
    static let comfortaaScale: CGFloat = 0.94

    /// Надпись кнопки выбора шрифта — тем же шрифтом, какой она называет (P690).
    static func sampleFont(_ key: String, bold: Bool) -> Font {
        switch key {
        case "comfortaa": return .custom(bold ? "Comfortaa-Bold" : "Comfortaa-Regular", size: 13.5)
        case "system": return .system(size: 13.5, weight: bold ? .semibold : .regular)
        default: return .system(size: 13.5, weight: bold ? .semibold : .regular, design: .serif)
        }
    }

    /// Жирный шрифт заголовка записи (P759) — один для открытой страницы
    /// (поле UIKit) и соседних (надпись SwiftUI). Прежде открытая брала
    /// жирное начертание через признак шрифта и без поправки размера
    /// Comfortaa, а соседняя — своё: лист ложился, и заголовок на глазах
    /// становился шире и толще.
    static func titleUIFont(_ size: CGFloat) -> UIFont {
        if fontKey == "comfortaa",
           let own = UIFont(name: "Comfortaa-Bold", size: size * comfortaaScale) { return own }
        if fontKey == "system" || fontKey == "comfortaa" { return .systemFont(ofSize: size, weight: .bold) }
        let plain = UIFont.systemFont(ofSize: size, weight: .bold)
        return plain.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? plain
    }

    /// Шрифт записи для полей UIKit.
    static func serifUIFont(_ size: CGFloat) -> UIFont {
        if fontKey == "comfortaa",
           let own = UIFont(name: "Comfortaa-Regular", size: size * comfortaaScale) { return own }
        if fontKey == "system" || fontKey == "comfortaa" { return .systemFont(ofSize: size) }
        let plain = UIFont.systemFont(ofSize: size)
        return plain.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? plain
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
