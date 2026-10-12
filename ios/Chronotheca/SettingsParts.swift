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
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
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
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        label
                        Spacer(minLength: 4)
                        trailing()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        label
                        trailing()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Каждая строка — листок бумаги на записке (P381, P387): бумага
        // страницы, тонкий край и лёгкая тень, как у листков на экране, а
        // не гладкая плашка обычного приложения.
        .background(Look.planBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.stickerEdge.opacity(0.9), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.07), radius: 1.5, y: 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
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
        Flow(spacing: 4) {
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
                        .modifier(Tag(main: on))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Look.sans(13.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .modifier(Tag(main: main))
        }
        .buttonStyle(.plain)
    }
}

/// Кнопки в ряд; не помещаются — переходят на следующую строку (P383).
/// Прежде длинные русские варианты («как iPhone», «без сжатия») стояли
/// одной строкой и уходили за край записки.
struct Flow: Layout {
    var spacing: CGFloat = 4

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
            var x = bounds.minX
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
    var main = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(main ? Look.note : Look.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(main ? Look.accent : Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(main ? Look.accent : Look.inkFaint, lineWidth: 1))
            .shadow(color: .black.opacity(main ? 0.12 : 0.06), radius: 1, y: 1)
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
