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
    /// Кто открывает разделы — оболочка приложения (P423).
    static var go: (Shell.Screen) -> Void = { _ in }

    /// Строка вложений и под ней строка разделов вдвое тоньше (P423):
    /// клавиатура закрывает нижнюю строку экрана — она поднимается над
    /// клавиатурой вместе со строкой вложений. Разделы не пропадают (P113).
    static let attachHeight: CGFloat = 36
    /// Вдвое шире прежней (P425): названия разделов читаются.
    static let sectionsHeight: CGFloat = 36
    static let height: CGFloat = attachHeight + sectionsHeight
    /// Насколько проступает цвет дня у строки вложений: сквозь неё видно
    /// страницу — и над клавиатурой, и внизу страницы (P424).
    /// Плотнее прежней половины (P435): сквозь строку страница едва видна.
    static let see: Double = 0.85
    /// Нижняя безопасная полоса телефона (жест «домой»).
    static var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }
    /// Отступ строк от краёв экрана — бока скруглены (P424).
    static let inset: CGFloat = 6

    /// Какой день открыт: полоска над клавиатурой — в его цвет, как и
    /// полоска на странице (P297). Одна приставка на все поля, поэтому
    /// день ей сообщают, а не передают.
    final class Day: ObservableObject {
        @Published var date = DayStore.today()
    }
    static let day = Day()

    /// Куда строки над клавиатурой «втекают», когда она уходит (P440).
    static let glide = Glide()

    /// Строки над клавиатурой не уезжают вместе с ней вниз и не гаснут на
    /// полпути: как только клавиатуру отпустили, их место занимают такие же
    /// строки в окне приложения — они едут к настоящим нижним строкам
    /// (полоске вложений у низа страницы и названиям разделов внизу), на
    /// месте тают и сливаются с ними. Прежде строки над клавиатурой
    /// уезжали ниже настоящих, гасли, а настоящие «подпрыгивали» (запись
    /// экрана автора, P440).
    final class Glide: ObservableObject {
        @Published var on = false
        @Published var pillY: CGFloat = 0
        @Published var namesY: CGFloat = 0
        @Published var opacity: Double = 1
        /// Строка вложений не тает, а доезжает до нижней (P456): была
        /// приглушена смахиванием — по пути возвращает яркость.
        @Published var pillOpacity: Double = 1
        /// Где настоящие строки — по высоте экрана; их сообщают сами.
        var pillTarget: CGFloat?
        var namesTarget: CGFloat?
        private var token = 0

        func start(pill: CGFloat, names: CGFloat, opacity from: Double, duration: Double) -> Bool {
            guard let pt = pillTarget, let nt = namesTarget else { return false }
            token += 1
            let mine = token
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                on = true
                pillY = min(pill, pt)
                namesY = min(names, nt)
                // Названия могли уже наполовину растаять, пока клавиатуру
                // вели пальцем (P464).
                opacity = min(from, KeyboardBar.names.value)
                pillOpacity = from
            }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: duration)) {
                    self.pillY = pt
                    self.namesY = nt
                }
                // Тают только названия разделов; строка вложений доезжает
                // до нижней целиком и сливается с ней (P456).
                withAnimation(.easeOut(duration: duration * 0.6)) { self.opacity = 0 }
                withAnimation(.easeOut(duration: duration)) { self.pillOpacity = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                if self.token == mine { self.on = false }
            }
            return true
        }

        func stop() {
            token += 1
            on = false
        }
    }

    private static var host: UIHostingController<KeyboardBarView>?

    /// Сменили язык — приставка одна на всё время работы и сама не
    /// перерисовывается: в 106-й над клавиатурой оставались русские
    /// названия разделов при английском приложении (P463).
    static func relabel() {
        host?.rootView = KeyboardBarView()
    }
    private static var holder: UIView?

    /// Одна приставка на все поля: видна она только у того, в котором пишут.
    static var view: UIView {
        if let holder { return holder }
        let made = UIHostingController(rootView: KeyboardBarView())
        // Без этого приставка отступает от собственного нижнего края, как
        // от клавиатуры под ней, — а клавиатура под ней и есть: остаётся
        // пустая полоса между приставкой и настоящей клавиатурой (P310).
        made.safeAreaRegions = []
        made.view.backgroundColor = .clear
        // Простая подложка, а не клавиатурная: строка вложений
        // полупрозрачная, сквозь неё видна страница (P423).
        let box = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                       height: height))
        box.backgroundColor = .clear
        made.view.frame = box.bounds
        made.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(made.view)
        host = made
        holder = box
        // Клавиатура уходит — строки над ней гаснут сразу, а не едут с ней
        // до самого низа и пропадают там (P429). Пришла — снова видны.
        //
        // Клавиатуру смахивают пальцем — тогда iPhone молчит до самого
        // конца, и строки доезжали до низа экрана, ложились поверх нижней
        // строки разделов и только потом пропадали: это и был «скачок»
        // (запись экрана автора, P438). Теперь строки гаснут по ходу: чем
        // ниже их увели, тем прозрачнее.
        KeyboardBar.fader.box = box
        let centre = NotificationCenter.default
        centre.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil,
                           queue: .main) { _ in
            // Строки едут вниз вместе с клавиатурой до самого конца и
            // встают в нижнюю строку, где та стоит (P468). Прежде на уходе
            // их подменяли копией, которая догоняла свою анимацию: смахнули
            // клавиатуру быстро — копия отставала и висела посреди экрана
            // (запись экрана автора со 108-й). Теперь следит тот же
            // счётчик кадров, что и при смахивании пальцем, — по видимому
            // положению клавиатуры, а не по конечному.
            if KeyboardBar.fader.following { return }
            UIView.animate(withDuration: 0.12) { box.alpha = 0 }
        }
        centre.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil,
                           queue: .main) { _ in
            KeyboardBar.glide.stop()
            KeyboardBar.names.value = 1
            box.alpha = 1
        }
        centre.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil,
                           queue: .main) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
            KeyboardBar.fader.start(below: max(0, frame.height - KeyboardBar.height))
        }
        centre.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil,
                           queue: .main) { _ in
            KeyboardBar.fader.stop()
            // Ушла совсем — строк над ней нет, где бы счётчик их ни застал.
            box.alpha = 0
        }
        return box
    }

    private static let fader = Fader()

    /// Насколько видны названия разделов над клавиатурой: тают, когда
    /// клавиатуру ведут вниз пальцем (P464).
    final class Names: ObservableObject {
        @Published var value: Double = 1
    }
    static let names = Names()

    /// Следит, пока клавиатура открыта, где строки над ней: смахивают
    /// клавиатуру — строки тают, пройдя половину её высоты, гаснут совсем.
    private final class Fader: NSObject {
        weak var box: UIView?
        private var link: CADisplayLink?
        /// Высота самой клавиатуры под строками, когда она открыта.
        private var full: CGFloat = 0

        func start(below: CGFloat) {
            full = below
            box?.alpha = 1
            KeyboardBar.names.value = 1
            guard link == nil, below > 0 else { return }
            let made = CADisplayLink(target: self, selector: #selector(tick))
            made.add(to: .main, forMode: .common)
            link = made
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        /// Следит ли сейчас за строками.
        var following: Bool { link != nil && box != nil && full > 0 }

        /// Верх строк на экране — там, где их сейчас видно. Пока клавиатура
        /// уезжает анимацией, её место в окне уже конечное, а видна она
        /// ещё на пути: считать по видимым слоям (P468).
        private func shownTop(_ view: UIView) -> CGFloat {
            var y: CGFloat = 0
            var layer: CALayer? = view.layer
            while let current = layer {
                let shown = current.presentation() ?? current
                y += shown.frame.minY
                if let parent = current.superlayer {
                    y -= (parent.presentation() ?? parent).bounds.minY
                }
                layer = current.superlayer
            }
            return y
        }

        @objc private func tick() {
            guard let box, let window = box.window, full > 0 else { return }
            let top = shownTop(box) - shownTop(window)
            let frame = CGRect(x: 0, y: top, width: box.bounds.width, height: box.bounds.height)
            // Сколько клавиатуры ещё видно под строками.
            let left = window.bounds.height - frame.maxY
            // Строка вложений не тает, а встаёт в нижнюю (P464): едет с
            // клавиатурой целиком, и как только дошла до строки вложений
            // внизу страницы — уступает ей место, та точно такая же. Тают
            // только названия разделов под ней — и успевают растаять,
            // прежде чем лягут на нижнюю строку вложений (P463).
            guard let pill = KeyboardBar.glide.pillTarget else {
                box.alpha = max(0, min(1, left / (full * 0.5)))
                return
            }
            let travel = pill - (frame.minY + KeyboardBar.attachHeight / 2)
            box.alpha = travel > 0.5 ? 1 : 0
            let gap = KeyboardBar.attachHeight + KeyboardBar.sectionsHeight
            let names = Double(max(0, min(1, (travel - gap) / 60)))
            if abs(KeyboardBar.names.value - names) > 0.02 || names == 0 || names == 1,
               KeyboardBar.names.value != names {
                KeyboardBar.names.value = names
            }
        }
    }
}

struct KeyboardBarView: View {
    @ObservedObject private var day = KeyboardBar.day

    var body: some View {
        VStack(spacing: 0) {
            attachments
                .frame(height: KeyboardBar.attachHeight)
            fadingSections
                .frame(height: KeyboardBar.sectionsHeight)
        }
    }

    /// Разделы — одни названия, на том же крафте, что и внизу (P423).
    /// Пишут всегда на «Сегодня» — оно и обведено.
    var sections: some View {
        SectionsRow(current: .today) { KeyboardBar.go($0) }
            .padding(.horizontal, KeyboardBar.inset)
    }

    /// Названия над клавиатурой — с таянием, пока её ведут пальцем (P464).
    var fadingSections: some View {
        FadingSections { sections }
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
            // «Места» нет (P425): карта — в строке разделов под этой.
            // Кнопки «убрать клавиатуру» нет (P424): её смахивают вниз.
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
    }
}

/// Строка разделов над клавиатурой, которая тает вместе с её уходом (P464).
private struct FadingSections<Content: View>: View {
    @ObservedObject var names = KeyboardBar.names
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content().opacity(names.value)
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
        field.inputAccessoryView = KeyboardBar.view
        field.delegate = context.coordinator
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

/// Строка разделов над клавиатурой (P423, P425): одни названия на крафте,
/// бока скруглены, открытый раздел обведён — как в нижней строке. Над
/// клавиатурой на странице дня, на карте и в поиске.
struct SectionsRow: View {
    let current: Shell.Screen
    /// Верхняя строка-ориентир мельче нижней (P494).
    var compact = false
    let go: (Shell.Screen) -> Void

    /// Размер названий — тот же, что под значками внизу (P425).
    static let font: CGFloat = 15

    var body: some View {
        HStack(spacing: 0) {
            name(T("Сегодня", "Today"), .today)
            name(T("Календарь", "Calendar"), .calendar)
            name(T("Карта", "Map"), .map)
            name(T("Поиск", "Search"), .search)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 40 : KeyboardBar.sectionsHeight)
        .background(KraftPaper())
        // Верхняя строка — полоса от края до края (P495), нижняя над
        // клавиатурой — капсула.
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 18, style: .continuous))
    }

    private func name(_ title: String, _ target: Shell.Screen) -> some View {
        let on = target == current
        return Button { go(target) } label: {
            Text(title)
                .font(Look.sans(compact ? 14 : Self.font, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Look.accent : Look.kraftInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, compact ? 2 : 3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(on ? Color.black.opacity(0.08) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(on ? Look.accent.opacity(0.75) : .clear, lineWidth: 1.3)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Строки, втекающие в нижние, когда клавиатура уходит (P440): рисуются в
/// окне приложения поверх всего и не ловят касаний.
struct GlideView: View {
    @ObservedObject private var glide = KeyboardBar.glide

    var body: some View {
        if glide.on {
            let width = UIScreen.main.bounds.width
            let rows = KeyboardBarView()
            ZStack {
                rows.attachments
                    .frame(width: width, height: KeyboardBar.attachHeight)
                    .position(x: width / 2, y: glide.pillY)
                    .opacity(glide.pillOpacity)
                rows.sections
                    .frame(width: width, height: KeyboardBar.sectionsHeight)
                    .position(x: width / 2, y: glide.namesY)
                    .opacity(glide.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
