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
HOME_REF = "melodic-software/claude-code-plugins#98"
SHIPPED = "Shipped in PR #7."

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
        (HANDOFF_STALE, SHIPPED, 60),
        (HANDOFF_FRESH, "", 0),
        (HANDOFF_LINKED, "Open follow-up: #5222.", 60),
        (HANDOFF_CLOSED, SHIPPED, 60),
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
    age(handoffs / HANDOFF_LATER, 5)
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

    write(work / "measure-4608" / "out.txt", "x")
    age(work / "measure-4608", 60)

    write(work / "drain" / "status" / "5222.json", "{}")
    age(work / "drain", 90)

    write(work / "reviews" / "feat-x" / "report.md", "r")
    age(work / "reviews", 60)
    write(work / "exports" / "20260101T100000Z-talk.txt", "conversation")
    age(work / "exports", 60)

    handoff(home / ".work" / "handoffs" / HOME_HANDOFF, f"Shipped in {HOME_REF}.")
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
    assert items[HANDOFF_LATER]["reasons"] == ["modified within 14 days"]
    assert items["notes.txt"]["kind"] == "unknown"
    assert items["notes.txt"]["keep"]
    assert items["unfinished"]["kind"] == "checklist"
    assert items["unfinished"]["reasons"] == [
        "workflow-checklist.md has an unfinished stage"
    ]
    assert items["finished"]["kind"] == "checklist"
    assert items["finished"]["keep"]
    assert not items["finished"]["in_flight"]
    assert items["measure-4608"]["kind"] == "scratch"
    assert items["feat-x"]["kind"] == "concern"
    assert items["feat-x"]["keep"]
    assert not items["feat-x"]["in_flight"]
    assert items["20260101T100000Z-talk.txt"]["kind"] == "concern"
    assert items["20260101T100000Z-talk.txt"]["keep"]


def test_slice_status_decides_whether_an_idle_slice_is_in_flight(env):
    build(env)
    items = report(env, "--offline")
    assert items["widget"]["reasons"] == ["INDEX.md status is active"]
    assert items["parked"]["reasons"] == ["INDEX.md status is parked"]
    assert items["unmarked"]["reasons"] == ["INDEX.md status is missing"]
    assert items["shipped"]["kind"] == "slice"
    assert not items["shipped"]["in_flight"]
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
def test_gh_lists_the_open_items_once_per_repository_and_looks_up_each_closed_one_once(
    env,
):
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
        'case "$*" in\n'
        "  *repos/other/repo/issues?state=open*) echo 7 ;;\n"
        "  *issues?state=open*) echo 5222; echo 8 ;;\n"
        "  *issues/6\\ *) echo closed ;;\n"
        "  *) exit 1 ;;\n"
        "esac",
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
    assert len(calls) == 3
    assert sum("repos/other/repo/issues?state=open" in call for call in calls) == 1
    assert sum("issues/6 " in call for call in calls) == 1


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
    assert "keep: names no issue or PR" in result.stdout
    assert "keep: concern state read back by its skill" in result.stdout
    assert "removable," in result.stdout.splitlines()[-1]


def test_a_recent_concern_item_is_never_described_as_recent(env):
    build(env)
    _, _, repo = env
    write(repo / ".work" / "reviews" / "fresh" / "report.md", "r")
    result = run_cli(env, "--offline")
    row = next(ln for ln in result.stdout.splitlines() if "reviews/fresh" in ln)
    assert "keep: concern state read back by its skill" in row
    assert "modified within" not in row


def test_bad_link_state_exits_2(env):
    bad = env[0] / "bad.json"
    bad.write_text("[]", encoding="utf-8")
    assert run_cli(env, "--link-state", str(bad)).returncode == 2


STATE = {
    "#5222": "open",
    "#7": "closed",
    "#4608": "merged",
    URL_REF: "open",
    HOME_REF: "merged",
}
STALE = {HANDOFF_STALE, SIDECAR_STALE, HANDOFF_CLOSED, HOME_HANDOFF, "measure-4608"}
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
        Path(line.split(": ", 1)[1].split(" [", 1)[0])
        for line in result.stdout.splitlines()
        if line.startswith("would remove: ")
    ]
    assert {p.name for p in listed} == STALE
    assert all(p.is_absolute() for p in listed)
    closed = repo / ".work" / "handoffs" / HANDOFF_CLOSED
    assert (
        f"would remove: {closed.as_posix()} [#7 closed]" in result.stdout.splitlines()
    )


