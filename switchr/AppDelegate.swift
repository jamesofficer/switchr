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

        HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
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
