import SwiftUI
import UIKit

/// Строка «Как прошло?»: название дела и ответ одной полосой текста.
///
/// Раньше название стояло слева, а ответ — справа от него отдельным полем,
/// и длинный ответ складывался в узкий столбик под самим собой. Теперь это
/// одна полоса, как строка в тетради: название дела, двоеточие и дальше
/// ответ, который, дойдя до края, продолжается с начала следующей строки
/// (решение P185).
///
/// Название — часть того же текста, но его не сотрёшь и не поправишь:
/// курсор за него не заходит, правка его не касается. Отвечать можно
/// только после двоеточия.
///
/// Поле одно и то же и на открытой странице, и на соседних: соседняя лишь
/// не правится. Иначе строки разошлись бы в переносах, и текст прыгал бы
/// на повороте страницы (P114).
struct AskLine: UIViewRepresentable {

    /// Название дела с двоеточием.
    let label: String
    @Binding var answer: String

    var editable = false
    /// Ввод перешёл сюда: поле берёт его на себя.
    var typing = false

    var onBegin: () -> Void = {}
    var onDone: () -> Void = {}
    /// Нажат «Ввод»: ввод переходит к следующему ответу или к записи.
    var onNext: () -> Void = {}

    /// Где лежит снимок из ответа. Задано — ответ рисует снимки
    /// картинками, голос и файлы — кнопочками, точки — булавками прямо в
    /// строке, как запись ниже (P407). Задаётся и соседним страницам:
    /// иначе строки разошлись бы на повороте (P114).
    var resolve: ((String) -> URL?)?
    /// Касание по снимку, голосу или файлу в ответе — открыть.
    var onOpen: ((String) -> Void)?
    /// Касание по точке в ответе — карта.
    var onOpenPoint: ((GeoPoint) -> Void)?
    /// Долгое нажатие на снимок, голос или файл в ответе — вернуть в
    /// полоску внизу страницы (P407).
    var onReturn: ((String) -> Void)?

    static var size: CGFloat { DiaryView.size }
    static let placeholder = "…"

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        // Строка вложений над клавиатурой (P546).
        view.inputAccessoryView = KeyboardBar.view
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Без строки подсказок слов над клавишами: полоска вложений стоит
        // вплотную к клавиатуре и не съедает экран (P409).
        view.autocorrectionType = .no
        view.inlinePredictionType = .no
        view.allowsEditingTextAttributes = false
        view.isScrollEnabled = false
        view.returnKeyType = .default
        context.coordinator.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.45
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = view
        view.isEditable = editable
        view.isSelectable = editable
        if editable { AskLine.lines.add(context.coordinator) } else { AskLine.lines.remove(context.coordinator) }
        context.coordinator.apply(to: view)

