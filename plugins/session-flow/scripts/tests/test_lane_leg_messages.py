"""Tests for lane_leg_messages.py: a sealed lane leg's messages, one per line with their array index."""

from __future__ import annotations

import gzip
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "lane_leg_messages.py"
LEG = Path(__file__).resolve().parent / "lane-legs" / "leg.json"


def sealed(tmp_path: Path, text: str | None = None) -> Path:
    path = tmp_path / "7-1-a.json.gz"
    path.write_bytes(gzip.compress((LEG.read_text(encoding="utf-8") if text is None else text).encode("utf-8")))
    return path


def show(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, timeout=30)


def lines(done: subprocess.CompletedProcess[str]) -> list[tuple[int, dict]]:
    return [(int(i), json.loads(body)) for i, body in (line.split("\t", 1) for line in done.stdout.splitlines())]


def test_every_message_prints_with_its_index(tmp_path):
    done = show(str(sealed(tmp_path)))

    got = lines(done)
    assert done.returncode == 0
    assert [i for i, _ in got] == list(range(14))
    assert got[0][1]["subtype"] == "init"
    assert got[13][1]["type"] == "result"


def test_a_range_prints_only_those_indexes(tmp_path):
    got = lines(show(str(sealed(tmp_path)), "--from", "3", "--to", "5"))

    assert [i for i, _ in got] == [3, 4, 5]


def test_a_message_prints_as_stored(tmp_path):
    (_, message), = lines(show(str(sealed(tmp_path)), "--from", "3", "--to", "3"))

    assert message == json.loads(LEG.read_text(encoding="utf-8"))[3]


def test_a_non_object_item_keeps_its_index_and_prints_as_is(tmp_path):
    got = lines(show(str(sealed(tmp_path, '[{"type": "user"}, 3]'))))

    assert got == [(0, {"type": "user"}), (1, 3)]


def test_an_unreadable_leg_exits_2(tmp_path):
    broken = tmp_path / "x.json.gz"
    broken.write_bytes(b"\x1f\x8b\x08\x00not-gzip")

    assert show(str(broken)).returncode == 2
    assert show(str(tmp_path / "absent.json.gz")).returncode == 2
