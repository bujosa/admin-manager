import Foundation
import XCTest

@testable import SystemInventory

final class MultiOSInventoryTests: XCTestCase {
    func testMacBatteryPowerHandlesSignedAndUnsignedDischargeCurrent() {
        XCTAssertEqual(MacBatteryPower.watts(amperage: "-2000", millivolts: "15000"), 30)
        XCTAssertEqual(MacBatteryPower.watts(amperage: String(UInt64.max - 1999), millivolts: "15000"), 30)
        XCTAssertEqual(MacBatteryPower.watts(amperage: "2000", millivolts: "15000"), 30)
    }

    func testMacBatteryPowerRejectsUnavailableOrCorruptReadings() {
        XCTAssertNil(MacBatteryPower.watts(amperage: "invalid", millivolts: "15000"))
        XCTAssertNil(MacBatteryPower.watts(amperage: "-2000", millivolts: "0"))
        XCTAssertNil(MacBatteryPower.watts(amperage: String(Int64.min), millivolts: "15000"))
        XCTAssertNil(MacBatteryPower.watts(amperage: "0", millivolts: "15000"))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testMacAPFSVolumesLinkToPhysicalSSDWithoutCountingSynthesizedCapacity() throws {
        let inventory = try RemotePlatform.macOS.parseInventory(fixture("mac-multi-drive"))
        XCTAssertEqual(inventory.platform, .macOS)
        XCTAssertEqual(inventory.physicalDisks.count, 2)
        XCTAssertEqual(inventory.physicalCapacity, 3_000_000_000_000)
        let internalDisk = try XCTUnwrap(inventory.physicalDisks.first { $0.name == "disk0" })
        XCTAssertEqual(
            Set(inventory.descendants(of: internalDisk.path).map(\.name)), ["disk0s2", "disk3", "disk3s1", "disk3s2"])
        XCTAssertEqual(inventory.mountPoints(for: internalDisk), ["/System/Volumes/Data", "/Volumes/Shared media"])
        let external = try XCTUnwrap(inventory.physicalDisks.first { $0.name == "disk4" })
        XCTAssertEqual(external.mediaLabel, "SSD")
        XCTAssertTrue(inventory.mountPoints(for: external).isEmpty)
    }

    func testMacAPFSUsesPerVolumeUsageAndSharedContainerAvailability() throws {
        let inventory = try MacInventoryParser.parse(fixture("mac-multi-drive"))
        let volume = try XCTUnwrap(inventory.volumes.first { $0.mountPoint == "/System/Volumes/Data" })
        XCTAssertEqual(volume.usedBytes, 200_000_000_000)
        XCTAssertEqual(volume.availableBytes, 700_000_000_000)
        XCTAssertEqual(volume.totalBytes, 999_000_000_000)
        XCTAssertEqual(inventory.volumes.count, 2)
        XCTAssertEqual(inventory.resources.memoryAvailable, 8_589_934_592)
        XCTAssertEqual(inventory.resources.swapUsed, 1_073_741_824)
    }

    func testMacMissingClassificationDoesNotInventPhysicalCapacity() throws {
        let input = try fixture("mac-multi-drive")
        let start = try XCTUnwrap(input.range(of: "ADMIN_MAC_PHYSICAL_BEGIN"))
        let end = try XCTUnwrap(input.range(of: "ADMIN_MAC_PHYSICAL_END"))
        let partial = input.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "")
        let inventory = try MacInventoryParser.parse(partial)
        XCTAssertTrue(inventory.physicalDisks.isEmpty)
        XCTAssertNil(inventory.physicalCapacity)
        XCTAssertFalse(inventory.devices.isEmpty)
        XCTAssertTrue(inventory.warnings.contains { $0.contains("classification") })
    }

    func testMacRejectsTruncatedAndMalformedPlist() {
        XCTAssertThrowsError(try MacInventoryParser.parse("ADMIN_MAC_V1"))
        XCTAssertThrowsError(
            try MacInventoryParser.parse(
                "ADMIN_MAC_V1\nADMIN_MAC_LIST_BEGIN\ninvalid\nADMIN_MAC_LIST_END\nADMIN_MAC_END"))
    }

    func testReadOnlyMountMetadataIsPreservedAcrossMacAndLinux() throws {
        let mac = try MacInventoryParser.parse(
            fixture("mac-multi-drive").replacingOccurrences(
                of: "<key>CapacityInUse</key>", with: "<key>WritableVolume</key><false/><key>CapacityInUse</key>"))
        XCTAssertTrue(mac.volumes.allSatisfy { $0.readOnly == true })
        let linux = try StorageInventoryParser.parseVolumes(
            #"{"filesystems":[{"source":"/dev/sda1","target":"/","fstype":"ext4","options":"ro,relatime","size":100,"used":100,"avail":0}]}"#
        )
        XCTAssertEqual(linux.first?.readOnly, true)
    }

