import XCTest
@testable import Chronotheca

/// P570: две версии одного дня с разных устройств складываются в одну —
/// ничего не пропадает и не задваивается.
final class SyncMergeTests: XCTestCase {

    func testДневникДописываетсяНеТеряя() {
        let телефон = "---\ndate: 2026-10-21\ntitle: Туман\n---\n\n08:15 Утро на телефоне.\n"
        let айпад = "---\ndate: 2026-10-21\n---\n\n08:15 Утро на телефоне.\n\n14:00 День на iPad.\n"
        let вместе = Vault.merge(телефон, with: айпад, diary: true)
        XCTAssertTrue(вместе.contains("08:15 Утро на телефоне."))
        XCTAssertTrue(вместе.contains("14:00 День на iPad."))
        XCTAssertTrue(вместе.contains("title: Туман"))
        XCTAssertEqual(вместе.components(separatedBy: "08:15 Утро на телефоне.").count, 2,
                       "общая строка задвоилась")
    }

    func testОдинаковыеВерсииНеМеняются() {
        let одно = "---\ndate: 2026-10-21\n---\n\n08:15 Утро.\n"
        XCTAssertEqual(DayFile(text: Vault.merge(одно, with: одно, diary: true)), DayFile(text: одно))
    }

    func testПланДелаПоНазванию() {
        let телефон = "---\ndate: 2026-10-21\n---\n- [x] 09:00 Нотариус\n- [ ] Позвонить\n"
        let айпад = "---\ndate: 2026-10-21\n---\n- [ ] 09:00 Нотариус\n- [ ] Позвонить\n- [ ] Купить хлеб\n"
        let вместе = Vault.merge(телефон, with: айпад, diary: false)
        XCTAssertTrue(вместе.contains("- [x] 09:00 Нотариус"), "отметка «сделано» пропала")
        XCTAssertFalse(вместе.contains("- [ ] 09:00 Нотариус"), "дело задвоилось")
        XCTAssertTrue(вместе.contains("- [ ] Купить хлеб"), "дело с другого устройства пропало")
    }
}
