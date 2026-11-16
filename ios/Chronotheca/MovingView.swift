import Foundation
import SwiftUI


/// Ход переноса во весь экран.
///
/// Перенос между памятью телефона и iCloud идёт минутами, и всё это время
/// записи лежат в двух местах разом. Трогать их нельзя — экран закрыт
/// нарочно, а не по бедности: это единственное место, где приложение имеет
/// право остановить человека.
struct MovingView: View {

    let progress: Transfer.Progress
    var title = T("Переношу записи", "Moving your entries")

    var body: some View {
        ZStack {
            Look.chrome.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Look.ink)

                ProgressView(value: Double(progress.done),
                             total: Double(max(progress.total, 1)))
                    .frame(width: 220)

                Text(T("\(progress.done) из \(progress.total)", "\(progress.done) of \(progress.total)"))
                    .font(Look.mono(13))
                    .foregroundStyle(Look.inkSoft)

                Text(T("Не закрывайте приложение. Если перенос всё же\nоборвётся, ничего не пропадёт: его можно продолжить.",
                        "Please keep the app open. If it is interrupted,\nnothing is lost: you can continue it."))
                    .font(Look.sans(12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Look.inkFaint)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        // Пока идёт перенос, ничто под этим экраном не отзывается.
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}
