import Foundation
import AppKit
import Carbon.HIToolbox

protocol ApplicationLaunching {
    func launchApp(bundleId: String) -> Bool
}

struct WorkspaceApplicationLauncher: ApplicationLaunching {
    func launchApp(bundleId: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                print("Failed to launch app \(bundleId): \(error)")
            }
        }

        return true
    }
}

/// Coordinates keyboard events with app switching
/// This is the main logic component that ties everything together
final class WindowSwitcher {
    private let appManager: AppActivating
    private let hotkeyManager: HotkeyManaging
    private let launcher: ApplicationLaunching

    init(
        appManager: AppActivating,
        hotkeyManager: HotkeyManaging,
        launcher: ApplicationLaunching = WorkspaceApplicationLauncher()
    ) {
        self.appManager = appManager
        self.hotkeyManager = hotkeyManager
        self.launcher = launcher
    }

    /// Handle a keyboard event
    /// Returns true if the event was handled and should be suppressed
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        if event.character == "," && event.modifiers.contains(.maskCommand) {
            // Preserve the standard macOS shortcut for opening settings even when
            // our hotkey modifiers match. Limit to pure Command presses so it
            // doesn't interfere with other custom shortcuts.
            let nonCommandModifiers = event.modifiers.subtracting([.maskCommand, .maskSecondaryFn])
            if nonCommandModifiers.isEmpty {
                Task { @MainActor in
                    (NSApp.delegate as? AppDelegate)?.showSettingsWindow()
                }
                return true
            }
        }

        // Check if switching is enabled
        guard hotkeyManager.isEnabled else { return false }

        // Only process key down events for switching
        guard event.isKeyDown else {
            return false
        }

        // Check if the trigger modifiers are pressed
        guard hotkeyManager.matchesTriggerModifiers(event.modifiers) else {
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

        // App might not be running, launch if allowed
        guard hotkeyManager.relaunchInactiveApps else {
            return false
        }

        return launchApp(bundleId: bundleId)
    }

    private func launchApp(bundleId: String) -> Bool {
        launcher.launchApp(bundleId: bundleId)
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
