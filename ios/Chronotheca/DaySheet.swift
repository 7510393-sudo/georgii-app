import SwiftUI
import UIKit

/// Страница дня: сверху план, ниже дневник — одним листом (P408).
///
/// Прежде это были две вкладки, и «как прошло» писали на одной, не видя
/// задуманного на другой. Теперь задуманное стоит над тем, что из него
/// вышло, и страница едет целиком: одна прокрутка на план и дневник.
///
/// Бумага двух сортов: под планом — в клетку, под дневником — гладкая
/// (P245). Граница — заголовок «Дневник».
///
/// Открытый день и соседние собираются из неё одинаково: стоит им
/// разойтись хоть на строку — и при перелистывании текст прыгает (P114).
struct DaySheet<Plan: View, Diary: View>: View {

    let date: Date
    /// Приложение открыли заново или вернулись после паузы (P346):
    /// меняется — страница встаёт на своё место. У соседних не меняется.
    var home = 0
    /// Куда встать: к концу записи дневника или к началу плана (P402).
    var toDiary = false
    /// Дневника у этого дня ещё нет — будущий день: заголовок бледный.
    var diaryOpen = true
    /// Просьба встать на план или на дневник (P424): меняется — страница
    /// встаёт. Перелистнули назад, глядя в дневник, — новая страница
    /// открывается на дневнике; вперёд и из календаря — на плане.
    var land = 0
    var landDiary = false
    /// Больше половины окна занял дневник — или снова план (P424).
    var onDiary: ((Bool) -> Void)?
    /// Что сидит над заголовком «Дневник» — облачко «…помнишь?» открытого
    /// дня (P436). У соседних страниц нет.
    var diaryMark: AnyView? = nil
    /// Полоска вложений — конец самой страницы, под погодой, в самом низу
    /// (P502): едет со страницей, а не стоит у нижней строки.
    var strip: AnyView? = nil
    /// Накладка над текстом страницы, но под полоской вложений и её рядом
    /// галереи: ловит касание мимо ряда (P527).
    var catcher: AnyView? = nil
    /// Лента превью и строка вложений над клавиатурой, пока пишут (P541).
    var dock: AnyView? = nil
    /// Сколько полоска над клавиатурой отнимает у страницы.
    private var dockRoom: CGFloat { dock != nil ? KeyboardDock.height : 0 }

    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let diary: () -> Diary

    @State private var keyboard: CGFloat = 0
    /// Место под ушедшей клавиатурой, которое ещё держит страницу (P446).
    @State private var hold: CGFloat = 0
    /// Сама прокрутка листа — чтобы, когда клавиатура ушла, плавно опустить
    /// страницу на место (P457).
    @State private var scroller = SheetScroller()

