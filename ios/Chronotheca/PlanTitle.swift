import SwiftUI
import UIKit

/// Название дела: одна полоса текста во всю ширину строки.
///
/// Первая строка отступает вправо — под ней стоят номер, время и
/// колокольчик. Все остальные идут из-под времени, во всю ширину до
/// закладки. Иначе длинное название складывается в узкий столбик рядом с
/// двумя другими столбиками — времён и колокольчиков, — и страница читается
/// не строками, а колонками (решение P177).
///
/// Отступ первой строки задаётся числом и должен в точности равняться
/// ширине головы строки: номер, время и колокольчик стоят поверх него.
/// Поэтому ширина каждой из трёх частей задана намертво, а не меряется по
/// содержимому.
///
/// Поле одно и то же и на открытой странице, и на соседних: соседняя лишь
/// не правится. Два разных способа показать название разошлись бы в
/// переносах, и текст прыгал бы на повороте страницы (P114).
struct PlanTitle: UIViewRepresentable {

    @Binding var text: String

    /// Чьё это название: по нему точка с карты находит поле того дела,
    /// где стоял курсор (P276).
    var rowID: UUID?

    /// Отступ первой строки — ширина головы строки.
    var indent: CGFloat
    /// Отступ остальных строк — из-под времени, правее номера.
    var wrap: CGFloat

    var faded = false
    /// Можно ли ставить курсор и править.
    var editable = false
    /// Правят именно эту строку: поле берёт ввод на себя.
    var typing = false

    /// Правка кончилась: клавиатура ушла.
    var onDone: () -> Void = {}

    /// Нажат «Ввод»: ввод переходит к делу ниже.
    var onNext: () -> Void = {}
    /// Долгое нажатие на текст, пока его не правят, и ход пальца после
    /// него (P361, P362): дело поднимается в тот же миг, как нажатие стало
    /// долгим, и идёт за пальцем.
    var onLift: ((Lift) -> Void)?

    static var placeholder: String { T("Без названия", "Untitled") }
    /// На ступень крупнее прежних 15 и растёт с настройкой (P274).
    static var size: CGFloat { 16 * Prefs.textScale }
    static let spacing: CGFloat = 3

    /// Насколько вторая строка названия отступает от первой сверх обычного.
    ///
    /// Первая строка стоит рядом с номером, временем и колокольчиком, а
    /// вторая начинается под ними. Без зазора она прилипала к пунктиру
    /// времени, и «нотариусу» читалось как подпись к «09:00» (решение P186).
    static let clearance: CGFloat = 5

    /// Где проходит строчка письма, считая от верха поля. По ней голова
    /// строки садится на первую строку названия (P171).
    static var baseline: CGFloat { UIFont.systemFont(ofSize: size).ascender.rounded() }

    func makeUIView(context: Context) -> UITextView {
        // Старая раскладка текста, а не новая: только в ней можно дать
        // отдельный зазор после первой строки (P186).
        let view = TitleView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        // Строка вложений над клавиатурой (P546).
        view.inputAccessoryView = KeyboardBar.view
        view.layoutManager.delegate = context.coordinator
        view.backgroundColor = .clear
        // Ни отступов, ни полей: строчка письма должна считаться от самого
        // верха поля, иначе голова строки сядет мимо.
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Без строки подсказок слов над клавишами: полоска вложений стоит
        // вплотную к клавиатуре и не съедает экран (P409).
        view.autocorrectionType = .no
        view.inlinePredictionType = .no
        // Вставлять в название картинки и вложения нельзя: в файле это
        // обычная строка (P161).
        view.allowsEditingTextAttributes = false
        // Снимок, который несут по плану, ложится под дело, а не буквами в
        // его название (P358): поле названия переносов не принимает.
        if let drop = view.textDropInteraction { view.removeInteraction(drop) }
        // Поле меряется по тексту и не прокручивает в себе ничего: строка
        // плана растёт вниз вместе с названием.
        view.isScrollEnabled = false
        // Обычный «Ввод» со стрелкой, а не синее «Готово» с галочкой:
        // клавиша уводит на строку ниже, как ей и положено (решение P180).
        view.returnKeyType = .default
        context.coordinator.view = view
        // Касание по точке в названии открывает карту на ней (P256).
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.35
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.open = context.environment.openPoint
        (view as? TitleView)?.indent = indent
        view.isEditable = editable
        view.isSelectable = editable
        apply(to: view, context.coordinator)

        if typing, !view.isFirstResponder {
            view.becomeFirstResponder()
            let end = NSRange(location: (view.text as NSString).length, length: 0)
            view.selectedRange = end
        }
        if !typing, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let занято = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: занято.height.rounded(.up))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Вид

