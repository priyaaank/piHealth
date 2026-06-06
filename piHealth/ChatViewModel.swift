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

    /// Persists edits to a recorded meal and re-syncs the updated values to Apple Health.
    func resync(meal: Meal) async {
        try? context.save()
        if health.isAuthorized {
            _ = await health.save(meal: meal)
            try? context.save()
        }
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

            // Mirror to Apple Health.
            if let meal = loggedMeal, health.isAuthorized {
                _ = await health.save(meal: meal)
                try? context.save()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
