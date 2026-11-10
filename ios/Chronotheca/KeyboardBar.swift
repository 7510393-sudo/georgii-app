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

    /// Высота строки над разделами — в ней одна «＋» справа (P423, P615).
    static let attachHeight: CGFloat = 44

    /// Где по высоте экрана полоска вложений открытой страницы — её
    /// сообщает сама полоска. Снимок, отпущенный над ней, возвращается в
    /// ленту (P547). Прежнее «втекание» строк (P440) убрано (P551).
    static var pillTarget: CGFloat?

    private static var host: UIHostingController<KeyboardBarView>?

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
        let box = PassBox(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                        height: accessoryHeight))
        box.backgroundColor = .clear
        made.view.frame = box.bounds
        made.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(made.view)
        host = made
        holder = box
        // Перед каждым подъёмом клавиатуры строка перерисовывается заново и
        // сразу (P674): приставка вне экрана не слышит смены гаммы и
        // всплывала в цвете прежней; а нарисованная по ходу подъёма, она
        // проступала уже после клавиатуры.
        _ = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            refresh()
        }
        return box
    }

    /// Перерисовать строку в нынешней гамме — сейчас, до хода клавиатуры.
    static func refresh() {
        guard let host else { return }
        host.rootView = KeyboardBarView(palette: UserDefaults.standard.string(forKey: Prefs.calendarTint) ?? "")
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    /// Высота приставки — строка с «＋» и воздух (P799: строки разделов
    /// над клавиатурой больше нет).
    static let accessoryHeight: CGFloat = attachRoom
    /// Строка вложений с воздухом над и под ней.
    static let attachRoom: CGFloat = attachHeight + 10
}

/// Приставка, сквозь которую видно и можно коснуться записи (P764).
///
/// Строка с «＋» прозрачна во всю ширину, и текст записи проступает под
/// ней, но касание левее «＋» прежде съедала сама приставка — курсор не
/// вставал в нижнюю видимую строку. Теперь там касание уходит странице;
/// «＋» и строка разделов отвечают по-прежнему.
final class PassBox: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // «＋» — 44 точки у правого края с отступом 12, и немного воздуха.
        let plusLeft = bounds.width - 12 - 44 - 8
        if point.y < KeyboardBar.attachRoom, point.x < plusLeft { return false }
        return super.point(inside: point, with: event)
    }
}

struct KeyboardBarView: View {
    /// Гамма, в которой строка нарисована (P674): другая гамма — другой вид,
    /// и строка перерисовывается.
    var palette = ""

    var body: some View {
        // Над клавиатурой — только «＋» справа (P799, вместо строки разделов
        // P613): разделы листаются вбок, а пока пишут, экран нужнее.
        attachments
            .frame(height: KeyboardBar.attachHeight)
            .padding(.top, 6)
            .padding(.bottom, 4)
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
            // Стеклянный кружок, как лупа картотеки (P860, автор по 259:
            // «плюс уезжает от нижней кожаной строки» — кожа ему больше не
            // родня; прежде — тиснение на коже, как у строки).
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Look.inkSoft)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 1.5, y: 1.5)
        }
        .accessibilityLabel(T("Приложить", "Attach"))
        .accessibilityIdentifier(id)
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
        // Тот же шрифт, что у заголовка на соседних страницах (P759).
        let bold = Prefs.titleUIFont(size)
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
        weak var field: UITextField?

        init(_ parent: TitleLine) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardMoved(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            self.field = field
            if !parent.focused { parent.focused = true }
        }

        /// Заголовок, который пишут, не прячется под клавиатурой и строкой
        /// над ней (P671): прежде страница поднималась, только когда «Ввод»
        /// уводил в запись. Страница подъезжает ровно настолько, насколько
        /// заголовок зашёл под клавиатуру, — как у записи (P175).
        @objc private func keyboardMoved(_ note: Notification) {
            guard let field, field.isFirstResponder, let window = field.window,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let top = window.convert(frame, from: nil).minY
            DispatchQueue.main.async {
                let строка = field.convert(field.bounds, to: window)
                let ниже = строка.maxY + 16 - top
                guard ниже > 0 else { return }
                var выше = field.superview
                while let здесь = выше, !(здесь is UIScrollView) { выше = здесь.superview }
                guard let страница = выше as? UIScrollView else { return }
                let предел = max(0, страница.contentSize.height + страница.adjustedContentInset.bottom
                                 - страница.bounds.height)
                let куда = min(страница.contentOffset.y + ниже, предел)
                guard куда > страница.contentOffset.y else { return }
                страница.setContentOffset(CGPoint(x: страница.contentOffset.x, y: куда), animated: true)
            }
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
    /// На пару миллиметров тоньше прежних 55 (P613); под крупные значки
    /// тиснения — 48 (P760).
    static let height: CGFloat = 48
    /// Значки — 35 × эта доля (прежде 0,85; 0,72 до P760 — тиснение
    /// крупнее читается).
    static let scale: CGFloat = 0.79
    /// Названия (прежде 15 × 0,85; 12,5 до P760).
    static let font: CGFloat = 13.5

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
