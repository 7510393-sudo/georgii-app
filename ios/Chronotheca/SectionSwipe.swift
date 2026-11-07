import SwiftUI
import UIKit

/// Свайп между разделами (P778): «Календарь», «День», «Карта» лежат в ряд,
/// как в нижней строке, и по кругу (P779): за картой снова календарь, перед
/// календарём — карта. Палец ведут вбок — открытый раздел уезжает, соседний
/// выезжает за ним вплотную; отпустили за порогом — соседний доезжает, толчок
/// в руку (P780); не дотянули — оба мягко возвращаются. Вместо перелистывания дня
/// пальцем (P532, P540, P550 — отменены): дни меняют стрелки ‹ › у страницы
/// и карточки картотеки. Из открытой картотеки — так же, как из «Дня».
///
/// Сдвиг живёт здесь, а не в оболочке: на каждый кадр перерисовываются
/// только две едущие плашки, а не весь экран (как у ленты, P777).
final class SectionSlide: ObservableObject {

    /// Разделы слева направо — как в нижней строке (P773).
    static let order: [Shell.Screen] = [.calendar, .today, .map]

    /// Сдвиг вбок в точках: минус — палец ушёл влево и выезжает раздел
    /// справа, плюс — вправо, выезжает раздел слева.
    @Published private(set) var x: CGFloat = 0
    /// Палец ведёт разделы.
    @Published private(set) var active = false
    /// Откуда уезжают.
    @Published private(set) var from: Shell.Screen = .today
    /// Кто выезжает сбоку; пусто — соседа с этой стороны нет (оттяжка).
    @Published private(set) var target: Shell.Screen?

    /// Ширина экрана — на неё уезжает раздел.
    private(set) var width: CGFloat = 390
    /// Доезжает своим ходом — второго свайпа не начинать.
    private(set) var settling = false

    /// Где раздел в ряду; открытая картотека — на месте «Дня».
    private static func place(_ screen: Shell.Screen) -> Int? {
        order.firstIndex(of: screen == .search ? .today : screen)
    }

    /// Сосед раздела по кругу (P779): 1 — справа, -1 — слева.
    static func neighbour(of screen: Shell.Screen, _ side: Int) -> Shell.Screen? {
        guard let i = place(screen) else { return nil }
        return order[(i + side + order.count) % order.count]
    }

    /// С какой стороны выезжает сосед: 1 — справа, -1 — слева.
    private var side = 1

    func begin(from screen: Shell.Screen, width: CGFloat) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            self.width = max(1, width)
            from = screen
            target = nil
            x = 0
            active = true
        }
    }

    /// Палец сдвинулся на `dx` от начала.
    func move(_ dx: CGFloat) {
        guard active, !settling else { return }
        // Палец влево — едет сосед справа.
        side = dx < 0 ? 1 : -1
        let next = dx == 0 ? nil : Self.neighbour(of: from, side)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            if target != next { target = next }
            x = dx
        }
    }

    /// Где плашка раздела по горизонтали; `nil` — стоит, как стояла.
    func offset(for screen: Shell.Screen) -> CGFloat? {
        guard active else { return nil }
        // Из картотеки уезжают и лента, и день, стоящий в ней.
        if screen == from || (from == .search && screen == .today) { return x }
        if let target, screen == target { return x + CGFloat(side) * width }
        return nil
    }

    /// Отпустили. `speed` — скорость пальца по горизонтали. Возвращает раздел,
    /// куда доедут, или `nil` — всё вернётся на место.
    func end(speed: CGFloat, arrived: @escaping (Shell.Screen) -> Void) {
        guard active, !settling else { return }
        let far = abs(x) > width * 0.2
        let flung = abs(speed) > 500 && abs(x) > 30 && (speed < 0) == (x < 0)
        settling = true
        let ease = Animation.spring(response: 0.3, dampingFraction: 0.9)
        if let target, far || flung {
            // Толчок — тот же, что при касании раздела внизу (P780; прежде
            // «тик» P767, его в руке почти не слышно). Звука нет.
            Feel.thud()
            withAnimation(ease, completionCriteria: .logicallyComplete) {
                x = x < 0 ? -width : width
            } completion: { [weak self] in
                arrived(target)
                self?.finish()
            }
        } else {
            withAnimation(ease, completionCriteria: .logicallyComplete) {
                x = 0
            } completion: { [weak self] in
                self?.finish()
            }
        }
    }

    /// Свайп сорвался (пришёл звонок, палец ушёл в систему) — всё на место.
    func cancel() {
        guard active, !settling else { return }
        settling = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9), completionCriteria: .logicallyComplete) {
            x = 0
        } completion: { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            active = false
            target = nil
            x = 0
        }
        settling = false
    }
}

