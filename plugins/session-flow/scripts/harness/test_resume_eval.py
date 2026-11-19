"""Contract tests for resume_eval.py. No test reaches the API or a CLI."""

import json
import os

# The suite builds throwaway git repositories. Under an inherited absolute
# GIT_DIR (or GIT_WORK_TREE / GIT_CONFIG) git would write into the caller's
# repository instead, so clear the ambient git environment once, before any
# fixture is built (scripts/check-fixture-git-isolation.sh).
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

import resume_eval  # noqa: E402

PLUGIN = resume_eval.HERE.parents[1]


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


def test_interval_and_case_drop_match_plugin_evals_noise_report():
    import importlib.util
    from pathlib import Path

    here = Path(__file__).resolve().parent
    path = here.parents[2] / "evals/skills/plugin-eval/scripts/noise-report.py"
    spec = importlib.util.spec_from_file_location("noise_report", path)
    noise = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(noise)
    assert resume_eval.DROP == noise.DROP and resume_eval.Z95 == noise.Z95
    for values, low, high in (
        ([0.1, -0.2, 0.05, 0.3], -1.0, 1.0),
        ([0.9, 1.0, 0.95], -1.0, 1.0),
        ([1200.0, -400.0, 35.0], float("-inf"), float("inf")),
    ):
        assert resume_eval.normal_interval(values, low, high) == noise.normal_interval(
            values, low, high
        )


def test_child_env_turns_off_commit_signing_for_throwaway_repos():
    env = resume_eval.child_env(
        {"PATH": "/usr/bin", "GIT_CONFIG_COUNT": "1"},
        tmpdir="/e/t",
        stub_bin="/e/bin",
        gh_config="/e/gh",
    )
    pairs = {
        env[f"GIT_CONFIG_KEY_{i}"]: env[f"GIT_CONFIG_VALUE_{i}"]
        for i in range(int(env["GIT_CONFIG_COUNT"]))
    }
    assert pairs == {"commit.gpgsign": "false", "tag.gpgsign": "false"}


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
    # Not --ephemeral: the follow-up turn resumes the thread, which needs its rollout on
    # disk; the harness moves the rollout out of the Codex store after the run.
    assert "--ephemeral" not in cmd and "--ignore-user-config" in cmd
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
        and "Bash(git ls-remote https *)" in deny
        and "Bash(git ls-remote git@*)" in deny
    )
    assert not {"Bash(git ls-remote *)", "Bash(git ls-remote:*)"} & set(deny)
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
    assert match({"kind": "handoff_regex", "pattern": r"Intent:\s+keep"}, ctx)
    assert not match({"kind": "handoff_regex", "pattern": r"archive/"}, ctx)
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


def test_after_limits_a_check_to_what_followed_its_gate():
    ctx = resume_eval.GradeContext(
        reader="claude-code",
        events=[],
        gh_calls=["release view v2", "workflow run cut-release.yml", "run watch 9"],
        repo=None,
        seeded={},
        handoff_text=None,
    )
    watch = {
        "kind": "gh_call_regex",
        "pattern": r"release view|run watch",
        "after": r"workflow run cut-release",
    }
    assert resume_eval.check_matches(watch, ctx)
    ctx.gh_calls = ["release view v2", "workflow run cut-release.yml"]
    assert not resume_eval.check_matches(watch, ctx)
    ctx.gh_calls = ["release view v2"]
    assert not resume_eval.check_matches(watch, ctx)


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


def test_history_can_continue_an_existing_chain():
    first = [
        json.loads(x)
        for x in resume_eval.render_history([{"role": "user", "text": "a"}], "s", "/w")
    ]
    more = [
        json.loads(x)
        for x in resume_eval.render_history(
            [{"role": "assistant", "text": "b"}],
            "s",
            "/w",
            parent=first[-1]["uuid"],
            salt="hop4/",
        )
    ]
    assert more[0]["parentUuid"] == first[-1]["uuid"]
    assert more[0]["uuid"] != first[0]["uuid"]


def test_exclusion_ignores_limit_words_in_conversation_text():
    """A seeded lane history or a case prompt may mention usage limits; only the CLI's
    own error result or stderr marks a run as limit-hit."""
    talk = [
        {
            "type": "user",
            "message": {
                "content": "the lane hit its usage limit yesterday; rate limit reached twice"
            },
        },
        {
            "type": "result",
            "result": "Noted the usage limit history.",
            "num_turns": 1,
            "is_error": False,
        },
    ]
    stdout = "\n".join(json.dumps(e) for e in talk)
    assert resume_eval.exclusion_reason(0, stdout, "", talk) is None
    hit = [
        {
            "type": "result",
            "result": "You've hit your session limit · resets 4pm",
            "num_turns": 1,
            "is_error": True,
        }
    ]
    assert resume_eval.exclusion_reason(1, json.dumps(hit[0]), "", hit) is not None
    assert (
        resume_eval.exclusion_reason(1, "", "Error: rate limit exceeded", [])
        is not None
    )


def test_codex_rollouts_move_out_of_the_store_by_thread_id(tmp_path):
    store = tmp_path / "sessions" / "2026" / "10" / "24"
    store.mkdir(parents=True)
    mine = store / "rollout-2026-10-24T15-00-00-thread-a.jsonl"
    other = store / "rollout-2026-10-24T15-00-01-thread-b.jsonl"
    mine.write_text("a\n", encoding="utf-8")
    other.write_text("b\n", encoding="utf-8")
    keep = tmp_path / "keep"
    moved = resume_eval.move_codex_rollouts(["thread-a"], tmp_path / "sessions", keep)
    assert moved == 1 and not mine.exists() and other.exists()
    assert (keep / mine.name).read_text(encoding="utf-8") == "a\n"


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


