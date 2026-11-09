# MinerGuru for macOS: development

The [README](../README.md) describes the app for users.

**MinerGuru** is a native macOS app (SwiftUI, Swift Charts, MenuBarExtra) for monitoring and controlling open-source Bitcoin miners such as the **Bitaxe** (e.g. **Gamma 601**, Supra, Ultra) and the **NerdQAxe++** / **NerdQAxe+** on the local network.

**For developers:** [architecture of the Mac app](ARCHITECTURE.md) and [fundamentals of all three apps](FUNDAMENTALS.md) (miner API, poll cycle, write path, mock miners, counterparts on Android and Windows).

---

## Highlights and features

### 1. Seamless macOS integration
- **Native main window (`NavigationSplitView`)**: a clear sidebar with the fleet dashboard and every detected miner, including a live status indicator, hashrate and temperature.
- **Menu bar extra (`MenuBarExtra`)**: shows the fleet's current total hashrate right in the macOS menu bar, with quick access to all miners, temperatures, pool latencies and actions.
- **Inspector sidebar**: controls for clock, voltage, fan and mining pools that can be shown and hidden right next to the live charts.

### 2. Automatic network scan and manual IP entry
- **Automatic subnet scanner (`/24`)**: detects the Mac's local subnet (e.g. `192.168.1.1–254`) and finds every running Bitaxe (AxeOS) and NerdQAxe++ (NerdOS) miner in parallel within seconds through `/api/system/info`.
- **Adding by IP or hostname**: enter an IP address or a local hostname (e.g. `192.168.1.150` or `bitaxe.local`), with an immediate connection test.

### 3. Live monitoring and telemetry
- **Fleet dashboard**: total hashrate (`GH/s` / `TH/s`), total power (`W` and `kWh/day`), fleet efficiency (`J/TH`), accepted and rejected shares, record difficulty (`Best Diff`) and average pool latency.
- **Interactive real-time charts (Swift Charts)**:
  - Hashrate (`GH/s`)
  - ASIC and voltage regulator temperature (`°C`) with an adjustable warning threshold
  - Pool latency to the Stratum server (`ms`)
  - Power draw (`W`) and efficiency (`J/TH`)

### 4. Pool information and real-time pool latency
- **Primary and fallback Stratum pool**: server host, port, wallet/worker name, active pool difficulty and active mode (primary or fallback).
- **Two kinds of pool latency (`ms`)**:
  - The Stratum response time reported by the miner (`responseTime` in AxeOS, `stratum.pools[].responseTime` in NerdOS).
  - A direct TCP handshake RTT measurement (`SYN -> SYN-ACK`) to the primary and fallback pool servers, rated *Excellent*, *Good*, *Fair* or *High*.

### 5. Miner control and configuration (`PATCH /api/system` and `POST /api/system/restart`)
- **Clock and core voltage**: tuned quick profiles (*Eco*, *Standard*, *Performance/Boost*) for the **Bitaxe Gamma 601 (`BM1370`)** and the **NerdQAxe++ (`4x BM1370`)**, plus fine-grained manual settings for frequency (`MHz`) and core voltage (`mV`).
- **Fan control**: switch between automatic temperature control (`Auto-Fan`) and a manual fan speed (`20 % – 100 %`).
- **Pool configuration per miner**: edit every pool slot (AxeOS 2.15+: up to 8 slots with a freely chosen primary and fallback slot; older firmware and NerdOS: primary and fallback), dual-pool mode with a hashrate split on the NerdQAxe, templates for known pools and a built-in **live latency test**. After saving, the miner restarts so the pools take effect.
- **System actions**: restart the miner, change the hostname, inspect the raw JSON (`/api/system/info`) or open the web UI in the browser.

### 6. Pool library (sidebar entry "Pools")
- **Saved pools**: the pools of all miners are read in; your own pools can be created, edited and duplicated.
- **Assignment and quick switch**: assign pools to the slots of each miner, or set one as the primary or fallback pool on all miners with one click. Slots that are already saved are only switched over, not overwritten.

