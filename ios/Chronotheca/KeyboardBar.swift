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

    enum Ask: Equatable { case photo, camera, audio, files, place }

    /// Кто исполняет просьбы — оболочка приложения.
    static var ask: (Ask) -> Void = { _ in }
    /// Кто открывает раздел, выбранный над клавиатурой (P613).
    static var go: (Shell.Screen) -> Void = { _ in }

    /// Высота строки над разделами — в ней одна «＋» справа (P423, P615).
    static let attachHeight: CGFloat = 44

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

    /// Приставка, если она сейчас на экране — над клавиатурой поля дня.
    static var shownHolder: UIView? { holder?.window == nil ? nil : holder }

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

    var body: some View {
        // Нижняя строка разделов поднимается вместе с клавиатурой (P613):
        // она — часть приставки и едет с клавиатурой сама, и когда ту
        // смахивают пальцем. Над ней — «＋» справа, как и на странице
        // над нижней строкой (P615).
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

    /// Вместо пяти кнопок — одна «＋» справа (P615), как и на странице.
    var attachments: some View {
        HStack {
            Spacer(minLength: 0)
            PlusMenu(id: "keyboard.plus")
        }
        .padding(.horizontal, 12)
    }
}

/// Два уголка над скруглённым верхом клавиатуры: квадрат в каждом углу без
/// четверти круга (P614). Чуть шире скругления самой клавиатуры — лишнее
/// ложится под её полупрозрачное стекло.
struct KeyboardCorners: Shape {
    static let radius: CGFloat = 32
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        p.closeSubpath()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// «＋» — всё, что прикладывают к дню, одной кнопкой (P610, P615): камера,
/// фото, голос, файл, место. Просьба уходит открытой странице, как прежде
/// у пяти кнопок строки вложений (`KeyboardBar.ask`), — и со страницы, и
/// над клавиатурой. Новое ложится под последним текстом записи.
struct PlusMenu: View {
    var id: String

    var body: some View {
        Menu {
            Button { KeyboardBar.ask(.camera) } label: { Label(T("Камера", "Camera"), systemImage: "camera") }
            Button { KeyboardBar.ask(.photo) } label: { Label(T("Фото", "Photos"), systemImage: "photo") }
            Button { KeyboardBar.ask(.audio) } label: { Label(T("Голос", "Voice"), systemImage: "mic") }
            Button { KeyboardBar.ask(.files) } label: { Label(T("Файл", "File"), systemImage: "doc") }
            Button { KeyboardBar.ask(.place) } label: {
                Label(T("Где я сейчас", "Where I am"), systemImage: "location")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Look.kraftInk)
                .frame(width: 44, height: 44)
                .background(KraftPaper().clipShape(Circle()).opacity(0.78))
                .overlay(Circle().strokeBorder(Look.kraftEdge.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
        }
        .accessibilityLabel(T("Приложить", "Attach"))
        .accessibilityIdentifier(id)
    }
}

/// Картон в двух уголках над скруглённым верхом клавиатуры (P614): будто
/// строка разделов поднята, а клавиатура лежит на ней сверху.
///
/// Нарисовать их ниже самой приставки нельзя — iPhone обрезает её по краю
/// (так вышло в первой пробе, снимок проверки движения). Поэтому уголки
/// лежат в окне приложения, под окном клавиатуры, и каждый кадр, пока
/// клавиатура видна, встают под нижний край приставки — и когда клавиатуру
/// смахивают пальцем.
final class KeyboardCornersBand: NSObject {
    static let shared = KeyboardCornersBand()

    private var band: UIView?
    private var link: CADisplayLink?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.follow() })
        observers.append(center.addObserver(forName: UIResponder.keyboardDidHideNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.stop() })
    }

    private func follow() {
        guard link == nil else { return }
        let made = CADisplayLink(target: self, selector: #selector(tick))
        made.add(to: .main, forMode: .common)
        link = made
    }

    private func stop() {
        link?.invalidate()
        link = nil
        band?.isHidden = true
    }

    @objc private func tick() {
        let app = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        if Vault.isUITest { report(app) }
        guard let holder = KeyboardBar.shownHolder, let from = holder.window, let app
        else { band?.isHidden = true; return }
        let edge = from.convert(holder.convert(holder.bounds, to: from), to: app)
        let view = band ?? make(in: app)
        // Поверх всего, что приложение положило в окно позже (листки).
        if view.superview === app, app.subviews.last !== view { app.bringSubviewToFront(view) }
        let r = KeyboardCorners.radius
        view.frame = CGRect(x: 0, y: edge.maxY, width: app.bounds.width, height: r)
        view.isHidden = edge.maxY >= app.bounds.height - 1
    }

    /// Для проверки движения: где приставка и уголки — невидимой строкой.
    private var probe: UILabel?
    private func report(_ app: UIWindow?) {
        guard let app else { return }
        let label = probe ?? {
            let made = UILabel(frame: CGRect(x: 0, y: 60, width: 300, height: 4))
            made.alpha = 0.02
            made.accessibilityIdentifier = "cornerWhy"
            app.addSubview(made)
            probe = made
            return made
        }()
        let holder = KeyboardBar.shownHolder
        let from = holder?.window
        var text = "holder=\(holder != nil) window=\(from.map { String(describing: type(of: $0)) } ?? "nil")"
        text += " same=\(from === app)"
        if let holder, let from {
            let r = from.convert(holder.convert(holder.bounds, to: from), to: app)
            text += " edge=\(Int(r.minY))-\(Int(r.maxY))"
        }
        if let band { text += " band=\(Int(band.frame.minY)) hidden=\(band.isHidden) on=\(band.superview === app)" }
        else { text += " band=nil" }
        label.text = text
        label.accessibilityLabel = text
    }

    private func make(in window: UIWindow) -> UIView {
        let view = CornersView()
        window.addSubview(view)
        band = view
        return view
    }
}

/// Картон уголков — простым видом UIKit (P614): тот же цвет и волокно, что
/// у строки разделов, обрезанные по двум уголкам. Вид SwiftUI в окне
/// приложения оставался пустым — по замеру стоял на месте, но не рисовался.
private final class CornersView: UIView {
    private let fibre = UIView()
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(Look.kraft)
        fibre.backgroundColor = UIColor(patternImage: KraftPaper.fibre)
        fibre.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(fibre)
        layer.mask = shape
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        fibre.frame = bounds
        shape.path = KeyboardCorners(radius: KeyboardCorners.radius).path(in: bounds).cgPath
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
