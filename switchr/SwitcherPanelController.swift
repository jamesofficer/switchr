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
    private var revealWork: DispatchWorkItem?
    // True once a window was selected with the leader modifiers still held:
    // the panel stays up so further letters keep switching, until release.
    private var isFlicking = false
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
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onFlagsChanged = { [weak self] event in self?.handleFlags(event) }

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.visibleFrame.midX - hosting.frame.width / 2,
                y: screen.visibleFrame.midY - hosting.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        panelScreen = NSScreen.main
        self.panel = panel

        // Grace period: the panel takes key immediately so letters land right
        // away, but stays invisible for a beat. A fast leader+letter chord
        // switches without the panel ever appearing; it only shows on
        // hesitation.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        let work = DispatchWorkItem { [weak self] in self?.reveal() }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func reveal() {
        guard let panel else { return }
        let animate = UserDefaults.standard.object(forKey: PrefKey.animatePanel) as? Bool ?? true
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    func hide() {
        revealWork?.cancel()
        revealWork = nil
        isFlicking = false
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
        hide()
        focus(row)
    }

    /// Switch focus but keep the session alive: the target app takes key
    /// status when it activates, so reclaim it for the panel (nonactivating
    /// panels may hold key while another app stays active) unless the leader
    /// modifiers were released in the gap.
    private func flick(to row: SwitcherRow) {
        isFlicking = true
        focus(row)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let panel = self.panel else { return }
            if NSEvent.modifierFlags.contains(LeaderKey.current.cocoaModifiers) {
                panel.makeKey()
            } else {
                self.hide()
            }
        }
    }

    private func focus(_ row: SwitcherRow) {
        let moveTarget = UserDefaults.standard.bool(forKey: PrefKey.bringToCurrentScreen)
            ? panelScreen
            : nil
        let maximize = UserDefaults.standard.bool(forKey: PrefKey.maximizeOnFocus)
        WindowManager.focus(row.window, movingTo: moveTarget, maximizing: maximize)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            hide()
            return true
        }
        guard let letter = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        // Letters pressed with the leader modifiers still held flick between
        // windows without closing; a plain letter selects and closes.
        let leaderFlags = LeaderKey.current.cocoaModifiers
        let holdingLeader = !leaderFlags.isEmpty && event.modifierFlags.contains(leaderFlags)
        guard holdingLeader || !event.modifierFlags.contains(.command) else { return false }

        if let row = rows.first(where: { $0.letter == letter }) {
            holdingLeader ? flick(to: row) : select(row)
            return true
        }
        if let binding = closedApps.first(where: { $0.letter == letter }) {
            launch(binding)
            return true
        }
        return false
    }

    private func handleFlags(_ event: NSEvent) {
        guard isFlicking,
              !event.modifierFlags.contains(LeaderKey.current.cocoaModifiers) else { return }
        hide()
    }

    func windowDidResignKey(_ notification: Notification) {
        // During a flick the focused app steals key; take it back rather than
        // closing, as long as the leader modifiers are still held.
        if isFlicking, panel != nil, NSEvent.modifierFlags.contains(LeaderKey.current.cocoaModifiers) {
            DispatchQueue.main.async { [weak self] in self?.panel?.makeKey() }
            return
        }
        hide()
    }
}

final class SwitcherPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    // A borderless panel refuses key status unless we say otherwise.
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
        super.flagsChanged(with: event)
    }
}
