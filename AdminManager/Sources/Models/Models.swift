import Foundation
import SwiftUI

// MARK: - Device Model

struct Device: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var category: DeviceCategory
    var notes: String
    var lastConnected: Date?
    var isOnline: Bool

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        category: DeviceCategory = .server,
        notes: String = "",
        lastConnected: Date? = nil,
        isOnline: Bool = false,
        customCommands: DeviceCustomCommands? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.category = category
        self.notes = notes
        self.lastConnected = lastConnected
        self.isOnline = isOnline
        self.customCommands = customCommands
    }

    var displayName: String {
        name.isEmpty ? hostname : name
    }

    var connectionString: String {
        "\(username)@\(hostname):\(port)"
    }

    var isLocalhost: Bool {
        hostname == "localhost" || hostname == "127.0.0.1" || hostname == "::1"
    }

    /// Custom commands for this specific device. If set, these override the default commands.
    var customCommands: DeviceCustomCommands?
}

// MARK: - Device Custom Commands

struct DeviceCustomCommands: Codable, Sendable, Hashable {
    var cleanCache: String?
    var systemInfo: String?
    var listProcesses: String?
    var listPorts: String?

    var isEmpty: Bool {
        cleanCache == nil && systemInfo == nil && listProcesses == nil && listPorts == nil
    }
}

enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case password = "Password"
    case sshKey = "SSH Key"
    case sshAgent = "SSH Agent"

    var icon: String {
        switch self {
        case .password: return "key.fill"
        case .sshKey: return "doc.text.fill"
        case .sshAgent: return "person.badge.key.fill"
        }
    }
}

enum DeviceCategory: String, Codable, CaseIterable, Sendable {
    // Apple
    case macMini = "Mac Mini"
    case macStudio = "Mac Studio"
    case macPro = "Mac Pro"
    case macbookAir = "MacBook Air"
    case macbookPro = "MacBook Pro"
    case iMac = "iMac"
    // Single Board Computers
    case raspberryPi = "Raspberry Pi"
    case jetsonNano = "Jetson Nano"
    case jetsonThor = "Jetson Thor"
    // Infrastructure
    case server = "Server"
    case nas = "NAS"
    case router = "Router"
    // Generic
    case miniPC = "Mini PC"
    case desktop = "Desktop"
    case laptop = "Laptop"
    case other = "Other"

    var icon: String {
        switch self {
        case .macMini: return "macmini"
        case .macStudio: return "macstudio"
        case .macPro: return "macpro"
        case .macbookAir: return "laptopcomputer"
        case .macbookPro: return "laptopcomputer"
        case .iMac: return "desktopcomputer"
        case .raspberryPi: return "cpu"
        case .jetsonNano: return "cpu"
        case .jetsonThor: return "cpu"
        case .server: return "server.rack"
        case .nas: return "externaldrive.fill"
        case .router: return "wifi.router.fill"
        case .miniPC: return "macmini"
        case .desktop: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .other: return "rectangle.connected.to.line.below"
        }
    }

    var color: String {
        switch self {
        case .macMini: return "gray"
        case .macStudio: return "gray"
        case .macPro: return "gray"
        case .macbookAir: return "blue"
        case .macbookPro: return "purple"
        case .iMac: return "blue"
        case .raspberryPi: return "red"
        case .jetsonNano: return "green"
        case .jetsonThor: return "orange"
        case .server: return "blue"
        case .nas: return "orange"
        case .router: return "cyan"
        case .miniPC: return "cyan"
        case .desktop: return "purple"
        case .laptop: return "green"
        case .other: return "gray"
        }
    }
}

// MARK: - System Metrics

