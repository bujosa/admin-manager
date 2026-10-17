import SwiftUI

struct MetricsView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor

    @State private var selectedDeviceId: UUID?
    @State private var autoRefresh = true

    var body: some View {
        HSplitView {
            // Device List
            VStack(spacing: 0) {
                HStack {
                    Text("Devices")
                        .font(.headline)

                    Spacer()

                    Toggle("Auto", isOn: $autoRefresh)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(Theme.paddingMedium)

                Divider()

                if sshService.activeSessions.isEmpty {
                    VStack(spacing: Theme.paddingMedium) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.tertiaryText)

                        Text("No devices connected")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)

                        Text("Connect to devices to see metrics")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedDeviceId) {
                        ForEach(sshService.devices.filter { sshService.isConnected(deviceId: $0.id) }) { device in
                            DeviceMetricRow(
                                device: device,
                                metrics: monitor.getLatestMetrics(for: device.id)
                            )
                            .tag(device.id)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 250, maxWidth: 300)
            .background(Theme.secondaryBackground)

            // Metrics Detail
            if let deviceId = selectedDeviceId,
               let device = sshService.deviceById(deviceId),
               let metrics = monitor.getLatestMetrics(for: deviceId) {
                MetricsDetailView(device: device, metrics: metrics, history: monitor.getMetricsHistory(for: deviceId))
            } else {
                VStack(spacing: Theme.paddingMedium) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.tertiaryText)

                    Text("Select a device to view metrics")
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            }
        }
        .onAppear {
            if autoRefresh {
                monitor.startMonitoring(sshService: sshService)
            }
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
        .onChange(of: autoRefresh) { _, newValue in
            if newValue {
                monitor.startMonitoring(sshService: sshService)
            } else {
                monitor.stopMonitoring()
            }
        }
    }
}

struct DeviceMetricRow: View {
    let device: Device
    let metrics: SystemMetrics?

