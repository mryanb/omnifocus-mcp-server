import Foundation

/// Canonical OmniFocus tag representation.
struct OFTag: Codable, Hashable, Sendable {
    let id: String
    let name: String
    var parentId: String?
    var taskCount: Int?
}
