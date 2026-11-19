"""Contract tests for the two-call slot path's recorded attempt, the shrink WARN's
limit to the chain tip, and the number `new --shape 4` prints (PLAN.md Phase 7:
AC3, AC4, AC13). Expected values come from the Writer contract: the second fill
over a budget writes only for the slot the first fill refused, a finished-chain
shrink keeps only the newest hot file, and the budget is the 24,600-byte cap
minus the bytes `new` wrote."""

from __future__ import annotations

from pathlib import Path

import pytest
from test_save_point import FILL_RE, err, make_repo, out
from test_save_point_shape4_writer import (
    CAP,
    closed_chain,
    fill,
    hop,
    new,
    validate,
)


def test_validate_fails_a_closed_middle_file_whose_predecessor_is_gone(tmp_path):
    first, second = closed_chain(tmp_path, "3")
    hop(tmp_path / "repo", tmp_path, second, k=3, shape="3")
    first.unlink()
    result = validate(second)
    assert result.returncode == 1, out(result)
    assert "not found beside this file" in out(result)


@pytest.mark.parametrize("shape", ["3", "4"])
def test_a_newly_over_budget_slot_is_refused_once_on_its_own(tmp_path, shape):
    repo = make_repo(tmp_path)
    path = Path(out(new(repo, tmp_path, None, k=1, shape=shape)).strip())
    skeleton = path.read_bytes()
    assert fill(path, tmp_path, {"brief": "b" * 2_000}).returncode == 1
    values = {"brief": "b" * 1_500, "below-rail": "n" * 400}
    second = fill(path, tmp_path, values)
    assert second.returncode == 1, out(second)
    assert "'below-rail'" in err(second)
    assert "'brief'" not in err(second)
    assert path.read_bytes() == skeleton
    third = fill(path, tmp_path, values)
    assert third.returncode == 0, err(third)
    slots = [line for line in out(validate(path)).splitlines() if "slot_size:" in line]
    assert len(slots) == 2, slots


def test_new_clears_a_leftover_over_budget_marker_beside_its_file(tmp_path):
    repo = make_repo(tmp_path)
    handoffs = repo / ".work" / "handoffs"
    handoffs.mkdir(parents=True)
    marker = handoffs / ".20260901T100000Z-handoff-widget.md.over-budget"
    marker.write_text('[["brief", 2000, 979]]\n', encoding="utf-8")
    made = new(repo, tmp_path, None, k=1, shape="4")
    assert made.returncode == 0, err(made)
    assert not marker.exists()
    path = Path(out(made).strip())
    assert fill(path, tmp_path, {"brief": "b" * 2_000}).returncode == 1


def test_shape4_new_budget_is_the_cap_minus_the_bytes_new_wrote(tmp_path):
    made = new(make_repo(tmp_path), tmp_path, None, k=1, shape="4")
    skeleton = Path(out(made).strip()).read_text(encoding="utf-8")
    fixed = len(FILL_RE.sub("", skeleton).encode("utf-8"))
    line = next(x for x in err(made).splitlines() if x.startswith("budget:"))
    assert line.startswith(f"budget: {CAP - fixed} bytes for the written slots"), line
    assert 15_000 < CAP - fixed < CAP, line
