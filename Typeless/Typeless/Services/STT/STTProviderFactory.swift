import Foundation

@MainActor
enum STTProviderFactory {
    static func create(for settings: AppSettings) -> STTProvider {
        let apiKey = KeychainHelper.load(key: "stt_api_key") ?? ""
        return OpenAICompatibleSTT(
            apiKey: apiKey,
            baseURL: settings.effectiveSTTBaseURL,
            model: settings.effectiveSTTModel
        )
    }
}
