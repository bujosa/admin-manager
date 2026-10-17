import SwiftUI

struct DockerManagementView: View {
    let device: Device

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService
    @Environment(TabManager.self) private var tabManager

    @State private var searchText = ""
    @State private var filterState: String = "all"
    @State private var showRemoveConfirmation = false
    @State private var containerToRemove: DockerContainer?
    @State private var selectedContainerForLogs: DockerContainer?
    @State private var showLogSheet = false
    @State private var actionError: String?

    private var dockerStatus: DockerAvailability {
        adminService.dockerAvailability[device.id] ?? .unknown
    }

    private var containers: [DockerContainer] {
        adminService.containerCache[device.id] ?? []
    }

    private var filteredContainers: [DockerContainer] {
        var result = containers
        if filterState != "all" {
            result = result.filter { $0.state.rawValue == filterState }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.image.localizedCaseInsensitiveContains(searchText) ||
                $0.containerId.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var isLoading: Bool {
        adminService.isLoadingContainers[device.id] ?? false
    }

    var body: some View {
        VStack(spacing: Theme.paddingMedium) {
            switch dockerStatus {
            case .unknown:
                loadingState
            case .notInstalled:
                dockerNotInstalledView
            case .installed(let version):
                dockerHeader(version: version)
                    .padding(.horizontal, Theme.paddingLarge)

                if let error = adminService.dockerError[device.id] {
                    errorBanner(error)
                        .padding(.horizontal, Theme.paddingLarge)
                }

                if let error = actionError {
                    errorBanner(error)
                        .padding(.horizontal, Theme.paddingLarge)
                }

                if isLoading && containers.isEmpty {
                    loadingState
                } else if containers.isEmpty {
                    noContainersView
                } else {
                    ForEach(filteredContainers) { container in
                        ContainerRow(
                            container: container,
                            deviceId: device.id,
                            onStart: { performAction("start", on: container) },
                            onStop: { performAction("stop", on: container) },
                            onRestart: { performAction("restart", on: container) },
                            onExec: { openShell(container: container) },
                            onLogs: {
                                selectedContainerForLogs = container
                                showLogSheet = true
                            },
                            onRemove: {
                                containerToRemove = container
                                showRemoveConfirmation = true
                            }
                        )
                        .padding(.horizontal, Theme.paddingLarge)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await adminService.checkDocker(for: device.id, sshService: sshService)
                if case .installed = adminService.dockerAvailability[device.id] ?? .unknown {
                    await adminService.fetchContainers(for: device.id, sshService: sshService)
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            if let container = selectedContainerForLogs {
                ContainerLogSheet(container: container, deviceId: device.id)
            }
        }
        .alert("Remove Container", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { containerToRemove = nil }
            Button("Remove", role: .destructive) { removeContainer() }
        } message: {
            if let c = containerToRemove {
                Text("Remove container \"\(c.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Docker Header

    private func dockerHeader(version: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.paddingSmall) {
                    Text("Docker Containers")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(version.components(separatedBy: ",").first ?? version)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.15))
                        .foregroundStyle(Theme.success)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text("\(filteredContainers.count) containers")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Picker("", selection: $filterState) {
                Text("All").tag("all")
                Text("Running").tag("running")
                Text("Stopped").tag("exited")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

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
            .frame(width: 160)

            Button {
                Task { await adminService.fetchContainers(for: device.id, sshService: sshService) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.paddingMedium) {
            ProgressView()
            Text("Checking Docker...")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var dockerNotInstalledView: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(Theme.tertiaryText)

            Text("Docker not available")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Text("Docker is not installed or not accessible on this device.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                Task {
                    await adminService.checkDocker(for: device.id, sshService: sshService)
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var noContainersView: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(Theme.tertiaryText)

            Text("No containers found")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Button {
                Task { await adminService.fetchContainers(for: device.id, sshService: sshService) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
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
                .lineLimit(2)
            Spacer()
            Button {
                actionError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.paddingMedium)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    // MARK: - Actions

    private func performAction(_ action: String, on container: DockerContainer) {
        actionError = nil
        Task {
            do {
                try await adminService.containerAction(action, containerId: container.containerId, deviceId: device.id, sshService: sshService)
            } catch {
                actionError = "Failed to \(action) \(container.name): \(error.localizedDescription)"
            }
        }
    }

    private func openShell(container: DockerContainer) {
        let tab = tabManager.createTab(for: device)
        tabManager.updateTabConnection(id: tab.id, isConnected: true)
        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: "Entering container \(container.name)...", type: .system)
        )
        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: "$ docker exec -it \(container.containerId) /bin/sh", type: .command)
        )
        Task {
            do {
                let output = try await sshService.executeCommand(
                    "docker exec \(container.containerId) /bin/sh -c 'ls -la && echo \"---\" && whoami && echo \"---\" && pwd'",
                    on: device.id
                )
                tabManager.appendResponse(to: tab.id, output: output)
            } catch {
                tabManager.appendOutput(
                    to: tab.id,
                    line: TerminalLine(content: "Failed: \(error.localizedDescription)", type: .error)
                )
            }
        }
        NotificationCenter.default.post(name: .openTerminal, object: nil)
    }

    private func removeContainer() {
        guard let container = containerToRemove else { return }
        actionError = nil
        Task {
            do {
                try await adminService.containerAction("rm -f", containerId: container.containerId, deviceId: device.id, sshService: sshService)
            } catch {
                actionError = "Failed to remove \(container.name): \(error.localizedDescription)"
            }
        }
        containerToRemove = nil
    }
}

// MARK: - Container Row

private struct ContainerRow: View {
    let container: DockerContainer
    let deviceId: UUID
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onExec: () -> Void
    let onLogs: () -> Void
    let onRemove: () -> Void

    @Environment(DeviceAdminService.self) private var adminService

    var body: some View {
        HStack(spacing: Theme.paddingMedium) {
            // State icon
            Image(systemName: container.state.icon)
                .font(.title3)
                .foregroundStyle(stateColor)
                .frame(width: 28)

            // Container info
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Ports
            if !container.ports.isEmpty {
                Text(container.ports)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

            // Status
            Text(container.status)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 120, alignment: .trailing)

            // Actions
            HStack(spacing: 4) {
                if container.state != .running {
                    actionButton("play.fill", color: .green, action: onStart, actionName: "start")
                }
                if container.state == .running {
                    actionButton("stop.fill", color: .orange, action: onStop, actionName: "stop")
                    actionButton("terminal", color: .cyan, action: onExec, actionName: "exec")
                }
                actionButton("arrow.clockwise", color: .blue, action: onRestart, actionName: "restart")
                actionButton("doc.text", color: .purple, action: onLogs, actionName: "logs")
                actionButton("trash", color: .red, action: onRemove, actionName: "rm")
            }
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, Theme.paddingSmall)
        .cardStyle()
        .contextMenu {
            if container.state != .running {
                Button { onStart() } label: { Label("Start", systemImage: "play.fill") }
            }
            if container.state == .running {
                Button { onStop() } label: { Label("Stop", systemImage: "stop.fill") }
                Button { onExec() } label: { Label("Shell", systemImage: "terminal") }
            }
            Button { onRestart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
            Divider()
            Button { onLogs() } label: { Label("View Logs", systemImage: "doc.text") }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func actionButton(_ icon: String, color: Color, action: @escaping () -> Void, actionName: String) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(adminService.isActionInProgress(actionName, containerId: container.containerId, deviceId: deviceId))
        .help("\(actionName.capitalized) container")
    }

    private var stateColor: Color {
        switch container.state {
        case .running: return .green
        case .paused: return .yellow
        case .restarting: return .orange
        case .exited, .dead, .removing: return .red
        case .created: return .blue
        case .unknown: return .gray
        }
    }
}

// MARK: - Container Log Sheet

private struct ContainerLogSheet: View {
    let container: DockerContainer
    let deviceId: UUID

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService
    @Environment(\.dismiss) private var dismiss

    @State private var tailLines = 100
    @State private var isLoading = false

    private var logs: String {
        adminService.containerLogs[container.containerId] ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs: \(container.name)")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                Picker("Tail", selection: $tailLines) {
                    Text("100 lines").tag(100)
                    Text("500 lines").tag(500)
                    Text("1000 lines").tag(1000)
                }
                .frame(width: 130)

                Button {
                    fetchLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.paddingLarge)

            Divider().background(Theme.divider)

            // Log content
            ScrollView {
                if isLoading && logs.isEmpty {
                    ProgressView("Fetching logs...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if logs.isEmpty {
                    Text("No logs available")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Text(logs)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.terminalText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.paddingMedium)
                        .textSelection(.enabled)
                }
            }
            .background(Theme.terminalBackground)
        }
        .frame(width: 800, height: 500)
        .background(Theme.background)
        .onAppear {
            fetchLogs()
        }
        .onChange(of: tailLines) {
            fetchLogs()
        }
    }

    private func fetchLogs() {
        isLoading = true
        Task {
            _ = try? await adminService.fetchLogs(
                containerId: container.containerId,
                deviceId: deviceId,
                sshService: sshService,
                tail: tailLines
            )
            isLoading = false
        }
    }
}
