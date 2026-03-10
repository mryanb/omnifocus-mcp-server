import Foundation

/// Server configuration loaded from environment variables and optional config file.
/// Environment variables override config file values.
struct Configuration: Sendable {
    let logLevel: LogLevel
    let bulkOpsEnabled: Bool
    let deleteEnabled: Bool
    let toolAllowlist: Set<String>?
    let defaultLimit: Int
    let maxLimit: Int
    let cacheEnabled: Bool

    enum LogLevel: String, Sendable {
        case debug, info, warning, error
    }

    /// Load configuration from environment and optional config file.
    static func load() -> Configuration {
        let fileConfig = ConfigFile.load()

        let logLevel = LogLevel(rawValue:
            env("OMNIFOCUS_MCP_LOG_LEVEL") ?? fileConfig?.logLevel ?? "info"
        ) ?? .info

        let bulkOps = boolEnv("OMNIFOCUS_MCP_BULK_OPS") ?? fileConfig?.bulkOps ?? false
        let deleteEnabled = boolEnv("OMNIFOCUS_MCP_DELETE_ENABLED") ?? fileConfig?.deleteEnabled ?? false

        let allowlist: Set<String>? = {
            if let envVal = env("OMNIFOCUS_MCP_TOOL_ALLOWLIST") {
                return Set(envVal.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            }
            if let fileVal = fileConfig?.toolAllowlist {
                return Set(fileVal)
            }
            return nil
        }()

        let defaultLimit = intEnv("OMNIFOCUS_MCP_DEFAULT_LIMIT") ?? fileConfig?.defaultLimit ?? 50
        let maxLimit = intEnv("OMNIFOCUS_MCP_MAX_LIMIT") ?? fileConfig?.maxLimit ?? 200
        let cacheEnabled = boolEnv("OMNIFOCUS_MCP_CACHE_ENABLED") ?? fileConfig?.cacheEnabled ?? true

        return Configuration(
            logLevel: logLevel,
            bulkOpsEnabled: bulkOps,
            deleteEnabled: deleteEnabled,
            toolAllowlist: allowlist,
            defaultLimit: min(defaultLimit, maxLimit),
            maxLimit: maxLimit,
            cacheEnabled: cacheEnabled
        )
    }

    /// Check if a tool is allowed by the current configuration.
    func isToolAllowed(_ name: String) -> Bool {
        guard let allowlist = toolAllowlist else { return true }
        return allowlist.contains(name)
    }
}

// MARK: - Config File

private struct ConfigFile: Codable {
    let logLevel: String?
    let bulkOps: Bool?
    let deleteEnabled: Bool?
    let toolAllowlist: [String]?
    let defaultLimit: Int?
    let maxLimit: Int?
    let cacheEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case logLevel = "log_level"
        case bulkOps = "bulk_ops"
        case deleteEnabled = "enable_delete"
        case toolAllowlist = "tool_allowlist"
        case defaultLimit = "default_limit"
        case maxLimit = "max_limit"
        case cacheEnabled = "cache_enabled"
    }

    static func load() -> ConfigFile? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/omnifocus-mcp/config.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(ConfigFile.self, from: data)
    }
}

// MARK: - Environment Helpers

private func env(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]
}

private func boolEnv(_ key: String) -> Bool? {
    guard let val = env(key)?.lowercased() else { return nil }
    return val == "true" || val == "1" || val == "yes"
}

private func intEnv(_ key: String) -> Int? {
    guard let val = env(key) else { return nil }
    return Int(val)
}
