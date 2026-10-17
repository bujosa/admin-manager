import SwiftUI

@main
struct AdminManagerApp: App {
    @State private var sshService = SSHService()
    @State private var deviceMonitor = DeviceMonitorService()
    @State private var tabManager = TabManager()
    @State private var aiService = AIService()
    @State private var adminService = DeviceAdminService()
    @State private var networkScanService = NetworkScanService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .credentialStorageAlert()
                .environment(sshService)
                .environment(deviceMonitor)
                .environment(tabManager)
                .environment(aiService)
                .environment(adminService)
                .environment(networkScanService)
                .frame(minWidth: 1200, minHeight: 700)
                .preferredColorScheme(.dark)
                .onAppear {
                    configureWindow()
                    startupSequence()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Devices") {
                Button("Add Device") {
                    NotificationCenter.default.post(name: .addDevice, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Refresh All") {
                    NotificationCenter.default.post(name: .refreshDevices, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .credentialStorageAlert()
                .environment(sshService)
        }
    }

    private func startupSequence() {
        // Default to true if key not set yet (first launch)
        if UserDefaults.standard.object(forKey: "autoConnect") == nil {
            UserDefaults.standard.set(true, forKey: "autoConnect")
        }
        let autoConnect = UserDefaults.standard.bool(forKey: "autoConnect")
        guard autoConnect else { return }
        Task {
            await sshService.autoConnectDevices()
            if !sshService.activeSessions.isEmpty {
                deviceMonitor.startMonitoring(sshService: sshService)
            }
        }
    }

    private func configureWindow() {
        if let window = NSApplication.shared.windows.first {
            window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true)
            window.center()
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
        }
    }
}

extension Notification.Name {
    static let newTab = Notification.Name("newTab")
    static let closeTab = Notification.Name("closeTab")
    static let addDevice = Notification.Name("addDevice")
    static let refreshDevices = Notification.Name("refreshDevices")
    static let showDeviceDetail = Notification.Name("showDeviceDetail")
    static let openTerminal = Notification.Name("openTerminal")
}