def _job_runner(errors, ran):
    """A run_once stand-in: records each job and writes its graded.json as run_once does."""

    def run(case, arm, readers, index, out_dir):
        ran.append(index)
        results = [
            {
                "case": case["name"],
                "arm": arm,
                "reader": r,
                "index": index,
                "error": errors.get(index),
            }
            for r in readers
        ]
        keep = out_dir / case["name"] / arm / str(index)
        keep.mkdir(parents=True, exist_ok=True)
        (keep / "graded.json").write_text(json.dumps(results), encoding="utf-8")
        return results

    return run


def test_run_jobs_stops_at_the_first_limit_and_appends_each_run(tmp_path):
    case = {"name": "re-a"}
    jobs = [(case, "before", ["codex"], i) for i in range(5)]
    ran = []
    errors = {1: "reader: You've hit your session limit · resets 4pm"}
    code = resume_eval.run_jobs(jobs, _job_runner(errors, ran), tmp_path, 1)
    assert code == 4 and ran == [0, 1]
    rows = [
        json.loads(line)
        for line in (tmp_path / "graded.jsonl").read_text(encoding="utf-8").splitlines()
    ]
    assert [r["index"] for r in rows] == [0, 1]


def test_run_jobs_skips_runs_already_graded_without_error(tmp_path):
    case = {"name": "re-a"}
    jobs = [(case, "before", ["codex"], i) for i in range(3)]
    resume_eval.run_jobs(
        jobs, _job_runner({1: "reader: CLI exited 1: boom"}, []), tmp_path, 1
    )
    ran = []
    code = resume_eval.run_jobs(jobs, _job_runner({}, ran), tmp_path, 1)
    assert code == 0 and ran == [1]


def test_run_jobs_starts_no_more_than_the_writer_run_budget(tmp_path):
    case = {"name": "re-a"}
    jobs = [(case, "before", ["codex"], i) for i in range(5)]
    ran = []
    code = resume_eval.run_jobs(jobs, _job_runner({}, ran), tmp_path, 2, max_new=2)
    assert code == 0 and sorted(ran) == [0, 1]
    ran.clear()
    resume_eval.run_jobs(jobs, _job_runner({}, ran), tmp_path, 2, max_new=2)
    assert sorted(ran) == [2, 3]


def test_report_keeps_the_last_row_per_run_and_counts_every_exclusion(tmp_path, capsys):
    def row(index, error):
        return {
            "case": "re-a",
            "arm": "before",
            "reader": "codex",
            "index": index,
            "error": error,
            "probes": {"p": True},
        }

    graded = tmp_path / "graded.jsonl"
    graded.write_text(
        "".join(
            json.dumps(r) + "\n"
            # index 0 re-ran because its other reader errored; index 1 re-ran after an error
            for r in (
                row(0, None),
                row(0, None),
                row(1, "reader: CLI exited 1"),
                row(1, None),
            )
        ),
        encoding="utf-8",
    )
    code = resume_eval.main(
        ["report", "--graded", str(graded), "--out", str(tmp_path / "rep")]
    )
    assert "before.codex: 2 kept, 1 excluded" in capsys.readouterr().out
    assert code == 0


def test_one_before_run_flows_from_seed_to_graded_probes(tmp_path):
    """Real git and real seeding; every `claude` call is faked."""
    import subprocess
    import sys
    from pathlib import Path

    here = Path(resume_eval.__file__).resolve().parent
    case = resume_eval.load_cases(here.parents[1] / "evals", ["re-stale-github-fact"])[
        0
    ]
    origin = tmp_path / "base"
    origin.mkdir()
    (origin / "README.md").write_text("base\n", encoding="utf-8")
    for args in (
        ["init", "-q", "-b", "main"],
        ["add", "-A"],
        [
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@e",
            "commit",
            "-q",
            "-m",
            "chore: base",
        ],
    ):
        subprocess.run(["git", *args], cwd=origin, check=True)
    subprocess.run(
        ["git", "remote", "add", "origin", str(origin)], cwd=origin, check=True
    )
    calls = []

    def fake(cmd, cwd, env, stdin_text=None):
        if cmd[0] == "codex":
            prompt = cmd[-1]
            calls.append("codex: " + prompt)
            if "Read @fake" in prompt:
                subprocess.run(
                    [str(Path(cwd).parent / "bin" / "gh"), "pr", "view", "9"],
                    env=env,
                    capture_output=True,
                )
            events = [
                {"type": "thread.started", "thread_id": "th-1"},
                {
                    "type": "item.completed",
                    "item": {"type": "agent_message", "text": "1. answer"},
                },
                {
                    "type": "turn.completed",
                    "usage": {"input_tokens": 5, "output_tokens": 2},
                },
            ]
            return 0, "\n".join(json.dumps(e) for e in events), ""
        if cmd[0] != "claude":
            done = subprocess.run(
                cmd,
                cwd=cwd,
                env={
                    **env,
                    "GIT_AUTHOR_NAME": "t",
                    "GIT_AUTHOR_EMAIL": "t@e",
                    "GIT_COMMITTER_NAME": "t",
                    "GIT_COMMITTER_EMAIL": "t@e",
                },
                capture_output=True,
                text=True,
            )
            return done.returncode, done.stdout, done.stderr
        if "--no-session-persistence" in cmd:
            # A text-probe judge vote: the CLI's `--output-format json` reply.
            return 0, json.dumps({"result": "FAIL: fake judge", "is_error": False}), ""
        prompt = cmd[-1]
        calls.append(prompt)
        if prompt.startswith("/session-flow:handoff"):
            made = Path(cwd) / ".work" / "handoffs" / "29990101T000000Z-handoff-fake.md"
            made.write_text("# fake handoff\n", encoding="utf-8")
            text = (
                "`/clear`, then copy everything between the dashed lines:\n\n"
                + "─" * 20
                + "\nRead @fake. Continue.\n"
                + "─" * 20
            )
        elif prompt.startswith("Answer each question"):
            text = "1. answer"
        else:
            text = "ok"
            if "Read @fake" in prompt:
                subprocess.run(
                    [str(Path(cwd).parent / "bin" / "gh"), "pr", "view", "4318"],
                    env=env,
                    capture_output=True,
                )
        events = [
            {"type": "system", "subtype": "init", "session_id": "sess-1"},
            {
                "type": "assistant",
                "message": {
                    "id": f"m{len(calls)}",
                    "content": [{"type": "text", "text": text}],
                    "usage": {"input_tokens": 10, "output_tokens": 1},
                },
            },
            {
                "type": "result",
                "result": text,
                "num_turns": 1,
                "is_error": False,
                "session_id": "sess-1",
            },
        ]
        return 0, "\n".join(json.dumps(e) for e in events), ""

    case["seed"]["predecessor"]["shape"] = 2
    cfg = resume_eval.RunConfig(
        root=tmp_path / "root",
        tmpdir=str(tmp_path),
        copies={"before": str(PLUGIN)},
        codex_model="m",
        call=fake,
        python=sys.executable,
    )
    home = tmp_path / "home"
    old_home = os.environ.get("HOME")
    os.environ["HOME"] = str(home)
    try:
        both = resume_eval.run_once(
            case, "before", ["claude-code", "codex"], 0, origin, cfg, tmp_path / "out"
        )
        graded = both[0]
    finally:
        os.environ["HOME"] = old_home or ""
    assert graded["error"] is None, graded
    assert calls[0] == case["writer"]["interrupt"]["text"]
    assert calls[1] == case["writer"]["prompts"]["before"]
    assert calls[2] == "Read @fake. Continue."
    assert set(graded["probes"]) == {
        p["id"] for p in case["probes"] if "before" in p.get("arms", resume_eval.ARMS)
    }
    assert graded["m1"] == 11 + 11
    assert graded["reader_m1"] == 11 and graded["reader_whole_m1"] == 11
    assert len(graded["seed_hash"]) == 64
    kept = tmp_path / "out" / case["name"] / "before" / "0" / "claude-code"
    assert (
        (kept / "gh-calls.log").read_text(encoding="utf-8").startswith("pr view 4318")
    )
    assert not (cfg.root / "runs" / case["name"] / "before" / "0").exists()
    assert not any((home / ".claude" / "projects").iterdir())
    codex = both[1]
    assert codex["reader"] == "codex" and codex["error"] is None, codex
    assert codex["reader_m1"] == 7 and codex["seed_hash"] == graded["seed_hash"]
    assert codex["m1"] == 11 + 7
    assert sum(1 for c in calls if c == case["writer"]["prompts"]["before"]) == 1
    kept_codex = tmp_path / "out" / case["name"] / "before" / "0" / "codex"
    assert (kept_codex / "gh-calls.log").read_text(encoding="utf-8").splitlines() == [
        "pr view 9"
    ]
    assert (kept / "gh-calls.log").read_text(encoding="utf-8").splitlines() == [
        "pr view 4318"
    ]


