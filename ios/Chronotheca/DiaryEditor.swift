import SwiftUI
import UIKit

/// Поле записи дневника.
///
/// Обычного текстового поля здесь мало по двум причинам, и обе — решения,
/// а не украшения. Отметка времени в начале строки должна быть бледнее и
/// мельче текста: она служебная, читать надо не её. И первая буква после
/// отметки должна вставать заглавной — человек начинает предложение, а не
/// продолжает строку.
///
/// Оба правила живут здесь, а не в разметке, потому что внутри одного поля
/// разным кускам текста нужен разный вид.
struct DiaryEditor: UIViewRepresentable {

    @Binding var text: String
    var size: CGFloat = 15.5
    /// Засечный — для дневника, обычный — для подробностей дела.
    var serif = true
    /// Отметки времени бледнее и мельче. В подробностях они ни к чему.
    var stamped = true
    /// Соседние страницы показывают то же поле, только без правки: иначе
    /// рядом стоят два разных способа набрать текст, и строки на повороте
    /// расходятся (P114).
    var editable = true
    /// Просьба поставить курсор в конец текста при ближайшем обновлении.
    /// Её подаёт отметка времени: её ставит приложение, а писать после неё
    /// человеку — и тянуться до конца предыдущего куска он не должен.
    var caretToEnd: Binding<Bool> = .constant(false)

    /// Просьба взять ввод на себя. Её подаёт «Ввод» в заголовке дня:
    /// заголовок дописан, дальше человек пишет запись, и тянуться к ней
    /// пальцем он не должен (решение P40).
    var startEditing: Binding<Bool> = .constant(false)

    var onFocus: () -> Void = {}

    /// Поле меряется по тексту и растёт вместе с ним.
    ///
    /// Так стоит запись дневника: страница едет целиком, а поле внутри
    /// себя ничего не прокручивает. В подробностях дела наоборот — поле
    /// занимает отведённую коробку и прокручивает текст в себе.
    var grows = false

    /// Сколько поле просит себе, даже когда текста в нём нет. Нужно только
    /// там, где поле меряется по тексту.
    var minHeight: CGFloat = 0

    /// Пустое место под текстом внутри самого поля: касание туда ставит
    /// курсор в конец записи — открыл, коснулся, пишешь (P346).
    var room: CGFloat = 0

    /// Где лежит снимок, на который ссылается строка `![](…)`. Задано —
    /// значит поле рисует такие строки картинками (решение P204).
    var resolve: ((String) -> URL?)?

    /// Касание по снимку в тексте — открыть его (P216). Пусто — снимки не
    /// открываются: так на соседних страницах.
    var onOpenPhoto: ((String) -> Void)?
    /// Снимок из текста отпустили над полоской внизу — вернуть его туда
    /// (P272). Пусто — возвращать некуда.
    var onReturnPhoto: ((String) -> Void)?
    /// Касание по точке в тексте — открыть карту на ней (P213).
    var onOpenPoint: ((GeoPoint) -> Void)?
    /// Точку из текста отпустили над заголовком дня — она переходит туда
    /// (P358). Строка точки, как в файле.
    var onPointToTitle: ((String) -> Void)?

    /// Где на экране заголовок дня открытой страницы — туда можно бросить
    /// точку из текста (P358). Пусто — заголовка не видно.
    static var titleZone: CGRect = .null
    /// Снимок или точку в тексте можно взять долгим нажатием и перенести
    /// в другое место записи (P226) — без всякого режима (P362). Вид от
    /// этого не меняется: соседняя страница рисуется так же (P114).
    var moving = false
    /// Поле взяло ввод или отпустило его (P240).
    var onEditing: ((Bool) -> Void)?
    /// Отметка времени, ждущая первой буквы новой строки (P403): `nil` —
    /// не ждёт.
    var takeStamp: (() -> String?)? = nil
    /// Набрали текст в самом конце записи (P519): от этого отсчитывается час до
    /// новой отметки времени. Правка раньше по тексту — не в счёт.
    var onWrite: (() -> Void)? = nil
    /// Дело плана под пальцем (P409): снимок или точку из записи несут в
    /// план. `nil` — палец не над планом.
    var planTarget: ((CGPoint) -> UUID?)? = nil
    /// Над каким делом сейчас несут и снимок ли это: план подсвечивает
    /// дело и раздвигает строки.
    var onPlanHover: ((UUID?, Bool) -> Void)? = nil
    /// Отпустили над делом — встать под него. `true` — встало.
    var onToPlan: ((String, UUID) -> Bool)? = nil
    /// Крестик у снимка → «удалить файл» (P409): в корзину на 30 дней.
    var onDeleteAttachment: ((String) -> Void)? = nil

