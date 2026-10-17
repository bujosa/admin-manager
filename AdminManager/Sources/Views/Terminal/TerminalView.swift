import SwiftUI

struct TerminalView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(TabManager.self) private var tabManager
    @Environment(DeviceMonitorService.self) private var monitor

    @State private var showDevicePicker = false
    @State private var showAIChatPanel = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar (Chrome-like) with AI toggle
            HStack(spacing: 0) {
                TabBarView()

                Divider()
                    .frame(height: 24)

                Button {
                    withAnimation(Theme.animationFast) {
                        showAIChatPanel.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                        Text("AI")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(showAIChatPanel ? .purple : Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(showAIChatPanel ? Color.purple.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.paddingSmall)
                .help("Toggle AI Assistant Panel")
            }
            .background(Theme.secondaryBackground)

            Divider()
                .background(Theme.divider)

            // Terminal Content + AI Panel
            if let activeTab = tabManager.activeTab {
                HSplitView {
                    TerminalContent(tabId: activeTab.id)
                        .frame(minWidth: 400)

                    if showAIChatPanel {
                        AIChatPanel(tabId: activeTab.id)
                            .frame(minWidth: 300, idealWidth: 380, maxWidth: 500)
                    }
                }
            } else {
                EmptyTerminalView {
                    showDevicePicker = true
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            showDevicePicker = true
        }
    }
}

struct TabBarView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(SSHService.self) private var sshService

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabManager.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isActive: tabManager.activeTabId == tab.id,
                        device: sshService.deviceById(tab.deviceId)
                    ) {
                        tabManager.selectTab(id: tab.id)
                    } onClose: {
                        tabManager.closeTab(id: tab.id)
                    }
                }

                // New Tab Button
                Button {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(Theme.tertiaryBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, Theme.paddingSmall)
            .padding(.vertical, 6)
        }
        .background(Theme.secondaryBackground)
        .frame(height: 40)
    }
}

