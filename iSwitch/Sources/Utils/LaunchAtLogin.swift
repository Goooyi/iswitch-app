import Foundation
import ServiceManagement

/// Manages Launch at Login using SMAppService (macOS 13+)
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enable()
            } else {
                disable()
            }
        }
    }

    private init() {
        // Check current status
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
            // Revert the published value
            isEnabled = false
        }
    }

    private func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to disable launch at login: \(error)")
            // Revert the published value
            isEnabled = true
        }
    }

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
