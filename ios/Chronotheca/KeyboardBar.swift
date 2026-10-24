import SwiftUI
import UIKit

/// Полоска вложений над клавиатурой — частью самой клавиатуры (P279).
///
/// Раньше она стояла отдельно и догоняла клавиатуру по её сообщениям.
/// Когда клавиатуру смахивали пальцем, сообщений нет до самого конца —
/// и полоска висела на месте, пока клавиатура уже уехала. Приставка к
/// клавиатуре ездит с ней сама, как её собственная строка.
///
/// Кнопки только просят: окна выбора открывает полоска открытой
/// страницы — она на своём месте в окне, ей их и показывать.
enum KeyboardBar {

    enum Ask: Equatable { case photo, camera, audio, files, place, map }

    /// Кто исполняет просьбы — оболочка приложения.
    static var ask: (Ask) -> Void = { _ in }
    /// Кто открывает раздел, выбранный над клавиатурой (P613).
    static var go: (Shell.Screen) -> Void = { _ in }

    /// Высота строки вложений над клавиатурой (P423).
    static let attachHeight: CGFloat = 36
    /// Насколько проступает цвет дня у строки вложений: сквозь неё видно
    /// страницу — и над клавиатурой, и внизу страницы (P424).
    /// Плотнее прежней половины (P435): сквозь строку страница едва видна.
    static let see: Double = 0.85
    /// Отступ строк от краёв экрана — бока скруглены (P424).
    static let inset: CGFloat = 6

    /// Какой день открыт: полоска над клавиатурой — в его цвет, как и
    /// полоска на странице (P297). Одна приставка на все поля, поэтому
    /// день ей сообщают, а не передают.
    final class Day: ObservableObject {
        @Published var date = DayStore.today()
    }
    static let day = Day()

    /// Где по высоте экрана полоска вложений открытой страницы — её
    /// сообщает сама полоска. Снимок, отпущенный над ней, возвращается в
    /// ленту (P547). Прежнее «втекание» строк (P440) убрано (P551).
    static var pillTarget: CGFloat?

    private static var host: UIHostingController<KeyboardBarView>?

    /// Сменили язык — приставка одна на всё время работы и сама не
    /// перерисовывается: в 106-й над клавиатурой оставались русские
    /// названия разделов при английском приложении (P463).
    static func relabel() {
        host?.rootView = KeyboardBarView()
    }
    private static var holder: UIView?

    /// Одна приставка на все поля: видна она только у того, в котором пишут.
    ///
    /// Строка вложений — часть клавиатуры, как строка оформления в Diarium
    /// (P546): iPhone сам несёт её вместе с клавиатурой — и когда та уходит,
    /// и когда её смахивают пальцем. Ничего не догоняет и не «втекает» в
    /// нижние строки (прежние P438–P468 убраны).
    static var view: UIView {
        if let holder { return holder }
        let made = UIHostingController(rootView: KeyboardBarView())
        // Без этого приставка отступает от собственного нижнего края, как
        // от клавиатуры под ней (P310).
        made.safeAreaRegions = []
        made.view.backgroundColor = .clear
        let box = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                       height: accessoryHeight))
        box.backgroundColor = .clear
        made.view.frame = box.bounds
        made.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(made.view)
        host = made
        holder = box
        return box
    }

    /// Высота приставки: строка вложений с воздухом и под ней строка
    /// разделов с рваным краем (P613).
    static let accessoryHeight: CGFloat = attachRoom + SectionsRow.height + TornEdge.depth
    /// Строка вложений с воздухом над и под ней.
    static let attachRoom: CGFloat = attachHeight + 10
}

struct KeyboardBarView: View {
    @ObservedObject private var day = KeyboardBar.day

    var body: some View {
        // Нижняя строка разделов поднимается вместе с клавиатурой (P613):
        // она — часть приставки и едет с клавиатурой сама, и когда ту
        // смахивают пальцем. Над ней — строка вложений, как и на странице
        // над нижней строкой.
        VStack(spacing: 0) {
            attachments
                .frame(height: KeyboardBar.attachHeight)
                .padding(.top, 6)
                .padding(.bottom, 4)
            sections
        }
    }

