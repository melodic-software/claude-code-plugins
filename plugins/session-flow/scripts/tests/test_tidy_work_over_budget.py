"""Contract tests for tidy_work.py and the over-budget marker `save_point.py fill`
leaves beside a handoff: the marker belongs to that handoff, leaves with it, and
is never reported on its own."""

from __future__ import annotations

import test_tidy_work
from test_tidy_work import (
    HANDOFF_FRESH,
    HANDOFF_STALE,
    age,
    build,
    clean,
    report,
    write,
)

env = test_tidy_work.env


def marker(name: str) -> str:
    return f".{name}.over-budget"


def test_an_over_budget_marker_leaves_with_its_handoff_and_is_never_reported(env):
    build(env)
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    for name in (HANDOFF_STALE, HANDOFF_FRESH):
        write(handoffs / marker(name), '["brief"]\n')
        age(handoffs / marker(name), 60)
    items = report(env)
    assert marker(HANDOFF_STALE) not in items
    assert marker(HANDOFF_FRESH) not in items
    dry = clean(env)
    assert f"would remove: {handoffs / marker(HANDOFF_STALE)}" in dry.stdout
    assert clean(env, "--apply").returncode == 0
    assert not (handoffs / HANDOFF_STALE).exists()
    assert not (handoffs / marker(HANDOFF_STALE)).exists()
    assert (handoffs / marker(HANDOFF_FRESH)).exists()


ORPHAN = "20260201T100000Z-handoff-gone.md"


def test_a_marker_whose_handoff_is_gone_leaves_once_idle(env):
    build(env)
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    idle = handoffs / marker(ORPHAN)
    recent = handoffs / marker(HANDOFF_FRESH.replace("new", "newer"))
    slots = handoffs / ORPHAN.replace(".md", ".slots.json")
    for path in (idle, recent, slots):
        write(path, '["brief"]\n')
    for path in (idle, slots):
        age(path, 60)
    items = report(env)
    assert items[idle.name]["kind"] == "orphan-marker"
    assert items[idle.name]["keep"] is False
    assert items[recent.name]["kind"] == "orphan-marker"
    assert items[recent.name]["keep"] is True
    assert items[slots.name]["kind"] == "unknown"
    assert clean(env, "--apply").returncode == 0
    assert not idle.exists()
    assert recent.exists()
    assert slots.exists()
