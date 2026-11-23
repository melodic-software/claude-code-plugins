from __future__ import annotations

from pathlib import Path

CONTINUATION = (
    Path(__file__).resolve().parents[2] / "skills" / "workflow" / "context" / "continuation.md"
)


def test_router_hands_off_at_a_phase_or_task_boundary():
    text = CONTINUATION.read_text(encoding="utf-8")

    assert "is this a phase or task boundary with the next phase or\n   task next in sequence" in text
    assert "6. **Fallthrough: the next work is in the same phase, activity or task** →" in text


def test_human_stage_zone_rule_is_gone():
    assert "Between human stages" not in CONTINUATION.read_text(encoding="utf-8")
