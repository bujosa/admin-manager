import Foundation

enum MacBatteryPower {
    /// IOKit may expose a negative mA value as an unsigned two's-complement integer.
    static func watts(amperage: String, millivolts: String) -> Double? {
        let raw = amperage.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Int64(raw) ?? UInt64(raw).map { Int64(bitPattern: $0) }
        guard let current, let voltage = UInt64(millivolts.trimmingCharacters(in: .whitespacesAndNewlines)), voltage > 0
        else { return nil }
        let watts = abs(Double(current)) * Double(voltage) / 1_000_000
        guard watts.isFinite, watts > 0, watts <= 2_000 else { return nil }
        return watts
    }
}

enum MacInventoryProbe {
    static let script = #"""
        export LC_ALL=C
        printf 'ADMIN_MAC_V1\nADMIN_MAC_LIST_BEGIN\n'
        LIST=$(diskutil list -plist 2>/dev/null)
        printf '%s\n' "$LIST"
        printf 'ADMIN_MAC_LIST_END\nADMIN_MAC_PHYSICAL_BEGIN\n'
        diskutil list -plist physical 2>/dev/null
        printf '\nADMIN_MAC_PHYSICAL_END\nADMIN_MAC_APFS_BEGIN\n'
        diskutil apfs list -plist 2>/dev/null
        printf '\nADMIN_MAC_APFS_END\n'
        # Extract only disk identifiers; never interpolate volume names or paths.
        IDS=$(printf '%s\n' "$LIST" | plutil -extract AllDisks xml1 -o - - 2>/dev/null |
          sed -nE 's/^[[:space:]]*<string>(disk[0-9]+(s[0-9]+)*)<\/string>[[:space:]]*$/\1/p' | sort -u)
        for disk in $IDS; do
          printf 'ADMIN_MAC_INFO_BEGIN\n'
          diskutil info -plist "$disk" 2>/dev/null
          printf '\nADMIN_MAC_INFO_END\n'
        done
        printf 'ADMIN_RESOURCES_BEGIN\n'
        printf 'CPU_MODEL=%s\n' "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
        printf 'CPU_CORES=%s\n' "$(sysctl -n hw.logicalcpu 2>/dev/null)"
        printf 'MEM_TOTAL=%s\n' "$(sysctl -n hw.memsize 2>/dev/null)"
        vm_stat 2>/dev/null | awk '
          /page size of/ {for(i=1;i<=NF;i++)if($i=="of")page=$(i+1)}
          /^Pages free:|^Pages inactive:|^Pages speculative:/ {gsub(/\./,"",$NF);available+=$NF}
          END {if(page>0)printf "MEM_AVAILABLE=%.0f\n",available*page}'
        sysctl -n vm.swapusage 2>/dev/null | awk '
          function bytes(value) {unit=substr(value,length(value));n=value+0;return n*(unit=="G"?1073741824:unit=="M"?1048576:unit=="K"?1024:1)}
          {for(i=1;i<=NF;i++){if($i=="total")printf "SWAP_TOTAL=%.0f\n",bytes($(i+2));if($i=="free")printf "SWAP_FREE=%.0f\n",bytes($(i+2))}}'
        sysctl -n vm.loadavg 2>/dev/null | awk '{printf "LOAD=%s %s %s\n",$2,$3,$4}'
        BOOT=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[= ,]+' '{for(i=1;i<=NF;i++)if($i=="sec"){print $(i+1);exit}}')
        if [ -n "$BOOT" ]; then printf 'UPTIME=%s\n' "$(( $(date +%s) - BOOT ))"; fi
        printf 'ADMIN_RESOURCES_END\nADMIN_MAC_END\n'
        """#
}

enum MacInventoryParser {
    static func parse(_ output: String) throws -> StorageInventory {
        let lines = output.components(separatedBy: .newlines)
        guard lines.contains("ADMIN_MAC_V1"), lines.contains("ADMIN_MAC_END") else { throw InventoryError.incomplete }
        let listing = try plist(StorageInventoryParser.section("MAC_LIST", in: output))
        guard let roots = listing["AllDisksAndPartitions"] as? [[String: Any]] else { throw InventoryError.malformed }
        var warnings: [String] = []
        let physicalListing = try? plist(StorageInventoryParser.section("MAC_PHYSICAL", in: output))
        let physicalIDs = Set((physicalListing?["WholeDisks"] as? [String]) ?? [])
        if physicalListing == nil {
            warnings.append(
                "Physical disk classification is unavailable; disks are listed as logical to avoid overstating physical capacity."
            )
        }
        var devices: [String: StorageDevice] = [:]
        var infoByID: [String: [String: Any]] = [:]
        var block: [String]? = nil
        for line in lines {
            if line == "ADMIN_MAC_INFO_BEGIN" {
                block = []
                continue
            }
            if line == "ADMIN_MAC_INFO_END", let content = block {
                if let info = try? plist(content.joined(separator: "\n")), let id = info["DeviceIdentifier"] as? String
                {
                    infoByID[id] = info
                }
                block = nil
            } else if block != nil {
                block?.append(line)
            }
        }
        func add(_ row: [String: Any], parent: String?, whole: Bool) throws {
            guard let id = row["DeviceIdentifier"] as? String, validIdentifier(id) else {
                throw InventoryError.malformed
            }
            let info = infoByID[id] ?? row
            let path = "/dev/\(id)"
            let mounted =
                StorageInventoryParser.cleaned(info["MountPoint"]) ?? StorageInventoryParser.cleaned(row["MountPoint"])
            let solid = info["SolidState"] as? Bool
            var parents: Set<String> = parent.map { ["/dev/\($0)"] } ?? []
            if let existing = devices[path] { parents.formUnion(existing.parents) }
            devices[path] = StorageDevice(
                path: path, name: id, type: whole ? (physicalIDs.contains(id) ? "disk" : "virtual") : "part",
                sizeBytes: StorageInventoryParser.uint(info["TotalSize"]) ?? StorageInventoryParser.uint(row["Size"]),
                model: StorageInventoryParser.cleaned(info["MediaName"]),
                transport: StorageInventoryParser.cleaned(info["BusProtocol"]),
                rotational: solid.map { !$0 }, readOnly: (info["WritableMedia"] as? Bool).map { !$0 },
                fileSystem: StorageInventoryParser.cleaned(info["FilesystemType"]),
                label: StorageInventoryParser.cleaned(info["VolumeName"]),
                mountPoints: mounted.map { [$0] } ?? [], parents: parents)
            for child in (row["Partitions"] as? [[String: Any]] ?? []) + (row["APFSVolumes"] as? [[String: Any]] ?? [])
            {
                try add(child, parent: id, whole: false)
            }
        }
        for row in roots { try add(row, parent: nil, whole: true) }
        // APFS synthesized containers link to their physical stores, including Fusion drives.
        var containersByVolume: [String: [String: Any]] = [:]
        if let apfs = try? plist(StorageInventoryParser.section("MAC_APFS", in: output)) {
            for container in apfs["Containers"] as? [[String: Any]] ?? [] {
                if let id = container["ContainerReference"] as? String {
                    let path = "/dev/\(id)"
                    let stores = (container["PhysicalStores"] as? [[String: Any]] ?? []).compactMap {
                        $0["DeviceIdentifier"] as? String
                    }
                    devices[path]?.parents.formUnion(stores.filter(validIdentifier).map { "/dev/\($0)" })
                }
                for volume in container["Volumes"] as? [[String: Any]] ?? [] {
                    if let id = volume["DeviceIdentifier"] as? String { containersByVolume[id] = container }
                }
            }
        } else if roots.contains(where: { ($0["Content"] as? String) == "Apple_APFS" }) {
            warnings.append("APFS physical-store relationships are unavailable. Logical volumes may appear separately.")
        }
        let missingInfo = devices.values.filter { infoByID[$0.name] == nil }.count
        if missingInfo > 0 {
            warnings.append("Some disk details could not be read. Mount and usage measurements may be unavailable.")
        }
        var volumes: [StorageVolume] = []
        for device in devices.values {
            guard let mount = device.mountPoints.first, let info = infoByID[device.name] else { continue }
            let apfs = containersByVolume[device.name]
            let total = StorageInventoryParser.uint(apfs?["CapacityCeiling"] ?? info["VolumeSize"] ?? info["TotalSize"])
            let available = StorageInventoryParser.uint(apfs?["CapacityFree"] ?? info["FreeSpace"])
            let used =
                StorageInventoryParser.uint(info["CapacityInUse"])
                ?? total.flatMap { total in available.map { total - min(total, $0) } }
            volumes.append(
                StorageVolume(
                    source: device.path, mountPoint: mount, fileSystem: device.fileSystem ?? "Unknown",
                    deviceNumber: nil, totalBytes: total, usedBytes: used, availableBytes: available,
                    readOnly: ((info["WritableVolume"] ?? info["WritableMedia"]) as? Bool).map { !$0 }))
        }
        return StorageInventory(
            devices: devices.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            volumes: volumes.sorted { $0.mountPoint < $1.mountPoint },
            resources: StorageInventoryParser.parseResources(StorageInventoryParser.section("RESOURCES", in: output)),
            warnings: warnings, platform: .macOS)
    }

    private static func plist(_ text: String?) throws -> [String: Any] {
        guard let text, let data = text.data(using: .utf8),
            let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw InventoryError.malformed }
        return root
    }

    private static func validIdentifier(_ value: String) -> Bool {
        value.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil
    }
}
