import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, speech, ai, tones, dictionary

    var label: String {
        switch self {
        case .general: "General"
        case .speech: "Speech"
        case .ai: "AI"
        case .tones: "Tones"
        case .dictionary: "Dictionary"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .speech: "mic"
        case .ai: "brain"
        case .tones: "speaker.wave.2"
        case .dictionary: "book"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar-style tab bar
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general: GeneralSettingsView()
                    case .speech: STTSettingsView()
                    case .ai: LLMSettingsView()
                    case .tones: AppProfilesView()
                    case .dictionary: DictionaryView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 460, height: 520)
    }
}

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16))
                    .frame(height: 18)
                Text(tab.label)
                    .font(.caption2)
            }
            .frame(width: 56, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        )
    }
}

// MARK: - Shared Settings Components

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.bottom, 8)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 10)
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            content
        }
        .padding(.vertical, 3)
    }
}

struct SettingsDescription: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}
