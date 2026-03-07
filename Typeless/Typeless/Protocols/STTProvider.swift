import Foundation

protocol STTProvider: Sendable {
    func transcribe(audioData: Data, language: String?) async throws -> TranscriptionResult
}
