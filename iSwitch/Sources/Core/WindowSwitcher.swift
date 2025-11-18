import Foundation
import AppKit
import Carbon.HIToolbox

/// Coordinates keyboard events with app switching
/// This is the main logic component that ties everything together
@MainActor
final class WindowSwitcher {
    private let appManager: AppManager
    private let hotkeyManager: HotkeyManager

    // Track modifier key state for detecting right vs left
    private var lastModifierFlags: CGEventFlags = []

    init(appManager: AppManager, hotkeyManager: HotkeyManager) {
        self.appManager = appManager
        self.hotkeyManager = hotkeyManager
    }

    /// Handle a keyboard event
    /// Returns true if the event was handled and should be suppressed
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Check if switching is enabled
        guard hotkeyManager.isEnabled else { return false }

        // Only process key down events for switching
        guard event.isKeyDown else {
            lastModifierFlags = event.modifiers
            return false
        }

        // Check if the trigger modifier is pressed
        guard isModifierPressed(event: event) else {
            lastModifierFlags = event.modifiers
            return false
        }

        // Get the character for this key
        guard let char = event.character else {
            return false
        }

        // Get the next bundle ID for this key (cycles through multiple apps)
        guard let bundleId = hotkeyManager.nextBundleId(for: char) else {
            return false
        }

        // Try to activate the app
        if appManager.activateApp(bundleId: bundleId) {
            return true // Event handled, suppress it
        }

        // App might not be running, try to launch it
        return launchApp(bundleId: bundleId)
    }

    private func isModifierPressed(event: KeyEvent) -> Bool {
        switch hotkeyManager.triggerModifier {
        case .rightCommand:
            return isRightCommandPressed(event: event)
        case .leftCommand:
            return isLeftCommandPressed(event: event)
        case .rightOption:
            return isRightOptionPressed(event: event)
        case .leftOption:
            return isLeftOptionPressed(event: event)
        }
    }

    private func isRightCommandPressed(event: KeyEvent) -> Bool {
        // Check if Command is pressed
        guard event.modifiers.contains(.maskCommand) else { return false }

        // Check for right command by looking at the raw flags
        // The right command key sets bit 0x10 in the device-independent flags
        let rawFlags = event.modifiers.rawValue

        // Right Command key code is 54 (0x36)
        // We can detect it by checking if the command modifier is present
        // and the maskSecondaryFn is NOT set (which would indicate left command)
        // Actually, we need a different approach - check for NX_DEVICERCMDKEYMASK

        // NX_DEVICERCMDKEYMASK = 0x00000010
        return (rawFlags & 0x00000010) != 0
    }

    private func isLeftCommandPressed(event: KeyEvent) -> Bool {
        guard event.modifiers.contains(.maskCommand) else { return false }
        // NX_DEVICELCMDKEYMASK = 0x00000008
        let rawFlags = event.modifiers.rawValue
        return (rawFlags & 0x00000008) != 0
    }

    private func isRightOptionPressed(event: KeyEvent) -> Bool {
        guard event.modifiers.contains(.maskAlternate) else { return false }
        // NX_DEVICERALTKEYMASK = 0x00000040
        let rawFlags = event.modifiers.rawValue
        return (rawFlags & 0x00000040) != 0
    }

    private func isLeftOptionPressed(event: KeyEvent) -> Bool {
        guard event.modifiers.contains(.maskAlternate) else { return false }
        // NX_DEVICELALTKEYMASK = 0x00000020
        let rawFlags = event.modifiers.rawValue
        return (rawFlags & 0x00000020) != 0
    }

    private func launchApp(bundleId: String) -> Bool {
        // Try to find the app in the file system and launch it
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        // Launch asynchronously
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            if let error = error {
                print("Failed to launch app \(bundleId): \(error)")
            }
        }

        return true
    }
}

// MARK: - Additional Accessibility-based Window Switching

extension WindowSwitcher {
    /// Get all windows for an application using the Accessibility API
    /// This is useful for switching to specific windows within an app
    func getWindows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        return windows
    }

    /// Focus a specific window
    func focusWindow(_ window: AXUIElement) -> Bool {
        // Raise the window
        var result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        guard result == .success else { return false }

        // Set as the main window
        result = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)

        return result == .success
    }

    /// Get the title of a window
    func windowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

        guard result == .success,
              let title = titleRef as? String else {
            return nil
        }

        return title
    }

    /// Cycle through windows of the current application
    func cycleWindows(for pid: pid_t) {
        let windows = getWindows(for: pid)
        guard windows.count > 1 else { return }

        // Find the current frontmost window
        var frontIndex = 0
        for (index, window) in windows.enumerated() {
            var isMain: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &isMain) == .success,
               let main = isMain as? Bool, main {
                frontIndex = index
                break
            }
        }

        // Focus the next window
        let nextIndex = (frontIndex + 1) % windows.count
        _ = focusWindow(windows[nextIndex])
    }
}
