import Foundation
import AppKit
import Combine
import KeyboardShortcuts

/// Represents an app assignment for display purposes
struct AppAssignment: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let appName: String
}

/// Represents a hotkey assignment with multiple apps for cycling
struct HotkeyAssignment: Codable, Identifiable {
    var id: Character { key }
    let key: Character
    var apps: [AppAssignment]

    var primaryApp: AppAssignment? { apps.first }
    var appName: String { apps.map { $0.appName }.joined(separator: ", ") }
    var bundleIdentifier: String { apps.first?.bundleIdentifier ?? "" }

    enum CodingKeys: String, CodingKey {
        case key, apps
    }

    init(key: Character, apps: [AppAssignment]) {
        self.key = key
        self.apps = apps
    }

    init(key: Character, bundleIdentifier: String, appName: String) {
        self.key = key
        self.apps = [AppAssignment(bundleIdentifier: bundleIdentifier, appName: appName)]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyString = try container.decode(String.self, forKey: .key)
        guard let char = keyString.first else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: container, debugDescription: "Empty key")
        }
        self.key = char
        self.apps = try container.decode([AppAssignment].self, forKey: .apps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(key), forKey: .key)
        try container.encode(apps, forKey: .apps)
    }
}

/// Manages hotkey assignments with efficient storage and lookup
/// Supports multiple apps per key for cycling
final class HotkeyManager: ObservableObject {
    @Published var assignments: [Character: HotkeyAssignment] = [:]
    @Published var isEnabled: Bool = true

    // Efficient reverse lookup: bundleId -> key
    private var bundleIdToKey: [String: Character] = [:]

    // Track cycling state: key -> last activated index
    private var cycleIndex: [Character: Int] = [:]

    private let userDefaults = UserDefaults.standard
    private let assignmentsKey = "hotkeyAssignments_v2"
    private let isEnabledKey = "isEnabled"

    // Debounce saves to avoid excessive disk I/O
    private var saveWorkItem: DispatchWorkItem?

