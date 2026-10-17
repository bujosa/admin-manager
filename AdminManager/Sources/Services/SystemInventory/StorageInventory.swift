import Foundation

struct StorageDevice: Identifiable, Sendable {
    let path: String
    let name: String
    let type: String
    var sizeBytes: UInt64?
    var model: String?
    var transport: String?
    var rotational: Bool?
    var readOnly: Bool?
    var fileSystem: String?
    var label: String?
    var deviceNumber: String?
    var mountPoints: [String]
    var parents: Set<String>

    var id: String { path }
    var isFirmwareRegion: Bool {
        name.hasPrefix("mmcblk") && (name.hasSuffix("boot0") || name.hasSuffix("boot1") || name.hasSuffix("rpmb"))
    }
    var isVirtualDisk: Bool { ["nbd", "vd", "xvd", "rbd"].contains { name.hasPrefix($0) } }
    var isPhysicalDisk: Bool { type == "disk" && !isVirtual && !isVirtualDisk }
    var isVirtual: Bool {
        ["loop", "rom"].contains(type) || name.hasPrefix("zram") || name.hasPrefix("ram") || isFirmwareRegion
            || (name.hasPrefix("nbd") && sizeBytes == 0)
    }
    var mediaLabel: String {
        if isVirtualDisk { return name.hasPrefix("nbd") ? "Network block device" : "Virtual disk" }
        if name.hasPrefix("mmcblk") { return "eMMC / flash" }
        if name.hasPrefix("nvme") || transport == "nvme" { return "NVMe SSD" }
        if rotational == true { return "HDD" }
        if rotational == false { return transport == "usb" ? "USB flash / SSD" : "SSD" }
        return type == "disk" ? "Disk" : type.uppercased()
    }
}

struct StorageVolume: Identifiable, Sendable {
    let source: String
    let mountPoint: String
    let fileSystem: String
    let deviceNumber: String?
    let totalBytes: UInt64?
    let usedBytes: UInt64?
    let availableBytes: UInt64?
    var readOnly: Bool? = nil
    var id: String { "\(source)@\(mountPoint)" }
    var usagePercent: Double? {
        guard let totalBytes, totalBytes > 0, let usedBytes else { return nil }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100)
    }
}

struct SystemResources: Sendable, Decodable {
    var cpuModel: String?
    var logicalCPUs: Int?
    var memoryTotal: UInt64?
    var memoryAvailable: UInt64?
    var swapTotal: UInt64?
    var swapFree: UInt64?
    var uptime: TimeInterval?
    var loadAverage: [Double] = []
    var swapUsed: UInt64? {
        guard let swapTotal, let swapFree else { return nil }
        return swapTotal - min(swapFree, swapTotal)
    }
}

