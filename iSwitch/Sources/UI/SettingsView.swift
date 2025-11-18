import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var appManager: AppManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environmentObject(hotkeyManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            HotkeysSettingsView()
                .environmentObject(hotkeyManager)
                .environmentObject(appManager)
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
                .tag(1)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        Form {
            Section {
                Toggle("Enable iSwitch", isOn: $hotkeyManager.isEnabled)

                Picker("Trigger Modifier", selection: $hotkeyManager.triggerModifier) {
                    ForEach(TriggerModifier.allCases, id: \.self) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .pickerStyle(.menu)

                Text("Hold the trigger modifier and press a letter key to switch to the assigned app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility Access")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Required")
                            .foregroundColor(.red)
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: .constant(false))
                    .disabled(true) // TODO: Implement launch at login
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct HotkeysSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var appManager: AppManager
    @State private var showingAppPicker = false
    @State private var selectedKey: Character?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Auto-Assign All") {
                    hotkeyManager.autoAssign(apps: appManager.regularApps)
                }

                Button("Clear All") {
                    for assignment in hotkeyManager.sortedAssignments {
                        hotkeyManager.removeAssignment(for: assignment.key)
                    }
                }

                Spacer()

                Text("\(hotkeyManager.assignments.count) hotkeys assigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Assignments list
            List {
                ForEach(KeyCodeMap.allLetters, id: \.self) { letter in
                    HotkeyRow(
                        key: letter,
                        assignment: hotkeyManager.assignments[letter],
                        appManager: appManager,
                        onAssign: {
                            selectedKey = letter
                            showingAppPicker = true
                        },
                        onRemove: {
                            hotkeyManager.removeAssignment(for: letter)
                        }
                    )
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(
                selectedKey: selectedKey,
                onSelect: { app in
                    if let key = selectedKey {
                        hotkeyManager.assign(key: key, to: app.bundleIdentifier, appName: app.name)
                    }
                    showingAppPicker = false
                },
                onCancel: {
                    showingAppPicker = false
                }
            )
            .environmentObject(appManager)
        }
    }
}

struct HotkeyRow: View {
    let key: Character
    let assignment: HotkeyAssignment?
    let appManager: AppManager
    let onAssign: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            // Key label
            Text(String(key).uppercased())
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .frame(width: 30)

            if let assignment = assignment {
                // Show assigned app
                if let app = appManager.app(forBundleId: assignment.bundleIdentifier) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                }

                Text(assignment.appName)
                    .lineLimit(1)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                // Show unassigned state
                Text("Not assigned")
                    .foregroundColor(.secondary)

                Spacer()

                Button("Assign...", action: onAssign)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppPickerView: View {
    let selectedKey: Character?
    let onSelect: (RunningApp) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appManager: AppManager
    @State private var searchText = ""

    var filteredApps: [RunningApp] {
        if searchText.isEmpty {
            return appManager.regularApps
        } else {
            return appManager.regularApps.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select App for Key '\(String(selectedKey ?? Character(" ")).uppercased())'")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding()

            // Search
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            // App list
            List(filteredApps) { app in
                Button(action: { onSelect(app) }) {
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading) {
                            Text(app.name)
                                .fontWeight(.medium)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .frame(width: 400, height: 500)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("iSwitch")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A fast and efficient window switcher for macOS")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("How to Use")
                    .fontWeight(.semibold)

                Text("Hold Right Command and press a letter key to switch to the assigned application.")
                    .multilineTextAlignment(.center)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(HotkeyManager())
        .environmentObject(AppManager())
}
