import SwiftUI

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // STT
    var sttBaseURL: String {
        didSet { defaults.set(sttBaseURL, forKey: "sttBaseURL") }
    }
    var effectiveSTTBaseURL: String { sttBaseURL.isEmpty ? AppConstants.defaultSTTBaseURL : sttBaseURL }

    var sttModel: String {
        didSet { defaults.set(sttModel, forKey: "sttModel") }
    }
    var effectiveSTTModel: String { sttModel.isEmpty ? AppConstants.defaultSTTModel : sttModel }
    var inputLanguage: String {
        didSet { defaults.set(inputLanguage, forKey: "inputLanguage") }
    }

    // LLM
    var processingMode: ProcessingMode {
        didSet { defaults.set(processingMode.rawValue, forKey: "processingMode") }
    }
    var llmBaseURL: String {
        didSet { defaults.set(llmBaseURL, forKey: "llmBaseURL") }
    }
    var effectiveLLMBaseURL: String { llmBaseURL.isEmpty ? AppConstants.defaultLLMBaseURL : llmBaseURL }

    var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "llmModel") }
    }
    var effectiveLLMModel: String { llmModel.isEmpty ? AppConstants.defaultLLMModel : llmModel }

    // Translation
    var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: "sourceLanguage") }
    }
    var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: "targetLanguage") }
    }

    // General
    var showOverlay: Bool {
        didSet { defaults.set(showOverlay, forKey: "showOverlay") }
    }
    var audioFeedback: Bool {
        didSet { defaults.set(audioFeedback, forKey: "audioFeedback") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    var selectedMicrophoneID: String {
        didSet { defaults.set(selectedMicrophoneID, forKey: "selectedMicrophoneID") }
    }
    var alwaysCopyToClipboard: Bool {
        didSet { defaults.set(alwaysCopyToClipboard, forKey: "alwaysCopyToClipboard") }
    }
    var customSystemPrompt: String {
        didSet { defaults.set(customSystemPrompt, forKey: "customSystemPrompt") }
    }
    var customTranslatePrompt: String {
        didSet { defaults.set(customTranslatePrompt, forKey: "customTranslatePrompt") }
    }
    var transcribeHotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(transcribeHotkey) {
                defaults.set(data, forKey: "transcribeHotkey")
            }
            HotkeyService.registerHotkeys()
        }
    }
    var translateHotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(translateHotkey) {
                defaults.set(data, forKey: "translateHotkey")
            }
            HotkeyService.registerHotkeys()
        }
    }

    private init() {
        let d = UserDefaults.standard

        self.sttBaseURL = d.string(forKey: "sttBaseURL") ?? ""
        self.sttModel = d.string(forKey: "sttModel") ?? ""
        self.inputLanguage = d.string(forKey: "inputLanguage") ?? "en"

        self.processingMode = ProcessingMode(rawValue: d.string(forKey: "processingMode") ?? "") ?? .reformat
        self.llmBaseURL = d.string(forKey: "llmBaseURL") ?? ""
        self.llmModel = d.string(forKey: "llmModel") ?? ""

        self.sourceLanguage = d.string(forKey: "sourceLanguage") ?? "Chinese"
        self.targetLanguage = d.string(forKey: "targetLanguage") ?? "English"

        self.showOverlay = d.object(forKey: "showOverlay") as? Bool ?? true
        self.audioFeedback = d.object(forKey: "audioFeedback") as? Bool ?? true
        self.hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        self.launchAtLogin = d.bool(forKey: "launchAtLogin")
        self.selectedMicrophoneID = d.string(forKey: "selectedMicrophoneID") ?? ""
        self.alwaysCopyToClipboard = d.object(forKey: "alwaysCopyToClipboard") as? Bool ?? false
        self.customSystemPrompt = d.string(forKey: "customSystemPrompt") ?? ""
        self.customTranslatePrompt = d.string(forKey: "customTranslatePrompt") ?? ""

        if let data = d.data(forKey: "transcribeHotkey"),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.transcribeHotkey = hotkey
        } else {
            self.transcribeHotkey = .defaultTranscribe
        }
        if let data = d.data(forKey: "translateHotkey"),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.translateHotkey = hotkey
        } else {
            self.translateHotkey = .defaultTranslate
        }
    }
}
