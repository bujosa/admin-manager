import Foundation

enum WindowsInventoryProbe {
    static var command: String { PowerShellCommand.encode(script) }

    static let script = #"""
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $warnings = @()
        $disks = @(); $partitions = @(); $volumes = @()
        $physical = @(); $partitionObjects = @()
        try { $physical = @(Get-PhysicalDisk) } catch { }
        try {
          $disks = @(Get-Disk | ForEach-Object {
            $d = $_
            $media = @($physical | Where-Object { $_.UniqueId -and $_.UniqueId -eq $d.UniqueId } | Select-Object -First 1)
            [ordered]@{number=[int]$d.Number;size=$d.Size;model=$d.FriendlyName;bus=[string]$d.BusType;readOnly=$d.IsReadOnly;media=$(if($media.Count){[string]$media[0].MediaType}else{$null})}
          })
        } catch {
          $warnings += 'Basic CIM disk inventory is in use; storage-module details may be unavailable.'
          try {
            $disks = @(Get-CimInstance Win32_DiskDrive | ForEach-Object {
              [ordered]@{number=[int]$_.Index;size=$_.Size;model=$_.Model;bus=[string]$_.InterfaceType;readOnly=$null;media=$null}
            })
          } catch { $warnings += 'Disk inventory is unavailable. Check Storage module/CIM permissions.' }
        }
        try {
          $partitionObjects = @(Get-Partition)
          $partitions = @($partitionObjects | ForEach-Object {
            [ordered]@{disk=[int]$_.DiskNumber;number=[int]$_.PartitionNumber;size=$_.Size;paths=@($_.AccessPaths | Where-Object { $_ -and -not $_.StartsWith('\\?\Volume',[StringComparison]::OrdinalIgnoreCase) })}
          })
        } catch { $warnings += 'Partition relationships are unavailable. Volumes may appear separately.' }
        try {
          $volumes = @(Get-Volume | ForEach-Object {
            $v = $_
            $p = @($partitionObjects | Where-Object { $v.Path -and @($_.AccessPaths) -contains $v.Path })
            $paths = @($p | ForEach-Object { $_.AccessPaths } | Where-Object { $_ -and -not $_.StartsWith('\\?\Volume',[StringComparison]::OrdinalIgnoreCase) } | Select-Object -Unique)
            if (-not $paths.Count -and $v.DriveLetter) { $paths = @(([string]$v.DriveLetter) + ':\') }
            if ($paths.Count) {
              [ordered]@{disk=$(if($p.Count -eq 1){[int]$p[0].DiskNumber}else{$null});partition=$(if($p.Count -eq 1){[int]$p[0].PartitionNumber}else{$null});paths=@($paths);fileSystem=[string]$v.FileSystemType;size=$v.Size;available=$v.SizeRemaining;readOnly=$(if($p.Count -eq 1 -and $null -ne $p[0].IsReadOnly){[bool]$p[0].IsReadOnly}else{$null})}
            }
          })
        } catch {
          $warnings += 'Basic drive-letter usage is in use; folder-mounted volumes may be unavailable.'
          try {
            $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
              [ordered]@{disk=$null;partition=$null;paths=@($_.DeviceID+'\');fileSystem=$_.FileSystem;size=$_.Size;available=$_.FreeSpace}
            })
          } catch { $warnings += 'Mounted volume usage is unavailable. Check Storage module/CIM permissions.' }
        }
        $resources = [ordered]@{cpuModel=$null;logicalCPUs=$null;memoryTotal=$null;memoryAvailable=$null;swapTotal=$null;swapFree=$null;uptime=$null;loadAverage=@()}
        try {
          $os = Get-CimInstance Win32_OperatingSystem
          $cpu = @(Get-CimInstance Win32_Processor)
          $resources.cpuModel = ($cpu | Select-Object -First 1).Name
          $resources.logicalCPUs = [int](($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
          $resources.memoryTotal = [uint64]$os.TotalVisibleMemorySize * 1024
          $resources.memoryAvailable = [uint64]$os.FreePhysicalMemory * 1024
          $resources.uptime = [math]::Max(0, ((Get-Date)-$os.LastBootUpTime).TotalSeconds)
        } catch { $warnings += 'Some CPU/RAM information could not be read through CIM.' }
        try {
          $pages = @(Get-CimInstance Win32_PageFileUsage)
          $resources.swapTotal = [uint64](($pages | Measure-Object AllocatedBaseSize -Sum).Sum) * 1048576
          $used = [uint64](($pages | Measure-Object CurrentUsage -Sum).Sum) * 1048576
          $resources.swapFree = $resources.swapTotal - [math]::Min($used,$resources.swapTotal)
        } catch { $warnings += 'Page-file usage is unavailable.' }
        $result = [ordered]@{version=1;disks=@($disks);partitions=@($partitions);volumes=@($volumes);resources=$resources;warnings=@($warnings)}
        Write-Output 'ADMIN_WINDOWS_V1'
        $result | ConvertTo-Json -Depth 7 -Compress
        Write-Output 'ADMIN_WINDOWS_END'
        """#
}

enum WindowsInventoryParser {
    private struct Response: Decodable {
        let version: Int
        let disks: [Disk]
        let partitions: [Partition]
        let volumes: [Volume]
        let resources: SystemResources
        let warnings: [String]
    }
    private struct Disk: Decodable {
        let number: Int
        let size: UInt64?
        let model: String?
        let bus: String?
        let readOnly: Bool?
        let media: String?
    }
    private struct Partition: Decodable {
        let disk: Int
        let number: Int
        let size: UInt64?
        let paths: [String]
    }
    private struct Volume: Decodable {
        let disk: Int?
        let partition: Int?
        let paths: [String]
        let fileSystem: String?
        let size: UInt64?
        let available: UInt64?
        let readOnly: Bool?
    }
    static func parse(_ output: String) throws -> StorageInventory {
        let lines = output.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "ADMIN_WINDOWS_V1"),
            let end = lines[(start + 1)...].firstIndex(of: "ADMIN_WINDOWS_END")
        else { throw InventoryError.incomplete }
        let data = Data(lines[(start + 1)..<end].joined(separator: "\n").utf8)
        guard let result = try? JSONDecoder().decode(Response.self, from: data), result.version == 1 else {
            throw InventoryError.malformed
        }
        var devices: [String: StorageDevice] = [:]
        for disk in result.disks {
            guard disk.number >= 0 else { throw InventoryError.malformed }
            let path = "Disk \(disk.number)"
            let bus = disk.bus?.lowercased() ?? ""
            let virtual = [
                "virtual", "file backed virtual", "filebackedvirtual", "storage spaces", "spaces", "iscsi", "raid",
            ].contains(bus)
            devices[path] = StorageDevice(
                path: path, name: path, type: virtual ? "virtual" : "disk", sizeBytes: disk.size, model: disk.model,
                transport: bus.isEmpty ? nil : bus,
                rotational: disk.media == "HDD" ? true : disk.media == "SSD" ? false : nil, readOnly: disk.readOnly,
                mountPoints: [], parents: [])
        }
        for part in result.partitions {
            guard part.disk >= 0, part.number >= 0 else { throw InventoryError.malformed }
            let path = "Disk \(part.disk) / Partition \(part.number)"
            devices[path] = StorageDevice(
                path: path, name: "Partition \(part.number)", type: "part", sizeBytes: part.size,
                mountPoints: part.paths, parents: ["Disk \(part.disk)"])
        }
        var volumes: [String: StorageVolume] = [:]
        for volume in result.volumes {
            let source: String
            if let disk = volume.disk, let part = volume.partition {
                guard disk >= 0, part >= 0 else { throw InventoryError.malformed }
                source = "Disk \(disk) / Partition \(part)"
            } else {
                source = volume.paths.first ?? "Volume"
            }
            let used = volume.size.flatMap { total in volume.available.map { total - min(total, $0) } }
            for mount in volume.paths where !mount.isEmpty {
                let item = StorageVolume(
                    source: source, mountPoint: mount, fileSystem: volume.fileSystem ?? "Unknown", deviceNumber: nil,
                    totalBytes: volume.size, usedBytes: used, availableBytes: volume.available,
                    readOnly: volume.readOnly)
                volumes[item.id] = item
                if var device = devices[source] {
                    device.mountPoints = Array(Set(device.mountPoints + [mount])).sorted()
                    devices[source] = device
                }
            }
        }
        return StorageInventory(
            devices: devices.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            volumes: volumes.values.sorted { $0.mountPoint < $1.mountPoint }, resources: result.resources,
            warnings: result.warnings, platform: .windows)
    }
}
