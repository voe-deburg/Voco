import Foundation
import SwiftData

@Model
final class TranscriptionHistory {
    var rawText: String
    var processedText: String
    var timestamp: Date
    var appName: String
    var mode: String
    var language: String

    init(rawText: String, processedText: String, appName: String = "", mode: String = "", language: String = "en") {
        self.rawText = rawText
        self.processedText = processedText
        self.timestamp = Date()
        self.appName = appName
        self.mode = mode
        self.language = language
    }
}
