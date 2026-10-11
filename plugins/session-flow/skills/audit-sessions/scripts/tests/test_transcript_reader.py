# test-scope: plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/reader/subagents/*
"""Unit tests for transcript_reader.py, the one reader of Claude Code transcript JSONL.

Drives the public interface only: `iter_records`, `record_kind`, `UsageLedger`, `is_typed_turn`
and `iter_subagents`. Fixtures under `fixtures/reader/` are synthetic; CRLF and unterminated
inputs are generated at test time because `.gitattributes` normalizes committed files to LF.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path

import pytest
import transcript_reader
from conftest import FIXTURES

READER = FIXTURES / "reader"

# The record types type-inventory §1 names, in the fixture's order.
KNOWN_TYPES = [
    "user",
    "assistant",
    "system",
    "attachment",
    "progress",
    "queue-operation",
    "last-prompt",
    "custom-title",
    "agent-name",
    "pr-link",
    "worktree-state",
    "permission-mode",
    "file-history-snapshot",
]


def read(path: Path) -> tuple[list[dict], dict[str, int]]:
    stats: dict[str, int] = {}
    return list(transcript_reader.iter_records(path, stats)), stats


def test_every_known_record_type_is_classified_as_itself():
    records, _ = read(READER / "record-types.jsonl")

    kinds = [transcript_reader.record_kind(r) for r in records]

    assert kinds[:13] == KNOWN_TYPES


def test_other_record_types_classify_as_unknown_and_are_counted():
    records, stats = read(READER / "record-types.jsonl")

    kinds = Counter(transcript_reader.record_kind(r) for r in records)

    # Fixture tail: future-record-kind twice, another-new-kind once, one record with no type.
    assert kinds["unknown"] == 4
    assert stats["unknown"] == 4
    assert stats["records"] == 17


def test_malformed_lines_are_counted_and_skipped():
    records, stats = read(READER / "malformed.jsonl")

    # Truncated object, plain text, a JSON array and a JSON string are bad; the blank line is not.
    assert [r["uuid"] for r in records] == ["m-01", "m-07"]
    assert stats["bad_lines"] == 4
    assert stats["incomplete"] == 0


GROWING_HEAD = '{"type": "user", "uuid": "g-01", "message": {"role": "user", "content": "go"}}\n'
GROWING_TAIL = '{"type": "assistant", "uuid": "g-02", "message": {"id": "msg_g", "usage": {"output_tokens": 3}}}'


def test_unterminated_final_line_is_incomplete_not_bad(tmp_path):
    session = tmp_path / "growing.jsonl"
    session.write_bytes((GROWING_HEAD + GROWING_TAIL[:40]).encode("utf-8"))

    records, stats = read(session)

    assert [r["uuid"] for r in records] == ["g-01"]
    assert stats["incomplete"] == 1
    assert stats["bad_lines"] == 0


def test_still_growing_session_reads_whole_once_the_write_finishes(tmp_path):
    session = tmp_path / "growing.jsonl"
    session.write_bytes((GROWING_HEAD + GROWING_TAIL[:40]).encode("utf-8"))
    read(session)

    with session.open("ab") as handle:
        handle.write((GROWING_TAIL[40:] + "\n").encode("utf-8"))
    records, stats = read(session)

    assert [r["uuid"] for r in records] == ["g-01", "g-02"]
    assert stats["incomplete"] == 0
    assert stats["bad_lines"] == 0


def test_crlf_and_lf_files_read_the_same(tmp_path):
    lines = [GROWING_HEAD.rstrip("\n"), GROWING_TAIL, "not json"]
    lf = tmp_path / "lf.jsonl"
    crlf = tmp_path / "crlf.jsonl"
    lf.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))
    crlf.write_bytes(("\r\n".join(lines) + "\r\n").encode("utf-8"))

    lf_records, lf_stats = read(lf)
    crlf_records, crlf_stats = read(crlf)

    assert [r["uuid"] for r in crlf_records] == ["g-01", "g-02"]
    assert crlf_records == lf_records
    assert crlf_stats == lf_stats == {"records": 2, "bad_lines": 1, "incomplete": 0, "unknown": 0}


def test_invalid_utf8_is_replaced_not_raised(tmp_path):
    session = tmp_path / "bytes.jsonl"
    session.write_bytes(b'{"type": "user", "uuid": "b-01", "message": {"content": "data\xff"}}\n')

    records, stats = read(session)

    assert records[0]["message"]["content"] == "data�"
    assert stats["bad_lines"] == 0


def test_complete_record_without_trailing_newline_is_yielded(tmp_path):
    session = tmp_path / "no-newline.jsonl"
    session.write_bytes((GROWING_HEAD + GROWING_TAIL).encode("utf-8"))

    records, stats = read(session)

    assert [r["uuid"] for r in records] == ["g-01", "g-02"]
    assert stats["incomplete"] == 0


def assistant(uuid: str, message_id: str | None, **usage) -> dict:
    message: dict = {"role": "assistant", "usage": usage}
    if message_id is not None:
        message["id"] = message_id
    return {"type": "assistant", "uuid": uuid, "message": message}


def ledger_totals(*records: dict) -> dict[str, int]:
    ledger = transcript_reader.UsageLedger()
    for record in records:
        ledger.add(record)
    return ledger.totals()


def test_usage_dedup_keeps_the_last_record_per_message_id():
    totals = ledger_totals(
        assistant("a-1", "msg_A", input_tokens=10, output_tokens=5, cache_read_input_tokens=100),
        assistant("a-2", "msg_A", input_tokens=10, output_tokens=20, cache_read_input_tokens=100),
        assistant("a-3", "msg_A", input_tokens=10, output_tokens=40, cache_read_input_tokens=100),
        assistant("a-4", "msg_B", input_tokens=3, output_tokens=7, cache_read_input_tokens=50),
    )

    # Per-record sums would be input 33, output 72, cache_read 350.
    assert (totals["input"], totals["output"], totals["cache_read"]) == (13, 47, 150)
    assert totals["unique_messages"] == 2


def test_last_record_wins_even_when_a_later_value_is_smaller():
    totals = ledger_totals(
        assistant("a-1", "msg_A", output_tokens=40),
        assistant("a-2", "msg_A", output_tokens=12),
    )

    assert totals["output"] == 12


def test_usage_without_message_id_is_keyed_by_record_uuid():
    totals = ledger_totals(
        assistant("u-1", None, output_tokens=4),
        assistant("u-2", None, output_tokens=6),
        assistant("u-2", None, output_tokens=9),
    )

    assert totals["output"] == 4 + 9
    assert totals["unique_messages"] == 2


def test_cache_creation_split_is_read_from_the_nested_object():
    totals = ledger_totals(
        assistant(
            "a-1",
            "msg_A",
            cache_creation_input_tokens=30,
            cache_creation={"ephemeral_1h_input_tokens": 20, "ephemeral_5m_input_tokens": 10},
        )
    )

    assert (totals["cache_creation"], totals["cache_creation_1h"], totals["cache_creation_5m"]) == (30, 20, 10)


def test_usage_ledger_ignores_drifted_shapes_without_raising():
    totals = ledger_totals(
        {"type": "assistant", "uuid": "d-1", "message": "a string, not an object"},
        {"type": "assistant", "uuid": "d-2", "message": {"id": "msg_D", "usage": [1, 2]}},
        {"type": "assistant", "uuid": "d-3", "message": {"id": ["msg"], "usage": {"output_tokens": 5}}},
        assistant("d-4", "msg_E", output_tokens="12", input_tokens=None, cache_creation=7),
        assistant("d-5", "msg_F", output_tokens=8),
    )

    # d-3's list id is unusable as a key, so its uuid keys it; msg_E's string and null are not counts.
    assert totals["output"] == 5 + 8
    assert totals["unique_messages"] == 3


def user(content: object = "Rename the widget", **fields) -> dict:
    return {"type": "user", "uuid": "u-1", "message": {"role": "user", "content": content}, **fields}


# The injected-prefix denylist of the design spike (spike signals.py:25-31).
SPIKE_INJECTED_PREFIXES = [
    "<local-command-caveat>",
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<command-name>",
    "<command-message>",
    "<bash-input>",
    "<bash-stdout>",
    "<bash-stderr>",
    "<task-notification>",
    "<system-reminder>",
    "Another Claude session sent",
    "[Cross-session idle notice]",
    "[Usage limit",
    "[Earlier usage-limit",
    "Your claude.ai usage limit",
    "(Re-invocation of",
    "Base directory for this skill",
    "Caveat:",
    "<user-prompt-submit-hook>",
]


@pytest.mark.parametrize(
    "record",
    [
        user(),
        user(promptSource="typed"),
        user(promptSource="queued"),
        user(origin={"kind": "human"}),
        user([{"type": "text", "text": "Rename"}, {"type": "image"}, {"type": "text", "text": "the widget"}]),
        user("   Rename the widget  \n"),
    ],
    ids=["plain", "typed", "queued", "origin-human", "text-blocks", "padded"],
)
def test_typed_turns(record):
    assert transcript_reader.is_typed_turn(record) is True


@pytest.mark.parametrize(
    "record",
    [
        {**user(), "type": "assistant"},
        user([{"type": "tool_result", "tool_use_id": "t-1", "content": "ok"}]),
        user([{"type": "text", "text": "see output"}, {"type": "tool_result", "tool_use_id": "t-2"}]),
        user(isMeta=True),
        user(isCompactSummary=True),
        user(isVisibleInTranscriptOnly=True),
        user(origin={"kind": "task-notification"}),
        user(promptSource="hook"),
        user("[Request interrupted by user]"),
        user("[Request interrupted by user for tool use]"),
        user(""),
        user([{"type": "image"}]),
        user(None),
    ],
    ids=[
        "assistant",
        "tool-result",
        "tool-result-with-text",
        "meta",
        "compact-summary",
        "transcript-only",
        "origin-not-human",
        "prompt-source-other",
        "interrupt",
        "interrupt-tool-use",
        "empty",
        "image-only",
        "no-content",
    ],
)
def test_not_typed_turns(record):
    assert transcript_reader.is_typed_turn(record) is False


@pytest.mark.parametrize("prefix", SPIKE_INJECTED_PREFIXES)
def test_injected_prefixes_are_not_typed_turns(prefix):
    assert transcript_reader.is_typed_turn(user(f"{prefix} trailing words")) is False
    assert transcript_reader.is_typed_turn(user([{"type": "text", "text": f"  {prefix}"}])) is False


REMINDER = "<system-reminder>\nToday's date is 2026-10-04.\n</system-reminder>\n"


def desktop(content: object, **fields) -> dict:
    """A Claude Desktop user record: typed by the person, yet written with promptSource sdk."""
    return user(content, origin={"kind": "human"}, promptSource="sdk", **fields)


@pytest.mark.parametrize(
    ("record", "text"),
    [
        (desktop("retry, keep using sonnet"), "retry, keep using sonnet"),
        (desktop(REMINDER + "retry, keep using sonnet"), "retry, keep using sonnet"),
        (desktop([{"type": "text", "text": REMINDER}, {"type": "text", "text": "retry"}]), "retry"),
    ],
    ids=["plain", "leading-reminder", "reminder-block"],
)
def test_desktop_human_prompts_are_typed_turns(record, text):
    assert transcript_reader.is_typed_turn(record) is True
    assert transcript_reader.typed_text(record) == text


@pytest.mark.parametrize(
    "record",
    [
        desktop(REMINDER),
        desktop(REMINDER + REMINDER + "retry"),
        desktop(REMINDER + "<command-name>/clear</command-name>"),
        desktop(REMINDER + "[Request interrupted by user]"),
        desktop("<system-reminder>never closed retry"),
        user("retry", promptSource="sdk"),
        user(REMINDER + "retry"),
        user(REMINDER + "retry", promptSource="typed"),
    ],
    ids=[
        "reminder-only",
        "second-reminder",
        "reminder-then-command",
        "reminder-then-interrupt",
        "unclosed-reminder",
        "sdk-without-origin",
        "cli-reminder-led",
        "cli-typed-reminder-led",
    ],
)
def test_reminder_strip_and_sdk_source_need_a_human_origin(record):
    assert transcript_reader.is_typed_turn(record) is False
    assert transcript_reader.typed_text(record) is None


@pytest.mark.parametrize(
    ("record", "typed"),
    [
        ({"type": "user", "message": "a string, not an object"}, False),
        ({"type": "user", "message": {"content": ["text", 7, None]}}, False),
        ({"type": "user", "message": {"content": [{"type": "text", "text": 42}]}}, False),
        # A non-object origin carries no kind, so the rule reads it as absent.
        ({"type": "user", "origin": "human", "message": {"content": "hello"}}, True),
        # A promptSource that is present but not typed/queued fails the rule, whatever its shape.
        ({"type": "user", "promptSource": ["typed"], "message": {"content": "hello"}}, False),
    ],
    ids=["message-string", "content-scalars", "text-not-string", "origin-string", "prompt-source-list"],
)
def test_typed_turn_rule_tolerates_drifted_shapes(record, typed):
    assert transcript_reader.is_typed_turn(record) is typed


@pytest.mark.parametrize(
    ("record", "text"),
    [
        (user("  plain words \n"), "plain words"),
        (user([{"type": "text", "text": "one"}, {"type": "image"}, {"type": "text", "text": "two"}]), "one\ntwo"),
        (user("<command-name>/clear</command-name>"), "<command-name>/clear</command-name>"),
        (user([{"type": "tool_result", "content": "out"}, {"type": "text", "text": "x"}]), None),
        ({"type": "user", "message": "a string, not an object"}, None),
    ],
    ids=["string", "text-blocks", "injected-kept", "tool-result", "drifted"],
)
def test_user_text_joins_text_blocks_and_drops_tool_results(record, text):
    assert transcript_reader.user_text(record) == text


def test_subagents_stream_with_their_meta(copy_fixture):
    root = copy_fixture("reader/subagents")
    (root / "sess-0001" / "subagents" / "agent-c3.meta.json").write_text('{"agentType": ', encoding="utf-8")

    subagents = list(transcript_reader.iter_subagents(root / "sess-0001.jsonl"))

    # notes.jsonl is not an agent file and agent-d4 has meta but no transcript; neither is yielded.
    # agent-b2 has no meta file and agent-c3's is malformed: both yield meta None.
    assert [s.path.name for s in subagents] == ["agent-a1.jsonl", "agent-b2.jsonl", "agent-c3.jsonl"]
    assert [s.meta for s in subagents] == [
        {"agentType": "general-purpose", "model": "model-y", "spawnDepth": 1},
        None,
        None,
    ]


def test_subagent_records_stream_through_the_reader(copy_fixture):
    root = copy_fixture("reader/subagents")
    stats: dict[str, int] = {}
    ledger = transcript_reader.UsageLedger()

    for subagent in transcript_reader.iter_subagents(root / "sess-0001.jsonl"):
        for record in transcript_reader.iter_records(subagent.path, stats):
            ledger.add(record)

    # msg_a1 streams 3 then 9 (last wins), msg_b2 4, msg_c3 2; agent-b2 carries one bad line.
    assert ledger.totals()["output"] == 9 + 4 + 2
    assert stats["records"] == 5
    assert stats["bad_lines"] == 1


def test_session_without_subagents_yields_none(copy_fixture):
    root = copy_fixture("reader/subagents")

    assert list(transcript_reader.iter_subagents(root / "no-such-session.jsonl")) == []
