"""A journey read from a mid-chain handoff file, or from one branch of a fork, holds
that file and its older hops only. Expected values are the session ids and hop
numbers each test writes: hop k of a chain is session `SIDS[k - 1]`."""

from __future__ import annotations

import sys
from pathlib import Path

from shape4_chain import SIDS, s4_chain
from test_save_point import make_repo, s3_hop

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import handoff_chain  # noqa: E402
import parse_transcript  # noqa: E402


def walk(path: Path) -> tuple[list[int | None], list[str]]:
    found = handoff_chain.journey(path)
    return [hop.hop for hop in found.hops], found.session_ids


def test_journey_from_a_mid_chain_file_stops_at_that_hop(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 5)
    assert walk(paths[2]) == ([3, 2, 1], [SIDS[2], SIDS[1], SIDS[0]])
    base = tmp_path / "base"
    base.mkdir()
    assert parse_transcript.extract_chain_from_handoff(paths[2], base) == [
        SIDS[2],
        SIDS[1],
        SIDS[0],
    ]


def test_journey_from_the_tip_still_reads_every_hop(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 5)
    assert walk(paths[-1]) == ([5, 4, 3, 2, 1], list(reversed(SIDS)))


def test_journey_from_one_branch_of_a_fork_skips_the_other(tmp_path):
    repo = make_repo(tmp_path)
    first = s3_hop(repo, tmp_path, sid=SIDS[0], now="2026-09-01T10:00:00Z")
    second = s3_hop(repo, tmp_path, first, sid=SIDS[1], now="2026-09-02T10:00:00Z")
    left = s3_hop(repo, tmp_path, second, sid=SIDS[2], now="2026-09-03T10:00:00Z")
    right = s3_hop(repo, tmp_path, second, sid=SIDS[3], now="2026-09-04T10:00:00Z")
    right_tip = s3_hop(repo, tmp_path, right, sid=SIDS[4], now="2026-09-05T10:00:00Z")

    assert walk(left) == ([3, 2, 1], [SIDS[2], SIDS[1], SIDS[0]])
    assert walk(right_tip) == ([4, 3, 2, 1], [SIDS[4], SIDS[3], SIDS[1], SIDS[0]])
