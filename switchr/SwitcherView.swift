//
//  SwitcherView.swift
//  switchr
//

import AppKit
import SwiftUI

struct SwitcherView: View {
    let rows: [SwitcherRow]
    let closedApps: [CustomBinding]
    let hasPermission: Bool
    let onSelect: (SwitcherRow) -> Void
    let onLaunch: (CustomBinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !hasPermission {
                permissionHint
            } else if rows.isEmpty && closedApps.isEmpty {
                Text("No windows open")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                        if !closedApps.isEmpty {
                            if !rows.isEmpty {
                                Divider()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            ForEach(closedApps) { binding in
                                closedAppRow(binding)
                            }
                        }
                    }
                }
                .frame(maxHeight: 600)
            }
        }
        .padding(8)
        .frame(width: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private func rowView(_ row: SwitcherRow) -> some View {
        HStack(spacing: 10) {
            Text(row.letter.map { String($0).uppercased() } ?? "")
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            if let icon = row.window.app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(row.window.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if row.window.title != row.window.appName, !row.window.title.isEmpty {
                    Text(row.window.appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if row.window.isMinimized {
                Image(systemName: "arrow.down.right.square")
                    .foregroundStyle(.tertiary)
                    .help("Minimized")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onSelect(row) }
        .opacity(row.window.isMinimized ? 0.6 : 1)
    }

    // Bound apps that aren't open: compact single-line rows so they stay out
    // of the way. Their key launches the app instead of focusing a window.
    private func closedAppRow(_ binding: CustomBinding) -> some View {
        HStack(spacing: 10) {
            Text(binding.key.uppercased())
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            Image(nsImage: NSWorkspace.shared.icon(forFile: binding.appPath))
                .resizable()
                .frame(width: 18, height: 18)
            Text(binding.appName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onLaunch(binding) }
        .opacity(0.75)
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission needed", systemImage: "lock.shield")
                .font(.headline)
            Text("Switchr needs Accessibility access to list and focus windows.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }
        .padding(16)
    }
}
