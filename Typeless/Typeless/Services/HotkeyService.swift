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
    nonisolated(unsafe) static var fnTapPort: CFMachPort?
    nonisolated(unsafe) static var fnRunLoopSource: CFRunLoopSource?
    nonisolated(unsafe) static var pipeline: VoiceInputPipeline?
    nonisolated(unsafe) static var isSuspended = false
    nonisolated(unsafe) static var carbonHandlerInstalled = false

    // Fn key state
    nonisolated(unsafe) static var fnWasPressed = false
    nonisolated(unsafe) static var otherKeyDuringFn = false
    nonisolated(unsafe) static var fnModifiers: UInt32 = 0

    static let fnKeyCode: UInt16 = 0x3F

    @MainActor
    static func register(pipeline: VoiceInputPipeline) {
        self.pipeline = pipeline

        if !carbonHandlerInstalled {
            installCarbonHandler()
            carbonHandlerInstalled = true
        }

        registerHotkeys()
        installEscMonitors()

        print("[Typeless] HotkeyService registered")
    }

    @MainActor
    static func suspend() {
        isSuspended = true
        print("[Typeless] Hotkeys suspended")
    }

    @MainActor
    static func resume() {
        isSuspended = false
        // Re-enable Fn tap in case system disabled it
        if let port = fnTapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        print("[Typeless] Hotkeys resumed")
    }

    @MainActor
    static func registerHotkeys() {
        // Unregister old Carbon hotkeys
        if let ref = transcribeRef { UnregisterEventHotKey(ref); transcribeRef = nil }
        if let ref = translateRef { UnregisterEventHotKey(ref); translateRef = nil }
        removeFnTap()

        let settings = AppSettings.shared
        let transcribe = settings.transcribeHotkey
        let translate = settings.translateHotkey
        let needsFn = transcribe.keyCode == fnKeyCode || translate.keyCode == fnKeyCode

        // Register Carbon hotkeys for non-Fn keys
        if transcribe.keyCode != fnKeyCode {
            var ref: EventHotKeyRef?
            let hid = transcribeID
            let status = RegisterEventHotKey(
                UInt32(transcribe.keyCode), transcribe.modifiers,
                hid, GetApplicationEventTarget(), 0, &ref
            )
            transcribeRef = ref
            print("[Typeless] Registered transcribe hotkey (\(transcribe.label)): status=\(status), ref=\(ref != nil)")
        }
        if translate.keyCode != fnKeyCode {
            var ref: EventHotKeyRef?
            let hid = translateID
            let status = RegisterEventHotKey(
                UInt32(translate.keyCode), translate.modifiers,
                hid, GetApplicationEventTarget(), 0, &ref
            )
            translateRef = ref
            print("[Typeless] Registered translate hotkey (\(translate.label)): status=\(status), ref=\(ref != nil)")
        }

        if needsFn {
            installFnTap()
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

        print("[Typeless] ESC monitors installed")
    }

    @discardableResult
    private static func handleEsc(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_Escape) else { return false }
        guard !isSuspended else { return false }
        guard let p = pipeline else { return false }
        Task { @MainActor in
            guard !p.state.isIdle else { return }
            p.cancel()
            print("[Typeless] Cancelled via ESC")
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
            print("[Typeless] Carbon hotkey fired: id=\(hid.id)")
            switch hid.id {
            case 1: Task { @MainActor in await p.toggle(mode: .reformat) }
            case 2: Task { @MainActor in await p.toggle(mode: .reformatAndTranslate) }
            default: break
            }
            return noErr
        }, 1, &eventType, nil, nil)
        print("[Typeless] Carbon handler installed: status=\(status)")
    }

    // MARK: - Fn Key Tap

    private static func installFnTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { proxy, type, event, _ -> Unmanaged<CGEvent>? in

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = HotkeyService.fnTapPort { CGEvent.tapEnable(tap: port, enable: true) }
                    print("[Typeless] Fn tap re-enabled after disable")
                    return Unmanaged.passRetained(event)
                }

                guard !HotkeyService.isSuspended else { return Unmanaged.passRetained(event) }

                if type == .keyDown && HotkeyService.fnWasPressed {
                    HotkeyService.otherKeyDuringFn = true
                    return Unmanaged.passRetained(event)
                }

                if type == .flagsChanged {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keyCode == Int64(HotkeyService.fnKeyCode) {
                        let fnDown = event.flags.contains(CGEventFlags(rawValue: 0x800000))
                        if fnDown {
                            HotkeyService.fnWasPressed = true
                            HotkeyService.otherKeyDuringFn = false
                            var mods: UInt32 = 0
                            let cgFlags = event.flags
                            if cgFlags.contains(.maskShift) { mods |= UInt32(shiftKey) }
                            if cgFlags.contains(.maskControl) { mods |= UInt32(controlKey) }
                            if cgFlags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
                            if cgFlags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
                            HotkeyService.fnModifiers = mods
                        } else if HotkeyService.fnWasPressed {
                            HotkeyService.fnWasPressed = false
                            if !HotkeyService.otherKeyDuringFn {
                                let capturedMods = HotkeyService.fnModifiers
                                guard let p = HotkeyService.pipeline else { return Unmanaged.passRetained(event) }
                                Task { @MainActor in
                                    let s = AppSettings.shared
                                    if s.transcribeHotkey.keyCode == HotkeyService.fnKeyCode &&
                                       s.transcribeHotkey.modifiers == capturedMods {
                                        await p.toggle(mode: .reformat)
                                    } else if s.translateHotkey.keyCode == HotkeyService.fnKeyCode &&
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
            print("[Typeless] Failed to create CGEventTap for Fn key — check Accessibility permission")
            return
        }
        fnTapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        fnRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[Typeless] Fn tap installed")
    }

    private static func removeFnTap() {
        if let source = fnRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            fnRunLoopSource = nil
        }
        if let port = fnTapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            fnTapPort = nil
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
        default:
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
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
