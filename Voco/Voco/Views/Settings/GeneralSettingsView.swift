import SwiftUI
import Carbon.HIToolbox

// MARK: - Key Recorder

struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: Hotkey
    var otherHotkey: Hotkey?
    @State private var isRecording = false

    private var isDuplicate: Bool {
        otherHotkey != nil && hotkey == otherHotkey
    }

    var body: some View {
        SettingsRow(label) {
            HStack(spacing: 6) {
                Button {
                    isRecording.toggle()
                } label: {
                    Text(isRecording ? "Press any key..." : hotkey.label)
                        .frame(minWidth: 100)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .keyboardShortcut(.none)
                .background(isRecording ? KeyCaptureView(hotkey: $hotkey, isRecording: $isRecording) : nil)
                .onChange(of: isRecording) {
                    if isRecording {
                        HotkeyService.suspend()
                    } else {
                        HotkeyService.resume()
                    }
                }
                .onDisappear {
                    if isRecording {
                        isRecording = false
                        HotkeyService.resume()
                    }
                }
                if isDuplicate {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .help("Same as the other hotkey")
                }
            }
        }
    }
}

/// An invisible NSView that captures the next key press.
struct KeyCaptureView: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKey = { keyCode, modifierFlags in
            let carbonMods = carbonModifiers(from: modifierFlags)
            let label = HotkeyService.labelForKeyCode(keyCode, modifiers: carbonMods)
            hotkey = Hotkey(keyCode: keyCode, modifiers: carbonMods, label: label)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {}

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

final class KeyCaptureNSView: NSView {
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    private var modifierKeyDown: UInt16? = nil

    override var acceptsFirstResponder: Bool { true }

    private static let functionKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
        UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
    ]

    override func keyDown(with event: NSEvent) {
        modifierKeyDown = nil
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let hasNonShiftModifier = mods.contains(.control) || mods.contains(.option) || mods.contains(.command)
        // Reject plain keys (or shift-only) that would conflict with normal typing
        if !hasNonShiftModifier && !Self.functionKeyCodes.contains(event.keyCode) {
            return
        }
        onKey?(UInt16(event.keyCode), mods)
    }

    override func flagsChanged(with event: NSEvent) {
        let keyCode = event.keyCode
        guard HotkeyService.isModifierKey(keyCode),
              let flag = modifierFlag(for: keyCode) else { return }

        let isDown = event.modifierFlags.contains(flag)
        if isDown {
            modifierKeyDown = keyCode
        } else if modifierKeyDown == keyCode {
            modifierKeyDown = nil
            let normalized = HotkeyService.normalizeModifierKeyCode(keyCode)
            // Pass remaining held modifiers (e.g. Shift held during Fn release → Shift+Fn)
            let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
            onKey?(normalized, mods)
        }
    }

    private func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 0x3F: return .function
        case 0x3A, 0x3D: return .option
        case 0x3B, 0x3E: return .control
        case 0x38, 0x3C: return .shift
        case 0x37, 0x36: return .command
        default: return nil
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = LaunchAgentHelper.isEnabled
    @State private var micGranted = PermissionsService.checkMicrophonePermission()
    @State private var accessibilityGranted = PermissionsService.checkAccessibilityPermission()

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) {
                    LaunchAgentHelper.setEnabled(launchAtLogin)
                }

            SettingsDivider()

            SectionHeader("Hotkeys")
            HotkeyRecorder(label: "Transcribe:", hotkey: $settings.transcribeHotkey, otherHotkey: settings.translateHotkey)
            HotkeyRecorder(label: "Translate:", hotkey: $settings.translateHotkey, otherHotkey: settings.transcribeHotkey)
            SettingsDescription("Click to record a new key. ESC to cancel. Supports Fn, Option, Control, Shift, Command, F1–F12, and modifier combos.")

            SettingsDivider()

            SectionHeader("Interface")
            Toggle("Show overlay during recording", isOn: $settings.showOverlay)
                .toggleStyle(.checkbox)
                .padding(.bottom, 6)
            Toggle("Audio feedback sounds", isOn: $settings.audioFeedback)
                .toggleStyle(.checkbox)
                .padding(.bottom, 6)
            Toggle("Always copy to clipboard", isOn: $settings.alwaysCopyToClipboard)
                .toggleStyle(.checkbox)

            SettingsDivider()

            SectionHeader("Permissions")
            permissionRow("Microphone", granted: micGranted, buttonLabel: "Request") {
                micGranted = await PermissionsService.requestMicrophonePermission()
            }
            permissionRow("Accessibility", granted: accessibilityGranted, buttonLabel: "Open Settings") {
                AccessibilityHelper.requestAccessibility()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(permissionTimer) { _ in refreshPermissions() }
        .onAppear { refreshPermissions() }
    }

    private func refreshPermissions() {
        micGranted = PermissionsService.checkMicrophonePermission()
        accessibilityGranted = PermissionsService.checkAccessibilityPermission()
    }

    private func permissionRow(_ label: String, granted: Bool, buttonLabel: String, action: @escaping () async -> Void) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted").foregroundStyle(.secondary).font(.callout)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Not Granted").foregroundStyle(.orange).font(.callout)
                Spacer()
                Button(buttonLabel) { Task { await action() } }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
