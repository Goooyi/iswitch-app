import XCTest
import ServiceManagement
import CoreGraphics
@testable import iSwitch

final class HotkeyManagerTests: XCTestCase {
    func testCycleIndexClampsAfterRemovingApp() {
        let suiteName = "HotkeyManagerTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create user defaults suite")
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        let manager = HotkeyManager(userDefaults: userDefaults)
        let key: Character = "a"

        manager.assign(key: key, to: "app.one", appName: "App One")
        manager.assign(key: key, to: "app.two", appName: "App Two")

        XCTAssertEqual(manager.nextBundleId(for: key), "app.one")

        manager.removeApp("app.two", from: key)

        XCTAssertEqual(manager.nextBundleId(for: key), "app.one")
    }
}

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testToggleRevertsWhenRegisterFails() {
        let service = MockLoginService(initialStatus: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertFalse(manager.isEnabled)
        service.registerError = MockError()

        manager.isEnabled = true

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
    }

    func testToggleRevertsWhenUnregisterFails() {
        let service = MockLoginService(initialStatus: .enabled)
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertTrue(manager.isEnabled)
        service.unregisterError = MockError()

        manager.isEnabled = false

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }
}

private struct MockError: Error {}

private final class MockLoginService: LoginServicing {
    var statusValue: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(initialStatus: SMAppService.Status) {
        self.statusValue = initialStatus
    }

    var status: SMAppService.Status {
        statusValue
    }

    func register() throws {
        registerCallCount += 1
        if let error = registerError {
            throw error
        }
        statusValue = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let error = unregisterError {
            throw error
        }
        statusValue = .notRegistered
    }
}

final class WindowSwitcherTests: XCTestCase {
    func testHandleEventWhenDisabled() {
        let (windowSwitcher, _, hotkeys, _) = makeSwitcher()
        hotkeys.isEnabled = false

        XCTAssertFalse(windowSwitcher.handleKeyEvent(makeEvent()))
    }

    func testHandleEventActivationSuccess() {
        let (windowSwitcher, appManager, hotkeys, _) = makeSwitcher()
        hotkeys.nextBundleIdResult = "com.test.app"
        appManager.activateResult = true

        XCTAssertTrue(windowSwitcher.handleKeyEvent(makeEvent()))
        XCTAssertEqual(appManager.lastBundleId, "com.test.app")
        XCTAssertEqual(appManager.activateCallCount, 1)
    }

    func testHandleEventFallsBackToLauncher() {
        let (windowSwitcher, appManager, hotkeys, launcher) = makeSwitcher()
        hotkeys.nextBundleIdResult = "com.test.app"
        appManager.activateResult = false
        launcher.launchResult = true

        XCTAssertTrue(windowSwitcher.handleKeyEvent(makeEvent()))
        XCTAssertEqual(launcher.launchCallCount, 1)
    }

    func testHandleEventRejectsInvalidStates() {
        let (windowSwitcher, appManager, hotkeys, _) = makeSwitcher()
        hotkeys.matchesResult = false
        XCTAssertFalse(windowSwitcher.handleKeyEvent(makeEvent()))
        XCTAssertEqual(appManager.activateCallCount, 0)

        hotkeys.matchesResult = true
        hotkeys.nextBundleIdResult = nil
        XCTAssertFalse(windowSwitcher.handleKeyEvent(makeEvent()))
    }

    private func makeEvent(isKeyDown: Bool = true, modifiers: CGEventFlags = [.maskCommand], character: Character = "a") -> KeyEvent {
        let keyCode = KeyCodeMap.keyCode(for: character) ?? 0
        return KeyEvent(keyCode: keyCode, modifiers: modifiers, isKeyDown: isKeyDown, timestamp: 0)
    }

    private func makeSwitcher() -> (WindowSwitcher, MockAppManager, MockHotkeyManager, MockLauncher) {
        let appManager = MockAppManager()
        let hotkeyManager = MockHotkeyManager()
        let launcher = MockLauncher()
        let switcher = WindowSwitcher(appManager: appManager, hotkeyManager: hotkeyManager, launcher: launcher)
        return (switcher, appManager, hotkeyManager, launcher)
    }
}

private final class MockAppManager: AppActivating {
    var activateResult = false
    private(set) var activateCallCount = 0
    private(set) var lastBundleId: String?

    func activateApp(bundleId: String) -> Bool {
        activateCallCount += 1
        lastBundleId = bundleId
        return activateResult
    }
}

private final class MockHotkeyManager: HotkeyManaging {
    var isEnabled: Bool = true
    var matchesResult: Bool = true
    var nextBundleIdResult: String? = "com.test.app"

    func matchesTriggerModifiers(_ flags: CGEventFlags) -> Bool {
        matchesResult
    }

    func nextBundleId(for key: Character) -> String? {
        nextBundleIdResult
    }
}

private final class MockLauncher: ApplicationLaunching {
    var launchResult = false
    private(set) var launchCallCount = 0
    private(set) var lastBundleId: String?

    func launchApp(bundleId: String) -> Bool {
        launchCallCount += 1
        lastBundleId = bundleId
        return launchResult
    }
}
