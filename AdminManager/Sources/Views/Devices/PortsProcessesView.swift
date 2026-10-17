import SwiftUI

struct PortsProcessesView: View {
    let device: Device

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService

    @State private var searchText = ""
    @State private var showKillConfirmation = false
    @State private var processToKill: PortInfo?

    private var ports: [PortInfo] {
        adminService.portCache[device.id] ?? []
    }

    private var filteredPorts: [PortInfo] {
        if searchText.isEmpty { return ports }
        return ports.filter {
            $0.processName.localizedCaseInsensitiveContains(searchText) ||
            "\($0.port)".contains(searchText) ||
            $0.localAddress.contains(searchText)
        }
    }

    private var isLoading: Bool {
        adminService.isLoadingPorts[device.id] ?? false
    }

    var body: some View {
        VStack(spacing: Theme.paddingMedium) {
            sectionHeader
                .padding(.horizontal, Theme.paddingLarge)

            if let error = adminService.portError[device.id] {
                errorBanner(error)
                    .padding(.horizontal, Theme.paddingLarge)
            }

            if isLoading && ports.isEmpty {
                loadingState
            } else if ports.isEmpty {
                emptyState
            } else {
                portTableHeader
                    .padding(.horizontal, Theme.paddingLarge)

                ForEach(filteredPorts) { port in
                    PortRow(port: port) {
                        processToKill = port
                        showKillConfirmation = true
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                }
            }
        }
        .onAppear {
            if ports.isEmpty {
                Task { await adminService.fetchPorts(for: device.id, sshService: sshService) }
            }
        }
        .alert("Kill Process", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) { processToKill = nil }
            Button("Kill") { killSelected(sudo: false) }
            Button("Kill (sudo)", role: .destructive) { killSelected(sudo: true) }
        } message: {
            if let p = processToKill {
                Text("Kill \(p.processName) (PID \(p.pid)) on port \(p.port)?")
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Listening Ports & Processes")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("\(filteredPorts.count) listening ports")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryText)
                    .font(.caption)
                TextField("Filter...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, Theme.paddingSmall)
            .padding(.vertical, 6)
            .background(Theme.tertiaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .frame(width: 180)

            Button {
                Task { await adminService.fetchPorts(for: device.id, sshService: sshService) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    // MARK: - Table Header

    private var portTableHeader: some View {
        HStack(spacing: 0) {
            Text("PROTO")
                .frame(width: 60, alignment: .leading)
            Text("PORT")
                .frame(width: 80, alignment: .leading)
            Text("ADDRESS")
                .frame(width: 130, alignment: .leading)
            Text("PID")
                .frame(width: 70, alignment: .leading)
            Text("PROCESS")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("STATE")
                .frame(width: 80, alignment: .leading)
            Text("")
                .frame(width: 40)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, Theme.paddingMedium)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.paddingMedium) {
            ProgressView()
            Text("Fetching ports...")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "network.slash")
                .font(.system(size: 36))
                .foregroundStyle(Theme.tertiaryText)

            Text("No listening ports found")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Text("The device may not have any services running, or the command requires elevated privileges.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                Task { await adminService.fetchPorts(for: device.id, sshService: sshService) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
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

    // MARK: - Actions

    private func killSelected(sudo: Bool) {
        guard let port = processToKill else { return }
        Task {
            try? await adminService.killProcess(pid: port.pid, deviceId: device.id, sshService: sshService, useSudo: sudo)
        }
        processToKill = nil
    }
}

// MARK: - Port Row

private struct PortRow: View {
    let port: PortInfo
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(port.proto.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(protocolColor.opacity(0.2))
                .foregroundStyle(protocolColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 60, alignment: .leading)

            Text("\(port.port)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 80, alignment: .leading)

            Text(port.localAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 130, alignment: .leading)

            Text("\(port.pid)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 70, alignment: .leading)

            Text(port.processName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(port.state)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.success.opacity(0.15))
                .foregroundStyle(Theme.success)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 80, alignment: .leading)

            Button {
                onKill()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.error.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .help("Kill process (PID \(port.pid))")
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, Theme.paddingSmall)
        .cardStyle()
        .contextMenu {
            Button("Kill Process") { onKill() }
            Button("Kill Process (sudo)") { onKill() }
        }
    }

    private var protocolColor: Color {
        switch port.proto {
        case .tcp, .tcp6: return .blue
        case .udp, .udp6: return .orange
        }
    }
}
