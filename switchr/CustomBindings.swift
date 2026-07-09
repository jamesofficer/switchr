//
//  CustomBindings.swift
//  switchr
//
//  User-defined app → key bindings, managed in Settings. Custom letters
//  always win over (and are never taken by) automatic assignments.
//

import AppKit
import Combine
import Foundation

struct CustomBinding: Codable, Identifiable, Equatable {
    var bundleID: String
    var appName: String
    var appPath: String
    var key: String

    var id: String { bundleID }
    var letter: Character? { key.first }
}

final class CustomBindingsStore: ObservableObject {
    static let shared = CustomBindingsStore()
    private static let defaultsKey = "customAppBindings"

    @Published private(set) var bindings: [CustomBinding]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([CustomBinding].self, from: data) {
            bindings = decoded
        } else {
            bindings = []
        }
    }

    func add(_ binding: CustomBinding) {
        bindings.removeAll { $0.bundleID == binding.bundleID }
        bindings.append(binding)
        bindings.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        save()
    }

    func remove(_ binding: CustomBinding) {
        bindings.removeAll { $0.id == binding.id }
        save()
    }

    func letter(for bundleID: String) -> Character? {
        bindings.first { $0.bundleID == bundleID }?.letter
    }

    /// Letters that automatic assignment must never hand out, whether or not
    /// the bound app is currently running.
    var reservedLetters: Set<Character> {
        Set(bindings.compactMap(\.letter))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
