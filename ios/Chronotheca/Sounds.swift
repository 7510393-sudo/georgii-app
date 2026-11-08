import UIKit

/// Толчки в руку (P263, P267): у каждого движения свой.
enum Feel {
    /// Экран тронулся — опускается или поднимается.
    static func thud() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    }
    /// Лёгкое касание: шаг назад, точка легла в текст.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Щелчок колёсика и готового ответа.
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    /// Дело сделано.
    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    /// Дело или точка поднялись под пальцем долгим нажатием (P362).
    static func lift() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    /// Бумажный листок лёг на место.
    static func paper() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
    }
}
