import Carbon.HIToolbox
import AppKit
import CoreGraphics

// MARK: - Hotkey Model

struct Hotkey: Codable, Sendable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32 // Carbon modifier flags
    var label: String

    static let defaultTranscribe = Hotkey(keyCode: 0x3F, modifiers: 0, label: "🌐 Fn")
    static let defaultTranslate = Hotkey(keyCode: 0x3F, modifiers: UInt32(shiftKey), label: "⇧ 🌐 Fn")
}

// MARK: - Hotkey Service

enum HotkeyService {
    private static let transcribeID = EventHotKeyID(signature: OSType(0x54595031), id: 1)
    private static let translateID = EventHotKeyID(signature: OSType(0x54595031), id: 2)

    nonisolated(unsafe) static var transcribeRef: EventHotKeyRef?
    nonisolated(unsafe) static var translateRef: EventHotKeyRef?
    nonisolated(unsafe) static var escGlobalMonitor: Any?
    nonisolated(unsafe) static var escLocalMonitor: Any?
    nonisolated(unsafe) static var modifierTapPort: CFMachPort?
    nonisolated(unsafe) static var modifierRunLoopSource: CFRunLoopSource?
    nonisolated(unsafe) static var pipeline: VoiceInputPipeline?
    nonisolated(unsafe) static var isSuspended = false
    nonisolated(unsafe) static var carbonHandlerInstalled = false
    nonisolated(unsafe) static var modifierHealthTimer: Timer?

    // Solo modifier key state
    nonisolated(unsafe) static var soloModifierKeyCode: UInt16? = nil
    nonisolated(unsafe) static var otherKeyDuringModifier = false
    nonisolated(unsafe) static var modifierAdditionalMods: UInt32 = 0

    static let fnKeyCode: UInt16 = 0x3F

