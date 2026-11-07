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
    private var done: (() -> Void)?

    /// Когда ленту открыли — первые полторы секунды она ещё встаёт в покой,
    /// пока догоняют высота экрана и опись.
    private var openedAt: CFTimeInterval = 0
    func opened() { openedAt = CACurrentMediaTime() }
    var fresh: Bool { CACurrentMediaTime() - openedAt < 1.5 }

    /// Где место дня стоит в покое: 1 — прошлое (вчера над нижней строкой,
    /// день за нижним краем), -1 — будущее (завтра под строкой поиска).
    func restY(_ dir: Int) -> CGFloat {
        dir > 0 ? height : Search.fieldHeight + Search.restTop - height
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
        follow(scroll.contentOffset.y)
    }

    /// Следить за прокруткой ленты: каждый её сдвиг — сразу сдвиг дня.
    private func watchScroll(_ scroll: UIScrollView) {
        guard watched !== scroll else { return }
        watched = scroll
        watch = scroll.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
            self?.follow(view.contentOffset.y)
        }
    }

    private func follow(_ offset: CGFloat) {
        let now = slotTop - offset
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
    func glide(to target: CGFloat, duration: CFTimeInterval = 0.3,
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
        length = duration
        done = then
        let made = CADisplayLink(target: self, selector: #selector(tick))
        made.add(to: .main, forMode: .common)
        link = made
    }

    @objc private func tick() {
        guard let scroll = box.view else { finish(); return }
        let p = min(1, (CACurrentMediaTime() - startTime) / length)
        // Мягкий конец хода, без отскока.
        let e = 1 - pow(1 - p, 3)
        scroll.contentOffset.y = startOffset + shift * e
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
        content.offset(y: live ? ribbon.y : 0)
    }
}

/// Ленту отпустили, и место дня видно больше чем наполовину — она сама
/// доезжает до дня, и день снова живой (P777). Ход прокрутки знает только
/// iOS 18; на iOS 17 в день возвращает касание по нему или «День» внизу.
struct SnapToDay: ViewModifier {
    let shell: Shell

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                let ribbon = shell.ribbon
                guard phase == .idle, shell.screen == .search, shell.ribbonOpen,
                      !shell.pulling, !ribbon.busy, ribbon.seen,
                      abs(ribbon.y) < ribbon.height * 0.5 else { return }
                shell.screen = .today
            }
        } else {
            content
        }
    }
}