struct TabButton: View {
    let tab: SSHTab
    let isActive: Bool
    let device: Device?
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tab.isConnected ? Theme.success : Theme.tertiaryText)
                .frame(width: 6, height: 6)

            if let device = device {
                Image(systemName: device.category.icon)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 120)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 16, height: 16)
                    .background(isHovered ? Theme.tertiaryBackground : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isActive
                ? Theme.tertiaryBackground
                : (isHovered ? Theme.tertiaryBackground.opacity(0.5) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Theme.border : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct TerminalContent: View {
    let tabId: UUID

    @Environment(SSHService.self) private var sshService
    @Environment(TabManager.self) private var tabManager
    @Environment(AIService.self) private var aiService
    @Environment(DeviceMonitorService.self) private var monitor

    @State private var commandInput = ""
    @State private var isAIMode = false
    @State private var aiSuggestion: (command: String, explanation: String)?
    @FocusState private var isInputFocused: Bool

    /// Read tab directly from the @Observable tabManager so the view re-renders on every mutation.
    private var tab: SSHTab {
        tabManager.tabs.first { $0.id == tabId } ?? SSHTab(deviceId: UUID(), title: "")
    }

    private var device: Device? {
        sshService.deviceById(tab.deviceId)
    }

    private var deviceInfo: String {
        guard let device = device else { return "unknown" }
        return "\(device.displayName) (\(device.connectionString))"
    }

    private var systemStats: String {
        guard let metrics = monitor.getLatestMetrics(for: tab.deviceId) else { return "" }
        var parts = [
            String(format: "CPU: %.0f%%", metrics.cpuUsage),
            String(format: "RAM: %.1f/%.1fGB (%.0f%%)", metrics.memoryUsedGB, metrics.memoryTotalGB, metrics.memoryUsagePercent),
            String(format: "Disk: %.0f%%", metrics.diskUsagePercent),
            "Uptime: \(metrics.uptimeFormatted)"
        ]
        if let temp = metrics.temperature {
            parts.append(String(format: "Temp: %.0f°C", temp))
        }
        if let power = metrics.powerUsage {
            parts.append(String(format: "Power: %.1fW", power))
        }
        if let gpuUsage = metrics.gpuUsage {
            parts.append(String(format: "GPU: %.0f%%", gpuUsage))
        }
        return parts.joined(separator: " | ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tab.terminalOutput) { line in
                            TerminalLineView(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(Theme.paddingMedium)
                }
                .onChange(of: tab.terminalOutput.count) { _, _ in
                    if let lastLine = tab.terminalOutput.last {
                        withAnimation {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Theme.terminalBackground)

            // AI suggestions always require review.
            if let suggestion = aiSuggestion {
                AISuggestionBanner(
                    command: suggestion.command,
                    explanation: suggestion.explanation,
                    onRun: {
                        let cmd = suggestion.command
                        aiSuggestion = nil
                        if !cmd.isEmpty {
                            runCommandFromAI(cmd)
                        }
                    },
                    onDismiss: {
                        aiSuggestion = nil
                    }
                )
            }

            // AI Mode indicator bar
            if isAIMode {
                HStack(spacing: Theme.paddingSmall) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(.purple)
                    Text("AI Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                    Text("— ask questions or give instructions. Review each suggested command before running it.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button {
                        exitAIMode()
                    } label: {
                        Label("Exit", systemImage: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, Theme.paddingMedium)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.08))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.purple.opacity(0.2)),
                    alignment: .top
                )
            }

            // Command Input
            HStack(spacing: Theme.paddingSmall) {
                Text(isAIMode ? "AI" : "$")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(isAIMode ? .bold : .regular)
                    .foregroundStyle(isAIMode ? .purple : Theme.terminalCommand)
                    .frame(minWidth: 20)

                TextField(
                    isAIMode ? "Ask AI anything..." : "Enter command or 'ai' to start AI mode...",
                    text: $commandInput
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.terminalFontSize, design: .monospaced))
                    .foregroundStyle(isAIMode ? Theme.aiUser : Theme.terminalText)
                    .focused($isInputFocused)
                    .onSubmit {
                        executeCommand()
                    }

                if aiService.isProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(aiService.progressMessage ?? "")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(height: 20)
                }

                if !commandInput.isEmpty {
                    Button {
                        executeCommand()
                    } label: {
                        Image(systemName: "return")
                            .foregroundStyle(isAIMode ? .purple : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.paddingMedium)
            .background(isAIMode ? Color.purple.opacity(0.04) : Theme.terminalBackground)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(isAIMode ? Color.purple.opacity(0.3) : Theme.border),
                alignment: .top
            )
        }
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Command Execution

    private func executeCommand() {
        guard !commandInput.isEmpty else { return }

        let command = commandInput
        commandInput = ""

        // Handle AI mode commands
        if isAIMode {
            let lower = command.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "/exit" || lower == "/ai" || lower == "exit" || lower == "/quit" {
                exitAIMode()
                return
            }
            askAI(question: command)
            return
        }

        // Check if entering AI mode
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        if lower == "ai" {
            enterAIMode()
            return
        }

        if lower.hasPrefix("ai ") {
            let question = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !question.isEmpty else {
                enterAIMode()
                return
            }
            enterAIMode()
            askAI(question: question)
            return
        }

        // Handle clear/cls locally (SSH non-interactive sessions don't support TERM)
        if lower == "clear" || lower == "cls" || lower == "reset" {
            tabManager.clearTerminal(for: tab.id)
            return
        }

        // Normal terminal command
        tabManager.appendCommand(to: tab.id, command: command)

        Task {
            do {
                let output = try await sshService.executeCommand(command, on: tab.deviceId)
                tabManager.appendResponse(to: tab.id, output: output)
            } catch {
                tabManager.appendResponse(to: tab.id, output: error.localizedDescription, isError: true)
            }
        }
    }

    // MARK: - AI Mode

    private func enterAIMode() {
        withAnimation(Theme.animationFast) {
            isAIMode = true
        }
        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: "AI mode active — ask anything. Safe commands run automatically. Type /exit to return.", type: .system)
        )
    }

    private func exitAIMode() {
        withAnimation(Theme.animationFast) {
            isAIMode = false
        }
        aiSuggestion = nil
        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: "Exited AI mode.", type: .system)
        )
    }

    // MARK: - AI Chat Flow

    private func buildRecentContext() -> String {
        tab.terminalOutput.suffix(50).map(\.content).joined(separator: "\n")
    }

    private func askAI(question: String) {
        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: question, type: .aiUser)
        )

        let context = buildRecentContext()
        let info = deviceInfo
        let stats = systemStats

        Task {
            guard let response = await aiService.chat(
                question: question,
                deviceInfo: info,
                systemStats: stats,
                recentOutput: context
            ) else {
                tabManager.appendOutput(
                    to: tab.id,
                    line: TerminalLine(
                        content: aiService.lastError ?? "AI could not generate a response.",
                        type: .error
                    )
                )
                return
            }

            // Show AI explanation
            tabManager.appendOutput(
                to: tab.id,
                line: TerminalLine(content: response.explanation, type: .aiResponse)
            )

            // Model output never authorizes shell execution.
            if !response.command.isEmpty {
                aiSuggestion = (command: response.command, explanation: response.explanation)
            }
        }
    }

    /// Run a command from the suggestion banner, then analyze the result.
    private func runCommandFromAI(_ command: String) {
        tabManager.appendCommand(to: tab.id, command: command)

        Task {
            do {
                let output = try await sshService.executeCommand(command, on: tab.deviceId)
                tabManager.appendResponse(to: tab.id, output: output)

                // If we're in AI mode, auto-analyze
                if isAIMode {
                    await analyzeCommandResult(command: command, output: output)
                }
            } catch {
                tabManager.appendResponse(to: tab.id, output: error.localizedDescription, isError: true)
            }
        }
    }

    /// Feed command output back to AI for analysis, creating a conversational loop.
    private func analyzeCommandResult(command: String, output: String) async {
        guard isAIMode, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let info = deviceInfo
        let stats = systemStats

        guard let analysis = await aiService.analyzeOutput(
            command: command,
            output: output,
            deviceInfo: info,
            systemStats: stats
        ) else { return }

        tabManager.appendOutput(
            to: tab.id,
            line: TerminalLine(content: analysis.explanation, type: .aiResponse)
        )

        if !analysis.followUp.isEmpty {
            aiSuggestion = (command: analysis.followUp, explanation: analysis.explanation)
        }
    }
}

