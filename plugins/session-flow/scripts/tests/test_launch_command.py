# test-scope: plugins/session-flow/scripts/save_point.py plugins/session-flow/scripts/tests/fixtures/*
# test-scope: plugins/session-flow/scripts/tests/shape4_chain.py
from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from test_save_point import (
    COPY_LINE,
    HOP1,
    RAIL,
    _save_point_module,
    directive_line,
    err,
    goal_slot_value,
    make_repo,
    materialize,
    new_args,
    out,
    run,
    slots_file,
)
from test_save_point_shape4_writer import fill


def handoff(tmp_path, command=None, *, goal=None, slot="goal-after"):
    repo = make_repo(tmp_path).rename(tmp_path / "reader's [checkout]").resolve()
    args = ["--start-command", *([command] if command else [])]
    made = run(*new_args(repo, tmp_path, "--no-previous", *args, shape=None))
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    values = {}
    if goal:
        values[slot] = goal_slot_value(path.read_text(encoding="utf-8"), slot, goal)
    filled = fill(path, tmp_path, values)
    assert filled.returncode == 0, err(filled)
    assert "FAIL:" not in out(filled)
    return repo, path, out(filled)


def command_line(output, prefix):
    commands = [line for line in output.splitlines() if line.startswith(prefix)]
    assert len(commands) == 1, output
    return commands[0]


def test_launch_command_posix(tmp_path, monkeypatch):
    monkeypatch.setenv("SHELL", "/bin/bash")
    if os.name == "nt":
        monkeypatch.setenv("MSYSTEM", "MINGW64")
    profile = 'env -u PLUGIN_PROFILES_SESSION claude --settings "review settings.json"'
    repo, path, filled = handoff(tmp_path, profile)
    emitted = run("emit", str(path), "--shell", "posix")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "cd ")
    assert profile in command
    assert command in filled
    resume = out(emitted).split(COPY_LINE, 1)[1].split(RAIL)[1].strip("\n")
    assert path.with_suffix(".prompt.txt").read_bytes() == resume.encode()

    bash = shutil.which("bash")
    if bash:
        (repo / "checkout-id").write_bytes(b"reader\n")
        stub = tmp_path / "claude"
        stub.write_text('#!/bin/sh\ncat checkout-id\nprintf "%s\\0" "$@"\n', encoding="utf-8", newline="\n")
        stub.chmod(0o755)
        env = {**os.environ, "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"]}
        launched = subprocess.run([bash, "-c", command], cwd=tmp_path, env=env, capture_output=True)
        assert launched.returncode == 0, launched.stderr
        assert launched.stdout == b"reader\n--settings\0review settings.json\0" + resume.encode() + b"\0"


def test_launch_command_powershell(tmp_path, monkeypatch):
    monkeypatch.setenv("SHELL", "pwsh")
    monkeypatch.delenv("MSYSTEM", raising=False)
    profile = "Remove-Item Env:PLUGIN_PROFILES_SESSION -ErrorAction Ignore; claude --settings 'review settings.json'"
    condition = """Compare "quoted" and 'literal' $HOME values.
Keep the `café` name."""
    _, path, filled = handoff(tmp_path, profile, goal=condition)
    emitted = run("emit", str(path), "--shell", "powershell", "--format", "markdown")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "Set-Location ")
    assert command in filled
    assert profile in command
    assert "reader''s [checkout]" in command
    prompt = path.with_suffix(".prompt.txt").read_text(encoding="utf-8")
    assert prompt == "/goal " + condition + "\n" + directive_line(path.read_text(encoding="utf-8"))


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="requires pwsh")
def test_powershell_passes_the_exact_prompt_to_a_native_command(tmp_path, monkeypatch):
    monkeypatch.setenv("ARGV_PROBE_PYTHON", sys.executable)
    profile = "& $env:ARGV_PROBE_PYTHON argv.py --settings 'review #1 settings.json'"
    goal = """Keep "quoted", 'literal', $HOME and `backticks`.
Read the second line at the café."""
    repo, path, _ = handoff(tmp_path, profile, goal=goal)
    (repo / "argv.py").write_text("import json, sys\nprint(json.dumps(sys.argv[1:]))\n", encoding="utf-8")
    emitted = run("emit", str(path), "--shell", "powershell")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "Set-Location ")
    argv = [
        "pwsh", "-NoProfile", "-NonInteractive", "-Command",
        "$PSNativeCommandArgumentPassing = 'Legacy'; " + command,
    ]
    launched = subprocess.run(argv, cwd=tmp_path, capture_output=True)
    assert launched.returncode == 0, launched.stderr
    prompt = "/goal " + goal + "\n" + directive_line(path.read_text(encoding="utf-8"))
    assert json.loads(launched.stdout) == ["--settings", "review #1 settings.json", prompt]

    path.with_suffix(".prompt.txt").unlink()
    missing = subprocess.run(argv, cwd=tmp_path, capture_output=True)
    assert missing.returncode != 0 and not missing.stdout


