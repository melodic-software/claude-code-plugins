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
import shlex
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
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
del _leaked_var

SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "away.py"
SESSION = "11111111-2222-3333-4444-555555555555"
RULES_TAIL = "skills/step-away/reference/rules.md"
HEADINGS = ("Needs you", "Decided while you were away", "Waiting on me", "Done", "Found", "Additional notes")

sys.path.insert(0, str(SCRIPTS))
import away  # noqa: E402
import away_launch  # noqa: E402

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
        self.data = root / "plugin-data" / "session-flow-test"
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
    own = {"CLAUDE_PLUGIN_DATA": "/x/data/session-flow-my-market"}
    assert away.data_root(own, str(cache_root)) == Path("/x/data/session-flow-my-market"), "its own env value wins"
    inline = {"CLAUDE_PLUGIN_DATA": "/x/data/session-flow-inline"}
    assert away.data_root(inline, None) == Path("/x/data/session-flow-inline"), "a --plugin-dir run is accepted"
    foreign = {"CLAUDE_PLUGIN_DATA": "/x/data/disk-hygiene-my-market"}
    assert away.data_root(foreign, str(cache_root)) == tmp_path / "plugins" / "data" / "session-flow-my-market", (
        "another plugin's data dir exported under the same name is ignored"
    )
    assert away.data_root(foreign, None) is None
    assert away.data_root({}, str(cache_root)) == tmp_path / "plugins" / "data" / "session-flow-my-market", (
        "<plugins>/data/<name@marketplace with disallowed characters as ->"
    )
    assert away.data_root({}, str(tmp_path / "loose" / "session-flow")) is None, "no cache marker, no guess"
    assert away.data_root({}, None) is None


def test_data_root_flag_wins(ctx):
    flag_root = ctx.root / "flag-data" / "session-flow-inline"
    ctx.start("--kind", "trip", "--data-root", str(flag_root))
    assert (flag_root / "away" / SESSION / "state.json").is_file(), "the --data-root directory holds the state"
    assert not ctx.state_dir.exists(), "CLAUDE_PLUGIN_DATA is not used when --data-root is given"


def test_data_root_flag_foreign_rejected(ctx):
    foreign = ctx.root / "flag-data" / "disk-hygiene-inline"
    result = ctx.cli("start", "--kind", "trip", "--data-root", str(foreign))
    assert result.returncode == 2, "another plugin's data directory is a usage error"
    assert "--data-root" in result.stderr, "the error names the flag"
    assert "is not a session-flow data directory" in result.stderr, "the error says why the flag is refused"
    assert not foreign.exists(), "nothing is written under the refused directory"
    assert not ctx.state_dir.exists(), "a refused flag never falls back to another root"


@pytest.mark.parametrize("value", ["${CLAUDE_PLUGIN_DATA}", ""])
def test_data_root_flag_unexpanded_ignored(ctx, value):
    ctx.start("--kind", "trip", "--data-root", value)
    assert (ctx.state_dir / "state.json").is_file(), "an unexpanded or empty flag falls back to CLAUDE_PLUGIN_DATA"


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


def test_start_twice_rewrites_header(ctx):
    first_task, second_task = ctx.repo / "tasks.md", ctx.repo / "later.md"
    first_task.write_text("- [ ] one\n", encoding="utf-8")
    second_task.write_text("- [ ] two\n", encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(first_task), "--scope", "the widget")
    report = ctx.report()
    report.write_text(report.read_text(encoding="utf-8") + "\nhand-written note\n", encoding="utf-8")
    ctx.start("--kind", "until", "--until", "2099-01-02T07:30:00+00:00", "--task-file", str(second_task), "--scope", "the gadget")
    lines = report.read_text(encoding="utf-8").splitlines()
    assert "- Report by: 2099-01-02T07:30:00+00:00" in lines, "the header shows the new report-by time"
    assert "- Kind: until" in lines
    assert "- Scope: the gadget" in lines
    assert f"- Task file: {second_task}" in lines, "the header names the task file the second start gave"
    assert "- Report by: until you are back" not in lines, "the stale report-by line is gone"
    assert f"- Task file: {first_task}" not in lines, "the stale task-file line is gone"
    assert "hand-written note" in lines, "the rest of the report is kept"


