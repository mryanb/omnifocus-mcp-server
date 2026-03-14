import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusMCPServer

// MARK: - JS Syntax Validation Helper

/// Checks that a JavaScript string is syntactically valid by parsing it in JavaScriptCore.
/// This catches bugs like using Swift-style named parameters in JS constructor calls.
private func assertValidJSSyntax(_ js: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let ctx = JSContext()!
    // Wrap in a try/catch so syntax errors are captured, not thrown
    let wrapped = "try { \(js) } catch(e) { e.toString(); }"
    ctx.evaluateScript(wrapped)
    if let exception = ctx.exception {
        let msg = exception.toString() ?? "unknown JS error"
        // Only fail on SyntaxError (runtime errors like "Task is not defined" are expected)
        if msg.contains("SyntaxError") {
            Issue.record("Generated JS has syntax error: \(msg)\n\nJS:\n\(js)", sourceLocation: sourceLocation)
        }
    }
}

@Suite("JavaScriptBuilder")
struct JavaScriptBuilderTests {
    @Test("listInbox produces valid JS with correct limit and offset")
    func listInbox() {
        let js = JSBuilder.listInbox(fields: TaskFieldSet.minimal, limit: 10, offset: 0)
        #expect(js.contains("inInbox"))
        #expect(js.contains("Task.Status.Completed"))
        #expect(js.contains("Task.Status.Dropped"))
        #expect(js.contains("slice(0, 10)"))
        #expect(js.contains("JSON.stringify"))
    }

    @Test("listInbox with offset")
    func listInboxOffset() {
        let js = JSBuilder.listInbox(fields: TaskFieldSet.minimal, limit: 10, offset: 20)
        #expect(js.contains("slice(20, 30)"))
    }

    @Test("getTaskById escapes ID")
    func getTaskById() {
        let js = JSBuilder.getTaskById(id: "abc\"123", fields: TaskFieldSet.standard)
        #expect(js.contains("Task.byIdentifier"))
        #expect(js.contains("abc\\\"123"))
    }

    @Test("searchTasks with query filter")
    func searchWithQuery() {
        let js = JSBuilder.searchTasks(
            query: "buy milk", project: nil, tag: nil,
            flagged: nil, completed: nil,
            dueBefore: nil, dueAfter: nil, status: nil,
            fields: TaskFieldSet.minimal, limit: 50, offset: 0
        )
        #expect(js.contains("buy milk"))
        #expect(js.contains("toLowerCase"))
    }

    @Test("searchTasks with multiple filters")
    func searchMultipleFilters() {
        let js = JSBuilder.searchTasks(
            query: "report", project: "Work", tag: "Important",
            flagged: true, completed: false,
            dueBefore: nil, dueAfter: nil, status: nil,
            fields: TaskFieldSet.minimal, limit: 10, offset: 0
        )
        #expect(js.contains("report"))
        #expect(js.contains("work"))  // project name is lowercased for case-insensitive matching
        #expect(js.contains("Important"))  // tag name is exact match
        #expect(js.contains("t.flagged === true"))
        #expect(js.contains("Task.Status.Completed"))
    }

    @Test("createTask builds valid JS")
    func createTask() {
        let js = JSBuilder.createTask(
            name: "Test Task",
            note: "A note",
            projectId: nil,
            parentId: nil,
            tagIds: nil,
            tagNames: ["Work"],
            dueDate: "2026-03-15T17:00:00Z",
            deferDate: nil,
            flagged: true,
            estimatedMinutes: 30
        )
        #expect(js.contains("new Task(\"Test Task\""))
        #expect(js.contains("t.note = \"A note\""))
        #expect(js.contains("t.flagged = true"))
        #expect(js.contains("t.estimatedMinutes = 30"))
        #expect(js.contains("Work"))
        // Properties must be set AFTER construction, not as constructor args
        #expect(!js.contains("new Task(name:"))
    }

    @Test("createTask with project target")
    func createTaskInProject() {
        let js = JSBuilder.createTask(
            name: "Sub task",
            note: nil,
            projectId: "proj123",
            parentId: nil,
            tagIds: nil,
            tagNames: nil,
            dueDate: nil,
            deferDate: nil,
            flagged: nil,
            estimatedMinutes: nil
        )
        #expect(js.contains("Project.byIdentifier"))
        #expect(js.contains("proj123"))
        #expect(js.contains("new Task(\"Sub task\", proj)"))
        #expect(!js.contains("new Task(name:"))
    }

