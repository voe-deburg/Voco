import Foundation
import SwiftData

@MainActor
final class PersonalDictionaryService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func addEntry(word: String, pronunciationHint: String = "", category: String = "General") {
        let entry = DictionaryEntry(word: word, pronunciationHint: pronunciationHint, category: category)
        modelContext.insert(entry)
        try? modelContext.save()
    }

    func deleteEntry(_ entry: DictionaryEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    func updateEntry(_ entry: DictionaryEntry, word: String, pronunciationHint: String, category: String) {
        entry.word = word
        entry.pronunciationHint = pronunciationHint
        entry.category = category
        try? modelContext.save()
    }

    func fetchAll() -> [DictionaryEntry] {
        let descriptor = FetchDescriptor<DictionaryEntry>(sortBy: [SortDescriptor(\.word)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allTerms() -> [String] {
        fetchAll().map { $0.word }
    }
}
