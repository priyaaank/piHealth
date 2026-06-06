import Foundation

/// Calls the OpenAI Chat Completions API directly. Uses function calling
/// (`log_meal`) to get structured macros alongside a friendly reply, and
/// sends food photos as base64 image_url content (vision models).
struct OpenAIClient: MealAnalyzing {
    let apiKey: String
    let model: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static let tool: [String: Any] = [
        "type": "function",
        "function": [
            "name": MealAnalysis.toolName,
            "description": MealAnalysis.toolDescription,
            "parameters": MealAnalysis.schema,
        ],
    ]

    func analyze(history: [ChatTurn], calorieGoal: Int, remaining: Int) async throws -> AnalysisResult {
        guard !apiKey.isEmpty else { throw LLMError.missingKey }

        var messages: [[String: Any]] = [
            ["role": "system", "content": MealAnalysis.systemPrompt(calorieGoal: calorieGoal, remaining: remaining)],
        ]

        for turn in history {
            // A turn with an image needs the structured content-parts form; plain text can be a string.
            if let data = turn.imageData {
                var parts: [[String: Any]] = [[
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"],
                ]]
                if !turn.text.isEmpty {
                    parts.insert(["type": "text", "text": turn.text], at: 0)
                }
                messages.append(["role": turn.role.rawValue, "content": parts])
            } else {
                messages.append(["role": turn.role.rawValue, "content": turn.text.isEmpty ? "(no message)" : turn.text])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": messages,
            "tools": [Self.tool],
            "tool_choice": "auto",
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw LLMError.decoding("Unexpected response shape") }

        var reply = (message["content"] as? String) ?? ""
        var estimate: MacroEstimate?

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let function = call["function"] as? [String: Any],
                      (function["name"] as? String) == MealAnalysis.toolName,
                      let argString = function["arguments"] as? String,
                      let argData = argString.data(using: .utf8),
                      let input = try? JSONSerialization.jsonObject(with: argData) as? [String: Any]
                else { continue }
                estimate = MealAnalysis.estimate(from: input)
            }
        }

        reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.isEmpty {
            reply = estimate == nil ? "I'm not sure how to help with that yet." : "Logged it for you."
        }
        return AnalysisResult(reply: reply, estimate: estimate)
    }
}