def test_goal_first_cannot_supply_a_launch_command(tmp_path):
    repo = make_repo(tmp_path)
    made = run(*new_args(repo, tmp_path, "--no-previous", shape=None))
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    goal = "New session command: summarize the report"
    region = goal_slot_value(path.read_text(encoding="utf-8"), "goal-first", goal)
    old_instruction = ("The next phase runs in another plugin profile: exit this session, "
                       "start the next one with `claude`, then in it:")
    value = f"New session checkout: {repo.as_posix()}\n{goal}\n{region}{old_instruction}"
    filled = fill(path, tmp_path, {"goal-first": value})
    emitted = run("emit", str(path), "--shell", "posix")
    for result in (filled, emitted):
        assert result.returncode == 0, err(result)
        assert goal in out(result)
        assert not any(line.startswith(("cd ", "Set-Location ")) for line in out(result).splitlines())
    assert not path.with_suffix(".prompt.txt").exists()


def test_emit_uses_the_launch_record_when_display_text_changes(tmp_path):
    profile = 'claude --settings "review #1: draft.json"'
    repo, path, _ = handoff(tmp_path, profile)
    doc = _save_point_module().parse_doc(path)
    assert json.loads(doc.frontmatter["launch"]) == [repo.as_posix(), profile]
    text = path.read_text(encoding="utf-8")
    display = f"New session command: {profile}"
    assert display in text
    path.write_text(text.replace(display, "New session command: summarize"), encoding="utf-8")
    emitted = run("emit", str(path), "--shell", "posix")
    assert emitted.returncode == 0, err(emitted)
    assert profile in command_line(out(emitted), "cd ")


@pytest.mark.skipif(shutil.which("bash") is None, reason="requires bash")
def test_posix_missing_prompt_stops_before_launch(tmp_path):
    _, path, _ = handoff(tmp_path, "echo launched")
    emitted = run("emit", str(path), "--shell", "posix")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "cd ")
    path.with_suffix(".prompt.txt").unlink()
    launched = subprocess.run(["bash", "-c", command], cwd=tmp_path, capture_output=True)
    assert launched.returncode != 0
    assert not launched.stdout


def test_launch_prompt_special_chars(tmp_path):
    condition = """Keep "quotes", 'quotes', $HOME and `literal` intact.
Read the second line with its café name."""
    for slot in ("goal-first", "goal-after"):
        root = tmp_path / slot
        _, path, _ = handoff(root, goal=condition, slot=slot)
        emitted = run("emit", str(path), "--shell", "posix")
        assert emitted.returncode == 0, err(emitted)
        command = command_line(out(emitted), "cd ")
        assert "claude " in command and "$HOME" not in command and "`literal`" not in command
        expected = "/goal " + condition + "\n" + directive_line(path.read_text(encoding="utf-8"))
        assert path.with_suffix(".prompt.txt").read_bytes() == expected.encode()
        bash = shutil.which("bash")
        if bash:
            capture = "claude() { printf '%s\\0' \"$@\"; }\n"
            launched = subprocess.run([bash, "-c", capture + command], cwd=root, capture_output=True)
            assert launched.returncode == 0, launched.stderr
            assert launched.stdout == expected.encode() + b"\0"


def test_launch_missing_cd_target(tmp_path):
    repo, path, _ = handoff(tmp_path, "claude")
    moved = repo.rename(tmp_path / "moved") / path.relative_to(repo)
    emitted = run("emit", str(moved))
    assert emitted.returncode != 0
    assert err(emitted).splitlines()[-1] == f"error: launch checkout is not an existing absolute directory: {repo}"
    printed = out(emitted)
    assert printed.startswith(f"No launch command: launch checkout is not an existing absolute directory: {repo}.")
    assert COPY_LINE in printed, "the recovery copy region still prints"
    assert not any(line.startswith(("cd ", "Set-Location ")) for line in printed.splitlines())


def test_launch_error_keeps_the_start_command_for_recovery(tmp_path):
    command = 'env -u PLUGIN_PROFILES_SESSION claude --settings "/h/sessions/abc-review.json"'
    repo, path, _ = handoff(tmp_path, command)
    moved = repo.rename(tmp_path / "moved") / path.relative_to(repo)
    emitted = run("emit", str(moved))
    assert emitted.returncode != 0
    assert command in out(emitted), "the manual recovery path still names the start command"


