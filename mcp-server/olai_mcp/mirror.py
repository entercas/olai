"""Reading the Olai Markdown mirror.

The mirror is export-only: the app writes it and never reads it back, and nothing
here writes to it either. Everything in this module is plain Python so it can be
tested without the MCP runtime.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

ARCHIVE_DIRECTORY = "_archive"
_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)
_LIST_ITEM = re.compile(r"^\s*[-*]\s+(?:\[[ xX]\]\s+)?(.*\S)\s*$")


def mirror_root(explicit: str | None = None) -> Path:
    """The folder to read, from the argument, then OLAI_ROOT, then ~/Olai."""
    root = explicit or os.environ.get("OLAI_ROOT") or "~/Olai"
    return Path(root).expanduser()


@dataclass
class Page:
    """One Markdown file: its frontmatter, its body, and where it sits."""

    id: str
    title: str
    path: Path
    body: str
    template: str | None = None
    folder: str = ""
    created: datetime | None = None
    updated: datetime | None = None
    period_start: datetime | None = None
    event_date: datetime | None = None
    goals: list[str] = field(default_factory=list)
    archived: bool = False
    pinned: bool = False

    def as_dict(self, include_body: bool = True) -> dict:
        result = {
            "id": self.id,
            "title": self.title,
            "folder": self.folder,
            "template": self.template,
            "archived": self.archived,
            "pinned": self.pinned,
            "created": _iso(self.created),
            "updated": _iso(self.updated),
            "period_start": _iso(self.period_start),
            "event_date": _iso(self.event_date),
            "goals": self.goals,
            "path": str(self.path),
        }
        if include_body:
            result["body"] = self.body
        return result

    @property
    def evidence(self) -> list[str]:
        """Bullet lines under an "Evidence" heading, for goal pages."""
        return section_bullets(self.body, "Evidence")


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


# MARK: Parsing


def parse_page(path: Path) -> Page | None:
    """Reads one file. Returns None when it has no Olai frontmatter, which is how a
    file the app did not write is ignored."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None

    match = _FRONTMATTER.match(text)
    if not match:
        return None

    fields = _parse_frontmatter(match.group(1))
    if "id" not in fields:
        return None

    return Page(
        id=str(fields.get("id", "")),
        title=str(fields.get("title", "")),
        path=path,
        body=match.group(2).strip(),
        template=fields.get("template") or None,
        folder=str(fields.get("folder") or ""),
        created=_parse_date(fields.get("created")),
        updated=_parse_date(fields.get("updated")),
        period_start=_parse_date(fields.get("period_start")),
        event_date=_parse_date(fields.get("event_date")),
        goals=fields.get("goals") or [],
        archived=bool(fields.get("archived")),
        pinned=bool(fields.get("pinned")),
    )


def _parse_frontmatter(block: str) -> dict:
    """A deliberately small YAML reader: the mirror only ever writes scalars and flat
    lists, so pulling in a YAML dependency would buy nothing."""
    fields: dict = {}
    for line in block.splitlines():
        if not line.strip() or ":" not in line:
            continue
        key, _, raw = line.partition(":")
        fields[key.strip()] = _parse_value(raw.strip())
    return fields


def _parse_value(raw: str):
    if raw in ("null", "~", ""):
        return None
    if raw in ("true", "false"):
        return raw == "true"
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if not inner:
            return []
        return [_unquote(part.strip()) for part in inner.split(",")]
    return _unquote(raw)


def _unquote(raw: str) -> str:
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return raw


def _parse_date(raw) -> datetime | None:
    if not raw or not isinstance(raw, str):
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


# MARK: Loading and querying


def load_pages(root: Path) -> list[Page]:
    """Every page in the mirror, newest first."""
    if not root.exists():
        return []

    pages = [
        page
        for path in sorted(root.rglob("*.md"))
        if (page := parse_page(path)) is not None
    ]
    pages.sort(key=lambda page: page.updated or datetime.min, reverse=True)
    return pages


