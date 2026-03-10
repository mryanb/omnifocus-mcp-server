import Foundation

/// Actor-isolated TTL cache for OmniFocus query results.
/// Keyed by a hash of (tool name, normalized arguments, field selection, cursor).
/// Full invalidation on any mutation for simplicity and correctness.
actor TTLCache {
    struct Entry: Sendable {
        let value: String  // JSON string
        let insertedAt: Date
        let ttl: TimeInterval
    }

    struct Stats: Codable, Sendable {
        var entries: Int
        var hits: Int
        var misses: Int
        var evictions: Int
    }

    private var store: [String: Entry] = [:]
    private var stats = Stats(entries: 0, hits: 0, misses: 0, evictions: 0)
    private let enabled: Bool

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    /// Get a cached value if it exists and hasn't expired.
    func get(key: String) -> String? {
        guard enabled else { return nil }

        guard let entry = store[key] else {
            stats.misses += 1
            return nil
        }

        if Date().timeIntervalSince(entry.insertedAt) > entry.ttl {
            store.removeValue(forKey: key)
            stats.entries -= 1
            stats.evictions += 1
            stats.misses += 1
            return nil
        }

        stats.hits += 1
        return entry.value
    }

    /// Store a value with a TTL.
    func set(key: String, value: String, ttl: TimeInterval) {
        guard enabled else { return }
        let isNew = store[key] == nil
        store[key] = Entry(value: value, insertedAt: Date(), ttl: ttl)
        if isNew { stats.entries += 1 }
    }

    /// Invalidate all cached entries. Called on any mutation.
    func invalidateAll() {
        let count = store.count
        store.removeAll()
        stats.entries = 0
        stats.evictions += count
    }

    /// Remove expired entries proactively.
    func evictExpired() {
        let now = Date()
        var removed = 0
        store = store.filter { _, entry in
            let alive = now.timeIntervalSince(entry.insertedAt) <= entry.ttl
            if !alive { removed += 1 }
            return alive
        }
        stats.entries = store.count
        stats.evictions += removed
    }

    /// Get cache statistics.
    func getStats() -> Stats {
        stats
    }

    /// Build a cache key from tool name and arguments.
    static func key(tool: String, args: [String: String] = [:]) -> String {
        var components = [tool]
        for key in args.keys.sorted() {
            components.append("\(key)=\(args[key] ?? "")")
        }
        return components.joined(separator: "|")
    }
}

/// TTL constants for different data types.
enum CacheTTL {
    static let inbox: TimeInterval = 5
    static let today: TimeInterval = 10
    static let flagged: TimeInterval = 10
    static let projects: TimeInterval = 120
    static let tags: TimeInterval = 120
    static let singleTask: TimeInterval = 30
    static let search: TimeInterval = 15
    static let count: TimeInterval = 15
}
