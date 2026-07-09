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

    static func focus(_ window: WindowInfo) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)

        // Setting AXFrontmost works from a background app where cooperative
        // activation can be refused; NSRunningApplication.activate is a backup.
        let axApp = AXUIElementCreateApplication(window.app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        window.app.activate()
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
