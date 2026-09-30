import SwiftUI
import AppKit

@main
struct ZoomStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // One model for the process lifetime (SwiftUI may evaluate App init more than once).
    @StateObject private var model = AppModel.shared

    init() {
        // No Dock icon even when run outside the .app bundle (Info.plist sets LSUIElement too).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// Opening ZoomStat again (Finder, Spotlight, Launchpad) shows the statistics in a
/// normal window — useful when the menu bar item is hidden by the notch or a
/// full-screen Zoom meeting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { showWindow() }
        return false
    }

    @MainActor
    func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: PopoverView().environmentObject(AppModel.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "ZoomStat"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("ZoomStatWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
