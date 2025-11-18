import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var appManager: AppManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Enable/Disable toggle
            Toggle(isOn: $hotkeyManager.isEnabled) {
                Text("Enabled")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Quick list of assignments
            if hotkeyManager.assignments.isEmpty {
                Text("No hotkeys assigned")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                Text("Hotkeys")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                ForEach(hotkeyManager.sortedAssignments.prefix(10)) { assignment in
                    HStack {
                        Text(String(assignment.key).uppercased())
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .frame(width: 20)

                        if let app = appManager.app(forBundleId: assignment.bundleIdentifier) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }

                        Text(assignment.appName)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }

                if hotkeyManager.assignments.count > 10 {
                    Text("+\(hotkeyManager.assignments.count - 10) more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
            }

            Divider()

            // Auto-assign button
            Button("Auto-Assign Running Apps") {
                hotkeyManager.autoAssign(apps: appManager.regularApps)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            // Settings button
            SettingsLink {
                Text("Settings...")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Divider()

            // Quit button
            Button("Quit iSwitch") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(HotkeyManager())
        .environmentObject(AppManager())
}