def test_multi_hop_writes_one_handoff_per_hop_and_applies_scripted_turns(tmp_path):
    import subprocess
    import sys
    from pathlib import Path

    here = Path(resume_eval.__file__).resolve().parent
    case = resume_eval.load_cases(here.parents[1] / "evals", ["re-multi-hop"])[0]
    origin = tmp_path / "base"
    origin.mkdir()
    (origin / "README.md").write_text("base\n", encoding="utf-8")
    for args in (
        ["init", "-q", "-b", "main"],
        ["add", "-A"],
        [
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@e",
            "commit",
            "-q",
            "-m",
            "chore: base",
        ],
    ):
        subprocess.run(["git", *args], cwd=origin, check=True)
    subprocess.run(
        ["git", "remote", "add", "origin", str(origin)], cwd=origin, check=True
    )
    calls, made = [], []

    def fake(cmd, cwd, env, stdin_text=None):
        if cmd[0] != "claude":
            done = subprocess.run(
                cmd,
                cwd=cwd,
                env={
                    **env,
                    "GIT_AUTHOR_NAME": "t",
                    "GIT_AUTHOR_EMAIL": "t@e",
                    "GIT_COMMITTER_NAME": "t",
                    "GIT_COMMITTER_EMAIL": "t@e",
                },
                capture_output=True,
                text=True,
            )
            return done.returncode, done.stdout, done.stderr
        prompt = cmd[-1]
        resume = cmd[cmd.index("--resume") + 1] if "--resume" in cmd else None
        calls.append((resume, prompt))
        sid = resume or f"hop-session-{len(calls)}"
        if prompt.startswith("/session-flow:handoff"):
            path = (
                Path(cwd)
                / ".work"
                / "handoffs"
                / f"2999010{len(made)}T000000Z-handoff-fake.md"
            )
            path.write_text("# hop handoff\n" * (len(made) + 1), encoding="utf-8")
            made.append(path)
            text = (
                "`/clear`, then copy everything between the dashed lines:\n\n"
                + "─" * 20
                + f"\nRead @{path.name}.\n"
                + "─" * 20
            )
        else:
            text = "ok"
        events = [
            {"type": "system", "subtype": "init", "session_id": sid},
            {
                "type": "assistant",
                "message": {
                    "id": f"m{len(calls)}",
                    "content": [{"type": "text", "text": text}],
                    "usage": {"input_tokens": 1, "output_tokens": 1},
                },
            },
            {
                "type": "result",
                "result": text,
                "num_turns": 1,
                "is_error": False,
                "session_id": sid,
            },
        ]
        if resume and resume.startswith("hop-session-"):
            keydir = (
                Path(env["HOME"])
                / ".claude"
                / "projects"
                / resume_eval.project_key(cwd)
            )
            keydir.mkdir(parents=True, exist_ok=True)
            with (keydir / f"{resume}.jsonl").open("a", encoding="utf-8") as handle:
                handle.write(
                    json.dumps(
                        {
                            "type": "user",
                            "uuid": f"u-{len(calls)}",
                            "message": {"role": "user", "content": prompt},
                        }
                    )
                    + "\n"
                )
        return 0, "\n".join(json.dumps(e) for e in events), ""

    case["seed"]["predecessor"]["shape"] = 2
    cfg = resume_eval.RunConfig(
        root=tmp_path / "root",
        tmpdir=str(tmp_path),
        copies={"before": str(PLUGIN)},
        codex_model="m",
        call=fake,
        python=sys.executable,
    )
    home = tmp_path / "home"
    old_home = os.environ.get("HOME")
    os.environ["HOME"] = str(home)
    try:
        run = resume_eval.seed_run(case, cfg.root / "r", origin, cfg, "before")
        written = resume_eval.write_stage(case, "before", run, cfg)
    finally:
        os.environ["HOME"] = old_home or ""
    assert written.get("excluded") is None, written
    hops = case["writer"]["hops"]
    assert len(made) == len(hops)
    assert written["handoff"] == made[-1]
    assert written["hop_bytes"] == [p.stat().st_size for p in made]
    sent = [prompt for _resume, prompt in calls]
    for hop in hops[1:]:
        for turn in hop.get("owner_turns", []):
            assert turn in sent
    assert sent.count(case["writer"]["prompts"]["before"]) == len(hops)
    for hop in hops:
        for rel in (hop.get("effects") or {}).get("files", {}):
            assert (run["repo"] / rel).is_file()
    scripted = [
        t["text"]
        for hop in hops
        for t in [*hop.get("scripted_agent_turns", []), *hop.get("scripted_turns", [])]
        if t.get("text")
    ]
    transcripts = "".join(
        p.read_text(encoding="utf-8") for p in run["keydir"].glob("*.jsonl")
    )
    assert scripted and all(text in transcripts for text in scripted)
    # A scripted hop sends none of its turns live: only the interrupt and the arm prompt run.
    for hop in hops:
        if hop.get("scripted"):
            for turn in hop["scripted_turns"]:
                if turn["role"] == "user":
                    assert turn["text"] not in sent


