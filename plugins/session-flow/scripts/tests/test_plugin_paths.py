"""Unit tests for plugin_paths.py: the data root rule, the atomic write and the git call."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import plugin_paths  # noqa: E402


def test_data_root_accepts_only_session_flow_segments(tmp_path):
    cache_root = tmp_path / "plugins" / "cache" / "mkt" / "session-flow" / "2.0.0"
    derived = tmp_path / "plugins" / "data" / "session-flow-mkt"
    for value in ("/d/session-flow", "/d/session-flow-mkt/", "/d/session-flow-inline"):
        assert plugin_paths.data_root({"CLAUDE_PLUGIN_DATA": value}, cache_root) == Path(value.rstrip("/"))
    for value in ("", "/d/other-plugin", "/d/session-flowx", "${CLAUDE_PLUGIN_DATA}"):
        assert plugin_paths.data_root({"CLAUDE_PLUGIN_DATA": value}, cache_root) == derived, value
    assert plugin_paths.data_root({}, tmp_path / "checkout" / "plugins" / "session-flow") is None
    assert plugin_paths.data_root({}, None) is None


def test_write_atomic_replaces_whole_and_private(tmp_path):
    target = tmp_path / "sub" / "state.json"
    assert plugin_paths.write_atomic(target, "one\n") is True
    assert plugin_paths.write_atomic(target, "two\n") is True
    assert target.read_text(encoding="utf-8") == "two\n"
    assert [p.name for p in target.parent.iterdir()] == ["state.json"], "no temp file is left behind"
    if os.name == "posix":
        assert target.stat().st_mode & 0o777 == 0o600


def test_write_atomic_retries_a_held_target(tmp_path, monkeypatch):
    target = tmp_path / "report.md"
    real_replace = os.replace
    calls = []

    def held_twice(src, dst):
        calls.append(dst)
        if len(calls) <= 2:
            raise PermissionError("held by a reader")
        real_replace(src, dst)

    monkeypatch.setattr(plugin_paths.os, "replace", held_twice)
    monkeypatch.setattr(plugin_paths.time, "sleep", lambda _s: None)
    assert plugin_paths.write_atomic(target, "x") is True
    assert len(calls) == 3

    monkeypatch.setattr(plugin_paths.os, "replace", lambda *_a: (_ for _ in ()).throw(PermissionError("held")))
    assert plugin_paths.write_atomic(tmp_path / "never.md", "x") is False
    assert not list(tmp_path.glob(".never.md.*")), "the temp file is removed after the last retry"


def test_run_git_reports_failure_as_none(tmp_path, monkeypatch):
    result = plugin_paths.run_git(tmp_path, "rev-parse", "--show-toplevel")
    assert result is not None and result.returncode != 0, "not a repository: git runs and fails"

    def missing(*_a, **_k):
        raise FileNotFoundError("git")

    monkeypatch.setattr(plugin_paths.subprocess, "run", missing)
    assert plugin_paths.run_git(tmp_path, "status") is None

    def slow(*_a, **_k):
        raise subprocess.TimeoutExpired("git", 1)

    monkeypatch.setattr(plugin_paths.subprocess, "run", slow)
    assert plugin_paths.run_git(tmp_path, "status", timeout=1) is None


@pytest.mark.parametrize("value", ["", "/d/disk-hygiene-mkt", "/d/session-flow", "/d/session-flow-inline/"])
def test_matches_save_point_rule(value, monkeypatch):
    import away
    import save_point

    monkeypatch.setenv("CLAUDE_PLUGIN_DATA", value)
    expected = save_point._plugin_data_root()
    assert plugin_paths.data_root(os.environ, save_point._SCRIPTS_DIR.parent) == expected
    assert away.data_root(os.environ, away.DEFAULT_PLUGIN_ROOT) == expected
