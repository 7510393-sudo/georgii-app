import Foundation
import SwiftUI

/// Перенос архива из прежней папки в новую.
///
/// Самое опасное место во всём приложении: здесь можно потерять написанное.
/// Поэтому порядок действий один и не меняется — **копия, проверка,
/// и только потом удаление исходника**. Оборвись перенос на любом файле
/// (сел телефон, ушла сеть, закрыли приложение) — файл останется целым либо
/// в прежней папке, либо в новой, но не пропадёт нигде. Запустите перенос
/// снова, и он продолжится с того места, где встал.
///
/// Чужую запись приложение не перезаписывает никогда. Если на новом месте
/// уже есть запись за то же число, разбираться должен человек: обе остаются,
/// и о них говорится вслух (решение P147).
enum Transfer {

    /// Предложение перенести. Показывается, когда человек сменил папку,
    /// а в прежней остались записи.
    struct Offer: Identifiable {
        let id = UUID()
        let fromPath: String
        let toPath: String
        let records: Int
    }

    /// Ход переноса. Между памятью телефона и iCloud он занимает минуты,
    /// и человек должен видеть, что происходит.
    struct Progress {
        var done: Int
        var total: Int
    }

    /// Чем кончилось. Показывается всегда, даже когда всё прошло гладко:
    /// человек должен знать, что стало с его записями.
    struct Report: Identifiable {
        let id = UUID()
        let moved: Int
        let kept: Int
        let failed: Int
        let fromPath: String
    }

    // MARK: - Опись

    /// Сколько записей лежит в папке.
    static func records(in root: URL) -> Int {
        contents(of: root).filter { $0.hasSuffix(".md") }.count
    }

