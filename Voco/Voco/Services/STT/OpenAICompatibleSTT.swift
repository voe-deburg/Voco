import Foundation

/// STT provider that sends audio via the chat completions endpoint.
/// Supports DashScope Qwen ASR (audio as base64 in message content)
/// and standard OpenAI-compatible /audio/transcriptions endpoints.
final class OpenAICompatibleSTT: STTProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func transcribe(audioData: Data, language: String?) async throws -> TranscriptionResult {
        // Qwen ASR models use chat completions with audio content
        if model.contains("qwen") && model.contains("asr") {
            return try await transcribeViaChatCompletions(audioData: audioData, language: language)
        }
        // Standard Whisper-style /audio/transcriptions
        return try await transcribeViaWhisperEndpoint(audioData: audioData, language: language)
    }

    // MARK: - DashScope Qwen ASR (chat completions with audio)

    private func transcribeViaChatCompletions(audioData: Data, language: String?) async throws -> TranscriptionResult {
        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw STTError.apiError("Invalid STT base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let base64Audio = "data:audio/wav;base64," + audioData.base64EncodedString()

        var body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": base64Audio
                            ]
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]

        // Add ASR options
        var asrOptions: [String: Any] = ["enable_itn": true]
        if let language {
            asrOptions["language"] = language
        }
        body["asr_options"] = asrOptions

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[Voco] STT request: \(endpoint) model=\(model) (chat completions)")
        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[Voco] STT response: HTTP \(statusCode), \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("[Voco] STT error body: \(responseBody)")
            throw STTError.apiError(parseError(data: data, statusCode: statusCode))
        }

        let json = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = json.choices.first?.message.content, !content.isEmpty else {
            throw STTError.recognitionFailed("Empty transcription result")
        }

        return TranscriptionResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            confidence: nil,
            segments: nil
        )
    }

    // MARK: - Standard Whisper-style endpoint

    private func transcribeViaWhisperEndpoint(audioData: Data, language: String?) async throws -> TranscriptionResult {
        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)audio/transcriptions"
            : "\(baseURL)/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw STTError.apiError("Invalid STT base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("model", value: model)
        appendField("response_format", value: "verbose_json")

        if let language {
            appendField("language", value: language)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        print("[Voco] STT request: \(endpoint) model=\(model) (whisper)")
        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[Voco] STT response: HTTP \(statusCode), \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("[Voco] STT error body: \(responseBody)")
            throw STTError.apiError(parseError(data: data, statusCode: statusCode))
        }

        let json = try JSONDecoder().decode(WhisperResponse.self, from: data)

        return TranscriptionResult(
            text: json.text,
            language: json.language,
            confidence: nil,
            segments: json.segments?.map { seg in
                TranscriptionResult.Segment(text: seg.text, start: seg.start, end: seg.end)
            }
        )
    }

    // MARK: - Helpers

    private func parseError(data: Data, statusCode: Int) -> String {
        var errorMessage = "HTTP \(statusCode)"
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            } else if let message = json["message"] as? String {
                errorMessage = message
            }
        } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            errorMessage = text
        }
        return errorMessage
    }
}

// MARK: - Response Types

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct WhisperResponse: Decodable {
    let text: String
    let language: String?
    let segments: [WhisperSegment]?
}

private struct WhisperSegment: Decodable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

enum STTError: Error, LocalizedError {
    case apiError(String)
    case noAudioData
    case modelNotLoaded
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "STT API error: \(msg)"
        case .noAudioData: return "No audio data to transcribe"
        case .modelNotLoaded: return "STT model not loaded"
        case .recognitionFailed(let msg): return "Recognition failed: \(msg)"
        }
    }
}