def test_new_absence_starts_a_fresh_report(ctx):
    ctx.start()
    report = ctx.report()
    report.write_text(report.read_text(encoding="utf-8") + "\nleft over from the last absence\n", encoding="utf-8")
    assert ctx.cli("end").returncode == 0
    assert ctx.cli("deliver").returncode == 0
    ctx.start("--kind", "until", "--until", "2099-01-02T07:30:00+00:00")
    assert ctx.report() == report, "the session-local report path is reused"
    text = report.read_text(encoding="utf-8")
    assert "left over from the last absence" not in text, "a new absence does not inherit the delivered report"
    assert f"- Started: {ctx.state()['started']}" in text.splitlines(), "the header names the new absence's start"


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


def test_hook_finds_state_without_plugin_data_env(ctx):
    """A skill-frontmatter hook gets no CLAUDE_PLUGIN_DATA; under --plugin-dir the root is not derivable."""
    ctx.data = ctx.config / "plugins" / "data" / "session-flow-inline"
    ctx.start()
    payload = dict(HOOK_INPUTS["permission_request_bash"], session_id=SESSION, cwd=str(ctx.repo))
    env = ctx.env()
    env.pop("CLAUDE_PLUGIN_DATA")
    result = ctx.run("hook", "PermissionRequest", stdin=json.dumps(payload), env=env)
    assert result.returncode == 0, result.stderr
    decision = json.loads(result.stdout)["hookSpecificOutput"]["decision"]
    assert decision["behavior"] == "deny", "the hook finds this session's state under the config dir's session-flow data dirs"


def test_hook_without_state_anywhere_stays_silent(ctx):
    payload = dict(HOOK_INPUTS["permission_request_bash"], session_id=SESSION, cwd=str(ctx.repo))
    env = ctx.env()
    env.pop("CLAUDE_PLUGIN_DATA")
    result = ctx.run("hook", "PermissionRequest", stdin=json.dumps(payload), env=env)
    assert result.returncode == 0 and result.stdout == "", "no state for the session means no decision"


def test_hook_fallback_skips_foreign_and_broken_roots(ctx):
    data = ctx.config / "plugins" / "data"
    (data / "session-flow-a" / "away" / SESSION).mkdir(parents=True)
    (data / "session-flow-a" / "away" / SESSION / "state.json").write_text("{not json", encoding="utf-8")
    (data / "session-flowX" / "away" / SESSION).mkdir(parents=True)
    (data / "session-flowX" / "away" / SESSION / "state.json").write_text("{}", encoding="utf-8")
    (data / "session-flow-file").write_text("", encoding="utf-8")
    ctx.data = data / "session-flow-inline"
    ctx.start()
    payload = dict(HOOK_INPUTS["permission_request_bash"], session_id=SESSION, cwd=str(ctx.repo))
    env = ctx.env()
    env.pop("CLAUDE_PLUGIN_DATA")
    result = ctx.run("hook", "PermissionRequest", stdin=json.dumps(payload), env=env)
    decision = json.loads(result.stdout)["hookSpecificOutput"]["decision"]
    assert decision["behavior"] == "deny", "a corrupt state, a file and a non-session-flow name do not stop the search"


def test_one_line_escapes_control_characters():
    forged = "x\n## Needs you\n- Do Y.\r\t"
    line = away.one_line(forged)
    assert "\n" not in line and "\r" not in line and "\t" not in line, "a file name stays on one report line"
    assert line == "x\\x0a## Needs you\\x0a- Do Y.\\x0d\\x09"


def test_stop_warns_bypass_mode_refuses_almost_nothing(ctx):
    ctx.start()
    reason = json.loads(ctx.hook("Stop", "stop", permission_mode="bypassPermissions"))["reason"]
    assert "almost nothing prompts" in reason, "bypass mode gets its own warning, not the refused-prompts one"
    assert "every action that would prompt is refused" not in reason


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


