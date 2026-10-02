# macOS Network Monitor

A sleek, native macOS menu bar accessory that displays real-time network upload and download speeds, built entirely with Swift and standard macOS libraries (no third-party dependencies).

![Menu Bar View](menu_bar.png)

## Features

- **Real-time Speeds**: View download (↓) and upload (↑) speeds calculated dynamically from macOS `sysctl` kernel APIs.
- **Latency Monitor**: Probe a configurable HTTPS host (Cloudflare DNS by default) and track latency, jitter, and loss.
- **Connection Quality**: Good / Fair / Poor badge in the menu bar and popover from recent latency samples.
- **Wi‑Fi Details**: RSSI and TX rate in the popover (SSID when Location access allows it).
- **Speed Test**: Run on-demand download + upload tests (Cloudflare) from the menu or graph popover.
- **Live Graph**: Left-click the menu bar item for a SwiftUI chart of recent download/upload history (right-click for the full menu).
- **Data Limits**: Set custom data usage limits and receive visual alerts when you approach or exceed them.
- **SF Symbols**: Uses native Apple symbols for a clean and beautiful look in both light and dark mode.
- **Dynamic Colors**: Numbers change color (Green/Orange) when data thresholds are exceeded.
- **Interface Selection**: Choose to monitor all traffic, or isolate specific interfaces like Wi-Fi (`en0`) or loopback (`lo0`).
- **Session Totals**: See how much data has been downloaded and uploaded since the monitor was launched.
- **Customizable Intervals**: Dynamically update refresh rate from 0.5 to 5 seconds.
- **Bits vs Bytes**: Toggle between bits per second (Mbps) and bytes per second (MB/s).
- **Compact & Hide Modes**: Save menu bar space with `Compact Mode`, or automatically hide the monitor entirely when network traffic is inactive.
- **Launch at Login**: Integrates natively with `SMAppService` to safely auto-start on boot.

![Dropdown Menu](dropdown_menu.png)

## Installation & Running

This project is a Swift Package. You must be on macOS 13+.

1. Clone the repository.
2. Build the project using the build script, which compiles the package and securely codesigns it:
   ```bash
   ./build.sh
   ```
3. Wait for the build to complete. The script creates the standard app bundle with Hardened Runtime and App Sandbox enabled.
4. Drag **`NetworkMon.app`** into your Mac's **Applications** folder.
5. Double-click it to launch! Since it is a menu bar accessory, it will silently appear in the top right of your screen. 
   *(Tip: Use the dropdown menu to toggle 'Launch at Login' so it starts automatically!)*

## Development

```bash
swift test
./build.sh
```

## Releases

### v1.3.0
- Connection quality badge (latency + jitter + loss).
- Configurable latency host (presets + custom).
- Wi‑Fi RSSI / TX rate in the popover and menu.

### v1.2.0
- Left-click opens a live download/upload history chart popover; right-click opens the menu.
- Speed test now measures download (20MB) and upload (10MB) via Cloudflare.

### v1.1.0
- Prefer IPv4 for local IP, refresh IPs on demand and every 15 minutes.
- Fix usage totals while “Hide when Inactive” is on; safer UInt64 preference storage.
- Speed test: prevent double-runs, request notification permission, report failures.
- Cancel overlapping latency probes; keep menu open without full rebuild flicker.
- Extract format helpers and add unit tests.

### v1.0.0
- Initial release featuring core network tracking, dynamic colors, interval toggling, interface isolation, and native backgrounding.
