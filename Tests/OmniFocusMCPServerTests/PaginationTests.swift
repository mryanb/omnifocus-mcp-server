import Testing
@testable import OmniFocusMCPServer

@Suite("Pagination")
struct PaginationTests {
    @Test("cursor round-trip preserves offset")
    func cursorRoundTrip() {
        let encoded = Cursor.encode(offset: 50)
        let decoded = Cursor.decode(encoded)
        #expect(decoded == 50)
    }

    @Test("cursor decode handles invalid input")
    func cursorInvalid() {
        #expect(Cursor.decode("not-base64") == nil)
        #expect(Cursor.decode("") == nil)
        #expect(Cursor.decode("aGVsbG8=") == nil) // valid base64 but not valid JSON
    }

    @Test("cursor encode produces non-empty string")
    func cursorEncode() {
        let encoded = Cursor.encode(offset: 0)
        #expect(!encoded.isEmpty)
    }
}
