"""Tests for parse_transcript.py --legs: metrics from sealed lane legs (gzipped stream-json arrays).

The leg is the hand-written `lane-legs/leg.json`, gzipped into tmp_path per test.
"""

from __future__ import annotations

import gzip
import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "parse_transcript.py"
LEG = Path(__file__).resolve().parent / "lane-legs" / "leg.json"


def write_leg(tmp_path: Path, name: str = "7-1-check-intent", strip_timestamps: bool = False) -> Path:
    messages = json.loads(LEG.read_text(encoding="utf-8"))
    if strip_timestamps:
        for message in messages:
            message.pop("timestamp", None)
    path = tmp_path / f"{name}.json.gz"
    path.write_bytes(gzip.compress(json.dumps(messages).encode("utf-8")))
    return path


def parse(*paths: Path | str) -> tuple[int, dict]:
    done = subprocess.run([sys.executable, str(SCRIPT), "--legs", *map(str, paths)], capture_output=True, text=True, timeout=30)
    return done.returncode, json.loads(done.stdout)


def only_data(tmp_path: Path, **kwargs) -> dict:
    code, out = parse(write_leg(tmp_path, **kwargs))
    assert code == 0, out
    (leg,) = out["legs"]
    return leg["data"]


def test_main_thread_metrics_leave_out_the_inline_subagent(tmp_path):
    data = only_data(tmp_path)

    assert data["tools"]["usage"] == {"Read": 1, "Agent": 1, "Edit": 1}
    assert data["tools"]["rejection_count"] == 0
    assert data["turns"]["assistant"] == 5
    assert data["turns"]["human_messages"] == 0
    assert data["session"]["models"] == ["model-a"]


def test_tokens_count_each_main_message_once(tmp_path):
    tokens = only_data(tmp_path)["tokens"]

    assert (tokens["total_input"], tokens["total_output"]) == (10 + 3 + 2 + 1, 40 + 30 + 50 + 12)


def test_the_inline_subagent_is_inventoried_with_its_own_tools_and_rejections(tmp_path):
    (sub,) = only_data(tmp_path)["subagents"]

    assert sub == {"id": "toolu_02", "type": "unknown", "description": "count widgets", "assistant_turns": 1, "tools": {"Bash": 1}, "rejection_count": 1}


def test_the_leg_carries_its_result_init_and_compaction(tmp_path):
    data = only_data(tmp_path)

    assert data["result"] == {"subtype": "success", "is_error": False, "num_turns": 4, "duration_ms": 66000, "api_error_status": None, "models": ["model-a", "model-b"], "permission_denials": 0}
    assert data["session"]["versions"] == ["9.9.1"]
    assert data["compactions"]["details"] == [{"timestamp": None, "trigger": "auto", "pre_tokens": 150000}]
    assert data["files_modified"] == ["config.yaml"]


def test_timing_comes_from_timestamps_when_the_messages_carry_them(tmp_path):
    data = only_data(tmp_path)

    assert data["timing_source"] == "timestamps"
    assert data["session"]["duration_minutes"] == 1.1
    assert data["turn_durations"]["count"] == 4


def test_without_timestamps_duration_comes_from_the_result_and_turn_timing_is_unavailable(tmp_path):
    data = only_data(tmp_path, strip_timestamps=True)

    assert data["timing_source"] == "result"
    assert data["session"]["duration_minutes"] == 1.1
    assert data["turn_durations"]["count"] == 0


def test_several_legs_aggregate(tmp_path):
    code, out = parse(write_leg(tmp_path, "7-1-a"), write_leg(tmp_path, "7-1-a-fallback"))

    assert code == 0
    assert [leg["id"] for leg in out["legs"]] == ["7-1-a", "7-1-a-fallback"]
    assert out["aggregate"]["total_output_tokens"] == 2 * 132
    assert out["aggregate"]["all_tools"] == {"Read": 2, "Agent": 2, "Edit": 2}


def test_a_missing_leg_is_reported_and_the_rest_still_parse(tmp_path):
    code, out = parse(write_leg(tmp_path), tmp_path / "gone.json.gz")

    assert (code, out["status"]) == (0, "warning")
    assert out["legs"][1]["transcript_present"] is False


def test_an_unreadable_leg_is_not_reported_as_a_zero_turn_run(tmp_path):
    broken = tmp_path / "7-1-broken.json.gz"
    broken.write_bytes(b"\x1f\x8b\x08\x00not-gzip")

    code, out = parse(write_leg(tmp_path), broken)
    only_code, only_out = parse(broken)

    assert (code, out["status"]) == (0, "warning")
    assert out["legs"][1]["transcript_present"] is False
    assert "unreadable" in out["legs"][1]["error"]
    assert (only_code, only_out["status"]) == (2, "error")


def test_no_leg_found_is_an_error(tmp_path):
    code, out = parse(tmp_path / "gone.json.gz")

    assert (code, out["status"]) == (2, "error")


def test_session_transcripts_keep_counting_sidechain_records_as_before(tmp_path):
    record = {"type": "assistant", "isSidechain": True, "message": {"id": "m", "content": [{"type": "tool_use", "name": "Bash", "input": {}}]}}
    (tmp_path / "s.jsonl").write_text(json.dumps(record) + "\n", encoding="utf-8")

    done = subprocess.run([sys.executable, str(SCRIPT), "s", str(tmp_path)], capture_output=True, text=True, timeout=30)

    assert json.loads(done.stdout)["data"]["tools"]["usage"] == {"Bash": 1}
