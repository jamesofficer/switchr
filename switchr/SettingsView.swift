//
//  SettingsView.swift
//  switchr
//

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

enum PrefKey {
    static let bringToCurrentScreen = "bringWindowToCurrentScreen"
    static let leaderKeyCode = "leaderKeyCode"
    static let leaderKeyModifiers = "leaderKeyModifiers"
}

struct SettingsView: View {
    @AppStorage(PrefKey.bringToCurrentScreen) private var bringToCurrentScreen = false
    @AppStorage(PrefKey.leaderKeyCode) private var leaderKeyCode = Int(LeaderKey.default.keyCode)
    @AppStorage(PrefKey.leaderKeyModifiers) private var leaderModifiers = Int(LeaderKey.default.carbonModifiers)

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    @ObservedObject private var customBindings = CustomBindingsStore.shared
    @State private var pendingApp: PendingApp?

    private var leaderKey: LeaderKey {
        LeaderKey(keyCode: UInt32(leaderKeyCode), carbonModifiers: UInt32(leaderModifiers))
    }

    var body: some View {
        Form {
            Section("Leader Key") {
                HStack {
                    Text(isRecording ? "Press shortcut…" : leaderKey.displayString)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button(isRecording ? "Cancel" : "Record Shortcut") {
                        isRecording ? stopRecording() : startRecording()
                    }
                }
                Text(isRecording
                     ? "Press a key combination including ⌃, ⌥ or ⌘. Esc cancels."
                     : "Press this shortcut anywhere to open the switcher.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("App Bindings") {
                if customBindings.bindings.isEmpty {
                    Text("No custom bindings. Apps you add here always get your chosen key; other apps are assigned letters automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(customBindings.bindings) { binding in
                    HStack(spacing: 10) {
                        Text(binding.key.uppercased())
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Image(nsImage: NSWorkspace.shared.icon(forFile: binding.appPath))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(binding.appName)
                        Spacer()
                        Button {
                            customBindings.remove(binding)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove binding")
                    }
                }
                Button {
                    pickApp()
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
            }

            Section("Behavior") {
                Toggle("Bring window to current screen", isOn: $bringToCurrentScreen)
                Text("When enabled, switching moves the window to the screen the switcher is on, keeping its relative position. When off, the window is focused wherever it already is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 540)
        .onDisappear { stopRecording() }
        .sheet(item: $pendingApp) { app in
            BindingKeySheet(app: app)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app to bind a key to"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            let alert = NSAlert()
            alert.messageText = "Not a valid app"
            alert.informativeText = "Couldn't read a bundle identifier from \(url.lastPathComponent)."
            alert.runModal()
            return
        }
        pendingApp = PendingApp(
            bundleID: bundleID,
            name: FileManager.default.displayName(atPath: url.path),
            path: url.path
        )
    }

    private func startRecording() {
        isRecording = true
        // Release the current hotkey, otherwise pressing it now would open
        // the switcher instead of being captured by the recorder.
        HotKeyCenter.shared.pause()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
        HotKeyCenter.shared.resume()
    }

    private func capture(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.control, .option, .command]).isEmpty {
            stopRecording()
            return nil
        }
        let modifiers = LeaderKey.carbonModifiers(from: event.modifierFlags)
        // Require a real modifier so bare typing keys can't become the leader.
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            NSSound.beep()
            return nil
        }
        leaderKeyCode = Int(event.keyCode)
        leaderModifiers = Int(modifiers)
        stopRecording()
        NotificationCenter.default.post(name: .leaderKeyChanged, object: nil)
        return nil
    }
}

struct PendingApp: Identifiable {
    let bundleID: String
    let name: String
    let path: String
    var id: String { bundleID }
}

struct BindingKeySheet: View {
    let app: PendingApp
    @ObservedObject private var store = CustomBindingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @FocusState private var keyFieldFocused: Bool

    private var conflict: CustomBinding? {
        store.bindings.first { $0.key == key && $0.bundleID != app.bundleID }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                Text(app.name)
                    .font(.headline)
            }

            TextField("Key (letter or number)", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .multilineTextAlignment(.center)
                .focused($keyFieldFocused)
                .onChange(of: key) { _, newValue in
                    key = String(newValue.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(1))
                }
                .onSubmit(save)

            if let conflict {
                Text("\(key.uppercased()) is already assigned to \(conflict.appName)")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Binding", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.isEmpty || conflict != nil)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { keyFieldFocused = true }
    }

    private func save() {
        guard !key.isEmpty, conflict == nil else { return }
        store.add(CustomBinding(bundleID: app.bundleID, appName: app.name, appPath: app.path, key: key))
        dismiss()
    }
}
