import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Represents a keyboard event with all necessary information
struct KeyEvent {
    let keyCode: UInt16
    let modifiers: CGEventFlags
    let isKeyDown: Bool
    let timestamp: CFTimeInterval

    var hasRightCommand: Bool {
        modifiers.contains(.maskCommand) && modifiers.contains(.maskSecondaryFn)
    }

    var hasLeftCommand: Bool {
        modifiers.contains(.maskCommand) && !modifiers.contains(.maskSecondaryFn)
    }

    var character: Character? {
        KeyCodeMap.character(for: keyCode)
    }
}

/// Efficient keyboard monitoring using CGEventTap
/// This is much more efficient than using NSEvent monitors as it operates at a lower level
final class KeyboardMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let callback: (KeyEvent) -> Bool

    init(callback: @escaping (KeyEvent) -> Bool) {
        self.callback = callback
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        // Create event tap for key down and key up events
        // We use CGEventMaskBit for specific events to minimize overhead
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Store callback in a context that can be passed to C function
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // Handle tap disabled event
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let modifiers = event.flags
                let isKeyDown = type == .keyDown
                let timestamp = event.timestamp

                let keyEvent = KeyEvent(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    isKeyDown: isKeyDown,
                    timestamp: Double(timestamp) / 1_000_000_000
                )

                // If callback returns true, we handled the event and should suppress it
                if monitor.callback(keyEvent) {
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            print("Failed to create event tap. Make sure accessibility permissions are granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    var isRunning: Bool {
        eventTap != nil
    }
}

/// Efficient key code to character mapping
/// Uses a pre-computed lookup table instead of regex or string parsing
enum KeyCodeMap {
    // Pre-computed mapping for maximum efficiency
    // These are standard US QWERTY key codes
    private static let keyCodeToChar: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
        41: ";", 43: ",", 45: "n", 46: "m", 47: "."
    ]

    // Reverse mapping for character to key code lookups
    private static let charToKeyCode: [Character: UInt16] = {
        var result: [Character: UInt16] = [:]
        for (code, char) in keyCodeToChar {
            result[char] = code
        }
        return result
    }()

    static func character(for keyCode: UInt16) -> Character? {
        keyCodeToChar[keyCode]
    }

    static func keyCode(for character: Character) -> UInt16? {
        charToKeyCode[character.lowercased().first ?? character]
    }

    static var allLetters: [Character] {
        Array("abcdefghijklmnopqrstuvwxyz")
    }
}
