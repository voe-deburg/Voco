import os

/// Thread-safe box for passing audio level from a realtime audio thread to the main actor.
final class AudioLevelBox: @unchecked Sendable {
    private let _lock = OSAllocatedUnfairLock(initialState: Float(0))

    var level: Float {
        get { _lock.withLock { $0 } }
        set { _lock.withLock { $0 = newValue } }
    }
}