    @Test("updateTask applies patch fields")
    func updateTask() {
        let js = JSBuilder.updateTask(id: "abc123", patch: [
            "name": "New Name",
            "flagged": true,
            "status": "complete",
        ])
        #expect(js.contains("Task.byIdentifier"))
        #expect(js.contains("abc123"))
        #expect(js.contains("t.name = \"New Name\""))
        #expect(js.contains("t.flagged = true"))
        #expect(js.contains("t.markComplete()"))
    }

    @Test("updateTask moves task to a project")
    func updateTaskProjectId() {
        let js = JSBuilder.updateTask(id: "task1", patch: [
            "projectId": "proj99",
        ])
        #expect(js.contains("Project.byIdentifier(\"proj99\")"))
        #expect(js.contains("moveTasks([t], proj)"))
    }

    @Test("updateTask moves task to Inbox when projectId is null")
    func updateTaskMoveToInbox() {
        let patch: [String: Any] = ["projectId": NSNull()]
        let js = JSBuilder.updateTask(id: "task1", patch: patch)
        #expect(js.contains("moveTasks([t], inbox.ending)"))
    }

    @Test("updateTask response includes projectId and projectName")
    func updateTaskResponseIncludesProject() {
        let js = JSBuilder.updateTask(id: "task1", patch: ["name": "Test"])
        #expect(js.contains("projectId:"))
        #expect(js.contains("projectName:"))
    }

    @Test("field projection includes requested fields")
    func fieldProjection() {
        let fields: Set<TaskFieldSet> = [.id, .name, .dueDate, .tagNames]
        let js = JSBuilder.listInbox(fields: fields, limit: 10, offset: 0)
        #expect(js.contains("id: t.id.primaryKey"))
        #expect(js.contains("name: t.name"))
        #expect(js.contains("dueDate"))
        #expect(js.contains("tagNames"))
        // Should NOT include unrequested fields
        #expect(!js.contains("note: t.note"))
        #expect(!js.contains("parentId"))
    }

    @Test("string escaping handles special characters")
    func stringEscaping() {
        let escaped = "Hello \"world\"\nNew\tline\\".jsEscaped
        #expect(escaped.contains("\\\""))
        #expect(escaped.contains("\\n"))
        #expect(escaped.contains("\\t"))
        #expect(escaped.contains("\\\\"))
    }

    @Test("countTasks with inbox flag")
    func countInbox() {
        let js = JSBuilder.countTasks(
            project: nil, tag: nil, flagged: nil,
            completed: nil, inbox: true, status: nil
        )
        #expect(js.contains("inInbox"))
        #expect(js.contains("count"))
    }

    @Test("searchTasks defaults to excluding completed/dropped")
    func searchDefaultsActive() {
        let js = JSBuilder.searchTasks(
            query: nil, project: nil, tag: nil,
            flagged: nil, completed: nil,
            dueBefore: nil, dueAfter: nil, status: nil,
            fields: TaskFieldSet.minimal, limit: 50, offset: 0
        )
        #expect(js.contains("Task.Status.Completed"))
        #expect(js.contains("Task.Status.Dropped"))
    }

    @Test("searchTasks with status=any includes all tasks")
    func searchStatusAny() {
        let js = JSBuilder.searchTasks(
            query: nil, project: nil, tag: nil,
            flagged: nil, completed: nil,
            dueBefore: nil, dueAfter: nil, status: "any",
            fields: TaskFieldSet.minimal, limit: 50, offset: 0
        )
        #expect(js.contains("filter(t => true)"))  // no status filter applied
    }

    @Test("searchTasks with status=blocked uses Task.Status.Blocked")
    func searchStatusBlocked() {
        let js = JSBuilder.searchTasks(
            query: nil, project: nil, tag: nil,
            flagged: nil, completed: nil,
            dueBefore: nil, dueAfter: nil, status: "blocked",
            fields: TaskFieldSet.minimal, limit: 50, offset: 0
        )
        #expect(js.contains("Task.Status.Blocked"))
    }

    @Test("listForecast includes overdue, due today, and flagged")
    func listForecast() {
        let js = JSBuilder.listForecast(fields: TaskFieldSet.minimal, limit: 20, offset: 0)
        #expect(js.contains("Task.Status.Completed"))  // filters out completed
        #expect(js.contains("Task.Status.Dropped"))    // filters out dropped
        #expect(js.contains("t.flagged"))
        #expect(js.contains("startOfDay"))
        #expect(js.contains("endOfDay"))
        #expect(js.contains("slice(0, 20)"))
        #expect(js.contains(".sort"))
    }

    @Test("listPerspectives returns name and id")
    func listPerspectives() {
        let js = JSBuilder.listPerspectives()
        #expect(js.contains("Perspective.BuiltIn.all"))
        #expect(js.contains("Perspective.Custom.all"))
        #expect(js.contains("id: p.id.primaryKey"))
        #expect(js.contains("name: p.name"))
    }

