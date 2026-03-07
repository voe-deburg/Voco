import CoreGraphics
import Carbon.HIToolbox
import ApplicationServices

enum PasteSimulator {
    @MainActor
    static func simulatePaste() async {
        guard AXIsProcessTrusted() else {
            print("[Voco] Accessibility not granted — cannot simulate Cmd+V. Text is in clipboard.")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(30))

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
