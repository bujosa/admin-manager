import SwiftUI

struct DeviceListView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor
    @Environment(TabManager.self) private var tabManager

    @State private var searchText = ""
    @State private var selectedCategory: DeviceCategory?
    @State private var showAddDevice = false
    @State private var selectedDevice: Device?
    @State private var deviceToEdit: Device?

    var filteredDevices: [Device] {
        var devices = sshService.devices

        if let category = selectedCategory {
            devices = devices.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            devices = devices.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.hostname.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText)
            }
        }

        return devices.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("\(sshService.devices.count) devices registered")
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                Button {
                    showAddDevice = true
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(Theme.paddingLarge)

            // Filters
            HStack(spacing: Theme.paddingMedium) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.secondaryText)

                    TextField("Search devices...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(Theme.paddingSmall)
                .background(Theme.tertiaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as DeviceCategory?)
                    ForEach(DeviceCategory.allCases, id: \.self) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category as DeviceCategory?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            .padding(.horizontal, Theme.paddingLarge)
            .padding(.bottom, Theme.paddingMedium)

            Divider()
                .background(Theme.divider)

            // Device List
            if filteredDevices.isEmpty {
                VStack(spacing: Theme.paddingMedium) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.tertiaryText)

                    Text("No devices found")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)

                    if sshService.devices.isEmpty {
                        Button("Add your first device") {
                            showAddDevice = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedDevice) {
                    ForEach(filteredDevices) { device in
                        DeviceRow(
                            device: device,
                            isConnected: sshService.isConnected(deviceId: device.id),
                            metrics: monitor.getLatestMetrics(for: device.id)
                        )
                        .tag(device)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NotificationCenter.default.post(name: .showDeviceDetail, object: device.id)
                        }
                        .contextMenu {
                            deviceContextMenu(for: device)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showAddDevice) {
            AddDeviceSheet()
        }
        .sheet(item: $deviceToEdit) { device in
            EditDeviceSheet(device: device)
        }
    }

    @ViewBuilder
    private func deviceContextMenu(for device: Device) -> some View {
        if sshService.isConnected(deviceId: device.id) {
            Button {
                _ = tabManager.createTab(for: device)
            } label: {
                Label("Open Terminal", systemImage: "terminal")
            }

            Button {
                Task {
                    await sshService.disconnect(from: device.id)
                }
            } label: {
                Label("Disconnect", systemImage: "wifi.slash")
            }
        } else {
            Button {
                // Show password dialog
            } label: {
                Label("Connect", systemImage: "wifi")
            }
        }

        Divider()

        Button {
            deviceToEdit = device
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button(role: .destructive) {
            sshService.deleteDevice(device)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct DeviceRow: View {
    let device: Device
    let isConnected: Bool
    let metrics: SystemMetrics?

    var body: some View {
        HStack(spacing: Theme.paddingMedium) {
            // Status indicator
            Circle()
                .fill(isConnected ? Theme.success : Theme.tertiaryText)
                .frame(width: 8, height: 8)

            // Icon
            DeviceIconView(category: device.category, size: 32)
                .frame(width: 40)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)

                HStack(spacing: Theme.paddingSmall) {
                    Text(device.connectionString)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    Text("•")
                        .foregroundStyle(Theme.tertiaryText)

                    Text(device.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer()

            // Metrics preview
            if let metrics = metrics {
                HStack(spacing: Theme.paddingMedium) {
                    MetricBadge(
                        icon: "cpu",
                        value: String(format: "%.0f%%", metrics.cpuUsage),
                        status: metricStatus(metrics.cpuUsage),
                        tooltip: String(format: "CPU Usage: %.1f%% — %@", metrics.cpuUsage, metrics.cpuUsage < 60 ? "Normal" : metrics.cpuUsage < 80 ? "Moderate load" : "High load")
                    )

                    MetricBadge(
                        icon: "memorychip",
                        value: String(format: "%.0f%%", metrics.memoryUsagePercent),
                        status: metricStatus(metrics.memoryUsagePercent),
                        tooltip: String(format: "RAM: %.1f GB used of %.1f GB", metrics.memoryUsedGB, metrics.memoryTotalGB)
                    )

                    Image(systemName: metrics.healthStatus.icon)
                        .foregroundStyle(statusColor(metrics.healthStatus))
                        .help("Health: \(metrics.healthStatus.rawValue)")
                }
            }

            // Last connected
            if let lastConnected = device.lastConnected {
                Text(lastConnected, style: .relative)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, Theme.paddingSmall)
    }

    private func metricStatus(_ value: Double) -> HealthStatus {
        if value < 60 { return .healthy }
        if value < 80 { return .warning }
        return .critical
    }

    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

struct MetricBadge: View {
    let icon: String
    let value: String
    let status: HealthStatus
    var tooltip: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)

            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(statusColor)
        .help(tooltip.isEmpty ? value : tooltip)
    }

    private var statusColor: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    DeviceListView()
        .environment(SSHService())
        .environment(DeviceMonitorService())
        .environment(TabManager())
        .frame(width: 800, height: 600)
}