def filter_pages(
    pages: list[Page],
    template: str | None = None,
    folder: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    include_archived: bool = False,
) -> list[Page]:
    selected = pages
    if not include_archived:
        selected = [page for page in selected if not page.archived]
    if template:
        selected = [page for page in selected if page.template == template]
    if folder:
        selected = [
            page
            for page in selected
            if page.folder == folder or page.folder.startswith(f"{folder}/")
        ]

    start = _parse_date(date_from)
    end = _parse_date(date_to)
    if start:
        selected = [p for p in selected if p.updated and _naive(p.updated) >= _naive(start)]
    if end:
        selected = [p for p in selected if p.updated and _naive(p.updated) <= _naive(end)]
    return selected


def _naive(value: datetime) -> datetime:
    return value.replace(tzinfo=None)


def search_pages(pages: list[Page], query: str, limit: int = 20) -> list[dict]:
    """Case-insensitive search over title and body, title matches first, each result
    carrying the line it matched on."""
    needle = query.strip().lower()
    if not needle:
        return []

    results = []
    for page in pages:
        in_title = needle in page.title.lower()
        lines = [line.strip() for line in page.body.splitlines() if needle in line.lower()]
        if not in_title and not lines:
            continue
        results.append(
            {
                "id": page.id,
                "title": page.title,
                "folder": page.folder,
                "template": page.template,
                "updated": _iso(page.updated),
                "matches": lines[:5],
                "_rank": 0 if in_title else 1,
            }
        )

    results.sort(key=lambda item: (item["_rank"], item["updated"] or ""), reverse=False)
    for item in results:
        del item["_rank"]
    return results[:limit]


def current_monday(today: date | None = None) -> date:
    """The Monday of the week a page created now would be for.

    Sunday belongs to the week that starts the next day, matching how the app titles a
    weekly page: one started on a Sunday is for the week ahead. Without this the server
    would not return the page the app had just created.
    """
    today = today or date.today()
    if today.weekday() == 6:  # Sunday
        return today + timedelta(days=1)
    return today - timedelta(days=today.weekday())


def weekly_pages(pages: list[Page], weeks_back: int, today: date | None = None) -> list[Page]:
    """Weekly pages whose period_start falls in the last `weeks_back` weeks."""
    monday = current_monday(today)
    earliest = monday - timedelta(weeks=max(weeks_back - 1, 0))

    selected = [
        page
        for page in pages
        if page.template == "weekly"
        and page.period_start
        and earliest <= page.period_start.date() <= monday
    ]
    selected.sort(key=lambda page: page.period_start or datetime.min, reverse=True)
    return selected


def goals_with_evidence(pages: list[Page]) -> list[dict]:
    """Every goal page, with the pages that name it in their `goals` frontmatter."""
    goals = [page for page in pages if page.template == "goals"]

    result = []
    for goal in goals:
        referencing = [
            page for page in pages if goal.id in page.goals and page.id != goal.id
        ]
        result.append(
            {
                "goal": goal.as_dict(include_body=True),
                "evidence_bullets": goal.evidence,
                "referenced_by": [page.as_dict(include_body=False) for page in referencing],
            }
        )
    return result


def section_bullets(body: str, heading: str) -> list[str]:
    """Bullet lines under a heading, up to the next heading of any level."""
    lines = body.splitlines()
    wanted = heading.strip().lower()

    bullets: list[str] = []
    inside = False
    for line in lines:
        if line.startswith("#"):
            inside = line.lstrip("#").strip().lower() == wanted
            continue
        if inside and (match := _LIST_ITEM.match(line)):
            bullets.append(match.group(1))
    return bullets


def find_page(pages: list[Page], page_id: str) -> Page | None:
    wanted = page_id.strip().lower()
    for page in pages:
        if page.id.lower() == wanted:
            return page
    return None