    @Test("listPerspectiveTasks for custom perspective")
    func listPerspectiveTasksCustom() {
        let js = JSBuilder.listPerspectiveTasks(
            perspectiveId: "abc123",
            perspectiveType: "custom",
            fields: TaskFieldSet.minimal,
            limit: 50,
            offset: 0
        )
        #expect(js.contains("Perspective.Custom.byIdentifier"))
        #expect(js.contains("abc123"))
        #expect(js.contains("win.perspective = target"))
        #expect(js.contains("win.perspective = saved"))
        #expect(js.contains("instanceof Task"))
        #expect(js.contains("rootNode.apply"))
        #expect(js.contains("slice(0, 50)"))
    }

    @Test("listPerspectiveTasks for built-in perspective")
    func listPerspectiveTasksBuiltIn() {
        let js = JSBuilder.listPerspectiveTasks(
            perspectiveId: "Flagged",
            perspectiveType: "built_in",
            fields: TaskFieldSet.minimal,
            limit: 20,
            offset: 0
        )
        #expect(js.contains("Perspective.BuiltIn.all"))
        #expect(js.contains("Flagged"))
        #expect(!js.contains("Perspective.Custom"))
        #expect(js.contains("win.perspective = target"))
        #expect(js.contains("win.perspective = saved"))
        #expect(js.contains("slice(0, 20)"))
    }

    @Test("listProjects with status filter")
    func listProjectsActive() {
        let js = JSBuilder.listProjects(
            status: "active",
            fields: ProjectFieldSet.minimal,
            limit: 50, offset: 0
        )
        #expect(js.contains("Project.Status.Active"))
        #expect(js.contains("flattenedProjects"))
    }

    // MARK: - updateProject Tests

    @Test("updateProject applies patch fields")
    func updateProject() {
        let js = JSBuilder.updateProject(id: "proj1", patch: [
            "name": "Renamed Project",
            "note": "Updated note",
            "sequential": true,
            "status": "on_hold",
        ])
        #expect(js.contains("Project.byIdentifier(\"proj1\")"))
        #expect(js.contains("p.name = \"Renamed Project\""))
        #expect(js.contains("p.note = \"Updated note\""))
        #expect(js.contains("p.sequential = true"))
        #expect(js.contains("Project.Status.OnHold"))
    }

    @Test("updateProject sets and clears dates")
    func updateProjectDates() {
        let js = JSBuilder.updateProject(id: "proj2", patch: [
            "dueDate": "2026-04-01T17:00:00Z",
            "deferDate": "2026-03-15T09:00:00Z",
        ])
        #expect(js.contains("p.dueDate = new Date(\"2026-04-01T17:00:00Z\")"))
        #expect(js.contains("p.deferDate = new Date(\"2026-03-15T09:00:00Z\")"))

        let jsNull = JSBuilder.updateProject(id: "proj2", patch: [
            "dueDate": NSNull(),
        ])
        #expect(jsNull.contains("p.dueDate = null"))
    }

    @Test("updateProject complete and drop use correct methods")
    func updateProjectStatusTransitions() {
        let jsComplete = JSBuilder.updateProject(id: "proj3", patch: ["status": "complete"])
        #expect(jsComplete.contains("p.markComplete()"))

        let jsDrop = JSBuilder.updateProject(id: "proj3", patch: ["status": "drop"])
        #expect(jsDrop.contains("p.drop(true)"))

        let jsActive = JSBuilder.updateProject(id: "proj3", patch: ["status": "active"])
        #expect(jsActive.contains("Project.Status.Active"))
    }

    @Test("updateProject response includes all project fields")
    func updateProjectResponse() {
        let js = JSBuilder.updateProject(id: "proj1", patch: ["name": "Test"])
        #expect(js.contains("id: p.id.primaryKey"))
        #expect(js.contains("name: p.name"))
        #expect(js.contains("status:"))
        #expect(js.contains("dueDate:"))
        #expect(js.contains("deferDate:"))
        #expect(js.contains("taskCount:"))
    }

    // MARK: - JS Syntax Validation (JavaScriptCore)

