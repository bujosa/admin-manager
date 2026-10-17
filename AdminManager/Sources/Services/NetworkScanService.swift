import Foundation
import SwiftUI

@Observable
@MainActor
final class NetworkScanService {
    var hosts: [NetworkHost] = []
    var isScanning = false
    var scanProgress: String = ""

    var nodes: [TopologyNode] = []
    var connections: [TopologyConnection] = []
    var containers: [TopologyContainer] = []
    var decorativeIcons: [TopologyDecorativeIcon] = []

    init() {
        loadTopology()
    }

    // MARK: - Local Network Scan

    func scanLocalNetwork(devices: [Device]) async {
        isScanning = true
        scanProgress = "Scanning local network..."
        hosts = []

        let output = await runLocalCommand("/usr/sbin/arp", arguments: ["-a"])
        hosts = parseArpOutput(output, source: .local)
        matchWithDevices(devices)

        scanProgress = "Found \(hosts.count) hosts"
        isScanning = false
    }

    // MARK: - Remote Network Scan

    func scanRemoteNetwork(deviceId: UUID, sshService: SSHService, devices: [Device]) async {
        isScanning = true
        scanProgress = "Scanning remote network..."
        hosts = []

        do {
            let output = try await sshService.executeCommand("arp -a 2>/dev/null || ip neigh show 2>/dev/null", on: deviceId)
            hosts = parseArpOutput(output, source: .remote)
            matchWithDevices(devices)
            scanProgress = "Found \(hosts.count) hosts"
        } catch {
            scanProgress = "Scan failed: \(error.localizedDescription)"
        }

        isScanning = false
    }

    // MARK: - ARP Output Parsing

    func parseArpOutput(_ output: String, source: ScanSource) -> [NetworkHost] {
        var results: [NetworkHost] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // macOS/BSD format: hostname (IP) at MAC on interface [ifscope]
            // Linux format: hostname (IP) at MAC [ether] on interface
            if let host = parseArpLine(trimmed, source: source) {
                results.append(host)
            } else if let host = parseIpNeighLine(trimmed, source: source) {
                // Linux ip neigh format: IP dev eth0 lladdr MAC REACHABLE
                results.append(host)
            }
        }

