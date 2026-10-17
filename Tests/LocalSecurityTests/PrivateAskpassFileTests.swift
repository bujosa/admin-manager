import XCTest
@testable import LocalSecurity

final class PrivateAskpassFileTests: XCTestCase {
    func testHelperPermissionsAndLiteralPasswordOutput() throws {
        let example = "example 'quoted' value\nsecond line %s"
        let helper = try PrivateAskpassFile(password: example)
        defer { helper.remove() }
        for url in [helper.url, helper.url.deletingLastPathComponent()] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
        let process = Process()
        process.executableURL = helper.url
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: data, encoding: .utf8), example + "\n")
        helper.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.url.deletingLastPathComponent().path))
    }
}
