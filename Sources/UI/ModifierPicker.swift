import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Custom modifier flags that can be combined
struct ModifierConfig: Codable, Equatable {
    enum CommandSide: String, Codable, CaseIterable, Identifiable {
        case any
        case left
        case right

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .any: return "Any Command"
            case .left: return "Left Command"
            case .right: return "Right Command"
            }
        }

        var glyph: String {
            switch self {
            case .any: return "⌘"
            case .left: return "⌘(L)"
            case .right: return "⌘(R)"
            }
        }
    }

    var command: Bool = true
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false
    var commandSide: CommandSide = .right

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
        if command {
            guard flags.contains(.maskCommand) else { return false }

            let hasRight = flags.contains(.maskSecondaryFn)
            switch commandSide {
            case .any:
                break
            case .left:
                if hasRight { return false }
            case .right:
                // Some remapping tools (e.g., Hyperkey) synthesize Command without side information.
                // Prefer the right-side signal when present, but allow ambiguous Command flags so the
                // shortcut still works even if the side isn't encoded.
                break
            }
        }
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
        if command { parts.append(commandSide.glyph) }
        return parts.isEmpty ? "None" : parts.joined()
    }

    /// Default configuration
    static let `default` = ModifierConfig(command: true, option: false, control: false, shift: false, commandSide: .right)
}

/// A view for selecting modifier keys
struct ModifierPicker: View {
    @Binding var config: ModifierConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ModifierToggle(symbol: "⌃", name: "Control", isOn: $config.control)
                ModifierToggle(symbol: "⌥", name: "Option", isOn: $config.option)
                ModifierToggle(symbol: "⇧", name: "Shift", isOn: $config.shift)
                ModifierToggle(symbol: "⌘", name: "Command", isOn: $config.command)
            }

            if config.command {
                HStack(alignment: .center, spacing: 8) {
                    Text("Command Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Picker("Command Key", selection: $config.commandSide) {
                        ForEach(ModifierConfig.CommandSide.allCases) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }
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
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text("Recorded")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(config.displayString)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 60)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )

            Button(isRecording ? "Stop" : "Record") {
                isRecording.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Modifier Recorder")
        .accessibilityValue(config.displayString)
    }

    private func startRecording() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard isRecording else { return event }
            apply(event: event)
            return event
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func apply(event: NSEvent) {
        let flags = event.modifierFlags
        let baseFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let intersection = flags.intersection(baseFlags)
        guard !intersection.isEmpty else { return }

        config.command = intersection.contains(.command)
        config.option = intersection.contains(.option)
        config.control = intersection.contains(.control)
        config.shift = intersection.contains(.shift)
    }
}

#Preview {
    VStack(spacing: 20) {
        ModifierPicker(config: .constant(ModifierConfig()))
        ModifierRecorder(config: .constant(ModifierConfig()))
    }
    .padding()
}