// MARK: - AI Suggestion Banner

struct AISuggestionBanner: View {
    let command: String
    let explanation: String
    let onRun: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.paddingMedium) {
            Image(systemName: "sparkle")
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested command:")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)

                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.white)
                    .fontWeight(.medium)
            }

            Spacer()

            Button {
                onRun()
            } label: {
                Label("Run", systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, Theme.paddingSmall)
        .background(Color.purple.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.purple.opacity(0.3)),
            alignment: .top
        )
    }
}

struct TerminalLineView: View {
    let line: TerminalLine

    var body: some View {
        HStack(alignment: .top, spacing: Theme.paddingSmall) {
            Text(line.timestamp, style: .time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 60, alignment: .leading)

            if line.type == .aiUser || line.type == .aiResponse {
                Image(systemName: line.type == .aiUser ? "person.fill" : "sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(line.type == .aiUser ? Theme.aiUser : Theme.aiResponse)
                    .frame(width: 12)
            }

            Text(line.content)
                .font(.system(size: Theme.terminalFontSize, design: .monospaced))
                .foregroundStyle(lineColor)
                .textSelection(.enabled)
        }
    }

    private var lineColor: Color {
        switch line.type {
        case .command:
            return Theme.terminalCommand
        case .output:
            return Theme.terminalText
        case .error:
            return Theme.terminalError
        case .system:
            return Theme.terminalSystem
        case .aiUser:
            return Theme.aiUser
        case .aiResponse:
            return Theme.aiResponse
        }
    }
}

struct EmptyTerminalView: View {
    let onNewTab: () -> Void

    var body: some View {
        VStack(spacing: Theme.paddingLarge) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(Theme.tertiaryText)

            Text("No Terminal Open")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Open a new tab to connect to a device")
                .foregroundStyle(Theme.secondaryText)

            Button {
                onNewTab()
            } label: {
                Label("New Terminal Tab", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Text("⌘T to open new tab • ⌘W to close tab")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminalBackground)
    }
}

struct DevicePickerSheet: View {
    @Environment(SSHService.self) private var sshService
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDeviceId: UUID?
    @State private var password = ""
    @State private var isConnecting = false
    @State private var error: String?

