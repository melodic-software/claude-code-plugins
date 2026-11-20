"""The settle clause on the UNVERIFIED marks `new` writes (PLAN.md AC14, Contracts:
the tool's strings stay matchable by older validators). A shape-2 hop carried past a
predecessor that failed validation passes head's validator and the validator at
c1d455ccdc, the base of this branch's shape-4 work."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

from test_save_point import (
    HOP1,
    HOP2,
    HOP3,
    SID_B,
    SID_C,
    _save_point_module,
    err,
    make_repo,
    model_fill,
    new_args,
    out,
    run,
)

os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"

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


MULTI_LINE = "- [h1] The thing must stay green\n  across every hop of the chain."


def hop2_past_a_failed_predecessor(tmp_path: Path, multi_line: bool = False) -> Path:
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    text = model_fill(hop1.read_text(encoding="utf-8"))
    if multi_line:
        text = text.replace("- [h1] The thing must stay green.", MULTI_LINE, 1)
        assert MULTI_LINE in text
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


def test_the_carried_marks_stay_settled_one_hop_later_on_both_validators(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    repo = hop2.parents[2]
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop2),
            sid=SID_C,
            now="2026-09-03T10:00:00Z",
        )
    )
    assert made.returncode == 0, err(made)
    hop3 = hop2.parent / HOP3
    hop3.write_text(
        model_fill(hop3.read_text(encoding="utf-8")), encoding="utf-8", newline="\n"
    )
    assert "UNVERIFIED (predecessor failed validation)" in hop3.read_text(
        encoding="utf-8"
    )
    head = run("validate", str(hop3))
    assert head.returncode == 0, out(head)
    old = subprocess.run(
        [sys.executable, str(base_validator(tmp_path)), "validate", str(hop3)],
        capture_output=True,
        timeout=30,
    )
    assert old.returncode == 0, old.stdout.decode()


def test_a_multi_line_carried_entry_passes_head_and_the_base_validator(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path, multi_line=True)
    assert (
        "- [h1] UNVERIFIED (predecessor failed validation): The thing must stay green\n"
        "  across every hop of the chain." in hop2.read_text(encoding="utf-8")
    )
    head = run("validate", str(hop2))
    assert head.returncode == 0, out(head)
    old = subprocess.run(
        [sys.executable, str(base_validator(tmp_path)), "validate", str(hop2)],
        capture_output=True,
        timeout=30,
    )
    assert old.returncode == 0, old.stdout.decode()


def test_a_forged_carried_mark_past_a_missing_predecessor_needs_its_own_settle(
    tmp_path,
):
    hop2 = forged_past_a_missing_predecessor(tmp_path)
    result = run("validate", str(hop2))
    assert result.returncode == 1, out(result)
    assert "UNVERIFIED without naming what settles it" in out(result), out(result)


def forged_past_a_missing_predecessor(tmp_path: Path) -> Path:
    """Hop 2 written past a deleted hop 1, with a hand-added settle comment and
    an `[h1]` mark in the tool's carried form."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    run(*new_args(repo, tmp_path, "--no-previous")).check_returncode()
    hop1 = handoffs / HOP1
    hop1.unlink()
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
    text = model_fill(hop2.read_text(encoding="utf-8"))
    heading = "## Findings that cost effort to discover\n\n"
    forged = (
        "<!-- UNVERIFIED (predecessor failed validation) marks in this section:"
        f" (settle: save_point.py validate {HOP1}) -->\n\n"
        "- [h1] UNVERIFIED (predecessor failed validation): the cache holds stale rows.\n"
    )
    assert heading in text
    hop2.write_text(
        text.replace(heading, heading + forged, 1), encoding="utf-8", newline="\n"
    )
    return hop2


def test_an_unchecked_hop_key_does_not_make_a_this_hop_mark_carried(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    text = hop2.read_text(encoding="utf-8")
    heading = "## Findings that cost effort to discover\n\n"
    spoof = (
        "- [h2] UNVERIFIED (predecessor failed validation): The thing takes a minute."
    )
    text = text.replace("handoff_shape: 2\n", "handoff_shape: 2\nhop: 99\n", 1)
    hop2.write_text(
        text.replace(heading, f"{heading}{spoof}\n", 1), encoding="utf-8", newline="\n"
    )
    result = run("validate", str(hop2))
    assert result.returncode == 1, out(result)
    assert "UNVERIFIED without naming what settles it" in out(result), out(result)


def test_a_forged_mark_past_a_missing_predecessor_fails_the_shallow_check(tmp_path):
    hop2 = forged_past_a_missing_predecessor(tmp_path)
    sp = _save_point_module()
    findings, code = sp.validate_doc(sp.parse_doc(hop2), None, False, shallow=True)
    assert code == 1, [x.text for x in findings.items]
    assert any(x.kind is sp.CheckKind.UNVERIFIED for x in findings.fails)


def test_a_this_hop_entry_spoofing_the_carried_prefix_needs_its_own_settle(tmp_path):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    text = hop2.read_text(encoding="utf-8")
    heading = "## Findings that cost effort to discover\n\n"
    spoof = (
        "- [h2] UNVERIFIED (predecessor failed validation): the cache holds stale rows."
    )
    hop2.write_text(
        text.replace(heading, f"{heading}{spoof}\n", 1), encoding="utf-8", newline="\n"
    )
    result = run("validate", str(hop2))
    assert result.returncode == 1, out(result)
    assert any(
        "UNVERIFIED without naming what settles it" in line and "[h2]" in line
        for line in out(result).splitlines()
    ), out(result)


def test_an_earlier_tag_on_text_the_predecessor_never_held_needs_its_own_settle(
    tmp_path,
):
    hop2 = hop2_past_a_failed_predecessor(tmp_path)
    text = hop2.read_text(encoding="utf-8")
    heading = "## Findings that cost effort to discover\n\n"
    spoof = (
        "- [h1] UNVERIFIED (predecessor failed validation): the cache holds stale rows."
    )
    hop2.write_text(
        text.replace(heading, f"{heading}{spoof}\n", 1), encoding="utf-8", newline="\n"
    )
    result = run("validate", str(hop2))
    assert result.returncode == 1, out(result)
    assert "UNVERIFIED without naming what settles it" in out(result), out(result)


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
