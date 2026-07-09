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
            Button("Show Switcher  ⌥Space") {
                appDelegate.switcher.toggle()
            }
            Divider()
            Button("Quit switchr") {
                NSApp.terminate(nil)
            }
        }
    }
}