/// Плашка раздела едет вбок за пальцем (P778); едущие две — поверх прочих.
struct FollowSlide: ViewModifier {
    @ObservedObject var slide: SectionSlide
    let which: Shell.Screen
    /// Плашка лежит на экране (в стопке).
    let down: Bool
    /// Куда она уходит по вертикали, когда её нет.
    let away: CGFloat
    /// Её место в стопке.
    let z: Double

    func body(content: Content) -> some View {
        let dx = slide.offset(for: which)
        // Выезжающий сбоку раздел стоит на месте по вертикали, даже если
        // его плашки ещё нет в стопке.
        let shown = down || dx != nil
        content
            .offset(x: dx ?? 0, y: shown ? 0 : away)
            .zIndex(dx != nil ? (which == slide.target ? 101 : 100) : z)
    }
}

/// Распознаватель свайпа: один на окно, рядом со всеми прочими — касаний
/// не задерживает. Начинается только быстрым движением вбок сразу после
/// касания: то, что берут удержанием (дело, снимок, курсор, выделение), он
/// не перехватывает.
final class SectionSwipe: NSObject, UIGestureRecognizerDelegate {

    static let shared = SectionSwipe()
    /// На карте свайп начинают у края — полоса около 7 мм (P767), у обоих
    /// краёв (P779).
    static let mapEdge: CGFloat = 40

    /// Можно ли начать отсюда: точка в окне, куда идёт палец (1 — вправо)
    /// и ширина окна.
    var allowed: ((CGPoint, Int, CGFloat) -> Bool)?
    /// Свайп начался, едет, кончился.
    var began: ((CGFloat) -> Void)?
    var moved: ((CGFloat) -> Void)?
    var ended: ((CGFloat) -> Void)?
    var cancelled: (() -> Void)?

    private weak var pan: UIPanGestureRecognizer?
    /// Когда лёг палец и на что.
    private var touchDown: CFTimeInterval = 0
    private weak var touched: UIView?

    /// Повесить на окно приложения. Повторный вызов ничего не меняет.
    func install() {
        guard pan == nil else { return }
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else {
            // Окно ещё не готово — чуть позже.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.install() }
            return
        }
        let g = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        g.delegate = self
        g.maximumNumberOfTouches = 1
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        window.addGestureRecognizer(g)
        pan = g
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Поверх приложения листок или вопрос — свайп не для них.
        if let root = g.view?.window?.rootViewController, root.presentedViewController != nil {
            return false
        }
        touchDown = CACurrentMediaTime()
        touched = touch.view
        return true
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let speed = pan.velocity(in: view)
        let way = pan.translation(in: view)
        let dx = abs(way.x) > 0 ? way.x : speed.x
        let dy = abs(way.y) > 0 ? way.y : speed.y
        // Вбок, а не вверх-вниз.
        guard abs(dx) > abs(dy) * 1.2 else { return false }
        // Сразу после касания: удержанием берут дело, снимок и курсор.
        guard CACurrentMediaTime() - touchDown < Cross.hold else { return false }
        // Выделен текст — палец, скорее всего, тянет ручку выделения.
        guard !Self.selecting else { return false }
        let start = CGPoint(x: pan.location(in: view).x - way.x, y: pan.location(in: view).y - way.y)
        return allowed?(start, dx > 0 ? 1 : -1, view.bounds.width) ?? false
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        switch pan.state {
        case .began:
            // Свайп взят — прокрутка или карта под пальцем больше не едут.
            stopOthers()
            began?(view.bounds.width)
            moved?(pan.translation(in: view).x)
        case .changed:
            moved?(pan.translation(in: view).x)
        case .ended:
            ended?(pan.velocity(in: view).x)
        default:
            cancelled?()
        }
    }

    /// Прочие тяги под пальцем (прокрутка листа, карта) отпустить: иначе
    /// лист чуть ехал бы вверх-вниз вместе с разделом.
    private func stopOthers() {
        var v = touched
        while let view = v {
            for g in view.gestureRecognizers ?? [] where g !== pan && g is UIPanGestureRecognizer {
                if g.state == .began || g.state == .changed {
                    g.isEnabled = false
                    g.isEnabled = true
                }
            }
            v = view.superview
        }
    }

    /// Выделен ли текст в поле, где пишут (прежде — у привратника листания,
    /// P679).
    static var selecting: Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows {
                if let text = firstResponderText(in: window), text.selectedRange.length > 0 { return true }
            }
        }
        return false
    }

    private static func firstResponderText(in view: UIView) -> UITextView? {
        if let text = view as? UITextView, text.isFirstResponder { return text }
        for sub in view.subviews { if let found = firstResponderText(in: sub) { return found } }
        return nil
    }
}

/// Лента картотеки уезжает вбок вместе с днём, стоящим в ней (P779).
struct SlideAlong: ViewModifier {
    @ObservedObject var slide: SectionSlide

    func body(content: Content) -> some View {
        content.offset(x: slide.active && slide.from == .search ? slide.x : 0)
    }
}
