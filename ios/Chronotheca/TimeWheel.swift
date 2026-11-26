import SwiftUI
import UIKit

/// Ролик времени с шагом в пять минут.
///
/// У ролика, который даёт SwiftUI, шага не задать — он всегда по минуте,
/// то есть шестьдесят делений на час. А в планах почти всегда стоит
/// круглое: ровно, четверть, половина. Шестьдесят делений ради четырёх
/// нужных — лишняя работа на каждом деле, и кручения вшестеро больше, чем
/// надо (решение P153).
///
/// Поэтому здесь системный ролик берётся напрямую: он тот же самый, просто
/// с заданным шагом.
struct TimeWheel: UIViewRepresentable {

    @Binding var time: Date

    /// Шаг в минутах. Должен делить шестьдесят нацело — иначе система
    /// молча вернётся к минуте.
    var step: Int = 5

    /// Рамка ролика (P1089, автор по 363: «выставляя повтор, нажимается не
    /// кнопка, а колёсико с часами — нарушена зона касания»). Системный ролик
    /// не сжимается уже своей ширины: снаружи он был обрезан только видом, а
    /// касания ловил по всей ширине — и над кнопками повтора и напоминания.
    /// Теперь он внутри рамки ровно того размера, что отвёл экран: что за
    /// рамкой, того не видно и того не коснуться.
    final class Frame: UIView {
        let picker = UIDatePicker()
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            picker.translatesAutoresizingMaskIntoConstraints = false
            addSubview(picker)
            NSLayoutConstraint.activate([
                picker.centerXAnchor.constraint(equalTo: centerXAnchor),
                picker.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        required init?(coder: NSCoder) { nil }
        /// Высота — своя у ролика, ширина — какую даст экран.
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: picker.intrinsicContentSize.height)
        }
    }

    func makeUIView(context: Context) -> Frame {
        let frame = Frame()
        let picker = frame.picker
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = step
        // 12 или 24 часа — как выбрано в настройках (P602).
        picker.locale = Locale(identifier: Clock.twelve ? "en_US" : "en_GB")
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.spun(_:)),
                         for: .valueChanged)
        return frame
    }

    func updateUIView(_ frame: Frame, context: Context) {
        let picker = frame.picker
        context.coordinator.time = $time
        if picker.minuteInterval != step { picker.minuteInterval = step }
        // Сравнение нужно: без него ролик дёргался бы обратно на каждом
        // обороте отрисовки, пока человек его крутит.
        guard picker.date != time else { return }
        picker.setDate(time, animated: false)
        // Настоящее время ролику подставляет `.onAppear` снаружи — уже
        // после того, как этот же ролик создался со своим «сейчас». Тем же
        // проходом, пока у листа ещё нет раскладки, барабаны иногда не
        // прокручиваются, хотя `date` уже верный: подстраховка — тем же
        // кадром позже (P303).
        DispatchQueue.main.async {
            if picker.date != time { picker.setDate(time, animated: false) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(time: $time) }

    final class Coordinator: NSObject {
        var time: Binding<Date>
        init(time: Binding<Date>) { self.time = time }
        @objc func spun(_ picker: UIDatePicker) { time.wrappedValue = picker.date }
    }
}
