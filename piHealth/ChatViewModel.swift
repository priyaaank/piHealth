import Foundation
import SwiftData
import SwiftUI

/// Drives a chat turn: persists messages, calls the LLM, logs the meal, syncs Health.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var isThinking = false
    @Published var errorMessage: String?

    private let context: ModelContext
    private let settings: SettingsStore
    private let health: HealthKitManager

    init(context: ModelContext, settings: SettingsStore, health: HealthKitManager) {
        self.context = context
        self.settings = settings
        self.health = health
    }

    /// Persists edits to a recorded meal. Only re-syncs Health if the meal was
    /// already added there (we never sync silently — see `syncToHealth`).
    func resync(meal: Meal) async {
        try? context.save()
        if meal.syncedToHealth, health.isAuthorized {
            _ = await health.save(meal: meal)
            try? context.save()
        }
        upsertTemplate(from: meal)
    }

    /// Explicit user action: mirror this meal into Apple Health.
    func syncToHealth(meal: Meal) async {
        guard health.isAuthorized else {
            errorMessage = "Connect Apple Health in Settings to sync this meal."
            return
        }
        _ = await health.save(meal: meal)
        try? context.save()
    }

    /// Deletes a logged meal: zeroes its macros in Apple Health (if it was synced),
    /// then removes it from the local store.
    func delete(meal: Meal) async {
        if meal.syncedToHealth, health.isAuthorized {
            _ = await health.zeroOut(meal: meal)
        }
        // Detach from any chat message so the card disappears, then delete.
        let descriptor = FetchDescriptor<ChatMessage>()
        if let messages = try? context.fetch(descriptor) {
            for message in messages where message.meal?.id == meal.id {
                message.meal = nil
            }
        }
        context.delete(meal)
        try? context.save()
    }

    /// One-tap log of a frequently used food — reuses its cached macros, no LLM call.
    func quickAdd(template: FoodTemplate) {
        let meal = Meal(template: template)
        context.insert(meal)
        template.useCount += 1
        template.lastUsedAt = meal.createdAt

        let reply = "Added \(template.name) — about \(Int(template.calories)) kcal, from your favorites. Tap “Add to Apple Health” to sync it."
        let assistant = ChatMessage(role: .assistant, text: reply, meal: meal)
        context.insert(assistant)
        try? context.save()
    }

    /// Records or refreshes a food template so it can be quick-added later.
    private func upsertTemplate(from meal: Meal) {
        let key = FoodTemplate.key(for: meal.name)
        guard !key.isEmpty else { return }
        var descriptor = FetchDescriptor<FoodTemplate>(predicate: #Predicate { $0.nameKey == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.useCount += 1
            existing.lastUsedAt = Date()
            existing.refresh(from: meal)
        } else {
            context.insert(FoodTemplate(meal: meal))
        }
        try? context.save()
    }

    /// Calories consumed today (from locally logged meals).
    func consumedToday(_ meals: [Meal]) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return Int(meals
            .filter { Calendar.current.startOfDay(for: $0.createdAt) == today }
            .reduce(0) { $0 + $1.calories })
    }

    func send(text: String, image: UIImage?, history: [ChatMessage], meals: [Meal]) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = image?.jpegData(compressionQuality: 0.7)
        guard !trimmed.isEmpty || imageData != nil else { return }

        guard settings.isConfigured else {
            errorMessage = LLMError.missingKey.errorDescription
            return
        }

        // Persist the user's turn immediately.
        let userMessage = ChatMessage(role: .user, text: trimmed, imageData: imageData)
        context.insert(userMessage)
        try? context.save()

        isThinking = true
        errorMessage = nil
        defer { isThinking = false }

        // Build context from recent history (cap to keep requests small).
        var turns = history.suffix(10).map {
            ChatTurn(role: $0.role, text: $0.text, imageData: nil)
        }
        turns.append(ChatTurn(role: .user, text: trimmed, imageData: imageData))

        let consumed = consumedToday(meals)
        let remaining = max(0, settings.calorieGoal - consumed)

        let client = settings.makeAnalyzer()
        do {
            let result = try await client.analyze(
                history: turns,
                calorieGoal: settings.calorieGoal,
                remaining: remaining
            )

            var loggedMeal: Meal?
            if let estimate = result.estimate {
                let meal = Meal(estimate: estimate)
                context.insert(meal)
                loggedMeal = meal
            }

            let assistant = ChatMessage(role: .assistant, text: result.reply, meal: loggedMeal)
            context.insert(assistant)
            try? context.save()

            // Don't sync to Health automatically — the user reviews/edits the macro
            // card and taps "Add to Apple Health". Record it as a reusable template now.
            if let meal = loggedMeal {
                upsertTemplate(from: meal)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
