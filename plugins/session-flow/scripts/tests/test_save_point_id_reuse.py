"""Contract tests for the `id_reuse` check (PLAN.md AC2): a handoff file stamped
`checks: 3` or higher that reuses an id retired anywhere earlier in its chain for a
different entry fails `validate`. Expected values come from AC2's wording and the
Design's check rules: same id with different text fails, same text does not, and an
older stamp keeps its old verdict."""

from __future__ import annotations

import re
from pathlib import Path

import pytest
from test_save_point import (
    HOP1,
    ID_VALUES,
    QUESTION,
    SID_A,
    SID_B,
    SID_C,
    SID_D,
    edit,
    hop_file,
    make_repo,
    out,
    retire_by_hand,
    s3_hop,
    strict,
)

RULE = "- [R2] Never push to main."
REUSED_RULE = "- [R2] Always rebase before merging."
KEPT_RULE = "- [R1] The thing must stay green.\n"
LISTINGS = {
    "entry-then-reason": f"\n## Retired rules\n\n{RULE}\nRetired: main now has a branch rule.\n",
    "one-line-reason": "\n## Retired rules\n\n- [R2] main now has a branch rule.\n",
}


def _id_reuse_lines(result) -> list[str]:
    return [
        line
        for line in out(result).splitlines()
        if line.startswith("FAIL: ") and "id_reuse" in line
    ]


def _with_transcript(tmp_path: Path, sid: str) -> None:
    """A transcript for `sid` beside the fixture ones, so its hop validates strict."""
    projects = tmp_path / "projects" / "-work-repo"
    (projects / f"{sid}.jsonl").write_bytes((projects / f"{SID_C}.jsonl").read_bytes())


def _restamp(path: Path, checks: int) -> None:
    text = path.read_text(encoding="utf-8")
    path.write_text(
        re.sub(r"^checks: \d+$", f"checks: {checks}", text, count=1, flags=re.M),
        encoding="utf-8",
        newline="\n",
    )


def rule_retired_at_hop2(tmp_path: Path, listing: str) -> Path:
    """Hops 1 to 4 of one shape-3 chain: [R2] retired at hop 2, hops 3 and 4 carry
    only [R1]; returns hop 4, which validates clean."""
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    hop1 = s3_hop(repo, tmp_path, sid=SID_A, now="2026-09-01T10:00:00Z")
    hop2 = s3_hop(repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z")
    edit(hop2, RULE + "\n", "")
    with hop_file(handoffs, HOP1, 2, SID_B).open(
        "a", encoding="utf-8", newline="\n"
    ) as fh:
        fh.write(listing)
    assert strict(hop2).returncode == 0, out(strict(hop2))
    hop3 = s3_hop(repo, tmp_path, hop2, sid=SID_C, now="2026-09-03T10:00:00Z")
    assert strict(hop3).returncode == 0, out(strict(hop3))
    _with_transcript(tmp_path, SID_D)
    hop4 = s3_hop(repo, tmp_path, hop3, sid=SID_D, now="2026-09-04T10:00:00Z")
    assert RULE not in hop4.read_text(encoding="utf-8")
    clean = strict(hop4)
    assert clean.returncode == 0, out(clean)
    return hop4


@pytest.mark.parametrize("listing", sorted(LISTINGS))
def test_a_rule_id_retired_two_hops_back_and_reused_for_another_rule_fails(
    tmp_path, listing
):
    hop4 = rule_retired_at_hop2(tmp_path, LISTINGS[listing])
    edit(hop4, KEPT_RULE, KEPT_RULE + REUSED_RULE + "\n")
    result = strict(hop4)
    assert result.returncode == 1, out(result)
    flagged = _id_reuse_lines(result)
    assert len(flagged) == 1 and "[R2]" in flagged[0], out(result)


def test_a_retired_rule_id_brought_back_with_its_own_text_is_no_reuse(tmp_path):
    hop4 = rule_retired_at_hop2(tmp_path, LISTINGS["entry-then-reason"])
    edit(hop4, KEPT_RULE, KEPT_RULE + RULE + "\n")
    result = strict(hop4)
    assert _id_reuse_lines(result) == [], out(result)
    assert result.returncode == 0, out(result)


def test_a_file_stamped_below_3_keeps_its_verdict_on_a_reused_id(tmp_path):
    hop4 = rule_retired_at_hop2(tmp_path, LISTINGS["entry-then-reason"])
    edit(hop4, KEPT_RULE, KEPT_RULE + REUSED_RULE + "\n")
    _restamp(hop4, 2)
    result = strict(hop4)
    assert result.returncode == 0, out(result)
    assert _id_reuse_lines(result) == [], out(result)


def test_writers_stamp_checks_3(tmp_path):
    hop1 = s3_hop(make_repo(tmp_path), tmp_path)
    assert re.search(r"^checks: 3$", hop1.read_text(encoding="utf-8"), re.M)


def test_a_question_id_retired_at_the_previous_hop_and_reused_fails(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    hop1 = s3_hop(repo, tmp_path, values=ID_VALUES)
    hop2 = s3_hop(
        repo, tmp_path, hop1, sid=SID_B, now="2026-09-02T10:00:00Z", values=ID_VALUES
    )
    hop3 = s3_hop(
        repo, tmp_path, hop2, sid=SID_C, now="2026-09-03T10:00:00Z", values=ID_VALUES
    )
    retire_by_hand(
        hop3,
        hop_file(handoffs, HOP1, 3, SID_C),
        "Retired open questions",
        QUESTION,
        "blue was chosen",
    )
    edit(
        hop3,
        "## Open questions\n\n",
        "## Open questions\n\nNone. The color is settled.\n",
    )
    assert strict(hop3).returncode == 0, out(strict(hop3))
    _with_transcript(tmp_path, SID_D)
    hop4 = s3_hop(repo, tmp_path, hop3, sid=SID_D, now="2026-09-04T10:00:00Z")
    assert strict(hop4).returncode == 0, out(strict(hop4))
    edit(
        hop4,
        "None. Nothing is unknown.",
        "- [Q1] Which size? Options S or M; recommend S; unblocks the cut.",
    )
    result = strict(hop4)
    assert result.returncode == 1, out(result)
    flagged = _id_reuse_lines(result)
    assert len(flagged) == 1 and "[Q1]" in flagged[0], out(result)
