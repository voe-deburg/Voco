import SwiftUI
import SwiftData

struct AppProfilesView: View {
    @Query(sort: \AppProfile.appName) private var profiles: [AppProfile]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false

    private let tones = ["formal", "casual", "technical", "neutral", "concise", "friendly"]

    /// Bundle IDs that have a custom override
    private var overriddenBundleIDs: Set<String> {
        Set(profiles.map(\.appBundleID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Custom Tones")

            if profiles.isEmpty {
                Text("No custom tones yet. Modify a built-in tone below or add a new one.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(profiles) { profile in
                    toneRow(
                        name: profile.appName,
                        detail: profile.appBundleID,
                        tone: profile.tone,
                        onToneChange: { newTone in
                            profile.tone = newTone
                            try? modelContext.save()
                        },
                        onDelete: {
                            modelContext.delete(profile)
                            try? modelContext.save()
                        }
                    )
                }
            }

            HStack {
                Button("Add Tone...") { showingAddSheet = true }
                    .controlSize(.small)
            }
            .padding(.top, 8)

            SettingsDivider()

            SectionHeader("Built-in Tones")
            SettingsDescription("Change a tone to create a custom override.")

            ForEach(AppProfileManager.allBuiltInProfiles, id: \.bundleID) { item in
                let override = profiles.first(where: { $0.appBundleID == item.bundleID })
                let isOverridden = override != nil
                toneRow(
                    name: item.profile.appName,
                    detail: item.bundleID,
                    tone: override?.tone ?? item.profile.tone,
                    isOverridden: isOverridden,
                    onToneChange: { newTone in
                        guard newTone != item.profile.tone else {
                            // Same as built-in default — remove override if one exists
                            if let existing = profiles.first(where: { $0.appBundleID == item.bundleID }) {
                                modelContext.delete(existing)
                                try? modelContext.save()
                            }
                            return
                        }
                        if let existing = profiles.first(where: { $0.appBundleID == item.bundleID }) {
                            existing.tone = newTone
                        } else {
                            let override = AppProfile(
                                appBundleID: item.bundleID,
                                appName: item.profile.appName,
                                tone: newTone,
                                formattingHints: item.profile.formattingHints
                            )
                            modelContext.insert(override)
                        }
                        try? modelContext.save()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingAddSheet) {
            AddProfileSheet()
        }
    }

    private func toneRow(
        name: String,
        detail: String,
        tone: String,
        isOverridden: Bool = false,
        onToneChange: @escaping (String) -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.body)
                    if isOverridden {
                        Text("(modified)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { tone },
                set: { onToneChange($0) }
            )) {
                ForEach(tones, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
    }
}

struct AddProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var appName = ""
    @State private var bundleID = ""
    @State private var tone = "neutral"
    @State private var hints = ""

    private let tones = ["formal", "casual", "technical", "neutral", "concise", "friendly"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Tone").font(.headline)

            SettingsRow("App Name:") {
                TextField("e.g. Slack", text: $appName)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsRow("Bundle ID:") {
                TextField("e.g. com.tinyspeck.slackmacgap", text: $bundleID)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsRow("Tone:") {
                Picker("", selection: $tone) {
                    ForEach(tones, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            SettingsRow("Hints:") {
                TextField("Formatting instructions", text: $hints)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let profile = AppProfile(appBundleID: bundleID, appName: appName, tone: tone, formattingHints: hints)
                    modelContext.insert(profile)
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appName.isEmpty || bundleID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
