import Foundation

/// Which LLM backend analyzes meals. Both are configured in parallel; the user picks the active one.
enum LLMProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-…"
        }
    }

    var consoleHint: String {
        switch self {
        case .anthropic: return "Get a key at console.anthropic.com."
        case .openai: return "Get a key at platform.openai.com."
        }
    }

    /// Keychain account used to store this provider's key.
    var keychainAccount: String {
        switch self {
        case .anthropic: return "anthropic.apiKey"
        case .openai: return "openai.apiKey"
        }
    }

    var models: [LLMModel] {
        switch self {
        case .anthropic:
            return [
                LLMModel(id: "claude-haiku-4-5", label: "Claude Haiku 4.5 (fast, cheapest)"),
                LLMModel(id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6 (balanced)"),
                LLMModel(id: "claude-opus-4-8", label: "Claude Opus 4.8 (best)"),
            ]
        case .openai:
            return [
                LLMModel(id: "gpt-4o", label: "GPT-4o (best)"),
                LLMModel(id: "gpt-4o-mini", label: "GPT-4o mini (fast)"),
                LLMModel(id: "gpt-4.1", label: "GPT-4.1"),
            ]
        }
    }

    var defaultModel: String { models[0].id }
}

/// A selectable model within a provider. Vision-capable models can analyze food photos.
struct LLMModel: Identifiable, Hashable {
    let id: String      // API model id
    let label: String
}

/// One prior turn of context to send to the model.
struct ChatTurn {
    let role: ChatMessage.Role
    let text: String
    let imageData: Data?
}

/// The unified output of a meal analysis, regardless of provider.
struct AnalysisResult {
    var reply: String
    var estimate: MacroEstimate?
}

enum LLMError: LocalizedError {
    case missingKey
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add an API key for the selected provider in Settings to start logging meals."
        case .http(let code, let message):
            return "Request failed (\(code)): \(message)"
        case .decoding(let message):
            return "Couldn't read the response: \(message)"
        case .network(let message):
            return message
        }
    }
}

/// Common interface so the chat flow is provider-agnostic.
protocol MealAnalyzing {
    func analyze(history: [ChatTurn], calorieGoal: Int, remaining: Int) async throws -> AnalysisResult
}

/// Shared system prompt and JSON schema for the `log_meal` function/tool.
/// The schema body is identical across providers — only the request envelope differs.
enum MealAnalysis {
    static let toolName = "log_meal"
    static let toolDescription = "Record the estimated nutrition for a meal the user ate."

    static func systemPrompt(calorieGoal: Int, remaining: Int) -> String {
        """
        You are a warm, encouraging nutrition assistant inside an iOS app.
        The user describes a meal in text and/or sends a food photo. Your job:

        1. Identify the foods and estimate their nutrition as best you can.
        2. ALWAYS call the `log_meal` function with your best total estimate for the meal \
        (calories, protein, carbs, fat, fiber, sugar, sodium) plus a breakdown of items.
        3. In your text reply, briefly list what you estimated (one short line per item with \
        its calories), then add one encouraging, specific sentence of nutrition guidance.

        Keep the text reply concise and friendly — no markdown headers, no preamble like \
        "Here is". Today the user's calorie goal is \(calorieGoal) kcal and they have about \
        \(remaining) kcal remaining. If the user just chats and there is no food to log, \
        reply helpfully and do NOT call the function.
        """
    }

    /// JSON Schema describing the meal estimate. Reused as Anthropic `input_schema`
    /// and OpenAI function `parameters`.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string", "description": "Short name for the meal, e.g. 'Toast & eggs'"],
            "meal_type": [
                "type": "string",
                "enum": ["breakfast", "lunch", "dinner", "snacks"],
                "description": "Which meal this is. Infer from the food and time of day.",
            ],
            "calories": ["type": "number", "description": "Total kilocalories"],
            "protein_g": ["type": "number"],
            "carbs_g": ["type": "number"],
            "fat_g": ["type": "number"],
            "fiber_g": ["type": "number"],
            "sugar_g": ["type": "number"],
            "sodium_mg": ["type": "number"],
            "items": [
                "type": "array",
                "description": "Individual foods in the meal.",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "calories": ["type": "number"],
                    ],
                    "required": ["name"],
                ],
            ],
        ],
        "required": ["name", "calories", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg", "items"],
    ]

    /// Builds a `MacroEstimate` from the function/tool arguments dictionary.
    static func estimate(from input: [String: Any]) -> MacroEstimate {
        func num(_ key: String) -> Double {
            if let d = input[key] as? Double { return d }
            if let i = input[key] as? Int { return Double(i) }
            if let s = input[key] as? String { return Double(s) ?? 0 }
            return 0
        }
        let items = (input["items"] as? [[String: Any]] ?? []).map { dict in
            MacroEstimate.Item(
                name: dict["name"] as? String ?? "Item",
                calories: (dict["calories"] as? Double) ?? (dict["calories"] as? Int).map(Double.init)
            )
        }
        return MacroEstimate(
            name: input["name"] as? String ?? "Meal",
            mealType: (input["meal_type"] as? String).flatMap(MealType.init),
            calories: num("calories"),
            proteinG: num("protein_g"),
            carbsG: num("carbs_g"),
            fatG: num("fat_g"),
            fiberG: num("fiber_g"),
            sugarG: num("sugar_g"),
            sodiumMg: num("sodium_mg"),
            items: items
        )
    }

    /// Extracts the API error message from a provider error body.
    static func errorMessage(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
