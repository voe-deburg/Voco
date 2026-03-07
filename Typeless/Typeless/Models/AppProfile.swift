import Foundation
import SwiftData

@Model
final class AppProfile {
    var appBundleID: String
    var appName: String
    var tone: String  // "formal", "casual", "technical"
    var formattingHints: String

    init(appBundleID: String, appName: String, tone: String = "neutral", formattingHints: String = "") {
        self.appBundleID = appBundleID
        self.appName = appName
        self.tone = tone
        self.formattingHints = formattingHints
    }
}
