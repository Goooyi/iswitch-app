import Foundation
import ServiceManagement

protocol LoginServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct SMAppServiceLoginService: LoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

/// Manages Launch at Login using SMAppService (macOS 13+)
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            guard !isApplyingChange, isEnabled != oldValue else { return }
            applyStateChange(desiredState: isEnabled, previousState: oldValue)
        }
    }

    private let service: LoginServicing
    private var isApplyingChange = false

    init(service: LoginServicing = SMAppServiceLoginService()) {
        self.service = service
        self.isEnabled = service.status == .enabled
    }

    private func applyStateChange(desiredState: Bool, previousState: Bool) {
        isApplyingChange = true
        defer { isApplyingChange = false }

        do {
            if desiredState {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to update launch at login setting: \(error)")
            isEnabled = previousState
        }
    }

    var status: SMAppService.Status {
        service.status
    }
}
