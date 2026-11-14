import XCTest
@testable import Chronotheca

/// Таблица переходов картотеки (P921, `docs/71` §3): что разрешено и куда
/// ведёт. Чего в таблице нет — помечается (со сборки Б — отбрасывается).
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
        let fold = Deck.Event.fold(card: "2026-11-01", .past, swipe: nil)
        let done = walk([.pull(.future, today: false), fold, .rebuilt, .stood, .landed])
        // Сторона — где карточка, а не куда тянули лист.
        XCTAssertEqual(done.deck, .file(.past))
        XCTAssertTrue(done.listed)
        let half = walk([.pull(.past, today: false), fold, .rebuilt])
        XCTAssertEqual(half.deck, .landing(card: "2026-11-01", .past, .waiting))
    }

    func testСтупеньНеПерескакивает() {
        let fold = Deck.Event.fold(card: "2026-11-20", .future, swipe: nil)
        // Лента ещё не пересобрана, а «встала» уже пришло — не по таблице.
        let early = walk([.pull(.past, today: false), fold, .stood])
        XCTAssertFalse(early.listed)
        XCTAssertEqual(early.deck, .landing(card: "2026-11-20", .future, .flying))
        // Села, не встав.
        XCTAssertFalse(walk([.pull(.past, today: false), fold, .landed]).listed)
    }

    func testТянутьВоВремяПосадкиНельзя() {
        let fold = Deck.Event.fold(card: "2026-11-01", .past, swipe: nil)
        XCTAssertFalse(walk([.pull(.past, today: false), fold, .pull(.past, today: true)]).listed)
        // Сегодняшний лист в карточку не закрывается.
        XCTAssertFalse(walk([.pull(.past, today: true), fold]).listed)
    }

    func testКартотекаБезТягиИНазад() {
        XCTAssertEqual(Deck.step(.day, .place(open: true), aim: -1).to, .file(.future))
        XCTAssertEqual(Deck.step(.day, .place(open: true), aim: 0).to, .file(.past))
        let card = walk([.place(open: true), .openCard])
        XCTAssertEqual(card.deck, .day)
        XCTAssertTrue(card.listed)
        let today = walk([.place(open: true), .todayAtEdge(-1), .backInDay])
        XCTAssertEqual(today.deck, .day)
        XCTAssertTrue(today.listed)
        // Другой раздел закрывает картотеку из любого состояния.
        XCTAssertTrue(Deck.step(.landing(card: "x", .past, .waiting), .closeNow).listed)
    }

    func testКасаниеСегодняЗакрываетОткрытуюКарточку() {
        let fold = Deck.Event.fold(card: "2026-11-01", .past, swipe: 1)
        let done = walk([fold, .rebuilt, .stood, .landed, .todayAtEdge(1), .backInDay])
        XCTAssertEqual(done.deck, .day)
        XCTAssertTrue(done.listed)
    }
}
