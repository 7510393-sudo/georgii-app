import SwiftUI
import UIKit

/// Бумага: рельеф и крапинки страницы, затёртые края и бока, износ
/// карточек картотеки. Вынесено из `DayPager.swift` без правок (P919).

/// Бумага прошедшего дня для мелких мест — клетки календаря, строки списка,
/// панельки месяцев (P684): тот же рельеф и те же крапинки, что у страницы
/// (`PageTexture.paper`), и затёртые края. Листов два на весь календарь
/// (P809, вместо своего износа у каждой клетки, P723): нарисованы один раз,
/// лежат готовыми, клетки чередуют их по номеру. `base` — цвет бумаги под рельефом: он вырезается
/// вместе с ним, и выщербины по краю видны насквозь. Касаний не ловит.
struct OldPaper: View {
    @Environment(\.colorScheme) private var scheme
    /// Ширина затёртой полосы по краю (P722): у клеток — узкая.
    var band: CGFloat = 7
    /// Чей износ — номер дня (`PageTexture.seed`): у соседних клеток разный.
    var seed: Int = 0
    var base: Color? = nil
    /// Старая бумага выключена в настройках (P730): только цвет прошлого.
    @AppStorage(Prefs.plainPast) private var plainPast = false
    /// Готовая клетка приходит следом (P732, P807).
    @State private var cell: PageTexture.CellArt?

