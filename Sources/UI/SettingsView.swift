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
        .frame(width: 500, height: 450)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable iSwitch", isOn: $hotkeyManager.isEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger Modifiers")
                    ModifierPicker(config: $hotkeyManager.modifierConfig)
                    ModifierRecorder(config: $hotkeyManager.modifierConfig)
                        .padding(.top, 2)
                    Text("Click Record and hold the desired modifiers (e.g., Right Command + Option) to capture them automatically.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Current: \(hotkeyManager.modifierConfig.displayString) + Letter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Hold the selected modifiers and press a letter key to switch to the assigned app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Launch app if not running", isOn: $hotkeyManager.relaunchInactiveApps)
                Text("When off, iSwitch will only cycle through currently running apps and won't reopen closed ones.")
                    .font(.caption2)
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
                Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: hotkeyManager.modifierConfig) { _, _ in
            hotkeyManager.saveAssignments()
        }
        .onChange(of: hotkeyManager.isEnabled) { _, _ in
            hotkeyManager.saveAssignments()
        }
        .onChange(of: hotkeyManager.relaunchInactiveApps) { _, _ in
            hotkeyManager.saveAssignments()
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct HotkeysSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var appManager: AppManager
    @State private var pickerContext: AppPickerContext?

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
                Section("Key Assignments") {
                    ForEach(KeyCodeMap.allLetters, id: \.self) { letter in
                        HotkeyRow(
                            key: letter,
                            assignment: hotkeyManager.assignments[letter],
                            appManager: appManager,
                            onAssign: {
                                pickerContext = .assign(letter)
                            },
                            onRemove: {
                                hotkeyManager.removeAssignment(for: letter)
                            }
                        )
                        .environmentObject(hotkeyManager)
                    }
                }

                Section {
                    if hotkeyManager.sortedIgnoredApps.isEmpty {
                        Text("Ignored apps won't be auto-assigned. Add apps here to keep them out of suggestions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(hotkeyManager.sortedIgnoredApps) { app in
                            IgnoredAppRow(app: app, appManager: appManager) {
                                hotkeyManager.removeIgnoredApp(bundleId: app.bundleIdentifier)
                            }
                        }
                    }

                    Button {
                        pickerContext = .ignore
                    } label: {
                        Label("Add App to Ignore List", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                } header: {
                    Text("Ignored Apps")
                }
            }
            .listStyle(.inset)
        }
        .sheet(item: $pickerContext) { context in
            AppPickerView(
                title: context.title,
                onSelect: { app in
                    switch context {
                    case .assign(let key):
                        hotkeyManager.assign(key: key, to: app.bundleIdentifier, appName: app.name)
                    case .ignore:
                        hotkeyManager.addIgnoredApp(bundleId: app.bundleIdentifier, appName: app.name)
                    }
                    pickerContext = nil
                },
                onCancel: {
                    pickerContext = nil
                }
            )
            .environmentObject(appManager)
        }
    }
}

private enum AppPickerContext: Identifiable {
    case assign(Character)
    case ignore

    var id: String {
        switch self {
        case .assign(let key):
            return "assign-\(key)"
        case .ignore:
            return "ignore"
        }
    }

    var title: String {
        switch self {
        case .assign(let key):
            return "Select App for Key '\(String(key).uppercased())'"
        case .ignore:
            return "Choose App to Ignore"
        }
    }
}

struct HotkeyRow: View {
    let key: Character
    let assignment: HotkeyAssignment?
    let appManager: AppManager
    let onAssign: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        HStack {
            // Key label
            Text(String(key).uppercased())
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .frame(width: 30)

            if let assignment = assignment {
                // Show all assigned apps with icons
                HStack(spacing: 4) {
                    ForEach(assignment.apps) { appAssignment in
                        let icon = appManager.app(forBundleId: appAssignment.bundleIdentifier)?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                        RemovableAppIcon(
                            icon: icon,
                            appName: appAssignment.appName,
                            onRemove: {
                                hotkeyManager.removeApp(appAssignment.bundleIdentifier, from: assignment.key)
                            },
                            onIgnore: {
                                hotkeyManager.addIgnoredApp(bundleId: appAssignment.bundleIdentifier, appName: appAssignment.appName)
                            }
                        )
                    }
                }

                // Show app names (truncated if multiple)
                if assignment.apps.count == 1 {
                    Text(assignment.appName)
                        .lineLimit(1)
                } else {
                    Text("\(assignment.apps.count) apps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Add more apps button
                Button(action: onAssign) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add another app to this key")

                // Remove all button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove all apps from this key")
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

struct IgnoredAppRow: View {
    let app: AppAssignment
    let appManager: AppManager
    let onRemove: () -> Void

    var body: some View {
        HStack {
            let icon = appManager.app(forBundleId: app.bundleIdentifier)?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(app.appName)
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(app.appName) from ignore list")
        }
        .padding(.vertical, 2)
    }
}

struct RemovableAppIcon: View {
    let icon: NSImage
    let appName: String
    let onRemove: () -> Void
    let onIgnore: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onRemove) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Remove \(appName) from this key")
        .contextMenu {
            Button("Remove from key", action: onRemove)
            Button("Add to ignore list", action: onIgnore)
        }
    }
}

struct AppPickerView: View {
    let title: String
    let onSelect: (RunningApp) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appManager: AppManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

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
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            // Search
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .padding(.horizontal)
                .onAppear {
                    // Delay focus to ensure the view is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFocused = true
                    }
                }

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
