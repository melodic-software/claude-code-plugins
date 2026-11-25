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


def active_rule_before_handoff(command: str) -> str:
    text = CONTINUATION.read_text(encoding="utf-8")
    router = text.split("## The router:", 1)[1]
    early_rules, _ = router.split("5. **Does the work leave this session", 1)
    for rule in early_rules.split("\n\n"):
        question = rule.partition("?**")[0]
        if "active" in question.lower() and f"`{command}`" in question:
            return " ".join(rule.lower().split())
    return ""


def test_active_goal_routes_to_compaction():
    assert "let automatic compaction run" in active_rule_before_handoff("/goal")


def test_active_loop_routes_to_compaction():
    assert "let automatic compaction run" in active_rule_before_handoff("/loop")


def test_explicit_handoff_under_goal():
    rule = active_rule_before_handoff("/goal")
    assert "only an explicit user request for a handoff routes to `session-flow:handoff`" in rule
