import Testing
import MCP
@testable import OmniFocusMCPServer

@Suite("ToolRouter")
struct ToolRouterTests {
    private func makeRouter(mode: CapabilityMode = .pro) async -> (ToolRouter, MockBridge) {
        let bridge = MockBridge()
        bridge.mockMode = mode
        let cache = TTLCache(enabled: true)
        let config = Configuration.load()
        let router = ToolRouter(bridge: bridge, cache: cache, config: config)
        await router.detectMode()
        return (router, bridge)
    }

    @Test("diagnostics returns server info")
    func diagnostics() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "diagnostics", arguments: nil)
        let text = extractText(result)
        #expect(text.contains("omnifocusRunning"))
        #expect(text.contains("\"mode\""))
        #expect(result.isError != true)
    }

    @Test("list_inbox calls bridge and returns result")
    func listInbox() async {
        let (router, bridge) = await makeRouter()
        bridge.jsResults["inInbox"] = """
        {"items": [{"id": "abc", "name": "Test"}], "totalCount": 1}
        """
        let result = await router.handle(name: "list_inbox", arguments: [
            "limit": .int(10),
        ])
        let text = extractText(result)
        #expect(text.contains("abc"))
        #expect(bridge.callCount == 1)
    }

    @Test("Pro-required tools fail in standard mode")
    func standardModeBlock() async {
        let (router, _) = await makeRouter(mode: .standard)
        let result = await router.handle(name: "list_inbox", arguments: nil)
        let text = extractText(result)
        #expect(text.contains("capability_unavailable"))
        #expect(result.isError == true)
    }

    @Test("standard mode tools work without Pro")
    func standardModePass() async {
        let (router, _) = await makeRouter(mode: .standard)
        let result = await router.handle(name: "open_task_url", arguments: [
            "id": .string("abc123"),
        ])
        // Should not error with capability_unavailable
        let text = extractText(result)
        #expect(!text.contains("capability_unavailable"))
    }

    @Test("get_task_by_id requires id parameter")
    func getTaskNoId() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "get_task_by_id", arguments: [:])
        let text = extractText(result)
        #expect(text.contains("invalid_input"))
    }

    @Test("create_task requires name parameter")
    func createTaskNoName() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "create_task", arguments: [:])
        let text = extractText(result)
        #expect(text.contains("invalid_input"))
    }

    @Test("update_task dry_run returns preview with token")
    func updateDryRun() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "update_task", arguments: [
            "id": .string("abc123"),
            "patch": .object(["status": .string("complete")]),
        ])
        let text = extractText(result)
        #expect(text.contains("dry_run"))
        #expect(text.contains("confirm_token"))
    }

    @Test("update_task without token fails for destructive ops")
    func updateNoToken() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "update_task", arguments: [
            "id": .string("abc123"),
            "patch": .object(["status": .string("complete")]),
            "dry_run": .bool(false),
        ])
        let text = extractText(result)
        #expect(text.contains("confirm_token"))
    }

    @Test("cached results avoid bridge call")
    func cacheHit() async {
        let (router, bridge) = await makeRouter()
        bridge.jsResults["inInbox"] = """
        {"items": [], "totalCount": 0}
        """
        // First call hits bridge
        _ = await router.handle(name: "list_inbox", arguments: ["limit": .int(10)])
        #expect(bridge.callCount == 1)

        // Second call should hit cache
        _ = await router.handle(name: "list_inbox", arguments: ["limit": .int(10)])
        #expect(bridge.callCount == 1)
    }

    @Test("mutation invalidates cache")
    func mutationInvalidatesCache() async {
        let (router, bridge) = await makeRouter()
        bridge.jsResults["inInbox"] = """
        {"items": [], "totalCount": 0}
        """
        bridge.jsResults["inbox"] = """
        {"id": "new1", "name": "Test", "url": "omnifocus:///task/new1"}
        """

        // Prime cache
        _ = await router.handle(name: "list_inbox", arguments: ["limit": .int(10)])
        #expect(bridge.callCount == 1)

        // Mutate
        _ = await router.handle(name: "create_task", arguments: [
            "name": .string("Test"),
        ])

        // Cache should be invalidated, so this hits bridge again
        _ = await router.handle(name: "list_inbox", arguments: ["limit": .int(10)])
        #expect(bridge.callCount == 3)
    }

    @Test("update_project dry_run returns preview with token")
    func updateProjectDryRun() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "update_project", arguments: [
            "id": .string("proj1"),
            "patch": .object(["status": .string("complete")]),
        ])
        let text = extractText(result)
        #expect(text.contains("dry_run"))
        #expect(text.contains("confirm_token"))
        #expect(text.contains("project_id"))
    }

    @Test("update_project without token fails for destructive ops")
    func updateProjectNoToken() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "update_project", arguments: [
            "id": .string("proj1"),
            "patch": .object(["status": .string("drop")]),
            "dry_run": .bool(false),
        ])
        let text = extractText(result)
        #expect(text.contains("confirm_token"))
    }

    @Test("update_project requires id parameter")
    func updateProjectNoId() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "update_project", arguments: [:])
        let text = extractText(result)
        #expect(text.contains("invalid_input"))
    }

    @Test("unknown tool returns error")
    func unknownTool() async {
        let (router, _) = await makeRouter()
        let result = await router.handle(name: "nonexistent_tool", arguments: nil)
        let text = extractText(result)
        #expect(text.contains("Unknown tool"))
        #expect(result.isError == true)
    }

    // MARK: - Helpers

    private func extractText(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined()
    }
}
