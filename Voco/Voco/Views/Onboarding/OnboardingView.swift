import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var apiKey = ""
    private let settings = AppSettings.shared

    private let totalSteps = 5

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
                case 3: apiKeyStep
                case 4: hotkeyStep
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
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 450)
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

            if PermissionsService.checkMicrophonePermission() {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        await PermissionsService.requestMicrophonePermission()
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

            if PermissionsService.checkAccessibilityPermission() {
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

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("API Keys")
                .font(.title2.bold())
            Text("Configure API keys for STT and LLM. You can change these later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            SecureField("LLM API Key (Cerebras, OpenAI, etc.)", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 350)

            if !apiKey.isEmpty {
                Button("Save Key") {
                    try? KeychainHelper.save(key: "llm_api_key", value: apiKey)
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
            Text("Default hotkeys are set. You can change them in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcribe:")
                        .frame(width: 90, alignment: .trailing)
                        .fontWeight(.medium)
                    Text(settings.transcribeHotkey.label)
                        .monospaced()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                }
                HStack {
                    Text("Translate:")
                        .frame(width: 90, alignment: .trailing)
                        .fontWeight(.medium)
                    Text(settings.translateHotkey.label)
                        .monospaced()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                }
            }

            Text("Press once to start recording, press again to stop and process. ESC to cancel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
