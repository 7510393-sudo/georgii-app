import SwiftUI

// Детали настроек в духе тетради на голубой записке (P367).
//
// Кнопок три вида, и они различаются на глаз:
// — кружки-выбор: видны все варианты, выбранный закрашен синим;
// — «Открыть ›»: открывает окно или листок, сама ничего не меняет;
// — одна главная кнопка (резервная копия): закрашена целиком.
// Нажимается только кнопка — название строки не меняет ничего. Прежде
// касание по строке молча перебирало варианты по кругу, и не было видно,
// что ещё бывает и что сейчас изменится.

/// Заголовок раздела: синим засечным, с чертой до края — как в тетради.
struct NoteSection: View {
    let title: String

    var body: some View {
        // Заголовок раздела — крупнее и без черты до края (P381): разделы
        // отделены воздухом и плашками строк, а не линиями.
        Text(title)
            .font(Look.serif(19, weight: .semibold))
            .foregroundStyle(Look.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

/// Раздел настроек — жёлтый стикер на белом листе, с тенью (P600): строки
/// раздела на одном стикере, между ними тонкие черты, как в меню страницы.
/// Прежде каждая строка была отдельной белой плашкой на жёлтой записке —
/// десятки одинаковых плашек читались как анкета.
struct NoteCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.bottom, 4)
            // Тень — у простой фигуры под стикером, а не у содержимого
            // (P428, P488): так она не пересчитывается на каждом кадре выезда.
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Look.sticker)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Look.stickerEdge, lineWidth: 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
    }
}

/// Строка настроек: название (и мелко — пояснение) и кнопки. Помещаются
/// в одну линию — стоят в линию; нет — кнопки уходят под название.
struct NoteRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var detailColor: Color = Look.inkSoft
    /// Кнопка всегда справа, подпись переносится (P485) — для строк, у которых
    /// подпись дополняется уже на открытом листке.
    var pinned = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        Group {
            if pinned, detail != nil {
                // Со второй строкой кнопка стоит справа всегда (P485): через
                // секунду после открытия листка к подписи добавлялся объём
                // памяти, строка переставала помещаться в ряд, и кнопка
                // прыгала влево и вниз. Теперь подпись сама переносится в
                // своём месте, а кнопка не двигается.
                HStack(alignment: .center, spacing: 8) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    trailing().fixedSize()
                }
            } else {
                // Кнопки всегда у правого края, на одной вертикали (P600):
                // не помещаются рядом с названием — уходят строкой ниже, но
                // тоже вправо. Прежде они уходили влево, и в одном разделе
                // кнопки стояли то справа, то слева.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        label
                        Spacer(minLength: 4)
                        trailing()
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        label.frame(maxWidth: .infinity, alignment: .leading)
                        trailing()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Строки одного стикера-раздела разделены тонкой чертой (P600).
        .overlay(alignment: .top) {
            Rectangle().fill(Look.stickerEdge).frame(height: 0.8).padding(.horizontal, 12)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Название — засечным, как записи и заголовки (P387).
            Text(title)
                .font(Look.serif(16.5))
                .foregroundStyle(Look.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Look.sans(12.5))
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Кружки-выбор: все варианты на виду, выбранный закрашен.
struct Choice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        // Не помещаются в строку — переходят на следующую, а не уходят за
        // край записки (P383).
        Flow(spacing: 4, trailing: true) {
            ForEach(options.indices, id: \.self) { i in
                let (value, name) = options[i]
                let on = value == selection
                Button {
                    guard !on else { return }
                    Feel.tick()
                    selection = value
                } label: {
                    Text(name)
                        .font(Look.sans(13.5, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .modifier(Tag(look: on ? .chosen : .plain))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Выбор цветовой гаммы (P498): кнопки — словами, без образцов (P647).
struct SchemeChoice: View {
    @Binding var selection: String
    /// Какие варианты показать: «без цвета» стоит в строке с названием, три
    /// гаммы — строкой ниже (P650).
    var keys: [String]? = nil

    private var options: [(String, String)] {
        [("distance", T("Абрикос", "Apricot")),
         ("sage", T("Шалфей", "Sage")),
         ("lavender", T("Лаванда", "Lavender")),
         ("none", T("без цвета", "none"))]
    }

    var body: some View {
        Flow(spacing: 4, trailing: true) {
            ForEach(options.filter { keys?.contains($0.0) ?? true }, id: \.0) { key, name in
                // Прежний «weekday» читается как первая гамма.
                let on = key == selection || (key == "distance" && selection == "weekday")
                Button {
                    guard !on else { return }
                    Feel.tick()
                    selection = key
                } label: {
                    // Кнопка — размером со слово (замечание автора к 182):
                    // с кружками-образцами четыре кнопки вставали в три строки.
                    Text(name)
                        .font(Look.sans(13.5, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .modifier(Tag(look: on ? .chosen : .plain))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// «Открыть ›» и главная кнопка.
struct NoteButton: View {
    let title: String
    var main = false
    /// В рамке, как ярлычок (листок переноса дела). В настройках «Открыть ›»
    /// — просто надпись со стрелкой, как в меню страницы (P600).
    var framed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if main || framed {
                Text(title)
                    .font(Look.sans(13.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .modifier(Tag(look: main ? .main : .plain))
            } else {
                Text(title)
                    .font(Look.sans(14.5, weight: .semibold))
                    .foregroundStyle(Look.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// Вкл/выкл — рычажком в цветах приложения (P600), а не двумя ярлычками:
/// они занимали полстроки, и строки не помещались.
struct Lever: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { now in
            Feel.tick()
            isOn = now
        }))
        .labelsHidden()
        .tint(Look.accent)
    }
}

/// Кнопки в ряд; не помещаются — переходят на следующую строку (P383).
/// Прежде длинные русские варианты («как iPhone», «без сжатия») стояли
/// одной строкой и уходили за край записки.
struct Flow: Layout {
    var spacing: CGFloat = 4
    /// Ряды прижаты к правому краю (P600): в настройках варианты стоят на
    /// одной вертикали с прочими кнопками.
    var trailing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let wide = rows.map(\.width).max() ?? 0
        let high = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: wide, height: high)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = trailing ? bounds.maxX - row.width : bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let need = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, need > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// Кнопка-ярлычок (P387): выпуклая панелька, как номер, время и
/// колокольчик у дела в плане (P364, P374), — вместо капсул обычного
/// приложения. Главная (или выбранный вариант) — залита синим.
struct Tag: ViewModifier {
    /// Ярлычок бумажный; выбранный — голубой стикер (P600: прежде тёмно-синий,
    /// как главная кнопка, и выбор путали с действием); главная кнопка —
    /// залитая, одна на листок.
    enum Kind { case plain, chosen, main }
    var look: Kind = .plain

    func body(content: Content) -> some View {
        let fill: Color = look == .main ? Look.accent : look == .chosen ? Look.noteChosen : Look.planBg
        let edge: Color = look == .plain ? Look.inkFaint.opacity(0.7) : Look.accent
        content
            .foregroundStyle(look == .main ? Look.note : Look.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(edge, lineWidth: look == .plain ? 0.8 : 1.2))
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(look == .plain ? 0.06 : 0.12)).offset(y: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Кнопка, которую пора нажать (P428): красная и мигает — резервная копия
/// давно не делалась. Мигание просил автор: строка должна звать сама.
struct DueButton: View {
    let title: String
    let action: () -> Void
    @State private var dim = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Look.sans(13.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.red.opacity(dim ? 0.45 : 0.9)))
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}
