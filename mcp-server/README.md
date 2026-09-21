# Olai MCP server

Read-only access to the Olai Markdown mirror, over stdio.

The mirror is export-only: Olai writes it and never reads it back, and neither does
this server. `append_to_page` exists because the spec lists it, and returns an error
saying so.

## Install

```bash
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
```

Point it at a mirror with `OLAI_ROOT`. Without it, the server reads `~/Olai`.

Requires `mcp` 2.x. In 2.0 `FastMCP` was renamed `MCPServer`; pin `mcp<2` only if you
also revert `olai_mcp/server.py` to the old import.

## Connect it

**Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "olai": {
      "command": "/Users/rahulr/Documents/olai/mcp-server/.venv/bin/python",
      "args": ["-m", "olai_mcp.server"],
      "env": { "OLAI_ROOT": "/Users/rahulr/Olai" }
    }
  }
}
```

Restart Claude Desktop afterwards.

**Claude Code**:

```bash
claude mcp add olai --scope user --env OLAI_ROOT=/Users/rahulr/Olai -- \
  /Users/rahulr/Documents/olai/mcp-server/.venv/bin/olai-mcp
```

Without `--scope user` the server is registered for the current directory only.

## Tools

| Tool | What it returns |
| --- | --- |
| `search_notes(query, folder?, template?, limit?)` | Matching pages with the lines they matched on |
| `get_page(id)` | One page in full, by frontmatter id |
| `list_pages(template?, folder?, date_from?, date_to?, include_archived=false)` | Pages, newest first, without bodies |
| `get_weekly_pages(weeks_back)` | Weekly pages by `period_start`, newest first |
| `get_goals_with_evidence()` | Goal pages, their Evidence bullets, and the pages citing them |
| `append_to_page(id, markdown)` | An error: the mirror is export-only in v1 |

## Prompts

`weekly_summary`, `next_week_priorities`, `performance_review_draft(period)`.

## Tests

```bash
.venv/bin/python -m pytest tests -q
```

The tests build a fixture mirror in a temporary folder — including a hand-written file
with no frontmatter, which the server must ignore — and cover every tool's logic. They
do not need the `mcp` package: the reading lives in `olai_mcp/mirror.py`, and
`server.py` is only the wiring.

## Without installing anything

`olai_mcp.standalone` is the same tools over an MCP stdio server written against the
Python standard library, for machines where packages cannot be installed:

```bash
claude mcp add olai --scope user \
  --env OLAI_ROOT="$HOME/Olai" \
  --env PYTHONPATH="/path/to/olai/mcp-server" \
  -- python3 -m olai_mcp.standalone
```

It runs on the `python3` macOS ships. Both servers call the same functions in
`olai_mcp/tools.py`, so they cannot drift apart. See `docs/work-laptop.md`.