struct SystemMetrics: Identifiable, Sendable {
    let id: UUID
    let deviceId: UUID
    var timestamp: Date
    var cpuUsage: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskUsed: UInt64
    var diskTotal: UInt64
    var rootVolumeReadOnly: Bool
    var temperature: Double?
    var fanSpeed: Int?
    var powerUsage: Double?
    var powerSource: String?
    var networkIn: UInt64
    var networkOut: UInt64
    var loadAverage: [Double]
    var uptime: TimeInterval
    var processes: Int
    // GPU metrics
    var gpuUsage: Double?
    var gpuTemperature: Double?
    var gpuMemoryUsed: UInt64?
    var gpuMemoryTotal: UInt64?
    var gpuPowerDraw: Double?

    init(
        id: UUID = UUID(),
        deviceId: UUID,
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsed: UInt64 = 0,
        memoryTotal: UInt64 = 0,
        diskUsed: UInt64 = 0,
        diskTotal: UInt64 = 0,
        rootVolumeReadOnly: Bool = false,
        temperature: Double? = nil,
        fanSpeed: Int? = nil,
        powerUsage: Double? = nil,
        powerSource: String? = nil,
        networkIn: UInt64 = 0,
        networkOut: UInt64 = 0,
        loadAverage: [Double] = [],
        uptime: TimeInterval = 0,
        processes: Int = 0,
        gpuUsage: Double? = nil,
        gpuTemperature: Double? = nil,
        gpuMemoryUsed: UInt64? = nil,
        gpuMemoryTotal: UInt64? = nil,
        gpuPowerDraw: Double? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.rootVolumeReadOnly = rootVolumeReadOnly
        self.temperature = temperature
        self.fanSpeed = fanSpeed
        self.powerUsage = powerUsage
        self.powerSource = powerSource
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.loadAverage = loadAverage
        self.uptime = uptime
        self.processes = processes
        self.gpuUsage = gpuUsage
        self.gpuTemperature = gpuTemperature
        self.gpuMemoryUsed = gpuMemoryUsed
        self.gpuMemoryTotal = gpuMemoryTotal
        self.gpuPowerDraw = gpuPowerDraw
    }

    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var diskUsagePercent: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal) * 100
    }

    var memoryUsedGB: Double {
        Double(memoryUsed) / 1_073_741_824
    }

    var memoryTotalGB: Double {
        Double(memoryTotal) / 1_073_741_824
    }

    var diskUsedGB: Double {
        Double(diskUsed) / 1_073_741_824
    }

    var diskTotalGB: Double {
        Double(diskTotal) / 1_073_741_824
    }

    var uptimeFormatted: String {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var gpuMemoryUsedGB: Double {
        Double(gpuMemoryUsed ?? 0) / 1_073_741_824
    }

    var gpuMemoryTotalGB: Double {
        Double(gpuMemoryTotal ?? 0) / 1_073_741_824
    }

    var gpuMemoryUsagePercent: Double {
        guard let total = gpuMemoryTotal, total > 0, let used = gpuMemoryUsed else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var hasGPUMetrics: Bool {
        gpuUsage != nil || gpuTemperature != nil || gpuMemoryUsed != nil || gpuPowerDraw != nil
    }

    var healthStatus: HealthStatus {
        var score = 0
        var total = rootVolumeReadOnly || diskTotal == 0 ? 2 : 3 // Only measured writable volumes contribute disk pressure.

        if cpuUsage < 70 { score += 1 }
        if memoryUsagePercent < 80 { score += 1 }
        if !rootVolumeReadOnly && diskTotal > 0 && !StoragePressure.isHigh(used: diskUsed, total: diskTotal, readOnly: false) { score += 1 }
        if let temp = temperature {
            total += 1
            if temp < 75 { score += 1 }
        }

        if score == total { return .healthy }
        if score >= total - 1 { return .warning }
        return .critical
    }
}

enum HealthStatus: String, Sendable {
    case healthy = "Healthy"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .healthy: return "green"
        case .warning: return "yellow"
        case .critical: return "red"
        case .unknown: return "gray"
        }
    }

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - SSH Session Tab

struct SSHTab: Identifiable, Hashable {
    let id: UUID
    var deviceId: UUID
    var title: String
    var isConnected: Bool
    var terminalOutput: [TerminalLine]
    var currentCommand: String

