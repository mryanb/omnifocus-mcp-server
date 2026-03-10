import Foundation
import CryptoKit

/// Manages confirm tokens for destructive operations.
/// Tokens are HMAC-SHA256 signed, single-use, and time-limited.
actor ConfirmTokenManager {
    /// Per-session random signing key. Not persisted.
    private let signingKey: SymmetricKey

    /// Set of consumed tokens to prevent replay.
    private var consumedTokens: Set<String> = []

    /// Token TTL in seconds.
    private let tokenTTL: TimeInterval = 300  // 5 minutes

    init() {
        self.signingKey = SymmetricKey(size: .bits256)
    }

    /// Generate a confirm token for a destructive operation.
    /// The token encodes the task ID, a hash of the patch, and a timestamp.
    func generate(taskId: String, patchHash: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let payload = "\(taskId)|\(patchHash)|\(timestamp)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: signingKey
        )
        let sigHex = signature.map { String(format: "%02x", $0) }.joined()
        // Token format: base64(payload)|signature
        let encodedPayload = Data(payload.utf8).base64EncodedString()
        return "\(encodedPayload).\(sigHex)"
    }

    /// Verify and consume a confirm token. Returns true if valid.
    func verify(token: String, taskId: String, patchHash: String) -> Bool {
        // Check not already consumed
        guard !consumedTokens.contains(token) else { return false }

        // Split token
        let parts = token.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let payloadData = Data(base64Encoded: String(parts[0])),
              let payload = String(data: payloadData, encoding: .utf8)
        else {
            return false
        }

        // Parse payload
        let components = payload.split(separator: "|", maxSplits: 2)
        guard components.count == 3,
              let timestamp = Int(components[2])
        else {
            return false
        }

        // Verify task ID matches
        guard String(components[0]) == taskId else { return false }

        // Verify patch hash matches
        guard String(components[1]) == patchHash else { return false }

        // Verify not expired
        let age = Date().timeIntervalSince1970 - Double(timestamp)
        guard age >= 0 && age <= tokenTTL else { return false }

        // Verify signature
        let expectedSig = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: signingKey
        )
        let expectedHex = expectedSig.map { String(format: "%02x", $0) }.joined()
        guard String(parts[1]) == expectedHex else { return false }

        // Consume token
        consumedTokens.insert(token)

        // Prune old consumed tokens periodically (keep set bounded)
        if consumedTokens.count > 1000 {
            consumedTokens.removeAll()
        }

        return true
    }

    /// Hash a patch dictionary for token binding.
    static func hashPatch(_ patch: [String: Any]) -> String {
        // Sort keys for determinism, then hash the description
        let sorted = patch.keys.sorted().map { "\($0)=\(patch[$0] ?? "nil")" }
        let joined = sorted.joined(separator: "&")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Determines if a patch contains destructive operations requiring confirmation.
func patchRequiresConfirmation(_ patch: [String: Any]) -> Bool {
    guard let status = patch["status"] as? String else { return false }
    return status == "complete" || status == "drop"
}
