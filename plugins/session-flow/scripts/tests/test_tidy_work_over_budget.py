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
        write(handoffs / marker(name), '[["brief", 2000, 979]]\n')
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
