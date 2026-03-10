import Foundation

/// Structured error categories for MCP responses.
enum ErrorCategory: String, Codable, Sendable {
    case permission
    case notFound = "not_found"
    case invalidInput = "invalid_input"
    case timeout
    case omnifocusUnavailable = "omnifocus_unavailable"
    case capabilityUnavailable = "capability_unavailable"
    case confirmationRequired = "confirmation_required"
    case configDisabled = "config_disabled"
    case internalError = "internal_error"
}

/// Structured error response included in MCP tool results.
struct StructuredError: Codable, Sendable {
    let category: ErrorCategory
    let message: String
    let retryable: Bool

    init(_ category: ErrorCategory, _ message: String, retryable: Bool = false) {
        self.category = category
        self.message = message
        self.retryable = retryable
    }
}

/// Errors thrown internally within the server.
enum OFMCPError: Error, Sendable {
    case omnifocusNotRunning
    case omnifocusEvalFailed(String)
    case proRequired(String)
    case taskNotFound(String)
    case invalidInput(String)
    case confirmationRequired(token: String, preview: String)
    case invalidConfirmToken
    case configDisabled(String)
    case timeout
}

extension OFMCPError {
    /// Convert to a structured error for MCP response.
    var structured: StructuredError {
        switch self {
        case .omnifocusNotRunning:
            return StructuredError(.omnifocusUnavailable, "OmniFocus is not running", retryable: true)
        case .omnifocusEvalFailed(let msg):
            return StructuredError(.omnifocusUnavailable, "OmniFocus evaluation failed: \(msg)", retryable: true)
        case .proRequired(let tool):
            return StructuredError(.capabilityUnavailable,
                "Tool '\(tool)' requires OmniFocus Pro. Upgrade at https://www.omnigroup.com/omnifocus",
                retryable: false)
        case .taskNotFound(let id):
            return StructuredError(.notFound, "Task '\(id)' not found", retryable: false)
        case .invalidInput(let msg):
            return StructuredError(.invalidInput, msg, retryable: false)
        case .confirmationRequired(_, let preview):
            return StructuredError(.confirmationRequired, preview, retryable: false)
        case .invalidConfirmToken:
            return StructuredError(.invalidInput, "Invalid or expired confirm_token. Request a new dry_run", retryable: false)
        case .configDisabled(let feature):
            return StructuredError(.configDisabled,
                "'\(feature)' is disabled. Set OMNIFOCUS_MCP_\(feature.uppercased())=true to enable", retryable: false)
        case .timeout:
            return StructuredError(.timeout, "OmniFocus did not respond in time", retryable: true)
        }
    }
}
