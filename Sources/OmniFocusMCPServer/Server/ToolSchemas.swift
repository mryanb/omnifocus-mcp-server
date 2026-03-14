import MCP

/// All tool definitions with JSON schemas for the MCP server.
enum ToolSchemas {
    /// Build the list of tools based on capability mode and configuration.
    static func tools(mode: CapabilityMode, config: Configuration) -> [Tool] {
        var tools: [Tool] = []

        // Always available
        tools.append(diagnosticsTool)

        if mode == .pro {
            // Read tools
            tools.append(listInboxTool)
            tools.append(listTodayTool)
            tools.append(listFlaggedTool)
            tools.append(listForecastTool)
            tools.append(listProjectsTool)
            tools.append(listTagsTool)
            tools.append(listPerspectivesTool)
            tools.append(getPerspectiveTasksTool)
            tools.append(getTaskByIdTool)
            tools.append(searchTasksTool)
            tools.append(getTaskCountTool)

            // Mutation tools
            tools.append(createTaskTool)
            tools.append(updateTaskTool)
            tools.append(updateProjectTool)

            // Batch tools (config-gated)
            if config.bulkOpsEnabled {
                tools.append(batchUpdateTasksTool)
            }
        }

        // Standard mode tools (always available)
        tools.append(createTaskViaURLTool)
        tools.append(openTaskURLTool)

        // Filter by allowlist
        if let allowlist = config.toolAllowlist {
            tools = tools.filter { allowlist.contains($0.name) || $0.name == "diagnostics" }
        }

        return tools
    }

    // MARK: - Shared Schema Components

    private static let limitProperty: (String, Value) = (
        "limit", .object([
            "type": "integer",
            "description": "Maximum results to return",
            "default": 50,
            "minimum": 1,
            "maximum": 200,
        ])
    )

    private static let cursorProperty: (String, Value) = (
        "cursor", .object([
            "type": "string",
            "description": "Pagination cursor from previous response",
        ])
    )

    private static let taskFieldsProperty: (String, Value) = (
        "fields", .object([
            "type": "array",
            "items": .object([
                "type": "string",
                "enum": .array([
                    "id", "name", "note", "status", "flagged", "completed",
                    "dueDate", "deferDate", "estimatedMinutes", "projectName",
                    "tagNames", "tagIds", "url", "parentId", "projectId",
                    "hasChildren", "sequential", "completionDate", "dropped",
                ].map { Value.string($0) }),
            ]),
            "description": "Fields to include. Default: minimal set (id, name, status, flagged, dueDate)",
        ])
    )

    // MARK: - Tool Definitions

