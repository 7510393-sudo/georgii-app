import SwiftUI

/// Поиск по архиву.
///
/// Ищет по тому, что лежит в файлах: по заголовку дня, по тексту записи, по
/// названиям дел и по ответам «Как прошло?». Показывает при этом только
/// заголовок и текст: ответы — служебная часть записи, в выдаче от них
/// рябит. Но если искомое слово нашлось именно в них, день всё равно
/// попадает в список — иначе поиск лгал бы.
struct SearchView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var vault: Vault

    /// Строка поиска лежит в оболочке: её очищает и меню поиска.
    private var query: String { shell.query }
    @FocusState private var typing: Bool

    /// Насколько клавиатура закрывает список находок.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            field
            if archive.newestFirst.isEmpty {
                message(T("Пока нечего искать.", "Nothing to search yet."),
                        T("Напишите первую запись — и она найдётся здесь.",
                          "Write your first entry, and it will turn up here."))
            } else if found.isEmpty {
                message(T("Ничего не нашлось.", "Nothing found."),
                        T("По запросу «\(query)» \(whereNot)записей нет.",
                          "No entries \(whereNot)match “\(query)”."))
            } else {
                list
            }
        }
        .keyboardHeight($keyboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Фон поиска — ровный, без фактуры (P696): фактурная бумага — сами
        // карточки, а не стол под ними (замена P693).
        .background(Scheme.current.today.overlay(Color.black.opacity(0.05)))
    }

    /// Строка поиска стоит вместо заголовка «Поиск» — между уголками
    /// шестерёнки и трёх точек, лупа слева на том же месте, что и на
    /// карте (P334).
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField(prompt, text: $shell.query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { shell.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Look.inkFaint)
                    .accessibilityLabel(T("Очистить", "Clear"))
            }
            filterMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Полупрозрачная: под ней видна петля ленты находок (P716).
        .background(Look.chrome.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        // Тот же отступ от уголков, что у строки поиска на карте.
        .padding(.leading, Corner.size + 8)
        .padding(.trailing, Corner.size + 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Где и что искать — меню в самой строке поиска (P632; прежде в меню
    /// уголка). Горит, когда ищем не по всему архиву.
    private var filterMenu: some View {
        Menu {
            scopeButton(T("Искать везде", "Search everywhere"), .all)
            scopeButton(T("Только в дневнике", "Only in the diary"), .diary)
            scopeButton(T("Только в плане", "Only in the plan"), .plan)
            Divider()
            ForEach(Shell.Find.allCases, id: \.self) { kind in
                Button {
                    shell.find = kind
                } label: {
                    let title = kind == .all ? T("Искать всё", "Find everything")
                                             : T("Только: ", "Only: ") + kind.title.lowercased()
                    if shell.find == kind { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(shell.scope != .all || shell.find != .all ? Look.accent : Look.inkFaint)
        }
        .accessibilityLabel(T("Что и где искать", "What and where to search"))
    }

    private func scopeButton(_ title: String, _ scope: Shell.Scope) -> some View {
        Button {
            shell.scope = scope
        } label: {
            if shell.scope == scope { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// Где ищем — видно прямо в строке поиска, а не только в меню: иначе,
    /// выбрав «только в плане» и забыв об этом, человек решит, что запись
    /// пропала.
    private var prompt: String {
        switch shell.scope {
        case .all:   return T("Поиск по словам", "Search")
        case .diary: return T("Поиск в дневнике", "Search the diary")
        case .plan:  return T("Поиск в плане", "Search the plan")
        }
    }

    private var whereNot: String {
        switch shell.scope {
        case .all:   return ""
        case .diary: return T("в дневнике ", "in the diary ")
        case .plan:  return T("в плане ", "in the plan ")
        }
    }

    /// Ответы «Как прошло?» — часть дневника: их пишут там, а не в плане.
    private var found: [Archive.Day] {
        let days = archive.newestFirst.filter(kept)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        // Пока ничего не набрано, список начинается с последнего заполненного
        // дня: пустые будущие дни, заведённые планировщиком (повторы, дела
        // вперёд), в нём ничего не говорят (P426).
        guard !needle.isEmpty else {
            let today = DayStore.today()
            return days.filter { $0.date <= today || !$0.isPlanOnly }
        }
        let scope = shell.scope
        return days.filter { day in
            if scope != .plan {
                if day.title.lowercased().contains(needle) { return true }
                if day.text.lowercased().contains(needle) { return true }
                if day.answers.values.contains(where: { $0.lowercased().contains(needle) }) {
                    return true
                }
            }
            if scope != .diary {
                return day.tasks.contains { $0.text.lowercased().contains(needle) }
            }
            return false
        }
    }

    /// Подходит ли день под «что искать» из меню поиска (P249).
    private func kept(_ day: Archive.Day) -> Bool {
        let kinds = day.attachments.map { Diary.kind(of: $0) }
        switch shell.find {
        case .all:   return true
        case .photo: return kinds.contains(.photo)
        case .video: return kinds.contains(.video)
        case .audio: return kinds.contains(.audio)
        case .file:  return kinds.contains(.file)
        case .place:
            return day.place != nil || day.text.contains("geo:")
        }
    }

    private var list: some View {
        // Выборка считается один раз, а не на каждую карточку.
        // На снимке CI «лента поиска» находки повторены, чтобы было что
        // листать (P717).
        let days = Search.deep ? Array(repeating: found, count: 12).flatMap { $0 } : found
        let items = days.enumerated().map { index, day in
            Search.Item(id: Search.deep ? String(index) : day.id, index: index, day: day)
        }
        return ScrollViewReader { proxy in ScrollView {
            // Находки — карточки картотеки, вид сверху: нижняя лежит поверх
            // верхней и своим корешком с датой закрывает её низ (P694, P695).
            LazyVStack(spacing: -Search.overlap) {
                ForEach(items) { item in
                    SearchCard(stamp: Search.stamp(item.day.date)) { row(item.day) }
                        // Лента поворачивает вдаль, как по большому цилиндру
                        // (P712): каждая карточка искажается той же общей
                        // формулой по своему месту на экране, поэтому края
                        // соседних сходятся точно и ступенек нет.
                        .modifier(Ribbon(index: item.index, preview: Vault.isPreview && !Search.deep))
                }
            }
            .padding(.horizontal, 10)
            // `lift` — запас над списком: туда лента заходит и оттуда уходит
            // к горизонту (P707, P712).
            .padding(.top, Search.lift + Search.restTop)
            // Место под клавиатуру. Без него последние находки лежат под
            // ней и не достаются прокруткой: список кончается там, где
            // начинается клавиатура (решение P174).
            // Строки разделов над клавиатурой больше нет (P505).
            .padding(.bottom, keyboard > 0 ? keyboard + 4 : 0)
            // Изнанка ленты (P715): за дальним концом лента заворачивается
            // по невидимому валику и спускается обратно позади карточек.
            // Рисуется под всеми карточками, на месте экрана, а не списка.
            .background(alignment: .top) {
                GeometryReader { g in
                    let contentTop = g.frame(in: .named(Search.space)).minY
                    RibbonBack(contentTop: contentTop, count: days.count,
                               preview: Vault.isPreview && !Search.deep)
                        .frame(width: g.size.width, height: Search.lift + 2 * Search.pitch)
                        .offset(y: -contentTop)
                }
            }
        }
        .coordinateSpace(name: Search.space)
        // Второе нажатие на «Поиск» — список заново, с начала (P576).
        .id(shell.searchHome)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Снимок «лента поиска»: список пролистан, как у человека.
            guard Search.deep else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                proxy.scrollTo("20", anchor: .top)
            }
        }
        }
        .animation(.easeOut(duration: 0.25), value: keyboard)
        // У самого горизонта лента тает.
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: Search.lift - Search.fieldHeight)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 3)
                Color.black
            }
        }
        // Список продолжается вверх на `lift` — под строку поиска; строка
        // лежит выше и принимает касания.
        .padding(.top, -Search.lift)
        .zIndex(-1)
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            typing = false
            store.go(to: day.date)
            // Искали в плане — туда и открываем: там нашлось искомое.
            shell.tab = shell.scope == .plan || (day.text.isEmpty && !day.tasks.isEmpty)
                ? .plan : .diary
            shell.screen = .today
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: Search.lineGap) {
                    // Дата — на корешке карточки (P695): год, месяц, число —
                    // в этом порядке, при поиске по архиву сначала выбирают
                    // время, а не день недели (P282).
                    if !day.title.isEmpty {
                        Text(Geo.stripped(day.title))
                            .font(Look.serif(15, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .lineLimit(1)
                    }
                    if !day.text.isEmpty {
                        Text(day.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(day.title.isEmpty ? 5 : 4)
                            .multilineTextAlignment(.leading)
                    }
                }
                // Ровно пять строк: низ пятой строки — на одной линии с низом
                // снимка (P696).
                .frame(height: Search.body, alignment: .top)
                Spacer(minLength: 0)
                if let cover = day.cover { preview(cover, of: day) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    /// Превью справа от находки: снимок, кадр видео, голос или документ
    /// (P215).
    @ViewBuilder private func preview(_ link: String, of day: Archive.Day) -> some View {
        let url = vault.mediaURL(link, for: day.date)
        Group {
            switch Diary.kind(of: link) {
            case .photo: PhotoThumb(url: url)
            case .video: PhotoThumb(url: url, video: true)
            case .audio: FileTile(icon: "waveform", label: T("голос", "voice"))
            case .file:  FileTile(icon: "doc.text",
                                  label: (link as NSString).pathExtension.lowercased())
            }
        }
        // Превью — той же высоты, что блок из пяти строк (P282, P696): низы
        // совпадают.
        .frame(width: Search.body, height: Search.body)
    }

    private func message(_ head: String, _ tail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(head).font(Look.sans(15)).foregroundStyle(Look.inkSoft)
            Text(tail).font(Look.sans(13)).foregroundStyle(Look.inkFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

/// Искажение карточки (P707, P712). Шейдер на весь список не годится:
/// прокрутку рисует сама система, и шейдер получал пустую картинку (снимок CI
/// 30.10). Карточка же рисуется целиком SwiftUI. `index` — место карточки в
/// списке: по нему видно, на сколько список пролистан.
private struct Ribbon: ViewModifier {
    let index: Int
    /// Снимки и проверки CI (`Vault.isPreview`).
    let preview: Bool

    func body(content: Content) -> some View {
        let index = index, preview = preview
        return content.visualEffect { view, proxy in
            Search.bend(view, proxy, index: index, preview: preview)
        }
    }
}

/// Петля и изнанка ленты находок (P715–P717) — по рисунку автора. Дальний
/// конец передней ленты под строкой поиска перекатывается петлёй до самого
/// верха экрана, а изнанка выходит из неё правее и спускается полосой вдоль
/// правого края передней ленты, пока не уйдёт за карточки. Между передней
/// лентой и изнанкой — просвет петли (на рисунке — овал). Изнанка — старая
/// бумага без текста, с тёмной границей у каждой карточки, чтобы было видно
/// движение. Где идёт полоса, взято с рисунка (`Search.backTrack`).
///
/// Всё едет с той же скоростью, что передняя часть: петля забирает столько
/// ленты, сколько прошло бы по экрану за то же время у дальнего конца, а
/// место изнанки `d` точек за петлёй стоит на той высоте, где передняя лента
/// на `d` точек не доходит до дальнего конца.
private struct RibbonBack: View {
    /// Верх содержимого прокрутки в системе списка (`Search.space`).
    let contentTop: CGFloat
    let count: Int
    let preview: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let paper = Scheme.current.past
        let dark = scheme == .dark
        let edge = Scheme.current.kraftEdge
        return Canvas { ctx, size in
            let lift = Search.lift, pitch = Search.pitch
            let scrolled = preview ? 2 * pitch : max(0, -contentTop)
            let (bend, horizon, r, f, roll) = Search.shape(scrolled: scrolled)
            guard roll > 0 else { return }
            let width = size.width
            let half = (width - 20) / 2
            // Холст начинается на `lift` выше верха списка; экран поиска —
            // на `fieldHeight` выше верха списка.
            let toCanvas = lift - Search.fieldHeight
            let end = Search.curl(roll, bend: bend, horizon: horizon, r: r, f: f)
            let endView = end.y + Search.fieldHeight
            // Полоса изнанки по рисунку: середина и полуширина на высоте `y`.
            func track(_ y: CGFloat) -> (x: CGFloat, w: CGFloat) {
                let t = Search.backTrack
                guard y > t[0].y else { return (t[0].x * width, t[0].w * width) }
                for k in 1..<t.count where y <= t[k].y {
                    let u = (y - t[k - 1].y) / (t[k].y - t[k - 1].y)
                    return ((t[k - 1].x + (t[k].x - t[k - 1].x) * u) * width,
                            (t[k - 1].w + (t[k].w - t[k - 1].w) * u) * width)
                }
                return (t[t.count - 1].x * width, t[t.count - 1].w * width)
            }
            let start = track(endView)
            // Середина дальнего конца: лента сходится к `vanish`.
            let vx = 10 + Search.vanish * (width - 20)
            let endX = vx + (width / 2 - vx) * end.s
            let a = (start.x - endX) / 2
            let b = max(endView - Search.loopTopView, 4)
            // Петля забирает столько ленты, сколько у дальнего конца проходит
            // по экрану за её длину.
            // Петля — `loopCards` карточек: на ней полосы идут чуть быстрее,
            // чем у дальнего конца, зато она не съедает весь список.
            let loop = Search.loopCards * pitch
            // Место ленты `d` точек за дальним концом: высота на холсте,
            // середина, полуширина, глубина (для порядка) и темнота.
            func place(_ d: CGFloat) -> (y: CGFloat, x: CGFloat, w: CGFloat, z: CGFloat, dim: Double) {
                if d < loop {
                    let th = .pi * d / loop
                    let u = (1 - cos(th)) / 2
                    return (endView - b * sin(th) + toCanvas, endX + a * (1 - cos(th)),
                            half * end.s + (start.w - half * end.s) * u, u,
                            0.05 + 0.13 * Double(u))
                }
                let c = max(roll - (d - loop), 0)
                let y = Search.curl(c, bend: bend, horizon: horizon, r: r, f: f).y
                    + Search.fieldHeight
                let q = track(y)
                return (y + toCanvas, q.x, q.w, 2, 0.2)
            }
            let reach = loop + roll
            // Куски ленты: дальние рисуются первыми.
            var pieces: [(z: CGFloat, path: Path, dim: Double)] = []
            var lines: [(z: CGFloat, path: Path, width: CGFloat)] = []
            // Лента — замкнутая петля: на петле и изнанке едут и те
            // карточки, что выше первой находки, — без текста их не
            // отличить, а изнанка видна всегда, сколько ни листай.
            guard count > 0 || preview else { return }
            let first = max(-400, Int(((bend - roll - reach - contentTop - Search.restTop) / pitch)
                .rounded(.down)) - 1)
            guard first < max(count, 1) else { return }
            for i in first..<max(count, 1) {
                let y = contentTop + Search.restTop + CGFloat(i) * pitch
                let top = bend - y - roll
                guard top > 0 else { continue }
                let near = max(top - pitch, 0)
                let far = min(top, reach)
                guard far > near else { continue }
                let n = max(2, min(16, Int((far - near) / pitch * 10)))
                var prev = place(near)
                for j in 1...n {
                    let q = place(near + (far - near) * CGFloat(j) / CGFloat(n))
                    var p = Path()
                    p.addLines([CGPoint(x: prev.x - prev.w, y: prev.y),
                                CGPoint(x: prev.x + prev.w, y: prev.y),
                                CGPoint(x: q.x + q.w, y: q.y),
                                CGPoint(x: q.x - q.w, y: q.y)])
                    p.closeSubpath()
                    pieces.append(((prev.z + q.z) / 2, p, (prev.dim + q.dim) / 2))
                    prev = q
                }
                // Граница карточки — у её верха (корешка).
                if top <= reach {
                    let q = place(top)
                    var line = Path()
                    line.move(to: CGPoint(x: q.x - q.w, y: q.y))
                    line.addLine(to: CGPoint(x: q.x + q.w, y: q.y))
                    lines.append((q.z, line, 0.8))
                }
            }
            pieces.sort { $0.z > $1.z }
            for piece in pieces {
                // Обводка тем же цветом — без волосяных щелей между кусками.
                ctx.fill(piece.path, with: .color(paper))
                ctx.stroke(piece.path, with: .color(paper), lineWidth: 0.6)
                ctx.fill(piece.path, with: .color(.black.opacity(piece.dim * (dark ? 2 : 1))))
            }
            for line in lines {
                ctx.stroke(line.path, with: .color(edge), lineWidth: line.width)
            }
        }
        .allowsHitTesting(false)
    }
}

enum Search {
    /// Высота корешка карточки (P695).
    static let tabHeight: CGFloat = 22
    /// На сколько карточка заходит на предыдущую: корешок и ещё немного
    /// листа, чтобы нижний край предыдущей скрылся под ней (P696).
    static let overlap: CGFloat = tabHeight + 10

    static let lineGap: CGFloat = 3

    /// Шаг карточек: сколько видно каждой до следующей — корешок, пять строк
    /// и немного воздуха (P697).
    static var pitch: CGFloat { tabHeight + 8 + body + 6 }

    /// Система координат прокрутки: по ней карточка знает своё место.
    static let space = "searchList"
    /// Где стоит первая находка, пока список не листали (от верха списка).
    static let restTop: CGFloat = 4
    /// Где лента начинает поворачивать (от верха списка), когда список
    /// пролистан: за одну карточку до верха (P712, по согласию автора; прежде
    /// за треть — поворот выходил слишком резким). Пока список в начале,
    /// изгиба нет: он «вырастает» по мере листания (`bendNow`).
    static var bendMax: CGFloat { pitch }
    /// Высота строки поиска над списком (с отступами): до её верха лента
    /// видна (P716).
    static let fieldHeight: CGFloat = 56
    /// Мерки с рисунка автора (P717), снятые с его контуров поверх снимка, в
    /// точках от верха экрана поиска (верх строки поиска — 8). Передняя
    /// лента уходит к горизонту чуть выше экрана: шириной 0,35 на высоте 44,
    /// 0,53 — на 80, 0,69 — на 104, 0,79 — на 128.
    static let horizonView: CGFloat = -18
    /// Куда сходится лента — левее середины (на рисунке подъём уведён влево,
    /// мы смотрим чуть справа): доля ширины карточки.
    static let vanish: CGFloat = 0.366
    /// Горизонт в системе списка.
    static var horizon: CGFloat { horizonView - fieldHeight }
    /// Верх петли — у самого верха экрана поиска (на рисунке 0).
    static let loopTopView: CGFloat = 2
    /// Изнанка с рисунка: высота (от верха экрана поиска), середина и
    /// полуширина — доли ширины экрана. Выходит из петли правее передней
    /// ленты и спускается вдоль её правого края, пока не уйдёт за карточки.
    static let backTrack: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
        (20, 0.726, 0.057), (44, 0.769, 0.075), (68, 0.791, 0.082), (80, 0.796, 0.087),
        (104, 0.82, 0.075), (150, 0.86, 0.06),
    ]
    /// Радиус поворота и расстояние до зрителя — доли высоты от изгиба до
    /// горизонта; подобраны по рисунку (P717): поворот кончается шириной
    /// 0,86 на высоте 105, карточки у дальнего конца — частые полосы.
    static let radiusShare: CGFloat = 0.20
    static let focalShare: CGFloat = 1.0
    /// Сколько точек над верхом списка тоже рисуется: оттуда уходит «хвост»
    /// ленты — семь карточек до дальнего конца (P712, P717).
    static var lift: CGFloat { 7 * pitch }

    /// Лента (P712): от линии изгиба вверх — четверть цилиндра радиуса `r`
    /// (лента плавно ложится от вертикали в горизонталь), дальше — плоскость
    /// к горизонту; вид с расстояния `f`. `c` — на сколько точек ленты место
    /// выше линии изгиба. Возвращает место на экране и ширину (1 — прежняя).
    /// Та же формула — в `Ribbon.metal`.
    static func curl(_ c: CGFloat, bend: CGFloat, horizon: CGFloat, r: CGFloat,
                     f: CGFloat) -> (y: CGFloat, s: CGFloat) {
        guard c > 0 else { return (bend - c, 1) }
        let arc = .pi / 2 * r
        let h: CGFloat, z: CGFloat
        if c < arc {
            h = r * sin(c / r)
            z = r * (1 - cos(c / r))
        } else {
            h = r
            z = r + (c - arc)
        }
        let s = f / (f + z)
        return (horizon + (bend - horizon - h) * s, s)
    }

    /// Искажение одной карточки — шейдером у всех карточек на ленте (P714):
    /// карточка сдвигается на своё место на ленте (`shift`), а шейдер для
    /// каждой точки находит, откуда в карточке взять цвет. Прежде карточка
    /// сперва сжималась целиком до средней ширины, а шейдер лишь доводил
    /// перспективу — но доводка не срабатывала: на снимке CI (P717) края
    /// карточек шли ступеньками, каждая — прямоугольником своей средней
    /// ширины. Теперь сжатия заранее нет — шейдер делает всё сам.
    static func bend(_ view: EmptyVisualEffect, _ proxy: GeometryProxy, index: Int,
                     preview: Bool) -> some VisualEffect {
        let top = proxy.frame(in: .named(space)).minY - lift
        let h = max(proxy.size.height, 1)
        // На сколько список пролистан: где карточка стоит и где стояла бы в
        // покое. В снимках CI — как пролистанный (в них три находки, листать
        // некуда), чтобы поворот был виден на снимке.
        let scrolled = preview ? 2 * pitch : max(0, restTop + CGFloat(index) * pitch - top)
        let (bend, horizon, r, f, roll) = shape(scrolled: scrolled)
        let lower = curl(bend - (top + h), bend: bend, horizon: horizon, r: r, f: f)
        let shift = lower.y - (top + h)
        let inBend = top < bend
        let half = proxy.size.width / 2
        let vx = vanish * proxy.size.width
        // Карточка целиком за валиком — её место на изнанке (`RibbonBack`).
        let gone = inBend && bend - (top + h) > roll
        return view
            .distortionEffect(
                ShaderLibrary.ribbon(.float2(proxy.size), .float(top), .float(shift),
                                     .float(bend), .float(horizon), .float(r), .float(f),
                                     .float(roll), .float(vx)),
                // Выборка — в пределах самой карточки и чуть за её краем.
                maxSampleOffset: CGSize(width: max(vx, 2 * half - vx) + 8, height: h + 8),
                isEnabled: inBend)
            .offset(y: inBend ? shift : 0)
            .opacity(gone ? 0 : 1)
    }

    /// Ход ленты для списка, пролистанного на `scrolled`: линия изгиба,
    /// горизонт, радиус поворота, расстояние до зрителя и `roll` — где
    /// дальний конец переходит в петлю (P715): там, где лента сузилась до
    /// `rollShare` ширины, как на рисунке автора (P717).
    static func shape(scrolled: CGFloat)
        -> (bend: CGFloat, horizon: CGFloat, r: CGFloat, f: CGFloat, roll: CGFloat) {
        let bend = min(bendMax, restTop + scrolled)
        let height = bend - horizon
        let r = radiusShare * height
        let f = focalShare * height
        let z = f * (1 / rollShare - 1)
        // Не дальше, чем рисуются карточки над списком (`lift`).
        let roll = min(z - r + .pi / 2 * r, bend + lift - 8)
        return (bend, horizon, r, f, roll)
    }

    /// Ширина ленты у дальнего конца — доля прежней (с рисунка: 0,32 на
    /// высоте 27, чуть выше — петля).
    static let rollShare: CGFloat = 0.22
    /// Сколько карточек ленты уходит на петлю.
    static let loopCards: CGFloat = 10

    /// Снимок CI «лента поиска» (P717): находок много, список пролистан —
    /// как у человека на телефоне, чтобы сличить ленту с рисунком автора.
    /// Находка в списке: место по порядку нужно ленте, а на снимке «лента
    /// поиска» одни и те же дни повторяются — им нужен свой ключ.
    struct Item: Identifiable {
        let id: String
        let index: Int
        let day: Archive.Day
    }

    static let deep = Vault.isPreview
        && ProcessInfo.processInfo.environment["CHRONOTHECA_SCREEN"] == "searchdeep"

    /// Высота блока из пяти строк находки: строка заголовка и четыре строки
    /// текста; по ней же — сторона снимка (P696).
    static var body: CGFloat {
        let title = ceil(Prefs.serifUIFont(15).lineHeight)
        let line = ceil(Prefs.serifUIFont(13.5).lineHeight)
        // Между заголовком и текстом один промежуток; четыре строки текста идут подряд.
        return title + lineGap + line * 4
    }

    /// «2026 сентябрь 22» — от крупного к мелкому, как ищут в архиве.
    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        // Промежутки — в один пробел, вдвое уже прежних (P282).
        return "\(c.year ?? 2026) \(Ru.monthNames[(c.month ?? 1) - 1]) \(c.day ?? 1)"
    }

}


/// Карточка находки — лист картотеки с корешком (P695): на левой трети
/// сверху выступает корешок с датой; корешок и лист — один контур без черты
/// между ними (P697). Карточка из фактурной старой бумаги (цвет прошлого и
/// рельеф, P696) с заранее нарисованной тенью вправо-вниз (лампа слева сверху,
/// P670, P675). Снизу пустое место: следующая карточка заходит на него и
/// скрывает нижний край этой.
private struct SearchCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let stamp: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(stamp)
                    .font(Look.mono(11.5, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Look.dateBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
            }
            .frame(height: Search.tabHeight)
            content()
                .padding(.top, 8)
                // Пустое место под карточкой — под следующую (P696).
                .padding(.bottom, Search.overlap + 6)
                .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                // Тень — только у листа, не у корешка.
                PaintedShadow(radius: 5, corner: 12, x: 2, y: 3,
                              opacity: scheme == .dark ? 0.5 : 0.3)
                    .padding(.top, Search.tabHeight)
                paper.clipShape(FolderShape(tabHeight: Search.tabHeight))
                FolderShape(tabHeight: Search.tabHeight)
                    .stroke(Scheme.current.kraftEdge.opacity(0.5), lineWidth: 0.8)
            }
        }
    }

    /// Старая бумага: цвет прошлого и рельеф плиткой — непрозрачная, иначе
    /// корешок соседа просвечивал бы.
    private var paper: some View {
        ZStack {
            Scheme.current.past
            Image(uiImage: PageTexture.paper)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.25 : 0.7)
        }
    }
}

/// Контур карточки с корешком на левой трети: корешок и лист — одна фигура.
private struct FolderShape: Shape {
    let tabHeight: CGFloat

    func path(in r: CGRect) -> Path {
        let tabWidth = r.width / 3
        let tabR: CGFloat = 10, bodyR: CGFloat = 12, inner: CGFloat = 6
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + tabR))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tabR, y: r.minY), radius: tabR)
        p.addLine(to: CGPoint(x: r.minX + tabWidth - tabR, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + tabWidth, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tabWidth, y: r.minY + tabR), radius: tabR)
        p.addLine(to: CGPoint(x: r.minX + tabWidth, y: r.minY + tabHeight - inner))
        p.addArc(tangent1End: CGPoint(x: r.minX + tabWidth, y: r.minY + tabHeight),
                 tangent2End: CGPoint(x: r.minX + tabWidth + inner, y: r.minY + tabHeight), radius: inner)
        p.addLine(to: CGPoint(x: r.maxX - bodyR, y: r.minY + tabHeight))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY + tabHeight),
                 tangent2End: CGPoint(x: r.maxX, y: r.minY + tabHeight + bodyR), radius: bodyR)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bodyR))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX - bodyR, y: r.maxY), radius: bodyR)
        p.addLine(to: CGPoint(x: r.minX + bodyR, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                 tangent2End: CGPoint(x: r.minX, y: r.maxY - bodyR), radius: bodyR)
        p.closeSubpath()
        return p
    }
}
