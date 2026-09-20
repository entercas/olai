"""A fixture mirror folder, written the way the app writes one."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _page(
    *,
    page_id: str,
    title: str,
    body: str,
    template: str | None = None,
    folder: str = "",
    updated: str = "2026-09-18T10:00:00Z",
    period_start: str | None = None,
    goals: list[str] | None = None,
    archived: bool = False,
    pinned: bool = False,
) -> str:
    goal_list = ", ".join(f'"{goal}"' for goal in (goals or []))
    return (
        "---\n"
        f"id: {page_id}\n"
        f'title: "{title}"\n'
        f"template: {f'\"{template}\"' if template else 'null'}\n"
        f'folder: "{folder}"\n'
        "created: 2026-09-01T09:00:00Z\n"
        f"updated: {updated}\n"
        f"period_start: {period_start or 'null'}\n"
        "event_date: null\n"
        f"goals: [{goal_list}]\n"
        f"archived: {'true' if archived else 'false'}\n"
        f"pinned: {'true' if pinned else 'false'}\n"
        "---\n\n"
        f"{body}\n"
    )


@pytest.fixture
def mirror_root(tmp_path: Path) -> Path:
    """Two weekly pages, a goal, a page citing that goal, an archived page, and a file
    the app did not write."""
    root = tmp_path / "Olai"
    (root / "Work").mkdir(parents=True)
    (root / "_archive").mkdir(parents=True)

    (root / "Week of Sep 14, 2026-aaaaaaa1.md").write_text(
        _page(
            page_id="AAAAAAA1-0000-0000-0000-000000000001",
            title="Week of Sep 14, 2026",
            template="weekly",
            period_start="2026-09-14T00:00:00Z",
            updated="2026-09-18T10:00:00Z",
            body="## Priorities\n\n- Ship the mirror\n\n## To-do\n\n- [x] Write converter\n- [ ] Write server\n",
        ),
        encoding="utf-8",
    )

    (root / "Week of Sep 7, 2026-aaaaaaa2.md").write_text(
        _page(
            page_id="AAAAAAA2-0000-0000-0000-000000000002",
            title="Week of Sep 7, 2026",
            template="weekly",
            period_start="2026-09-07T00:00:00Z",
            updated="2026-09-11T10:00:00Z",
            body="## Wins\n\n- Shipped the editor\n",
        ),
        encoding="utf-8",
    )

    (root / "Work" / "Goal - reliability-bbbbbbb1.md").write_text(
        _page(
            page_id="BBBBBBB1-0000-0000-0000-000000000003",
            title="Goal: reliability",
            template="goals",
            folder="Work",
            updated="2026-09-10T10:00:00Z",
            body="## Goal\n\nFewer crashes\n\n## Evidence\n\n- Crash rate down 40%\n- Two fixes shipped\n",
        ),
        encoding="utf-8",
    )

    (root / "Work" / "Reliability review-ccccccc1.md").write_text(
        _page(
            page_id="CCCCCCC1-0000-0000-0000-000000000004",
            title="Reliability review",
            folder="Work",
            updated="2026-09-09T10:00:00Z",
            goals=["BBBBBBB1-0000-0000-0000-000000000003"],
            body="Notes about reliability work.\n",
        ),
        encoding="utf-8",
    )

    (root / "_archive" / "Old plan-ddddddd1.md").write_text(
        _page(
            page_id="DDDDDDD1-0000-0000-0000-000000000005",
            title="Old plan",
            archived=True,
            updated="2026-09-02T10:00:00Z",
            body="Shelved.\n",
        ),
        encoding="utf-8",
    )

    # Something the app never wrote: no frontmatter, and it must be ignored.
    (root / "notes-from-elsewhere.md").write_text("# Hand written\n\nNot Olai's.\n", encoding="utf-8")

    return root
