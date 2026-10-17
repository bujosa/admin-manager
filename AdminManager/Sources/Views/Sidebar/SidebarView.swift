import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    @Environment(SSHService.self) private var sshService

    var body: some View {
        VStack(spacing: 0) {
            // Logo/Title
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Admin Manager").font(.headline.weight(.semibold))
                    Text("BETA").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, Theme.paddingLarge)
            .frame(maxWidth: .infinity)

            Divider()
                .background(Theme.divider)

            // Navigation Items
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(NavigationItem.allCases) { item in
                        SidebarButton(
                            item: item,
                            isSelected: selectedItem == item
                        ) {
                            withAnimation(Theme.animationFast) {
                                selectedItem = item
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.paddingSmall)
                .padding(.top, Theme.paddingMedium)
            }

            Divider()
                .background(Theme.divider)

            // Connected Devices Quick Access
            VStack(alignment: .leading, spacing: Theme.paddingSmall) {
                Text("CONNECTED")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, Theme.paddingMedium)

                if sshService.activeSessions.isEmpty {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(Theme.tertiaryText)
                        Text("No devices connected")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.horizontal, Theme.paddingMedium)
                    .padding(.vertical, Theme.paddingSmall)
                } else {
                    ForEach(sshService.devices.filter { sshService.isConnected(deviceId: $0.id) }) { device in
                        ConnectedDeviceRow(device: device)
                    }
                }
            }
            .padding(.vertical, Theme.paddingMedium)

            Divider()
                .background(Theme.divider)

            // Stats Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sshService.devices.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Devices")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(sshService.activeSessions.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.success)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(Theme.paddingMedium)
        }
        .frame(width: Theme.sidebarWidth)
        .background(Theme.secondaryBackground)
    }
}

struct SidebarButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.paddingMedium) {
                Image(systemName: item.icon)
                    .font(.body)
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(.body)

                Spacer()
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, Theme.paddingSmall)
            .background(
                isSelected
                    ? Theme.accent.opacity(0.2)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Theme.accent : Theme.text)
    }
}

struct ConnectedDeviceRow: View {
    let device: Device

    var body: some View {
        HStack(spacing: Theme.paddingSmall) {
            Circle()
                .fill(Theme.success)
                .frame(width: 8, height: 8)

            DeviceIconView(category: device.category, size: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(device.displayName)
                        .font(.caption)
                        .lineLimit(1)

                    Text("(\(device.category.rawValue))")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .showDeviceDetail, object: device.id)
        }
    }
}

#Preview {
    SidebarView(selectedItem: .constant(.dashboard))
        .environment(SSHService())
        .frame(height: 600)
}
