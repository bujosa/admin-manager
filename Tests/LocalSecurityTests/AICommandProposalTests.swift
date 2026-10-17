import XCTest

@testable import LocalSecurity

final class AICommandProposalTests: XCTestCase {
    func testModelCannotAuthorizeExecutionIncludingReadCommandsAndShellOperators() {
        for command in ["ls -la", "mount /dev/example /mnt", "echo example; reboot"] {
            let value = AICommandProposal(
                json: ["explanation": "Suggested action", "command": command, "autoExecute": true], fallback: "")
            XCTAssertEqual(value.command, command)
            XCTAssertFalse(value.automaticExecutionAllowed)
        }
    }

    func testMalformedCommandIsNotConvertedIntoExecutableText() {
        let value = AICommandProposal(json: ["command": ["unexpected"], "safe": true], fallback: "Review the response")
        XCTAssertEqual(value.command, "")
        XCTAssertEqual(value.explanation, "Review the response")
        XCTAssertFalse(value.automaticExecutionAllowed)
    }
}
