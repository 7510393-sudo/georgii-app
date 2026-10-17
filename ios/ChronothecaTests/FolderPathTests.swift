import XCTest
@testable import Chronotheca

/// Путь к папке словами «Файлов» (решение P190).
///
/// Человек ищет папку в «Файлах», а там нет «/private/var/mobile/…» — там
/// «iCloud Drive» и «На iPhone». Путь в настройках должен совпадать с тем,
/// что человек увидит, открыв «Файлы».
final class FolderPathTests: XCTestCase {

    func testICloudDrive() {
        let path = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Chronotheca"
        XCTAssertEqual(Vault.friendly(path), "iCloud Drive › Chronotheca")
    }

    func testВложеннаяПапкаВICloud() {
        let path = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Личное/Chronotheca"
        XCTAssertEqual(Vault.friendly(path), "iCloud Drive › Личное › Chronotheca")
    }

    func testНаIPhone() {
        let path = "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Chronotheca"
        XCTAssertEqual(Vault.friendly(path), T("На iPhone", "On My iPhone") + " › Chronotheca")
    }

    func testПапкаДругогоПриложения() {
        let path = "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Chronotheca"
        XCTAssertEqual(Vault.friendly(path), "iCloud Drive › Documents › Chronotheca")
    }

    /// Своя папка приложения на телефоне — так, как её называют «Файлы» (P223).
    func testСвояПапкаНаТелефоне() {
        let path = "/private/var/mobile/Containers/Data/Application/0A1B/Documents"
        XCTAssertEqual(Vault.friendly(path), T("На iPhone", "On My iPhone") + " › Chronotheca")
        XCTAssertEqual(Vault.friendly(path + "/Дневник"), T("На iPhone", "On My iPhone") + " › Chronotheca › Дневник")
    }
}
