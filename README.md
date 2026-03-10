# OmniFocus MCP Server

A high-performance, native macOS [MCP](https://modelcontextprotocol.io) server for [OmniFocus](https://www.omnigroup.com/omnifocus).
Single universal binary — no Node.js, no Python, no runtime dependencies.

## Features

- **Fast**: Native Swift binary with TTL caching, server-side filtering, and field projection.
- **Safe**: Destructive operations use dry-run by default with HMAC-SHA256 confirm-token flow.
- **Bounded**: All queries have default limits and cursor pagination. No full database dumps.
- **Pro-aware**: Detects OmniFocus Pro vs Standard. Falls back to URL scheme capture in Standard mode.
- **Perspectives**: Query tasks from any perspective — built-in or custom — via the Window content tree API.

## Requirements

- macOS 14.0+
- OmniFocus 4 (or 3)
- OmniFocus Pro license (for full automation; Standard supports capture-only mode)
- System Preferences → Privacy & Security → Automation: allow `omnifocus-mcp-server` to control OmniFocus

## Installation

### Homebrew

```bash
brew tap ryanbantz/tap
brew install ryanbantz/tap/omnifocus-mcp-server
```

### Direct Download

Download the universal binary from [GitHub Releases](https://github.com/ryanbantz/omnifocus-mcp-server/releases):

```bash
curl -L -o omnifocus-mcp-server https://github.com/ryanbantz/omnifocus-mcp-server/releases/latest/download/omnifocus-mcp-server-universal
chmod +x omnifocus-mcp-server
sudo mv omnifocus-mcp-server /usr/local/bin/
```

### Build from Source

```bash
git clone https://github.com/ryanbantz/omnifocus-mcp-server.git
cd omnifocus-mcp-server
swift build -c release
cp .build/release/omnifocus-mcp-server /usr/local/bin/
```

## Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "omnifocus": {
      "command": "/usr/local/bin/omnifocus-mcp-server",
      "env": {
        "OMNIFOCUS_MCP_LOG_LEVEL": "info"
      }
    }
  }
}
```

Or if installed via Homebrew:

```json
{
  "mcpServers": {
    "omnifocus": {
      "command": "omnifocus-mcp-server"
    }
  }
}
```

## Tools

### Read Tools (OmniFocus Pro required)

| Tool | Description |
|------|-------------|
| `diagnostics` | Server health, capability mode, cache stats |
| `list_inbox` | Inbox tasks (bounded, paginated) |
| `list_today` | Tasks due or deferred until today |
| `list_flagged` | Flagged incomplete tasks |
| `list_forecast` | Overdue + due today + flagged, sorted by due date |
| `list_projects` | Projects with status filter |
| `list_tags` | All tags |
| `list_perspectives` | All built-in and custom perspectives |
| `get_perspective_tasks` | Tasks from a specific perspective |
| `get_task_by_id` | Single task by stable ID |
| `search_tasks` | Filtered search with AND logic |
| `get_task_count` | Count matching tasks without returning data |

### Mutation Tools (OmniFocus Pro required)

| Tool | Description |
|------|-------------|
| `create_task` | Create task in inbox or project |
| `update_task` | Patch-based update with dry-run/confirm |
| `batch_update_tasks` | Batch updates (config-gated) |

### Standard Mode Tools (no Pro required)

| Tool | Description |
|------|-------------|
| `create_task_via_url` | Create via URL scheme (opens OmniFocus) |
| `open_task_url` | Open task in OmniFocus by ID |

## Tool Examples

### List inbox tasks

```json
{
  "name": "list_inbox",
  "arguments": {
    "limit": 10,
    "fields": ["id", "name", "dueDate", "flagged"]
  }
}
```

### Daily forecast

```json
{
  "name": "list_forecast",
  "arguments": {
    "limit": 50,
    "fields": ["id", "name", "dueDate", "flagged", "projectName", "tagNames"]
  }
}
```

### Get tasks from a custom perspective

```json
{
  "name": "get_perspective_tasks",
  "arguments": {
    "id": "abc123",
    "type": "custom",
    "fields": ["id", "name", "dueDate", "projectName", "tagNames"]
  }
}
```

### Search tasks

```json
{
  "name": "search_tasks",
  "arguments": {
    "query": "report",
    "project": "Work",
    "flagged": true,
    "limit": 20
  }
}
```

### Create a task

```json
{
  "name": "create_task",
  "arguments": {
    "name": "Review Q4 report",
    "projectId": "abc123",
    "dueDate": "2026-03-15T17:00:00Z",
    "flagged": true,
    "tagNames": ["Work", "Important"]
  }
}
```

### Update a task (two-step for destructive changes)

Step 1 — dry run (default):
```json
{
  "name": "update_task",
  "arguments": {
    "id": "dXL1Kdp4XCx",
    "patch": {
      "status": "complete"
    }
  }
}
```

Response includes `confirm_token`.

Step 2 — apply:
```json
{
  "name": "update_task",
  "arguments": {
    "id": "dXL1Kdp4XCx",
    "patch": {
      "status": "complete"
    },
    "dry_run": false,
    "confirm_token": "eyJ0YXNrX2lkIjo...abc123"
  }
}
```

### Field projection

All list tools accept a `fields` parameter. Default is minimal (`id`, `name`, `status`, `flagged`, `dueDate`). Request more fields as needed:

```json
{
  "name": "list_inbox",
  "arguments": {
    "fields": ["id", "name", "note", "dueDate", "tagNames", "projectName"]
  }
}
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OMNIFOCUS_MCP_LOG_LEVEL` | `info` | `debug`, `info`, `warning`, `error` |
| `OMNIFOCUS_MCP_BULK_OPS` | `false` | Enable batch operations |
| `OMNIFOCUS_MCP_DELETE_ENABLED` | `false` | Enable delete capability |
| `OMNIFOCUS_MCP_TOOL_ALLOWLIST` | (all) | Comma-separated tool names |
| `OMNIFOCUS_MCP_DEFAULT_LIMIT` | `50` | Default result limit |
| `OMNIFOCUS_MCP_MAX_LIMIT` | `200` | Maximum result limit |
| `OMNIFOCUS_MCP_CACHE_ENABLED` | `true` | Enable TTL caching |

### Config File (optional)

`~/.config/omnifocus-mcp/config.json`:

```json
{
  "log_level": "info",
  "bulk_ops": false,
  "enable_delete": false,
  "default_limit": 50
}
```

Environment variables override config file values.

## Security

### Data Access

- The server controls OmniFocus through Omni Automation (JavaScript) via `osascript`
- It does **not** read OmniFocus database files directly
- Requires macOS Automation permission (System Preferences prompt on first use)
- All communication is via MCP stdio — no network access

### Logging

- Logs go to **stderr only** (stdout is reserved for MCP protocol)
- Task notes are **never logged** (may contain sensitive data)
- Set `OMNIFOCUS_MCP_LOG_LEVEL=error` for minimal logging

### Safety Controls

- **Destructive operations** default to `dry_run: true`
- **Irreversible transitions** (complete, drop) require an HMAC-SHA256 `confirm_token`
- **Batch operations** are disabled by default (`OMNIFOCUS_MCP_BULK_OPS=true` to enable)
- **Delete** is disabled by default (`OMNIFOCUS_MCP_DELETE_ENABLED=true` to enable)
- **Tool allowlist** restricts which tools are exposed

## Troubleshooting

### "OmniFocus is not running"

Start OmniFocus before using the server. The server does not launch OmniFocus automatically.

### "capability_unavailable" errors

You're running OmniFocus Standard (not Pro). Automation requires Pro.
In Standard mode, only `create_task_via_url` and `open_task_url` are available.

### Permission denied

macOS needs to grant Automation permission:
1. System Preferences → Privacy & Security → Automation
2. Find `omnifocus-mcp-server` (or the terminal running it)
3. Enable access to OmniFocus

### Server not connecting

Check Claude Desktop config syntax. Verify the binary path is correct:
```bash
which omnifocus-mcp-server
omnifocus-mcp-server  # Should print "[omnifocus-mcp-server] Starting..." to stderr
```

### Perspective tasks require an open window

`get_perspective_tasks` uses the OmniFocus Window content tree API. At least one OmniFocus window must be open (not just running in the background).

## Protocol

- **MCP version**: `2025-11-25` (pinned)
- **Transport**: stdio (JSON-RPC, newline-delimited)
- **SDK**: [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) v0.11.0

## License

[MIT](LICENSE)