        if typing, editable, !view.isFirstResponder {
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
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

    /// Тот же засечный шрифт и та же подгонка под системный размер текста,
    /// что у записи ниже: строки «Как прошло?» и запись — одна тетрадь.
    static var font: UIFont {
        let base = Prefs.serifUIFont(size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    static func style(_ color: Color) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(for: size * 0.24)
        return [.font: font, .foregroundColor: UIColor(color), .paragraphStyle: paragraph]
    }

    /// Ответ на экране: снимки — картинками, голос и файлы — кнопочками,
    /// точки — булавками, прямо в строке (P407). В файле ответ остаётся
    /// одной строкой «- Дело: ответ ![](…)» (P172): ссылки — те же, что в
    /// записи, их понимает любой редактор разметки.
    static func dressed(_ answer: String, resolve: ((String) -> URL?)?) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(string: answer, attributes: style(Look.ink))
        guard let resolve, answer.contains("](") || answer.contains("geo:") else { return out }
        let ns = answer as NSString
        var found: [(range: NSRange, chip: NSTextAttachment, key: NSAttributedString.Key, value: String)] = []
        for piece in Diary.anywhere(in: answer) where Diary.kind(of: piece.link) == .photo {
            found.append((piece.range, PhotoAttachment(link: piece.link, url: resolve(piece.link)),
                          DiaryEditor.photoKey, piece.link))
        }
        for m in DiaryEditor.fileLink.matches(in: answer, range: NSRange(location: 0, length: ns.length)) {
            var link = ns.substring(with: m.range(at: 1))
            if link.hasPrefix("<"), link.hasSuffix(">") { link = String(link.dropFirst().dropLast()) }
            guard !link.contains("://"), !link.hasPrefix("geo:"), Diary.kind(of: link) != .photo
            else { continue }
            found.append((m.range, FileChip(link: link), DiaryEditor.lineKey, ns.substring(with: m.range)))
        }
        for (r, point) in Geo.points(inText: answer) {
            found.append((r, PointChip(tile: point), DiaryEditor.lineKey, ns.substring(with: r)))
        }
        // С конца к началу: замена не сдвигает того, что ещё впереди.
        var edge = ns.length
        for piece in found.sorted(by: { $0.range.location > $1.range.location })
        where NSMaxRange(piece.range) <= edge {
            let chip = NSMutableAttributedString(attachment: piece.chip)
            let whole = NSRange(location: 0, length: chip.length)
            chip.addAttributes(style(Look.ink), range: whole)
            chip.addAttribute(piece.key, value: piece.value, range: whole)
            out.replaceCharacters(in: piece.range, with: chip)
            edge = piece.range.location
        }
        return out
    }

    // MARK: - Перенос в ответ (P407)

    /// Строки «Как прошло?» открытой страницы — в них несут вложения из
    /// полоски и из записи.
    static let lines = NSHashTable<Coordinator>.weakObjects()

    /// Строка ответа под пальцем (в окне).
    static func under(_ global: CGPoint) -> Coordinator? {
        lines.allObjects.first { line in
            guard line.parent.editable, line.parent.resolve != nil,
                  let view = line.view, let window = view.window else { return false }
            return view.convert(view.bounds, to: window).insetBy(dx: -4, dy: -8).contains(global)
        }
    }

    /// Несут вложение: строка под пальцем показывает его у себя в конце,
    /// прочие — какими были. `true` — палец над строкой ответа.
    @discardableResult
    static func carry(_ piece: String, at global: CGPoint) -> Bool {
        let target = under(global)
        for line in lines.allObjects where line !== target { line.carryOut() }
        target?.carryIn(piece)
        return target != nil
    }

    /// Отпустили: вложение встаёт в ответ под пальцем. `true` — встало.
    @discardableResult
    static func carryEnd(at global: CGPoint) -> Bool {
        let target = under(global)
        for line in lines.allObjects where line !== target { line.carryOut() }
        return target?.carryEnd() ?? false
    }

    static func carryOutAll() {
        for line in lines.allObjects { line.carryOut() }
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: AskLine
        private var clamping = false

        init(_ parent: AskLine) {
            self.parent = parent
            super.init()
            let вести = NotificationCenter.default
            вести.addObserver(self, selector: #selector(keyboardMoved(_:)),
                              name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            вести.addObserver(self, selector: #selector(keyboardGone(_:)),
                              name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        /// Верх клавиатуры вместе со строкой кнопок над ней — в окне.
        private var keyboardTop: CGFloat?
        weak var view: UITextView?

        @objc private func keyboardMoved(_ note: Notification) {
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let window = view?.window else { return }
            keyboardTop = window.convert(frame, from: nil).minY
        }

        @objc private func keyboardGone(_ note: Notification) { keyboardTop = nil }

        /// Строка, в которой пишут, не уходит под клавиатуру и строку кнопок
        /// над ней (P406): страница подъезжает ровно настолько, насколько
        /// курсор зашёл под них, — как у записи ниже (P175).
        func showCaret() {
            guard let view, view.isFirstResponder, let window = view.window,
                  let top = keyboardTop, let end = view.selectedTextRange?.end else { return }
            let курсор = view.convert(view.caretRect(for: end), to: window)
            let ниже = курсор.maxY + 16 - top
            guard ниже > 0 else { return }
            var выше = view.superview
            while let здесь = выше, !(здесь is UIScrollView) { выше = здесь.superview }
            guard let страница = выше as? UIScrollView else { return }
            let предел = max(0, страница.contentSize.height + страница.adjustedContentInset.bottom
                             - страница.bounds.height)
            let куда = min(страница.contentOffset.y + ниже, предел)
            guard куда > страница.contentOffset.y else { return }
            страница.setContentOffset(CGPoint(x: страница.contentOffset.x, y: куда), animated: true)
        }

        /// Сколько знаков занимает название с пробелом за ним.
        var prefix: Int { ((parent.label + " ") as NSString).length }

        /// Собрать строку: бледное название, ответ чернилами, а у пустого
        /// ответа, пока в нём не пишут, — бледное многоточие.
        func styled(for view: UITextView, answer: String? = nil) -> NSAttributedString {
            let answer = answer ?? parent.answer
            let out = NSMutableAttributedString(string: parent.label + " ",
                                                attributes: AskLine.style(Look.hint))
            if answer.isEmpty && !view.isFirstResponder {
                out.append(NSAttributedString(string: AskLine.placeholder,
                                              attributes: AskLine.style(Look.hint)))
            } else {
                out.append(AskLine.dressed(answer, resolve: parent.resolve))
            }
            return out
        }

        /// Что сейчас в поле — так, как легло бы в файл.
        private func shown(_ view: UITextView) -> String {
            DiaryEditor.plain(view.attributedText)
        }

        /// Переписать строку, не сдвинув курсор. Строка, где уже стоит то
        /// же самое, не переписывается: снимки в ней не мигают, а набор
        /// не сбивается (P407).
        func apply(to view: UITextView) {
            guard carried == nil else { return }
            let empty = parent.answer.isEmpty && !view.isFirstResponder
            let wanted = parent.label + " " + (empty ? AskLine.placeholder : parent.answer)
            if view.attributedText.length > 0, empty == placeholderShown,
               (view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont) == AskLine.font,
               shown(view) == wanted { return }
            let было = view.selectedRange
            view.attributedText = styled(for: view)
            placeholderShown = empty
            view.typingAttributes = AskLine.style(Look.ink)
            DiaryEditor.loadPhotos(in: view)
            let длина = (view.text as NSString).length
            view.selectedRange = NSRange(location: min(max(было.location, prefix), длина),
                                         length: 0)
        }

        /// В строке сейчас бледное многоточие пустого ответа.
        private var placeholderShown = false

        // MARK: Перенос в ответ (P407)

        /// Строка до переноса и ответ, каким он станет.
        private var before: NSAttributedString?
        private(set) var carried: String?

        func carryIn(_ piece: String) {
            guard let view, carried == nil else { return }
            before = view.attributedText.copy() as? NSAttributedString
            let next = Diary.adding(piece, to: parent.answer)
            carried = next
            view.attributedText = styled(for: view, answer: next)
            DiaryEditor.loadPhotos(in: view)
            view.invalidateIntrinsicContentSize()
            Feel.light()
        }

        func carryOut() {
            guard let view, carried != nil else { return }
            if let before { view.attributedText = before }
            before = nil
            carried = nil
            view.invalidateIntrinsicContentSize()
        }

        func carryEnd() -> Bool {
            guard let next = carried else { return false }
            before = nil
            carried = nil
            parent.answer = next
            if let view { apply(to: view) }
            return true
        }

        // MARK: Касание и долгое нажатие по вложению

        /// Вложение под пальцем: строка, как в файле, и место в поле.
        private func object(at at: CGPoint, in view: UITextView) -> (line: String, photo: Bool)? {
            guard let position = view.closestPosition(to: at) else { return nil }
            let storage = view.textStorage
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            for i in [offset, offset - 1] where i >= 0 && i < storage.length {
                guard storage.attribute(.attachment, at: i, effectiveRange: nil) != nil,
                      let start = view.position(from: view.beginningOfDocument, offset: i),
                      let end = view.position(from: start, offset: 1),
                      let range = view.textRange(from: start, to: end),
                      view.firstRect(for: range).insetBy(dx: -4, dy: -4).contains(at)
                else { continue }
                if let link = storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) as? String {
                    return (link, true)
                }
                if let line = storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) as? String {
                    return (line, false)
                }
            }
            return nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view, parent.resolve != nil else { return false }
            if g is UILongPressGestureRecognizer {
                guard parent.editable, parent.onReturn != nil,
                      let hit = object(at: touch.location(in: view), in: view) else { return false }
                return hit.photo || Diary.picture(in: hit.line) != nil
            }
            return object(at: touch.location(in: view), in: view) != nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UILongPressGestureRecognizer)
        }

        /// Касание по снимку или файлу — открыть; по точке — карта.
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view, let hit = object(at: g.location(in: view), in: view) else { return }
            if hit.photo {
                parent.onOpen?(hit.line)
            } else if let point = Geo.point(in: hit.line) ?? Geo.points(inText: hit.line).first?.point {
                parent.onOpenPoint?(point)
            } else if let link = Diary.picture(in: hit.line) {
                parent.onOpen?(link)
            }
        }

        /// Долгое нажатие на снимок или файл — назад в полоску (P407).
        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let view,
                  let hit = object(at: g.location(in: view), in: view),
                  let link = hit.photo ? hit.line : Diary.picture(in: hit.line)
            else { return }
            // Лупа и выделение поля отпускают палец.
            for other in view.gestureRecognizers ?? [] where other !== g && other.isEnabled {
                other.isEnabled = false
                other.isEnabled = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onReturn?(link)
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            self.view = view
            apply(to: view)   // многоточие уходит, как только начали писать
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showCaret() }
            view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
            parent.onBegin()
        }

