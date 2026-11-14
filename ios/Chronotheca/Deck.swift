import SwiftUI

/// Что сейчас на экране в разделе «День» — одним значением (P921, план —
/// `docs/71`). Прежде это складывалось из двух десятков флажков в `Shell` и
/// `Ribbon`, и недопустимое их сочетание возникало при определённой
/// скорости телефона (поломки сборок 278–288).
///
/// Сборка А: состояние живёт рядом с прежними флажками. Каждое место,
/// менявшее `pulling`, `ribbonOpen`, `dayCard`, `fileFrom`, теперь сообщает
/// событие в `Shell.go(_:)`; тот ведёт состояние по таблице и сам ставит
/// прежние флажки — ровно как раньше. Событие, которого в таблице нет,
/// пока исполняется по-старому, но помечается в следе: по нему видно, где
/// прежний код попадал в недопустимое. Со сборки Б такие события
/// отбрасываются.
enum Deck: Equatable {
    /// С какой стороны от «Сегодня»: прошлое или будущее. Число — прежний
    /// знак `fileFrom`: 1 — прошлое, −1 — будущее.
    enum Side: Int {
        case past = 1
        case future = -1

        init(_ dir: Int) { self = dir < 0 ? .future : .past }

        var name: String { self == .past ? "прошлое" : "будущее" }
    }

    /// Ступени посадки закрытой карточки: летит · ждёт ленту · встаёт.
    enum Step {
        case flying, waiting, settling

        var name: String {
            switch self {
            case .flying: return "летит"
            case .waiting: return "ждёт ленту"
            case .settling: return "встаёт"
            }
        }
    }

    /// Лист открыт целиком (сегодня или день с карточки).
    case day
    /// Лист тянут за край, под ним видна картотека.
    case pulling(Side, today: Bool)
    /// Картотека: прошлое или будущее; «Сегодня» — полоской у края.
    case file(Side)
    /// Не сегодняшний день закрывается в карточку и садится на место.
    case landing(card: String, Side, Step)

    enum Event {
        /// Лист потянули за край (или сменили сторону тяги).
        case pull(Side, today: Bool)
        /// Отпустили до порога, вернули палец или тягу отменили.
        case pullBack
        /// Сегодняшний лист отпустили за порогом, лента доехала.
        case released
        /// Не сегодняшний лист закрывают в карточку: тягой за порог
        /// (`swipe` — пусто) или касанием «Сегодня» (`swipe` — с какой
        /// стороны «Сегодня» выйдет).
        case fold(card: String, Side, swipe: Int?)
        /// Посадка: лента пересобрана вокруг сегодня.
        case rebuilt
        /// Посадка: лента встала, карточка на месте.
        case stood
        /// Посадка: карточка села.
        case landed
        /// Картотеку поставили без тяги: запуск, снимок, кнопка.
        case place(open: Bool)
        /// С какой стороны открыть картотеку (снимок, замер).
        case aim(Int)
        /// «Сегодня» встаёт у своего края вместо недосевшей карточки.
        case hide(Int)
        /// «Сегодня» у своего края — сейчас поднимется.
        case todayAtEdge(Int)
        /// Лента доехала местом дня на экран — снова день.
        case backInDay
        /// Нажали карточку — открыт её день.
        case openCard
        /// Ушли в другой раздел — картотека закрыта без хода.
        case closeNow

        var name: String {
            switch self {
            case .pull: return "тянут"
            case .pullBack: return "тягу вернули"
            case .released: return "отпустили за порогом"
            case .fold(_, _, let swipe): return swipe == nil ? "закрыли тягой" : "закрыли касанием «Сегодня»"
            case .rebuilt: return "лента пересобрана"
            case .stood: return "лента встала"
            case .landed: return "карточка села"
            case .place(let open): return open ? "поставили картотеку" : "поставили день"
            case .aim: return "сторона"
            case .hide: return "«Сегодня» вместо посадки"
            case .todayAtEdge: return "«Сегодня» у края"
            case .backInDay: return "лента доехала до дня"
            case .openCard: return "нажали карточку"
            case .closeNow: return "другой раздел"
            }
        }
    }

    var name: String {
        switch self {
        case .day: return "день"
        case .pulling(let side, let today): return "тянут(\(side.name), \(today ? "сегодня" : "карточка"))"
        case .file(let side): return "картотека(\(side.name))"
        case .landing(let card, let side, let step): return "посадка(\(card), \(side.name), \(step.name))"
        }
    }

