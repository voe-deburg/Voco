import SwiftUI
import Carbon.HIToolbox

// MARK: - Key Recorder

struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: Hotkey
    @State private var isRecording = false

    var body: some View {
        SettingsRow(label) {
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
        view.onFnKey = { modifierFlags in
            let carbonMods = carbonModifiers(from: modifierFlags)
            let label = HotkeyService.labelForKeyCode(HotkeyService.fnKeyCode, modifiers: carbonMods)
            hotkey = Hotkey(keyCode: HotkeyService.fnKeyCode, modifiers: carbonMods, label: label)
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
    var onFnKey: ((NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    private var fnDown = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        onKey?(UInt16(event.keyCode), event.modifierFlags.intersection([.shift, .control, .option, .command]))
    }

    override func flagsChanged(with event: NSEvent) {
        let isFn = event.modifierFlags.contains(.function) && event.keyCode == 0x3F
        if isFn {
            if !fnDown {
                fnDown = true
            }
        } else if fnDown {
            fnDown = false
            // Pass the remaining modifiers (shift, control, option, command) that were held with Fn
            let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
            onFnKey?(mods)
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
            HotkeyRecorder(label: "Transcribe:", hotkey: $settings.transcribeHotkey)
            HotkeyRecorder(label: "Translate:", hotkey: $settings.translateHotkey)
            SettingsDescription("Click to record a new key. ESC to cancel. Supports Fn, F1–F12, and modifier combos.")

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
                Button(buttonLabel) { Task { await action() } }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
