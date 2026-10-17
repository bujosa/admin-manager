import SwiftUI

struct StorageView: View {
    let device: Device
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService

    private var inventory: StorageInventory? { adminService.storageInventoryCache[device.id] }
    private var isLoading: Bool { adminService.isLoadingStorage[device.id] ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingLarge) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage & resources").font(.title2.bold())
                    Text("Disks, mounted filesystems and system resources")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button {
                    refresh()
                } label: {
                    Label("Refresh Storage", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || !sshService.isConnected(deviceId: device.id))
            }
            Label(
                inventory?.platform.displayName ?? sshService.remotePlatforms[device.id]?.displayName
                    ?? "Detecting operating system", systemImage: "desktopcomputer"
            )
            .font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
            if inventory?.platform == .macOS {
                Text("APFS volumes share container space. Available space can repeat across mounts.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            } else if inventory?.platform == .windows {
                Text(
                    "OS-visible disks. Hardware RAID and Storage Spaces members are not counted as separate physical drives."
                )
                .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let error = adminService.storageError[device.id] {
                notice(error + (inventory == nil ? "" : " Showing the previous snapshot below."), color: .orange)
            }
            if let inventory {
                content(inventory)
            } else if isLoading {
                HStack {
                    ProgressView()
                    Text("Reading disks and resources…").foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if adminService.storageError[device.id] == nil {
                ContentUnavailableView(
                    "No inventory yet", systemImage: "externaldrive",
                    description: Text("Refresh to detect Linux, macOS or Windows and read its storage inventory."))
            }
        }
        .padding(.horizontal, Theme.paddingLarge)
        .task(id: device.id) {
            await adminService.fetchStorage(for: device.id, sshService: sshService)
        }
    }

    private func content(_ inventory: StorageInventory) -> some View {
        VStack(alignment: .leading, spacing: Theme.paddingLarge) {
            ForEach(inventory.warnings, id: \.self) { warning in notice(warning, color: .orange) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: Theme.paddingMedium) {
                summary(
                    "Physical drives", value: "\(inventory.physicalDisks.count)", detail: "HDD, SSD, NVMe and flash",
                    icon: "externaldrive.fill")
                summary(
                    "Raw capacity", value: bytes(inventory.physicalCapacity),
                    detail: "Physical drives only · not usable RAID space", icon: "internaldrive")
                summary(
                    "Mounted filesystems", value: "\(inventory.volumes.count)",
                    detail: "Mounts can share the same capacity", icon: "folder.fill")
            }
            if inventory.physicalDisks.isEmpty && inventory.warnings.isEmpty {
                notice(
                    "No physical drives were returned. A VM, container or restricted account may expose only virtual storage.",
                    color: .orange)
            }
            ForEach(inventory.physicalDisks) { disk in diskCard(disk, inventory: inventory) }
            let physicalPaths = Set(
                inventory.physicalDisks.flatMap { [$0.path] + inventory.descendants(of: $0.path).map(\.path) })
            let otherDevices = inventory.devices.filter { !physicalPaths.contains($0.path) }
            let otherPaths = Set(otherDevices.map(\.path))
            let logicalRoots = otherDevices.filter { $0.parents.isDisjoint(with: otherPaths) }
            if !logicalRoots.isEmpty {
                Text("Virtual & logical storage").font(.headline)
                ForEach(logicalRoots) { disk in diskCard(disk, inventory: inventory) }
            }
            let shownPaths = physicalPaths.union(
                logicalRoots.flatMap { [$0.path] + inventory.descendants(of: $0.path).map(\.path) })
            let linkedIDs = Set(
                inventory.devices.filter { shownPaths.contains($0.path) }.flatMap {
                    inventory.volumes(for: $0).map(\.id)
                })
            let otherVolumes = inventory.volumes.filter { !linkedIDs.contains($0.id) }
            if !otherVolumes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Other mounted filesystems").font(.headline)
                    Text("Network shares and filesystems without a matching physical device.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    ForEach(otherVolumes) { volume in volumeRow(volume) }
                }.padding(Theme.paddingMedium).cardStyle()
            }
            resourceSection(inventory.resources, platform: inventory.platform)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(
                    "Last read \(inventory.capturedAt.formatted(date: .omitted, time: .standard)) · Refresh after adding a drive"
                )
            }.font(.caption).foregroundStyle(Theme.secondaryText)
            Text(
                "Read-only inventory. No mounting, formatting or disk changes. SMART health is not collected; an unmounted drive may still be healthy."
            )
            .font(.caption).foregroundStyle(Theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func diskCard(_ disk: StorageDevice, inventory: StorageInventory) -> some View {
        let children = inventory.descendants(of: disk.path)
        let mounts = inventory.mountPoints(for: disk)
        let nodes = [disk] + children
        let volumes = Dictionary(grouping: nodes.flatMap { inventory.volumes(for: $0) }, by: \.id).values.compactMap(
            \.first
        ).sorted { $0.mountPoint < $1.mountPoint }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: disk.rotational == true ? "externaldrive" : "internaldrive")
                    .font(.title2).foregroundStyle(Theme.accent).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(disk.model ?? disk.name).font(.headline).textSelection(.enabled)
                    Text(disk.path).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        tag(disk.mediaLabel, color: .blue)
                        if let transport = disk.transport { tag(transport.uppercased(), color: .secondary) }
                        if disk.readOnly == true { tag("Read-only", color: .orange) }
                        tag(mounts.isEmpty ? "Not mounted" : "Mounted", color: mounts.isEmpty ? .orange : .green)
                    }
                }
                Spacer(minLength: 8)
                Text(bytes(disk.sizeBytes)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            if mounts.isEmpty {
                Text(
                    nodes.contains(where: { $0.fileSystem == "swap" })
                        ? "Used as swap; no mounted filesystem usage."
                        : "Detected by the operating system. No mounted filesystem usage is available for this drive."
                )
                .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let primary = volumes.max(by: { ($0.totalBytes ?? 0) < ($1.totalBytes ?? 0) }) {
                volumeRow(primary)
            }
            if !children.isEmpty || volumes.count > 1 {
                DisclosureGroup("Partitions & mounts · \(children.count) devices · \(volumes.count) mounts") {
                    if !children.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Partitions & logical devices").font(.caption.weight(.semibold)).foregroundStyle(
                                Theme.secondaryText)
                            ForEach(children) { child in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.tertiaryText)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(child.path).font(.system(.caption, design: .monospaced)).textSelection(
                                            .enabled)
                                        Text(
                                            [child.type, child.fileSystem, child.label].compactMap { $0 }.joined(
                                                separator: " · ")
                                        )
                                        .font(.caption2).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                                    }
                                    Spacer()
                                    Text(bytes(child.sizeBytes)).font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    ForEach(volumes) { volume in volumeRow(volume) }
                }
                .font(.caption)
            }
            if nodes.contains(where: { $0.parents.count > 1 }) {
                Text(
                    "A shared RAID/logical device also belongs to another physical drive. Its capacity is not added to raw capacity."
                )
                .font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(Theme.paddingMedium).cardStyle()
    }

    private func volumeRow(_ volume: StorageVolume) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(volume.mountPoint).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                    Text("\(volume.fileSystem) · \(volume.source)").font(.caption2).foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                }
                Spacer()
                if let percent = volume.usagePercent {
                    Text(String(format: "%.1f%% used", percent) + (volume.readOnly == true ? " · Read-only" : ""))
                        .font(.caption.weight(.medium)).foregroundStyle(
                            volume.readOnly == true ? .gray : percent >= 85 ? .orange : Theme.secondaryText)
                }
            }
            if let percent = volume.usagePercent {
                ProgressView(value: percent, total: 100).tint(
                    volume.readOnly == true ? .gray : percent >= 85 ? .orange : Theme.accent
                )
                .accessibilityLabel("\(volume.mountPoint) storage used")
                Text(
                    "\(bytes(volume.usedBytes)) used · \(bytes(volume.availableBytes)) available · \(bytes(volume.totalBytes)) total"
                )
                .font(.caption).foregroundStyle(Theme.secondaryText)
            } else {
                Text("Usage unavailable").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }.padding(12).background(Theme.tertiaryBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resourceSection(_ resources: SystemResources, platform: RemotePlatform) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System resources").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: Theme.paddingMedium) {
                summary(
                    "Processor", value: resources.cpuModel ?? "Unavailable",
                    detail: resources.logicalCPUs.map { "\($0) logical CPUs" } ?? "Core count unavailable", icon: "cpu")
                summary(
                    platform == .macOS ? "RAM available (estimate)" : "RAM available",
                    value: bytes(resources.memoryAvailable),
                    detail: "\(bytes(resources.memoryTotal)) total · "
                        + (platform == .macOS
                            ? "free, inactive & speculative pages"
                            : platform == .windows ? "OS-reported free physical memory" : "includes reclaimable cache"),
                    icon: "memorychip"
                )
                summary(
                    platform == .windows ? "Page file" : "Swap",
                    value: resources.swapTotal == 0 ? "Not configured" : "\(bytes(resources.swapUsed)) used",
                    detail: "\(bytes(resources.swapTotal)) total", icon: "arrow.left.arrow.right")
                summary(
                    "Load average",
                    value: resources.loadAverage.isEmpty
                        ? "Unavailable"
                        : resources.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " / "),
                    detail: platform == .windows
                        ? "Windows does not report Unix load averages"
                        : "1 / 5 / 15 minutes · compare with logical CPUs", icon: "chart.line.uptrend.xyaxis")
            }
        }
    }
    private func summary(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(value).font(.headline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption2).foregroundStyle(Theme.tertiaryText).fixedSize(
                horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).padding(Theme.paddingMedium).cardStyle()
    }
    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
    private func notice(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    private func bytes(_ value: UInt64?) -> String {
        guard let value else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
    private func refresh() {
        Task { await adminService.fetchStorage(for: device.id, sshService: sshService) }
    }
}
