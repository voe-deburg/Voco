import Foundation

@MainActor
enum LLMProviderFactory {
    static func create(for settings: AppSettings) -> LLMProvider {
        let apiKey = KeychainHelper.load(key: "llm_api_key") ?? ""
        return OpenAICompatibleLLM(
            apiKey: apiKey,
            baseURL: settings.effectiveLLMBaseURL,
            model: settings.effectiveLLMModel
        )
    }
}
