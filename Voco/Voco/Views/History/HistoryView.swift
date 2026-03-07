import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \TranscriptionHistory.timestamp, order: .reverse) private var entries: [TranscriptionHistory]
    @Environment(\.modelContext) private var modelContext
    @State private var showClearConfirm = false
    @State private var expandedID: PersistentIdentifier?
    @State private var copiedID: PersistentIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear All") { showClearConfirm = true }
                    .controlSize(.small)
                    .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if entries.isEmpty {
                Spacer()
                Text("No history yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(entries) { entry in
                        let isExpanded = expandedID == entry.persistentModelID
                        VStack(alignment: .leading, spacing: 0) {
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        Text(entry.processedText)
                                            .font(.body)
                                            .textSelection(.enabled)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }

                                    if entry.rawText != entry.processedText {
                                        Text(entry.rawText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    HStack(spacing: 6) {
                                        if !entry.appName.isEmpty {
                                            Text(entry.appName)
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.quaternary)
                                                .clipShape(Capsule())
                                        }
                                        Text(entry.mode)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(entry.processedText, forType: .string)
                                            copiedID = entry.persistentModelID
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                if copiedID == entry.persistentModelID { copiedID = nil }
                                            }
                                        } label: {
                                            Image(systemName: copiedID == entry.persistentModelID ? "checkmark" : "doc.on.doc")
                                                .font(.caption)
                                                .foregroundStyle(copiedID == entry.persistentModelID ? .green : .secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy to clipboard")
                                    }
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Text(entry.processedText)
                                        .font(.body)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .layoutPriority(1)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedID = isExpanded ? nil : entry.persistentModelID
                            }
                        }
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.processedText, forType: .string)
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(entry)
                                try? modelContext.save()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 360, minHeight: 300)
        .alert("Clear all history?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                for entry in entries { modelContext.delete(entry) }
                try? modelContext.save()
            }
        }
    }
}