    init() {
        // Set default shortcut if none exists
        if KeyboardShortcuts.getShortcut(for: .triggerModifier) == nil {
            // Default to Right Command + Space (user will only use the modifiers)
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: .command), for: .triggerModifier)
        }
        loadAssignments()
    }

    /// Get the current trigger modifiers from KeyboardShortcuts
    var triggerModifiers: NSEvent.ModifierFlags {
        KeyboardShortcuts.getShortcut(for: .triggerModifier)?.modifiers ?? .command
    }

    /// Check if the given event flags match our trigger modifiers
    func matchesTriggerModifiers(_ flags: CGEventFlags) -> Bool {
        let modifiers = triggerModifiers

        // Check each required modifier
        if modifiers.contains(.command) {
            guard flags.contains(.maskCommand) else { return false }
        }
        if modifiers.contains(.option) {
            guard flags.contains(.maskAlternate) else { return false }
        }
        if modifiers.contains(.control) {
            guard flags.contains(.maskControl) else { return false }
        }
        if modifiers.contains(.shift) {
            guard flags.contains(.maskShift) else { return false }
        }

        return true
    }

    /// Assign a key to an application (adds to existing if key already has apps)
    func assign(key: Character, to bundleId: String, appName: String) {
        let lowercaseKey = Character(key.lowercased())

        // Remove old assignment for this bundle ID from any key
        if let oldKey = bundleIdToKey[bundleId] {
            if var oldAssignment = assignments[oldKey] {
                oldAssignment.apps.removeAll { $0.bundleIdentifier == bundleId }
                if oldAssignment.apps.isEmpty {
                    assignments.removeValue(forKey: oldKey)
                } else {
                    assignments[oldKey] = oldAssignment
                }
            }
        }

        // Add to existing assignment or create new
        let newApp = AppAssignment(bundleIdentifier: bundleId, appName: appName)
        if var existing = assignments[lowercaseKey] {
            // Don't add duplicate
            if !existing.apps.contains(where: { $0.bundleIdentifier == bundleId }) {
                existing.apps.append(newApp)
                assignments[lowercaseKey] = existing
            }
        } else {
            assignments[lowercaseKey] = HotkeyAssignment(key: lowercaseKey, apps: [newApp])
        }

        bundleIdToKey[bundleId] = lowercaseKey
        scheduleSave()
    }

    /// Remove assignment for a key (removes all apps)
    func removeAssignment(for key: Character) {
        let lowercaseKey = Character(key.lowercased())
        if let assignment = assignments.removeValue(forKey: lowercaseKey) {
            for app in assignment.apps {
                bundleIdToKey.removeValue(forKey: app.bundleIdentifier)
            }
        }
        cycleIndex.removeValue(forKey: lowercaseKey)
        scheduleSave()
    }

    /// Remove a specific app from a key's assignment
    func removeApp(_ bundleId: String, from key: Character) {
        let lowercaseKey = Character(key.lowercased())
        guard var assignment = assignments[lowercaseKey] else { return }

        assignment.apps.removeAll { $0.bundleIdentifier == bundleId }
        bundleIdToKey.removeValue(forKey: bundleId)

        if assignment.apps.isEmpty {
            assignments.removeValue(forKey: lowercaseKey)
            cycleIndex.removeValue(forKey: lowercaseKey)
        } else {
            assignments[lowercaseKey] = assignment
        }

        scheduleSave()
    }

    /// Remove assignment for a bundle ID
    func removeAssignment(forBundleId bundleId: String) {
        if let key = bundleIdToKey[bundleId] {
            removeApp(bundleId, from: key)
        }
    }

    /// Get all bundle IDs assigned to a key - for cycling
    func bundleIds(for key: Character) -> [String] {
        assignments[Character(key.lowercased())]?.apps.map { $0.bundleIdentifier } ?? []
    }

    /// Get the next bundle ID to activate (for cycling)
    func nextBundleId(for key: Character) -> String? {
        let lowercaseKey = Character(key.lowercased())
        guard let assignment = assignments[lowercaseKey], !assignment.apps.isEmpty else {
            return nil
        }

        let currentIndex = cycleIndex[lowercaseKey] ?? 0
        let nextIndex = (currentIndex + 1) % assignment.apps.count

        // Only update cycle index if there are multiple apps
        if assignment.apps.count > 1 {
            cycleIndex[lowercaseKey] = nextIndex
        }

        return assignment.apps[nextIndex].bundleIdentifier
    }

    /// Get the key assigned to a bundle ID - O(1) lookup
    func key(for bundleId: String) -> Character? {
        bundleIdToKey[bundleId]
    }

    /// Get all assignments sorted by key
    var sortedAssignments: [HotkeyAssignment] {
        assignments.values.sorted { $0.key < $1.key }
    }

    /// Get available (unassigned) keys
    var availableKeys: [Character] {
        let assigned = Set(assignments.keys)
        return KeyCodeMap.allLetters.filter { !assigned.contains($0) }
    }

    /// Auto-assign keys based on app name first letter
    /// Apps with same first letter will be grouped together for cycling
    func autoAssign(apps: [RunningApp]) {
        // Group apps by first letter
        var appsByLetter: [Character: [RunningApp]] = [:]

        for app in apps {
            // Skip if already assigned
            if bundleIdToKey[app.bundleIdentifier] != nil {
                continue
            }

            if let firstChar = app.name.first?.lowercased().first, firstChar.isLetter {
                appsByLetter[firstChar, default: []].append(app)
            }
        }

        // Assign each group
        for (letter, letterApps) in appsByLetter {
            for app in letterApps {
                assign(key: letter, to: app.bundleIdentifier, appName: app.name)
            }
        }
    }

    /// Suggest a key for an app based on its name
    func suggestKey(for app: RunningApp) -> Character? {
        // Try first letter (can share with other apps)
        if let firstChar = app.name.first?.lowercased().first, firstChar.isLetter {
            return firstChar
        }

        // Try other letters
        for char in app.name.lowercased() where char.isLetter {
            return char
        }

        return availableKeys.first
    }

    // MARK: - Persistence

    func loadAssignments() {
        // Load enabled state
        if userDefaults.object(forKey: isEnabledKey) != nil {
            isEnabled = userDefaults.bool(forKey: isEnabledKey)
        }

        // Load assignments using PropertyListDecoder (more efficient than JSON)
        guard let data = userDefaults.data(forKey: assignmentsKey) else { return }

        do {
            let decoder = PropertyListDecoder()
            let assignmentArray = try decoder.decode([HotkeyAssignment].self, from: data)

            assignments.removeAll(keepingCapacity: true)
            bundleIdToKey.removeAll(keepingCapacity: true)

            for assignment in assignmentArray {
                assignments[assignment.key] = assignment
                for app in assignment.apps {
                    bundleIdToKey[app.bundleIdentifier] = assignment.key
                }
            }
        } catch {
            print("Failed to load hotkey assignments: \(error)")
        }
    }

    func saveAssignments() {
        // Cancel any pending save
        saveWorkItem?.cancel()
        saveWorkItem = nil

        // Save enabled state
        userDefaults.set(isEnabled, forKey: isEnabledKey)

        // Save assignments using PropertyListEncoder (more efficient than JSON)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary // Binary plist is faster to read/write
            let data = try encoder.encode(Array(assignments.values))
            userDefaults.set(data, forKey: assignmentsKey)
        } catch {
            print("Failed to save hotkey assignments: \(error)")
        }
    }

    private func scheduleSave() {
        // Debounce saves to avoid excessive disk I/O
        saveWorkItem?.cancel()
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveAssignments()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: saveWorkItem!)
    }
}
