"""Tests for parse_transcript.py — output contract and edge case coverage.

Runs the script as a subprocess to test the CLI interface, not internals.
Following python/testing.md "Testing standalone scripts" pattern.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).parent / "parse_transcript.py"
SESSION_ID = "test-session"


def _run_script(session_id: str, base_path: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), session_id, base_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def _run_with_event(tmp_path: Path, event: dict) -> dict:
    """Write a single JSONL event and return the parsed `data` dict from stdout."""
    (tmp_path / f"{SESSION_ID}.jsonl").write_text(json.dumps(event) + "\n")
    result = _run_script(SESSION_ID, str(tmp_path))
    result.check_returncode()
    return json.loads(result.stdout)["data"]


def test_missing_args():
    """No arguments produces error status with exit code 2."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    output = json.loads(result.stdout)
    assert output["status"] == "error"
    assert result.returncode == 2


def test_nonexistent_session(tmp_path):
    """Nonexistent session ID produces error status."""
    result = _run_script("nonexistent-session", str(tmp_path))
    output = json.loads(result.stdout)
    assert output["status"] == "error"
    assert result.returncode == 2


def test_empty_jsonl(tmp_path):
    """Empty JSONL file produces pass status with zero counts."""
    jsonl = tmp_path / f"{SESSION_ID}.jsonl"
    jsonl.write_text("")
    result = _run_script(SESSION_ID, str(tmp_path))
    output = json.loads(result.stdout)
    assert output["status"] == "pass"
    assert output["data"]["turns"]["assistant"] == 0


def test_single_assistant_turn_extracts_cache_tokens(tmp_path):
    """Cache tokens are extracted from usage data."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "message": {
                "model": "claude-opus-4-6",
                "content": [{"type": "tool_use", "name": "Read", "id": "123"}],
                "stop_reason": "tool_use",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50,
                    "cache_creation_input_tokens": 500,
                    "cache_read_input_tokens": 10000,
                },
            },
            "version": "2.1.81",
            "gitBranch": "main",
        },
    )
    assert data["tokens"]["cache_creation"] == 500
    assert data["tokens"]["cache_read"] == 10000
    assert data["tokens"]["total_context"] == 10600
    assert data["tokens"]["total_input"] == 100
    assert data["tokens"]["total_output"] == 50
    assert data["tools"]["usage"]["Read"] == 1


def test_assistant_turn_with_null_usage(tmp_path):
    """Null usage field does not crash token extraction."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "message": {
                "model": "claude-opus-4-6",
                "content": [{"type": "text", "text": "hi"}],
                "stop_reason": "end_turn",
                "usage": None,
            },
            "version": "2.1.81",
            "gitBranch": "main",
        },
    )
    assert data["turns"]["assistant"] == 1
    assert data["tokens"]["total_input"] == 0
    assert data["tokens"]["total_output"] == 0


def test_write_edit_file_paths_extracted(tmp_path):
    """File paths from Write/Edit tool_use inputs are captured in files_modified."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "id": "w1",
                        "input": {"file_path": "/tmp/test.py", "content": "hello"},
                    }
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert "/tmp/test.py" in data["files_modified"]


def test_files_modified_dedups_relative_and_absolute_posix(tmp_path):
    """Same file referenced as relative + absolute under cwd dedups to one entry."""
    cwd = str(tmp_path)
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "cwd": cwd,
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "id": "w1",
                        "input": {"file_path": "CLAUDE.md", "content": "x"},
                    },
                    {
                        "type": "tool_use",
                        "name": "Edit",
                        "id": "e1",
                        "input": {
                            "file_path": f"{cwd}/CLAUDE.md",
                            "old_string": "a",
                            "new_string": "b",
                        },
                    },
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert data["files_modified"] == ["CLAUDE.md"]


def test_files_modified_dedups_windows_backslash_absolute(tmp_path):
    """Windows-style absolute path collapses to relative form against Windows cwd."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "cwd": "C:\\Projects\\example",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "id": "w1",
                        "input": {"file_path": "CLAUDE.md", "content": "x"},
                    },
                    {
                        "type": "tool_use",
                        "name": "Edit",
                        "id": "e1",
                        "input": {
                            "file_path": "C:\\Projects\\example\\CLAUDE.md",
                            "old_string": "a",
                            "new_string": "b",
                        },
                    },
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert data["files_modified"] == ["CLAUDE.md"]


