import Foundation

/// Calls the Anthropic Messages API directly (no official Swift SDK exists).
/// Uses the `log_meal` tool to get structured macros alongside a friendly reply.
struct AnthropicClient: MealAnalyzing {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let tool: [String: Any] = [
        "name": MealAnalysis.toolName,
        "description": MealAnalysis.toolDescription,
        "input_schema": MealAnalysis.schema,
    ]

    func analyze(history: [ChatTurn], calorieGoal: Int, remaining: Int) async throws -> AnalysisResult {
        guard !apiKey.isEmpty else { throw LLMError.missingKey }

        let messages = history.map { turn -> [String: Any] in
            var content: [[String: Any]] = []
            if let data = turn.imageData {
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": data.base64EncodedString(),
                    ],
                ])
            }
            if !turn.text.isEmpty {
                content.append(["type": "text", "text": turn.text])
            }
            if content.isEmpty {
                content.append(["type": "text", "text": "(no message)"])
            }
            return ["role": turn.role.rawValue, "content": content]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": MealAnalysis.systemPrompt(calorieGoal: calorieGoal, remaining: remaining),
            "tools": [Self.tool],
            "messages": messages,
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, MealAnalysis.errorMessage(from: data))
        }

        return try Self.parse(data)
    }

    // MARK: - Parsing

    private static func parse(_ data: Data) throws -> AnalysisResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]]
        else { throw LLMError.decoding("Unexpected response shape") }

        var reply = ""
        var estimate: MacroEstimate?

        for block in content {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String { reply += text }
            case "tool_use":
                if (block["name"] as? String) == MealAnalysis.toolName,
                   let input = block["input"] as? [String: Any] {
                    estimate = MealAnalysis.estimate(from: input)
                }
            default:
                break
            }
        }

        reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.isEmpty {
            reply = estimate == nil ? "I'm not sure how to help with that yet." : "Logged it for you."
        }
        return AnalysisResult(reply: reply, estimate: estimate)
    }
}