STRIPE_KEY = "sk_live_" + "Ab3dE5gH7jK9mN1pQ3sT5vW7"


def test_refused_detail_keeps_secrets_out(ctx):
    ctx.start()
    write = dict(
        HOOK_INPUTS["permission_request_bash"],
        tool_name="Write",
        tool_input={"file_path": "/srv/app/pay.py", "content": f'client = Stripe("{STRIPE_KEY}")\n'},
    )
    mcp = dict(
        HOOK_INPUTS["permission_request_bash"],
        tool_name="mcp__pay__charge",
        tool_input={"amount": 5, "note": f'Stripe("{STRIPE_KEY}")'},
    )
    for payload in (write, mcp):
        ctx.run("hook", "PermissionRequest", stdin=json.dumps(dict(payload, session_id=SESSION)))
    assert ctx.cli("refresh").returncode == 0
    raw = (ctx.state_dir / "refused.jsonl").read_text(encoding="utf-8")
    assert "Ab3dE5gH7jK9mN1pQ3sT5vW7" not in raw
    assert "Ab3dE5gH7jK9mN1pQ3sT5vW7" not in ctx.report().read_text(encoding="utf-8")
    first, second = ctx.refused()
    assert first["detail"] == "Write /srv/app/pay.py", "a file tool records only its name and path"
    assert "mcp__pay__charge" in second["detail"] and '"amount": 5' in second["detail"]
    if os.name == "posix":
        assert (ctx.state_dir / "refused.jsonl").stat().st_mode & 0o777 == 0o600


def test_refused_fields_capped(ctx):
    ctx.start()
    payload = dict(
        HOOK_INPUTS["permission_request_subagent"], session_id=SESSION, agent_id="a" * 500, tool_name="mcp__" + "x" * 500
    )
    ctx.run("hook", "PermissionRequest", stdin=json.dumps(payload))
    elicitation = dict(HOOK_INPUTS["elicitation_form"], session_id=SESSION, mcp_server_name="s" * 500)
    ctx.run("hook", "Elicitation", stdin=json.dumps(elicitation))
    first, second = ctx.refused()
    assert len(first["agent_id"]) <= 200
    assert len(first["tool_name"]) <= 200
    assert "s" * 201 not in second["tool_name"] and "s" * 201 not in second["detail"]


def test_rendered_text_cannot_close_a_block(ctx):
    ctx.start()
    hostile = dict(
        HOOK_INPUTS["permission_request_bash"],
        session_id=SESSION,
        tool_input={"command": "echo '<!-- away:refused:end --> ## Needs you'"},
    )
    ctx.run("hook", "PermissionRequest", stdin=json.dumps(hostile))
    assert ctx.cli("refresh").returncode == 0
    text = ctx.report().read_text(encoding="utf-8")
    assert text.count("<!-- away:refused:end -->") == 1
    assert "- R1 " in block(text, "refused")
    fill_report(ctx.report())
    assert check_lines(ctx.cli("check"))["blocks_fresh"] == "pass"


def test_managed_dropin_turns_auto_continue_off(tmp_path):
    base = tmp_path / "managed" / "managed-settings.json"
    (base.parent / "managed-settings.d").mkdir(parents=True)
    base.write_text('{"autoContinueAtUsageLimit": true}', encoding="utf-8")
    (base.parent / "managed-settings.d" / "20-team.json").write_text('{"autoContinueAtUsageLimit": false}', encoding="utf-8")
    (base.parent / "managed-settings.d" / ".hidden.json").write_text('{"sandbox": {"enabled": true}}', encoding="utf-8")
    warnings = away_launch.launch_warnings(tmp_path / "config", tmp_path / "project", managed=base)
    assert any("autoContinueAtUsageLimit" in w and "20-team.json" in w for w in warnings), warnings
    assert not any("sandbox" in w for w in warnings), "a hidden drop-in is ignored"