    /// Что показываем: своё название, а у пустого дела, пока его не правят, —
    /// бледное «Без названия».
    private var shown: String {
        editable ? text : (text.isEmpty ? Self.placeholder : text)
    }

    private var ink: UIColor {
        UIColor(faded || text.isEmpty ? Look.inkFaint : Look.ink)
    }

    private var style: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = wrap
        // Расстояние между строками задаёт попечитель раскладки — у первой
        // строки оно своё. Здесь ноль, чтобы оно не сложилось дважды.
        paragraph.lineSpacing = 0
        return [
            .font: UIFont.systemFont(ofSize: Self.size),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
    }

    /// Название с точками-кнопочками: координаты в строке дела стоят
    /// кнопочкой, как в дневнике, а в файле — той же ссылкой (P256).
    func styled() -> NSAttributedString {
        let out = NSMutableAttributedString(string: shown, attributes: style)
        for (range, point) in Geo.points(inText: shown).reversed() {
            let token = (shown as NSString).substring(with: range)
            out.replaceCharacters(in: range, with: Self.chip(point, token: token, style: style))
        }
        return out
    }

    static func chip(_ point: GeoPoint, token: String,
                     style: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let piece = NSMutableAttributedString(attachment: PointChip(tile: point))
        let whole = NSRange(location: 0, length: piece.length)
        piece.addAttributes(style, range: whole)
        piece.addAttribute(DiaryEditor.lineKey, value: token, range: whole)
        return piece
    }

    /// Переписать содержимое, не сдвинув курсор.
    private func apply(to view: UITextView, _ coordinator: Coordinator) {
        // Оформление набора ставится всегда, даже когда текст не менялся:
        // у пустого поля только по нему и видно, где начинать строку.
        view.typingAttributes = style
        // Кнопочки каждый раз рисуются заново и на равенство не проверишь —
        // сверяется текст и то, от чего зависит вид.
        let look = "\(indent)|\(wrap)|\(faded)|\(text.isEmpty)|\(editable)"
        guard DiaryEditor.plain(view.attributedText) != shown || coordinator.look != look
        else { return }
        coordinator.look = look
        let fresh = styled()
        let было = view.selectedRange
        view.attributedText = fresh
        view.typingAttributes = style
        let длина = (view.text as NSString).length
        view.selectedRange = NSRange(location: min(было.location, длина), length: 0)
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate, NSLayoutManagerDelegate,
                             UIGestureRecognizerDelegate {
        var parent: PlanTitle
        weak var view: UITextView?
        var open: ((GeoPoint) -> Void)?
        /// С каким видом название нарисовано в последний раз.
        var look = ""

        /// Какая точка под пальцем, если под ним кнопочка.
        func point(at g: UIGestureRecognizer) -> GeoPoint? {
            guard let view = g.view as? UITextView, view.textStorage.length > 0 else { return nil }
            var p = g.location(in: view)
            p.x -= view.textContainerInset.left
            p.y -= view.textContainerInset.top
            let layout = view.layoutManager
            let glyph = layout.glyphIndex(for: p, in: view.textContainer)
            let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                          in: view.textContainer)
            guard box.insetBy(dx: -4, dy: -6).contains(p) else { return nil }
            let i = layout.characterIndexForGlyph(at: glyph)
            guard i < view.textStorage.length,
                  let token = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                         effectiveRange: nil) as? String
            else { return nil }
            return Geo.points(inText: token).first?.point
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Долгое нажатие — только пока текст не правят: при правке оно
            // принадлежит курсору и лупе.
            if g is UILongPressGestureRecognizer {
                return parent.onLift != nil && view?.isFirstResponder == false
            }
            return open != nil
        }

