"""Tests for hop_chain.load_transcript: a hop's transcript read through the shared reader.

Fixtures are written to tmp_path per test, so no transcript on this machine is read.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1] / "harness" / "hop_chain.py"
SESSION_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"


def load_hop_chain():
    spec = importlib.util.spec_from_file_location("hop_chain_under_test", HARNESS)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # Registered before execution: `dataclasses` resolves a field annotation
    # through `sys.modules[cls.__module__]`, which is absent otherwise.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


hop_chain = load_hop_chain()


def write_transcript(projects_root: Path, session_id: str, chunks: list[bytes]) -> Path:
    path = projects_root / "-work-repo" / f"{session_id}.jsonl"
    path.parent.mkdir(parents=True)
    path.write_bytes(b"".join(chunks))
    return path


def test_drops_a_non_object_line_and_replaces_invalid_utf8(tmp_path):
    path = write_transcript(
        tmp_path,
        SESSION_ID,
        [
            json.dumps({"type": "user", "message": {"content": "first"}}).encode() + b"\n",
            b"[1, 2, 3]\n",
            b'{"type": "assistant", "text": "bad \xff\xfe bytes"}\n',
            json.dumps({"type": "user", "message": {"content": "last"}}).encode() + b"\n",
        ],
    )

    transcript = hop_chain.load_transcript(SESSION_ID, tmp_path)

    assert transcript.found
    assert transcript.path == path
    assert [record["type"] for record in transcript.records] == ["user", "assistant", "user"]
    assert all(isinstance(record, dict) for record in transcript.records)
    assert transcript.records[1]["text"] == "bad �� bytes"


def test_a_session_id_with_no_transcript_is_an_empty_transcript(tmp_path):
    write_transcript(tmp_path, SESSION_ID, [b'{"type": "user"}\n'])

    transcript = hop_chain.load_transcript("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", tmp_path)

    assert not transcript.found
    assert transcript.path is None
    assert transcript.records == []
