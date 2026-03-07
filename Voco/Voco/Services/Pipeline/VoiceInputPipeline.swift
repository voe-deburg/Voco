import Foundation
import SwiftData

@Observable
@MainActor
final class VoiceInputPipeline {
    var state: RecordingState = .idle
    var currentTranscription: String = ""
    var lastError: String = ""

    private let audioRecorder = AudioRecorderService()
    private let settings = AppSettings.shared
    private var activeAppName: String = ""
    private var activeAppBundleID: String = ""
    private var modelContext: ModelContext?
    private var processingTask: Task<Void, Never>?
    private var activeMode: ProcessingMode = .reformat
    private var lastAudioData: Data?
    private var lastActiveMode: ProcessingMode = .reformat

    let overlayController = OverlayWindowController()

    var audioLevel: Float { audioRecorder.audioLevel }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func toggle(mode: ProcessingMode? = nil) async {
        switch state {
        case .idle, .done, .error:
            processingTask?.cancel()
            processingTask = nil
            state = .idle
            if let mode { activeMode = mode }
            await startRecording()
        case .recording:
            await stopAndProcess()
        default:
            break
        }
    }

    var canRetry: Bool {
        lastAudioData != nil && (state.isIdle || { if case .error = state { return true }; return false }())
    }

    func retry() async {
        guard let audioData = lastAudioData else { return }
        activeMode = lastActiveMode
        await processAudio(audioData)
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        overlayPollTask?.cancel()
        overlayPollTask = nil
        _ = audioRecorder.stopRecording()
        state = .idle
        currentTranscription = ""
        updateOverlay()
    }

    private var overlayModeLabel: String? {
        guard activeMode == .reformatAndTranslate else { return nil }
        return "🌐 \(settings.sourceLanguage) → \(settings.targetLanguage)"
    }

    private func updateOverlay() {
        guard settings.showOverlay else {
            overlayController.hide()
            return
        }
        overlayController.update(
            state: state,
            audioLevel: audioLevel,
            modeLabel: overlayModeLabel,
            onCancel: { [weak self] in self?.cancel() },
            onConfirm: { [weak self] in
                guard let self else { return }
                Task { await self.stopAndProcess() }
            },
            onRetry: canRetry ? { [weak self] in
                guard let self else { return }
                Task { await self.retry() }
            } : nil
        )
    }

    private var overlayPollTask: Task<Void, Never>?

    private func startRecording() async {
        let activeApp = ActiveAppDetector.detect()
        activeAppName = activeApp.name
        activeAppBundleID = activeApp.bundleID

        do {
            try audioRecorder.startRecording()
            state = .recording
            updateOverlay()
            if settings.audioFeedback {
                AudioFeedbackService.playStartRecording()
            }
            overlayPollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.state.isRecording else { break }
                    self.updateOverlay()
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            updateOverlay()
            if settings.audioFeedback {
                AudioFeedbackService.playError()
            }
        }
    }

    private func stopAndProcess() async {
        state = .transcribing
        updateOverlay()

        overlayPollTask?.cancel()
        overlayPollTask = nil

        if settings.audioFeedback {
            AudioFeedbackService.playStopRecording()
        }

        let audioData = audioRecorder.stopRecording()

        guard audioData.count > 44 else {
            print("[Voco] No audio data recorded (size: \(audioData.count))")
            state = .error("No audio recorded. Check microphone permissions and selection.")
            updateOverlay()
            if settings.audioFeedback { AudioFeedbackService.playError() }
            return
        }

        lastAudioData = audioData
        lastActiveMode = activeMode
        await processAudio(audioData)
    }

