# iSwitch - Fast macOS Window Switcher

A high-performance macOS window switcher inspired by rcmd, but optimized to avoid CPU spikes and designed with efficiency in mind.

## Features

- **Fast app switching** - Hold Right Command (or other modifier) + letter key to instantly switch to assigned apps
- **Auto-assignment** - Automatically assigns keys based on app names
- **Event-driven architecture** - Uses NSWorkspace notifications instead of polling
- **Efficient lookups** - O(1) hash-based lookups instead of regex matching
- **Minimal resource usage** - No constant CPU usage when idle
- **Menu bar integration** - Quick access to assignments and settings
- **Accessibility API** - Native macOS window management

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)
- Accessibility permissions

## Building

### Using Xcode

1. Open `Package.swift` in Xcode
2. Select the "iSwitch" scheme
3. Build (Cmd+B) and Run (Cmd+R)

### Using Command Line

```bash
cd iSwitch
swift build -c release
```

The built executable will be in `.build/release/iSwitch`

### Creating an App Bundle

To create a proper .app bundle:

```bash
# Build release
swift build -c release

# Create app structure
mkdir -p iSwitch.app/Contents/MacOS
mkdir -p iSwitch.app/Contents/Resources

# Copy binary and Info.plist
cp .build/release/iSwitch iSwitch.app/Contents/MacOS/
cp Sources/Resources/Info.plist iSwitch.app/Contents/
```

## Usage

1. **Grant Accessibility Permissions**
   - Go to System Preferences > Privacy & Security > Accessibility
   - Add iSwitch to the allowed apps

2. **Assign Hotkeys**
   - Click the menu bar icon
   - Go to Settings > Hotkeys
   - Click "Assign..." next to a letter to select an app
   - Or click "Auto-Assign All" to automatically assign based on app names

3. **Switch Apps**
   - Hold Right Command (⌘) and press the assigned letter
   - The assigned app will be activated instantly

## Configuration

### Trigger Modifier Options

- Right Command (default)
- Left Command
- Right Option
- Left Option

### Auto-Assignment

The auto-assign feature tries to:
1. Use the first letter of the app name
2. If taken, use other letters from the app name
3. Assign to the first available letter

## Architecture

### Performance Optimizations

iSwitch was designed to avoid the CPU spike issues found in similar apps:

1. **No Regex** - Uses direct string comparison and hash lookups instead of regex matching
2. **Event-driven** - Uses NSWorkspace notifications instead of polling timers
3. **Efficient caching** - Pre-built lookup tables for O(1) access
4. **Binary plist storage** - Uses PropertyListEncoder with binary format instead of JSON
5. **Debounced saves** - Batches preference saves to avoid disk I/O spikes
6. **CGEventTap** - Low-level keyboard monitoring without NSEvent overhead

### Key Components

- **KeyboardMonitor** - Uses CGEventTap for efficient global keyboard monitoring
- **AppManager** - Manages running apps with NSWorkspace notifications
- **HotkeyManager** - Efficient key-to-app mapping with reverse lookups
- **WindowSwitcher** - Coordinates keyboard events with app activation

## Comparison with rcmd

| Feature | iSwitch | rcmd |
|---------|---------|------|
| Keyboard monitoring | CGEventTap | Similar |
| App lookup | Hash table O(1) | Regex matching |
| Preferences | Binary plist | JSON |
| Updates | Event-driven | Timer-based |
| CPU at idle | ~0% | Variable |

## Known Limitations

- Requires accessibility permissions
- Some apps may not respond to activation (security software, etc.)
- Window-level switching requires additional setup

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Inspired by [rcmd](https://lowtechguys.com/rcmd/) by Low Tech Guys
- Technical insights from [Alin Panaitiu's blog](https://alinpanaitiu.com/blog/window-switcher-app-store/)
