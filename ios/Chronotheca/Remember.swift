import SwiftUI

/// Облачко «…помнишь?».
///
/// Нарисовано автором от руки и обведено в вектор. Лежит за вкладкой
/// «Дневник», расслабленно опершись на неё левым локтем: низ облачка
/// стоит на верхнем крае вкладки, а локоть заходит на саму вкладку и
/// накрывает её край. Так видно объём, и у приложения появляется свой
/// симпатичный жилец (решение P206, вместо P140).
///
/// Негромкое: это не напоминание и не требование, а предложение вернуться
/// к своей же записи (решения P66–P69, P140).
///
/// Если записи за то же число год назад нет — облачка нет вовсе. Пока года
/// записей не накопилось, вспоминается месяц назад.
struct RememberCloud: View {

    let date: Date

    /// Пропорции рисунка — снятые с эскиза 26 сентября (P230).
    static let ratio: CGFloat = 1.757
    /// Где на рисунке верхний край вкладки: на нём облачко стоит, ниже
    /// уходит только локоть.
    static let tabEdge: CGFloat = 0.823
    /// Где локоть заходит на вкладку — доли ширины рисунка. Здесь серая
    /// черта вкладки прерывается, всюду ещё — идёт под облачком (P256).
    static let elbow: ClosedRange<CGFloat> = (400.0 / 715)...(588.0 / 715)

    /// Ширина облачка. Подпись «…а помнишь?» теперь от руки автора и
    /// обведена вместе с рисунком (P230).
    let width: CGFloat

    /// Последним: замыкание в хвосте вызова связывается с последним
    /// параметром, а не с первым подходящим.
    let open: () -> Void

    var body: some View {
        let height = width / Self.ratio
        Button(action: open) {
            ZStack {
                Image("облачко-бумага")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Look.cloudPaper)
                // Подпись нарисована по-русски (P230). На других языках —
                // рисунок без слов, а подпись своим языком ложится поверх
                // тем же наклоном и на то же место, рукописным шрифтом (P397).
                // «А вот когда-то…» вместо «…а помнишь?» (P452): рисунка с
                // новой подписью нет — подпись на всех языках шрифтом.
                Image("облачко-без-слов")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(Look.ink)
                Text(T("А вот когда-то…", "Back then…"))
                    .font(Lang.isRussian ? Look.serif(width * 0.092, weight: .semibold).italic()
                                         : .custom("Noteworthy-Bold", size: width * 0.105))
                    .foregroundStyle(Look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(width: width * 0.56)
                    .rotationEffect(.degrees(-28.5))
                    // Середина русской подписи на рисунке: 310 и 215
                    // из 715 × 407.
                    .offset(x: width * (310.0 / 715 - 0.5), y: height * (215.0 / 407 - 0.5))
                    .accessibilityHidden(true)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("А вот когда-то… Запись этого же числа в прошлые годы", "Back then… The entry from this date in past years"))
    }
}

/// Прочитанные напоминания.
///
/// Облачко, на которое нажали, больше не зовёт: оно своё дело сделало,
/// а висеть и дальше — значит требовать внимания впустую (решение P136).
///
/// Помечается день, на котором облачко висело: у каждого дня своё
/// воспоминание, и завтрашнее облачко позовёт к другой записи.
enum Remembered {

    /// Ключ для `@AppStorage`: метки дней через пробел. Простая строка
    /// переживает и перезапуск, и обновление приложения.
    static let key = "remember.read"

    /// Дальше не помним: список не должен расти без края.
    private static let limit = 400

    static func has(_ stamp: String, in list: String) -> Bool {
        list.split(separator: " ").contains { $0 == stamp }
    }

    static func adding(_ stamp: String, to list: String) -> String {
        guard !has(stamp, in: list) else { return list }
        var stamps = list.split(separator: " ").map(String.init)
        stamps.append(stamp)
        if stamps.count > limit { stamps.removeFirst(stamps.count - limit) }
        return stamps.joined(separator: " ")
    }
}

/// Листок с записью того же числа год назад.
struct RememberSheet: View {

    let day: Archive.Day
    let ago: Ago
    @Binding var open: Bool
    @EnvironmentObject private var vault: Vault

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ago.title)
                        .font(Look.sans(12.5))
                        .tracking(0.6)
                        .foregroundStyle(Look.inkFaint)

                    if !day.title.isEmpty {
                        Text(Geo.stripped(day.title))
                            .font(Look.serif(19, weight: .semibold))
                            .foregroundStyle(Look.ink)
                    }
                    // Снимки того дня — сверху, до слов (P466): снимок
                    // возвращает в день сильнее записи.
                    let photos = Array(day.attachments
                        .filter { Diary.kind(of: $0) == .photo }.prefix(3))
                    if !photos.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(photos, id: \.self) { link in
                                PhotoThumb(url: vault.mediaURL(link, for: day.date))
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    Text(day.text)
                        .font(Look.serif(DiaryView.size))
                        .foregroundStyle(Look.ink)
                        .lineSpacing(DiaryView.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(Look.diaryBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { open = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension Archive {

    /// Что вспомнить в этот день.
    ///
    /// Сначала ищется тот же день год назад — это самое ценное: год спустя
    /// запись читается как чужая. Нет года — месяц. Нет месяца — неделя.
    /// Пустой день не вспоминается: показывать нечего (решение P67).
    func remembered(for date: Date) -> (day: Day, ago: Ago)? {
        let cal = Calendar.current
        var tries: [(Ago, Date)] = []

        for years in 1...5 {
            if let then = cal.date(byAdding: .year, value: -years, to: date) {
                tries.append((.years(years), then))
            }
        }
        if let month = cal.date(byAdding: .month, value: -1, to: date) {
            tries.append((.month, month))
        }
        if let week = cal.date(byAdding: .day, value: -7, to: date) {
            tries.append((.week, week))
        }

        for (ago, when) in tries {
            if let day = self.day(Vault.stamp(when)), !day.text.isEmpty {
                return (day, ago)
            }
        }
        return nil
    }
}

/// Насколько давно. Отдельно, чтобы подпись на листке была человеческой.
enum Ago {
    case years(Int), month, week

    var title: String {
        switch self {
        case .years(1): return T("ГОД НАЗАД", "A YEAR AGO")
        case .years(let n) where n < 5: return T("\(n) ГОДА НАЗАД", "\(n) YEARS AGO")
        case .years(let n): return T("\(n) ЛЕТ НАЗАД", "\(n) YEARS AGO")
        case .month: return T("МЕСЯЦ НАЗАД", "A MONTH AGO")
        case .week: return T("НЕДЕЛЮ НАЗАД", "A WEEK AGO")
        }
    }
}