    private func processAudio(_ audioData: Data) async {
        state = .transcribing
        updateOverlay()

        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sttProvider = STTProviderFactory.create(for: self.settings)
                let transcription = try await sttProvider.transcribe(
                    audioData: audioData,
                    language: self.settings.inputLanguage
                )

                try Task.checkCancellation()

                let rawText = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.currentTranscription = rawText

                if rawText.isEmpty {
                    print("[Voco] Empty transcription, skipping LLM")
                    self.state = .idle
                    self.updateOverlay()
                    return
                }

                self.state = .processing
                self.updateOverlay()

                let dictionaryTerms = self.fetchDictionaryTerms()
                let tone = self.fetchTone(for: self.activeAppBundleID)
                let systemPrompt = Prompts.systemPrompt(
                    mode: self.activeMode,
                    sourceLanguage: self.settings.sourceLanguage,
                    targetLanguage: self.settings.targetLanguage,
                    dictionaryTerms: dictionaryTerms,
                    customTranscribePrompt: self.settings.customSystemPrompt,
                    customTranslatePrompt: self.settings.customTranslatePrompt,
                    appName: self.activeAppName,
                    appBundleID: self.activeAppBundleID,
                    tone: tone
                )

                print("[Voco] ── Pipeline ──")
                print("[Voco] Mode: \(self.activeMode.rawValue)")
                print("[Voco] Active app: \(self.activeAppName) (\(self.activeAppBundleID))")
                print("[Voco] STT result: \(rawText)")
                print("[Voco] System prompt:\n\(systemPrompt)")
                print("[Voco] ────────────")

                let userPrompt: String
                if self.activeMode == .reformatAndTranslate {
                    userPrompt = rawText + "\n\nRewrite the above in clean, natural \(self.settings.targetLanguage):"
                } else {
                    userPrompt = rawText + "\n\nRewrite the above in clean, natural text:"
                }

                let llmProvider = LLMProviderFactory.create(for: self.settings)
                let processedText = try await llmProvider.process(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt
                )

                try Task.checkCancellation()

                print("[Voco] LLM output: \(processedText)")
                if processedText.isEmpty {
                    print("[Voco] Empty LLM output, skipping paste")
                    self.state = .idle
                    self.updateOverlay()
                    return
                }
                let pasteResult = await PasteService.paste(text: processedText, alwaysCopy: self.settings.alwaysCopyToClipboard)
                self.saveToHistory(rawText: rawText, processedText: processedText)

                let copiedToClipboard = pasteResult == .copied
                self.state = .done(processedText, copied: copiedToClipboard)
                self.updateOverlay()
                if self.settings.audioFeedback {
                    AudioFeedbackService.playDone()
                }

                try? await Task.sleep(for: .seconds(AppConstants.overlayFadeDuration))
                self.state = .idle
                self.currentTranscription = ""
                self.updateOverlay()

            } catch is CancellationError {
                self.state = .idle
                self.currentTranscription = ""
                self.updateOverlay()
            } catch let urlError as URLError where urlError.code == .cancelled {
                self.state = .idle
                self.currentTranscription = ""
                self.updateOverlay()
            } catch {
                let msg = error.localizedDescription
                print("[Voco] Pipeline error: \(msg)")
                self.lastError = msg
                self.state = .error(msg)
                self.updateOverlay()
                if self.settings.audioFeedback {
                    AudioFeedbackService.playError()
                }
            }
        }
    }

    private func fetchDictionaryTerms() -> [(word: String, hint: String)] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<DictionaryEntry>()
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map { ($0.word, $0.pronunciationHint) }
    }

    private func fetchTone(for bundleID: String) -> String {
        // Check custom profiles first
        if let context = modelContext {
            let descriptor = FetchDescriptor<AppProfile>(
                predicate: #Predicate { $0.appBundleID == bundleID }
            )
            if let profile = (try? context.fetch(descriptor))?.first {
                var result = "Use a \(profile.tone) tone."
                if !profile.formattingHints.isEmpty {
                    result += " \(profile.formattingHints)"
                }
                return result
            }
        }
        // Then built-in
        if let builtIn = AppProfileManager.builtInProfile(for: bundleID) {
            var result = "Use a \(builtIn.tone) tone."
            if !builtIn.formattingHints.isEmpty {
                result += " \(builtIn.formattingHints)"
            }
            return result
        }
        return "Use a neutral, clear tone."
    }

    private func saveToHistory(rawText: String, processedText: String) {
        guard let context = modelContext else { return }
        let entry = TranscriptionHistory(
            rawText: rawText,
            processedText: processedText,
            appName: activeAppName,
            mode: settings.processingMode.rawValue,
            language: settings.inputLanguage
        )
        context.insert(entry)
        try? context.save()
    }
}
