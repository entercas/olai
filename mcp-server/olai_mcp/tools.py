"""The tools and prompts themselves, independent of any MCP runtime.

Kept free of the `mcp` package so the same behaviour is available whether the server
runs on the SDK or on the standard library alone. Everything here reads the mirror and
nothing writes to it.
"""

from __future__ import annotations

import json
from typing import Any, Callable

from . import mirror


def _pages() -> list[mirror.Page]:
    return mirror.load_pages(mirror.mirror_root())


def _dump(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False)


# MARK: Tools


def search_notes(
    query: str,
    folder: str | None = None,
    template: str | None = None,
    limit: int = 20,
) -> str:
    pages = mirror.filter_pages(_pages(), template=template, folder=folder)
    return _dump(mirror.search_pages(pages, query, limit=limit))


def get_page(id: str) -> str:
    page = mirror.find_page(_pages(), id)
    if page is None:
        return _dump({"error": f"No page with id {id}"})
    return _dump(page.as_dict())


def list_pages(
    template: str | None = None,
    folder: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    include_archived: bool = False,
) -> str:
    pages = mirror.filter_pages(
        _pages(),
        template=template,
        folder=folder,
        date_from=date_from,
        date_to=date_to,
        include_archived=include_archived,
    )
    return _dump([page.as_dict(include_body=False) for page in pages])


def get_weekly_pages(weeks_back: int = 4) -> str:
    return _dump([page.as_dict() for page in mirror.weekly_pages(_pages(), weeks_back)])


def get_goals_with_evidence() -> str:
    return _dump(mirror.goals_with_evidence(_pages()))


def append_to_page(id: str, markdown: str = "") -> str:
    return _dump(
        {
            "error": "The Olai mirror is export-only. Edit the page in Olai; "
            "the mirror is rewritten from it.",
            "id": id,
        }
    )


TOOLS: list[dict[str, Any]] = [
    {
        "name": "search_notes",
        "description": "Search pages by title and body text. Returns the matching lines for each hit.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Text to look for."},
                "folder": {"type": "string", "description": "Limit to a folder path."},
                "template": {"type": "string", "description": "Limit to a template id."},
                "limit": {"type": "integer", "description": "Most results to return."},
            },
            "required": ["query"],
        },
        "run": search_notes,
    },
    {
        "name": "get_page",
        "description": "The full text of one page, by the id in its frontmatter.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"],
        },
        "run": get_page,
    },
    {
        "name": "list_pages",
        "description": "Pages matching the filters, newest first, without their bodies.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "template": {"type": "string"},
                "folder": {"type": "string"},
                "date_from": {"type": "string", "description": "ISO date, inclusive."},
                "date_to": {"type": "string", "description": "ISO date, inclusive."},
                "include_archived": {"type": "boolean"},
            },
        },
        "run": list_pages,
    },
    {
        "name": "get_weekly_pages",
        "description": "Weekly pages for the last N weeks, newest first, with their bodies.",
        "inputSchema": {
            "type": "object",
            "properties": {"weeks_back": {"type": "integer"}},
        },
        "run": get_weekly_pages,
    },
    {
        "name": "get_goals_with_evidence",
        "description": "Every goal page, its Evidence bullets, and the pages whose frontmatter cites it.",
        "inputSchema": {"type": "object", "properties": {}},
        "run": get_goals_with_evidence,
    },
    {
        "name": "append_to_page",
        "description": "Not available: the mirror is export-only in v1.",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}, "markdown": {"type": "string"}},
            "required": ["id"],
        },
        "run": append_to_page,
    },
]


# MARK: Prompts


def weekly_summary(weeks_back: str = "1") -> str:
    return (
        f"Read my weekly pages with get_weekly_pages(weeks_back={weeks_back}). "
        "Summarise what actually happened: what shipped, what moved, what stalled. "
        "Group by theme rather than by day, keep it to what the notes support, and "
        "say plainly where a week's notes are too thin to tell."
    )


def next_week_priorities() -> str:
    return (
        "Read the last three weekly pages with get_weekly_pages(weeks_back=3). "
        "Propose next week's priorities: unfinished to-dos that still matter, "
        "commitments made in the notes, and anything slipping week over week. "
        "Rank them, and for each one cite the page it came from."
    )


def performance_review_draft(period: str = "the last quarter") -> str:
    return (
        f"Draft a performance review covering {period}. "
        "Start with get_goals_with_evidence() for the goals and what is filed against "
        "them, then get_weekly_pages(weeks_back=13) for what the weeks show. "
        "For each goal: what was achieved, the evidence for it, and what is still open. "
        "Use only what the notes support, and list any goal with thin evidence "
        "separately rather than padding it."
    )


PROMPTS: list[dict[str, Any]] = [
    {
        "name": "weekly_summary",
        "description": "Summarise recent weekly pages.",
        "arguments": [
            {"name": "weeks_back", "description": "How many weeks to read.", "required": False}
        ],
        "run": weekly_summary,
    },
    {
        "name": "next_week_priorities",
        "description": "Propose next week's priorities from recent weeks.",
        "arguments": [],
        "run": next_week_priorities,
    },
    {
        "name": "performance_review_draft",
        "description": "Draft a review from goals and their evidence.",
        "arguments": [
            {"name": "period", "description": "The period under review.", "required": False}
        ],
        "run": performance_review_draft,
    },
]


def find(entries: list[dict[str, Any]], name: str) -> Callable[..., str] | None:
    for entry in entries:
        if entry["name"] == name:
            return entry["run"]
    return None
