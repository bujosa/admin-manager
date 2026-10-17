import Foundation

/// Remote operating system, independent of the Mac running AdminManager.
enum RemotePlatform: String, Sendable, CaseIterable {
    case linux, macOS, windows, freeBSD, unsupported

    var displayName: String {
        switch self {
        case .linux: return "Linux / ZimaOS"
        case .macOS: return "macOS"
        case .windows: return "Windows"
        case .freeBSD: return "FreeBSD"
        case .unsupported: return "Unrecognized system"
        }
    }

    var supportsInventory: Bool { [.linux, .macOS, .windows].contains(self) }

    func hasValidMetrics(_ output: String) -> Bool {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let pair = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if pair.count == 2 { values[pair[0]] = pair[1] }
        }
        let expected = self == .linux ? "Linux" : self == .macOS ? "Darwin" : self == .windows ? "Windows" : nil
        guard let expected, values["METRIC_OS"] == expected,
            let cpu = Double(values["METRIC_CPU"] ?? ""), cpu.isFinite, cpu >= 0,
            let total = UInt64(values["METRIC_MEM_TOTAL"] ?? ""), total > 0,
            UInt64(values["METRIC_MEM_USED"] ?? "") != nil
        else { return false }
        return true
    }

    static func fromUname(_ output: String) -> RemotePlatform {
        // Login banners must not turn into a platform or an executable command.
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if lines.contains("Linux") { return .linux }
        if lines.contains("Darwin") { return .macOS }
        if lines.contains("FreeBSD") { return .freeBSD }
        return .unsupported
    }

    static let windowsDetectionCommand = PowerShellCommand.encode(
        "if ($env:OS -eq 'Windows_NT') { Write-Output 'ADMIN_PLATFORM_WINDOWS' }")

    var inventoryCommand: String? {
        switch self {
        case .linux: return LinuxInventoryProbe.script
        case .macOS: return MacInventoryProbe.script
        case .windows: return WindowsInventoryProbe.command
        default: return nil
        }
    }

    func parseInventory(_ output: String) throws -> StorageInventory {
        switch self {
        case .linux: return try StorageInventoryParser.parse(output)
        case .macOS: return try MacInventoryParser.parse(output)
        case .windows: return try WindowsInventoryParser.parse(output)
        default: throw InventoryError.unsupported
        }
    }
}

enum PowerShellCommand {
    /// A fixed script encoded for either cmd.exe or PowerShell as the SSH shell.
    /// Does not bypass execution policy, request elevation or load user profiles.
    static func encode(_ script: String) -> String {
        "powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand \(Data(script.utf16LittleEndianBytes).base64EncodedString())"
    }
}

extension String {
    fileprivate var utf16LittleEndianBytes: [UInt8] {
        utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
    }
}
