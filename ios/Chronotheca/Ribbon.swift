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
    /// Рост первой карточки под местом дня (P857).
    var laterHeight: CGFloat = 0

    /// Где лента в архиве — для линии слева (P850): 0 — у дня; к 1 — к самой
    /// старой карточке; к −1 — к самой дальней будущей.
    @Published private(set) var reach: CGFloat = 0
    /// Как собрана лента: поля сверху и снизу, карточек до будущего и
    /// всего, есть ли место дня. Ставит картотека при каждой сборке.
    var plan = Plan()
    struct Plan {
        var lead: CGFloat = 0
        var tail: CGFloat = 0
        var before = 0
        var total = 0
        var slot = true
    }

    /// Доля пройденного архива. Прошлое — от покоя «вчера над нижней
    /// строкой» до самого верха ленты; будущее — от покоя «завтра у верха»
    /// до самого низа. Без места дня (день закрыт в карточку, P834) граница
    /// будущего — по числу карточек: они одной высоты.
    private func measureReach(_ scroll: UIScrollView) {
        let offset = scroll.contentOffset.y
        let most = max(0, scroll.contentSize.height - scroll.bounds.height)
        let line: CGFloat
        if plan.slot {
            line = slotTop
        } else {
            let cards = scroll.contentSize.height - plan.lead - plan.tail
            let pitch = plan.total > 0 ? cards / CGFloat(plan.total) : 0
            line = plan.lead + CGFloat(plan.before) * pitch
        }
        let pastRest = line - height
        let futureRest = plan.slot ? slotTop + height : line
        var r: CGFloat = 0
        if offset < pastRest, pastRest > 0 {
            r = (pastRest - offset) / pastRest
        } else if offset > futureRest, most > futureRest {
            r = -(offset - futureRest) / (most - futureRest)
        }
        r = min(1, max(-1, r))
        if abs(r - reach) > 0.002 { reach = r }
    }
    /// Высота места дня — высота экрана раздела.
    var height: CGFloat = 0
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
        // Лист с экрана не уходит (P860): в прошлом вчерашняя карточка встаёт
        // над корешком «Сегодня» и уходит под него, как под следующую
        // карточку; в будущем завтрашняя — под полоской низа листа.
        dir > 0 ? height - FollowRibbon.peekBottom + Search.overlap : -height + FollowRibbon.peekTop
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
        measureReach(scroll)
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
        guard !frozen else { return }
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

    /// Лист прошедшего дня закрыт в карточку (P859): лист стоит, где был, и
    /// тает — место дня из ленты ушло, и замеры его больше не двигают.
    /// Прежде лист в этот миг пропадал разом (автор по 259: «низ листа,
    /// торчащий сверху экрана, рывком пропадает»).
    var frozen = false

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
/// Лист «Сегодня» с экрана не уходит (P860, автор по 259): внизу остаётся
/// корешок с именем дня и датой, вверху — полоска низа листа поверх
/// картотеки будущего. Касание или тяга за них — назад в день.
struct FollowRibbon: ViewModifier {
    @ObservedObject var ribbon: Ribbon
    let live: Bool

    func body(content: Content) -> some View {
        let y = live ? ribbon.y : 0
        content
            .offset(y: FollowRibbon.shown(y, height: ribbon.height))
            // Лист всегда поверх картотеки (P860, вместо ухода под неё за
            // верхней четвертью P831): карточки будущего выходят из-под его
            // низа, а он остаётся у верха.
            .zIndex(1)
    }

    /// Сколько листа видно внизу: корешок с именем дня и датой (P860).
    static var peekBottom: CGFloat { DayPage.folder.tabHeight + 4 }
    /// Сколько низа листа видно вверху (P860).
    static let peekTop: CGFloat = 44

    /// Верх листа, когда он стоит у верха экрана (P860): видна полоска его низа.
    static func topClamp(_ height: CGFloat) -> CGFloat {
        peekTop - height - DayPage.under
    }

    /// Где лист «Дня», когда его место в ленте на `y`. Вниз (прошлое) —
    /// вместе с местом, пока над нижним краем не останется один корешок
    /// (P860). Вверх (будущее): лист чуть обгоняет место — завтрашняя
    /// карточка выходит из-под него (P831), — пока у верха не останется
    /// полоска его низа.
    static func shown(_ y: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return y }
        if y >= 0 { return min(y, height - peekBottom) }
        let swap = -0.75 * height
        let ahead = y >= swap ? y - Search.overlap * (y / swap) : y - Search.overlap
        return max(ahead, topClamp(height))
    }
}

/// Где ты в картотеке (P845, замысел автора; вместо полей с месяцами и
/// числами P844): от середины левого края — вверх линия будущего, вниз
/// линия прошлого. Длина — насколько далеко ушёл от дня: чем дальше, тем
/// длиннее, у дня — ноль. Бегунка нет: середина — просто
/// рубеж, от которого растёт одна из двух линий. Мера — сдвиг ленты от места
/// дня; длина растёт всё медленнее и не доходит до краёв экрана. Ноль —
/// короткая черта поперёк середины (P859).
struct TimeLine: View {
    @ObservedObject var ribbon: Ribbon
    let height: CGFloat

    var body: some View {
        // Доля пройденного архива (P850, вместо «насколько ушли» P845):
        // прошлое растёт от середины вверх — на середине архива линия в
        // половину, у самой старой записи — до верха; будущее так же вниз.
        let reach: CGFloat = ribbon.reach
        let most: CGFloat = max(0, height / 2 - 70)
        let length: CGFloat = most * abs(reach)
        let past = reach > 0
        // Цвет — как у карточек картотеки, по гамме (P846): та же бумага цвета
        // прошлого и та же кромка; прошлое — с кромкой темнее (его края
        // затёрты сильнее), будущее — светлее.
        let rim: Color = Scheme.current.kraftEdge.opacity(past ? 0.9 : 0.45)
        ZStack {
            // Ноль — короткая черта поперёк середины (P859, автор по 259): от
            // неё линия уходит вверх или вниз. Не доходит ни до края экрана, ни
            // до карточек: полоса линии — 24 точки, черта — 12 посередине.
            Capsule()
                .fill(Scheme.current.kraftEdge.opacity(0.7))
                .frame(width: 12, height: 1.5)
                .frame(width: 24, height: height)
            Capsule()
                .fill(Scheme.current.past)
                .overlay(Capsule().strokeBorder(rim, lineWidth: 1))
                .frame(width: 5, height: max(0, length))
                // Прошлое — вверх от середины, будущее — вниз.
                .offset(y: past ? -length / 2 : length / 2)
                .frame(width: 24, height: height)
                .opacity(length < 1 ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
