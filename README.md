# Admin Manager · Beta

A native macOS application for managing remote devices via SSH with real-time system monitoring.

## Features

- **Device Management** — Register and organize servers, desktops, laptops, Raspberry Pi, NAS, routers and more
- **SSH Terminal** — Tabbed terminal interface with command execution; AI suggestions require review before running
- **Real-time Monitoring** — Live CPU, memory, disk, temperature, network and process metrics
- **Dashboard** — Overview of all devices with health status indicators
- **Device Detail** — Full specs view with historical metrics charts
- **Dark Theme** — Polished dark UI designed for system administrators

## Status: Beta

AdminManager is beta software under active development. The Mac app detects the
remote operating system and uses its native read-only collector. Storage shows
disks (including unmounted drives), partitions, mounted filesystem usage and
CPU/RAM/swap resources without adding logical volume capacity to physical capacity.

| Remote system | Storage and resources | Requirements / limits |
| --- | --- | --- |
| Linux, including ZimaOS/CasaOS | Block devices, partitions, Btrfs/other mounts, RAM/swap/load | `lsblk`, `findmnt`, `/proc`; missing tools show partial data and warnings |
| macOS | Physical disks, USB drives, APFS containers and volumes, estimated available RAM/swap/load | `diskutil`, `plutil`, `sysctl`, `vm_stat`; APFS free space is shared |
| Windows | OS-visible disks, partitions, drive letters/folder mounts, RAM/page file | Existing OpenSSH server, Windows PowerShell 5.1+, Storage/CIM read access; basic CIM fallback when possible |
| FreeBSD / TrueNAS CORE, other systems | Recognized or reported as unsupported | Detailed inventory/monitoring is not implemented; no Linux/macOS disk commands are substituted |

System information, processes and listening ports also choose their collector by
detected OS. This does not promise feature parity for administrative write actions.
NAS vendors with restricted shells or missing utilities can expose partial data;
Synology/QNAP, hardware RAID members and Storage Spaces members are not certified.
The application itself still runs on macOS 14+.

Storage requires no sudo, installs nothing, and never mounts, formats or changes
disks. Enable/configure SSH yourself on each remote host; AdminManager does not
change OS access settings. Refresh Storage after adding a drive. On the Mac running
AdminManager, allow Local Network access when prompted. Missing measurements stay
unavailable, failed refreshes retain a clearly labelled previous snapshot, and
unsupported systems do not produce fabricated zero-usage metrics.

Linux CPU uses counter differences (including I/O wait as idle and excluding guest
double-counting). Read-only OS roots are excluded from writable disk pressure.
Network values are cumulative byte totals. System Volume means the root/data/OS
volume, while Storage shows additional drives. Windows uses the actual system
drive rather than assuming `C:`; Unix load averages are unavailable on Windows.
SMART assessment and disk administration are not implemented.

See [Operating-system support](docs/operating-system-support.md) for the adapter
contract, limitations and validation coverage.

## Credentials and privacy

Your server list is kept on your Mac. SSH passwords and AI API keys are stored
in macOS Keychain; no credentials or device inventory are bundled with the app.
Existing AI keys are migrated from preferences after a verified Keychain write.
See [SECURITY.md](SECURITY.md) for migration failures and remote/AI trust boundaries.

This is a developer beta. Review administration commands before running them.

## Download the beta

Download the versioned macOS DMG and `SHA256SUMS.txt` from
[GitHub Releases](https://github.com/bujosa/admin-manager/releases).
The universal app supports Apple Silicon and Intel Macs running macOS 14+.
Open the DMG and drag AdminManager to Applications. No server list or credentials
are included. Windows and Linux support refers to remote SSH hosts; the desktop
application runs on macOS.

These developer builds are ad-hoc signed, not Apple Developer ID signed or
notarized. macOS can block the first launch. Read the release notes and
[Apple's guidance on opening downloaded apps](https://support.apple.com/en-us/102445).
Only install a build whose source and checksum you trust; do not disable
Gatekeeper globally.

## Requirements

- macOS 14.0+ and Xcode 16+
- [Tuist](https://tuist.io) for project generation

## Getting Started

```bash
# Install Tuist (if not installed)
brew tap tuist/tuist
brew install tuist

# Generate Xcode project
make generate

# Build and run
make run
```

## Available Commands

```
make help      # Show all available targets
make install   # Install dependencies with Tuist
make generate  # Generate Xcode project
make build     # Build debug version
make run       # Build and run the app
make release   # Build release version
make dmg       # Create DMG installer
make clean     # Clean all build artifacts
make edit      # Edit Tuist manifest
```

## Project Structure

```
AdminManager/
├── Sources/
│   ├── AdminManagerApp.swift       # App entry point
│   ├── ContentView.swift           # Root navigation
│   ├── Models/
│   │   └── Models.swift            # Device, SystemMetrics, SSHConfig
│   ├── Services/
│   │   ├── SSHService.swift        # SSH connections & device persistence
│   │   ├── DeviceMonitorService.swift  # System metrics monitoring
│   │   └── TabManager.swift        # Terminal tab management
│   ├── Theme/
│   │   └── Theme.swift             # Design tokens & view modifiers
│   └── Views/
│       ├── Devices/
│       │   ├── DashboardView.swift     # Device grid overview
│       │   ├── DeviceListView.swift    # Filterable device list
│       │   ├── DeviceDetailView.swift  # Full device specs & metrics
│       │   └── AddDeviceSheet.swift    # New device form
│       ├── Terminal/
│       │   └── TerminalView.swift      # SSH terminal interface
│       ├── Metrics/
│       │   └── MetricsView.swift       # Metrics dashboard
│       ├── Settings/
│       │   └── SettingsView.swift      # App preferences
│       └── Sidebar/
│           └── SidebarView.swift       # Navigation sidebar
├── Resources/
│   └── Assets.xcassets/
└── AdminManager.entitlements
```

## Validation

```bash
swift test
make build XCODEBUILD_FLAGS=CODE_SIGNING_ALLOWED=NO
```

The security tests use an in-memory credential backend and isolated test
preferences; they never read your saved devices or production credentials.

## Releasing

Releases are automated via GitHub Actions. To create a new release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Or trigger manually from the Actions tab with a version number.

## License

MIT

### AI model selection

Settings includes current text-model presets, a custom model ID, and a separate saved selection for each provider. Existing pinned models are preserved; select Recommended to adopt the current default. CLI providers can use their own configured default, and Ollama accepts an installed model name. Account access and inference charges depend on your provider.

The curated catalog was checked on 2026-10-16 against [OpenAI](https://developers.openai.com/api/docs/guides/latest-model), [Anthropic](https://platform.claude.com/docs/en/models/overview), and [Gemini](https://ai.google.dev/gemini-api/docs/models). OpenAI defaults to Luna for focused tasks; other tiers remain selectable.

Inventory uses explicit JSON columns from [lsblk](https://man7.org/linux/man-pages/man8/lsblk.8.html) and [findmnt](https://man7.org/linux/man-pages/man8/findmnt.8.html), with an older lsblk column fallback. Local network privacy follows [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Ad-hoc development builds may require separate permission review from signed distribution builds.
