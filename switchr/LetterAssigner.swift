//
//  LetterAssigner.swift
//  switchr
//
//  Assigns each app a stable letter, persisted by bundle identifier so the
//  same app keeps the same key across launches. Preference order: letters of
//  the app's own name (Safari -> s, then a, f, ...), then the free pool.
//  Extra windows of an app get session-only letters from the pool.
//

import AppKit
import ApplicationServices
import Foundation

struct SwitcherRow: Identifiable {
    let letter: Character?
    let window: WindowInfo
    var id: UUID { window.id }
}

/// Identifies a window across enumerations: AXUIElements for the same window
/// compare equal via CFEqual for as long as the window exists.
private struct WindowKey: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

final class LetterAssigner {
    private static let defaultsKey = "appLetterAssignments"
    private static let pool = Array("asdfghjklqwertyuiopzxcvbnm1234567890")

    // AX lists an app's windows in z-order, which reshuffles every time focus
    // changes within the app. Remember, per living window, its row position
    // and letter so both stay put for as long as the window is open.
    private var sessionLetters: [WindowKey: Character] = [:]
    private var firstSeen: [WindowKey: Int] = [:]
    private var seenCounter = 0

    private var persisted: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    func assign(to windows: [WindowInfo]) -> [SwitcherRow] {
        let customBindings = CustomBindingsStore.shared
        // Custom letters are reserved up front, even for apps that aren't
        // running, so automatic assignment can never steal them.
        var taken = customBindings.reservedLetters
        var map = persisted

        // First pass: custom bindings win, then the primary window per app
        // claims its persisted letter, in list order, so conflicts between
        // stale assignments resolve the same way every time.
        var primaryLetters: [String: Character] = [:]
        var seenApps = Set<String>()
        for window in windows {
            guard let bundleID = window.app.bundleIdentifier, !seenApps.contains(bundleID) else { continue }
            seenApps.insert(bundleID)
            if let custom = customBindings.letter(for: bundleID) {
                primaryLetters[bundleID] = custom
            } else if let stored = map[bundleID]?.first, !taken.contains(stored) {
                primaryLetters[bundleID] = stored
                taken.insert(stored)
            }
        }

        // Second pass: apps without a usable persisted letter get one derived
        // from their name, falling back to the pool, and it's persisted.
        for window in windows {
            guard let bundleID = window.app.bundleIdentifier, primaryLetters[bundleID] == nil else { continue }
            let candidates = window.appName.lowercased().filter(\.isLetter) + Self.pool
            guard let letter = candidates.first(where: { !taken.contains($0) }) else { continue }
            primaryLetters[bundleID] = letter
            taken.insert(letter)
            map[bundleID] = String(letter)
        }
        persisted = map

        // Order an app's windows by when they were first seen, not by the
        // z-order AX reports, so rows don't reshuffle as focus moves.
        for window in windows {
            let key = WindowKey(element: window.axWindow)
            if firstSeen[key] == nil {
                firstSeen[key] = seenCounter
                seenCounter += 1
            }
        }
        var appOrder: [String: Int] = [:]
        for window in windows {
            let bundleID = window.app.bundleIdentifier ?? ""
            if appOrder[bundleID] == nil { appOrder[bundleID] = appOrder.count }
        }
        let ordered = windows.sorted { lhs, rhs in
            let lhsApp = appOrder[lhs.app.bundleIdentifier ?? ""] ?? 0
            let rhsApp = appOrder[rhs.app.bundleIdentifier ?? ""] ?? 0
            if lhsApp != rhsApp { return lhsApp < rhsApp }
            return (firstSeen[WindowKey(element: lhs.axWindow)] ?? 0)
                < (firstSeen[WindowKey(element: rhs.axWindow)] ?? 0)
        }

        // Per app, the primary letter belongs to the window that held it last
        // time (falling back to the oldest window), and every other window
        // keeps its previous letter too, so switching between two windows of
        // one app never swaps their keys.
        var holders: [String: WindowKey] = [:]
        for (bundleID, group) in Dictionary(grouping: ordered, by: { $0.app.bundleIdentifier ?? "" }) {
            guard let primary = primaryLetters[bundleID] else { continue }
            let holder = group.first { sessionLetters[WindowKey(element: $0.axWindow)] == primary } ?? group.first
            if let holder { holders[bundleID] = WindowKey(element: holder.axWindow) }
        }

        var used = taken // reserved letters plus every app's primary letter
        var newSessionLetters: [WindowKey: Character] = [:]
        let rows = ordered.map { window in
            let bundleID = window.app.bundleIdentifier ?? ""
            let key = WindowKey(element: window.axWindow)
            let letter: Character?
            if holders[bundleID] == key {
                letter = primaryLetters[bundleID]
            } else if let previous = sessionLetters[key], !used.contains(previous) {
                letter = previous
                used.insert(previous)
            } else {
                letter = Self.pool.first { !used.contains($0) }
                if let letter { used.insert(letter) }
            }
            if let letter { newSessionLetters[key] = letter }
            return SwitcherRow(letter: letter, window: window)
        }

        // Forget windows that have closed so the maps don't grow unbounded.
        sessionLetters = newSessionLetters
        let currentKeys = Set(ordered.map { WindowKey(element: $0.axWindow) })
        firstSeen = firstSeen.filter { currentKeys.contains($0.key) }

        return rows
    }
}
