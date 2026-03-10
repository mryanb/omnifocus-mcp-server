import Testing
@testable import OmniFocusMCPServer

@Suite("ConfirmTokenManager")
struct ConfirmTokenTests {
    @Test("generate produces non-empty token")
    func generate() async {
        let mgr = ConfirmTokenManager()
        let token = await mgr.generate(taskId: "abc123", patchHash: "hash1")
        #expect(!token.isEmpty)
        #expect(token.contains("."))
    }

    @Test("verify accepts valid token")
    func verifyValid() async {
        let mgr = ConfirmTokenManager()
        let token = await mgr.generate(taskId: "abc123", patchHash: "hash1")
        let valid = await mgr.verify(token: token, taskId: "abc123", patchHash: "hash1")
        #expect(valid)
    }

    @Test("verify rejects wrong task ID")
    func verifyWrongTaskId() async {
        let mgr = ConfirmTokenManager()
        let token = await mgr.generate(taskId: "abc123", patchHash: "hash1")
        let valid = await mgr.verify(token: token, taskId: "WRONG", patchHash: "hash1")
        #expect(!valid)
    }

    @Test("verify rejects wrong patch hash")
    func verifyWrongPatch() async {
        let mgr = ConfirmTokenManager()
        let token = await mgr.generate(taskId: "abc123", patchHash: "hash1")
        let valid = await mgr.verify(token: token, taskId: "abc123", patchHash: "WRONG")
        #expect(!valid)
    }

    @Test("token is single-use")
    func singleUse() async {
        let mgr = ConfirmTokenManager()
        let token = await mgr.generate(taskId: "abc123", patchHash: "hash1")
        let first = await mgr.verify(token: token, taskId: "abc123", patchHash: "hash1")
        let second = await mgr.verify(token: token, taskId: "abc123", patchHash: "hash1")
        #expect(first)
        #expect(!second)
    }

    @Test("verify rejects garbage token")
    func verifyGarbage() async {
        let mgr = ConfirmTokenManager()
        let valid = await mgr.verify(token: "garbage.token", taskId: "abc", patchHash: "hash")
        #expect(!valid)
    }

    @Test("patchRequiresConfirmation detects destructive ops")
    func destructiveCheck() {
        #expect(patchRequiresConfirmation(["status": "complete"]))
        #expect(patchRequiresConfirmation(["status": "drop"]))
        #expect(!patchRequiresConfirmation(["status": "active"]))
        #expect(!patchRequiresConfirmation(["name": "new name"]))
        #expect(!patchRequiresConfirmation(["flagged": true]))
        #expect(!patchRequiresConfirmation([:]))
    }

    @Test("hashPatch is deterministic")
    func hashDeterminism() {
        let hash1 = ConfirmTokenManager.hashPatch(["name": "a", "flagged": true])
        let hash2 = ConfirmTokenManager.hashPatch(["flagged": true, "name": "a"])
        #expect(hash1 == hash2)
    }
}
