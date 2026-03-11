# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-03-10

### Fixed

- `create_task` now works correctly — was generating invalid JavaScript (`new Task(name: "...")` instead of `new Task("...")`)
- Version string is now auto-injected from git tag during CI release builds

## [0.2.0] - 2026-03-10

### Added

- `update_task` now supports `projectId` in the patch to move tasks between projects or back to Inbox (set to `null`)
- `update_task` response now includes `projectId` and `projectName` fields

### Fixed

- GitHub username corrected from `ryanbantz` to `mryanb` in all URLs
- Removed Homebrew references from public README until distribution criteria are met

## [0.1.1] - 2026-03-10

### Fixed

- Require Xcode 16.3 in CI workflows for Swift 6.1 compatibility (MCP Swift SDK requires `withThrowingTaskGroup` without `of:` parameter)

## [0.1.0] - 2026-03-10

### Added

- **Core server** — Native Swift MCP server using stdio transport (MCP protocol `2025-11-25`)
- **OmniFocus bridge** — Omni Automation JavaScript via `osascript` subprocess with TCC-safe permission handling
- **Capability detection** — Automatic Pro vs Standard mode detection at startup

#### Read Tools (Pro required)
- `diagnostics` — Server health, connection status, capability mode, cache stats
- `list_inbox` — Inbox tasks with pagination and field projection
- `list_today` — Tasks due or deferred until today
- `list_flagged` — Flagged incomplete tasks
- `list_forecast` — Overdue + due today + flagged, sorted by due date
- `list_projects` — Projects with status filter (active, on_hold, completed, dropped, all)
- `list_tags` — All tags with optional task count
- `list_perspectives` — All built-in and custom perspectives
- `get_perspective_tasks` — Tasks from any perspective via Window content tree API
- `get_task_by_id` — Single task lookup by stable OmniFocus ID
- `search_tasks` — Filtered search with AND logic (text, project, tag, status, date range, flagged)
- `get_task_count` — Count matching tasks without returning data

#### Mutation Tools (Pro required)
- `create_task` — Create tasks in inbox or specific project with tags, dates, and flags
- `update_task` — Patch-based updates with dry-run default and HMAC-SHA256 confirm-token for irreversible transitions (complete, drop)
- `batch_update_tasks` — Batch updates for up to 25 tasks (disabled by default, config-gated)

#### Standard Mode Tools (no Pro required)
- `create_task_via_url` — Create tasks via OmniFocus URL scheme
- `open_task_url` — Open a task in OmniFocus by ID

#### Infrastructure
- **TTL caching** — Actor-isolated cache with configurable TTLs (5s–120s) and full invalidation on mutations
- **Cursor-based pagination** — Stable iteration with opaque cursors on all list operations
- **Field projection** — Client-controlled response fields with minimal defaults to reduce payload size
- **Configuration** — Environment variables (`OMNIFOCUS_MCP_*`) and optional config file (`~/.config/omnifocus-mcp/config.json`)
- **Safety controls** — Dry-run defaults, single-use confirm tokens (5-minute TTL), config-gated batch/delete operations, tool allowlist
- **CI/CD** — GitHub Actions for build/test/lint on push, automated universal binary releases on tag

[0.2.1]: https://github.com/mryanb/omnifocus-mcp-server/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mryanb/omnifocus-mcp-server/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/mryanb/omnifocus-mcp-server/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mryanb/omnifocus-mcp-server/releases/tag/v0.1.0