    @Test("createTask generates syntactically valid JavaScript")
    func createTaskJSSyntax() {
        // Minimal
        assertValidJSSyntax(JSBuilder.createTask(
            name: "Test", note: nil, projectId: nil, parentId: nil,
            tagIds: nil, tagNames: nil, dueDate: nil, deferDate: nil,
            flagged: nil, estimatedMinutes: nil
        ))

        // All fields populated
        assertValidJSSyntax(JSBuilder.createTask(
            name: "Task with \"quotes\" and special chars",
            note: "A note\nwith newlines",
            projectId: nil, parentId: nil,
            tagIds: ["tag1", "tag2"],
            tagNames: nil,
            dueDate: "2026-03-15T17:00:00Z",
            deferDate: "2026-03-10T09:00:00Z",
            flagged: true,
            estimatedMinutes: 30
        ))

        // With project target
        assertValidJSSyntax(JSBuilder.createTask(
            name: "Project task", note: "note", projectId: "proj123",
            parentId: nil, tagIds: nil, tagNames: ["Work"],
            dueDate: nil, deferDate: nil, flagged: false, estimatedMinutes: nil
        ))

        // With parent task target
        assertValidJSSyntax(JSBuilder.createTask(
            name: "Subtask", note: nil, projectId: nil,
            parentId: "parent456", tagIds: nil, tagNames: nil,
            dueDate: nil, deferDate: nil, flagged: nil, estimatedMinutes: nil
        ))
    }

    @Test("updateTask generates syntactically valid JavaScript")
    func updateTaskJSSyntax() {
        assertValidJSSyntax(JSBuilder.updateTask(id: "abc123", patch: [
            "name": "New Name",
            "note": "Updated note with \"quotes\"",
            "flagged": true,
            "dueDate": "2026-03-15T17:00:00Z",
            "estimatedMinutes": 45,
            "tagIds": ["t1", "t2"],
            "status": "complete",
        ]))

        // projectId move
        assertValidJSSyntax(JSBuilder.updateTask(id: "task1", patch: [
            "projectId": "proj99",
        ]))

        // projectId null (move to inbox)
        assertValidJSSyntax(JSBuilder.updateTask(id: "task1", patch: [
            "projectId": NSNull(),
        ]))
    }

    @Test("updateProject generates syntactically valid JavaScript")
    func updateProjectJSSyntax() {
        // All fields
        assertValidJSSyntax(JSBuilder.updateProject(id: "proj1", patch: [
            "name": "New Name",
            "note": "Updated note",
            "dueDate": "2026-04-01T17:00:00Z",
            "deferDate": "2026-03-15T09:00:00Z",
            "sequential": true,
            "status": "complete",
        ]))

        // Null dates
        assertValidJSSyntax(JSBuilder.updateProject(id: "proj1", patch: [
            "dueDate": NSNull(),
            "deferDate": NSNull(),
        ]))

        // Status transitions
        assertValidJSSyntax(JSBuilder.updateProject(id: "proj1", patch: ["status": "drop"]))
        assertValidJSSyntax(JSBuilder.updateProject(id: "proj1", patch: ["status": "on_hold"]))
        assertValidJSSyntax(JSBuilder.updateProject(id: "proj1", patch: ["status": "active"]))
    }

    @Test("read tools generate syntactically valid JavaScript")
    func readToolsJSSyntax() {
        assertValidJSSyntax(JSBuilder.listInbox(fields: TaskFieldSet.standard, limit: 50, offset: 0))
        assertValidJSSyntax(JSBuilder.listToday(fields: TaskFieldSet.standard, limit: 50, offset: 0))
        assertValidJSSyntax(JSBuilder.listFlagged(fields: TaskFieldSet.minimal, limit: 20, offset: 0))
        assertValidJSSyntax(JSBuilder.listForecast(fields: TaskFieldSet.standard, limit: 50, offset: 0))
        assertValidJSSyntax(JSBuilder.listPerspectives())
        assertValidJSSyntax(JSBuilder.getTaskById(id: "test-id", fields: TaskFieldSet.standard))
        assertValidJSSyntax(JSBuilder.listProjects(status: "active", fields: ProjectFieldSet.minimal, limit: 50, offset: 0))
        assertValidJSSyntax(JSBuilder.listTags(limit: 50))
        assertValidJSSyntax(JSBuilder.countTasks(project: "Work", tag: "Important", flagged: true, completed: false, inbox: false, status: nil))

        assertValidJSSyntax(JSBuilder.searchTasks(
            query: "test", project: "Work", tag: "Urgent",
            flagged: true, completed: false,
            dueBefore: "2026-12-31", dueAfter: "2026-01-01", status: "available",
            fields: TaskFieldSet.standard, limit: 50, offset: 0
        ))

        assertValidJSSyntax(JSBuilder.listPerspectiveTasks(
            perspectiveId: "abc123", perspectiveType: "custom",
            fields: TaskFieldSet.standard, limit: 50, offset: 0
        ))
    }
}
