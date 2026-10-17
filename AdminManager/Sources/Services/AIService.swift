import Foundation

// MARK: - AI Provider



// MARK: - AI Error

enum AIError: LocalizedError {
    case noProvider
    case cliError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProvider: return "No AI provider configured"
        case .cliError(let msg): return "CLI error: \(msg)"
        case .apiError(let msg): return "API error: \(msg)"
        }
    }
}

// MARK: - AI Service

@Observable
@MainActor
final class AIService {
    var isProcessing = false
    var progressMessage: String?
    var lastError: String?

    var isConfigured: Bool {
        let provider = currentProvider
        guard provider != .none else { return false }
        if provider.isCLI {
            return !resolvedCLIPath(for: provider).isEmpty
        } else {
            let apiKey = CredentialStore.shared.value(for: "aiAPIKey")
            return !apiKey.isEmpty
        }
    }

    private var currentProvider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "none") ?? .none
    }

    // MARK: - AI Chat (Main Interaction)

    struct ChatResponse {
        let explanation: String
        let command: String
        let autoExecute: Bool
    }

    func chat(question: String, deviceInfo: String, systemStats: String, recentOutput: String) async -> ChatResponse? {
        let provider = currentProvider
        guard provider != .none else {
            lastError = "No AI provider configured. Go to Settings > AI to set up a provider."
            return nil
        }

        isProcessing = true
        lastError = nil
        progressMessage = "Thinking..."
        defer {
            isProcessing = false
            progressMessage = nil
        }

        let contextSnippet = String(recentOutput.suffix(4000))

        let prompt = """
        You are a sysadmin AI assistant. You help manage remote servers via SSH.
        Device: \(deviceInfo)
        \(systemStats)

        Recent terminal session:
        \(contextSnippet)

        User: \(question)

        Respond ONLY with a JSON object (no markdown, no code fences):
        {"explanation":"your response","command":"shell command or empty string","autoExecute":true or false}

        Rules:
        - Always set autoExecute=false. Every proposed command requires the user's explicit review and Run action.
        - If the user asks a question that doesn't need a command, set command to empty string
        - Keep explanations concise (1-3 sentences)
        - Always respond with valid JSON only
        """

        do {
            let raw = try await runPrompt(provider: provider, prompt: prompt)
            if let json = Self.parseJSON(raw) {
                let proposal = AICommandProposal(json: json, fallback: raw)
                return ChatResponse(
                    explanation: proposal.explanation,
                    command: proposal.command,
                    autoExecute: proposal.automaticExecutionAllowed
                )
            }
            return ChatResponse(explanation: raw, command: "", autoExecute: false)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Analyze Command Output

    struct AnalysisResponse {
        let explanation: String
        let followUp: String
    }

    func analyzeOutput(command: String, output: String, deviceInfo: String, systemStats: String) async -> AnalysisResponse? {
        let provider = currentProvider
        guard provider != .none else { return nil }

        isProcessing = true
        lastError = nil
        progressMessage = "Analyzing..."
        defer {
            isProcessing = false
            progressMessage = nil
        }

        let outputSnippet = String(output.suffix(4000))

        let prompt = """
        You are a sysadmin AI assistant analyzing command output.
        Device: \(deviceInfo)
        \(systemStats)

        Command executed: \(command)
        Output:
        \(outputSnippet)

        Briefly explain the output (1-3 sentences). If there are issues, mention them.
        Respond ONLY with JSON (no markdown):
        {"explanation":"concise analysis","followUp":"optional next command or empty string"}
        """

        do {
            let raw = try await runPrompt(provider: provider, prompt: prompt)
            if let json = Self.parseJSON(raw) {
                return AnalysisResponse(
                    explanation: json["explanation"] as? String ?? raw,
                    followUp: json["followUp"] as? String ?? json["suggestion"] as? String ?? ""
                )
            }
            return AnalysisResponse(explanation: raw, followUp: "")
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> Bool {
        let provider = currentProvider
        guard provider != .none else {
            lastError = "No AI provider configured"
            return false
        }

        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        if provider.isCLI {
            let cliPath = resolvedCLIPath(for: provider)
            guard !cliPath.isEmpty else {
                lastError = "CLI path not configured"
                return false
            }
            let environment = Self.minimalEnvironment
            do {
                let succeeded = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: cliPath)
                            process.arguments = ["--version"]
                            process.environment = environment
                            let pipe = Pipe()
                            process.standardOutput = pipe
                            process.standardError = pipe
                            try process.run()
                            let _ = pipe.fileHandleForReading.readDataToEndOfFile()
                            process.waitUntilExit()
                            continuation.resume(returning: process.terminationStatus == 0)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                if !succeeded {
                    lastError = "CLI returned exit code"
                }
                return succeeded
            } catch {
                lastError = error.localizedDescription
                return false
            }
        } else {
            let apiKey = CredentialStore.shared.value(for: "aiAPIKey")
            let storedModel = AIModelPreferences.value(for: provider.rawValue)
            let model = storedModel.isEmpty ? provider.defaultModel : storedModel
            guard !apiKey.isEmpty else {
                lastError = "API key not configured"
                return false
            }
            do {
                _ = try await runAPI(provider: provider, apiKey: apiKey, model: model, prompt: "Say hello in one word.")
                return true
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }
    }

    // MARK: - Shared Prompt Runner

    private func runPrompt(provider: AIProvider, prompt: String) async throws -> String {
        if provider.isCLI {
            let cliPath = resolvedCLIPath(for: provider)
            let model = AIModelPreferences.value(for: provider.rawValue)
            guard !cliPath.isEmpty else {
                throw AIError.cliError("CLI path not configured")
            }
            return try await runCLI(provider: provider, path: cliPath, model: model, prompt: prompt)
        } else {
            let apiKey = CredentialStore.shared.value(for: "aiAPIKey")
            let storedModel = AIModelPreferences.value(for: provider.rawValue)
            let model = storedModel.isEmpty ? provider.defaultModel : storedModel
            guard !apiKey.isEmpty else {
                throw AIError.apiError("API key not configured")
            }
            return try await runAPI(provider: provider, apiKey: apiKey, model: model, prompt: prompt)
        }
    }

    // MARK: - CLI Execution

    /// Minimal environment to avoid macOS permission prompts for network volumes.
    private static let minimalEnvironment: [String: String] = {
        var env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "TERM": "xterm-256color"
        ]
        // Forward API keys if set so CLI tools can authenticate
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            env["ANTHROPIC_API_KEY"] = key
        }
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            env["OPENAI_API_KEY"] = key
        }
        return env
    }()

    private func resolvedCLIPath(for provider: AIProvider) -> String {
        let defaults = UserDefaults.standard
        let storedPath = (defaults.string(forKey: "aiCLIPath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard provider.isCLI else { return "" }

        if !storedPath.isEmpty {
            if FileManager.default.fileExists(atPath: storedPath) {
                return storedPath
            }
            if provider.isKnownPath(storedPath) {
                let detected = provider.defaultPath
                if !detected.isEmpty, FileManager.default.fileExists(atPath: detected) {
                    defaults.set(detected, forKey: "aiCLIPath")
                    return detected
                }
            }
            return storedPath
        }

        let detected = provider.defaultPath
        if !detected.isEmpty {
            defaults.set(detected, forKey: "aiCLIPath")
        }
        return detected
    }

    private func runCLI(provider: AIProvider, path: String, model: String, prompt: String) async throws -> String {
        let environment = Self.minimalEnvironment
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.environment = environment

                    switch provider {
                    case .claude:
                        var args = ["--print"]
                        if !model.isEmpty {
                            args += ["--model", model]
                        }
                        args.append(prompt)
                        process.arguments = args
                    case .codex:
                        var args = ["--quiet", "--full-auto"]
                        if !model.isEmpty {
                            args += ["--model", model]
                        }
                        args.append(prompt)
                        process.arguments = args
                    case .ollama:
                        let modelName = model.isEmpty ? "llama3.2" : model
                        process.arguments = ["run", modelName, prompt]
                    default:
                        continuation.resume(throwing: AIError.noProvider)
                        return
                    }

                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    try process.run()

                    var outputData = Data()
                    var errorData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        let errStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: AIError.cliError(errStr))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - API Execution

    private func runAPI(provider: AIProvider, apiKey: String, model: String, prompt: String) async throws -> String {
        let request = try buildAPIRequest(provider: provider, apiKey: apiKey, model: model, prompt: prompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.apiError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try extractTextFromAPIResponse(provider: provider, data: data)
    }

    private func buildAPIRequest(provider: AIProvider, apiKey: String, model: String, prompt: String) throws -> URLRequest {
        try AIAPITransport.request(provider: provider, apiKey: apiKey, model: model, prompt: prompt)
    }

    private func extractTextFromAPIResponse(provider: AIProvider, data: Data) throws -> String {
        try AIAPITransport.text(provider: provider, data: data)
    }

    // MARK: - Parse JSON Helpers

    static func parseJSON(_ raw: String) -> [String: Any]? {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if jsonStr.hasPrefix("```") {
            let lines = jsonStr.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.hasPrefix("```") }
            jsonStr = filtered.joined(separator: "\n")
        }

        // Extract JSON object
        if let start = jsonStr.firstIndex(of: "{"), let end = jsonStr.lastIndex(of: "}") {
            jsonStr = String(jsonStr[start...end])
        }

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }
}