    private static var top: String { "страница-верх" }
    private static var diaryTop: String { "страница-дневник" }
    static var space: String { "лист" }
    private static var window: String { "окно-листа" }
    /// Строка вложений лежит поверх низа страницы, полупрозрачная (P424):
    /// столько места под концом записи, чтобы её можно было поднять из-под
    /// строки.
    static var stripRoom: CGFloat { 46 }

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Чуть ниже середины своей полосы: у верхнего края
                            // страница тает под шапкой, и буквы не должны
                            // попадать в эту дымку (P441).
                            SheetHeading(title: T("План", "Plan"), drop: 6)
                                .id(Self.top)
                            plan()
                        }
                        // Под планом — клетка, она закрывает гладкую бумагу
                        // дневника, лежащую под всей страницей.
                        .background(Ru.tint(date).overlay(PageTexture(tab: .plan, space: Self.space)))
                        VStack(alignment: .leading, spacing: 0) {
                            SheetHeading(title: T("Дневник", "Diary"), faint: !diaryOpen)
                                .id(Self.diaryTop)
                                // Облачко «…помнишь?» сидит над заголовком,
                                // у правого края (P436): низом на его верху.
                                .overlay(alignment: .topTrailing) {
                                    if let diaryMark {
                                        diaryMark.alignmentGuide(.top) { $0[.bottom] - 6 }
                                    }
                                }
                                .zIndex(1)
                            diary()
                        }
                        .background {
                            if onDiary != nil {
                                GeometryReader { g in
                                    Color.clear.preference(key: DiaryShare.self,
                                                           value: g.frame(in: .named(Self.window)).minY)
                                }
                            }
                        }
                        // Страница открыта на дневнике — дневник не короче
                        // окна: иначе на коротком дне листать некуда, и план
                        // остаётся сверху, хотя должен уйти за верхний край
                        // (P426). Соседняя страница считает так же (P114).
                        .frame(minHeight: landDiary && diaryOpen
                               ? max(0, outer.size.height - Self.stripRoom) : nil,
                               alignment: .top)
                        // Короткая страница — низ дневника (погода, полоска)
                        // всё равно у нижнего края экрана.
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    // Место под строкой вложений — всегда, и с клавиатурой
                    // (P432): прежде оно пропадало, пока клавиатура открыта,
                    // и возвращалось скачком, когда она уходила, — низ
                    // страницы прыгал на эти 36 точек (около 6 мм) вниз и
                    // обратно (видео автора).
                    .padding(.bottom, Self.stripRoom)
                    .frame(minHeight: outer.size.height, alignment: .top)
                    .overlay { if let catcher { catcher } }
                    // Полоска — у самого низа листа: на короткой странице у
                    // нижнего края окна, на длинной — под концом записи.
                    .overlay(alignment: .bottom) {
                        if let strip {
                            // Полоска стоит на 6 точек выше края страницы (P511):
                            // на пустой странице она целиком над нижней
                            // строкой, рваный край которой иначе её закрывает.
                            // Пока над клавиатурой своя строка вложений (P541),
                            // эта прячется — место за ней остаётся, ничего
                            // не сдвигается (P542).
                            let docked = keyboard > 0 && dock != nil
                            strip
                                .frame(height: KeyboardBar.attachHeight)
                                .padding(.bottom, Self.stripRoom - KeyboardBar.attachHeight)
                                .opacity(docked ? 0 : 1)
                                .allowsHitTesting(!docked)
                        }
                    }
                    .background(Ru.tint(date).overlay(PageTexture(tab: .diary, space: Self.space)))
                    // Клетка и волокно отсчитываются от самого листа, а не
                    // от экрана: тянешь план — клетка едет с текстом (P412).
                    .coordinateSpace(name: Self.space)
                    // Страница не оттягивается пальцем за край (P445):
                    // клавиатуру смахивали вниз — короткая страница ехала за
                    // пальцем на пару сантиметров и, когда клавиатура уходила,
                    // прыгала обратно (запись экрана автора). Это и был
                    // «скачок».
                    .background(NoBounce(box: scroller))
                    // Где лист и какой он высоты без места под клавиатуру —
                    // по ним место отпускается, когда клавиатура ушла (P446).
                    .background(GeometryReader { g in
                        Color.clear.preference(key: SheetBox.self, value: g.frame(in: .named(Self.window)))
                    })
                    // Место под клавиатуру: без него строку, в которой пишут,
                    // некуда поднять (P166, P175). Ровно столько, сколько
                    // клавиатура закрывает саму страницу: прежде отводилась
                    // вся её высота, хотя низ экрана и так занят разделами, —
                    // и страница, поднятая до конца, висела над клавиатурой
                    // с зазором в несколько строк (P413).
                    // Строка вложений — конец самой страницы (P496) и своё
                    // место уже имеет, но клавиатура её больше не несёт на
                    // себе: место под клавиатуру — полностью, иначе страница
                    // кончается погодой, а полоска остаётся под клавиатурой
                    // (замечание автора к 121).
                    // И над ней — полоска с превью и вложениями (P541).
                    .padding(.bottom, max(keyboard > 0 ? covered(outer, keyboard) + dockRoom : 0, hold))
                    .onAppear {
                        goHome(proxy)
                        settle(proxy, fresh: true)
                    }
                    .onChange(of: home) { _, _ in goHome(proxy) }
                    .onChange(of: land) { _, _ in settle(proxy, fresh: false) }
                }
            }
            .coordinateSpace(name: Self.window)
            // Пока поднята клавиатура — над ней лента превью и строка
            // вложений (P541): их видно, пока пишут, и превью можно унести
            // в текст, не опуская клавиатуру.
            .overlay(alignment: .bottom) {
                if keyboard > 0, let dock {
                    dock
                        .padding(.bottom, covered(outer, keyboard))
                        .transition(.opacity)
                }
            }
            // Клавиатура ушла — место под ней остаётся, пока страница стоит
            // ниже, чем позволил бы лист без него: иначе iPhone подтягивает
            // страницу вниз одним рывком (запись экрана автора, P446).
            // Запоминается, пока клавиатура ещё открыта: в миг её ухода
            // место уже на месте, и лист не становится короче ни на кадр.
            .onChange(of: keyboard) { _, now in
                if now > 0 {
                    hold = max(0, covered(outer, now) + dockRoom)
                } else if hold > 0 {
                    release()
                }
            }
            // Прокрутили вверх — лишнее место отпускается ровно настолько,
            // насколько оно больше не нужно: ничто не прыгает.
            .onPreferenceChange(SheetBox.self) { box in
                guard keyboard == 0, hold > 0 else { return }
                let needed = max(0, -box.minY + outer.size.height - box.height)
                if needed < hold { hold = needed }
            }
            .onChange(of: date) { _, _ in hold = 0 }
            .onPreferenceChange(DiaryShare.self) { top in
                onDiary?(top < (outer.size.height - Self.stripRoom) / 2)
            }
            .scrollDismissesKeyboard(.interactively)
            // Ход плавный и один: клавиатура и страница едут вместе.
            .animation(.easeOut(duration: 0.25), value: keyboard)
        }
        .keyboardHeight($keyboard)
    }

    /// Клавиатура ушла (P457): страница плавно опускается так, чтобы её низ
    /// — полоска вложений — лёг на своё место над нижней строкой, и только
    /// потом место под клавиатурой отпускается. Прежде (P446) место
    /// оставалось, и конец записи висел посреди экрана над пустой бумагой
    /// (запись экрана автора); а если отпустить его сразу, iPhone подтягивает
    /// страницу одним рывком.
    private func release() {
        guard let view = scroller.view else { hold = 0; return }
        let inset = view.adjustedContentInset
        let natural = view.contentSize.height - hold
        let lowest = max(-inset.top, natural - view.bounds.height + inset.bottom)
        guard view.contentOffset.y > lowest + 0.5 else { hold = 0; return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            view.contentOffset.y = lowest
        } completion: { _ in
            hold = 0
        }
    }

    /// Сколько страницы закрыто клавиатурой вместе с полоской вложений над
    /// ней.
    private func covered(_ outer: GeometryProxy, _ keyboard: CGFloat) -> CGFloat {
        guard keyboard > 0 else { return 0 }
        let safe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        let top = UIScreen.main.bounds.height - keyboard - safe
        return max(0, outer.frame(in: .global).maxY - top)
    }

    /// Встать на место — один раз на каждое открытие приложения: открыли
    /// «на дневнике» — к концу записи, «на плане» — к началу (P346, P402).
    private func goHome(_ proxy: ScrollViewProxy) {
        guard home > 0, home != SheetMemory.homed else { return }
        SheetMemory.homed = home
        let diary = toDiary && diaryOpen
        DispatchQueue.main.async {
            if diary {
                proxy.scrollTo(DiaryPage.end, anchor: .bottom)
            } else {
                proxy.scrollTo(Self.top, anchor: .top)
            }
        }
    }

    /// Встать на план или на дневник по просьбе (P424). Новая страница
    /// встаёт по просьбе один раз; соседняя, у которой своей просьбы нет
    /// (`land == 0`), — сразу туда, куда встанет открытая.
    ///
    /// Просьба помнится вместе с днём (P445): прежде — одним номером, и
    /// уходящая страница успевала «исполнить» его за новую — новая страница
    /// считала, что уже встала, и оставалась на плане.
    private func settle(_ proxy: ScrollViewProxy, fresh: Bool) {
        let key = "\(land)|\(Vault.stamp(date))"
        if fresh {
            if land > 0 {
                guard key != SheetMemory.landed else { return }
            } else if !landDiary {
                return
            }
        }
        if land > 0 { SheetMemory.landed = key }
        let target = landDiary && diaryOpen ? Self.diaryTop : Self.top
        // Ещё раз, когда страница нового дня уже разложена: первая прокрутка
        // могла прийтись на прежнюю раскладку.
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(target, anchor: .top) }
    }
}

