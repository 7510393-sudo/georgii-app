import SwiftUI

/// Листки и окна поверх «Дня» (P963, `docs/68` §2.2): настройки за уголок,
/// «На другой день», неделя, файл, выбор папки, приветствие пробы, окно
/// «Время» и снимок во весь экран.
///
/// Прежде эти поля лежали в `Shell`, и каждое открытие листка пересчитывало
/// всё, что смотрит на оболочку, — и страницу «Дня», и картотеку. Теперь их
/// смотрят только оболочка экрана (`RootView`), уголок листка (`Sticker`) и
/// показ голосовой записи (`VoiceShown`). В файл ничего не пишется.
final class Overlays: ObservableObject {

    /// Дело, которому выбирают время, напоминание и повтор (P872).
    @Published var roller: Roller?

    struct Roller: Identifiable {
        let id: UUID
    }

    /// Снимок, открытый во весь экран: который по счёту в ряду внизу
    /// страницы (ряд один и лежит в файле дневника, P961); `-1` — не из ряда.
    struct OpenedPhoto: Identifiable {
        let index: Int
        /// Снимок, стоящий посреди страницы, а не в полоске: открывается
        /// прямо по месту, без «убрать» (P205).
        var url: URL? = nil
        /// Строка-ссылка снимка из текста: по ней он возвращается в
        /// полоску (P216).
        var link: String? = nil
        var id: String { String(index) + (url?.path ?? "") }
    }
    @Published var openedPhoto: OpenedPhoto?

    /// Показать приветствие первого запуска для пробы (P452).
    @Published var trialWelcome = false

    /// Листок настроек вытянут за уголок.
    @Published var showingSettings = false
    /// Дело отвели вправо — листок «На другой день» (P383, P387).
    @Published var movingTask: MovingTask?
    /// Бумажку тянут за уголок: сколько её ещё за краем, 1 — вся, 0 — на
    /// месте. Пусто — никто не тянет (P233).
    @Published var settingsPull: CGFloat?

    /// Вытянуть листок за уголок до конца: он стоит за краем экрана так,
    /// что наружу торчит только его угол, и съезжает вниз целиком (P237).
    func pullOut() {
        // Толчок — сразу по нажатию, не когда бумажка уже легла на место:
        // рука должна почувствовать отклик в момент касания (P320).
        Feel.paper()
        let built = showingSettings
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            showingSettings = true
            settingsPull = settingsPull ?? 1
        }
        if built {
            // Листок уже тянули пальцем — он построен, ехать сразу.
            DispatchQueue.main.async { withAnimation(.pull) { self.settingsPull = nil } }
        } else {
            // Ход — когда листок построен (P669): прежде он начинался сразу,
            // первые кадры уходили на постройку листка, и он выпрыгивал
            // рывком. Подстраховка — если листок не скажет, что появился.
            pullPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.startPull() }
        }
    }

    /// Листок ждёт своего первого кадра, чтобы поехать (P669).
    private var pullPending = false

    /// Листок появился — ехать.
    func startPull() {
        guard pullPending else { return }
        pullPending = false
        DispatchQueue.main.async { withAnimation(.pull) { self.settingsPull = nil } }
    }

    /// Задвинуть листок обратно: он уезжает вверх, пока снова не останется
    /// один уголок.
    func tuckIn() {
        // Толчок — в момент нажатия, как при выезде, а не когда листок уже
        // ушёл (P515).
        Feel.paper()
        withAnimation(.tuck) { settingsPull = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                self.showingSettings = false
                self.settingsPull = nil
            }
        }
    }

    /// Листок «Файл»: вывоз дня, PDF, корзина.
    @Published var showingFile = false
    /// Неделя одним взглядом (P466).
    @Published var showingWeek = false
    /// Выбор папки записей.
    @Published var picking = false
}
