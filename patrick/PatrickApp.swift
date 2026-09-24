import AppKit
import SwiftUI

@main
struct PatrickApp: App {
    @NSApplicationDelegateAdaptor(PatrickAppDelegate.self) private var appDelegate
    @StateObject private var accessStore = SafariAccessStore()
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup("Patrick", id: "main") {
            PatrickRootView(hasFinishedOnboarding: $hasFinishedOnboarding)
                .environmentObject(accessStore)
                .background(DisableWindowRestoration())
        }
        .defaultSize(width: 520, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(accessStore)
        }
    }
}

private struct PatrickRootView: View {
    @Binding var hasFinishedOnboarding: Bool

    var body: some View {
        if hasFinishedOnboarding {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 520, minHeight: 640)
        } else {
            OnboardingView {
                hasFinishedOnboarding = true
            }
        }
    }
}

private struct DisableWindowRestoration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isRestorable = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class PatrickAppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            Self.presentMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.presentMainWindow()
        }
        return true
    }

    private static func presentMainWindow() {
        let windows = NSApp.windows.filter { $0.canBecomeMain && $0.styleMask.contains(.titled) }
        if let window = windows.first(where: \.isVisible) ?? windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
