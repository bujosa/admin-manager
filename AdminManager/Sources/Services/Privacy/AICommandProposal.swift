import Foundation

/// AI output is a proposal, never authority to execute a shell command.
struct AICommandProposal {
    let explanation: String
    let command: String
    var automaticExecutionAllowed: Bool { false }

    init(json: [String: Any], fallback: String) {
        explanation = json["explanation"] as? String ?? fallback
        command = json["command"] as? String ?? ""
    }
}
