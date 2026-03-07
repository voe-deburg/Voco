import AppKit

enum AudioFeedbackService {
    private static let startSound = NSSound(named: .init("Blow"))
    private static let stopSound = NSSound(named: .init("Pop"))
    private static let doneSound = NSSound(named: .init("Glass"))
    private static let errorSound = NSSound(named: .init("Basso"))

    static func playStartRecording() {
        startSound?.stop()
        startSound?.play()
    }

    static func playStopRecording() {
        stopSound?.stop()
        stopSound?.play()
    }

    static func playDone() {
        doneSound?.stop()
        doneSound?.play()
    }

    static func playError() {
        errorSound?.stop()
        errorSound?.play()
    }
}
