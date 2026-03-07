import SwiftUI

struct TranscriptionOverlayView: View {
    let state: RecordingState
    let audioLevel: Float
    var modeLabel: String? = nil
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let modeLabel {
                Text(modeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }

            HStack(spacing: 8) {
                // Cancel button
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                // Status indicator
                statusContent

                // Confirm / done button
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(confirmForeground)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(confirmBackground))
                }
                .buttonStyle(.plain)
                .disabled(!isConfirmEnabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.12)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .recording:
            WaveformView(audioLevel: audioLevel)
                .frame(width: 60, height: 20)
        case .transcribing, .processing:
            ProgressDotsView()
                .frame(width: 60, height: 20)
        case .done(_, let copied):
            HStack(spacing: 3) {
                Image(systemName: copied ? "doc.on.clipboard" : "checkmark.circle")
                    .font(.system(size: 10, weight: .medium))
                if copied {
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle(.green)
            .frame(width: 60, height: 20)
        case .error:
            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Retry")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 60, height: 20)
                    .background(Capsule().fill(.red.opacity(0.5)))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .frame(width: 60, height: 20)
            }
        case .idle:
            EmptyView()
        }
    }

    private var confirmForeground: Color {
        switch state {
        case .recording: .black
        case .done: .black
        default: .white.opacity(0.35)
        }
    }

    private var confirmBackground: Color {
        switch state {
        case .recording: .white
        case .done: .green
        default: .white.opacity(0.1)
        }
    }

    private var isConfirmEnabled: Bool {
        if case .recording = state { return true }
        return false
    }
}

// MARK: - Audio-reactive waveform during recording

private struct WaveformView: View {
    let audioLevel: Float

    private let barCount = 7
    @State private var heights: [CGFloat] = Array(repeating: 2, count: 7)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.9))
                    .frame(width: 2.5, height: heights[i])
            }
        }
        .onChange(of: audioLevel) {
            updateHeights()
        }
        .onAppear {
            updateHeights()
        }
    }

    private func updateHeights() {
        let level = CGFloat(min(1.0, max(0, audioLevel) * 12.0))
        let minHeight: CGFloat = 2
        let maxHeight: CGFloat = 18

        var newHeights = [CGFloat](repeating: minHeight, count: barCount)
        let center = Double(barCount - 1) / 2.0

        for i in 0..<barCount {
            if level < 0.005 {
                newHeights[i] = minHeight + CGFloat.random(in: 0...1.5)
            } else {
                let distFromCenter = abs(Double(i) - center) / center
                let shape = 1.0 - distFromCenter * 0.5
                let variation = CGFloat.random(in: 0.6...1.0)
                newHeights[i] = minHeight + (maxHeight - minHeight) * level * CGFloat(shape) * variation
            }
        }

        withAnimation(.easeOut(duration: 0.08)) {
            heights = newHeights
        }
    }
}

// MARK: - Animated progress dots for transcribing/processing

private struct ProgressDotsView: View {
    @State private var activeIndex = 0
    private let dotCount = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(opacity(for: i)))
                    .frame(width: 5, height: 5)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeIndex = (activeIndex + 1) % dotCount
                    }
                }
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let distance = abs(index - activeIndex)
        switch distance {
        case 0: return 0.9
        case 1: return 0.5
        default: return 0.2
        }
    }
}

// MARK: - Overlay window controller

@MainActor
final class OverlayWindowController {
    private var window: NSPanel?
    private var hostingView: NSHostingView<TranscriptionOverlayView>?

    func update(state: RecordingState, audioLevel: Float, modeLabel: String? = nil, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        if case .idle = state {
            hide()
            return
        }

        if window == nil {
            createWindow()
        }

        let view = TranscriptionOverlayView(
            state: state,
            audioLevel: audioLevel,
            modeLabel: modeLabel,
            onCancel: onCancel,
            onConfirm: onConfirm,
            onRetry: onRetry
        )
        hostingView?.rootView = view
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let view = TranscriptionOverlayView(state: .idle, audioLevel: 0)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hostingView = hosting

        positionWindow(panel)

        self.window = panel
    }

    private func positionWindow(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 90
        let y = screenFrame.minY + 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