def test_removing_one_run_leaves_runs_whose_index_shares_its_prefix(tmp_path):
    arm = tmp_path / "runs" / "case" / "before"
    for name in ("1", "1-claude", "1-codex", "10", "10-codex", "11", "2"):
        (arm / name).mkdir(parents=True)
    resume_eval.remove_run_dirs(arm / "1")
    assert sorted(p.name for p in arm.iterdir()) == ["10", "10-codex", "11", "2"]


def test_base_snapshot_takes_paths_with_spaces_and_shell_metacharacters(
    tmp_path, monkeypatch
):
    import subprocess

    for key in ("GIT_AUTHOR", "GIT_COMMITTER"):
        monkeypatch.setenv(f"{key}_NAME", "eval")
        monkeypatch.setenv(f"{key}_EMAIL", "eval@example.invalid")
    repo = tmp_path / "src dir;touch PWNED-1"
    repo.mkdir()
    (repo / "kept.txt").write_text("kept\n", encoding="utf-8")
    for args in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "seed"]):
        subprocess.run(["git", "-C", str(repo), *args], check=True)
    root = tmp_path / "eval root $(touch PWNED-2)"
    root.mkdir()
    cfg = resume_eval.RunConfig(
        root=root, tmpdir=str(tmp_path), copies={}, codex_model="unused"
    )
    base = resume_eval.build_base(repo, root, cfg)
    assert (base / "kept.txt").read_text(encoding="utf-8") == "kept\n"
    assert not list(tmp_path.rglob("PWNED-*"))


def test_writer_tokens_count_the_whole_writer_run_past_its_writes():
    def call(msg_id, tokens, *blocks):
        usage = {key: tokens for key in resume_eval.TOKEN_KEYS}
        return {
            "type": "assistant",
            "message": {"id": msg_id, "usage": usage, "content": list(blocks)},
        }

    write = {"type": "tool_use", "name": "Write", "input": {"file_path": "h.md"}}
    events = [call("m1", 10, write), call("m2", 5), call("m3", 1)]
    per_call = len(resume_eval.TOKEN_KEYS)
    assert resume_eval.reader_tokens(events)["m1"] == 10 * per_call
    assert resume_eval.writer_tokens(events)["m1"] == 16 * per_call
    assert resume_eval.writer_tokens(events)["calls"] == 3


def _judge_with(tmp_path, *replies):
    calls = iter(replies)
    cfg = resume_eval.RunConfig(
        root=tmp_path,
        tmpdir=str(tmp_path),
        copies={},
        codex_model="",
        call=lambda cmd, cwd, env, stdin_text=None: next(calls),
    )
    return resume_eval.make_judge(cfg, tmp_path)


def test_a_judge_usage_limit_excludes_the_run_instead_of_voting_fail(tmp_path):
    limit = (1, "", "You've hit your usage limit · resets 5pm")
    judge = _judge_with(tmp_path, limit, limit, limit)
    try:
        judge("q", "c", "a")
    except resume_eval.JudgeError as exc:
        assert resume_eval.EXCLUDE_MARKERS[1].search(str(exc)), str(exc)
    else:
        raise AssertionError("a usage limit was counted as a vote")


def test_the_limit_marker_matches_each_limit_message_wording():
    for message in (
        "You've hit your session limit · resets 4pm",
        "You've hit your 5-hour limit · resets 4pm",
        "You've hit your weekly limit · resets Nov 3, 9am",
        "You've hit your Fable weekly limit · resets Nov 3, 9am",
    ):
        assert resume_eval.EXCLUDE_MARKERS[1].search(message), message


def test_a_judge_reply_with_no_verdict_excludes_the_run(tmp_path):
    judge = _judge_with(tmp_path, (0, "not json", ""))
    try:
        judge("q", "c", "a")
    except resume_eval.JudgeError:
        pass
    else:
        raise AssertionError("an unparsable judge reply was counted as a vote")


def test_judge_votes_count_only_verdicts(tmp_path):
    passed = (0, json.dumps({"result": "PASS"}), "")
    failed = (0, json.dumps({"result": "FAIL: missing"}), "")
    assert _judge_with(tmp_path, passed, failed, passed)("q", "c", "a") is True
    assert _judge_with(tmp_path, failed, failed, passed)("q", "c", "a") is False


