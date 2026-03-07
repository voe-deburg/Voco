import Foundation
import AppKit

@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    var updateAvailable = false
    var latestVersion = ""
    var downloadURL = ""
    var isChecking = false

    private init() {}

    func checkOnLaunch() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            await check(silent: true)
        }
    }

    func check(silent: Bool = false) async {
        print("[Voco] check(silent: \(silent)) called, isChecking=\(isChecking)")
        guard !isChecking else { print("[Voco] already checking, skipping"); return }
        isChecking = true
        defer { isChecking = false }

        do {
            let url = URL(string: "https://api.github.com/repos/\(AppConstants.githubRepo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let remote = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = AppConstants.appVersion
            print("[Voco] remote=\(remote), current=\(current)")

            if isNewer(remote: remote, current: current) {
                latestVersion = remote
                if let assets = json["assets"] as? [[String: Any]],
                   let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                   let browserURL = dmgAsset["browser_download_url"] as? String {
                    downloadURL = browserURL
                } else {
                    downloadURL = (json["html_url"] as? String) ?? "https://github.com/\(AppConstants.githubRepo)/releases/latest"
                }
                updateAvailable = true
                if !silent {
                    showUpdateAlert(version: remote)
                }
            } else {
                updateAvailable = false
                if !silent {
                    showUpToDateAlert(version: current)
                }
            }
        } catch {
            print("[Voco] Update check failed: \(error.localizedDescription)")
            if !silent {
                showErrorAlert()
            }
        }
    }

    nonisolated func checkInBackground() {
        print("[Voco] checkInBackground called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("[Voco] dispatched check")
            Task { @MainActor in
                await UpdateChecker.shared.check(silent: false)
            }
        }
    }

    func openDownload() {
        guard let url = URL(string: downloadURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showUpdateAlert(version: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Voco v\(version) is available. You are currently on v\(AppConstants.appVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            openDownload()
        }
    }

    private func showUpToDateAlert(version: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Voco v\(version) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    private func showErrorAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub. Please try again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
