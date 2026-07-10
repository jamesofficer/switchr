//
//  SwitcherPanelController.swift
//  switchr
//
//  A Spotlight-style non-activating panel: it takes key presses without
//  activating this app, so dismissing returns you to where you were.
//

import AppKit
import SwiftUI

final class SwitcherPanelController: NSObject, NSWindowDelegate {
    private var panel: SwitcherPanel?
    private var panelScreen: NSScreen?
    private var rows: [SwitcherRow] = []
    private let letterAssigner = LetterAssigner()

    func toggle() {
        if panel != nil {
            hide()
        } else {
            show()
        }
    }

    func show() {
        rows = letterAssigner.assign(to: WindowManager.listWindows())

        let view = SwitcherView(
            rows: rows,
            hasPermission: WindowManager.hasAccessibilityPermission,
            onSelect: { [weak self] row in self?.select(row) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = SwitcherPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let animate = UserDefaults.standard.object(forKey: PrefKey.animatePanel) as? Bool ?? true
        panel.animationBehavior = animate ? .utilityWindow : .none
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.visibleFrame.midX - hosting.frame.width / 2,
                y: screen.visibleFrame.midY - hosting.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panelScreen = NSScreen.main
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        panelScreen = nil
        rows = []
    }

    private func select(_ row: SwitcherRow) {
        let moveTarget = UserDefaults.standard.bool(forKey: PrefKey.bringToCurrentScreen)
            ? panelScreen
            : nil
        let maximize = UserDefaults.standard.bool(forKey: PrefKey.maximizeOnFocus)
        hide()
        WindowManager.focus(row.window, movingTo: moveTarget, maximizing: maximize)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            hide()
            return true
        }
        guard !event.modifierFlags.contains(.command),
              let letter = event.charactersIgnoringModifiers?.lowercased().first,
              let row = rows.first(where: { $0.letter == letter }) else { return false }
        select(row)
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

final class SwitcherPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    // A borderless panel refuses key status unless we say otherwise.
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
