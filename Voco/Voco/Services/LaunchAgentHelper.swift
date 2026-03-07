import Foundation

enum LaunchAgentHelper {
    private static let label = "com.voco.launcher"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var appPath: String {
        Bundle.main.bundlePath
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["open", appPath],
                "RunAtLoad": true,
            ]
            let dir = plistURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: plistURL, atomically: true)
            print("[Voco] Launch agent installed: \(plistURL.path)")
        } else {
            try? FileManager.default.removeItem(at: plistURL)
            print("[Voco] Launch agent removed")
        }
    }
}
