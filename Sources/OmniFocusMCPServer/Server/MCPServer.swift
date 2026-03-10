import Foundation
import MCP

/// Server metadata.
enum ServerInfo {
    static let name = "omnifocus-mcp-server"
    static let version = "0.1.0"
}

/// Sets up and runs the MCP server with stdio transport.
func startMCPServer() async throws {
    let config = Configuration.load()
    Log.configure(from: config)

    Log.info("Starting \(ServerInfo.name) v\(ServerInfo.version)")

    let bridge = OmniFocusBridge()
    let cache = TTLCache(enabled: config.cacheEnabled)
    let router = ToolRouter(bridge: bridge, cache: cache, config: config)

    // Detect OmniFocus capability mode
    await router.detectMode()

    let mode = await router.mode

    // Create MCP server
    let server = Server(
        name: ServerInfo.name,
        version: ServerInfo.version,
        capabilities: Server.Capabilities(
            resources: .init(subscribe: false, listChanged: false),
            tools: .init(listChanged: false)
        )
    )

    // Register ListTools handler
    let currentMode = mode
    let currentConfig = config
    await server.withMethodHandler(ListTools.self) { _ in
        let tools = ToolSchemas.tools(mode: currentMode, config: currentConfig)
        return .init(tools: tools)
    }

    // Register CallTool handler
    await server.withMethodHandler(CallTool.self) { params in
        await router.handle(name: params.name, arguments: params.arguments)
    }

    // Register ListResources handler (empty for v1)
    await server.withMethodHandler(ListResources.self) { _ in
        .init(resources: [])
    }

    // Start stdio transport
    let transport = StdioTransport()
    Log.info("Starting stdio transport")

    try await server.start(transport: transport) { clientInfo, _ in
        Log.info("Client connected: \(clientInfo.name) \(clientInfo.version)")
    }

    Log.info("Server initialized, waiting for requests")
    await server.waitUntilCompleted()
    Log.info("Server shutting down")
}
