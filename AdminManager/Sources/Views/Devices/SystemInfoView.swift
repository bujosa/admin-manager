import SwiftUI

struct SystemInfoView: View {
    let device: Device

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService

    private var info: DeviceSystemInfo? {
        adminService.systemInfoCache[device.id]
    }

    private var isLoading: Bool {
        adminService.isLoadingSystemInfo[device.id] ?? false
    }

    var body: some View {
        VStack(spacing: Theme.paddingMedium) {
            sectionHeader
                .padding(.horizontal, Theme.paddingLarge)

            if let error = adminService.systemInfoError[device.id] {
                errorBanner(error)
                    .padding(.horizontal, Theme.paddingLarge)
            }

            if isLoading && info == nil {
                loadingState
            } else if let info = info {
                infoContent(info)
                    .padding(.horizontal, Theme.paddingLarge)
            } else {
                emptyState
            }
        }
        .onAppear {
            if info == nil {
                Task { await adminService.fetchSystemInfo(for: device.id, sshService: sshService) }
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("System Information")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(device.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Button {
                Task { await adminService.fetchSystemInfo(for: device.id, sshService: sshService) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    // MARK: - Content

    private func infoContent(_ info: DeviceSystemInfo) -> some View {
        VStack(spacing: Theme.paddingMedium) {
            // Device identity card
            HStack(spacing: Theme.paddingLarge) {
                DeviceIconView(category: device.category, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.hostname)
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(info.osName)
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)

                    HStack(spacing: Theme.paddingSmall) {
                        Text(info.architecture)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text("Kernel \(info.kernelVersion)")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }

                Spacer()
            }
            .padding(Theme.paddingMedium)
            .cardStyle()

            // Hardware info
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.paddingMedium),
                GridItem(.flexible(), spacing: Theme.paddingMedium)
            ], spacing: Theme.paddingMedium) {
                InfoCard(icon: "cpu", label: "CPU", value: info.cpuModel, detail: "\(info.cpuCores) cores")
                InfoCard(icon: "memorychip", label: "Memory", value: info.memoryTotal, detail: "Total RAM")
                InfoCard(icon: "internaldrive", label: "System Volume", value: "\(info.diskUsed) / \(info.diskTotal)", detail: "Used / total · all disks in Storage")
                InfoCard(icon: "clock", label: "Uptime", value: info.uptimeFormatted, detail: "Since last boot")
                InfoCard(icon: "terminal", label: "Shell", value: info.shellVersion.isEmpty ? "Unknown" : String(info.shellVersion.prefix(40)), detail: "Default shell")
                InfoCard(icon: "network", label: "IP Addresses", value: info.ipAddresses.first ?? "N/A", detail: info.ipAddresses.count > 1 ? "+\(info.ipAddresses.count - 1) more" : "Primary")
            }

            // All IP addresses
            if info.ipAddresses.count > 1 {
                VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                    Text("Network Interfaces")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.secondaryText)

                    ForEach(info.ipAddresses, id: \.self) { ip in
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(Theme.success)

                            Text(ip)
                                .font(.system(.caption, design: .monospaced))

                            Spacer()
                        }
                    }
                }
                .padding(Theme.paddingMedium)
                .cardStyle()
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.paddingMedium) {
            ProgressView()
            Text("Fetching system info...")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "info.circle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.tertiaryText)

            Text("No system information available")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Button {
                Task { await adminService.fetchSystemInfo(for: device.id, sshService: sshService) }
            } label: {
                Label("Fetch Info", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.paddingSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(Theme.paddingMedium)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Info Card

private struct InfoCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.paddingMedium) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)

                Text(value)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}
