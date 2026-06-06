import Foundation
import SwiftUI

/// App configuration: the active LLM provider, a key + model per provider, and the daily calorie goal.
/// Both providers are configured in parallel; `provider` selects which one analyzes meals.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let provider = "llm.provider"
        static let anthropicModel = "llm.model.anthropic"
        static let openAIModel = "llm.model.openai"
        static let calorieGoal = "calorie.goal"
    }

    @Published var provider: LLMProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published var anthropicKey: String {
        didSet { KeychainHelper.set(anthropicKey, account: LLMProvider.anthropic.keychainAccount) }
    }

    @Published var openAIKey: String {
        didSet { KeychainHelper.set(openAIKey, account: LLMProvider.openai.keychainAccount) }
    }

    @Published var anthropicModel: String {
        didSet { UserDefaults.standard.set(anthropicModel, forKey: Keys.anthropicModel) }
    }

    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }

    @Published var calorieGoal: Int {
        didSet { UserDefaults.standard.set(calorieGoal, forKey: Keys.calorieGoal) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.provider = LLMProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .anthropic
        self.anthropicKey = KeychainHelper.get(account: LLMProvider.anthropic.keychainAccount) ?? ""
        self.openAIKey = KeychainHelper.get(account: LLMProvider.openai.keychainAccount) ?? ""
        self.anthropicModel = defaults.string(forKey: Keys.anthropicModel) ?? LLMProvider.anthropic.defaultModel
        self.openAIModel = defaults.string(forKey: Keys.openAIModel) ?? LLMProvider.openai.defaultModel
        let savedGoal = defaults.integer(forKey: Keys.calorieGoal)
        self.calorieGoal = savedGoal == 0 ? 2350 : savedGoal
    }

    // MARK: - Active provider accessors

    func key(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic: return anthropicKey
        case .openai: return openAIKey
        }
    }

    func setKey(_ value: String, for provider: LLMProvider) {
        switch provider {
        case .anthropic: anthropicKey = value
        case .openai: openAIKey = value
        }
    }

    func model(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic: return anthropicModel
        case .openai: return openAIModel
        }
    }

    func bindingForModel(_ provider: LLMProvider) -> Binding<String> {
        switch provider {
        case .anthropic: return Binding(get: { self.anthropicModel }, set: { self.anthropicModel = $0 })
        case .openai: return Binding(get: { self.openAIModel }, set: { self.openAIModel = $0 })
        }
    }

    /// Whether the currently selected provider has a usable key.
    var isConfigured: Bool {
        !key(for: provider).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Builds the analyzer for the active provider.
    func makeAnalyzer() -> MealAnalyzing {
        let apiKey = key(for: provider)
        let modelID = model(for: provider)
        switch provider {
        case .anthropic: return AnthropicClient(apiKey: apiKey, model: modelID)
        case .openai: return OpenAIClient(apiKey: apiKey, model: modelID)
        }
    }
}
