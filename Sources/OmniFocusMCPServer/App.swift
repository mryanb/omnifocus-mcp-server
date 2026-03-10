import Foundation

// Entry point for the OmniFocus MCP server.
//
// Uses @main with async main() for clean Swift concurrency integration.
// OmniFocus automation runs via osascript subprocess (no MainActor/run loop needed).

@main
struct OmniFocusMCPApp {
    static func main() async {
        do {
            try await startMCPServer()
        } catch {
            fputs("Fatal error: \(error)\n", stderr)
            exit(1)
        }
    }
}
