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

    /// С какой стороны «Сегодня», пока закрывается не сегодняшний день
    /// (P896): −1 — сверху (закрыт будущий), 1 — снизу (прошедший).
    @Published var foldSide = 0

    /// Ключ места дня в ленте.
    static let slotID = "ribbon-day"
    /// Система мер ленты: от верха её экрана.
    static let space = "ribbon"

    /// Где верх места дня — от верха экрана раздела. По нему едет день.
    @Published private(set) var y: CGFloat = 0

    /// Прокрутка ленты.
    let box = SheetScroller()

    /// Где лента в архиве — для линии слева (P850): 0 — у дня; к 1 — к самой
    /// старой карточке; к −1 — к самой дальней будущей.
    @Published private(set) var reach: CGFloat = 0
    /// На листе сегодняшний день (P863): только его лист остаётся у края
    /// экрана. Прошедший уходит за край целиком — он закроется в карточку,
    /// и полоска его листа рядом со своей же карточкой мелькала (видео
    /// автора к 260).
    var stick = true

    // MARK: - Лист в своё гнездо (P883)

    /// Лист закрывают в карточку — он складывается, а не прячется.
    var folding = false
    /// Рамка его карточки на экране раздела — куда сложиться. Пока её нет,
    /// лист стоит, где его отпустили.
    @Published var foldTo: CGRect?
    /// Где на экране карточки ленты (только видимые) — по ним лента
    /// возвращается туда, где была до открытия дня (P893).
    var frames: [String: CGRect] = [:]
    /// С какой карточки открыли день и где она стояла.
    var openedFrom: (id: String, top: CGFloat)?

    /// Замер рамки карточки ленты (`frame` — пусто: карточку разобрала
    /// ленивая стопка). В проверке с медленной лентой доходит позже, с
    /// поправкой на то, сколько лента прошла с мига замера (P921).
    /// Замер несёт метку (P923): сколько раз лента к мигу замера двигала
    /// себя сама. Снятый до последнего сдвига решений не принимает — по
    /// таким лента прежде поправляла себя дважды и уезжала мимо.
    func saw(_ id: String, _ frame: CGRect?) {
        let at = box.view?.contentOffset.y ?? 0
        let mark = moves
        Slow.late(Slow.card) { [weak self] in
            guard let self else { return }
            var frame = frame
            if Slow.on, let was = frame, let now = self.box.view?.contentOffset.y {
                frame = was.offsetBy(dx: 0, dy: at - now)
            }
            self.frames[id] = frame
            guard frame != nil, id == self.seatWant?.id, mark == self.moves else { return }
            self.seatIdle = 0
            // Не из самого замера: сдвиг ленты меняет то, что сейчас мерится.
            DispatchQueue.main.async { [weak self] in self?.seatStep() }
        }
    }

    /// Какие карточки есть в ленте (ставит картотека при каждой сборке).
    var ids: Set<String> = []

    /// Лист «Сегодня» — не выше своего места у края (P893): закрытая
    /// карточка рядом с сегодня, и лента вставала так, что лист торчал на
    /// полэкрана. Сдвигает ленту, только если место дня собрано.
    func keepToday(_ side: Int) {
        guard let scroll = box.view, seen, known, height > 0 else { return }
        let raw = slotTop - scroll.contentOffset.y
        var step: CGFloat = 0
        if side > 0, raw < restY(1, stick: true) { step = raw - restY(1, stick: true) }
        if side < 0, raw > restY(-1, stick: true) { step = raw - restY(-1, stick: true) }
        let most = max(0, scroll.contentSize.height - scroll.bounds.height)
        step = min(most, max(0, scroll.contentOffset.y + step)) - scroll.contentOffset.y
        guard abs(step) > 0.5 else { return }
        Trace.note(String(format: "лента: «Сегодня» на своё место — сдвиг %.0f", step))
        nudge(by: step)
    }

    // MARK: - Наведение на карточку (P923)

    /// Перейти к карточке: верхом на столько от верха экрана. Ставит
    /// картотека — у неё ключ к прокрутке.
    var jump: ((String, CGFloat) -> Void)?

    private struct Seat {
        let id: String
        let top: CGFloat
        /// Сколько ещё раз можно перейти или поправить.
        var tries: Int
        /// Сколько кадров подряд карточка стоит на месте; пусто — не стоит.
        var calm: Int?
        let then: (CGRect?) -> Void
    }
    private var seatWant: Seat?
    private var seatLink: CADisplayLink?
    /// Кадров без свежего замера карточки.
    private var seatIdle = 0
    /// Сколько раз лента двигала себя сама — метка замеров.
    private var moves = 0

    /// Рост карточки, пока её рамка не замерена.
    static var cardHeight: CGFloat { Search.tabHeight + 8 + Search.body + Search.overlap + 6 }

    /// Где встать карточке закрываемого дня — верх её рамки от верха
    /// экрана: где стоит, если на виду («картотека открыта ровно там, где
    /// была», P893); иначе — где была, когда с неё открыли день; иначе — у
    /// края «Сегодня» (прошедшая — над корешком внизу, будущая — под
    /// полоской вверху).
    func nest(for id: String, side: Int) -> (top: CGFloat, inPlace: Bool) {
        let full = frames[id]?.height ?? Ribbon.cardHeight
        let low: CGFloat = side < 0 ? FollowRibbon.peekTop : 8
        let high = max(low, height - FollowRibbon.peekBottom - (full - Search.overlap))
        if let frame = frames[id], frame.minY >= low - 0.5, frame.minY <= high + 0.5 {
            return (frame.minY, true)
        }
        if let from = openedFrom, from.id == id { return (min(high, max(low, from.top)), false) }
        return (side > 0 ? high : low, false)
    }

    /// Навести ленту: карточка `id` — верхом на `top` от верха экрана.
    /// Без шагов по времени (P923, вместо `align` P894 с его повторами через
    /// 0,03 и 0,05 с): решение — по замеру самой карточки, снятому после
    /// последнего сдвига ленты; «встала» — когда замер совпал с местом и два
    /// кадра ничто его не оспорило. Карточки нет на экране — переход к ней,
    /// и ещё раз, если за восемь кадров она не появилась (ленивая стопка
    /// ставит дальнюю карточку не с первого раза, P906). `then` получает
    /// рамку карточки или пусто, если её так и не нашлось.
    func seat(_ id: String, top: CGFloat, then: @escaping (CGRect?) -> Void) {
        unseat()
        seatWant = Seat(id: id, top: top, tries: 6, calm: nil, then: then)
        seatIdle = 0
        let made = CADisplayLink(target: self, selector: #selector(seatTick))
        made.add(to: .main, forMode: .common)
        seatLink = made
        seatStep()
    }

    /// Наведение больше не нужно.
    func unseat() {
        seatLink?.invalidate()
        seatLink = nil
        seatWant = nil
    }

    /// Тягу не сегодняшнего листа начали (P923): лента под ним невидима и
    /// листом не движется — заранее встаёт на его карточку, чтобы к порогу
    /// картотека была готова.
    func aim(_ id: String, side: Int) {
        guard ids.contains(id), seatWant?.id != id else { return }
        let spot = nest(for: id, side: side)
        guard !spot.inPlace else { return }
        seat(id, top: spot.top) { [weak self] frame in
            if frame != nil { self?.keepToday(side) }
        }
    }

    @objc private func seatTick() {
        guard var want = seatWant else {
            unseat()
            return
        }
        if let calm = want.calm {
            if calm >= 1 {
                seated(frames[want.id])
            } else {
                want.calm = calm + 1
                seatWant = want
            }
            return
        }
        seatIdle += 1
        if seatIdle >= 8 {
            seatIdle = 0
            seatStep()
        }
    }

    private func seatStep() {
        guard var want = seatWant, let scroll = box.view else { return }
        guard let frame = frames[want.id] else {
            want.calm = nil
            guard want.tries > 0 else {
                seatWant = want
                seated(nil)
                return
            }
            want.tries -= 1
            seatWant = want
            Trace.note("лента: карточки \(want.id) нет на экране — переход")
            jump?(want.id, want.top)
            return
        }
        let miss = frame.minY - want.top
        let most = max(0, scroll.contentSize.height - scroll.bounds.height)
        let step = min(most, max(0, scroll.contentOffset.y + miss)) - scroll.contentOffset.y
        // На месте — или дальше ленте ехать некуда.
        if abs(miss) <= 0.5 || abs(step) <= 0.5 || want.tries <= 0 {
            if want.calm == nil {
                want.calm = 0
                seatWant = want
            }
            return
        }
        want.tries -= 1
        want.calm = nil
        seatWant = want
        Trace.note(String(format: "лента: карточка %@ мимо места на %.0f — поправка", want.id, miss))
        nudge(by: step)
    }

    private func seated(_ frame: CGRect?) {
        guard let want = seatWant else { return }
        unseat()
        want.then(frame)
    }

    /// Лента двигает себя сама: известные рамки карточек едут вместе с ней,
    /// а метка замеров растёт — снятые до сдвига больше ничего не решают.
    private func nudge(by step: CGFloat) {
        guard let scroll = box.view else { return }
        moves += 1
        fixing = true
        scroll.contentOffset.y += step
        fixing = false
        for (id, frame) in frames { frames[id] = frame.offsetBy(dx: 0, dy: -step) }
    }

    /// Места дня в ленте нет — с какой оно стороны (P899): 1 — ниже экрана
    /// (картотека прошлого), −1 — выше (будущего), 0 — место собрано, верим
    /// замеру. Прежде лист «Сегодня» вставал по старому замеру посреди
    /// картотеки прошлого и «прилипал» (автор по 279).
    private var farSide = 0

    // MARK: - Не сегодняшний лист несут рукой (P923)

    /// Тягу не сегодняшнего листа начали: лист идёт прямо за пальцем, а
    /// лента под ним стоит. Прежде и он ехал через прокрутку ленты — та
    /// пересобиралась вокруг его дня и пересобиралась обратно, когда он
    /// закрывался; отсюда пустой экран и мелькание (`docs/71` §8).
    func lift() {
        interrupt()
        driving = false
        frozen = true
        if y != 0 { y = 0 }
    }

    /// Лист несут: его верх — на `amount` от своего места.
    func carry(_ amount: CGFloat) {
        guard frozen else { return }
        if abs(amount - y) > 0.25 || amount == 0 { y = amount }
    }

    /// Лист «Сегодня» берут с его места у края (P926): дальше он идёт сам,
    /// лента под ним стоит. Отвечает, где лист стоял: 1 — корешком внизу,
    /// −1 — полоской вверху.
    func hold(_ dir: Int) -> CGFloat {
        interrupt()
        driving = false
        frozen = true
        let from = dir > 0 ? height - FollowRibbon.peekBottom : restY(-1, stick: true)
        y = from
        return from
    }

    /// Ход схемы карточки к гнезду и ступени её посадки (P926).
    let flight = Glide()
    /// Ход листа, который несут: назад на место или «Сегодня» с края.
    let lifting = Glide()
    /// Ход листа «Сегодня» поверх открытого дня (P924, P926).
    let rise = RiseMove()

    /// Лента уже не «только что открыта» (P898): закрытая карточка села, и
    /// перечитанная опись больше не ставит ленту в покой у дня. Прежде,
    /// если опись догоняла в первые полторы секунды (после карты — почти
    /// всегда), лента сама уезжала к вчера (автор по 279: «будущее → карта
    /// → убрал лист — прошлая картотека»).
    func settledHere() { openedAt = 0 }

    /// Схема долетела до гнезда — дальше садится сама карточка (P895).
    @Published var foldLanded = false
    /// Посадка закрытой карточки в своё гнездо (P895).
    let landing = Landing()

    /// Последняя прокрутка, которую видели (для следа, P894).
    private var lastSeen: CGFloat = 0

    /// Доля пройденного архива. Прошлое — от покоя «вчера над нижней
    /// строкой» до самого верха ленты; будущее — от покоя «завтра у верха»
    /// до самого низа.
    private func measureReach(_ scroll: UIScrollView) {
        let offset = scroll.contentOffset.y
        let most = max(0, scroll.contentSize.height - scroll.bounds.height)
        let pastRest = slotTop - height
        let futureRest = slotTop + height
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
    func restY(_ dir: Int, stick: Bool? = nil) -> CGFloat {
        // Будущее (P797): завтрашняя — у самого верха, день — над ним, за
        // верхним краем; строка поиска теперь внизу.
        // В прошлом лист «Сегодня» стоит корешком внизу (P860): вчерашняя
        // карточка встаёт над ним и уходит под него, как под следующую. В
        // будущем у верха остаётся низ листа с именем, датой и днём недели
        // (P896, вместо кольца P876): завтрашняя карточка — сразу под ним,
        // дальние уходят под него.
        guard stick ?? self.stick else { return dir > 0 ? height : -height }
        return dir > 0 ? height - FollowRibbon.peekBottom + Search.overlap
            : FollowRibbon.peekTop - height
    }

    /// Ленту сейчас ведёт программа.
    var busy: Bool { driving }

    /// Замер места дня лентой: узнаём, где оно в содержимом.
    func measured(_ value: CGFloat) {
        guard let scroll = box.view else { return }
        watchScroll(scroll)
        // Место в содержимом ленты — по прокрутке в миг замера: в проверке
        // с медленной лентой замер доходит позже (P921).
        let top = value + scroll.contentOffset.y
        Slow.late(Slow.slot) { [weak self] in self?.took(top) }
    }

    private func took(_ top: CGFloat) {
        guard let scroll = box.view else { return }
        // Пока ведёт программа, содержимое не меняется, а замер может
        // отставать на кадр от прокрутки — не верим ему.
        guard !driving else { return }
        slotTop = top
        known = true
        farSide = 0
        // Замер пришёл — значит, место собрано (P894): отметку «собрано»
        // иногда снимал уход прежнего места при пересборке ленты уже после
        // появления нового, и тяга листа отказывала (автор по 278: «после
        // пометок не закрыть свайпом»).
        seen = true
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
        // Для проверок движения: лента сдвинулась сама — без пальца, без
        // разгона и не своим ходом (P894).
        let moved = scroll.contentOffset.y - lastSeen
        lastSeen = scroll.contentOffset.y
        if abs(moved) > 20, !scroll.isTracking, !scroll.isDecelerating, !driving {
            Trace.note(String(format: "лента: сама на %.0f (стена %@)", moved, walls() ? "да" : "нет"))
        }
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
            if inside, anchor == nil {
                anchor = t
                // Дошли до листа «Сегодня» — лёгкий щелчок (P891); на пороге —
                // толчок, как прежде.
                Feel.tick()
            }
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
                    // За стеной — тугой ход, как у листа (P891, автор:
                    // «стандартное сопротивление»; отменяет ход вровень с
                    // пальцем P890).
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
            Trace.note(String(format: "лента: без пальца к стене — день %.0f стена %.0f", raw, wall))
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
        // Место дня не замерено после пересборки — лист у своего края
        // (P899), а не по старому замеру.
        let now = (!known || !seen) && farSide != 0 ? CGFloat(farSide) * (2 * height + 1) : slotTop - offset
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
    /// Сколько мест дня сейчас собрано в ленте (P913). Лента пересобирается
    /// вокруг другого дня — новое место появляется раньше, чем уходит
    /// прежнее; прежде уход прежнего снимал отметку «место собрано» уже
    /// после появления нового, и тяга листа отказывала до следующего
    /// замера (автор по 286: «открыл завтрашний день из картотеки будущего —
    /// лист не закрывается свайпом»; та же беда — замечание 91).
    private var slots = 0

    func appeared() {
        Slow.late(Slow.slot) { [weak self] in
            guard let self else { return }
            self.slots += 1
            self.seen = true
        }
    }

    func lost() {
        Slow.late(Slow.slot) { [weak self] in self?.gone() }
    }

    private func gone() {
        slots = max(0, slots - 1)
        guard slots == 0 else { return }
        seen = false
        // Места дня в ленте сейчас нет — лист у своего края, а не там, где
        // его место видели в последний раз (P906). С какой стороны — по
        // последнему замеру места и нынешней прокрутке (P923): лента всегда
        // собрана вокруг сегодня, место дня в ней не переезжает. Прежние
        // подсказки «с какой стороны сегодня» (P906, P907) убраны.
        if farSide == 0 {
            let offset = box.view?.contentOffset.y ?? 0
            farSide = (known ? slotTop - offset : y) >= 0 ? 1 : -1
        }
        if let scroll = box.view { follow(scroll.contentOffset.y) }
    }

    /// Начало тяги из дня: место дня должно быть собрано и измерено. Если
    /// нет — ставим его и ждём следующего движения пальца.
    func begin() -> Bool {
        guard box.view != nil, seen else {
            Trace.note("тяга: место дня не собрано — ставим (\(box.view != nil ? "лента есть" : "ленты нет"))")
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

    /// День — заново по месту в ленте (P878): после замороженного хода.
    func refresh() {
        guard let scroll = box.view else { return }
        follow(scroll.contentOffset.y)
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

    /// Погасить разгон пальца (P892, автор: «хорошая функция»): картотека
    /// открылась, а палец ещё ведёт — прежде лента подхватывала остаток
    /// движения с разгоном и уезжала на недели вперёд (след проверки: до
    /// декабря). Текущее касание ленты обрывается, ход по инерции — тоже;
    /// листать дальше — новым движением.
    func quench() {
        guard let scroll = box.view else { return }
        scroll.setContentOffset(scroll.contentOffset, animated: false)
        let pan = scroll.panGestureRecognizer
        if pan.state == .began || pan.state == .changed {
            pan.isEnabled = false
            pan.isEnabled = true
        }
    }

    /// Лента — в чистое состояние (P888): открыли день с карточки. Прежде
    /// после складывания лента иногда оставалась «замороженной» или в ходу,
    /// и открытую карточку было не закрыть ни вверх, ни вниз (видео автора).
    func reset() {
        stop()
        driving = false
        frozen = false
        folding = false
        foldTo = nil
        foldLanded = false
        landing.clear()
        foldSide = 0
        veiled = false
        done = nil
        unseat()
        flight.stop()
    }

    /// Лента скрыта, пока пересобирается вокруг другого дня (P888: после
    /// «Дневника» на глазах мелькали 1994 год и прошлое).
    @Published var veiled = false

    /// Тяга кончилась или ход прерван: замеры снова ведут день.
    func release() {
        guard link == nil else { return }
        driving = false
    }
}

/// Ход по кадрам экрана (P926): от нуля до единицы за заданное время,
/// плавно в начале и в конце; последний шаг — ровно единица, и только за
/// ним — «кончил». Схема карточки и лист «Сегодня» едут им, а не ходом
/// SwiftUI с ответом «ход окончен»: на телефоне тот ответ приходил, когда
/// схема была ещё в пути, и карточка появлялась раньше неё — прыжок в
/// конце посадки (видео автора к 291). По следу автора ответ приходил
/// вовремя по часам, а на экране ход начинался позже: в миг закрытия экран
/// замирал на 0,15–0,2 с, пока проступала картотека. Поэтому время здесь
/// считается по показанным кадрам: замерший кадр хода не съедает, после
/// замирания схема продолжает с того же места, а не перескакивает.
final class Glide {
    private var link: CADisplayLink?
    /// Сколько хода уже показано и когда был прошлый кадр.
    private var shown: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var length: CFTimeInterval = 0.3
    private var step: ((CGFloat) -> Void)?
    private var done: (() -> Void)?

    var running: Bool { link != nil }

    func run(_ length: CFTimeInterval, step: ((CGFloat) -> Void)? = nil,
             then: @escaping () -> Void) {
        stop()
        self.length = max(0.01, length)
        self.step = step
        done = then
        shown = 0
        last = 0
        let made = CADisplayLink(target: self, selector: #selector(tick))
        made.add(to: .main, forMode: .common)
        link = made
    }

    func stop() {
        link?.invalidate()
        link = nil
        step = nil
        done = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        // За один кадр — не больше двух обычных: замирание хода не съедает.
        if last > 0 { shown += min(1.0 / 30, now - last) }
        last = now
        let t = CGFloat(min(1, shown / length))
        step?(t * t * (3 - 2 * t))
        guard t >= 1 else { return }
        let then = done
        stop()
        then?()
    }
}

/// Насколько лист «Сегодня» лёг поверх открытого дня: от нуля до единицы.
/// Смотрит на него только сам этот лист — экран целиком не перерисовывается.
final class RiseMove: ObservableObject {
    @Published var p: CGFloat = 0
    let glide = Glide()
}

/// Посадка закрытой карточки (P895, автор по видео к 278: «совсем не
/// похоже на физическое действие: карточка дёргается и не вставляется в
/// своё место, а растворяется, наложенная на настоящую»). Пока схема
/// летит, гнездо пустует (`away`); над гнездом схема становится самой
/// карточкой (`hover`), та опускается в ряд под следующую (`down`), и на
/// ней проступает надпись (`done`).
final class Landing: ObservableObject {
    enum Stage { case none, away, hover, down, done }
    @Published var id: String?
    @Published var stage: Stage = .none
    /// Насколько над гнездом карточка ждёт, прежде чем опуститься: выше
    /// нахлёста — следующая карточка её ещё не закрывает.
    static let lift: CGFloat = Search.overlap + 4

    /// Номер посадки (P923): шаги прежней, прерванной посадки по нему
    /// узнают, что они уже не к месту.
    private(set) var run = 0
    /// Досадить разом — человек не стал ждать (нажал «Сегодня» или
    /// «Дневник», пока карточка садится).
    var hurry: (() -> Void)?

    func begin() -> Int {
        run += 1
        return run
    }

    func clear() {
        run += 1
        hurry = nil
        if id != nil { id = nil }
        if stage != .none { stage = .none }
    }
}

/// День едет за своим местом в ленте (P777). Смотрит только на ленту:
/// при её прокрутке пересчитывается один сдвиг, а не весь экран.
/// Лист «Сегодня» с экрана не уходит (P860, автор по 259): внизу остаётся
/// корешок с именем дня и датой, вверху — низ листа с тем же именем, датой
/// и днём недели (P896, вместо кольца P876). Касание или тяга — в день.
struct FollowRibbon: ViewModifier {
    @ObservedObject var ribbon: Ribbon
    let live: Bool

    func body(content: Content) -> some View {
        let y = live ? ribbon.y : 0
        content
            .offset(y: FollowRibbon.shown(y, height: ribbon.height, stick: ribbon.stick))
            // Лист всегда поверх картотеки (P860, вместо ухода под неё за
            // верхней четвертью P831): карточки будущего выходят из-под его
            // низа, а он остаётся у верха.
            .zIndex(1)
    }

    /// Сколько листа видно внизу: корешок с именем дня и датой (P860).
    static var peekBottom: CGFloat { DayPage.folder.tabHeight + 4 }
    /// Сколько низа листа видно вверху (P896; крупнее прежних 44 точек P860):
    /// помещаются «Сегодня», дата и день недели.
    static let peekTop: CGFloat = 56
    /// Где начинается лист будущего дня (P896): на 8 точек под низом листа
    /// «Сегодня» — заходит под него, как карточки.
    static let futureTop: CGFloat = peekTop - 8

    /// Верх листа «Сегодня», когда он стоит у верха экрана: видна полоска
    /// его низа (P860, P896).
    static func topClamp(_ height: CGFloat) -> CGFloat {
        peekTop - height - DayPage.under
    }

    /// Где лист «Дня», когда его место в ленте на `y`. Вниз (прошлое) —
    /// вместе с местом, пока над нижним краем не останется один корешок
    /// (P860). Вверх (будущее): лист чуть обгоняет место — завтрашняя
    /// карточка выходит из-под него (P831), — пока у верха не останется
    /// полоска его низа (P896, вместо ухода за верх по кольцу P876).
    /// Не сегодняшний лист (`stick` — нет) у края не останавливается (P863).
    static func shown(_ y: CGFloat, height: CGFloat, stick: Bool = true) -> CGFloat {
        guard height > 0 else { return y }
        if y >= 0 { return stick ? min(y, height - peekBottom) : y }
        let swap = -0.75 * height
        let ahead = y >= swap ? y - Search.overlap * (y / swap) : y - Search.overlap
        guard stick else { return ahead }
        // Лист длиннее вниз на поле под надпись «Сегодня» (P907) — и на
        // столько же должен уйти выше, чтобы у верха осталась только эта
        // полоска (P912; в 285 лист торчал на сто точек, показывал шаги и
        // закрывал завтрашнюю карточку). Добавка набирается по ходу листа.
        let rest = peekTop - height
        let extra = (DayPage.under - 20) * min(1, max(0, y / rest))
        return max(ahead - extra, topClamp(height))
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
