import SwiftUI

/// Короткие сообщения человеку внизу экрана (P933, `docs/68` §2.2).
///
/// Прежде текст сообщения лежал в `Shell`, и каждое сообщение дважды —
/// появляясь и уходя — пересчитывало всё, что смотрит на оболочку. Теперь
/// его смотрит одна плашка (`Toast`). Говорят по-прежнему через
/// `shell.say(…)`.
final class Notices: ObservableObject {

    @Published private(set) var text: String?
    private var hiding: DispatchWorkItem?

    /// Сказать человеку, почему ничего не произошло.
    ///
    /// Молчаливый отказ — худшее, что может сделать приложение: человек решает,
    /// что сломалось оно, хотя оно просто не даёт нарушить правило.
    func say(_ text: String, for seconds: Double = 2.3) {
        hiding?.cancel()
        withAnimation { self.text = text }
        let item = DispatchWorkItem { [weak self] in
            withAnimation { self?.text = nil }
        }
        hiding = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

/// Плашка сообщения: тёмная капсула над нижней строкой; над клавиатурой и
/// полоской на ней, иначе не видно.
struct Toast: View {
    @ObservedObject var notices: Notices
    /// Высота клавиатуры.
    let keys: CGFloat

    var body: some View {
        ZStack {
            if let text = notices.text {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Look.planBg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Look.ink, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .padding(.bottom, keys > 0 ? keys + 24 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}
