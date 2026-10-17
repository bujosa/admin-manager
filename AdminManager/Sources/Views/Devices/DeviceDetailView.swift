import SwiftUI
import Charts

struct DeviceDetailView: View {
    let device: Device
    let onBack: () -> Void

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor
    @Environment(TabManager.self) private var tabManager
    @Environment(DeviceAdminService.self) private var adminService

    @State private var showPassword = false
    @State private var selectedTab: DeviceDetailTab = .overview
    @State private var showCleanCacheConfirmation = false
    @State private var showCacheResult = false

    private var isConnected: Bool {
        sshService.isConnected(deviceId: device.id)
    }

    private var metrics: SystemMetrics? {
        monitor.getLatestMetrics(for: device.id)
    }

    private var history: [SystemMetrics] {
        monitor.getMetricsHistory(for: device.id)
    }

    private var isCleaning: Bool {
        adminService.isCleaningCache[device.id] ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLarge) {
                header
                deviceInfoSection

                if isConnected {
                    tabPicker
                }

                switch selectedTab {
                case .overview:
                    if isConnected, let error = monitor.metricsError[device.id] {
                        Label(error + (metrics == nil ? "" : " Showing the previous measurements."), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.paddingLarge)
                    }
                    if let metrics = metrics {
                        metricsOverview(metrics)
                        secondaryMetrics(metrics)
                        if history.count > 1 {
                            chartsSection
                        }
                    } else if !isConnected {
                        notConnectedPlaceholder
                    }
                case .systemInfo:
                    if isConnected {
                        SystemInfoView(device: device)
                    } else {
                        notConnectedPlaceholder
                    }
                case .storage:
                    if isConnected {
                        StorageView(device: device)
                    } else {
                        notConnectedPlaceholder
                    }
                case .ports:
                    if isConnected {
                        PortsProcessesView(device: device)
                    } else {
                        notConnectedPlaceholder
                    }
                case .docker:
                    if isConnected {
                        DockerManagementView(device: device)
                    } else {
                        notConnectedPlaceholder
                    }
                case .processes:
                    if isConnected {
                        ProcessManagerView(device: device)
                    } else {
                        notConnectedPlaceholder
                    }
                }

                Spacer(minLength: Theme.paddingLarge)
            }
            .padding(.top, Theme.paddingLarge)
        }
        .background(Theme.background)
        .sheet(isPresented: $showPassword) {
            PasswordSheet(device: device)
        }
        .alert("Clean Cache", isPresented: $showCleanCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clean", role: .destructive) {
                Task {
                    await adminService.cleanCache(for: device.id, sshService: sshService)
                    await monitor.refreshMetrics(for: device.id, sshService: sshService)
                    showCacheResult = true
                    try? await Task.sleep(for: .seconds(4))
                    showCacheResult = false
                }
            }
        } message: {
            Text("This will free RAM by clearing system caches on \(device.displayName). May require sudo privileges.")
        }
        .overlay(alignment: .bottom) {
            if showCacheResult, let result = adminService.cacheCleanResult[device.id] {
                HStack(spacing: Theme.paddingSmall) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                    Text(result)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, Theme.paddingMedium)
                .padding(.vertical, Theme.paddingSmall)
                .background(Theme.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .padding(.bottom, Theme.paddingLarge)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Theme.animationFast, value: showCacheResult)
            } else if showCacheResult, let error = adminService.cacheCleanError[device.id] {
                HStack(spacing: Theme.paddingSmall) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.error)
                    Text(error)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, Theme.paddingMedium)
                .padding(.vertical, Theme.paddingSmall)
                .background(Theme.error.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .padding(.bottom, Theme.paddingLarge)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Theme.animationFast, value: showCacheResult)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.paddingMedium) {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)

            Spacer()

            Circle()
                .fill(isConnected ? Theme.success : Theme.error.opacity(0.5))
                .frame(width: 10, height: 10)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(isConnected ? Theme.success : Theme.secondaryText)

            if isConnected {
                Button {
                    let tab = tabManager.createTab(for: device)
                    tabManager.updateTabConnection(id: tab.id, isConnected: true)
                    NotificationCenter.default.post(name: .openTerminal, object: nil)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await sshService.disconnect(from: device.id)
                    }
                } label: {
                    Label("Disconnect", systemImage: "wifi.slash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await monitor.refreshMetrics(for: device.id, sshService: sshService)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    showCleanCacheConfirmation = true
                } label: {
                    if isCleaning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Clean Cache", systemImage: "eraser.line.dashed")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCleaning)
            } else {
                Button {
                    showPassword = true
                } label: {
                    Label("Connect", systemImage: "wifi")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, Theme.paddingLarge)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(DeviceDetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(Theme.animationFast) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, Theme.paddingMedium)
                    .padding(.vertical, Theme.paddingSmall)
                    .background(selectedTab == tab ? Theme.accent.opacity(0.2) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.tertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .padding(.horizontal, Theme.paddingLarge)
    }

    // MARK: - Device Info

    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            HStack(spacing: Theme.paddingMedium) {
                DeviceIconView(category: device.category, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(device.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15))
                            .foregroundStyle(categoryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(device.connectionString)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                if let metrics = metrics {
                    healthBadge(metrics.healthStatus)
                }
            }

            Divider().background(Theme.divider)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.paddingMedium) {
                InfoField(label: "Category", value: device.category.rawValue, icon: device.category.icon)
                InfoField(label: "Hostname", value: device.hostname, icon: "network")
                InfoField(label: "Port", value: "\(device.port)", icon: "number")
                InfoField(label: "Username", value: device.username, icon: "person.fill")
                InfoField(label: "Auth Method", value: device.authMethod.rawValue, icon: device.authMethod.icon)
                if let lastConnected = device.lastConnected {
                    InfoField(label: "Last Connected", value: formatDate(lastConnected), icon: "clock")
                }
                if !device.notes.isEmpty {
                    InfoField(label: "Notes", value: device.notes, icon: "note.text")
                }
            }
        }
        .padding(Theme.paddingLarge)
        .cardStyle()
        .padding(.horizontal, Theme.paddingLarge)
    }

    // MARK: - Metrics Overview

    private func metricsOverview(_ metrics: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            HStack(spacing: Theme.paddingMedium) {
                GaugeCard(
                    title: "CPU",
                    value: metrics.cpuUsage,
                    subtitle: String(format: "%.1f%%", metrics.cpuUsage),
                    color: metricColor(metrics.cpuUsage),
                    icon: "cpu"
                )

                GaugeCard(
                    title: "Memory",
                    value: metrics.memoryUsagePercent,
                    subtitle: String(format: "%.1f / %.1f GB", metrics.memoryUsedGB, metrics.memoryTotalGB),
                    color: metricColor(metrics.memoryUsagePercent),
                    icon: "memorychip"
                )

                GaugeCard(
                    title: metrics.rootVolumeReadOnly ? "System Volume (RO)" : "System Volume",
                    value: metrics.diskUsagePercent,
                    subtitle: metrics.diskTotal == 0 ? "Unavailable" : String(format: "%.0f / %.0f GB", metrics.diskUsedGB, metrics.diskTotalGB),
                    color: metrics.rootVolumeReadOnly || metrics.diskTotal == 0 ? .gray : metricColor(metrics.diskUsagePercent),
                    icon: "internaldrive"
                )
            }
            Button {
                withAnimation(Theme.animationFast) { selectedTab = .storage }
            } label: {
                Label("View all drives & resources", systemImage: "externaldrive.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.paddingLarge)
    }

    // MARK: - Secondary Metrics

    private func secondaryMetrics(_ metrics: SystemMetrics) -> some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 180, maximum: 250), spacing: Theme.paddingMedium)
        ], spacing: Theme.paddingMedium) {
            if let temp = metrics.temperature {
                DetailMetricItem(
                    title: "Temperature",
                    value: String(format: "%.1f°C", temp),
                    icon: "thermometer",
                    color: tempColor(temp)
                )
            }

            if let fan = metrics.fanSpeed {
                DetailMetricItem(
                    title: "Fan Speed",
                    value: "\(fan) RPM",
                    icon: "fan.fill",
                    color: .cyan
                )
            }

            if let power = metrics.powerUsage {
                DetailMetricItem(
                    title: metrics.powerSource ?? "Power Usage",
                    value: String(format: "%.1f W", power),
                    icon: "bolt.fill",
                    color: .yellow
                )
            } else {
                let spec = DevicePowerSpec.spec(for: device.category)
                DetailMetricItem(
                    title: "Power (Typical)",
                    value: String(format: "%.0f W", spec.typicalWatts),
                    subtitle: String(format: "Max: %.0f W", spec.maxWatts),
                    icon: "bolt.fill",
                    color: .yellow
                )
            }

            // GPU Section
            if metrics.hasGPUMetrics {
                if let gpuUsage = metrics.gpuUsage {
                    DetailMetricItem(
                        title: "GPU Usage",
                        value: String(format: "%.0f%%", gpuUsage),
                        icon: "gpu",
                        color: .green
                    )
                }
                if let gpuTemp = metrics.gpuTemperature {
                    DetailMetricItem(
                        title: "GPU Temp",
                        value: String(format: "%.0f°C", gpuTemp),
                        icon: "thermometer.variable.and.figure",
                        color: tempColor(gpuTemp)
                    )
                }
                if metrics.gpuMemoryUsed != nil, let gpuMemTotal = metrics.gpuMemoryTotal, gpuMemTotal > 0 {
                    DetailMetricItem(
                        title: "GPU Memory",
                        value: String(format: "%.1f / %.1f GB", metrics.gpuMemoryUsedGB, metrics.gpuMemoryTotalGB),
                        icon: "memorychip.fill",
                        color: .mint
                    )
                }
                if let gpuPower = metrics.gpuPowerDraw {
                    DetailMetricItem(
                        title: "GPU Power",
                        value: String(format: "%.1f W", gpuPower),
                        icon: "bolt.circle.fill",
                        color: .orange
                    )
                }
            } else {
                let spec = DevicePowerSpec.spec(for: device.category)
                if !spec.gpuName.isEmpty {
                    DetailMetricItem(
                        title: "GPU",
                        value: spec.gpuName,
                        icon: "gpu",
                        color: .green
                    )
                }
            }

            DetailMetricItem(
                title: "Uptime",
                value: metrics.uptimeFormatted,
                icon: "clock.arrow.circlepath",
                color: .green
            )

            DetailMetricItem(
                title: "Processes",
                value: "\(metrics.processes)",
                icon: "list.bullet.rectangle",
                color: .purple
            )

            if !metrics.loadAverage.isEmpty {
                DetailMetricItem(
                    title: "Load Average",
                    value: metrics.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
            }

            DetailMetricItem(
                title: "Network Received (total)",
                value: formatBytes(metrics.networkIn),
                icon: "arrow.down.circle",
                color: .blue
            )

            DetailMetricItem(
                title: "Network Sent (total)",
                value: formatBytes(metrics.networkOut),
                icon: "arrow.up.circle",
                color: .indigo
            )
        }
        .padding(.horizontal, Theme.paddingLarge)
    }

    // MARK: - Charts

    private var chartsSection: some View {
        VStack(spacing: Theme.paddingMedium) {
            HStack {
                Text("History")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(history.count) samples")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, Theme.paddingLarge)

            HStack(spacing: Theme.paddingMedium) {
                ChartCard(title: "CPU Usage", data: history.map { $0.cpuUsage }, color: .blue, unit: "%")
                ChartCard(title: "Memory Usage", data: history.map { $0.memoryUsagePercent }, color: .purple, unit: "%")
            }
            .padding(.horizontal, Theme.paddingLarge)
        }
    }

    // MARK: - Not Connected

    private var notConnectedPlaceholder: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)

            Text("Connect to view system metrics")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Button {
                showPassword = true
            } label: {
                Label("Connect", systemImage: "wifi")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func healthBadge(_ status: HealthStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(healthColor(status).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        .foregroundStyle(healthColor(status))
        .help(healthTooltip(status))
    }

    private func healthTooltip(_ status: HealthStatus) -> String {
        guard let m = metrics else { return status.rawValue }
        var issues: [String] = []
        if m.cpuUsage >= 70 {
            issues.append(String(format: "CPU: %.1f%%", m.cpuUsage))
        }
        if m.memoryUsagePercent >= 80 {
            issues.append(String(format: "Memory: %.1f%%", m.memoryUsagePercent))
        }
        if StoragePressure.isHigh(used: m.diskUsed, total: m.diskTotal, readOnly: m.rootVolumeReadOnly) {
            issues.append(String(format: "Disk: %.1f%%", m.diskUsagePercent))
        }
        if let temp = m.temperature, temp >= 75 {
            issues.append(String(format: "Temp: %.0f°C", temp))
        }
        if issues.isEmpty {
            return "Available measurements are within thresholds"
        }
        return "Issues: " + issues.joined(separator: ", ")
    }

    private func healthColor(_ status: HealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private var categoryColor: Color {
        switch device.category.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }

    private func metricColor(_ value: Double) -> Color {
        if value < 60 { return .green }
        if value < 80 { return .yellow }
        return .red
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 50 { return .green }
        if temp < 70 { return .yellow }
        return .red
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Subviews

private struct InfoField: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: Theme.paddingSmall) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)

                Text(value)
                    .font(.caption)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(Theme.paddingSmall)
    }
}

private struct GaugeCard: View {
    let title: String
    let value: Double
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: Theme.paddingMedium) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(String(format: "%.1f%%", value))
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.tertiaryBackground)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(value / 100, 1.0))
                }
            }
            .frame(height: 8)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}

private struct DetailMetricItem: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.paddingSmall) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)

                Text(value)
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer()
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}

private struct ChartCard: View {
    let title: String
    let data: [Double]
    let color: Color
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value(title, value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", index),
                        y: .value(title, value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))\(unit)")
                                .font(.caption2)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(Theme.divider)
                }
            }
            .frame(height: 140)
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}

#Preview {
    DeviceDetailView(
        device: Device(
            name: "Production Server",
            hostname: "192.0.2.10",
            username: "admin",
            category: .server
        ),
        onBack: {}
    )
    .environment(SSHService())
    .environment(DeviceMonitorService())
    .environment(TabManager())
    .environment(DeviceAdminService())
    .frame(width: 1000, height: 800)
}
