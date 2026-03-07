import Foundation

final class OpenAICompatibleLLM: LLMProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func process(systemPrompt: String, userPrompt: String) async throws -> String {
        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw LLMError.apiError("Invalid LLM base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_completion_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            var errorMessage = "HTTP \(statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            } else if let text = String(data: data, encoding: .utf8) {
                errorMessage = text
            }
            throw LLMError.apiError(errorMessage)
        }

        let json = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let output = (json.choices.first?.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Strict mode guard (from VoiceInk): reject if the LLM added commentary
        // instead of cleaning up the transcription
        if StrictModeGuard.isInvalid(input: userPrompt, output: output) {
            return userPrompt
        }

        return output
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

enum LLMError: Error, LocalizedError {
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "LLM API error: \(msg)"
        case .emptyResponse: return "LLM returned empty response"
        }
    }
}