    /// Отметка времени в начале строки: «08:15 » и дальше текст.
    /// В прошедший день за временем идёт дата, когда писали:
    /// «08:15 25.09.26 » (P227, P232).
    static let stamp = try! NSRegularExpression(
        pattern: #"^(\d{2}:\d{2}(?: \d{2}\.\d{2}\.\d{2})?)[  ]"#)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        // Метка для проверок движения (P552).
        view.accessibilityIdentifier = "diaryText"
        view.delegate = context.coordinator
        // Над клавиатурой — строка вложений, частью самой клавиатуры, как в
        // Diarium (P546); лента превью — конец страницы, клавиатура её
        // закрывает, пока страницу не подняли.
        view.inputAccessoryView = KeyboardBar.view
        // Своё перетаскивание поля выключено (P374): оно перехватывало
        // долгое нажатие на снимок или точку, поднимало свою копию и, не
        // найдя, куда её положить, возвращало назад. Переносит только своё
        // долгое нажатие — с раздвиганием текста.
        view.textDragInteraction?.isEnabled = false
        context.coordinator.view = view
        // Касание по снимку или точке в тексте открывает их, а не ставит
        // курсор рядом (P213, P216).
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let carry = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.carried(_:)))
        carry.minimumPressDuration = 0.25
        carry.delegate = context.coordinator
        view.addGestureRecognizer(carry)
        // Подержали вложение и отпустили — оно не открывается (P561).
        // Касание по тексту не ждёт: там долгое нажатие сразу не берётся.
        tap.require(toFail: carry)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Без строки подсказок слов над клавишами: полоска вложений стоит
        // вплотную к клавиатуре и не съедает экран (P409).
        view.autocorrectionType = .no
        view.inlinePredictionType = .no
        // Вставлять в запись картинки и вложения нельзя: файл должен
        // читаться обычным текстовым редактором. Разрешённое оформление
        // порождает в тексте знак-заместитель, который виден как «OBJ»
        // в пунктирной рамке (решение P161).
        view.allowsEditingTextAttributes = false
        // Клавиатура уезжает движением пальца вниз по тексту.
        view.keyboardDismissMode = .interactive
        // Растущее поле не отбирает движение пальца у страницы: прокручивать
        // ему нечего, а пружинило бы оно вместо неё (решение P175).
        view.alwaysBounceVertical = !grows
        view.scrollsToTop = false
        view.isEditable = editable
        view.isSelectable = editable
        // Прокрутка включена всегда, даже там, где не правят. Без прокрутки
        // поле само подбирает себе высоту, и строки ложатся не так, как в
        // таком же поле рядом: на повороте страницы текст перескакивает из
        // одной строки в две. Одинаковое поле — одинаковые строки (P114).
        view.isScrollEnabled = true
        return view
    }

    /// Поле записи открытого дня — в него несут из полоски (P380).
    static weak var active: Coordinator?

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if editable && grows { DiaryEditor.active = context.coordinator }
        view.isEditable = editable
        view.isSelectable = editable
        context.coordinator.resolve = resolve

        // Поле сверяется с записью без знаков-заместителей. Пока идёт
        // диктовка, система держит в поле свой временный знак; переписать
        // из-за него поле — вырвать знак у неё из рук, и он остаётся в
        // тексте «OBJ» (решение P197).
        if context.coordinator.previewing {
            // Идёт перенос — в поле показано, как ляжет взятое; запись
            // поменяется, когда палец отпустят.
        } else if DiaryEditor.plain(view.attributedText) != text || view.attributedText.length == 0 {
            let selection = view.selectedRange
            view.attributedText = Self.styled(text, size: size, serif: serif, stamped: stamped,
                                              resolve: resolve)
            view.typingAttributes = Self.body(size, serif: serif)
            view.selectedRange = selection.location <= (view.text as NSString).length
                ? selection
                : NSRange(location: (view.text as NSString).length, length: 0)
            context.coordinator.loadPhotos()
        } else {
            context.coordinator.restyle(view)
        }

        if startEditing.wrappedValue {
            // Сбрасываем просьбу сразу. Фокус берём не здесь же, а на
            // следующем обороте: `becomeFirstResponder` внутри этого же
            // прохода перерисовки зовёт `onFocus` (он ставит отметку
            // времени) прямо сейчас, но запись обновится только со
            // следующим проходом — а он поверх свежего текста восстановит
            // старое, ещё безвременное место курсора. Вне прохода перерисовки
            // отметка и перевод курсора в конец успевают попасть в один и
            // тот же, уже свежий проход (P302).
            //
            // И сбрасываем тоже не здесь (P389): запись в просьбу прямо во
            // время перерисовки система вправе молча не принять. Тогда
            // просьба оставалась висеть, и каждая следующая перерисовка —
            // хотя бы от касания по заголовку — снова забирала курсор в
            // запись, на прежнее место в конце строки. Лечилось только
            // перезапуском. Теперь сброс — на следующем обороте, вместе с
            // фокусом, и только один раз, сколько бы перерисовок ни прошло.
            let ask = startEditing
            DispatchQueue.main.async {
                guard ask.wrappedValue else { return }
                ask.wrappedValue = false
                view.becomeFirstResponder()
            }
        }

        // Курсор переставляется только по просьбе — и только туда, куда
        // человек и так собирался писать (решение P137).
        if caretToEnd.wrappedValue {
            let end = NSRange(location: (view.text as NSString).length, length: 0)
            view.selectedRange = end
            view.typingAttributes = Self.body(size, serif: serif)
            view.scrollRangeToVisible(end)
            let попечитель = context.coordinator
            DispatchQueue.main.async {
                caretToEnd.wrappedValue = false
                попечитель.showCaret(animated: true)
            }
        }
    }

    /// Сколько места поле просит себе.
    ///
    /// Растущее поле просит ровно столько, сколько занял текст. Тогда
    /// страница дневника едет целиком: «Как прошло?» и заголовок уходят
    /// вверх вместе с записью, а не висят над ней, пока текст ползёт под
    /// ними (решение P175).
    ///
    /// Остальные поля меряются как обычно — по отведённой им коробке.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        guard grows, let width = proposal.width, width > 0 else { return nil }
        let занято = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width,
                      height: max(minHeight, занято.height.rounded(.up) + room))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Вид

    static func body(_ size: CGFloat, serif: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: size * 0.24)
        // Размер подгоняется под системную настройку текста — ровно так же,
        // как это делает обычный текст на соседней странице. Без этого после
        // поворота страницы текст «мельчает»: рядом стояли два разных шрифта.
        let base = serif
            ? Prefs.serifUIFont(size)
            : UIFont.systemFont(ofSize: size)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        return [
            .font: font,
            .foregroundColor: UIColor(Look.ink),
            .paragraphStyle: paragraph,
        ]
    }

    /// Знак-заместитель вложения. Система ставит его туда, где в тексте
    /// было что-то не буквенное; в простом тексте он рисуется как «OBJ» в
    /// пунктирной рамке и попадает в файл записи, где ему совсем не место.
    ///
    /// Откуда он берётся, зависит от клавиатуры и способа ввода, поэтому
    /// перекрыт и источник (правка оформления запрещена), и следствие: знак
    /// убирается из текста, что бы его ни поставило (решение P161).
    static let placeholder: Character = "\u{FFFC}"

    static func clean(_ text: String) -> String {
        text.contains(placeholder) ? text.filter { $0 != placeholder } : text
    }

    static func styled(_ text: String, size: CGFloat, serif: Bool, stamped: Bool,
                       resolve: ((String) -> URL?)? = nil,
                       glowing: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString(string: clean(text),
                                            attributes: body(size, serif: serif))
        defer { if let resolve { placePhotos(in: out, resolve: resolve, glowing: glowing) } }
        guard stamped else { return out }
        let ns = text as NSString
        var start = 0
        while start <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: start, length: 0))
            if let m = stamp.firstMatch(in: text, range: lineRange), m.numberOfRanges > 1 {
                out.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: size * 0.84, weight: .regular),
                    .foregroundColor: UIColor(Look.inkFaint),
                ], range: m.range(at: 1))
            }
            if let place = placeRange(in: ns, line: lineRange) {
                out.addAttributes(placeLook(size), range: place)
            }
            if lineRange.length == 0 { break }
            start = lineRange.location + lineRange.length
            if start >= ns.length { break }
        }
        return out
    }

    // MARK: - Место в тексте

    /// Строка `geo:широта,долгота` — место, вписанное долгим нажатием на
    /// геоточку. Служебная, как отметка времени: бледнее и моноширинная
    /// (P165, P207).
    static func placeRange(in ns: NSString, line: NSRange) -> NSRange? {
        let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
        guard content.hasPrefix("geo:"), Geo.parse(content) != nil else { return nil }
        return NSRange(location: line.location, length: (content as NSString).length)
    }

    static func placeLook(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.monospacedSystemFont(ofSize: size * 0.8, weight: .regular),
         .foregroundColor: UIColor(Look.accent)]
    }

    // MARK: - Снимки в тексте

    /// Метка снимка в поле: на экране — картинка, в файле — строка-ссылка.
    static let photoKey = NSAttributedString.Key("chronotheca.photo")

    /// Размер снимка в тексте. Задан числом: картинка, пришедшая с диска
    /// позже текста, встаёт в уже отведённое место и ничего не сдвигает
    /// (P113).
    /// Снимок в тексте — в пять строк дневника высотой и столько же в
    /// ширину (P383; прежде — как превью в поиске, 86, P348). Тот же
    /// размер — у снимков под делами плана и в полоске внизу страницы.
    /// Ровно четыре в ширину экрана (P431) — и в тексте, и в ленте внизу
    /// (P557): отступ 16 по бокам и три промежутка. Прежде промежутков не
    /// было, а в тексте снимки в ряду разделяет пробел — четвёртый снимок
    /// не помещался и уходил на следующую строку (снимок автора).
    static let photoSize: CGSize = {
        let side = floor((UIScreen.main.bounds.width - 32 - 3 * photoGap) / 4)
        return CGSize(width: side, height: side)
    }()

    /// Промежуток между снимками в ряд (P557): с запасом на пробел между
    /// снимками в тексте при самом крупном шрифте записи. Тот же — в ленте.
    static let photoGap: CGFloat = 8

    /// Текст поля таким, каким он ляжет в файл: снимки — обратно строками
    /// `![](…)`, чужие знаки-заместители — вон (P161, P204).
    static func plain(_ s: NSAttributedString) -> String {
        let ns = s.string as NSString
        var out = ""
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attributes, range, _ in
            if let link = attributes[photoKey] as? String {
                out += Array(repeating: Diary.line(link), count: range.length)
                    .joined(separator: "\n")
            } else if let line = attributes[lineKey] as? String {
                // Точкой становится только сама кнопочка. Буква, набранная
                // вплотную за ней, могла унаследовать метку, — она остаётся
                // буквой (P256).
                var chips = 0
                for ch in ns.substring(with: range) {
                    if ch == placeholder {
                        out += (chips > 0 ? "\n" : "") + line
                        chips += 1
                    } else {
                        out += String(ch)
                        chips = 0
                    }
                }
            } else {
                out += clean(ns.substring(with: range))
            }
        }
        return out
    }

    /// Где в поле то место записи, что стоит в файле на отступе `plain`.
    /// Снимок и точка в поле — один знак, а в файле — целая строка.
    static func viewOffset(plain target: Int, in s: NSAttributedString) -> Int {
        let ns = s.string as NSString
        var seen = 0
        var found = s.length
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attributes, range, stop in
            var line: String?
            if let link = attributes[photoKey] as? String { line = Diary.line(link) }
            if let l = attributes[lineKey] as? String { line = l }
            if let line {
                let each = (line as NSString).length
                for k in 0..<range.length {
                    if seen >= target { found = range.location + k; stop.pointee = true; return }
                    seen += each + (k < range.length - 1 ? 1 : 0)
                }
            } else {
                let piece = (clean(ns.substring(with: range)) as NSString).length
                if seen + piece >= target {
                    let inside = piece == range.length ? target - seen : range.length
                    found = range.location + max(0, min(inside, range.length))
                    stop.pointee = true
                    return
                }
                seen += piece
            }
        }
        return found
    }

    /// Метка точки в поле: на экране — кнопочка, в файле — та же строка,
    /// что была (P213).
    static let lineKey = NSAttributedString.Key("chronotheca.line")

    /// Заменить строки-ссылки на картинки.
    static func placePhotos(in out: NSMutableAttributedString,
                            resolve: (String) -> URL?, glowing: Bool = false) {
        let ns = out.string as NSString
        // Последнее — точка своей строкой: она квадратом, как снимок (P559).
        var found: [(NSRange, String, GeoPoint?, Bool)] = []
        var start = 0
        while start < ns.length {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
            let range = NSRange(location: line.location, length: (content as NSString).length)
            let row = Diary.objects(in: content)
            if let link = Diary.picture(in: content) {
                // Снимок, голос, видео, документ своей строкой — квадратной
                // плиткой, как снимок (P456; прежде голос и документ были
                // кнопочкой с именем, P377): переносятся, раздвигают строки,
                // возвращаются в полоску и удаляются крестиком так же.
                found.append((range, link, nil, false))
            } else if row.count > 1 {
                // Несколько вложений в одной строке — рядом, через пробел
                // (P348): снимки, голос, файлы и точки вперемешку (P560).
                // Каждое — своим квадратом, пробел остаётся.
                for piece in row {
                    let at = NSRange(location: line.location + piece.range.location,
                                     length: piece.range.length)
                    if let point = piece.point {
                        found.append((at, piece.link, point, true))
                    } else {
                        found.append((at, piece.link, nil, false))
                    }
                }
            } else if let point = Geo.point(in: content) {
                found.append((range, content, point, true))
            } else if content.contains("geo:") {
                // Точка посреди строки — тоже кнопочка (P256).
                for (r, point) in Geo.points(inText: content) {
                    found.append((NSRange(location: line.location + r.location, length: r.length),
                                  (content as NSString).substring(with: r), point, false))
                }
            }
            // Снимок посреди фразы — тоже картинка, а не буквы (P357): так
            // он мог лечь при переносе, и выглядеть набором цифр не должен.
            if Diary.picture(in: content) == nil, row.count < 2 {
                for piece in Diary.anywhere(in: content) where Diary.kind(of: piece.link) == .photo {
                    found.append((NSRange(location: line.location + piece.range.location,
                                          length: piece.range.length), piece.link, nil, false))
                }
            }
            guard line.length > 0 else { break }
            start = line.location + line.length
        }
        // С конца к началу: замена не сдвигает того, что ещё впереди.
        for (range, link, point, own) in found.sorted(by: { $0.0.location < $1.0.location }).reversed() {
            let attachment: NSTextAttachment
            let file = point == nil && Diary.picture(in: link).map { Diary.kind(of: $0) != .photo } == true
            // Место, куда ляжет несомое, — пунктирной рамкой, а не вторым
            // таким же снимком (P593): два одинаковых снимка путали.
            if let awaiting = DiaryEditor.awaiting, link == awaiting || Diary.picture(in: link) == awaiting {
                attachment = AwaitingSlot()
            } else if let point, own {
                attachment = PointChip(tile: point, glowing: glowing)
            } else if let point {
                attachment = PointChip(mini: point, glowing: glowing)
            } else if file, let inner = Diary.picture(in: link) {
                attachment = FileChip(link: inner)
            } else {
                attachment = PhotoAttachment(link: link, url: resolve(link))
            }
            let piece = NSMutableAttributedString(attachment: attachment)
            let whole = NSRange(location: 0, length: piece.length)
            piece.addAttributes(out.attributes(at: range.location, effectiveRange: nil),
                                range: whole)
            piece.addAttribute(point == nil && !file ? photoKey : lineKey, value: link, range: whole)
            out.replaceCharacters(in: range, with: piece)
        }
    }

    /// Ссылка на голос, видео или документ — `[Голос](…)`, не снимок.
    static let fileLink = try! NSRegularExpression(
        pattern: #"(?<!!)\[[^\]\n]*\]\((<[^>\n]+>|[^)\s]+)\)"#)

    /// Поставить вложение своей строкой за абзацем, где `drop` (в тексте
    /// записи); снимок к снимкам — рядом в ту же строку (P348, P380).
    /// Возвращает текст и где стоит вложение.
    static func putting(_ piece: String, at drop: Int, into text: String) -> (String, Int) {
        let ns = text as NSString
        guard ns.length > 0 else { return (piece, 0) }
        let spot = min(max(drop, 0), ns.length)
        let para = ns.paragraphRange(for: NSRange(location: min(spot, ns.length - 1), length: 0))
        var j = para.location + para.length
        if j > para.location, ns.character(at: j - 1) == 10 { j -= 1 }
        let above = ns.substring(with: NSRange(location: para.location, length: j - para.location))
            .trimmingCharacters(in: .whitespaces)
        if above.isEmpty {
            let out = ns.replacingCharacters(in: NSRange(location: para.location,
                                                         length: j - para.location), with: piece)
            return (out, para.location)
        }
        // Вложение к вложениям — рядом в ту же строку, какого бы вида они
        // ни были (P560).
        let isPhoto = { (s: String) in !Diary.objects(in: s).isEmpty }
        let lead = isPhoto(piece) && isPhoto(above) ? " " : "\n"
        let out = ns.replacingCharacters(in: NSRange(location: j, length: 0), with: lead + piece)
        return (out, j + (lead as NSString).length)
    }

    /// Есть ли в поле строка-ссылка, ещё не ставшая картинкой: её только
    /// что бросили в текст или вписали руками.
    static func hasLoosePicture(_ text: String) -> Bool {
        guard text.contains("![") || text.contains("geo:") || text.contains("](") else { return false }
        return text.components(separatedBy: "\n").contains {
            Diary.picture(in: $0) != nil
                || Diary.pictures(in: $0).contains { Diary.kind(of: $0.link) == .photo }
                || Diary.objects(in: $0).count > 1
                || Diary.anywhere(in: $0).contains { Diary.kind(of: $0.link) == .photo }
                || Geo.point(in: $0) != nil
                // Посреди строки — когда точка дописана: за ней пробел или
                // она в скобках с названием. Иначе кнопочкой стали бы
                // цифры, которые ещё набирают (P256).
                || $0.range(of: #"\]\(geo:[^)\s]+\)|geo:-?\d+(\.\d+)?,\s?-?\d+(\.\d+)?\s"#,
                            options: .regularExpression) != nil
        }
    }

    /// Прочитать с диска снимки, стоящие в поле пустыми клетками, — и
    /// поставить на их место. Общее для записи и строк «Как прошло?» (P407).
    static func loadPhotos(in view: UITextView) {
        let storage = view.textStorage
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let photo = value as? PhotoAttachment, !photo.loaded,
                  let url = photo.url else { return }
            photo.loaded = true
            Task.detached(priority: .userInitiated) {
                guard let got = Photo.load(url, side: 280) else { return }
                let framed = PhotoAttachment.frame(got)
                await MainActor.run { [weak view] in
                    Photo.cache.setObject(framed, forKey: PhotoAttachment.key(url))
                    photo.image = framed
                    guard let view else { return }
                    let storage = view.textStorage
                    storage.enumerateAttribute(.attachment,
                                               in: NSRange(location: 0, length: storage.length)) { v, r, stop in
                        guard (v as? PhotoAttachment) === photo else { return }
                        // Та же вложенная картинка кладётся заново — и поле
                        // перерисовывает её клетку.
                        storage.beginEditing()
                        storage.addAttribute(.attachment, value: photo, range: r)
                        storage.endEditing()
                        stop.pointee = true
                    }
                }
            }
        }
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate,
                             UIGestureRecognizerDelegate {
        fileprivate var parent: DiaryEditor

        /// Где лежат снимки — обновляется с каждым обновлением поля.
        var resolve: ((String) -> URL?)?
        /// До какого мига поле, взявшее ввод, не ставит отметку времени:
        /// в запись принесли снимок или переставили точку, а не пишут
        /// дальше (прежде это делал режим изменений, P362).
        private var quietUntil = Date.distantPast

        /// Поле, за которым присматривает этот попечитель.
        weak var view: UITextView?

        /// Верхняя кромка клавиатуры в окне. Пусто — клавиатуры нет.
        private var keyboardTop: CGFloat?

        init(_ parent: DiaryEditor) {
            self.parent = parent
            super.init()
            let вести = NotificationCenter.default
            вести.addObserver(self, selector: #selector(keyboardMoved(_:)),
                              name: UIResponder.keyboardWillChangeFrameNotification,
                              object: nil)
            вести.addObserver(self, selector: #selector(keyboardGone(_:)),
                              name: UIResponder.keyboardWillHideNotification,
                              object: nil)
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            parent.onEditing?(true)
            if Date() > quietUntil { parent.onFocus() }
            // Клавиатура могла подняться раньше — например, человек писал
            // заголовок дня и перешёл в запись. Тогда вестей о ней больше
            // не будет, и место надо освободить самому.
            DispatchQueue.main.async { [weak self] in self?.makeRoom(scroll: true) }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            parent.onEditing?(false)
            scrub()
            makeRoom(scroll: false)
        }

        /// Вычистить из поля знаки-заместители, оставив курсор на месте.
        ///
        /// Зовётся, когда поле отпускает ввод: диктовка к этому времени
        /// кончилась, и поле снова принадлежит нам (решение P197).
        func scrub() {
            guard let view else { return }
            let storage = view.textStorage
            let ns = storage.string as NSString
            var курсор = view.selectedRange
            var i = ns.length - 1
            var changed = false
            storage.beginEditing()
            while i >= 0 {
                // Свои снимки не трогаем: это картинки на месте строк-ссылок.
                if ns.character(at: i) == 0xFFFC,
                   storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) == nil,
                   storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) == nil {
                    storage.deleteCharacters(in: NSRange(location: i, length: 1))
                    if i < курсор.location { курсор.location -= 1 }
                    changed = true
                }
                i -= 1
            }
            storage.endEditing()
            guard changed else { return }
            view.selectedRange = NSRange(
                location: min(курсор.location, storage.length), length: 0)
            parent.text = DiaryEditor.plain(storage)
            restyle(view)
        }

        // MARK: - Касание по снимку и точке

        /// Что оказалось под пальцем в начале касания, и когда.
        private var pressed: (photo: String?, point: GeoPoint?)?
        private var pressedAt = Date.distantPast

        /// Снимок или точка под пальцем.
        private func hit(_ at: CGPoint, in view: UITextView) -> (photo: String?, point: GeoPoint?)? {
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
                if let link = storage.attribute(DiaryEditor.photoKey, at: i,
                                                effectiveRange: nil) as? String {
                    guard parent.onOpenPhoto != nil else { return nil }
                    return (photo: link, point: nil)
                }
                if let line = storage.attribute(DiaryEditor.lineKey, at: i,
                                                effectiveRange: nil) as? String,
                   let point = Geo.point(in: line) {
                    guard parent.onOpenPoint != nil else { return nil }
                    return (photo: nil, point: point)
                }
                // Голос или файл в тексте — открыть, как из полоски (P377).
                if let line = storage.attribute(DiaryEditor.lineKey, at: i,
                                                effectiveRange: nil) as? String,
                   let link = Diary.picture(in: line) {
                    guard parent.onOpenPhoto != nil else { return nil }
                    return (photo: link, point: nil)
                }
            }
            return nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g is UILongPressGestureRecognizer {
                guard parent.moving, let view else { return false }
                taken = attachment(at: touch.location(in: view), in: view)
                return taken != nil
            }
            guard let view, parent.onOpenPhoto != nil || parent.onOpenPoint != nil else {
                return false
            }
            pressed = hit(touch.location(in: view), in: view)
            pressedAt = Date()
            return pressed != nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UILongPressGestureRecognizer)
        }

        // MARK: - Перенос снимка и точки по тексту (P226)

        /// Место в тексте поля, где лежит взятое.
        private var taken: Int?
        /// Взятое — строкой, как в файле: его несут и в ответ «Как прошло?»
        /// (P407).
        private var takenPiece: String?

        /// Дело плана под пальцем, если взятое может туда встать: снимок
        /// или точка (P409).
        private func planTask(_ g: UIGestureRecognizer) -> UUID? {
            guard let piece = takenPiece, Self.isPhotoLine(piece) || Geo.point(in: piece) != nil
            else { return nil }
            return parent.planTarget?(g.location(in: nil))
        }

        static func isPhotoLine(_ piece: String) -> Bool {
            Diary.picture(in: piece).map { Diary.kind(of: $0) == .photo } ?? false
        }
        /// Картинка взятого, которая идёт за пальцем.
        private var ghost: UIView?

        /// Снимок или точка под пальцем — их место в тексте поля.
        private func attachment(at at: CGPoint, in view: UITextView) -> Int? {
            guard let position = view.closestPosition(to: at) else { return nil }
            let storage = view.textStorage
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            for i in [offset, offset - 1] where i >= 0 && i < storage.length {
                guard storage.attribute(.attachment, at: i, effectiveRange: nil) != nil,
                      storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
                        || storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) != nil,
                      let start = view.position(from: view.beginningOfDocument, offset: i),
                      let end = view.position(from: start, offset: 1),
                      let range = view.textRange(from: start, to: end),
                      view.firstRect(for: range).insetBy(dx: -4, dy: -4).contains(at)
                else { continue }
                return i
            }
            return nil
        }

        /// Взятое идёт над пальцем, а не под ним: иначе палец закрывает его
        /// целиком и тащить приходится вслепую (P349). Ложится оно тоже туда,
        /// где видно, — над пальцем.
        /// Насколько несомое выше пальца (P593: было 48 — палец закрывал
        /// низ картинки). То же у несомого из ленты.
        static let lift: CGFloat = 70

        /// Тонкая синяя черта там, куда ляжет взятое (P358): палец и
        /// поднятая над ним картинка не дают увидеть место точно.
        private var mark: UIView?

        /// Взята точка, а не снимок.
        private func takenIsPoint(_ view: UITextView) -> Bool {
            guard let i = taken else { return false }
            return takenIsPoint(at: i, in: view)
        }

        private func takenIsPoint(at i: Int, in view: UITextView) -> Bool {
            guard i < view.textStorage.length else { return false }
            guard let line = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                        effectiveRange: nil) as? String
            else { return false }
            return Geo.point(in: line) != nil
                && view.textStorage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) == nil
        }

        private func takenIsPhoto(at i: Int, in view: UITextView) -> Bool {
            i < view.textStorage.length
                && view.textStorage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
        }

        // MARK: - Крестик у точки (P362) и у снимка (P392)

        /// Покрывало поверх окна: на нём точка крупнее и крестик. Касание
        /// мимо крестика — покрывало уходит, и всё как было.
        private var cover: UIView?

        /// Показать точку крупнее, с крестиком «удалить» на углу — как
        /// значок на экране «Домой», когда его подержали.
        private func arm(_ i: Int, in view: UITextView) {
            let photo = view.textStorage.attribute(DiaryEditor.photoKey, at: i,
                                                   effectiveRange: nil) as? String
            guard let window = view.window,
                  let line = photo ?? view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                                 effectiveRange: nil) as? String,
                  let picture = (view.textStorage.attribute(.attachment, at: i, effectiveRange: nil)
                                 as? NSTextAttachment)?.image,
                  let start = view.position(from: view.beginningOfDocument, offset: i),
                  let end = view.position(from: start, offset: 1),
                  let range = view.textRange(from: start, to: end)
            else { return }
            disarm()
            Feel.light()
            let place = view.convert(view.firstRect(for: range), to: window)
            let veil = UIControl(frame: window.bounds)
            veil.backgroundColor = UIColor.black.withAlphaComponent(0.06)
            veil.addTarget(self, action: #selector(disarm), for: .touchDown)
            // Синей рамки во всю строку больше нет (P561, прежде P380): в
            // ряду стоят и другие вложения — выделяется только взятое.
            let field = view.convert(view.bounds, to: window)
            let chip = UIImageView(image: picture)
            chip.center = CGPoint(x: place.midX, y: place.midY)
            // Квадрат — снимок, файл и точка своей строкой или в ряду (P560);
            // кнопочка — точка посреди фразы.
            let square = picture.size.height >= 40
            // Синяя кромка — та же, что у поднятого дела (P374).
            chip.layer.borderColor = UIColor(Look.glow).cgColor
            chip.layer.borderWidth = square ? 3 : 2
            chip.layer.cornerRadius = square ? 8 : picture.size.height / 2
            chip.layer.shadowOpacity = 0.25
            chip.layer.shadowRadius = 6
            chip.layer.shadowOffset = CGSize(width: 0, height: 2)
            veil.addSubview(chip)
            // Снимок и так крупный — он лишь чуть приподнимается (P392).
            let grow: CGFloat = square ? 1.05 : 1.4
            // Крестик нарисован свой (P409): системный значок с двумя
            // цветами в кнопке выходил пустым кружком без креста.
            let cross = UIControl(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
            let mark = UIImageView(image: Self.crossImage)
            mark.frame = CGRect(x: 6, y: 6, width: 44, height: 44)
            mark.isUserInteractionEnabled = false
            cross.addSubview(mark)
            cross.layer.shadowColor = UIColor.black.cgColor
            cross.layer.shadowOpacity = 0.3
            cross.layer.shadowRadius = 3
            cross.layer.shadowOffset = CGSize(width: 0, height: 1)
            cross.isAccessibilityElement = true
            cross.accessibilityTraits = .button
            if square {
                // У снимка крестик — на верхнем правом углу, как у значка
                // на экране «Домой».
                cross.center = CGPoint(x: min(place.midX + picture.size.width * grow / 2, field.maxX - 10),
                                       y: place.midY - picture.size.height * grow / 2 + 4)
                cross.accessibilityLabel = photo != nil
                    ? T("Убрать снимок из текста", "Remove photo from text") : T("Удалить точку", "Delete place")
            } else {
                cross.center = CGPoint(x: min(place.midX + picture.size.width * grow / 2 + 22, field.maxX - 10),
                                       y: place.midY)
                cross.accessibilityLabel = T("Удалить точку", "Delete place")
            }
            cross.addAction(UIAction { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.disarm()
                // Удаляется то самое, если оно ещё на своём месте.
                guard i < view.textStorage.length,
                      (view.textStorage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) as? String
                        ?? view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                      effectiveRange: nil) as? String) == line
                else { return }
                Feel.light()
                // Снимок: спросить — в полоску внизу или удалить файл
                // (P409; прежде крестик молча уводил в полоску, P392).
                if let link = photo {
                    self.askAbout(link, in: view)
                } else {
                    // Точка — тоже после вопроса, тем же окошком (P563).
                    self.askPoint(at: i, line: line, in: view)
                }
            }, for: .touchUpInside)
            cross.alpha = 0
            veil.addSubview(cross)
            window.addSubview(veil)
            cover = veil
            UIView.animate(withDuration: 0.15) {
                chip.transform = CGAffineTransform(scaleX: grow, y: grow)
                cross.alpha = 1
            }
        }

        /// Крестик: белая кайма, красный круг, белый крест.
        static let crossImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 40, height: 40)).fill()
            UIColor(Look.pin).setFill()
            UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 32, height: 32)).fill()
            let x = UIBezierPath()
            x.move(to: CGPoint(x: 16, y: 16)); x.addLine(to: CGPoint(x: 28, y: 28))
            x.move(to: CGPoint(x: 28, y: 16)); x.addLine(to: CGPoint(x: 16, y: 28))
            x.lineWidth = 3.4
            x.lineCapStyle = .round
            UIColor.white.setStroke()
            x.stroke()
        }

        /// Что сделать со снимком из текста: убрать в полоску внизу или
        /// удалить файл — в корзину на 30 дней (P371, P409).
        /// Удалить точку из записи — после вопроса, как и файл (P563): всё
        /// удаляется по одному лекалу.
        private func askPoint(at i: Int, line: String, in view: UITextView) {
            let sheet = UIAlertController(title: T("Удалить точку?", "Delete the place?"),
                                          message: nil, preferredStyle: .alert)
            sheet.addAction(UIAlertAction(title: T("Удалить точку", "Delete place"),
                                          style: .destructive) { [weak self, weak view] _ in
                guard let self, let view, i < view.textStorage.length,
                      view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                 effectiveRange: nil) as? String == line
                else { return }
                self.remove(at: i, in: view)
            })
            sheet.addAction(UIAlertAction(title: T("Отмена", "Cancel"), style: .cancel))
            var top = view.window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            top?.present(sheet, animated: true)
        }

        private func askAbout(_ link: String, in view: UITextView) {
            // Окошко посередине экрана, над клавиатурой (P556): лист,
            // привязанный ко всему полю записи, вставал под клавиатуру.
            // Тот же вопрос и те же слова, что у превью в ленте.
            let sheet = UIAlertController(title: T("Что сделать с файлом?", "What should happen to the file?"),
                                          message: nil, preferredStyle: .alert)
            if let giveBack = parent.onReturnPhoto {
                sheet.addAction(UIAlertAction(title: T("Убрать в полоску внизу", "Move to the strip below"),
                                              style: .default) { _ in giveBack(link) })
            }
            if let delete = parent.onDeleteAttachment {
                sheet.addAction(UIAlertAction(title: T("Удалить файл — в корзину на 30 дней",
                                                       "Delete the file — trash for 30 days"),
                                              style: .destructive) { _ in delete(link) })
            }
            sheet.addAction(UIAlertAction(title: T("Отмена", "Cancel"), style: .cancel))
            var top = view.window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            top?.present(sheet, animated: true)
        }

        @objc private func disarm() {
            cover?.removeFromSuperview()
            cover = nil
        }

        /// Точка над заголовком дня — отпустить здесь значит перенести её в
        /// заголовок (P358).
        private func overTitle(_ g: UIGestureRecognizer, in view: UITextView) -> Bool {
            guard takenIsPoint(view), let window = view.window,
                  !DiaryEditor.titleZone.isNull else { return false }
            let spot = g.location(in: window)
            let lifted = CGPoint(x: spot.x, y: spot.y - Self.lift)
            return DiaryEditor.titleZone.insetBy(dx: -8, dy: -10).contains(lifted)
        }

        /// Палец со взятым снимком ниже страницы — над полоской превью:
        /// отпустить здесь значит вернуть снимок вниз (P272, P349).
        private func overStrip(_ g: UIGestureRecognizer, in view: UITextView) -> Bool {
            guard let window = view.window, let page = page(over: view),
                  view.textStorage.attribute(DiaryEditor.photoKey, at: taken ?? 0,
                                             effectiveRange: nil) != nil
            else { return false }
            // Считается сам палец, а не поднятая над ним картинка: её край
            // уже над полоской, когда палец ещё на странице.
            let y = g.location(in: window).y
            // Лента и строка вложений — конец самой записи (P546), а не низ
            // экрана: над ними — значит вниз, в ленту (P547). Прежде
            // считался только низ страницы — снимок из текста не возвращался.
            if let strip = StripZones.strip, y >= strip.minY - 8, y <= strip.maxY + 60 { return true }
            if let pill = KeyboardBar.pillTarget, y >= pill - KeyboardBar.attachHeight { return true }
            return y > page.convert(page.bounds, to: window).maxY - 24
        }

        /// Где палец взял снимок или точку — в окне.
        private var takenAt: CGPoint = .zero
        /// Когда отпустили долгое нажатие — касание в тот же миг не считается.
        private var heldEnded = Date.distantPast
        /// Идёт перенос: в поле уже показано, как ляжет взятое (P374).
        fileprivate(set) var previewing = false
        /// Поле до переноса — чтобы вернуть его, если перенос отменили.
        private var before: NSAttributedString?
        /// Где взятое стоит сейчас — в показанном поле.
        private var now: Int?
        /// Запись, как она станет после переноса.
        private var result: String?
        /// Где начинались абзацы поля до переноса — верх каждого (P584).
        /// Место под пальцем считается по ним, а не по полю, уже
        /// раздвинутому показом: высокий снимок раздвигал строки, под
        /// пальцем оказывалась другая строка, место прыгало — и снимок
        /// вставал не туда, выдавливая текст и точки.
        private var paraTops: [(start: Int, top: CGFloat, cells: [(index: Int, midX: CGFloat)])] = []
        /// Что несут из полоски — строка вложения (P584).
        private var carriedPiece: String?

        private func measureParagraphs(_ view: UITextView) {
            let storage = view.textStorage
            let ns = storage.string as NSString
            func rect(_ k: Int, _ length: Int) -> CGRect? {
                guard let s = view.position(from: view.beginningOfDocument, offset: k),
                      let e = view.position(from: s, offset: length),
                      let range = view.textRange(from: s, to: e) else { return nil }
                return view.firstRect(for: range)
            }
            var out: [(start: Int, top: CGFloat, cells: [(index: Int, midX: CGFloat)])] = []
            var k = 0
            while k < ns.length {
                let para = ns.paragraphRange(for: NSRange(location: k, length: 0))
                var end = NSMaxRange(para)
                if end > para.location, ns.character(at: end - 1) == 10 { end -= 1 }
                // Ряд вложений — где стоит каждое: встать можно между ними.
                var cells: [(index: Int, midX: CGFloat)] = []
                let row = NSRange(location: para.location, length: end - para.location)
                if Self.photoRow(row, in: storage) {
                    for c in row.location..<NSMaxRange(row) where ns.character(at: c) == 0xFFFC {
                        if let r = rect(c, 1) { cells.append((c, r.midX)) }
                    }
                }
                if let r = rect(para.location, min(1, para.length)) {
                    out.append((para.location, r.minY, cells))
                }
                k = max(NSMaxRange(para), k + 1)
            }
            paraTops = out
        }

        /// Место в поле до переноса, над которым палец: начало абзаца, а в
        /// ряду вложений — между ними, по их местам.
        private func paragraph(at point: CGPoint) -> Int {
            guard let para = paraTops.last(where: { $0.top <= point.y }) ?? paraTops.first else { return 0 }
            guard let last = para.cells.last else { return para.start }
            return para.cells.first(where: { $0.midX > point.x })?.index ?? last.index + 1
        }

        @objc func carried(_ g: UILongPressGestureRecognizer) {
            guard let view, let i = taken else { return }
            let touch = g.location(in: view)
            let at = CGPoint(x: touch.x, y: touch.y - Self.lift)
            quietUntil = Date().addingTimeInterval(1.5)
            switch g.state {
            case .began:
                takenAt = g.location(in: nil)
                disarm()
                // Прочие жесты поля — лупа, выделение — отпускают палец.
                for other in view.gestureRecognizers ?? [] where other !== g && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Точка — сразу крупнее и с крестиком, ещё под пальцем
                // (P374): «удалить» видно, не отпуская. Повели — крестик
                // уходит, точка идёт за пальцем.
                // Снимок — так же (P392): рамка и крестик на месте; повели —
                // крестик уходит, снимок идёт над пальцем.
                if takenIsPoint(at: i, in: view) || takenIsPhoto(at: i, in: view) {
                    arm(i, in: view)
                } else {
                    lift(i, g, in: view)
                }
                finger = g.location(in: nil)
                takenPiece = DiaryEditor.plain(view.textStorage.attributedSubstring(
                    from: NSRange(location: i, length: 1)))
                startPump()
            case .changed:
                let spot = g.location(in: nil)
                finger = spot
                if ghost == nil {
                    guard hypot(spot.x - takenAt.x, spot.y - takenAt.y) >= 10 else { return }
                    disarm()
                    lift(i, g, in: view)
                }
                let local = g.location(in: ghost?.superview ?? view)
                ghost?.center = CGPoint(x: local.x, y: local.y - Self.lift)
                // Над полоской снимок бледнеет — видно, что отпустить здесь
                // значит вернуть его вниз; над заголовком — то же для точки.
                // Над делом плана — встанет под него (P409): план подсвечивает
                // дело, запись остаётся как была.
                let toPlan = planTask(g)
                parent.onPlanHover?(toPlan, takenPiece.map(Self.isPhotoLine) ?? false)
                if toPlan != nil { AskLine.carryOutAll() }
                // Над строкой «Как прошло?» — встанет в конец ответа (P407):
                // ответ показывает это у себя, запись остаётся как была.
                let intoAnswer = toPlan == nil
                    && takenPiece.map { AskLine.carry($0, at: g.location(in: nil)) } == true
                let away = toPlan != nil || intoAnswer || overStrip(g, in: view) || overTitle(g, in: view)
                ghost?.alpha = away && !intoAnswer && toPlan == nil ? 0.5 : 0.9
                if away { restore(view) } else { previewSoon(view) }
            case .ended:
                stopPump()
                heldEnded = Date()
                let toPlan = planTask(g)
                parent.onPlanHover?(nil, false)
                let intoAnswer = toPlan == nil && takenPiece != nil
                    && AskLine.under(g.location(in: nil)) != nil
                let back = !intoAnswer && toPlan == nil && overStrip(g, in: view)
                let up = !intoAnswer && toPlan == nil && overTitle(g, in: view)
                let moved = ghost != nil
                ghost?.removeFromSuperview()
                ghost = nil
                mark?.removeFromSuperview()
                mark = nil
                // Подержали и отпустили, не сдвинув: точка так и стоит
                // крупнее, с крестиком; снимок — на месте.
                guard moved else {
                    AskLine.carryOutAll()
                    taken = nil
                    takenPiece = nil
                    rowSlots = nil
                    return
                }
                // Отпустили — ложится ровно под пальцем, даже если наплыв
                // ещё не успел показать это место (P406).
                if !back, !up, !intoAnswer, toPlan == nil { preview(at, in: view) }
                let done = result
                let piece = takenPiece
                restore(view)
                taken = nil
                takenPiece = nil
                rowSlots = nil
                // Отпустили над делом плана — уходит из записи под него
                // (P409).
                if let task = toPlan, let piece {
                    AskLine.carryOutAll()
                    if parent.onToPlan?(piece, task) == true {
                        remove(at: i, in: view)
                        Feel.light()
                    }
                    return
                }
                // Отпустили над строкой «Как прошло?» — вложение уходит из
                // записи в конец ответа, в ту же строку (P407).
                if intoAnswer {
                    if AskLine.carryEnd(at: g.location(in: nil)) {
                        remove(at: i, in: view)
                        Feel.light()
                    }
                    return
                }
                // Точку отпустили над заголовком дня — она уходит туда (P358).
                if up, let line = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                             effectiveRange: nil) as? String,
                   Geo.point(in: line) != nil,
                   let toTitle = parent.onPointToTitle {
                    remove(at: i, in: view)
                    Feel.light()
                    toTitle(line)
                    return
                }
                // Отпустили ниже страницы, над полоской превью — снимок
                // возвращается туда, откуда его взяли (P272).
                if back, let link = (view.textStorage.attribute(DiaryEditor.photoKey, at: i,
                                                                effectiveRange: nil) as? String)
                    ?? (view.textStorage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) as? String)
                        .flatMap(Diary.picture(in:)),
                   let giveBack = parent.onReturnPhoto {
                    Feel.light()
                    giveBack(link)
                    return
                }
                // Встаёт туда, где его только что показывали.
                if let done {
                    Feel.light()
                    show(done, in: view)
                    parent.text = done
                }
            default:
                stopPump()
                AskLine.carryOutAll()
                parent.onPlanHover?(nil, false)
                takenPiece = nil
                heldEnded = Date()
                ghost?.removeFromSuperview()
                ghost = nil
                mark?.removeFromSuperview()
                mark = nil
                restore(view)
                taken = nil
                rowSlots = nil
            }
        }

        /// Поднять взятое над пальцем — с синей кромкой (P374).
        private func lift(_ i: Int, _ g: UIGestureRecognizer, in view: UITextView) {
            let picture = (view.textStorage.attribute(.attachment, at: i, effectiveRange: nil)
                           as? NSTextAttachment)?.image
            let shadow = UIImageView(image: picture)
            shadow.alpha = 0.9
            shadow.layer.shadowOpacity = 0.3
            shadow.layer.shadowRadius = 8
            shadow.layer.borderColor = UIColor(Look.glow).cgColor
            shadow.layer.borderWidth = 2.6
            shadow.layer.cornerRadius = min(8, (picture?.size.height ?? 0) / 2)
            // Точка посреди фразы — маленькая кнопочка: над пальцем она
            // крупнее, чтобы её было видно (P349). Едет только она сама —
            // строки целиком в синей рамке больше нет (P561, прежде P380).
            let small = (picture?.size.height ?? 0) < 40
            shadow.transform = CGAffineTransform(scaleX: small ? 1.8 : 1.1, y: small ? 1.8 : 1.1)
            // Тень снимка — поверх всего окна: её можно донести и до
            // полоски внизу, за край страницы (P272).
            let host: UIView = view.window ?? view
            let spot = g.location(in: host)
            shadow.center = CGPoint(x: spot.x, y: spot.y - Self.lift)
            host.addSubview(shadow)
            ghost = shadow
            before = view.attributedText.copy() as? NSAttributedString
            measureParagraphs(view)
            now = i
            result = nil
            previewing = true
            rowSlots = slots(around: i, in: view)
        }

        /// Снимок взят из ряда снимков (P418): где стоят снимки ряда до
        /// переноса. Место в ряду считается по ним, а не по ряду, уже
        /// раздвинутому показом, — иначе место перескакивало туда-обратно
        /// и снимок дёргался под пальцем.
        private var rowSlots: (band: CGRect, cells: [(index: Int, rect: CGRect)],
                               original: NSAttributedString)?

        private func slots(around i: Int, in view: UITextView)
            -> (band: CGRect, cells: [(index: Int, rect: CGRect)], original: NSAttributedString)? {
            let storage = view.textStorage
            // Любое вложение ряда — снимок, файл или точка (P560).
            func object(_ k: Int) -> Bool {
                storage.attribute(DiaryEditor.photoKey, at: k, effectiveRange: nil) != nil
                    || storage.attribute(DiaryEditor.lineKey, at: k, effectiveRange: nil) != nil
            }
            guard i < storage.length, object(i),
                  let original = view.attributedText.copy() as? NSAttributedString
            else { return nil }
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: i, length: 0))
            var end = NSMaxRange(para)
            if end > para.location, ns.character(at: end - 1) == 10 { end -= 1 }
            let row = NSRange(location: para.location, length: end - para.location)
            guard Self.photoRow(row, in: storage) else { return nil }
            var cells: [(index: Int, rect: CGRect)] = []
            for k in row.location..<NSMaxRange(row) where object(k) {
                guard let start = view.position(from: view.beginningOfDocument, offset: k),
                      let stop = view.position(from: start, offset: 1),
                      let range = view.textRange(from: start, to: stop) else { continue }
                cells.append((k, view.firstRect(for: range)))
            }
            guard cells.count > 1 else { return nil }
            let band = cells.map(\.rect).reduce(cells[0].rect) { $0.union($1) }
                .insetBy(dx: -40, dy: -28)
            return (band, cells, original)
        }

        /// Показать в поле, как ляжет взятое, если отпустить палец здесь:
        /// текст раздвигается, строки расходятся (P374).
        private func preview(_ at: CGPoint, in view: UITextView) {
            // Внутри своего ряда — по местам снимков до переноса (P418).
            if let row = rowSlots, let i = taken, row.band.contains(at) {
                let others = row.cells.filter { $0.index != i }
                let k = others.filter { $0.rect.midX < at.x }.count
                let drop = k < others.count ? others[k].index : (others.last?.index ?? i) + 1
                if let next = placed(from: i, to: drop, in: row.original) {
                    guard next.0 != result else { return }
                    result = next.0
                    show(next.0, in: view)
                    now = DiaryEditor.viewOffset(plain: next.1, in: view.attributedText)
                } else if result != nil {
                    // Над своим же местом — ряд как был.
                    result = nil
                    view.attributedText = row.original
                    view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                    loadPhotos()
                    now = i
                }
                return
            }
            // Всё считается по полю до переноса, одним шагом (P584): прежде —
            // от последнего показа к следующему, и ошибка копилась.
            guard let original = before else { return }
            // Что несут — его будущее место рисуется рамкой (P593).
            if let piece = carriedPiece {
                DiaryEditor.awaiting = Diary.picture(in: piece) ?? piece.trimmingCharacters(in: .whitespaces)
            } else if let i = taken, i < original.length {
                let piece = DiaryEditor.plain(original.attributedSubstring(from: NSRange(location: i, length: 1)))
                DiaryEditor.awaiting = Diary.picture(in: piece) ?? piece.trimmingCharacters(in: .whitespaces)
            }
            let drop = paragraph(at: at)
            let next: (String, Int)?
            if let piece = carriedPiece {
                let plainDrop = (DiaryEditor.plain(original.attributedSubstring(
                    from: NSRange(location: 0, length: min(drop, original.length)))) as NSString).length
                next = DiaryEditor.putting(piece, at: plainDrop, into: DiaryEditor.plain(original))
            } else if let i = taken {
                next = placed(from: i, to: drop, in: original)
            } else {
                return
            }
            guard let next else {
                // Над своим же местом — поле как было.
                if result != nil {
                    result = nil
                    view.attributedText = original
                    view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                    loadPhotos()
                    now = taken
                }
                return
            }
            guard next.0 != result else { return }
            result = next.0
            show(next.0, in: view)
            now = DiaryEditor.viewOffset(plain: next.1, in: view.attributedText)
        }

        // MARK: - Из полоски в текст (P380)

        /// Снимок, голос или файл из полоски несут над полем: текст
        /// расступается там, куда он ляжет. `false` — палец не над полем.
        @discardableResult
        func carryIn(_ piece: String, at global: CGPoint) -> Bool {
            guard let view, let window = view.window else { return false }
            let local = view.convert(global, from: window)
            guard view.bounds.insetBy(dx: -10, dy: -30).contains(local) else {
                carryOut()
                return false
            }
            let at = CGPoint(x: local.x, y: local.y - Self.lift)
            quietUntil = Date().addingTimeInterval(1.5)
            if !previewing {
                before = view.attributedText.copy() as? NSAttributedString
                measureParagraphs(view)
                previewing = true
            }
            carriedPiece = piece
            preview(at, in: view)
            return true
        }

        /// Палец ушёл с поля — текст, каким был.
        func carryOut() {
            guard let view, previewing, taken == nil else { return }
            restore(view)
        }

        /// Отпустили над полем — вложение встаёт туда, где его показывали.
        @discardableResult
        func carryEnd() -> Bool {
            guard let view, previewing, taken == nil, let done = result else {
                carryOut()
                return false
            }
            restore(view)
            show(done, in: view)
            parent.text = done
            return true
        }

        /// Вернуть поле, каким оно было до переноса.
        private func restore(_ view: UITextView) {
            if let before, result != nil {
                view.attributedText = before
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                loadPhotos()
            }
            before = nil
            result = nil
            now = taken
            previewing = false
            shownSpot = nil
            carriedPiece = nil
            DiaryEditor.awaiting = nil
            paraTops = []
        }

        private func show(_ text: String, in view: UITextView) {
            view.attributedText = DiaryEditor.styled(text, size: parent.size, serif: parent.serif,
                                                     stamped: parent.stamped, resolve: resolve)
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            loadPhotos()
        }

        // MARK: - Перенос мягко (P406)

        /// Где палец — в окне.
        private var finger: CGPoint = .zero
        /// Когда поле в последний раз показало, как ляжет взятое.
        private var shownAt = Date.distantPast
        /// Где палец был тогда — в поле.
        private var shownSpot: CGPoint?
        private var pump: CADisplayLink?

        /// Пока несут — каждый кадр: у краёв страница сама едет к пальцу,
        /// а поле показывает, как ляжет взятое, не чаще раза в шестую
        /// долю секунды и мягким наплывом, а не рывком на каждый сдвиг.
        private func startPump() {
            stopPump()
            shownAt = .distantPast
            shownSpot = nil
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            pump = link
        }

        private func stopPump() {
            pump?.invalidate()
            pump = nil
        }

        /// Превью из полоски несут (P409): у верхнего и нижнего края страница
        /// едет к пальцу, а несущий узнаёт, что под пальцем теперь другое.
        private var stripFollow: (() -> Void)?

        func followStrip(at global: CGPoint, moved: @escaping () -> Void) {
            finger = global
            stripFollow = moved
            if pump == nil { startPump() }
        }

        /// Пока превью из ленты несут, страница пальцем не листается (P539):
        /// жест превью теперь совместный с прокрутками вокруг. Сама к пальцу
        /// у края она по-прежнему едет — это не палец, а приложение.
        func holdPage(_ hold: Bool) {
            guard let view, let page = page(over: view) else { return }
            page.isScrollEnabled = !hold
        }

        func stopFollowingStrip() {
            stripFollow = nil
            if taken == nil { stopPump() }
        }

        @objc private func tick() {
            guard let view else { return }
            if let follow = stripFollow {
                if scrollTowardFinger(view) { follow() }
                return
            }
            guard ghost != nil, taken != nil else { return }
            if scrollTowardFinger(view) { ghostFollows(view) }
            previewSoon(view)
        }

        /// Палец у верхнего или нижнего края страницы — страница едет туда:
        /// тем быстрее, чем ближе к краю. `true` — уехала.
        private func scrollTowardFinger(_ view: UITextView) -> Bool {
            guard let page = page(over: view), let window = view.window else { return false }
            let seen = page.convert(page.bounds, to: window)
            let bottom = min(seen.maxY, keyboardTop ?? .infinity)
            let band: CGFloat = 90
            var step: CGFloat = 0
            if finger.y < seen.minY + band {
                step = -max(0, seen.minY + band - finger.y) / band * 9
            } else if finger.y > bottom - band {
                step = max(0, finger.y - (bottom - band)) / band * 9
            }
            guard abs(step) > 0.3 else { return false }
            let lowest = -page.adjustedContentInset.top
            let highest = max(lowest, page.contentSize.height + page.adjustedContentInset.bottom
                              - page.bounds.height)
            let to = min(max(page.contentOffset.y + step, lowest), highest)
            guard to != page.contentOffset.y else { return false }
            page.contentOffset.y = to
            return true
        }

        /// Страница уехала — несомое остаётся под пальцем.
        private func ghostFollows(_ view: UITextView) {
            guard let ghost, let host = ghost.superview else { return }
            let local = host.convert(finger, from: nil)
            ghost.center = CGPoint(x: local.x, y: local.y - Self.lift)
        }

        /// Показать, как ляжет взятое, — но не чаще раза в 0,16 секунды и
        /// только если палец сдвинулся заметно; сама смена — наплывом.
        private func previewSoon(_ view: UITextView) {
            guard previewing || ghost != nil else { return }
            let local = view.convert(finger, from: nil)
            let at = CGPoint(x: local.x, y: local.y - Self.lift)
            if let was = shownSpot, hypot(was.x - at.x, was.y - at.y) < 8 { return }
            guard Date().timeIntervalSince(shownAt) > 0.16 else { return }
            shownAt = Date()
            shownSpot = at
            UIView.transition(with: view, duration: 0.18,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.preview(at, in: view)
            }
        }

        /// Убрать точку из текста — вместе с пробелом рядом, а если она
        /// стояла своей строкой — с этой строкой (P358).
        private func remove(at i: Int, in view: UITextView) {
            let storage = view.textStorage
            let start = (DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: 0, length: i))) as NSString).length
            let piece = DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: i, length: 1)))
            let text = DiaryEditor.plain(storage) as NSString
            var cut = NSRange(location: start, length: (piece as NSString).length)
            let after = NSMaxRange(cut) < text.length ? text.character(at: NSMaxRange(cut)) : 10
            let before = cut.location > 0 ? text.character(at: cut.location - 1) : 10
            if after == 32 || (after == 10 && before == 10 && NSMaxRange(cut) < text.length) {
                cut.length += 1
            } else if before == 32 || before == 10 && cut.location > 0 {
                cut.location -= 1
                cut.length += 1
            }
            let result = text.replacingCharacters(in: cut, with: "")
            view.attributedText = DiaryEditor.styled(result, size: parent.size, serif: parent.serif,
                                                     stamped: parent.stamped, resolve: resolve)
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            loadPhotos()
            parent.text = result
        }

        /// Куда ляжет снимок или точка, если отпустить их здесь: запись после
        /// переноса и где в ней (в буквах записи) стоит взятое. `nil` — с
        /// места не сдвинется.
        ///
        /// Точка — значок в строке: встаёт ровно туда, где отпустили, посреди
        /// текста (P259). Снимок встаёт своей строкой в конец абзаца — или
        /// рядом со снимками, если над ними (P204, P348, P357).
        private func placed(from i: Int, to drop: Int,
                            in storage: NSAttributedString) -> (String, Int)? {
            let ns = storage.string as NSString
            guard i < storage.length else { return nil }
            func plainLength(_ upTo: Int) -> Int {
                (DiaryEditor.plain(storage.attributedSubstring(
                    from: NSRange(location: 0, length: upTo))) as NSString).length
            }
            let piece = DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: i, length: 1)))
            let text = DiaryEditor.plain(storage) as NSString

            // Точка, как и снимок, встаёт только своей строкой (P380): строку
            // текста она больше не рвёт.
            let para = ns.paragraphRange(for: NSRange(location: min(drop, ns.length), length: 0))
            var j = para.location + para.length
            if j > para.location, ns.character(at: j - 1) == 10 { j -= 1 }
            // Снимок над рядом снимков — встаёт в ряд туда, куда показали:
            // так снимки меняются местами (P409; прежде — всегда в конец ряда).
            if storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
                || storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) != nil,
               Self.photoRow(NSRange(location: para.location, length: j - para.location), in: storage) {
                let spot = min(max(drop, para.location), j)
                guard spot != i, spot != i + 1 else { return nil }
                var cut = NSRange(location: plainLength(i), length: (piece as NSString).length)
                let after = NSMaxRange(cut) < text.length ? text.character(at: NSMaxRange(cut)) : 10
                let before = cut.location > 0 ? text.character(at: cut.location - 1) : 10
                if before == 32 {
                    cut.location -= 1
                    cut.length += 1
                } else if after == 32 {
                    cut.length += 1
                } else if NSMaxRange(cut) < text.length, after == 10 {
                    cut.length += 1
                } else if cut.location > 0, before == 10 {
                    cut.location -= 1
                    cut.length += 1
                }
                var target = plainLength(spot)
                if target >= NSMaxRange(cut) {
                    target -= cut.length
                } else if target > cut.location {
                    target = cut.location
                }
                let rest = text.replacingCharacters(in: cut, with: "") as NSString
                target = min(max(target, 0), rest.length)
                let left = target > 0 ? rest.character(at: target - 1) : 10
                let right = target < rest.length ? rest.character(at: target) : 10
                let lead = left != 10 && left != 32 ? " " : ""
                let trail = right != 10 && right != 32 ? " " : ""
                let out = rest.replacingCharacters(in: NSRange(location: target, length: 0),
                                                   with: lead + piece + trail)
                return (out, target + (lead as NSString).length)
            }
            guard j != i, j != i + 1 else { return nil }
            // Вынуть взятое — и поставить тем же правилом, что и из ленты
            // (P586): своей строкой за абзацем, к ряду вложений — в ряд, на
            // пустую строку — на неё. Прежде у переноса в тексте, из ленты и
            // броска системой были три своих правила, и они расходились.
            var cut = NSRange(location: plainLength(i), length: (piece as NSString).length)
            var target = plainLength(para.location)
            let after = NSMaxRange(cut) < text.length ? text.character(at: NSMaxRange(cut)) : 10
            let before = cut.location > 0 ? text.character(at: cut.location - 1) : 10
            // Снимок из ряда (P348) уходит со своим пробелом, ряд остаётся
            // строкой; одинокий снимок — со своим переводом строки.
            if before == 32 {
                cut.location -= 1
                cut.length += 1
            } else if after == 32 {
                cut.length += 1
            } else if NSMaxRange(cut) < text.length, after == 10 {
                cut.length += 1
            } else if cut.location > 0, before == 10 {
                cut.location -= 1
                cut.length += 1
            }
            if target >= NSMaxRange(cut) {
                target -= cut.length
            } else if target > cut.location {
                target = cut.location
            }
            let rest = text.replacingCharacters(in: cut, with: "")
            return DiaryEditor.putting(piece, at: target, into: rest)
        }

        /// Строка поля — только снимки рядом (и пробелы между ними).
        static func photoRow(_ range: NSRange, in storage: NSAttributedString) -> Bool {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
            let ns = storage.string as NSString
            var photos = 0
            for k in range.location..<NSMaxRange(range) {
                // Любое вложение ряда — снимок, файл или точка (P560).
                if ns.character(at: k) == 0xFFFC,
                   storage.attribute(DiaryEditor.photoKey, at: k, effectiveRange: nil) != nil
                    || storage.attribute(DiaryEditor.lineKey, at: k, effectiveRange: nil) != nil {
                    photos += 1
                } else if ns.character(at: k) != 32 {
                    return false
                }
            }
            return photos > 0
        }

        // Долгое нажатие на снимок или точку iPhone сам превращал в меню
        // «Скопировать изображение / Сохранить в Фото» (P380) — его нет:
        // у вложений в записи свои касание и долгое нажатие.
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                      defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? { nil }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? { nil }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            // Метка касания не снимается здесь: поле может спросить
            // разрешения писать уже после этого — и должно получить отказ.
            guard g.state == .ended, let got = pressed else { return }
            // Это было долгое нажатие, а не касание: точка с крестиком
            // остаётся на экране, карта не открывается (P374).
            // Несут ли что-то сейчас — по картинке над пальцем, а не по
            // `taken`: ту ставит уже само касание, и после короткого касания
            // она оставалась — снимки в записи переставали открываться (P418).
            guard Date().timeIntervalSince(heldEnded) > 0.4, ghost == nil, cover == nil else { return }
            taken = nil
            if let link = got.photo { parent.onOpenPhoto?(link) }
            if let point = got.point { parent.onOpenPoint?(point) }
        }

        /// Касание пришлось на снимок или точку — клавиатура не нужна:
        /// человек открывает, а не пишет. Иначе заодно ставилась бы
        /// отметка времени.
        func textViewShouldBeginEditing(_ view: UITextView) -> Bool {
            !(pressed != nil && Date().timeIntervalSince(pressedAt) < 1.5)
        }

        /// Курсор переставлен: за вложением пишут обычными буквами.
        func textViewDidChangeSelection(_ view: UITextView) {
            if view.typingAttributes[DiaryEditor.lineKey] != nil
                || view.typingAttributes[DiaryEditor.photoKey] != nil {
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            }
        }

        // MARK: - Снимки

        /// Прочитать с диска картинки снимков, которые пока стоят пустыми
        /// клетками, и поставить их на место.
        func loadPhotos() {
            guard let view else { return }
            DiaryEditor.loadPhotos(in: view)
        }

        // MARK: - Клавиатура

        @objc private func keyboardMoved(_ note: Notification) {
            guard let view, let window = view.window,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
            else { return }
            // Полоска вложений — часть клавиатуры (P279): верх клавиатуры
            // уже её верх.
            // Строка вложений над клавиатурой — её часть (P546): верх
            // клавиатуры уже её верх.
            keyboardTop = window.convert(frame, from: nil).minY
            makeRoom(scroll: true)
            // Страница получает место под клавиатуру чуть позже самой
            // клавиатуры (P516): первая прокрутка к курсору видела ещё
            // короткую страницу и ничего не делала — строку, в которой
            // пишут, закрывало клавиатурой, пока не набирали букву.
            // Поэтому курсор доводится до глаз ещё раз, когда место уже есть.
            for delay in [0.3, 0.65] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.showCaret(animated: true)
                }
            }
        }

        @objc private func keyboardGone(_ note: Notification) {
            keyboardTop = nil
            makeRoom(scroll: false)
        }

        /// Освободить место под клавиатурой и довести курсор до глаз.
        ///
        /// Приложение нарочно не отдаёт клавиатуре весь экран: шестерёнка и
        /// нижние разделы стоят на месте всегда (P113). Значит, поле само
        /// отмеряет, сколько его закрыто снизу, и на столько же отступает
        /// изнутри — после чего курсор доводится обычной прокруткой поля,
        /// той же, какой человек листает текст рукой.
        ///
        /// Отступает только то поле, в котором пишут: у соседних страниц
        /// поле точно такое же, и трогать их нельзя — разойдутся строки
        /// (P114). Решение P174.
        private func makeRoom(scroll: Bool) {
            guard let view, let window = view.window else { return }
            let место = view.convert(view.bounds, to: window)
            // Отступ изнутри нужен только полю в коробке: растущему поле
            // место под клавиатурой отводит сама страница.
            let закрыто = view.isFirstResponder && !parent.grows
                ? (keyboardTop.map { max(0, место.maxY - $0) } ?? 0)
                : 0
            if view.contentInset.bottom != закрыто {
                view.contentInset.bottom = закрыто
                view.verticalScrollIndicatorInsets.bottom = закрыто
            }
            guard scroll, view.isFirstResponder else { return }
            // Прокрутка — следующим оборотом: к этому времени и курсор
            // стоит на месте, и высота поля пересчитана.
            DispatchQueue.main.async { [weak self] in self?.showCaret(animated: true) }
        }

        /// Довести курсор до глаз.
        ///
        /// Сперва — прокруткой самого поля: так устроены подробности дела,
        /// где поле стоит в отведённой коробке. Если внутри прокручивать
        /// нечего — поле подобрало себе высоту по тексту, как в дневнике, —
        /// едет вся страница, ровно настолько, насколько курсор зашёл под
        /// клавиатуру (решение P175).
        func showCaret(animated: Bool) {
            guard let view, view.isFirstResponder, let window = view.window,
                  let top = keyboardTop, let end = view.selectedTextRange?.end
            else { return }
            view.scrollRangeToVisible(view.selectedRange)

            let курсор = view.convert(view.caretRect(for: end), to: window)
            let ниже = курсор.maxY + 16 - top
            guard ниже > 0, let страница = page(over: view) else { return }
            let предел = max(0, страница.contentSize.height
                             + страница.adjustedContentInset.bottom
                             - страница.bounds.height)
            let куда = min(страница.contentOffset.y + ниже, предел)
            guard куда > страница.contentOffset.y else { return }
            страница.setContentOffset(CGPoint(x: страница.contentOffset.x, y: куда),
                                      animated: animated)
        }

        /// Ближайшая прокрутка над полем — сама страница дневника.
        private func page(over view: UITextView) -> UIScrollView? {
            var выше = view.superview
            while let здесь = выше {
                if let scroll = здесь as? UIScrollView { return scroll }
                выше = здесь.superview
            }
            return nil
        }

        /// Последняя правка добавила буквы (P558): только она — «писали».
        /// Стёртые пустые строки под записью, перенос строки, вставленный
        /// снимок — не набор, и час до новой отметки времени от них не
        /// отсчитывается заново.
        private var typedLetters = false

        func textViewDidChange(_ view: UITextView) {
            let now = DiaryEditor.plain(view.attributedText)
            parent.text = now
            if typedLetters, view.isFirstResponder,
               view.selectedRange.location >= view.textStorage.length {
                parent.onWrite?()
            }
            typedLetters = false
            if resolve != nil, DiaryEditor.hasLoosePicture(view.text) {
                // Строку-ссылку только что бросили или вписали — рисуем её
                // картинкой. Курсор остаётся примерно там, где был.
                let at = view.selectedRange.location
                view.attributedText = DiaryEditor.styled(now, size: parent.size,
                                                         serif: parent.serif,
                                                         stamped: parent.stamped,
                                                         resolve: resolve)
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                view.selectedRange = NSRange(location: min(at, view.textStorage.length), length: 0)
                loadPhotos()
            } else {
                restyle(view)
            }
            // Строка прибавилась — курсор мог уйти под клавиатуру.
            DispatchQueue.main.async { [weak self] in self?.showCaret(animated: false) }
        }

        /// Первая буква строки после отметки времени набирается заглавной.
        ///
        /// Не только при наборе: диктовка вставляет целую фразу разом, и её
        /// первая буква должна вести себя так же.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            typedLetters = text.contains { !$0.isWhitespace && $0 != "\u{FFFC}" }
            if let decided = keepObjectsApart(view, range, text) { return decided }
            // Первая буква в новой строке под записью — и только тогда
            // перед ней встаёт время (P403). Буква — заглавная.
            // Только с чистой строки и только буквой: пробел и продолжение
            // начатой строки отметку не зовут (P528) — в P520 пробел после
            // паузы перебрасывал текст на новый абзац с отметкой.
            if range.length == 0, range.location == view.textStorage.length,
               let first = text.first, !first.isWhitespace, !text.contains("\u{FFFC}"),
               view.textStorage.string.isEmpty || view.textStorage.string.hasSuffix("\n"),
               let stamp = parent.takeStamp?() {
                let piece = stamp + String(first).uppercased() + String(text.dropFirst())
                view.textStorage.replaceCharacters(
                    in: range,
                    with: NSAttributedString(string: piece,
                                             attributes: DiaryEditor.body(parent.size, serif: parent.serif)))
                view.selectedRange = NSRange(location: range.location + (piece as NSString).length, length: 0)
                textViewDidChange(view)
                return false
            }
            guard parent.stamped,
                  let first = text.first, first.isLowercase else { return true }
            let before = (view.text as NSString).substring(to: range.location)
            guard let line = before.components(separatedBy: .newlines).last,
                  line.range(of: #"^\d{2}:\d{2}( \d{2}\.\d{2}\.\d{2})?[  ]+$"#,
                             options: .regularExpression) != nil
            else { return true }

            let upper = String(first).uppercased() + String(text.dropFirst())
            // Правка — в самом тексте поля, а не заменой всего текста:
            // иначе снимки в нём превратились бы в знаки-заместители.
            view.textStorage.replaceCharacters(in: range, with: upper)
            let after = range.location + (upper as NSString).length
            view.selectedRange = NSRange(location: after, length: 0)
            parent.text = DiaryEditor.plain(view.attributedText)
            restyle(view)
            return false
        }

        // MARK: - Вложение — своя строка (P392)

        /// Снимок, точка, голос или файл в поле (знак вложения с нашей
        /// меткой).
        private func isObject(_ i: Int, in storage: NSTextStorage) -> Bool {
            guard i >= 0, i < storage.length,
                  (storage.string as NSString).character(at: i) == 0xFFFC else { return false }
            return storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
                || storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) != nil
        }

        /// В строке есть вложение и есть буквы: так быть не должно.
        static func mixed(_ s: NSString, objects: Set<Int>, in para: NSRange) -> Bool {
            var object = false, letters = false
            for i in para.location..<NSMaxRange(para) {
                if objects.contains(i) { object = true; continue }
                let c = s.character(at: i)
                if c != 32, c != 10, c != 13, c != 9, c != 0xA0 { letters = true }
            }
            return object && letters
        }

        /// Одно вложение — одна строка (P392). Вложение не стирается
        /// клавишей и не заменяется набранным — только крестиком. Буквы,
        /// набранные в строке вложения, уходят своей строкой — над ним, если
        /// курсор стоял перед ним, и под ним, если после. Стереть перевод
        /// строки так, чтобы текст въехал в строку вложения, нельзя. Прежде
        /// снимок под курсором заменялся набранным, а в строку с точкой можно
        /// было дописывать — хотя перенесённая точка встаёт своей строкой.
        /// `nil` — правка обычная, решает поле.
        private func keepObjectsApart(_ view: UITextView, _ range: NSRange, _ text: String) -> Bool? {
            // Диктовка ставит свой временный знак — его не трогаем (P197).
            guard !text.contains("\u{FFFC}") else { return nil }
            let storage = view.textStorage
            let old = storage.string as NSString
            guard NSMaxRange(range) <= old.length else { return nil }
            var objects = Set<Int>()
            for i in 0..<old.length where old.character(at: i) == 0xFFFC && isObject(i, in: storage) {
                objects.insert(i)
            }
            guard !objects.isEmpty else { return nil }
            if objects.contains(where: { NSLocationInRange($0, range) }) { return false }
            // Строка, где вложение уже стоит посреди слов (записи до этого
            // правила), правится как раньше — только само вложение не
            // стирается.
            if Self.mixed(old, objects: objects, in: old.paragraphRange(for: range)) { return nil }
            let added = text as NSString
            let new = old.replacingCharacters(in: range, with: text) as NSString
            let shift = added.length - range.length
            let moved = Set(objects.map { $0 >= NSMaxRange(range) ? $0 + shift : $0 })
            let touched = new.paragraphRange(for: NSRange(location: range.location, length: added.length))
            guard Self.mixed(new, objects: moved, in: touched) else { return nil }
            // Стирали — и текст въехал бы в строку вложения: не стираем.
            guard added.length > 0, range.length == 0 else { return false }
            let para = old.paragraphRange(for: NSRange(location: range.location, length: 0))
            let first = objects.filter { NSLocationInRange($0, para) }.min() ?? para.location
            var end = NSMaxRange(para)
            if end > para.location, old.character(at: end - 1) == 10 { end -= 1 }
            let at: Int, piece: String, caret: Int
            if range.location <= first {
                at = para.location
                piece = text + "\n"
                caret = at + added.length
            } else {
                at = end
                // Пишут за вложением, стоящим последним в записи: своя строка
                // — и, как всякая новая строка в конце, с отметкой времени
                // (P591; прежде отметку здесь обходили).
                var typed = text
                if at == old.length, let first = text.first, !first.isWhitespace,
                   let stamp = parent.takeStamp?() {
                    typed = stamp + String(first).uppercased() + String(text.dropFirst())
                }
                piece = "\n" + typed
                caret = at + 1 + (typed as NSString).length
            }
            storage.replaceCharacters(in: NSRange(location: at, length: 0),
                                      with: NSAttributedString(string: piece,
                                                               attributes: DiaryEditor.body(parent.size, serif: parent.serif)))
            view.selectedRange = NSRange(location: min(caret, storage.length), length: 0)
            textViewDidChange(view)
            return false
        }

        /// Перекрасить отметки времени, не сдвинув курсор.
        ///
        /// Краска кладётся на тот же текст, а не заменяет его новым: замена
        /// выдёргивала у диктовки её временный знак, и в записи оставалось
        /// «OBJ» (решение P197). Заодно курсор и выделение не трогаются.
        func restyle(_ view: UITextView) {
            let text = view.text ?? ""
            let ns = text as NSString
            let всё = NSRange(location: 0, length: ns.length)
            let body = DiaryEditor.body(parent.size, serif: parent.serif)
            let storage = view.textStorage
            storage.beginEditing()
            storage.addAttributes(body, range: всё)
            // Отметка ищется в начале каждой строки — так же, как при
            // первой раскраске поля.
            var start = 0
            while parent.stamped, start < ns.length {
                let line = ns.lineRange(for: NSRange(location: start, length: 0))
                if let place = DiaryEditor.placeRange(in: ns, line: line) {
                    storage.addAttributes(DiaryEditor.placeLook(parent.size), range: place)
                }
                if let m = DiaryEditor.stamp.firstMatch(in: text, range: line),
                   m.numberOfRanges > 1 {
                    storage.addAttributes([
                        .font: UIFont.monospacedSystemFont(ofSize: parent.size * 0.84,
                                                           weight: .regular),
                        .foregroundColor: UIColor(Look.inkFaint),
                    ], range: m.range(at: 1))
                }
                guard line.length > 0 else { break }
                start = line.location + line.length
            }
            storage.endEditing()
            view.typingAttributes = body
        }
    }
}

