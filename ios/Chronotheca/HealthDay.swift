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
                                      options: .cumulativeSum) { _, stats, _ in
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
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, found, _ in
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
