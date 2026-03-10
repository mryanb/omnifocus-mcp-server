import Foundation
import MCP

/// Routes MCP tool calls to their implementations.
/// Holds references to the bridge, cache, config, and confirm token manager.
actor ToolRouter {
    let bridge: OmniFocusAutomation
    let cache: TTLCache
    let config: Configuration
    let confirmTokens: ConfirmTokenManager
    private(set) var mode: CapabilityMode = .unknown

    init(bridge: OmniFocusAutomation, cache: TTLCache, config: Configuration) {
        self.bridge = bridge
        self.cache = cache
        self.config = config
        self.confirmTokens = ConfirmTokenManager()
    }

    /// Detect capability mode at startup.
    func detectMode() async {
        mode = await bridge.detectCapability()
        Log.info("Capability mode: \(mode.rawValue)")
    }

    /// Route a tool call to its handler.
    func handle(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        Log.debug("Tool call: \(name)", tool: name)

        // Check tool is allowed
        guard config.isToolAllowed(name) else {
            return errorResult(StructuredError(.configDisabled, "Tool '\(name)' is not in the allowlist"))
        }

        // Check Pro requirement
        let proRequired: Set<String> = [
            "list_inbox", "list_today", "list_flagged", "list_forecast",
            "list_projects", "list_tags", "list_perspectives", "get_perspective_tasks",
            "get_task_by_id", "search_tasks", "get_task_count",
            "create_task", "update_task", "batch_update_tasks",
        ]
        if proRequired.contains(name) && mode != .pro {
            return errorResult(OFMCPError.proRequired(name).structured)
        }

        do {
            switch name {
            case "diagnostics":
                return try await handleDiagnostics()
            case "list_inbox":
                return try await handleListInbox(arguments)
            case "list_today":
                return try await handleListToday(arguments)
            case "list_flagged":
                return try await handleListFlagged(arguments)
            case "list_forecast":
                return try await handleListForecast(arguments)
            case "list_projects":
                return try await handleListProjects(arguments)
            case "list_tags":
                return try await handleListTags(arguments)
            case "list_perspectives":
                return try await handleListPerspectives()
            case "get_perspective_tasks":
                return try await handleGetPerspectiveTasks(arguments)
            case "get_task_by_id":
                return try await handleGetTaskById(arguments)
            case "search_tasks":
                return try await handleSearchTasks(arguments)
            case "get_task_count":
                return try await handleGetTaskCount(arguments)
            case "create_task":
                return try await handleCreateTask(arguments)
            case "update_task":
                return try await handleUpdateTask(arguments)
            case "batch_update_tasks":
                return try await handleBatchUpdateTasks(arguments)
            case "create_task_via_url":
                return try await handleCreateTaskViaURL(arguments)
            case "open_task_url":
                return try await handleOpenTaskURL(arguments)
            default:
                return errorResult(StructuredError(.invalidInput, "Unknown tool: \(name)"))
            }
        } catch let error as OFMCPError {
            Log.error("\(error)", tool: name)
            return errorResult(error.structured)
        } catch {
            Log.error("Unexpected: \(error)", tool: name)
            return errorResult(StructuredError(.internalError, "Internal error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Diagnostics

    private func handleDiagnostics() async throws -> CallTool.Result {
        let isRunning = await bridge.isOmniFocusRunning()
        let version = await bridge.omniFocusVersion()
        let cacheStats = await cache.getStats()

        let toolNames = ToolSchemas.tools(mode: mode, config: config).map { $0.name }

        let result: [String: Any] = [
            "mode": mode.rawValue,
            "omnifocusRunning": isRunning,
            "omnifocusVersion": version ?? "unknown",
            "serverVersion": ServerInfo.version,
            "protocolVersion": "2025-11-25",
            "cacheStats": [
                "entries": cacheStats.entries,
                "hits": cacheStats.hits,
                "misses": cacheStats.misses,
                "evictions": cacheStats.evictions,
            ],
            "enabledTools": toolNames,
            "permissions": [
                "bulkOps": config.bulkOpsEnabled,
                "delete": config.deleteEnabled,
            ],
        ]

        return textResult(toJSON(result))
    }

    // MARK: - List Tools

    private func handleListInbox(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "list_inbox", args: ["limit": "\(limit)", "offset": "\(offset)", "fields": "\(fields.hashValue)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listInbox(fields: fields, limit: limit, offset: offset)
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.inbox)
        return textResult(response)
    }

    private func handleListToday(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "list_today", args: ["limit": "\(limit)", "offset": "\(offset)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listToday(fields: fields, limit: limit, offset: offset)
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.today)
        return textResult(response)
    }

    private func handleListFlagged(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "list_flagged", args: ["limit": "\(limit)", "offset": "\(offset)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listFlagged(fields: fields, limit: limit, offset: offset)
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.flagged)
        return textResult(response)
    }

    private func handleListForecast(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "list_forecast", args: ["limit": "\(limit)", "offset": "\(offset)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listForecast(fields: fields, limit: limit, offset: offset)
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.today)
        return textResult(response)
    }

    private func handleListPerspectives() async throws -> CallTool.Result {
        let cacheKey = TTLCache.key(tool: "list_perspectives", args: [:])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listPerspectives()
        let result = try await bridge.evaluateJS(js)
        await cache.set(key: cacheKey, value: result, ttl: CacheTTL.tags)
        return textResult(result)
    }

    private func handleGetPerspectiveTasks(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let perspectiveId = args?["id"]?.stringValue, !perspectiveId.isEmpty else {
            throw OFMCPError.invalidInput("'id' is required")
        }
        guard let perspectiveType = args?["type"]?.stringValue, !perspectiveType.isEmpty else {
            throw OFMCPError.invalidInput("'type' is required (custom or built_in)")
        }
        guard perspectiveType == "custom" || perspectiveType == "built_in" else {
            throw OFMCPError.invalidInput("'type' must be 'custom' or 'built_in'")
        }

        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "get_perspective_tasks", args: [
            "id": perspectiveId, "type": perspectiveType,
            "limit": "\(limit)", "offset": "\(offset)", "fields": "\(fields.hashValue)",
        ])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listPerspectiveTasks(
            perspectiveId: perspectiveId,
            perspectiveType: perspectiveType,
            fields: fields,
            limit: limit,
            offset: offset
        )
        let result = try await bridge.evaluateJS(js)

        // Check for errors
        if result.contains("\"error\"") {
            if result.contains("no_window") {
                throw OFMCPError.omnifocusEvalFailed("OmniFocus has no open windows. Open a window and try again.")
            }
            if result.contains("not_found") {
                throw OFMCPError.omnifocusEvalFailed("Perspective not found: \(perspectiveId)")
            }
        }

        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.today)
        return textResult(response)
    }

    private func handleListProjects(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let status = args?["status"]?.stringValue ?? "active"
        let cacheKey = TTLCache.key(tool: "list_projects", args: ["limit": "\(limit)", "offset": "\(offset)", "status": status])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let fields = projectFields(args)
        let js = JSBuilder.listProjects(status: status, fields: fields, limit: limit, offset: offset)
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.projects)
        return textResult(response)
    }

    private func handleListTags(_ args: [String: Value]?) async throws -> CallTool.Result {
        let limit = clampLimit(args?["limit"]?.intValue)
        let cacheKey = TTLCache.key(tool: "list_tags", args: ["limit": "\(limit)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.listTags(limit: limit)
        let result = try await bridge.evaluateJS(js)
        await cache.set(key: cacheKey, value: result, ttl: CacheTTL.tags)
        return textResult(result)
    }

    // MARK: - Get / Search

    private func handleGetTaskById(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let id = args?["id"]?.stringValue, !id.isEmpty else {
            throw OFMCPError.invalidInput("'id' is required")
        }
        let fields = taskFields(args)
        let cacheKey = TTLCache.key(tool: "get_task_by_id", args: ["id": id, "fields": "\(fields.hashValue)"])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.getTaskById(id: id, fields: fields)
        let result = try await bridge.evaluateJS(js)

        // Check for not_found
        if result.contains("\"error\"") && result.contains("not_found") {
            throw OFMCPError.taskNotFound(id)
        }

        await cache.set(key: cacheKey, value: result, ttl: CacheTTL.singleTask)
        return textResult(result)
    }

    private func handleSearchTasks(_ args: [String: Value]?) async throws -> CallTool.Result {
        let (limit, offset) = pagination(args)
        let fields = taskFields(args)
        let query = args?["query"]?.stringValue
        let project = args?["project"]?.stringValue
        let tag = args?["tag"]?.stringValue
        let flagged = args?["flagged"]?.boolValue
        let completed = args?["completed"]?.boolValue
        let dueBefore = args?["due_before"]?.stringValue
        let dueAfter = args?["due_after"]?.stringValue
        let status = args?["status"]?.stringValue

        let cacheKey = TTLCache.key(tool: "search_tasks", args: [
            "q": query ?? "", "proj": project ?? "", "tag": tag ?? "",
            "f": flagged.map { "\($0)" } ?? "", "c": completed.map { "\($0)" } ?? "",
            "db": dueBefore ?? "", "da": dueAfter ?? "", "s": status ?? "",
            "l": "\(limit)", "o": "\(offset)",
        ])

        if let cached = await cache.get(key: cacheKey) {
            return textResult(cached)
        }

        let js = JSBuilder.searchTasks(
            query: query, project: project, tag: tag,
            flagged: flagged, completed: completed,
            dueBefore: dueBefore, dueAfter: dueAfter, status: status,
            fields: fields, limit: limit, offset: offset
        )
        let result = try await bridge.evaluateJS(js)
        let response = wrapPagination(result, limit: limit, offset: offset)
        await cache.set(key: cacheKey, value: response, ttl: CacheTTL.search)
        return textResult(response)
    }

    private func handleGetTaskCount(_ args: [String: Value]?) async throws -> CallTool.Result {
        let project = args?["project"]?.stringValue
        let tag = args?["tag"]?.stringValue
        let flagged = args?["flagged"]?.boolValue
        let completed = args?["completed"]?.boolValue
        let inbox = args?["inbox"]?.boolValue

        let js = JSBuilder.countTasks(
            project: project, tag: tag, flagged: flagged,
            completed: completed, inbox: inbox, status: nil
        )
        let result = try await bridge.evaluateJS(js)
        return textResult(result)
    }

    // MARK: - Mutations

    private func handleCreateTask(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let name = args?["name"]?.stringValue, !name.isEmpty else {
            throw OFMCPError.invalidInput("'name' is required and must not be empty")
        }

        let js = JSBuilder.createTask(
            name: name,
            note: args?["note"]?.stringValue,
            projectId: args?["projectId"]?.stringValue,
            parentId: args?["parentId"]?.stringValue,
            tagIds: args?["tagIds"]?.arrayValue?.compactMap { $0.stringValue },
            tagNames: args?["tagNames"]?.arrayValue?.compactMap { $0.stringValue },
            dueDate: args?["dueDate"]?.stringValue,
            deferDate: args?["deferDate"]?.stringValue,
            flagged: args?["flagged"]?.boolValue,
            estimatedMinutes: args?["estimatedMinutes"]?.intValue
        )

        let result = try await bridge.evaluateJS(js)

        // Check for errors in result
        if result.contains("\"error\"") {
            throw OFMCPError.omnifocusEvalFailed(result)
        }

        // Invalidate caches on mutation
        await cache.invalidateAll()
        Log.info("Task created: \(name)", tool: "create_task")

        return textResult(result)
    }

    private func handleUpdateTask(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let id = args?["id"]?.stringValue, !id.isEmpty else {
            throw OFMCPError.invalidInput("'id' is required")
        }
        guard let patchValue = args?["patch"] else {
            throw OFMCPError.invalidInput("'patch' is required")
        }

        let dryRun = args?["dry_run"]?.boolValue ?? true
        let confirmToken = args?["confirm_token"]?.stringValue

        // Convert patch Value to [String: Any]
        let patch = valueToDictionary(patchValue)

        let requiresConfirm = patchRequiresConfirmation(patch)
        let patchHash = ConfirmTokenManager.hashPatch(patch)

        if dryRun {
            // Preview mode: return what would change + confirm_token if needed
            let token = requiresConfirm ? await confirmTokens.generate(taskId: id, patchHash: patchHash) : nil

            var preview: [String: Any] = [
                "dry_run": true,
                "task_id": id,
                "changes": patch,
                "requires_confirmation": requiresConfirm,
            ]
            if let token {
                preview["confirm_token"] = token
                preview["message"] = "This operation includes irreversible status change(s). Re-call with dry_run=false and this confirm_token to apply."
            } else {
                preview["message"] = "Re-call with dry_run=false to apply these changes."
            }
            return textResult(toJSON(preview))
        }

        // Apply mode
        if requiresConfirm {
            guard let token = confirmToken else {
                throw OFMCPError.invalidInput("Status transitions require confirm_token from a dry_run. Call with dry_run=true first.")
            }
            let valid = await confirmTokens.verify(token: token, taskId: id, patchHash: patchHash)
            guard valid else {
                throw OFMCPError.invalidConfirmToken
            }
        }

        let js = JSBuilder.updateTask(id: id, patch: patch)
        let result = try await bridge.evaluateJS(js)

        if result.contains("\"error\"") && result.contains("not_found") {
            throw OFMCPError.taskNotFound(id)
        }

        await cache.invalidateAll()
        Log.info("Task updated: \(id)", tool: "update_task")

        return textResult(result)
    }

    private func handleBatchUpdateTasks(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard config.bulkOpsEnabled else {
            throw OFMCPError.configDisabled("bulk_ops")
        }

        guard let updates = args?["updates"]?.arrayValue, !updates.isEmpty else {
            throw OFMCPError.invalidInput("'updates' array is required and must not be empty")
        }
        guard updates.count <= 25 else {
            throw OFMCPError.invalidInput("Maximum 25 updates per batch")
        }

        let dryRun = args?["dry_run"]?.boolValue ?? true

        var results: [[String: Any]] = []
        for update in updates {
            guard let id = update.objectValue?["id"]?.stringValue else {
                results.append(["error": "missing id"])
                continue
            }
            guard let patchValue = update.objectValue?["patch"] else {
                results.append(["error": "missing patch", "id": id])
                continue
            }

            let patch = valueToDictionary(patchValue)

            if dryRun {
                results.append(["id": id, "changes": patch, "dry_run": true])
            } else {
                let js = JSBuilder.updateTask(id: id, patch: patch)
                do {
                    let result = try await bridge.evaluateJS(js)
                    results.append(["id": id, "result": result])
                } catch {
                    results.append(["id": id, "error": "\(error)"])
                }
            }
        }

        if !dryRun {
            await cache.invalidateAll()
            Log.info("Batch update: \(updates.count) tasks", tool: "batch_update_tasks")
        }

        return textResult(toJSON(["updates": results, "dry_run": dryRun]))
    }

    // MARK: - Standard Mode Tools

    private func handleCreateTaskViaURL(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let name = args?["name"]?.stringValue, !name.isEmpty else {
            throw OFMCPError.invalidInput("'name' is required")
        }

        guard let url = OmniFocusURL.addTaskURL(
            name: name,
            note: args?["note"]?.stringValue,
            project: args?["project"]?.stringValue,
            tags: args?["tags"]?.arrayValue?.compactMap { $0.stringValue },
            dueDate: args?["dueDate"]?.stringValue,
            deferDate: args?["deferDate"]?.stringValue,
            flagged: args?["flagged"]?.boolValue,
            estimatedMinutes: args?["estimatedMinutes"]?.intValue
        ) else {
            throw OFMCPError.invalidInput("Failed to build URL")
        }

        OmniFocusURL.open(url)
        Log.info("Task created via URL: \(name)", tool: "create_task_via_url")

        return textResult(toJSON([
            "created": true,
            "name": name,
            "url": url.absoluteString,
            "note": "Task created via URL scheme. ID is not available via this method.",
        ]))
    }

    private func handleOpenTaskURL(_ args: [String: Value]?) async throws -> CallTool.Result {
        guard let id = args?["id"]?.stringValue, !id.isEmpty else {
            throw OFMCPError.invalidInput("'id' is required")
        }

        guard let url = OmniFocusURL.taskURL(id: id) else {
            throw OFMCPError.invalidInput("Failed to build URL for id '\(id)'")
        }

        OmniFocusURL.open(url)

        return textResult(toJSON(["opened": true, "url": url.absoluteString]))
    }

    // MARK: - Helpers

    private func pagination(_ args: [String: Value]?) -> (limit: Int, offset: Int) {
        let limit = clampLimit(args?["limit"]?.intValue)
        let offset: Int
        if let cursor = args?["cursor"]?.stringValue {
            offset = Cursor.decode(cursor) ?? 0
        } else {
            offset = 0
        }
        return (limit, offset)
    }

    private func clampLimit(_ value: Int?) -> Int {
        let raw = value ?? config.defaultLimit
        return max(1, min(raw, config.maxLimit))
    }

    private func taskFields(_ args: [String: Value]?) -> Set<TaskFieldSet> {
        guard let fieldArray = args?["fields"]?.arrayValue else {
            return TaskFieldSet.minimal
        }
        let names = fieldArray.compactMap { $0.stringValue }
        if names.isEmpty { return TaskFieldSet.minimal }
        var fields: Set<TaskFieldSet> = []
        for name in names {
            if let field = TaskFieldSet(rawValue: name) {
                fields.insert(field)
            }
        }
        return fields.isEmpty ? TaskFieldSet.minimal : fields
    }

    private func projectFields(_ args: [String: Value]?) -> Set<ProjectFieldSet> {
        guard let fieldArray = args?["fields"]?.arrayValue else {
            return ProjectFieldSet.minimal
        }
        let names = fieldArray.compactMap { $0.stringValue }
        if names.isEmpty { return ProjectFieldSet.minimal }
        var fields: Set<ProjectFieldSet> = []
        for name in names {
            if let field = ProjectFieldSet(rawValue: name) {
                fields.insert(field)
            }
        }
        return fields.isEmpty ? ProjectFieldSet.minimal : fields
    }

    /// Wrap a JS result that has {items, totalCount} with cursor pagination.
    private func wrapPagination(_ jsonResult: String, limit: Int, offset: Int) -> String {
        guard let data = jsonResult.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return jsonResult
        }

        let totalCount = dict["totalCount"] as? Int ?? 0
        let nextOffset = offset + limit
        let hasMore = nextOffset < totalCount

        dict["hasMore"] = hasMore
        if hasMore {
            dict["cursor"] = Cursor.encode(offset: nextOffset)
        }

        return toJSON(dict)
    }

    private func textResult(_ text: String) -> CallTool.Result {
        .init(content: [.text(text)])
    }

    private func errorResult(_ error: StructuredError) -> CallTool.Result {
        let json = toJSON([
            "error": [
                "category": error.category.rawValue,
                "message": error.message,
                "retryable": error.retryable,
            ] as [String: Any],
        ])
        return .init(content: [.text(json)], isError: true)
    }

    /// Convert a Value to a [String: Any] dictionary for patch handling.
    private func valueToDictionary(_ value: Value) -> [String: Any] {
        guard let obj = value.objectValue else { return [:] }
        var dict: [String: Any] = [:]
        for (key, val) in obj {
            switch val {
            case .string(let s): dict[key] = s
            case .int(let i): dict[key] = i
            case .double(let d): dict[key] = d
            case .bool(let b): dict[key] = b
            case .null: dict[key] = NSNull()
            case .array(let arr): dict[key] = arr.compactMap { $0.stringValue }
            default: break
            }
        }
        return dict
    }
}

// MARK: - JSON Serialization Helper

func toJSON(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let str = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return str
}

// MARK: - Value Extension

extension Value {
    var objectValue: [String: Value]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    var arrayValue: [Value]? {
        if case .array(let arr) = self { return arr }
        return nil
    }
}
