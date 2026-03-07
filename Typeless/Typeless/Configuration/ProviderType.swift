import Foundation

enum ProcessingMode: String, CaseIterable, Codable, Sendable {
    case reformat = "Reformat"
    case reformatAndTranslate = "Reformat + Translate"
}
