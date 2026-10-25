"""Contract tests for save_point.py (new / fill / validate / emit).

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

import base64
import functools
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
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
    "shape-4/handoffs/20260901T100000Z-handoff-widget.md",
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
FILL_RE = re.compile(r"<!-- FILL: ([a-z-]+) — (.*?) -->")
NEXT_CLOSED = "Next: none (closed)"


def rail_lines(text: str) -> int:
    """Lines consisting solely of ten or more U+2500 characters."""
    return sum(1 for line in text.split("\n") if RAIL_RE.match(line.strip()))


def test_fixture_manifest_is_complete():
    on_disk = sorted(
        p.relative_to(FIXTURES).as_posix() for p in FIXTURES.rglob("*") if p.is_file()
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


def run(
    *args: str,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    script: Path = SCRIPT,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        capture_output=True,
        env=env if env is not None else _base_env(),
        cwd=cwd,
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


def test_validate_newer_shape_hard_fails_with_exit_3(tmp_path):
    handoffs = materialize(tmp_path, "shape-4")
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
    result = run(
        "validate",
        str(handoffs / "20260902T100000Z-handoff-legacy.md"),
        "--strict-transcript",
    )
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
    located = run(
        "validate", str(handoffs / HOP1), "--projects-root", projects_root(tmp_path)
    )
    assert located.returncode == 0, out(located)
    expected = real_posix(tmp_path / "projects" / "-work-repo" / (SID_A + ".jsonl"))
    assert f"present now at {expected}" in out(located)


def test_validate_chain_longer_than_predecessor_plus_self_fails(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP2
    text = target.read_text(encoding="utf-8")
    text = text.replace(
        f"chain:\n  - {HOP1}\n",
        f"chain:\n  - 20260831T100000Z-handoff-widget.md\n  - {HOP1}\n",
    )
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


@pytest.mark.parametrize(
    ("pointer", "passes"),
    [
        ("[h1] Promoted to docs/adr/0007.md: Migrations run forward-only;", True),
        ("[h1] Promoted to docs/adr/0007.md: Migrations", False),
        ("[h2] Promoted to docs/adr/0007.md: Migrations run forward-only;", False),
        ("[h1] Promoted to docs/adr/0007.md: Something else entirely here", False),
        ("[h1] Promoted to : Migrations run forward-only;", False),
    ],
)
def test_validate_promoted_pointer_replaces_a_dropped_entry(tmp_path, pointer, passes):
    """A resolved entry may leave the handoff for a committed doc, but only behind a
    pointer that keeps its tag and quotes enough of it to name which entry left."""
    handoffs = materialize(tmp_path, "dropped-entry")
    hop2 = handoffs / HOP2
    text = hop2.read_text(encoding="utf-8")
    anchor = "- [h1] The public `WidgetReader` signature is frozen.\n"
    hop2.write_text(text.replace(anchor, anchor + f"- {pointer}\n"), encoding="utf-8")
    result = run("validate", str(hop2), "--strict-transcript")
    assert (result.returncode == 0) is passes, out(result)
    assert ("predecessor entry dropped" not in out(result)) is passes, out(result)


@pytest.mark.parametrize(("pointers", "passes"), [(1, False), (2, True)])
def test_validate_promoted_pointer_stands_in_for_one_entry(tmp_path, pointers, passes):
    """Two dropped same-tag entries sharing a prefix need two pointers, not one."""
    handoffs = materialize(tmp_path, "dropped-entry")
    hop1, hop2 = handoffs / HOP1, handoffs / HOP2
    kept = "- [h1] Migrations run forward-only; a down-migration corrupts the tenant partition key.\n"
    text1 = hop1.read_text(encoding="utf-8")
    hop1.write_text(
        text1.replace(
            kept, kept + "- [h1] Migrations run forward-only; seeds are too.\n"
        ),
        encoding="utf-8",
    )
    anchor = "- [h1] The public `WidgetReader` signature is frozen.\n"
    pointer = "- [h1] Promoted to docs/adr/0007.md: Migrations run forward-only;\n"
    text2 = hop2.read_text(encoding="utf-8")
    hop2.write_text(
        text2.replace(anchor, anchor + pointer * pointers), encoding="utf-8"
    )
    result = run("validate", str(hop2), "--strict-transcript")
    assert (result.returncode == 0) is passes, out(result)


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
        text.replace(
            stored, "Read @/work/elsewhere/20260101T000000Z-handoff-other.md,"
        ),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "does not name this file" in out(result)
    assert "FAIL" in out(result)


def test_validate_warns_on_an_oversized_file_only(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    normal = run("validate", str(target), "--strict-transcript")
    assert normal.returncode == 0 and "size:" not in out(normal), out(normal)
    text = target.read_text(encoding="utf-8")
    target.write_text(text + "\n" * 300, encoding="utf-8", newline="\n")
    big = run("validate", str(target), "--strict-transcript")
    assert big.returncode == 0, out(big)
    assert "WARN" in out(big) and "size:" in out(big)


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
    assert (
        "WARN" in out(result)
        and "secret-shaped" in out(result)
        and "GitHub token" in out(result)
    )


def test_validate_flags_a_github_app_installation_token_in_jwt_form(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    # ghs_<APPID>_<JWT>, about 520 characters; the segments spell FAKE.
    token = "ghs" + "_1234567_eyJFAKE.FAKEpayload" + "A" * 450 + ".FAKEsignatureNOTreal"
    text = text.replace(
        "None. Nothing waits on a person or an access grant.",
        f"None. The token {token} was rotated.",
    )
    target.write_text(text, encoding="utf-8", newline="\n")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 0, out(result)
    assert "secret-shaped" in out(result) and "GitHub token" in out(result)


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


# A stateless installation token is ghs_ then a JWT of about 520 characters, with
# no app id. The RS256 header encodes to exactly 36 alphanumerics, the length
# gh[pousr]_ accepts; the kid header carries a '-' 16 characters in, before any
# alphanumeric minimum is met. Payload and signature are fake.
_STATELESS_JWT_TAIL = (
    "."
    + _b64url(b'{"sub":"FAKE-not-a-real-token","iat":0}')
    + "."
    + _b64url(b"\xfb\xff\xfeFAKE signature, not a real token" * 9)
)


@pytest.mark.parametrize(
    "header",
    [
        _b64url(b'{"alg":"RS256","typ":"JWT"}'),
        _b64url(b'{"kid":"k?~>","alg":"RS256","typ":"JWT"}'),
    ],
    ids=["rs256-header", "kid-header"],
)
@pytest.mark.parametrize(
    "prefix", ["ghs" + "_", "ghs" + "_123456_"], ids=["no-app-id", "app-id"]
)
def test_stateless_installation_token_is_flagged_whole(header, prefix):
    token = prefix + header + _STATELESS_JWT_TAIL
    assert len(token) > 500
    matches = [
        pattern.search(f"tok {token} z").group()
        for pattern, label in _save_point_module().SECRET_SHAPES
        if label == "GitHub token" and pattern.search(f"tok {token} z")
    ]
    assert token in matches


@pytest.mark.parametrize(
    "text", ["ghs_job", "ghs_lane", "3e7fef0587433cfb07332dbeabf0d79fc0baadf3"]
)
def test_token_placeholders_are_not_secret_shaped(text):
    shapes = _save_point_module().SECRET_SHAPES
    assert not [label for pattern, label in shapes if pattern.search(text)]


@pytest.mark.parametrize(
    "line",
    [
        "ghs_1_-" * 50000,
        "ghs_1_eyJ" * 30000,
        "ghs_1_eyJa." * 30000,
        "ghs_1_eyJ-" * 30000,
        ("ghs_1_eyJ" + "A" * 600) * 1000,
        "-eyJ" * 75000,
        "eyJ" + "A" * 600000,
        ("eyJ" + "A" * 600) * 1000,
        ("-eyJ" * 127 + " ") * 600,
        "a." * 150000,
        "a." * 32 + "a@" + "a." * 150000,
        "-----BEGIN a PRIVATE KEY-----" * 20000,
    ],
    ids=[
        "dash",
        "header",
        "dotted",
        "header-dash",
        "header-long-repeated",
        "jwt-header",
        "jwt-long-header",
        "jwt-long-header-repeated",
        "jwt-header-near-bound",
        "scheme",
        "scheme-at",
        "private-key",
    ],
)
def test_secret_shape_scan_of_an_adversarial_line_finishes_promptly(line):
    # Shapes that made the GitHub token, JWT and connection string patterns
    # here, or the observer's private key pattern, backtrack for seconds to
    # minutes.
    start = time.monotonic()
    for pattern, _ in _save_point_module().SECRET_SHAPES:
        pattern.search(line)
    assert time.monotonic() - start < 1.0


@pytest.mark.parametrize(
    ("text", "label"),
    [
        # Header, payload and signature spell FAKE.
        (
            "auth eyJhbGciOiJIUzI1NiJ9" + ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal x",
            "JWT",
        ),
        ("eyJ" + "A" * 509 + ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal", "JWT"),
        ("eyJ" + "A" * 513 + ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal", "JWT"),
        ("eyJ" + "A" * 4000 + ".eyJzdWIiOiJGQUtFIn0.FAKEsignatureNOTreal", "JWT"),
        (
            "ghs" + "_1_eyJ" + "A" * 513 + ".FAKEpayload.FAKEsignatureNOTreal",
            "GitHub token",
        ),
        (
            "ghs" + "_1_eyJ" + "A" * 4000 + ".FAKEpayload.FAKEsignatureNOTreal",
            "GitHub token",
        ),
        ("dsn postgres://u:p@h/db", "connection string"),
        (
            "postgresql+psycopg2://user:FAKEpass@db.example.com:5432/app",
            "connection string",
        ),
        ("m" * 64 + "://u:p@h", "connection string"),
    ],
    ids=[
        "jwt",
        "jwt-512-header",
        "jwt-513-header",
        "jwt-4000-header",
        "ghs-513-header",
        "ghs-4000-header",
        "url",
        "url-compound-scheme",
        "url-64-scheme",
    ],
)
def test_bounded_secret_shapes_still_flag_realistic_secrets(text, label):
    labels = {
        found
        for pattern, found in _save_point_module().SECRET_SHAPES
        if pattern.search(text)
    }
    assert label in labels


@pytest.mark.parametrize("marker", ["- ", "* ", "+ ", "1. ", "2) "])
def test_validate_refuses_a_bulleted_next_headline(tmp_path, marker):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    headline = "Add the re-run test to tests/test_importer.py"
    assert f"\n{headline}\n" in text
    target.write_text(
        text.replace(f"\n{headline}\n", f"\n{marker}{headline}\n"),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "headline must not be a bullet" in out(result), out(result)
    assert headline in out(result), out(result)


def _blank_section(path: Path, title: str) -> None:
    """Leave the heading in place with a body of blank lines only."""
    lines = path.read_text(encoding="utf-8").split("\n")
    start = lines.index(f"## {title}")
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")),
        len(lines),
    )
    path.write_text(
        "\n".join(lines[: start + 1] + ["", ""] + lines[end:]),
        encoding="utf-8",
        newline="\n",
    )


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
    target.write_text(
        text.replace("handoff_shape: 2\n", f"handoff_shape: {value}\n", 1),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert f"handoff_shape {value} is not a shape" in out(result), out(result)
    # -1 was the old unparsable sentinel, so it used to be mislabelled.
    assert "not an integer" not in out(result), out(result)


def test_validate_reports_a_non_integer_shape_as_not_an_integer(tmp_path):
    handoffs = materialize(tmp_path, "good-chain")
    target = handoffs / HOP1
    text = target.read_text(encoding="utf-8")
    target.write_text(
        text.replace("handoff_shape: 2\n", "handoff_shape: two\n", 1),
        encoding="utf-8",
        newline="\n",
    )
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
    assert result.stdout.decode("utf-8") == _section_body(
        handoffs / HOP2, "Resume prompt"
    )
    assert b"\r" not in result.stdout
    assert rail_lines(out(result)) == 2
    assert result.stdout.decode("utf-8").startswith(
        "`/clear`, then copy everything between the dashed lines:"
    )


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


def make_repo(
    tmp_path: Path, remote: str | None = "ssh://git@github.com/example/repo"
) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir(parents=True)
    subprocess.run(
        ["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True
    )
    subprocess.run(
        ["git", "-C", str(repo), "config", "commit.gpgsign", "false"], check=True
    )
    subprocess.run(
        ["git", "-C", str(repo), "config", "core.autocrlf", "false"], check=True
    )
    if remote:
        subprocess.run(
            ["git", "-C", str(repo), "remote", "add", "origin", remote], check=True
        )
    (repo / ".work").mkdir()
    (repo / ".work" / ".gitignore").write_text("*\n", encoding="utf-8")
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    return repo


def new_args(
    repo: Path,
    tmp_path: Path,
    *extra: str,
    sid: str = SID_A,
    now: str = "2026-09-01T10:00:00Z",
    shape: str | None = "2",
) -> list[str]:
    """`new` arguments; the shape-2 writer by default, so the shape-2 contract
    keeps its tests; `shape=None` passes no --shape (the default shape)."""
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
        *(["--shape", shape] if shape else []),
        *extra,
    ]


def model_fill(text: str) -> str:
    """Fill every reasoning slot the way a well-behaved model would: optional
    slots deleted, cumulative slots given one tagged entry, the rest prose."""

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

    filled: list[str] = []
    for line in text.split("\n"):
        whole = FILL_RE.fullmatch(line.strip())
        if whole and (
            whole.group(1) in ("goal-first", "goal-after", "below-rail")
            or whole.group(1).endswith("-new")
        ):
            continue
        filled.append(FILL_RE.sub(repl, line))
    return "\n".join(filled)


def test_new_hop1_writes_skeleton_and_prints_path(tmp_path):
    repo = make_repo(
        tmp_path,
        remote="https://x-access-token:ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123@github.com/example/repo.git",
    )
    result = run(*new_args(repo, tmp_path, "--no-previous"))
    assert result.returncode == 0, err(result)
    target = repo / ".work" / "handoffs" / HOP1
    assert target.is_file()
    assert out(result).strip() == real_posix(target)
    text = target.read_text(encoding="utf-8")
    assert "\r" not in text
    assert "handoff_shape: 2" in text
    assert f"session_id: {SID_A}" in text
    assert (
        f"transcript: {real_posix(tmp_path / 'projects' / '-work-repo' / (SID_A + '.jsonl'))}"
        in text
    )
    assert "previous_handoff" not in text
    assert f"chain:\n  - {HOP1}\n---" in text
    assert f"Read @{real_posix(target)}, confirm its Original goal" in text
    assert (
        "invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand."
        in text
    )
    assert (
        f"Handoff origin: https://github.com/example/repo.git .work/handoffs/{HOP1}"
        in text
    )
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
    target.write_text(
        model_fill(target.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
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
    hop1.write_text(
        model_fill(hop1.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    hop2 = handoffs / HOP2
    text = hop2.read_text(encoding="utf-8")
    assert f"previous_handoff: {HOP1}" in text
    assert f"chain:\n  - {HOP1}\n  - {HOP2}\n---" in text
    assert f"Opening ask: see {HOP1} § Original goal\n" in text
    assert "> Do the thing." in text
    assert "- [h1] The thing must stay green." in text
    assert "<!-- FILL: constraints-new" in text and "[h2]" in text
    assert (
        f"| 2026-09-01T10:00:00Z | {SID_A} | " in text
        and f"| did: did the thing · left: the rest | {HOP1} |" in text
    )
    assert "None (first hop)." not in text
    hop2.write_text(model_fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    assert "WARN" not in out(validated)


def test_new_hop2_carries_amendments_below_the_opening_ask(tmp_path):
    """An amendment bullet sitting BELOW the predecessor's 'Opening ask:' line
    is still part of the goal and must survive the carry: the skip that drops
    the ask runs to the next structural marker, and a bullet is one."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    text = model_fill(hop1.read_text(encoding="utf-8"))
    amendment = '- **Amended (verbatim, 2026-09-01):** "Also do the other thing."'
    anchor = "Opening ask:\nDo the thing please.\n"
    assert anchor in text
    hop1.write_text(
        text.replace(anchor, f"{anchor}\n{amendment}\n"), encoding="utf-8", newline="\n"
    )
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    hop2 = handoffs / HOP2
    carried = hop2.read_text(encoding="utf-8")
    assert amendment in carried, carried
    # Carried above the pointer, where an amendment belongs.
    assert carried.index(amendment) < carried.index(
        f"Opening ask: see {HOP1} § Original goal"
    )
    hop2.write_text(model_fill(carried), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_new_hop2_from_shape1_legacy_tags_and_points(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    legacy = handoffs / LEGACY
    shutil.copy(FIXTURES / "legacy-14" / "handoffs" / LEGACY, legacy)
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(legacy),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    hop2 = handoffs / HOP2
    text = hop2.read_text(encoding="utf-8")
    assert f"chain:\n  - {LEGACY}\n  - {HOP2}\n---" in text
    assert (
        f"Opening ask: see {LEGACY} § Original goal (shape-1 root, no verbatim ask recorded)"
        in text
    )
    assert (
        "> Make the widget importer idempotent so a re-run never duplicates rows."
        in text
    )
    assert (
        "- [h1] The public `WidgetReader` signature is frozen; two downstream repos compile against it."
        in text
    )
    assert (
        "- [h1] Migration `20260901_add_widget_index` is APPLIED to the local database; do not re-run."
        in text
    )
    assert (
        "UNVERIFIED (shape-1 predecessor; brief: Purpose: finish the importer dedup key."
        in text
    )
    assert (
        "| 11111111-1111-4111-8111-111111111111 | unresolved (session 11111111-1111-4111-8111-111111111111"
        in text
    )
    hop2.write_text(model_fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


LEGACY_ROOT = "20260831T100000Z-handoff-legacy.md"


def _two_hop_legacy_chain(handoffs: Path) -> Path:
    """LEGACY_ROOT <- LEGACY, both shape-1 (no chain:), linked by a pointer."""
    handoffs.mkdir()
    source = (FIXTURES / "legacy-14" / "handoffs" / LEGACY).read_text(encoding="utf-8")
    (handoffs / LEGACY_ROOT).write_text(source, encoding="utf-8", newline="\n")
    linked = source.replace(
        "session_id: 11111111-1111-4111-8111-111111111111\n",
        "session_id: 11111111-1111-4111-8111-111111111111\n"
        f"previous_handoff: {LEGACY_ROOT}\n",
        1,
    )
    assert linked != source
    legacy = handoffs / LEGACY
    legacy.write_text(linked, encoding="utf-8", newline="\n")
    return legacy


def test_new_after_a_shape1_chain_records_every_hop_its_pointers_reach(tmp_path):
    """A shape-1 predecessor has no chain: list, so its previous_handoff
    pointers are walked; the successor's chain is not capped at two."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    legacy = _two_hop_legacy_chain(handoffs)
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(legacy),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    hop = handoffs / HOP2
    text = hop.read_text(encoding="utf-8")
    assert f"chain:\n  - {LEGACY_ROOT}\n  - {LEGACY}\n  - {HOP2}\n---" in text
    hop.write_text(model_fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_validate_still_accepts_the_two_entry_chain_after_a_shape1_predecessor(
    tmp_path,
):
    """Files written before the walk carry [predecessor, self]; they stay valid,
    and any other chain is refused with the walked chain named."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    legacy = _two_hop_legacy_chain(handoffs)
    linked = legacy.read_text(encoding="utf-8")
    legacy.write_text(
        linked.replace(f"previous_handoff: {LEGACY_ROOT}\n", ""),
        encoding="utf-8",
        newline="\n",
    )
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(legacy),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    legacy.write_text(linked, encoding="utf-8", newline="\n")
    hop = handoffs / HOP2
    text = model_fill(hop.read_text(encoding="utf-8"))
    assert f"chain:\n  - {LEGACY}\n  - {HOP2}\n---" in text
    hop.write_text(text, encoding="utf-8", newline="\n")
    validated = run("validate", str(hop), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    hop.write_text(
        text.replace(f"chain:\n  - {LEGACY}\n", f"chain:\n  - {HOP1}\n  - {LEGACY}\n"),
        encoding="utf-8",
        newline="\n",
    )
    refused = run("validate", str(hop), "--strict-transcript")
    assert refused.returncode != 0
    assert f"['{LEGACY_ROOT}', '{LEGACY}', '{HOP2}']" in out(refused) + err(refused)


def test_new_hop2_from_seven_section_legacy_maps_absent_sections(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    legacy = handoffs / LEGACY7
    shutil.copy(FIXTURES / "legacy-7" / "handoffs" / LEGACY7, legacy)
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(legacy),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    text = (handoffs / HOP2).read_text(encoding="utf-8")
    assert "<!-- FILL: goal — RECONSTRUCTED from the transcript" in text
    assert "None. (shape-1 predecessor had no Constraints that must hold)" in text
    assert (
        "None. (shape-1 predecessor had no Findings that cost effort to discover)"
        in text
    )
    assert (
        "UNVERIFIED (shape-1 predecessor; brief: no Resumption brief section)" in text
    )
    unfinished = run("validate", str(handoffs / HOP2))
    assert unfinished.returncode == 1
    hop2 = handoffs / HOP2
    hop2.write_text(model_fill(text), encoding="utf-8", newline="\n")
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_new_hop2_from_malformed_shape2_marks_carried_rows_unverified(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    bad = handoffs / HOP1
    shutil.copy(FIXTURES / "malformed-predecessor" / "handoffs" / HOP1, bad)
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(bad),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert result.returncode == 0, err(result)
    text = (handoffs / HOP2).read_text(encoding="utf-8")
    assert (
        "- [h1] UNVERIFIED (predecessor failed validation): The public `WidgetReader` signature is frozen."
        in text
    )
    assert (
        bad.read_bytes()
        == (FIXTURES / "malformed-predecessor" / "handoffs" / HOP1).read_bytes()
    )


def test_new_hop2_from_relocated_predecessor_carries_rows_verified(tmp_path):
    """A predecessor whose only defect is relocation must not taint the
    entries carried into its successor."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    text = model_fill(hop1.read_text(encoding="utf-8"))
    stored = f"Read @{real_posix(hop1)},"
    assert stored in text
    # Same basename under a root that no longer exists: what copying a chain
    # out of a removed worktree leaves behind.
    text = text.replace(
        stored, f"Read @/work/elsewhere/removed-worktree/.work/handoffs/{HOP1},"
    )
    hop1.write_text(text, encoding="utf-8", newline="\n")
    relocated = run("validate", str(hop1), "--projects-root", projects_root(tmp_path))
    assert relocated.returncode == 0, out(relocated) + err(relocated)
    assert "WARN" in out(relocated)
    result = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
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
    assert (
        f"transcript: unresolved (session {sid}, projects-root {projects_root(tmp_path)})"
        in text
    )


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
    bridge_shaped = run(
        *new_args(repo, tmp_path, "--no-previous", sid="cse_0123456789abcdef")
    )
    assert bridge_shaped.returncode == 1 and "not a UUID" in err(bridge_shaped)
    assert not (repo / ".work" / "handoffs").exists()


def test_new_reads_session_id_from_env(tmp_path):
    repo = make_repo(tmp_path)
    env = dict(_base_env(), CLAUDE_CODE_SESSION_ID=SID_B.upper())
    args = new_args(repo, tmp_path, "--no-previous")
    del args[args.index("--session-id") : args.index("--session-id") + 2]
    result = run(*args, env=env)
    assert result.returncode == 0, err(result)
    assert f"session_id: {SID_B}" in (repo / ".work" / "handoffs" / HOP1).read_text(
        encoding="utf-8"
    )


def test_new_refuses_memory_root_without_self_ignore_guard(tmp_path):
    repo = make_repo(tmp_path)
    (repo / ".work" / ".gitignore").unlink()
    result = run(*new_args(repo, tmp_path, "--no-previous"))
    assert result.returncode == 1
    assert "self-ignore guard" in err(result)
    assert not (repo / ".work" / ".gitignore").exists()
    assert not (repo / ".work" / "handoffs").exists()


def test_new_outside_any_git_repo_still_requires_guard_and_uses_absolute_origin_path(
    tmp_path,
):
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    memory = tmp_path / "plugin-data" / "artifacts"
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


def _no_memory_dir_args(tmp_path: Path) -> list[str]:
    args = new_args(tmp_path, tmp_path, "--no-previous")
    at = args.index("--memory-dir")
    del args[at : at + 2]
    return args


def _outside_git(tmp_path: Path) -> Path:
    shutil.copytree(FIXTURES / "projects", tmp_path / "projects", dirs_exist_ok=True)
    cwd = tmp_path / "home-dir"
    cwd.mkdir()
    probe = subprocess.run(
        ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
        capture_output=True,
        check=False,
    )
    if probe.returncode == 0:
        pytest.skip("tmp_path sits inside a git work tree")
    return cwd


def test_new_without_memory_dir_outside_git_uses_plugin_data_env(tmp_path):
    cwd = _outside_git(tmp_path)
    data = tmp_path / "session-flow-test"
    memory = data / "artifacts"
    memory.mkdir(parents=True)
    env = {**_base_env(), "CLAUDE_PLUGIN_DATA": str(data)}
    args = _no_memory_dir_args(tmp_path)
    refused = run(*args, env=env, cwd=cwd)
    assert refused.returncode == 1, err(refused)
    assert f"create {real_posix(memory / '.gitignore')}" in err(refused)
    assert not (cwd / ".work").exists()
    (memory / ".gitignore").write_text("*\n", encoding="utf-8")
    result = run(*args, env=env, cwd=cwd)
    assert result.returncode == 0, err(result)
    assert out(result).strip() == real_posix(memory / "handoffs" / HOP1)
    assert not (cwd / ".work").exists()


def _install_in_cache(version_dir):
    # save_point.py and io_streams.py, the one module it imports, under the
    # plugin cache layout.
    scripts = version_dir / "scripts"
    scripts.mkdir(parents=True)
    for name in ("save_point.py", "io_streams.py"):
        shutil.copy2(SCRIPT.parent / name, scripts / name)


def test_new_without_memory_dir_outside_git_derives_data_dir_from_cache(tmp_path):
    cwd = _outside_git(tmp_path)
    config = tmp_path / "config"
    version_dir = config / "plugins" / "cache" / "my.market" / "session-flow" / "1.2.3"
    _install_in_cache(version_dir)
    memory = config / "plugins" / "data" / "session-flow-my-market" / "artifacts"
    memory.mkdir(parents=True)
    (memory / ".gitignore").write_text("*\n", encoding="utf-8")
    result = run(
        *_no_memory_dir_args(tmp_path),
        cwd=cwd,
        script=version_dir / "scripts" / "save_point.py",
    )
    assert result.returncode == 0, err(result)
    assert out(result).strip() == real_posix(memory / "handoffs" / HOP1)


def test_new_without_memory_dir_outside_git_and_no_data_dir_refuses(tmp_path):
    cwd = _outside_git(tmp_path)
    result = run(*_no_memory_dir_args(tmp_path), cwd=cwd)
    assert result.returncode == 1
    assert "pass --memory-dir" in err(result)
    assert not (cwd / ".work").exists()


def test_new_without_memory_dir_ignores_another_plugins_data_env(tmp_path):
    # Another plugin's SessionStart hook can export its own data dir into every
    # Bash call as CLAUDE_PLUGIN_DATA; the derivation from the cache path wins.
    cwd = _outside_git(tmp_path)
    config = tmp_path / "config"
    version_dir = config / "plugins" / "cache" / "my.market" / "session-flow" / "1.2.3"
    _install_in_cache(version_dir)
    memory = config / "plugins" / "data" / "session-flow-my-market" / "artifacts"
    memory.mkdir(parents=True)
    (memory / ".gitignore").write_text("*\n", encoding="utf-8")
    foreign = tmp_path / "codex-openai-codex"
    (foreign / "artifacts").mkdir(parents=True)
    (foreign / "artifacts" / ".gitignore").write_text("*\n", encoding="utf-8")
    env = {**_base_env(), "CLAUDE_PLUGIN_DATA": str(foreign)}
    result = run(
        *_no_memory_dir_args(tmp_path),
        env=env,
        cwd=cwd,
        script=version_dir / "scripts" / "save_point.py",
    )
    assert result.returncode == 0, err(result)
    assert out(result).strip() == real_posix(memory / "handoffs" / HOP1)
    assert not (foreign / "artifacts" / "handoffs").exists()


def test_memory_root_outside_git_prints_the_plugin_data_artifacts(tmp_path):
    cwd = _outside_git(tmp_path)
    data = tmp_path / "session-flow-test"
    env = {**_base_env(), "CLAUDE_PLUGIN_DATA": str(data)}
    result = run("memory-root", env=env, cwd=cwd)
    assert result.returncode == 0, err(result)
    assert out(result).strip() == real_posix(data / "artifacts")
    refused = run("memory-root", cwd=cwd)
    assert refused.returncode == 1


def test_new_without_memory_dir_inside_git_keeps_the_work_default(tmp_path):
    repo = make_repo(tmp_path)
    data = tmp_path / "plugin-data"
    env = {**_base_env(), "CLAUDE_PLUGIN_DATA": str(data)}
    result = run(*_no_memory_dir_args(tmp_path), env=env, cwd=repo)
    assert result.returncode == 0, err(result)
    assert out(result).strip() == real_posix(repo / ".work" / "handoffs" / HOP1)
    assert not data.exists()


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
    missing = run(
        *new_args(
            repo, tmp_path, "--previous", str(repo / ".work" / "handoffs" / "nope.md")
        )
    )
    assert missing.returncode == 1


def test_a_live_entry_repeating_a_superseded_one_warns(tmp_path):
    target = new_hop2_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    carried = "- [h1] The thing must stay green."
    assert carried in text
    target.write_text(
        text.replace(
            carried,
            carried + "\n\nSuperseded:\n- [h2] The thing must stay green.",
        ),
        encoding="utf-8",
        newline="\n",
    )
    warned = run("validate", str(target))
    assert "WARN: Constraints that must hold: duplicate" in out(warned)


def test_new_hop2_places_the_new_slot_above_a_carried_superseded_marker(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    filled = model_fill(hop1.read_text(encoding="utf-8"))
    live = "- [h1] The thing must stay green."
    assert live in filled
    hop1.write_text(
        filled.replace(
            live, live + "\n\nSuperseded:\n- [h1] The old thing, since disproved."
        ),
        encoding="utf-8",
        newline="\n",
    )
    run("validate", str(hop1), "--strict-transcript").check_returncode()

    run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    ).check_returncode()
    hop2 = handoffs / HOP2
    section = _section_body(hop2, "Constraints that must hold").split("\n")
    slot_index = next(
        i
        for i, line in enumerate(section)
        if line.startswith("<!-- FILL: constraints-new")
    )
    marker_index = next(
        i for i, line in enumerate(section) if line.startswith("Superseded:")
    )
    assert slot_index < marker_index, section

    entry = "- [h2] A constraint this hop discovered."
    text = hop2.read_text(encoding="utf-8")
    assert section[slot_index] in text
    hop2.write_text(
        model_fill(text.replace(section[slot_index], entry)),
        encoding="utf-8",
        newline="\n",
    )
    validated = run("validate", str(hop2), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)

    # The placement is only worth anything if the parser agrees: an entry
    # filled into the slot is live, not superseded.
    body = _section_body(hop2, "Constraints that must hold").split("\n")
    parsed = [
        e
        for e in _save_point_module().parse_entries(body)
        if e.normalized.endswith("A constraint this hop discovered.")
    ]
    assert len(parsed) == 1, body
    assert not parsed[0].superseded, body


def test_new_hop2_leaves_a_multi_paragraph_opening_ask_behind_the_pointer(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    filled = model_fill(hop1.read_text(encoding="utf-8"))
    ask = "Opening ask:\nDo the thing please."
    assert ask in filled
    hop1.write_text(
        filled.replace(ask, ask + "\n\nSecond paragraph of the very same opening ask."),
        encoding="utf-8",
        newline="\n",
    )
    first = run("validate", str(hop1), "--strict-transcript")
    assert first.returncode == 0, out(first) + err(first)

    run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    ).check_returncode()
    hop2 = handoffs / HOP2
    goal = _section_body(hop2, "Original goal")
    assert "Second paragraph of the very same opening ask." not in goal, goal
    assert f"Opening ask: see {HOP1} § Original goal" in goal, goal
    hop2.write_text(
        model_fill(hop2.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
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
    except (
        OSError,
        NotImplementedError,
    ) as exc:  # unprivileged Windows, or a filesystem without symlinks
        pytest.skip(f"symlink creation unavailable: {exc}")
    result = run("validate", str(handoffs / HOP2), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "resolves outside this file's directory" in out(result), out(result)


# --- fill ---------------------------------------------------------------------------

FILL_VALUES = {
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
}


def slot_instructions(text: str) -> dict[str, str]:
    """Every slot a skeleton carries, name to instruction."""
    return {m.group(1): m.group(2) for m in FILL_RE.finditer(text)}


def required_slots(text: str) -> dict[str, str]:
    """A slots payload keying every REQUIRED slot this skeleton carries, valued
    the way a well-behaved model would. Optional slots (instruction opening
    `optional:`) are omitted, so `fill` deletes their lines; a caller that wants
    one filled adds the key itself. Read off the file rather than a name list,
    because the slot set is branch-dependent."""
    return {
        name: FILL_VALUES.get(name, f"Filled {name}.")
        for name, instruction in slot_instructions(text).items()
        if not instruction.startswith("optional:")
    }


def slots_file(tmp_path: Path, payload: object, name: str = "slots.json") -> str:
    path = tmp_path / name
    path.write_text(json.dumps(payload), encoding="utf-8")
    return str(path)


def raw_slots_file(tmp_path: Path, body: str, name: str = "slots.json") -> str:
    path = tmp_path / name
    path.write_text(body, encoding="utf-8")
    return str(path)


def new_skeleton(tmp_path: Path) -> Path:
    """A fresh first-hop skeleton, ready to fill."""
    repo = make_repo(tmp_path)
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    return repo / ".work" / "handoffs" / HOP1


def new_hop2_skeleton(tmp_path: Path) -> Path:
    """A continuation skeleton: the only branch carrying the `<section>-new`
    optional slots, so the deletion cases need it."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    hop1.write_text(
        model_fill(hop1.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
    run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    ).check_returncode()
    return handoffs / HOP2


def test_fill_then_validate_and_emit_exit_zero(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    result = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert result.returncode == 0, err(result)
    assert result.stdout == b"", out(result)
    assert "<!-- FILL" not in target.read_text(encoding="utf-8")
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    assert "FAIL" not in out(validated) and "WARN" not in out(validated)
    emitted = run("emit", str(target))
    assert emitted.returncode == 0, err(emitted)
    assert emitted.stdout.decode("utf-8") == _section_body(target, "Resume prompt")


def test_fill_preserves_crlf_on_untouched_lines(tmp_path):
    target = new_skeleton(tmp_path)
    # `cmd_new` writes with newline="\n", so CRLF never arises from `new` itself;
    # a CRLF skeleton is what a consumer's own editor or checkout leaves behind.
    target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
    payload = required_slots(target.read_text(encoding="utf-8"))
    result = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert result.returncode == 0, err(result)
    data = target.read_bytes()
    assert b"\r\n" in data
    assert b"\n" not in data.replace(b"\r\n", b"")
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_fill_preserves_every_inline_prefix(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["amended"] = "None."
    payload["drift-check"] = "the next action writes the save-point, which is the goal."
    payload["did"] = "did the thing"
    payload["left"] = "the rest"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert "**Amended:** None." in text
    assert (
        "**Next action serves it by:** the next action writes the save-point, which is the goal."
        in text
    )
    assert "did: did the thing · left: the rest" in text


def test_fill_handles_two_slots_on_the_this_session_line(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["did"] = "landed the fill subcommand"
    payload["left"] = "the docs sweep"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    line = next(
        ln
        for ln in target.read_text(encoding="utf-8").split("\n")
        if ln.startswith("did: ")
    )
    assert re.fullmatch(r"did: .+ · left: .+", line), line
    assert "|" not in line
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_this_session_carries_one_rescan_line_and_refuses_a_second_or_a_stray(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["rescan"] = "read the lossless on-disk transcript; no compaction occurred"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert text.count("\nRe-scan: read the lossless on-disk transcript") == 1
    assert run("validate", str(target), "--strict-transcript").returncode == 0
    for extra in ("Re-scan: again", "a stray line"):
        target.write_text(
            text.replace("\nRe-scan: ", f"\n{extra}\nRe-scan: ", 1),
            encoding="utf-8",
            newline="\n",
        )
        assert run("validate", str(target), "--strict-transcript").returncode == 1, (
            extra
        )


def test_a_predecessor_constraint_attestation_entry_carries_forward(tmp_path):
    """An attestation an earlier chain wrote into Constraints is an ordinary
    entry: it stays, so the successor still validates."""
    target = new_hop2_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    assert "Re-scanned" not in text
    old = "- [h1] Re-scanned the visible conversation only; a compaction occurred this session."
    hop1 = target.parent / HOP1
    hop1.write_text(
        hop1.read_text(encoding="utf-8").replace(
            "- [h1] The thing must stay green.",
            f"- [h1] The thing must stay green.\n{old}",
            1,
        ),
        encoding="utf-8",
        newline="\n",
    )
    assert run("validate", str(hop1), "--strict-transcript").returncode == 0
    repo = target.parent.parent.parent
    target.unlink()
    run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    ).check_returncode()
    carried = target.read_text(encoding="utf-8")
    assert old in carried
    payload = required_slots(carried)
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    assert run("validate", str(target), "--strict-transcript").returncode == 0


def test_carrying_a_rule_already_in_the_predecessor_adds_no_second_copy(tmp_path):
    """A new entry whose text matches a carried one (tag, UNVERIFIED prefix,
    spacing and case aside) is a duplicate: validate warns and the oldest tag
    stays the only copy once the writer drops it."""
    target = new_hop2_skeleton(tmp_path)
    carried = "- [h1] The thing must stay green."
    text = target.read_text(encoding="utf-8")
    assert carried in text
    slot = next(
        line
        for line in text.splitlines()
        if line.startswith("<!-- FILL: constraints-new")
    )
    copy = (
        "- [h2] UNVERIFIED (predecessor failed validation): the  THING must stay green."
    )
    payload = required_slots(text)
    target.write_text(text.replace(slot, copy), encoding="utf-8", newline="\n")
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    warned = run("validate", str(target), "--strict-transcript")
    assert warned.returncode == 0, out(warned) + err(warned)
    assert "WARN: Constraints that must hold: duplicate" in out(warned)

    filled = target.read_text(encoding="utf-8")
    target.write_text(filled.replace(copy + "\n", ""), encoding="utf-8", newline="\n")
    clean = run("validate", str(target), "--strict-transcript")
    assert clean.returncode == 0, out(clean) + err(clean)
    assert "WARN" not in out(clean)
    assert target.read_text(encoding="utf-8").count("must stay green") == 1


def test_fill_multi_line_value_lands_as_lines_in_place(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = "First headline\nSecond headline\nThird headline"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert "\nNext:\nFirst headline\nSecond headline\nThird headline\n─" in text
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_fill_multi_line_value_into_crlf_stays_all_crlf(tmp_path):
    target = new_skeleton(tmp_path)
    target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = "First headline\nSecond headline"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    data = target.read_bytes()
    assert "Next:\r\nFirst headline\r\nSecond headline\r\n─".encode("utf-8") in data
    assert b"\n" not in data.replace(b"\r\n", b"")


def test_fill_normalizes_a_crlf_value_to_one_break_per_line(tmp_path):
    lf_root = tmp_path / "lf"
    lf_root.mkdir()
    lf = new_skeleton(lf_root)
    payload = required_slots(lf.read_text(encoding="utf-8"))
    payload["next"] = "a\r\nb"
    run("fill", str(lf), "--slots", slots_file(lf_root, payload)).check_returncode()
    lf_data = lf.read_bytes()
    assert "\nNext:\na\nb\n─".encode("utf-8") in lf_data
    assert b"\r" not in lf_data

    crlf_root = tmp_path / "crlf"
    crlf_root.mkdir()
    crlf = new_skeleton(crlf_root)
    crlf.write_bytes(crlf.read_bytes().replace(b"\n", b"\r\n"))
    payload = required_slots(crlf.read_text(encoding="utf-8"))
    payload["next"] = "a\r\nb"
    run("fill", str(crlf), "--slots", slots_file(crlf_root, payload)).check_returncode()
    crlf_data = crlf.read_bytes()
    assert "\r\nNext:\r\na\r\nb\r\n─".encode("utf-8") in crlf_data
    assert b"\n" not in crlf_data.replace(b"\r\n", b"")


@pytest.mark.parametrize(
    "slot", ["goal-first", "goal-after", "below-rail", "constraints-new"]
)
def test_fill_deletes_absent_optional_slot_line(tmp_path, slot):
    target = new_hop2_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    assert f"<!-- FILL: {slot} " in text
    payload = required_slots(text)
    assert slot not in payload
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    after = target.read_text(encoding="utf-8")
    assert "<!-- FILL" not in after
    assert slot not in after
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_fill_substitutes_a_present_optional_slot(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["goal-first"] = goal_slot_value(
        target.read_text(encoding="utf-8"), "goal-first", "ship the fill subcommand"
    )
    payload["below-rail"] = "Re-arm the sweep loop in its own follow-up message."
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    after = target.read_text(encoding="utf-8")
    assert "\nship the fill subcommand\n" in after
    assert "Re-arm the sweep loop in its own follow-up message." in after
    assert "<!-- FILL" not in after
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


# --- goal region ----------------------------------------------------------------------

GOAL_COPY_LINE = (
    "Type `/goal ` (with a trailing space), then paste everything between the dashed "
    "lines. Confirm the `◎ /goal active` indicator appears after you send it; if it "
    "is missing, redo it:"
)
COPY_LINE = "`/clear`, then copy everything between the dashed lines:"
RAIL = "─" * 58
CONDITION = (
    "Every call site of OrderReader uses the retry policy and `dotnet test` exits 0."
)


def directive_line(text: str) -> str:
    return next(line for line in text.split("\n") if line.startswith("Read @"))


def goal_slot_value(skeleton: str, slot: str, condition: str = CONDITION) -> str:
    """The whole goal region as the `goal-first` / `goal-after` slot takes it:
    the value carries its own blank-line separator."""
    directive = directive_line(skeleton)
    region = "\n".join([GOAL_COPY_LINE, "", RAIL, condition, directive, RAIL])
    return region + "\n" if slot == "goal-first" else "\n" + region


def goal_target(tmp_path: Path, *slots: str, condition: str = CONDITION) -> Path:
    """A filled first-hop handoff with the goal region in each named slot."""
    target = new_skeleton(tmp_path)
    skeleton = target.read_text(encoding="utf-8")
    payload = required_slots(skeleton)
    for slot in slots:
        payload[slot] = goal_slot_value(skeleton, slot, condition)
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    return target


def validate_text(target: Path, text: str) -> subprocess.CompletedProcess[bytes]:
    target.write_text(text, encoding="utf-8", newline="\n")
    return run("validate", str(target), "--strict-transcript")


def test_goal_first_region_validates_and_emits_before_the_resume_region(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    assert "goal-after" not in text and "<!-- FILL" not in text
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    emitted = out(run("emit", str(target)))
    assert rail_lines(emitted) == 4
    assert emitted.startswith(GOAL_COPY_LINE + "\n\n" + RAIL + "\n" + CONDITION + "\n")
    assert emitted.index(GOAL_COPY_LINE) < emitted.index(COPY_LINE)


def test_goal_after_region_validates_and_emits_after_the_resume_region(tmp_path):
    target = goal_target(tmp_path, "goal-after")
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    emitted = out(run("emit", str(target)))
    assert rail_lines(emitted) == 4
    assert emitted.startswith(COPY_LINE)
    assert emitted.index(COPY_LINE) < emitted.index(GOAL_COPY_LINE)
    assert emitted.index("Or reopen the producing session") > emitted.index(CONDITION)


def test_no_goal_output_is_the_single_resume_region(tmp_path):
    target = goal_target(tmp_path)
    emitted = out(run("emit", str(target)))
    assert rail_lines(emitted) == 2
    assert emitted.startswith(COPY_LINE + "\n\n" + RAIL + "\nRead @")
    assert "/goal" not in emitted
    assert run("validate", str(target), "--strict-transcript").returncode == 0


def test_goal_condition_at_the_limit_passes_and_over_it_fails(tmp_path):
    # Equal-length directory names keep the stored directive line the same length.
    probe = goal_target(tmp_path / "p1", "goal-first")
    directive = directive_line(probe.read_text(encoding="utf-8"))
    fits = "x" * (4000 - len(directive) - 1)
    at_limit = goal_target(tmp_path / "p2", "goal-first", condition=fits)
    assert run("validate", str(at_limit), "--strict-transcript").returncode == 0
    over = goal_target(tmp_path / "p3", "goal-first", condition=fits + "x")
    result = run("validate", str(over), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "goal region holds 4001 characters (max 4000)" in out(result), out(result)


def test_validate_refuses_a_leading_goal_line_in_the_goal_region(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    result = validate_text(
        target, text.replace(f"\n{CONDITION}\n", f"\n/goal {CONDITION}\n")
    )
    assert result.returncode == 1, out(result) + err(result)
    assert "starts with '/goal'" in out(result), out(result)


def test_validate_refuses_a_leading_goal_line_in_the_resume_region(tmp_path):
    target = new_skeleton(tmp_path)
    run(
        "fill",
        str(target),
        "--slots",
        slots_file(tmp_path, required_slots(target.read_text(encoding="utf-8"))),
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    result = validate_text(
        target, text.replace(f"{RAIL}\nRead @", f"{RAIL}\n/goal ship it\nRead @", 1)
    )
    assert result.returncode == 1, out(result) + err(result)
    assert "starts with '/goal'" in out(result), out(result)
    assert "must be the 'Read @' directive" in out(result), out(result)


def test_validate_refuses_a_goal_region_without_its_instruction_line(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    result = validate_text(target, text.replace(GOAL_COPY_LINE + "\n", "", 1))
    assert result.returncode == 1, out(result) + err(result)
    assert "no copy instruction line above a top rail" in out(result), out(result)


def test_validate_refuses_two_goal_regions(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    result = validate_text(target, text.replace(COPY_LINE, GOAL_COPY_LINE, 1))
    assert result.returncode == 1, out(result) + err(result)
    assert "more than one goal region" in out(result), out(result)


def test_validate_refuses_a_goal_region_on_each_side_of_the_resume_region(tmp_path):
    target = goal_target(tmp_path, "goal-first", "goal-after")
    result = run("validate", str(target), "--strict-transcript")
    assert result.returncode == 1, out(result) + err(result)
    assert "two U+2500 rails" in out(result), out(result)


def test_validate_refuses_a_goal_region_not_ending_in_the_directive(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    directive = directive_line(text)
    result = validate_text(
        target,
        text.replace(
            f"{directive}\n{RAIL}\n\n{COPY_LINE}",
            f"Do the thing.\n{RAIL}\n\n{COPY_LINE}",
            1,
        ),
    )
    assert result.returncode == 1, out(result) + err(result)
    assert "ending in the 'Read @' directive line" in out(result), out(result)


def test_validate_refuses_a_goal_region_with_a_blank_line_between_the_rails(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    result = validate_text(
        target, text.replace(f"{RAIL}\n{CONDITION}\n", f"{RAIL}\n{CONDITION}\n\n", 1)
    )
    assert result.returncode == 1, out(result) + err(result)
    assert "blank line between the rails" in out(result), out(result)


def test_emit_substitutes_the_real_path_in_both_regions(tmp_path):
    target = goal_target(tmp_path, "goal-first")
    text = target.read_text(encoding="utf-8")
    stored = f"Read @{real_posix(target)}"
    assert text.count(stored) == 2
    target.write_text(
        text.replace(stored, f"Read @/work/elsewhere/{target.name}"),
        encoding="utf-8",
        newline="\n",
    )
    result = run("emit", str(target))
    assert result.returncode == 0, err(result)
    assert out(result).count(f"{stored}, confirm") == 2
    assert "/work/elsewhere/" not in out(result)


@pytest.mark.parametrize(
    ("case", "expected", "needle"),
    [
        ("missing-required", 1, "'next'"),
        ("unknown-key", 1, "'not-a-slot'"),
        ("value-carries-a-slot-opener", 1, "<!-- FILL"),
        ("malformed-json", 2, "not valid JSON"),
        ("non-object-json", 2, "JSON object"),
        ("non-string-value", 2, "must be a string"),
        ("lone-surrogate-value", 2, "'brief'"),
        ("both-defects", 2, "must be a string"),
    ],
)
def test_fill_refusals_leave_the_target_byte_identical(
    tmp_path, case, expected, needle
):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    if case == "missing-required":
        del payload["next"]
        slots = slots_file(tmp_path, payload)
    elif case == "unknown-key":
        payload["not-a-slot"] = "x"
        slots = slots_file(tmp_path, payload)
    elif case == "value-carries-a-slot-opener":
        payload["brief"] = "the leftover <!-- FILL: next — headlines --> slot"
        slots = slots_file(tmp_path, payload)
    elif case == "malformed-json":
        slots = raw_slots_file(tmp_path, '{"brief": "x",}')
    elif case == "non-object-json":
        slots = raw_slots_file(tmp_path, '["brief"]')
    elif case == "non-string-value":
        payload["brief"] = 7
        slots = slots_file(tmp_path, payload)
    elif case == "both-defects":
        # The exit-1 defect is keyed FIRST and the exit-2 defect LAST, so a
        # single interleaved loop would exit 1; the split loops exit 2.
        payload["brief"] = "carries <!-- FILL: next — headlines --> verbatim"
        del payload["did"]
        payload["did"] = 7
        slots = slots_file(tmp_path, payload)
    else:
        payload["brief"] = "\ud800"
        slots = slots_file(tmp_path, payload)
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots)
    assert result.returncode == expected, out(result) + err(result)
    assert needle in err(result), err(result)
    assert target.read_bytes() == before


def test_fill_refuses_a_target_with_no_slots(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    before = target.read_bytes()
    again = run(
        "fill", str(target), "--slots", slots_file(tmp_path, {}, name="empty.json")
    )
    assert again.returncode == 1, out(again) + err(again)
    assert "<!-- FILL" in err(again), err(again)
    assert target.read_bytes() == before


def test_fill_refuses_a_duplicate_slot_name(tmp_path):
    target = new_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    line = next(ln for ln in text.split("\n") if ln.startswith("<!-- FILL: brief "))
    target.write_text(
        text.replace(line, line + "\n" + line, 1), encoding="utf-8", newline="\n"
    )
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots_file(tmp_path, {"brief": "x"}))
    assert result.returncode == 1, out(result) + err(result)
    assert "'brief'" in err(result) and "twice" in err(result)
    assert target.read_bytes() == before


def test_fill_refuses_a_missing_target(tmp_path):
    result = run(
        "fill",
        str(tmp_path / "absent.md"),
        "--slots",
        slots_file(tmp_path, {"brief": "x"}),
    )
    assert result.returncode == 2, out(result) + err(result)
    assert "not a file" in err(result)


def test_fill_refuses_an_undecodable_target(tmp_path):
    """A directory here would only re-run the missing-target branch; invalid
    UTF-8 is what exercises the decode refusal."""
    target = tmp_path / "not-utf8.md"
    target.write_bytes(b"---\ntype: handoff\n---\n\xff\xfe not utf-8\n")
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots_file(tmp_path, {"brief": "x"}))
    assert result.returncode == 2, out(result) + err(result)
    assert "cannot read" in err(result)
    assert target.read_bytes() == before


def test_fill_refuses_a_file_that_is_not_a_handoff(tmp_path):
    target = tmp_path / "not-a-handoff.md"
    target.write_text(
        "---\ntype: note\n---\n\n<!-- FILL: brief — one line -->\n",
        encoding="utf-8",
        newline="\n",
    )
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots_file(tmp_path, {"brief": "x"}))
    assert result.returncode == 2, out(result) + err(result)
    assert "not a handoff file" in err(result)
    assert target.read_bytes() == before


@pytest.mark.parametrize(
    ("line", "expected", "needle"),
    [
        ("handoff_shape: 4\n", 3, "read it, do not rewrite it"),
        ("handoff_shape: 1\n", 2, "handoff_shape 1"),
        ("", 2, "no handoff_shape key"),
        ("handoff_shape: 0\n", 2, "handoff_shape 0 is not a shape"),
        ("handoff_shape: -1\n", 2, "handoff_shape -1 is not a shape"),
        ("handoff_shape: two\n", 2, "handoff_shape 'two' is not an integer"),
    ],
)
def test_fill_refuses_a_shape_that_is_not_two(tmp_path, line, expected, needle):
    """A newer shape is read and never rewritten, as `validate` says; every
    other shape that is not 2 is refused beside the `type: handoff` guard. Both
    refusals land before the write, so the target stays byte-identical."""
    target = new_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    payload = required_slots(text)
    assert "handoff_shape: 2\n" in text
    target.write_text(
        text.replace("handoff_shape: 2\n", line, 1), encoding="utf-8", newline="\n"
    )
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert result.returncode == expected, out(result) + err(result)
    assert needle in err(result), err(result)
    assert target.read_bytes() == before


def test_fill_refuses_an_unreadable_slots_file(tmp_path):
    target = new_skeleton(tmp_path)
    before = target.read_bytes()
    directory = tmp_path / "slots-is-a-directory.json"
    directory.mkdir()
    result = run("fill", str(target), "--slots", str(directory))
    assert result.returncode == 2, out(result) + err(result)
    assert "cannot read" in err(result)
    assert target.read_bytes() == before


def test_fill_closing_value_rewrites_next_and_deletes_the_slot(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = NEXT_CLOSED
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert f"\n{NEXT_CLOSED}\n─" in text
    assert "\nNext:\n" not in text
    assert text.count(NEXT_CLOSED) == 1
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    emitted = run("emit", str(target))
    assert emitted.returncode == 0, err(emitted)
    assert NEXT_CLOSED in out(emitted)


def test_fill_closing_value_into_crlf_keeps_crlf(tmp_path):
    target = new_skeleton(tmp_path)
    target.write_bytes(target.read_bytes().replace(b"\n", b"\r\n"))
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = NEXT_CLOSED
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    data = target.read_bytes()
    assert f"\r\n{NEXT_CLOSED}\r\n─".encode("utf-8") in data
    assert b"\r\r" not in data
    assert b"\n" not in data.replace(b"\r\n", b"")
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_fill_closing_value_works_with_a_goal_region_present(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = NEXT_CLOSED
    payload["goal-after"] = goal_slot_value(
        target.read_text(encoding="utf-8"), "goal-after", "close the loop"
    )
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert f"\n{NEXT_CLOSED}\n─" in text
    assert "\nclose the loop\n" in text
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)
    emitted = run("emit", str(target))
    assert emitted.returncode == 0, err(emitted)


def test_fill_closing_value_refuses_when_the_line_above_is_not_bare_next(tmp_path):
    target = new_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    assert "\nNext:\n<!-- FILL: next " in text
    target.write_text(
        text.replace(
            "\nNext:\n<!-- FILL: next ", "\nNext: already here\n<!-- FILL: next ", 1
        ),
        encoding="utf-8",
        newline="\n",
    )
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = NEXT_CLOSED
    before = target.read_bytes()
    result = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert result.returncode == 1, out(result) + err(result)
    assert "Next:" in err(result)
    assert target.read_bytes() == before


def test_fill_an_ordinary_next_value_leaves_next_bare(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["next"] = "Ship the docs sweep"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    text = target.read_text(encoding="utf-8")
    assert "\nNext:\nShip the docs sweep\n─" in text
    assert NEXT_CLOSED not in text
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 0, out(validated) + err(validated)


def test_fill_slot_pattern_round_trips_through_the_fill_helper(tmp_path):
    """The pattern and `_fill()` are one grammar: every slot the skeleton
    carries re-renders to the exact span the pattern matched. Comparing whole
    lines would be false for the prefixed lines and for the two-slot line.

    The line that pins non-greediness is `len(matches) > len(carrying)`. The
    round trip alone does not: a greedy instruction group swallows the rest of
    the two-slot line INTO the group, so `_fill()` re-renders it identically and
    every assertion in the loop still passes on one match instead of two."""
    module = _save_point_module()
    target = new_skeleton(tmp_path)
    text = target.read_text(encoding="utf-8")
    matches = [
        m for line in text.split("\n") for m in module.FILL_SLOT_RE.finditer(line)
    ]
    carrying = [line for line in text.split("\n") if module.FILL_MARK in line]
    assert matches
    # One line carries two slots, so the spans outnumber the lines holding them.
    assert len(matches) > len(carrying)
    for m in matches:
        assert module._fill(m.group(1), m.group(2)) == m.group(0)


def test_fill_empty_string_value_substitutes_and_validate_judges(tmp_path):
    """Substitution only: an empty value leaves a bare prefix and `validate`
    rules on it, rather than `fill` inventing a deletion rule."""
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["did"] = ""
    result = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert result.returncode == 0, err(result)
    assert "did:  · left: the rest" in target.read_text(encoding="utf-8")
    validated = run("validate", str(target), "--strict-transcript")
    assert validated.returncode == 1, out(validated)
    assert "This session" in out(validated)


def test_fill_preserves_a_file_with_no_trailing_newline(tmp_path):
    target = new_skeleton(tmp_path)
    data = target.read_bytes()
    assert data.endswith(b"\n")
    target.write_bytes(data.rstrip(b"\n"))
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["below-rail"] = "Re-arm nothing; the loop is retired."
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    after = target.read_bytes()
    assert after.endswith(b"the loop is retired.")


def test_fill_leaves_no_other_file_beside_the_target(tmp_path):
    """The write goes through a temporary file in the handoffs dir; a run that
    leaves one behind would put a stray file where handoffs are swept for."""
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    assert sorted(p.name for p in target.parent.iterdir()) == [target.name]


def test_fill_value_with_a_lone_cr_is_not_split(tmp_path):
    target = new_skeleton(tmp_path)
    payload = required_slots(target.read_text(encoding="utf-8"))
    payload["brief"] = "before\rafter"
    run(
        "fill", str(target), "--slots", slots_file(tmp_path, payload)
    ).check_returncode()
    data = target.read_bytes()
    assert b"before\rafter\n" in data
    assert data.count(b"\r") == 1


def test_help_exits_zero():
    result = run("--help")
    assert result.returncode == 0
    for command in ("new", "fill", "validate", "emit"):
        assert command in out(result), out(result)


# --- shape 3: hot file plus one immutable archive file per hop ----------------------
#
# Expected values come from PLAN.md `## Design` Contracts: the frontmatter keys, the
# hop-file name `archive/<chain-root-stem>/h<N>-<session8>.md`, the FAIL list and the
# cap of 10,000 tokens at the 2.46 bytes per token AUDIT.md measured on handoff files.

SID_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
SID_D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
SID_E = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
HOP4 = "20260904T100000Z-handoff-widget.md"
HOP5 = "20260905T100000Z-handoff-widget.md"
HOT_CAP = 24_600
# The Read tool's 25,000-token page cap at 2.34 bytes per token (#9238 asks for a
# FAIL above it).
READ_CAP = 58_500
# The Brief's hot-file content list in its written order, `Original goal` first and
# `## Resume prompt` last (PLAN.md "Hot file and archive"): an external contract.
SHAPE3_SECTIONS = [
    "Original goal",
    "Review before you continue",
    "Direction changes",
    "Resumption brief",
    "Completion criteria",
    "Remaining actions, in order",
    "Open questions",
    "Current rules",
    "Observations",
    "Pending commands",
    "Environment to re-establish",
    "Decisions in force",
    "Suggested skills",
    "This session",
    "Prior sessions",
    "Standing preferences",
    "Resume prompt",
]
SHAPE3_VALUES = {
    "goal": "> Do the thing.",
    "intent": "Fewer bytes, same accuracy.",
    "vision": "Every change is a measured improvement.",
    "amended": "None.",
    "opening-ask": "Do the thing please.",
    "review": "- Nothing beyond this file: the next action needs no archive section.",
    "trail": '- [h1] start: do the thing (owner-directed, "Do the thing please.").',
    "brief": "Do the next thing on `main`; read Current rules first.",
    "criteria": "- [ ] the thing is done",
    "remaining": "1. Do the next thing.",
    "open-questions": "None. Nothing is unknown.",
    "rules": "- [R1] The thing must stay green.\n- [R2] Never push to main.",
    "observations": "- The thing takes a minute to run.",
    "commands": "None. No command waits on the user.",
    "environment": "Branch `main`, clean tree; nothing to recreate.",
    "decisions": "- The thing over the other thing.",
    "skills": "None. Remaining work runs inline.",
    "did": "did the thing",
    "left": "the rest",
    "rescan": "the re-scan read the lossless on-disk transcript",
    "preferences": "None. No standing preference this chain.",
    "next": "Do the next thing",
}


def shape3_fill(text: str, values: dict[str, str] | None = None) -> str:
    """Fill a shape-3 skeleton the way a well-behaved model would. Optional slot
    lines not keyed in `values` are deleted; an unknown required slot raises."""
    merged = {**SHAPE3_VALUES, **(values or {})}
    kept: list[str] = []
    for line in text.split("\n"):
        whole = FILL_RE.fullmatch(line.strip())
        if (
            whole
            and whole.group(1) not in merged
            and whole.group(2).startswith("optional:")
        ):
            continue
        kept.append(FILL_RE.sub(lambda m: merged[m.group(1)], line))
    return "\n".join(kept)


def s3_new(
    repo: Path,
    tmp_path: Path,
    previous: Path | None = None,
    *,
    sid: str = SID_A,
    now: str = "2026-09-01T10:00:00Z",
) -> subprocess.CompletedProcess[bytes]:
    flag = ["--previous", str(previous)] if previous else ["--no-previous"]
    return run(*new_args(repo, tmp_path, *flag, sid=sid, now=now, shape="3"))


def s3_hop(
    repo: Path,
    tmp_path: Path,
    previous: Path | None = None,
    *,
    sid: str = SID_A,
    now: str = "2026-09-01T10:00:00Z",
    values: dict[str, str] | None = None,
) -> Path:
    made = s3_new(repo, tmp_path, previous, sid=sid, now=now)
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    text = shape3_fill(path.read_text(encoding="utf-8"), values)
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def s3_chain(repo: Path, tmp_path: Path, sids: list[str]) -> list[Path]:
    paths: list[Path] = []
    for day, sid in enumerate(sids, 1):
        previous = paths[-1] if paths else None
        now = f"2026-09-0{day}T10:00:00Z"
        paths.append(s3_hop(repo, tmp_path, previous, sid=sid, now=now))
    return paths


def hop_file(handoffs: Path, root: str, hop: int, sid: str) -> Path:
    return handoffs / "archive" / root.removesuffix(".md") / f"h{hop}-{sid[:8]}.md"


def strict(path: Path) -> subprocess.CompletedProcess[bytes]:
    return run("validate", str(path), "--strict-transcript")


def headings(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").split("\n")
    return [line[3:] for line in lines if line.startswith("## ")]


def edit(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, old
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def _sections_by_hand(text: str) -> dict[str, str]:
    """Each `## ` section body of a file, trimmed of blank edge lines."""
    found: dict[str, str] = {}
    for chunk in text.split("\n## ")[1:]:
        title, _, body = chunk.partition("\n")
        found[title] = body.strip("\n")
    return found


def test_shape3_is_what_new_writes_by_default(tmp_path):
    repo = make_repo(tmp_path)
    made = run(*new_args(repo, tmp_path, "--no-previous", shape=None))
    assert made.returncode == 0, err(made)
    text = (repo / ".work" / "handoffs" / HOP1).read_text(encoding="utf-8")
    assert "handoff_shape: 3\n" in text
    assert "\nchain:" not in text
    for line in (
        f"chain_root: {HOP1}",
        "hop: 1",
        "archive: archive/20260901T100000Z-handoff-widget/",
        "archive_from: 1",
        "repo: ssh://git@github.com/example/repo",
    ):
        assert f"\n{line}\n" in text, line
    assert "previous_handoff" not in text


def test_shape3_hop1_validates_with_sections_in_the_contract_order(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    result = strict(hop1)
    assert result.returncode == 0, out(result) + err(result)
    assert "FAIL" not in out(result) and "WARN" not in out(result), out(result)
    assert headings(hop1) == SHAPE3_SECTIONS
    assert hop_file(repo / ".work" / "handoffs", HOP1, 1, SID_A).is_file()
    edit(hop1, "## Observations\n", "## Observations held\n")
    renamed = strict(hop1)
    assert renamed.returncode == 1 and "headings:" in out(renamed), out(renamed)


def test_shape3_written_before_suggested_skills_still_validates(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    text = hop1.read_text(encoding="utf-8")
    start = text.index("## Suggested skills\n")
    legacy = text[:start] + text[text.index("## This session\n") :]
    hop1.write_text(legacy, encoding="utf-8", newline="\n")
    result = strict(hop1)
    assert result.returncode == 0, out(result) + err(result)
    assert "WARN" in out(result) and "Suggested skills" in out(result), out(result)


@pytest.mark.parametrize("shape", ["2", "3"])
def test_new_purpose_leads_the_brief_and_changes_nothing_else(tmp_path, shape):
    texts: dict[str, str] = {}
    emitted: dict[str, str] = {}
    for arm, extra in (
        ("plain", []),
        ("purpose", ["--purpose", "review the design\n  with the platform team"]),
    ):
        base = tmp_path / arm
        repo = make_repo(base)
        made = run(*new_args(repo, base, "--no-previous", *extra, shape=shape))
        assert made.returncode == 0, err(made)
        path = Path(out(made).strip())
        text = path.read_text(encoding="utf-8")
        fill = shape3_fill if shape == "3" else model_fill
        path.write_text(fill(text), encoding="utf-8", newline="\n")
        checked = run("validate", str(path))
        assert checked.returncode == 0, out(checked)
        printed = run("emit", str(path))
        assert printed.returncode == 0, err(printed)
        here = real_posix(base)
        texts[arm] = text.replace(here, "<base>")
        emitted[arm] = out(printed).replace(here, "<base>")
    plain = _sections_by_hand(texts["plain"])
    tailored = _sections_by_hand(texts["purpose"])
    assert list(tailored) == list(plain)
    changed = {title for title in plain if plain[title] != tailored[title]}
    assert changed == {"Resumption brief", "Suggested skills"}
    brief = tailored["Resumption brief"].split("\n")
    assert brief[0] == "Purpose: review the design with the platform team"
    assert "Purpose:" not in plain["Resumption brief"]
    assert "selected for the Purpose line" in tailored["Suggested skills"]
    assert emitted["purpose"] == emitted["plain"]


@pytest.mark.parametrize("purpose", ["see --> here", "a <!-- FILL: x — y --> b"])
def test_new_refuses_a_purpose_that_breaks_the_slot_grammar(tmp_path, purpose):
    repo = make_repo(tmp_path)
    made = run(*new_args(repo, tmp_path, "--no-previous", "--purpose", purpose))
    assert made.returncode == 2
    assert "--purpose must not carry" in err(made)
    assert not (repo / ".work" / "handoffs" / HOP1).exists()


def test_shape3_validate_enforces_the_section_order(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    text = hop1.read_text(encoding="utf-8")
    swapped = (
        text.replace("## Observations\n", "## @@\n")
        .replace("## Pending commands\n", "## Observations\n")
        .replace("## @@\n", "## Pending commands\n")
    )
    hop1.write_text(swapped, encoding="utf-8", newline="\n")
    result = strict(hop1)
    assert result.returncode == 1, out(result)
    assert "headings: expected '## Observations' at position 9" in out(result)


def test_shape3_hot_file_over_the_byte_cap_fails(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    text = hop1.read_text(encoding="utf-8")
    size = len(text.encode("utf-8"))
    anchor = SHAPE3_VALUES["observations"] + "\n"

    def padded(total: int) -> str:
        return text.replace(anchor, anchor + "x" * (total - size - 1) + "\n", 1)

    hop1.write_text(padded(HOT_CAP), encoding="utf-8", newline="\n")
    assert len(hop1.read_bytes()) == HOT_CAP
    at_cap = strict(hop1)
    assert at_cap.returncode == 0, out(at_cap)
    hop1.write_text(padded(HOT_CAP + 1), encoding="utf-8", newline="\n")
    over = strict(hop1)
    assert over.returncode == 1, out(over)
    assert "FAIL: size: 24601 bytes" in out(over) and "24600" in out(over), out(over)


def test_shape3_core_alone_over_the_cap_is_unvalidated_and_still_emits(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path, values={"rules": "- [R1] " + "y" * HOT_CAP})
    result = strict(hop1)
    assert result.returncode == 0, out(result)
    assert "FAIL" not in out(result), out(result)
    assert "UNVALIDATED" in out(result)
    assert out(result).strip().splitlines()[-1].startswith("validate: UNVALIDATED")
    emitted = run("emit", str(hop1))
    assert emitted.returncode == 0, err(emitted)
    assert out(emitted) == _section_body(hop1, "Resume prompt")
    assert "UNVALIDATED" in err(emitted)


def test_shape3_hot_file_over_the_read_cap_fails_even_when_its_core_is_too_large(
    tmp_path,
):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path, values={"rules": "- [R1] " + "y" * READ_CAP})
    assert len(hop1.read_bytes()) > READ_CAP
    result = strict(hop1)
    assert result.returncode == 1, out(result)
    assert f"FAIL: size: {len(hop1.read_bytes())} bytes" in out(result), out(result)
    assert f"{READ_CAP}-byte Read page cap" in out(result), out(result)
    assert "UNVALIDATED" not in out(result), out(result)
    emitted = run("emit", str(hop1))
    assert emitted.returncode == 0, err(emitted)
    assert out(emitted) == _section_body(hop1, "Resume prompt")
    assert "FAIL:" in err(emitted) and f"{READ_CAP}-byte Read page cap" in err(emitted)
    assert "UNVALIDATED" not in err(emitted), err(emitted)


def test_shape3_goal_must_start_with_the_predecessors_section_byte_for_byte(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path, values={"goal": "> Do the thing. "})
    hop2 = s3_hop(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    assert "> Do the thing. \n" in hop2.read_text(encoding="utf-8")
    assert strict(hop2).returncode == 0, out(strict(hop2))
    edit(hop2, "> Do the thing. \n", "> Do the thing.\n")
    trimmed = strict(hop2)
    assert trimmed.returncode == 1, out(trimmed)
    needle = "FAIL: Original goal: does not start with the predecessor's section"
    assert needle in out(trimmed), out(trimmed)
    edit(hop2, "> Do the thing.\n", "> Do the thing now. \n")
    reworded = strict(hop2)
    assert reworded.returncode == 1 and needle in out(reworded), out(reworded)


def test_shape3_goal_appends_a_new_amendment_below_the_copied_section(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    amendment = '- **Amended (verbatim, 2026-09-02):** "Also do the other thing."'
    hop2 = s3_hop(
        repo,
        tmp_path,
        hop1,
        sid=SID_B,
        now="2026-09-02T10:00:00Z",
        values={"goal-new": amendment},
    )
    result = strict(hop2)
    assert result.returncode == 0, out(result)
    goal = _sections_by_hand(hop2.read_text(encoding="utf-8"))["Original goal"]
    carried = _sections_by_hand(hop1.read_text(encoding="utf-8"))["Original goal"]
    assert goal.startswith(carried + "\n")
    assert goal.endswith(amendment)


def test_shape3_crlf_predecessor_goal_compares_by_line_content(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    hop1.write_bytes(hop1.read_bytes().replace(b"\n", b"\r\n"))
    assert strict(hop1).returncode == 0, out(strict(hop1))
    hop2 = s3_hop(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    assert b"\r" not in hop2.read_bytes()
    result = strict(hop2)
    assert result.returncode == 0, out(result) + err(result)
    assert "Original goal" not in out(result)


def test_shape3_retired_rule_may_leave_for_the_archive_but_not_vanish(tmp_path):
    repo = make_repo(tmp_path)
    hop1, hop2 = s3_chain(repo, tmp_path, [SID_A, SID_B])
    edit(hop2, "- [R2] Never push to main.\n", "")
    retired = strict(hop2)
    assert retired.returncode == 0, out(retired)
    archived = hop_file(repo / ".work" / "handoffs", HOP1, 2, SID_B)
    edit(archived, "- [R2] Never push to main.\n", "")
    vanished = strict(hop2)
    assert vanished.returncode == 1, out(vanished)
    assert "[R2]" in out(vanished) and "h2-bbbbbbbb.md" in out(vanished), out(vanished)


def test_shape3_duplicate_rule_id_fails(tmp_path):
    repo = make_repo(tmp_path)
    rules = "- [R1] The thing must stay green.\n- [R1] Never push to main."
    hop1 = s3_hop(repo, tmp_path, values={"rules": rules})
    result = strict(hop1)
    assert result.returncode == 1, out(result)
    assert "duplicate rule id [R1]" in out(result), out(result)


def test_shape3_rule_without_an_id_fails(tmp_path):
    repo = make_repo(tmp_path)
    rules = "- [R1] The thing must stay green.\n- Never push to main."
    hop1 = s3_hop(repo, tmp_path, values={"rules": rules})
    result = strict(hop1)
    assert result.returncode == 1, out(result)
    assert "without a [R<n>] id" in out(result), out(result)


def test_shape3_changed_rule_needs_its_prior_text_in_the_hop_file(tmp_path):
    repo = make_repo(tmp_path)
    hop1, hop2 = s3_chain(repo, tmp_path, [SID_A, SID_B])
    rule = "- [R1] The thing must stay green.\n"
    edit(hop2, rule, "- [R1] The thing must stay green and fast.\n")
    rewritten = strict(hop2)
    assert rewritten.returncode == 0, out(rewritten)
    edit(hop_file(repo / ".work" / "handoffs", HOP1, 2, SID_B), rule, "")
    lost = strict(hop2)
    assert lost.returncode == 1, out(lost)
    assert "[R1]" in out(lost) and "prior text" in out(lost), out(lost)


def test_shape3_missing_hop_file_on_the_chain_path_fails(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    hop1, hop2, hop3 = s3_chain(repo, tmp_path, [SID_A, SID_B, SID_C])
    assert strict(hop3).returncode == 0, out(strict(hop3))
    own = hop_file(handoffs, HOP1, 3, SID_C)
    kept = own.read_bytes()
    own.unlink()
    no_own = strict(hop3)
    assert no_own.returncode == 1 and "h3-cccccccc.md" in out(no_own), out(no_own)
    own.write_bytes(kept)
    hop_file(handoffs, HOP1, 2, SID_B).unlink()
    no_pred = strict(hop3)
    assert no_pred.returncode == 1, out(no_pred)
    assert "h2-bbbbbbbb.md" in out(no_pred), out(no_pred)


def test_shape3_github_state_claim_warns(tmp_path):
    repo = make_repo(tmp_path)
    claim = "- PR #42 is merged into main."
    hop1 = s3_hop(repo, tmp_path, values={"observations": claim})
    result = strict(hop1)
    assert result.returncode == 0, out(result)
    assert "WARN: line" in out(result) and "GitHub state" in out(result), out(result)
    edit(hop1, claim, "- PR #42 holds the change; re-read it before acting.")
    pointer = strict(hop1)
    assert pointer.returncode == 0 and "GitHub state" not in out(pointer), out(pointer)


def test_shape3_retry_rewrites_only_its_own_hop_file(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    hop1 = s3_hop(repo, tmp_path)
    s3_hop(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    s3_hop(repo, tmp_path, hop1, sid=SID_C, now="2026-09-03T10:00:00Z")
    own = hop_file(handoffs, HOP1, 2, SID_B)
    sibling = hop_file(handoffs, HOP1, 2, SID_C)
    own_bytes, sibling_bytes = own.read_bytes(), sibling.read_bytes()
    own.write_bytes(own_bytes + b"tampered\n")
    retry = s3_new(repo, tmp_path, hop1, sid=SID_B, now="2026-09-04T10:00:00Z")
    assert retry.returncode == 0, err(retry)
    assert own.read_bytes() == own_bytes
    assert sibling.read_bytes() == sibling_bytes
    other = "bbbbbbbb-0000-4000-8000-000000000000"
    clash = s3_new(repo, tmp_path, hop1, sid=other, now="2026-09-05T10:00:00Z")
    assert clash.returncode == 1, err(clash)
    assert "h2-bbbbbbbb.md" in err(clash), err(clash)
    assert own.read_bytes() == own_bytes
    assert not (handoffs / HOP5).exists()


def test_shape3_fork_writes_a_sibling_hop_file(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    hop1 = s3_hop(repo, tmp_path)
    left = s3_hop(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    right = s3_hop(repo, tmp_path, hop1, sid=SID_C, now="2026-09-03T10:00:00Z")
    archive = handoffs / "archive" / HOP1.removesuffix(".md")
    assert sorted(p.name for p in archive.iterdir()) == [
        "h1-aaaaaaaa.md",
        "h2-bbbbbbbb.md",
        "h2-cccccccc.md",
    ]
    for successor in (left, right):
        result = strict(successor)
        assert result.returncode == 0, out(result)
        assert "\nhop: 2\n" in successor.read_text(encoding="utf-8")


def _good_chain_memory(tmp_path: Path) -> Path:
    """The good-chain fixture as a memory root `new` accepts (outside any git repo)."""
    handoffs = materialize(tmp_path, "good-chain")
    (handoffs.parent / ".gitignore").write_text("*\n", encoding="utf-8")
    return handoffs


def _new_in(
    handoffs: Path, tmp_path: Path, previous: Path, sid: str, now: str
) -> subprocess.CompletedProcess[bytes]:
    return run(
        "new",
        "--topic",
        "widget",
        "--memory-dir",
        str(handoffs.parent),
        "--session-id",
        sid,
        "--projects-root",
        projects_root(tmp_path),
        "--now",
        now,
        "--previous",
        str(previous),
    )


def test_shape3_first_split_of_a_hop57_shape2_chain_needs_no_earlier_hop_files(
    tmp_path,
):
    handoffs = _good_chain_memory(tmp_path)
    names = [f"20260801T{i:02d}0000Z-handoff-widget.md" for i in range(53)]
    chain = "".join(f"  - {name}\n" for name in [*names, HOP1, HOP2, HOP3])
    edit(
        handoffs / HOP3,
        f"chain:\n  - {HOP1}\n  - {HOP2}\n  - {HOP3}\n",
        "chain:\n" + chain,
    )
    made = _new_in(handoffs, tmp_path, handoffs / HOP3, SID_D, "2026-09-10T10:00:00Z")
    assert made.returncode == 0, err(made)
    hot = Path(out(made).strip())
    text = hot.read_text(encoding="utf-8")
    assert f"\nchain_root: {names[0]}\n" in text
    assert "\nhop: 57\n" in text and "\narchive_from: 57\n" in text
    assert hop_file(handoffs, names[0], 57, SID_D).is_file()
    hot.write_text(shape3_fill(text), encoding="utf-8", newline="\n")
    result = run("validate", str(hot))
    assert result.returncode == 0, out(result)
    assert "FAIL" not in out(result) and "h56" not in out(result), out(result)


def test_shape3_first_split_dereferences_the_root_goal(tmp_path):
    handoffs = _good_chain_memory(tmp_path)
    made = _new_in(handoffs, tmp_path, handoffs / HOP3, SID_D, "2026-09-10T10:00:00Z")
    assert made.returncode == 0, err(made)
    hot = Path(out(made).strip())
    text = hot.read_text(encoding="utf-8")
    assert "\nhop: 4\n" in text and "\narchive_from: 4\n" in text
    assert f"\nchain_root: {HOP1}\n" in text
    ask = (
        "Opening ask:\n"
        "Make the widget importer idempotent. A second run doubles every row today.\n"
        "Start with the composite key, then the re-run test.\n"
    )
    assert ask in text
    assert "Opening ask: see" not in text
    assert "Next action serves it by" not in _sections_by_hand(text)["Original goal"]
    hot.write_text(shape3_fill(text), encoding="utf-8", newline="\n")
    result = run("validate", str(hot))
    assert result.returncode == 0, out(result)
    assert "FAIL" not in out(result), out(result)
    edit(hot, ask, f"Opening ask: see {HOP1} § Original goal\n")
    pointer = run("validate", str(hot))
    assert pointer.returncode == 1, out(pointer)
    assert "Opening ask" in out(pointer) and HOP1 in out(pointer), out(pointer)


def test_shape3_first_split_of_a_370kb_predecessor_moves_sections_verbatim(tmp_path):
    handoffs = _good_chain_memory(tmp_path)
    pred = handoffs / HOP1
    anchor = (
        "- [h1] The public `WidgetReader` signature is frozen; "
        "two downstream repos compile against it.\n"
    )
    sentence = "the lane must keep this rule while the chain runs "
    filler = "".join(f"- [h1] Rule {i}: {sentence * 12}\n" for i in range(700))
    edit(pred, anchor, anchor + filler)
    assert len(pred.read_bytes()) >= 370_000
    before = pred.read_bytes()
    made = _new_in(handoffs, tmp_path, pred, SID_D, "2026-09-10T10:00:00Z")
    assert made.returncode == 0, err(made)
    assert pred.read_bytes() == before
    archived = hop_file(handoffs, HOP1, 2, SID_D).read_text(encoding="utf-8")
    for title, body in _sections_by_hand(before.decode("utf-8")).items():
        if title in ("Original goal", "Resume prompt"):
            continue
        assert f"## {title}\n\n{body}\n" in archived, title
    hot = Path(out(made).strip())
    filled = shape3_fill(hot.read_text(encoding="utf-8"))
    hot.write_text(filled, encoding="utf-8", newline="\n")
    assert len(hot.read_bytes()) < HOT_CAP
    assert "Rule 17:" not in filled
    result = run("validate", str(hot))
    assert result.returncode == 0, out(result)


def test_shape3_prior_sessions_keeps_the_last_three_rows(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    paths = s3_chain(repo, tmp_path, [SID_A, SID_B, SID_C, SID_D, SID_E])
    body = _sections_by_hand(paths[-1].read_text(encoding="utf-8"))["Prior sessions"]
    rows = [line for line in body.split("\n") if line.startswith("| 2026")]
    assert [row.rstrip(" |").rsplit("| ", 1)[-1] for row in rows] == [HOP2, HOP3, HOP4]
    archived = hop_file(handoffs, HOP1, 5, SID_E).read_text(encoding="utf-8")
    assert f"| {HOP1} |" in archived
    result = run("validate", str(paths[-1]))
    assert result.returncode == 0, out(result)
    assert "FAIL" not in out(result), out(result)


def test_shape3_skeleton_fills_through_fill_and_validates(tmp_path):
    repo = make_repo(tmp_path)
    made = s3_new(repo, tmp_path)
    assert made.returncode == 0, err(made)
    target = Path(out(made).strip())
    instructions = slot_instructions(target.read_text(encoding="utf-8"))
    payload = {
        name: SHAPE3_VALUES[name]
        for name, instruction in instructions.items()
        if not instruction.startswith("optional:")
    }
    filled = run("fill", str(target), "--slots", slots_file(tmp_path, payload))
    assert filled.returncode == 0, err(filled)
    result = strict(target)
    assert result.returncode == 0, out(result)


def test_shape3_predecessor_is_never_continued_as_shape2(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SID_B,
            now="2026-09-02T10:00:00Z",
        )
    )
    assert made.returncode == 1, err(made)
    assert "shape 3" in err(made), err(made)
    assert not (repo / ".work" / "handoffs" / HOP2).exists()


def test_shape3_after_a_shape1_predecessor_points_at_its_root_and_validates(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir()
    legacy = handoffs / LEGACY
    shutil.copy(FIXTURES / "legacy-14" / "handoffs" / LEGACY, legacy)
    before = legacy.read_bytes()
    hot = s3_hop(repo, tmp_path, legacy, sid=SID_B, now="2026-09-02T10:00:00Z")
    assert legacy.read_bytes() == before
    text = hot.read_text(encoding="utf-8")
    assert f"\nprevious_handoff: {LEGACY}\n" in text
    assert f"\nchain_root: {LEGACY}\n" in text and "\nhop: 2\n" in text
    pointer = f"Opening ask: see {LEGACY} § Original goal (shape-1 root, no verbatim ask recorded)"
    assert pointer in text
    archived = hop_file(handoffs, LEGACY, 2, SID_B).read_text(encoding="utf-8")
    assert "## Constraints that must hold\n" in archived
    result = strict(hot)
    assert result.returncode == 0, out(result)


@pytest.mark.parametrize(
    ("old", "new"),
    [
        (f"chain_root: {HOP1}", "chain_root: ../../../escaped.md"),
        (
            f"chain_root: {HOP1}",
            "chain_root: 20260901T100000Z-handoff-x/../../../../escaped.md",
        ),
    ],
)
def test_shape3_new_refuses_a_chain_root_that_leaves_the_archive(tmp_path, old, new):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    edit(hop1, old, new)
    before = sorted(p.as_posix() for p in tmp_path.rglob("*"))
    made = s3_new(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    assert made.returncode == 1, err(made)
    assert "chain_root" in err(made), err(made)
    assert sorted(p.as_posix() for p in tmp_path.rglob("*")) == before


def test_shape2_to_3_new_refuses_a_chain_entry_that_leaves_the_archive(tmp_path):
    handoffs = _good_chain_memory(tmp_path)
    edit(handoffs / HOP3, f"chain:\n  - {HOP1}\n", "chain:\n  - ../../../escaped.md\n")
    before = sorted(p.as_posix() for p in tmp_path.rglob("*"))
    made = _new_in(handoffs, tmp_path, handoffs / HOP3, SID_D, "2026-09-10T10:00:00Z")
    assert made.returncode == 1, err(made)
    assert sorted(p.as_posix() for p in tmp_path.rglob("*")) == before


def test_shape3_a_retired_rule_id_is_never_offered_again(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    made = s3_new(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    hop2 = Path(out(made).strip())
    hop2.write_text(
        shape3_fill(hop2.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
    edit(hop2, "- [R2] Never push to main.\n", "")
    assert strict(hop2).returncode == 0, out(strict(hop2))
    hop3 = s3_hop(repo, tmp_path, hop2, sid=SID_C, now="2026-09-03T10:00:00Z")
    assert strict(hop3).returncode == 0, out(strict(hop3))
    made = s3_new(repo, tmp_path, hop3, sid=SID_D, now="2026-09-04T10:00:00Z")
    skeleton = Path(out(made).strip()).read_text(encoding="utf-8")
    assert "new ids from R3" in slot_instructions(skeleton)["rules-new"]