    /// Таблица переходов (`docs/71`, §3). Возвращает, куда ведёт событие и
    /// есть ли такой переход в таблице. `aim` — прежний `fileFrom`: сторона,
    /// с которой открыть картотеку, поставленную без тяги.
    static func step(_ from: Deck, _ event: Event, aim: Int = 0) -> (to: Deck, listed: Bool) {
        switch event {
        case .pull(let side, let today):
            switch from {
            case .day, .pulling: return (.pulling(side, today: today), true)
            default: return (.pulling(side, today: today), false)
            }
        case .pullBack:
            switch from {
            case .day, .pulling: return (.day, true)
            default: return (from, false)
            }
        case .released:
            if case .pulling(let side, true) = from { return (.file(side), true) }
            return (.file(Side(aim)), false)
        case .fold(let card, let side, let swipe):
            let to = Deck.landing(card: card, side, .flying)
            switch from {
            case .pulling(_, let today): return (to, !today && swipe == nil)
            case .day: return (to, swipe != nil)
            default: return (to, false)
            }
        case .rebuilt:
            if case .landing(let card, let side, .flying) = from { return (.landing(card: card, side, .waiting), true) }
            return (from, false)
        case .stood:
            if case .landing(let card, let side, .waiting) = from { return (.landing(card: card, side, .settling), true) }
            return (from, false)
        case .landed:
            if case .landing(_, let side, let at) = from { return (.file(side), at == .settling) }
            return (from, false)
        case .place(let open):
            guard open else { return (.day, true) }
            switch from {
            case .day: return (.file(Side(aim)), true)
            case .file, .landing: return (from, true)
            case .pulling: return (.file(Side(aim)), false)
            }
        case .aim:
            return (from, true)
        case .hide:
            if case .landing = from { return (from, true) }
            return (from, false)
        case .todayAtEdge(let dir):
            if case .file = from { return (.file(Side(dir)), true) }
            return (.file(Side(dir)), false)
        case .backInDay, .openCard:
            if case .file = from { return (.day, true) }
            return (.day, false)
        case .closeNow:
            return (.day, true)
        }
    }
}

extension Shell {
    /// Единственное место, где меняется состояние картотеки (P921). Ведёт
    /// `deck` по таблице, пишет переход в след и ставит прежние флажки —
    /// в том же порядке, в каком их ставили места вызова до сборки А.
    func go(_ event: Deck.Event) {
        let from = deck
        let next = Deck.step(from, event, aim: fileFrom)
        deck = next.to
        DeckTrail.note(from: from, event: event, to: next.to, listed: next.listed)
        switch event {
        case .pull(let side, _):
            let dir = side.rawValue
            if !pulling {
                fileFrom = dir
                pulling = true
            } else if fileFrom != dir {
                fileFrom = dir
            }
        case .pullBack:
            pulling = false
        case .released:
            ribbonOpen = true
            screen = .search
            pulling = false
        case .fold(_, _, let swipe):
            if let swipe { fileFrom = swipe }
            ribbon.frozen = true
            if swipe != nil { ribbon.opened() }
            ribbon.folding = true
            // Картотека под листом не вспыхивает на кадр перед тем, как
            // скрыться на пересборку (P913).
            ribbon.veiled = true
            dayCard = true
            ribbonOpen = true
            screen = .search
            if swipe == nil { pulling = false }
        case .rebuilt, .stood:
            break
        case .landed:
            dayCard = false
        case .place(let open):
            ribbonOpen = open
        case .aim(let dir):
            fileFrom = dir
        case .hide(let dir):
            ribbon.frozen = true
            ribbon.foldSide = dir
            dayCard = true
        case .todayAtEdge(let dir):
            dayCard = false
            fileFrom = dir
        case .backInDay, .openCard:
            ribbonOpen = false
            fileFrom = 0
        case .closeNow:
            ribbonOpen = false
            pulling = false
            fileFrom = 0
        }
    }
}

/// След переходов картотеки (P921): последние шестьдесят — в «Замерах
/// скорости» (долгое нажатие на «Версия»), все — в следе проверок
/// движения. Строка с «✗» — события нет в таблице переходов: прежний код
/// исполнил его, новый отбросит.
enum DeckTrail {
    private(set) static var lines: [String] = []

    static func note(from: Deck, event: Deck.Event, to: Deck, listed: Bool) {
        // То же состояние по таблице — не событие для следа (кнопка
        // «Дневник» ставит открытую картотеку ещё раз).
        guard from != to || !listed else { return }
        let line = String(format: "%.2f ", Date().timeIntervalSince(LaunchClock.start))
            + (listed ? "" : "✗ ") + from.name + " → " + to.name + " · " + event.name
        lines.append(line)
        if lines.count > 60 { lines.removeFirst(lines.count - 60) }
        Trace.note("колода: " + (listed ? "" : "✗ ") + from.name + " → " + to.name + " · " + event.name)
    }
}

/// Медленная лента для проверок движения (P921, `docs/71` §5): замеры ячеек
/// ленты приходят с опозданием и вразнобой — как на телефоне, где ленивая
/// стопка собирает карточки позже, чем ждут шаги по времени. В симуляторе
/// лента всегда успевает, и поломки автора там не повторялись. Только по
/// просьбе проверки; у человека этот путь недостижим.
enum Slow {
    static let on = Vault.isUITest
        && ProcessInfo.processInfo.environment["CHRONOTHECA_SLOW_RIBBON"] == "1"
    /// Место дня — позже, чем рамки карточек: вразнобой.
    static let slot = 0.5
    static let card = 0.3

    static func late(_ delay: Double, _ act: @escaping () -> Void) {
        guard on else {
            act()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: act)
    }
}

/// Для проверок движения (P921): состояние картотеки и где лист «Сегодня» —
/// невидимой строкой, только когда приложение запустила проверка.
struct DeckProbe: View {
    @EnvironmentObject private var shell: Shell
    @ObservedObject var ribbon: Ribbon

    var body: some View {
        let y = shell.ribbonLive ? ribbon.y : 0
        let today = FollowRibbon.shown(y, height: ribbon.height, stick: ribbon.stick)
        Text("deck=\(shell.deck.name);today=\(Int(today));height=\(Int(ribbon.height));"
             + "veiled=\(ribbon.veiled ? 1 : 0);card=\(shell.dayCard ? 1 : 0)")
            .font(.system(size: 2))
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("deckProbe")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
