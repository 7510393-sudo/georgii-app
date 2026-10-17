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

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = step
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.spun(_:)),
                         for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
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