def test_files_modified_keeps_path_outside_cwd(tmp_path):
    """Absolute path outside cwd is preserved (not stripped or dropped)."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "cwd": str(tmp_path),
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "id": "w1",
                        "input": {"file_path": "/etc/hosts", "content": "x"},
                    },
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert "/etc/hosts" in data["files_modified"]


def test_files_modified_snapshot_dedups_with_write_event(tmp_path):
    """file-history-snapshot absolute path deduplicates against a Write relative path."""
    cwd = str(tmp_path)
    events = [
        json.dumps(
            {
                "type": "assistant",
                "timestamp": "2026-03-23T18:00:00Z",
                "cwd": cwd,
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Write",
                            "id": "w1",
                            "input": {"file_path": "README.md", "content": "x"},
                        }
                    ],
                    "usage": {"input_tokens": 0, "output_tokens": 0},
                },
            }
        ),
        json.dumps(
            {
                "type": "file-history-snapshot",
                "timestamp": "2026-03-23T18:00:01Z",
                "snapshot": {
                    "trackedFileBackups": {
                        f"{cwd}/README.md": "backup-content",
                    }
                },
            }
        ),
    ]
    jsonl = tmp_path / f"{SESSION_ID}.jsonl"
    jsonl.write_text("\n".join(events) + "\n")
    data = json.loads(_run_script(SESSION_ID, str(tmp_path)).stdout)["data"]
    assert data["files_modified"] == ["README.md"]


def test_files_modified_no_cwd_keeps_paths_unchanged(tmp_path):
    """No cwd in any event: paths survive normalization unchanged."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "id": "w1",
                        "input": {"file_path": "/tmp/test.py", "content": "x"},
                    },
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert "/tmp/test.py" in data["files_modified"]


def test_queue_operation_counted(tmp_path):
    """queue-operation enqueue events are counted."""
    events = [
        json.dumps(
            {
                "type": "queue-operation",
                "operation": "enqueue",
                "timestamp": "2026-03-23T18:00:00Z",
                "content": "user message",
            }
        ),
        json.dumps(
            {
                "type": "queue-operation",
                "operation": "remove",
                "timestamp": "2026-03-23T18:00:01Z",
            }
        ),
    ]
    jsonl = tmp_path / f"{SESSION_ID}.jsonl"
    jsonl.write_text("\n".join(events) + "\n")
    data = json.loads(_run_script(SESSION_ID, str(tmp_path)).stdout)["data"]
    assert data["queued_user_messages"] == 1


def test_except_syntax_handles_non_string_timestamp(tmp_path):
    """Non-string timestamp doesn't crash (Python 2 except syntax regression)."""
    _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": 12345,
            "message": {"content": [], "usage": {}},
        },
    )


def test_turn_durations_derived_from_assistant_timestamps(tmp_path):
    """N assistant events yield N-1 turn durations derived from timestamp deltas.

    Replaces reliance on CC's sparse system.turn_duration events
    (empirically 0-5 per session vs hundreds of assistant turns).
    """
    events = [
        json.dumps(
            {
                "type": "assistant",
                "timestamp": f"2026-05-23T01:38:{secs:02d}.000Z",
                "message": {"content": [], "usage": {}},
            }
        )
        for secs in (10, 15, 30, 45)
    ]
    jsonl = tmp_path / f"{SESSION_ID}.jsonl"
    jsonl.write_text("\n".join(events) + "\n")
    data = json.loads(_run_script(SESSION_ID, str(tmp_path)).stdout)["data"]
    assert data["turns"]["assistant"] == 4
    assert data["turn_durations"]["count"] == 3
    assert data["turn_durations"]["min_ms"] == 5000
    assert data["turn_durations"]["max_ms"] == 15000
    assert data["turn_durations"]["total_ms"] == 35000