    var body: some View {
        if plainPast {
            if let base { base }
        } else {
            GeometryReader { geo in
                // Два листа на весь календарь (P809, по слову автора):
                // нарисованы один раз, лежат готовыми, клетки их чередуют.
                let order = PageTexture.agedOrder(size: geo.size, band: band, seed: seed, kinds: 2)
                let dark = scheme == .dark
                let name = PageTexture.cellName(order, dark: dark)
                Group {
                    if let ready = cell ?? PaperShop.shared.readyCell(name) {
                        worn(ready, geo.size)
                    } else if let base {
                        base
                    }
                }
                .task(id: name) { cell = await PageTexture.agedCell(order, dark: dark) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Клетка — три готовые картинки (P807): тень рваного края, лист цвета
    /// дня по форме рваного края и бумага с износом поверх. Прежде слои
    /// складывались на ходу с маской и тенью — у каждой из сотни клеток
    /// свой отдельный проход рисования: календарь открывался секундами.
    private func worn(_ ready: PageTexture.CellArt, _ size: CGSize) -> some View {
        ZStack {
            // Под рваным листком — целый лист того же цвета (P728, по
            // образцу автора: под повреждением не пустота, а следующий лист).
            if let base {
                base.overlay(Color.black.opacity(scheme == .dark ? 0.12 : 0.06))
            }
            // Рваный край отбрасывает тонкую тень на лист под ним.
            Image(uiImage: ready.shadow).resizable()
            if let base {
                Image(uiImage: ready.shape).renderingMode(.template).resizable().foregroundStyle(base)
            }
            Image(uiImage: ready.sheet).resizable()
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension PageTexture {

    /// Готовая клетка старой бумаги (P807): что прежде складывалось на ходу
    /// — рельеф, износ, маска рваного края и тень — сложено заранее, в
    /// стороне от экрана.
    final class CellArt: NSObject {
        let shadow: UIImage
        /// Форма рваного листа — красится цветом дня.
        let shape: UIImage
        /// Рельеф и износ, уже обрезанные по рваному краю.
        let sheet: UIImage
        init(shadow: UIImage, shape: UIImage, sheet: UIImage) {
            self.shadow = shadow; self.shape = shape; self.sheet = sheet
        }
    }

    static func cellName(_ order: AgedOrder, dark: Bool) -> String {
        "\(order.key)\(dark ? "d" : "")-cell"
    }

    /// Клетка — когда будет готова (в стороне от экрана). Рисуется один раз
    /// и лежит в служебной папке (P809): следующие запуски берут готовую.
    static func agedCell(_ order: AgedOrder, dark: Bool) async -> CellArt {
        let art = await aged(order)
        return await PaperShop.shared.cell(cellName(order, dark: dark), shape: art.cut) {
            makeCell(art, size: CGSize(width: order.w, height: order.h), seed: order.variant + 1, dark: dark)
        }
    }

    /// Те же слои, что прежде складывались на экране: под рельефом цвет дня,
    /// рельеф сдвинут по номеру дня, износ поверх, всё обрезано рваным
    /// краем; тень — по рваному краю, без самого листа.
    fileprivate static func makeCell(_ art: AgedArt, size: CGSize, seed: Int, dark: Bool) -> CellArt {
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(px)
        format.opaque = false
        let rect = CGRect(origin: .zero, size: size)
        let tile = paper.size
        let dx = CGFloat(abs(seed &* 97) % max(1, Int(tile.width)))
        let dy = CGFloat(abs(seed &* 61) % max(1, Int(tile.height)))
        let shape = art.cut.withTintColor(.black, renderingMode: .alwaysOriginal)
        let sheet = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            var y = -dy
            while y < size.height {
                var x = -dx
                while x < size.width {
                    paper.draw(in: CGRect(x: x, y: y, width: tile.width, height: tile.height),
                               blendMode: .normal, alpha: dark ? 0.15 : 0.25)
                    x += tile.width
                }
                y += tile.height
            }
            art.frame.draw(in: rect, blendMode: .normal, alpha: dark ? 0.35 : 1)
            art.cut.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
        let shadow = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let scale = CGFloat(px)
            // Сдвиг и размытие тени — в пикселях, и вверх там плюс.
            ctx.cgContext.setShadow(offset: CGSize(width: 0.4 * scale, height: -0.6 * scale),
                                    blur: 1.6 * scale,
                                    color: UIColor.black.withAlphaComponent(0.28).cgColor)
            shape.draw(in: rect)
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            shape.draw(in: rect, blendMode: .destinationOut, alpha: 1)
        }
        return CellArt(shadow: shadow, shape: art.cut, sheet: sheet)
    }
}

/// Затёртые бока страницы дня (P735): одной полосой на всю страницу — от
/// верха шапки до низа, без шва под шапкой. Едут вместе с листом (P737:
/// «страница и текст — единое целое»; в P735 они стояли на месте) — сдвиг
/// берётся из `PageScroll`, при прокрутке меняется только он.
/// Пока заготовки краёв не готовы — края не затёрты (P732).
struct PageSides: View {
    let aged: Bool
    /// Номер дня (P736): у каждого дня бока свои — кусок края берётся с
    /// другого места, левый и правый меняются местами, край переворачивается.
    /// Картинок столько же, сколько было, — памяти и работы не прибавилось.
    let seed: Int
    @ObservedObject var scroll: PageScroll
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false
    // periphery:ignore - не читается, но перерисовывает вид, когда заготовки готовы
    @ObservedObject private var shop = PaperShop.shared

    var body: some View {
        if aged && !plainPast && scheme != .dark {
            let swap = seed & 1 == 1
            let flip: CGFloat = (seed >> 1) & 1 == 1 ? -1 : 1
            HStack(spacing: 0) {
                if let left = swap ? PageTexture.sideEdgeRight : PageTexture.sideEdge {
                    strip(left, from: seed &* 389, flip: flip)
                }
                Spacer(minLength: 0)
                if let right = swap ? PageTexture.sideEdge : PageTexture.sideEdgeRight {
                    strip(right, from: seed &* 577 &+ 211, flip: flip)
                        .scaleEffect(x: -1)
                }
            }
            // Бока сходят на нет к низу листа (P854): прямые полосы не
            // повторяли нижние скругления, и у поднятого листа по углам
            // торчали их кусочки. Низ затёрт по контуру — `bottom`.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 44)
                }
            }
            // Верх листа (P850): прежде у прошедшего дня он оставался
            // чистым — износ шёл только по бокам и низу. Та же полоса, что
            // внизу, перевёрнутая, — по верху корешка; вырез корешка и
            // плечо — по контуру (P854).
            .overlay(alignment: .topLeading) { top }
            .overlay { bottom }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var top: some View {
        if let foot = PageTexture.footEdge {
            let folder = DayPage.folder
            GeometryReader { geo in
                let tab: CGFloat = geo.size.width * folder.tabShare
                ZStack(alignment: .topLeading) {
                    band(foot, width: tab, from: seed &* 151)
                    EdgeWear(shape: folder, depth: 12)
                        .mask(alignment: .topLeading) {
                            WearNotch.region(width: geo.size.width, tab: tab,
                                           tabHeight: folder.tabHeight, depth: 12)
                        }
                }
            }
        }
    }

    /// Низ листа — по контуру, со скруглёнными углами (P854): виден, когда
    /// лист подняли; в покое он под нижней строкой.
    private var bottom: some View {
        ZStack {
            // Затёртый низ — та же полоса, что была у низа страницы, теперь
            // по низу самого листа и в его контуре (P857).
            if let foot = PageTexture.footEdge {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    let length = foot.size.width
                    let shift = CGFloat(abs(seed &* 263) % max(1, Int(length)))
                    GeometryReader { geo in
                        Image(uiImage: foot).resizable(resizingMode: .tile)
                            .frame(width: geo.size.width + length, height: PageTexture.footDepth)
                            .offset(x: -shift)
                    }
                    .frame(height: PageTexture.footDepth)
                    .clipped()
                    .scaleEffect(x: (seed >> 2) & 1 == 1 ? -1 : 1, y: 1)
                    // Только у самого края (P744): к 15 точкам — ноль.
                    .mask(LinearGradient(stops: PageSides.fade(full: 3, gone: 15, depth: PageTexture.footDepth),
                                         startPoint: .bottom, endPoint: .top))
                }
            }
            // Следы рук (P680): нижний внешний угол, нижний левый, правый край.
            GeometryReader { geo in
                PageTexture.thumbSmudge(radius: 95, opacity: 0.20)
                    .position(x: geo.size.width, y: geo.size.height - DayPage.under)
                PageTexture.thumbSmudge(radius: 70, opacity: 0.11)
                    .position(x: 0, y: geo.size.height - DayPage.under - 6)
                PageTexture.thumbSmudge(radius: 60, opacity: 0.09)
                    .position(x: geo.size.width + 4, y: geo.size.height * 0.62)
            }
            bottomWear
        }
        .clipShape(DayPage.folder)
    }

    private var bottomWear: some View {
        EdgeWear(shape: DayPage.folder, depth: 12)
            .mask {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                }
            }
    }

    /// Полоса износа вдоль верхнего края: картинка низа, отражённая.
    private func band(_ foot: UIImage, width: CGFloat, from: Int) -> some View {
        let length = foot.size.width
        let shift = CGFloat(abs(from) % max(1, Int(length)))
        return GeometryReader { _ in
            Image(uiImage: foot).resizable(resizingMode: .tile)
                .frame(width: width + length, height: PageTexture.footDepth)
                .offset(x: -shift)
        }
        .frame(width: width, height: PageTexture.footDepth)
        .clipped()
        .mask(LinearGradient(stops: PageSides.fade(full: 3, gone: 15, depth: PageTexture.footDepth),
                             startPoint: .bottom, endPoint: .top))
        .scaleEffect(x: 1, y: -1)
    }

    /// Кусок края — с места `from` (кусок замкнут сам на себя, шва нет),
    /// сдвинутый вместе с листом. Переворот — у самой картинки, чтобы край
    /// ехал в ту же сторону, что и лист.
    /// Бока только на поле, у самого края (P742: «фактура налезает на файлы
    /// и на текст»): в полную силу до 3 точек, к 15 мягко сходят на нет
    /// (P744 — без резкой границы; P748 — «ещё уже вдоль края»).
    private static let margin = LinearGradient(
        stops: PageSides.fade(full: 3, gone: 15, depth: PageTexture.sideDepth),
        startPoint: .leading, endPoint: .trailing)

    /// Плавный спад (P744: «резкая граница, которая ограничивает
    /// потемнение, — неестественно, должна быть размыта»): от полной силы у
    /// края до нуля — мягкой кривой, без ступеньки.
    static func fade(full: CGFloat, gone: CGFloat, depth: CGFloat) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = [.init(color: .black, location: 0)]
        for k in 0...8 {
            let t = CGFloat(k) / 8
            let q = 1 - t * t * (3 - 2 * t)
            stops.append(.init(color: .black.opacity(q), location: (full + (gone - full) * t) / depth))
        }
        return stops
    }

    private func strip(_ picture: UIImage, from: Int, flip: CGFloat) -> some View {
        let length = picture.size.height
        let start = CGFloat(abs(from) % max(1, Int(length)))
        let dy = (scroll.y - start).truncatingRemainder(dividingBy: length)
        return GeometryReader { geo in
            // Кусок повторяется столбиком: на любой сдвиг хватает.
            VStack(spacing: 0) {
                ForEach(0..<Int((geo.size.height / length).rounded(.up)) + 2, id: \.self) { _ in
                    Image(uiImage: picture)
                        .resizable()
                        .frame(width: PageTexture.sideDepth, height: length)
                        .scaleEffect(x: 1, y: flip)
                }
            }
            .offset(y: dy - length)
        }
        .frame(width: PageTexture.sideDepth)
        .clipped()
        .mask(PageSides.margin)
    }
}

/// Фактура страницы: у плана — бледная клетка, как в тетради; у дневника —
/// волокно бумаги (P245). Рисуется один раз и кладётся плиткой.
struct PageTexture: View {
    let tab: Shell.Tab
    /// Кусок сдвинут при рисовании (открытая вкладка опущена на точку) —
    /// узор сдвигается обратно, чтобы клетка не разошлась.
    var shift: CGFloat = 0
    /// От чего отсчитывается узор. На листе дня — от самого листа, который
    /// едет при прокрутке: клетка идёт вместе с текстом (P412).
    var space: String = PageTexture.space
    /// Прошедший день: поверх обычной фактуры — старая бумага (P676).
    var aged = false
    // Затёртый низ и следы рук — не у страницы, а у самого листа
    // (`PageSides`, P857): низ страницы стоял выше низа листа.
    @Environment(\.colorScheme) private var scheme
    /// Старая бумага выключена в настройках (P730).
    @AppStorage(Prefs.plainPast) private var plainPast = false
    /// Готовые заготовки краёв приходят следом (P732).
    // periphery:ignore - не читается, но перерисовывает вид, когда заготовки готовы
    @ObservedObject private var shop = PaperShop.shared
    private var dark: Bool { scheme == .dark }

    /// Общая точка отсчёта фактуры — вся страница дня.
    static let space = "страница"

    var body: some View {
        ZStack {
            tiled(tab == .plan ? PageTexture.grid : PageTexture.grain)
            if aged && !plainPast {
                ZStack {
                    // Бумага почти гладкая, как у образца (P727): рельеф слабее.
                    tiled(PageTexture.paper).opacity(0.4)
                }
                .opacity(dark ? 0.45 : 1)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tiled(_ picture: UIImage) -> some View {
        let tile = picture.size
        return GeometryReader { geo in
            // Узор сдвигается так, будто он нарисован на всей странице
            // разом, а этот кусок — окно в него.
            let at = geo.frame(in: .named(space)).origin
            let dx = at.x.truncatingRemainder(dividingBy: tile.width)
            let dy = (at.y + shift).truncatingRemainder(dividingBy: tile.height)
            Image(uiImage: picture)
                .resizable(resizingMode: .tile)
                .frame(width: geo.size.width + tile.width * 2,
                       height: geo.size.height + tile.height * 2)
                .offset(x: -dx - tile.width, y: -dy - tile.height)
        }
    }

    /// Сторона клетки — по ней же строки плана (P413). 22 точки — ровно
    /// строчка названия дела: каждая строчка сидит на линии клетки, как в
    /// тетради (P795; прежде 18, и строчки в 22 расходились с клеткой).
    static let cell: CGFloat = 22

    /// Клетка — как в школьной тетради, но еле видная.
    static let grid: UIImage = {
        let side: CGFloat = cell
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            // Заметнее прежнего (P680: было 0,09 и 0,6): клетка видна между
            // плашками и по полям — под плашками её нет (P415).
            UIColor(Look.accent).withAlphaComponent(0.17).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: 0.7))
            ctx.fill(CGRect(x: 0, y: 0, width: 0.7, height: side))
        }
    }()

    /// Волокно бумаги: мелкие крапинки и короткие волоски, светлые и
    /// тёмные вперемешку. Узор один и тот же при каждом запуске — иначе
    /// соседние страницы различались бы на снимках (P114).
    static let grain: UIImage = {
        let side: CGFloat = 160
        var seed: UInt64 = 0x5EED_2026
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            for _ in 0..<700 {
                let x = next() * side, y = next() * side
                let r = 0.3 + next() * 0.7
                let dark = next() < 0.6
                (dark ? UIColor(Look.ink).withAlphaComponent(0.035 + next() * 0.03)
                      : UIColor.white.withAlphaComponent(0.25 + next() * 0.2)).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            for _ in 0..<40 {
                let x = next() * side, y = next() * side
                let angle = next() * .pi
                let length = 3 + next() * 6
                let fibre = UIBezierPath()
                fibre.move(to: CGPoint(x: x, y: y))
                fibre.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                   controlPoint: CGPoint(x: x + cos(angle + 0.6) * length / 2,
                                                         y: y + sin(angle + 0.6) * length / 2))
                fibre.lineWidth = 0.4
                UIColor(Look.ink).withAlphaComponent(0.05).setStroke()
                fibre.stroke()
            }
        }
    }()

    /// След руки (P680): мягкое бурое пятно. Рисует его низ листа
    /// (`PageSides`, P857).
    static func thumbSmudge(radius: CGFloat, opacity: Double) -> some View {
        let tint: Color = PageTexture.grey ? PageTexture.greySmudge : PageTexture.warmSmudge
        let strength: Double = opacity * Double(PageTexture.wearStrength)
        return RadialGradient(colors: [tint.opacity(strength), .clear],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Густота износа (облака, края, крапинки): 1 — средняя (второй вариант
    /// эскиза `docs/paper/износ-по-образцу.png`); 1,7 — сильнее.
    static let wearStrength = CGFloat(1.05)

    /// Гамма «Без цвета» (P825): износ серый, без охры. Заготовки серой
    /// бумаги лежат отдельно от тёплых (`PaperShop`, приставка «g-»).
    static var grey: Bool { UserDefaults.standard.string(forKey: Prefs.calendarTint) == "none" }

    private typealias Tone = (r: Float, g: Float, b: Float)
    private static let warmAmber: Tone = (r: 0.753, g: 0.518, b: 0.251)
    // Серые — светлее прежних (P848): подпалина 0,28 читалась почти чёрной
    // обводкой, край выглядел грубо, как сборки назад.
    private static let greyAmber: Tone = (r: 0.700, g: 0.690, b: 0.670)
    private static var amber: Tone { grey ? greyAmber : warmAmber }
    /// Подпалина у самого края (P722) — темнее и рыжее охры.
    private static let warmBurnt: Tone = (r: 0.431, g: 0.227, b: 0.086)
    private static let greyBurnt: Tone = (r: 0.470, g: 0.460, b: 0.440)
    private static var burnt: Tone { grey ? greyBurnt : warmBurnt }
    /// Те же охра и подпалина — для края по контуру (`EdgeWear`, P854).
    static var wearAmber: Color { Color(red: Double(amber.r), green: Double(amber.g), blue: Double(amber.b)) }
    static var wearBurnt: Color { Color(red: Double(burnt.r), green: Double(burnt.g), blue: Double(burnt.b)) }
    private static let warmTorn: (Float, Float, Float) = (0.24, 0.15, 0.08)
    private static let greyTorn: (Float, Float, Float) = (0.36, 0.35, 0.34)
    private static let warmSmudge = Color(red: 0.42, green: 0.30, blue: 0.16)
    private static let greySmudge = Color(red: 0.33, green: 0.32, blue: 0.31)

    /// Круговое размытие: края плитки сходятся. Бегущей суммой — работа не
    /// растёт с радиусом (P679: прежнее перебирание окна заново для каждой
    /// точки считалось секундами на главном потоке при первом показе
    /// прошедшего дня).
    private static func wrapBlur(_ a: [Float], side n: Int, radius r: Int, passes: Int) -> [Float] {
        var src = a, dst = a
        let w = Float(2 * r + 1)
        for _ in 0..<passes {
            for y in 0..<n {
                let row = y * n
                var sum: Float = 0
                for k in -r...r { sum += src[row + (k + n) % n] }
                for x in 0..<n {
                    dst[row + x] = sum / w
                    sum += src[row + (x + r + 1) % n] - src[row + (x - r + n) % n]
                }
            }
            for x in 0..<n {
                var sum: Float = 0
                for k in -r...r { sum += dst[((k + n) % n) * n + x] }
                for y in 0..<n {
                    src[y * n + x] = sum / w
                    sum += dst[((y + r + 1) % n) * n + x] - dst[((y - r + n) % n) * n + x]
                }
            }
        }
        return src
    }

    /// Всю бумагу — заранее, в стороне, пока приложение запускается (P679):
    /// первый показ прошедшего дня не должен ждать, пока она нарисуется.
    static func prepareSoon() {
        DispatchQueue.global(qos: .utility).async {
            _ = paper
        }
        // Края страницы — в пачку заготовок: нарисуются в стороне или
        // достанутся из служебной памяти (P732).
        DispatchQueue.main.async {
            _ = sideEdge
            _ = sideEdgeRight
            _ = footEdge
        }
    }

    private static func normalised(_ a: [Float]) -> [Float] {
        let mean = a.reduce(0, +) / Float(a.count)
        let sd = (a.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(a.count)).squareRoot()
        return a.map { ($0 - mean) / max(sd, 0.0001) }
    }

    private static func picture(_ bytes: [UInt8], width: Int, height: Int, scale: CGFloat) -> UIImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true,
                            intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// Облака тона (P676): крупные мягкие пятна, где светлее и теплее, где
    /// темнее. Плитка 576 точек, замкнута сама на себя.
    /// Бумага одним слоем (P679): рельеф и редкие бледные крапинки с
    /// волосками. Плитка 384 точки — рельеф (128) повторён три на три,
    /// поверх разбросаны крапинки, которых на ней около полусотни, так что
    /// повтор не бросается в глаза. Слоёв на странице стало меньше —
    /// страница, которую листают, легче.
    static let paper: UIImage = {
        var seed: UInt64 = 0x5BECC5
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        let side: CGFloat = 384
        let k = wearStrength
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let tile = relief
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            for row in 0..<3 {
                for column in 0..<3 {
                    tile.draw(at: CGPoint(x: CGFloat(column) * 128, y: CGFloat(row) * 128))
                }
            }
            for _ in 0..<Int(48 * k) {
                let d = 0.9 + next() * 1.5
                UIColor(red: 0.42, green: 0.32, blue: 0.18, alpha: 0.10 + next() * 0.12).setFill()
                cg.fillEllipse(in: CGRect(x: next() * side, y: next() * side, width: d, height: d))
            }
            for _ in 0..<Int(12 * k) {
                let x = next() * side, y = next() * side
                let angle = next() * .pi, length = 4 + next() * 7
                let hair = UIBezierPath()
                hair.move(to: CGPoint(x: x, y: y))
                hair.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                hair.lineWidth = 0.5
                UIColor(red: 0.45, green: 0.36, blue: 0.22, alpha: 0.22).setStroke()
                hair.stroke()
            }
        }
    }()

    /// Пикселей на точку у картинок старой бумаги (P731): как у экрана
    /// iPhone — втрое. При двух рваный край на экране расплывался.
    private static let px = 3

    static let sideDepth: CGFloat = 96
    static let footDepth: CGFloat = 110

    /// Бок: широкая тёплая полоса к краю, глубина и сила гуляют пятнами;
    /// сам край рваный. Длина куска — 1200 точек (P723): на странице он
    /// почти не повторяется. Левый и правый — разные куски, не зеркало.
    static var sideEdge: UIImage? {
        PaperShop.shared.picture("side-left") {
            edgeImage(depthPoints: sideDepth, alongPoints: 1200, falloff: 14, peak: 0.5, vertical: true, seed: 0xED6E1)
        }
    }
    static var sideEdgeRight: UIImage? {
        PaperShop.shared.picture("side-right") {
            edgeImage(depthPoints: sideDepth, alongPoints: 1200, falloff: 14, peak: 0.5, vertical: true, seed: 0xED6E3)
        }
    }
    /// Низ: темнее и шире боков.
    static var footEdge: UIImage? {
        PaperShop.shared.picture("foot") {
            edgeImage(depthPoints: footDepth, alongPoints: 480, falloff: 16, peak: 0.55, vertical: false, seed: 0xED6E2)
        }
    }

    /// Полоска вдоль края, 2 пикселя на точку. Вертикальная — край слева;
    /// горизонтальная — край внизу. По образцу автора (P727): бумага к краю
    /// плавно темнеет из бежевого в охру широкой полосой, тон чуть
    /// неровный мягкими пятнами, у самого края — тёмная опалённая кромка, и
    /// сам край рваный: волнистый, кое-где вырван глубже. Вырванное
    /// закрашено тёмным — страница во весь экран, вырезать нечем. К
    /// внутренней границе картинки износ сходит на нет (без ступеньки).
    /// Значение поля между точками сетки — плавно (P744).
    private static func smooth(_ f: [Float], _ w: Int, _ h: Int, _ x: Float, _ y: Float) -> Float {
        let x0 = min(w - 1, max(0, Int(x))), y0 = min(h - 1, max(0, Int(y)))
        let x1 = min(w - 1, x0 + 1), y1 = min(h - 1, y0 + 1)
        let tx = x - Float(x0), ty = y - Float(y0)
        let top = f[y0 * w + x0] * (1 - tx) + f[y0 * w + x1] * tx
        let bottom = f[y1 * w + x0] * (1 - tx) + f[y1 * w + x1] * tx
        return top * (1 - ty) + bottom * ty
    }

    private static func edgeImage(depthPoints: CGFloat, alongPoints: CGFloat, falloff: Float, peak: Float,
                                  vertical: Bool, seed start: UInt64) -> UIImage {
        let along = Int(alongPoints) * px, depth = Int(depthPoints) * px
        var seed = start
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let width = vertical ? depth : along, height = vertical ? along : depth
        // Плавные поля — по точкам, а не по пикселям (P731): им чёткость не
        // нужна, а считать их втрое подробнее — в девять раз дольше.
        let cw = width / px, ch = height / px
        let reachBig = smoothField(width: cw, height: ch, cell: 160, wrapX: !vertical, wrapY: vertical, next: next)
        let reachSmall = smoothField(width: cw, height: ch, cell: 60, wrapX: !vertical, wrapY: vertical, next: next)
        let tone = smoothField(width: cw, height: ch, cell: 350, wrapX: !vertical, wrapY: vertical, next: next)
        let mottle = mottling(width: cw, height: ch, wrapX: !vertical, wrapY: vertical, next: next)
        let torn = tornLine(length: along, scale: Float(px), deep: 3.2, next: next)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let k = Float(wearStrength)
        let fadeFrom = Float(depth) * 0.5
        for y in 0..<height {
            for x in 0..<width {
                let d = vertical ? x : depth - 1 - y          // пикселей от края картинки
                let a = vertical ? y : x                      // место вдоль края
                let i = y * width + x
                let fromTear = Float(d) - torn[a]             // пикселей от рваного края
                if fromTear < 0 {
                    // Вырванное: тёмная тень под листом.
                    write(&bytes, i * 4, grey ? greyTorn : warmTorn, 0.85)
                    continue
                }
                let distance = fromTear / Float(px)
                // Дальше 14 затуханий износа нет — не считаем (P731).
                guard distance < falloff * 14 else { continue }
                // Поля — плавно между точками (P744): прежде бралась
                // ближайшая точка, и пятна у края шли квадратиками.
                let fx = Float(x) / Float(px), fy = Float(y) / Float(px)
                let reach = max(0.5, min(2, 1 + 0.35 * (smooth(reachBig, cw, ch, fx, fy)
                                                         + 0.4 * smooth(reachSmall, cw, ch, fx, fy))))
                let strength = max(0.35, 1 + 0.4 * smooth(tone, cw, ch, fx, fy))
                var worn = min(peak * k * strength * exp(-distance / (falloff * reach)), 0.75)
                if Float(d) > fadeFrom {
                    let q = (Float(depth) - Float(d)) / (Float(depth) - fadeFrom)
                    worn *= q * q * (3 - 2 * q)
                }
                paintAged(&bytes, i * 4, worn: worn, distance: distance, mottle: smooth(mottle, cw, ch, fx, fy))
            }
        }
        let plain = picture(bytes, width: width, height: height, scale: CGFloat(px))
        // Мелкие изъяны на полях (P729): только у самого края, где нет
        // текста, — бок до 9 точек, низ — нижние 12 (P748: «ещё сильнее
        // сместить к краям»); подальше от концов куска, чтобы шов плитки
        // их не резал.
        let size = CGSize(width: CGFloat(width) / CGFloat(px), height: CGFloat(height) / CGFloat(px))
        let margin = vertical
            ? CGRect(x: 1, y: 12, width: 8, height: size.height - 24)
            : CGRect(x: 12, y: size.height - 12, width: size.width - 24, height: 11)
        let scaleOfFlaws = Float(vertical ? size.height : size.width) / 480
        let format = UIGraphicsImageRendererFormat(); format.scale = CGFloat(px)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            plain.draw(at: .zero)
            scatterFlaws(ctx.cgContext, in: margin, amount: scaleOfFlaws,
                         inward: vertical ? 0 : -.pi / 2, next: next)
        }
    }

    /// Мелкие изъяны бумаги на полях (P729): волоски, крошечные щербинки и
    /// крапинки (иногда кучкой), бледные складочки — следы замятости, идут
    /// от края внутрь (`inward` — направление внутрь листа). Всё бледное,
    /// без бликов, чтобы не мешать читать. `amount` — на сколько кусков по
    /// 480 точек края рассчитано.
    private static func scatterFlaws(_ cg: CGContext, in area: CGRect, amount: Float, inward: CGFloat,
                                     next: () -> Float) {
        func r() -> CGFloat { CGFloat(next()) }
        func spot() -> CGPoint { CGPoint(x: area.minX + r() * area.width, y: area.minY + r() * area.height) }
        let ink = UIColor(red: 0.36, green: 0.24, blue: 0.13, alpha: 1)
        cg.saveGState()
        cg.clip(to: area.insetBy(dx: -2, dy: -2))
        cg.setLineCap(.round)
        // Волоски: тонкие изогнутые, разной длины.
        for _ in 0..<Int(amount * (2 + next() * 3)) {
            let a = spot()
            let length = 3 + r() * 8
            let turn = r() * .pi * 2
            let b = CGPoint(x: a.x + cos(turn) * length, y: a.y + sin(turn) * length)
            let bend = CGPoint(x: (a.x + b.x) / 2 + (r() - 0.5) * length * 0.6,
                               y: (a.y + b.y) / 2 + (r() - 0.5) * length * 0.6)
            cg.move(to: a); cg.addQuadCurve(to: b, control: bend)
            cg.setStrokeColor(ink.withAlphaComponent(0.18 + r() * 0.14).cgColor)
            cg.setLineWidth(0.3 + r() * 0.25)
            cg.strokePath()
        }
        // Щербинки и крапинки: неровные, где по одной, где кучкой.
        for _ in 0..<Int(amount * (6 + next() * 8)) {
            let centre = spot()
            let cluster = next() < 0.3 ? 2 + Int(next() * 4) : 1
            for _ in 0..<cluster {
                let at = CGPoint(x: centre.x + (r() - 0.5) * 3, y: centre.y + (r() - 0.5) * 3)
                let rad = 0.25 + r() * 0.6
                let pit = CGMutablePath()
                for k in 0..<7 {
                    let ang = CGFloat(k) / 7 * .pi * 2
                    let rr = rad * (0.6 + r() * 0.7)
                    let pt = CGPoint(x: at.x + cos(ang) * rr, y: at.y + sin(ang) * rr * (0.6 + r() * 0.6))
                    if k == 0 { pit.move(to: pt) } else { pit.addLine(to: pt) }
                }
                pit.closeSubpath()
                cg.addPath(pit)
                cg.setFillColor(ink.withAlphaComponent(0.16 + r() * 0.2).cgColor)
                cg.fillPath()
            }
        }
        // Следы замятости: бледная складочка — тёмная ложбинка и светлый
        // гребень рядом, от края внутрь листа под разным углом.
        for _ in 0..<Int(amount * (1 + next() * 2.5)) {
            let a = spot()
            let length = 8 + r() * 18
            let turn = inward + (r() - 0.5) * 1.2
            let b = CGPoint(x: a.x + cos(turn) * length, y: a.y + sin(turn) * length)
            let bend = CGPoint(x: (a.x + b.x) / 2 + (r() - 0.5) * 4, y: (a.y + b.y) / 2 + (r() - 0.5) * 4)
            let fold = CGMutablePath()
            fold.move(to: a); fold.addQuadCurve(to: b, control: bend)
            cg.addPath(fold)
            cg.setStrokeColor(ink.withAlphaComponent(0.13).cgColor)
            cg.setLineWidth(0.5)
            cg.strokePath()
            cg.saveGState()
            cg.translateBy(x: 0.6, y: 0.6)
            cg.addPath(fold)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor)
            cg.setLineWidth(0.45)
            cg.strokePath()
            cg.restoreGState()
        }
        cg.restoreGState()
    }

    /// Цвет старой бумаги в точке (P727, по образцу автора): к краю — из
    /// бежевого в тёплую охру, у самого края — тёмная опалённая кромка; тон
    /// чуть неровный (`mottle`), без бугорков и бликов.
    private static func paintAged(_ bytes: inout [UInt8], _ i: Int, worn: Float, distance: Float, mottle: Float) {
        let rim = 0.55 * exp(-distance / 1.4)
        // Серый износ — на четверть прозрачнее (P848): на светлой серой бумаге
        // он виден резче тёплого.
        let soften: Float = grey ? 0.75 : 1
        let alpha = min(1 - (1 - max(0, worn * (1 + 0.3 * mottle))) * (1 - rim), 0.9) * soften
        guard alpha > 0.003 else { return }
        let t = min(1, rim / 0.4 + max(0, worn - 0.3) * 0.8)
        let c = (amber.r + (burnt.r - amber.r) * t,
                 amber.g + (burnt.g - amber.g) * t,
                 amber.b + (burnt.b - amber.b) * t)
        write(&bytes, i, c, alpha)
    }

    private static func write(_ bytes: inout [UInt8], _ i: Int, _ c: (Float, Float, Float), _ alpha: Float) {
        bytes[i] = UInt8(min(c.0 * alpha, 1) * 255)
        bytes[i + 1] = UInt8(min(c.1 * alpha, 1) * 255)
        bytes[i + 2] = UInt8(min(c.2 * alpha, 1) * 255)
        bytes[i + 3] = UInt8(min(alpha, 1) * 255)
    }

    /// Неровность тона (P727): мягкие пятна в несколько точек и мельче —
    /// как у образца, без рельефа.
    private static func mottling(width: Int, height: Int, wrapX: Bool, wrapY: Bool, next: () -> Float) -> [Float] {
        let a = smoothField(width: width, height: height, cell: 14, wrapX: wrapX, wrapY: wrapY, next: next)
        let b = smoothField(width: width, height: height, cell: 4, wrapX: wrapX, wrapY: wrapY, next: next)
        return normalised(zip(a, b).map { $0 * 0.6 + $1 * 0.8 })
    }

    /// Рваный край (P727; с P728 у каждого края свой характер и каждая
    /// выщербина своя): насколько бумага вырвана вглубь от ровного края,
    /// в пикселях, по длине края. Волна крупная, средняя и мелкая — их сила
    /// и шаг у каждого края свои: один край ровнее, другой лохматее.
    /// Выщербины собраны из нескольких кусков разной ширины и глубины, с
    /// разной крутизной слева и справа — от острого клина до плоской
    /// ямки, — и с рваной кромкой внутри. Замкнута по длине — кусок края
    /// повторяется без шва. `deep` — средняя глубина в точках.
    private static func tornLine(length n: Int, scale: Float, deep: Float, next: () -> Float) -> [Float] {
        func wave(_ cell: Int) -> [Float] {
            let count = max(2, n / max(1, cell))
            let nodes = (0..<count).map { _ in next() }
            return (0..<n).map { p in
                let f = Float(p) * Float(count) / Float(n)
                let i = Int(f) % count, j = (i + 1) % count
                let t = f - Float(Int(f)), u = t * t * (3 - 2 * t)
                return nodes[i] + (nodes[j] - nodes[i]) * u
            }
        }
        let aBig = 0.25 + next() * 0.6, aMid = 0.15 + next() * 0.45, aFine = 0.1 + next() * 0.35
        let big = wave(Int((50 + next() * 50) * scale))
        let mid = wave(Int((8 + next() * 10) * scale))
        let fine = wave(Int((2 + next() * 2.5) * scale))
        let grit = wave(Int(1.5 * scale))
        var out = (0..<n).map { p in (big[p] * aBig + mid[p] * aMid + fine[p] * aFine) * deep * scale }
        let density = 0.3 + next() * 1.4
        let bites = Int(Float(n) / (120 * scale) * density + next())
        let half = Float(n) / 2
        for _ in 0..<bites {
            let at = Float(n) * next()
            let size = (3 + next() * 9) * scale                     // полуширина
            let depth = (1.2 + next() * 3.5) * deep * scale * 0.6
            // Куски выщербины: сдвиг, ширина слева и справа, глубина,
            // крутизна (1 — острый клин, 4 — плоская ямка).
            var parts: [(off: Float, left: Float, right: Float, d: Float, p: Float)] = []
            for _ in 0..<(1 + Int(next() * 4)) {
                parts.append(((next() - 0.5) * size * 1.4,
                              size * (0.25 + next() * 0.8), size * (0.25 + next() * 0.8),
                              depth * (0.35 + next() * 0.65), 1.1 + next() * 2.9))
            }
            let ragged = 0.15 + next() * 0.5
            for p in 0..<n {
                var dp = Float(p) - at
                if dp > half { dp -= Float(n) } else if dp < -half { dp += Float(n) }
                guard abs(dp) < size * 3 else { continue }
                var cut: Float = 0
                for part in parts {
                    let x = dp - part.off
                    let w = x < 0 ? part.left : part.right
                    cut = max(cut, part.d * exp(-pow(abs(x) / w, part.p)))
                }
                if cut > 0.01 { out[p] += cut * (1 + ragged * (grit[p] * 2 - 1)) }
            }
        }
        return out
    }

    /// Плавное случайное поле на плоскости (P723): случайные значения в
    /// узлах сетки с шагом `cell` пикселей, между ними — мягкий переход.
    /// По `wrapX`/`wrapY` замкнуто по ширине или высоте. Среднее 0, разброс 1.
    private static func smoothField(width: Int, height: Int, cell: Int, wrapX: Bool, wrapY: Bool,
                                    next: () -> Float) -> [Float] {
        let gx = max(1, width / cell) + (wrapX ? 0 : 2)
        let gy = max(1, height / cell) + (wrapY ? 0 : 2)
        let nodes = (0..<gx * gy).map { _ in next() }
        let sx = wrapX ? Float(gx) / Float(width) : 1 / Float(cell)
        let sy = wrapY ? Float(gy) / Float(height) : 1 / Float(cell)
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let fy = Float(y) * sy
            let iy = Int(fy)
            let ty = fy - Float(iy), uy = ty * ty * (3 - 2 * ty)
            let y0 = wrapY ? iy % gy : min(iy, gy - 1)
            let y1 = wrapY ? (iy + 1) % gy : min(iy + 1, gy - 1)
            for x in 0..<width {
                let fx = Float(x) * sx
                let ix = Int(fx)
                let tx = fx - Float(ix), ux = tx * tx * (3 - 2 * tx)
                let x0 = wrapX ? ix % gx : min(ix, gx - 1)
                let x1 = wrapX ? (ix + 1) % gx : min(ix + 1, gx - 1)
                let top = nodes[y0 * gx + x0] + (nodes[y0 * gx + x1] - nodes[y0 * gx + x0]) * ux
                let bottom = nodes[y1 * gx + x0] + (nodes[y1 * gx + x1] - nodes[y1 * gx + x0]) * ux
                out[y * width + x] = top + (bottom - top) * uy
            }
        }
        return normalised(out)
    }

    /// Номер дня для износа мелкой бумаги: у каждого дня свой.
    static func seed(_ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 86400).rounded(.down))
    }

    /// Износ мелкой бумаги: края и маска рваного края.
    final class AgedArt: NSObject {
        let frame: UIImage
        let cut: UIImage
        init(frame: UIImage, cut: UIImage) { self.frame = frame; self.cut = cut }
    }

    /// Готовый лист из пачки заготовок (P732, по слову автора «заготовить
    /// листы заранее и раскладывать готовые»): листов немного — 16 клеток и
    /// строк, 24 карточки на размер, — день берёт свой по номеру; рисуются
    /// в стороне, хранятся в служебной памяти (`PaperShop`). Пока лист не
    /// готов — `nil`: показывается просто цвет прошлого, бумага проступает
    /// следом. Размер округляется (у строк и клеток до 4 точек, у карточек
    /// до 20), лист тянется на свой размер — разница незаметна.
    struct AgedOrder: Hashable {
        let key: String, w: CGFloat, h: CGFloat, band: CGFloat, variant: Int, openBottom: Bool, light: Bool
        /// Карточка с корешком (P859): высота корешка и его доля ширины; 0 — без корешка.
        var tab: CGFloat = 0
        var share: CGFloat = 1.0 / 3
    }

    static func agedOrder(size: CGSize, band: CGFloat, seed number: Int, openBottom: Bool = false,
                          light: Bool = false, kinds: Int? = nil,
                          tab: CGFloat = 0, share: CGFloat = 1.0 / 3) -> AgedOrder {
        let small = min(size.width, size.height) < 60
        let step: CGFloat = small ? 4 : 20
        let w = max(4, size.width.rounded())
        let h = max(step, (size.height / step).rounded() * step)
        let variant = abs(number) % (kinds ?? (small ? 16 : 24))
        // Серая бумага (P825) — свой ключ: лист, уже показанный тёплым,
        // заказывается заново.
        var key = "\(Int(w))x\(Int(h))b\(Int(band * 10))v\(variant)\(openBottom ? "o" : "")\(light ? "l" : "")"
        if grey { key += "g" }
        if tab > 0 { key += "t\(Int(tab))s\(Int((share * 100).rounded()))" }
        return AgedOrder(key: key, w: w, h: h, band: band, variant: variant, openBottom: openBottom, light: light,
                         tab: tab, share: share)
    }

    /// Готовый лист, если он уже в памяти, — сразу.
    static func agedReady(_ order: AgedOrder) -> AgedArt? {
        PaperShop.shared.readyArt(order.key)
    }

    /// Лист — когда будет готов (в стороне от экрана).
    static func aged(_ order: AgedOrder) async -> AgedArt {
        await PaperShop.shared.art(order.key, small: min(order.w, order.h) < 60) {
            if order.tab > 0 {
                return makeAgedFolder(size: CGSize(width: order.w, height: order.h), band: order.band,
                                      seed: order.variant + 1, tab: order.tab, share: order.share,
                                      light: order.light)
            }
            return makeAged(size: CGSize(width: order.w, height: order.h), band: order.band, seed: order.variant + 1,
                     openBottom: order.openBottom, light: order.light)
        }
    }

    /// Старая бумага под размер клетки, строки или карточки (P727, по
    /// образцу автора; отменяет отдельные травмы, загнутые уголки и
    /// рельеф P723–P726): край рваный — волнистый, кое-где вырван глубже,
    /// вырезан маской `cut`; у края — тёмная опалённая кромка, от неё
    /// внутрь тёплая охра сходит на нет, тон чуть неровный. Всё — по номеру
    /// `seed`: вид одного дня не меняется. `band` — ширина потемнения.
    /// `openBottom` — низ уходит под следующую карточку: ровный и чистый.
    fileprivate static func makeAged(size: CGSize, band: CGFloat, seed number: Int, openBottom: Bool,
                                     light: Bool) -> AgedArt {
        let w = size.width, h = size.height
        var seed = UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15 &+ 0xA6ED0 &+ UInt64(band * 10)
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let W = Int(w) * px, H = Int(h) * px
        let wear = min(band, min(w, h) * 0.18)
        // Плавные поля — по точкам (P731), рваный край и кромка — по пикселям.
        let cw = Int(w), ch = Int(h)
        let reachField = smoothField(width: cw, height: ch, cell: 30, wrapX: false, wrapY: false, next: next)
        let tone = smoothField(width: cw, height: ch, cell: 60, wrapX: false, wrapY: false, next: next)
        let mottle = mottling(width: cw, height: ch, wrapX: false, wrapY: false, next: next)
        // Рваный край по каждой стороне: мелкий — у клеток, крупнее — у карточек.
        // `light` — слегка тронутая бумага (P728: карточка сегодняшнего дня
        // в поиске не должна выглядеть совсем целой среди старых).
        let deep: Float = (min(w, h) < 60 ? 0.9 : 1.6) * (light ? 0.45 : 1)
        let torn = [W, W, H, H].enumerated().map { e, n -> [Float] in
            if openBottom && e == 1 { return [Float](repeating: 0, count: n) }
            // Верх карточки состарен так же, как бока (P823, автор: «в верхней
            // части карточек прошлого не обработаны состариванием»; прежде
            // вдвое мельче, P742).
            // Верх карточки рвётся мельче боков (P848: во всю глубину, P823,
            // край выглядел грубо), но заметнее прежней половины (P742).
            return tornLine(length: n, scale: Float(px), deep: openBottom && e == 0 ? deep * 0.7 : deep,
                            next: next)
        }
        var power = (0..<4).map { _ in 0.75 + next() * 0.3 }        // верх, низ, лево, право
        if openBottom { power[1] = 0 }
        if light { power = power.map { $0 * 0.3 } }
        let fall = Float(wear) * Float(px) / 1.6                             // в пикселях
        let peak: Float = 0.45
        var frameBytes = [UInt8](repeating: 0, count: W * H * 4)
        var cutBytes = [UInt8](repeating: 0, count: W * H * 4)
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                let d0 = Float(y) - torn[0][x], d1 = Float(H - 1 - y) - torn[1][x]
                let d2 = Float(x) - torn[2][y], d3 = Float(W - 1 - x) - torn[3][y]
                let nearest = min(min(d0, d1), min(d2, d3))
                // Маска: внутри — бумага, у рваного края — мягкий переход в пиксель.
                let inside = max(0, min(1, nearest + 0.5))
                cutBytes[i * 4 + 3] = UInt8(inside * 255)
                guard inside > 0 else { continue }
                // Дальше восьми затуханий от края износа уже не видно —
                // середину карточки не считаем (P731).
                guard nearest < fall * 2 * 8 else { continue }
                let fx = Float(x) / Float(px), fy = Float(y) / Float(px)
                let reach = fall * max(0.5, min(2, 1 + 0.35 * smooth(reachField, cw, ch, fx, fy)))
                let strength = max(0.4, 1 + 0.3 * smooth(tone, cw, ch, fx, fy))
                func kept(_ e: Int, _ d: Float) -> Float {
                    1 - min(peak * power[e] * strength * exp(-max(0, d) / reach), 0.75)
                }
                let keep = kept(0, d0) * kept(1, d1) * kept(2, d2) * kept(3, d3)
                // Кромка — только у рваных сторон (низ карточки поиска чистый).
                let rimEdge = openBottom ? min(min(d0, d2), d3) : nearest
                paintAged(&frameBytes, i * 4, worn: 1 - keep, distance: max(0, rimEdge) / Float(px),
                          mottle: smooth(mottle, cw, ch, fx, fy))
            }
        }
        var frame = picture(frameBytes, width: W, height: H, scale: CGFloat(px))
        // Мелкие изъяны на боковых полях крупной бумаги — карточек поиска
        // (P729); у клеток и строк полей нет.
        if min(w, h) > 60 && !light {
            let format = UIGraphicsImageRendererFormat(); format.scale = CGFloat(px)
            let plain = frame
            let amount = Float(h) / 480
            frame = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
                plain.draw(at: .zero)
                scatterFlaws(ctx.cgContext, in: CGRect(x: 3, y: 30, width: 10, height: h - 40),
                             amount: amount, inward: 0, next: next)
                scatterFlaws(ctx.cgContext, in: CGRect(x: w - 13, y: 30, width: 10, height: h - 40),
                             amount: amount, inward: .pi, next: next)
            }
        }
        return AgedArt(frame: frame, cut: picture(cutBytes, width: W, height: H, scale: CGFloat(px)))
    }

    /// Карточка картотеки с корешком (P859, автор по 259: «сверху один тип
    /// износа, с боков другой», «вверху слишком локально перетемнены, у букв
    /// дня недели затемнение резко кончается»). Прежде верх рвался и темнел
    /// по прямой верхней кромке картинки — то есть только у корешка, — а
    /// вырез корешка и плечо затирались отдельно, другим способом
    /// (`EdgeWear`, P854), и полоса выреза начиналась резко. Теперь край
    /// один — сам контур карточки: корешок, его скругления, вырез, плечо и
    /// бока рвутся и темнеют одинаково, по расстоянию до ближайшего края.
    /// Углы не темнеют вдвое: берётся ближайший край, а не сумма двух. Низ
    /// уходит под следующую карточку — чистый.
    fileprivate static func makeAgedFolder(size: CGSize, band: CGFloat, seed number: Int, tab: CGFloat,
                                           share: CGFloat, light: Bool) -> AgedArt {
        let w = size.width, h = size.height
        var seed = UInt64(bitPattern: Int64(number)) &* 0x9E37_79B9_7F4A_7C15 &+ 0xA6ED0 &+ UInt64(band * 10)
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let W = Int(w) * px, H = Int(h) * px
        let wear = min(band, min(w, h) * 0.18)
        let cw = Int(w), ch = Int(h)
        let reachField = smoothField(width: cw, height: ch, cell: 30, wrapX: false, wrapY: false, next: next)
        let tone = smoothField(width: cw, height: ch, cell: 60, wrapX: false, wrapY: false, next: next)
        let mottle = mottling(width: cw, height: ch, wrapX: false, wrapY: false, next: next)
        let deep: Float = 1.6 * (light ? 0.45 : 1)
        // Верх по контуру рвётся мельче боков (P848).
        let topTear = tornLine(length: W, scale: Float(px), deep: deep * 0.7, next: next)
        let leftTear = tornLine(length: H, scale: Float(px), deep: deep, next: next)
        let rightTear = tornLine(length: H, scale: Float(px), deep: deep, next: next)
        let roof = folderRoof(width: W, height: H, size: size, tab: tab, share: share)
        var inside = [Bool](repeating: false, count: W * H)
        for y in 0..<H {
            let fy = Float(y)
            for x in 0..<W {
                inside[y * W + x] = fy >= roof[x] + topTear[x]
                    && Float(x) >= leftTear[y] && Float(W - 1 - x) >= rightTear[y]
            }
        }
        let dist = edgeDistance(inside, width: W, height: H)
        var power: Float = 0.75 + next() * 0.3
        if light { power *= 0.3 }
        let fall = Float(wear) * Float(px) / 1.6                             // в пикселях
        let peak: Float = 0.45
        var frameBytes = [UInt8](repeating: 0, count: W * H * 4)
        var cutBytes = [UInt8](repeating: 0, count: W * H * 4)
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                guard inside[i] else { continue }
                // У самого края расстояние — один пиксель: край мягкий, в полпикселя.
                let d = dist[i] - 1
                cutBytes[i * 4 + 3] = UInt8(max(0, min(1, d + 0.5)) * 255)
                guard d < fall * 2 * 8 else { continue }
                let fx = Float(x) / Float(px), fy = Float(y) / Float(px)
                let reach = fall * max(0.5, min(2, 1 + 0.35 * smooth(reachField, cw, ch, fx, fy)))
                let strength = max(0.4, 1 + 0.3 * smooth(tone, cw, ch, fx, fy))
                let worn = min(peak * power * strength * exp(-max(0, d) / reach), 0.75)
                paintAged(&frameBytes, i * 4, worn: worn, distance: max(0, d) / Float(px),
                          mottle: smooth(mottle, cw, ch, fx, fy))
            }
        }
        var frame = picture(frameBytes, width: W, height: H, scale: CGFloat(px))
        if min(w, h) > 60 && !light {
            let format = UIGraphicsImageRendererFormat(); format.scale = CGFloat(px)
            let plain = frame
            let amount = Float(h) / 480
            frame = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
                plain.draw(at: .zero)
                scatterFlaws(ctx.cgContext, in: CGRect(x: 3, y: tab + 8, width: 10, height: max(1, h - tab - 18)),
                             amount: amount, inward: 0, next: next)
                scatterFlaws(ctx.cgContext, in: CGRect(x: w - 13, y: tab + 8, width: 10, height: max(1, h - tab - 18)),
                             amount: amount, inward: .pi, next: next)
            }
        }
        return AgedArt(frame: frame, cut: picture(cutBytes, width: W, height: H, scale: CGFloat(px)))
    }

    /// Верх карточки по столбцам, в пикселях (P859): где начинается сама
    /// фигура — корешок со скруглениями, вырез, плечо.
    private static func folderRoof(width W: Int, height H: Int, size: CGSize, tab: CGFloat,
                                   share: CGFloat) -> [Float] {
        var roof = [Float](repeating: 0, count: W)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return roof }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        // Сверху вниз, в точках — как рисует SwiftUI.
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: CGFloat(px), y: -CGFloat(px))
        let shape = FolderShape(tabHeight: tab, tabShare: share)
        ctx.addPath(shape.path(in: CGRect(origin: .zero, size: size)).cgPath)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        guard let data = ctx.data else { return roof }
        let row = ctx.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: row * H)
        for x in 0..<W {
            var y = 0
            while y < H && bytes[y * row + x] < 128 { y += 1 }
            roof[x] = Float(y)
        }
        return roof
    }

    /// Расстояние от каждой точки бумаги до ближайшего края, в пикселях
    /// (P859): два прохода — сверху слева и снизу справа. За картинкой сверху
    /// и с боков — край; снизу — нет: низ карточки уходит под следующую.
    private static func edgeDistance(_ inside: [Bool], width W: Int, height H: Int) -> [Float] {
        let far: Float = 1e6
        let diag: Float = 1.4142
        var d = inside.map { $0 ? far : 0 }
        func at(_ x: Int, _ y: Int) -> Float {
            if x < 0 || x >= W || y < 0 { return 0 }
            if y >= H { return far }
            return d[y * W + x]
        }
        for y in 0..<H {
            for x in 0..<W where d[y * W + x] > 0 {
                var v = d[y * W + x]
                v = min(v, at(x - 1, y) + 1)
                v = min(v, at(x - 1, y - 1) + diag)
                v = min(v, at(x, y - 1) + 1)
                v = min(v, at(x + 1, y - 1) + diag)
                d[y * W + x] = v
            }
        }
        for y in stride(from: H - 1, through: 0, by: -1) {
            for x in stride(from: W - 1, through: 0, by: -1) where d[y * W + x] > 0 {
                var v = d[y * W + x]
                v = min(v, at(x + 1, y) + 1)
                v = min(v, at(x + 1, y + 1) + diag)
                v = min(v, at(x, y + 1) + 1)
                v = min(v, at(x - 1, y + 1) + diag)
                d[y * W + x] = v
            }
        }
        return d
    }

    /// Рельеф шершавой бумаги (P676, отменяет пятна и волоски): впадинки и
    /// бугорки, освещённые слева сверху, как все тени (P670). Складывается
    /// из двух слоёв случайных высот — мелкого и крупного; каждая точка
    /// светлеет или темнеет по тому, куда наклонена. Плитка 128 точек
    /// замкнута сама на себя — шва нет. Рисуется один раз.
    static let relief: UIImage = {
        let n = 256                                  // пикселей, плитка 128 точек при масштабе 2
        var seed: UInt64 = 0x0E11EF
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let noise1 = (0..<n * n).map { _ in next() }
        let noise2 = (0..<n * n).map { _ in next() }
        let fine = normalised(wrapBlur(noise1, side: n, radius: 1, passes: 2))
        let coarse = normalised(wrapBlur(noise2, side: n, radius: 2, passes: 4))
        let height = zip(fine, coarse).map { $0 + $1 * 1.6 }
        // Наклон: свет слева сверху — склон, смотрящий на свет, светлый.
        var lit = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let h = height[y * n + x]
                let dx = height[y * n + (x + 1) % n] - h
                let dy = height[((y + 1) % n) * n + x] - h
                lit[y * n + x] = -(dx + dy)
            }
        }
        lit = normalised(lit)
        // Светлое — белым, тёмное — чёрным, густота по наклону.
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<n * n {
            let v = lit[i] * Float(PageTexture.reliefStrength)
            let white = v > 0
            let alpha = min(abs(v) * (white ? 0.11 : 0.021), 0.5)
            let c: Float = white ? 1 : 0
            bytes[i * 4] = UInt8(c * alpha * 255)
            bytes[i * 4 + 1] = UInt8(c * alpha * 255)
            bytes[i * 4 + 2] = UInt8(c * alpha * 255)
            bytes[i * 4 + 3] = UInt8(alpha * 255)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()

    /// Густота рельефа: 1 — средняя (в эскизе `docs/paper/рельеф.png` — второй
    /// вариант); 0,55 — тихая, 1,55 — резкая.
    static let reliefStrength = CGFloat(1.3)
}
