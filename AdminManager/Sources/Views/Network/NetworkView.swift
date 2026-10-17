import SwiftUI

struct NetworkView: View {
    @Environment(SSHService.self) private var sshService
    @Environment(NetworkScanService.self) private var networkService

    @Binding var selectedTab: NetworkTab

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)

                Text("Network")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Tab Picker
                Picker("", selection: $selectedTab) {
                    ForEach(NetworkTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .padding(Theme.paddingLarge)

            Divider()
                .background(Theme.divider)

            // Content
            switch selectedTab {
            case .scanner:
                NetworkScanView()

            case .topology:
                NetworkMapView()
            }
        }
        .background(Theme.background)
    }
}
