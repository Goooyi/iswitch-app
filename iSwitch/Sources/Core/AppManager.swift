import Foundation
import AppKit
import Combine

/// Represents a running application with cached properties
struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    let bundleURL: URL?

    init(from app: NSRunningApplication) {
        self.id = app.processIdentifier
        self.bundleIdentifier = app.bundleIdentifier ?? ""
        self.name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        self.bundleURL = app.bundleURL

        // Cache the icon immediately to avoid repeated lookups
        if let icon = app.icon {
            self.icon = icon
        } else {
            self.icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages running applications using efficient event-driven updates
/// Uses NSWorkspace notifications instead of polling to avoid CPU spikes
final class AppManager: ObservableObject {
    @Published private(set) var runningApps: [RunningApp] = []

    // Efficient lookup caches - O(1) access instead of O(n) searches
    private var appsByBundleId: [String: RunningApp] = [:]
    private var appsByPid: [pid_t: RunningApp] = [:]
    private var appsByName: [String: RunningApp] = [:]

    private var cancellables = Set<AnyCancellable>()
    private let workspace = NSWorkspace.shared
    private let notificationCenter = NSWorkspace.shared.notificationCenter

    init() {
        // Initial population of running apps
        refreshRunningApps()
    }

    func startMonitoring() {
        // Use NSWorkspace notifications for event-driven updates
        // This is much more efficient than polling

        notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.addApp(app)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.removeApp(app)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.updateActiveApp(app)
            }
            .store(in: &cancellables)
    }

    func stopMonitoring() {
        cancellables.removeAll()
    }

    /// Get app by bundle identifier - O(1) lookup
    func app(forBundleId bundleId: String) -> RunningApp? {
        appsByBundleId[bundleId]
    }

    /// Get app by process ID - O(1) lookup
    func app(forPid pid: pid_t) -> RunningApp? {
        appsByPid[pid]
    }

    /// Get app by name (case-insensitive) - O(1) lookup
    func app(forName name: String) -> RunningApp? {
        appsByName[name.lowercased()]
    }

    /// Activate an application by bundle identifier
    func activateApp(bundleId: String) -> Bool {
        guard let app = appsByBundleId[bundleId] else { return false }
        return activateApp(pid: app.id)
    }

    /// Activate an application by process ID
    func activateApp(pid: pid_t) -> Bool {
        guard let nsApp = NSRunningApplication(processIdentifier: pid) else {
            return false
        }

        // Use activate for macOS 14+
        return nsApp.activate()
    }

    /// Get all regular (non-background) apps sorted by name
    var regularApps: [RunningApp] {
        runningApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private Methods

    private func refreshRunningApps() {
        let apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { RunningApp(from: $0) }

        runningApps = apps
        rebuildCaches()
    }

    private func rebuildCaches() {
        appsByBundleId.removeAll(keepingCapacity: true)
        appsByPid.removeAll(keepingCapacity: true)
        appsByName.removeAll(keepingCapacity: true)

        for app in runningApps {
            appsByBundleId[app.bundleIdentifier] = app
            appsByPid[app.id] = app
            appsByName[app.name.lowercased()] = app
        }
    }

    private func addApp(_ nsApp: NSRunningApplication) {
        guard nsApp.activationPolicy == .regular else { return }

        let app = RunningApp(from: nsApp)

        // Check if already exists
        guard appsByPid[app.id] == nil else { return }

        runningApps.append(app)
        appsByBundleId[app.bundleIdentifier] = app
        appsByPid[app.id] = app
        appsByName[app.name.lowercased()] = app
    }

    private func removeApp(_ nsApp: NSRunningApplication) {
        let pid = nsApp.processIdentifier

        guard let app = appsByPid[pid] else { return }

        runningApps.removeAll { $0.id == pid }
        appsByBundleId.removeValue(forKey: app.bundleIdentifier)
        appsByPid.removeValue(forKey: pid)
        appsByName.removeValue(forKey: app.name.lowercased())
    }

    private func updateActiveApp(_ nsApp: NSRunningApplication) {
        // We could track the active app here if needed
        // For now, we don't need to do anything special
    }
}
