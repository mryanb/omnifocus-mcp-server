import Foundation
@testable import OmniFocusMCPServer

/// Mock OmniFocus bridge for unit testing without OmniFocus installed.
final class MockBridge: OmniFocusAutomation, @unchecked Sendable {
    var mockMode: CapabilityMode = .pro
    var mockRunning: Bool = true
    var mockVersion: String? = "4.5"
    var jsResults: [String: String] = [:]
    var lastJS: String?
    var shouldThrow: OFMCPError?
    var callCount: Int = 0

    func evaluateJS(_ js: String) async throws -> String {
        callCount += 1
        lastJS = js

        if let error = shouldThrow {
            throw error
        }

        // Return matching mock result or default empty JSON
        for (pattern, result) in jsResults {
            if js.contains(pattern) {
                return result
            }
        }

        return "{\"items\": [], \"totalCount\": 0}"
    }

    func detectCapability() async -> CapabilityMode {
        mockMode
    }

    func isOmniFocusRunning() async -> Bool {
        mockRunning
    }

    func omniFocusVersion() async -> String? {
        mockVersion
    }
}
