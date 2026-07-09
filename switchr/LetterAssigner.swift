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
import Foundation

struct SwitcherRow: Identifiable {
    let letter: Character?
    let window: WindowInfo
    var id: UUID { window.id }
}

final class LetterAssigner {
    private static let defaultsKey = "appLetterAssignments"
    private static let pool = Array("asdfghjklqwertyuiopzxcvbnm1234567890")

    private var persisted: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    func assign(to windows: [WindowInfo]) -> [SwitcherRow] {
        var taken = Set<Character>()
        var map = persisted

        // First pass: primary window per app claims its persisted letter, in
        // list order, so conflicts between stale assignments resolve the same
        // way every time.
        var primaryLetters: [String: Character] = [:]
        var seenApps = Set<String>()
        for window in windows {
            guard let bundleID = window.app.bundleIdentifier, !seenApps.contains(bundleID) else { continue }
            seenApps.insert(bundleID)
            if let stored = map[bundleID]?.first, !taken.contains(stored) {
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

        // Build rows: first window of each app gets the stable letter, the
        // rest draw from whatever is left in the pool.
        var usedPrimary = Set<String>()
        var poolIterator = Self.pool.filter { !taken.contains($0) }.makeIterator()
        return windows.map { window in
            let bundleID = window.app.bundleIdentifier ?? ""
            if !usedPrimary.contains(bundleID), let letter = primaryLetters[bundleID] {
                usedPrimary.insert(bundleID)
                return SwitcherRow(letter: letter, window: window)
            }
            return SwitcherRow(letter: poolIterator.next(), window: window)
        }
    }
}
