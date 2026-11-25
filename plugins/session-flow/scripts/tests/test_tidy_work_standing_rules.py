"""Contract tests for tidy_work.py's standing-rules files: one leaves with its chain's archive,
and one whose chain has no hot file on disk is an archive item kept until that archive goes."""

from __future__ import annotations

from pathlib import Path

import test_tidy_work
from test_tidy_work import (
    HOP3_2,
    ROOT3,
    SHIPPED,
    STATE,
    age,
    clean,
    handoff,
    links,
    report,
    three_chain,
    write,
)

env = test_tidy_work.env


def standing_rules_file(env) -> Path:
    _, _, repo = env
    path = repo / ".work" / "handoffs" / "standing-rules" / ROOT3
    write(path, "---\ntype: handoff-standing-rules\n---\n\n## Current rules\n")
    age(path.parent, 60)
    return path


def test_a_standing_rules_file_leaves_with_its_chain_archive(env):
    archive = three_chain(env)
    standing = standing_rules_file(env)
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    (handoffs / HOP3_2).unlink()
    handoff(handoffs / ROOT3, SHIPPED)
    age(handoffs / ROOT3, 60)
    items = report(env, *links(env[0], STATE))
    assert "standing-rules" not in items
    assert ROOT3 not in items or items[ROOT3]["kind"] == "handoff"
    assert items[archive.name]["kind"] == "archive"
    result = clean(env, "--apply", *links(env[0], STATE))
    assert result.returncode == 0, result.stdout + result.stderr
    assert f"removed: {standing.as_posix()}" in result.stdout
    assert not archive.exists()
    assert not standing.exists()


def test_a_standing_rules_file_without_its_archive_is_an_archive_item(env):
    standing = standing_rules_file(env)
    items = report(env, *links(env[0], STATE))
    assert items[standing.name]["kind"] == "archive"
    assert items[standing.name]["reasons"] == ["no hot file of its chain is on disk"]
    assert clean(env, "--apply").returncode == 0
    assert standing.is_file()
