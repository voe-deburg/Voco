import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let pipeline = VoiceInputPipeline()
    private var windowObservers: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyService.register(pipeline: pipeline)

        // Install minimal main menu for Cmd+W support (LSUIElement apps have no menu bar)
        let mainMenu = NSMenu()
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        NSApp.mainMenu = mainMenu

        // Switch back to accessory when all windows close
        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkAndHideFromDock()
                }
            }
        )
    }

    func activateAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkAndHideFromDock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible && !window.title.isEmpty && !(window is NSPanel)
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@main
struct OpenTypeLessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var didOpenSettings = false

    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                DictionaryEntry.self,
                TranscriptionHistory.self,
                AppProfile.self,
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(pipeline: appDelegate.pipeline)
        } label: {
            Label {
                Text("OpenTypeLess")
            } icon: {
                if appDelegate.pipeline.state.isRecording {
                    Image(systemName: "mic.fill")
                } else if case .error = appDelegate.pipeline.state {
                    Image(systemName: "exclamationmark.triangle.fill")
                } else {
                    Image(nsImage: {
                        let img = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
                        img.isTemplate = true
                        return img
                    }())
                }
            }
            .onAppear {
                appDelegate.pipeline.setModelContext(container.mainContext)
                if !didOpenSettings {
                    didOpenSettings = true
                    openWindow(id: "settings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appDelegate.activateAsRegularApp()
                        for window in NSApp.windows where window.title == "Settings" {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .modelContainer(container)
        }
        .windowResizability(.contentSize)

        Window("History", id: "history") {
            HistoryView()
                .modelContainer(container)
        }
        .defaultSize(width: 500, height: 400)

        Window("Onboarding", id: "onboarding") {
            OnboardingView()
                .modelContainer(container)
        }
        .windowResizability(.contentSize)
    }
}
