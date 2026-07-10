//
//  switchrApp.swift
//  switchr
//

import SwiftUI

@main
struct switchrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Switchr", systemImage: "rectangle.stack") {
            MenuContent(switcher: appDelegate.switcher)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PrefKey.leaderKeyCode) private var leaderKeyCode = Int(LeaderKey.default.keyCode)
    @AppStorage(PrefKey.leaderKeyModifiers) private var leaderModifiers = Int(LeaderKey.default.carbonModifiers)
    let switcher: SwitcherPanelController

    var body: some View {
        Button("Show Switcher  \(LeaderKey(keyCode: UInt32(leaderKeyCode), carbonModifiers: UInt32(leaderModifiers)).displayString)") {
            switcher.toggle()
        }
        Divider()
        Button("Settings…") {
            // An accessory app isn't active when the menu item fires, and the
            // menu is still tearing down, so openSettings() can lose the
            // activation race — sometimes the request is dropped outright and
            // no window appears. Keep re-requesting until the window is
            // actually visible, then force it front.
            presentSettings(retriesLeft: 8)
        }
        Divider()
        Button("Quit Switchr") {
            NSApp.terminate(nil)
        }
    }

    private var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("com_apple_SwiftUI_Settings") == true }
    }

    private func presentSettings(retriesLeft: Int) {
        // The plain activate() is a cooperative request that the frontmost
        // app can (and does) deny, leaving the settings window behind it.
        // The deprecated forceful variant is the only reliable way for an
        // accessory app to bring its own window to the front.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if let window = settingsWindow, window.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else if retriesLeft > 0 {
                presentSettings(retriesLeft: retriesLeft - 1)
            }
        }
    }
}
