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
            // menu is still tearing down, so opening the window in the same
            // runloop pass loses the activation race and the window stays
            // behind the frontmost app. Activate, open on the next pass, and
            // force the window to key.
            NSApp.activate()
            DispatchQueue.main.async {
                openSettings()
                NSApp.activate()
                NSApp.windows
                    .first { $0.identifier?.rawValue.hasPrefix("com_apple_SwiftUI_Settings") == true }?
                    .makeKeyAndOrderFront(nil)
            }
        }
        Divider()
        Button("Quit Switchr") {
            NSApp.terminate(nil)
        }
    }
}
