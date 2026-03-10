import Testing
@testable import OmniFocusMCPServer

@Suite("TTLCache")
struct CacheTests {
    @Test("get returns nil for missing key")
    func getMissing() async {
        let cache = TTLCache()
        let result = await cache.get(key: "nonexistent")
        #expect(result == nil)
    }

    @Test("set and get returns cached value")
    func setAndGet() async {
        let cache = TTLCache()
        await cache.set(key: "test", value: "{\"data\": 1}", ttl: 60)
        let result = await cache.get(key: "test")
        #expect(result == "{\"data\": 1}")
    }

    @Test("expired entries return nil")
    func expiry() async throws {
        let cache = TTLCache()
        await cache.set(key: "short", value: "val", ttl: 0.01)
        try await Task.sleep(for: .milliseconds(20))
        let result = await cache.get(key: "short")
        #expect(result == nil)
    }

    @Test("invalidateAll clears all entries")
    func invalidateAll() async {
        let cache = TTLCache()
        await cache.set(key: "a", value: "1", ttl: 60)
        await cache.set(key: "b", value: "2", ttl: 60)
        await cache.invalidateAll()
        let a = await cache.get(key: "a")
        let b = await cache.get(key: "b")
        #expect(a == nil)
        #expect(b == nil)
    }

    @Test("stats track hits and misses")
    func stats() async {
        let cache = TTLCache()
        await cache.set(key: "k", value: "v", ttl: 60)
        _ = await cache.get(key: "k")       // hit
        _ = await cache.get(key: "k")       // hit
        _ = await cache.get(key: "missing") // miss

        let stats = await cache.getStats()
        #expect(stats.hits == 2)
        #expect(stats.misses == 1)
        #expect(stats.entries == 1)
    }

    @Test("disabled cache always returns nil")
    func disabled() async {
        let cache = TTLCache(enabled: false)
        await cache.set(key: "k", value: "v", ttl: 60)
        let result = await cache.get(key: "k")
        #expect(result == nil)
    }

    @Test("cache key generation is deterministic")
    func keyGeneration() {
        let key1 = TTLCache.key(tool: "list_inbox", args: ["limit": "50", "offset": "0"])
        let key2 = TTLCache.key(tool: "list_inbox", args: ["offset": "0", "limit": "50"])
        // Keys should be the same regardless of insertion order (sorted)
        #expect(key1 == key2)
    }

    @Test("evictExpired removes stale entries")
    func evictExpired() async throws {
        let cache = TTLCache()
        await cache.set(key: "fresh", value: "1", ttl: 60)
        await cache.set(key: "stale", value: "2", ttl: 0.01)
        try await Task.sleep(for: .milliseconds(20))
        await cache.evictExpired()

        let fresh = await cache.get(key: "fresh")
        let stale = await cache.get(key: "stale")
        #expect(fresh == "1")
        #expect(stale == nil)
    }
}
