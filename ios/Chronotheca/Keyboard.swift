import SwiftUI
import UIKit

/// Насколько клавиатура закрывает экран снизу.
///
/// Приложение не отдаёт клавиатуре весь экран: шестерёнка, три точки и три
/// раздела внизу стоят на месте всегда (P113). Поднимается только то, в чём
/// пишут, и ровно на столько, сколько закрыто.
struct KeyboardHeight: ViewModifier {

    @Binding var height: CGFloat
    /// Отступ считать от нижнего края экрана, а не от границы безопасной
    /// полосы. Нужно там, где поднимаемое стоит вплотную к физическому
    /// низу (карта, P308) — не там, где оно и так стоит внутри отступов
    /// экрана, и вычитать полосу дважды нельзя.
    var toScreenEdge = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect ?? .zero
                let screen = UIScreen.main.bounds.height
                // Нижняя безопасная полоса телефона уже учтена отступами:
                // не вычесть её — и остаётся пустое поле шириной в палец.
                let safe = toScreenEdge ? 0 : UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
                    .first ?? 0
                // Полоска вложений — часть клавиатуры (P279), её высота уже
                // в размере клавиатуры.
                height = max(0, screen - frame.origin.y - safe)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                height = 0
            }
    }
}

extension View {
    func keyboardHeight(_ height: Binding<CGFloat>, toScreenEdge: Bool = false) -> some View {
        modifier(KeyboardHeight(height: height, toScreenEdge: toScreenEdge))
    }
}