        /// Где палец поднял дело — в координатах окна: поле едет вместе с
        /// делом, и мерка от него дёргала бы дело взад-вперёд (P195).
        private var start: CGPoint = .zero

        @objc func held(_ g: UILongPressGestureRecognizer) {
            let spot = g.location(in: nil)
            let way = CGSize(width: spot.x - start.x, height: spot.y - start.y)
            switch g.state {
            case .began:
                start = spot
                parent.onLift?(.began)
            case .changed:
                parent.onLift?(.moved(way))
            case .ended:
                parent.onLift?(.ended(way))
            default:
                parent.onLift?(.cancelled)
            }
        }

        /// Поднятое дело ведёт палец один: страница под ним не
        /// прокручивается и не листается (P362).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UILongPressGestureRecognizer)
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let point = point(at: g) else { return }
            open?(point)
        }

        init(_ parent: PlanTitle) { self.parent = parent }

        /// После первой строки — зазор, если за ней есть вторая: вторая
        /// начинается под головой строки и не должна к ней прилипать.
        /// Одиночное название строку не удлиняет (решение P186).
        func layoutManager(_ layoutManager: NSLayoutManager,
                           lineSpacingAfterGlyphAt glyphIndex: Int,
                           withProposedLineFragmentRect rect: CGRect) -> CGFloat {
            let первая = rect.minY < 1
            let дальше = glyphIndex + 1 < layoutManager.numberOfGlyphs
            return первая && дальше ? PlanTitle.spacing + PlanTitle.clearance : PlanTitle.spacing
        }

        /// Буквы, набранные сразу за кнопочкой, — обычные буквы, а не
        /// продолжение точки.
        func textViewDidChangeSelection(_ view: UITextView) {
            if view.typingAttributes[DiaryEditor.lineKey] != nil
                || view.typingAttributes[.attachment] != nil {
                view.typingAttributes = parent.style
            }
        }

        func textViewDidChange(_ view: UITextView) {
            parent.text = DiaryEditor.plain(view.attributedText)
        }

        func textViewDidEndEditing(_ view: UITextView) { parent.onDone() }

        /// В названии не бывает перевода строки.
        ///
        /// В файле дело занимает ровно строку: перевод разорвал бы его
        /// надвое, и хвост осел бы отдельной непонятой строкой вместе с
        /// напоминанием. Но клавиша «Ввод» и не должна ничего рвать — она
        /// уводит на строку ниже, к следующему делу (P180). Вставленный из
        /// буфера перевод строки становится пробелом (решение P172).
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text.contains(where: \.isNewline) else { return true }
            if text.allSatisfy(\.isNewline) {
                parent.onNext()
                return false
            }
            let одной = String(text.map { $0.isNewline ? " " : $0 })
            if let target = Range(range, in: view.text) {
                view.text.replaceSubrange(target, with: одной)
                view.selectedRange = NSRange(location: range.location
                                             + (одной as NSString).length, length: 0)
                parent.text = view.text
            }
            return false
        }
    }
}

/// Поле названия, у которого курсор пустой строки стоит там, где начнётся
/// текст, а не под номером.
///
/// Пока в поле ни буквы, отступу первой строки не к чему приложиться, и
/// курсор вставал у самого левого края — под номером, временем и
/// колокольчиком. Человек заводил дело и не видел, где печатать
/// (решение P193).
final class TitleView: UITextView {
    var indent: CGFloat = 0

    override func caretRect(for position: UITextPosition) -> CGRect {
        var r = super.caretRect(for: position)
        if text.isEmpty, r.minX < indent { r.origin.x = indent }
        return r
    }
}

/// Что делать по касанию на точку в тексте: открыть карту на ней. Задано
/// только на открытой странице (P256).
private struct OpenPointKey: EnvironmentKey {
    static let defaultValue: ((GeoPoint) -> Void)? = nil
}

extension EnvironmentValues {
    var openPoint: ((GeoPoint) -> Void)? {
        get { self[OpenPointKey.self] }
        set { self[OpenPointKey.self] = newValue }
    }
}
