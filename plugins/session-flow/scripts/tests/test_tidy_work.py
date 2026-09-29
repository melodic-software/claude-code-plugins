"""Contract tests for tidy_work.py, run as a subprocess.

Every fixture is a temp HOME plus a temp git repo; the real ~/.work is never read.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

SCRIPT = Path(__file__).resolve().parents[1] / "tidy_work.py"
DAY = 86400

HANDOFF_STALE = "20260101T100000Z-handoff-old.md"
HANDOFF_FRESH = "20260920T100000Z-handoff-new.md"
HANDOFF_LINKED = "20260102T100000Z-handoff-linked.md"
HANDOFF_NAMED = "20260103T100000Z-handoff-named.md"
HANDOFF_CLOSED = "20260104T100000Z-handoff-closed.md"
HANDOFF_LATER = "20260105T100000Z-handoff-later.md"
HOME_HANDOFF = "20260101T090000Z-handoff-home.md"
SLICE_LINK = "melodic-software/claude-code-plugins#99"

CHECKLIST_DONE = (
    "# Workflow Checklist\n\n## Stages\n\n- [x] 0. Contract\n"
    "- [ ] 1. Explore: SKIPPED, intent crisp\n\n## PR lifecycle\n\n- [ ] PR created\n"
)
CHECKLIST_OPEN = (
    "# Workflow Checklist\n\n## Stages\n\n- [x] 0. Contract\n- [ ] 1. Explore\n"
)


def age(path: Path, days: float) -> None:
    stamp = time.time() - days * DAY
    if path.is_dir():
        for base, dirs, files in os.walk(path):
            for name in (*dirs, *files):
                os.utime(os.path.join(base, name), (stamp, stamp))
    os.utime(path, (stamp, stamp))


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def handoff(path: Path, extra: str = "", body: str = "") -> None:
    write(path, f"---\ntype: handoff\n{extra}---\n\n{body}\n")


@pytest.fixture
def env(tmp_path: Path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    home.mkdir()
    repo.mkdir()
    subprocess.run(
        ["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True
    )
    write(repo / ".work" / ".gitignore", "*\n")
    return tmp_path, home, repo


def build(env) -> None:
    _, home, repo = env
    work = repo / ".work"
    handoffs = work / "handoffs"
    for name, extra, days in (
        (HANDOFF_STALE, "", 60),
        (HANDOFF_FRESH, "", 0),
        (HANDOFF_LINKED, "topic: linked\nissue: 5222\n", 60),
        (HANDOFF_CLOSED, "pr: 7\n", 60),
        (HANDOFF_NAMED, "", 60),
    ):
        handoff(handoffs / name, extra)
        age(handoffs / name, days)
    handoff(handoffs / HANDOFF_LATER, body=f"See {HANDOFF_NAMED} for the prior state.")
    age(handoffs / HANDOFF_LATER, 30)
    write(handoffs / "notes.txt", "stray")
    age(handoffs / "notes.txt", 60)

    write(work / "unfinished" / "workflow-checklist.md", CHECKLIST_OPEN)
    age(work / "unfinished", 60)
    write(work / "finished" / "workflow-checklist.md", CHECKLIST_DONE)
    age(work / "finished", 60)

    write(
        work / "widget" / "INDEX.md",
        f"---\nslice: widget\nabstract: w\nstatus: active\nissue: {SLICE_LINK}\n---\n",
    )
    age(work / "widget", 60)

    write(work / "drain" / "status" / "5222.json", "{}")
    age(work / "drain", 90)

    write(work / "reviews" / "feat-x" / "report.md", "r")
    age(work / "reviews", 60)

    handoff(home / ".work" / "handoffs" / HOME_HANDOFF)
    age(home / ".work", 60)


def run_tidy(env, command: str, *args: str) -> subprocess.CompletedProcess[str]:
    _, home, repo = env
    return subprocess.run(
        [sys.executable, str(SCRIPT), command, *args],
        cwd=repo,
        env={**os.environ, "HOME": str(home)},
        capture_output=True,
        text=True,
        check=False,
    )


def run_cli(env, *args: str) -> subprocess.CompletedProcess[str]:
    return run_tidy(env, "report", *args)


def report(env, *args: str) -> dict[str, dict]:
    result = run_cli(env, "--json", *args)
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    return {Path(item["path"]).name: item for item in payload["items"]}


def links(tmp_path: Path, table: dict[str, str]) -> list[str]:
    path = tmp_path / "links.json"
    path.write_text(json.dumps(table), encoding="utf-8")
    return ["--link-state", str(path)]


def snapshot(*roots: Path) -> list[tuple[str, float, int]]:
    return sorted(
        (p.as_posix(), p.lstat().st_mtime, p.lstat().st_size)
        for root in roots
        for p in root.rglob("*")
    )


def test_kinds_and_in_flight(env):
    build(env)
    table = {"#5222": "open", "#7": "closed", SLICE_LINK: "open"}
    items = report(env, *links(env[0], table))
    assert items[HANDOFF_STALE]["kind"] == "handoff"
    assert not items[HANDOFF_STALE]["keep"]
    assert items[HANDOFF_FRESH]["reasons"] == ["modified within 14 days"]
    assert items[HANDOFF_LINKED]["reasons"] == ["link #5222 is open"]
    assert not items[HANDOFF_CLOSED]["in_flight"]
    assert items[HANDOFF_NAMED]["reasons"] == ["named by a later handoff"]
    assert items["notes.txt"]["kind"] == "unknown"
    assert items["notes.txt"]["keep"]
    assert items["unfinished"]["kind"] == "checklist"
    assert items["unfinished"]["reasons"] == ["checklist has an unfinished stage"]
    assert items["finished"]["kind"] == "checklist"
    assert not items["finished"]["keep"]
    assert items["widget"]["kind"] == "slice"
    assert items["widget"]["reasons"] == [f"link {SLICE_LINK} is open"]
    assert items["feat-x"]["kind"] == "scratch"
    assert not items["feat-x"]["keep"]


def test_drain_status_tree_is_unknown_and_kept(env):
    build(env)
    drain = report(env, "--offline")["drain"]
    assert drain["kind"] == "unknown"
    assert drain["keep"]
    assert not drain["in_flight"]


def test_closed_link_frees_a_slice(env):
    build(env)
    assert not report(env, *links(env[0], {SLICE_LINK: "closed"}))["widget"]["keep"]


def test_offline_and_missing_links_are_in_flight(env):
    build(env)
    assert report(env, "--offline")[HANDOFF_CLOSED]["reasons"] == ["link #7 is unknown"]
    assert report(env, *links(env[0], {}))[HANDOFF_LINKED]["in_flight"]


def test_days_window(env):
    build(env)
    stale = report(env, "--offline", "--days", "100")[HANDOFF_STALE]
    assert stale["reasons"] == ["modified within 100 days"]


def test_home_root_is_inventoried(env):
    build(env)
    result = run_cli(env, "--json", "--offline")
    payload = json.loads(result.stdout)
    assert {r["label"] for r in payload["roots"]} == {"memory", "home"}
    home_items = [i for i in payload["items"] if i["root"] == "home"]
    assert [Path(i["path"]).name for i in home_items] == [HOME_HANDOFF]


def test_self_ignore_file_is_not_an_item(env):
    build(env)
    assert ".gitignore" not in report(env, "--offline")


def test_report_is_read_only(env):
    build(env)
    _, home, repo = env
    before = snapshot(repo, home)
    assert run_cli(env, "--offline").returncode == 0
    assert run_cli(env, "--json", *links(env[0], {})).returncode == 0
    assert snapshot(repo, home) == before


def test_text_table(env):
    build(env)
    result = run_cli(env, "--offline")
    assert result.returncode == 0
    assert "KIND" in result.stdout
    assert "keep: unknown kind" in result.stdout
    assert "items," in result.stdout.splitlines()[-1]


def test_bad_link_state_exits_2(env):
    bad = env[0] / "bad.json"
    bad.write_text("[]", encoding="utf-8")
    assert run_cli(env, "--link-state", str(bad)).returncode == 2


STATE = {"#5222": "open", "#7": "closed", SLICE_LINK: "open"}
STALE = {
    HANDOFF_STALE,
    HANDOFF_CLOSED,
    HANDOFF_LATER,
    HOME_HANDOFF,
    "finished",
    "feat-x",
}
RETRO = "20260101T100000Z-running-retro-x.md"
RETRO2 = "20260102T100000Z-running-retro-y.md"


def tree(*roots: Path) -> set[str]:
    return {p.as_posix() for root in roots for p in root.rglob("*")}


def clean(env, *args: str) -> subprocess.CompletedProcess[str]:
    return run_tidy(env, "clean", *links(env[0], STATE), *args)


def test_clean_dry_run_changes_nothing_and_prints_absolute_paths(env):
    build(env)
    _, home, repo = env
    before = snapshot(repo, home)
    result = clean(env)
    assert result.returncode == 0, result.stderr
    assert snapshot(repo, home) == before
    listed = [
        Path(line.split(": ", 1)[1])
        for line in result.stdout.splitlines()
        if line.startswith("would remove: ")
    ]
    assert {p.name for p in listed} == STALE
    assert all(p.is_absolute() for p in listed)


def test_clean_apply_removes_only_stale_known_items(env):
    build(env)
    _, home, repo = env
    before = tree(repo, home)
    result = clean(env, "--apply")
    assert result.returncode == 0, result.stderr
    gone = {Path(p).name for p in before - tree(repo, home)}
    assert gone == STALE | {"report.md", "workflow-checklist.md"}
    work = repo / ".work"
    for survivor in (
        work / "handoffs" / HANDOFF_FRESH,
        work / "handoffs" / HANDOFF_LINKED,
        work / "handoffs" / HANDOFF_NAMED,
        work / "handoffs" / "notes.txt",
        work / "unfinished",
        work / "widget",
        work / "drain" / "status" / "5222.json",
    ):
        assert survivor.exists(), survivor
    assert (work / ".gitignore").read_text(encoding="utf-8") == "*\n"


def test_clean_offline_apply_keeps_unresolved_links(env):
    build(env)
    _, _, repo = env
    result = run_tidy(env, "clean", "--offline", "--apply")
    assert result.returncode == 0, result.stderr
    assert (repo / ".work" / "handoffs" / HANDOFF_CLOSED).exists()
    assert not (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()


def test_clean_refuses_symlink_leaving_the_root(env):
    build(env)
    tmp, _, repo = env
    outside = tmp / "outside"
    write(outside / "precious.txt", "keep")
    stale = repo / ".work" / "reviews" / "feat-x"
    (stale / "escape").symlink_to(outside)
    age(stale, 60)
    stamp = time.time() - 60 * DAY
    os.utime(stale / "escape", (stamp, stamp), follow_symlinks=False)
    result = clean(env, "--apply")
    assert result.returncode == 1
    assert f"refused: {stale.as_posix()}" in result.stdout
    assert stale.exists()
    assert (outside / "precious.txt").read_text(encoding="utf-8") == "keep"
    assert not (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()


def test_clean_never_follows_a_symlinked_item(env):
    build(env)
    tmp, _, repo = env
    outside = tmp / "outside-dir"
    write(outside / "workflow-checklist.md", CHECKLIST_DONE)
    age(outside, 60)
    (repo / ".work" / "linked").symlink_to(outside)
    assert clean(env, "--apply").returncode == 0
    assert (repo / ".work" / "linked").is_symlink()
    assert (outside / "workflow-checklist.md").exists()


def misplace(env) -> None:
    _, _, repo = env
    work = repo / ".work"
    handoff(work / HANDOFF_STALE)
    write(work / RETRO, "---\ntype: running-retro\n---\n")
    write(work / "handoffs" / RETRO2, "---\ntype: running-retro\n---\n")
    write(work / "notes.txt", "stray")
    write(work / "drain" / "status" / HANDOFF_FRESH, "not a handoff here")


def normalize(env, *args: str) -> subprocess.CompletedProcess[str]:
    return run_tidy(env, "normalize", *args)


def test_normalize_dry_run_changes_nothing(env):
    misplace(env)
    _, home, repo = env
    before = snapshot(repo, home)
    result = normalize(env)
    assert result.returncode == 0, result.stderr
    assert snapshot(repo, home) == before
    work = repo / ".work"
    expected = (
        f"would move: {work / HANDOFF_STALE} -> {work / 'handoffs' / HANDOFF_STALE}"
    )
    assert expected in result.stdout


def test_normalize_apply_moves_without_deleting_and_skips_unknown(env):
    misplace(env)
    _, _, repo = env
    work = repo / ".work"
    content = (work / HANDOFF_STALE).read_text(encoding="utf-8")
    result = normalize(env, "--apply")
    assert result.returncode == 0, result.stderr
    assert (work / "handoffs" / HANDOFF_STALE).read_text(encoding="utf-8") == content
    assert not (work / HANDOFF_STALE).exists()
    assert (work / "running-retros" / RETRO).exists()
    assert (work / "running-retros" / RETRO2).exists()
    assert not (work / "handoffs" / RETRO2).exists()
    assert (work / "notes.txt").read_text(encoding="utf-8") == "stray"
    assert (work / "drain" / "status" / HANDOFF_FRESH).exists()
    assert (work / ".gitignore").read_text(encoding="utf-8") == "*\n"


def test_normalize_refuses_to_overwrite(env):
    misplace(env)
    _, _, repo = env
    work = repo / ".work"
    handoff(work / "handoffs" / HANDOFF_STALE, body="original")
    result = normalize(env, "--apply")
    assert result.returncode == 1
    assert "target exists" in result.stdout
    assert "original" in (work / "handoffs" / HANDOFF_STALE).read_text(encoding="utf-8")
    assert (work / HANDOFF_STALE).exists()
    assert (work / "running-retros" / RETRO).exists()


def test_normalize_refuses_symlinked_target_dir(env):
    misplace(env)
    tmp, _, repo = env
    outside = tmp / "outside"
    outside.mkdir()
    (repo / ".work" / "running-retros").symlink_to(outside)
    result = normalize(env, "--apply")
    assert result.returncode == 1
    assert list(outside.iterdir()) == []
    assert (repo / ".work" / RETRO).exists()