/// Точка в тексте записи: кнопочка с названием и координатами, бледная,
/// как отметка времени (P213).
final class PointChip: NSTextAttachment {

    /// Точка в тексте — значок шириной в знак-два, прямо в строке (P259).
    /// Название и координаты — на карте, куда ведёт касание.
    init(mini point: GeoPoint, glowing: Bool = false) {
        super.init(data: nil, ofType: nil)
        let picture = PointChip.mark(glowing: glowing, title: point.title)
        image = picture
        let pad: CGFloat = glowing ? 3 : 0
        bounds = CGRect(origin: CGPoint(x: 0, y: -5 - pad), size: picture.size)
        accessibilityLabel = T("Точка на карте: ", "Place on the map: ") + point.label
    }

    /// Точка своей строкой — квадрат размером со снимок (P559): булавка
    /// и подпись — название, а без него — «Место» и, если рядом своё место,
    /// сколько до него. Как голос и файл, все вложения — одного вида.
    init(tile point: GeoPoint, glowing: Bool = false) {
        super.init(data: nil, ofType: nil)
        let given = point.title.trimmingCharacters(in: .whitespaces)
        let name = given.isEmpty ? T("Место", "Place") : given
        let note = given.isEmpty ? Places.caption(for: point.at) : nil
        let picture = PointChip.square(name, note: note, glowing: glowing)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: picture.size)
        accessibilityLabel = T("Точка на карте: ", "Place on the map: ") + point.label
    }

    static func square(_ name: String, note: String?, glowing: Bool) -> UIImage {
        let size = DiaryEditor.photoSize
        let red = UIColor(Look.pin)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 6)
            UIColor(Look.planBg).setFill()
            shape.fill()
            red.withAlphaComponent(0.10).setFill()
            shape.fill()
            (glowing ? UIColor(Look.glow) : red.withAlphaComponent(0.6)).setStroke()
            shape.lineWidth = glowing ? 2.2 : 1.2
            shape.stroke()
            if let pin = UIImage(systemName: "mappin.circle.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: size.width * 0.26,
                                                                                weight: .semibold))?
                .withTintColor(red, renderingMode: .alwaysOriginal) {
                pin.draw(at: CGPoint(x: (size.width - pin.size.width) / 2, y: size.height * 0.12))
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(11, size.width * 0.125), weight: .semibold),
                .foregroundColor: UIColor(Look.ink), .paragraphStyle: style,
            ]
            let small: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10.5),
                .foregroundColor: UIColor(Look.inkSoft), .paragraphStyle: style,
            ]
            let top = size.height * 0.52
            let lines: CGFloat = note == nil ? 2 : 1
            let titleFont = title[.font] as! UIFont
            (name as NSString).draw(
                with: CGRect(x: 5, y: top, width: size.width - 10, height: titleFont.lineHeight * lines),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: title, context: nil)
            if let note {
                (note as NSString).draw(
                    with: CGRect(x: 4, y: top + titleFont.lineHeight + 2, width: size.width - 8,
                                 height: UIFont.systemFont(ofSize: 10.5).lineHeight * 2),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: small, context: nil)
            }
        }
    }

    /// Булавка; у точки с названием — и название рядом (P284). Красная
    /// булавка на светло-красной подложке с красной кромкой — точку видно в
    /// тексте сразу (P358).
    static func mark(glowing: Bool, title: String = "") -> UIImage {
        let pad: CGFloat = glowing ? 3 : 0
        let red = UIColor(Look.pin)
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: UIColor(Look.ink)]
        // Точка без названия подписана «Место» (P380): одна булавка в
        // строке не читалась как запись.
        let given = title.trimmingCharacters(in: .whitespaces)
        let name = given.isEmpty ? T("Место", "Place") : given
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let chip = CGSize(width: name.isEmpty ? 24 : 24 + wide + 8, height: 21)
        let size = CGSize(width: chip.width + pad * 2, height: chip.height + pad * 2)
        let pin = UIImage(systemName: "mappin.circle.fill",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.5,
                                                                         weight: .semibold))?
            .withTintColor(red, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let box = CGRect(x: pad, y: pad, width: chip.width, height: chip.height)
                .insetBy(dx: 0.6, dy: 0.6)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 7)
            if glowing {
                ctx.cgContext.setShadow(offset: .zero, blur: 4, color: UIColor(Look.glow).cgColor)
            }
            UIColor(Look.planBg).setFill()
            shape.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            red.withAlphaComponent(0.13).setFill()
            shape.fill()
            (glowing ? UIColor(Look.glow) : red.withAlphaComponent(0.75)).setStroke()
            shape.lineWidth = glowing ? 1.6 : 1.2
            shape.stroke()
            if let pin {
                let s = pin.size
                pin.draw(in: CGRect(x: pad + (24 - s.width) / 2,
                                    y: pad + (chip.height - s.height) / 2,
                                    width: s.width, height: s.height))
            }
            if !name.isEmpty {
                (name as NSString).draw(
                    with: CGRect(x: pad + 22, y: pad + (chip.height - font.lineHeight) / 2,
                                 width: wide, height: font.lineHeight),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: words, context: nil)
            }
        }
    }

    required init?(coder: NSCoder) { nil }

}

