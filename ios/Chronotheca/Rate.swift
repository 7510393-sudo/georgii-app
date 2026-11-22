import StoreKit
import UIKit

/// Системное окно «Оцените» (P1037, автор: «через неделю пускай
/// появляется окно»). Текст и звёзды рисует сам iPhone; приложение только
/// просит — и не раньше, чем через неделю с первого открытия, после
/// хорошего мига: человек дописал запись сегодняшнего дня и убрал
/// клавиатуру. Не чаще раза в четыре месяца (iPhone и сам показывает не
/// больше трёх раз в год). В TestFlight окна нет — так у Apple.
enum Rate {
    private static let firstKey = "rate.first"
    private static let askedKey = "rate.asked"
    private static let week: TimeInterval = 7 * 24 * 3600
    private static let gap: TimeInterval = 120 * 24 * 3600

    /// Первое открытие приложения — от него неделя.
    static func noteOpened() {
        let d = UserDefaults.standard
        if d.object(forKey: firstKey) == nil { d.set(Date(), forKey: firstKey) }
    }

    /// Хороший миг: попросить, если пора. Через секунду — когда клавиатура
    /// ушла и экран успокоился.
    static func goodMoment() {
        guard !Vault.isUITest, !Vault.isPreview else { return }
        let d = UserDefaults.standard
        let now = Date()
        guard let first = d.object(forKey: firstKey) as? Date,
              now.timeIntervalSince(first) >= week else { return }
        if let asked = d.object(forKey: askedKey) as? Date, now.timeIntervalSince(asked) < gap { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) else { return }
            d.set(Date(), forKey: askedKey)
            AppStore.requestReview(in: scene)
        }
    }
}
