//
//  AppDelegate.swift
//  switchr
//

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    let switcher = SwitcherPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptForAccessibilityIfNeeded()
        registerLeaderKey()

        NotificationCenter.default.addObserver(
            forName: .leaderKeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.registerLeaderKey()
            }
        }
    }

    func registerLeaderKey() {
        let key = LeaderKey.current
        HotKeyCenter.shared.register(
            keyCode: key.keyCode,
            modifiers: key.carbonModifiers
        ) { [weak self] in
            self?.switcher.toggle()
        }
    }

    private func promptForAccessibilityIfNeeded() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