        // Deduplicate by IP
        var seen: Set<String> = []
        return results.filter { seen.insert($0.ip).inserted }
    }

    private func parseArpLine(_ line: String, source: ScanSource) -> NetworkHost? {
        // Pattern: hostname (IP) at MAC on interface
        guard line.contains("(") && line.contains(")") && line.contains(" at ") else { return nil }

        let parts = line.components(separatedBy: " ")
        guard parts.count >= 4 else { return nil }

        let hostname = parts[0] == "?" ? "" : parts[0]

        // Extract IP from parentheses
        guard let ipStart = line.firstIndex(of: "("),
              let ipEnd = line.firstIndex(of: ")") else { return nil }
        let ip = String(line[line.index(after: ipStart)..<ipEnd])

        // Extract MAC after "at"
        var mac = ""
        if let atIndex = parts.firstIndex(of: "at"), atIndex + 1 < parts.count {
            let macCandidate = parts[atIndex + 1]
            if macCandidate.contains(":") || macCandidate.contains("-") {
                mac = macCandidate
            }
        }

        // Skip incomplete entries
        if mac == "(incomplete)" || mac.isEmpty { mac = "N/A" }

        let vendor = lookupVendor(mac: mac)

        return NetworkHost(ip: ip, hostname: hostname, mac: mac, vendor: vendor, source: source)
    }

    private func parseIpNeighLine(_ line: String, source: ScanSource) -> NetworkHost? {
        // Pattern: 192.0.2.1 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE
        guard line.contains("lladdr") else { return nil }
        // Skip if it's already an arp-style line
        guard !line.contains("(") else { return nil }

        let parts = line.components(separatedBy: " ")
        guard parts.count >= 5 else { return nil }

        let ip = parts[0]
        guard ip.contains(".") || ip.contains(":") else { return nil }

        var mac = "N/A"
        if let lladdrIndex = parts.firstIndex(of: "lladdr"), lladdrIndex + 1 < parts.count {
            mac = parts[lladdrIndex + 1]
        }

        let vendor = lookupVendor(mac: mac)

        return NetworkHost(ip: ip, hostname: "", mac: mac, vendor: vendor, source: source)
    }

    // MARK: - Device Matching

    func matchWithDevices(_ devices: [Device]) {
        for i in hosts.indices {
            if let matched = devices.first(where: { $0.hostname == hosts[i].ip || $0.hostname == hosts[i].hostname }) {
                hosts[i].matchedDeviceId = matched.id
            }
        }
    }

    // MARK: - MAC Vendor Lookup (common prefixes)

    private func lookupVendor(mac: String) -> String {
        guard mac != "N/A" else { return "" }
        let prefix = mac.replacingOccurrences(of: "-", with: ":").uppercased()
        guard prefix.count >= 8 else { return "" }
        let oui = String(prefix.prefix(8))

        let vendors: [String: String] = [
            "DC:A6:32": "Raspberry Pi",
            "B8:27:EB": "Raspberry Pi",
            "E4:5F:01": "Raspberry Pi",
            "28:CD:C1": "Raspberry Pi",
            "00:50:56": "VMware",
            "00:0C:29": "VMware",
            "00:1C:42": "Parallels",
            "08:00:27": "VirtualBox",
            "52:54:00": "QEMU/KVM",
            "AA:BB:CC": "Docker",
            "02:42:AC": "Docker",
            "AC:DE:48": "Apple",
            "A4:83:E7": "Apple",
            "F0:18:98": "Apple",
            "3C:22:FB": "Apple",
            "14:98:77": "Apple",
            "DC:56:E7": "Apple",
            "70:56:81": "Apple",
            "A8:5C:2C": "Apple",
            "BC:D0:74": "Apple",
            "78:7B:8A": "Apple",
            "88:66:A5": "Apple",
            "A0:99:9B": "Apple",
            "38:F9:D3": "Apple",
            "44:2A:60": "Apple",
            "FC:E9:98": "Apple",
            "30:35:AD": "Apple",
            "8C:85:90": "Apple",
            "00:1A:2B": "Ayecom",
            "B0:BE:76": "TP-Link",
            "50:C7:BF": "TP-Link",
            "EC:08:6B": "TP-Link",
            "C0:06:C3": "TP-Link",
            "30:B5:C2": "TP-Link",
            "60:A4:4C": "ASUSTek",
            "04:92:26": "ASUSTek",
            "1C:87:2C": "ASUSTek",
            "C8:60:00": "ASUSTek",
            "F4:6D:04": "ASUSTek",
            "00:11:32": "Synology",
            "00:11:24": "QNAP",
            "B4:2E:99": "Ubiquiti",
            "78:8A:20": "Ubiquiti",
            "FC:EC:DA": "Ubiquiti",
            "18:E8:29": "Ubiquiti",
            "24:5A:4C": "Ubiquiti",
            "68:D7:9A": "Ubiquiti",
            "F0:9F:C2": "Ubiquiti",
            "74:DA:38": "Edimax",
            "44:D9:E7": "Ubiquiti",
            "00:E0:4C": "Realtek",
            "48:5D:60": "Realtek",
            "52:54:AB": "Realtek",
            "00:1E:58": "D-Link",
            "1C:7E:E5": "D-Link",
            "28:10:7B": "D-Link",
            "00:26:F2": "Netgear",
            "C4:3D:C7": "Netgear",
            "E0:91:F5": "Netgear",
            "20:E5:2A": "Netgear",
            "A4:2B:B0": "Netgear",
            "E8:48:B8": "Dell",
            "00:14:22": "Dell",
            "F8:DB:88": "Dell",
            "B0:83:FE": "Dell",
            "18:DB:F2": "Dell",
            "00:25:B5": "Dell",
            "EC:F4:BB": "Dell",
            "C8:1F:66": "Dell",
            "3C:97:0E": "HP/HPE",
            "00:1A:4B": "HP/HPE",
            "94:57:A5": "HP/HPE",
            "3C:D9:2B": "HP/HPE",
            "70:10:6F": "HP/HPE",
            "24:BE:05": "HP/HPE",
            "E4:11:5B": "HP/HPE",
            "68:B5:99": "HP/HPE",
            "50:65:F3": "HP/HPE",
            "00:30:48": "Supermicro",
            "AC:1F:6B": "Supermicro",
            "0C:C4:7A": "Supermicro",
        ]

        return vendors[oui] ?? ""
    }

    // MARK: - Local Command Execution

    private func runLocalCommand(_ path: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: - Topology Persistence

    func loadTopology() {
        if let data = UserDefaults.standard.data(forKey: "topologyNodes"),
           let decoded = try? JSONDecoder().decode([TopologyNode].self, from: data) {
            nodes = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "topologyConnections"),
           let decoded = try? JSONDecoder().decode([TopologyConnection].self, from: data) {
            connections = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "topologyContainers"),
           let decoded = try? JSONDecoder().decode([TopologyContainer].self, from: data) {
            containers = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "topologyDecorativeIcons"),
           let decoded = try? JSONDecoder().decode([TopologyDecorativeIcon].self, from: data) {
            decorativeIcons = decoded
        }
    }

    func saveTopology() {
        if let data = try? JSONEncoder().encode(nodes) {
            UserDefaults.standard.set(data, forKey: "topologyNodes")
        }
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: "topologyConnections")
        }
        if let data = try? JSONEncoder().encode(containers) {
            UserDefaults.standard.set(data, forKey: "topologyContainers")
        }
        if let data = try? JSONEncoder().encode(decorativeIcons) {
            UserDefaults.standard.set(data, forKey: "topologyDecorativeIcons")
        }
    }

    func addNode(deviceId: UUID, position: CGPoint) {
        guard !nodes.contains(where: { $0.deviceId == deviceId }) else { return }
        nodes.append(TopologyNode(deviceId: deviceId, position: CGPointCodable(position)))
        saveTopology()
    }

    func removeNode(deviceId: UUID) {
        nodes.removeAll { $0.deviceId == deviceId }
        connections.removeAll { $0.sourceDeviceId == deviceId || $0.targetDeviceId == deviceId }
        saveTopology()
    }

    func updateNodePosition(deviceId: UUID, position: CGPoint) {
        if let index = nodes.firstIndex(where: { $0.deviceId == deviceId }) {
            nodes[index].position = CGPointCodable(position)
            saveTopology()
        }
    }

    func addConnection(source: UUID, target: UUID, label: String = "") {
        guard !connections.contains(where: {
            ($0.sourceDeviceId == source && $0.targetDeviceId == target) ||
            ($0.sourceDeviceId == target && $0.targetDeviceId == source)
        }) else { return }
        connections.append(TopologyConnection(source: source, target: target, label: label))
        saveTopology()
    }

    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        saveTopology()
    }

    func updateConnectionSource(id: UUID, newSource: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        // Prevent self-connections and duplicates
        let target = connections[index].targetDeviceId
        guard newSource != target else { return }
        guard !connections.contains(where: {
            $0.id != id &&
            (($0.sourceDeviceId == newSource && $0.targetDeviceId == target) ||
             ($0.sourceDeviceId == target && $0.targetDeviceId == newSource))
        }) else { return }
        connections[index].sourceDeviceId = newSource
        saveTopology()
    }

    func updateConnectionTarget(id: UUID, newTarget: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let source = connections[index].sourceDeviceId
        guard newTarget != source else { return }
        guard !connections.contains(where: {
            $0.id != id &&
            (($0.sourceDeviceId == source && $0.targetDeviceId == newTarget) ||
             ($0.sourceDeviceId == newTarget && $0.targetDeviceId == source))
        }) else { return }
        connections[index].targetDeviceId = newTarget
        saveTopology()
    }

    func reverseConnection(id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let old = connections[index]
        connections[index].sourceDeviceId = old.targetDeviceId
        connections[index].targetDeviceId = old.sourceDeviceId
        saveTopology()
    }

    func autoLayout(devices: [Device], in size: CGSize) {
        let deviceIds = nodes.map { $0.deviceId }
        guard !deviceIds.isEmpty else { return }

        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) * 0.35
        let count = deviceIds.count

        for (index, deviceId) in deviceIds.enumerated() {
            let angle = (2 * Double.pi / Double(count)) * Double(index) - Double.pi / 2
            let x = centerX + radius * cos(angle)
            let y = centerY + radius * sin(angle)
            if let nodeIndex = nodes.firstIndex(where: { $0.deviceId == deviceId }) {
                nodes[nodeIndex].position = CGPointCodable(x: x, y: y)
            }
        }
        saveTopology()
    }

    // MARK: - Position Lookup

    func positionForElement(id: UUID) -> CGPoint? {
        if let node = nodes.first(where: { $0.deviceId == id }) {
            return node.position.cgPoint
        }
        if let container = containers.first(where: { $0.id == id }) {
            return containerCenter(container)
        }
        if let icon = decorativeIcons.first(where: { $0.id == id }) {
            return icon.position.cgPoint
        }
        return nil
    }

    /// Returns the connection point on an element's edge nearest to `towards`.
    /// Snaps to container rect edges, device node circle edges, and icon circle edges.
    func connectionPoint(for id: UUID, towards target: CGPoint) -> CGPoint? {
        if let container = containers.first(where: { $0.id == id }) {
            return edgePoint(of: container, towards: target)
        }
        if let node = nodes.first(where: { $0.deviceId == id }) {
            return circleEdgePoint(center: node.position.cgPoint, radius: 28, towards: target)
        }
        if let icon = decorativeIcons.first(where: { $0.id == id }) {
            return circleEdgePoint(center: icon.position.cgPoint, radius: 24, towards: target)
        }
        return positionForElement(id: id)
    }

    /// Point on a circle edge closest to `towards`.
    func circleEdgePoint(center: CGPoint, radius: CGFloat, towards target: CGPoint) -> CGPoint {
        let dx = target.x - center.x
        let dy = target.y - center.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return CGPoint(x: center.x, y: center.y - radius) }
        return CGPoint(
            x: center.x + (dx / length) * radius,
            y: center.y + (dy / length) * radius
        )
    }

    /// 4 anchor points for a device node circle (top, right, bottom, left).
    func anchorPointsForNode(at position: CGPoint, radius: CGFloat = 28) -> [CGPoint] {
        [
            CGPoint(x: position.x, y: position.y - radius),
            CGPoint(x: position.x + radius, y: position.y),
            CGPoint(x: position.x, y: position.y + radius),
            CGPoint(x: position.x - radius, y: position.y),
        ]
    }

    func containerCenter(_ container: TopologyContainer) -> CGPoint {
        CGPoint(
            x: container.position.cgPoint.x + container.size.cgSize.width / 2,
            y: container.position.cgPoint.y + container.size.cgSize.height / 2
        )
    }

    /// Computes the point on the container edge where a ray from center toward `target` intersects.
    func edgePoint(of container: TopologyContainer, towards target: CGPoint) -> CGPoint {
        let center = containerCenter(container)
        let halfW = container.size.cgSize.width / 2
        let halfH = container.size.cgSize.height / 2

        let dx = target.x - center.x
        let dy = target.y - center.y

        guard dx != 0 || dy != 0 else { return center }

        let scaleX = abs(dx) > 0 ? halfW / abs(dx) : .infinity
        let scaleY = abs(dy) > 0 ? halfH / abs(dy) : .infinity
        let scale = min(scaleX, scaleY)

        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    /// Returns the 8 anchor points for a container (midpoints + corners).
    func anchorPoints(for container: TopologyContainer) -> [CGPoint] {
        let origin = container.position.cgPoint
        let w = container.size.cgSize.width
        let h = container.size.cgSize.height
        return [
            CGPoint(x: origin.x + w / 2, y: origin.y),           // top-center
            CGPoint(x: origin.x + w, y: origin.y),               // top-right
            CGPoint(x: origin.x + w, y: origin.y + h / 2),       // right-center
            CGPoint(x: origin.x + w, y: origin.y + h),           // bottom-right
            CGPoint(x: origin.x + w / 2, y: origin.y + h),       // bottom-center
            CGPoint(x: origin.x, y: origin.y + h),               // bottom-left
            CGPoint(x: origin.x, y: origin.y + h / 2),           // left-center
            CGPoint(x: origin.x, y: origin.y),                   // top-left
        ]
    }

    // MARK: - Container CRUD

    func addContainer(label: String, position: CGPoint, color: String = "blue", icon: String = "rectangle.3.group") {
        let container = TopologyContainer(label: label, position: position, color: color, icon: icon)
        containers.append(container)
        saveTopology()
    }

    func removeContainer(id: UUID) {
        containers.removeAll { $0.id == id }
        connections.removeAll { $0.sourceDeviceId == id || $0.targetDeviceId == id }
        saveTopology()
    }

    func updateContainerPosition(id: UUID, position: CGPoint) {
        if let index = containers.firstIndex(where: { $0.id == id }) {
            containers[index].position = CGPointCodable(position)
            saveTopology()
        }
    }

    func updateContainerSize(id: UUID, size: CGSize) {
        if let index = containers.firstIndex(where: { $0.id == id }) {
            containers[index].size = CGSizeCodable(size)
            saveTopology()
        }
    }

    func updateContainerLabel(id: UUID, label: String) {
        if let index = containers.firstIndex(where: { $0.id == id }) {
            containers[index].label = label
            saveTopology()
        }
    }

    func updateContainerColor(id: UUID, color: String) {
        if let index = containers.firstIndex(where: { $0.id == id }) {
            containers[index].color = color
            saveTopology()
        }
    }

    // MARK: - Decorative Icon CRUD

    func addDecorativeIcon(type: DecorativeIconType, position: CGPoint, label: String = "") {
        let icon = TopologyDecorativeIcon(iconType: type, position: position, label: label)
        decorativeIcons.append(icon)
        saveTopology()
    }

    func removeDecorativeIcon(id: UUID) {
        decorativeIcons.removeAll { $0.id == id }
        connections.removeAll { $0.sourceDeviceId == id || $0.targetDeviceId == id }
        saveTopology()
    }

    func updateDecorativeIconPosition(id: UUID, position: CGPoint) {
        if let index = decorativeIcons.firstIndex(where: { $0.id == id }) {
            decorativeIcons[index].position = CGPointCodable(position)
            saveTopology()
        }
    }

    func updateDecorativeIconLabel(id: UUID, label: String) {
        if let index = decorativeIcons.firstIndex(where: { $0.id == id }) {
            decorativeIcons[index].label = label
            saveTopology()
        }
    }
}
