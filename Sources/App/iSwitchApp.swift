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

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appManager = AppManager()
    let hotkeyManager = HotkeyManager()
    private var keyboardMonitor: KeyboardMonitor?
    private var windowSwitcher: WindowSwitcher?
    private var settingsWindow: NSWindow?

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

    @MainActor
    func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // First try the system Settings handler (SwiftUI Settings scene)
        let selectors: [Selector] = ["showSettingsWindow:", "showPreferencesWindow:"].map(NSSelectorFromString)
        var handled = false
        for selector in selectors where NSApp.responds(to: selector) {
            if NSApp.sendAction(selector, to: nil, from: nil) {
                handled = true
                break
            }
        }

        // If a settings window already exists, bring it forward.
        if bringExistingSettingsWindowToFront() {
            return
        }

        // If the system action was sent, try once more on the next run loop to let it create the window.
        if handled {
            DispatchQueue.main.async { [weak self] in
                if self?.bringExistingSettingsWindowToFront() == true {
                    return
                }
                self?.presentEmbeddedSettingsWindow()
            }
        } else {
            presentEmbeddedSettingsWindow()
        }
    }

    @MainActor
    private func bringExistingSettingsWindowToFront() -> Bool {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return true
        }

        if let window = NSApp.windows.first(where: isSettingsWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            settingsWindow = window
            window.delegate = self
            return true
        }

        return false
    }

    @MainActor
    private func presentEmbeddedSettingsWindow() {
        let hosting = NSHostingController(
            rootView: SettingsView()
                .environmentObject(hotkeyManager)
                .environmentObject(appManager)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("iswitch.settings.window")
        window.center()

        settingsWindow = window
        window.delegate = self

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @MainActor
    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if let id = window.identifier?.rawValue.lowercased(),
           id.contains("settings") || id.contains("preferences") {
            return true
        }
        let title = window.title.lowercased()
        return title.contains("settings") || title.contains("preferences")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        }
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
