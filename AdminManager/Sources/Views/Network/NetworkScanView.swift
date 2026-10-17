import SwiftUI

struct NetworkScanView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(NetworkScanService.self) private var networkService

    @State private var scanSource: ScanSource = .local
    @State private var selectedRemoteDeviceId: UUID?
    @State private var showAddDeviceSheet = false
    @State private var prefillHostname = ""
    @State private var sortOrder = [KeyPathComparator(\NetworkHost.ip)]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Theme.paddingMedium) {
                // Scan Source
                Picker("Source", selection: $scanSource) {
                    Text("Local").tag(ScanSource.local)
                    Text("Remote").tag(ScanSource.remote)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                if scanSource == .remote {
                    Picker("Device", selection: $selectedRemoteDeviceId) {
                        Text("Select device...").tag(nil as UUID?)
                        ForEach(sshService.devices.filter { sshService.connectedDevices.contains($0.id) }) { device in
                            Text(device.displayName).tag(device.id as UUID?)
                        }
                    }
                    .frame(width: 200)
                }

                Button {
                    startScan()
                } label: {
                    HStack(spacing: 4) {
                        if networkService.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(networkService.isScanning ? "Scanning..." : "Scan")
                    }
                    .padding(.horizontal, Theme.paddingMedium)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(networkService.isScanning || (scanSource == .remote && selectedRemoteDeviceId == nil))

                Spacer()

                if !networkService.hosts.isEmpty {
                    let matched = networkService.hosts.filter { $0.matchedDeviceId != nil }.count
                    Text("\(networkService.hosts.count) hosts found (\(matched) matched)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                if !networkService.scanProgress.isEmpty {
                    Text(networkService.scanProgress)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(Theme.paddingMedium)
            .background(Theme.secondaryBackground)

            Divider()
                .background(Theme.divider)

            // Results Table
            if networkService.hosts.isEmpty && !networkService.isScanning {
                emptyState
            } else {
                hostTable
            }
        }
        .sheet(isPresented: $showAddDeviceSheet) {
            AddDeviceFromScanSheet(hostname: prefillHostname)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.paddingLarge) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)

            Text("No Scan Results")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Click \"Scan\" to discover devices on your network")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var hostTable: some View {
        Table(networkService.hosts, sortOrder: $sortOrder) {
            TableColumn("Status") { host in
                HStack(spacing: 6) {
                    Circle()
                        .fill(host.matchedDeviceId != nil ? Theme.success : Theme.secondaryText.opacity(0.5))
                        .frame(width: 8, height: 8)

                    if host.matchedDeviceId != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.success)
                    }
                }
            }
            .width(50)

            TableColumn("IP Address", value: \.ip) { host in
                Text(host.ip)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Hostname") { host in
                Text(host.hostname.isEmpty ? "—" : host.hostname)
                    .foregroundStyle(host.hostname.isEmpty ? Theme.tertiaryText : Theme.text)
            }
            .width(min: 140, ideal: 200)

            TableColumn("MAC Address") { host in
                Text(host.mac)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
            }
            .width(min: 130, ideal: 160)

            TableColumn("Vendor") { host in
                if host.vendor.isEmpty {
                    Text("—")
                        .foregroundStyle(Theme.tertiaryText)
                } else {
                    Text(host.vendor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Theme.accent)
                        .font(.caption)
                }
            }
            .width(min: 100, ideal: 120)

            TableColumn("Actions") { host in
                if host.matchedDeviceId == nil {
                    Button {
                        prefillHostname = host.ip
                        showAddDeviceSheet = true
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.accent)
                } else {
                    Text("Managed")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
            }
            .width(80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func startScan() {
        Task {
            if scanSource == .local {
                await networkService.scanLocalNetwork(devices: sshService.devices)
            } else if let deviceId = selectedRemoteDeviceId {
                await networkService.scanRemoteNetwork(deviceId: deviceId, sshService: sshService, devices: sshService.devices)
            }
        }
    }
}

// MARK: - Add Device From Scan Sheet

struct AddDeviceFromScanSheet: View {
    @Environment(SSHService.self) private var sshService
    @Environment(\.dismiss) private var dismiss

    let hostname: String

    @State private var name = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var category = DeviceCategory.server
    @State private var authMethod = AuthMethod.password

    var isValid: Bool {
        !username.isEmpty && Int(port) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Discovered Device")
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

            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    // Pre-filled info
                    HStack {
                        Image(systemName: "network")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Discovered Host")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Text(hostname)
                                .font(.headline)
                                .font(.system(.body, design: .monospaced))
                        }

                        Spacer()
                    }
                    .padding(Theme.paddingMedium)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))

                    GroupBox("Device Information") {
                        VStack(spacing: Theme.paddingMedium) {
                            FormField(label: "Name", placeholder: "My Server", text: $name)

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
                        }
                        .padding(Theme.paddingSmall)
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
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.paddingLarge)
        }
        .frame(width: 480, height: 500)
        .background(Theme.secondaryBackground)
    }

    private func addDevice() {
        guard let portNumber = Int(port) else { return }

        if sshService.hasDevice(hostname: hostname, port: portNumber) {
            return
        }

        let device = Device(
            name: name.isEmpty ? hostname : name,
            hostname: hostname,
            port: portNumber,
            username: username,
            authMethod: authMethod,
            category: category
        )

        sshService.addDevice(device)
        dismiss()
    }
}
