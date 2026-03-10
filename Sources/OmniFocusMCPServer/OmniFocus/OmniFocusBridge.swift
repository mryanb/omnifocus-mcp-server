import AppKit
import Foundation

/// Protocol for OmniFocus automation, enabling mock injection for tests.
protocol OmniFocusAutomation: Sendable {
    func evaluateJS(_ js: String) async throws -> String
    func detectCapability() async -> CapabilityMode
    func isOmniFocusRunning() async -> Bool
    func omniFocusVersion() async -> String?
}

enum CapabilityMode: String, Codable, Sendable {
    case pro
    case standard
    case unknown
}

/// Main OmniFocus bridge. Uses /usr/bin/osascript to run Omni Automation JavaScript.
///
/// We use osascript (subprocess) instead of in-process NSAppleScript because:
/// - NSAppleScript requires MainActor and can deadlock with Swift concurrency
/// - macOS TCC (Automation permissions) are attributed to the parent app when
///   using in-process NSAppleScript. When launched by Claude Code (Electron),
///   the permission dialog is suppressed for background child processes.
/// - osascript is a system binary that handles permission prompting reliably.
final class OmniFocusBridge: OmniFocusAutomation, @unchecked Sendable {

    /// Evaluate Omni Automation JavaScript in OmniFocus via osascript.
    func evaluateJS(_ js: String) async throws -> String {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        let appleScript = """
        tell application "OmniFocus"
            evaluate javascript "\(escaped)"
        end tell
        """

        let (exitCode, stdout, stderr) = try await runOsascript(appleScript)

        if exitCode != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse known error patterns from osascript stderr
            // -1743: user canceled / no permission (Pro required)
            if msg.contains("-1743") || msg.contains("not allowed assistive access") {
                throw OFMCPError.proRequired("evaluate javascript")
            }
            // -1728: can't get object (app not running or no document)
            if msg.contains("-1728") {
                throw OFMCPError.omnifocusNotRunning
            }
            throw OFMCPError.omnifocusEvalFailed(msg.isEmpty ? "osascript exited with code \(exitCode)" : msg)
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detect whether OmniFocus Pro automation is available.
    func detectCapability() async -> CapabilityMode {
        do {
            let version = try await evaluateJS("app.version")
            if !version.isEmpty {
                Log.info("OmniFocus Pro detected, version: \(version)")
                return .pro
            }
            Log.warning("evaluateJS returned empty string during capability detection")
            return .unknown
        } catch let error as OFMCPError {
            switch error {
            case .proRequired:
                Log.info("OmniFocus Standard detected (Pro not available)")
                return .standard
            case .omnifocusNotRunning:
                Log.warning("OmniFocus not running during capability detection")
                return .unknown
            case .omnifocusEvalFailed(let msg):
                Log.warning("AppleScript failed during capability detection: \(msg)")
                return .unknown
            default:
                Log.warning("Unexpected OFMCPError during capability detection: \(error)")
                return .unknown
            }
        } catch {
            Log.warning("Unexpected error during capability detection: \(error)")
            return .unknown
        }
    }

    /// Check if OmniFocus is currently running.
    func isOmniFocusRunning() async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == "com.omnigroup.OmniFocus4"
                || $0.bundleIdentifier == "com.omnigroup.OmniFocus3"
                || $0.bundleIdentifier == "com.omnigroup.OmniFocus3.MacAppStore"
            }
        }
    }

    /// Get OmniFocus version string.
    func omniFocusVersion() async -> String? {
        try? await evaluateJS("app.version")
    }

    // MARK: - osascript subprocess

    /// Run an AppleScript string via /usr/bin/osascript and return (exitCode, stdout, stderr).
    private func runOsascript(_ script: String) async throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Disconnect stdin so osascript doesn't read from MCP transport
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Read output asynchronously to avoid deadlock on pipe buffers
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (process.terminationStatus, stdout, stderr)
    }
}

/// URL scheme bridge for Standard mode (no Pro required).
enum OmniFocusURL {
    /// Build an omnifocus:///add URL for task creation.
    static func addTaskURL(
        name: String,
        note: String? = nil,
        project: String? = nil,
        tags: [String]? = nil,
        dueDate: String? = nil,
        deferDate: String? = nil,
        flagged: Bool? = nil,
        estimatedMinutes: Int? = nil
    ) -> URL? {
        var components = URLComponents(string: "omnifocus:///add")!
        var items = [URLQueryItem(name: "name", value: name)]
        if let note { items.append(URLQueryItem(name: "note", value: note)) }
        if let project { items.append(URLQueryItem(name: "project", value: project)) }
        if let tags {
            for tag in tags {
                items.append(URLQueryItem(name: "tag", value: tag))
            }
        }
        if let dueDate { items.append(URLQueryItem(name: "due", value: dueDate)) }
        if let deferDate { items.append(URLQueryItem(name: "defer", value: deferDate)) }
        if let flagged, flagged { items.append(URLQueryItem(name: "flag", value: "true")) }
        if let mins = estimatedMinutes { items.append(URLQueryItem(name: "estimate", value: "\(mins)m")) }
        components.queryItems = items
        return components.url
    }

    /// Build an omnifocus:///task/ID URL.
    static func taskURL(id: String) -> URL? {
        URL(string: "omnifocus:///task/\(id)")
    }

    /// Open a URL via NSWorkspace (fire-and-forget).
    static func open(_ url: URL) {
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
