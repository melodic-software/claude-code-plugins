"""Contract tests for save_point.py (new / validate / emit).

Runs the script as a subprocess to test the CLI interface, not internals,
following the retro skill's test_parse_transcript.py precedent.

Fixtures live under ``fixtures/<case>/handoffs/`` with neutral ``/work/...``
roots so nothing tracked carries a machine path. ``validate`` compares the
``Read @`` directive against the file's own absolute path, so every fixture
chain is materialized under ``tmp_path`` and the neutral root rewritten to the
materialized directory before the script sees it; tracked fixtures are never
validated in place.
"""

from __future__ import annotations

import functools
import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

# The origin-identity tests build a throwaway git repository. Under an inherited
# absolute GIT_DIR (or GIT_WORK_TREE / GIT_CONFIG) `git init` and `git config`
# would write into the caller's repository instead of the fixture, so clear the
# ambient git environment once, before any fixture is built
# (scripts/check-fixture-git-isolation.sh).
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

SCRIPT = Path(__file__).resolve().parents[1] / "save_point.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"

NEUTRAL_HANDOFFS = "/work/repo/.work/handoffs"
NEUTRAL_PROJECTS = "/work/projects"

# Every fixture basename, so a fixture edit selects this suite under the
# affected-tests reference rule (fixture .md files otherwise fall in the *.md
# no-suite class, and no *.jsonl no-suite class exists).
FIXTURE_MANIFEST = (
    ".markdownlint-cli2.jsonc",
    "projects/-work-repo/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jsonl",
    "projects/-work-repo/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jsonl",
    "projects/-work-repo/cccccccc-cccc-4ccc-8ccc-cccccccccccc.jsonl",
    "legacy-14/handoffs/20260901T100000Z-handoff-legacy.md",
    "legacy-7/handoffs/20260901T100000Z-handoff-legacy7.md",
    "good-chain/handoffs/20260901T100000Z-handoff-widget.md",
    "good-chain/handoffs/20260902T100000Z-handoff-widget.md",
    "good-chain/handoffs/20260903T100000Z-handoff-widget.md",
    "prefixed-pointer/handoffs/20260902T100000Z-handoff-widget.md",
    "non-uuid/handoffs/20260901T100000Z-handoff-widget.md",
    "ascii-rails/handoffs/20260901T100000Z-handoff-widget.md",
    "fill-leftover/handoffs/20260901T100000Z-handoff-widget.md",
    "shape-3/handoffs/20260901T100000Z-handoff-widget.md",
    "malformed-predecessor/handoffs/20260901T100000Z-handoff-widget.md",
    "malformed-predecessor/handoffs/20260902T100000Z-handoff-widget.md",
    "dropped-entry/handoffs/20260901T100000Z-handoff-widget.md",
    "dropped-entry/handoffs/20260902T100000Z-handoff-widget.md",
    "moved-file/handoffs/20260901T100000Z-handoff-widget.md",
    "then-not-last/handoffs/20260901T100000Z-handoff-widget.md",
    "six-next-lines/handoffs/20260901T100000Z-handoff-widget.md",
    "untagged-entry/handoffs/20260901T100000Z-handoff-widget.md",
    "shape1-predecessor/handoffs/20260901T100000Z-handoff-legacy.md",
    "shape1-predecessor/handoffs/20260902T100000Z-handoff-legacy.md",
    "unresolved-transcript/handoffs/20260901T100000Z-handoff-widget.md",
    "missing-transcript/handoffs/20260901T100000Z-handoff-widget.md",
    "heading-order/handoffs/20260901T100000Z-handoff-widget.md",
)

HOP1 = "20260901T100000Z-handoff-widget.md"
HOP2 = "20260902T100000Z-handoff-widget.md"
HOP3 = "20260903T100000Z-handoff-widget.md"
LEGACY = "20260901T100000Z-handoff-legacy.md"
LEGACY7 = "20260901T100000Z-handoff-legacy7.md"
SID_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
SID_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
RAIL_RE = re.compile(r"^─{10,}$")
FILL_RE = re.compile(r"<!-- FILL: ([a-z-]+) — .*? -->")


def rail_lines(text: str) -> int:
    """Lines consisting solely of ten or more U+2500 characters."""
    return sum(1 for line in text.split("\n") if RAIL_RE.match(line.strip()))


def test_fixture_manifest_is_complete():
    on_disk = sorted(
        p.relative_to(FIXTURES).as_posix()
        for p in FIXTURES.rglob("*")
        if p.is_file()
    )
    assert on_disk == sorted(FIXTURE_MANIFEST)


