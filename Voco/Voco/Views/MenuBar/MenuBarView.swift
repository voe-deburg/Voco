import SwiftUI

struct MenuBarView: View {
    @Bindable var pipeline: VoiceInputPipeline
    @Environment(\.openWindow) private var openWindow
    private let settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: pipeline.state.systemImage)
                        .foregroundStyle(statusColor)
                    Text(pipeline.state.statusText)
                        .font(.headline)
                }
                if case .error(let msg) = pipeline.state {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                if !pipeline.lastError.isEmpty {
                    Text("Last error: \(pipeline.lastError)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            if pipeline.state.isRecording {
                Button {
                    Task { await pipeline.toggle() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    Task { await pipeline.toggle(mode: .reformat) }
                } label: {
                    Label("Transcribe (\(settings.transcribeHotkey.label))", systemImage: "mic.circle.fill")
                }

                Button {
                    Task { await pipeline.toggle(mode: .reformatAndTranslate) }
                } label: {
                    Label("Translate (\(settings.translateHotkey.label))", systemImage: "globe")
                }

                if pipeline.canRetry {
                    Button {
                        Task { await pipeline.retry() }
                    } label: {
                        Label("Retry Last Recording", systemImage: "arrow.clockwise")
                    }
                }
            }

            Divider()

            // Quick actions
            Button {
                activateAndOpen("history")
            } label: {
                Label("History", systemImage: "clock")
            }

            Button {
                activateAndOpen("settings")
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Voco") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(4)
    }

    private func activateAndOpen(_ windowID: String) {
        openWindow(id: windowID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.isVisible && window.title != "" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var statusColor: Color {
        switch pipeline.state {
        case .idle: .secondary
        case .recording: .red
        case .transcribing, .processing: .orange
        case .done: .green
        case .error: .red
        }
    }
}
