import AppKit
import CoreGraphics
import ApplicationServices

enum PasteResult: Sendable {
    /// Text was pasted via Cmd+V (and possibly also left in clipboard).
    case pasted
    /// No text field detected — text copied to clipboard only.
    case copied
}

enum PasteService {
    @MainActor
    static func paste(text: String, alwaysCopy: Bool) async -> PasteResult {
        let pasteboard = NSPasteboard.general

        // Check if we can positively confirm no text field is focused.
        // If detection is inconclusive (AX error, etc.), default to pasting.
        let definitelyNoTextField = hasDefinitelyNoTextFieldFocus()

        if definitelyNoTextField {
            // Confirmed no text field — clipboard only
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[Typeless] No text field focused — text copied to clipboard.")
            return .copied
        }

        // Paste via Cmd+V (need clipboard as transport)
        let savedContents = alwaysCopy ? nil : pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(50))
        await PasteSimulator.simulatePaste()
        try? await Task.sleep(for: .milliseconds(50))

        if !alwaysCopy {
            // Restore previous clipboard contents
            pasteboard.clearContents()
            if let saved = savedContents {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return .pasted
    }

    /// Returns true ONLY when we can positively confirm no text input is focused.
    /// Returns false (= assume paste will work) when detection is inconclusive.
    private static func hasDefinitelyNoTextFieldFocus() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // If AX query failed (app doesn't support AX, e.g. WeChat), assume paste will work
        guard err == .success, let focusedElement = focusedRef else { return false }
        let element = focusedElement as! AXUIElement

        // Check role — if it's a known text role, definitely has text field
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        let textRoles: Set<String> = [
            kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
            "AXWebArea", "AXSearchField",
        ]
        if textRoles.contains(role) { return false }

        // Check if AXValue is settable
        var settable: DarwinBoolean = false
        let settableErr = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settableErr == .success && settable.boolValue { return false }

        // We got a focused element and it's NOT a text input
        print("[Typeless] Focused element role=\(role), not a text field → clipboard only")
        return true
    }
}
