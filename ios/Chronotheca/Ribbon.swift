import SwiftUI
import UIKit

/// Лента картотеки (P777): прошлые карточки, место дня, будущие карточки —
/// одной прокруткой, вплотную, без щелей. Вместо трёх плашек (прошлое,
/// день, будущее) с полями между ними (P771–P776).
///
/// Живой день второй раз не рисуется: в ленте под него оставлено пустое
/// место его высоты, а сам день едет за этим местом. Так легче телефону —
/// одна страница дня, а не её копия в ленте.
///
/// Пока ленту ведёт сама программа (тяга из дня, доезд, возврат), место дня
/// и прокрутка двигаются в одном такте, без отставания на кадр. Когда ленту
/// листает палец, день следует за замером места.
final class Ribbon: ObservableObject {

    /// Ключ места дня в ленте.
    static let slotID = "ribbon-day"
    /// Система мер ленты: от верха её экрана.
    static let space = "ribbon"

    /// Где верх места дня — от верха экрана раздела. По нему едет день.
    @Published private(set) var y: CGFloat = 0

    /// Прокрутка ленты.
    let box = SheetScroller()
    /// Высота места дня — высота экрана раздела.
    var height: CGFloat = 0
    /// Насколько вчерашняя карточка (над местом дня) выступает над ним — её
    /// высота без наползания (P837). Мерит сама карточка; ноль — не мерена.
    var aboveGap: CGFloat = 0
    /// За сколько точек тяги ближнее плечо позади листа ложится на место
    /// вчерашней карточки (P837). Порог открытия картотеки — 150.
    static let reveal: CGFloat = 130
    /// Место дня собрано в ленте и его замер верен.
    var seen = false
    /// Поставить место дня на верх экрана (ставит сама лента, без хода).
    var home: (() -> Void)?
    /// Ленту ведёт программа — замеры не перебивают её.
    private var driving = false
    /// Где верх места дня в самой ленте (в её содержимом). Положение дня на
    /// экране всегда считается от него и от настоящей прокрутки — день не
    /// может разойтись с местом, кто бы ни сдвинул ленту: палец, программа
    /// или сама лента, доводя переход к карточке (снимки CI к P777).
    private var slotTop: CGFloat = 0
    private var watch: NSKeyValueObservation?
    private weak var watched: UIScrollView?

    private var link: CADisplayLink?
    private var startOffset: CGFloat = 0
    private var shift: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var length: CFTimeInterval = 0.3
    /// С какой скоростью лента шла в миг начала хода (точек в секунду, в
    /// мерах прокрутки) — ход подхватывает её (P820).
    private var startSpeed: CGFloat = 0
    private var done: (() -> Void)?

    /// Скорость дня на экране по последним сдвигам — чтобы ход после
    /// отпускания продолжал движение пальца, а не срывался с места.
    private var lastY: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private var speed: CGFloat = 0

    /// Когда ленту открыли — первые полторы секунды она ещё встаёт в покой,
    /// пока догоняют высота экрана и опись.
    private var openedAt: CFTimeInterval = 0
    func opened() { openedAt = CACurrentMediaTime() }
    var fresh: Bool { CACurrentMediaTime() - openedAt < 1.5 }

    /// Где место дня стоит в покое: 1 — прошлое (вчера над нижней строкой,
    /// день за нижним краем), -1 — будущее (завтра под строкой поиска).
    func restY(_ dir: Int) -> CGFloat {
        // Будущее (P797): завтрашняя — у самого верха, день — над ним, за
        // верхним краем; строка поиска теперь внизу.
        dir > 0 ? height : -height
    }

    /// Ленту сейчас ведёт программа.
    var busy: Bool { driving }

    /// Замер места дня лентой: узнаём, где оно в содержимом.
    func measured(_ value: CGFloat) {
        guard let scroll = box.view else { return }
        watchScroll(scroll)
        // Пока ведёт программа, содержимое не меняется, а замер может
        // отставать на кадр от прокрутки — не верим ему.
        guard !driving else { return }
        slotTop = value + scroll.contentOffset.y
        known = true
        follow(scroll.contentOffset.y)
    }