    var selectedDevice: Device? {
        guard let id = selectedDeviceId else { return nil }
        return sshService.devices.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connect to Device")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.paddingLarge)

            Divider()

            // Device List
            if sshService.devices.isEmpty {
                VStack(spacing: Theme.paddingMedium) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.tertiaryText)

                    Text("No devices registered")
                        .foregroundStyle(Theme.secondaryText)

                    Text("Add devices first from the Devices section")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sshService.devices, selection: $selectedDeviceId) { device in
                    HStack {
                        Image(systemName: device.category.icon)
                            .foregroundStyle(Theme.secondaryText)

                        VStack(alignment: .leading) {
                            Text(device.displayName)
                                .fontWeight(.medium)

                            Text(device.connectionString)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }

                        Spacer()

                        if sshService.isConnected(deviceId: device.id) {
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(Theme.success)
                        }
                    }
                    .tag(device.id)
                }
                .listStyle(.inset)
            }

            // Password field (if device selected and not connected)
            if let device = selectedDevice, !sshService.isConnected(deviceId: device.id) {
                Divider()

                VStack(spacing: Theme.paddingMedium) {
                    if device.authMethod == .password {
                        SecureField("Password for \(device.username)", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }
                }
                .padding(Theme.paddingMedium)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDevice == nil || isConnecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.paddingLarge)
        }
        .frame(width: 450, height: 500)
        .background(Theme.secondaryBackground)
    }

