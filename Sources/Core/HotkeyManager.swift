import Foundation
import AppKit
import Combine

protocol HotkeyManaging: AnyObject {
    var isEnabled: Bool { get }
    func matchesTriggerModifiers(_ flags: CGEventFlags) -> Bool
    func nextBundleId(for key: Character) -> String?
}

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
    @Published var modifierConfig: ModifierConfig = .default

    // Efficient reverse lookup: bundleId -> key
    private var bundleIdToKey: [String: Character] = [:]

    // Track cycling state: key -> last activated index
    private var cycleIndex: [Character: Int] = [:]

    private let userDefaults: UserDefaults
    private let assignmentsKey = "hotkeyAssignments_v2"
    private let isEnabledKey = "isEnabled"
    private let modifierConfigKey = "modifierConfig"

    // Debounce saves to avoid excessive disk I/O
    private var saveWorkItem: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadAssignments()
    }

    /// Check if the given event flags match our trigger modifiers
    func matchesTriggerModifiers(_ flags: CGEventFlags) -> Bool {
        modifierConfig.matches(flags)
    }

    /// Assign a key to an application (adds to existing if key already has apps)
    func assign(key: Character, to bundleId: String, appName: String) {
        let lowercaseKey = normalizedKey(key)

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
        clampCycleIndex(for: lowercaseKey)
        scheduleSave()
    }

    /// Remove assignment for a key (removes all apps)
    func removeAssignment(for key: Character) {
        let lowercaseKey = normalizedKey(key)
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
        let lowercaseKey = normalizedKey(key)
        guard var assignment = assignments[lowercaseKey] else { return }

        assignment.apps.removeAll { $0.bundleIdentifier == bundleId }
        bundleIdToKey.removeValue(forKey: bundleId)

        if assignment.apps.isEmpty {
            assignments.removeValue(forKey: lowercaseKey)
            cycleIndex.removeValue(forKey: lowercaseKey)
        } else {
            assignments[lowercaseKey] = assignment
            clampCycleIndex(for: lowercaseKey)
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
        assignments[normalizedKey(key)]?.apps.map { $0.bundleIdentifier } ?? []
    }

    /// Get the next bundle ID to activate (for cycling)
    func nextBundleId(for key: Character) -> String? {
        let lowercaseKey = normalizedKey(key)
        guard let assignment = assignments[lowercaseKey], !assignment.apps.isEmpty else {
            cycleIndex.removeValue(forKey: lowercaseKey)
            return nil
        }

        let currentIndex = normalizedCycleIndex(for: lowercaseKey, appCount: assignment.apps.count)
        let bundleId = assignment.apps[currentIndex].bundleIdentifier

        if assignment.apps.count > 1 {
            cycleIndex[lowercaseKey] = (currentIndex + 1) % assignment.apps.count
        } else {
            cycleIndex[lowercaseKey] = 0
        }

        return bundleId
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

        // Load modifier config
        if let data = userDefaults.data(forKey: modifierConfigKey) {
            do {
                modifierConfig = try PropertyListDecoder().decode(ModifierConfig.self, from: data)
            } catch {
                print("Failed to load modifier config: \(error)")
            }
        }

        // Load assignments using PropertyListDecoder (more efficient than JSON)
        guard let data = userDefaults.data(forKey: assignmentsKey) else { return }

        do {
            let decoder = PropertyListDecoder()
            let assignmentArray = try decoder.decode([HotkeyAssignment].self, from: data)

            assignments.removeAll(keepingCapacity: true)
            bundleIdToKey.removeAll(keepingCapacity: true)
            cycleIndex.removeAll(keepingCapacity: true)

            for assignment in assignmentArray {
                assignments[assignment.key] = assignment
                for app in assignment.apps {
                    bundleIdToKey[app.bundleIdentifier] = assignment.key
                }
                clampCycleIndex(for: assignment.key)
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

        // Save modifier config
        do {
            let data = try PropertyListEncoder().encode(modifierConfig)
            userDefaults.set(data, forKey: modifierConfigKey)
        } catch {
            print("Failed to save modifier config: \(error)")
        }

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

    private func normalizedKey(_ key: Character) -> Character {
        Character(String(key).lowercased())
    }

    private func normalizedCycleIndex(for key: Character, appCount: Int) -> Int {
        guard appCount > 0 else {
            cycleIndex.removeValue(forKey: key)
            return 0
        }

        let current = cycleIndex[key] ?? 0
        let clamped = min(current, appCount - 1)

        if clamped != current {
            cycleIndex[key] = clamped
        }

        return clamped
    }

    private func clampCycleIndex(for key: Character) {
        guard let count = assignments[key]?.apps.count else {
            cycleIndex.removeValue(forKey: key)
            return
        }

        _ = normalizedCycleIndex(for: key, appCount: count)
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

extension HotkeyManager: HotkeyManaging {}