    /// Следить за прокруткой ленты: каждый её сдвиг — сразу сдвиг дня.
    private func watchScroll(_ scroll: UIScrollView) {
        guard watched !== scroll else { return }
        watched = scroll
        watch = scroll.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
            self?.scrolled(view)
        }
        scroll.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
    }

    // MARK: - Порог у дня (P779)

    /// Держать ли сейчас стену у дня: лента открыта, её не тянут из дня.
    var walls: () -> Bool = { false }
    /// Дотянули до дня за порог и отпустили — в день.
    var wantDay: (() -> Void)?
    /// В день вернули тягой: толчок уже был на пороге, второго не надо (P800).
    var felt = false
    /// С какой стороны дня лента: 1 — прошлое (день ниже), -1 — будущее.
    /// Считается заново при каждом сдвиге (P785).
    private var wallSide = 1
    /// Где был палец, когда лента упёрлась в стену.
    private var anchor: CGFloat?
    private var armed = false
    /// Лента ставится своей рукой — свой сдвиг не разбирать.
    private var fixing = false
    /// Место дня хоть раз измерено. Стена держится и тогда, когда место
    /// за краем и лента его не собирает (`seen` — нет): иначе лента
    /// подъезжала к дню свободно, и порог начинал считаться поздно
    /// (проверка движения к P779).
    private var known = false

    /// Открытую ленту листают к дню — день не выезжает сразу (P779): лента
    /// упирается в стену у его края, за стеной идёт туго (как тяга из дня,
    /// `EdgePull.resisted`), на пороге — толчок в руку; отпустили за
    /// порогом — день, нет — лента возвращается к стене. Разгон пальца
    /// останавливается у стены.
    private func scrolled(_ scroll: UIScrollView) {
        guard !fixing else { return }
        guard walls(), !driving, link == nil, known, height > 0 else {
            if scroll.isTracking {
                Trace.note("лента: стены нет — открыта \(walls()) ведёт \(driving) ход \(link != nil) "
                    + "мерена \(known) высота \(Int(height))")
            }
            anchor = nil
            armed = false
            follow(scroll.contentOffset.y)
            return
        }
        let raw = slotTop - scroll.contentOffset.y
        let high = restY(1), low = restY(-1)
        // Сторона — по тому, где место дня сейчас, а не по памяти (P785):
        // прежде сторона по умолчанию была «прошлое», и открытое будущее,
        // вставшее на долю точки мимо места, лента уводила в прошлое.
        wallSide = raw >= (high + low) / 2 ? 1 : -1
        let wall = wallSide > 0 ? high : low
        let inside = wallSide > 0 ? raw < wall : raw > wall
        var target: CGFloat?
        Trace.note(String(format: "лента: день %.0f стена %.0f сторона %ld за стеной %@ палец ведёт %@",
                          raw, wall, wallSide, inside ? "да" : "нет", scroll.isTracking ? "да" : "нет"))
        if scroll.isTracking {
            // Где палец, а не сколько прошла тяга прокрутки: прокрутка сама
            // обнуляет свой ход по шагам, и порог не набирался (P783).
            let t = scroll.panGestureRecognizer.location(in: scroll.window ?? scroll).y
            if inside, anchor == nil { anchor = t }
            if let a = anchor {
                // Прошлое: день снизу, палец идёт вверх; будущее — вниз.
                let over = wallSide > 0 ? a - t : t - a
                // Ровно ноль — палец только что упёрся: отметку не сбрасывать
                // (P788; прежде сбрасывалась в тот же миг, и порог никогда не
                // набирался — видно по следу проверки).
                if over < 0 {
                    anchor = nil
                    armed = false
                    if inside { target = wall }
                } else {
                    let shown = EdgePull.resisted(over)
                    target = wallSide > 0 ? wall - shown : wall + shown
                    let on = over >= EdgePull.threshold
                    Trace.note(String(format: "лента: за стеной на %.0f, порог %@", over, on ? "взят" : "нет"))
                    if on && !armed { Feel.light() }
                    armed = on
                }
            }
        } else if inside {
            target = wall
        }
        if let target {
            fixing = true
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: slotTop - target),
                                    animated: false)
            fixing = false
        }
        follow(scroll.contentOffset.y)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
        let go = armed && pan.state == .ended
        Trace.note("лента: отпустили — \(go ? "в день" : "к стене") (состояние \(pan.state.rawValue))")
        anchor = nil
        armed = false
        // После того как прокрутка сама решит про разгон.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.walls(), !self.driving else { return }
            if go {
                self.felt = true
                self.wantDay?()
                return
            }
            let wall = self.restY(self.wallSide)
            let inside = self.wallSide > 0 ? self.y < wall - 0.5 : self.y > wall + 0.5
            if inside { self.glide(to: wall) }
        }
    }

    private func follow(_ offset: CGFloat) {
        let now = slotTop - offset
        let t = CACurrentMediaTime()
        let dt = t - lastTime
        if dt > 0.12 {
            speed = 0
        } else if dt > 0.001 {
            speed = speed * 0.4 + (now - lastY) / CGFloat(dt) * 0.6
        }
        lastY = now
        lastTime = t
        if abs(now - y) > 0.25 { y = now }
    }

    /// Место дня ушло из ленты далеко за край (её стопка его разобрала).
    func lost() {
        seen = false
    }

    /// Начало тяги из дня: место дня должно быть собрано и измерено. Если
    /// нет — ставим его и ждём следующего движения пальца.
    func begin() -> Bool {
        guard box.view != nil, seen else {
            home?()
            return false
        }
        interrupt()
        driving = true
        return true
    }

    /// Тянут: место дня — на `amount` от верха экрана (больше нуля — день
    /// ниже, сверху прошлое; меньше — день выше, снизу будущее). День
    /// сдвигается в том же такте, что и лента.
    func pull(_ amount: CGFloat) {
        guard driving, link == nil, let scroll = box.view else { return }
        scroll.contentOffset.y = slotTop - amount
    }

    /// Довести место дня до `target` (от верха экрана) мягким ходом.
    ///
    /// Ход подхватывает скорость, с которой лента шла под пальцем, и мягко
    /// встаёт (P820). Прежде ход в 0,3 с с резким началом срывался с места
    /// во много раз быстрее пальца — после плавной тяги был скачок. Чем
    /// дальше ехать, тем дольше ход, от 0,3 до 0,55 с.
    func glide(to target: CGFloat, duration: CFTimeInterval? = nil,
               then: (() -> Void)? = nil) {
        guard let scroll = box.view, seen || driving else {
            then?()
            return
        }
        interrupt()
        // Погасить разгон пальца: иначе прокрутка поехала бы своим ходом.
        scroll.setContentOffset(scroll.contentOffset, animated: false)
        driving = true
        startOffset = scroll.contentOffset.y
        shift = (slotTop - target) - startOffset
        startTime = CACurrentMediaTime()
        length = duration ?? min(0.55, max(0.3, 0.22 + Double(abs(shift)) / 1800))
        // Скорость в мерах прокрутки: день вниз — прокрутка назад. Только
        // свежая и в ту же сторону, куда ехать; не больше, чем даёт ход без
        // проскока за цель.
        var v = startTime - lastTime < 0.12 ? -speed : 0
        if v * shift <= 0 { v = 0 }
        let most = 2 * abs(shift) / CGFloat(length)
        startSpeed = max(-most, min(most, v))
        done = then
        let made = CADisplayLink(target: self, selector: #selector(tick))
        made.add(to: .main, forMode: .common)
        link = made
    }

    @objc private func tick() {
        guard let scroll = box.view else { finish(); return }
        let p = CGFloat(min(1, (CACurrentMediaTime() - startTime) / length))
        // Начало — со скорости пальца, конец — мягко, без отскока (кривая
        // Эрмита: начальная скорость задана, конечная ноль).
        let carry = (p * p * p - 2 * p * p + p) * startSpeed * CGFloat(length)
        let reach = (3 * p * p - 2 * p * p * p) * shift
        scroll.contentOffset.y = startOffset + carry + reach
        if p >= 1 { finish() }
    }

    /// Поставить место дня на `target` без хода.
    func place(_ target: CGFloat) {
        guard let scroll = box.view, seen, !driving else { return }
        scroll.contentOffset.y = slotTop - target
    }

    /// Лента в покой без хода. Место дня собрано — ставится сразу. Нет —
    /// лента сперва подводит его своим переходом к карточке; ставим, когда
    /// переход улёгся, и ещё раз проверяем: переход мог доводить себя сам.
    func settle(_ dir: Int, then: (() -> Void)? = nil) {
        if seen, !driving {
            place(restY(dir))
            then?()
            return
        }
        home?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.place(self.restY(dir))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if abs(self.y - self.restY(dir)) > 2 { self.place(self.restY(dir)) }
                then?()
            }
        }
    }

    /// Место дня — на верх экрана, под день, без хода.
    func park() {
        if seen, !driving { place(0) } else { home?() }
    }

    private func finish() {
        stop()
        driving = false
        let then = done
        done = nil
        then?()
    }

    /// Прерванный ход всё же договаривает своё: открыта лента или нет,
    /// тянут или нет — иначе это осталось бы висеть.
    private func interrupt() {
        guard link != nil else { return }
        stop()
        driving = false
        let then = done
        done = nil
        then?()
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    /// Тяга кончилась или ход прерван: замеры снова ведут день.
    func release() {
        guard link == nil else { return }
        driving = false
    }
}