# --- shape-3 predecessors ---------------------------------------------------------

SUPERSEDED = "Also log every drain exit to stderr."
BINDING = "Never delete a telemetry row.\nThis binds every later hop."
NEWER = "Exit reasons go to telemetry only."
RETIRED_DECISION = "The drain cap is 42 items, settled with the owner."


def _shape3_spec(**overrides):
    pred = {
        "shape": 3,
        "topic": "drain-exit",
        "hops": 4,
        "start": "2026-07-06T08:00:00Z",
        "goal": "Make the drain exit deterministic.",
        "vision": "Telemetry says why a drain stopped.",
        "opening_ask": "Make the drain exit deterministic.",
        "injections": [
            {
                "id": "superseded",
                "hop": 2,
                "section": "amendment",
                "text": SUPERSEDED,
                "retire": {"hop": 3, "reason": "superseded by the hop-3 amendment"},
                "visible_in_reads": False,
            },
            {
                "id": "binding",
                "hop": 2,
                "section": "amendment",
                "text": BINDING,
                "visible_in_reads": True,
            },
            {"id": "newer", "hop": 3, "section": "amendment", "text": NEWER},
            {
                "id": "question",
                "hop": 1,
                "section": "open-questions",
                "text": "Which exit codes? Options: 0 or 1; recommendation: 0.",
                "retire": {"hop": 4, "reason": "answered: 0 and 1"},
            },
            {
                "id": "decision",
                "hop": 2,
                "section": "decisions",
                "text": RETIRED_DECISION,
                "retire": {"hop": 3, "reason": "moved to docs/work-loop.md"},
                "visible_in_reads": False,
            },
            {
                "id": "detour",
                "hop": 2,
                "section": "trail",
                "text": "detour to the flaky test (owner-directed)",
                "retire": {"hop": 4, "reason": "the detour closed"},
            },
            {
                "id": "rule",
                "hop": 3,
                "section": "rules",
                "text": "Rows are append-only.",
            },
        ],
    }
    pred.update(overrides)
    return {
        "name": "re-shape3-probe",
        "seed": {
            "predecessor": pred,
            "history": {"after_reads": "I've read the handoff."},
        },
    }


def _hop_file(chain, hop):
    found = list((chain[0].parent / "archive").glob(f"*/h{hop}-*.md"))
    assert len(found) == 1, found
    return found[0]


def _section(text, title):
    return text.split(f"\n## {title}\n", 1)[1].split("\n## ", 1)[0]


def _shape3_chain(tmp_path):
    import resume_cases

    spec = _shape3_spec()
    return spec, resume_cases.build_predecessor_chain(spec, tmp_path / "repo")


def test_shape3_keeps_live_amendments_and_lists_the_retired_one_in_its_hop_file(
    tmp_path,
):
    _, chain = _shape3_chain(tmp_path)
    newest = chain[-1].read_text(encoding="utf-8")
    assert "handoff_shape: 3" in newest
    goal = _section(newest, "Original goal")
    assert "**Amended (owner, 2026-07-06):** " + BINDING in goal
    assert "**Amended (owner, 2026-07-06):** " + NEWER in goal
    assert SUPERSEDED not in newest
    listed = _section(
        _hop_file(chain, 3).read_text(encoding="utf-8"), "Retired goal amendments"
    )
    assert (
        f"**Amended (owner, 2026-07-06):** {SUPERSEDED}\n"
        "Retired: superseded by the hop-3 amendment"
    ) in listed
    review = _section(newest, "Review before you continue").split("\n")
    pointer = f"{_hop_file(chain, 3).name} § Retired goal amendments"
    assert any(pointer in line for line in review), review


def test_shape3_retires_ids_and_trail_lines_through_fill(tmp_path):
    _, chain = _shape3_chain(tmp_path)
    newest = chain[-1].read_text(encoding="utf-8")
    hop3 = _hop_file(chain, 3).read_text(encoding="utf-8")
    hop4 = _hop_file(chain, 4).read_text(encoding="utf-8")
    decision = _section(hop3, "Retired decisions")
    assert f"] {RETIRED_DECISION}\nRetired: moved to docs/work-loop.md" in decision
    assert (
        decision.split(f"] {RETIRED_DECISION}")[0].rsplit("- [", 1)[1].startswith("D")
    )
    assert RETIRED_DECISION not in newest
    question = _section(hop4, "Retired open questions")
    assert (
        "Which exit codes? Options: 0 or 1; recommendation: 0.\nRetired: answered: 0 and 1"
        in question
    )
    assert (
        "- [h2] detour to the flaky test (owner-directed)\nRetired: the detour closed"
        in _section(hop4, "Retired direction changes")
    )
    assert "Rows are append-only." in _section(newest, "Current rules")
    for title, prefix in (("Open questions", "Q"), ("Decisions in force", "D")):
        entries = [e for e in _section(newest, title).split("\n") if e.strip()]
        assert entries and all(e.startswith(f"- [{prefix}") for e in entries), entries