    private func connect() {
        guard let device = selectedDevice else { return }

        // If already connected, just open tab
        if sshService.isConnected(deviceId: device.id) {
            let tab = tabManager.createTab(for: device)
            tabManager.updateTabConnection(id: tab.id, isConnected: true)
            dismiss()
            return
        }

        isConnecting = true
        error = nil

        Task {
            do {
                try await sshService.connect(to: device, password: password)
                let tab = tabManager.createTab(for: device)
                tabManager.updateTabConnection(id: tab.id, isConnected: true)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

// MARK: - AI Chat Panel

/// A standalone AI chat panel that lives beside the terminal.
/// Suggests commands with copy and execute buttons.
struct AIChatPanel: View {
    let tabId: UUID

    @Environment(SSHService.self) private var sshService
    @Environment(TabManager.self) private var tabManager
    @Environment(AIService.self) private var aiService
    @Environment(DeviceMonitorService.self) private var monitor

    @State private var chatInput = ""
    @State private var messages: [AIChatMessage] = []
    @FocusState private var isInputFocused: Bool

    private var tab: SSHTab {
        tabManager.tabs.first { $0.id == tabId } ?? SSHTab(deviceId: UUID(), title: "")
    }

    private var device: Device? {
        sshService.deviceById(tab.deviceId)
    }

    private var deviceInfo: String {
        guard let device = device else { return "unknown" }
        return "\(device.displayName) (\(device.connectionString))"
    }

    private var systemStats: String {
        guard let metrics = monitor.getLatestMetrics(for: tab.deviceId) else { return "" }
        var parts = [
            String(format: "CPU: %.0f%%", metrics.cpuUsage),
            String(format: "RAM: %.1f/%.1fGB", metrics.memoryUsedGB, metrics.memoryTotalGB),
        ]
        if let temp = metrics.temperature {
            parts.append(String(format: "Temp: %.0f°C", temp))
        }
        return parts.joined(separator: " | ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Panel Header
            HStack(spacing: Theme.paddingSmall) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.purple)
                Text("AI Assistant")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if let device = device {
                    Text(device.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(Theme.paddingMedium)
            .background(Color.purple.opacity(0.06))

            Divider().background(Color.purple.opacity(0.2))

            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.paddingMedium) {
                        if messages.isEmpty {
                            aiWelcomeView
                        }

                        ForEach(messages) { message in
                            AIChatBubble(message: message) { command in
                                copyToClipboard(command)
                            } onExecute: { command in
                                executeInTerminal(command)
                            }
                            .id(message.id)
                        }
                    }
                    .padding(Theme.paddingMedium)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().background(Color.purple.opacity(0.2))

            // Chat Input
            HStack(spacing: Theme.paddingSmall) {
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.purple)

                TextField("Ask about commands, troubleshoot...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                if aiService.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                if !chatInput.isEmpty {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.paddingMedium)
            .background(Color.purple.opacity(0.04))
        }
        .background(Theme.secondaryBackground)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Welcome View

    private var aiWelcomeView: some View {
        VStack(spacing: Theme.paddingMedium) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.purple.opacity(0.5))

            Text("AI Assistant")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            Text("Ask me anything about this device.\nI'll suggest commands you can copy or execute directly.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)

            // Quick action chips
            VStack(spacing: 6) {
                quickChip("Show disk usage")
                quickChip("List running processes")
                quickChip("Check memory usage")
                quickChip("Show network connections")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.paddingLarge)
    }

    private func quickChip(_ text: String) -> some View {
        Button {
            chatInput = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        chatInput = ""

        messages.append(AIChatMessage(role: .user, text: text))

        let recentOutput = tab.terminalOutput.suffix(30).map(\.content).joined(separator: "\n")
        let info = deviceInfo
        let stats = systemStats

        Task {
            guard let response = await aiService.chat(
                question: text,
                deviceInfo: info,
                systemStats: stats,
                recentOutput: recentOutput
            ) else {
                messages.append(AIChatMessage(
                    role: .assistant,
                    text: aiService.lastError ?? "Could not get a response.",
                    command: nil
                ))
                return
            }

            messages.append(AIChatMessage(
                role: .assistant,
                text: response.explanation,
                command: response.command.isEmpty ? nil : response.command,
                isSafeCommand: response.autoExecute
            ))
        }
    }

    private func copyToClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func executeInTerminal(_ command: String) {
        tabManager.appendCommand(to: tab.id, command: command)

        Task {
            do {
                let output = try await sshService.executeCommand(command, on: tab.deviceId)
                tabManager.appendResponse(to: tab.id, output: output)

                // Show execution confirmation in chat
                let preview = output.prefix(200)
                messages.append(AIChatMessage(
                    role: .system,
                    text: "Executed `\(command)` in terminal.\(preview.isEmpty ? "" : "\n\(preview)\(output.count > 200 ? "..." : "")")"
                ))
            } catch {
                tabManager.appendResponse(to: tab.id, output: error.localizedDescription, isError: true)
                messages.append(AIChatMessage(
                    role: .system,
                    text: "Error: \(error.localizedDescription)"
                ))
            }
        }
    }
}

// MARK: - AI Chat Message Model

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    var command: String?
    var isSafeCommand: Bool = false
    let timestamp = Date()

    enum Role {
        case user
        case assistant
        case system
    }
}

// MARK: - AI Chat Bubble View

struct AIChatBubble: View {
    let message: AIChatMessage
    let onCopy: (String) -> Void
    let onExecute: (String) -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            // Role label
            HStack(spacing: 4) {
                if message.role != .user {
                    Image(systemName: message.role == .assistant ? "sparkle" : "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(message.role == .assistant ? .purple : Theme.terminalSystem)
                }
                Text(roleLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                Text(message.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText.opacity(0.6))
            }

            // Message bubble
            VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)

                // Command suggestion with buttons
                if let command = message.command, !command.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Command display
                        Text(command)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(Theme.paddingSmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)

                        // Action buttons
                        HStack(spacing: Theme.paddingSmall) {
                            Button {
                                onCopy(command)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                onExecute(command)
                            } label: {
                                Label("Execute", systemImage: "play.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(message.isSafeCommand ? .green : .orange)
                            .controlSize(.small)

                            if !message.isSafeCommand {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .help("This command may modify system state")
                            }
                        }
                    }
                }
            }
            .padding(Theme.paddingMedium)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(bubbleBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "AI"
        case .system: return "System"
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return Theme.aiResponse
        case .system: return Theme.terminalSystem
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.15)
        case .assistant: return Color.purple.opacity(0.08)
        case .system: return Theme.tertiaryBackground.opacity(0.5)
        }
    }

    private var bubbleBorder: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.2)
        case .assistant: return Color.purple.opacity(0.15)
        case .system: return Theme.border
        }
    }
}

#Preview {
    TerminalView()
        .environment(SSHService())
        .environment(TabManager())
        .environment(DeviceMonitorService())
        .environment(AIService())
        .frame(width: 1100, height: 600)
}
