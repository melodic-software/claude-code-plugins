"""Contract tests for away.py: the step-away state, report, check and hook entry.

The CLI and every hook run as a subprocess with a temp HOME, config dir and plugin data root, so
the real ~/.claude is never read or written. Hook inputs follow the documented shapes
(https://code.claude.com/docs/en/hooks), and the transcript records are written by hand in the
shape session-flow's transcript_reader reads. Both live here rather than under fixtures/, whose
manifest test_save_point.py pins.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import pytest

for _leaked_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG", "GIT_INDEX_FILE"):
    os.environ.pop(_leaked_var, None)
del _leaked_var

SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "away.py"
SESSION = "11111111-2222-3333-4444-555555555555"
RULES_TAIL = "skills/step-away/reference/rules.md"
HEADINGS = ("Needs you", "Decided while you were away", "Waiting on me", "Done", "Found", "Additional notes")

sys.path.insert(0, str(SCRIPTS))
import away  # noqa: E402

DEFAULTS = {
    "away_night_start": "21:00",
    "away_report_by_workday": "09:00",
    "away_report_by_day_off": "10:00",
    "away_days_off": "Sat,Sun",
}

COMMON = {"session_id": "__SESSION__", "transcript_path": "__TRANSCRIPT__", "cwd": "__CWD__"}
HOOK_INPUTS = {
    "permission_request_bash": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_input": {"command": "git -C repo branch askme-main", "description": "Create a branch"},
        "permission_suggestions": [
            {
                "type": "addRules",
                "rules": [{"toolName": "Bash", "ruleContent": "git -C repo branch askme-main"}],
                "behavior": "allow",
                "destination": "localSettings",
            }
        ],
    },
    "permission_request_subagent": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "PermissionRequest",
        "agent_id": "a176806189f9a60c0",
        "agent_type": "general-purpose",
        "tool_name": "Bash",
        "tool_input": {"command": "git -C repo branch askme-sub", "description": "Create a branch"},
    },
    "elicitation_form": {
        **COMMON,
        "hook_event_name": "Elicitation",
        "mcp_server_name": "example-server",
        "message": "Please provide your username",
        "mode": "form",
        "requested_schema": {"type": "object", "properties": {"username": {"type": "string", "title": "Username"}}},
    },
    "stop": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "Stop",
        "stop_hook_active": False,
        "last_assistant_message": "Finished the first task.",
        "background_tasks": [],
        "session_crons": [],
    },
    "user_prompt_typed": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "UserPromptSubmit",
        "prompt": "I'm back, what happened overnight?",
    },
    "user_prompt_subagent_report": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "UserPromptSubmit",
        "prompt": (
            "<task-notification>\n<task-id>a5c1</task-id>\n<status>completed</status>\n"
            '<summary>Agent "Run the test suite" completed</summary>\n<result>All 42 tests passed.</result>\n'
            "</task-notification>"
        ),
    },
    "user_prompt_loop": {
        **COMMON,
        "permission_mode": "auto",
        "hook_event_name": "UserPromptSubmit",
        "prompt": "check the build",
    },
}

CLASSIFIER_TEXT = (
    "Error: Permission for this action was denied by the Claude Code auto mode classifier. Reason: "
    "[External System Write]. If you have other tasks that don't depend on this action, continue working on those."
)
HOOK_DENIAL_TEXT = "Error: PermissionRequest:Bash hook error: R1: refused because the person is away."


def tool_use(uid: str, ts: str, tool_id: str, name: str, tool_input: dict, **extra) -> dict:
    content = [{"type": "tool_use", "id": tool_id, "name": name, "input": tool_input}]
    return {"type": "assistant", "uuid": uid, "timestamp": ts, "message": {"role": "assistant", "content": content}, **extra}


def tool_result(uid: str, ts: str, tool_id: str, text: str, **extra) -> dict:
    content = [{"type": "tool_result", "tool_use_id": tool_id, "content": text, "is_error": "Error" in text}]
    return {"type": "user", "uuid": uid, "timestamp": ts, "toolUseResult": text, "message": {"role": "user", "content": content}, **extra}


MAIN_TRANSCRIPT = [
    tool_use("a0", "2000-01-01T00:00:00Z", "t0", "Bash", {"command": "git push origin before-the-absence"}),
    tool_use("a1", "2099-01-01T00:00:01Z", "t1", "Bash", {"command": "gh pr create --title 'Add widget' --body 'Adds it.'"}),
    tool_result("u1", "2099-01-01T00:00:02Z", "t1", "https://example.invalid/pull/1"),
    tool_use("a2", "2099-01-01T00:00:03Z", "t2", "Bash", {"command": "ls -la src"}),
    tool_use("a3", "2099-01-01T00:00:04Z", "t3", "mcp__tracker__create_issue", {"title": "Follow-up"}),
    tool_use("a4", "2099-01-01T00:00:05Z", "t4", "Bash", {"command": "curl -X POST https://example.invalid/api/deploy"}),
    tool_result(
        "u4", "2099-01-01T00:00:06Z", "t4", CLASSIFIER_TEXT,
        toolDenialKind="automode-blocked",
        permissionDecision={"decision": "reject", "source": "config", "reasonType": "classifier"},
    ),
    tool_use("a5", "2099-01-01T00:00:07Z", "t5", "Bash", {"command": "git -C repo branch askme-main"}),
    tool_result(
        "u5", "2099-01-01T00:00:08Z", "t5", HOOK_DENIAL_TEXT,
        toolDenialKind="permission-rule",
        permissionDecision={"decision": "reject", "source": "hook", "reasonType": "hook"},
    ),
]
SUBAGENT_TRANSCRIPT = [
    tool_use("s1", "2099-01-01T00:01:00Z", "st1", "Bash", {"command": "git push origin feat-from-subagent"}, isSidechain=True),
    tool_use("s2", "2099-01-01T00:01:01Z", "st2", "Read", {"file_path": "README.md"}, isSidechain=True),
]
SUBAGENT_META = {"agentType": "general-purpose", "description": "Push the follow-up branch"}


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")


class Away:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.data = root / "data"
        self.home = root / "home"
        self.config = self.home / ".claude"
        self.repo = root / "repo"
        self.config.mkdir(parents=True)
        self.repo.mkdir()
        git("init", "-q", str(self.repo))

    @property
    def state_dir(self) -> Path:
        return self.data / "away" / SESSION

    def env(self, **extra: str) -> dict[str, str]:
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE_", "GIT_"))}
        env.update(HOME=str(self.home), CLAUDE_CONFIG_DIR=str(self.config), CLAUDE_PLUGIN_DATA=str(self.data))
        env.update(extra)
        return env

    def run(self, *args: str, stdin: str | None = None, cwd: Path | None = None, env: dict | None = None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=stdin,
            capture_output=True,
            text=True,
            cwd=str(cwd or self.repo),
            env=env or self.env(),
            timeout=60,
        )

    def cli(self, command: str, *args: str, **kwargs):
        return self.run(command, "--session", SESSION, *args, **kwargs)

    def start(self, *args: str, **kwargs):
        result = self.cli("start", *(args or ("--kind", "trip")), **kwargs)
        assert result.returncode == 0, result.stderr
        return result

    def hook(self, event: str, fixture: str, session: str = SESSION, **overrides):
        payload = json.loads(json.dumps(HOOK_INPUTS[fixture]))
        payload.update(session_id=session, cwd=str(self.repo), transcript_path=str(self.root / "t.jsonl"))
        payload.update(overrides)
        result = self.run("hook", event, stdin=json.dumps(payload))
        assert result.returncode == 0, result.stderr
        return result.stdout

    def state(self) -> dict:
        return json.loads((self.state_dir / "state.json").read_text(encoding="utf-8"))

    def refused(self) -> list[dict]:
        path = self.state_dir / "refused.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

    def report(self) -> Path:
        return Path(self.state()["report_path"])

    def install_transcript(self) -> Path:
        target = self.root / "t.jsonl"
        write_jsonl(target, MAIN_TRANSCRIPT)
        write_jsonl(self.root / "t" / "subagents" / "agent-a1.jsonl", SUBAGENT_TRANSCRIPT)
        (self.root / "t" / "subagents" / "agent-a1.meta.json").write_text(json.dumps(SUBAGENT_META), encoding="utf-8")
        return target


def git(*args: str) -> None:
    subprocess.run(["git", *args], check=True, capture_output=True, timeout=30)


@pytest.fixture
def ctx(tmp_path: Path) -> Away:
    return Away(tmp_path)


def fill_report(path: Path, needs_you: str = "None.\n") -> None:
    """Give every hand-written section content while keeping the generated blocks."""
    text = path.read_text(encoding="utf-8")
    start = text.index("## Needs you")
    end = text.index("## Decided while you were away")
    path.write_text(text[:start] + "## Needs you\n\n" + needs_you + "\n" + text[end:], encoding="utf-8")


def check_lines(result) -> dict[str, str]:
    lines = {}
    for line in result.stdout.splitlines():
        if line.startswith("criterion="):
            name, status = line.split()
            lines[name.split("=", 1)[1]] = status.split("=", 1)[1]
        elif line.startswith("open="):
            lines["open"] = line.split("=", 1)[1]
    return lines




def test_report_by_night():
    assert away.next_report_by(datetime(2026, 11, 18, 23, 0), DEFAULTS) == datetime(2026, 11, 19, 9, 0), (
        "Wednesday 23:00 is inside the night window, so the report is due Thursday 09:00"
    )
    assert away.next_report_by(datetime(2026, 11, 18, 2, 0), DEFAULTS) == datetime(2026, 11, 18, 9, 0), (
        "Wednesday 02:00 is still inside the window that began Tuesday 21:00"
    )
    assert away.next_report_by(datetime(2026, 11, 18, 21, 0), DEFAULTS) == datetime(2026, 11, 19, 9, 0), (
        "the window opens at night_start itself"
    )


def test_report_by_day_off():
    assert away.next_report_by(datetime(2026, 11, 20, 22, 30), DEFAULTS) == datetime(2026, 11, 21, 10, 0), (
        "Friday night: Saturday is a day off, so the report is due at the day-off time"
    )
    assert away.next_report_by(datetime(2026, 11, 22, 23, 0), DEFAULTS) == datetime(2026, 11, 23, 9, 0), (
        "Sunday night: Monday is a workday"
    )
    custom = dict(DEFAULTS, away_days_off="Thu")
    assert away.next_report_by(datetime(2026, 11, 18, 23, 0), custom) == datetime(2026, 11, 19, 10, 0), (
        "a configured day off moves Thursday to the day-off time"
    )


def test_report_by_daytime_until_back():
    assert away.next_report_by(datetime(2026, 11, 18, 14, 0), DEFAULTS) is None, "14:00 is outside the window"
    assert away.next_report_by(datetime(2026, 11, 18, 9, 0), DEFAULTS) is None, "the window closes at report-by"


def test_start_until_overrides_settings(ctx):
    out = ctx.start("--kind", "until", "--until", "2099-01-02T07:30:00+00:00").stdout
    assert ctx.state()["report_by"] == "2099-01-02T07:30:00+00:00"
    assert "report_by=2099-01-02T07:30:00+00:00" in out
    trip = Away(ctx.root / "second")
    trip.start("--kind", "trip")
    assert trip.state()["report_by"] is None, "a trip lasts until the person is back"



def test_data_root(tmp_path):
    cache_root = tmp_path / "plugins" / "cache" / "my.market" / "session-flow" / "1.2.3"
    assert away.data_root({"CLAUDE_PLUGIN_DATA": "/x/data"}, str(cache_root)) == Path("/x/data"), "env wins"
    assert away.data_root({}, str(cache_root)) == tmp_path / "plugins" / "data" / "session-flow-my-market", (
        "<plugins>/data/<name@marketplace with disallowed characters as ->"
    )
    assert away.data_root({}, str(tmp_path / "loose" / "session-flow")) is None, "no cache marker, no guess"
    assert away.data_root({}, None) is None


def test_cli_without_plugin_data_fails(ctx):
    env = ctx.env()
    env.pop("CLAUDE_PLUGIN_DATA")
    result = ctx.run("start", "--session", SESSION, "--kind", "trip", env=env)
    assert result.returncode == 2
    assert "data root" in result.stderr



def test_start_twice_reconciles(ctx):
    task = ctx.repo / "tasks.md"
    task.write_text("- [ ] one\n", encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(task), "--scope", "the widget")
    first = ctx.state()
    report = ctx.report()
    report.write_text(report.read_text(encoding="utf-8") + "\nhand-written note\n", encoding="utf-8")
    time.sleep(0.01)
    ctx.start("--kind", "bed")
    second = ctx.state()
    assert second["started"] == first["started"]
    assert second["report_path"] == first["report_path"]
    assert second["task_file"] == str(task), "a bare second start keeps the task file"
    assert second["scope"] == "the widget"
    assert second["kind"] == "bed"
    assert "hand-written note" in report.read_text(encoding="utf-8"), "the report is not rewritten"


def test_report_path_not_ignored(ctx):
    ctx.start()
    assert ctx.report() == ctx.state_dir / "report.md", "not git-ignored: the report stays beside the state"
    assert ctx.report().exists()

    ignored = Away(ctx.root / "ignored")
    (ignored.repo / ".gitignore").write_text(".work/\n", encoding="utf-8")
    out = ignored.start().stdout
    report = ignored.report()
    assert report.parent == ignored.repo / ".work" / "away"
    assert report.name.endswith(f"-{SESSION[:8]}.md")
    assert report.exists()
    assert f"report={report}" in out


def test_report_skeleton_headings(ctx):
    ctx.start()
    text = ctx.report().read_text(encoding="utf-8")
    positions = [text.index(f"\n## {h}\n") for h in HEADINGS]
    assert positions == sorted(positions)


def test_warn_sandbox(ctx):
    out = ctx.start().stdout
    assert not any(line.startswith("warning=") and "sandbox" in line.lower() for line in out.splitlines()), out
    sandboxed = Away(ctx.root / "sandboxed")
    (sandboxed.repo / ".claude").mkdir()
    (sandboxed.repo / ".claude" / "settings.local.json").write_text('{"sandbox": {"enabled": true}}', encoding="utf-8")
    out = sandboxed.start().stdout
    assert any(line.startswith("warning=") and "sandbox" in line.lower() for line in out.splitlines()), out


def test_warn_auto_continue_off(ctx):
    out = ctx.start().stdout
    assert "autoContinueAtUsageLimit" not in out, "the default is on"
    assert any(line.startswith("warning=") and "awake" in line for line in out.splitlines()), "always warned"

    off = Away(ctx.root / "off")
    (off.config / "settings.json").write_text('{"autoContinueAtUsageLimit": false}', encoding="utf-8")
    out = off.start().stdout
    assert any(line.startswith("warning=") and "autoContinueAtUsageLimit" in line for line in out.splitlines()), out

    project = Away(ctx.root / "project")
    (project.repo / ".claude").mkdir()
    (project.repo / ".claude" / "settings.json").write_text('{"autoContinueAtUsageLimit": true}', encoding="utf-8")
    out = project.start().stdout
    assert "autoContinueAtUsageLimit" in out, "a project file that sets the key turns the feature off"



def test_hook_inactive_silent(ctx):
    events = {
        "PermissionRequest": "permission_request_bash",
        "Elicitation": "elicitation_form",
        "Stop": "stop",
        "UserPromptSubmit": "user_prompt_typed",
    }
    for event, fixture in events.items():
        assert ctx.hook(event, fixture) == "", f"{event} with no state prints nothing"
    assert not ctx.data.exists(), "a lookup creates nothing"

    ctx.start()
    assert ctx.hook("PermissionRequest", "permission_request_bash") != "", "active: the paired case prints"
    ctx.cli("end")
    for event in ("PermissionRequest", "Elicitation", "Stop"):
        assert ctx.hook(event, events[event]) == "", f"{event} after end prints nothing"
    ctx.cli("deliver")
    for event, fixture in events.items():
        assert ctx.hook(event, fixture) == "", f"{event} after deliver prints nothing"


def test_hook_rejects_unsafe_session_id(ctx):
    ctx.start()
    assert ctx.hook("PermissionRequest", "permission_request_bash", session=f"../away/{SESSION}") == ""
    result = ctx.run("status", "--session", "../x")
    assert result.returncode == 2


def test_hook_bad_input_exits_zero(ctx):
    for stdin in ("", "not json", "[]"):
        result = ctx.run("hook", "PermissionRequest", stdin=stdin)
        assert (result.returncode, result.stdout) == (0, "")
    result = ctx.run("hook", "NoSuchEvent", stdin="{}")
    assert (result.returncode, result.stdout) == (0, "")


def test_permission_request_never_allows(ctx):
    ctx.start()
    main = json.loads(ctx.hook("PermissionRequest", "permission_request_bash"))
    sub = json.loads(ctx.hook("PermissionRequest", "permission_request_subagent"))
    for output, rid in ((main, "R1"), (sub, "R2")):
        specific = output["hookSpecificOutput"]
        assert specific["hookEventName"] == "PermissionRequest"
        assert specific["decision"]["behavior"] == "deny"
        assert rid in specific["decision"]["message"]
        assert "interrupt" not in specific["decision"]
        assert "updatedPermissions" not in specific["decision"]
    refused = ctx.refused()
    assert [r["id"] for r in refused] == ["R1", "R2"]
    assert refused[0]["tool_name"] == "Bash"
    assert "askme-main" in refused[0]["detail"]
    assert "agent_id" not in refused[0]
    assert refused[1]["agent_id"] == "a176806189f9a60c0"


def test_elicitation_declined(ctx):
    ctx.start()
    output = json.loads(ctx.hook("Elicitation", "elicitation_form"))
    assert output == {"hookSpecificOutput": {"hookEventName": "Elicitation", "action": "decline"}}
    [entry] = ctx.refused()
    assert entry["id"] == "R1"
    assert entry["event"] == "Elicitation"
    assert "example-server" in entry["detail"]


def test_parallel_refusals(ctx):
    ctx.start()
    with ThreadPoolExecutor(max_workers=16) as pool:
        outputs = list(pool.map(lambda _: ctx.hook("PermissionRequest", "permission_request_bash"), range(16)))
    ids = sorted((r["id"] for r in ctx.refused()), key=lambda rid: int(rid[1:]))
    assert ids == [f"R{n}" for n in range(1, 17)], "sixteen parallel hooks get sixteen distinct ids, none lost"
    named = sorted(json.loads(o)["hookSpecificOutput"]["decision"]["message"].split(":", 1)[0] for o in outputs)
    assert named == sorted(ids), "each deny message names the id its own entry got"

    with ThreadPoolExecutor(max_workers=1) as pool:
        with away.locked(away.session_paths(ctx.data, SESSION, SCRIPTS.parent).lock):
            waiting = pool.submit(ctx.hook, "PermissionRequest", "permission_request_bash")
            time.sleep(1.0)
            assert len(ctx.refused()) == 16, "a hook does not append while another process holds the lock"
        waiting.result(timeout=30)
    assert len(ctx.refused()) == 17, "once the lock is free the waiting hook appends"


def test_wrapper_relays_decision_and_fails_open(ctx):
    wrapper = SCRIPTS.parent / "hooks" / "run-away-hook.sh"
    payload = dict(HOOK_INPUTS["permission_request_bash"], session_id=SESSION)
    ctx.start()

    def run(env: dict[str, str]):
        return subprocess.run(
            [shutil.which("bash"), str(wrapper), "PermissionRequest", "--plugin-root", str(SCRIPTS.parent)],
            input=json.dumps(payload), capture_output=True, text=True, env=env, timeout=60,
        )

    relayed = run(ctx.env())
    assert relayed.returncode == 0
    assert json.loads(relayed.stdout)["hookSpecificOutput"]["decision"]["behavior"] == "deny"
    bare = ctx.root / "bare-path"
    bare.mkdir()
    (bare / "dirname").symlink_to(shutil.which("dirname"))
    no_python = run(ctx.env(PATH=str(bare)))
    assert (no_python.returncode, no_python.stdout) == (0, ""), "no Python: the normal prompt appears"



def started_with_tasks(ctx: Away, tasks: str) -> Path:
    task = ctx.repo / "tasks.md"
    task.write_text(tasks, encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(task))
    fill_report(ctx.report())
    return task


def test_stop_open_items(ctx):
    started_with_tasks(ctx, "# Tasks\n\n- [x] shipped the widget\n- [ ] write the docs\n- [ ] fix the flaky test\n")
    output = json.loads(ctx.hook("Stop", "stop"))
    assert output["decision"] == "block"
    assert "write the docs" in output["reason"]
    assert "fix the flaky test" in output["reason"]
    assert RULES_TAIL in output["reason"]
    check = ctx.cli("check")
    assert check.returncode == 1
    assert check_lines(check)["open"] == "2"


def test_stop_parked_counts_done(ctx):
    started_with_tasks(ctx, "- [x] shipped the widget\n- [ ] pick the database (parked)\n")
    assert ctx.hook("Stop", "stop") == ""
    check = ctx.cli("check")
    assert check.returncode == 0, check.stdout
    assert check_lines(check)["open"] == "0"


def test_stop_hook_active_unchanged(ctx):
    started_with_tasks(ctx, "- [ ] write the docs\n")
    assert json.loads(ctx.hook("Stop", "stop"))["decision"] == "block"
    assert ctx.hook("Stop", "stop", stop_hook_active=True) == "", "no progress since the block: let it stop"
    report = ctx.report()
    report.write_text(report.read_text(encoding="utf-8") + "\nprogress\n", encoding="utf-8")
    assert json.loads(ctx.hook("Stop", "stop", stop_hook_active=True))["decision"] == "block", (
        "the report changed, so the open item still holds the run"
    )


def test_stop_background_tasks(ctx):
    started_with_tasks(ctx, "- [ ] write the docs\n")
    running = [{"id": "task-001", "type": "shell", "status": "running", "description": "ci watch"}]
    assert ctx.hook("Stop", "stop", background_tasks=running) == ""


def test_stop_warns_not_auto_once(ctx):
    started_with_tasks(ctx, "- [x] done\n")
    first = json.loads(ctx.hook("Stop", "stop", permission_mode="default"))
    assert first["decision"] == "block"
    assert "auto" in first["reason"].lower()
    assert ctx.hook("Stop", "stop", permission_mode="default") == "", "warned once only"
    assert ctx.state()["mode_warned"] is True


def test_stop_blocks_on_unlisted_refusal(ctx):
    started_with_tasks(ctx, "- [x] done\n")
    ctx.hook("PermissionRequest", "permission_request_bash")
    output = json.loads(ctx.hook("Stop", "stop"))
    assert output["decision"] == "block"
    assert "refresh" in output["reason"]
    assert ctx.cli("refresh").returncode == 0
    assert ctx.hook("Stop", "stop") == ""


def test_stop_records_transcript_path(ctx):
    started_with_tasks(ctx, "- [x] done\n")
    ctx.hook("Stop", "stop")
    assert ctx.state()["transcript_path"] == str(ctx.root / "t.jsonl")



def context_of(output: str) -> str:
    specific = json.loads(output)["hookSpecificOutput"]
    assert specific["hookEventName"] == "UserPromptSubmit"
    return specific["additionalContext"]


def test_prompt_subagent_report_not_return(ctx):
    ctx.start("--kind", "until", "--until", "2099-01-02T07:30:00+00:00")
    for fixture in ("user_prompt_subagent_report", "user_prompt_loop", "user_prompt_typed"):
        text = context_of(ctx.hook("UserPromptSubmit", fixture))
        assert "2099-01-02T07:30:00+00:00" in text
        assert RULES_TAIL in text
        assert "only when" in text
        assert "subagent" in text
        assert ctx.state()["status"] == "active", f"{fixture}: the hook never ends the absence itself"


def test_deliver_once(ctx):
    ctx.start()
    assert ctx.cli("deliver").returncode == 1, "an active absence cannot be delivered before it ends"
    assert ctx.cli("end").returncode == 0
    text = context_of(ctx.hook("UserPromptSubmit", "user_prompt_typed"))
    assert str(ctx.report()) in text
    assert "deliver" in text
    assert ctx.cli("deliver").returncode == 0
    assert ctx.state()["status"] == "delivered"
    assert ctx.hook("UserPromptSubmit", "user_prompt_typed") == ""
    assert ctx.cli("deliver").returncode == 0, "a second deliver is a no-op"
    assert ctx.state()["status"] == "delivered"


def test_end_keeps_a_copy_beside_state(ctx):
    ignored = Away(ctx.root / "ignored")
    (ignored.repo / ".gitignore").write_text(".work/\n", encoding="utf-8")
    ignored.start()
    assert ignored.cli("end").returncode == 0
    assert (ignored.state_dir / "report.md").read_text(encoding="utf-8") == ignored.report().read_text(encoding="utf-8")
    ctx.start()
    assert ctx.cli("end").returncode == 0, "a report already beside the state is not copied onto itself"


def test_start_after_delivery_begins_new_absence(ctx):
    ctx.start()
    first = ctx.state()
    ctx.cli("end")
    ctx.cli("deliver")
    time.sleep(0.01)
    ctx.start()
    second = ctx.state()
    assert second["status"] == "active"
    assert second["started"] != first["started"]



def test_check_order(ctx):
    ctx.start()
    report = ctx.report()
    fill_report(report)
    assert check_lines(ctx.cli("check"))["headings"] == "pass"
    text = report.read_text(encoding="utf-8")
    swapped = text.replace("## Done\n", "## TMP\n").replace("## Waiting on me\n", "## Done\n").replace(
        "## TMP\n", "## Waiting on me\n"
    )
    report.write_text(swapped, encoding="utf-8")
    result = ctx.cli("check")
    assert result.returncode == 1
    assert check_lines(result)["headings"] == "fail"


def test_check_needs_you_items(ctx):
    ctx.start()
    good = "- **Decision:** which database.\n  **Options:** Postgres; SQLite.\n  **Recommendation:** Postgres.\n"
    fill_report(ctx.report(), good)
    assert check_lines(ctx.cli("check"))["needs_you"] == "pass"
    fill_report(ctx.report(), "- **Decision:** which database.\n  **Options:** Postgres; SQLite.\n")
    result = ctx.cli("check")
    assert check_lines(result)["needs_you"] == "fail"
    assert result.returncode == 1



def refreshed(ctx: Away) -> str:
    ctx.start()
    ctx.install_transcript()
    ctx.hook("UserPromptSubmit", "user_prompt_loop")
    result = ctx.cli("refresh")
    assert result.returncode == 0, result.stderr
    return ctx.report().read_text(encoding="utf-8")


def block(text: str, name: str) -> str:
    return text.split(f"<!-- away:{name}:begin -->", 1)[1].split(f"<!-- away:{name}:end -->", 1)[0]


def test_externals_subagent(ctx):
    externals = block(refreshed(ctx), "externals")
    assert "git push origin feat-from-subagent" in externals
    assert "general-purpose" in externals
    assert "gh pr create" in externals
    assert "before-the-absence" not in externals, "records before the absence started are not listed"
    assert "ls -la" not in externals


def test_externals_mcp(ctx):
    externals = block(refreshed(ctx), "externals")
    assert "mcp__tracker__create_issue" in externals
    assert "README.md" not in externals, "a read-only tool is not an external action"


def test_denials_from_transcript(ctx):
    refused = block(refreshed(ctx), "refused")
    assert "- R1 " in refused
    assert "curl -X POST https://example.invalid/api/deploy" in refused
    assert "askme-main" not in refused, "a hook denial in the transcript is already listed by its hook"
    assert ctx.cli("refresh").returncode == 0
    assert [r["id"] for r in ctx.refused()] == ["R1"], "a second refresh adds no duplicate"


def test_slow_file_scan_cut_short_keeps_refusals_and_end(ctx, monkeypatch):
    ctx.start()
    ctx.hook("PermissionRequest", "permission_request_bash")
    monkeypatch.setenv("CLAUDE_PLUGIN_DATA", str(ctx.data))

    def interrupted(*_args):
        raise KeyboardInterrupt("file scan cut short")

    monkeypatch.setattr(away, "scan_files", interrupted)
    with pytest.raises(KeyboardInterrupt):
        away.main(["end", "--session", SESSION])
    assert ctx.state()["status"] == "ended", "the absence ends before the slow scan starts"
    assert "- R1 " in block(ctx.report().read_text(encoding="utf-8"), "refused"), (
        "the refused block is written before the file scan"
    )


def test_files_prune(ctx):
    old = ctx.home / "Documents" / "old.txt"
    old.parent.mkdir()
    old.write_text("old", encoding="utf-8")
    past = time.time() - 3600
    os.utime(old, (past, past))
    ctx.repo = ctx.home / "projects" / "launch"
    ctx.repo.mkdir(parents=True)
    git("init", "-q", str(ctx.repo))
    other = ctx.home / "projects" / "other"
    other.mkdir()
    git("init", "-q", str(other))
    ctx.start()
    new = ctx.home / "Documents" / "new.txt"
    new.write_text("new", encoding="utf-8")
    (ctx.home / ".cache").mkdir()
    (ctx.home / ".cache" / "hidden.bin").write_text("x", encoding="utf-8")
    (other / "stray.txt").write_text("x", encoding="utf-8")
    (ctx.repo / "work.txt").write_text("x", encoding="utf-8")
    assert ctx.cli("refresh").returncode == 0
    files = block(ctx.report().read_text(encoding="utf-8"), "files")
    assert str(new) in files
    assert str(other / "stray.txt") in files, "a repository the run did not launch in is still watched"
    assert "old.txt" not in files
    assert "hidden.bin" not in files
    assert "work.txt" not in files, "the run's own repository is pruned"
