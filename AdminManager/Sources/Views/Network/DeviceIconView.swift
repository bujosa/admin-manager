import SwiftUI

struct DeviceIconView: View {
    let category: DeviceCategory
    var size: CGFloat = 32

    var body: some View {
        Group {
            switch category {
            case .raspberryPi:
                raspberryPiIcon
            case .jetsonNano:
                jetsonIcon(label: "NANO")
            case .jetsonThor:
                jetsonIcon(label: "THOR")
            default:
                sfSymbolIcon
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - SF Symbol Icon (Apple devices, servers, etc.)

    private var sfSymbolIcon: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.6))
            .foregroundStyle(categoryColor)
    }

    // MARK: - Raspberry Pi (PCB board with GPIO pins)

    private var raspberryPiIcon: some View {
        ZStack {
            // PCB board
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(Color.green.opacity(0.8))
                .frame(width: size * 0.75, height: size * 0.85)

            // GPIO pins (top row)
            HStack(spacing: size * 0.04) {
                ForEach(0..<6, id: \.self) { _ in
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: size * 0.06, height: size * 0.06)
                }
            }
            .offset(y: -size * 0.38)

            // Chip in center
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(Color.black.opacity(0.6))
                .frame(width: size * 0.3, height: size * 0.25)

            // Pi symbol
            Text("Pi")
                .font(.system(size: size * 0.15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Jetson (NVIDIA board with heatsink)

    private func jetsonIcon(label: String) -> some View {
        ZStack {
            // Board
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(Color.black.opacity(0.8))
                .frame(width: size * 0.8, height: size * 0.85)

            // Green NVIDIA accent stripe
            Rectangle()
                .fill(Color.green)
                .frame(width: size * 0.8, height: size * 0.06)
                .offset(y: -size * 0.3)

            // Heatsink fins
            VStack(spacing: size * 0.04) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: size * 0.5, height: size * 0.04)
                }
            }
            .offset(y: -size * 0.08)

            // Label
            Text(label)
                .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green)
                .offset(y: size * 0.25)
        }
    }

    // MARK: - Color

    private var categoryColor: Color {
        switch category.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ForEach([DeviceCategory.macMini, .macStudio, .macbookAir, .iMac], id: \.self) { cat in
                VStack {
                    DeviceIconView(category: cat, size: 48)
                    Text(cat.rawValue).font(.caption2)
                }
            }
        }
        HStack(spacing: 20) {
            ForEach([DeviceCategory.raspberryPi, .jetsonNano, .jetsonThor, .server], id: \.self) { cat in
                VStack {
                    DeviceIconView(category: cat, size: 48)
                    Text(cat.rawValue).font(.caption2)
                }
            }
        }
    }
    .padding()
}
