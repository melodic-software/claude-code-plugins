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
SIDECAR_STALE = "20260101T100000Z-handoff-old.slots.json"
SIDECAR_ORPHAN = "20260107T100000Z-handoff-gone.slots.json"
HANDOFF_FRESH = "20260920T100000Z-handoff-new.md"
HANDOFF_LINKED = "20260102T100000Z-handoff-linked.md"
HANDOFF_NAMED = "20260103T100000Z-handoff-named.md"
HANDOFF_CLOSED = "20260104T100000Z-handoff-closed.md"
HANDOFF_LATER = "20260105T100000Z-handoff-later.md"
HANDOFF_URL = "20260106T100000Z-handoff-url.md"
HOME_HANDOFF = "20260101T090000Z-handoff-home.md"
URL_REF = "melodic-software/claude-code-plugins#99"

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


def handoff(path: Path, body: str = "") -> None:
    """A handoff as the writer produces it: no issue or PR keys in the frontmatter."""
    write(
        path,
        "---\ntype: handoff\nhandoff_shape: 2\ndate: 2026-01-01T10:00:00Z\n"
        "topic: x\nsession_id: 00000000-0000-4000-8000-000000000000\n"
        f"transcript: /t.jsonl\nchain:\n  - {path.name}\n---\n\n{body}\n",
    )


def slice_dir(path: Path, status: str | None) -> None:
    line = "" if status is None else f"status: {status}   # active | parked | done\n"
    write(path / "INDEX.md", f"---\nslice: {path.name}\nabstract: a\n{line}---\n")


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
    for name, body, days in (
        (HANDOFF_STALE, "", 60),
        (HANDOFF_FRESH, "", 0),
        (HANDOFF_LINKED, "Open follow-up: #5222.", 60),
        (HANDOFF_CLOSED, "Shipped in PR #7.", 60),
        (HANDOFF_URL, f"https://github.com/{URL_REF.replace('#', '/pull/')}", 60),
        (HANDOFF_NAMED, "", 60),
    ):
        handoff(handoffs / name, body)
        age(handoffs / name, days)
    write(handoffs / SIDECAR_STALE, "{}")
    age(handoffs / SIDECAR_STALE, 60)
    write(handoffs / SIDECAR_ORPHAN, "{}")
    age(handoffs / SIDECAR_ORPHAN, 60)
    handoff(handoffs / HANDOFF_LATER, f"See {HANDOFF_NAMED} for the prior state.")
    age(handoffs / HANDOFF_LATER, 30)
    write(handoffs / "notes.txt", "stray")
    age(handoffs / "notes.txt", 60)

    write(work / "unfinished" / "workflow-checklist.md", CHECKLIST_OPEN)
    age(work / "unfinished", 60)
    write(work / "finished" / "workflow-checklist.md", CHECKLIST_DONE)
    age(work / "finished", 60)

    for name, status in (
        ("widget", "active"),
        ("parked", "parked"),
        ("unmarked", None),
        ("shipped", "done"),
    ):
        slice_dir(work / name, status)
        age(work / name, 60)
    slice_dir(work / "tree", "done")
    slice_dir(work / "tree" / "child", "parked")
    age(work / "tree", 60)

    write(work / "drain" / "status" / "5222.json", "{}")
    age(work / "drain", 90)

    write(work / "reviews" / "feat-x" / "report.md", "r")
    age(work / "reviews", 60)
    write(work / "exports" / "20260101T100000Z-talk.txt", "conversation")
    age(work / "exports", 60)

    handoff(home / ".work" / "handoffs" / HOME_HANDOFF)
    age(home / ".work", 60)