    init(
        id: UUID = UUID(),
        deviceId: UUID,
        title: String,
        isConnected: Bool = false,
        terminalOutput: [TerminalLine] = [],
        currentCommand: String = ""
    ) {
        self.id = id
        self.deviceId = deviceId
        self.title = title
        self.isConnected = isConnected
        self.terminalOutput = terminalOutput
        self.currentCommand = currentCommand
    }

    static func == (lhs: SSHTab, rhs: SSHTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TerminalLine: Identifiable, Hashable {
    let id: UUID
    var content: String
    var type: LineType
    var timestamp: Date

    init(id: UUID = UUID(), content: String, type: LineType = .output, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
    }

    enum LineType: Sendable, Hashable {
        case command
        case output
        case error
        case system
        case aiUser
        case aiResponse
    }
}

// MARK: - SSH Config

struct SSHConfig: Codable, Sendable {
    var defaultPort: Int
    var connectionTimeout: Int
    var keepAliveInterval: Int
    var defaultKeyPath: String
    var knownHostsPath: String

    init(
        defaultPort: Int = 22,
        connectionTimeout: Int = 30,
        keepAliveInterval: Int = 60,
        defaultKeyPath: String = "~/.ssh/id_rsa",
        knownHostsPath: String = "~/.ssh/known_hosts"
    ) {
        self.defaultPort = defaultPort
        self.connectionTimeout = connectionTimeout
        self.keepAliveInterval = keepAliveInterval
        self.defaultKeyPath = defaultKeyPath
        self.knownHostsPath = knownHostsPath
    }
}

// MARK: - Device Detail Tabs

enum DeviceDetailTab: String, CaseIterable {
    case overview = "Overview"
    case systemInfo = "System Info"
    case storage = "Storage"
    case ports = "Ports & Processes"
    case docker = "Docker"
    case processes = "Processes"

    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .systemInfo: return "info.circle"
        case .storage: return "externaldrive.fill"
        case .ports: return "network"
        case .docker: return "shippingbox.fill"
        case .processes: return "cpu"
        }
    }
}

// MARK: - System Info Model

struct DeviceSystemInfo: Sendable {
    let hostname: String
    let osName: String
    let osVersion: String
    let kernelVersion: String
    let architecture: String
    let cpuModel: String
    let cpuCores: Int
    let memoryTotal: String
    let diskTotal: String
    let diskUsed: String
    let uptimeFormatted: String
    let shellVersion: String
    let ipAddresses: [String]
}

// MARK: - Port/Process Models

struct PortInfo: Identifiable, Sendable {
    let id: UUID
    let port: Int
    let proto: PortProtocol
    let pid: Int
    let processName: String
    let state: String
    let localAddress: String

    init(
        id: UUID = UUID(),
        port: Int,
        proto: PortProtocol = .tcp,
        pid: Int,
        processName: String,
        state: String = "LISTEN",
        localAddress: String = "0.0.0.0"
    ) {
        self.id = id
        self.port = port
        self.proto = proto
        self.pid = pid
        self.processName = processName
        self.state = state
        self.localAddress = localAddress
    }
}

enum PortProtocol: String, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
    case tcp6 = "TCP6"
    case udp6 = "UDP6"
}

// MARK: - Process Models

struct SystemProcess: Identifiable, Sendable {
    let id: UUID
    let pid: Int
    let user: String
    let cpuPercent: Double
    let memPercent: Double
    let memMB: Double
    let command: String
    let state: String

    init(
        id: UUID = UUID(),
        pid: Int,
        user: String,
        cpuPercent: Double,
        memPercent: Double,
        memMB: Double,
        command: String,
        state: String = ""
    ) {
        self.id = id
        self.pid = pid
        self.user = user
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.memMB = memMB
        self.command = command
        self.state = state
    }
}

enum ProcessSortField: String, CaseIterable {
    case memory = "Memory"
    case cpu = "CPU"
    case pid = "PID"
    case name = "Name"
}

enum KillSignal: Int {
    case term = 15
    case kill = 9
}

