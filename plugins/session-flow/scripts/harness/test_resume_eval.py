"""Contract tests for resume_eval.py. No test reaches the API or a CLI."""

import json

import resume_eval


def test_history_renders_a_parent_chained_transcript():
    turns = [
        {"role": "user", "text": "The codename is MAGNOLIA-7."},
        {"role": "assistant", "text": "ok"},
        {"role": "user", "text": "And the rule is never push on Fridays."},
    ]
    lines = resume_eval.render_history(
        turns, "0e5f2a10-4c7b-4d2e-9a61-5b3c8d7e9f01", "/w"
    )
    records = [json.loads(line) for line in lines]
    assert [r["type"] for r in records] == ["user", "assistant", "user"]
    assert records[0]["parentUuid"] is None
    assert [r["parentUuid"] for r in records[1:]] == [
        records[0]["uuid"],
        records[1]["uuid"],
    ]
    assert {r["sessionId"] for r in records} == {"0e5f2a10-4c7b-4d2e-9a61-5b3c8d7e9f01"}
    assert all(r["cwd"] == "/w" and r["isSidechain"] is False for r in records)
    assert records[0]["message"] == {
        "role": "user",
        "content": "The codename is MAGNOLIA-7.",
    }
    reply = records[1]["message"]
    assert reply["content"] == [{"type": "text", "text": "ok"}]
    assert (
        reply["type"] == "message"
        and reply["stop_reason"] == "end_turn"
        and reply["id"]
    )


def test_history_renders_a_tool_call_and_its_result_as_a_pair():
    turns = [
        {"role": "user", "text": "Resume from the handoff."},
        {
            "role": "tool",
            "name": "Read",
            "input": {"file_path": "h.md", "limit": 100},
            "result": "line 1 of the handoff",
        },
        {"role": "assistant", "text": "Read it."},
    ]
    records = [
        json.loads(line) for line in resume_eval.render_history(turns, "s", "/w")
    ]
    assert [r["type"] for r in records] == ["user", "assistant", "user", "assistant"]
    call = records[1]["message"]["content"][0]
    assert call["type"] == "tool_use" and call["name"] == "Read"
    assert call["input"] == {"file_path": "h.md", "limit": 100}
    result = records[2]["message"]["content"][0]
    assert result == {
        "type": "tool_result",
        "tool_use_id": call["id"],
        "content": "line 1 of the handoff",
        "is_error": False,
    }
    assert records[1]["message"]["stop_reason"] == "tool_use"
    assert [r["parentUuid"] for r in records[1:]] == [r["uuid"] for r in records[:-1]]


def test_child_env_cuts_every_route_to_live_sessions_and_github():
    parent = {
        "PATH": "/usr/bin",
        "HOME": "/h",
        "CLAUDE_CODE_MESSAGING_SOCKET": "/run/s.sock",
        "CLAUDE_CODE_MESSAGING_TOKEN": "t",
        "CLAUDE_CODE_BRIDGE_SESSION_ID": "b",
        "GH_TOKEN": "g",
        "GITHUB_TOKEN": "g2",
        "TMPDIR": "/tmp",
    }
    env = resume_eval.child_env(
        parent, tmpdir="/e/t", stub_bin="/e/bin", gh_config="/e/gh"
    )
    for key in (
        "CLAUDE_CODE_MESSAGING_SOCKET",
        "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_BRIDGE_SESSION_ID",
        "GH_TOKEN",
        "GITHUB_TOKEN",
    ):
        assert key not in env
    assert env["TMPDIR"] == "/e/t" and env["GH_CONFIG_DIR"] == "/e/gh"
    assert env["PATH"] == "/e/bin:/usr/bin" and env["HOME"] == "/h"
    assert parent["GH_TOKEN"] == "g"
    for tool in (
        "WebFetch",
        "WebSearch",
        "SendMessage",
        "ListAgents",
        "RemoteTrigger",
        "CronCreate",
        "PushNotification",
    ):
        assert tool in resume_eval.DISALLOWED_TOOLS


