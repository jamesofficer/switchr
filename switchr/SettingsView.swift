//
//  SettingsView.swift
//  switchr
//

import SwiftUI

enum PrefKey {
    static let bringToCurrentScreen = "bringWindowToCurrentScreen"
}

struct SettingsView: View {
    @AppStorage(PrefKey.bringToCurrentScreen) private var bringToCurrentScreen = false

    var body: some View {
        Form {
            Section {
                Toggle("Bring window to current screen", isOn: $bringToCurrentScreen)
                Text("When enabled, switching moves the window to the screen the switcher is on, keeping its relative position. When off, the window is focused wherever it already is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Leader key", value: "⌥ Space")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