def run_tidy(
    env,
    command: str,
    *args: str,
    cwd: Path | None = None,
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    _, home, repo = env
    return subprocess.run(
        [sys.executable, str(SCRIPT), command, *args],
        cwd=cwd or repo,
        env={**os.environ, "HOME": str(home), **(extra_env or {})},
        capture_output=True,
        text=True,
        check=False,
    )


def run_cli(env, *args: str, **kwargs) -> subprocess.CompletedProcess[str]:
    return run_tidy(env, "report", *args, **kwargs)


def report(env, *args: str, **kwargs) -> dict[str, dict]:
    result = run_cli(env, "--json", *args, **kwargs)
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


needs_posix_sh = pytest.mark.skipif(
    sys.platform == "win32", reason="the fake gh is a shell script"
)


def fake_gh(tmp_path: Path, body: str) -> dict[str, str]:
    """A `gh` on PATH that logs each call to gh-calls.log; returns the env to use."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(f'#!/bin/sh\necho "$*" >> "{tmp_path}/gh-calls.log"\n{body}\n')
    gh.chmod(0o755)
    return {"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}


def test_kinds_and_in_flight(env):
    build(env)
    table = {"#5222": "open", "#7": "closed", URL_REF: "open"}
    items = report(env, *links(env[0], table))
    assert items[HANDOFF_STALE]["kind"] == "handoff"
    assert not items[HANDOFF_STALE]["keep"]
    assert SIDECAR_STALE not in items
    assert items[SIDECAR_ORPHAN]["kind"] == "unknown"
    assert items[SIDECAR_ORPHAN]["keep"]
    assert items[HANDOFF_FRESH]["reasons"] == ["modified within 14 days"]
    assert items[HANDOFF_LINKED]["reasons"] == ["link #5222 is open"]
    assert items[HANDOFF_URL]["reasons"] == [f"link {URL_REF} is open"]
    assert not items[HANDOFF_CLOSED]["in_flight"]
    assert items[HANDOFF_NAMED]["reasons"] == ["named by a later handoff"]
    assert items["notes.txt"]["kind"] == "unknown"
    assert items["notes.txt"]["keep"]
    assert items["unfinished"]["kind"] == "checklist"
    assert items["unfinished"]["reasons"] == [
        "workflow-checklist.md has an unfinished stage"
    ]
    assert items["finished"]["kind"] == "checklist"
    assert not items["finished"]["keep"]
    assert items["feat-x"]["kind"] == "concern"
    assert items["feat-x"]["keep"]
    assert not items["feat-x"]["in_flight"]
    assert items["20260101T100000Z-talk.txt"]["kind"] == "concern"
    assert items["20260101T100000Z-talk.txt"]["keep"]


def test_slice_status_decides_whether_an_idle_slice_is_stale(env):
    build(env)
    items = report(env, "--offline")
    assert items["widget"]["reasons"] == ["INDEX.md status is active"]
    assert items["parked"]["reasons"] == ["INDEX.md status is parked"]
    assert items["unmarked"]["reasons"] == ["INDEX.md status is missing"]
    assert items["shipped"]["kind"] == "slice"
    assert not items["shipped"]["keep"]
    assert items["tree"]["reasons"] == ["child/INDEX.md status is parked"]
    assert all(items[name]["keep"] for name in ("widget", "parked", "unmarked", "tree"))


def test_only_references_in_the_text_count_not_frontmatter_keys(env):
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    write(
        handoffs / HANDOFF_STALE,
        "---\ntype: handoff\nissue: 5222\npr: 7\n---\n\nplain 1234, C#5, &#123;, "
        "#000, color #123abc\n",
    )
    age(handoffs / HANDOFF_STALE, 60)
    assert report(env, "--offline")[HANDOFF_STALE]["reasons"] == []

    write(
        handoffs / HANDOFF_STALE,
        "---\ntype: handoff\n---\n\nsee #5222, org/repo#9 and "
        "https://github.com/o/r/issues/12#issuecomment-1\n",
    )
    age(handoffs / HANDOFF_STALE, 60)
    reasons = report(env, "--offline")[HANDOFF_STALE]["reasons"]
    assert reasons == [
        "link #5222 is unknown",
        "link org/repo#9 is unknown",
        "link o/r#12 is unknown",
    ]


def test_closed_link_frees_a_handoff(env):
    build(env)
    table = {"#5222": "closed", "#7": "closed", URL_REF: "merged"}
    items = report(env, *links(env[0], table))
    assert not items[HANDOFF_LINKED]["keep"]
    assert not items[HANDOFF_URL]["keep"]


def test_offline_and_missing_links_are_in_flight(env):
    build(env)
    assert report(env, "--offline")[HANDOFF_CLOSED]["reasons"] == ["link #7 is unknown"]
    assert report(env, *links(env[0], {}))[HANDOFF_LINKED]["in_flight"]


def test_links_are_looked_up_only_when_nothing_cheaper_keeps_the_item(env):
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    handoff(handoffs / HANDOFF_FRESH, "Open: #5222.")
    handoff(handoffs / HANDOFF_STALE, "Open: #5222.")
    age(handoffs / HANDOFF_STALE, 60)
    items = report(env, *links(env[0], {}))
    assert items[HANDOFF_FRESH]["reasons"] == ["modified within 14 days"]
    assert items[HANDOFF_STALE]["reasons"] == ["link #5222 is unknown"]


@needs_posix_sh
def test_gh_lists_the_open_items_once_per_repository(env):
    tmp, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    for name, body in (
        (HANDOFF_STALE, "Open: #5222 and #6."),
        (HANDOFF_LINKED, "Shipped: #6. Also #8 and other/repo#7."),
        (HANDOFF_CLOSED, "Shipped: #6."),
        (HANDOFF_URL, "Other repo: other/repo#7."),
    ):
        handoff(handoffs / name, body)
        age(handoffs / name, 60)
    handoff(repo.parent / "home" / ".work" / "handoffs" / HOME_HANDOFF, "Bare #5222.")
    age(repo.parent / "home" / ".work", 60)
    gh_env = fake_gh(
        tmp,
        'case "$*" in\n  *repos/other/repo/*) echo 7 ;;\n  *) echo 5222; echo 8 ;;\nesac',
    )
    items = report(env, extra_env=gh_env)
    assert items[HANDOFF_STALE]["reasons"] == ["link #5222 is open"]
    assert items[HANDOFF_LINKED]["reasons"] == [
        "link #8 is open",
        "link other/repo#7 is open",
    ]
    assert items[HANDOFF_CLOSED]["reasons"] == []
    assert items[HANDOFF_URL]["reasons"] == ["link other/repo#7 is open"]
    assert items[HOME_HANDOFF]["reasons"] == ["link #5222 is unknown"]
    calls = (tmp / "gh-calls.log").read_text(encoding="utf-8").splitlines()
    assert len(calls) == 2
    assert sum("repos/other/repo/issues" in call for call in calls) == 1


@needs_posix_sh
def test_gh_failure_keeps_the_item(env):
    tmp, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    handoff(handoffs / HANDOFF_STALE, "Open: #5222.")
    age(handoffs / HANDOFF_STALE, 60)
    items = report(env, extra_env=fake_gh(tmp, "exit 1"))
    assert items[HANDOFF_STALE]["reasons"] == ["link #5222 is unknown"]


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
    assert "keep: concern state read back by its skill" in result.stdout
    assert "items," in result.stdout.splitlines()[-1]


def test_bad_link_state_exits_2(env):
    bad = env[0] / "bad.json"
    bad.write_text("[]", encoding="utf-8")
    assert run_cli(env, "--link-state", str(bad)).returncode == 2


STATE = {"#5222": "open", "#7": "closed", URL_REF: "open"}
STALE = {
    HANDOFF_STALE,
    SIDECAR_STALE,
    HANDOFF_CLOSED,
    HANDOFF_LATER,
    HOME_HANDOFF,
    "finished",
    "shipped",
}
RETRO = "20260101T100000Z-running-retro-x.md"
RETRO2 = "20260102T100000Z-running-retro-y.md"


def tree(*roots: Path) -> set[str]:
    return {p.as_posix() for root in roots for p in root.rglob("*")}


def clean(env, *args: str, **kwargs) -> subprocess.CompletedProcess[str]:
    return run_tidy(env, "clean", *links(env[0], STATE), *args, **kwargs)


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
    assert gone == STALE | {"workflow-checklist.md", "INDEX.md"}
    work = repo / ".work"
    for survivor in (
        work / "handoffs" / HANDOFF_FRESH,
        work / "handoffs" / HANDOFF_LINKED,
        work / "handoffs" / HANDOFF_URL,
        work / "handoffs" / HANDOFF_NAMED,
        work / "handoffs" / "notes.txt",
        work / "handoffs" / SIDECAR_ORPHAN,
        work / "unfinished",
        work / "widget",
        work / "parked",
        work / "unmarked",
        work / "tree" / "child" / "INDEX.md",
        work / "drain" / "status" / "5222.json",
        work / "reviews" / "feat-x" / "report.md",
        work / "exports" / "20260101T100000Z-talk.txt",
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
    stale = repo / ".work" / "finished"
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


def test_sidecar_leaves_with_its_handoff_and_an_orphan_stays(env):
    build(env)
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    dry = clean(env)
    assert f"would remove: {handoffs / SIDECAR_STALE}" in dry.stdout
    assert clean(env, "--apply").returncode == 0
    assert not (handoffs / HANDOFF_STALE).exists()
    assert not (handoffs / SIDECAR_STALE).exists()
    assert (handoffs / SIDECAR_ORPHAN).exists()


def test_root_equivalent_memory_dir_is_rejected_by_every_command(env):
    build(env)
    _, home, repo = env
    slice_dir(repo / "topic", "done")
    age(repo / "topic", 60)
    before = snapshot(repo, home)
    for command in ("report", "normalize", "clean"):
        for memory_dir in (".", str(repo)):
            args = ["--memory-dir", memory_dir]
            if command != "report":
                args.append("--apply")
            result = run_tidy(env, command, *args)
            assert result.returncode == 2, (command, memory_dir, result.stdout)
            assert "repository root" in result.stderr
    assert snapshot(repo, home) == before


def test_memory_root_without_the_self_ignore_guard_is_never_modified(env):
    build(env)
    _, home, repo = env
    (repo / ".work" / ".gitignore").unlink()
    result = clean(env, "--apply")
    assert result.returncode == 1
    assert "self-ignore guard" in result.stdout
    assert (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()
    assert (repo / ".work" / "shipped").exists()
    assert not (home / ".work" / "handoffs" / HOME_HANDOFF).exists()


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def test_clean_never_removes_content_git_tracks(env):
    build(env)
    _, _, repo = env
    work = repo / ".work"
    git(repo, "add", "-f", ".work/handoffs/" + HANDOFF_STALE, ".work/shipped/INDEX.md")
    result = clean(env, "--apply")
    assert result.returncode == 1
    assert f"refused: {work / 'handoffs' / HANDOFF_STALE} (git tracks content" in (
        result.stdout
    )
    assert f"refused: {work / 'shipped'} (git tracks content" in result.stdout
    assert (work / "handoffs" / HANDOFF_STALE).exists()
    assert (work / "handoffs" / SIDECAR_STALE).exists()
    assert (work / "shipped" / "INDEX.md").exists()
    assert not (work / "handoffs" / HANDOFF_CLOSED).exists()
    assert not (work / "finished").exists()


def test_relative_memory_dir_resolves_against_the_repository_top(env):
    _, _, repo = env
    write(repo / "notes" / "mem" / ".gitignore", "*\n")
    handoff(repo / "notes" / "mem" / "handoffs" / HANDOFF_STALE)
    age(repo / "notes" / "mem", 60)
    (repo / "sub").mkdir()
    payload = json.loads(
        run_cli(
            env, "--json", "--offline", "--memory-dir", "notes/mem", cwd=repo / "sub"
        ).stdout
    )
    memory = next(r for r in payload["roots"] if r["label"] == "memory")
    assert memory["path"] == (repo / "notes" / "mem").resolve().as_posix()
    assert [
        Path(i["path"]).name for i in payload["items"] if i["root"] == "memory"
    ] == [HANDOFF_STALE]


def misplace(env) -> None:
    _, _, repo = env
    work = repo / ".work"
    handoff(work / HANDOFF_STALE)
    write(work / SIDECAR_STALE, "{}")
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
    assert (work / "handoffs" / SIDECAR_STALE).exists()
    assert not (work / SIDECAR_STALE).exists()
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


def test_normalize_never_moves_content_git_tracks(env):
    misplace(env)
    _, _, repo = env
    work = repo / ".work"
    git(repo, "add", "-f", ".work/" + HANDOFF_STALE)
    result = normalize(env, "--apply")
    assert result.returncode == 1
    assert f"refused: {work / HANDOFF_STALE} (git tracks content" in result.stdout
    assert (work / HANDOFF_STALE).exists()
    assert (work / "running-retros" / RETRO).exists()


def test_normalize_apply_reports_an_oserror_and_keeps_going(env, monkeypatch, capsys):
    misplace(env)
    _, home, repo = env
    monkeypatch.syspath_prepend(str(SCRIPT.parent))
    import tidy_work

    real_rename = os.rename

    def rename(src, dst):
        if Path(src).name == HANDOFF_STALE:
            raise PermissionError("denied")
        real_rename(src, dst)

    monkeypatch.setattr(tidy_work.os, "rename", rename)
    monkeypatch.chdir(repo)
    monkeypatch.setenv("HOME", str(home))
    args = tidy_work.build_parser().parse_args(["normalize", "--apply"])
    assert args.func(args) == 1
    out = capsys.readouterr().out
    assert f"failed: {repo / '.work' / HANDOFF_STALE} (denied)" in out
    assert (repo / ".work" / HANDOFF_STALE).exists()
    assert (repo / ".work" / "running-retros" / RETRO).exists()