def test_claude_command_runs_the_lane_mode_with_the_copy_and_the_fences():
    cmd = resume_eval.claude_command(
        "go on",
        plugin_dir="/c/after",
        settings="/r/settings.json",
        mcp_config="/r/mcp.json",
        resume="sid-1",
    )
    assert cmd[:2] == ["claude", "-p"]
    assert cmd[-1] == "go on"
    pairs = {cmd[i]: cmd[i + 1] for i in range(len(cmd) - 1) if cmd[i].startswith("--")}
    assert pairs["--model"] == "claude-opus-5-5"
    assert pairs["--permission-mode"] == "auto"
    assert pairs["--plugin-dir"] == "/c/after"
    assert pairs["--settings"] == "/r/settings.json"
    assert pairs["--mcp-config"] == "/r/mcp.json" and "--strict-mcp-config" in cmd
    assert pairs["--output-format"] == "stream-json" and "--verbose" in cmd
    assert pairs["--resume"] == "sid-1"
    tools = cmd[
        cmd.index("--disallowed-tools") + 1 : cmd.index("--disallowed-tools")
        + 1
        + len(resume_eval.DISALLOWED_TOOLS)
    ]
    assert tuple(tools) == resume_eval.DISALLOWED_TOOLS
    assert "--resume" not in resume_eval.claude_command(
        "x", plugin_dir=None, settings="s", mcp_config="m"
    )
    assert "--plugin-dir" not in resume_eval.claude_command(
        "x", plugin_dir=None, settings="s", mcp_config="m"
    )


def test_codex_command_pins_the_model_and_stays_ephemeral():
    cmd = resume_eval.codex_command(
        "resume now", model="gpt-x", workdir="/r", reply="/o/reply.txt"
    )
    assert cmd[:3] == ["codex", "exec", "--json"]
    assert "--ephemeral" in cmd and "--ignore-user-config" in cmd
    assert cmd[cmd.index("-m") + 1] == "gpt-x"
    assert cmd[cmd.index("-C") + 1] == "/r"
    assert cmd[cmd.index("-o") + 1] == "/o/reply.txt"
    assert cmd[cmd.index("-s") + 1] == "workspace-write"
    assert cmd[-1] == "resume now"


def test_settings_disable_the_installed_plugin_and_deny_the_network():
    doc = resume_eval.run_settings(
        plugin_configs={"planning@inline": {"options": {"x": True}}}
    )
    assert doc["enabledPlugins"] == {"session-flow@melodic-software": False}
    deny = doc["permissions"]["deny"]
    assert (
        "Bash(curl *)" in deny
        and "Bash(wget *)" in deny
        and "Bash(git ls-remote *)" in deny
    )
    assert "WebFetch" in deny
    assert doc["pluginConfigs"] == {"planning@inline": {"options": {"x": True}}}
    assert "pluginConfigs" not in resume_eval.run_settings()


def test_worktree_isolated_session_is_found_in_an_ancestor_claude_argv():
    tree = {
        300: (200, ["python3", "resume_eval.py"]),
        200: (100, ["bash", "-c", "x"]),
        100: (1, ["claude", "--worktree", "feature-x"]),
        1: (0, ["init"]),
    }

    def read(pid):
        return tree.get(pid)

    assert resume_eval.isolated_session(300, read) == "claude --worktree feature-x"
    tree[100] = (1, ["/usr/bin/claude", "-w"])
    assert resume_eval.isolated_session(300, read) == "/usr/bin/claude -w"
    tree[100] = (1, ["claude", "--resume", "abc"])
    assert resume_eval.isolated_session(300, read) is None
    tree[100] = (1, ["node", "my-worktree-tool", "--worktree"])
    assert resume_eval.isolated_session(300, read) is None


def test_resource_guard_names_every_floor_it_breaks():
    gib = 1024**3
    ok = {
        "root_free": 600 * gib,
        "tmp_free": gib,
        "tmp_inodes": 400_000,
        "mem_available": 20 * gib,
        "swap_used": 2 * gib,
    }
    assert resume_eval.resource_stops(ok) == []
    bad = dict(
        ok,
        root_free=40 * gib,
        tmp_free=400 * 1024**2,
        tmp_inodes=10_000,
        mem_available=7 * gib,
        swap_used=7 * gib,
    )
    assert resume_eval.resource_stops(bad) == [
        "root disk under 50 GB free",
        "/tmp under 500 MB free",
        "/tmp under 50,000 free inodes",
        "MemAvailable under 8 GiB",
        "swap in use over 6 GiB",
    ]


def _claude_events():
    return [
        _assistant("m1", {}, _tool("Bash", command="gh pr view 4231 --json state")),
        _assistant("m2", {}, _tool("Read", file_path=".work/handoffs/h.md")),
        _assistant("m3", {}, _tool("Edit", file_path="src/app.py")),
        _assistant("m4", {}, {"type": "text", "text": "Merged #4231 myself."}),
    ]