    /// Те же четыре раздела, что внизу экрана, того же вида. Приставка есть
    /// только у полей дня — открыт «День».
    private var sections: some View {
        HStack(spacing: 0) {
            section("календарь", T("Календарь", "Calendar"), .calendar)
            section("сегодня", T("День", "Day"), .today)
            section("карта", T("Карта", "Map"), .map)
            section("поиск", T("Поиск", "Search"), .search)
        }
        .padding(.vertical, 1)
        .frame(height: SectionsRow.height)
        .padding(.top, TornEdge.depth)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                KraftPaper()
                    .clipShape(TornEdge())
                TornEdgeLine()
                    .stroke(Look.kraftEdge.opacity(0.55), lineWidth: 0.8)
                    .frame(height: TornEdge.depth + 1)
                    .clipped()
            }
        }
    }

    private func section(_ icon: String, _ name: String, _ target: Shell.Screen) -> some View {
        let on = target == .today
        let side = 35 * SectionsRow.scale * SectionsRow.grow(target)
        return Button { KeyboardBar.go(target) } label: {
            VStack(spacing: 3) {
                Image(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: side, height: side)
                Text(name).font(Look.sans(SectionsRow.font, weight: on ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? Look.tabLit : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(on ? Look.accent.opacity(0.75) : .clear, lineWidth: 1.3))
                    .padding(.horizontal, -16)
                    .padding(.vertical, -3))
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Look.accent : Look.kraftInk)
        }
        .buttonStyle(.plain)
        // Метка для проверок движения (P552, P613).
        .accessibilityIdentifier("keys.\(target)")
    }

    /// Строка вложений — полупрозрачная: сквозь неё видна страница (P423).
    var attachments: some View {
        HStack(spacing: 0) {
            // Тот же порядок, что и в полоске без клавиатуры: камера
            // слева, дальше фото, аудио, файлы — у каждой кнопки своё
            // место, оно не должно меняться (P310).
            key("camera", T("камера", "camera")) { KeyboardBar.ask(.camera) }
            key("photo", T("фото", "photo")) { KeyboardBar.ask(.photo) }
            key("mic", T("аудио", "audio")) { KeyboardBar.ask(.audio) }
            key("doc", T("файлы", "files")) { KeyboardBar.ask(.files) }
            // «Место» — крайней справа, рядом с файлами (P496): касание —
            // где вы сейчас, долгое нажатие — карта.
            BarFace(icon: "mappin.and.ellipse", name: T("место", "place"), tint: Look.stripInk,
                    compact: true, spot: Ru.tint(day.date))
                .onTapGesture { KeyboardBar.ask(.place) }
                .onLongPressGesture(minimumDuration: 0.5) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    KeyboardBar.ask(.map)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(T("Долгое нажатие — вписать, где вы", "Long press to note where you are"))
        }
        .padding(.top, 4)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Полупрозрачная (P424): прежде под цветом дня лежало матовое
        // стекло — и строка выглядела сплошной.
        .background(DayStrip(date: day.date).opacity(KeyboardBar.see))
        // Бока скруглены целиком (P425).
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6))
        .padding(.horizontal, KeyboardBar.inset)
    }

    private func key(_ icon: String, _ name: String, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            BarFace(icon: icon, name: name, tint: Look.stripInk, compact: true, spot: Ru.tint(day.date))
        }
            .buttonStyle(.plain)
            // Метка для проверок движения (P552).
            .accessibilityIdentifier("keyboard." + icon)
    }
}

/// Заголовок дня — поле UIKit со своей приставкой над клавиатурой (P425).
///
/// У поля SwiftUI приставки нет, а найти под ним поле UIKit и дать её ему
/// не вышло (P424): курсор в заголовке — и строки вложений и разделов над
/// клавиатурой пропадали. Поле UIKit несёт ту же приставку, что и запись.
struct TitleLine: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var size: CGFloat
    /// «Ввод» — дальше, в текст записи.
    var onReturn: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        // Строка вложений над клавиатурой (P546).
        field.inputAccessoryView = KeyboardBar.view
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                        for: .editingChanged)
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = UIColor(Look.ink)
        field.tintColor = UIColor(Look.accent)
        // Без строки подсказок над клавиатурой (P409).
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .sentences
        field.returnKeyType = .next
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let plain = Prefs.serifUIFont(size)
        let bold = plain.fontDescriptor.withSymbolicTraits(.traitBold)
            .map { UIFont(descriptor: $0, size: size) } ?? plain
        if field.font != bold { field.font = bold }
        if field.markedTextRange == nil, field.text != text { field.text = text }
        if focused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !focused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TitleLine
        init(_ parent: TitleLine) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.focused { parent.focused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.focused { parent.focused = false }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

/// Строка разделов — внизу экрана и над клавиатурой одна и та же (P613).
enum SectionsRow {
    /// На пару миллиметров тоньше прежних 55 (P613).
    static let height: CGFloat = 44
    /// Значки — 35 × эта доля (прежде 0,85).
    static let scale: CGFloat = 0.72
    /// Названия (прежде 15 × 0,85).
    static let font: CGFloat = 12.5

    /// Книжка на 10%, микроскоп на 5% крупнее прочих (P227).
    static func grow(_ target: Shell.Screen) -> CGFloat {
        switch target {
        case .today:    return 1.10
        case .search:   return 1.05
        case .calendar, .map: return 1
        }
    }
}

extension View {
    /// Сообщить, где по высоте экрана стоит эта строка (P440).
    func reportsY(_ set: @escaping (CGFloat?) -> Void) -> some View {
        background(GeometryReader { g in
            Color.clear
                .onAppear { set(g.frame(in: .global).midY) }
                .onChange(of: g.frame(in: .global).midY) { _, y in set(y) }
                .onDisappear { set(nil) }
        })
    }
}
