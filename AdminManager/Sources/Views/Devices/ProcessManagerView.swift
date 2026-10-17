import SwiftUI

struct ProcessManagerView: View {
    let device: Device

    @Environment(SSHService.self) private var sshService
    @Environment(DeviceAdminService.self) private var adminService

    @State private var searchText = ""
    @State private var sortField: ProcessSortField = .memory
    @State private var showKillConfirmation = false
    @State private var processToKill: SystemProcess?
    @State private var killSignal: KillSignal = .term
    @State private var killWithSudo = false
    @State private var autoRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    private var processes: [SystemProcess] {
        adminService.processCache[device.id] ?? []
    }

    private var filteredAndSorted: [SystemProcess] {
        var result = processes

        if !searchText.isEmpty {
            result = result.filter {
                $0.command.localizedCaseInsensitiveContains(searchText) ||
                $0.user.localizedCaseInsensitiveContains(searchText) ||
                "\($0.pid)".contains(searchText)
            }
        }

        switch sortField {
        case .memory: result.sort { $0.memMB > $1.memMB }
        case .cpu: result.sort { $0.cpuPercent > $1.cpuPercent }
        case .pid: result.sort { $0.pid < $1.pid }
        case .name: result.sort { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
        }

        return result
    }

    private var isLoading: Bool {
        adminService.isLoadingProcesses[device.id] ?? false
    }

    var body: some View {
        VStack(spacing: Theme.paddingMedium) {
            sectionHeader
                .padding(.horizontal, Theme.paddingLarge)

            if let error = adminService.processError[device.id] {
                errorBanner(error)
                    .padding(.horizontal, Theme.paddingLarge)
            }

            if isLoading && processes.isEmpty {
                loadingState
            } else if processes.isEmpty {
                emptyState
            } else {
                tableHeader
                    .padding(.horizontal, Theme.paddingLarge)

                ForEach(filteredAndSorted) { proc in
                    ProcessRow(process: proc) { signal, sudo in
                        processToKill = proc
                        killSignal = signal
                        killWithSudo = sudo
                        showKillConfirmation = true
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                }
            }
        }
        .onAppear {
            if processes.isEmpty {
                Task { await adminService.fetchProcesses(for: device.id, sshService: sshService) }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
        .onChange(of: autoRefresh) { _, newValue in
            if newValue {
                startAutoRefresh()
            } else {
                refreshTask?.cancel()
            }
        }
        .alert("Kill Process", isPresented: $showKillConfirmation) {
            Button("Cancel", role: .cancel) { processToKill = nil }
            Button(killSignal == .kill ? "Force Kill" : "Kill", role: .destructive) {
                killSelected()
            }
        } message: {
            if let p = processToKill {
                Text("Kill \(p.command) (PID \(p.pid))?\nSignal: \(killSignal == .kill ? "SIGKILL (9)" : "SIGTERM (15)")\(killWithSudo ? " with sudo" : "")")
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Process Manager")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("\(filteredAndSorted.count) processes")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Picker("Sort", selection: $sortField) {
                ForEach(ProcessSortField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

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

            Toggle(isOn: $autoRefresh) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .help("Auto-refresh every 5s")

            Button {
                Task { await adminService.fetchProcesses(for: device.id, sshService: sshService) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("PID")
                .frame(width: 70, alignment: .leading)
            Text("USER")
                .frame(width: 90, alignment: .leading)
            Text("CPU%")
                .frame(width: 70, alignment: .trailing)
            Text("MEM%")
                .frame(width: 70, alignment: .trailing)
            Text("RAM")
                .frame(width: 80, alignment: .trailing)
            Text("STATE")
                .frame(width: 60, alignment: .center)
            Text("COMMAND")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Theme.paddingSmall)
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
            Text("Fetching processes...")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(Theme.tertiaryText)

            Text("No processes found")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Text("Could not retrieve the process list. The command may require elevated privileges.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                Task { await adminService.fetchProcesses(for: device.id, sshService: sshService) }
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

    private func killSelected() {
        guard let proc = processToKill else { return }
        Task {
            try? await adminService.killProcessByPid(
                pid: proc.pid,
                deviceId: device.id,
                sshService: sshService,
                signal: killSignal,
                useSudo: killWithSudo
            )
        }
        processToKill = nil
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await adminService.fetchProcesses(for: device.id, sshService: sshService)
            }
        }
    }
}

// MARK: - Process Row

private struct ProcessRow: View {
    let process: SystemProcess
    let onKill: (KillSignal, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(process.pid)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 70, alignment: .leading)

            Text(process.user)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            usageBadge(value: process.cpuPercent, suffix: "%")
                .frame(width: 70, alignment: .trailing)

            usageBadge(value: process.memPercent, suffix: "%")
                .frame(width: 70, alignment: .trailing)

            Text(formatRAM(process.memMB))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 80, alignment: .trailing)

            stateBadge(process.state)
                .frame(width: 60, alignment: .center)

            Text(process.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Theme.paddingSmall)
                .help(process.command)

            Button {
                onKill(.term, false)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.error.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .help("Kill process (PID \(process.pid))")
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, Theme.paddingSmall)
        .cardStyle()
        .contextMenu {
            Button {
                onKill(.term, false)
            } label: {
                Label("Kill (SIGTERM)", systemImage: "stop.circle")
            }

            Button {
                onKill(.kill, false)
            } label: {
                Label("Force Kill (SIGKILL)", systemImage: "xmark.circle")
            }

            Divider()

            Button(role: .destructive) {
                onKill(.kill, true)
            } label: {
                Label("Kill with sudo (SIGKILL)", systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func usageBadge(value: Double, suffix: String) -> some View {
        Text(String(format: "%.1f%@", value, suffix))
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(usageColor(value).opacity(0.15))
            .foregroundStyle(usageColor(value))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func usageColor(_ value: Double) -> Color {
        if value < 5 { return .green }
        if value < 20 { return .yellow }
        return .red
    }

    @ViewBuilder
    private func stateBadge(_ state: String) -> some View {
        let (color, label) = stateInfo(state)
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func stateInfo(_ state: String) -> (Color, String) {
        let first = state.prefix(1).uppercased()
        switch first {
        case "R": return (.green, "Run")
        case "S": return (.blue, "Sleep")
        case "D": return (.orange, "Disk")
        case "Z": return (.red, "Zombie")
        case "T": return (.gray, "Stop")
        case "I": return (.gray, "Idle")
        default: return (.gray, state.prefix(3).uppercased().isEmpty ? "-" : String(state.prefix(3)))
        }
    }

    private func formatRAM(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}
