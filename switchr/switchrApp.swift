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
    let switcher: SwitcherPanelController

    var body: some View {
        Button("Show Switcher  ⌥Space") {
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
