# test-scope: plugins/session-flow/scripts/tests/fixtures/* plugins/session-flow/scripts/dialect.py plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/handoff_fit.py plugins/session-flow/scripts/io_streams.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/scripts/save_point.py
"""Where a role chain's standing-rules file lives. Expected values come from
reference/structure.md ("Role chains: the standing-rules file"): a new chain
writes `handoffs/standing-rules/<chain-root-stem>.md`, outside `archive/` and
outside the direct-child `*-handoff-*.md` listing, and a chain written while the
file lived at `archive/<chain-root-stem>/standing-rules.md` keeps reading it."""

from __future__ import annotations

import json
from pathlib import Path

from test_save_point import err, make_repo, out, run
from test_save_point_shape4_writer import body, standing_hop, validate


def new_rel(path: Path) -> str:
    return f"standing-rules/{path.stem}.md"


def legacy_rel(path: Path) -> str:
    return f"archive/{path.stem}/standing-rules.md"


def to_legacy(path: Path) -> Path:
    """Rewrite a one-hop role chain into the layout written before the
    standing-rules file left `archive/`."""
    handoffs = path.parent
    legacy = handoffs / legacy_rel(path)
    (handoffs / new_rel(path)).rename(legacy)
    path.write_text(
        path.read_text(encoding="utf-8").replace(new_rel(path), legacy_rel(path)),
        encoding="utf-8",
    )
    return legacy


def test_a_new_role_chain_keeps_standing_rules_beside_its_handoff_file(tmp_path):
    path = standing_hop(make_repo(tmp_path), tmp_path)
    handoffs = path.parent
    text = path.read_text(encoding="utf-8")
    assert f"standing_rules: {new_rel(path)}\n" in text
    assert body(path, "Current rules") == (
        f"- Standing rules: {new_rel(path)}#Current rules"
    )
    assert "[R1] The thing must stay green." in body(
        handoffs / new_rel(path), "Current rules"
    )
    assert not (handoffs / legacy_rel(path)).exists()
    assert [p.name for p in handoffs.glob("*-handoff-*.md")] == [path.name]
    result = validate(path)
    assert result.returncode == 0, out(result)


def test_a_legacy_role_chain_still_validates_and_amends_in_place(tmp_path):
    path = standing_hop(make_repo(tmp_path), tmp_path)
    legacy = to_legacy(path)
    assert validate(path).returncode == 0, out(validate(path))
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"retire": [{"ref": "[R2]", "reason": "moved to AGENTS.md"}]}),
        encoding="utf-8",
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    assert "[R2]" not in body(legacy, "Current rules")
    assert "[R1] The thing must stay green." in body(legacy, "Current rules")
    assert not (path.parent / new_rel(path)).exists()
    assert validate(path).returncode == 0, out(validate(path))


def test_a_successor_of_a_legacy_hop_moves_the_rules_and_leaves_the_old_file(
    tmp_path,
):
    repo = make_repo(tmp_path)
    first = standing_hop(repo, tmp_path)
    legacy = to_legacy(first)
    before = legacy.read_bytes()
    second = standing_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"rules-new": "- [R3] Report every red check."},
    )
    assert f"standing_rules: {new_rel(first)}\n" in second.read_text(encoding="utf-8")
    held = body(second.parent / new_rel(first), "Current rules")
    assert "[R1] The thing must stay green." in held
    assert "[R3] Report every red check." in held
    assert legacy.read_bytes() == before
    for path in (first, second):
        result = validate(path)
        assert result.returncode == 0, out(result)


def test_validate_refuses_a_standing_rules_path_of_another_chain(tmp_path):
    path = standing_hop(make_repo(tmp_path), tmp_path)
    other = "archive/20260101T000000Z-handoff-other/standing-rules.md"
    path.write_text(
        path.read_text(encoding="utf-8").replace(
            f"standing_rules: {new_rel(path)}\n", f"standing_rules: {other}\n"
        ),
        encoding="utf-8",
    )
    result = validate(path)
    assert result.returncode == 1, out(result)
    assert any(
        line.startswith("FAIL: frontmatter: standing_rules must be")
        for line in out(result).splitlines()
    ), out(result)
