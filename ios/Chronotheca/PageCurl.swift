import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Дорога домой: один поворот на всё расстояние.
///
/// Раньше дорога делилась на несколько поворотов, и они шли друг за другом:
/// система переворачивает по одному листу и ждёт, пока он ляжет. Человеку
/// оставалось смотреть, как они мелькают, и ждать, пока это кончится.
///
/// Поворот один (P178). Издалека дорогу показывает вихрь листов (P266) —
/// весь, без настоящего поворота напоследок: тот шёл отдельным, заметно
/// более медленным шагом уже после вихря, и дорога распадалась на два
/// разных движения вместо одного (P314). Толщину пачки поэтому теперь
/// не рисуем: число летящих листов и так видно.
func wayHome(_ distance: Int) -> [Int] {
    distance == 0 ? [] : [distance]
}

/// Сколько листов пролетает по дороге домой — вихрем, почти разом, а не
/// по одному (P266). Соседний день — один лист, дальше — от двух до пяти:
/// чем дальше ушли, тем больше.
func whirlLeaves(_ distance: Int) -> Int {
    switch abs(distance) {
    case 0:        return 0
    case 1:        return 1
    case 2:        return 2
    case 3...6:    return 3
    case 7...30:   return 4
    default:       return 5
    }
}

/// Перелистывание страницы, как в бумажной книге.
///
/// Тот же механизм, что в «Книгах» Apple: страница поднимается за пальцем,
/// загибается и ложится на соседнюю. Своими силами такое не нарисовать, да и
/// не нужно — система умеет это сама, и умеет правильно.
///
/// Содержимое задаётся смещением: 0 — нынешняя страница, −1 и +1 — соседние.
/// Перелистнув, человек оказывается на соседней, и она становится нулевой.
struct PageCurl<Content: View>: UIViewControllerRepresentable {

    let content: (Int) -> Content
    let onTurn: (Int) -> Void

    /// Просьба перелистнуть самому: очередь шагов, по одному на поворот.
    ///
    /// Нужна кнопке «Сегодня» — возвращаясь с далёкого дня, человек должен
    /// увидеть дорогу назад, а не оказаться на месте мгновенно. Шаг может
    /// быть любой длины: поворот открывает сразу нужный день, а не соседний,
    /// поэтому дальняя дорога проходится за два-три поворота, а не за
    /// двадцать (решение P164).
    ///
    /// Очередь убывает после каждого поворота — и следующий поворот
    /// собирается уже по свежим данным, а не по тем, что были в начале.
    var plan: Binding<[Int]> = .constant([])

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pages = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        pages.dataSource = context.coordinator
        pages.delegate = context.coordinator
        pages.isDoubleSided = false
        pages.view.backgroundColor = UIColor(Look.chrome)
        pages.setViewControllers([context.coordinator.make(0)],
                                 direction: .forward, animated: false)