def _base_env() -> dict[str, str]:
    """The launching session's env minus every CLAUDE_* variable, so a test
    never inherits this session's id, effort, or plugin-data dir."""
    return {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_")}


@functools.lru_cache(maxsize=1)
def _save_point_module():
    """Import the script as a module. The suite tests the CLI; this is for the
    one assertion the CLI cannot express, since whether the parser reads an
    entry as superseded is internal state rather than output."""
    spec = importlib.util.spec_from_file_location("save_point_under_test", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # Registered before execution: `dataclasses` resolves a field annotation
    # through `sys.modules[cls.__module__]`, which is absent otherwise.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        env=env if env is not None else _base_env(),
        timeout=30,
    )


def out(result: subprocess.CompletedProcess[bytes]) -> str:
    return result.stdout.decode("utf-8")


def err(result: subprocess.CompletedProcess[bytes]) -> str:
    return result.stderr.decode("utf-8")


def real_posix(path: Path) -> str:
    return Path(os.path.realpath(path)).as_posix()


def materialize(tmp_path: Path, case: str) -> Path:
    """Copy one fixture case (plus the shared projects root) under tmp_path and
    rewrite the neutral roots to the materialized directory. Returns the
    materialized handoffs directory."""
    root = real_posix(tmp_path)
    dst = tmp_path / case
    shutil.copytree(FIXTURES / case, dst)
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    for md in dst.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        text = text.replace(NEUTRAL_HANDOFFS, f"{root}/{case}/handoffs")
        text = text.replace(NEUTRAL_PROJECTS, f"{root}/projects")
        md.write_text(text, encoding="utf-8", newline="\n")
    return dst / "handoffs"


def projects_root(tmp_path: Path) -> str:
    return (tmp_path / "projects").as_posix()


# --- validate: shape detection -------------------------------------------------


def test_validate_shape1_legacy_warns_and_exits_zero(tmp_path):
    handoffs = materialize(tmp_path, "legacy-14")
    result = run("validate", str(handoffs / LEGACY))
    assert result.returncode == 0, err(result)
    assert "WARN" in out(result)
    assert "shape 1" in out(result)


def test_validate_shape1_seven_section_legacy_warns_and_exits_zero(tmp_path):
    handoffs = materialize(tmp_path, "legacy-7")
    result = run("validate", str(handoffs / LEGACY7))
    assert result.returncode == 0, err(result)
    assert "WARN" in out(result)


def test_validate_shape3_hard_fails_with_exit_3(tmp_path):
    handoffs = materialize(tmp_path, "shape-3")
    result = run("validate", str(handoffs / HOP1))
    assert result.returncode == 3, out(result)
    assert "read it, do not rewrite it" in out(result)
    assert "validate: UNSUPPORTED-SHAPE" in out(result)


@pytest.mark.parametrize(
    "goal_body",
    [
        "**Goal (verbatim, 2026-09-01):**\n\n> None.\n",
        "**Goal (verbatim, 2026-09-01):**\n\nNone.\n",
        "**Goal (verbatim, 2026-09-01):**\n",
    ],
)
def test_validate_rejects_empty_or_none_goal(tmp_path, goal_body):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    original = "**Goal (verbatim, 2026-09-01):**\n\n> Make the widget importer idempotent so a re-run never duplicates rows.\n"
    assert original in text
    target.write_text(text.replace(original, goal_body), encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result)
    assert "Original goal: the goal quote is empty or 'None.'" in out(result)


def test_validate_not_a_handoff_is_usage_error(tmp_path):
    plain = tmp_path / "notes.md"
    plain.write_text("# Notes\n\nnothing here\n", encoding="utf-8")
    result = run("validate", str(plain))
    assert result.returncode == 2
    assert "not a handoff file" in err(result)


def test_validate_missing_file_is_usage_error(tmp_path):
    result = run("validate", str(tmp_path / "absent.md"))
    assert result.returncode == 2


# --- validate: shape 2 good chain ----------------------------------------------


@pytest.mark.parametrize("name", [HOP1, HOP2, HOP3])
def test_validate_shape2_good_chain_passes_clean(tmp_path, name):
    handoffs = materialize(tmp_path, "good-chain")
    result = run("validate", str(handoffs / name), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "FAIL" not in out(result)
    assert "WARN" not in out(result)
    assert out(result).strip().endswith(f"validate: PASS {real_posix(handoffs)}/{name}")


def test_validate_tolerates_crlf_line_endings(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)


def test_validate_shape1_predecessor_chain_passes(tmp_path):
    handoffs = materialize(tmp_path, "shape1-predecessor")
    result = run("validate", str(handoffs / "20260902T100000Z-handoff-legacy.md"), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "FAIL" not in out(result)


def test_validate_malformed_predecessor_downgrades_to_warn(tmp_path):
    handoffs = materialize(tmp_path, "malformed-predecessor")
    result = run("validate", str(handoffs / HOP2), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "WARN: predecessor" in out(result)
    assert "failed validation" in out(result)
    assert "FAIL" not in out(result)


def test_validate_unresolved_transcript_warns_by_default_fails_strict(tmp_path):
    handoffs = materialize(tmp_path, "unresolved-transcript")
    lenient = run("validate", str(handoffs / HOP1))
    assert lenient.returncode == 0, out(lenient)
    assert "WARN: transcript: unresolved" in out(lenient)
    assert "present now" not in out(lenient)
    strict = run("validate", str(handoffs / HOP1), "--strict-transcript")
    assert strict.returncode == 1, out(strict)
    assert "FAIL: transcript: unresolved" in out(strict)
    located = run("validate", str(handoffs / HOP1), "--projects-root", projects_root(tmp_path))
    assert located.returncode == 0, out(located)
    expected = real_posix(tmp_path / "projects" / "-work-repo" / (SID_A + ".jsonl"))
    assert f"present now at {expected}" in out(located)


def test_validate_chain_longer_than_predecessor_plus_self_fails(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP2
    text = target.read_text(encoding="utf-8")
    text = text.replace(f"chain:\n  - {HOP1}\n", f"chain:\n  - 20260831T100000Z-handoff-widget.md\n  - {HOP1}\n")
    target.write_text(text, encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result)
    assert "predecessor's chain plus this file" in out(result)


def test_validate_missing_predecessor_beside_file_fails(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    (handoffs / HOP1).unlink()
    result = run("validate", str(handoffs / HOP2), "--strict-transcript")
    assert result.returncode == 1, out(result)
    assert "not found beside this file" in out(result)


# --- validate: shape 2 failures -----------------------------------------------------


@pytest.mark.parametrize(
    ("case", "name", "needle"),
    [
        ("prefixed-pointer", HOP2, "bare filename"),
        ("non-uuid", HOP1, "not a UUID"),
        ("ascii-rails", HOP1, "U+2500"),
        ("fill-leftover", HOP1, "<!-- FILL"),
        ("dropped-entry", HOP2, "dropped"),
        ("then-not-last", HOP1, "'Then: /<skill>' must be the last line"),
        ("six-next-lines", HOP1, "6 headline lines (max 5)"),
        ("untagged-entry", HOP1, "provenance tag"),
        ("missing-transcript", HOP1, "stated path does not exist"),
        ("heading-order", HOP1, "headings:"),
    ],
)
def test_validate_shape2_failures_exit_one(tmp_path, case, name, needle):
    handoffs = materialize(tmp_path, case)
    result = run("validate", str(handoffs / name), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert needle in out(result), out(result)
    assert "FAIL" in out(result)


# --- validate: relocation is a warning, misidentification is a failure -------------


def test_validate_relocated_file_warns_and_exits_zero(tmp_path):
    """The moved-file fixture stores a 'Read @' path under another root with
    this file's own basename: a relocated save-point, not a wrong one."""
    handoffs = materialize(tmp_path, "moved-file")
    result = run("validate", str(handoffs / HOP1), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "FAIL" not in out(result)
    assert "WARN" in out(result)
    assert "/work/elsewhere/removed-worktree/.work/handoffs/" + HOP1 in out(result)
    assert real_posix(handoffs / HOP1) in out(result)


def test_validate_survives_a_copy_out_of_its_handoffs_dir(tmp_path):
    """The reported case: a chain copied out of a worktree before the worktree
    is removed still validates where it landed."""
    handoffs = materialize(tmp_path, "good-chain")
    in_place = run("validate", str(handoffs / HOP1), "--strict-transcript")
    assert in_place.returncode == 0, out(in_place)
    assert "WARN" not in out(in_place)
    elsewhere = tmp_path / "relocated"
    elsewhere.mkdir()
    copied = elsewhere / HOP1
    shutil.copy(handoffs / HOP1, copied)
    result = run("validate", str(copied), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "WARN" in out(result) and "FAIL" not in out(result)
    assert real_posix(handoffs / HOP1) in out(result)


def test_validate_rejects_a_read_at_naming_a_different_basename(tmp_path):
    """Relaxing relocation must not relax misidentification: a stored path
    naming some other save-point is still a hard failure."""
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    stored = f"Read @{real_posix(target)},"
    assert stored in text
    target.write_text(
        text.replace(stored, "Read @/work/elsewhere/20260101T000000Z-handoff-other.md,"),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "does not name this file" in out(result)
    assert "FAIL" in out(result)


def test_validate_secret_shape_is_warn_only(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    text = text.replace(
        "None. Nothing waits on a person or an access grant.",
        "None. The token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123 was rotated.",
    )
    target.write_text(text, encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 0, out(result)
    assert "WARN" in out(result) and "secret-shaped" in out(result) and "GitHub token" in out(result)


@pytest.mark.parametrize("marker", ["- ", "* ", "+ ", "1. ", "2) "])
def test_validate_refuses_a_bulleted_next_headline(tmp_path, marker):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    headline = "Add the re-run test to tests/test_importer.py"
    assert f"\n{headline}\n" in text
    target.write_text(text.replace(f"\n{headline}\n", f"\n{marker}{headline}\n"), encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "headline must not be a bullet" in out(result), out(result)
    assert headline in out(result), out(result)


def _blank_section(path: Path, title: str) -> None:
    """Leave the heading in place with a body of blank lines only."""
    lines = path.read_text(encoding="utf-8").split("\n")
    start = lines.index(f"## {title}")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    path.write_text("\n".join(lines[: start + 1] + ["", ""] + lines[end:]), encoding="utf-8", newline="\n")


@pytest.mark.parametrize(
    "title",
    [
        "Completion criteria",
        "Environment to re-establish",
        "Remaining actions, in order",
        "Findings that cost effort to discover",
    ],
)
def test_validate_refuses_an_empty_required_section(tmp_path, title):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    _blank_section(target, title)
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert f"{title}: empty; write 'None.' plus a reason" in out(result), out(result)


@pytest.mark.parametrize("value", ["0", "-3", "-1"])
def test_validate_refuses_a_shape_below_one(tmp_path, value):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    assert "handoff_shape: 2\n" in text
    target.write_text(text.replace("handoff_shape: 2\n", f"handoff_shape: {value}\n", 1), encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert f"handoff_shape {value} is not a shape" in out(result), out(result)
    # -1 was the old unparsable sentinel, so it used to be mislabelled.
    assert "not an integer" not in out(result), out(result)


def test_validate_reports_a_non_integer_shape_as_not_an_integer(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    target.write_text(text.replace("handoff_shape: 2\n", "handoff_shape: two\n", 1), encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "handoff_shape 'two' is not an integer" in out(result), out(result)


# --- emit ---------------------------------------------------------------------------


def _section_body(path: Path, title: str) -> str:
    lines = path.read_text(encoding="utf-8").split("\n")
    start = lines.index(f"## {title}") + 1
    body = lines[start:]
    while body and not body[0].strip():
        body = body[1:]
    while body and not body[-1].strip():
        body = body[:-1]
    return "\n".join(body) + "\n"


def test_emit_prints_resume_prompt_section_verbatim(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    result = run("emit", str(handoffs / HOP2))
    assert result.returncode == 0, err(result)
    assert result.stdout.decode("utf-8") == _section_body(handoffs / HOP2, "Resume prompt")
    assert b"\r" not in result.stdout
    assert rail_lines(out(result)) == 2
    assert result.stdout.decode("utf-8").startswith("`/clear`, then copy everything between the dashed lines:")


def test_emit_shape1_legacy_says_so_and_exits_one(tmp_path):
    handoffs = materialize(tmp_path, "legacy-14")
    result = run("emit", str(handoffs / LEGACY))
    assert result.returncode == 1
    assert result.stdout == b""
    assert "shape 1" in err(result)


def test_emit_refuses_unfinished_skeleton(tmp_path):
    handoffs = materialize(tmp_path, "fill-leftover")
    result = run("emit", str(handoffs / HOP1))
    assert result.returncode == 1
    assert result.stdout == b""
    assert "unfinished skeleton" in err(result)


def test_emit_substitutes_real_path_on_mismatch_without_rewriting(tmp_path):
    handoffs = materialize(tmp_path, "moved-file")
    target = handoffs / HOP1
    before = target.read_bytes()
    result = run("emit", str(target))
    assert result.returncode == 0, err(result)
    assert "WARN" in err(result) and "substituting" in err(result)
    assert f"Read @{real_posix(target)}, confirm" in out(result)
    assert "/work/elsewhere/" not in out(result)
    assert target.read_bytes() == before


def test_emit_and_validate_survive_cp1252_pipe(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    env = _base_env()
    env["PYTHONIOENCODING"] = "cp1252"
    env["PYTHONUTF8"] = "0"
    emitted = run("emit", str(handoffs / HOP1), env=env)
    assert emitted.returncode == 0, err(emitted)
    assert rail_lines(out(emitted)) == 2
    validated = run("validate", str(handoffs / HOP1), "--strict-transcript", env=env)
    assert validated.returncode == 0, out(validated) + err(validated)


# --- new ------------------------------------------------------------------------------


def make_repo(tmp_path: Path, remote: str | None = "ssh://git@github.com/example/repo") -> Path:
    repo = tmp_path / "repo"
    repo.mkdir(parents=True)
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "commit.gpgsign", "false"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "core.autocrlf", "false"], check=True)
    if remote:
        subprocess.run(["git", "-C", str(repo), "remote", "add", "origin", remote], check=True)
    (repo / ".work").mkdir()
    (repo / ".work" / ".gitignore").write_text("*\n", encoding="utf-8")
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    return repo


def new_args(repo: Path, tmp_path: Path, *extra: str, sid: str = SID_A, now: str = "2026-09-01T10:00:00Z") -> list[str]:
    return [
        "new",
        "--topic",
        "widget",
        "--memory-dir",
        str(repo / ".work"),
        "--session-id",
        sid,
        "--projects-root",
        projects_root(tmp_path),
        "--now",
        now,
        *extra,
    ]


def fill(text: str) -> str:
    """Fill every reasoning slot the way a well-behaved model would: optional
    slots deleted, cumulative slots given one tagged entry, the rest prose."""
    filled: list[str] = []
    for line in text.split("\n"):
        whole = FILL_RE.fullmatch(line.strip())
        if whole and (whole.group(1) in ("goal-rearm", "below-rail") or whole.group(1).endswith("-new")):
            continue

        def repl(m: re.Match[str]) -> str:
            name = m.group(1)
            return {
                "goal": "> Do the thing.",
                "amended": "None.",
                "opening-ask": "Do the thing please.",
                "next": "Do the next thing",
                "did": "did the thing",
                "left": "the rest",
                "constraints": "- [h1] The thing must stay green.",
                "side-effects": "- [h1] The thing was applied once.",
                "decisions": "- [h1] The thing over the other thing.",
                "abandoned": "- [h1] The other thing, which broke.",
                "findings": "- [h1] The thing takes a minute.",
            }.get(name, f"Filled {name}.")

        filled.append(FILL_RE.sub(repl, line))
    return "\n".join(filled)


def test_new_hop1_writes_skeleton_and_prints_path(tmp_path):
    repo = make_repo(tmp_path, remote="https://x-access-token:ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123@github.com/example/repo.git")
    result = run(*new_args(repo, tmp_path, "--no-previous"))
    assert result.returncode == 0, err(result)
    target = repo / ".work" / "handoffs" / HOP1
    assert target.is_file()
    assert out(result).strip() == real_posix(target)
    text = target.read_text(encoding="utf-8")
    assert "\r" not in text
    assert "handoff_shape: 2" in text
    assert f"session_id: {SID_A}" in text
    assert f"transcript: {real_posix(tmp_path / 'projects' / '-work-repo' / (SID_A + '.jsonl'))}" in text
    assert "previous_handoff" not in text
    assert f"chain:\n  - {HOP1}\n---" in text
    assert f"Read @{real_posix(target)}, confirm its Original goal" in text
    assert "invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand." in text
    assert f"Handoff origin: https://github.com/example/repo.git .work/handoffs/{HOP1}" in text
    assert "ghp_" not in text
    assert "None (first hop)." in text
    assert f"claude --resume {SID_A}" in text
    assert rail_lines(text) == 2
    assert "<!-- FILL: goal" in text and "<!-- FILL: next" in text
    assert "Opening ask:\n<!-- FILL: opening-ask" in text
    unfinished = run("validate", str(target))
    assert unfinished.returncode == 1 and "<!-- FILL" in out(unfinished)
    refused = run("emit", str(target))
    assert refused.returncode == 1


def test_new_hop1_filled_skeleton_validates_clean(tmp_path):
    repo = make_repo(tmp_path)
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    target = repo / ".work" / "handoffs" / HOP1
    target.write_text(fill(target.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 0, out(result) + err(result)
    assert "FAIL" not in out(result) and "WARN" not in out(result)
    emitted = run("emit", str(target))
    assert emitted.returncode == 0
    assert emitted.stdout.decode("utf-8") == _section_body(target, "Resume prompt")


def test_new_hop2_from_shape2_carries_chain_rows_and_tags(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    hop1.write_text(fill(hop1.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    result = run(*new_args(repo, tmp_path, "--previous", str(hop1), sid=SID_B, now="2026-09-02T10:00:00Z"))
    assert result.returncode == 0, err(result)
    hop2 = handoffs / HOP2
    text = hop2.read_text(encoding="utf-8")
    assert f"previous_handoff: {HOP1}" in text
    assert f"chain:\n  - {HOP1}\n  - {HOP2}\n---" in text
    assert f"Opening ask: see {HOP1} § Original goal\n" in text
    assert "> Do the thing." in text
    assert "- [h1] The thing must stay green." in text
    assert "<!-- FILL: constraints-new" in text and "[h2]" in text
    assert f"| 2026-09-01T10:00:00Z | {SID_A} | " in text and f"| did: did the thing · left: the rest | {HOP1} |" in text
    assert "None (first hop)." not in text
    hop2.write_text(fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    assert "WARN" not in out(validated)


def test_new_hop2_from_shape1_legacy_tags_and_points(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    legacy = handoffs / LEGACY
    shutil.copy(FIXTURES / "legacy-14" / "handoffs" / LEGACY, legacy)
    result = run(*new_args(repo, tmp_path, "--previous", str(legacy), sid=SID_B, now="2026-09-02T10:00:00Z"))
    assert result.returncode == 0, err(result)
    hop2 = handoffs / HOP2
    text = hop2.read_text(encoding="utf-8")
    assert f"chain:\n  - {LEGACY}\n  - {HOP2}\n---" in text
    assert f"Opening ask: see {LEGACY} § Original goal (shape-1 root, no verbatim ask recorded)" in text
    assert "> Make the widget importer idempotent so a re-run never duplicates rows." in text
    assert "- [h1] The public `WidgetReader` signature is frozen; two downstream repos compile against it." in text
    assert "- [h1] Migration `20260901_add_widget_index` is APPLIED to the local database; do not re-run." in text
    assert "UNVERIFIED (shape-1 predecessor; brief: Purpose: finish the importer dedup key." in text
    assert "| 11111111-1111-4111-8111-111111111111 | unresolved (session 11111111-1111-4111-8111-111111111111" in text
    hop2.write_text(fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_new_hop2_from_seven_section_legacy_maps_absent_sections(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    legacy = handoffs / LEGACY7
    shutil.copy(FIXTURES / "legacy-7" / "handoffs" / LEGACY7, legacy)
    result = run(*new_args(repo, tmp_path, "--previous", str(legacy), sid=SID_B, now="2026-09-02T10:00:00Z"))
    assert result.returncode == 0, err(result)
    text = (handoffs / HOP2).read_text(encoding="utf-8")
    assert "<!-- FILL: goal — RECONSTRUCTED from the transcript" in text
    assert "None. (shape-1 predecessor had no Constraints that must hold)" in text
    assert "None. (shape-1 predecessor had no Findings that cost effort to discover)" in text
    assert "UNVERIFIED (shape-1 predecessor; brief: no Resumption brief section)" in text
    unfinished = run("validate", str(handoffs / HOP2))
    assert unfinished.returncode == 1
    hop2 = handoffs / HOP2
    hop2.write_text(fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_new_hop2_from_malformed_shape2_marks_carried_rows_unverified(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    bad = handoffs / HOP1
    shutil.copy(FIXTURES / "malformed-predecessor" / "handoffs" / HOP1, bad)
    result = run(*new_args(repo, tmp_path, "--previous", str(bad), sid=SID_B, now="2026-09-02T10:00:00Z"))
    assert result.returncode == 0, err(result)
    text = (handoffs / HOP2).read_text(encoding="utf-8")
    assert "- [h1] UNVERIFIED (predecessor failed validation): The public `WidgetReader` signature is frozen." in text
    assert bad.read_bytes() == (FIXTURES / "malformed-predecessor" / "handoffs" / HOP1).read_bytes()


def test_new_hop2_from_relocated_predecessor_carries_rows_verified(tmp_path):
    """A predecessor whose only defect is relocation must not taint the
    entries carried into its successor."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    text = fill(hop1.read_text(encoding="utf-8"))
    stored = f"Read @{real_posix(hop1)},"
    assert stored in text
    # Same basename under a root that no longer exists: what copying a chain
    # out of a removed worktree leaves behind.
    text = text.replace(stored, f"Read @/work/elsewhere/removed-worktree/.work/handoffs/{HOP1},")
    hop1.write_text(text, encoding="utf-8", newline="\n")
    relocated = run("validate", str(hop1), "--projects-root", projects_root(tmp_path))
    assert relocated.returncode == 0, out(relocated) + err(relocated)
    assert "WARN" in out(relocated)
    result = run(*new_args(repo, tmp_path, "--previous", str(hop1), sid=SID_B, now="2026-09-02T10:00:00Z"))
    assert result.returncode == 0, err(result)
    carried = (handoffs / HOP2).read_text(encoding="utf-8")
    assert "UNVERIFIED" not in carried, carried
    assert "- [h1] The thing must stay green." in carried


def test_new_origin_falls_back_to_directory_name(tmp_path):
    scp = make_repo(tmp_path / "scp", remote="git@github.com:example/repo.git")
    result = run(*new_args(scp, tmp_path / "scp", "--no-previous"))
    assert result.returncode == 0, err(result)
    text = (scp / ".work" / "handoffs" / HOP1).read_text(encoding="utf-8")
    assert f"Handoff origin: repo .work/handoffs/{HOP1}" in text
    bare = make_repo(tmp_path / "bare", remote=None)
    result = run(*new_args(bare, tmp_path / "bare", "--no-previous"))
    assert result.returncode == 0, err(result)
    text = (bare / ".work" / "handoffs" / HOP1).read_text(encoding="utf-8")
    assert f"Handoff origin: repo .work/handoffs/{HOP1}" in text


def test_new_unresolved_transcript_is_recorded_honestly(tmp_path):
    repo = make_repo(tmp_path)
    sid = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    result = run(*new_args(repo, tmp_path, "--no-previous", sid=sid))
    assert result.returncode == 0, err(result)
    text = (repo / ".work" / "handoffs" / HOP1).read_text(encoding="utf-8")
    assert f"transcript: unresolved (session {sid}, projects-root {projects_root(tmp_path)})" in text


def test_new_refuses_without_session_uuid(tmp_path):
    repo = make_repo(tmp_path)
    env = _base_env()
    args = new_args(repo, tmp_path, "--no-previous")
    del args[args.index("--session-id") : args.index("--session-id") + 2]
    unset = run(*args, env=env)
    assert unset.returncode == 1 and "prompt-only" in err(unset)
    bridge_only = dict(env, CLAUDE_CODE_BRIDGE_SESSION_ID=SID_A)
    ignored = run(*args, env=bridge_only)
    assert ignored.returncode == 1 and "CLAUDE_CODE_SESSION_ID unset" in err(ignored)
    bridge_shaped = run(*new_args(repo, tmp_path, "--no-previous", sid="cse_0123456789abcdef"))
    assert bridge_shaped.returncode == 1 and "not a UUID" in err(bridge_shaped)
    assert not (repo / ".work" / "handoffs").exists()


def test_new_reads_session_id_from_env(tmp_path):
    repo = make_repo(tmp_path)
    env = dict(_base_env(), CLAUDE_CODE_SESSION_ID=SID_B.upper())
    args = new_args(repo, tmp_path, "--no-previous")
    del args[args.index("--session-id") : args.index("--session-id") + 2]
    result = run(*args, env=env)
    assert result.returncode == 0, err(result)
    assert f"session_id: {SID_B}" in (repo / ".work" / "handoffs" / HOP1).read_text(encoding="utf-8")


def test_new_refuses_memory_root_without_self_ignore_guard(tmp_path):
    repo = make_repo(tmp_path)
    (repo / ".work" / ".gitignore").unlink()
    result = run(*new_args(repo, tmp_path, "--no-previous"))
    assert result.returncode == 1
    assert "self-ignore guard" in err(result)
    assert not (repo / ".work" / ".gitignore").exists()
    assert not (repo / ".work" / "handoffs").exists()


def test_new_outside_any_git_repo_still_requires_guard_and_uses_absolute_origin_path(tmp_path):
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    memory = tmp_path / "plugin-data" / "topic-docs"
    memory.mkdir(parents=True)
    args = new_args(tmp_path, tmp_path, "--no-previous")
    args[args.index("--memory-dir") + 1] = str(memory)
    refused = run(*args)
    assert refused.returncode == 1, err(refused)
    assert "self-ignore guard" in err(refused)
    assert not (memory / ".gitignore").exists()
    (memory / ".gitignore").write_text("*\n", encoding="utf-8")
    result = run(*args)
    assert result.returncode == 0, err(result)
    target = memory / "handoffs" / HOP1
    text = target.read_text(encoding="utf-8")
    assert f"Handoff origin: plugin-data {real_posix(target)}" in text


def test_new_refuses_root_equivalent_memory_dir(tmp_path):
    repo = make_repo(tmp_path)
    args = new_args(repo, tmp_path, "--no-previous")
    args[args.index("--memory-dir") + 1] = str(repo)
    result = run(*args)
    assert result.returncode == 1
    assert "Invalid memory_dir" in err(result)
    args[args.index("--memory-dir") + 1] = str(repo / ".work" / "..")
    result = run(*args)
    assert result.returncode == 1


def test_new_never_overwrites_an_existing_target(tmp_path):
    repo = make_repo(tmp_path)
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    target = repo / ".work" / "handoffs" / HOP1
    before = target.read_bytes()
    result = run(*new_args(repo, tmp_path, "--no-previous"))
    assert result.returncode == 1
    assert "never overwritten" in err(result)
    assert target.read_bytes() == before


def test_new_requires_exactly_one_predecessor_flag(tmp_path):
    repo = make_repo(tmp_path)
    neither = run(*new_args(repo, tmp_path))
    assert neither.returncode == 2
    both = run(*new_args(repo, tmp_path, "--no-previous", "--previous", "x.md"))
    assert both.returncode == 2


def test_new_refuses_predecessor_outside_handoffs_dir(tmp_path):
    repo = make_repo(tmp_path)
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    stray = elsewhere / LEGACY
    shutil.copy(FIXTURES / "legacy-14" / "handoffs" / LEGACY, stray)
    result = run(*new_args(repo, tmp_path, "--previous", str(stray)))
    assert result.returncode == 1
    assert "must live in the handoffs dir" in err(result)
    missing = run(*new_args(repo, tmp_path, "--previous", str(repo / ".work" / "handoffs" / "nope.md")))
    assert missing.returncode == 1


def test_new_hop2_places_the_new_slot_above_a_carried_superseded_marker(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    filled = fill(hop1.read_text(encoding="utf-8"))
    live = "- [h1] The thing must stay green."
    assert live in filled
    hop1.write_text(
        filled.replace(live, live + "\n\nSuperseded:\n- [h1] The old thing, since disproved."),
        encoding="utf-8",
        newline="\n",
    )
    run("validate", str(hop1), "--strict-transcript").check_returncode()

    run(*new_args(repo, tmp_path, "--previous", str(hop1), sid=SID_B, now="2026-09-02T10:00:00Z")).check_returncode()
    hop2 = handoffs / HOP2
    section = _section_body(hop2, "Constraints that must hold").split("\n")
    slot_index = next(i for i, line in enumerate(section) if line.startswith("<!-- FILL: constraints-new"))
    marker_index = next(i for i, line in enumerate(section) if line.startswith("Superseded:"))
    assert slot_index < marker_index, section

    entry = "- [h2] A constraint this hop discovered."
    text = hop2.read_text(encoding="utf-8")
    assert section[slot_index] in text
    hop2.write_text(fill(text.replace(section[slot_index], entry)), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)

    # The placement is only worth anything if the parser agrees: an entry
    # filled into the slot is live, not superseded.
    body = _section_body(hop2, "Constraints that must hold").split("\n")
    parsed = [e for e in _save_point_module().parse_entries(body) if e.normalized.endswith("A constraint this hop discovered.")]
    assert len(parsed) == 1, body
    assert not parsed[0].superseded, body


def test_new_hop2_leaves_a_multi_paragraph_opening_ask_behind_the_pointer(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    filled = fill(hop1.read_text(encoding="utf-8"))
    ask = "Opening ask:\nDo the thing please."
    assert ask in filled
    hop1.write_text(
        filled.replace(ask, ask + "\n\nSecond paragraph of the very same opening ask."),
        encoding="utf-8",
        newline="\n",
    )
    first = run("validate", str(hop1), "--strict-transcript")
    assert first.returncode == 0, out(first) + err(first)

    run(*new_args(repo, tmp_path, "--previous", str(hop1), sid=SID_B, now="2026-09-02T10:00:00Z")).check_returncode()
    hop2 = handoffs / HOP2
    goal = _section_body(hop2, "Original goal")
    assert "Second paragraph of the very same opening ask." not in goal, goal
    assert f"Opening ask: see {HOP1} § Original goal" in goal, goal
    hop2.write_text(fill(hop2.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    assert "WARN" not in out(validated)


def test_validate_refuses_a_traversing_previous_handoff_and_never_echoes_it(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    outside = tmp_path / "outside.md"
    outside.write_text("SENTINEL-CONTENT-OUTSIDE-THE-HANDOFFS-DIR\n", encoding="utf-8")
    target = handoffs / HOP2
    text = target.read_text(encoding="utf-8")
    assert f"previous_handoff: {HOP1}\n" in text
    traversal = f"{HOP1[:-3]}/../../../outside.md"
    target.write_text(
        text.replace(f"previous_handoff: {HOP1}\n", f"previous_handoff: {traversal}\n"),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "bare filename" in out(result), out(result)
    assert "SENTINEL" not in out(result) + err(result)


def test_validate_refuses_a_predecessor_symlinked_out_of_the_handoffs_dir(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    outside = tmp_path / "outside-handoffs"
    outside.mkdir()
    real = outside / HOP1
    shutil.move(str(handoffs / HOP1), str(real))
    try:
        (handoffs / HOP1).symlink_to(real)
    except (OSError, NotImplementedError) as exc:  # unprivileged Windows, or a filesystem without symlinks
        pytest.skip(f"symlink creation unavailable: {exc}")
    result = run("validate", str(handoffs / HOP2), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "resolves outside this file's directory" in out(result), out(result)


def test_help_exits_zero():
    result = run("--help")
    assert result.returncode == 0
    assert "validate" in out(result) and "emit" in out(result)