    static let diagnosticsTool = Tool(
        name: "diagnostics",
        description: "Server health, OmniFocus connection, capability mode, cache stats",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listInboxTool = Tool(
        name: "list_inbox",
        description: "List tasks in the OmniFocus inbox",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listTodayTool = Tool(
        name: "list_today",
        description: "List tasks due today or deferred until today",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listFlaggedTool = Tool(
        name: "list_flagged",
        description: "List flagged, incomplete tasks",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listProjectsTool = Tool(
        name: "list_projects",
        description: "List OmniFocus projects",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                "status": .object([
                    "type": "string",
                    "enum": .array(["active", "on_hold", "completed", "dropped", "all"].map { Value.string($0) }),
                    "default": "active",
                ]),
                "fields": .object([
                    "type": "array",
                    "items": .object([
                        "type": "string",
                        "enum": .array([
                            "id", "name", "status", "note", "sequential",
                            "dueDate", "deferDate", "taskCount",
                            "folderId", "folderName", "url",
                        ].map { Value.string($0) }),
                    ]),
                ]),
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listTagsTool = Tool(
        name: "list_tags",
        description: "List OmniFocus tags",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                "fields": .object([
                    "type": "array",
                    "items": .object([
                        "type": "string",
                        "enum": .array(["id", "name", "parentId", "taskCount"].map { Value.string($0) }),
                    ]),
                ]),
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listForecastTool = Tool(
        name: "list_forecast",
        description: "Get a forecast view: overdue tasks + due today + flagged, sorted by due date. Great for daily planning",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let listPerspectivesTool = Tool(
        name: "list_perspectives",
        description: "List all OmniFocus perspectives",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let getPerspectiveTasksTool = Tool(
        name: "get_perspective_tasks",
        description: "Get tasks shown in a specific OmniFocus perspective. Uses the Window content tree API to read exactly what the perspective displays. Requires at least one open OmniFocus window.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "id": .object([
                    "type": "string",
                    "description": "Perspective identifier: primaryKey for custom perspectives, or name for built-in (e.g. 'Inbox', 'Flagged'). Use list_perspectives to discover available IDs.",
                ]),
                "type": .object([
                    "type": "string",
                    "enum": .array(["custom", "built_in"].map { Value.string($0) }),
                    "description": "Whether this is a 'custom' or 'built_in' perspective",
                ]),
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "required": .array([.string("id"), .string("type")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let getTaskByIdTool = Tool(
        name: "get_task_by_id",
        description: "Get a single task by its stable OmniFocus ID",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "id": .object([
                    "type": "string",
                    "description": "OmniFocus task primary key",
                ]),
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "required": .array([.string("id")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let searchTasksTool = Tool(
        name: "search_tasks",
        description: "Search tasks with filters. All filters combine with AND logic",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "query": .object(["type": "string", "description": "Text search in name and note"]),
                "project": .object(["type": "string", "description": "Project name (substring match)"]),
                "tag": .object(["type": "string", "description": "Tag name (exact match)"]),
                "flagged": .object(["type": "boolean"]),
                "completed": .object(["type": "boolean", "default": false]),
                "due_before": .object(["type": "string", "format": "date-time"]),
                "due_after": .object(["type": "string", "format": "date-time"]),
                "status": .object([
                    "type": "string",
                    "enum": .array(["available", "blocked", "completed", "dropped", "any"].map { Value.string($0) }),
                    "default": "available",
                ]),
                limitProperty.0: limitProperty.1,
                cursorProperty.0: cursorProperty.1,
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let getTaskCountTool = Tool(
        name: "get_task_count",
        description: "Get count of tasks matching filters without returning task data",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "project": .object(["type": "string"]),
                "tag": .object(["type": "string"]),
                "flagged": .object(["type": "boolean"]),
                "completed": .object(["type": "boolean", "default": false]),
                "inbox": .object(["type": "boolean"]),
            ]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )

    static let createTaskTool = Tool(
        name: "create_task",
        description: "Create a new task in OmniFocus inbox or a specific project",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "name": .object(["type": "string", "minLength": 1]),
                "note": .object(["type": "string"]),
                "projectId": .object(["type": "string", "description": "Target project ID. Omit for inbox"]),
                "parentId": .object(["type": "string", "description": "Parent task ID for subtasks"]),
                "tagIds": .object(["type": "array", "items": .object(["type": "string"])]),
                "tagNames": .object(["type": "array", "items": .object(["type": "string"]), "description": "Tag names (created if missing)"]),
                "dueDate": .object(["type": "string", "format": "date-time"]),
                "deferDate": .object(["type": "string", "format": "date-time"]),
                "flagged": .object(["type": "boolean", "default": false]),
                "estimatedMinutes": .object(["type": "integer", "minimum": 0]),
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: false)
    )

    static let updateTaskTool = Tool(
        name: "update_task",
        description: "Update a task using patch semantics. Only provided fields change. Status transitions (complete/drop) require confirm_token from a dry_run",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "id": .object(["type": "string", "description": "Stable OmniFocus task ID"]),
                "patch": .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string", "minLength": 1]),
                        "note": .object(["type": "string"]),
                        "flagged": .object(["type": "boolean"]),
                        "dueDate": .object(["type": .array(["string", "null"].map { Value.string($0) })]),
                        "deferDate": .object(["type": .array(["string", "null"].map { Value.string($0) })]),
                        "estimatedMinutes": .object(["type": .array(["integer", "null"].map { Value.string($0) })]),
                        "tagIds": .object(["type": "array", "items": .object(["type": "string"])]),
                        "projectId": .object(["type": .array(["string", "null"].map { Value.string($0) }), "description": "Move task to a project by ID, or null to move to Inbox"]),
                        "status": .object([
                            "type": "string",
                            "enum": .array(["complete", "drop", "active"].map { Value.string($0) }),
                            "description": "Transition task status. complete/drop are irreversible and require confirm_token",
                        ]),
                    ]),
                    "additionalProperties": false,
                ]),
                "dry_run": .object([
                    "type": "boolean",
                    "default": true,
                    "description": "When true, returns preview without applying. Default true for safety",
                ]),
                "confirm_token": .object([
                    "type": "string",
                    "description": "Token from dry_run. Required for irreversible status transitions",
                ]),
                taskFieldsProperty.0: taskFieldsProperty.1,
            ]),
            "required": .array([.string("id"), .string("patch")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: false)
    )

    static let updateProjectTool = Tool(
        name: "update_project",
        description: "Update a project using patch semantics. Only provided fields change. Status transitions (complete/drop) require confirm_token from a dry_run",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "id": .object(["type": "string", "description": "Stable OmniFocus project ID"]),
                "patch": .object([
                    "type": "object",
                    "properties": .object([
                        "name": .object(["type": "string", "minLength": 1]),
                        "note": .object(["type": "string"]),
                        "dueDate": .object(["type": .array(["string", "null"].map { Value.string($0) })]),
                        "deferDate": .object(["type": .array(["string", "null"].map { Value.string($0) })]),
                        "sequential": .object(["type": "boolean"]),
                        "status": .object([
                            "type": "string",
                            "enum": .array(["active", "on_hold", "complete", "drop"].map { Value.string($0) }),
                            "description": "Transition project status. complete/drop are irreversible and require confirm_token",
                        ]),
                    ]),
                    "additionalProperties": false,
                ]),
                "dry_run": .object([
                    "type": "boolean",
                    "default": true,
                    "description": "When true, returns preview without applying. Default true for safety",
                ]),
                "confirm_token": .object([
                    "type": "string",
                    "description": "Token from dry_run. Required for irreversible status transitions",
                ]),
            ]),
            "required": .array([.string("id"), .string("patch")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: true, idempotentHint: false)
    )

    static let batchUpdateTasksTool = Tool(
        name: "batch_update_tasks",
        description: "Update multiple tasks. Max 25 per batch. Requires bulk_ops enabled",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "updates": .object([
                    "type": "array",
                    "items": .object([
                        "type": "object",
                        "properties": .object([
                            "id": .object(["type": "string"]),
                            "patch": .object(["type": "object"]),
                        ]),
                        "required": .array([.string("id"), .string("patch")]),
                    ]),
                    "minItems": 1,
                    "maxItems": 25,
                ]),
                "dry_run": .object(["type": "boolean", "default": true]),
                "confirm_token": .object(["type": "string"]),
            ]),
            "required": .array([.string("updates")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: true)
    )

    // MARK: - Standard Mode Tools (no Pro required)

    static let createTaskViaURLTool = Tool(
        name: "create_task_via_url",
        description: "Create a task via OmniFocus URL scheme (no Pro required). Opens OmniFocus",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "name": .object(["type": "string", "minLength": 1]),
                "note": .object(["type": "string"]),
                "project": .object(["type": "string", "description": "Project name"]),
                "tags": .object(["type": "array", "items": .object(["type": "string"])]),
                "dueDate": .object(["type": "string"]),
                "deferDate": .object(["type": "string"]),
                "flagged": .object(["type": "boolean"]),
                "estimatedMinutes": .object(["type": "integer"]),
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: false, destructiveHint: false)
    )

    static let openTaskURLTool = Tool(
        name: "open_task_url",
        description: "Open a task in OmniFocus by ID (no Pro required)",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "id": .object(["type": "string", "description": "OmniFocus task ID"]),
            ]),
            "required": .array([.string("id")]),
            "additionalProperties": false,
        ]),
        annotations: Tool.Annotations(readOnlyHint: true, destructiveHint: false)
    )
}
