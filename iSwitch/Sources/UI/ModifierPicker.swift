import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Custom modifier flags that can be combined
struct ModifierConfig: Codable, Equatable {
    var command: Bool = true
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false

    /// Convert to NSEvent.ModifierFlags for comparison
    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if shift { flags.insert(.shift) }
        return flags
    }

    /// Check if at least one modifier is selected
    var hasModifiers: Bool {
        command || option || control || shift
    }

    /// Check if CGEventFlags contain our required modifiers
    func matches(_ flags: CGEventFlags) -> Bool {
        // Must have at least one modifier configured
        guard hasModifiers else { return false }

        // Check required modifiers are present
        if command && !flags.contains(.maskCommand) { return false }
        if option && !flags.contains(.maskAlternate) { return false }
        if control && !flags.contains(.maskControl) { return false }
        if shift && !flags.contains(.maskShift) { return false }
        return true
    }

    /// Display string for the modifier combination
    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.isEmpty ? "None" : parts.joined()
    }

    /// Default configuration
    static let `default` = ModifierConfig(command: true, option: false, control: false, shift: false)
}

/// A view for selecting modifier keys
struct ModifierPicker: View {
    @Binding var config: ModifierConfig

    var body: some View {
        HStack(spacing: 12) {
            ModifierToggle(symbol: "⌃", name: "Control", isOn: $config.control)
            ModifierToggle(symbol: "⌥", name: "Option", isOn: $config.option)
            ModifierToggle(symbol: "⇧", name: "Shift", isOn: $config.shift)
            ModifierToggle(symbol: "⌘", name: "Command", isOn: $config.command)
        }
    }
}

/// Individual modifier toggle button
struct ModifierToggle: View {
    let symbol: String
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isOn ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

/// A recorder view that captures modifier key presses
struct ModifierRecorder: View {
    @Binding var config: ModifierConfig
    @State private var isRecording = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            // Display current modifiers
            Text(config.displayString)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 60)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Button(isRecording ? "Done" : "Record") {
                if isRecording {
                    isRecording = false
                } else {
                    isRecording = true
                }
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            setupEventMonitor()
        }
    }

    private func setupEventMonitor() {
        // We'll use a local event monitor when recording
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard isRecording else { return event }

            // Capture the modifier flags
            let flags = event.modifierFlags
            config.command = flags.contains(.command)
            config.option = flags.contains(.option)
            config.control = flags.contains(.control)
            config.shift = flags.contains(.shift)

            return event
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ModifierPicker(config: .constant(ModifierConfig()))
        ModifierRecorder(config: .constant(ModifierConfig()))
    }
    .padding()
}
