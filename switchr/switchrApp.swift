//
//  switchrApp.swift
//  switchr
//

import SwiftUI

@main
struct switchrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("switchr", systemImage: "rectangle.stack") {
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
            // An accessory app isn't active, so the window would open behind
            // the frontmost app without this.
            NSApp.activate()
            openSettings()
        }
        Divider()
        Button("Quit switchr") {
            NSApp.terminate(nil)
        }
    }
}
