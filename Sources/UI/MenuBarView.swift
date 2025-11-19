import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var appManager: AppManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Enable/Disable button (Toggle doesn't work well in MenuBarExtra)
            Button(action: {
                hotkeyManager.isEnabled.toggle()
            }) {
                HStack {
                    Image(systemName: hotkeyManager.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(hotkeyManager.isEnabled ? .green : .secondary)
                    Text(hotkeyManager.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Quick list of assignments - compact grid style
            if hotkeyManager.assignments.isEmpty {
                Text("No hotkeys assigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                // Show assignments in a compact 2-column grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], spacing: 1) {
                    ForEach(hotkeyManager.sortedAssignments.prefix(20)) { assignment in
                        CompactHotkeyItem(
                            assignment: assignment,
                            appManager: appManager
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                if hotkeyManager.assignments.count > 20 {
                    Text("+\(hotkeyManager.assignments.count - 20) more")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
            }

            Divider()

            // Buttons - compact
            Button(action: {
                hotkeyManager.autoAssign(apps: appManager.regularApps)
            }) {
                Label("Auto-Assign", systemImage: "wand.and.stars")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Button(action: {
                openSettings()
            }) {
                Label("Settings...", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 4)
        .frame(width: 200)
    }

    private func openSettings() {
        // Try multiple methods to open settings
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }

        // Ensure app comes to front
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            // Also try to bring windows to front
            for window in NSApp.windows {
                if window.title.contains("Settings") || window.title.contains("iSwitch") {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

/// Compact hotkey item for the menu bar grid
struct CompactHotkeyItem: View {
    let assignment: HotkeyAssignment
    let appManager: AppManager

    var body: some View {
        HStack(spacing: 2) {
            Text(String(assignment.key).uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 12)

            // Show icons for all apps (up to 3)
            HStack(spacing: -4) {
                ForEach(assignment.apps.prefix(3)) { appAssignment in
                    if let app = appManager.app(forBundleId: appAssignment.bundleIdentifier) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                }
            }

            if assignment.apps.count == 1 {
                Text(assignment.apps[0].appName)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("×\(assignment.apps.count)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(HotkeyManager())
        .environmentObject(AppManager())
}
