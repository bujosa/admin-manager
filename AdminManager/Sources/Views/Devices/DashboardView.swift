import SwiftUI

struct DashboardView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor
    @Environment(TabManager.self) private var tabManager

    @State private var showAddDevice = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLarge) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Overview of all your devices and systems")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    Button {
                        showAddDevice = true
                    } label: {
                        Label("Add Device", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task {
                            await monitor.refreshAllMetrics(sshService: sshService)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, Theme.paddingLarge)

                // Stats Cards
                HStack(spacing: Theme.paddingMedium) {
                    StatCard(
                        title: "Total Devices",
                        value: "\(sshService.devices.count)",
                        icon: "desktopcomputer",
                        color: .blue
                    )

                    StatCard(
                        title: "Connected",
                        value: "\(sshService.activeSessions.count)",
                        icon: "wifi",
                        color: .green
                    )

                    StatCard(
                        title: "Healthy",
                        value: "\(monitor.healthySystems)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    StatCard(
                        title: "Warnings",
                        value: "\(monitor.warningSystems)",
                        icon: "exclamationmark.triangle.fill",
                        color: .yellow
                    )

                    StatCard(
                        title: "Critical",
                        value: "\(monitor.criticalSystems)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }
                .padding(.horizontal, Theme.paddingLarge)

                // Device Grid
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: Theme.paddingMedium)
                    ],
                    spacing: Theme.paddingMedium
                ) {
                    ForEach(sshService.devices) { device in
                        DeviceCard(
                            device: device,
                            metrics: monitor.getLatestMetrics(for: device.id),
                            isConnected: sshService.isConnected(deviceId: device.id)
                        ) {
                            openTerminal(for: device)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NotificationCenter.default.post(name: .showDeviceDetail, object: device.id)
                        }
                    }
                }
                .padding(.horizontal, Theme.paddingLarge)

                Spacer(minLength: Theme.paddingLarge)
            }
            .padding(.top, Theme.paddingLarge)
        }
        .background(Theme.background)
        .sheet(isPresented: $showAddDevice) {
            AddDeviceSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDevice)) { _ in
            showAddDevice = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDevices)) { _ in
            Task {
                await monitor.refreshAllMetrics(sshService: sshService)
            }
        }
    }

    private func openTerminal(for device: Device) {
        let tab = tabManager.createTab(for: device)
        if sshService.isConnected(deviceId: device.id) {
            tabManager.updateTabConnection(id: tab.id, isConnected: true)
        }
        NotificationCenter.default.post(name: .openTerminal, object: nil)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Spacer()
            }

            Spacer()

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Theme.paddingMedium)
        .frame(maxWidth: .infinity, minHeight: 120)
        .cardStyle()
    }
}

struct DeviceCard: View {
    let device: Device
    let metrics: SystemMetrics?
    let isConnected: Bool
    let onOpenTerminal: () -> Void