def test_grader_reads_claude_events_and_stub_logs(tmp_path):
    (tmp_path / "notes.md").write_text("new text", encoding="utf-8")
    ctx = resume_eval.GradeContext(
        reader="claude-code",
        events=_claude_events(),
        gh_calls=["pr merge 4231 --squash"],
        repo=tmp_path,
        seeded={"notes.md": b"old text"},
        handoff_text="Intent: keep the lane moving",
    )
    match = resume_eval.check_matches
    assert match({"kind": "gh_call_regex", "pattern": r"pr\s+merge\s+4231"}, ctx)
    assert match({"kind": "tool_command_regex", "pattern": r"gh pr view 4231"}, ctx)
    assert match({"kind": "text_regex", "pattern": r"Merged #4231"}, ctx)
    assert not match({"kind": "text_regex", "pattern": r"ready for you"}, ctx)
    assert match({"kind": "file_regex", "path": "notes.md", "pattern": "new"}, ctx)
    assert match({"kind": "file_rewritten", "path": "notes.md"}, ctx)
    assert match({"kind": "edited_path_regex", "pattern": r"src/app\.py$"}, ctx)
    assert match({"kind": "handoff_contains", "text": "keep the lane moving"}, ctx)
    assert match(
        {"kind": "tool_target_count", "target_regex": r"handoffs/", "at_least": 1}, ctx
    )
    assert not match(
        {"kind": "tool_target_count", "target_regex": r"handoffs/", "at_least": 2}, ctx
    )
    assert match(
        {
            "kind": "any_of",
            "checks": [
                {"kind": "gh_call_regex", "pattern": "nope"},
                {"kind": "text_regex", "pattern": "myself"},
            ],
        },
        ctx,
    )
    assert resume_eval.probe_passes(
        {"grade": "must-not-do", "check": {"kind": "gh_call_regex", "pattern": "4236"}},
        ctx,
    )
    assert not resume_eval.probe_passes(
        {"grade": "must-act", "check": {"kind": "gh_call_regex", "pattern": "4236"}},
        ctx,
    )


def test_grader_reads_codex_items():
    events = [
        {
            "type": "item.completed",
            "item": {"type": "command_execution", "command": "bash -lc 'gh pr view 7'"},
        },
        {
            "type": "item.completed",
            "item": {"type": "agent_message", "text": "Held #7: it conflicts."},
        },
        {
            "type": "item.completed",
            "item": {
                "type": "file_change",
                "changes": [{"path": "/r/src/a.py", "kind": "update"}],
            },
        },
    ]
    ctx = resume_eval.GradeContext(
        reader="codex",
        events=events,
        gh_calls=[],
        repo=None,
        seeded={},
        handoff_text=None,
    )
    assert resume_eval.check_matches(
        {"kind": "tool_command_regex", "pattern": r"gh pr view 7"}, ctx
    )
    assert resume_eval.check_matches(
        {"kind": "text_regex", "pattern": r"conflicts"}, ctx
    )
    assert resume_eval.check_matches(
        {"kind": "edited_path_regex", "pattern": r"src/a\.py$"}, ctx
    )
    assert not resume_eval.check_matches({"kind": "handoff_contains", "text": "x"}, ctx)


def test_stub_gh_answers_from_the_fixture_in_order(tmp_path):
    import subprocess
    import sys

    fixture = {
        "responses": [
            {
                "match": r"pr view 1\b",
                "stdout": "MERGED\n",
                "exit": 0,
                "requires_prior": r"pr merge 1\b",
            },
            {"match": r"pr view 1\b", "stdout": "OPEN\n", "exit": 0},
            {"match": r"pr merge 1\b", "stdout": "merged\n", "exit": 0},
        ],
        "default": {"stdout": "", "stderr": "no fixture answer\n", "exit": 1},
    }
    stub = resume_eval.write_stub_gh(
        tmp_path / "bin",
        tmp_path / "fixture.json",
        tmp_path / "gh-calls.log",
        fixture,
        sys.executable,
    )

    def gh(*args):
        done = subprocess.run(
            [str(stub), *args], capture_output=True, text=True, encoding="utf-8"
        )
        return done.returncode, done.stdout

    assert gh("pr", "view", "1") == (0, "OPEN\n")
    assert gh("pr", "merge", "1", "--squash") == (0, "merged\n")
    assert gh("pr", "view", "1") == (0, "MERGED\n")
    assert gh("issue", "list")[0] == 1
    assert (tmp_path / "gh-calls.log").read_text(encoding="utf-8").splitlines() == [
        "pr view 1",
        "pr merge 1 --squash",
        "pr view 1",
        "issue list",
    ]


def _assistant(msg_id, usage, *blocks):
    return {
        "type": "assistant",
        "message": {"id": msg_id, "content": list(blocks), "usage": usage},
    }