struct StorageInventory: Sendable {
    var capturedAt: Date = Date()
    let devices: [StorageDevice]
    let volumes: [StorageVolume]
    let resources: SystemResources
    let warnings: [String]
    var platform: RemotePlatform = .linux
    var physicalDisks: [StorageDevice] { devices.filter(\.isPhysicalDisk) }
    var physicalCapacity: UInt64? {
        let disks = physicalDisks
        guard !disks.isEmpty, disks.allSatisfy({ $0.sizeBytes != nil }) else { return nil }
        return disks.reduce(UInt64(0)) { total, disk in
            let (sum, overflow) = total.addingReportingOverflow(disk.sizeBytes ?? 0)
            return overflow ? UInt64.max : sum
        }
    }
    func descendants(of path: String) -> [StorageDevice] {
        var visited: Set<String> = [path]
        var result: [StorageDevice] = []
        var pending = [path]
        while let parent = pending.popLast() {
            for device in devices where device.parents.contains(parent) && visited.insert(device.path).inserted {
                result.append(device)
                pending.append(device.path)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    func volumes(for device: StorageDevice) -> [StorageVolume] {
        volumes.filter { volume in
            // Btrfs subvolume mounts may report an anonymous major:minor number.
            // Source paths and lsblk mount points remain authoritative matches.
            if volume.source.components(separatedBy: "[").first == device.path
                || device.mountPoints.contains(volume.mountPoint)
            {
                return true
            }
            if let number = device.deviceNumber, let other = volume.deviceNumber { return number == other }
            return false
        }
    }
    func mountPoints(for disk: StorageDevice) -> [String] {
        Array(
            Set(
                ([disk] + descendants(of: disk.path)).flatMap { device in
                    device.mountPoints + volumes(for: device).map(\.mountPoint)
                })
        ).filter { !$0.isEmpty && $0 != "[SWAP]" }.sorted()
    }
}

enum InventoryError: LocalizedError {
    case unsupported, incomplete, malformed
    var errorDescription: String? {
        switch self {
        case .unsupported:
            return
                "Detailed inventory supports Linux, macOS and Windows over SSH. This system is not supported yet; no disk commands were run."
        case .incomplete: return "The inventory command did not complete. Reconnect and refresh."
        case .malformed: return "The device returned an unreadable inventory. Refresh or check util-linux support."
        }
    }
}

/// Parses fixed, read-only probe sections. Never evaluates device-provided text.
enum StorageInventoryParser {
    static func parse(_ output: String) throws -> StorageInventory {
        guard output.components(separatedBy: .newlines).contains("ADMIN_INVENTORY_V1") else {
            throw InventoryError.incomplete
        }
        if output.components(separatedBy: .newlines).contains("ADMIN_UNSUPPORTED") { throw InventoryError.unsupported }
        guard output.components(separatedBy: .newlines).contains("ADMIN_INVENTORY_END") else {
            throw InventoryError.incomplete
        }
        var warnings: [String] = []
        var devices: [StorageDevice] = []
        if let json = section("BLOCKS", in: output), !json.isEmpty {
            devices = try parseDevices(json)
        } else {
            warnings.append(
                "Physical disk inventory is unavailable. lsblk (util-linux) may be missing or inaccessible; mounted filesystem usage can still be shown."
            )
        }
        var volumes: [StorageVolume] = []
        if let json = section("VOLUMES", in: output), !json.isEmpty {
            volumes = try parseVolumes(json)
        } else {
            warnings.append(
                "Mounted filesystem usage is unavailable. findmnt (util-linux) may be missing or inaccessible. Detected disks remain visible."
            )
        }
        let resources = parseResources(section("RESOURCES", in: output))
        return StorageInventory(devices: devices, volumes: volumes, resources: resources, warnings: warnings)
    }

    static func parseResources(_ section: String?) -> SystemResources {
        var values: [String: String] = [:]
        for line in (section ?? "").components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        return SystemResources(
            cpuModel: cleaned(values["CPU_MODEL"]), logicalCPUs: values["CPU_CORES"].flatMap(Int.init),
            memoryTotal: uint(values["MEM_TOTAL"]), memoryAvailable: uint(values["MEM_AVAILABLE"]),
            swapTotal: uint(values["SWAP_TOTAL"]), swapFree: uint(values["SWAP_FREE"]),
            uptime: values["UPTIME"].flatMap(Double.init),
            loadAverage: (values["LOAD"] ?? "").split(separator: " ").compactMap { Double($0) }
        )
    }

    static func parseDevices(_ json: String) throws -> [StorageDevice] {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["blockdevices"] as? [[String: Any]]
        else { throw InventoryError.malformed }
        var devices: [String: StorageDevice] = [:]
        func walk(_ rows: [[String: Any]], parent: String?) throws {
            for row in rows {
                guard let rawName = cleaned(row["name"]), let type = cleaned(row["type"]) else {
                    throw InventoryError.malformed
                }
                let path = rawName.hasPrefix("/dev/") ? rawName : "/dev/\(rawName)"
                let name = URL(fileURLWithPath: path).lastPathComponent
                var parents: Set<String> = []
                if let parent { parents.insert(parent) }
                if let pk = cleaned(row["pkname"]) { parents.insert(pk.hasPrefix("/dev/") ? pk : "/dev/\(pk)") }
                let mountPoints =
                    (row["mountpoints"] as? [Any] ?? []).compactMap(cleaned)
                    + [cleaned(row["mountpoint"])].compactMap { $0 }
                var device =
                    devices[path]
                    ?? StorageDevice(
                        path: path, name: name, type: type, sizeBytes: uint(row["size"]),
                        model: cleaned(row["model"]), transport: cleaned(row["tran"]), rotational: bool(row["rota"]),
                        readOnly: bool(row["ro"]), fileSystem: cleaned(row["fstype"]), label: cleaned(row["label"]),
                        deviceNumber: cleaned(row["maj:min"]), mountPoints: [], parents: []
                    )
                device.parents.formUnion(parents)
                device.mountPoints = Array(Set(device.mountPoints + mountPoints)).sorted()
                devices[path] = device
                if let children = row["children"] as? [[String: Any]] { try walk(children, parent: path) }
            }
        }
        try walk(rows, parent: nil)
        return devices.values.filter { !$0.isVirtual }.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func parseVolumes(_ json: String) throws -> [StorageVolume] {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["filesystems"] as? [[String: Any]]
        else { throw InventoryError.malformed }
        var volumes: [String: StorageVolume] = [:]
        func walk(_ rows: [[String: Any]]) {
            for row in rows {
                if let source = cleaned(row["source"]), let target = cleaned(row["target"]) {
                    let fs = cleaned(row["fstype"]) ?? "Unknown"
                    if !["overlay", "tmpfs", "devtmpfs", "squashfs", "proc", "sysfs", "cgroup", "cgroup2", "ramfs"]
                        .contains(fs)
                    {
                        let volume = StorageVolume(
                            source: source, mountPoint: target, fileSystem: fs, deviceNumber: cleaned(row["maj:min"]),
                            totalBytes: uint(row["size"]), usedBytes: uint(row["used"]),
                            availableBytes: uint(row["avail"]),
                            readOnly: (row["options"] as? String).map { $0.split(separator: ",").contains("ro") })
                        volumes[volume.id] = volume
                    }
                }
                if let children = row["children"] as? [[String: Any]] { walk(children) }
            }
        }
        walk(rows)
        return volumes.values.sorted { $0.mountPoint.localizedStandardCompare($1.mountPoint) == .orderedAscending }
    }

    static func section(_ name: String, in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "ADMIN_\(name)_BEGIN"),
            let end = lines[(start + 1)...].firstIndex(of: "ADMIN_\(name)_END")
        else { return nil }
        return lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func cleaned(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    static func uint(_ value: Any?) -> UInt64? {
        if let value = value as? String { return UInt64(value) }
        if let value = value as? NSNumber { return UInt64(value.stringValue) }
        return nil
    }
    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "1", "true": return true
            case "0", "false": return false
            default: return nil
            }
        }
        return nil
    }
}

/// Read-only OS images (for example a ZimaOS root filesystem) can be 100% used
/// by design; they must not be treated as writable storage pressure.
enum StoragePressure {
    static func isHigh(used: UInt64, total: UInt64, readOnly: Bool) -> Bool {
        guard !readOnly, total > 0 else { return false }
        return Double(used) / Double(total) >= 0.85
    }
}
