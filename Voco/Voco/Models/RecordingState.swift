import Foundation

enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case done(String, copied: Bool = false)
    case error(String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording..."
        case .transcribing: "Transcribing..."
        case .processing: "Processing..."
        case .done: "Done"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "mic.fill"
        case .recording: "mic.badge.plus"
        case .transcribing: "waveform"
        case .processing: "brain"
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}
