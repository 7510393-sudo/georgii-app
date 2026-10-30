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
        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 10))
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
        let days = found
        return ScrollView {
            // Находки — карточки картотеки, вид сверху: нижняя лежит поверх
            // верхней и своим корешком с датой закрывает её низ; уходя
            // вверх, карточка уменьшается и бледнеет, будто уходит
            // вдаль (P694, P695).
            LazyVStack(spacing: -Search.overlap) {
                ForEach(days) { day in
                    SearchCard(stamp: Search.stamp(day.date)) { row(day) }
                        // Лента карточек сгибается и уходит вдаль одним гладким
                        // потоком (P698): общий изгиб на всех, каждая карточка
                        // ложится по своему куску ленты.
                        .visualEffect { content, proxy in
                            Search.recede(content,
                                          minY: proxy.frame(in: .named("searchList")).minY,
                                          size: proxy.size)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            // Место под клавиатуру. Без него последние находки лежат под
            // ней и не достаются прокруткой: список кончается там, где
            // начинается клавиатура (решение P174).
            // Строки разделов над клавиатурой больше нет (P505).
            .padding(.bottom, keyboard > 0 ? keyboard + 4 : 0)
        }
        .coordinateSpace(name: "searchList")
        // Второе нажатие на «Поиск» — список заново, с начала (P576).
        .id(shell.searchHome)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeOut(duration: 0.25), value: keyboard)
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

    /// Где лента начинает сгибаться (от верха списка): за треть карточки до
    /// верха (P703; было за две трети, ещё раньше — за одну и за полторы).
    private static var bendY: CGFloat { pitch / 3 }
    /// Во сколько раз уже становится карточка там, где она уходит за верх
    /// списка: сужение на 60% (P704; прежде 44%, а в P702 — «вдвое интенсивнее»).
    private static let vanishWidth: CGFloat = 0.40
    /// Расстояние до зрителя: подобрано так, чтобы у верха списка лента была
    /// шириной `vanishWidth`.
    private static var focal: CGFloat { 2 * bendY / (1 - vanishWidth * vanishWidth) }

    /// Одна общая лента (P699, P701) — как плоскость, ложащаяся к горизонту:
    /// `c` — на сколько точек выше линии сгиба место ленты; ширина там
    /// `focal / (focal + c)` от прежней, а высота ужимается как куб этой
    /// ширины, поэтому растягиваться по вертикали нечему и щелей не бывает.
    /// Возвращает, где это место на экране и во сколько раз ужато по ширине.
    /// Выше сгиба и ниже — одна функция, швов нет.
    private static func ribbon(_ c: CGFloat) -> (y: CGFloat, s: CGFloat) {
        guard c > 0 else { return (bendY - c, 1) }
        let s = focal / (focal + c)
        return (bendY - focal / 2 * (1 - s * s), s)
    }

    /// Во сколько точек раз `perspective: 1` у `rotation3DEffect` ослабляет
    /// масштаб на каждую точку высоты при повороте на 90° (замер по снимку
    /// сборки 207: расстояние до зрителя около 255 точек).
    private static let rotationDistance: CGFloat = 255

    /// Карточка — кусок ленты (P699, P702): её видимая часть — от верха корешка
    /// до верха листа следующей карточки (`pitch` и корешок), и низ видимой
    /// части совпадает с верхом листа следующей по месту и по ширине, поэтому
    /// щелей нет, а следующая (ближняя) карточка нигде не уже низа дальней.
    /// Прямоугольник становится трапецией (верх уже низа): поворот назад вокруг
    /// линии низа видимой части, сплющивание по высоте и сдвиг на место. Под
    /// этой линией остаётся лишь узкая полоса листа, которую закрывает листок
    /// следующей. Дальние карточки тают.
    static func recede(_ content: EmptyVisualEffect, minY: CGFloat, size: CGSize) -> some VisualEffect {
        let span = pitch + tabHeight
        let h = max(size.height, span + 1)
        let bottom = ribbon(bendY - (minY + span))
        let top = ribbon(bendY - minY)
        let sb = bottom.s
        let r = min(top.s / sb, 1)
        let drop = max(bottom.y - top.y, 0.01)
        // Наклон растёт вместе с сужением (без сужения — прямая карточка),
        // перспектива подбирается под ширину верха, высота куска — сплющиванием.
        let angle = min(0.6, (1 / r - 1) * 1.2)
        let power: CGFloat = r > 0.999
            ? 1
            : min((1 / r - 1) * rotationDistance / (span * max(sin(angle), 0.08)), 40)
        // Растягивать по высоте нельзя: только сплющивать.
        let squash = min(drop / (sb * span * cos(angle) * r), 1)
        // Тают по пути к верху списка: целые, пока лента не сузилась до 0,67,
        // исчезают там, где верх карточки доходит до верха списка (0,40).
        let away = min(max((bendY - minY - 0.5 * focal) / focal, 0), 1)
        let anchor = UnitPoint(x: 0.5, y: span / h)
        return content
            .rotation3DEffect(.radians(angle), axis: (x: 1, y: 0, z: 0),
                              anchor: anchor, perspective: power)
            .scaleEffect(x: sb, y: sb * squash, anchor: anchor)
            .offset(y: bottom.y - (minY + span))
            .opacity(1 - away * away * (3 - 2 * away))
    }

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
