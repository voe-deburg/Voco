import AVFoundation
import Cocoa

enum PermissionsService {
    static func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func checkAccessibilityPermission() -> Bool {
        AccessibilityHelper.isAccessibilityEnabled
    }
}