    /// Всё, что переносится, — относительными путями от корня архива.
    ///
    /// «Служебное» не трогаем: метка архива и записка «что это за папка» у
    /// новой папки свои, и подменять их чужими незачем. Кроме списка
    /// повторяющихся дел — он часть записей (P427).
    ///
    /// Пути — с именами папок, как они лежат в прежнем архиве; русские и
    /// английские смотрятся обе (P353). На новом месте каждая ложится под
    /// тем именем, какое у этой папки там (`destination`).
    static func contents(of root: URL) -> [String] {
        let fm = FileManager.default
        let head = root.standardizedFileURL.path
        var out: [String] = []

        let names = Vault.Folder.allCases.filter { $0 != .service }
            .flatMap { [$0.rawValue, $0.russian] }
        for name in names {
            let base = root.appendingPathComponent(name)
            // Скрытое не пропускаем целиком: не скачанный из iCloud файл
            // лежит невидимой заглушкой «.ИМЯ.icloud». Прежде такие файлы
            // молча оставались на старом месте, и на новом записей не было
            // (P426). Заглушка считается тем файлом, который за ней стоит.
            guard let walk = fm.enumerator(at: base,
                                           includingPropertiesForKeys: [.isDirectoryKey],
                                           options: []) else { continue }
            for case var url as URL in walk {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                let leaf = url.lastPathComponent
                if leaf.hasPrefix(".") {
                    if isDir { walk.skipDescendants(); continue }
                    guard let real = stubbed(leaf) else { continue }
                    url = url.deletingLastPathComponent().appendingPathComponent(real)
                }
                if isDir { continue }
                let full = url.standardizedFileURL.path
                guard full.hasPrefix(head) else { continue }
                out.append(String(full.dropFirst(head.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
        }
        // Из служебного переезжает только список повторяющихся дел: без
        // него на новом месте «этот и все следующие» не находили следующих,
        // и повторы не дописывались дальше (P427).
        for name in [Vault.Folder.service.rawValue, Vault.Folder.service.russian] {
            let list = root.appendingPathComponent(name).appendingPathComponent(Repeats.fileName)
            if fm.fileExists(atPath: list.path) || fm.fileExists(atPath: stub(of: list).path) {
                out.append(name + "/" + Repeats.fileName)
            }
        }
        return Array(Set(out)).sorted()
    }

    /// Имя файла за заглушкой iCloud: «.2026-10-07.md.icloud» → «2026-10-07.md».
    static func stubbed(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"),
              name.count > ".icloud".count + 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// Заглушка, которая стоит на месте не скачанного файла.
    private static func stub(of url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    // MARK: - Перенос

    /// Перенести перечисленное из одной папки в другую.
    ///
    /// `step` зовётся после каждого файла — по нему рисуется ход.
    @discardableResult
    static func move(_ files: [String], from: URL, to: URL,
                     step: (Int) -> Void = { _ in }) -> Report {
        let fm = FileManager.default
        var moved = 0, kept = 0, failed = 0

        // Всё, что ещё в iCloud, просим скачать сразу, а не по одному: пока
        // переносится скачанное, докачивается остальное. Ждём не дольше двух
        // минут на весь перенос — без сети он не должен висеть вечно.
        for rel in files {
            let src = from.appendingPathComponent(rel)
            if !fm.fileExists(atPath: src.path), fm.fileExists(atPath: stub(of: src).path) {
                try? fm.startDownloadingUbiquitousItem(at: src)
            }
        }
        let patience = Date().addingTimeInterval(120)

        for (i, rel) in files.enumerated() {
            defer { step(i + 1) }

            let src = from.appendingPathComponent(rel)
            let dst = destination(rel, in: to)
            if !fm.fileExists(atPath: src.path) {
                // Файла нет — может быть, он ещё в iCloud: ждём, пока
                // докачается. Не дождались — файл остаётся на прежнем месте
                // и в отчёте числится неперенесённым, а не пропадает молча
                // (P426).
                guard fm.fileExists(atPath: stub(of: src).path) else { continue }
                while !fm.fileExists(atPath: src.path), Date() < patience {
                    Thread.sleep(forTimeInterval: 0.3)
                }
                guard fm.fileExists(atPath: src.path) else { failed += 1; continue }
            }

            // На новом месте за то же число лежит не скачанный из iCloud
            // файл: прочитать его нечем, писать поверх нельзя (P182).
            // Остаются оба — как с разными записями за одно число.
            if !fm.fileExists(atPath: dst.path), fm.fileExists(atPath: stub(of: dst).path) {
                kept += 1
                continue
            }

            if fm.fileExists(atPath: dst.path) {
                if same(src, dst) {
                    // Та же самая запись: перенос уже доходил сюда раньше.
                    // Лишнюю копию убираем — это и есть продолжение с места
                    // обрыва.
                    if (try? fm.removeItem(at: src)) != nil { moved += 1 } else { failed += 1 }
                } else {
                    // Разные записи за одно число. Не наше дело решать, какая
                    // из них важнее: остаются обе.
                    kept += 1
                }
                continue
            }

            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dst)
                // Удаляем исходник, только убедившись, что копия на месте
                // и целая. Иначе обрыв посреди копирования стоил бы записи.
                guard same(src, dst) else { failed += 1; continue }
                try fm.removeItem(at: src)
                moved += 1
            } catch {
                failed += 1
            }
        }

        return Report(moved: moved, kept: kept, failed: failed,
                      fromPath: from.path.removingPercentEncoding ?? from.path)
    }

    /// Куда ляжет файл в новом архиве: папка — под тем именем, какое у неё
    /// там, русским или английским (P353). Иначе «Дневник» из прежнего
    /// архива лёг бы рядом с «Diary» нового, и записей бы не было видно.
    static func destination(_ rel: String, in root: URL) -> URL {
        var parts = rel.components(separatedBy: "/")
        guard parts.count > 1, let folder = Vault.Folder.named(parts[0]) else {
            return root.appendingPathComponent(rel)
        }
        parts.removeFirst()
        return Vault.folder(folder, in: root).appendingPathComponent(parts.joined(separator: "/"))
    }

    /// Один ли это файл. Для записей сверяем побайтно: размер совпадает и у
    /// разных дней, а спутать два разных дня — худшее, что тут может быть.
    private static func same(_ a: URL, _ b: URL) -> Bool {
        guard let ka = size(a), let kb = size(b), ka == kb else { return false }
        guard a.pathExtension == "md" else { return true }
        return (try? Data(contentsOf: a)) == (try? Data(contentsOf: b))
    }

    private static func size(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}

/// Ход переноса во весь экран.
///
/// Перенос между памятью телефона и iCloud идёт минутами, и всё это время
/// записи лежат в двух местах разом. Трогать их нельзя — экран закрыт
/// нарочно, а не по бедности: это единственное место, где приложение имеет
/// право остановить человека.
struct MovingView: View {

    let progress: Transfer.Progress
    var title = T("Переношу записи", "Moving your entries")

    var body: some View {
        ZStack {
            Look.chrome.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Look.ink)

                ProgressView(value: Double(progress.done),
                             total: Double(max(progress.total, 1)))
                    .frame(width: 220)

                Text(T("\(progress.done) из \(progress.total)", "\(progress.done) of \(progress.total)"))
                    .font(Look.mono(13))
                    .foregroundStyle(Look.inkSoft)

                Text(T("Не закрывайте приложение. Если перенос всё же\nоборвётся, ничего не пропадёт: его можно продолжить.",
                        "Please keep the app open. If it is interrupted,\nnothing is lost: you can continue it."))
                    .font(Look.sans(12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Look.inkFaint)
                    .padding(.top, 4)
            }
            .padding(28)
        }
        // Пока идёт перенос, ничто под этим экраном не отзывается.
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}
