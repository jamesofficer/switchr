//
//  WindowManager.swift
//  switchr
//
//  Enumerates and focuses other apps' windows via the Accessibility API.
//  Requires the Accessibility permission and a non-sandboxed build.
//

import AppKit
import ApplicationServices

struct WindowInfo: Identifiable {
    let id = UUID()
    let app: NSRunningApplication
    let axWindow: AXUIElement
    let title: String
    let isMinimized: Bool

    var appName: String { app.localizedName ?? "Unknown" }
    var displayTitle: String { title.isEmpty ? appName : title }
}

enum WindowManager {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// All standard windows of regular apps, grouped per app, apps sorted by
    /// name so the list order is stable across invocations.
    static func listWindows() -> [WindowInfo] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != NSRunningApplication.current.processIdentifier }
            .sorted { ($0.localizedName ?? "") .localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }

        var result: [WindowInfo] = []
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for window in windows {
                guard stringAttribute(window, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
                result.append(WindowInfo(
                    app: app,
                    axWindow: window,
                    title: stringAttribute(window, kAXTitleAttribute) ?? "",
                    isMinimized: boolAttribute(window, kAXMinimizedAttribute)
                ))
            }
        }
        return result
    }

    static func focus(_ window: WindowInfo, movingTo screen: NSScreen? = nil, maximizing: Bool = false) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if maximizing {
            maximize(window, on: screen)
        } else if let screen {
            move(window, to: screen)
        }
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)

        // Setting AXFrontmost works from a background app where cooperative
        // activation can be refused; NSRunningApplication.activate is a backup.
        let axApp = AXUIElementCreateApplication(window.app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        window.app.activate()
    }

    /// Resizes a window to fill the visible frame (edge to edge, below the
    /// menu bar and above the Dock) of the given screen, or of the screen the
    /// window is currently on. This is a plain resize, not macOS full screen.
    private static func maximize(_ window: WindowInfo, on screen: NSScreen?) {
        guard let frame = axFrame(of: window.axWindow) else { return }
        let targetScreen = screen
            ?? NSScreen.screens.first { axRect(from: $0.visibleFrame).contains(CGPoint(x: frame.midX, y: frame.midY)) }
            ?? NSScreen.main
        guard let targetScreen else { return }

        let destination = axRect(from: targetScreen.visibleFrame)
        guard frame != destination else { return }

        var origin = destination.origin
        var size = destination.size
        if let positionValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window.axWindow, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window.axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Moves a window onto the given screen, preserving its position relative
    /// to its current screen's visible area (a window in the top-right corner
    /// of one monitor lands in the top-right of the target monitor).
    private static func move(_ window: WindowInfo, to screen: NSScreen) {
        guard let frame = axFrame(of: window.axWindow) else { return }
        let destination = axRect(from: screen.visibleFrame)
        guard !destination.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return }

        let source = NSScreen.screens
            .map { axRect(from: $0.visibleFrame) }
            .first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            ?? frame

        var size = frame.size
        size.width = min(size.width, destination.width)
        size.height = min(size.height, destination.height)

        // Fractional offset within the source screen's free space, clamped.
        func fraction(_ position: CGFloat, _ min: CGFloat, _ free: CGFloat) -> CGFloat {
            free > 0 ? Swift.max(0, Swift.min(1, (position - min) / free)) : 0
        }
        let fx = fraction(frame.minX, source.minX, source.width - frame.width)
        let fy = fraction(frame.minY, source.minY, source.height - frame.height)
        var origin = CGPoint(
            x: destination.minX + fx * (destination.width - size.width),
            y: destination.minY + fy * (destination.height - size.height)
        )

        if let positionValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window.axWindow, kAXPositionAttribute as CFString, positionValue)
        }
        if size != frame.size, let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window.axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// AX uses global coordinates with the origin at the primary screen's
    /// top-left, y increasing downward; Cocoa's origin is the bottom-left.
    private static func axRect(from cocoaRect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: cocoaRect.minX,
            y: primaryHeight - cocoaRect.maxY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    private static func axFrame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}