    @Environment(SSHService.self) private var sshService
    @State private var showPassword = false
    @State private var showEditDevice = false
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            // Header
            HStack {
                DeviceIconView(category: device.category, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(device.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("(\(device.category.rawValue))")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    Text(device.connectionString)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                Circle()
                    .fill(isConnected ? Theme.success : Theme.error.opacity(0.5))
                    .frame(width: 10, height: 10)
            }

            // Metrics (if connected)
            if let metrics = metrics {
                VStack(spacing: Theme.paddingSmall) {
                    MetricRow(
                        label: "CPU",
                        value: String(format: "%.1f%%", metrics.cpuUsage),
                        progress: metrics.cpuUsage / 100,
                        color: metricColor(metrics.cpuUsage),
                        tooltip: String(format: "CPU Usage: %.1f%% — %@", metrics.cpuUsage, metrics.cpuUsage < 60 ? "Normal" : metrics.cpuUsage < 80 ? "Moderate load" : "High load")
                    )

                    MetricRow(
                        label: "Memory",
                        value: String(format: "%.1f%%", metrics.memoryUsagePercent),
                        progress: metrics.memoryUsagePercent / 100,
                        color: metricColor(metrics.memoryUsagePercent),
                        tooltip: String(format: "RAM: %.1f GB used of %.1f GB (%.1f%% utilization)", metrics.memoryUsedGB, metrics.memoryTotalGB, metrics.memoryUsagePercent)
                    )

                    MetricRow(
                        label: metrics.rootVolumeReadOnly ? "System (RO)" : "System",
                        value: metrics.diskTotal == 0 ? "Unavailable" : String(format: "%.1f%%", metrics.diskUsagePercent),
                        progress: metrics.diskUsagePercent / 100,
                        color: metrics.rootVolumeReadOnly || metrics.diskTotal == 0 ? .gray : metricColor(metrics.diskUsagePercent),
                        tooltip: (metrics.rootVolumeReadOnly ? "Read-only OS volume; full capacity does not indicate low writable space. " : "Root filesystem. ") + String(format: "Disk: %.0f GB used of %.0f GB (%.0f GB free)", metrics.diskUsedGB, metrics.diskTotalGB, metrics.diskTotalGB - metrics.diskUsedGB)
                    )

                    HStack {
                        if let temp = metrics.temperature {
                            Image(systemName: "thermometer")
                                .foregroundStyle(tempColor(temp))
                            Text(String(format: "%.1f°C", temp))
                                .font(.caption)
                                .help(String(format: "Temperature: %.1f°C — %@", temp, temp < 50 ? "Cool" : temp < 70 ? "Warm" : "Hot"))
                        }
                        Spacer()
                        if metrics.uptime > 0 {
                            Text("Uptime: \(metrics.uptimeFormatted)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } else if !isConnected {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.paddingMedium)
            }

            // Actions
            HStack(spacing: Theme.paddingSmall) {
                if isConnected {
                    Button {
                        onOpenTerminal()
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
                } else {
                    Button {
                        showPassword = true
                    } label: {
                        Label("Connect", systemImage: "wifi")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Menu {
                    Button {
                        showEditDevice = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button("Delete", role: .destructive) {
                        sshService.deleteDevice(device)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.paddingMedium)
        .cardStyle()
        .sheet(isPresented: $showPassword) {
            PasswordSheet(device: device)
        }
        .sheet(isPresented: $showEditDevice) {
            EditDeviceSheet(device: device)
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
}

struct MetricRow: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color
    var tooltip: String = ""

    var body: some View {
        HStack(spacing: Theme.paddingSmall) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.tertiaryBackground)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0))
                }
            }
            .frame(height: 6)

            Text(value)
                .font(.caption)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
        .help(tooltip.isEmpty ? label : tooltip)
    }
}

struct PasswordSheet: View {
    let device: Device
    @Environment(SSHService.self) private var sshService
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var triedKeychain = false

    var body: some View {
        VStack(spacing: Theme.paddingLarge) {
            Text("Connect to \(device.displayName)")
                .font(.headline)

            if isConnecting && !triedKeychain {
                ProgressView("Connecting with saved credentials...")
                    .frame(maxWidth: .infinity)
            } else {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isConnecting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.paddingLarge)
        .frame(width: 300)
        .onAppear {
            tryKeychainFirst()
        }
    }

    private func tryKeychainFirst() {
        guard device.authMethod == .password else {
            // For key/agent auth, just try connecting directly
            isConnecting = true
            Task {
                do {
                    try await sshService.connect(to: device)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                    isConnecting = false
                }
            }
            return
        }

        guard let savedPwd = KeychainHelper.getPassword(for: device) else { return }
        isConnecting = true
        Task {
            do {
                try await sshService.connect(to: device, password: savedPwd)
                dismiss()
            } catch {
                // Keychain password failed, let user type it manually
                self.error = nil
                isConnecting = false
                triedKeychain = true
            }
        }
    }

    private func connect() {
        isConnecting = true
        error = nil

        Task {
            do {
                try await sshService.connect(to: device, password: password)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

#Preview {
    DashboardView()
        .environment(SSHService())
        .environment(DeviceMonitorService())
        .environment(TabManager())
        .frame(width: 1000, height: 700)
}
