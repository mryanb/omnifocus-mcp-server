import Foundation

/// Builds Omni Automation JavaScript queries with proper escaping and field projection.
/// All queries return JSON strings for parsing.
enum JSBuilder {
    // MARK: - Task Queries

    /// Build JS to list inbox tasks with field projection and pagination.
    /// Uses `flattenedTasks` (global) filtered by `t.inInbox` since the Omni Automation
    /// context exposes `flattenedTasks`, `flattenedProjects`, `flattenedTags` as bare globals.
    static func listInbox(fields: Set<TaskFieldSet>, limit: Int, offset: Int) -> String {
        let projection = taskProjection(fields)
        return """
        (() => {
            const all = [];
            flattenedTasks.forEach(t => { if (t.inInbox && t.taskStatus !== Task.Status.Completed && t.taskStatus !== Task.Status.Dropped) all.push(t); });
            const total = all.length;
            const slice = all.slice(\(offset), \(offset + limit));
            const items = slice.map(t => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    /// Build JS to list tasks due today or deferred until today.
    static func listToday(fields: Set<TaskFieldSet>, limit: Int, offset: Int) -> String {
        let projection = taskProjection(fields)
        return """
        (() => {
            const now = new Date();
            const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            const endOfDay = new Date(startOfDay.getTime() + 86400000);
            const tasks = flattenedTasks.filter(t => {
                if (t.taskStatus !== Task.Status.Available && t.taskStatus !== Task.Status.DueSoon) return false;
                const due = t.dueDate;
                const defer_ = t.deferDate;
                return (due && due >= startOfDay && due < endOfDay) ||
                       (defer_ && defer_ <= now && (!due || due >= startOfDay));
            });
            const total = tasks.length;
            const slice = tasks.slice(\(offset), \(offset + limit));
            const items = slice.map(t => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    /// Build JS to list flagged, incomplete tasks.
    static func listFlagged(fields: Set<TaskFieldSet>, limit: Int, offset: Int) -> String {
        let projection = taskProjection(fields)
        return """
        (() => {
            const tasks = flattenedTasks.filter(t => t.flagged && t.taskStatus !== Task.Status.Completed && t.taskStatus !== Task.Status.Dropped);
            const total = tasks.length;
            const slice = tasks.slice(\(offset), \(offset + limit));
            const items = slice.map(t => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    /// Build JS to get a single task by ID.
    static func getTaskById(id: String, fields: Set<TaskFieldSet>) -> String {
        let escaped = id.jsEscaped
        let projection = taskProjection(fields)
        return """
        (() => {
            const t = Task.byIdentifier("\(escaped)");
            if (!t) return JSON.stringify({error: "not_found"});
            return JSON.stringify(\(projection));
        })()
        """
    }

    /// Build JS to search tasks with filters.
    static func searchTasks(
        query: String?,
        project: String?,
        tag: String?,
        flagged: Bool?,
        completed: Bool?,
        dueBefore: String?,
        dueAfter: String?,
        status: String?,
        fields: Set<TaskFieldSet>,
        limit: Int,
        offset: Int
    ) -> String {
        let projection = taskProjection(fields)
        var filters: [String] = []

        // Status-based filtering (defaults to "available" which excludes completed/dropped)
        switch status {
        case "any":
            break // No status filter
        case "completed":
            filters.append("t.taskStatus === Task.Status.Completed")
        case "dropped":
            filters.append("t.taskStatus === Task.Status.Dropped")
        case "blocked":
            filters.append("t.taskStatus === Task.Status.Blocked")
        default: // "available" or nil
            if completed == true {
                // Explicit override: include completed
            } else {
                filters.append("t.taskStatus !== Task.Status.Completed && t.taskStatus !== Task.Status.Dropped")
            }
        }

        if let query {
            let escaped = query.jsEscaped.lowercased()
            filters.append("(t.name.toLowerCase().includes(\"\(escaped)\") || (t.note && t.note.toLowerCase().includes(\"\(escaped)\")))")
        }
        if let project {
            let escaped = project.jsEscaped.lowercased()
            filters.append("(t.containingProject && t.containingProject.name.toLowerCase().includes(\"\(escaped)\"))")
        }
        if let tag {
            let escaped = tag.jsEscaped
            filters.append("t.tags.some(tag => tag.name === \"\(escaped)\")")
        }
        if let flagged {
            filters.append("t.flagged === \(flagged)")
        }
        if let dueBefore {
            filters.append("(t.dueDate && t.dueDate < new Date(\"\(dueBefore.jsEscaped)\"))")
        }
        if let dueAfter {
            filters.append("(t.dueDate && t.dueDate >= new Date(\"\(dueAfter.jsEscaped)\"))")
        }

        let filterExpr = filters.isEmpty ? "true" : filters.joined(separator: " && ")

        return """
        (() => {
            const tasks = flattenedTasks.filter(t => \(filterExpr));
            const total = tasks.length;
            const slice = tasks.slice(\(offset), \(offset + limit));
            const items = slice.map(t => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    /// Build JS to count tasks matching filters.
    static func countTasks(
        project: String?,
        tag: String?,
        flagged: Bool?,
        completed: Bool?,
        inbox: Bool?,
        status: String?
    ) -> String {
        var filters: [String] = []

        if completed != true {
            filters.append("t.taskStatus !== Task.Status.Completed && t.taskStatus !== Task.Status.Dropped")
        }
        if let inbox, inbox {
            return """
            (() => {
                const count = flattenedTasks.filter(t => t.inInbox && t.taskStatus !== Task.Status.Completed && t.taskStatus !== Task.Status.Dropped).length;
                return JSON.stringify({count: count});
            })()
            """
        }
        if let project {
            let escaped = project.jsEscaped.lowercased()
            filters.append("(t.containingProject && t.containingProject.name.toLowerCase().includes(\"\(escaped)\"))")
        }
        if let tag {
            let escaped = tag.jsEscaped
            filters.append("t.tags.some(tag => tag.name === \"\(escaped)\")")
        }
        if let flagged {
            filters.append("t.flagged === \(flagged)")
        }

        let filterExpr = filters.isEmpty ? "true" : filters.joined(separator: " && ")

        return """
        (() => {
            const count = flattenedTasks.filter(t => \(filterExpr)).length;
            return JSON.stringify({count: count});
        })()
        """
    }

    /// Build JS for a forecast view: overdue + due today + flagged, all non-completed.
    static func listForecast(fields: Set<TaskFieldSet>, limit: Int, offset: Int) -> String {
        let projection = taskProjection(fields)
        return """
        (() => {
            const now = new Date();
            const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            const endOfDay = new Date(startOfDay.getTime() + 86400000);
            const seen = new Set();
            const all = [];
            flattenedTasks.forEach(t => {
                if (t.taskStatus === Task.Status.Completed || t.taskStatus === Task.Status.Dropped) return;
                const dominated = t.dueDate;
                const isOverdue = dominated && dominated < startOfDay;
                const isDueToday = dominated && dominated >= startOfDay && dominated < endOfDay;
                const isFlagged = t.flagged;
                if (isOverdue || isDueToday || isFlagged) {
                    const pk = t.id.primaryKey;
                    if (!seen.has(pk)) {
                        seen.add(pk);
                        all.push(t);
                    }
                }
            });
            all.sort((a, b) => {
                const aDue = a.dueDate ? a.dueDate.getTime() : Infinity;
                const bDue = b.dueDate ? b.dueDate.getTime() : Infinity;
                return aDue - bDue;
            });
            const total = all.length;
            const slice = all.slice(\(offset), \(offset + limit));
            const items = slice.map(t => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    /// Build JS to list all perspectives.
    static func listPerspectives() -> String {
        return """
        (() => {
            const builtIn = Perspective.BuiltIn.all.map(p => ({id: p.name, name: p.name, type: "built_in"}));
            const custom = Perspective.Custom.all.map(p => ({id: p.id.primaryKey, name: p.name, type: "custom"}));
            const items = builtIn.concat(custom);
            return JSON.stringify({items: items, totalCount: items.length});
        })()
        """
    }

    /// Build JS to get tasks from a perspective using the Window content tree API.
    /// Saves current perspective, switches to target, walks the content tree for Task objects,
    /// then restores the original perspective. Requires at least one open OmniFocus window.
    static func listPerspectiveTasks(
        perspectiveId: String,
        perspectiveType: String,
        fields: Set<TaskFieldSet>,
        limit: Int,
        offset: Int
    ) -> String {
        let projection = taskProjection(fields)
        let escapedId = perspectiveId.jsEscaped

        // Resolve the perspective based on type
        let perspectiveLookup: String
        if perspectiveType == "built_in" {
            // Built-in perspectives are accessed as named constants on Perspective.BuiltIn
            perspectiveLookup = """
            var target = null;
            var builtIns = Perspective.BuiltIn.all;
            for (var i = 0; i < builtIns.length; i++) {
                if (builtIns[i].name === "\(escapedId)") { target = builtIns[i]; break; }
            }
            if (!target) return JSON.stringify({error: "not_found", message: "Built-in perspective not found: \(escapedId)"});
            """
        } else {
            perspectiveLookup = """
            var target = Perspective.Custom.byIdentifier("\(escapedId)");
            if (!target) {
                target = Perspective.Custom.byName("\(escapedId)");
            }
            if (!target) return JSON.stringify({error: "not_found", message: "Custom perspective not found: \(escapedId)"});
            """
        }

        return """
        (() => {
            var wins = document.windows;
            if (!wins || wins.length === 0) return JSON.stringify({error: "no_window", message: "OmniFocus has no open windows. Open a window and try again."});
            var win = wins[0];
            var saved = win.perspective;
            \(perspectiveLookup)
            win.perspective = target;
            var all = [];
            win.content.rootNode.apply(function(node) {
                var obj = node.object;
                if (obj && obj instanceof Task) {
                    all.push(obj);
                }
            });
            win.perspective = saved;
            var total = all.length;
            var slice = all.slice(\(offset), \(offset + limit));
            var items = slice.map(function(t) { return \(projection); });
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    // MARK: - Project Queries

    static func listProjects(
        status: String?,
        fields: Set<ProjectFieldSet>,
        limit: Int,
        offset: Int
    ) -> String {
        let projection = projectProjection(fields)
        var filter = ""
        switch status {
        case "active": filter = ".filter(p => p.status === Project.Status.Active)"
        case "on_hold": filter = ".filter(p => p.status === Project.Status.OnHold)"
        case "completed": filter = ".filter(p => p.status === Project.Status.Done)"
        case "dropped": filter = ".filter(p => p.status === Project.Status.Dropped)"
        default: break // "all" or nil
        }

        return """
        (() => {
            const projects = flattenedProjects\(filter);
            const total = projects.length;
            const slice = projects.slice(\(offset), \(offset + limit));
            const items = slice.map(p => (\(projection)));
            return JSON.stringify({items: items, totalCount: total});
        })()
        """
    }

    // MARK: - Tag Queries

    static func listTags(limit: Int) -> String {
        return """
        (() => {
            const tags = flattenedTags.slice(0, \(limit));
            const items = tags.map(t => ({
                id: t.id.primaryKey,
                name: t.name,
                parentId: t.parent ? t.parent.id.primaryKey : null,
                taskCount: t.tasks.length
            }));
            return JSON.stringify({items: items, totalCount: flattenedTags.length});
        })()
        """
    }

    // MARK: - Mutations

    /// Build JS to create a new task.
    static func createTask(
        name: String,
        note: String?,
        projectId: String?,
        parentId: String?,
        tagIds: [String]?,
        tagNames: [String]?,
        dueDate: String?,
        deferDate: String?,
        flagged: Bool?,
        estimatedMinutes: Int?
    ) -> String {
        let escapedName = name.jsEscaped

        // Determine creation location
        var locationCode: String
        if let parentId {
            locationCode = """
            const parent = Task.byIdentifier("\(parentId.jsEscaped)");
            if (!parent) return JSON.stringify({error: "not_found", message: "Parent task not found"});
            const t = new Task("\(escapedName)", parent);
            """
        } else if let projectId {
            locationCode = """
            const proj = Project.byIdentifier("\(projectId.jsEscaped)");
            if (!proj) return JSON.stringify({error: "not_found", message: "Project not found"});
            const t = new Task("\(escapedName)", proj);
            """
        } else {
            locationCode = """
            const t = new Task("\(escapedName)", inbox);
            """
        }

        // Set properties after creation
        var propCode: [String] = []
        if let note { propCode.append("t.note = \"\(note.jsEscaped)\";") }
        if let dueDate { propCode.append("t.dueDate = new Date(\"\(dueDate.jsEscaped)\");") }
        if let deferDate { propCode.append("t.deferDate = new Date(\"\(deferDate.jsEscaped)\");") }
        if let flagged { propCode.append("t.flagged = \(flagged);") }
        if let mins = estimatedMinutes { propCode.append("t.estimatedMinutes = \(mins);") }

        // Tag assignment
        if let tagIds, !tagIds.isEmpty {
            let lookups = tagIds.map { "Tag.byIdentifier(\"\($0.jsEscaped)\")" }.joined(separator: ", ")
            propCode.append("[\(lookups)].filter(x => x).forEach(tag => t.addTag(tag));")
        } else if let tagNames, !tagNames.isEmpty {
            let lookups = tagNames.map { "\"\($0.jsEscaped)\"" }.joined(separator: ", ")
            propCode.append("""
            [\(lookups)].forEach(name => {
                let tag = flattenedTags.byName(name);
                if (!tag) tag = new Tag(name);
                t.addTag(tag);
            });
            """)
        }

        let propsStr = propCode.joined(separator: "\n            ")

        return """
        (() => {
            \(locationCode)
            \(propsStr)
            return JSON.stringify({
                id: t.id.primaryKey,
                name: t.name,
                url: "omnifocus:///task/" + t.id.primaryKey
            });
        })()
        """
    }

    /// Build JS to update a task by ID with patch fields.
    static func updateTask(id: String, patch: [String: Any]) -> String {
        let escaped = id.jsEscaped
        var updates: [String] = []

        if let name = patch["name"] as? String {
            updates.append("t.name = \"\(name.jsEscaped)\";")
        }
        if let note = patch["note"] as? String {
            updates.append("t.note = \"\(note.jsEscaped)\";")
        }
        if let flagged = patch["flagged"] as? Bool {
            updates.append("t.flagged = \(flagged);")
        }
        if let key = "dueDate" as String?, patch.keys.contains(key) {
            if let date = patch[key] as? String {
                updates.append("t.dueDate = new Date(\"\(date.jsEscaped)\");")
            } else {
                updates.append("t.dueDate = null;")
            }
        }
        if let key = "deferDate" as String?, patch.keys.contains(key) {
            if let date = patch[key] as? String {
                updates.append("t.deferDate = new Date(\"\(date.jsEscaped)\");")
            } else {
                updates.append("t.deferDate = null;")
            }
        }
        if let mins = patch["estimatedMinutes"] as? Int {
            updates.append("t.estimatedMinutes = \(mins);")
        }
        if let key = "projectId" as String?, patch.keys.contains(key) {
            if let projectId = patch[key] as? String {
                updates.append("""
                { const proj = Project.byIdentifier("\(projectId.jsEscaped)"); \
                if (!proj) return JSON.stringify({error: "not_found", message: "Project not found"}); \
                moveTasks([t], proj); }
                """)
            } else {
                updates.append("moveTasks([t], Inbox);")
            }
        }
        if let tagIds = patch["tagIds"] as? [String] {
            updates.append("t.clearTags();")
            for tagId in tagIds {
                updates.append("""
                { const tag = Tag.byIdentifier("\(tagId.jsEscaped)"); if (tag) t.addTag(tag); }
                """)
            }
        }
        if let status = patch["status"] as? String {
            switch status {
            case "complete":
                updates.append("t.markComplete();")
            case "drop":
                updates.append("t.drop(true);")
            case "active":
                updates.append("t.markIncomplete();")
            default:
                break
            }
        }

        let updatesStr = updates.joined(separator: "\n            ")

        return """
        (() => {
            const t = Task.byIdentifier("\(escaped)");
            if (!t) return JSON.stringify({error: "not_found"});
            \(updatesStr)
            return JSON.stringify({
                id: t.id.primaryKey,
                name: t.name,
                status: t.completed ? "completed" : (t.dropped ? "dropped" : "active"),
                flagged: t.flagged,
                completed: t.completed,
                dueDate: t.dueDate ? t.dueDate.toISOString() : null,
                projectId: t.containingProject ? t.containingProject.id.primaryKey : null,
                projectName: t.containingProject ? t.containingProject.name : null,
                url: "omnifocus:///task/" + t.id.primaryKey
            });
        })()
        """
    }

    // MARK: - Field Projections

    private static func taskProjection(_ fields: Set<TaskFieldSet>) -> String {
        var props: [String] = []

        if fields.contains(.id) { props.append("id: t.id.primaryKey") }
        if fields.contains(.name) { props.append("name: t.name") }
        if fields.contains(.note) { props.append("note: t.note || null") }
        if fields.contains(.status) {
            props.append("status: t.taskStatus === Task.Status.Completed ? 'completed' : (t.taskStatus === Task.Status.Dropped ? 'dropped' : (t.taskStatus === Task.Status.Blocked ? 'blocked' : 'available'))")
        }
        if fields.contains(.flagged) { props.append("flagged: t.flagged") }
        if fields.contains(.completed) { props.append("completed: t.completed") }
        if fields.contains(.dropped) { props.append("dropped: t.dropped") }
        if fields.contains(.dueDate) { props.append("dueDate: t.dueDate ? t.dueDate.toISOString() : null") }
        if fields.contains(.deferDate) { props.append("deferDate: t.deferDate ? t.deferDate.toISOString() : null") }
        if fields.contains(.completionDate) { props.append("completionDate: t.completionDate ? t.completionDate.toISOString() : null") }
        if fields.contains(.estimatedMinutes) { props.append("estimatedMinutes: t.estimatedMinutes") }
        if fields.contains(.projectId) { props.append("projectId: t.containingProject ? t.containingProject.id.primaryKey : null") }
        if fields.contains(.projectName) { props.append("projectName: t.containingProject ? t.containingProject.name : null") }
        if fields.contains(.parentId) { props.append("parentId: t.parent ? t.parent.id.primaryKey : null") }
        if fields.contains(.tagIds) { props.append("tagIds: t.tags.map(tag => tag.id.primaryKey)") }
        if fields.contains(.tagNames) { props.append("tagNames: t.tags.map(tag => tag.name)") }
        if fields.contains(.hasChildren) { props.append("hasChildren: t.children.length > 0") }
        if fields.contains(.sequential) { props.append("sequential: t.sequential") }
        if fields.contains(.url) { props.append("url: 'omnifocus:///task/' + t.id.primaryKey") }

        return "{\(props.joined(separator: ", "))}"
    }

    private static func projectProjection(_ fields: Set<ProjectFieldSet>) -> String {
        var props: [String] = []

        if fields.contains(.id) { props.append("id: p.id.primaryKey") }
        if fields.contains(.name) { props.append("name: p.name") }
        if fields.contains(.status) {
            props.append("""
            status: p.status === Project.Status.Active ? 'active' : \
            (p.status === Project.Status.OnHold ? 'on_hold' : \
            (p.status === Project.Status.Done ? 'completed' : 'dropped'))
            """)
        }
        if fields.contains(.note) { props.append("note: p.note || null") }
        if fields.contains(.sequential) { props.append("sequential: p.sequential") }
        if fields.contains(.dueDate) { props.append("dueDate: p.dueDate ? p.dueDate.toISOString() : null") }
        if fields.contains(.deferDate) { props.append("deferDate: p.deferDate ? p.deferDate.toISOString() : null") }
        if fields.contains(.taskCount) { props.append("taskCount: p.flattenedTasks.length") }
        if fields.contains(.folderId) { props.append("folderId: p.parentFolder ? p.parentFolder.id.primaryKey : null") }
        if fields.contains(.folderName) { props.append("folderName: p.parentFolder ? p.parentFolder.name : null") }
        if fields.contains(.url) { props.append("url: 'omnifocus:///task/' + p.id.primaryKey") }

        return "{\(props.joined(separator: ", "))}"
    }
}

// MARK: - String Escaping

extension String {
    /// Escape a string for safe inclusion in a JavaScript string literal.
    var jsEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
