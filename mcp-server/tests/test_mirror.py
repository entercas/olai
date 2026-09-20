from __future__ import annotations

from datetime import date
from pathlib import Path

from olai_mcp import mirror


def test_loads_only_files_the_app_wrote(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    titles = {page.title for page in pages}
    assert "Hand written" not in titles
    assert len(pages) == 5


def test_frontmatter_is_parsed(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    weekly = next(p for p in pages if p.title == "Week of Sep 14, 2026")

    assert weekly.template == "weekly"
    assert weekly.period_start is not None
    assert weekly.period_start.date() == date(2026, 9, 14)
    assert weekly.archived is False
    assert weekly.folder == ""


def test_quoted_titles_with_colons_survive(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    goal = next(p for p in pages if p.template == "goals")
    assert goal.title == "Goal: reliability"


def test_pages_come_back_newest_first(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    stamps = [page.updated for page in pages if page.updated]
    assert stamps == sorted(stamps, reverse=True)


def test_archived_pages_are_excluded_unless_asked_for(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    assert all(not p.archived for p in mirror.filter_pages(pages))
    assert any(p.archived for p in mirror.filter_pages(pages, include_archived=True))


def test_filter_by_template_and_folder(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    assert len(mirror.filter_pages(pages, template="weekly")) == 2
    assert {p.title for p in mirror.filter_pages(pages, folder="Work")} == {
        "Goal: reliability",
        "Reliability review",
    }


def test_filter_by_date_range(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    recent = mirror.filter_pages(pages, date_from="2026-09-15T00:00:00Z")
    assert {p.title for p in recent} == {"Week of Sep 14, 2026"}


def test_search_matches_title_and_body_and_returns_lines(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)

    hits = mirror.search_pages(pages, "converter")
    assert len(hits) == 1
    assert hits[0]["title"] == "Week of Sep 14, 2026"
    assert any("converter" in line.lower() for line in hits[0]["matches"])

    assert mirror.search_pages(pages, "reliability")
    assert mirror.search_pages(pages, "") == []


def test_search_limit_is_respected(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    assert len(mirror.search_pages(pages, "e", limit=2)) <= 2


def test_weekly_pages_go_back_the_requested_number_of_weeks(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    today = date(2026, 9, 18)  # the week of Sep 14

    one = mirror.weekly_pages(pages, weeks_back=1, today=today)
    assert [p.title for p in one] == ["Week of Sep 14, 2026"]

    two = mirror.weekly_pages(pages, weeks_back=2, today=today)
    assert [p.title for p in two] == ["Week of Sep 14, 2026", "Week of Sep 7, 2026"]


def test_goals_come_back_with_their_evidence_and_citations(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    goals = mirror.goals_with_evidence(pages)

    assert len(goals) == 1
    entry = goals[0]
    assert entry["goal"]["title"] == "Goal: reliability"
    assert entry["evidence_bullets"] == ["Crash rate down 40%", "Two fixes shipped"]
    assert [page["title"] for page in entry["referenced_by"]] == ["Reliability review"]


def test_section_bullets_stop_at_the_next_heading():
    body = "## Evidence\n\n- one\n- two\n\n## Next\n\n- three\n"
    assert mirror.section_bullets(body, "Evidence") == ["one", "two"]
    assert mirror.section_bullets(body, "Missing") == []


def test_find_page_is_case_insensitive(mirror_root: Path):
    pages = mirror.load_pages(mirror_root)
    found = mirror.find_page(pages, "aaaaaaa1-0000-0000-0000-000000000001")
    assert found is not None and found.title == "Week of Sep 14, 2026"
    assert mirror.find_page(pages, "nope") is None


def test_a_missing_root_is_empty_not_an_error(tmp_path: Path):
    assert mirror.load_pages(tmp_path / "nothing-here") == []


def test_root_comes_from_argument_then_environment(monkeypatch):
    monkeypatch.setenv("OLAI_ROOT", "/tmp/from-env")
    assert mirror.mirror_root() == Path("/tmp/from-env")
    assert mirror.mirror_root("/tmp/explicit") == Path("/tmp/explicit")
    monkeypatch.delenv("OLAI_ROOT")
    assert mirror.mirror_root() == Path.home() / "Olai"
