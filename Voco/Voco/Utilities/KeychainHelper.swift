import Foundation

/// Stores secrets in a file with restricted permissions (0600) in Application Support.
/// Avoids Keychain password dialogs that appear during development when code signing changes.
enum KeychainHelper {
    private static var secretsFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppConstants.bundleID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".secrets")
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveAll(_ secrets: [String: String]) throws {
        let data = try JSONEncoder().encode(secrets)
        try data.write(to: secretsFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretsFile.path
        )
    }

    static func save(key: String, value: String) throws {
        var secrets = loadAll()
        secrets[key] = value
        try saveAll(secrets)
    }

    static func load(key: String) -> String? {
        loadAll()[key]
    }

    static func delete(key: String) {
        var secrets = loadAll()
        secrets.removeValue(forKey: key)
        try? saveAll(secrets)
    }
}
