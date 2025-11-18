import SwiftUI
import AppKit

@main
struct iSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.hotkeyManager)
                .environmentObject(appDelegate.appManager)
        }

        MenuBarExtra("iSwitch", systemImage: "square.grid.2x2") {
            MenuBarView()
                .environmentObject(appDelegate.hotkeyManager)
                .environmentObject(appDelegate.appManager)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appManager = AppManager()
    let hotkeyManager = HotkeyManager()
    private var keyboardMonitor: KeyboardMonitor?
    private var windowSwitcher: WindowSwitcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check and request accessibility permissions
        checkAccessibilityPermissions()

        // Initialize the window switcher
        windowSwitcher = WindowSwitcher(
            appManager: appManager,
            hotkeyManager: hotkeyManager
        )

        // Start keyboard monitoring
        keyboardMonitor = KeyboardMonitor { [weak self] event in
            self?.windowSwitcher?.handleKeyEvent(event) ?? false
        }
        keyboardMonitor?.start()

        // Start monitoring running applications
        appManager.startMonitoring()

        // Load saved hotkey assignments
        hotkeyManager.loadAssignments()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor?.stop()
        appManager.stopMonitoring()
        hotkeyManager.saveAssignments()
    }

    private func checkAccessibilityPermissions() {
        // Use the string value directly for Swift 6 concurrency safety
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            print("iSwitch requires accessibility permissions to monitor keyboard events.")
            print("Please grant access in System Preferences > Privacy & Security > Accessibility")
        }
    }
}
