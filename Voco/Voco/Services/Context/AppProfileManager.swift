import Foundation

enum AppProfileManager {
    struct BuiltInProfile {
        let appName: String
        let tone: String
        let formattingHints: String
    }

    private static let builtInProfiles: [String: BuiltInProfile] = [
        // Email clients - formal
        "com.apple.mail": BuiltInProfile(appName: "Apple Mail", tone: "formal", formattingHints: "Format as professional email text with proper paragraphs."),
        "com.microsoft.Outlook": BuiltInProfile(appName: "Outlook", tone: "formal", formattingHints: "Format as professional email text with proper paragraphs."),
        "com.google.Chrome": BuiltInProfile(appName: "Chrome", tone: "neutral", formattingHints: ""),

        // Messaging - casual
        "com.apple.MobileSMS": BuiltInProfile(appName: "Messages", tone: "casual", formattingHints: "Keep it short and conversational. No formal structure needed."),
        "com.tinyspeck.slackmacgap": BuiltInProfile(appName: "Slack", tone: "casual", formattingHints: "Keep it conversational. Use short paragraphs."),
        "ru.keepcoder.Telegram": BuiltInProfile(appName: "Telegram", tone: "casual", formattingHints: "Keep it short and conversational."),
        "com.hnc.Discord": BuiltInProfile(appName: "Discord", tone: "casual", formattingHints: "Keep it casual and conversational."),

        // Code editors - technical
        "com.apple.dt.Xcode": BuiltInProfile(appName: "Xcode", tone: "technical", formattingHints: "Use precise technical language. Format code comments appropriately."),
        "com.microsoft.VSCode": BuiltInProfile(appName: "VS Code", tone: "technical", formattingHints: "Use precise technical language. Format code comments appropriately."),
        "dev.zed.Zed": BuiltInProfile(appName: "Zed", tone: "technical", formattingHints: "Use precise technical language."),

        // Notes - neutral
        "com.apple.Notes": BuiltInProfile(appName: "Notes", tone: "neutral", formattingHints: "Use clear formatting with headers and bullet points when appropriate."),
        "md.obsidian": BuiltInProfile(appName: "Obsidian", tone: "neutral", formattingHints: "Use Markdown formatting. Support headers, bullet points, and links."),
        "com.notion.Notion": BuiltInProfile(appName: "Notion", tone: "neutral", formattingHints: "Use clear structure with headers and bullet points."),

        // Documents - formal
        "com.apple.iWork.Pages": BuiltInProfile(appName: "Pages", tone: "formal", formattingHints: "Format as properly structured document text."),
        "com.microsoft.Word": BuiltInProfile(appName: "Word", tone: "formal", formattingHints: "Format as properly structured document text."),
        "com.google.drivefs.finderhelper.findersync": BuiltInProfile(appName: "Google Docs", tone: "formal", formattingHints: "Format as properly structured document text."),
    ]

    static func builtInProfile(for bundleID: String) -> BuiltInProfile? {
        builtInProfiles[bundleID]
    }

    static var allBuiltInProfiles: [(bundleID: String, profile: BuiltInProfile)] {
        builtInProfiles.map { ($0.key, $0.value) }.sorted { $0.profile.appName < $1.profile.appName }
    }
}