    var body: some View {
        HStack(spacing: Theme.paddingSmall) {
            Image(systemName: device.category.icon)
                .foregroundStyle(Theme.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                if let metrics = metrics {
                    HStack(spacing: 4) {
                        Text("CPU: \(String(format: "%.0f%%", metrics.cpuUsage))")
                        Text("•")
                        Text("MEM: \(String(format: "%.0f%%", metrics.memoryUsagePercent))")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer()

            if let metrics = metrics {
                Image(systemName: metrics.healthStatus.icon)
                    .foregroundStyle(statusColor(metrics.healthStatus))
            }
        }
        .padding(.vertical, 4)
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

struct MetricsDetailView: View {
    let device: Device
    let metrics: SystemMetrics
    let history: [SystemMetrics]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLarge) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: device.category.icon)
                                .font(.title2)

                            Text(device.displayName)
                                .font(.title)
                                .fontWeight(.bold)
                        }

                        Text("Last updated: \(metrics.timestamp, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    // Health Status
                    HStack(spacing: Theme.paddingSmall) {
                        Image(systemName: metrics.healthStatus.icon)
                            .font(.title2)

                        Text(metrics.healthStatus.rawValue)
                            .font(.headline)
                    }
                    .padding(.horizontal, Theme.paddingMedium)
                    .padding(.vertical, Theme.paddingSmall)
                    .background(statusBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                }
                .padding(.horizontal, Theme.paddingLarge)

                // Main Metrics Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: Theme.paddingMedium
                ) {
                    MetricCard(
                        title: "CPU Usage",
                        value: String(format: "%.1f%%", metrics.cpuUsage),
                        icon: "cpu",
                        progress: metrics.cpuUsage / 100,
                        color: metricColor(metrics.cpuUsage)
                    )

                    MetricCard(
                        title: "Memory",
                        value: String(format: "%.1f%%", metrics.memoryUsagePercent),
                        subtitle: String(format: "%.1f / %.1f GB", metrics.memoryUsedGB, metrics.memoryTotalGB),
                        icon: "memorychip",
                        progress: metrics.memoryUsagePercent / 100,
                        color: metricColor(metrics.memoryUsagePercent)
                    )

                    MetricCard(
                        title: metrics.rootVolumeReadOnly ? "System Volume (RO)" : "System Volume",
                        value: metrics.diskTotal == 0 ? "Unavailable" : String(format: "%.1f%%", metrics.diskUsagePercent),
                        subtitle: String(format: "%.0f / %.0f GB", metrics.diskUsedGB, metrics.diskTotalGB),
                        icon: "internaldrive",
                        progress: metrics.diskUsagePercent / 100,
                        color: metrics.rootVolumeReadOnly || metrics.diskTotal == 0 ? .gray : metricColor(metrics.diskUsagePercent)
                    )
                }
                .padding(.horizontal, Theme.paddingLarge)

                // Secondary Metrics
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: Theme.paddingMedium
                ) {
                    if let temp = metrics.temperature {
                        SmallMetricCard(
                            title: "Temperature",
                            value: String(format: "%.1f°C", temp),
                            icon: "thermometer",
                            color: tempColor(temp)
                        )
                    }

                    if let fan = metrics.fanSpeed {
                        SmallMetricCard(
                            title: "Fan Speed",
                            value: "\(fan) RPM",
                            icon: "fan",
                            color: .blue
                        )
                    }

                    if let power = metrics.powerUsage {
                        SmallMetricCard(
                            title: metrics.powerSource ?? "Power",
                            value: String(format: "%.1fW", power),
                            icon: "bolt.fill",
                            color: .yellow
                        )
                    } else {
                        let spec = DevicePowerSpec.spec(for: device.category)
                        SmallMetricCard(
                            title: "Power (Typ)",
                            value: String(format: "%.0fW", spec.typicalWatts),
                            icon: "bolt",
                            color: .yellow
                        )
                    }

                    SmallMetricCard(
                        title: "Uptime",
                        value: metrics.uptimeFormatted,
                        icon: "clock",
                        color: .green
                    )

                    SmallMetricCard(
                        title: "Processes",
                        value: "\(metrics.processes)",
                        icon: "list.bullet",
                        color: .purple
                    )

                    SmallMetricCard(
                        title: "Load Avg",
                        value: metrics.loadAverage.isEmpty ? "N/A" : String(format: "%.2f", metrics.loadAverage[0]),
                        icon: "chart.bar",
                        color: .orange
                    )

                    // GPU metrics
                    if let gpuUsage = metrics.gpuUsage {
                        SmallMetricCard(
                            title: "GPU",
                            value: String(format: "%.0f%%", gpuUsage),
                            icon: "gpu",
                            color: .green
                        )
                    }

                    if let gpuTemp = metrics.gpuTemperature {
                        SmallMetricCard(
                            title: "GPU Temp",
                            value: String(format: "%.0f°C", gpuTemp),
                            icon: "thermometer.variable.and.figure",
                            color: .red
                        )
                    }

                    if let gpuPower = metrics.gpuPowerDraw {
                        SmallMetricCard(
                            title: "GPU Power",
                            value: String(format: "%.1fW", gpuPower),
                            icon: "bolt.circle.fill",
                            color: .orange
                        )
                    }

                    SmallMetricCard(
                        title: "Network In",
                        value: formatBytes(metrics.networkIn),
                        icon: "arrow.down.circle",
                        color: .cyan
                    )

                    SmallMetricCard(
                        title: "Network Out",
                        value: formatBytes(metrics.networkOut),
                        icon: "arrow.up.circle",
                        color: .pink
                    )
                }
                .padding(.horizontal, Theme.paddingLarge)

                // History Chart (placeholder)
                if !history.isEmpty {
                    GroupBox("CPU History") {
                        MetricHistoryChart(
                            data: history.map { $0.cpuUsage },
                            color: .blue
                        )
                        .frame(height: 100)
                    }
                    .padding(.horizontal, Theme.paddingLarge)

                    GroupBox("Memory History") {
                        MetricHistoryChart(
                            data: history.map { $0.memoryUsagePercent },
                            color: .purple
                        )
                        .frame(height: 100)
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                }

                Spacer(minLength: Theme.paddingLarge)
            }
            .padding(.top, Theme.paddingLarge)
        }
        .background(Theme.background)
    }

    private var statusBackground: Color {
        switch metrics.healthStatus {
        case .healthy: return .green.opacity(0.2)
        case .warning: return .yellow.opacity(0.2)
        case .critical: return .red.opacity(0.2)
        case .unknown: return .gray.opacity(0.2)
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
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        return String(format: "%.1f KB", kb)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Spacer()

                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.tertiaryBackground)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0))
                }
            }
            .frame(height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}

struct SmallMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.paddingSmall) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.paddingMedium)
        .cardStyle()
    }
}

struct MetricHistoryChart: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                Path { path in
                    let maxValue = max(data.max() ?? 100, 100)
                    let step = geo.size.width / CGFloat(data.count - 1)

                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * step
                        let y = geo.size.height - (CGFloat(value) / CGFloat(maxValue) * geo.size.height)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 2)

                // Fill
                Path { path in
                    let maxValue = max(data.max() ?? 100, 100)
                    let step = geo.size.width / CGFloat(data.count - 1)

                    path.move(to: CGPoint(x: 0, y: geo.size.height))

                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * step
                        let y = geo.size.height - (CGFloat(value) / CGFloat(maxValue) * geo.size.height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                Text("Not enough data")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    MetricsView()
        .environment(SSHService())
        .environment(DeviceMonitorService())
        .frame(width: 1000, height: 700)
}
