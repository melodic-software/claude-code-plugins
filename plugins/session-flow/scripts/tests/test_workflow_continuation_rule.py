"""Tripwire: the workflow's continuation context keeps its handoff-zone rule line."""

from __future__ import annotations

from pathlib import Path

CONTINUATION = (
    Path(__file__).resolve().parents[2] / "skills" / "workflow" / "context" / "continuation.md"
)
RULE = (
    "**Between human stages, suggest a handoff only at context-usage zone `heavy`"
    " or on its compaction marker.**"
)


def test_continuation_keeps_the_handoff_zone_rule_line():
    lines = CONTINUATION.read_text(encoding="utf-8").splitlines()

    assert any(line.startswith(RULE) for line in lines)
