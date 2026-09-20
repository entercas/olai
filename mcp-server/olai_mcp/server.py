"""The Olai MCP server: read-only tools over the Markdown mirror.

Transport is stdio. The root comes from OLAI_ROOT, defaulting to ~/Olai. Nothing
here writes to the mirror -- the app owns it, and v1 is export-only.
"""

from __future__ import annotations

import json
from typing import Any

from mcp.server.mcpserver import MCPServer

from . import mirror

# MCP 2.x: FastMCP was renamed MCPServer. Pin mcp<2 if an older runtime is needed.
mcp = MCPServer("olai")


def _pages() -> list[mirror.Page]:
    return mirror.load_pages(mirror.mirror_root())


def _dump(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False)


# MARK: Tools


@mcp.tool()
def search_notes(
    query: str,
    folder: str | None = None,
    template: str | None = None,
    limit: int = 20,
) -> str:
    """Search pages by title and body text. Returns the matching lines for each hit."""
    pages = mirror.filter_pages(_pages(), template=template, folder=folder)
    return _dump(mirror.search_pages(pages, query, limit=limit))


@mcp.tool()
def get_page(id: str) -> str:
    """The full text of one page, by the id in its frontmatter."""
    page = mirror.find_page(_pages(), id)
    if page is None:
        return _dump({"error": f"No page with id {id}"})
    return _dump(page.as_dict())


@mcp.tool()
def list_pages(
    template: str | None = None,
    folder: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    include_archived: bool = False,
) -> str:
    """Pages matching the filters, newest first, without their bodies."""
    pages = mirror.filter_pages(
        _pages(),
        template=template,
        folder=folder,
        date_from=date_from,
        date_to=date_to,
        include_archived=include_archived,
    )
    return _dump([page.as_dict(include_body=False) for page in pages])


@mcp.tool()
def get_weekly_pages(weeks_back: int = 4) -> str:
    """Weekly pages for the last `weeks_back` weeks, newest first, with their bodies."""
    pages = mirror.weekly_pages(_pages(), weeks_back)
    return _dump([page.as_dict() for page in pages])


@mcp.tool()
def get_goals_with_evidence() -> str:
    """Every goal page, its Evidence bullets, and the pages whose frontmatter cites it."""
    return _dump(mirror.goals_with_evidence(_pages()))


@mcp.tool()
def append_to_page(id: str, markdown: str) -> str:
    """Not available: the mirror is export-only in v1."""
    return _dump(
        {
            "error": "The Olai mirror is export-only. Edit the page in Olai; "
            "the mirror is rewritten from it.",
            "id": id,
        }
    )


# MARK: Prompts


@mcp.prompt()
def weekly_summary(weeks_back: int = 1) -> str:
    """Summarise recent weekly pages."""
    return (
        f"Read my weekly pages with get_weekly_pages(weeks_back={weeks_back}). "
        "Summarise what actually happened: what shipped, what moved, what stalled. "
        "Group by theme rather than by day, keep it to what the notes support, and "
        "say plainly where a week's notes are too thin to tell."
    )


@mcp.prompt()
def next_week_priorities() -> str:
    """Propose next week's priorities from recent weeks."""
    return (
        "Read the last three weekly pages with get_weekly_pages(weeks_back=3). "
        "Propose next week's priorities: unfinished to-dos that still matter, "
        "commitments made in the notes, and anything slipping week over week. "
        "Rank them, and for each one cite the page it came from."
    )


@mcp.prompt()
def performance_review_draft(period: str = "the last quarter") -> str:
    """Draft a review from goals and their evidence."""
    return (
        f"Draft a performance review covering {period}. "
        "Start with get_goals_with_evidence() for the goals and what is filed against "
        "them, then get_weekly_pages(weeks_back=13) for what the weeks show. "
        "For each goal: what was achieved, the evidence for it, and what is still open. "
        "Use only what the notes support, and list any goal with thin evidence "
        "separately rather than padding it."
    )


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