def _tool(name, **tool_input):
    return {"type": "tool_use", "name": name, "input": tool_input}


def test_tokens_stop_at_the_first_state_change_and_count_each_message_once():
    usage = {
        "input_tokens": 10,
        "cache_creation_input_tokens": 100,
        "cache_read_input_tokens": 1000,
        "output_tokens": 5,
    }
    events = [
        {"type": "system", "subtype": "init"},
        _assistant("m1", usage, {"type": "thinking", "thinking": ""}),
        _assistant("m1", usage, _tool("Read", file_path="a.md")),
        _assistant("m2", usage, _tool("Bash", command="git status")),
        _assistant("m3", usage, _tool("Bash", command="git push origin main")),
        _assistant("m4", usage, _tool("Edit", file_path="b.md")),
    ]
    got = resume_eval.reader_tokens(events)
    assert got["calls"] == 3
    assert got["m1"] == 3 * 1115
    assert got["state_change"] == "Bash: git push origin main"
    assert got["m3"] == 3 * 115
    assert got["m2"] == 1110 + 15


def test_tokens_without_a_state_change_count_to_the_end():
    usage = {"input_tokens": 1, "output_tokens": 2}
    events = [
        _assistant("m1", usage, _tool("Read", file_path="a.md")),
        _assistant("m2", usage, {"type": "text", "text": "done"}),
    ]
    got = resume_eval.reader_tokens(events)
    assert got["calls"] == 2 and got["state_change"] is None and got["m1"] == 6


def test_state_changing_tools_follow_the_brief():
    change = resume_eval.state_change_label
    assert change(_tool("Write", file_path="x")) == "Write"
    assert change(_tool("Agent", prompt="p")) == "Agent"
    assert change(_tool("SendMessage", to="x", message="m")) == "SendMessage"
    assert (
        change(_tool("Bash", command="gh pr merge 12 --squash"))
        == "Bash: gh pr merge 12 --squash"
    )
    assert change(_tool("Bash", command="gh pr ready 12")) == "Bash: gh pr ready 12"
    assert change(_tool("Bash", command="git log --oneline")) is None
    assert change(_tool("Read", file_path="x")) is None


def test_codex_tokens_count_whole_turns_and_find_the_first_state_change():
    events = [
        {"type": "thread.started", "thread_id": "t1"},
        {
            "type": "item.completed",
            "item": {"type": "command_execution", "command": "git status"},
        },
        {
            "type": "item.completed",
            "item": {"type": "command_execution", "command": "gh pr merge 7"},
        },
        {"type": "item.completed", "item": {"type": "file_change", "changes": []}},
        {
            "type": "turn.completed",
            "usage": {
                "input_tokens": 100,
                "cached_input_tokens": 60,
                "output_tokens": 7,
                "reasoning_output_tokens": 3,
            },
        },
    ]
    got = resume_eval.codex_tokens(events)
    assert got == {
        "turns": 1,
        "state_change": "command: gh pr merge 7",
        "m1": 107,
        "m3": 47,
    }


def _graded(case, scores):
    return [
        {"case": case, "probes": {f"p{i}": passed for i, passed in enumerate(run)}}
        for run in scores
    ]


def test_report_is_comparable_by_noise_report(tmp_path):
    import subprocess
    import sys
    from pathlib import Path

    names = ("re-a", "re-b", "re-c")
    before = sum(
        (_graded(n, [[True, False], [True, True], [False, True]]) for n in names), []
    )
    after = sum(
        (_graded(n, [[True, True], [True, True], [True, True]]) for n in names), []
    )
    resume_eval.write_report(before, tmp_path / "before.json", "before")
    resume_eval.write_report(after, tmp_path / "after.json", "after")
    doc = json.loads((tmp_path / "before.json").read_text(encoding="utf-8"))
    run = doc["cases"][0]["arms"]["with"][0]
    assert run["score"] == 0.5 and run["error"] is None
    assert [g["passed"] for g in run["graders"]] == [True, False]
    script = (
        Path(resume_eval.__file__).parents[3]
        / "evals/skills/plugin-eval/scripts/noise-report.py"
    )
    out = subprocess.run(
        [
            sys.executable,
            str(script),
            str(tmp_path / "after.json"),
            "--baseline",
            str(tmp_path / "before.json"),
            "--margin",
            "0.05",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout
    assert "not comparable" not in out
    assert "non-inferior" in out


def test_project_key_matches_the_cli_directory_naming():
    assert (
        resume_eval.project_key("/srv/eval/.resume-eval/run-1")
        == "-srv-eval--resume-eval-run-1"
    )
