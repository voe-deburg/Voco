import Foundation

enum AppConstants {
    static let bundleID = "com.voco.app"
    static let appName = "Voco"
    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Voco/Models", isDirectory: true)
    }()
    static let defaultWhisperModel = "openai_whisper-base"
    static let clipboardRestoreDelay: TimeInterval = 0.2
    static let overlayFadeDuration: TimeInterval = 2.0
    static let sampleRate: Double = 16000
    static let audioChannels: UInt32 = 1

    // Default STT endpoint (DashScope Qwen ASR)
    static let defaultSTTBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    static let defaultSTTModel = "qwen3-asr-flash"

    // Default LLM endpoint (OpenAI)
    static let defaultLLMBaseURL = "https://api.openai.com/v1"
    static let defaultLLMModel = "gpt-4o-mini"
}
