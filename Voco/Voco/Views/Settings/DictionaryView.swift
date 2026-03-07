import SwiftUI
import SwiftData

struct DictionaryView: View {
    @Query(sort: \DictionaryEntry.word) private var entries: [DictionaryEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    @State private var searchText = ""

    private var filteredEntries: [DictionaryEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.word.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search dictionary...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            SettingsDivider()

            if filteredEntries.isEmpty {
                Text(entries.isEmpty
                    ? "No dictionary entries yet. Add custom words, names, or technical terms to improve transcription."
                    : "No matches for \"\(searchText)\".")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.vertical, 8)
            } else {
                ForEach(filteredEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.word).font(.body)
                            if !entry.pronunciationHint.isEmpty {
                                Text(entry.pronunciationHint)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(entry.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        Button(role: .destructive) {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            SettingsDivider()

            HStack {
                Text("\(entries.count) entries")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
                Button("Add Word...") { showingAddSheet = true }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingAddSheet) {
            AddDictionaryEntrySheet()
        }
    }
}

struct AddDictionaryEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var pronunciationHint = ""
    @State private var category = "General"

    private let categories = ["General", "Name", "Technical", "Brand", "Acronym"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Dictionary Entry").font(.headline)

            SettingsRow("Word:") {
                TextField("e.g. Kubernetes", text: $word)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsRow("Hint:") {
                TextField("How it sounds when spoken", text: $pronunciationHint)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsRow("Category:") {
                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let entry = DictionaryEntry(word: word, pronunciationHint: pronunciationHint, category: category)
                    modelContext.insert(entry)
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(word.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
