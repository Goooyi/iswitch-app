import XCTest
@testable import iSwitch

final class ModifierConfigTests: XCTestCase {
    func testExactMatchRejectsExtraModifiers() {
        let config = ModifierConfig(command: true, option: true, control: true, shift: false, commandSide: .left)

        // Exact combo should pass
        XCTAssertTrue(config.matches([.maskCommand, .maskAlternate, .maskControl]))

        // Extra shift should fail
        XCTAssertFalse(config.matches([.maskCommand, .maskAlternate, .maskControl, .maskShift]))
    }

    func testRightCommandRequiresRightFlag() {
        let config = ModifierConfig(command: true, option: false, control: false, shift: false, commandSide: .right)

        // Missing right-flag should fail
        XCTAssertFalse(config.matches([.maskCommand]))

        // With right-flag should pass
        XCTAssertTrue(config.matches([.maskCommand, .maskSecondaryFn]))
    }

    func testAnyCommandAllowsEitherSideButNoExtras() {
        let config = ModifierConfig(command: true, option: false, control: false, shift: false, commandSide: .any)

        XCTAssertTrue(config.matches([.maskCommand]))
        XCTAssertTrue(config.matches([.maskCommand, .maskSecondaryFn]))

        // Extra shift should fail
        XCTAssertFalse(config.matches([.maskCommand, .maskSecondaryFn, .maskShift]))
    }
}
