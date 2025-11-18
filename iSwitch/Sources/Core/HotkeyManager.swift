import Foundation
import AppKit
import Combine

/// Represents a hotkey assignment
struct HotkeyAssignment: Codable, Identifiable {
    var id: Character { key }
    let key: Character
    let bundleIdentifier: String
    let appName: String

    enum CodingKeys: String, CodingKey {
        case key, bundleIdentifier, appName
    }

    init(key: Character, bundleIdentifier: String, appName: String) {
        self.key = key
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyString = try container.decode(String.self, forKey: .key)
        guard let char = keyString.first else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: container, debugDescription: "Empty key")
        }
        self.key = char
        self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.appName = try container.decode(String.self, forKey: .appName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(key), forKey: .key)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(appName, forKey: .appName)
    }
}

/// Configuration for the hotkey trigger
enum TriggerModifier: String, Codable, CaseIterable {
    case rightCommand = "rightCommand"
    case leftCommand = "leftCommand"
    case rightOption = "rightOption"
    case leftOption = "leftOption"

    var displayName: String {
        switch self {
        case .rightCommand: return "Right Command"
        case .leftCommand: return "Left Command"
        case .rightOption: return "Right Option"
        case .leftOption: return "Left Option"
        }
    }
}

/// Manages hotkey assignments with efficient storage and lookup
final class HotkeyManager: ObservableObject {
    @Published var assignments: [Character: HotkeyAssignment] = [:]
    @Published var triggerModifier: TriggerModifier = .rightCommand
    @Published var isEnabled: Bool = true

    // Efficient reverse lookup: bundleId -> key
    private var bundleIdToKey: [String: Character] = [:]

    private let userDefaults = UserDefaults.standard
    private let assignmentsKey = "hotkeyAssignments"
    private let triggerModifierKey = "triggerModifier"
    private let isEnabledKey = "isEnabled"

    // Debounce saves to avoid excessive disk I/O
    private var saveWorkItem: DispatchWorkItem?

    init() {
        loadAssignments()
    }

    /// Assign a key to an application
    func assign(key: Character, to bundleId: String, appName: String) {
        let lowercaseKey = Character(key.lowercased())

        // Remove old assignment for this key
        if let oldAssignment = assignments[lowercaseKey] {
            bundleIdToKey.removeValue(forKey: oldAssignment.bundleIdentifier)
        }

        // Remove old assignment for this bundle ID
        if let oldKey = bundleIdToKey[bundleId] {
            assignments.removeValue(forKey: oldKey)
        }

        let assignment = HotkeyAssignment(key: lowercaseKey, bundleIdentifier: bundleId, appName: appName)
        assignments[lowercaseKey] = assignment
        bundleIdToKey[bundleId] = lowercaseKey

        scheduleSave()
    }

    /// Remove assignment for a key
    func removeAssignment(for key: Character) {
        let lowercaseKey = Character(key.lowercased())
        if let assignment = assignments.removeValue(forKey: lowercaseKey) {
            bundleIdToKey.removeValue(forKey: assignment.bundleIdentifier)
        }
        scheduleSave()
    }

    /// Remove assignment for a bundle ID
    func removeAssignment(forBundleId bundleId: String) {
        if let key = bundleIdToKey.removeValue(forKey: bundleId) {
            assignments.removeValue(forKey: key)
        }
        scheduleSave()
    }

    /// Get the bundle ID assigned to a key - O(1) lookup
    func bundleId(for key: Character) -> String? {
        assignments[Character(key.lowercased())]?.bundleIdentifier
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
    func autoAssign(apps: [RunningApp]) {
        for app in apps {
            // Skip if already assigned
            if bundleIdToKey[app.bundleIdentifier] != nil {
                continue
            }

            // Try first letter of app name
            if let firstChar = app.name.first?.lowercased().first,
               firstChar.isLetter,
               assignments[firstChar] == nil {
                assign(key: firstChar, to: app.bundleIdentifier, appName: app.name)
                continue
            }

            // Try other letters in app name
            for char in app.name.lowercased() where char.isLetter {
                if assignments[char] == nil {
                    assign(key: char, to: app.bundleIdentifier, appName: app.name)
                    break
                }
            }
        }
    }

    /// Suggest a key for an app based on its name
    func suggestKey(for app: RunningApp) -> Character? {
        // Try first letter
        if let firstChar = app.name.first?.lowercased().first,
           firstChar.isLetter,
           assignments[firstChar] == nil {
            return firstChar
        }

        // Try other letters
        for char in app.name.lowercased() where char.isLetter {
            if assignments[char] == nil {
                return char
            }
        }

        // Return any available key
        return availableKeys.first
    }

    // MARK: - Persistence

    func loadAssignments() {
        // Load trigger modifier
        if let modifierRaw = userDefaults.string(forKey: triggerModifierKey),
           let modifier = TriggerModifier(rawValue: modifierRaw) {
            triggerModifier = modifier
        }

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
                bundleIdToKey[assignment.bundleIdentifier] = assignment.key
            }
        } catch {
            print("Failed to load hotkey assignments: \(error)")
        }
    }

    func saveAssignments() {
        // Cancel any pending save
        saveWorkItem?.cancel()
        saveWorkItem = nil

        // Save trigger modifier
        userDefaults.set(triggerModifier.rawValue, forKey: triggerModifierKey)

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