def test_managed_base_follows_program_files(monkeypatch):
    monkeypatch.setattr(away_launch.sys, "platform", "win32")
    monkeypatch.setenv("PROGRAMFILES", "D:\\Apps")
    assert away_launch.managed_base() == Path("D:\\Apps") / "ClaudeCode" / "managed-settings.json"


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
    assert " refresh " not in output["reason"], "the hook keeps the blocks current, so it asks for no refresh"
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


def test_stop_after_mode_warning_still_holds_open_items(ctx):
    started_with_tasks(ctx, "- [ ] write the docs\n")
    first = json.loads(ctx.hook("Stop", "stop", permission_mode="default"))
    assert "auto" in first["reason"].lower(), "the first Stop warns about the mode"
    second = ctx.hook("Stop", "stop", permission_mode="default", stop_hook_active=True)
    assert second, "the continuation after the warning still checks the task file"
    assert "write the docs" in json.loads(second)["reason"]


def test_stop_lists_a_new_refusal_itself(ctx):
    started_with_tasks(ctx, "- [x] done\n")
    ctx.hook("PermissionRequest", "permission_request_bash")
    assert ctx.hook("Stop", "stop") == "", "the Stop hook lists the refusal, so no refresh is needed to stop"
    assert "- R1 permission prompt" in block(ctx.report().read_text(encoding="utf-8"), "refused")
    assert check_lines(ctx.cli("check"))["blocks_fresh"] == "pass"


def test_stop_refreshes_blocks_from_the_transcript_and_keeps_the_agents_sections(ctx):
    started_with_tasks(ctx, "- [x] done\n")
    fill_report(ctx.report(), "- **Decision:** which database.\n  **Options:** Postgres; SQLite.\n  **Recommendation:** Postgres.\n")
    before = ctx.report().read_text(encoding="utf-8")
    ctx.install_transcript()
    assert ctx.hook("Stop", "stop") == ""
    text = ctx.report().read_text(encoding="utf-8")
    assert "gh pr create" in block(text, "externals"), "the first Stop records the transcript and lists its external actions"
    assert "curl -X POST https://example.invalid/api/deploy" in block(text, "refused"), "an auto mode denial is listed"
    assert [r["id"] for r in ctx.refused()] == ["R1"]
    assert text.split("<!-- away:refused:begin -->")[0] == before.split("<!-- away:refused:begin -->")[0], (
        "everything above the script-owned blocks, Needs you included, is left as the agent wrote it"
    )
    assert ctx.hook("Stop", "stop") == ""
    assert [r["id"] for r in ctx.refused()] == ["R1"], "a second Stop adds no duplicate"


def test_stop_leaves_the_file_scan_to_end(ctx):
    watched = ctx.root / "watched"
    watched.mkdir()
    task = ctx.repo / "tasks.md"
    task.write_text("- [x] done\n", encoding="utf-8")
    ctx.start(
        "--kind", "until", "--until", "2000-01-01T00:00:00+00:00", "--task-file", str(task),
        "--setting", f"away_watched_folders={watched}",
    )
    fill_report(ctx.report())
    (watched / "written.txt").write_text("x", encoding="utf-8")
    assert ctx.hook("Stop", "stop") == ""
    assert "written.txt" not in block(ctx.report().read_text(encoding="utf-8"), "files"), "the Stop hook runs no file scan"
    assert ctx.cli("end").returncode == 0
    assert "written.txt" in block(ctx.report().read_text(encoding="utf-8"), "files"), "end scans the watched folders"


def test_stop_still_holds_open_items_when_the_report_cannot_be_written(ctx):
    started_with_tasks(ctx, "- [ ] write the docs\n")
    blocker = ctx.root / "not-a-dir"
    blocker.write_text("", encoding="utf-8")
    state = ctx.state()
    (ctx.state_dir / "state.json").write_text(json.dumps(dict(state, report_path=str(blocker / "report.md"))), encoding="utf-8")
    payload = dict(HOOK_INPUTS["stop"], session_id=SESSION, transcript_path=str(ctx.root / "t.jsonl"))
    result = ctx.run("hook", "Stop", stdin=json.dumps(payload))
    assert result.returncode == 0
    output = json.loads(result.stdout)
    assert output["decision"] == "block" and "write the docs" in output["reason"], "a failed rewrite keeps the open-items hold"
    assert "stop refresh failed" in result.stderr


