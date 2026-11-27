# test-scope: plugins/session-flow/.claude-plugin/plugin.json plugins/session-flow/scripts/dispatches.py plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/multi/*

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import PLUGIN_SCRIPTS, envelope, run_cli
from test_collect import collect, records, store_root
from test_collect_fleet import collect_sources


def _write_session_with_subagents(projects: Path, proj: str, sid: str, dispatches: list[dict]) -> None:
    """Create a main session transcript and one subagent transcript per spec in `dispatches`."""
    proj_dir = projects / proj
    proj_dir.mkdir(parents=True, exist_ok=True)
    main_lines = [
        {"type": "user", "uuid": "u0", "timestamp": "2026-09-20T10:00:00Z", "promptSource": "typed", "message": {"role": "user", "content": "run agents"}},
        {"type": "assistant", "uuid": "a0", "timestamp": "2026-09-20T10:00:05Z", "message": {"id": "main_m0", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn", "content": [{"type": "text", "text": "done"}]}},
    ]
    (proj_dir / f"{sid}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in main_lines), encoding="utf-8", newline="\n")
    sub_dir = proj_dir / sid / "subagents"
    sub_dir.mkdir(parents=True, exist_ok=True)
    for spec in dispatches:
        name = spec["name"]
        day = spec["date"]
        turns = spec["turns"]
        stop_final = spec.get("stop_reason", "end_turn")
        if spec.get("agent_type") is not None:
            (sub_dir / f"agent-{name}.meta.json").write_text(
                json.dumps({"agentType": spec["agent_type"]}) + "\n", encoding="utf-8", newline="\n"
            )
        lines: list[dict] = [
            {"type": "user", "timestamp": f"{day}T01:00:00Z", "message": {"role": "user", "content": "start"}},
        ]
        for i in range(turns):
            stop = stop_final if i == turns - 1 else "tool_use"
            for kind in (["thinking", "tool_use"] if spec.get("parallel") else ["tool_use"]):
                lines.append(
                    {
                        "type": "assistant",
                        "timestamp": f"{day}T01:00:01Z",
                        "message": {"id": f"m_{i}", "role": "assistant", "stop_reason": stop, "content": [{"type": kind}]},
                    }
                )
            lines.append(
                {
                    "type": "user",
                    "timestamp": f"{day}T01:00:02Z",
                    "message": {"role": "user", "content": [{"type": "tool_result"}]},
                }
            )
        if spec.get("resumed"):
            lines.append(
                {
                    "type": "user",
                    "timestamp": f"{day}T02:00:00Z",
                    "message": {"role": "user", "content": "continue"},
                }
            )
            extra = spec.get("after_resume_turns", 0)
            for j in range(extra):
                lines.append(
                    {
                        "type": "assistant",
                        "timestamp": f"{day}T02:00:05Z",
                        "message": {
                            "id": f"m_resumed_{j}",
                            "role": "assistant",
                            "stop_reason": "end_turn" if j == extra - 1 else "tool_use",
                            "content": [{"type": "text", "text": "ok"}],
                        },
                    }
                )
        (sub_dir / f"agent-{name}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in lines), encoding="utf-8", newline="\n")


def run_dispatches(data_dir: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return run_cli("dispatches.py", "--data-dir", str(data_dir), *extra)


def test_collect_writes_per_dispatch_rows_and_dispatches_script_filters(data_dir, tmp_path):
    projects = tmp_path / "cfg" / "projects"
    _write_session_with_subagents(
        projects,
        "proj-a",
        "sess-1",
        [
            {"name": "par", "agent_type": "discovery:researcher", "date": "2026-08-01", "turns": 5, "parallel": True},
            {"name": "ceil", "agent_type": "discovery:explorer", "date": "2026-08-02", "turns": 40},
            {"name": "resumed", "agent_type": "discovery:researcher", "date": "2026-08-05", "turns": 40, "resumed": True, "after_resume_turns": 2},
            {"name": "maxturns", "agent_type": "discovery:research-verifier", "date": "2026-08-06", "turns": 30, "stop_reason": "max_turns", "resumed": True},
            {"name": "running", "agent_type": "discovery:researcher", "date": "2026-09-11", "turns": 6, "stop_reason": "tool_use"},
            {"name": "other", "agent_type": "general-purpose", "date": "2026-08-04", "turns": 7},
            {"name": "nometa", "agent_type": None, "date": "2026-08-07", "turns": 3},
        ],
    )
    collected = collect(data_dir, projects)
    assert collected.returncode == 0, collected.stdout + collected.stderr

    stored = records(data_dir)["sess-1"]
    assert stored["subagents"]["count"] == 7
    assert len(stored["subagents"]["dispatches"]) == 7

    res = run_dispatches(
        data_dir,
        "--agent-type",
        "discovery:researcher,discovery:explorer,discovery:research-verifier",
    )
    assert res.returncode == 0, res.stdout + res.stderr
    env = envelope(res)
    assert env["schema"] == "audit-sessions.dispatches/v1"
    data = env["data"]
    assert data["header"] == []
    assert data["unfinished"] == 1
    assert data["sessions_read"] == 1
    assert data["sessions_missing_dispatches"] == {}

    by_date = {row["date"]: row for row in data["dispatches"]}
    assert set(by_date) == {"2026-08-01", "2026-08-02", "2026-08-05", "2026-08-06"}
    assert by_date["2026-08-01"] == {
        "agentType": "discovery:researcher",
        "complete": True,
        "date": "2026-08-01",
        "turns": 5,
        "hit_ceiling": False,
        "resumed": "n/a",
        "source": "local",
    }
    assert by_date["2026-08-02"]["turns"] == 40
    assert by_date["2026-08-02"]["hit_ceiling"] is True
    assert by_date["2026-08-02"]["resumed"] == "unknown"
    assert by_date["2026-08-05"]["turns"] == 42
    assert by_date["2026-08-05"]["hit_ceiling"] is True
    assert by_date["2026-08-05"]["resumed"] == "yes"
    assert by_date["2026-08-06"]["turns"] == 30
    assert by_date["2026-08-06"]["hit_ceiling"] is True
    assert by_date["2026-08-06"]["resumed"] == "yes"

    since_res = run_dispatches(data_dir, "--agent-type", "discovery:researcher", "--since", "2026-09-01")
    assert since_res.returncode == 0
    since_data = envelope(since_res)["data"]
    assert since_data["dispatches"] == []
    assert since_data["unfinished"] == 1

    low = run_dispatches(data_dir, "--agent-type", "discovery:researcher", "--ceiling", "5")
    assert low.returncode == 0
    low_by_date = {row["date"]: row for row in envelope(low)["data"]["dispatches"]}
    assert low_by_date["2026-08-01"]["hit_ceiling"] is True
    assert low_by_date["2026-08-01"]["resumed"] == "unknown"
    assert low_by_date["2026-09-11"]["hit_ceiling"] is True


@pytest.mark.skipif(sys.platform == "win32", reason="the sh -c via and fake claude are POSIX shell")
def test_fleet_collect_reports_every_host_with_no_unread_source(data_dir, tmp_path):
    host_a = tmp_path / "host-a" / "config"
    host_b = tmp_path / "host-b" / "config"
    _write_session_with_subagents(
        host_a / "projects",
        "proj-a",
        "sess-a",
        [{"name": "a1", "agent_type": "discovery:researcher", "date": "2026-09-01", "turns": 12}],
    )
    _write_session_with_subagents(
        host_b / "projects",
        "proj-b",
        "sess-b",
        [{"name": "b1", "agent_type": "discovery:explorer", "date": "2026-09-02", "turns": 25}],
    )
    sources = tmp_path / "sources.json"
    sources.write_text(
        json.dumps(
            {
                "schema": "transcript-sources/v1",
                "sources": [
                    {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(host_a)},
                    {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": str(host_b), "via": ["sh", "-c"]},
                ],
            }
        ),
        encoding="utf-8",
    )
    collected = collect_sources(data_dir, sources, dict())
    assert collected.returncode == 0, collected.stdout + collected.stderr

    res = run_dispatches(data_dir, "--sources-file", str(sources), "--agent-type", "discovery:researcher,discovery:explorer")
    assert res.returncode == 0, res.stdout + res.stderr
    data = envelope(res)["data"]
    assert data["header"] == [], "every configured source was collected cleanly"
    assert [(r["source"], r["agentType"], r["turns"]) for r in data["dispatches"]] == [
        ("host-a-wsl", "discovery:researcher", 12),
        ("host-b-wsl", "discovery:explorer", 25),
    ]


def test_older_records_without_dispatches_stay_readable_and_named_in_header(data_dir, tmp_path):
    projects = tmp_path / "cfg" / "projects"
    _write_session_with_subagents(
        projects,
        "proj-a",
        "sess-new",
        [{"name": "n1", "agent_type": "discovery:researcher", "date": "2026-09-05", "turns": 9}],
    )
    assert collect(data_dir, projects).returncode == 0

    new_path = next(store_root(data_dir).glob("local/p-*/sess-new.json"))
    legacy = json.loads(new_path.read_text(encoding="utf-8"))
    legacy["session_id"] = "sess-legacy"
    legacy["status"] = "carried-over"
    legacy["subagents"].pop("dispatches")
    (new_path.parent / "sess-legacy.json").write_text(json.dumps(legacy), encoding="utf-8")

    res = run_dispatches(data_dir, "--agent-type", "discovery:researcher")
    assert res.returncode == 0, res.stdout + res.stderr
    data = envelope(res)["data"]
    assert len(data["dispatches"]) == 1
    assert data["sessions_read"] == 1
    assert data["sessions_missing_dispatches"] == {"local": 1}
    assert any("Not read by this skill: local (1 stored session record(s) lack per-dispatch rows" in line for line in data["header"])

    swept = run_cli("sweep.py", "--data-dir", str(data_dir), "--format", "json")
    assert swept.returncode in (0, 1), swept.stdout + swept.stderr


def test_missing_store_exits_3_and_corrupt_store_exits_2(data_dir, tmp_path):
    missing = run_dispatches(data_dir)
    assert missing.returncode == 3
    assert envelope(missing)["schema"] == "audit-sessions.dispatches/v1"

    bad = store_root(data_dir) / "local" / "p-000000000000" / "broken.json"
    bad.parent.mkdir(parents=True, exist_ok=True)
    bad.write_text('{"schema": "session-record/v0"}', encoding="utf-8")
    corrupt = run_dispatches(data_dir)
    assert corrupt.returncode == 2
    assert "re-run collect" in envelope(corrupt)["summary"]

    bad_sources = tmp_path / "bad.json"
    bad_sources.write_text('{"schema": "transcript-sources/v1"}', encoding="utf-8")
    malformed = run_dispatches(data_dir, "--sources-file", str(bad_sources))
    assert malformed.returncode == 2
    assert PLUGIN_SCRIPTS.is_dir()
