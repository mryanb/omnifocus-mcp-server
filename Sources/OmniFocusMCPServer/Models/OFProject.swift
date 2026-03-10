import Foundation

/// Canonical OmniFocus project representation.
struct OFProject: Codable, Hashable, Sendable {
    let id: String
    let name: String
    var status: ProjectStatus?
    var note: String?
    var sequential: Bool?
    var dueDate: String?
    var deferDate: String?
    var taskCount: Int?
    var folderId: String?
    var folderName: String?
    var url: String?
}

enum ProjectStatus: String, Codable, Hashable, Sendable {
    case active
    case onHold = "on_hold"
    case completed
    case dropped
}

enum ProjectFieldSet: String, CaseIterable, Sendable {
    case id, name, status, note, sequential
    case dueDate, deferDate, taskCount
    case folderId, folderName, url
}

extension ProjectFieldSet {
    static let minimal: Set<ProjectFieldSet> = [.id, .name, .status]
    static let standard: Set<ProjectFieldSet> = minimal.union([
        .sequential, .dueDate, .taskCount, .folderName,
    ])
    static let full: Set<ProjectFieldSet> = Set(ProjectFieldSet.allCases)
}
