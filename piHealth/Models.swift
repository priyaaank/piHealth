import Foundation
import SwiftData

/// Which meal a logged item belongs to.
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks
    var id: String { rawValue }
    var display: String { rawValue.capitalized }
}

/// A logged meal — the local source of truth, mirrored into Apple Health.
@Model
final class Meal: Identifiable {
    var id: UUID
    var createdAt: Date
    var name: String
    var mealTypeRaw: String

    var calories: Double
    var protein: Double      // grams
    var carbs: Double        // grams
    var fat: Double          // grams
    var fiber: Double        // grams
    var sugar: Double        // grams
    var sodium: Double       // milligrams

    var detail: String       // e.g. "Bread, Milk Tea, Egg, ..."
    var syncedToHealth: Bool
    /// Bumped on every Health write so edits replace prior samples (HKMetadataKeySyncVersion).
    /// Default enables lightweight SwiftData migration for stores created before this field existed.
    var healthSyncVersion: Int = 0

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snacks }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(estimate: MacroEstimate, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.name = estimate.name
        self.mealTypeRaw = (estimate.mealType ?? .snacks).rawValue
        self.calories = estimate.calories
        self.protein = estimate.proteinG
        self.carbs = estimate.carbsG
        self.fat = estimate.fatG
        self.fiber = estimate.fiberG
        self.sugar = estimate.sugarG
        self.sodium = estimate.sodiumMg
        self.detail = estimate.items.map(\.name).joined(separator: ", ")
        self.syncedToHealth = false
        self.healthSyncVersion = 0
    }

    /// Builds a fresh meal from a saved template — reuses cached macros, no LLM call.
    init(template: FoodTemplate, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.name = template.name
        self.mealTypeRaw = template.mealTypeRaw
        self.calories = template.calories
        self.protein = template.protein
        self.carbs = template.carbs
        self.fat = template.fat
        self.fiber = template.fiber
        self.sugar = template.sugar
        self.sodium = template.sodium
        self.detail = template.detail
        self.syncedToHealth = false
        self.healthSyncVersion = 0
    }
}

/// A reusable food the user logs often. Lets them re-add a meal with one tap,
/// reusing the LLM's prior macro estimate instead of paying for another analysis.
/// Upserted (keyed by `nameKey`) every time a meal is logged; ranked by `useCount`.
@Model
final class FoodTemplate: Identifiable {
    var id: UUID
    /// Lowercased, trimmed name used to match/dedupe templates.
    var nameKey: String
    var name: String
    var mealTypeRaw: String

    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var sodium: Double
    var detail: String

    var useCount: Int
    var lastUsedAt: Date

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snacks }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(meal: Meal) {
        self.id = UUID()
        self.nameKey = Self.key(for: meal.name)
        self.name = meal.name
        self.mealTypeRaw = meal.mealTypeRaw
        self.calories = meal.calories
        self.protein = meal.protein
        self.carbs = meal.carbs
        self.fat = meal.fat
        self.fiber = meal.fiber
        self.sugar = meal.sugar
        self.sodium = meal.sodium
        self.detail = meal.detail
        self.useCount = 1
        self.lastUsedAt = meal.createdAt
    }

    /// Refresh the cached macros to the most recent logged values for this food.
    func refresh(from meal: Meal) {
        self.name = meal.name
        self.mealTypeRaw = meal.mealTypeRaw
        self.calories = meal.calories
        self.protein = meal.protein
        self.carbs = meal.carbs
        self.fat = meal.fat
        self.fiber = meal.fiber
        self.sugar = meal.sugar
        self.sodium = meal.sodium
        self.detail = meal.detail
    }

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A single chat turn. An assistant turn may carry a logged `meal` to render the macro card.
@Model
final class ChatMessage {
    var id: UUID
    var createdAt: Date
    var roleRaw: String
    var text: String
    var imageData: Data?
    @Relationship(deleteRule: .nullify) var meal: Meal?

    enum Role: String { case user, assistant }

    var role: Role {
        get { Role(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    init(role: Role, text: String, imageData: Data? = nil, meal: Meal? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.roleRaw = role.rawValue
        self.text = text
        self.imageData = imageData
        self.meal = meal
    }
}

/// Structured macro estimate returned by the LLM via the `log_meal` tool.
struct MacroEstimate: Codable, Equatable {
    struct Item: Codable, Equatable {
        var name: String
        var calories: Double?
    }

    var name: String
    var mealType: MealType?
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var sugarG: Double
    var sodiumMg: Double
    var items: [Item]
}
