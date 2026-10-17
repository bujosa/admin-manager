import SwiftUI

struct SettingsView: View {
    @Environment(SSHService.self) private var sshService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SSHSettingsView()
                .tabItem {
                    Label("SSH", systemImage: "terminal")
                }

            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkle")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            DeviceCommandsSettingsView()
                .tabItem {
                    Label("Commands", systemImage: "terminal.fill")
                }
        }
        .frame(width: 600, height: 550)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30.0
    @AppStorage("autoConnect") private var autoConnect = true
    @AppStorage("showNotifications") private var showNotifications = true

    var body: some View {
        Form {
            Section("Monitoring") {
                HStack {
                    Text("Refresh Interval")
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .frame(width: 150)
                }

                Toggle("Auto-connect to last devices", isOn: $autoConnect)

                Toggle("Show system notifications", isOn: $showNotifications)
            }

            Section("Data") {
                Button("Clear Metrics History") {
                    // Clear action
                }

                Button("Export Devices", role: .none) {
                    // Export action
                }

                Button("Import Devices", role: .none) {
                    // Import action
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SSHSettingsView: View {
    @Environment(SSHService.self) private var sshService

    @State private var defaultPort = "22"
    @State private var connectionTimeout = "30"
    @State private var keepAliveInterval = "60"
    @State private var defaultKeyPath = "~/.ssh/id_rsa"
    @State private var knownHostsPath = "~/.ssh/known_hosts"

    var body: some View {
        Form {
            Section("Connection Defaults") {
                HStack {
                    Text("Default Port")
                    Spacer()
                    TextField("22", text: $defaultPort)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Connection Timeout (seconds)")
                    Spacer()
                    TextField("30", text: $connectionTimeout)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Keep Alive Interval (seconds)")
                    Spacer()
                    TextField("60", text: $keepAliveInterval)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("SSH Keys") {
                HStack {
                    Text("Default Key Path")
                    Spacer()
                    TextField("~/.ssh/id_rsa", text: $defaultKeyPath)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        // File picker
                    }
                }

                HStack {
                    Text("Known Hosts Path")
                    Spacer()
                    TextField("~/.ssh/known_hosts", text: $knownHostsPath)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("SSH Agent") {
                Button("Test SSH Agent Connection") {
                    // Test agent
                }

                Button("List Available Keys") {
                    // List keys
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadConfig()
        }
        .onChange(of: defaultPort) { _, _ in saveConfig() }
        .onChange(of: connectionTimeout) { _, _ in saveConfig() }
        .onChange(of: keepAliveInterval) { _, _ in saveConfig() }
        .onChange(of: defaultKeyPath) { _, _ in saveConfig() }
        .onChange(of: knownHostsPath) { _, _ in saveConfig() }
    }

    private func loadConfig() {
        defaultPort = String(sshService.config.defaultPort)
        connectionTimeout = String(sshService.config.connectionTimeout)
        keepAliveInterval = String(sshService.config.keepAliveInterval)
        defaultKeyPath = sshService.config.defaultKeyPath
        knownHostsPath = sshService.config.knownHostsPath
    }

    private func saveConfig() {
        sshService.config.defaultPort = Int(defaultPort) ?? 22
        sshService.config.connectionTimeout = Int(connectionTimeout) ?? 30
        sshService.config.keepAliveInterval = Int(keepAliveInterval) ?? 60
        sshService.config.defaultKeyPath = defaultKeyPath
        sshService.config.knownHostsPath = knownHostsPath
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("showLineNumbers") private var showLineNumbers = true
    @AppStorage("terminalColorScheme") private var terminalColorScheme = "default"

    var body: some View {
        Form {
            Section("Terminal") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $terminalFontSize, in: 10...24, step: 1)
                        .frame(width: 150)
                    Text("\(Int(terminalFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 50)
                }

                Toggle("Show Line Numbers", isOn: $showLineNumbers)

                Picker("Color Scheme", selection: $terminalColorScheme) {
                    Text("Default (Green)").tag("default")
                    Text("Amber").tag("amber")
                    Text("White").tag("white")
                    Text("Cyan").tag("cyan")
                }
            }

            Section("Window") {
                Toggle("Remember Window Position", isOn: .constant(true))
                Toggle("Start Maximized", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SSHConfigView: View {
    @Environment(SSHService.self) private var sshService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH Configuration")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Manage your SSH settings and keys")
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()
            }
            .padding(Theme.paddingLarge)

            // Config Form
            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    GroupBox("Connection Defaults") {
                        VStack(spacing: Theme.paddingMedium) {
                            ConfigRow(label: "Default Port", value: "\(sshService.config.defaultPort)")
                            ConfigRow(label: "Connection Timeout", value: "\(sshService.config.connectionTimeout)s")
                            ConfigRow(label: "Keep Alive Interval", value: "\(sshService.config.keepAliveInterval)s")
                        }
                        .padding(Theme.paddingSmall)
                    }

                    GroupBox("SSH Keys") {
                        VStack(spacing: Theme.paddingMedium) {
                            ConfigRow(label: "Default Key Path", value: sshService.config.defaultKeyPath)
                            ConfigRow(label: "Known Hosts", value: sshService.config.knownHostsPath)
                        }
                        .padding(Theme.paddingSmall)
                    }

                    GroupBox("Registered Devices (\(sshService.devices.count))") {
                        VStack(spacing: Theme.paddingSmall) {
                            ForEach(sshService.devices) { device in
                                HStack {
                                    Image(systemName: device.category.icon)
                                        .foregroundStyle(Theme.secondaryText)

                                    Text(device.displayName)

                                    Spacer()

                                    Text(device.connectionString)
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)

                                    Text(device.authMethod.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.tertiaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .padding(.vertical, 4)

                                if device.id != sshService.devices.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(Theme.paddingSmall)
                    }
                }
                .padding(Theme.paddingLarge)
            }
        }
        .background(Theme.background)
    }
}

struct AISettingsView: View {
    @AppStorage("aiProvider") private var aiProviderRaw = "none"
    @AppStorage("aiCLIPath") private var aiCLIPath = ""
    @SecureStorage("aiAPIKey") private var aiAPIKey: String

    @State private var testResult: Bool?
    @State private var isTesting = false
    @State private var testError: String?

    private var provider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .none
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI Provider", selection: $aiProviderRaw) {
                    ForEach(AIProvider.allCases) { p in
                        Label(p.label, systemImage: p.icon).tag(p.rawValue)
                    }
                }
                .onChange(of: aiProviderRaw) {
                    testResult = nil
                    testError = nil
                    let newProvider = AIProvider(rawValue: aiProviderRaw) ?? .none
                    if newProvider.isCLI {
                        aiCLIPath = newProvider.defaultPath
                    }
                }
            }

            if provider.isCLI {
                Section("CLI Configuration") {
                    HStack {
                        Text("Executable Path")
                        Spacer()
                        TextField("/opt/homebrew/bin/...", text: $aiCLIPath)
                            .frame(width: 220)
                            .textFieldStyle(.roundedBorder)
                    }

                }
            }

            if provider.isAPI {
                Section("API Configuration") {
                    HStack {
                        Text("API Key")
                        Spacer()
                        SecureField("sk-...", text: $aiAPIKey)
                            .frame(width: 220)
                            .textFieldStyle(.roundedBorder)
                    }

                }
            }

            if provider != .none {
                Section("Model") {
                    AIModelSelector(provider: provider).id(provider.rawValue)
                }
                Section("Test") {
                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            Label("Test Connection", systemImage: "bolt.fill")
                        }
                        .disabled(isTesting || (provider.isAPI && aiAPIKey.isEmpty) || (provider.isCLI && aiCLIPath.isEmpty))

                        Spacer()

                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let result = testResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                            Text(result ? "Connected" : "Failed")
                                .font(.caption)
                                .foregroundStyle(result ? .green : .red)
                        }
                    }

                    if let error = testError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Features") {
                    Text("Type **ai** followed by a question in the terminal to get command suggestions from AI.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        testError = nil

        let service = AIService()
        Task {
            let result = await service.testConnection()
            isTesting = false
            testResult = result
            testError = service.lastError
        }
    }
}

// MARK: - Device Commands Settings

struct DeviceCommandsSettingsView: View {
    @State private var selectedCategory: DeviceCategory = .server
    @State private var profiles: [DeviceCategory: DeviceCommandProfile] = [:]
    @State private var editingProfile: DeviceCommandProfile?
    @State private var hasChanges = false

    var body: some View {
        HSplitView {
            // Category list
            List(DeviceCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .frame(width: 20)
                    Text(category.rawValue)
                        .font(.callout)
                    Spacer()
                    if profiles[category] != nil {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .tag(category)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, maxWidth: 180)

            // Command editor
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: selectedCategory.icon)
                        .foregroundStyle(.secondary)
                    Text(selectedCategory.rawValue)
                        .font(.headline)
                    Spacer()

                    if profiles[selectedCategory] != nil {
                        Button("Reset to Default") {
                            profiles.removeValue(forKey: selectedCategory)
                            editingProfile = effectiveProfile
                            saveProfiles()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                if let profile = editingProfile {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            commandSection(title: "Clean Cache", command: profile.cleanCache) { newValue in
                                editingProfile?.cleanCache = newValue
                                markChanged()
                            }

                            commandSection(title: "System Info", command: profile.systemInfo) { newValue in
                                editingProfile?.systemInfo = newValue
                                markChanged()
                            }

                            commandSection(title: "List Processes", command: profile.listProcesses) { newValue in
                                editingProfile?.listProcesses = newValue
                                markChanged()
                            }

                            commandSection(title: "List Ports", command: profile.listPorts) { newValue in
                                editingProfile?.listPorts = newValue
                                markChanged()
                            }
                        }
                    }
                }

                if hasChanges {
                    HStack {
                        Spacer()
                        Button("Save Changes") {
                            saveCurrentProfile()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            profiles = DeviceCommandProfileStore.loadOverrides()
            editingProfile = effectiveProfile
        }
        .onChange(of: selectedCategory) {
            editingProfile = effectiveProfile
            hasChanges = false
        }
    }

    private var effectiveProfile: DeviceCommandProfile {
        profiles[selectedCategory] ?? DeviceCommandProfile.defaultProfile(for: selectedCategory)
    }

    private func commandSection(title: String, command: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { command },
                set: { onChange($0) }
            ))
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 80, maxHeight: 120)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func markChanged() {
        hasChanges = true
    }

    private func saveCurrentProfile() {
        guard var profile = editingProfile else { return }
        profile.category = selectedCategory
        profiles[selectedCategory] = profile
        saveProfiles()
        hasChanges = false
    }

    private func saveProfiles() {
        DeviceCommandProfileStore.saveOverrides(profiles)
    }
}

struct ConfigRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    SettingsView()
        .environment(SSHService())
}
