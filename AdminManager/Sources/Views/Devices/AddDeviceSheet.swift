import SwiftUI

struct AddDeviceSheet: View {
    @Environment(SSHService.self) private var sshService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod = AuthMethod.password
    @State private var category = DeviceCategory.server
    @State private var notes = ""
    @State private var sshKeyPath = "~/.ssh/id_rsa"

    @State private var isValidating = false
    @State private var error: String?

    var isValid: Bool {
        !hostname.isEmpty && !username.isEmpty && Int(port) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add New Device")
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
                    // Quick Add This Mac
                    Button {
                        addThisMac()
                    } label: {
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add This Mac")
                                    .font(.headline)
                                Text(Host.current().localizedName ?? "localhost")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(Theme.paddingMedium)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                        Text("or add manually")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                    }

                    // Basic Info
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

                    // Authentication
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

                    // Notes
                    GroupBox("Notes (Optional)") {
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                    }

                    // Error
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

                Button("Add Device") {
                    addDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isValidating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.paddingLarge)
        }
        .frame(width: 500, height: 600)
        .background(Theme.secondaryBackground)
    }

    private func addDevice() {
        guard let portNumber = Int(port) else {
            error = "Invalid port number"
            return
        }

        if sshService.hasDevice(hostname: hostname, port: portNumber) {
            error = "A device with hostname \(hostname):\(portNumber) already exists"
            return
        }

        let device = Device(
            name: name.isEmpty ? hostname : name,
            hostname: hostname,
            port: portNumber,
            username: username,
            authMethod: authMethod,
            category: category,
            notes: notes
        )

        sshService.addDevice(device)
        dismiss()
    }

    private func addThisMac() {
        if sshService.hasDevice(hostname: "localhost", port: 22) {
            error = "This Mac has already been added"
            return
        }

        let macName = Host.current().localizedName ?? "My Mac"
        let currentUser = NSUserName()

        let device = Device(
            name: macName,
            hostname: "localhost",
            port: 22,
            username: currentUser,
            authMethod: .password,
            category: .laptop,
            notes: "This Mac - Added automatically"
        )

        sshService.addDevice(device)
        dismiss()
    }
}

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    AddDeviceSheet()
        .environment(SSHService())
}
