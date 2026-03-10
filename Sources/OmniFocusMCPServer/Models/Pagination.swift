import Foundation

/// Paginated response wrapper.
struct PaginatedResponse<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let items: [T]
    let cursor: String?
    let hasMore: Bool
    let totalCount: Int?
}

/// Cursor encoding/decoding. Cursor is a base64-encoded JSON offset.
enum Cursor: Sendable {
    struct Payload: Codable, Sendable {
        let offset: Int
    }

    static func encode(offset: Int) -> String {
        let payload = Payload(offset: offset)
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        return data.base64EncodedString()
    }

    static func decode(_ cursor: String) -> Int? {
        guard let data = Data(base64Encoded: cursor),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }
        return payload.offset
    }
}
