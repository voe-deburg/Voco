import Foundation
import SwiftData

@Model
final class DictionaryEntry {
    var word: String
    var pronunciationHint: String
    var category: String
    var createdAt: Date

    init(word: String, pronunciationHint: String = "", category: String = "General") {
        self.word = word
        self.pronunciationHint = pronunciationHint
        self.category = category
        self.createdAt = Date()
    }
}