/// Голос, видео или документ в тексте записи (P377) — кнопочка со значком
/// и именем файла, как точка. Касание открывает, долгое нажатие несёт.
final class FileChip: NSTextAttachment {

    init(link: String) {
        super.init(data: nil, ofType: nil)
        let picture = FileChip.draw(link)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: picture.size)
        accessibilityLabel = FileChip.name(link)
    }

    required init?(coder: NSCoder) { nil }

    static func name(_ link: String) -> String {
        ((link as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func draw(_ link: String) -> UIImage {
        let icon: String
        switch Diary.kind(of: link) {
        case .audio: icon = "waveform"
        case .video: icon = "film"
        default: icon = "doc"
        }
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        let name = Self.name(link)
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let size = CGSize(width: 26 + wide + 9, height: 21)
        let tint = UIColor(Look.accent)
        let glyph = UIImage(systemName: icon,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.6, dy: 0.6),
                                     cornerRadius: 7)
            UIColor(Look.planBg).setFill()
            shape.fill()
            tint.withAlphaComponent(0.1).setFill()
            shape.fill()
            tint.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
            if let glyph {
                let s = glyph.size
                glyph.draw(in: CGRect(x: (26 - s.width) / 2, y: (size.height - s.height) / 2,
                                      width: s.width, height: s.height))
            }
            (name as NSString).draw(
                with: CGRect(x: 24, y: (size.height - font.lineHeight) / 2, width: wide, height: font.lineHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: words, context: nil)
        }
    }
}

/// Снимок в тексте записи.
///
/// Помнит свою строку-ссылку: по ней поле возвращает в файл ту же строку,
/// какая там и была (решение P204).
final class PhotoAttachment: NSTextAttachment {

    let link: String
    let url: URL?
    /// Картинку уже прочитали или читают — второй раз не надо.
    var loaded = false

    init(link: String, url: URL?) {
        self.link = link
        self.url = url
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: DiaryEditor.photoSize)
        // Голос, видео, документ — плитка со значком того же размера, что
        // снимок (P456). Читать с диска нечего.
        if Diary.kind(of: link) != .photo {
            image = PhotoAttachment.tile(link)
            loaded = true
            accessibilityLabel = FileChip.name(link)
            return
        }
        if let url, let cached = Photo.cache.object(forKey: PhotoAttachment.key(url)) {
            image = cached
            loaded = true
        } else {
            image = PhotoAttachment.empty
        }
    }

    required init?(coder: NSCoder) { nil }

    static func key(_ url: URL) -> NSString { ("в тексте:" + url.path) as NSString }

    /// Пустая клетка, пока картинка идёт с диска.
    static let empty: UIImage = UIGraphicsImageRenderer(size: DiaryEditor.photoSize).image { _ in
        let box = CGRect(origin: .zero, size: DiaryEditor.photoSize)
        UIColor(Look.chrome).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
    }

    /// Плитка голоса, видео или документа — как в полоске внизу: значок и
    /// подпись на бумаге с тонкой рамкой (P456).
    static func tile(_ link: String) -> UIImage {
        let size = DiaryEditor.photoSize
        let kind = Diary.kind(of: link)
        let icon = kind == .audio ? "waveform" : kind == .video ? "play.rectangle" : "doc.text"
        let label = kind == .audio ? T("голос", "voice") : kind == .video ? T("видео", "video")
            : ((link as NSString).pathExtension.lowercased().isEmpty
                ? T("файл", "file") : (link as NSString).pathExtension.lowercased())
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            let shape = UIBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6)
            UIColor(Look.chrome).setFill()
            shape.fill()
            UIColor(Look.rule).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            let tint = UIColor(Look.inkSoft)
            if let symbol = UIImage(systemName: icon,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: size.width * 0.22,
                                                                                   weight: .regular))?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: box.midX - symbol.size.width / 2,
                                        y: box.midY - symbol.size.height * 0.85))
            }
            let words: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(10, size.width * 0.1)),
                .foregroundColor: tint,
            ]
            let text = label as NSString
            let used = text.size(withAttributes: words)
            text.draw(at: CGPoint(x: box.midX - min(used.width, box.width - 8) / 2, y: box.midY + 6),
                      withAttributes: words)
        }
    }

    /// Снимок, обрезанный по клетке и со скруглёнными углами.
    static func frame(_ image: UIImage) -> UIImage {
        let size = DiaryEditor.photoSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: box, cornerRadius: 6).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2,
                                  width: w, height: h))
        }
    }
}

extension DiaryEditor {
    /// Вложение, которое сейчас несут: в показе «куда ляжет» его место —
    /// пунктирная рамка (P593). Пусто — ничего не несут.
    static var awaiting: String?
}

/// Пунктирная рамка размером со снимок — сюда ляжет несомое (P593).
final class AwaitingSlot: NSTextAttachment {
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        let size = DiaryEditor.photoSize
        image = UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 6)
            UIColor(Look.glow).withAlphaComponent(0.08).setFill()
            shape.fill()
            shape.lineWidth = 2
            shape.setLineDash([7, 5], count: 2, phase: 0)
            UIColor(Look.glow).withAlphaComponent(0.85).setStroke()
            shape.stroke()
        }
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: size)
    }

    convenience init() { self.init(data: nil, ofType: nil) }

    required init?(coder: NSCoder) { nil }
}
