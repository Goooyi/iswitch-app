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

## Building & Running Locally

### 1. Clone and enter the project

```bash
git clone https://github.com/goooyi/iswitch-app.git
cd iswitch-app
```

### 2. Install Xcode command-line tools (one-time)

```bash
xcode-select --install   # skip if already installed
```

### 3. Build & test from the command line

```bash
swift test         # runs the unit tests
swift build -c release
```

The optimized binary lives at `.build/release/iSwitch`.

### 4. Use the helper script to rebuild + bundle

```bash
# Make sure the script is executable
chmod +x scripts/build_app.sh

# Run the script from anywhere
./scripts/build_app.sh
```

The script runs `swift build -c release`, recreates `iSwitch.app` at the repo root, and reminds you how to launch it.

### 5. Create and launch manually (if you prefer)

```bash
# Build (if not already built)
swift build -c release

# Create bundle structure
rm -rf iSwitch.app
mkdir -p iSwitch.app/Contents/MacOS
mkdir -p iSwitch.app/Contents/Resources

# Copy binary + Info.plist
cp .build/release/iSwitch iSwitch.app/Contents/MacOS/
cp Sources/Resources/Info.plist iSwitch.app/Contents/

# Launch the app
open iSwitch.app
```

macOS may warn that the app is from an unidentified developer the first time you open it (unless you sign/notarize it). Approve it via System Settings → Privacy & Security if prompted.

### 6. Open the project in Xcode (optional)

1. Open `Package.swift` in Xcode.
2. Select the “iSwitch” scheme.
3. Build & Run (`⌘B` / `⌘R`) to debug inside Xcode.

### 7. (Optional) Codesign & notarize for distribution

For sharing with others, sign the bundle with your Developer ID certificate and notarize it:

```bash
# Replace TEAM_ID and APPLE_ID details with your own
codesign -s "Developer ID Application: Your Name (TEAM_ID)" --options runtime --deep iSwitch.app
xcrun notarytool submit iSwitch.zip --apple-id "you@example.com" --team-id TEAM_ID --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple iSwitch.app
```

Upload the resulting `.zip`/`.dmg` to a GitHub Release so users can download a trusted, notarized copy.

### 8. Create a distributable DMG

After running `./scripts/build_app.sh`, package the app into a compressed DMG:

```bash
chmod +x scripts/package_dmg.sh
./scripts/package_dmg.sh
```

The DMG is emitted to `dist/iSwitch.dmg`.

### 9. Automate releases with GitHub Actions

This repo ships with `.github/workflows/release.yml`. Pushing a tag like `v0.0.1` (or running the workflow manually) triggers it to:

1. Build the release binary
2. Create `iSwitch.app`
3. Package `dist/iSwitch.dmg`
4. Attach the DMG to the GitHub Release associated with the tag

Edit the workflow as needed to insert codesigning/notarization steps before packaging.

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
