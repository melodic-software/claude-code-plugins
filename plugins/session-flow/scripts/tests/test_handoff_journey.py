# test-scope: plugins/session-flow/scripts/tests/fixtures/*
"""Contract tests for reading a chain's journey: retro gets
every hop's Direction changes, This session and Observations from a shape-4 chain
whose sections moved to archive files, and a finished chain shrunk by `clean --apply`
keeps its newest handoff file, every archive file and every shape-2 handoff file, so every
session id comes back.
Expected values are the per-hop slot values `shape4_chain.hop_values` writes."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from shape4_chain import SIDS, hop_values, s4_chain
from test_save_point import edit, make_repo

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import parse_transcript  # noqa: E402

CLOSED = "Next: none (closed)"


def assert_hop_sections(journey: list[dict], hops: int) -> None:
    by_hop = {entry["hop"]: entry for entry in journey}
    assert sorted(by_hop) == list(range(1, hops + 1))
    for k in range(1, hops + 1):
        values = hop_values(k)
        sections = by_hop[k]["sections"]
        assert by_hop[k]["session_id"] == SIDS[k - 1]
        assert by_hop[k]["date"] == f"2026-09-0{k}T10:00:00Z"
        assert sections["Observations"] == [values["observations"]]
        assert sections["This session"][0] == (
            f"did: {values['did']} · left: {values['left']}"
        )
        if k > 1:
            assert values["trail-new"] in sections["Direction changes"]


def test_parse_transcript_recovers_each_hops_moved_sections(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 5)
    tip = paths[-1].read_text(encoding="utf-8")
    assert "- Folded: " in tip, "hop 5 folds hop 1's direction line out"
    assert "Hop 5 observation" not in tip, "hop 5's Observations moved"
    journey = parse_transcript.handoff_journey(paths[-1])
    assert_hop_sections(journey, 5)
    assert [e["hop"] for e in journey] == [5, 4, 3, 2, 1]


def test_chain_from_output_carries_the_journey(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 3)
    base = tmp_path / "base"
    base.mkdir()
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "parse_transcript.py"),
            "--chain-from",
            str(paths[-1]),
            "--base",
            str(base),
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    output = json.loads(result.stdout)
    assert_hop_sections(output["handoff_journey"], 3)


def shrink(tmp_path: Path, paths: list[Path]) -> subprocess.CompletedProcess[str]:
    """Close the chain at its newest handoff file, age every file past the window,
    give each handoff file a merged PR, and run `clean --apply`."""
    edit(paths[-1], "Next:\nDo the next thing\n", f"{CLOSED}\n")
    stamp = 1_700_000_000
    for path in paths:
        edit(path, "None. No command waits on the user.", "None. PR #7 shipped it.")
    for base, dirs, files in os.walk(paths[0].parent):
        for name in (*dirs, *files):
            os.utime(os.path.join(base, name), (stamp, stamp))
    for k, path in enumerate(paths):
        os.utime(path, (stamp + k * 86400, stamp + k * 86400))
    state = tmp_path / "links.json"
    state.write_text(json.dumps({"#7": "merged"}), encoding="utf-8")
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "tidy_work.py"),
            "clean",
            "--link-state",
            str(state),
            "--apply",
        ],
        cwd=paths[0].parent.parent.parent,
        env={**os.environ, "HOME": str(home)},
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_a_shrunk_finished_chain_gives_back_every_session_id(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 5)
    result = shrink(tmp_path, paths)
    assert result.returncode == 0, result.stdout + result.stderr
    assert [p.exists() for p in paths] == [False, False, False, False, True]
    archive = paths[0].parent / "archive" / paths[0].name[:-3]
    assert len(list(archive.glob("h*.md"))) == 5
    base = tmp_path / "base"
    base.mkdir()
    assert parse_transcript.extract_chain_from_handoff(paths[-1], base) == list(
        reversed(SIDS)
    )
    assert_hop_sections(parse_transcript.handoff_journey(paths[-1]), 5)


def test_a_shrunk_2_to_3_to_4_chain_keeps_its_shape2_hot_files(tmp_path):
    """No archive file holds a shape-2 hop's sections, so the shrink keeps every
    shape-2 handoff file and the journey still reaches each session id."""
    from test_save_point import model_fill
    from test_save_point_shape4_writer import hop, new

    repo = make_repo(tmp_path)
    paths: list[Path] = []
    for k in (1, 2, 3):
        made = new(repo, tmp_path, paths[-1] if paths else None, k=k, shape="2")
        assert made.returncode == 0, made.stderr
        path = Path(made.stdout.decode().strip())
        text = model_fill(path.read_text(encoding="utf-8"))
        path.write_text(
            text + "\nNone. No command waits on the user.\n", encoding="utf-8"
        )
        paths.append(path)
    paths.append(hop(repo, tmp_path, paths[-1], k=4, shape="3"))
    paths.append(hop(repo, tmp_path, paths[-1], k=5, shape="4"))
    result = shrink(tmp_path, paths)
    assert result.returncode == 0, result.stdout + result.stderr
    assert [p.exists() for p in paths] == [True, True, True, False, True], result.stdout
    base = tmp_path / "base"
    base.mkdir()
    assert parse_transcript.extract_chain_from_handoff(paths[-1], base) == list(
        reversed(SIDS)
    )
    journey = parse_transcript.handoff_journey(paths[-1])
    assert sorted(e["session_id"] for e in journey) == sorted(SIDS)
