# Statify

A lightweight macOS menu bar system monitor built with SwiftUI. Statify provides real-time hardware metrics at a glance — CPU, memory, disk, network, thermals, and power — without cluttering your dock.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

> **Tested on:** Apple M4 Max, macOS Tahoe. Other configurations may work but are untested.

## Features

- **CPU Monitor** — Per-core usage with P-Core/E-Core separation (Apple Silicon), overall utilization, and top processes
- **Memory Monitor** — Usage breakdown (wired, compressed, app, free), page in/out rates, swap usage, and memory pressure
- **Disk Monitor** — Storage capacity, real-time read/write I/O rates, and per-process disk activity
- **Network Monitor** — Upload/download speeds, per-process network activity, WiFi SSID, local/router/public IP with geolocation
- **Thermal & Fan Monitor** — CPU/GPU temperatures via SMC, fan speeds with RPM gauges, voltage readings
- **Power Metrics** — Real-time CPU/GPU/DRAM/ANE power consumption and core frequency tracking via IOReport

### UI

- Compact menu bar display with five clickable module icons
- Expandable popup panels with detailed stats, history graphs, and process lists
- Adaptive refresh rate — 10s idle, 3s when a popup is open
- Dark-themed UI with color-coded metrics

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac

## Building & Installing

### Option 1: Build with Xcode (development)

```bash
git clone https://github.com/weiloon1234/Statify.git
cd Statify
open Package.swift
```

Select **My Mac** as the run destination, then build and run (`Cmd+R`).

### Option 2: Build release binary from the command line

```bash
git clone https://github.com/weiloon1234/Statify.git
cd Statify

# Build release binary
swift build -c release

# The binary is at:
# .build/release/Statify
```

### Option 3: Build a standalone .app bundle and install

```bash
git clone https://github.com/weiloon1234/Statify.git
cd Statify

# Build release
swift build -c release

# Create the .app bundle
mkdir -p Statify.app/Contents/MacOS
mkdir -p Statify.app/Contents/Resources

cp .build/release/Statify Statify.app/Contents/MacOS/
cp Sources/Statify/Info.plist Statify.app/Contents/

# Copy app icon (optional — requires actool from Xcode)
xcrun actool Sources/Statify/Assets.xcassets \
  --compile Statify.app/Contents/Resources \
  --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist /dev/null 2>/dev/null

# Install to Applications
cp -r Statify.app /Applications/

# Launch
open /Applications/Statify.app
```

To **uninstall**, simply delete `/Applications/Statify.app`.

### Launch at login (optional)

1. Open **System Settings → General → Login Items**
2. Click **+** and select **Statify** from Applications

## Architecture

```
Sources/
├── Statify/
│   ├── main.swift                 # Entry point — NSApplication setup
│   ├── StatifyApp.swift           # AppDelegate, menu bar buttons, refresh logic
│   ├── Models/
│   │   ├── Stats.swift            # SystemStats, FanInfo, TemperatureSensor, ProcessStats
│   │   └── History.swift          # Rolling history tracker with UserDefaults persistence
│   ├── Services/
│   │   ├── SystemMonitor.swift    # CPU/memory/disk/network via Mach & sysctl APIs
│   │   ├── ThermalFanMonitor.swift# SMC direct access for temps, fans, and power
│   │   ├── PowerMetricsService.swift # IOReport private API for power & frequency
│   │   ├── ProcessMonitor.swift   # Per-process CPU/memory/disk/network tracking
│   │   └── NetworkInfoService.swift  # WiFi, IP detection, geolocation
│   └── Views/
│       ├── ModulePopupViews.swift # Network/Disk/CPU/Temp/Memory popup modules
│       ├── PopupManager.swift     # NSPopover lifecycle & positioning
│       ├── CPStyles.swift         # Color palette, fonts, custom modifiers
│       └── Components/            # Reusable UI components (equalizer bars, fan gauge, etc.)
└── IOKitShim/                     # C module wrapper for IOKit framework access
```

## Technologies

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI, AppKit (NSStatusBar, NSPopover) |
| CPU/Memory | Mach APIs (`host_processor_info`, `vm_statistics64`) |
| Disk/Network | `sysctl`, `getifaddrs`, `statfs` |
| Thermal/Fan | IOKit SMC direct access |
| Power/Frequency | IOReport private API |
| Process Stats | `proc_listallpids`, `proc_pidinfo` |
| WiFi | CoreWLAN |

## License

MIT
