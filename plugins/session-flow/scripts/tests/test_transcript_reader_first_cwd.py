"""Tests for transcript_reader.first_cwd: the launch directory a transcript records.

Fixtures are written to tmp_path per test, so no transcript on this machine is read.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import transcript_reader  # noqa: E402


def write_jsonl(path: Path, lines: list[object]) -> Path:
    path.write_text("".join((x if isinstance(x, str) else json.dumps(x)) + "\n" for x in lines), encoding="utf-8")
    return path


def test_returns_the_cwd_of_the_first_record_that_has_one(tmp_path):
    path = write_jsonl(
        tmp_path / "s.jsonl",
        [
            {"type": "permission-mode", "permissionMode": "default"},
            {"type": "user", "cwd": "/work/invoices", "message": {"content": "hi"}},
            {"type": "assistant", "cwd": "/work/invoices/api"},
        ],
    )

    assert transcript_reader.first_cwd(path) == "/work/invoices"


def test_skips_records_whose_cwd_is_empty_or_not_a_string(tmp_path):
    path = write_jsonl(
        tmp_path / "s.jsonl",
        [
            {"type": "user", "cwd": ""},
            {"type": "user", "cwd": 7},
            "not json at all",
            {"type": "user", "cwd": "C:\\work\\ledger"},
        ],
    )

    assert transcript_reader.first_cwd(path) == "C:\\work\\ledger"


def test_returns_none_when_no_record_has_a_cwd(tmp_path):
    path = write_jsonl(tmp_path / "s.jsonl", [{"type": "user"}, {"type": "assistant", "message": {}}])

    assert transcript_reader.first_cwd(path) is None


def test_returns_none_for_an_empty_file(tmp_path):
    path = tmp_path / "s.jsonl"
    path.write_text("", encoding="utf-8")

    assert transcript_reader.first_cwd(path) is None


def test_reads_no_record_after_the_first_cwd(tmp_path, monkeypatch):
    path = write_jsonl(
        tmp_path / "s.jsonl",
        [{"type": "user"}, {"type": "user", "cwd": "/work/a"}, {"type": "user", "cwd": "/work/b"}, {"type": "user"}],
    )
    real = transcript_reader.iter_records
    pulled: list[dict] = []

    def counting(p, stats=None):
        for record in real(p, stats):
            pulled.append(record)
            yield record

    monkeypatch.setattr(transcript_reader, "iter_records", counting)

    assert transcript_reader.first_cwd(path) == "/work/a"
    assert len(pulled) == 2
