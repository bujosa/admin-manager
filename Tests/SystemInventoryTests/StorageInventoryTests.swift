import Foundation
import XCTest

@testable import SystemInventory

final class StorageInventoryTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "zima-multi-drive", withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
    func testDetectsAdditionalUnmountedSSDAndExcludesLoopAndCompressedRAM() throws {
        let inventory = try StorageInventoryParser.parse(fixture())
        XCTAssertEqual(inventory.physicalDisks.count, 4)
        let ssd = try XCTUnwrap(inventory.physicalDisks.first { $0.name == "nvme0n1" })
        XCTAssertEqual(ssd.mediaLabel, "NVMe SSD")
        XCTAssertEqual(ssd.sizeBytes, 1_000_000_000_000)
        XCTAssertTrue(inventory.mountPoints(for: ssd).isEmpty)
        XCTAssertTrue(inventory.volumes(for: ssd).isEmpty)
        XCTAssertFalse(inventory.devices.contains { $0.name.hasPrefix("zram") || $0.type == "loop" })
        XCTAssertEqual(inventory.physicalCapacity, 3_532_000_000_000)
    }
    func testMatchesUsageToPartitionsPreservingSpacesMultipleMountsAndAvailableSpace() throws {
        let inventory = try StorageInventoryParser.parse(fixture())
        let hdd = try XCTUnwrap(inventory.physicalDisks.first { $0.name == "sda" })
        XCTAssertEqual(inventory.mountPoints(for: hdd), ["/media/Media library", "/srv/media"])
        let partition = try XCTUnwrap(inventory.descendants(of: hdd.path).first)
        let volume = try XCTUnwrap(inventory.volumes(for: partition).first)
        XCTAssertEqual(volume.usedBytes, 700_000_000_000)
        XCTAssertEqual(volume.availableBytes, 1_100_000_000_000)
        XCTAssertEqual(volume.totalBytes, 1_900_000_000_000)  // Filesystem size, not raw partition capacity.
        XCTAssertEqual(try XCTUnwrap(volume.usagePercent), 700.0 / 1900 * 100, accuracy: 0.001)
        XCTAssertFalse(inventory.volumes.contains { $0.fileSystem == "overlay" })
    }
    func testBtrfsAnonymousMountDeviceNumbersStillMatchThePhysicalSSD() throws {
        let devices = try StorageInventoryParser.parseDevices(
            #"{"blockdevices":[{"name":"/dev/nvme0n1","type":"disk","size":2000,"maj:min":"259:0","mountpoints":["/media/SSD"]}]}"#
        )
        let volumes = try StorageInventoryParser.parseVolumes(
            #"{"filesystems":[{"source":"/dev/nvme0n1","target":"/media/SSD","fstype":"btrfs","maj:min":"0:33","size":1900,"used":100,"avail":1800}]}"#
        )
        let inventory = StorageInventory(devices: devices, volumes: volumes, resources: SystemResources(), warnings: [])
        XCTAssertEqual(inventory.volumes(for: try XCTUnwrap(devices.first)).count, 1)
    }
    func testImmutableFullRootIsNotWritableDiskPressure() {
        XCTAssertFalse(StoragePressure.isHigh(used: 1000, total: 1000, readOnly: true))
        XCTAssertTrue(StoragePressure.isHigh(used: 950, total: 1000, readOnly: false))
        XCTAssertFalse(StoragePressure.isHigh(used: 840, total: 1000, readOnly: false))
        XCTAssertFalse(StoragePressure.isHigh(used: 0, total: 0, readOnly: false))
    }
    func testNetworkByteCountersPreserveLargeTotalsAndInterfaceColonSpacing() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = [LinuxInventoryProbe.networkCountersAWK]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let text =
            "header\nheader\n eth0:10000000000 0 0 0 0 0 0 0 20000000000 0 0 0 0 0 0 0\n lo: 999 0 0 0 0 0 0 0 999 0 0 0 0 0 0 0\n"
        input.fileHandleForWriting.write(Data(text.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: data, encoding: .utf8), "METRIC_NET=10000000000:20000000000\n")
    }
    func testCapturesAvailableRAMSwapLoadAndReadOnlyUSB() throws {
        let inventory = try StorageInventoryParser.parse(fixture())
        XCTAssertEqual(inventory.resources.logicalCPUs, 4)
        XCTAssertEqual(inventory.resources.memoryAvailable, 5_368_709_120)
        XCTAssertEqual(inventory.resources.swapUsed, 1_073_741_824)
        XCTAssertEqual(inventory.resources.loadAverage, [0.1, 0.2, 0.3])
        XCTAssertEqual(inventory.physicalDisks.first { $0.name == "sdb" }?.readOnly, true)
        XCTAssertNil(inventory.volumes.first { $0.fileSystem == "nfs4" }?.usagePercent)
    }
    func testLegacyMountpointAndStringBooleansAreSupported() throws {
        let devices = try StorageInventoryParser.parseDevices(
            #"{"blockdevices":[{"name":"sda","type":"disk","size":"1024","rota":"1","ro":"0","mountpoint":"/media/Legacy disk"}]}"#
        )
        XCTAssertEqual(devices.first?.path, "/dev/sda")
        XCTAssertEqual(devices.first?.mediaLabel, "HDD")
        XCTAssertEqual(devices.first?.readOnly, false)
        XCTAssertEqual(devices.first?.mountPoints, ["/media/Legacy disk"])
    }
    func testSharedRAIDDeviceIsDeduplicatedWithoutDoubleCountingCapacity() throws {
        let json =
            #"{"blockdevices":[{"name":"sda","type":"disk","size":1000,"children":[{"name":"md0","type":"raid1","size":1000}]},{"name":"sdb","type":"disk","size":1000,"children":[{"name":"md0","type":"raid1","size":1000}]}]}"#
        let devices = try StorageInventoryParser.parseDevices(json)
        let inventory = StorageInventory(devices: devices, volumes: [], resources: SystemResources(), warnings: [])
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices.first { $0.name == "md0" }?.parents, ["/dev/sda", "/dev/sdb"])
        XCTAssertEqual(inventory.physicalCapacity, 2000)
        XCTAssertEqual(inventory.descendants(of: "/dev/sda").count, 1)
    }
    func testMissingUtilitiesYieldExplicitWarningsAndRetainResources() throws {
        let output = "ADMIN_INVENTORY_V1\nADMIN_RESOURCES_BEGIN\nCPU_CORES=4\nADMIN_RESOURCES_END\nADMIN_INVENTORY_END"
        let inventory = try StorageInventoryParser.parse(output)
        XCTAssertEqual(inventory.warnings.count, 2)
        XCTAssertEqual(inventory.resources.logicalCPUs, 4)
        XCTAssertNil(inventory.physicalCapacity)
    }
    func testMalformedTruncatedAndUnsupportedResponsesDoNotLookLikeEmptyHealthyInventory() throws {
        XCTAssertThrowsError(try StorageInventoryParser.parse("ADMIN_INVENTORY_V1\n"))
        XCTAssertThrowsError(
            try StorageInventoryParser.parse("ADMIN_INVENTORY_V1\nADMIN_UNSUPPORTED\nADMIN_INVENTORY_END"))
        XCTAssertThrowsError(try StorageInventoryParser.parseDevices("not JSON"))
        XCTAssertThrowsError(try StorageInventoryParser.parseDevices(#"{"blockdevices":[{"size":1}]}"#))
    }
    func testFirmwareRegionsEmptyNetworkBlockDevicesAndVirtualDisksAreNotExtraSSDs() throws {
        let devices = try StorageInventoryParser.parseDevices(
            #"{"blockdevices":[{"name":"mmcblk0","type":"disk","size":64000},{"name":"mmcblk0boot0","type":"disk","size":4096},{"name":"mmcblk0boot1","type":"disk","size":4096},{"name":"nbd0","type":"disk","size":0,"rota":false},{"name":"nbd1","type":"disk","size":5000,"rota":false},{"name":"vda","type":"disk","size":9000,"rota":false}]}"#
        )
        let inventory = StorageInventory(devices: devices, volumes: [], resources: SystemResources(), warnings: [])
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(inventory.physicalDisks.map(\.name), ["mmcblk0"])
        XCTAssertEqual(inventory.physicalCapacity, 64000)
        XCTAssertEqual(devices.first { $0.name == "nbd1" }?.mediaLabel, "Network block device")
        XCTAssertEqual(devices.first { $0.name == "vda" }?.mediaLabel, "Virtual disk")
    }
    func testUnknownCapacityAndUsageRemainUnavailable() throws {
        let devices = try StorageInventoryParser.parseDevices(
            #"{"blockdevices":[{"name":"sda","type":"disk","size":null,"rota":null}]}"#)
        let inventory = StorageInventory(devices: devices, volumes: [], resources: SystemResources(), warnings: [])
        XCTAssertNil(inventory.physicalCapacity)
        XCTAssertEqual(devices.first?.mediaLabel, "Disk")
        let volumes = try StorageInventoryParser.parseVolumes(
            #"{"filesystems":[{"source":"/dev/sda","target":"/data","fstype":"ext4","size":0,"used":0}]}"#)
        XCTAssertNil(volumes.first?.usagePercent)
    }
    func testDescendantTraversalHandlesCycles() throws {
        let devices = try StorageInventoryParser.parseDevices(
            #"{"blockdevices":[{"name":"sda","pkname":"md0","type":"disk","children":[{"name":"md0","type":"raid1"}]}]}"#
        )
        let inventory = StorageInventory(devices: devices, volumes: [], resources: SystemResources(), warnings: [])
        XCTAssertEqual(inventory.descendants(of: "/dev/sda").map(\.name), ["md0"])
    }
}

final class LinuxCPUSampleTests: XCTestCase {
    func testUsesCounterDeltasAndCountsIOWaitAsIdleWithoutDuplicateGuestTime() throws {
        let previous = try XCTUnwrap(LinuxCPUSample(counters: "100 0 100 700 100 0 0 0 50 0"))
        let current = try XCTUnwrap(LinuxCPUSample(counters: "140 0 120 730 110 0 0 0 70 0"))
        XCTAssertEqual(try XCTUnwrap(current.usage(since: previous)), 60, accuracy: 0.001)
    }
    func testRejectsCounterResetZeroDeltaMalformedAndOverflow() throws {
        let sample = try XCTUnwrap(LinuxCPUSample(counters: "100 0 100 700 100 0 0 0"))
        let reset = try XCTUnwrap(LinuxCPUSample(counters: "1 0 1 2 0 0 0 0"))
        XCTAssertNil(reset.usage(since: sample))
        XCTAssertNil(sample.usage(since: sample))
        XCTAssertNil(LinuxCPUSample(counters: "bad data"))
        XCTAssertNil(LinuxCPUSample(counters: "1 invalid 2 3 4"))
        XCTAssertNil(LinuxCPUSample(counters: "18446744073709551615 1 1 1"))
    }
}
