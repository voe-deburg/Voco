import SwiftUI
import AppKit

// MARK: - Prompt file helper

@MainActor
final class PromptFileHelper {
    static let shared = PromptFileHelper()

    private let promptsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Voco/Prompts", isDirectory: true)
    }()

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    func openInEditor(filename: String, content: String, onChange: @escaping (String) -> Void) {
        try? FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)
        let file = promptsDir.appendingPathComponent(filename)
        try? content.write(to: file, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(file)
        watchFile(filename: filename, onChange: onChange)
    }

    func read(filename: String) -> String? {
        let file = promptsDir.appendingPathComponent(filename)
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func stopWatching(filename: String) {
        watchers[filename]?.cancel()
        watchers[filename] = nil
    }

    private func watchFile(filename: String, onChange: @escaping (String) -> Void) {
        stopWatching(filename: filename)
        let file = promptsDir.appendingPathComponent(filename)
        let fd = open(file.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // Small delay to let the editor finish writing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let text = self?.read(filename: filename) {
                    onChange(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    print("[Voco] Prompt file \(filename) reloaded")
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[filename] = source
    }
}

// MARK: - LLM Settings View

struct LLMSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var apiKeyInput: String = ""
    @State private var keySaved = false
    @State private var testResult: String = ""

    private let languages = [
        "Chinese", "English", "Japanese", "Korean", "Spanish",
        "French", "German", "Russian", "Portuguese", "Italian",
        "Arabic", "Hindi", "Thai", "Vietnamese", "Indonesian",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Translation Languages")
            SettingsDescription("Used when translating via the Translate hotkey.")

            SettingsRow("From:") {
                Picker("", selection: $settings.sourceLanguage) {
                    ForEach(languages, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }

            SettingsRow("To:") {
                Picker("", selection: $settings.targetLanguage) {
                    ForEach(languages, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }

            SettingsDivider()

            SectionHeader("LLM API (OpenAI-Compatible)")

            SettingsRow("Base URL:") {
                TextField(AppConstants.defaultLLMBaseURL, text: $settings.llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            SettingsRow("Model:") {
                TextField(AppConstants.defaultLLMModel, text: $settings.llmModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            SettingsRow("API Key:") {
                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onAppear {
                        apiKeyInput = KeychainHelper.load(key: "llm_api_key") ?? ""
                    }
                Button(keySaved ? "Saved" : "Save") {
                    try? KeychainHelper.save(key: "llm_api_key", value: apiKeyInput)
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                }
                .disabled(apiKeyInput.isEmpty)
                .controlSize(.small)
            }

            SettingsDivider()

            SectionHeader("System Prompts")

            promptRow(
                label: "Transcribe:",
                isCustom: !settings.customSystemPrompt.isEmpty,
                onEdit: {
                    let content = settings.customSystemPrompt.isEmpty
                        ? Prompts.defaultPrompt(mode: .reformat, sourceLanguage: "", targetLanguage: "")
                        : settings.customSystemPrompt
                    PromptFileHelper.shared.openInEditor(filename: "transcribe_prompt.txt", content: content) { text in
                        settings.customSystemPrompt = text
                    }
                },
                onReset: { settings.customSystemPrompt = "" }
            )

            promptRow(
                label: "Translate:",
                isCustom: !settings.customTranslatePrompt.isEmpty,
                onEdit: {
                    let content = settings.customTranslatePrompt.isEmpty
                        ? Prompts.defaultPrompt(mode: .reformatAndTranslate, sourceLanguage: settings.sourceLanguage, targetLanguage: settings.targetLanguage)
                        : settings.customTranslatePrompt
                    PromptFileHelper.shared.openInEditor(filename: "translate_prompt.txt", content: content) { text in
                        settings.customTranslatePrompt = text
                    }
                },
                onReset: { settings.customTranslatePrompt = "" }
            )

            SettingsDivider()

            VStack(alignment: .leading, spacing: 6) {
                Button("Test Processing") {
                    Task { await testProcessing() }
                }
                .controlSize(.small)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.callout)
                        .foregroundStyle(testResult.starts(with: "Error") ? .red : .green)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promptRow(label: String, isCustom: Bool, onEdit: @escaping () -> Void, onReset: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Text(isCustom ? "Custom" : "Default")
                .font(.callout)
                .foregroundStyle(isCustom ? .orange : .secondary)
            Spacer()
            Button("Edit") { onEdit() }
                .controlSize(.small)
            if isCustom {
                Button("Reset") { onReset() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    private func testProcessing() async {
        testResult = "Testing..."
        do {
            let provider = LLMProviderFactory.create(for: settings)
            let result = try await provider.process(
                systemPrompt: "You are a helpful assistant. Respond with exactly: Test successful!",
                userPrompt: "Test"
            )
            testResult = result
        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }
    }
}
