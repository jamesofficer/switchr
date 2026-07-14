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
    private var closedApps: [CustomBinding] = []
    private let letterAssigner = LetterAssigner()

    func toggle() {
        if panel != nil {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let windows = WindowManager.listWindows()
        rows = letterAssigner.assign(to: windows)

        // Bound apps with no open windows appear at the bottom; their key
        // launches (or re-activates) the app instead of focusing a window.
        let showClosed = UserDefaults.standard.object(forKey: PrefKey.showClosedApps) as? Bool ?? true
        if showClosed {
            let openBundleIDs = Set(windows.compactMap { $0.app.bundleIdentifier })
            closedApps = CustomBindingsStore.shared.bindings.filter { !openBundleIDs.contains($0.bundleID) }
        } else {
            closedApps = []
        }

        let view = SwitcherView(
            rows: rows,
            closedApps: closedApps,
            hasPermission: WindowManager.hasAccessibilityPermission,
            onSelect: { [weak self] row in self?.select(row) },
            onLaunch: { [weak self] binding in self?.launch(binding) }
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
        closedApps = []
    }

    private func launch(_ binding: CustomBinding) {
        hide()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: binding.appPath),
            configuration: NSWorkspace.OpenConfiguration()
        )
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
              let letter = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if let row = rows.first(where: { $0.letter == letter }) {
            select(row)
            return true
        }
        if let binding = closedApps.first(where: { $0.letter == letter }) {
            launch(binding)
            return true
        }
        return false
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
