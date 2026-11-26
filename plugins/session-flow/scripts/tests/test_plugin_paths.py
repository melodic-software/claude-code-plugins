from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

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


def test_file_lock_holds_out_a_second_holder_until_released(tmp_path):
    lock = tmp_path / "lock"
    with plugin_paths.file_lock(lock, wait=0) as first:
        assert first is True, "a free lock is taken at once"
        started = time.monotonic()
        with plugin_paths.file_lock(lock, wait=0.2) as second:
            assert second is False, "a held lock is not taken"
        assert time.monotonic() - started >= 0.2, "the second holder waits out its wait before giving up"
    with plugin_paths.file_lock(lock, wait=0) as again:
        assert again is True, "the lock is free once its holder leaves"
    if os.name == "posix":
        assert lock.stat().st_mode & 0o777 == 0o600


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


def test_git_toplevel_and_default_memory_dir(tmp_path):
    repo = tmp_path / "repo"
    sub = repo / "a" / "b"
    sub.mkdir(parents=True)
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True)
    assert plugin_paths.git_toplevel(sub) == repo.resolve()
    assert plugin_paths.git_toplevel(sub / "nonexistent" / "leaf") == repo.resolve()
    assert plugin_paths.default_memory_dir(sub, {}, None) == Path(".work")

    outside = tmp_path / "outside"
    outside.mkdir()
    assert plugin_paths.git_toplevel(outside) is None
    assert plugin_paths.default_memory_dir(outside, {}, None) is None
    assert (
        plugin_paths.default_memory_dir(
            outside, {"CLAUDE_PLUGIN_DATA": str(tmp_path / "session-flow")}, None
        )
        == tmp_path / "session-flow" / "artifacts"
    )


def test_is_self_ignored_accepts_star_and_doublestar(tmp_path):
    assert plugin_paths.is_self_ignored(tmp_path) is False
    gi = tmp_path / ".gitignore"
    gi.write_text("# comment only\n*.log\n", encoding="utf-8")
    assert plugin_paths.is_self_ignored(tmp_path) is False
    gi.write_text("*\n", encoding="utf-8")
    assert plugin_paths.is_self_ignored(tmp_path) is True
    gi.write_text("# header\n**\n", encoding="utf-8")
    assert plugin_paths.is_self_ignored(tmp_path) is True


def test_validate_memory_root_rejects_repo_root_and_unguarded_outside_root(tmp_path):
    import pytest

    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(repo)], check=True)
    with pytest.raises(ValueError, match="repository root"):
        plugin_paths.validate_memory_root(repo, repo)

    outside = tmp_path / "outside"
    outside.mkdir()
    with pytest.raises(ValueError, match="self-ignore guard"):
        plugin_paths.validate_memory_root(outside, repo)

    (outside / ".gitignore").write_text("**\n", encoding="utf-8")
    assert plugin_paths.validate_memory_root(outside, repo) == outside.resolve()

    absent = tmp_path / "absent"
    assert plugin_paths.validate_memory_root(absent, repo) == absent.resolve()


def test_read_session_flow_yaml_reads_extra_concern_dirs_from_convention_home(tmp_path):
    repo = tmp_path / "repo"
    home = tmp_path / "home"
    home.mkdir()
    (repo / "docs" / "conventions").mkdir(parents=True)
    (repo / "docs" / "conventions" / "session-flow.yaml").write_text(
        "extra_concern_dirs:\n  - team-scratch\n  - custom_cache\n",
        encoding="utf-8",
    )
    cfg = plugin_paths.read_session_flow_yaml(repo, home)
    assert cfg.get("extra_concern_dirs") == ["team-scratch", "custom_cache"]

    custom = tmp_path / "custom-repo"
    (custom / "team" / "rules").mkdir(parents=True)
    (custom / "AGENTS.md").write_text(
        "<!-- BEGIN GENERATED: convention-home -->\n"
        "Conventions live in `team/rules`.\n"
        "<!-- END GENERATED: convention-home -->\n",
        encoding="utf-8",
    )
    (custom / "team" / "rules" / "session-flow.yaml").write_text(
        "extra_concern_dirs: [bench, artifacts]\n",
        encoding="utf-8",
    )
    cfg2 = plugin_paths.read_session_flow_yaml(custom, home)
    assert cfg2.get("extra_concern_dirs") == ["bench", "artifacts"]