### 7. Screenshot mode and language
- **Hide sensitive data** (eye button in the sidebar, `⇧⌘H`): IP, wallet and MAC addresses and the Wi-Fi name are replaced by gibberish of the same shape, input fields and raw JSON are blurred. Worker names stay readable.
- **German and English**: on a German Mac the app starts in German, otherwise in English. The language can be fixed in the settings (takes effect after restarting the app). Numbers follow the Mac's region format.

---

## Project structure

```text
MinerGuru/
├── MinerGuru.xcodeproj/        # Xcode project (synchronized folders: new files are picked up automatically)
├── Package.swift               # Swift package (Swift 6, macOS 14+), another way to build and test
├── build-app.sh                # Quick app bundle without the Xcode project
├── scripts/
│   ├── release.sh              # Release: DMG, trace check, upload files with checksums
│   ├── make-dmg.sh             # Release build (universal) and DMG with the install background
│   └── generate-*.swift        # DMG background, app icon, QR codes, social preview image
├── MinerGuru/
│   ├── MinerGuruApp.swift      # App entry, main window, menu bar, shortcuts
│   ├── Localizable.xcstrings   # Translations (source German, English)
│   ├── Models/                 # Data models: miner telemetry (with lenient decoding), coins,
│   │                           # solo mining odds, pool slots, pool library
│   ├── Services/
│   │   ├── MinerStore.swift        # Miner list, polling, settings, persistence
│   │   ├── PoolLibraryStore.swift  # Saved pool configurations
│   │   ├── NetworkScanStore.swift  # State of the subnet scan
│   │   ├── MinerAPIClient.swift    # REST client for AxeOS / NerdOS
│   │   └── …                       # Network scanner, pool latency, live log WebSocket
│   ├── Support/                # Number formatting (DisplayFormat, MinerFormatting), language, logging
│   └── Views/
│       ├── Fleet/              # Dashboard: onboarding, solo odds, miner cards, pool table
│       ├── Miner/              # Miner details, controls, live log
│       ├── Pools/              # Pool library and assignment to miners
│       └── Components/         # Shared building blocks (cards, badges, layouts, privacy mode)
├── MinerGuruWidgets/           # Widgets and Control Center controls
├── MockMiners/                 # Simulated miners of every variant for testing without hardware
└── MinerGuruTests/             # About 300 unit tests (Swift Testing and XCTest)
```

---

## Build, test and release

```bash
open MinerGuru.xcodeproj   # in Xcode: ⌘R to run, ⌘U to test
```

```bash
swift test                 # all unit tests without the Xcode UI
```

```bash
scripts/make-dmg.sh        # creates dist/MinerGuru-<version>.dmg
```

### Testing without hardware (simulated miners)

`MockMiners/` holds a `/api/system/info` response for every known Bitaxe and NerdOS variant
(`variants/*.json`, generated by `make_variants.py` from two anonymized real responses and the
board tables in the firmware sources) and a server that behaves like the firmware
(AxeOS applies settings only after a restart, NerdOS at once; live log over WebSocket).

```bash
MockMiners/run-app-with-mocks.sh           # mock servers plus a separate app "MinerGuru (Mock)" with all variants
```

```bash
MockMiners/run-app-with-mocks.sh hex nerdqx   # matching variants only
```

```bash
python3 MockMiners/mock_miner.py --list    # variants and ports (from 127.0.0.1:48001)
```

The mock app has its own bundle ID (`app.minerguru.MinerGuru.mock`) and does not touch the real miner
list. Every request of the app shows up with its body in the terminal. The unit tests (`VariantTests`) check
model detection, pool format, dual pool and clock profiles for every variant. New variant: add an entry to
`make_variants.py`, run the script, add the expectation to `MinerGuruTests/VariantTests.swift`.

Xcode picks up new UI strings into `MinerGuru/Localizable.xcstrings` automatically when building; enter the English translation there in the catalog editor.

The full release guide (including the manual steps and notarization) is in [RELEASE.md](RELEASE.md).

The app's logs (network, persistence, live log) appear in Console.app under the subsystem `app.minerguru.MinerGuru`.