// MARK: - Docker Models

struct DockerContainer: Identifiable, Sendable {
    let id: UUID
    let containerId: String
    let name: String
    let image: String
    let status: String
    let state: DockerContainerState
    let ports: String

    init(
        id: UUID = UUID(),
        containerId: String,
        name: String,
        image: String,
        status: String,
        state: DockerContainerState,
        ports: String = ""
    ) {
        self.id = id
        self.containerId = containerId
        self.name = name
        self.image = image
        self.status = status
        self.state = state
        self.ports = ports
    }
}

enum DockerContainerState: String, Sendable {
    case running = "running"
    case exited = "exited"
    case paused = "paused"
    case restarting = "restarting"
    case created = "created"
    case dead = "dead"
    case removing = "removing"
    case unknown = "unknown"

    var icon: String {
        switch self {
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .restarting: return "arrow.clockwise.circle.fill"
        case .exited: return "stop.circle.fill"
        case .dead: return "xmark.circle.fill"
        case .created: return "plus.circle.fill"
        case .removing: return "trash.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

enum DockerAvailability: Sendable {
    case unknown
    case notInstalled
    case installed(version: String)
}

// MARK: - Navigation

enum NavigationItem: String, Identifiable, CaseIterable {
    case dashboard = "Dashboard"
    case devices = "Devices"
    case terminal = "Terminal"
    case metrics = "Metrics"
    case network = "Network"
    case sshConfig = "SSH Config"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .devices: return "desktopcomputer"
        case .terminal: return "terminal.fill"
        case .metrics: return "chart.bar.fill"
        case .network: return "network"
        case .sshConfig: return "gearshape.fill"
        }
    }
}

// MARK: - Network Scanner Models

struct NetworkHost: Identifiable, Hashable {
    let id: UUID
    let ip: String
    var hostname: String
    var mac: String
    var vendor: String
    var matchedDeviceId: UUID?
    var source: ScanSource

    init(id: UUID = UUID(), ip: String, hostname: String = "", mac: String = "", vendor: String = "", matchedDeviceId: UUID? = nil, source: ScanSource = .local) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.mac = mac
        self.vendor = vendor
        self.matchedDeviceId = matchedDeviceId
        self.source = source
    }
}

enum ScanSource: String, CaseIterable, Sendable {
    case local = "Local"
    case remote = "Remote"
}

// MARK: - Topology Models

struct TopologyNode: Identifiable, Codable, Hashable {
    let deviceId: UUID
    var position: CGPointCodable

    var id: UUID { deviceId }
}

struct CGPointCodable: Codable, Hashable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct TopologyConnection: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceDeviceId: UUID
    var targetDeviceId: UUID
    var label: String

    init(id: UUID = UUID(), source: UUID, target: UUID, label: String = "") {
        self.id = id
        self.sourceDeviceId = source
        self.targetDeviceId = target
        self.label = label
    }
}

enum NetworkTab: String, CaseIterable {
    case scanner = "Scanner"
    case topology = "Topology"