/// Где лист в окне и какой он высоты без места под клавиатуру (P446).
private struct SheetBox: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Где верх дневника в окне — по нему видно, что занимает экран (P424).
private struct DiaryShare: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Для какого открытия страница уже встала на место.
private enum SheetMemory {
    static var homed = -1
    static var landed = ""
}

/// Заголовок части страницы — «План» или «Дневник» (P408): прописными, в
/// разрядку, как прежние корешки вкладок; на 15% крупнее и без черт по
/// бокам (P412), и ещё на 30% (P424). Ростом ровно в две клетки листа
/// (P413).
struct SheetHeading: View {
    let title: String
    var faint = false
    /// Насколько буквы ниже середины полосы; сама полоса той же высоты —
    /// строки плана остаются на линиях клетки (P413, P441).
    var drop: CGFloat = 0

    var body: some View {
        Text(title.uppercased())
            .font(Look.sans(22.4, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(faint ? Look.inkFaint : Look.inkSoft)
            .lineLimit(1)
            .offset(y: drop)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: GridSnap.cell * 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Строка плана — целое число клеток листа (P413): высота округляется до
/// клеток вверх (недобор в три точки прощается — его съедают поля), а
/// содержимое стоит посередине. Клетка листа отсчитывается от верха плана,
/// и так промежутки между плашками ложатся ровно на её линии.
struct GridSnap: Layout {
    static let cell: CGFloat = PageTexture.cell

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: Self.snap(size.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }

    static func snap(_ h: CGFloat) -> CGFloat {
        guard h > 0.5 else { return 0 }
        return max(1, ((h - 3) / cell).rounded(.up)) * cell
    }
}

/// Прокрутка листа, найденная по месту (P457).
final class SheetScroller {
    weak var view: UIScrollView?
}

/// Выключает у прокрутки, в которой стоит, оттяжку за край (P445) и
/// запоминает её (P457).
private struct NoBounce: UIViewRepresentable {
    let box: SheetScroller

    func makeUIView(context: Context) -> Finder {
        let finder = Finder()
        finder.box = box
        return finder
    }
    func updateUIView(_ view: Finder, context: Context) {
        view.box = box
        view.apply()
    }

    final class Finder: UIView {
        var box: SheetScroller?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        /// Стоит внутри листа — первая прокрутка выше по цепочке и есть
        /// прокрутка страницы.
        func apply() {
            DispatchQueue.main.async { [weak self] in
                var node: UIView? = self?.superview
                while let here = node {
                    if let scroll = here as? UIScrollView {
                        scroll.bounces = false
                        self?.box?.view = scroll
                        return
                    }
                    node = here.superview
                }
            }
        }
    }
}