@pytest.mark.skipif(os.name != "posix", reason="symlinks need POSIX permissions")
@pytest.mark.parametrize("swap", ["report", "folder"])
def test_stop_never_writes_through_a_link_planted_at_the_report(ctx, swap):
    ignored = Away(ctx.root / "ignored")
    (ignored.repo / ".gitignore").write_text(".work/\n", encoding="utf-8")
    task = ignored.repo / "tasks.md"
    task.write_text("- [x] done\n", encoding="utf-8")
    ignored.start("--kind", "trip", "--task-file", str(task))
    report = ignored.report()
    secret = ctx.root / "secret.txt"
    secret.write_text("TOP-SECRET-VALUE\n", encoding="utf-8")
    outside = ctx.root / "outside"
    outside.mkdir()
    if swap == "report":
        report.unlink()
        report.symlink_to(secret)
    else:
        moved = report.parent.with_name("away-real")
        report.parent.rename(moved)
        report.parent.symlink_to(outside)
    ignored.hook("PermissionRequest", "permission_request_bash")
    ignored.hook("Stop", "stop")
    assert secret.read_text(encoding="utf-8") == "TOP-SECRET-VALUE\n", "the linked file is left as it was"
    assert list(outside.iterdir()) == [], "nothing is written into the linked folder"
    if swap == "report":
        assert report.is_symlink(), "the link is not replaced by a copy of what it points at"


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


def _active_note(ctx: Away) -> str:
    ctx.start()
    return context_of(ctx.hook("UserPromptSubmit", "user_prompt_typed"))


def _back_note(ctx: Away) -> str:
    ctx.start()
    assert ctx.cli("end").returncode == 0
    return context_of(ctx.hook("UserPromptSubmit", "user_prompt_typed"))


@pytest.mark.parametrize(
    ("note", "verb", "status_after"),
    [(_active_note, "end", "ended"), (_back_note, "deliver", None)],
    ids=["active-end", "back-deliver"],
)
def test_hook_note_command_names_data_root(ctx, note, verb, status_after):
    text = note(ctx)
    command = f'python3 "{SCRIPT}" {verb} --session {SESSION} --data-root "{ctx.data}"'
    assert f"`{command}`" in text, "the note prints the command with its data root double-quoted"
    env = ctx.env()
    env.pop("CLAUDE_PLUGIN_DATA")
    argv = shlex.split(command)
    result = subprocess.run(
        [sys.executable, *argv[1:]], capture_output=True, text=True, cwd=str(ctx.repo), env=env, timeout=60
    )
    assert result.returncode == 0, f"the printed command reaches the state without CLAUDE_PLUGIN_DATA: {result.stderr}"
    if status_after is None:
        assert not ctx.state_dir.exists(), "delivered: the state is gone"
    else:
        assert ctx.state()["status"] == status_after


def test_deliver_once(ctx):
    ctx.start()
    assert ctx.cli("deliver").returncode == 1, "an active absence cannot be delivered before it ends"
    assert ctx.cli("end").returncode == 0
    text = context_of(ctx.hook("UserPromptSubmit", "user_prompt_typed"))
    assert str(ctx.report()) in text
    assert "deliver" in text
    assert ctx.cli("deliver").returncode == 0
    assert not ctx.state_dir.exists(), "a delivered absence leaves no state behind"
    assert ctx.hook("UserPromptSubmit", "user_prompt_typed") == ""
    assert ctx.cli("deliver").returncode == 0, "a second deliver is a no-op"


def delivered_report(result) -> Path:
    assert result.returncode == 0, result.stderr
    [line] = [line for line in result.stdout.splitlines() if line.startswith("report=")]
    return Path(line[len("report="):])