    var icon: String {
        switch self {
        case .scanner: return "antenna.radiowaves.left.and.right"
        case .topology: return "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: - Topology Container

struct TopologyContainer: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var position: CGPointCodable
    var size: CGSizeCodable
    var color: String
    var icon: String

    init(
        id: UUID = UUID(),
        label: String,
        position: CGPoint,
        size: CGSize = CGSize(width: 250, height: 200),
        color: String = "blue",
        icon: String = "rectangle.3.group"
    ) {
        self.id = id
        self.label = label
        self.position = CGPointCodable(position)
        self.size = CGSizeCodable(size)
        self.color = color
        self.icon = icon
    }

    var rect: CGRect {
        CGRect(origin: position.cgPoint, size: size.cgSize)
    }
}

struct CGSizeCodable: Codable, Hashable {
    var width: Double
    var height: Double

    var cgSize: CGSize { CGSize(width: width, height: height) }

    init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

// MARK: - Topology Decorative Icon

struct TopologyDecorativeIcon: Identifiable, Codable, Hashable {
    let id: UUID
    var iconType: DecorativeIconType
    var position: CGPointCodable
    var label: String

    init(
        id: UUID = UUID(),
        iconType: DecorativeIconType,
        position: CGPoint,
        label: String = ""
    ) {
        self.id = id
        self.iconType = iconType
        self.position = CGPointCodable(position)
        self.label = label.isEmpty ? iconType.defaultLabel : label
    }
}

enum DecorativeIconType: String, Codable, CaseIterable, Hashable {
    case internet = "Internet"
    case firewall = "Firewall"
    case cloud = "Cloud"
    case switchDevice = "Switch"
    case database = "Database"
    case aiCluster = "AI Cluster"
    case storage = "Storage"
    case vpn = "VPN"
    case dns = "DNS"
    case loadBalancer = "Load Balancer"

    var icon: String {
        switch self {
        case .internet: return "globe"
        case .firewall: return "shield.lefthalf.filled"
        case .cloud: return "cloud.fill"
        case .switchDevice: return "arrow.triangle.swap"
        case .database: return "cylinder.split.1x2"
        case .aiCluster: return "brain.head.profile"
        case .storage: return "externaldrive.fill.badge.icloud"
        case .vpn: return "lock.shield"
        case .dns: return "list.bullet.rectangle"
        case .loadBalancer: return "arrow.triangle.branch"
        }
    }

    var defaultLabel: String { rawValue }

    var color: String {
        switch self {
        case .internet: return "blue"
        case .firewall: return "red"
        case .cloud: return "cyan"
        case .switchDevice: return "green"
        case .database: return "purple"
        case .aiCluster: return "orange"
        case .storage: return "gray"
        case .vpn: return "green"
        case .dns: return "blue"
        case .loadBalancer: return "purple"
        }
    }
}

// MARK: - Device Power Specifications

/// Reference power consumption data for known device categories.
/// Values are typical (TDP) wattages based on real hardware specs.
struct DevicePowerSpec: Sendable {
    let typicalWatts: Double
    let maxWatts: Double
    let hasDiscreteGPU: Bool
    let gpuName: String

    static func spec(for category: DeviceCategory) -> DevicePowerSpec {
        switch category {
        // Raspberry Pi 5: 5V/5A = 25W max, typical 5-12W
        case .raspberryPi:
            return DevicePowerSpec(typicalWatts: 8, maxWatts: 25, hasDiscreteGPU: false, gpuName: "VideoCore VII")

        // Jetson Nano: 5-10W modes
        case .jetsonNano:
            return DevicePowerSpec(typicalWatts: 10, maxWatts: 15, hasDiscreteGPU: true, gpuName: "128-core Maxwell")

        // Jetson Thor: Next-gen Jetson, ~100W module
        case .jetsonThor:
            return DevicePowerSpec(typicalWatts: 100, maxWatts: 200, hasDiscreteGPU: true, gpuName: "Blackwell GPU")

        // Mac Mini M4: 5-65W typical
        case .macMini:
            return DevicePowerSpec(typicalWatts: 15, maxWatts: 65, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // MacBook Air M4: 8-30W (fanless)
        case .macbookAir:
            return DevicePowerSpec(typicalWatts: 10, maxWatts: 30, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // MacBook Pro M3 Pro: 15-100W
        case .macbookPro:
            return DevicePowerSpec(typicalWatts: 30, maxWatts: 100, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // Mac Studio: 30-150W
        case .macStudio:
            return DevicePowerSpec(typicalWatts: 50, maxWatts: 150, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // Mac Pro: 80-300W
        case .macPro:
            return DevicePowerSpec(typicalWatts: 150, maxWatts: 300, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // iMac: 30-140W
        case .iMac:
            return DevicePowerSpec(typicalWatts: 40, maxWatts: 140, hasDiscreteGPU: false, gpuName: "Apple M-series GPU")

        // Generic server: 100-500W
        case .server:
            return DevicePowerSpec(typicalWatts: 200, maxWatts: 500, hasDiscreteGPU: false, gpuName: "")

        // NAS: 20-100W
        case .nas:
            return DevicePowerSpec(typicalWatts: 40, maxWatts: 100, hasDiscreteGPU: false, gpuName: "")

        // Router: 5-20W
        case .router:
            return DevicePowerSpec(typicalWatts: 10, maxWatts: 20, hasDiscreteGPU: false, gpuName: "")

        // Mini PC: 15-65W
        case .miniPC:
            return DevicePowerSpec(typicalWatts: 25, maxWatts: 65, hasDiscreteGPU: false, gpuName: "")

        // Desktop: 100-350W
        case .desktop:
            return DevicePowerSpec(typicalWatts: 150, maxWatts: 350, hasDiscreteGPU: false, gpuName: "")

        // Laptop: 15-65W
        case .laptop:
            return DevicePowerSpec(typicalWatts: 25, maxWatts: 65, hasDiscreteGPU: false, gpuName: "")

        // Other
        case .other:
            return DevicePowerSpec(typicalWatts: 30, maxWatts: 100, hasDiscreteGPU: false, gpuName: "")
        }
    }
}

// MARK: - Device Command Profiles

/// Holds the default commands for each device category.
/// Users can view these in Settings and override per-device.
struct DeviceCommandProfile: Codable, Sendable, Identifiable {
    var id: String { category.rawValue }
    var category: DeviceCategory
    var cleanCache: String
    var systemInfo: String
    var listProcesses: String
    var listPorts: String

    static func defaultProfile(for category: DeviceCategory) -> DeviceCommandProfile {
        switch category {
        // macOS devices
        case .macMini, .macStudio, .macPro, .macbookAir, .macbookPro, .iMac:
            return DeviceCommandProfile(
                category: category,
                cleanCache: """
                FREE_BEFORE=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
                sudo purge 2>/dev/null
                FREE_AFTER=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
                PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
                if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                  FREED=$(( (FREE_AFTER - FREE_BEFORE) * PAGE_SIZE / 1048576 ))
                  echo "CACHE_FREED=${FREED}MB"
                else
                  echo "CACHE_FREED=0MB"
                fi
                echo "CACHE_OS=Darwin"
                """,
                systemInfo: "system_profiler SPHardwareDataType SPSoftwareDataType",
                listProcesses: "ps aux --sort=-%mem | head -51",
                listPorts: "lsof -iTCP -sTCP:LISTEN -P -n"
            )

        // Jetson Nano - standard Linux with NVIDIA
        case .jetsonNano:
            return DeviceCommandProfile(
                category: category,
                cleanCache: """
                FREE_BEFORE=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                sync
                sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
                FREE_AFTER=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                  FREED=$((FREE_AFTER - FREE_BEFORE))
                  echo "CACHE_FREED=${FREED}MB"
                else
                  echo "CACHE_FREED=0MB"
                fi
                echo "CACHE_OS=Linux"
                """,
                systemInfo: "cat /proc/device-tree/model 2>/dev/null; uname -a; free -h; df -h /; tegrastats --interval 1000 --count 1 2>/dev/null || true",
                listProcesses: "ps aux --sort=-%mem | head -51",
                listPorts: "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
            )

        // Jetson Thor - JetPack 6+ / L4T with different thermal and cache paths
        case .jetsonThor:
            return DeviceCommandProfile(
                category: category,
                cleanCache: """
                FREE_BEFORE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
                sync
                sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
                sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory' 2>/dev/null
                if command -v nvidia-smi >/dev/null 2>&1; then
                  sudo nvidia-smi --gpu-reset 2>/dev/null || true
                fi
                FREE_AFTER=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
                if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                  FREED=$((FREE_AFTER - FREE_BEFORE))
                  echo "CACHE_FREED=${FREED}MB"
                else
                  echo "CACHE_FREED=0MB"
                fi
                echo "CACHE_OS=Linux-JetsonThor"
                """,
                systemInfo: """
                cat /proc/device-tree/model 2>/dev/null; echo "---"
                uname -a; echo "---"
                free -h; echo "---"
                df -h /; echo "---"
                nvidia-smi 2>/dev/null || echo "nvidia-smi not available"
                cat /etc/nv_tegra_release 2>/dev/null || cat /etc/jetson_release 2>/dev/null || true
                """,
                listProcesses: "ps aux --sort=-%mem | head -51",
                listPorts: "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
            )

        // Raspberry Pi
        case .raspberryPi:
            return DeviceCommandProfile(
                category: category,
                cleanCache: """
                FREE_BEFORE=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                sync
                sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
                FREE_AFTER=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                  FREED=$((FREE_AFTER - FREE_BEFORE))
                  echo "CACHE_FREED=${FREED}MB"
                else
                  echo "CACHE_FREED=0MB"
                fi
                echo "CACHE_OS=Linux-RPi"
                """,
                systemInfo: "cat /proc/device-tree/model 2>/dev/null; uname -a; free -h; df -h /; vcgencmd measure_temp 2>/dev/null || true",
                listProcesses: "ps aux --sort=-%mem | head -51",
                listPorts: "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
            )

        // Generic Linux (server, NAS, miniPC, desktop, laptop, other)
        default:
            return DeviceCommandProfile(
                category: category,
                cleanCache: """
                OS=$(uname -s 2>/dev/null)
                if [ "$OS" = "Darwin" ]; then
                  FREE_BEFORE=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
                  sudo purge 2>/dev/null
                  FREE_AFTER=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\\./, "", $3); print $3}')
                  PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
                  if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                    FREED=$(( (FREE_AFTER - FREE_BEFORE) * PAGE_SIZE / 1048576 ))
                    echo "CACHE_FREED=${FREED}MB"
                  else
                    echo "CACHE_FREED=0MB"
                  fi
                  echo "CACHE_OS=Darwin"
                elif [ "$OS" = "Linux" ]; then
                  FREE_BEFORE=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                  sync
                  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
                  FREE_AFTER=$(free -m 2>/dev/null | awk '/^Mem:/{print $4}')
                  if [ -n "$FREE_BEFORE" ] && [ -n "$FREE_AFTER" ]; then
                    FREED=$((FREE_AFTER - FREE_BEFORE))
                    echo "CACHE_FREED=${FREED}MB"
                  else
                    echo "CACHE_FREED=0MB"
                  fi
                  echo "CACHE_OS=Linux"
                else
                  echo "CACHE_FREED=0MB"
                  echo "CACHE_OS=Unknown"
                fi
                """,
                systemInfo: "uname -a; free -h 2>/dev/null; df -h / 2>/dev/null",
                listProcesses: "ps aux --sort=-%mem 2>/dev/null | head -51",
                listPorts: "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null"
            )
        }
    }
}

/// Manages saved command profile overrides per device category.
enum DeviceCommandProfileStore {
    private static let storageKey = "admin_manager_command_profiles"

    static func loadOverrides() -> [DeviceCategory: DeviceCommandProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([DeviceCommandProfile].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.category, $0) })
    }

    static func saveOverrides(_ overrides: [DeviceCategory: DeviceCommandProfile]) {
        let profiles = Array(overrides.values)
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Returns the effective command profile: device custom > category override > default
    static func effectiveProfile(for device: Device) -> DeviceCommandProfile {
        let defaultProfile = DeviceCommandProfile.defaultProfile(for: device.category)
        let overrides = loadOverrides()
        let categoryOverride = overrides[device.category]

        var profile = categoryOverride ?? defaultProfile

        // Per-device custom commands take highest priority
        if let custom = device.customCommands {
            if let cmd = custom.cleanCache { profile.cleanCache = cmd }
            if let cmd = custom.systemInfo { profile.systemInfo = cmd }
            if let cmd = custom.listProcesses { profile.listProcesses = cmd }
            if let cmd = custom.listPorts { profile.listPorts = cmd }
        }

        return profile
    }
}
