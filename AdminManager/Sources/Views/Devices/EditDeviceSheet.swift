import SwiftUI

struct EditDeviceSheet: View {
    @Environment(SSHService.self) private var sshService
    @Environment(\.dismiss) private var dismiss

    let device: Device

    @State private var name: String
    @State private var hostname: String
    @State private var port: String
    @State private var username: String
    @State private var authMethod: AuthMethod
    @State private var category: DeviceCategory
    @State private var notes: String
    @State private var sshKeyPath = "~/.ssh/id_rsa"
    @State private var error: String?
    @State private var showCustomCommands = false
    @State private var customCleanCache: String = ""
    @State private var customSystemInfo: String = ""
    @State private var customListProcesses: String = ""
    @State private var customListPorts: String = ""

    init(device: Device) {
        self.device = device
        _name = State(initialValue: device.name)
        _hostname = State(initialValue: device.hostname)
        _port = State(initialValue: String(device.port))
        _username = State(initialValue: device.username)
        _authMethod = State(initialValue: device.authMethod)
        _category = State(initialValue: device.category)
        _notes = State(initialValue: device.notes)
        _customCleanCache = State(initialValue: device.customCommands?.cleanCache ?? "")
        _customSystemInfo = State(initialValue: device.customCommands?.systemInfo ?? "")
        _customListProcesses = State(initialValue: device.customCommands?.listProcesses ?? "")
        _customListPorts = State(initialValue: device.customCommands?.listPorts ?? "")
        _showCustomCommands = State(initialValue: device.customCommands?.isEmpty == false)
    }

    var isValid: Bool {
        !hostname.isEmpty && !username.isEmpty && Int(port) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Device")
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
                .background(Theme.divider)

            // Form
            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    GroupBox("Device Information") {
                        VStack(spacing: Theme.paddingMedium) {
                            FormField(label: "Name", placeholder: "My Server", text: $name)

                            FormField(label: "Hostname / IP", placeholder: "192.0.2.10", text: $hostname)

                            HStack(spacing: Theme.paddingMedium) {
                                FormField(label: "Port", placeholder: "22", text: $port)
                                    .frame(width: 100)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Category")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)

                                    Picker("", selection: $category) {
                                        ForEach(DeviceCategory.allCases, id: \.self) { cat in
                                            Label(cat.rawValue, systemImage: cat.icon)
                                                .tag(cat)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(Theme.paddingSmall)
                    }

                    GroupBox("Authentication") {
                        VStack(spacing: Theme.paddingMedium) {
                            FormField(label: "Username", placeholder: "root", text: $username)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auth Method")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)

                                Picker("", selection: $authMethod) {
                                    ForEach(AuthMethod.allCases, id: \.self) { method in
                                        Label(method.rawValue, systemImage: method.icon)
                                            .tag(method)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if authMethod == .sshKey {
                                FormField(label: "SSH Key Path", placeholder: "~/.ssh/id_rsa", text: $sshKeyPath)
                            }
                        }
                        .padding(Theme.paddingSmall)
                    }

                    GroupBox("Notes (Optional)") {
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                    }

                    // Custom Commands Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                            Toggle(isOn: $showCustomCommands) {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal.fill")
                                    Text("Custom Commands")
                                        .font(.callout.bold())
                                }
                            }

                            if showCustomCommands {
                                Text("Override default commands for this specific device. Leave blank to use the category default (\(category.rawValue)).")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)

                                customCommandField(label: "Clean Cache", text: $customCleanCache, placeholder: "e.g. sync && echo 3 > /proc/sys/vm/drop_caches")
                                customCommandField(label: "System Info", text: $customSystemInfo, placeholder: "e.g. uname -a; free -h")
                                customCommandField(label: "List Processes", text: $customListProcesses, placeholder: "e.g. ps aux --sort=-%mem | head -51")
                                customCommandField(label: "List Ports", text: $customListPorts, placeholder: "e.g. ss -tlnp")
                            }
                        }
                        .padding(Theme.paddingSmall)
                    }

                    if let error = error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.error)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        }
                        .padding(Theme.paddingSmall)
                        .frame(maxWidth: .infinity)
                        .background(Theme.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    }
                }
                .padding(Theme.paddingLarge)
            }

            Divider()
                .background(Theme.divider)

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save Changes") {
                    saveDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.paddingLarge)
        }
        .frame(width: 500, height: showCustomCommands ? 750 : 550)
        .background(Theme.secondaryBackground)
    }

    private func saveDevice() {
        guard let portNumber = Int(port) else {
            error = "Invalid port number"
            return
        }

        var updated = device
        updated.name = name.isEmpty ? hostname : name
        updated.hostname = hostname
        updated.port = portNumber
        updated.username = username
        updated.authMethod = authMethod
        updated.category = category
        updated.notes = notes

        if showCustomCommands {
            updated.customCommands = DeviceCustomCommands(
                cleanCache: customCleanCache.isEmpty ? nil : customCleanCache,
                systemInfo: customSystemInfo.isEmpty ? nil : customSystemInfo,
                listProcesses: customListProcesses.isEmpty ? nil : customListProcesses,
                listPorts: customListPorts.isEmpty ? nil : customListPorts
            )
        } else {
            updated.customCommands = nil
        }

        sshService.updateDevice(updated)
        dismiss()
    }

    private func customCommandField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 50)
                .background(Theme.tertiaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
