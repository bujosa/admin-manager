import SwiftUI

struct ContentView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(DeviceMonitorService.self) private var monitor
    @Environment(TabManager.self) private var tabManager

    @State private var selectedNavItem: NavigationItem = .dashboard
    @State private var detailDeviceId: UUID?
    @State private var selectedNetworkTab: NetworkTab = .scanner

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(selectedItem: $selectedNavItem)

            Divider()
                .background(Theme.divider)

            // Main Content
            if let deviceId = detailDeviceId, let device = sshService.deviceById(deviceId) {
                DeviceDetailView(device: device) {
                    withAnimation(Theme.animationMedium) {
                        detailDeviceId = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .onChange(of: selectedNavItem) {
            detailDeviceId = nil
        }
        .onChange(of: sshService.connectedDevices.count) {
            if !sshService.connectedDevices.isEmpty && !monitor.isMonitoring {
                monitor.startMonitoring(sshService: sshService)
            } else if sshService.connectedDevices.isEmpty {
                monitor.stopMonitoring()
            }
        }
        .onAppear {
            if !sshService.activeSessions.isEmpty {
                monitor.startMonitoring(sshService: sshService)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDeviceDetail)) { notification in
            if let deviceId = notification.object as? UUID {
                withAnimation(Theme.animationMedium) {
                    detailDeviceId = deviceId
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTerminal)) { _ in
            withAnimation(Theme.animationMedium) {
                detailDeviceId = nil
                selectedNavItem = .terminal
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedNavItem {
        case .dashboard:
            DashboardView()

        case .devices:
            DeviceListView()

        case .terminal:
            TerminalView()

        case .metrics:
            MetricsView()

        case .network:
            NetworkView(selectedTab: $selectedNetworkTab)

        case .sshConfig:
            SSHConfigView()
        }
    }
}

#Preview {
    ContentView()
        .environment(SSHService())
        .environment(DeviceMonitorService())
        .environment(TabManager())
        .environment(NetworkScanService())
        .frame(width: 1200, height: 800)
}
