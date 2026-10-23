import Foundation
import HealthKit

/// День из «Здоровья» (P378): шаги, сон, тренировки — строкой в шапке
/// дневника. Данные остаются в «Здоровье»; в запись дня строка ложится
/// только касанием по ней. Включается в настройках — тогда же iPhone
/// спрашивает разрешение; приложение ничего в «Здоровье» не пишет.
enum HealthDay {

    static let key = "prefs.health"
    static let store = HKHealthStore()

    static var on: Bool { UserDefaults.standard.bool(forKey: key) }
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var types: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
    }

    /// Спросить разрешение читать. `done` — на главном потоке; `false` —
    /// iPhone отказал (или у приложения нет права на «Здоровье»).
    static func ask(_ done: @escaping (Bool) -> Void) {
        guard available else { return done(false) }
        store.requestAuthorization(toShare: [], read: types) { ok, _ in
            DispatchQueue.main.async {
                changed()
                done(ok)
            }
        }
    }

    /// Включили, выключили или разрешили — открытая страница считает строку
    /// заново (P443). Прежде строка считалась один раз при открытии дня, и
    /// если разрешения тогда ещё не было, оставалась пустой.
    static let note = Notification.Name("HealthDay.changed")

    static func changed() {
        Task { @MainActor in
            cache.removeAll()
            NotificationCenter.default.post(name: note, object: nil)
        }
    }

    /// Ответы «Здоровья» с ошибкой — для строки в настройках (P604). Пишутся
    /// сразу, под замком (P606): прежде — отложенно, и проверка успевала
    /// прочитать пустое раньше, чем ответ iPhone доходил до неё.
    private static let errorsLock = NSLock()
    private static var errors: [String] = []

    private static func remember(_ error: Error?) {
        guard let error else { return }
        let e = error as NSError
        let text = "\(e.code): \(e.localizedDescription)"
        errorsLock.lock()
        if !errors.contains(text) { errors.append(text) }
        errorsLock.unlock()
    }

    private static func takeErrors() -> String? {
        errorsLock.lock()
        defer { errors = []; errorsLock.unlock() }
        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    /// Сколько записей шагов «Здоровье» показывает приложению за месяц —
    /// без подсчёта сумм (P606): видно, отдаёт ли оно вообще хоть что-то.
    private static func stepSamples() async -> Int {
        let cal = Calendar.current
        let month = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return await withCheckedContinuation { done in
            let q = HKSampleQuery(sampleType: HKQuantityType(.stepCount),
                                  predicate: HKQuery.predicateForSamples(withStart: month, end: Date()),
                                  limit: 50, sortDescriptors: nil) { _, found, error in
                remember(error)
                done.resume(returning: found?.count ?? 0)
            }
            store.execute(q)
        }
    }

    /// Спрашивал ли iPhone разрешение (P606): «unnecessary» — уже спрашивал.
    private static func requestStatus() async -> String {
        await withCheckedContinuation { done in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, error in
                remember(error)
                switch status {
                case .unnecessary: done.resume(returning: "asked")
                case .shouldRequest: done.resume(returning: "not asked")
                default: done.resume(returning: "unknown")
                }
            }
        }
    }

    /// Что «Здоровье» отдаёт за сегодня — строкой для настроек (P604).
    @MainActor
    static func todayCheck() async -> String {
        _ = takeErrors()
        cache.removeAll()
        if let line = await summary(for: Date()) { return T("Сегодня: ", "Today: ") + line }
        let samples = await stepSamples()
        let asked = await requestStatus()
        // Служебная приписка для разбора — без перевода (P606).
        let why = " [\(asked), \(samples)" + (takeErrors().map { "; " + $0 } ?? "") + "]"
        // Сразу после полуночи за сегодня может ещё ничего не быть — смотрим
        // и неделю назад (P605): пусто и там — iPhone не отдаёт приложению
        // ничего, то есть чтение «Здоровья» ему не разрешено.
        let cal = Calendar.current
        let week = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date())) ?? Date()
        if let steps = await stepsSum(week, Date()), steps > 0 {
            return T("Сегодня из «Здоровья» ничего не пришло", "Nothing came from Health today") + why
                + T(". За неделю шагов: \(steps) — доступ есть.", ". Steps this week: \(steps) — access works.")
        }
        return T("Из «Здоровья» не пришло ничего и за неделю — iPhone не даёт приложению читать шаги.",
                 "Nothing came from Health for the whole week — iPhone does not let the app read steps.") + why
    }

    /// Прошедшие дни не меняются — их строка запоминается.
    @MainActor private static var cache: [String: String] = [:]

    /// «шаги 8 412 · сон 7 ч 10 мин · тренировки 45 мин» или `nil`.
    @MainActor
    static func summary(for day: Date) async -> String? {
        guard on, available, !Vault.isPreview else { return nil }
        let stamp = Vault.stamp(day)
        if let known = cache[stamp] { return known.isEmpty ? nil : known }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }

        let steps = await stepsSum(start, end)
        let sleep = await sleepSeconds(cal.date(byAdding: .hour, value: -6, to: start) ?? start,
                                       cal.date(byAdding: .hour, value: 14, to: start) ?? end)
        let workout = await workoutSeconds(start, end)

        var parts: [String] = []
        if let steps, steps > 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = Lang.locale
            parts.append(T("шаги ", "steps ") + (f.string(from: NSNumber(value: steps)) ?? "\(steps)"))
        }
        if sleep >= 30 * 60 { parts.append(T("сон ", "sleep ") + span(sleep)) }
        if workout >= 60 { parts.append(T("тренировки ", "workouts ") + span(workout)) }
        let text = parts.joined(separator: " · ")
        // Пустое не запоминается: шагов могло не быть потому, что ещё не
        // было разрешения (P443).
        if start < cal.startOfDay(for: Date()), !text.isEmpty { cache[stamp] = text }
        return text.isEmpty ? nil : text
    }

    /// «7 ч 10 мин», «45 мин».
    static func span(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60) % 60
        let h = Int(seconds / 3600)
        if h == 0 { return T("\(m) мин", "\(m) min") }
        return m == 0 ? T("\(h) ч", "\(h) h") : T("\(h) ч \(m) мин", "\(h) h \(m) min")
    }

    // MARK: - Вопросы к «Здоровью»

    private static func stepsSum(_ start: Date, _ end: Date) async -> Int? {
        await withCheckedContinuation { done in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount),
                                      quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      options: .cumulativeSum) { _, stats, error in
                // «Нет данных» — не беда: шагов могло не быть.
                remember(error)
                let n = stats?.sumQuantity()?.doubleValue(for: .count())
                done.resume(returning: n.map { Int($0.rounded()) })
            }
            store.execute(q)
        }
    }

    /// Сон, закончившийся в это утро: часы и iPhone пишут одно и то же
    /// по-своему — промежутки сливаются, а не складываются.
    private static func sleepSeconds(_ start: Date, _ end: Date) async -> TimeInterval {
        let samples: [HKCategorySample] = await withCheckedContinuation { done in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, found, error in
                remember(error)
                done.resume(returning: (found as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let spans = samples.filter { asleep.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        return merged(spans)
    }

    private static func workoutSeconds(_ start: Date, _ end: Date) async -> TimeInterval {
        let found: [HKWorkout] = await withCheckedContinuation { done in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, got, _ in
                done.resume(returning: (got as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return merged(found.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 })
    }

    /// Сумма промежутков без двойного счёта перекрытий.
    static func merged(_ spans: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for s in spans {
            if let c = current, s.0 <= c.1 {
                current = (c.0, max(c.1, s.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = s
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }
}