        // Страница переворачивается движением, а не касанием. Система сама
        // вешает на края экрана касания, которые листают: человек тыкает в
        // край — и день меняется без его намерения. Это нарушение главного
        // правила (P113), поэтому касания снимаем, тяга остаётся.
        for gesture in pages.gestureRecognizers where gesture is UITapGestureRecognizer {
            gesture.isEnabled = false
        }
        // Лист берут за край (P532): тяга, начатая посреди страницы, —
        // это курсор или выделение, а не листание. Привратник отпускает
        // тягу системы, только если палец лёг у левого или правого края.
        let gate = EdgeGate.make()
        pages.view.addGestureRecognizer(gate)
        for gesture in pages.gestureRecognizers where gesture is UIPanGestureRecognizer {
            gesture.require(toFail: gate)
        }
        return pages
    }

    func updateUIViewController(_ pages: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(pages)
        context.coordinator.obey(pages)
    }

    final class Host: UIHostingController<Content> {
        var offset = 0
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
                             UIPageViewControllerDelegate {
        var parent: PageCurl

        /// Пока страница в воздухе, второго поворота не начинаем.
        private var busy = false

        init(_ parent: PageCurl) { self.parent = parent }

        /// Выполнить первый шаг очереди, если он есть.
        func obey(_ pages: UIPageViewController) {
            guard !busy, let step = parent.plan.wrappedValue.first, step != 0 else { return }
            busy = true
            // Подстраховка (P480): если ход почему-то не закончился, книга не
            // должна остаться запертой навсегда.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.busy else { return }
                self.busy = false
                self.parent.plan.wrappedValue = []
            }
            let leaves = whirlLeaves(step)
            // Издалека — весь путь одним потоком вихря, без выделенного
            // последнего листа: раньше он один ложился отдельным, заметно
            // более медленным поворотом уже после того, как вихрь кончился
            // (P314).
            // Вперёд по дням (из прошлого домой) издалека — вихрь листьев,
            // которые улетают и открывают сегодняшнюю страницу (P475). Назад
            // (из будущего домой) — столько же листов, но в обратную
            // сторону: они прилетают к корешку и ложатся на прежнюю
            // страницу сегодняшней (P485). Один настоящий поворот системы
            // давал одну страницу вместо вихря (замечание к 115).
            if leaves > 1, let page = pages.viewControllers?.first?.view {
                if step > 0 {
                    Coordinator.whirl(over: page, in: pages.view, leaves: leaves,
                                      begin: { [weak self] in self?.land(pages, step) })
                } else {
                    Coordinator.gather(over: page, in: pages.view, leaves: leaves,
                                       fresh: { [weak pages] in pages?.viewControllers?.first?.view },
                                       begin: { [weak self] in self?.land(pages, step) })
                }
            } else {
                turn(pages, step)
            }
        }

        /// Книга встаёт на нужный день — в начале вихря, под летящими
        /// листьями (P475, прежде в конце — P314): ничего не
        /// переворачивается отдельно, и резкой смены в конце нет.
        private func land(_ pages: UIPageViewController, _ step: Int) {
            let host = make(step)
            pages.setViewControllers([host], direction: step > 0 ? .forward : .reverse,
                                     animated: false) { [weak self] done in
                guard let self else { return }
                guard done else { self.parent.plan.wrappedValue = []; self.busy = false; return }
                host.offset = 0
                // Сперва очередь убывает, потом книга свободна: иначе между
                // двумя строками обновление экрана успевало начать тот же
                // шаг ещё раз (P480).
                if !self.parent.plan.wrappedValue.isEmpty {
                    self.parent.plan.wrappedValue.removeFirst()
                }
                self.busy = false
                self.parent.onTurn(step)
            }
        }

        /// Вихрь страниц: снимки листа один за другим, почти разом,
        /// поднимаются от корешка — или прилетают к нему, если идём назад.
        /// Каждый шелестит сам.
        static func whirl(over page: UIView, in host: UIView, leaves: Int,
                          begin: @escaping () -> Void) {
            let forward = true
            let done: () -> Void = {}
            var perspective = CATransform3DIdentity
            perspective.m34 = -1.0 / 1400
            let away = CATransform3DRotate(perspective, -.pi / 2 * 0.98, 0, 1, 0)
            var flying: [UIView] = []
            for _ in 0..<leaves {
                guard let leaf = page.snapshotView(afterScreenUpdates: false) else { continue }
                let frame = page.convert(page.bounds, to: host)
                leaf.frame = frame
                // Лист вращается вокруг корешка — левого края.
                leaf.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
                leaf.layer.position = CGPoint(x: frame.minX, y: frame.midY)
                leaf.layer.shadowColor = UIColor.black.cgColor
                leaf.layer.shadowOpacity = 0.2
                leaf.layer.shadowRadius = 8
                leaf.isUserInteractionEnabled = false
                leaf.layer.transform = forward ? perspective : away
                leaf.alpha = forward ? 1 : 0.4
                host.addSubview(leaf)
                flying.append(leaf)
            }
            // Книга встаёт на нужный день под листьями — они закрывают её,
            // пока не улетят; сама книга может добавить свои виды поверх —
            // листья выносим на самый верх. Это — на следующем такте, а не
            // прямо здесь (P480): `obey` вызывается изнутри обновления экрана,
            // и смена дня, запрошенная оттуда же, давала зависание —
            // очередь шагов не убывала, и вихрь начинался снова и снова.
            guard !flying.isEmpty else {
                DispatchQueue.main.async { begin() }
                return
            }
            DispatchQueue.main.async {
                begin()
                flying.forEach { host.bringSubviewToFront($0) }
            }
            let each = 0.30
            let gap = 0.075
            for (i, leaf) in flying.enumerated() {
                // Вперёд первым уходит верхний лист, назад — первым
                // прилетает нижний.
                let order = forward ? flying.count - 1 - i : i
                let start = Double(order) * gap
                UIView.animate(withDuration: each, delay: start, options: [.curveEaseIn]) {
                    leaf.layer.transform = forward ? away : perspective
                    leaf.alpha = forward ? 0.25 : 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                    // Тише (P313, P330); вперёд — чуть выше тоном, назад —
                    // чуть ниже (P330).
                    let tone = 0.9 + Float(order % 3) * 0.1 + (forward ? 0.04 : -0.04)
                    Sounds.flip(volume: 0.15, rate: tone)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                }
            }
            let total = each + gap * Double(flying.count - 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + total) {
                flying.forEach { $0.removeFromSuperview() }
                done()
            }
        }

        /// Вихрь в обратную сторону (P485): прежняя страница остаётся
        /// снимком, книга под ним встаёт на нужный день, а снимки новой
        /// страницы по одному прилетают к корешку и ложатся сверху. Когда
        /// последний лёг, снимки уходят — под ними та же страница, и
        /// резкой смены нет.
        static func gather(over page: UIView, in host: UIView, leaves: Int,
                           fresh: @escaping () -> UIView?,
                           begin: @escaping () -> Void) {
            let frame = page.convert(page.bounds, to: host)
            let cover = page.snapshotView(afterScreenUpdates: false)
            if let cover {
                cover.frame = frame
                cover.isUserInteractionEnabled = false
                host.addSubview(cover)
            }
            DispatchQueue.main.async {
                begin()
                if let cover { host.bringSubviewToFront(cover) }
                // Новой странице нужен такт, чтобы нарисоваться.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard let target = fresh() else { cover?.removeFromSuperview(); return }
                    var perspective = CATransform3DIdentity
                    perspective.m34 = -1.0 / 1400
                    let away = CATransform3DRotate(perspective, -.pi / 2 * 0.98, 0, 1, 0)
                    var flying: [UIView] = []
                    for _ in 0..<leaves {
                        guard let leaf = target.snapshotView(afterScreenUpdates: true) else { continue }
                        leaf.frame = frame
                        leaf.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
                        leaf.layer.position = CGPoint(x: frame.minX, y: frame.midY)
                        leaf.layer.shadowColor = UIColor.black.cgColor
                        leaf.layer.shadowOpacity = 0.2
                        leaf.layer.shadowRadius = 8
                        leaf.isUserInteractionEnabled = false
                        leaf.layer.transform = away
                        leaf.alpha = 0.4
                        host.addSubview(leaf)
                        flying.append(leaf)
                    }
                    guard !flying.isEmpty else { cover?.removeFromSuperview(); return }
                    if let cover { host.insertSubview(cover, belowSubview: flying[0]) }
                    let each = 0.30
                    let gap = 0.075
                    for (i, leaf) in flying.enumerated() {
                        let start = Double(i) * gap
                        UIView.animate(withDuration: each, delay: start, options: [.curveEaseOut]) {
                            leaf.layer.transform = perspective
                            leaf.alpha = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                            let tone = 0.9 + Float(i % 3) * 0.1 - 0.04
                            Sounds.flip(volume: 0.15, rate: tone)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                        }
                    }
                    let total = each + gap * Double(flying.count - 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.02) {
                        cover?.removeFromSuperview()
                        flying.forEach { $0.removeFromSuperview() }
                    }
                }
            }
        }

        /// Настоящий поворот — последний лист дороги.
        private func turn(_ pages: UIPageViewController, _ step: Int) {
            // Вперёд — чуть выше тоном, назад — чуть ниже (P330).
            Sounds.flip(rate: step > 0 ? 1.04 : 0.96)
            let forward = step > 0
            let host = make(step)
            // Лист, который пойдёт вперёд, получает торец: при повороте
            // пальцем его нет — там переворачивают один лист, — а домой
            // возвращаются через пачку (решение P178).
            //
            // Вперёд поворачивается открытая страница, назад — та, что
            // возвращается из-под корешка: торец нужен тому листу, который
            // движется. Свободный край у обоих правый — корешок слева.
            let moving = forward ? pages.viewControllers?.first?.view : host.view
            let edge = moving.map { Coordinator.thicken($0) }

            pages.setViewControllers([host],
                                     direction: forward ? .forward : .reverse,
                                     animated: true) { [weak self] done in
                guard let self else { return }
                self.busy = false
                edge?.removeFromSuperview()
                guard done else { self.parent.plan.wrappedValue = []; return }
                // Страница, на которой человек оказался, становится нулевой —
                // та же перенумерация, что и после поворота пальцем (P131).
                host.offset = 0
                self.parent.onTurn(step)
                if !self.parent.plan.wrappedValue.isEmpty {
                    self.parent.plan.wrappedValue.removeFirst()
                }
            }
        }

        /// Торец пачки на свободном краю листа.
        ///
        /// Пачку не изобразить числом поворотов: система переворачивает по
        /// одному листу и ждёт, пока он ляжет, — три поворота подряд
        /// читаются как три отдельных, а не как один толстый. Поэтому
        /// толщина рисуется на самом листе: он поднимается вместе со своим
        /// торцом, и поворот выходит не дольше обычного, а весомее
        /// (решение P178).
        @discardableResult
        static func thicken(_ view: UIView) -> UIView {
            let ширина: CGFloat = 11
            let листов = 4
            let block = UIView(frame: CGRect(x: view.bounds.width - ширина, y: 0,
                                             width: ширина,
                                             height: view.bounds.height))
            block.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
            block.backgroundColor = UIColor(Look.boardFace)
            block.isUserInteractionEnabled = false
            block.clipsToBounds = true

            let лист = ширина / CGFloat(листов)
            for i in 0..<листов {
                let leaf = UIView(frame: CGRect(x: CGFloat(i) * лист, y: 0,
                                                width: лист - 0.7,
                                                height: block.bounds.height))
                leaf.autoresizingMask = [.flexibleHeight]
                leaf.backgroundColor = UIColor(i == листов - 1 ? Look.boardDeep : Look.boardLit)
                block.addSubview(leaf)
            }
            view.addSubview(block)
            return block
        }

        func make(_ offset: Int) -> Host {
            let host = Host(rootView: parent.content(offset))
            host.offset = offset
            host.view.backgroundColor = UIColor(Look.chrome)
            host.view.isOpaque = true
            // Страница не подбирается ни под клавиатуру, ни под края экрана.
            // Под клавиатуру — иначе весь экран вместе с шестерёнкой и
            // нижними разделами вздрагивает, едва человек ставит курсор.
            // Под края — иначе календарь, наезжая сверху, проходит под
            // часами и вырезом камеры: страница отступает от них, а у места
            // отступ снимается, и текст прыгает в самом конце хода. Своё
            // место на экране страница получает от оболочки (решение P191).
            host.safeAreaRegions = []
            return host
        }

        /// Перерисовать открытую страницу, не трогая соседние.
        func refresh(_ pages: UIPageViewController) {
            guard let current = pages.viewControllers?.first as? Host else { return }
            current.rootView = parent.content(current.offset)
        }

        func pageViewController(_ pages: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            (vc as? Host).map { make($0.offset - 1) }
        }

        func pageViewController(_ pages: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            (vc as? Host).map { make($0.offset + 1) }
        }

        /// Страницу потянули пальцем — шелест (P265). Вперёд — чуть выше
        /// тоном, назад — чуть ниже (P330).
        func pageViewController(_ pages: UIPageViewController,
                                willTransitionTo pending: [UIViewController]) {
            let from = (pages.viewControllers?.first as? Host)?.offset ?? 0
            let to = (pending.first as? Host)?.offset ?? 0
            Sounds.flip(rate: to > from ? 1.04 : 0.96)
        }

        func pageViewController(_ pages: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let current = pages.viewControllers?.first as? Host,
                  current.offset != 0
            else { return }

            parent.onTurn(current.offset)
            // Страница, на которой человек теперь стоит, становится нулевой —
            // но подменять её новой нельзя: новая соберётся по старым данным
            // и мелькнёт чужим месяцем, пока не подоспеют свежие. Поэтому
            // просто перенумеровываем ту же самую: на экране ничего не
            // меняется, а соседи теперь считаются от неё (P113).
            current.offset = 0
        }
    }
}

/// Привратник листания (P532). Палец лёг у края страницы — привратник сразу
/// сдаётся, и система листает, как прежде. Лёг посреди — привратник
/// «срабатывает», и ждавшая его тяга системы не начинается: движение вбок
/// достаётся тексту — курсору и выделению. Сам он ничего не делает и
/// никому не мешает: касания не задерживает и работает вместе со всеми.
final class EdgeGate: UIGestureRecognizer, UIGestureRecognizerDelegate {

    /// Ширина полосы у каждого края, где лист можно взять, — около 7 мм.
    static let band: CGFloat = 40

    /// Привратник, готовый к делу: касаний не держит и не отменяет.
    static func make() -> EdgeGate {
        let gate = EdgeGate(target: nil, action: nil)
        gate.cancelsTouchesInView = false
        gate.delaysTouchesBegan = false
        gate.delaysTouchesEnded = false
        gate.delegate = gate
        return gate
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, let view, let touch = touches.first else { return }
        let x = touch.location(in: view).x
        let atEdge = x < Self.band || x > view.bounds.width - Self.band
        state = atEdge ? .failed : .recognized
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
