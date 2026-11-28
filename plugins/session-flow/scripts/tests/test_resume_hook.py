# test-scope: plugins/session-flow/scripts/focus.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/reference/resume.md
"""Contract tests for resume_hook.py, the UserPromptSubmit hook that injects the resume
procedure when a pasted resume prompt starts with its `Read @<handoff file>` directive.

Expected behavior comes from the plan's decision D10 (anchored match on the first line, or on a
`/goal` paste's directive line; the file must exist; one injection per session through a focus.py
marker) and from the hook-enablement contract's precedence for `resume_context_enabled`
(docs/contracts/hook-enablement/README.md, "Precedence"). Every case runs the CLI as a subprocess
with a temp HOME and plugin data root.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "resume_hook.py"
RESUME_MD = SCRIPTS.parent / "reference" / "resume.md"
SESSION = "11111111-2222-3333-4444-555555555555"
OPTION = "CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED"
TAIL = (
    ", confirm its Original goal still governs the remaining next steps, then continue them. "
    "For the next save-point invoke /session-flow:handoff via the Skill tool; never write a "
    "handoff file free-hand."
)
MARK = "session-flow resume procedure"


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    home = tmp_path / "home"
    home.mkdir()
    base = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_")}
    base.update(HOME=str(home), CLAUDE_PLUGIN_DATA=str(tmp_path / "session-flow"))
    return base


@pytest.fixture
def handoff(tmp_path: Path) -> Path:
    path = (
        tmp_path / "repo" / ".work" / "handoffs" / "20261124T100000Z-handoff-widget.md"
    )
    path.parent.mkdir(parents=True)
    (tmp_path / "repo" / ".git").mkdir()
    path.write_text("---\nhandoff_shape: 5\n---\n", encoding="utf-8")
    return path


def fire(
    env: dict[str, str], prompt: str, cwd: Path | None = None
) -> subprocess.CompletedProcess:
    payload = {
        "session_id": SESSION,
        "transcript_path": "/dev/null",
        "cwd": str(cwd or env["HOME"]),
        "hook_event_name": "UserPromptSubmit",
        "prompt": prompt,
    }
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), "hook", "UserPromptSubmit"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
        cwd=env["HOME"],
        timeout=30,
        check=False,
    )


def directive(path: Path) -> str:
    return f"Read @{path}{TAIL}"


def test_anchor_first_line_only(env, handoff):
    first = fire(env, directive(handoff) + "\nPrior session: x.\nNext:\nShip it")
    assert first.returncode == 0
    assert MARK in first.stdout, "a directive on the first line injects the procedure"
    assert str(handoff) in first.stdout, "the injection names the handoff file"
    later = fire(
        {**env, "CLAUDE_PLUGIN_DATA": env["CLAUDE_PLUGIN_DATA"] + "-2"},
        "Look at this:\n" + directive(handoff),
    )
    assert later.returncode == 0 and later.stdout == "", (
        "a directive on a later line stays silent"
    )


def test_quoted_directive_silent(env, handoff):
    quoted = fire(env, f'The old prompt said "{directive(handoff)}", why did it fail?')
    assert quoted.returncode == 0 and quoted.stdout == "", (
        "a mid-text quote stays silent"
    )
    indented = fire(env, "  > " + directive(handoff))
    assert indented.stdout == "", "a quoted block line stays silent"


def test_non_handoff_read_silent(env, tmp_path, handoff):
    readme = tmp_path / "repo" / "README.md"
    readme.write_text("x", encoding="utf-8")
    assert fire(env, f"Read @{readme} and fix X").stdout == "", (
        "a non-handoff read stays silent"
    )
    assert fire(env, "Read @README.md and fix X").stdout == ""
    missing = handoff.with_name("20261124T110000Z-handoff-gone.md")
    assert fire(env, directive(missing)).stdout == "", (
        "a handoff path that does not exist stays silent"
    )
    assert fire(env, "fix the parser").stdout == "", "an ordinary prompt stays silent"


def test_once_per_session(env, handoff):
    assert MARK in fire(env, directive(handoff)).stdout
    again = fire(env, directive(handoff))
    assert again.returncode == 0 and again.stdout == "", (
        "a second paste in one session stays silent"
    )
    focus = Path(env["CLAUDE_PLUGIN_DATA"]) / "focus" / f"{SESSION}.md"
    assert f"This session resumed from {handoff}" in focus.read_text(
        encoding="utf-8"
    ), "the marker is the focus file's Handoff section, written through focus.py"


def test_goal_then_directive_single_injection(env, handoff):
    goal = fire(env, "/goal every widget test passes\n" + directive(handoff))
    assert MARK in goal.stdout, "a /goal paste whose last line is the directive injects"
    plain = fire(env, directive(handoff) + "\nNext:\nShip it")
    assert plain.stdout == "", (
        "the resume region pasted after the goal region does not inject twice"
    )


def test_goal_with_multiline_condition_reads_its_last_line(env, handoff):
    goal = fire(
        env, "/goal every widget test passes\nand the docs build\n" + directive(handoff)
    )
    assert MARK in goal.stdout, (
        "the goal region ends in the directive line (save_point.py goal-region rule)"
    )


def test_goal_with_directive_mid_condition_silent(env, handoff):
    prompt = "/goal finish\n" + directive(handoff) + "\nthen also ship"
    assert fire(env, prompt).stdout == "", (
        "a directive that is not the goal region's last line stays silent"
    )


def test_user_false_turns_it_off(env, handoff):
    off = fire({**env, OPTION: "false"}, directive(handoff))
    assert off.returncode == 0 and off.stdout == ""


def test_repository_false_turns_it_off_and_user_true_wins(env, handoff, tmp_path):
    repo = tmp_path / "repo"
    conventions = repo / "docs" / "conventions"
    conventions.mkdir(parents=True)
    (conventions / "session-flow.yaml").write_text(
        "resume_context_enabled: false\n", encoding="utf-8"
    )
    project = {**env, "CLAUDE_PROJECT_DIR": str(repo)}
    assert fire(project, directive(handoff)).stdout == "", (
        "the repository value decides when the user set none"
    )
    assert MARK in fire({**project, OPTION: "true"}, directive(handoff)).stdout, (
        "the user's own value wins"
    )


def test_invalid_user_value_is_named_and_dropped(env, handoff):
    result = fire({**env, OPTION: "yes"}, directive(handoff))
    assert MARK in result.stdout, (
        "an invalid value is dropped and the default (on) applies"
    )
    assert (
        "invalid_setting" in result.stderr and "resume_context_enabled" in result.stderr
    )


def test_malformed_payload_exit0(env):
    result = subprocess.run(
        [sys.executable, "-I", str(SCRIPT), "hook", "UserPromptSubmit"],
        input="{not json",
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0 and result.stdout == ""


def test_injection_carries_resume_md(env, handoff):
    result = fire(env, directive(handoff))
    assert RESUME_MD.read_text(encoding="utf-8").strip() in result.stdout


def test_compact_focus_off_writes_no_marker(env, handoff):
    off = {**env, "CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED": "false"}
    assert MARK in fire(off, directive(handoff)).stdout
    assert not (Path(env["CLAUDE_PLUGIN_DATA"]) / "focus" / f"{SESSION}.md").exists(), (
        "compact_focus_enabled gates every focus-file write"
    )
