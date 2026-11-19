"""The settle clause on the UNVERIFIED marks `new` writes (PLAN.md AC14, Contracts:
the tool's strings stay matchable by older validators). A shape-2 hop carried past a
predecessor that failed validation passes head's validator and the validator at
c1d455ccdc, the base of this branch's shape-4 work."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

from test_save_point import (
    HOP1,
    HOP2,
    SID_B,
    err,
    make_repo,
    model_fill,
    new_args,
    out,
    run,
)

BASE = "c1d455ccdc"
SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parents[2]


def base_validator(tmp_path: Path) -> Path:
    """save_point.py and the modules it imports, as they were at BASE."""
    dst = tmp_path / "base-scripts"
    dst.mkdir()
    for name in ("save_point.py", "handoff_chain.py", "io_streams.py"):
        shown = subprocess.run(
            [
                "git",
                "-C",
                str(REPO),
                "show",
                f"{BASE}:plugins/session-flow/scripts/{name}",
            ],
            capture_output=True,
            check=True,
        )
        (dst / name).write_bytes(shown.stdout)
    return dst / "save_point.py"


def hop2_past_a_failed_predecessor(tmp_path: Path) -> Path:
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    text = model_fill(hop1.read_text(encoding="utf-8"))
    hop1.write_text(
        re.sub(
            r"^transcript: .*$", "transcript: /gone/session.jsonl", text, flags=re.M
        ),
        encoding="utf-8",
        newline="\n",
    )
    assert run("validate", str(hop1)).returncode == 1
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
    assert made.returncode == 0, err(made)
    hop2 = handoffs / HOP2
    hop2.write_text(
        model_fill(hop2.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
    return hop2


def test_a_hop_carried_past_a_failed_predecessor_passes_the_base_validator(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    old = subprocess.run(
        [sys.executable, str(base_validator(tmp_path)), "validate", str(hop2)],
        capture_output=True,
        timeout=30,
    )
    assert "predecessor entry dropped" not in old.stdout.decode(), old.stdout.decode()
    assert old.returncode == 0, old.stdout.decode()


def test_the_same_hop_passes_head_with_its_marks_settled(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    text = hop2.read_text(encoding="utf-8")
    assert f"(settle: save_point.py validate {HOP1})" in text
    assert (
        "- [h1] UNVERIFIED (predecessor failed validation): The thing must stay green.\n"
        in text
    )
    result = run("validate", str(hop2))
    assert result.returncode == 0, out(result)


def test_a_hand_written_unverified_mark_still_needs_its_own_settle(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    text = hop2.read_text(encoding="utf-8")
    heading = "## Findings that cost effort to discover\n\n"
    assert heading in text
    hop2.write_text(
        text.replace(
            heading, f"{heading}- [h2] UNVERIFIED: the cache holds stale rows.\n", 1
        ),
        encoding="utf-8",
        newline="\n",
    )
    result = run("validate", str(hop2))
    assert result.returncode == 1, out(result)
    assert "UNVERIFIED without naming what settles it" in out(result)
