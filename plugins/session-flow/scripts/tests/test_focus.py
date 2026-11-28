# test-scope: plugins/session-flow/hooks/run-focus-hook.sh plugins/session-flow/hooks/hooks.json
"""Contract tests for focus.py: the per-session focus file the PreCompact hook prints.

Every case runs the CLI as a subprocess with a temp HOME and a temp plugin data root, so no real
plugin data is read or written. Hook payloads follow the documented shapes
(https://code.claude.com/docs/en/hooks#precompact-input, #userpromptsubmit-input); the raw
`"prompt":"/goal <condition>"` shape is the one the handoff behavior probe P2 recorded.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "focus.py"
SESSION = "11111111-2222-3333-4444-555555555555"
LEAD = (
    "Session focus from session-flow. Keep each item below in the summary verbatim. Where it "
    "conflicts with the user's own /compact instructions, the user's instructions win."
)
PRECOMPACT_STDOUT_LIMIT = 10_000  # https://code.claude.com/docs/en/hooks#precompact-output
GOAL_CLEAR_ALIASES = ("clear", "stop", "off", "reset", "none", "cancel")
OPTION = "CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED"


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    home = tmp_path / "home"
    home.mkdir()
    base = {key: value for key, value in os.environ.items() if not key.startswith("CLAUDE_")}
    base.update(HOME=str(home), CLAUDE_PLUGIN_DATA=str(tmp_path / "session-flow"))
    return base


@pytest.fixture
def project(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / ".git").mkdir(parents=True)
    return repo


def run(env: dict[str, str], *args: str, stdin: str = "", cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), *args],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd or env["HOME"],
        timeout=30,
        check=False,
    )


def focus_file(env: dict[str, str]) -> Path:
    return Path(env["CLAUDE_PLUGIN_DATA"]) / "focus" / f"{SESSION}.md"


def set_focus(env: dict[str, str], *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    result = run(env, "set", "--session", SESSION, *args, cwd=cwd)
    assert result.returncode == 0, result.stderr
    return result


def printed(env: dict[str, str]) -> str:
    result = run(env, "print", "--session", SESSION)
    assert result.returncode == 0, result.stderr
    return result.stdout


def payload(event: str, project: Path, **fields: object) -> str:
    return json.dumps(
        {
            "session_id": SESSION,
            "transcript_path": str(project / "t.jsonl"),
            "cwd": str(project),
            "hook_event_name": event,
            **fields,
        }
    )


def precompact(env: dict[str, str], project: Path, trigger: str = "auto") -> subprocess.CompletedProcess:
    body = payload("PreCompact", project, trigger=trigger, custom_instructions=None)
    return run(env, "hook", "PreCompact", stdin=body, cwd=project)


def prompt_hook(env: dict[str, str], project: Path, prompt: str) -> subprocess.CompletedProcess:
    body = payload("UserPromptSubmit", project, permission_mode="auto", prompt=prompt)
    return run(env, "hook", "UserPromptSubmit", stdin=body, cwd=project)


def write_repo_setting(project: Path, value: str) -> None:
    conventions = project / "docs" / "conventions"
    conventions.mkdir(parents=True, exist_ok=True)
    (conventions / "session-flow.yaml").write_text(f"compact_focus_enabled: {value}\n", encoding="utf-8")


def test_precompact_prints_focus_file(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "all tests in test/auth pass")
    result = precompact(env, project)
    assert result.returncode == 0
    assert result.stdout.splitlines()[0] == LEAD, "the lead line opens the printed focus"
    assert "If this /goal is still active, its condition: all tests in test/auth pass" in result.stdout


def test_precompact_setting_off_silent(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "ship it")
    result = precompact({**env, OPTION: "false"}, project)
    assert (result.returncode, result.stdout) == (0, ""), "a user-layer false prints nothing"


def test_precompact_no_file_silent(env: dict[str, str], project: Path) -> None:
    result = precompact(env, project)
    assert (result.returncode, result.stdout) == (0, ""), "no focus file prints nothing"


@pytest.mark.parametrize("event", ["PreCompact", "UserPromptSubmit"])
@pytest.mark.parametrize("body", ["not json", "", "[1, 2]", '{"session_id": "../escape", "prompt": "/goal x"}'])
def test_malformed_payload_exit0(env: dict[str, str], project: Path, event: str, body: str) -> None:
    set_focus(env, "--goal", "kept")
    result = run(env, "hook", event, stdin=body, cwd=project)
    assert (result.returncode, result.stdout) == (0, ""), "a malformed payload is silent and exits 0"
    assert "kept" in printed(env), "a malformed payload leaves the focus file alone"


def test_output_under_cap(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "g" * 20000, "--note", "n" * 3000, "--handoff", str(project / "h.md"))
    result = precompact(env, project)
    assert result.returncode == 0
    assert 0 < len(result.stdout) < PRECOMPACT_STDOUT_LIMIT, "the printed focus stays under the PreCompact cap"
    assert "(cut; full condition in the handoff file)" in result.stdout, "a cut goal says so"
    assert "n" * 3000 in result.stdout, "cutting the goal keeps the other sections whole"


def test_goal_fire_stdout_empty(env: dict[str, str], project: Path) -> None:
    result = prompt_hook(env, project, "/goal every item in tasks.md is ticked")
    assert (result.returncode, result.stdout) == (0, ""), "the prompt hook adds no context"
    assert "its condition: every item in tasks.md is ticked" in printed(env)


def test_goal_replaces_previous_goal(env: dict[str, str], project: Path) -> None:
    prompt_hook(env, project, "/goal first condition")
    prompt_hook(env, project, "/goal second condition")
    text = printed(env)
    assert "second condition" in text and "first condition" not in text


@pytest.mark.parametrize("alias", GOAL_CLEAR_ALIASES)
def test_goal_alias_clears(env: dict[str, str], project: Path, alias: str) -> None:
    set_focus(env, "--goal", "old condition", "--note", "keep me")
    result = prompt_hook(env, project, f"/goal {alias}")
    assert (result.returncode, result.stdout) == (0, "")
    text = printed(env)
    assert "## Goal" not in text and "old condition" not in text, f"/goal {alias} clears the goal"
    assert "keep me" in text, "clearing the goal keeps the other sections"


@pytest.mark.parametrize("prompt", ["/goal", "/goal   ", "/goal\n"])
def test_bare_goal_noop(env: dict[str, str], project: Path, prompt: str) -> None:
    set_focus(env, "--goal", "still here")
    result = prompt_hook(env, project, prompt)
    assert (result.returncode, result.stdout) == (0, "")
    assert "its condition: still here" in printed(env), "a bare /goal is a status check"


@pytest.mark.parametrize(
    "prompt",
    [
        "fix the parser",
        "please set /goal tests pass later",
        "Read @README.md and fix X",
        "/goals are nice",
        "/goalkeeper tests",
    ],
)
def test_prompt_without_goal_directive_stays_quiet(env: dict[str, str], project: Path, prompt: str) -> None:
    result = prompt_hook(env, project, prompt)
    assert (result.returncode, result.stdout) == (0, "")
    assert not (Path(env["CLAUDE_PLUGIN_DATA"]) / "focus").exists(), "no focus folder is created"


def test_prompt_hook_setting_off_writes_nothing(env: dict[str, str], project: Path) -> None:
    prompt_hook({**env, OPTION: "false"}, project, "/goal tests pass")
    assert not focus_file(env).exists()


def test_repo_false_turns_off_when_user_unset(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "repo says off")
    write_repo_setting(project, "false")
    assert precompact(env, project).stdout == "", "the repository layer decides when the user set nothing"


def test_user_true_wins_over_repo_false(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "user says on")
    write_repo_setting(project, "false")
    assert "user says on" in precompact({**env, OPTION: "true"}, project).stdout


def test_user_false_wins_over_repo_true(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "user says off")
    write_repo_setting(project, "true")
    assert precompact({**env, OPTION: "false"}, project).stdout == ""


def test_invalid_repo_value_is_dropped(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "default applies")
    write_repo_setting(project, '"false"')
    result = precompact(env, project)
    assert "default applies" in result.stdout, "a quoted boolean is invalid and falls to the default"
    assert "compact_focus_enabled" in result.stderr, "the invalid value is named"


def test_repo_file_under_home_root_is_skipped(env: dict[str, str]) -> None:
    home = Path(env["HOME"])
    (home / ".git").mkdir()
    write_repo_setting(home, "false")
    set_focus(env, "--goal", "home repo ignored")
    assert "home repo ignored" in precompact(env, home).stdout, "a git root at HOME has no repository layer"


def test_set_with_setting_off_writes_nothing(env: dict[str, str]) -> None:
    result = run(env, "set", "--session", SESSION, "--goal", "x", "--enabled", "false")
    assert result.returncode == 0
    assert not focus_file(env).exists()


def test_set_rendered_default_does_not_override_repo_false(env: dict[str, str], project: Path) -> None:
    write_repo_setting(project, "false")
    result = run(env, "set", "--session", SESSION, "--goal", "x", "--enabled", "true", cwd=project)
    assert result.returncode == 0
    assert not focus_file(env).exists(), "an unset option renders its default true; the repository false decides"


def test_set_user_false_wins_over_repo_true(env: dict[str, str], project: Path) -> None:
    write_repo_setting(project, "true")
    run(env, "set", "--session", SESSION, "--goal", "x", "--enabled", "false", cwd=project)
    assert not focus_file(env).exists()


def test_set_rendered_default_writes_when_repo_unset(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "written", "--enabled", "true", cwd=project)
    assert "written" in printed(env)


def test_invalid_user_value_is_dropped(env: dict[str, str], project: Path) -> None:
    set_focus(env, "--goal", "next layer decides")
    result = precompact({**env, OPTION: "yes"}, project)
    assert "next layer decides" in result.stdout, "an invalid user value is dropped, not read as off"
    assert "compact_focus_enabled" in result.stderr, "the invalid value is named"
    write_repo_setting(project, "false")
    assert precompact({**env, OPTION: "yes"}, project).stdout == "", "the repository layer then decides"


def test_unexpanded_enabled_placeholder_counts_as_unset(env: dict[str, str]) -> None:
    set_focus(env, "--goal", "placeholder", "--enabled", "${user_config.compact_focus_enabled}")
    assert "placeholder" in printed(env)


def test_set_keeps_other_sections(env: dict[str, str], tmp_path: Path) -> None:
    handoff = tmp_path / "chain-handoff-1.md"
    set_focus(env, "--goal", "the goal")
    set_focus(env, "--handoff", str(handoff))
    set_focus(env, "--note", "line one\nline two")
    text = printed(env)
    assert text.splitlines()[0] == LEAD
    assert "its condition: the goal" in text
    assert (
        f"This session resumed from {handoff}; its Reminders and Environment to re-establish still apply, "
        "so read them again after compaction."
    ) in text
    assert "## Note\nline one\nline two" in text


def test_value_line_starting_like_a_heading_keeps_sections_apart(env: dict[str, str]) -> None:
    set_focus(env, "--note", "first\n## Goal\nnot a goal")
    set_focus(env, "--goal", "real goal")
    set_focus(env, "--note", "")
    text = printed(env)
    assert "its condition: real goal" in text and "not a goal" not in text


def test_step_away_task_file_roundtrip(env: dict[str, str], tmp_path: Path) -> None:
    tasks = tmp_path / "tasks-11111111.md"
    set_focus(env, "--goal", "g")
    set_focus(env, "--task-file", str(tasks))
    assert f"Step-away task file: {tasks}" in printed(env)
    result = run(env, "clear", "--session", SESSION, "--task-file")
    assert result.returncode == 0, result.stderr
    text = printed(env)
    assert "Step-away task file" not in text and "its condition: g" in text


def test_step_away_posture_reaches_precompact(env: dict[str, str], project: Path, tmp_path: Path) -> None:
    tasks = tmp_path / "tasks-11111111.md"
    set_focus(env, "--task-file", str(tasks), "--posture", "orchestrator")
    result = precompact(env, project)
    assert result.returncode == 0
    assert f"Step-away task file: {tasks}" in result.stdout
    assert "## Posture\nStep-away orchestrator posture is on: invoke /session-flow:orchestrate" in result.stdout
    set_focus(env, "--posture", "off")
    text = printed(env)
    assert "## Posture" not in text and "Step-away task file" in text, "posture off removes only its section"
    set_focus(env, "--posture", "orchestrator")
    assert run(env, "clear", "--session", SESSION, "--task-file", "--posture").returncode == 0
    assert not focus_file(env).exists(), "the return step clears both and leaves no file"


def test_step_away_posture_rejects_other_values(env: dict[str, str]) -> None:
    result = run(env, "set", "--session", SESSION, "--posture", "maybe")
    assert result.returncode == 2 and "--posture" in result.stderr
    assert not focus_file(env).exists()


def test_step_away_set_with_focus_off_exits_0_and_writes_nothing(env: dict[str, str], project: Path) -> None:
    result = run(env, "set", "--session", SESSION, "--task-file", "t.md", "--posture", "orchestrator", "--enabled", "false")
    assert result.returncode == 0 and "focus=skipped" in result.stdout
    assert not focus_file(env).exists()
    assert precompact({**env, OPTION: "false"}, project).stdout == ""


def test_clear_all_removes_file(env: dict[str, str]) -> None:
    set_focus(env, "--goal", "g")
    assert run(env, "clear", "--session", SESSION, "--all").returncode == 0
    assert not focus_file(env).exists() and printed(env) == ""


def test_clear_last_section_removes_file(env: dict[str, str]) -> None:
    set_focus(env, "--goal", "g")
    run(env, "clear", "--session", SESSION, "--goal")
    assert not focus_file(env).exists()


def test_print_never_creates_the_folder(env: dict[str, str]) -> None:
    assert printed(env) == ""
    assert not (Path(env["CLAUDE_PLUGIN_DATA"]) / "focus").exists()


@pytest.mark.parametrize("session", ["../x", "", "a b", "x" * 129])
def test_invalid_session_is_refused(env: dict[str, str], session: str) -> None:
    result = run(env, "set", "--session", session, "--goal", "g")
    assert (result.returncode, "reason=invalid_session" in result.stderr) == (2, True)


def test_no_data_root_is_a_usage_error(env: dict[str, str]) -> None:
    bare = {key: value for key, value in env.items() if key != "CLAUDE_PLUGIN_DATA"}
    result = run(bare, "set", "--session", SESSION, "--goal", "g")
    assert (result.returncode, "reason=no_data_root" in result.stderr) == (2, True)


def test_data_root_argument_wins(env: dict[str, str], tmp_path: Path) -> None:
    root = tmp_path / "explicit"
    set_focus(env, "--goal", "g", "--data-root", str(root))
    assert (root / "focus" / f"{SESSION}.md").exists()


def test_set_sweeps_files_older_than_14_days(env: dict[str, str]) -> None:
    folder = Path(env["CLAUDE_PLUGIN_DATA"]) / "focus"
    folder.mkdir(parents=True)
    old, recent, old_lock = folder / "old.md", folder / "recent.md", folder / "gone.lock"
    for path in (old, recent, old_lock):
        path.write_text("x", encoding="utf-8")
    day = 86400
    os.utime(old, (time.time() - 15 * day,) * 2)
    os.utime(old_lock, (time.time() - 15 * day,) * 2)
    os.utime(recent, (time.time() - 13 * day,) * 2)
    set_focus(env, "--goal", "g")
    assert (old.exists(), old_lock.exists(), recent.exists()) == (False, False, True)


def test_precompact_never_sweeps(env: dict[str, str], project: Path) -> None:
    folder = Path(env["CLAUDE_PLUGIN_DATA"]) / "focus"
    folder.mkdir(parents=True)
    old = folder / "old.md"
    old.write_text("x", encoding="utf-8")
    os.utime(old, (time.time() - 30 * 86400,) * 2)
    precompact(env, project)
    assert old.exists()


@pytest.mark.skipif(sys.platform == "win32", reason="holds the lock with fcntl")
def test_lock_timeout_skips_write_and_exits_0(env: dict[str, str]) -> None:
    import fcntl

    set_focus(env, "--goal", "before")
    lock = Path(env["CLAUDE_PLUGIN_DATA"]) / "focus" / f"{SESSION}.lock"
    with lock.open("a") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        result = run(env, "set", "--session", SESSION, "--goal", "after")
    assert result.returncode == 0
    assert "its condition: before" in printed(env), "a held lock skips the write"
