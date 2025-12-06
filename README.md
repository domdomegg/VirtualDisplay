# VirtualDisplay

A macOS menu bar app to force specific screen resolutions on your Mac.

## Why?

Modern Macs have non-standard display resolutions (e.g. 3024×1964 on a MacBook Pro 16"). This can be problematic for AI computer use models like Claude, which are typically trained on standard resolutions like 1920×1080.

macOS doesn't natively support setting arbitrary resolutions on built-in displays. This app works around that by creating a virtual display at your desired resolution, which you can then mirror your main display to.

## Features

- Create virtual displays at 4K (3840×2160), 1080p (1920×1080), or 720p (1280×720)
- Menu bar app - no dock icon
- Switch between resolutions
- Disable when not needed

## Installation

```bash
# Clone the repo
git clone git@github.com:domdomegg/VirtualDisplay.git
cd VirtualDisplay

# Build
swiftc -O -o VirtualDisplay VirtualDisplay.swift

# Run
./VirtualDisplay
```

Or download a pre-built binary from the [Releases](https://github.com/domdomegg/VirtualDisplay/releases) page.

## Usage

1. Launch the app - a 📺 icon appears in your menu bar
2. Click and select a resolution (4K, 1080p, or 720p)
3. The virtual display appears in System Settings > Displays
4. Arrange it as needed, or mirror your main display to it
5. Click "Disable" to remove the virtual display (restarts the app)

## How it works

Uses the private `CGVirtualDisplay` API from CoreGraphics to create virtual display outputs. This is the same approach used by apps like BetterDisplay and FluffyDisplay.

## Limitations

- Disabling a display requires restarting the app (the CGVirtualDisplay API doesn't cleanly support destroying displays)
- Uses undocumented Apple APIs which could break in future macOS versions
- Only tested on Apple Silicon Macs

## License

MIT