def test_turn_durations_zero_when_single_turn(tmp_path):
    """A single assistant turn yields zero deltas (no pairs)."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-05-23T01:38:00.000Z",
            "message": {"content": [], "usage": {}},
        },
    )
    assert data["turn_durations"]["count"] == 0


def test_output_contract_has_required_keys(tmp_path):
    """Output JSON has all required top-level and nested keys."""
    # Re-run to capture full stdout (including status/summary), since
    # _run_with_event only returns the inner data dict.
    (tmp_path / f"{SESSION_ID}.jsonl").write_text(
        json.dumps(
            {
                "type": "assistant",
                "timestamp": "2026-03-23T18:00:00Z",
                "message": {
                    "model": "claude-opus-4-6",
                    "content": [],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 10, "output_tokens": 5},
                },
            }
        )
        + "\n"
    )
    output = json.loads(_run_script(SESSION_ID, str(tmp_path)).stdout)

    assert "status" in output
    assert "summary" in output
    assert "data" in output
    data = output["data"]
    assert "session" in data
    assert "turns" in data
    assert "tokens" in data
    assert "tools" in data
    assert "compactions" in data
    assert "files_modified" in data
    assert "subagents" in data
    assert "queued_user_messages" in data

    tokens = data["tokens"]
    assert "total_input" in tokens
    assert "total_output" in tokens
    assert "cache_creation" in tokens
    assert "cache_read" in tokens
    assert "total_context" in tokens

    assert "cwd" not in data["session"]


# -----------------------------------------------------------------------------
# Multi-session tests (Phase C — retro-pre-commit-chain)
# -----------------------------------------------------------------------------


def _write_assistant_event(
    tmp_path: Path, session_id: str, ts: str = "2026-05-23T00:00:00Z"
):
    """Write a minimal valid JSONL for the given session."""
    event = {
        "type": "assistant",
        "timestamp": ts,
        "message": {
            "model": "claude-opus-4-7",
            "content": [{"type": "tool_use", "name": "Read", "id": "x"}],
            "stop_reason": "tool_use",
            "usage": {
                "input_tokens": 10,
                "output_tokens": 5,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0,
            },
        },
    }
    (tmp_path / f"{session_id}.jsonl").write_text(json.dumps(event) + "\n")


def _run_multi(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_multi_session_all_present(tmp_path):
    """--sessions with N transcripts present → status=pass, aggregate populated."""
    _write_assistant_event(tmp_path, "sid-curr")
    _write_assistant_event(tmp_path, "sid-prev")
    result = _run_multi(["--sessions", "sid-curr", "sid-prev", "--base", str(tmp_path)])
    result.check_returncode()
    output = json.loads(result.stdout)
    assert output["status"] == "pass"
    assert len(output["sessions"]) == 2
    assert output["sessions"][0]["role"] == "current"
    assert output["sessions"][0]["id"] == "sid-curr"
    assert output["sessions"][1]["role"] == "previous"
    assert output["sessions"][1]["id"] == "sid-prev"
    assert output["sessions"][0]["transcript_present"] is True
    assert output["sessions"][1]["transcript_present"] is True
    agg = output["aggregate"]
    # 2 sessions x 1 assistant turn each = 2
    assert agg["total_assistant_turns"] == 2
    assert agg["total_input_tokens"] == 20
    assert agg["total_output_tokens"] == 10
    assert "Read" in agg["all_tools"]


def test_multi_session_one_missing(tmp_path):
    """--sessions with one transcript absent → status=warning, partial aggregate."""
    _write_assistant_event(tmp_path, "sid-curr")
    # sid-prev intentionally missing
    result = _run_multi(
        ["--sessions", "sid-curr", "sid-prev-missing", "--base", str(tmp_path)]
    )
    assert result.returncode == 0  # warning still exits 0
    output = json.loads(result.stdout)
    assert output["status"] == "warning"
    assert output["sessions"][0]["transcript_present"] is True
    assert output["sessions"][1]["transcript_present"] is False
    assert "error" in output["sessions"][1]
    # Aggregate counts only the present transcript
    assert output["aggregate"]["total_assistant_turns"] == 1


def test_multi_session_all_missing_is_error(tmp_path):
    """--sessions where every transcript is absent → status=error, exit 2."""
    result = _run_multi(
        ["--sessions", "sid-gone-a", "sid-gone-b", "--base", str(tmp_path)]
    )
    assert result.returncode == 2
    output = json.loads(result.stdout)
    assert output["status"] == "error"
    assert all(s["transcript_present"] is False for s in output["sessions"])


def test_notebook_edit_counts_as_file_modification(tmp_path):
    """NotebookEdit tool_use file_path lands in files_modified."""
    data = _run_with_event(
        tmp_path,
        {
            "type": "assistant",
            "timestamp": "2026-03-23T18:00:00Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "NotebookEdit",
                        "id": "n1",
                        "input": {"file_path": "analysis.ipynb", "new_source": "x"},
                    }
                ],
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        },
    )
    assert "analysis.ipynb" in data["files_modified"]


def test_multi_session_subagent_per_session_tagging(tmp_path):
    """Subagents from each session are tagged with session_id in the aggregate."""
    _write_assistant_event(tmp_path, "sid-a")
    _write_assistant_event(tmp_path, "sid-b")

    # Seed subagents per session — parse_subagents reads <agent>.meta.json files,
    # mirroring ~/.claude/projects/<slug>/<sid>/subagents/<agent-id>.meta.json shape
    for sid in ("sid-a", "sid-b"):
        sub_dir = tmp_path / sid / "subagents"
        sub_dir.mkdir(parents=True, exist_ok=True)
        (sub_dir / f"sub-{sid}.meta.json").write_text(
            json.dumps(
                {
                    "agentType": "explore",
                    "description": f"explore-from-{sid}",
                }
            )
        )

    result = _run_multi(["--sessions", "sid-a", "sid-b", "--base", str(tmp_path)])
    result.check_returncode()
    output = json.loads(result.stdout)
    all_subs = output["aggregate"]["all_subagents"]
    # Each subagent entry MUST carry session_id of its origin
    sids_seen = {sub["session_id"] for sub in all_subs}
    assert "sid-a" in sids_seen
    assert "sid-b" in sids_seen


def test_chain_from_walks_handoff_pointers(tmp_path):
    """--chain-from reads handoff journal-entry frontmatter + walks backwards."""
    # Subdir-prefixed layout: pointers keep a journal/ prefix
    slug = "test-slug"
    journal_dir = tmp_path / "work-notes" / slug / "journal"
    journal_dir.mkdir(parents=True)

    # Older handoff first
    (journal_dir / "20260520T100000Z-handoff-alpha.md").write_text(
        "---\ntype: handoff\nsession_id: sid-oldest\n---\nbody\n"
    )
    # Newer handoff points at the older one
    (journal_dir / "20260521T110000Z-handoff-beta.md").write_text(
        "---\ntype: handoff\nsession_id: sid-middle\n"
        "previous_handoff: journal/20260520T100000Z-handoff-alpha.md\n"
        "previous_session_id: sid-oldest\n---\nbody\n"
    )

    # Seed transcripts for chained SIDs
    base = tmp_path / "session-data"
    base.mkdir()
    _write_assistant_event(base, "sid-middle")
    _write_assistant_event(base, "sid-oldest")

    handoff_file = journal_dir / "20260521T110000Z-handoff-beta.md"
    result = _run_multi(["--chain-from", str(handoff_file), "--base", str(base)])
    assert result.returncode == 0, result.stderr
    output = json.loads(result.stdout)
    # Chain-walker emits the newest handoff's session_id first, then walks back
    sids = [s["id"] for s in output["sessions"]]
    assert "sid-middle" in sids
    assert "sid-oldest" in sids


def test_chain_from_walks_flat_layout_pointers(tmp_path):
    """--chain-from resolves previous_handoff as a sibling filename (flat handoffs dir)."""
    handoffs_dir = tmp_path / ".claude" / "handoffs"
    handoffs_dir.mkdir(parents=True)

    (handoffs_dir / "20260520T100000Z-handoff-alpha.md").write_text(
        "---\ntype: handoff\nsession_id: sid-oldest\n---\nbody\n"
    )
    (handoffs_dir / "20260521T110000Z-handoff-beta.md").write_text(
        "---\ntype: handoff\nsession_id: sid-middle\n"
        "previous_handoff: 20260520T100000Z-handoff-alpha.md\n"
        "previous_session_id: sid-oldest\n---\nbody\n"
    )

    base = tmp_path / "session-data"
    base.mkdir()
    _write_assistant_event(base, "sid-middle")
    _write_assistant_event(base, "sid-oldest")

    handoff_file = handoffs_dir / "20260521T110000Z-handoff-beta.md"
    result = _run_multi(["--chain-from", str(handoff_file), "--base", str(base)])
    assert result.returncode == 0, result.stderr
    output = json.loads(result.stdout)
    sids = [s["id"] for s in output["sessions"]]
    assert "sid-middle" in sids
    assert "sid-oldest" in sids


def test_chain_from_with_current_session_prepend(tmp_path):
    """--current-session prepends as first SID when not already in chain."""
    slug = "test-slug"
    journal_dir = tmp_path / "work-notes" / slug / "journal"
    journal_dir.mkdir(parents=True)
    (journal_dir / "20260521T110000Z-handoff-alpha.md").write_text(
        "---\ntype: handoff\nsession_id: sid-prior\n---\nbody\n"
    )

    base = tmp_path / "session-data"
    base.mkdir()
    _write_assistant_event(base, "sid-current")
    _write_assistant_event(base, "sid-prior")

    handoff_file = journal_dir / "20260521T110000Z-handoff-alpha.md"
    result = _run_multi(
        [
            "--chain-from",
            str(handoff_file),
            "--current-session",
            "sid-current",
            "--base",
            str(base),
        ]
    )
    assert result.returncode == 0, result.stderr
    output = json.loads(result.stdout)
    assert output["sessions"][0]["id"] == "sid-current"
    assert output["sessions"][0]["role"] == "current"
    assert output["sessions"][1]["id"] == "sid-prior"


def test_chain_from_handoff_without_session_id(tmp_path):
    """Handoff entry without session_id frontmatter → chain breaks at that entry."""
    slug = "test-slug"
    journal_dir = tmp_path / "work-notes" / slug / "journal"
    journal_dir.mkdir(parents=True)
    (journal_dir / "20260521T110000Z-handoff-preshape.md").write_text(
        "---\ntype: handoff\n---\nbody\n"
    )

    base = tmp_path / "session-data"
    base.mkdir()

    handoff_file = journal_dir / "20260521T110000Z-handoff-preshape.md"
    result = _run_multi(["--chain-from", str(handoff_file), "--base", str(base)])
    output = json.loads(result.stdout)
    # No SIDs extracted from the pre-shape entry → empty sessions list → error status
    assert output["status"] == "error"


def test_chain_from_nonexistent_file_errors(tmp_path):
    """Missing --chain-from file → exit 2."""
    result = _run_multi(
        [
            "--chain-from",
            str(tmp_path / "nonexistent.md"),
            "--base",
            str(tmp_path),
        ]
    )
    assert result.returncode == 2


def test_legacy_positional_still_works(tmp_path):
    """Positional form preserves existing single-session output shape."""
    _write_assistant_event(tmp_path, "legacy-sid")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "legacy-sid", str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    result.check_returncode()
    output = json.loads(result.stdout)
    # Single-session shape has "data" key (NOT "sessions" + "aggregate")
    assert "data" in output
    assert "sessions" not in output
    assert "aggregate" not in output
