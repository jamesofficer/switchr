//
//  SettingsView.swift
//  switchr
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum PrefKey {
    static let bringToCurrentScreen = "bringWindowToCurrentScreen"
    static let leaderKeyCode = "leaderKeyCode"
    static let leaderKeyModifiers = "leaderKeyModifiers"
}

struct SettingsView: View {
    @AppStorage(PrefKey.bringToCurrentScreen) private var bringToCurrentScreen = false
    @AppStorage(PrefKey.leaderKeyCode) private var leaderKeyCode = Int(LeaderKey.default.keyCode)
    @AppStorage(PrefKey.leaderKeyModifiers) private var leaderModifiers = Int(LeaderKey.default.carbonModifiers)

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    private var leaderKey: LeaderKey {
        LeaderKey(keyCode: UInt32(leaderKeyCode), carbonModifiers: UInt32(leaderModifiers))
    }

    var body: some View {
        Form {
            Section("Leader Key") {
                HStack {
                    Text(isRecording ? "Press shortcut…" : leaderKey.displayString)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button(isRecording ? "Cancel" : "Record Shortcut") {
                        isRecording ? stopRecording() : startRecording()
                    }
                }
                Text(isRecording
                     ? "Press a key combination including ⌃, ⌥ or ⌘. Esc cancels."
                     : "Press this shortcut anywhere to open the switcher.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Bring window to current screen", isOn: $bringToCurrentScreen)
                Text("When enabled, switching moves the window to the screen the switcher is on, keeping its relative position. When off, the window is focused wherever it already is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 340)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        // Release the current hotkey, otherwise pressing it now would open
        // the switcher instead of being captured by the recorder.
        HotKeyCenter.shared.pause()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
        HotKeyCenter.shared.resume()
    }

    private func capture(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.control, .option, .command]).isEmpty {
            stopRecording()
            return nil
        }
        let modifiers = LeaderKey.carbonModifiers(from: event.modifierFlags)
        // Require a real modifier so bare typing keys can't become the leader.
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            NSSound.beep()
            return nil
        }
        leaderKeyCode = Int(event.keyCode)
        leaderModifiers = Int(modifiers)
        stopRecording()
        NotificationCenter.default.post(name: .leaderKeyChanged, object: nil)
        return nil
    }
}
