import SwiftUI
import SwiftData

@main
struct PiHealthApp: App {
    /// Shared SwiftData container — local source of truth for chat + meals.
    let container: ModelContainer

    @StateObject private var settings = SettingsStore()
    @StateObject private var health = HealthKitManager()

    init() {
        do {
            container = try ModelContainer(for: Meal.self, ChatMessage.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(settings)
                .environmentObject(health)
                .tint(Theme.coral)
        }
        .modelContainer(container)
    }
}
