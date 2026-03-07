import Foundation

protocol LLMProvider: Sendable {
    func process(systemPrompt: String, userPrompt: String) async throws -> String
}
