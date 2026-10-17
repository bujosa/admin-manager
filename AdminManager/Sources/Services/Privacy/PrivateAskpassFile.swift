import Foundation

/// Creates the SSH password helper inside an owner-only temporary directory.
struct PrivateAskpassFile {
    let url: URL
    private let directory: URL

    init(password: String, parent: URL = FileManager.default.temporaryDirectory) throws {
        directory = parent.appendingPathComponent("adminmanager-askpass-" + UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("askpass")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
            let script = "#!/bin/sh\nprintf '%s\\n' '\(escaped)'\n"
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: Data(script.utf8),
                attributes: [.posixPermissions: 0o700]
            ) else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