/// День едет за своим местом в ленте (P777). Смотрит только на ленту:
/// при её прокрутке пересчитывается один сдвиг, а не весь экран.
struct FollowRibbon: ViewModifier {
    @ObservedObject var ribbon: Ribbon
    let live: Bool

    func body(content: Content) -> some View {
        let y = live ? ribbon.y : 0
        content
            .offset(y: FollowRibbon.shown(y, height: ribbon.height))
            // За верхней четвертью лист уходит под картотеку (P831).
            .zIndex(FollowRibbon.under(y, height: ribbon.height) ? -1 : 1)
    }

    /// Где лист «Дня», когда его место в ленте на `y` (P831). Вниз (прошлое)
    /// — вместе с местом. Вверх (будущее): до верхней четверти экрана лист
    /// поверх картотеки и чуть обгоняет место — завтрашняя карточка выходит
    /// из-под него, и на верхней четверти нижний край листа сравнивается с
    /// её верхним краем. Дальше лист отстаёт вдвое и уходит под картотеку:
    /// завтрашняя карточка наползает на него, и в покое лист выглядывает над
    /// ней, как карточка позади.
    static func shown(_ y: CGFloat, height: CGFloat) -> CGFloat {
        guard y < 0, height > 0 else { return y }
        let swap = -0.75 * height
        if y >= swap { return y - Search.overlap * (y / swap) }
        return swap - Search.overlap + (y - swap) * 0.5
    }

    /// Лист под картотекой — за верхней четвертью (P831).
    static func under(_ y: CGFloat, height: CGFloat) -> Bool {
        height > 0 && y < -0.75 * height
    }
}
