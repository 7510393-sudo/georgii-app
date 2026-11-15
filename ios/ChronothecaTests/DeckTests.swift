import XCTest
@testable import Chronotheca

/// Таблица переходов картотеки (P921, `docs/71` §3): что разрешено и куда
/// ведёт. Чего в таблице нет — отбрасывается, состояние прежнее (P923).
final class DeckTests: XCTestCase {

    private func walk(_ events: [Deck.Event], from start: Deck = .day) -> (deck: Deck, listed: Bool) {
        var deck = start
        var listed = true
        for event in events {
            let next = Deck.step(deck, event)
            deck = next.to
            listed = listed && next.listed
        }
        return (deck, listed)
    }

    func testСегодняТянутИОтпускаютЗаПорогом() {
        let past = walk([.pull(.past, today: true), .released])
        XCTAssertEqual(past.deck, .file(.past))
        XCTAssertTrue(past.listed)
        let future = walk([.pull(.past, today: true), .pull(.future, today: true), .released])
        XCTAssertEqual(future.deck, .file(.future))
        XCTAssertTrue(future.listed)
    }

    func testНеДотянули() {
        let back = walk([.pull(.past, today: true), .pullBack])
        XCTAssertEqual(back.deck, .day)
        XCTAssertTrue(back.listed)
    }

    func testКарточкаСадитсяПоСтупеням() {
        let fold = Deck.Event.fold(card: "2026-11-01", .past)
        let done = walk([.pull(.future, today: false), fold, .aimed, .stood, .landed])
        // Сторона — где карточка, а не куда тянули лист.
        XCTAssertEqual(done.deck, .file(.past))
        XCTAssertTrue(done.listed)
        let half = walk([.pull(.past, today: false), fold, .aimed])
        XCTAssertEqual(half.deck, .landing(card: "2026-11-01", .past, .waiting))
    }

    func testСтупеньНеПерескакивает() {
        let fold = Deck.Event.fold(card: "2026-11-20", .future)
        // Лента ещё не наведена, а «встала» уже пришло — не по таблице.
        let early = walk([.pull(.past, today: false), fold, .stood])
        XCTAssertFalse(early.listed)
        XCTAssertEqual(early.deck, .landing(card: "2026-11-20", .future, .flying))
        // Села, не встав.
        XCTAssertFalse(walk([.pull(.past, today: false), fold, .landed]).listed)
        // Досадить разом можно с любой ступени (предохранитель, «Сегодня»).
        let cut = walk([.pull(.past, today: false), fold, .cutShort])
        XCTAssertTrue(cut.listed)
        XCTAssertEqual(cut.deck, .file(.future))
    }

    func testТянутьВоВремяПосадкиНельзя() {
        let fold = Deck.Event.fold(card: "2026-11-01", .past)
        let pulled = walk([.pull(.past, today: false), fold, .pull(.past, today: true)])
        XCTAssertFalse(pulled.listed)
        // Отброшенное событие состояния не меняет.
        XCTAssertEqual(pulled.deck, .landing(card: "2026-11-01", .past, .flying))
        // Сегодняшний лист в карточку не закрывается.
        XCTAssertFalse(walk([.pull(.past, today: true), fold]).listed)
        // Открытую картотеку за лист не тянут.
        XCTAssertFalse(Deck.step(.file(.past), .pull(.past, today: true)).listed)
        XCTAssertFalse(Deck.file(.past).canPull)
        XCTAssertTrue(Deck.day.canPull)
    }

    func testКартотекаБезТягиИНазад() {
        XCTAssertEqual(Deck.step(.day, .place(open: true, .future)).to, .file(.future))
        XCTAssertEqual(Deck.step(.day, .place(open: true)).to, .file(.past))
        // Уже открытую картотеку постановка без тяги не переворачивает.
        XCTAssertEqual(Deck.step(.file(.future), .place(open: true)).to, .file(.future))
        let card = walk([.place(open: true), .openCard])
        XCTAssertEqual(card.deck, .day)
        XCTAssertTrue(card.listed)
        let today = walk([.place(open: true), .backInDay])
        XCTAssertEqual(today.deck, .day)
        XCTAssertTrue(today.listed)
        // Другой раздел закрывает картотеку из любого состояния.
        XCTAssertTrue(Deck.step(.landing(card: "x", .past, .waiting), .closeNow).listed)
    }

    /// «Сегодня» с открытого листа — сразу день, без посадки (P924).
    func testСегодняСОткрытогоЛистаБезПосадки() {
        let today = Deck.step(.day, .today)
        XCTAssertTrue(today.listed)
        XCTAssertEqual(today.to, .day)
        // Из картотеки и во время посадки такого события нет.
        XCTAssertFalse(Deck.step(.file(.past), .today).listed)
        XCTAssertFalse(Deck.step(.landing(card: "x", .past, .flying), .today).listed)
        XCTAssertFalse(Deck.step(.pulling(.past, today: false), .today).listed)
    }

    /// Что прежде держали флажки, читается из состояния (P928).
    func testИзСостоянияЧитаетсяВсёПрочее() {
        let day = Deck.day
        XCTAssertFalse(day.isLive)
        XCTAssertFalse(day.isOpen)
        XCTAssertNil(day.side)
        let pull = Deck.pulling(.future, today: true)
        XCTAssertTrue(pull.isPulled)
        XCTAssertTrue(pull.isLive)
        XCTAssertFalse(pull.isOpen)
        XCTAssertFalse(pull.isCarried)
        XCTAssertEqual(pull.side, .future)
        // Не сегодняшний лист несут рукой с первой точки тяги.
        XCTAssertTrue(Deck.pulling(.past, today: false).isCarried)
        let file = Deck.file(.past)
        XCTAssertTrue(file.isOpen)
        XCTAssertTrue(file.isFile)
        XCTAssertFalse(file.isLanding)
        XCTAssertFalse(file.isCarried)
        let flying = Deck.landing(card: "x", .future, .flying)
        XCTAssertTrue(flying.isOpen)
        XCTAssertFalse(flying.isFile)
        XCTAssertEqual(flying.folding, .future)
        XCTAssertTrue(flying.isCarried)
        // Картотека под карточкой скрыта, пока лента не встала.
        XCTAssertTrue(flying.isVeiled)
        XCTAssertTrue(Deck.landing(card: "x", .future, .waiting).isVeiled)
        let settling = Deck.landing(card: "x", .future, .settling)
        XCTAssertFalse(settling.isVeiled)
        // Ступень посадки для оболочки — не перемена.
        XCTAssertEqual(flying.coarse, settling.coarse)
        XCTAssertNotEqual(flying.coarse, file.coarse)
    }

    /// Оболочка ведёт состояние сама: отброшенное событие ничего не меняет.
    func testОболочкаВедётСостояние() {
        let shell = Shell()
        XCTAssertTrue(shell.go(.pull(.past, today: false)))
        XCTAssertTrue(shell.ribbon.inHand)
        XCTAssertFalse(shell.go(.released))
        XCTAssertTrue(shell.go(.fold(card: "2026-11-01", .past)))
        XCTAssertEqual(shell.screen, .search)
        XCTAssertFalse(shell.go(.pull(.past, today: true)))
        XCTAssertTrue(shell.go(.cutShort))
        XCTAssertEqual(shell.deck, .file(.past))
        XCTAssertFalse(shell.ribbon.inHand)
        XCTAssertTrue(shell.go(.closeNow))
        XCTAssertEqual(shell.deck, .day)
    }
}
