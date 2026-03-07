import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var sttApiKey = ""
    @State private var sttBaseURL = ""
    @State private var sttModel = ""
    @State private var sttSaved = false
    @State private var llmApiKey = ""
    @State private var llmBaseURL = ""
    @State private var llmModel = ""
    @State private var llmSaved = false
    @State private var micGranted = PermissionsService.checkMicrophonePermission()
    @State private var accessibilityGranted = PermissionsService.checkAccessibilityPermission()
    @Bindable private var settings = AppSettings.shared

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding()

            Divider()

            // Content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: microphoneStep
                case 2: accessibilityStep
                case 3: sttApiKeyStep
                case 4: llmApiKeyStep
                case 5: hotkeyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        // Relaunch so hotkeys and providers pick up new settings
                        let url = Bundle.main.bundleURL
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        task.arguments = ["-n", url.path]
                        try? task.run()
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onReceive(permissionTimer) { _ in
            micGranted = PermissionsService.checkMicrophonePermission()
            accessibilityGranted = PermissionsService.checkAccessibilityPermission()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Voco")
                .font(.largeTitle.bold())
            Text("Voice input that understands you. Speak naturally, get clean text pasted anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Microphone Access")
                .font(.title2.bold())
            Text("Voco needs microphone access to hear your voice.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if micGranted {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        let result = await PermissionsService.requestMicrophonePermission()
                        micGranted = result
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Accessibility Access")
                .font(.title2.bold())
            Text("Required to paste text into other applications using keyboard simulation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if accessibilityGranted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings") {
                    AccessibilityHelper.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var sttApiKeyStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.mint)
            Text("Speech-to-Text API")
                .font(.title2.bold())
            Text("Configure your STT provider. You can change this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                TextField("Base URL (default: \(AppConstants.defaultSTTBaseURL))", text: $sttBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                TextField("Model (default: \(AppConstants.defaultSTTModel))", text: $sttModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                SecureField("API Key", text: $sttApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
            }

            if sttSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if !sttApiKey.isEmpty {
                Button("Save") {
                    try? KeychainHelper.save(key: "stt_api_key", value: sttApiKey)
                    if !sttBaseURL.isEmpty { settings.sttBaseURL = sttBaseURL }
                    if !sttModel.isEmpty { settings.sttModel = sttModel }
                    sttSaved = true
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Skip (configure later in Settings)") {
                currentStep += 1
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var llmApiKeyStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("LLM API")
                .font(.title2.bold())
            Text("Configure your LLM provider. You can change this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                TextField("Base URL (default: \(AppConstants.defaultLLMBaseURL))", text: $llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                TextField("Model (default: \(AppConstants.defaultLLMModel))", text: $llmModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
                SecureField("API Key", text: $llmApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 380)
            }

            if llmSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if !llmApiKey.isEmpty {
                Button("Save") {
                    try? KeychainHelper.save(key: "llm_api_key", value: llmApiKey)
                    if !llmBaseURL.isEmpty { settings.llmBaseURL = llmBaseURL }
                    if !llmModel.isEmpty { settings.llmModel = llmModel }
                    llmSaved = true
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Skip (configure later in Settings)") {
                currentStep += 1
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var hotkeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text("Hotkeys")
                .font(.title2.bold())
            Text("Click a hotkey to change it. You can also change them later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HotkeyRecorder(label: "Transcribe:", hotkey: $settings.transcribeHotkey, otherHotkey: settings.translateHotkey)
                HotkeyRecorder(label: "Translate:", hotkey: $settings.translateHotkey, otherHotkey: settings.transcribeHotkey)
            }

            Text("Press once to start recording, press again to stop and process. ESC to cancel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
