from __future__ import annotations

import gzip
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import transcript_reader  # noqa: E402

LEG = Path(__file__).resolve().parent / "lane-legs" / "leg.json"


def sealed(tmp_path: Path, text: str | None = None) -> Path:
    path = tmp_path / "1-1-check-intent.json.gz"
    path.write_bytes(gzip.compress((LEG.read_text(encoding="utf-8") if text is None else text).encode("utf-8")))
    return path


def records(path: Path, stats: dict | None = None) -> list[dict]:
    return list(transcript_reader.iter_records(path, stats))


def test_a_gzipped_array_yields_each_message_as_a_record(tmp_path):
    stats: dict[str, int] = {}

    got = records(sealed(tmp_path), stats)

    assert [r["type"] for r in got][:3] == ["system", "assistant", "assistant"]
    assert stats == {"records": 14, "bad_lines": 0, "incomplete": 0, "unknown": 0}


def test_a_plain_array_reads_the_same_as_a_gzipped_one(tmp_path):
    plain = tmp_path / "leg.json"
    plain.write_text(LEG.read_text(encoding="utf-8"), encoding="utf-8")

    assert records(plain) == records(sealed(tmp_path))


def test_stream_fields_gain_their_transcript_names(tmp_path):
    got = records(sealed(tmp_path))
    init, tool_result, compact = got[0], got[3], got[9]

    assert init["version"] == "9.9.1"
    assert init["cwd"] == "/runner/work/widget"
    assert all(r["sessionId"] == "11111111-1111-4111-8111-111111111111" for r in got)
    assert tool_result["toolUseResult"] == {"type": "text", "file": {"filePath": "/runner/work/widget/config.yaml"}}
    assert compact["compactMetadata"] == {"trigger": "auto", "preTokens": 150000}


def test_a_message_inside_a_subagent_is_a_sidechain_record(tmp_path):
    got = records(sealed(tmp_path))

    assert [r["uuid"][-1] for r in got if r.get("isSidechain")] == ["7", "8"]
    assert all(r.get("isSidechain") is False for r in got if r["type"] in {"assistant", "user"} and r["parent_tool_use_id"] is None)


def test_the_original_stream_fields_stay(tmp_path):
    init = records(sealed(tmp_path))[0]

    assert init["claude_code_version"] == "9.9.1"
    assert init["session_id"] == "11111111-1111-4111-8111-111111111111"


def test_usage_counts_once_per_message_across_streamed_records(tmp_path):
    ledger = transcript_reader.UsageLedger()
    for record in records(sealed(tmp_path)):
        if record["type"] == "assistant":
            ledger.add(record)

    totals = ledger.totals()
    assert totals["unique_messages"] == 5
    assert totals["output"] == 40 + 30 + 9 + 50 + 12


def test_a_transcript_jsonl_is_not_normalized(tmp_path):
    path = tmp_path / "s.jsonl"
    path.write_text(json.dumps({"type": "user", "session_id": "x", "parent_tool_use_id": "t"}) + "\n", encoding="utf-8")

    (record,) = records(path)

    assert "sessionId" not in record and "isSidechain" not in record


def test_an_unreadable_gzip_counts_one_bad_line_and_never_raises(tmp_path):
    path = tmp_path / "broken.json.gz"
    path.write_bytes(b"\x1f\x8b\x08\x00not-gzip")
    stats: dict[str, int] = {}

    assert records(path, stats) == []
    assert stats["bad_lines"] == 1


def test_an_array_item_that_is_not_an_object_is_a_bad_line(tmp_path):
    stats: dict[str, int] = {}

    got = records(sealed(tmp_path, '[{"type": "user"}, 3, "x"]'), stats)

    assert len(got) == 1
    assert stats["bad_lines"] == 2


def test_a_top_level_value_that_is_not_an_array_is_a_bad_line(tmp_path):
    stats: dict[str, int] = {}

    assert records(sealed(tmp_path, '{"type": "user"}'), stats) == []
    assert stats["bad_lines"] == 1


def test_stream_only_message_types_are_known(tmp_path):
    for kind in ("rate_limit_event", "stream_event", "tool_progress", "tool_use_summary", "auth_status", "prompt_suggestion", "conversation_reset"):
        assert transcript_reader.record_kind({"type": kind}) == kind


def test_first_cwd_reads_a_sealed_leg(tmp_path):
    assert transcript_reader.first_cwd(sealed(tmp_path)) == "/runner/work/widget"
