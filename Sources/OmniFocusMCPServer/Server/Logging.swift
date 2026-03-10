import Foundation

/// Simple stderr logger. Never writes to stdout (reserved for MCP transport).
enum Log {
    enum Level: Int, Comparable, Sendable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERROR"
            }
        }
    }

    /// Current minimum log level. Set from configuration at startup.
    nonisolated(unsafe) static var minimumLevel: Level = .info

    static func debug(_ message: @autoclosure () -> String, tool: String? = nil) {
        log(.debug, message(), tool: tool)
    }

    static func info(_ message: @autoclosure () -> String, tool: String? = nil) {
        log(.info, message(), tool: tool)
    }

    static func warning(_ message: @autoclosure () -> String, tool: String? = nil) {
        log(.warning, message(), tool: tool)
    }

    static func error(_ message: @autoclosure () -> String, tool: String? = nil) {
        log(.error, message(), tool: tool)
    }

    private static func log(_ level: Level, _ message: String, tool: String?) {
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let toolPrefix = tool.map { " [\($0)]" } ?? ""
        let line = "[omnifocus-mcp-server] [\(timestamp)] [\(level.label)]\(toolPrefix) \(message)\n"

        // Write to stderr only — stdout is reserved for MCP JSON-RPC
        fputs(line, stderr)
    }

    /// Configure log level from Configuration.
    static func configure(from config: Configuration) {
        switch config.logLevel {
        case .debug: minimumLevel = .debug
        case .info: minimumLevel = .info
        case .warning: minimumLevel = .warning
        case .error: minimumLevel = .error
        }
    }
}