    func testWindowsDetectsUnmountedSSDAndSeparatesVHDFromPhysicalCapacity() throws {
        let inventory = try RemotePlatform.windows.parseInventory(fixture("windows-multi-drive"))
        XCTAssertEqual(inventory.platform, .windows)
        XCTAssertEqual(inventory.physicalDisks.count, 2)
        XCTAssertEqual(inventory.physicalCapacity, 3_000_000_000_000)
        let unmounted = try XCTUnwrap(inventory.physicalDisks.first { $0.path == "Disk 1" })
        XCTAssertEqual(unmounted.mediaLabel, "USB flash / SSD")
        XCTAssertTrue(inventory.mountPoints(for: unmounted).isEmpty)
        XCTAssertEqual(inventory.devices.first { $0.path == "Disk 2" }?.type, "virtual")
    }

    func testWindowsDriveLettersFolderMountsAndUnavailableMeasurements() throws {
        let inventory = try WindowsInventoryParser.parse(fixture("windows-multi-drive"))
        let disk = try XCTUnwrap(inventory.physicalDisks.first { $0.path == "Disk 0" })
        XCTAssertEqual(inventory.mountPoints(for: disk), ["D:\\", "D:\\Mounted media\\"])
        let partition = try XCTUnwrap(inventory.descendants(of: disk.path).first)
        XCTAssertEqual(inventory.volumes(for: partition).count, 2)
        XCTAssertEqual(inventory.volumes(for: partition).first?.usedBytes, 299_000_000_000)
        XCTAssertNil(inventory.volumes.first { $0.mountPoint == "E:\\" }?.usagePercent)
        XCTAssertEqual(inventory.resources.logicalCPUs, 12)
        XCTAssertEqual(inventory.resources.swapUsed, 2_147_483_648)
        XCTAssertTrue(inventory.resources.loadAverage.isEmpty)
    }

    func testWindowsStorageSpacesAndRAIDDoNotInflatePhysicalCapacity() throws {
        let input = try fixture("windows-multi-drive").replacingOccurrences(of: "NVMe", with: "Spaces")
            .replacingOccurrences(of: "USB", with: "RAID")
        let inventory = try WindowsInventoryParser.parse(input)
        XCTAssertTrue(inventory.physicalDisks.isEmpty)
        XCTAssertNil(inventory.physicalCapacity)
        XCTAssertEqual(inventory.devices.filter { $0.type == "virtual" }.count, 3)
    }

    func testWindowsRejectsWrongVersionTruncatedAndMalformedResponses() throws {
        XCTAssertThrowsError(try WindowsInventoryParser.parse("ADMIN_WINDOWS_V1\n{}"))
        XCTAssertThrowsError(try WindowsInventoryParser.parse("ADMIN_WINDOWS_V1\nnot json\nADMIN_WINDOWS_END"))
        XCTAssertThrowsError(
            try WindowsInventoryParser.parse(
                fixture("windows-multi-drive").replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")))
    }

    func testPlatformDetectionUsesExactLinesAndUnsupportedDoesNotChooseAnAdapter() {
        XCTAssertEqual(RemotePlatform.fromUname("Welcome\nLinux\n"), .linux)
        XCTAssertEqual(RemotePlatform.fromUname("Darwin\r\n"), .macOS)
        XCTAssertEqual(RemotePlatform.fromUname("FreeBSD"), .freeBSD)
        XCTAssertEqual(RemotePlatform.fromUname("Welcome to Linux hosting"), .unsupported)
        XCTAssertNil(RemotePlatform.freeBSD.inventoryCommand)
        XCTAssertThrowsError(try RemotePlatform.unsupported.parseInventory(""))
    }

    func testPowerShellEncodingPreservesUnicodeAndUsesNoninteractiveProfilesDisabled() throws {
        let script = "Write-Output 'Disco de prueba · 数据'"
        let command = PowerShellCommand.encode(script)
        XCTAssertTrue(command.hasPrefix("powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand "))
        let encoded = try XCTUnwrap(command.split(separator: " ").last)
        let data = try XCTUnwrap(Data(base64Encoded: String(encoded)))
        XCTAssertEqual(String(data: data, encoding: .utf16LittleEndian), script)
        XCTAssertFalse(command.contains("ExecutionPolicy"))
    }

    func testMissingMetricsNeverBecomeAnAllZeroHealthySampleOrWrongPlatformSample() {
        let valid = "METRIC_OS=Darwin\nMETRIC_CPU=5.0\nMETRIC_MEM_TOTAL=16000000000\nMETRIC_MEM_USED=4000000000"
        XCTAssertTrue(RemotePlatform.macOS.hasValidMetrics(valid))
        XCTAssertFalse(RemotePlatform.linux.hasValidMetrics(valid))
        XCTAssertFalse(
            RemotePlatform.windows.hasValidMetrics(
                "METRIC_OS=Windows\nMETRIC_CPU=0\nMETRIC_MEM_TOTAL=0\nMETRIC_MEM_USED=0"))
        XCTAssertFalse(RemotePlatform.macOS.hasValidMetrics(valid.replacingOccurrences(of: "5.0", with: "nan")))
        XCTAssertFalse(RemotePlatform.unsupported.hasValidMetrics(valid))
    }
}