def test_clean_apply_removes_only_stale_known_items(env):
    build(env)
    _, home, repo = env
    before = tree(repo, home)
    result = clean(env, "--apply")
    assert result.returncode == 0, result.stderr
    gone = {Path(p).name for p in before - tree(repo, home)}
    assert gone == STALE | {"out.txt"}
    work = repo / ".work"
    for survivor in (
        work / "handoffs" / HANDOFF_FRESH,
        work / "handoffs" / HANDOFF_LINKED,
        work / "handoffs" / HANDOFF_URL,
        work / "handoffs" / HANDOFF_NAMED,
        work / "handoffs" / HANDOFF_LATER,
        work / "handoffs" / "notes.txt",
        work / "handoffs" / SIDECAR_ORPHAN,
        work / "unfinished",
        work / "finished",
        work / "shipped",
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
    assert (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()
    assert (repo / ".work" / "measure-4608").exists()


def test_clean_refuses_symlink_leaving_the_root(env):
    build(env)
    tmp, _, repo = env
    outside = tmp / "outside"
    write(outside / "precious.txt", "keep")
    stale = repo / ".work" / "measure-4608"
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


def test_memory_root_outside_the_repository_needs_the_self_ignore_guard(env):
    tmp, home, repo = env
    outside = tmp / "outside"
    write(outside / "secret-notes.txt", "x")
    before = snapshot(repo, home, outside)
    for command in ("report", "normalize", "clean"):
        for memory_dir in (str(outside), "../outside"):
            args = ["--memory-dir", memory_dir]
            if command != "report":
                args.append("--apply")
            result = run_tidy(env, command, *args)
            assert result.returncode == 2, (command, memory_dir, result.stdout)
            assert "outside the repository" in result.stderr
            assert "self-ignore guard" in result.stderr
            assert "secret-notes" not in result.stdout
    assert snapshot(repo, home, outside) == before
    write(outside / ".gitignore", "*\n")
    payload = json.loads(
        run_cli(env, "--json", "--offline", "--memory-dir", str(outside)).stdout
    )
    assert [
        Path(i["path"]).name for i in payload["items"] if i["root"] == "memory"
    ] == ["secret-notes.txt"]


def test_absent_memory_root_outside_the_repository_is_an_empty_report(env):
    tmp, _, _ = env
    result = run_cli(env, "--json", "--offline", "--memory-dir", str(tmp / "absent"))
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["items"] == []


def test_memory_root_without_the_self_ignore_guard_is_never_modified(env):
    build(env)
    _, home, repo = env
    (repo / ".work" / ".gitignore").unlink()
    result = clean(env, "--apply")
    assert result.returncode == 1
    assert "self-ignore guard" in result.stdout
    assert (repo / ".work" / "handoffs" / HANDOFF_STALE).exists()
    assert (repo / ".work" / "measure-4608").exists()
    assert not (home / ".work" / "handoffs" / HOME_HANDOFF).exists()


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def test_clean_never_removes_content_git_tracks(env):
    build(env)
    _, _, repo = env
    work = repo / ".work"
    git(
        repo,
        "add",
        "-f",
        ".work/handoffs/" + HANDOFF_STALE,
        ".work/measure-4608/out.txt",
    )
    result = clean(env, "--apply")
    assert result.returncode == 1
    assert f"refused: {work / 'handoffs' / HANDOFF_STALE} (git tracks content" in (
        result.stdout
    )
    assert f"refused: {work / 'measure-4608'} (git tracks content" in result.stdout
    assert (work / "handoffs" / HANDOFF_STALE).exists()
    assert (work / "handoffs" / SIDECAR_STALE).exists()
    assert (work / "measure-4608" / "out.txt").exists()
    assert not (work / "handoffs" / HANDOFF_CLOSED).exists()


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
    handoff(work / HANDOFF_STALE, SHIPPED)
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


def test_report_classifies_every_file_normalize_would_move(env):
    misplace(env)
    items = report(env, "--offline")
    assert items[HANDOFF_STALE]["kind"] == "handoff"
    assert SIDECAR_STALE not in items
    assert items[RETRO]["kind"] == "running-retro"
    assert items[RETRO2]["kind"] == "running-retro"
    assert items["notes.txt"]["kind"] == "unknown"
    moved = [
        Path(line.removeprefix("would move: ").split(" -> ")[0]).name
        for line in normalize(env).stdout.splitlines()
        if line.startswith("would move: ")
    ]
    assert sorted(moved) == sorted([HANDOFF_STALE, SIDECAR_STALE, RETRO, RETRO2])
    assert all(items[name]["kind"] != "unknown" for name in moved if name in items)


def test_clean_removes_a_stale_misplaced_handoff_with_its_sidecar(env):
    misplace(env)
    _, _, repo = env
    work = repo / ".work"
    age(work / HANDOFF_STALE, 60)
    age(work / SIDECAR_STALE, 60)
    result = clean(env, "--apply")
    assert result.returncode == 0, result.stderr
    assert not (work / HANDOFF_STALE).exists()
    assert not (work / SIDECAR_STALE).exists()
    assert (work / "notes.txt").exists()


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


# Names as they sit in a real .work, each with the state of the number it carries.
SCRATCH = (
    "lint-5371.log",
    "measure-4608",
    "pr4120.md",
    "reverify-4186",
    "scratch-4586-d2cc1ea4d",
    "pr2026.md",  # a year-like number takes the prefix
)
NOT_ATTRIBUTED = (
    "native-surfaces-2-1-284",  # a version
    "triage-2026-09-28",  # a date
    "backup-2026.tar",  # a year, though #2026 is a closed PR here
    "notes-2025.md",  # a year, though #2025 is a merged PR here
    "compare-4608-4609",  # two numbers
    "t1",
    "12.txt",
    "verify-ci-r2",
    "audit-cursor-prs-full.json",
    "scratch-notes",
    "20260101T100000Z-notes-4608.txt",  # a writer's timestamp
)
SCRATCH_STATE = {
    "#5371": "closed",
    "#4608": "merged",
    "#4120": "open",
    "#4186": "closed-unmerged",
    "#4586": "closed",
    "#284": "closed",
    "#4609": "closed",
    "#2026": "closed",
    "#2025": "merged",
}


def scratch(env, days: float = 60) -> Path:
    work = env[2] / ".work"
    for name in (*SCRATCH, *NOT_ATTRIBUTED):
        if "." in name:
            write(work / name, "x")
        else:
            write(work / name / "out.txt", "x")
        age(work / name, days)
    return work


def test_scratch_is_attributed_by_the_number_in_its_name(env):
    scratch(env)
    items = report(env, *links(env[0], SCRATCH_STATE))
    assert {items[name]["kind"] for name in SCRATCH} == {"scratch"}
    assert items["lint-5371.log"]["links"] == {"#5371": "closed"}
    assert items["scratch-4586-d2cc1ea4d"]["links"] == {"#4586": "closed"}
    assert items["pr2026.md"]["links"] == {"#2026": "closed"}
    for name in (
        "lint-5371.log",
        "measure-4608",
        "scratch-4586-d2cc1ea4d",
        "pr2026.md",
    ):
        assert not items[name]["keep"], name
    assert items["pr4120.md"]["reasons"] == ["link #4120 is open"]
    assert items["reverify-4186"]["reasons"] == ["link #4186 is closed-unmerged"]
    for name in NOT_ATTRIBUTED:
        assert items[name]["kind"] == "unknown", name
        assert items[name]["keep"], name
        assert items[name]["links"] == {}, name


def test_a_year_in_a_name_is_attributed_only_with_a_prefix(monkeypatch):
    monkeypatch.syspath_prepend(str(SCRIPT.parent))
    import tidy_work

    for name, refs in (
        ("lint-5371.log", ["#5371"]),
        ("pr2026.md", ["#2026"]),
        ("issue1999-notes", ["#1999"]),
        ("backup-2026.tar", []),
        ("notes-2025.md", []),
        ("2024", []),
        ("report-2026-4608", []),
    ):
        assert tidy_work._name_refs(name) == refs, name


def test_scratch_shows_its_state_even_when_recent_or_offline(env):
    scratch(env, days=1)
    items = report(env, *links(env[0], SCRATCH_STATE))
    assert items["lint-5371.log"]["reasons"] == ["modified within 14 days"]
    assert items["lint-5371.log"]["links"] == {"#5371": "closed"}
    offline = report(env, "--offline")
    assert offline["lint-5371.log"]["links"] == {"#5371": "unknown"}
    assert offline["lint-5371.log"]["keep"]


def test_report_text_shows_the_attributed_state(env):
    scratch(env)
    result = run_cli(env, *links(env[0], SCRATCH_STATE))
    assert "stale [#5371 closed]" in result.stdout
    assert "keep: link #4120 is open [#4120 open]" in result.stdout
    assert "keep: unknown kind" in result.stdout


def test_clean_removes_scratch_only_when_its_number_is_closed_or_merged(env):
    work = scratch(env)
    dry = run_tidy(env, "clean", *links(env[0], SCRATCH_STATE))
    assert dry.returncode == 0, dry.stderr
    listed = {
        line for line in dry.stdout.splitlines() if line.startswith("would remove: ")
    }
    assert listed == {
        f"would remove: {(work / 'lint-5371.log').as_posix()} [#5371 closed]",
        f"would remove: {(work / 'measure-4608').as_posix()} [#4608 merged]",
        f"would remove: {(work / 'scratch-4586-d2cc1ea4d').as_posix()} [#4586 closed]",
        f"would remove: {(work / 'pr2026.md').as_posix()} [#2026 closed]",
    }
    assert all((work / name).exists() for name in (*SCRATCH, *NOT_ATTRIBUTED))
    applied = run_tidy(env, "clean", *links(env[0], SCRATCH_STATE), "--apply")
    assert applied.returncode == 0, applied.stderr
    survivors = {name for name in (*SCRATCH, *NOT_ATTRIBUTED) if (work / name).exists()}
    assert survivors == {"pr4120.md", "reverify-4186", *NOT_ATTRIBUTED}


def test_an_item_holding_a_git_repository_or_worktree_is_kept(env):
    work = scratch(env)
    (work / "measure-4608" / "clone" / ".git").mkdir(parents=True)
    write(work / "measure-4608" / "clone" / ".git" / "HEAD", "ref: refs/heads/main\n")
    write(work / "lint-5371.d" / "tree" / ".git", "gitdir: /elsewhere\n")
    age(work / "measure-4608", 60)
    age(work / "lint-5371.d", 60)
    items = report(env, *links(env[0], SCRATCH_STATE))
    for name in ("measure-4608", "lint-5371.d"):
        assert items[name]["reasons"] == ["holds a git repository or worktree"], name
    assert items["measure-4608"]["links"] == {"#4608": "merged"}
    result = run_tidy(env, "clean", *links(env[0], SCRATCH_STATE), "--apply")
    assert result.returncode == 0, result.stderr
    assert (work / "measure-4608" / "clone" / ".git" / "HEAD").exists()
    assert (work / "lint-5371.d" / "tree" / ".git").exists()
    assert not (work / "lint-5371.log").exists()


def test_clean_keeps_recent_scratch_however_closed_its_number(env):
    work = scratch(env, days=1)
    result = run_tidy(env, "clean", *links(env[0], SCRATCH_STATE), "--apply")
    assert result.returncode == 0, result.stderr
    assert all((work / name).exists() for name in (*SCRATCH, *NOT_ATTRIBUTED))


@needs_posix_sh
def test_a_number_that_is_no_issue_or_pr_keeps_its_scratch_item(env):
    tmp, home, repo = env
    work = repo / ".work"
    for name in ("lint-5371.log", "notes-123456.txt"):
        write(work / name, "x")
        age(work / name, 60)
    write(home / ".work" / "lint-5371.log", "x")
    age(home / ".work", 60)
    gh_env = fake_gh(
        tmp,
        'case "$*" in\n'
        "  *issues?state=open*) echo 7 ;;\n"
        "  *issues/5371\\ *) echo closed ;;\n"
        "  *) exit 1 ;;\n"
        "esac",
    )
    payload = json.loads(run_cli(env, "--json", extra_env=gh_env).stdout)
    by_root = {
        (i["root"], Path(i["path"]).name): i
        for i in payload["items"]
        if i["kind"] == "scratch"
    }
    assert by_root["memory", "lint-5371.log"]["links"] == {"#5371": "closed"}
    assert not by_root["memory", "lint-5371.log"]["keep"]
    assert by_root["memory", "notes-123456.txt"]["links"] == {"#123456": "unknown"}
    assert by_root["memory", "notes-123456.txt"]["reasons"] == [
        "link #123456 is unknown"
    ]
    assert by_root["home", "lint-5371.log"]["links"] == {"#5371": "unknown"}
    assert by_root["home", "lint-5371.log"]["keep"]


def test_a_stale_handoff_keeps_neither_the_handoff_nor_the_scratch_it_names(env):
    _, _, repo = env
    work = repo / ".work"
    first, second, third = (
        f"2025010{n}T100000Z-handoff-{name}.md"
        for n, name in ((1, "a"), (2, "b"), (3, "c"))
    )
    handoff(work / "handoffs" / first, SHIPPED)
    age(work / "handoffs" / first, 400)
    handoff(
        work / "handoffs" / second,
        f"{SHIPPED} Continues {first}. Scratch: measure-4608/",
    )
    age(work / "handoffs" / second, 399)
    write(work / "measure-4608" / "out.txt", "x")
    age(work / "measure-4608", 400)
    state = links(env[0], STATE)

    items = report(env, *state)
    assert not any(items[name]["keep"] for name in (first, second, "measure-4608"))
    dry = run_tidy(env, "clean", *state)
    listed = {
        Path(line.split(": ", 1)[1].split(" [", 1)[0]).name
        for line in dry.stdout.splitlines()
        if line.startswith("would remove: ")
    }
    assert listed == {first, second, "measure-4608"}

    handoff(work / "handoffs" / third, f"Continues {second}.")
    items = report(env, *state)
    assert items[third]["reasons"] == ["modified within 14 days"]
    assert items[second]["reasons"] == ["named by a later handoff"]
    assert items[first]["reasons"] == ["named by a later handoff"]
    assert items["measure-4608"]["reasons"] == ["named by a later handoff"]


def test_clean_never_removes_what_names_no_issue_or_pr(env):
    _, home, repo = env
    work = repo / ".work"
    handoff(work / "handoffs" / HANDOFF_STALE)
    write(work / "running-retros" / RETRO, "---\ntype: running-retro\n---\nno link\n")
    slice_dir(work / "shipped", "done")
    write(work / "finished" / "workflow-checklist.md", CHECKLIST_DONE)
    for path in (
        work / "handoffs",
        work / "running-retros",
        work / "shipped",
        work / "finished",
    ):
        age(path, 60)
    items = report(env, *links(env[0], STATE))
    for name in (HANDOFF_STALE, RETRO, "shipped", "finished"):
        assert items[name]["keep"], name
        assert not items[name]["in_flight"], name
    assert "keep: names no issue or PR" in run_cli(env, "--offline").stdout
    before = tree(repo, home)
    dry = clean(env)
    assert dry.returncode == 0, dry.stderr
    assert "would remove" not in dry.stdout
    assert clean(env, "--apply").returncode == 0
    assert tree(repo, home) == before


def test_a_kept_handoff_that_names_no_issue_keeps_what_it_names(env):
    _, _, repo = env
    work = repo / ".work"
    handoff(work / "handoffs" / HANDOFF_STALE, "Scratch: measure-4608/")
    age(work / "handoffs" / HANDOFF_STALE, 60)
    write(work / "measure-4608" / "out.txt", "x")
    age(work / "measure-4608", 90)
    items = report(env, *links(env[0], STATE))
    assert items[HANDOFF_STALE]["keep"]
    assert items["measure-4608"]["reasons"] == ["named by a later handoff"]
    assert "would remove" not in clean(env).stdout
