import AppKit

enum ActiveAppDetector {
    struct AppInfo: Sendable {
        let name: String
        let bundleID: String
    }

    static func detect() -> AppInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppInfo(name: "", bundleID: "")
        }
        return AppInfo(
            name: app.localizedName ?? "",
            bundleID: app.bundleIdentifier ?? ""
        )
    }
}