    static let modifierKeyCodes: Set<UInt16> = [
        0x3F,        // Fn
        0x3A, 0x3D,  // Left/Right Option
        0x3B, 0x3E,  // Left/Right Control
        0x38, 0x3C,  // Left/Right Shift
        0x37, 0x36,  // Left/Right Command
    ]

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// Normalize right-side modifier keyCodes to left-side equivalents.
    static func normalizeModifierKeyCode(_ keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 0x3D: return 0x3A  // Right Option → Left Option
        case 0x3E: return 0x3B  // Right Control → Left Control
        case 0x3C: return 0x38  // Right Shift → Left Shift
        case 0x36: return 0x37  // Right Command → Left Command
        default: return keyCode
        }
    }

    static func cgFlagForModifierKey(_ keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 0x3F: return CGEventFlags(rawValue: 0x800000)
        case 0x3A, 0x3D: return .maskAlternate
        case 0x3B, 0x3E: return .maskControl
        case 0x38, 0x3C: return .maskShift
        case 0x37, 0x36: return .maskCommand
        default: return nil
        }
    }

    @MainActor
    static func register(pipeline: VoiceInputPipeline) {
        self.pipeline = pipeline

        if !carbonHandlerInstalled {
            installCarbonHandler()
            carbonHandlerInstalled = true
        }

        registerHotkeys()
        installEscMonitors()

        print("[Voco] HotkeyService registered")
    }

    @MainActor
    static func suspend() {
        isSuspended = true
        print("[Voco] Hotkeys suspended")
    }

    @MainActor
    static func resume() {
        isSuspended = false
        // Re-enable Fn tap in case system disabled it
        let settings = AppSettings.shared
        let needsTap = isModifierKey(settings.transcribeHotkey.keyCode) || isModifierKey(settings.translateHotkey.keyCode)
        if needsTap {
            ensureModifierTapAlive()
        }
        print("[Voco] Hotkeys resumed")
    }

    @MainActor
    static func registerHotkeys() {
        // Unregister old Carbon hotkeys
        if let ref = transcribeRef { UnregisterEventHotKey(ref); transcribeRef = nil }
        if let ref = translateRef { UnregisterEventHotKey(ref); translateRef = nil }
        removeModifierTap()

        let settings = AppSettings.shared
        let transcribe = settings.transcribeHotkey
        let translate = settings.translateHotkey
        let needsTap = isModifierKey(transcribe.keyCode) || isModifierKey(translate.keyCode)

        // Register Carbon hotkeys for non-modifier keys
        if !isModifierKey(transcribe.keyCode) {
            var ref: EventHotKeyRef?
            let hid = transcribeID
            let status = RegisterEventHotKey(
                UInt32(transcribe.keyCode), transcribe.modifiers,
                hid, GetApplicationEventTarget(), 0, &ref
            )
            transcribeRef = ref
            print("[Voco] Registered transcribe hotkey (\(transcribe.label)): status=\(status), ref=\(ref != nil)")
        }
        if !isModifierKey(translate.keyCode) {
            var ref: EventHotKeyRef?
            let hid = translateID
            let status = RegisterEventHotKey(
                UInt32(translate.keyCode), translate.modifiers,
                hid, GetApplicationEventTarget(), 0, &ref
            )
            translateRef = ref
            print("[Voco] Registered translate hotkey (\(translate.label)): status=\(status), ref=\(ref != nil)")
        }

        if needsTap {
            installModifierTap()
            startModifierHealthCheck()
        } else {
            stopModifierHealthCheck()
        }
    }

    // MARK: - ESC Monitors

    private static func installEscMonitors() {
        // Remove old monitors if any
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }

        // Global: catches ESC when other apps are focused
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handleEsc(event)
        }

        // Local: catches ESC when our own windows are focused
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleEsc(event) {
                return nil // consume
            }
            return event
        }

        print("[Voco] ESC monitors installed")
    }

    @discardableResult
    private static func handleEsc(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_Escape) else { return false }
        guard !isSuspended else { return false }
        guard let p = pipeline else { return false }
        Task { @MainActor in
            guard !p.state.isIdle else { return }
            p.cancel()
            print("[Voco] Cancelled via ESC")
        }
        return false // never consume ESC — let it pass through to other handlers
    }

    // MARK: - Carbon Handler

    private static func installCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            guard !HotkeyService.isSuspended else { return noErr }
            var hid = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                            nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            guard let p = HotkeyService.pipeline else { return noErr }
            print("[Voco] Carbon hotkey fired: id=\(hid.id)")
            switch hid.id {
            case 1: Task { @MainActor in await p.toggle(mode: .reformat) }
            case 2: Task { @MainActor in await p.toggle(mode: .reformatAndTranslate) }
            default: break
            }
            return noErr
        }, 1, &eventType, nil, nil)
        print("[Voco] Carbon handler installed: status=\(status)")
    }

    // MARK: - Modifier Key Tap

    private static func installModifierTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { proxy, type, event, _ -> Unmanaged<CGEvent>? in

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = HotkeyService.modifierTapPort { CGEvent.tapEnable(tap: port, enable: true) }
                    print("[Voco] Modifier tap re-enabled after disable")
                    return Unmanaged.passRetained(event)
                }

                guard !HotkeyService.isSuspended else { return Unmanaged.passRetained(event) }

                if type == .keyDown && HotkeyService.soloModifierKeyCode != nil {
                    HotkeyService.otherKeyDuringModifier = true
                    return Unmanaged.passRetained(event)
                }

                if type == .flagsChanged {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

                    if HotkeyService.isModifierKey(keyCode),
                       let flag = HotkeyService.cgFlagForModifierKey(keyCode) {
                        let isDown = event.flags.contains(flag)

                        if isDown {
                            HotkeyService.soloModifierKeyCode = keyCode
                            HotkeyService.otherKeyDuringModifier = false
                            // Capture additional modifiers (excluding the one being pressed)
                            var mods: UInt32 = 0
                            let cgFlags = event.flags
                            if cgFlags.contains(.maskShift) && keyCode != 0x38 && keyCode != 0x3C { mods |= UInt32(shiftKey) }
                            if cgFlags.contains(.maskControl) && keyCode != 0x3B && keyCode != 0x3E { mods |= UInt32(controlKey) }
                            if cgFlags.contains(.maskAlternate) && keyCode != 0x3A && keyCode != 0x3D { mods |= UInt32(optionKey) }
                            if cgFlags.contains(.maskCommand) && keyCode != 0x37 && keyCode != 0x36 { mods |= UInt32(cmdKey) }
                            HotkeyService.modifierAdditionalMods = mods
                        } else if HotkeyService.soloModifierKeyCode == keyCode {
                            HotkeyService.soloModifierKeyCode = nil
                            if !HotkeyService.otherKeyDuringModifier {
                                let capturedMods = HotkeyService.modifierAdditionalMods
                                let normalizedKey = HotkeyService.normalizeModifierKeyCode(keyCode)
                                guard let p = HotkeyService.pipeline else { return Unmanaged.passRetained(event) }
                                Task { @MainActor in
                                    let s = AppSettings.shared
                                    if s.transcribeHotkey.keyCode == normalizedKey &&
                                       s.transcribeHotkey.modifiers == capturedMods {
                                        await p.toggle(mode: .reformat)
                                    } else if s.translateHotkey.keyCode == normalizedKey &&
                                              s.translateHotkey.modifiers == capturedMods {
                                        await p.toggle(mode: .reformatAndTranslate)
                                    }
                                }
                            }
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            }, userInfo: nil
        ) else {
            print("[Voco] Failed to create CGEventTap for modifier keys — check Accessibility permission")
            return
        }
        modifierTapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        modifierRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Voco] Modifier tap installed")
    }

    private static func startModifierHealthCheck() {
        stopModifierHealthCheck()
        modifierHealthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                ensureModifierTapAlive()
            }
        }
    }

    private static func stopModifierHealthCheck() {
        modifierHealthTimer?.invalidate()
        modifierHealthTimer = nil
    }

    @MainActor
    private static func ensureModifierTapAlive() {
        if let port = modifierTapPort {
            if !CGEvent.tapIsEnabled(tap: port) {
                CGEvent.tapEnable(tap: port, enable: true)
                print("[Voco] Modifier tap was disabled — re-enabled by health check")
            }
        } else {
            print("[Voco] Modifier tap not found — attempting to recreate")
            installModifierTap()
        }
    }

    private static func removeModifierTap() {
        stopModifierHealthCheck()
        if let source = modifierRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            modifierRunLoopSource = nil
        }
        if let port = modifierTapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            modifierTapPort = nil
        }
    }

    // MARK: - Key Label Helper

    static func labelForKeyCode(_ keyCode: UInt16, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_F1: keyName = "F1"
        case kVK_F2: keyName = "F2"
        case kVK_F3: keyName = "F3"
        case kVK_F4: keyName = "F4"
        case kVK_F5: keyName = "F5"
        case kVK_F6: keyName = "F6"
        case kVK_F7: keyName = "F7"
        case kVK_F8: keyName = "F8"
        case kVK_F9: keyName = "F9"
        case kVK_F10: keyName = "F10"
        case kVK_F11: keyName = "F11"
        case kVK_F12: keyName = "F12"
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "↩"
        case kVK_Tab: keyName = "⇥"
        case kVK_Delete: keyName = "⌫"
        case 0x3F: keyName = "🌐 Fn"
        case 0x3A: keyName = "⌥ Option"
        case 0x3B: keyName = "⌃ Control"
        case 0x38: keyName = "⇧ Shift"
        case 0x37: keyName = "⌘ Command"
        default:
            // Use ASCII-capable layout to avoid nil layoutData with non-Latin input sources (e.g. Chinese)
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            if let data = layoutData {
                let layout = unsafeBitCast(data, to: CFData.self)
                let layoutPtr = UnsafeRawPointer(CFDataGetBytePtr(layout)!).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                UCKeyTranslate(layoutPtr, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                              UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
                if length > 0 {
                    keyName = String(utf16CodeUnits: chars, count: length).uppercased()
                } else {
                    keyName = "Key\(keyCode)"
                }
            } else {
                keyName = "Key\(keyCode)"
            }
        }

        parts.append(keyName)
        return parts.joined()
    }
}