def test_deliver_moves_a_report_kept_beside_the_state(ctx):
    ctx.start()
    assert ctx.report().parent == ctx.state_dir, "not git-ignored: the report starts beside the state"
    fill_report(ctx.report(), "the person's note\n")
    assert ctx.cli("end").returncode == 0
    report = delivered_report(ctx.cli("deliver"))
    assert "the person's note" in report.read_text(encoding="utf-8"), "the report survives delivery"
    assert ctx.data / "away" not in report.parents, "the lasting report is outside the away state"
    assert not (ctx.data / "away").exists(), "the empty away dir goes, so the hook's shell gate exits early"


def test_retried_deliver_reports_where_an_interrupted_one_moved_the_report(ctx, monkeypatch):
    ctx.start()
    fill_report(ctx.report(), "the person's note\n")
    assert ctx.cli("end").returncode == 0
    paths = away.session_paths(ctx.data, SESSION, SCRIPTS.parent)

    def interrupted(self, missing_ok=False):
        raise KeyboardInterrupt

    with monkeypatch.context() as patch:
        patch.setattr(Path, "unlink", interrupted)
        with pytest.raises(KeyboardInterrupt), away.locked(paths.lock):
            away._clear_held(paths, away.read_state(paths))
    assert not (ctx.state_dir / "report.md").exists(), "interrupted after the move, before any unlink"
    report = delivered_report(ctx.cli("deliver"))
    assert "the person's note" in report.read_text(encoding="utf-8"), "the retry names the moved report"
    assert not ctx.state_dir.exists()


def test_deliver_keeps_a_git_ignored_report_in_place(ctx):
    ignored = Away(ctx.root / "ignored")
    (ignored.repo / ".gitignore").write_text(".work/\n", encoding="utf-8")
    ignored.start()
    report = ignored.report()
    assert ignored.cli("end").returncode == 0
    assert delivered_report(ignored.cli("deliver")) == report
    assert report.exists(), "the report in the launch checkout stays where the person was told"
    assert not (ignored.data / "away").exists()


def test_deliver_keeps_another_sessions_absence(ctx):
    other = "22222222-3333-4444-5555-666666666666"
    assert ctx.run("start", "--session", other, "--kind", "trip").returncode == 0
    ctx.start()
    ctx.cli("end")
    assert ctx.cli("deliver").returncode == 0
    assert not ctx.state_dir.exists()
    assert ctx.hook("PermissionRequest", "permission_request_bash", session=other) != "", "the other absence still refuses"


def test_deliver_sweeps_an_old_delivered_absence_unless_its_lock_is_held(ctx):
    old = "99999999-8888-7777-6666-555555555555"
    old_paths = away.session_paths(ctx.data, old, SCRIPTS.parent)
    assert ctx.run("start", "--session", old, "--kind", "trip").returncode == 0
    state = json.loads(old_paths.state.read_text(encoding="utf-8"))
    old_paths.state.write_text(json.dumps(dict(state, status="delivered")), encoding="utf-8")

    ctx.start()
    ctx.cli("end")
    with away.locked(old_paths.lock):
        assert ctx.cli("deliver").returncode == 0
        assert old_paths.state.exists(), "a dir whose lock another process holds is left alone"
    ctx.start()
    ctx.cli("end")
    assert ctx.cli("deliver").returncode == 0
    assert not old_paths.dir.exists(), "a delivered absence left by an earlier version is cleared once its lock is free"
    assert not (ctx.data / "away").exists()


def test_end_keeps_a_copy_beside_state(ctx):
    ignored = Away(ctx.root / "ignored")
    (ignored.repo / ".gitignore").write_text(".work/\n", encoding="utf-8")
    ignored.start()
    assert ignored.cli("end").returncode == 0
    assert (ignored.state_dir / "report.md").read_text(encoding="utf-8") == ignored.report().read_text(encoding="utf-8")
    if os.name == "posix":
        assert (ignored.state_dir / "report.md").stat().st_mode & 0o777 == 0o600, "the copy is private to the user"
    ctx.start()
    assert ctx.cli("end").returncode == 0, "a report already beside the state is not copied onto itself"