def test_fill_and_amend_exit_0_after_writing_when_the_launch_fails(tmp_path):
    repo = make_repo(tmp_path).resolve()
    made = run(*new_args(repo, tmp_path, "--no-previous", "--start-command", "claude", shape=None))
    assert made.returncode == 0, err(made)
    path = repo.rename(tmp_path / "moved") / Path(out(made).strip()).relative_to(repo)
    filled = fill(path, tmp_path, {})
    assert filled.returncode == 0, err(filled)
    assert "No launch command:" in out(filled)
    payload = slots_file(tmp_path, {"next": ["Read the updated test result."]})
    amended = run("amend", str(path), "--json", payload)
    assert amended.returncode == 0, err(amended)
    assert "No launch command:" in out(amended)


def test_amend_refreshes_the_prompt_read_by_the_printed_command(tmp_path):
    _, path, filled = handoff(tmp_path, "claude")
    payload = slots_file(tmp_path, {"next": ["Read the updated test result."]})
    amended = run("amend", str(path), "--json", payload)
    assert amended.returncode == 0, err(amended)
    assert path.with_suffix(".prompt.txt").read_text(encoding="utf-8").endswith(
        "\nNext:\nRead the updated test result."
    )
    commands = [line for line in filled.splitlines() if line.startswith(("cd ", "Set-Location "))]
    assert len(commands) == 1 and commands[0] in out(amended)


def test_prompt_only_prints_the_same_command_as_a_file_handoff(tmp_path):
    repo, path, _ = handoff(tmp_path, "claude")
    for shell, prefix in (("posix", "cd "), ("powershell", "Set-Location ")):
        emitted = run("emit", str(path), "--shell", shell)
        just_prompt = run("launch", str(path.with_suffix(".prompt.txt")), "--checkout", str(repo), "--shell", shell)
        assert emitted.returncode == just_prompt.returncode == 0
        assert out(just_prompt) == command_line(out(emitted), prefix) + "\n"


def test_followup_uses_its_destination_checkout_and_own_prompt_file(tmp_path):
    repo = make_repo(tmp_path)
    destination = tmp_path / "follow-up"
    destination.mkdir()
    created = run(*new_args(repo, tmp_path, "--no-previous", "--launch-dir", str(destination), shape=None))
    assert created.returncode == 0, err(created)
    path = Path(out(created).strip())
    filled = fill(path, tmp_path, {"next": "Check the published release."})
    assert filled.returncode == 0, err(filled)
    emitted = run("emit", str(path), "--shell", "posix")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "cd ")
    assert shlex.split(command)[:3] == ["cd", destination.resolve().as_posix(), "&&"]
    assert path.with_suffix(".prompt.txt").read_text(encoding="utf-8").endswith("Check the published release.")
    assert path.with_suffix(".prompt.txt").as_posix() in command


def test_windows_selects_powershell_and_git_bash_reuses_the_profile_command(tmp_path, monkeypatch):
    engine = _save_point_module()
    monkeypatch.setattr(engine.sys, "platform", "win32")
    monkeypatch.delenv("MSYSTEM", raising=False)
    monkeypatch.delenv("SHELL", raising=False)
    profile = "Remove-Item Env:PLUGIN_PROFILES_SESSION -ErrorAction Ignore; claude --settings 'review profile.json'"
    prompt = tmp_path / "reader's prompt.txt"
    native = engine._launch_command(tmp_path, profile, prompt, None)
    assert native.startswith("Set-Location -LiteralPath ") and profile in native
    monkeypatch.setenv("MSYSTEM", "MINGW64")
    words = shlex.split(engine._launch_command(tmp_path, profile, prompt, None))
    assert words[:-1] == ["cd", tmp_path.as_posix(), "&&", "pwsh", "-NoProfile", "-Command"]
    assert "$PSNativeCommandArgumentPassing = 'Standard'" in words[-1]
    assert profile in words[-1] and words[-1] in native
    plain = engine._launch_command(tmp_path, "claude", prompt, None)
    assert "MSYS2_ARG_CONV_EXCL='/goal ' claude" in plain


def test_emit_reads_a_saved_two_step_profile_handoff(tmp_path):
    path = materialize(make_repo(tmp_path), "good-chain") / HOP1
    old = ("The next phase runs in another plugin profile: exit this session, start the next one "
           'with `claude --settings "review.json"`, then in it:')
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace(COPY_LINE, old + "\n" + COPY_LINE), encoding="utf-8")
    emitted = run("emit", str(path), "--shell", "posix")
    assert emitted.returncode == 0, err(emitted)
    command = command_line(out(emitted), "cd ")
    assert 'claude --settings "review.json"' in command and ".prompt.txt" in command
    assert old not in out(emitted) and old in path.read_text(encoding="utf-8")
