import Foundation
import HealthKit

/// Writes logged meals into Apple Health and reads active energy ("burned").
@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Nutrition types we write, mapped to the units Health expects.
    private static let nutritionUnits: [(HKQuantityTypeIdentifier, HKUnit)] = [
        (.dietaryEnergyConsumed, .kilocalorie()),
        (.dietaryProtein, .gram()),
        (.dietaryCarbohydrates, .gram()),
        (.dietaryFatTotal, .gram()),
        (.dietaryFiber, .gram()),
        (.dietarySugar, .gram()),
        (.dietarySodium, .gramUnit(with: .milli)),
    ]

    private var writeTypes: Set<HKSampleType> {
        Set(Self.nutritionUnits.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) })
    }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }
    }

    func requestAuthorization() async {
        guard isAvailable else {
            lastError = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Mirrors a logged meal into Health. Uses a per-meal sync identifier and an
    /// incrementing sync version so re-saving an edited meal *replaces* the prior
    /// samples instead of creating duplicates.
    func save(meal: Meal) async -> Bool {
        guard isAvailable else { return false }

        let values: [HKQuantityTypeIdentifier: Double] = [
            .dietaryEnergyConsumed: meal.calories,
            .dietaryProtein: meal.protein,
            .dietaryCarbohydrates: meal.carbs,
            .dietaryFatTotal: meal.fat,
            .dietaryFiber: meal.fiber,
            .dietarySugar: meal.sugar,
            .dietarySodium: meal.sodium,
        ]

        let version = meal.healthSyncVersion + 1

        var samples: [HKSample] = []
        for (identifier, unit) in Self.nutritionUnits {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let value = max(0, values[identifier] ?? 0)
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            // Stable per-meal/per-nutrient identifier + rising version => HealthKit overwrites.
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: "\(meal.id.uuidString)-\(identifier.rawValue)",
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyFoodType: meal.name,
            ]
            samples.append(HKQuantitySample(
                type: type,
                quantity: quantity,
                start: meal.createdAt,
                end: meal.createdAt,
                metadata: metadata
            ))
        }
        guard !samples.isEmpty else { return false }

        do {
            try await store.save(samples)
            meal.syncedToHealth = true
            meal.healthSyncVersion = version
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Zeroes out a meal's contribution in Apple Health by overwriting its samples
    /// with 0 (same sync identifiers, bumped version). Used when deleting an entry.
    func zeroOut(meal: Meal) async -> Bool {
        guard isAvailable, meal.syncedToHealth else { return false }

        let version = meal.healthSyncVersion + 1
        var samples: [HKSample] = []
        for (identifier, unit) in Self.nutritionUnits {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let quantity = HKQuantity(unit: unit, doubleValue: 0)
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: "\(meal.id.uuidString)-\(identifier.rawValue)",
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyFoodType: meal.name,
            ]
            samples.append(HKQuantitySample(
                type: type,
                quantity: quantity,
                start: meal.createdAt,
                end: meal.createdAt,
                metadata: metadata
            ))
        }
        guard !samples.isEmpty else { return false }

        do {
            try await store.save(samples)
            meal.healthSyncVersion = version
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Active energy burned for a given day, used for the "burned" stat.
    func activeEnergyBurned(on date: Date) async -> Double {
        guard isAvailable,
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }

        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
    }
}