def test_shape3_chain_is_deterministic_and_a_successor_builds_on_it(tmp_path):
    import shutil
    import subprocess
    import sys
    from pathlib import Path

    import resume_cases

    spec, chain = _shape3_chain(tmp_path)
    first = {p.name: p.read_bytes() for p in chain}
    shutil.rmtree(tmp_path / "repo")
    again = resume_cases.build_predecessor_chain(spec, tmp_path / "repo")
    assert {p.name: p.read_bytes() for p in again} == first
    memory = tmp_path / "repo" / ".work"
    projects = memory / "predecessor-transcripts"
    sid = "11111111-2222-4333-8444-555555555555"
    (projects / "seed" / f"{sid}.jsonl").write_text("", encoding="utf-8")
    made = subprocess.run(
        [
            sys.executable,
            str(resume_cases.HERE.parent / "save_point.py"),
            "new",
            "--topic",
            "drain-exit",
            "--memory-dir",
            str(memory),
            "--repo-root",
            str(tmp_path / "repo"),
            "--projects-root",
            str(projects),
            "--session-id",
            sid,
            "--previous",
            str(again[-1]),
            "--now",
            "2027-01-01T00:00:00Z",
            "--shape",
            "3",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    assert made.returncode == 0, made.stderr
    successor = Path(made.stdout.strip()).read_text(encoding="utf-8")
    assert "UNVERIFIED" not in successor
    assert BINDING.split("\n")[0] in successor


def test_shape3_history_sees_live_amendments_and_not_retired_entries(tmp_path):
    import resume_cases

    spec, chain = _shape3_chain(tmp_path)
    turns = resume_cases.seed_history(spec, chain)
    seen = "\n".join(t["result"] for t in turns if t["role"] == "tool")
    assert BINDING.split("\n")[1] in seen
    assert SUPERSEDED not in seen and RETIRED_DECISION not in seen


def test_shape3_retires_the_named_amendment_when_another_one_contains_its_text(
    tmp_path,
):
    import resume_cases

    short, long = "Never delete rows", "Never delete rows, even on reruns."
    spec = _shape3_spec(
        hops=3,
        injections=[
            {"id": "long", "hop": 2, "section": "amendment", "text": long},
            {
                "id": "short",
                "hop": 2,
                "section": "amendment",
                "text": short,
                "retire": {"hop": 3, "reason": "folded into the longer amendment"},
            },
        ],
    )
    chain = resume_cases.build_predecessor_chain(spec, tmp_path / "repo")
    goal = _section(chain[-1].read_text(encoding="utf-8"), "Original goal")
    assert goal.count("Never delete rows") == 1 and long in goal
    listed = _section(
        _hop_file(chain, 3).read_text(encoding="utf-8"), "Retired goal amendments"
    )
    assert f":** {short}\nRetired: folded into the longer amendment" in listed


def test_shape3_spec_errors_are_refused_before_any_file_is_written(tmp_path):
    import resume_cases

    bad = (
        {"injections": [{"id": "x", "hop": 1, "section": "constraints", "text": "t"}]},
        {
            "injections": [
                {
                    "id": "x",
                    "hop": 2,
                    "section": "amendment",
                    "text": "t",
                    "retire": {"hop": 2, "reason": "r"},
                }
            ]
        },
        {
            "injections": [
                {
                    "id": "x",
                    "hop": 2,
                    "section": "amendment",
                    "text": "t",
                    "retire": {"hop": 3, "reason": " "},
                }
            ]
        },
        {
            "injections": [
                {"id": "x", "hop": 2, "section": "amendment", "text": "t\n**bold**"}
            ]
        },
        {"shape": 4},
    )
    for i, overrides in enumerate(bad):
        repo = tmp_path / str(i)
        try:
            resume_cases.build_predecessor_chain(_shape3_spec(**overrides), repo)
        except ValueError:
            assert not (repo / ".work" / "handoffs").exists(), overrides
        else:
            raise AssertionError(f"accepted {overrides}")


def _result(**fields):
    event = {"type": "result", "result": "ok", "num_turns": 1, "is_error": False}
    event.update(fields)
    return [event]


def test_a_behavior_failure_scores_0_and_an_infrastructure_one_is_re_run():
    S, C = resume_eval.Source, resume_eval.Cause
    cases = [
        (S.WRITER, 0, "", _result(num_turns=0), C.BEHAVIOR),
        (
            S.READER,
            0,
            "",
            _result(permission_denials=[{"tool_name": "Bash"}]),
            C.BEHAVIOR,
        ),
        (S.FOLLOW_UP, 0, "", _result(is_error=True, result="boom"), C.BEHAVIOR),
        (
            S.READER,
            1,
            "You've hit your session limit · resets 4pm",
            [],
            C.INFRASTRUCTURE,
        ),
        (
            S.WRITER,
            1,
            "Sandbox is required but failed to initialize",
            [],
            C.INFRASTRUCTURE,
        ),
        (S.READER, 7, "segfault", [], C.INFRASTRUCTURE),
        (S.JUDGE, 0, "", _result(num_turns=0), C.INFRASTRUCTURE),
    ]
    for source, code, err, events, cause in cases:
        out = "\n".join(json.dumps(e) for e in events)
        got = resume_eval.exclusion(source, code, out, err, events)
        assert got is not None and got.cause is cause, (source, err, events, got)
    assert resume_eval.exclusion(S.READER, 0, "", "", _result()) is None
    assert resume_eval.Exclusion(S.WRITER, resume_eval.Kind.NO_HANDOFF, "x").cause is (
        C.BEHAVIOR
    )


def test_codex_whole_run_tokens_count_turns_past_the_first_state_change():
    events = [
        {"type": "item.completed", "item": {"type": "file_change", "changes": []}},
        {"type": "turn.completed", "usage": {"input_tokens": 100, "output_tokens": 7}},
        {"type": "turn.completed", "usage": {"input_tokens": 40, "output_tokens": 3}},
    ]
    assert resume_eval.codex_tokens(events)["m1"] == 107
    whole = resume_eval.codex_tokens(events, whole=True)
    assert whole["m1"] == 150 and whole["turns"] == 2
    assert whole["state_change"] == "file_change"


def test_each_arm_seeds_with_its_own_copy_and_the_skill_less_arms_with_before():
    from pathlib import Path

    copies = {"before": "/c/before", "after": "/c/after", "compact": None}
    want = {
        "before": "/c/before",
        "after": "/c/after",
        "after-promoted": "/c/after",
        "compact": "/c/before",
        "free-hand": "/c/before",
    }
    for arm, root in want.items():
        got = resume_eval.seed_save_point(copies, arm)
        assert got == Path(root) / "scripts" / "save_point.py", arm
    try:
        resume_eval.seed_save_point({"after": "/c/after"}, "compact")
    except ValueError as exc:
        assert "before" in str(exc)
    else:
        raise AssertionError("seeded the compact arm with no before copy")


def test_run_jobs_counts_a_behavior_failure_done_and_re_runs_infrastructure(
    tmp_path, capsys
):
    case = {"name": "re-a"}
    jobs = [(case, "before", ["claude-code"], i) for i in range(3)]
    errors = {
        0: "writer produced no resume prompt or no new handoff file",
        1: "reader: marker: Sandbox is required but failed to initialize",
    }
    code = resume_eval.run_jobs(jobs, _job_runner(errors, []), tmp_path, 1)
    assert code == 6
    assert "1 run excluded for infrastructure" in capsys.readouterr().out
    ran = []
    assert resume_eval.run_jobs(jobs, _job_runner({}, ran), tmp_path, 1) == 0
    assert ran == [1]


def test_a_seed_that_differs_between_runs_fails_the_batch(tmp_path, capsys):
    case = {"name": "re-a"}
    jobs = [(case, "before", ["claude-code"], i) for i in range(4)]
    hashes = {0: "aa", 1: "aa", 2: "bb", 3: "aa"}

    def runner(case, arm, readers, index, out_dir):
        rows = _job_runner({}, [])(case, arm, readers, index, out_dir)
        for row in rows:
            row["seed_hash"] = hashes[index]
        return rows

    assert resume_eval.run_jobs(jobs, runner, tmp_path, 1) == 5
    assert "seed mismatch: case re-a arm before run 2" in capsys.readouterr().out
    lines = (tmp_path / "graded.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3


def test_run_refuses_an_arm_with_no_save_point_to_seed_from(tmp_path):
    assert (
        resume_eval.seed_problems({"before": str(PLUGIN)}, ["before", "compact"]) == []
    )
    problems = resume_eval.seed_problems(
        {"before": str(tmp_path)}, ["before", "free-hand"]
    )
    assert len(problems) == 2 and all("save_point.py" in p for p in problems)
    assert resume_eval.seed_problems({}, ["compact"])[0].startswith("no plugin copy")


CASE_PROBES = {
    "probes": [
        {"id": "acts", "grade": "must-act"},
        {"id": "handoff-only", "grade": "must-act", "arms": ["after"]},
        {"id": "after-acts", "grade": "must-act", "requires": "acts"},
        {"id": "answers", "grade": "text"},
    ]
}


def test_a_behavior_exclusion_scores_every_probe_of_the_run_0():
    S, K = resume_eval.Source, resume_eval.Kind
    row = {"probes": {}, "error": None}
    resume_eval.mark_excluded(
        row,
        resume_eval.Exclusion(S.WRITER, K.NO_HANDOFF, "writer: none"),
        CASE_PROBES,
        "before",
    )
    assert row["error"] is None and row["nondelivery"] == "writer: none"
    assert row["probes"] == {"acts": False, "answers": False}
    assert row["exclusion"] == {
        "source": "writer",
        "kind": "no-handoff",
        "cause": "behavior",
    }
    infra = {"probes": {}, "error": None}
    resume_eval.mark_excluded(
        infra,
        resume_eval.Exclusion(S.JUDGE, K.NO_VERDICT, "judge: x"),
        CASE_PROBES,
        "before",
    )
    assert infra["error"] == "judge: x" and infra["probes"] == {}
    assert "nondelivery" not in infra


def _row(case, arm, index, probes, reader="claude-code", **extra):
    return {
        "case": case,
        "arm": arm,
        "reader": reader,
        "index": index,
        "probes": probes,
        "error": None,
        **extra,
    }


def _graded_file(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return path


def _report(tmp_path, capsys, graded, *extra):
    args = ["report", "--out", str(tmp_path / "rep")]
    for path in graded:
        args += ["--graded", str(path)]
    code = resume_eval.main([*args, *extra])
    return code, capsys.readouterr().out


def _evals(tmp_path, specs):
    root = tmp_path / "evals"
    for spec in specs:
        (root / spec["name"]).mkdir(parents=True)
        (root / spec["name"] / "resume-eval.json").write_text(
            json.dumps(spec), encoding="utf-8"
        )
    return root


SINGLE_ARM = [
    _row(
        "re-a",
        "before",
        0,
        {"p1": True, "p2": True},
        reader_m1=100,
        reader_whole_m1=150,
    ),
    _row(
        "re-a",
        "before",
        1,
        {"p1": True, "p2": False},
        reader_m1=300,
        reader_whole_m1=350,
    ),
    {
        **_row("re-b", "before", 0, {}),
        "error": "writer produced no resume prompt or no new handoff file",
    },
    _row("re-b", "before", 1, {"p1": True}, reader_tokens={"m1": 50}),
]


def test_report_prints_accuracy_tokens_and_pass_counts_per_case(tmp_path, capsys):
    graded = _graded_file(tmp_path / "out" / "graded.jsonl", SINGLE_ARM)
    code, out = _report(tmp_path, capsys, [graded], "--threshold", "0.7")
    assert code == 0, out
    assert "before.claude-code: 4 kept, 0 excluded, 1 scored 0 for non-delivery" in out
    assert (
        "re-a: accuracy 0.75 over 2 runs; reader m1 200; whole-run m1 250; pass" in out
    )
    assert (
        "re-b: accuracy 0.50 over 2 runs; reader m1 50; whole-run m1 n/a; fail" in out
    )
    assert "pass count 1/2 at T=0.70" in out
    assert "left out" not in out
    doc = json.loads((tmp_path / "rep" / "before.claude-code.json").read_text())
    scores = {c["name"]: [r["score"] for r in c["arms"]["with"]] for c in doc["cases"]}
    assert scores == {"re-a": [1.0, 0.5], "re-b": [0.0, 1.0]}


def test_report_fails_on_an_excluded_or_missing_run(tmp_path, capsys):
    rows = [
        *SINGLE_ARM,
        {**_row("re-a", "before", 2, {}), "error": "reader: CLI exited 1: boom"},
    ]
    graded = _graded_file(tmp_path / "out" / "graded.jsonl", rows)
    code, out = _report(tmp_path, capsys, [graded])
    assert code == 1
    assert (
        "left out: case re-a in before.claude-code: run 2 excluded (reader: CLI exited 1: boom)"
        in out
    )
    assert "left out: case re-b in before.claude-code: run 2 has no row" in out


PAIR_SPECS = [
    {
        "name": name,
        "probes": [{"id": "p1"}, {"id": "p2", "arms": ["after"]}],
    }
    for name in ("re-a", "re-b", "re-c")
]


def _pair_rows():
    before = {"re-a": (True, True), "re-b": (True, False), "re-c": (True, True)}
    after = {"re-a": (True, True), "re-b": (True, True), "re-c": (False, True)}
    m1_before = {"re-a": 100, "re-b": 200, "re-c": 300}
    m1_after = {"re-a": 50, "re-b": 100, "re-c": 300}
    rows = []
    for case in before:
        for i in range(2):
            rows.append(
                _row(
                    case,
                    "before",
                    i,
                    {"p1": before[case][i]},
                    reader_m1=m1_before[case],
                )
            )
            rows.append(
                _row(
                    case,
                    "after",
                    i,
                    {"p1": after[case][i], "p2": False},
                    reader_m1=m1_after[case],
                )
            )
    return rows


def test_a_pair_scores_shared_probes_and_reports_drops_and_token_change(
    tmp_path, capsys
):
    import subprocess
    import sys

    graded = _graded_file(tmp_path / "out" / "graded.jsonl", _pair_rows())
    evals = _evals(tmp_path, PAIR_SPECS)
    code, out = _report(
        tmp_path,
        capsys,
        [graded],
        "--baseline",
        "before.claude-code",
        "--threshold",
        "0.9",
        "--evals-dir",
        str(evals),
    )
    assert code == 1, out
    pair = "after.claude-code vs before.claude-code"
    assert f"pair {pair}: accuracy change +0.00" in out
    assert (
        f"pair {pair}: reader m1 to first action change -50 (-25.0% of baseline)" in out
    )
    assert "case drop: case re-c in after.claude-code fell from 1.00 to 0.50" in out
    assert (
        "pass-to-fail: case re-c passes in before.claude-code (1.00) and fails in after.claude-code (0.50) at T=0.90"
        in out
    )
    assert "case drop: case re-a" not in out and "case drop: case re-b" not in out
    folder = tmp_path / "rep" / "pairs" / "after.claude-code--vs--before.claude-code"
    after = json.loads((folder / "after.claude-code.json").read_text())
    re_a = next(c for c in after["cases"] if c["name"] == "re-a")
    assert [g["name"] for g in re_a["arms"]["with"][0]["graders"]] == ["p1"]
    script = PLUGIN.parents[0] / "evals/skills/plugin-eval/scripts/noise-report.py"
    compared = subprocess.run(
        [
            sys.executable,
            str(script),
            str(folder / "after.claude-code.json"),
            "--baseline",
            str(folder / "before.claude-code.json"),
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "not comparable" not in compared and "case drop: case re-c" in compared


def test_two_graded_files_of_one_arm_stay_apart_for_an_a_a_pair(tmp_path, capsys):
    rows = [
        _row(c, "before", i, {"p1": True}) for c in ("re-a", "re-b") for i in range(2)
    ]
    first = _graded_file(tmp_path / "aa1" / "graded.jsonl", rows)
    second = _graded_file(tmp_path / "aa2" / "graded.jsonl", rows)
    evals = _evals(tmp_path, PAIR_SPECS)
    code, out = _report(
        tmp_path,
        capsys,
        [first, second],
        "--baseline",
        "before.claude-code@1",
        "--evals-dir",
        str(evals),
    )
    assert code == 0, out
    assert (
        "before.claude-code@1: 4 kept" in out and "before.claude-code@2: 4 kept" in out
    )
    assert (
        "pair before.claude-code@2 vs before.claude-code@1: accuracy change +0.00"
        in out
    )


def test_a_subset_keeps_its_tagged_cases_and_fails_on_an_untagged_one(tmp_path, capsys):
    rows = [_row(c, "before", 0, {"p1": True}) for c in ("re-a", "re-b", "re-c")]
    graded = _graded_file(tmp_path / "out" / "graded.jsonl", rows)
    specs = [
        {"name": "re-a", "task_relation": "same", "probes": []},
        {"name": "re-b", "task_relation": "boundary", "probes": []},
        {"name": "re-c", "probes": []},
    ]
    code, out = _report(
        tmp_path,
        capsys,
        [graded],
        "--subset",
        "same",
        "--evals-dir",
        str(_evals(tmp_path, specs)),
    )
    assert code == 1
    assert "re-a: accuracy" in out and "re-b: accuracy" not in out
    assert "untagged: case re-c has no task_relation" in out


def test_report_fails_when_a_case_was_seeded_differently(tmp_path, capsys):
    rows = [
        _row("re-a", "before", 0, {"p1": True}, seed_hash="a" * 64),
        _row("re-a", "before", 1, {"p1": True}, seed_hash="b" * 64),
    ]
    graded = _graded_file(tmp_path / "out" / "graded.jsonl", rows)
    code, out = _report(tmp_path, capsys, [graded])
    assert code == 1 and "seed mismatch: case re-a arm before" in out


def test_a_pair_fails_on_a_case_with_no_probe_both_sides_graded(tmp_path, capsys):
    rows = [
        _row(case, arm, 0, {f"{arm}-only": True})
        for case in ("re-a", "re-b")
        for arm in ("before", "after")
    ]
    graded = _graded_file(tmp_path / "out" / "graded.jsonl", rows)
    code, out = _report(
        tmp_path,
        capsys,
        [graded],
        "--baseline",
        "before.claude-code",
        "--evals-dir",
        str(tmp_path / "no-evals"),
    )
    assert code == 1, out
    pair = "after.claude-code vs before.claude-code"
    assert f"left out: case re-a has no probe both sides graded ({pair})" in out
