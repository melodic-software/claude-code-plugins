# test-scope: plugins/session-flow/hooks/run-away-hook.sh plugins/session-flow/lib/python-probe.sh
"""Contract tests for away.py's orchestrator posture: the away_orchestrate setting stored by
`start`, shown by `status`, and named in the Stop and UserPromptSubmit hook notes."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from test_away import Away, fill_report


@pytest.fixture
def ctx(tmp_path: Path) -> Away:
    return Away(tmp_path)


def test_posture_defaults_off(ctx):
    ctx.start("--kind", "bed")
    assert ctx.state()["posture"] == "off"


def test_posture_on_shows_in_status(ctx):
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=true")
    status = json.loads(ctx.cli("status").stdout)
    assert status["posture"] == "orchestrator"


@pytest.mark.parametrize(("value", "printed"), [("true", "orchestrator"), ("false", "off")])
def test_start_prints_the_posture_for_the_focus_file(ctx, value, printed):
    result = ctx.start("--kind", "bed", "--setting", f"away_orchestrate={value}")
    assert f"posture={printed}" in result.stdout.splitlines()


def test_absence_runs_without_a_focus_file(ctx):
    task = ctx.repo / "tasks.md"
    task.write_text("- [ ] write the docs\n", encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(task), "--setting", "away_orchestrate=true")
    fill_report(ctx.report())
    assert "session-flow:orchestrate" in json.loads(ctx.hook("Stop", "stop"))["reason"]
    assert not (ctx.data / "focus").exists(), "away.py neither writes nor needs the focus file"


def test_posture_rejects_other_values(ctx):
    result = ctx.cli("start", "--kind", "bed", "--setting", "away_orchestrate=maybe")
    assert result.returncode != 0
    assert "away_orchestrate" in result.stderr


def test_posture_unsubstituted_token_is_unset(ctx):
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=${user_config.away_orchestrate}")
    assert ctx.state()["posture"] == "off"


def test_posture_kept_by_a_start_without_the_setting(ctx):
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=true")
    ctx.start("--kind", "bed", "--task-file", str(ctx.repo / "tasks.md"))
    assert ctx.state()["posture"] == "orchestrator"


def test_posture_turned_off_by_a_later_start(ctx):
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=true")
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=false")
    assert ctx.state()["posture"] == "off"


def test_hook_notes_name_the_posture_only_when_on(ctx):
    task = ctx.repo / "tasks.md"
    task.write_text("- [ ] write the docs\n", encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(task))
    fill_report(ctx.report())
    off_stop = json.loads(ctx.hook("Stop", "stop"))["reason"]
    off_prompt = json.loads(ctx.hook("UserPromptSubmit", "user_prompt_typed"))["hookSpecificOutput"]["additionalContext"]
    assert "session-flow:orchestrate" not in off_stop
    assert "session-flow:orchestrate" not in off_prompt
    ctx.start("--kind", "trip", "--setting", "away_orchestrate=true")
    task.write_text("- [ ] write the docs\n- [ ] fix the test\n", encoding="utf-8")
    on_stop = json.loads(ctx.hook("Stop", "stop"))["reason"]
    on_prompt = json.loads(ctx.hook("UserPromptSubmit", "user_prompt_typed"))["hookSpecificOutput"]["additionalContext"]
    assert "session-flow:orchestrate" in on_stop
    assert "session-flow:orchestrate" in on_prompt


def test_new_absence_takes_the_option_from_the_environment(ctx):
    env = ctx.env(CLAUDE_PLUGIN_OPTION_AWAY_ORCHESTRATE="true")
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=${user_config.away_orchestrate}", env=env)
    assert ctx.state()["posture"] == "orchestrator"


def test_reconcile_keeps_a_launch_word_choice_over_the_environment(ctx):
    env = ctx.env(CLAUDE_PLUGIN_OPTION_AWAY_ORCHESTRATE="true")
    ctx.start("--kind", "bed", "--setting", "away_orchestrate=false", env=env)
    ctx.start("--kind", "bed", "--task-file", str(ctx.repo / "tasks.md"), env=env)
    assert ctx.state()["posture"] == "off"


def test_helper_reports_carry_the_posture_while_stop_stays_silent(ctx):
    task = ctx.repo / "tasks.md"
    task.write_text("- [ ] write the docs\n", encoding="utf-8")
    ctx.start("--kind", "trip", "--task-file", str(task), "--setting", "away_orchestrate=true")
    fill_report(ctx.report())
    assert ctx.hook("Stop", "stop", background_tasks=[{"id": "b1"}]) == ""
    report = json.loads(ctx.hook("UserPromptSubmit", "user_prompt_subagent_report"))
    assert "session-flow:orchestrate" in report["hookSpecificOutput"]["additionalContext"]