        func textViewDidEndEditing(_ view: UITextView) {
            apply(to: view)   // у пустого ответа снова многоточие
            parent.onDone()
        }

        func textViewDidChange(_ view: UITextView) {
            // Снимки и точки в поле — по знаку, в файле — ссылками (P407).
            let всё = shown(view) as NSString
            parent.answer = всё.length > prefix ? всё.substring(from: prefix) : ""
            view.typingAttributes = AskLine.style(Look.ink)
            self.view = view
            DispatchQueue.main.async { [weak self] in self?.showCaret() }
        }

        /// Курсор за название не заходит: писать можно только после
        /// двоеточия.
        func textViewDidChangeSelection(_ view: UITextView) {
            // Буква за снимком не берёт его метку: иначе в файл ушёл бы
            // второй такой же снимок (P407).
            view.typingAttributes = AskLine.style(Look.ink)
            guard !clamping, view.isFirstResponder else { return }
            let r = view.selectedRange
            guard r.location < prefix else { return }
            clamping = true
            let конец = r.location + r.length
            view.selectedRange = NSRange(location: prefix, length: max(0, конец - prefix))
            clamping = false
        }

        /// Название не правится. «Ввод» уводит дальше, а не рвёт ответ:
        /// в файле ответ — одна строка «- Дело: ответ» (P172, P180).
        /// Перевод строки, вставленный из буфера, становится пробелом.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard range.location >= prefix else { return false }
            // Снимок, голос и файл клавишей не стираются и набранным не
            // заменяются — их уводят долгим нажатием в полоску, как в
            // записи только крестиком (P392, P407). Точку стереть можно:
            // она — слово в строке.
            let storage = view.textStorage
            if NSMaxRange(range) <= storage.length {
                for i in range.location..<NSMaxRange(range)
                where storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
                    || (storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) as? String)
                        .map({ Diary.picture(in: $0) != nil }) == true {
                    return false
                }
            }
            guard text.contains(where: \.isNewline) else { return true }
            if text.allSatisfy(\.isNewline) {
                parent.onNext()
                return false
            }
            let одной = String(text.map { $0.isNewline ? " " : $0 })
            // Правка — в самом тексте поля, а не подменой всего текста:
            // снимки и точки в ответе остаются на месте (P407).
            guard NSMaxRange(range) <= view.textStorage.length else { return false }
            view.textStorage.replaceCharacters(in: range, with: NSAttributedString(
                string: одной, attributes: AskLine.style(Look.ink)))
            view.selectedRange = NSRange(location: range.location
                                         + (одной as NSString).length, length: 0)
            textViewDidChange(view)
            apply(to: view)
            return false
        }
    }
}