def test_start_after_delivery_begins_new_absence(ctx):
    ctx.start()
    first = ctx.state()
    ctx.hook("PermissionRequest", "permission_request_bash")
    assert len(ctx.refused()) == 1
    ctx.cli("end")
    ctx.cli("deliver")
    time.sleep(0.01)
    ctx.start()
    second = ctx.state()
    assert second["status"] == "active"
    assert second["started"] != first["started"]
    assert ctx.refused() == [], "the new absence starts with no refusals from the last one"



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
    worktree = ctx.home / "projects" / "wt"
    worktree.mkdir()
    (worktree / ".git").write_text("gitdir: /elsewhere\n", encoding="utf-8")
    (worktree / "wip.txt").write_text("x", encoding="utf-8")
    assert ctx.cli("refresh", "--files").returncode == 0
    files = block(ctx.report().read_text(encoding="utf-8"), "files")
    assert str(new) in files
    assert "stray.txt" not in files, "every git repository is pruned"
    assert "wip.txt" not in files, "a worktree's .git file prunes it too"
    assert "old.txt" not in files
    assert "hidden.bin" not in files
    assert "work.txt" not in files, "the run's own repository is pruned"
    assert files.split("\n\n", 1)[1].startswith("The list can include files other sessions wrote"), files


def test_plain_refresh_keeps_the_files_block(ctx):
    ctx.start()
    assert ctx.cli("refresh", "--files").returncode == 0
    first = (ctx.home / "first.txt")
    first.write_text("x", encoding="utf-8")
    assert ctx.cli("refresh").returncode == 0
    assert "first.txt" not in block(ctx.report().read_text(encoding="utf-8"), "files"), "no rescan on a plain refresh"
    fill_report(ctx.report())
    assert check_lines(ctx.cli("check"))["blocks_fresh"] == "pass", "a kept files block still counts as fresh"
    assert ctx.cli("refresh", "--files").returncode == 0
    assert str(first) in block(ctx.report().read_text(encoding="utf-8"), "files")
    second = ctx.home / "second.txt"
    second.write_text("x", encoding="utf-8")
    assert ctx.cli("end").returncode == 0
    assert str(second) in block(ctx.report().read_text(encoding="utf-8"), "files"), "end always rescans"


def test_file_walk_budget(ctx, monkeypatch):
    ctx.start()
    (ctx.home / "a" / "b").mkdir(parents=True)
    monkeypatch.setattr(away, "SCAN_BUDGET_SECONDS", 0.0)
    assert away.scan_files([str(ctx.home)], 0.0, set()).complete is False
    monkeypatch.setenv("CLAUDE_PLUGIN_DATA", str(ctx.data))
    monkeypatch.setenv("HOME", str(ctx.home))
    assert away.main(["refresh", "--session", SESSION, "--files"]) == 0
    assert "- Scan stopped after 0 s; the list is incomplete." in block(ctx.report().read_text(encoding="utf-8"), "files")
    monkeypatch.setattr(away, "SCAN_BUDGET_SECONDS", 120.0)
    assert away.scan_files([str(ctx.home)], 0.0, set()).complete is True


def test_file_scan_cut_short_leaves_an_honest_line(ctx, monkeypatch):
    """A caller's timeout can kill the walk; the report then says the list is incomplete, not None."""
    ctx.start()
    monkeypatch.setenv("CLAUDE_PLUGIN_DATA", str(ctx.data))
    monkeypatch.setenv("HOME", str(ctx.home))

    def killed(*_args):
        raise KeyboardInterrupt

    monkeypatch.setattr(away, "scan_files", killed)
    with pytest.raises(KeyboardInterrupt):
        away.main(["refresh", "--session", SESSION, "--files"])
    files = block(ctx.report().read_text(encoding="utf-8"), "files")
    assert "Scan in progress" in files and "None." not in files


def test_scan_budget_stays_under_the_bash_default_timeout():
    assert away.SCAN_BUDGET_SECONDS <= 60, "the walk plus transcript and git reads must finish inside two minutes"
