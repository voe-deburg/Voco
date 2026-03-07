import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let language: String?
    let confidence: Float?
    let segments: [Segment]?

    struct Segment: Sendable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
}
