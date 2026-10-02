"""Contract tests for collect.py: the CLI envelope and the store records it writes.

Runs the scripts by subprocess, testing the CLI interface, not internals. The tracer test also
drives sweep.py over the store and transcript_reader.py through collect; repo identity comes from
lib/state-key.sh. Fixtures: `tracer/proj-a/tracer-0001.jsonl`; `multi/proj-a/sess-a1.jsonl` with
`sess-a1/subagents/agent-x1.jsonl`, `multi/proj-a/sess-a2.jsonl`, `multi/proj-b/sess-b1.jsonl`.
Their `cwd` values are placeholders rewritten to `tmp_path` directories.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest
from conftest import SCRIPTS, envelope, run_cli

STATE_KEY = SCRIPTS.parents[2] / "lib" / "state-key.sh"

# Tracer fixture: msg_A streams three records (output 5, 20, 40; the last wins) and msg_B one (7).
# The per-record sum would be 72, the streaming double count.
TRACER_OUTPUT_TOKENS = 40 + 7


def test_tracer_end_to_end(data_dir, copy_fixture):
    root = copy_fixture("tracer")

    collected = run_cli("collect.py", "collect", "--data-dir", str(data_dir), "--projects-root", str(root))
    assert collected.returncode == 0, collected.stderr
    collect_env = envelope(collected)
    assert collect_env["schema"] == "audit-sessions.collect/v1"
    assert collect_env["data"]["ingested"] == 1

    swept = run_cli("sweep.py", "--data-dir", str(data_dir), "--format", "json")
    assert swept.returncode == 0, swept.stderr
    sweep_env = envelope(swept)
    assert sweep_env["schema"] == "audit-sessions.sweep/v1"
    assert sweep_env["data"]["window"]["sessions"] == 1
    assert sweep_env["data"]["metrics"]["tokens.main.output"]["value"] == TRACER_OUTPUT_TOKENS


# --- multi fixture: proj-a/sess-a1 (rich, one subagent), proj-a/sess-a2, proj-b/sess-b1 ---


@pytest.fixture
def multi(copy_fixture, tmp_path):
    """The multi fixture with `cwd` placeholders pointing at a real and a removed directory."""
    root = copy_fixture("multi")
    cwd_a = tmp_path / "work" / "repo-a"
    cwd_a.mkdir(parents=True)
    gone = tmp_path / "work" / "removed"
    for path in root.rglob("*.jsonl"):
        text = path.read_text(encoding="utf-8")
        text = text.replace("__CWD_A__", json.dumps(str(cwd_a))[1:-1])
        text = text.replace("__CWD_GONE__", json.dumps(str(gone))[1:-1])
        path.write_text(text, encoding="utf-8", newline="\n")
    return root, cwd_a


def collect(data_dir: Path, root: Path, *extra: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(SCRIPTS / "collect.py"), "collect", "--data-dir", str(data_dir)]
    return subprocess.run(
        [*args, "--projects-root", str(root), *extra],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        env=env,
    )


def records(data_dir: Path) -> dict[str, dict]:
    store = data_dir / "audit-sessions" / "store" / "v1" / "sessions"
    return {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in store.glob("p-*/*.json")}


def state_key(cwd: Path) -> str:
    return subprocess.run(
        ["bash", str(STATE_KEY), "--root", str(cwd)], capture_output=True, text=True, check=True
    ).stdout.strip()


def test_full_session_record(data_dir, multi):
    root, cwd_a = multi
    result = collect(data_dir, root)
    assert result.returncode == 0, result.stdout + result.stderr
    data = envelope(result)["data"]
    assert (data["scanned"], data["ingested"], data["failed"]) == (3, 3, [])
    assert data["unknown_record_types"] == {"future-thing": 1}
    assert data["redaction"]["excerpts_suppressed"] is False

    rec = records(data_dir)["sess-a1"]
    identity, worktree = state_key(cwd_a).rsplit("/", 1)
    assert rec["schema"] == "session-record/v1"
    assert rec["project_dir"] == "proj-a"
    assert rec["cwd"] == str(cwd_a)
    assert (rec["repo_identity"], rec["worktree"]) == (identity, worktree)
    assert rec["cc_versions"] == ["2.1.286", "2.1.287"]
    assert rec["time"] == {
        "start": "2026-09-20T10:00:00Z",
        "end": "2026-09-20T10:30:05Z",
        "wall_clock_s": 1805,
        "active_s": 45,
        "turn_durations": 2,
        "idle_gaps_gt5m": 2,
        "idle_gaps_gt1h": 0,
        "human_gaps_gt5m": 2,
        "human_gaps_gt1h": 0,
        "thinking_ms": 1500,
    }
    assert rec["models"] == {"main": {"claude-opus-5-5": 7, "<synthetic>": 1}, "sub": {"claude-haiku-4-5-20251001": 1}}
    assert rec["effort"] == {"main": {"high": 2}, "sub": {"low": 1}}
    assert rec["tokens"] == {
        "main": {
            "input": 170,
            "output": 142,
            "cache_read": 16000,
            "cache_creation": 300,
            "cache_creation_1h": 300,
            "cache_creation_5m": 0,
            "unique_messages": 8,
        },
        "sub": {
            "input": 50,
            "output": 8,
            "cache_read": 0,
            "cache_creation": 400,
            "cache_creation_1h": 0,
            "cache_creation_5m": 400,
            "unique_messages": 1,
        },
    }
    assert rec["cache_miss"] == {"reasons": {"ttl_expired": 1}, "missed_input_tokens": 4000}
    assert rec["rate_limit"] == {"types": {"five_hour": 1}, "usage_limit_notices": 1}
    assert rec["errors"] == {"rate_limit": 1}
    assert rec["tools"] == {
        "calls": 6,
        "by_name": {"Edit": 3, "Bash": 1, "Write": 1, "Skill": 1},
        "denials": {"permission-rule": 1},
        "user_rejected": 1,
        "interrupts": 1,
        "interrupts_sub": 1,
    }
    assert rec["edits"] == {
        "files": 2,
        "files_ge3": 1,
        "max_one_file": 3,
        "by_relpath": {"src/widget.py": 3, "README.md": 1},
    }
    assert rec["subagents"] == {
        "count": 1,
        "by_type": {"Explore": 1},
        "by_model": {"claude-haiku-4-5-20251001": 1},
        "by_depth": {"1": 1},
    }
    assert rec["stop_hooks"] == {"runs": 1, "ms_total": 150, "ms_p50": 150, "ms_p90": 150, "blocks": 0, "errors": 0}
    assert rec["context"] == {
        "compactions": [{"trigger": "manual", "pre_tokens": 150000, "post_tokens": 20000}],
        "compact_commands": 1,
        "clear_commands": 1,
        "started_with_clear": True,
    }
    assert rec["link_keys"] == {
        "custom_title": "widget work",
        "agent_name": "widget-agent",
        "first_ts": "2026-09-20T10:00:00Z",
    }
    assert rec["branches"] == ["feat/widget", "feat/widget-wt"]
    assert rec["prs"] == [{"repo": "example-org/widgets", "number": 42}]
    assert rec["permission"] == {"modes": {"default": 1, "auto": 1}, "changes": 1}
    assert rec["commands"] == {"slash": {"clear": 1, "compact": 1}, "skills_model_invoked": {"testing:write": 1}}
    assert rec["human"]["turns"] == 4
    assert [(t["idx"], t["uuid"], t["words"], t["flags"]) for t in rec["human"]["flagged"]] == [
        (1, "u8", 8, ["short-after-assistant", "lexicon-correction"]),
        (2, "u11", 3, ["short-after-assistant", "lexicon-correction", "frustration"]),
    ]
    assert [t["excerpt"] for t in rec["human"]["flagged"]] == [
        "no, that's wrong, use the existing store module",
        "ugh!! still failing",
    ]
    assert rec["unknown"] == {"record_types": {"future-thing": 1}, "system_subtypes": {"mystery_subtype": 1}}
    assert rec["parse"] == {"files": 2, "lines": 39, "records": 39, "bad_lines": 0, "incomplete": 0, "unknown": 1}
    assert rec["redaction"]["excerpts_suppressed"] is False
    assert rec["redaction"]["rules_skipped"] == 0
    assert rec["redaction"]["rules_loaded"] > 0
    assert rec["redaction"]["rules_version"]
    assert set(rec["fingerprint"]) == {"main_size", "main_mtime_ns", "head_sha256", "sub_count", "sub_size", "sub_mtime_ns"}
    assert rec["fingerprint"]["sub_count"] == 1

    census = rec["census"]
    assert census["2.1.287|claude-opus-5-5"]["record_type:assistant"] == 8
    assert census["2.1.287|claude-opus-5-5"]["effort_value:high"] == 3
    assert census["2.1.287|claude-opus-5-5"]["key_path:assistant:message.id"] == 8
    assert census["2.1.287|claude-opus-5-5"]["usage_key:cache_creation.ephemeral_1h_input_tokens"] == 2
    assert census["2.1.287|claude-haiku-4-5-20251001"]["record_type:assistant"] == 2
    assert census["2.1.287|<synthetic>"]["assistant_error:rate_limit"] == 1
    assert census["2.1.287|*"]["system_subtype:turn_duration"] == 2
    assert census["2.1.286|*"]["record_type:user"] == 1
    assert census["unknown|*"]["record_type:custom-title"] == 1


def test_second_run_skips_every_unchanged_session(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    before = records(data_dir)
    data = envelope(collect(data_dir, root))["data"]
    assert (data["ingested"], data["skipped_unchanged"], data["store_records"]) == (0, 3, 3)
    assert records(data_dir) == before


def append_record(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(record) + "\n")


def test_grown_and_shrunk_files_are_reparsed(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    append_record(
        root / "proj-a" / "sess-a2.jsonl",
        {"type": "user", "uuid": "b-u3", "timestamp": "2026-09-21T09:02:00Z", "promptSource": "typed",
         "message": {"role": "user", "content": "one more thing"}},
    )
    shrunk = root / "proj-b" / "sess-b1.jsonl"
    shrunk.write_text(shrunk.read_text(encoding="utf-8").splitlines(keepends=True)[0], encoding="utf-8", newline="\n")

    data = envelope(collect(data_dir, root))["data"]
    assert (data["ingested"], data["skipped_unchanged"]) == (2, 1)
    stored = records(data_dir)
    assert stored["sess-a2"]["human"]["turns"] == 3
    assert stored["sess-b1"]["tokens"]["main"]["unique_messages"] == 0


def test_force_reingests_unchanged_sessions(data_dir, multi):
    root, _ = multi
    assert collect(data_dir, root).returncode == 0
    assert envelope(collect(data_dir, root, "--force"))["data"]["ingested"] == 3


def test_session_and_since_filters(data_dir, multi):
    root, _ = multi
    data = envelope(collect(data_dir, root, "--session", "sess-b1"))["data"]
    assert (data["scanned"], data["ingested"]) == (1, 1)
    stamp = time.mktime((2020, 1, 1, 0, 0, 0, 0, 0, 0))
    os.utime(root / "proj-a" / "sess-a2.jsonl", (stamp, stamp))
    data = envelope(collect(data_dir, root, "--since", "2025-01-01"))["data"]
    assert data["scanned"] == 2
    assert set(records(data_dir)) == {"sess-a1", "sess-b1"}


def test_clear_after_the_first_turn_does_not_start_the_session(data_dir, multi):
    root, _ = multi
    append_record(
        root / "proj-a" / "sess-a2.jsonl",
        {"type": "user", "uuid": "b-u9", "timestamp": "2026-09-21T09:05:00Z",
         "message": {"role": "user", "content": "<command-name>/clear</command-name>"}},
    )
    assert collect(data_dir, root).returncode == 0
    context = records(data_dir)["sess-a2"]["context"]
    assert (context["clear_commands"], context["started_with_clear"]) == (1, False)


def write_session(root: Path, sid: str, turns: list[str]) -> None:
    """A session where each typed turn follows an assistant reply."""
    lines = []
    for n, text in enumerate(turns):
        lines.append({"type": "assistant", "uuid": f"a{n}", "timestamp": f"2026-09-25T10:{n:02d}:00Z",
                      "message": {"id": f"m{n}", "model": "claude-opus-5-5", "content": [{"type": "text", "text": "ok"}]}})
        lines.append({"type": "user", "uuid": f"u{n}", "timestamp": f"2026-09-25T10:{n:02d}:30Z",
                      "promptSource": "typed", "message": {"role": "user", "content": text}})
    project = root / "proj-r"
    project.mkdir(parents=True, exist_ok=True)
    (project / f"{sid}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in lines), encoding="utf-8", newline="\n")


def test_excerpts_are_redacted_then_capped(data_dir, tmp_path):
    root = tmp_path / "projects"
    email = "".join(("dev.person", "@", "example", ".com"))
    home = "/".join(("", "home", "someone", "repo"))
    key = "".join(("AKIA", "IOSFODNN7", "EXAMPLE"))
    write_session(root, "sess-r", [f"mail {email} now", f"open {home}/a.py", f"use {key} here", "x" * 50])

    assert collect(data_dir, root, "--excerpt-chars", "20").returncode == 0
    excerpts = [t["excerpt"] for t in records(data_dir)["sess-r"]["human"]["flagged"]]
    assert excerpts[0] == "mail <email> now"
    assert excerpts[1] == "open ~/repo/a.py"
    assert excerpts[2].startswith("use <redacted:")
    assert key not in excerpts[2]
    assert excerpts[3] == "x" * 20


def test_excerpt_chars_zero_stores_no_text_and_word_limit_bounds_flags(data_dir, tmp_path):
    root = tmp_path / "projects"
    write_session(root, "sess-w", ["two words", "three short words"])
    assert collect(data_dir, root, "--excerpt-chars", "0", "--excerpt-words", "2").returncode == 0
    flagged = records(data_dir)["sess-w"]["human"]["flagged"]
    assert [(t["words"], t["excerpt"]) for t in flagged] == [(2, None)]


def test_skipped_redaction_rule_suppresses_excerpts_but_keeps_numbers(data_dir, multi, tmp_path):
    root, _ = multi
    # The plugin's script layout, copied, with a vendored rules file whose one rule cannot compile.
    skill = tmp_path / "plugin" / "skills" / "audit-sessions"
    (skill / "scripts").mkdir(parents=True)
    (tmp_path / "plugin" / "scripts").mkdir()
    shutil.copy2(SCRIPTS.parents[2] / "scripts" / "transcript_reader.py", tmp_path / "plugin" / "scripts")
    for name in ("collect.py", "census.py", "redact.py"):
        shutil.copy2(SCRIPTS / name, skill / "scripts")
    (skill / "vendor" / "gitleaks").mkdir(parents=True)
    rules = {"rules": [{"id": "broken", "regex": "(unclosed", "keywords": []}], "source_version": "test"}
    (skill / "vendor" / "gitleaks" / "gitleaks-rules.json").write_text(json.dumps(rules), encoding="utf-8")

    script = skill / "scripts" / "collect.py"
    result = subprocess.run(
        [sys.executable, str(script), "collect", "--data-dir", str(data_dir), "--projects-root", str(root)],
        capture_output=True, text=True, encoding="utf-8", timeout=60,
    )
    assert result.returncode == 1, result.stdout + result.stderr
    env = envelope(result)
    assert env["status"] == "warning"
    assert env["data"]["redaction"] == {"rules_loaded": 0, "rules_skipped": 1, "excerpts_suppressed": True}
    rec = records(data_dir)["sess-a1"]
    assert rec["human"]["turns"] == 4
    assert [t["excerpt"] for t in rec["human"]["flagged"]] == [None, None]
    assert rec["redaction"]["excerpts_suppressed"] is True


def test_retention_prunes_old_records_and_never_reingests_them(data_dir, multi):
    root, _ = multi
    assert envelope(collect(data_dir, root, "--retention-days", "0"))["data"]["store_records"] == 3
    data = envelope(collect(data_dir, root, "--retention-days", "1"))["data"]
    assert (data["ingested"], data["pruned"], data["store_records"]) == (0, 3, 0)
    data = envelope(collect(data_dir, root, "--retention-days", "1"))["data"]
    assert (data["ingested"], data["skipped_expired"], data["pruned"], data["store_records"]) == (0, 3, 0, 0)


def test_files_older_than_retention_are_not_parsed(data_dir, multi):
    root, _ = multi
    stamp = time.mktime((2020, 1, 1, 0, 0, 0, 0, 0, 0))
    for path in root.rglob("*.jsonl"):
        os.utime(path, (stamp, stamp))
    data = envelope(collect(data_dir, root, "--retention-days", "30"))["data"]
    assert (data["scanned"], data["skipped_expired"], data["ingested"]) == (3, 3, 0)


def test_removed_cwd_gives_null_identity_and_one_warning(data_dir, multi):
    root, _ = multi
    # A second session in a different removed directory: still one warning.
    source = (root / "proj-b" / "sess-b1.jsonl").read_text(encoding="utf-8")
    source = source.replace("sess-b1", "sess-b2").replace("removed", "removed-too")
    (root / "proj-b" / "sess-b2.jsonl").write_text(source, encoding="utf-8", newline="\n")
    result = collect(data_dir, root)
    assert result.returncode == 0
    stored = records(data_dir)
    assert (stored["sess-b1"]["repo_identity"], stored["sess-b2"]["worktree"]) == (None, None)
    assert stored["sess-a1"]["repo_identity"] is not None
    assert result.stderr.count("warning:") == 1


@pytest.mark.skipif(sys.platform == "win32", reason="the fake bash on PATH is a POSIX shell script")
def test_unusable_bash_gives_null_identity_and_one_warning(data_dir, multi, tmp_path):
    root, _ = multi
    shutil.rmtree(root / "proj-b")
    fake = tmp_path / "fakebin"
    fake.mkdir()
    (fake / "bash").write_text("#!/bin/sh\nexit 3\n", encoding="utf-8")
    (fake / "bash").chmod(0o755)
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_GIT_BASH_PATH"}
    env["PATH"] = str(fake)
    result = collect(data_dir, root, env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert {r["repo_identity"] for r in records(data_dir).values()} == {None}
    assert result.stderr.count("warning:") == 1


def test_concurrent_collectors_leave_valid_records(data_dir, multi):
    root, _ = multi
    args = [sys.executable, str(SCRIPTS / "collect.py"), "collect", "--data-dir", str(data_dir)]
    args += ["--projects-root", str(root), "--force"]
    runs = [subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
    for run in runs:
        run.communicate(timeout=60)
        assert run.returncode in (0, 1)
    stored = records(data_dir)
    assert set(stored) == {"sess-a1", "sess-a2", "sess-b1"}
    assert {r["schema"] for r in stored.values()} == {"session-record/v1"}


def test_unusable_data_dir_and_missing_projects_root_exit_2(tmp_path, multi):
    root, _ = multi
    not_a_dir = tmp_path / "file"
    not_a_dir.write_text("x", encoding="utf-8")
    result = collect(not_a_dir, root)
    assert (result.returncode, envelope(result)["status"]) == (2, "error")
    result = collect(tmp_path / "data", tmp_path / "missing")
    assert (result.returncode, envelope(result)["status"]) == (2, "error")


@pytest.mark.skipif(sys.platform == "win32" or os.geteuid() == 0, reason="needs POSIX permissions that bind")
def test_unreadable_projects_root_exits_2(data_dir, multi):
    root, _ = multi
    root.chmod(0)
    try:
        result = collect(data_dir, root)
    finally:
        root.chmod(0o755)
    assert (result.returncode, envelope(result)["status"]) == (2, "error")


def test_titles_and_paths_outside_cwd_are_redacted(data_dir, multi):
    root, _ = multi
    email = "".join(("dev.person", "@", "example", ".com"))
    outside = "/".join(("", "home", "someone", "notes.md"))
    path = root / "proj-a" / "sess-a2.jsonl"
    append_record(path, {"type": "custom-title", "customTitle": f"ask {email}"})
    append_record(
        path,
        {"type": "assistant", "uuid": "b-a9", "timestamp": "2026-09-21T09:03:00Z",
         "message": {"id": "msg_z", "model": "claude-sonnet-5-5",
                     "content": [{"type": "tool_use", "id": "toolu_z", "name": "Write", "input": {"file_path": outside}}]}},
    )
    assert collect(data_dir, root).returncode == 0
    rec = records(data_dir)["sess-a2"]
    assert rec["link_keys"]["custom_title"] == "ask <email>"
    assert rec["edits"]["by_relpath"] == {"~/notes.md": 1}


# resolve_bash mirrors hooks/exec-bash.mjs; the filesystem is injected, as the JS tests do.
WIN_ENV = {"ProgramFiles": "C:\\Program Files", "PATH": "C:\\Windows\\System32;\"D:\\tools\";C:\\Program Files\\WindowsApps"}


@pytest.mark.parametrize(
    ("env", "platform", "present", "expected"),
    [
        ({**WIN_ENV, "CLAUDE_CODE_GIT_BASH_PATH": "E:\\git\\bin\\bash.exe"}, "win32",
         {"E:\\git\\bin\\bash.exe", "C:\\Program Files\\Git\\bin\\bash.exe"}, "E:\\git\\bin\\bash.exe"),
        ({**WIN_ENV, "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Windows\\System32\\bash.exe"}, "win32",
         {"C:\\Windows\\System32\\bash.exe", "C:\\Program Files\\Git\\usr\\bin\\bash.exe"},
         "C:\\Program Files\\Git\\usr\\bin\\bash.exe"),
        (WIN_ENV, "win32",
         {"C:\\Windows\\System32\\bash.exe", "C:\\Program Files\\WindowsApps\\bash.exe",
          "D:\\tools\\bash.exe"}, "D:\\tools\\bash.exe"),
        (WIN_ENV, "win32", {"C:\\Windows\\System32\\bash.exe"}, None),
        ({"CLAUDE_CODE_GIT_BASH_PATH": "/opt/other/bash", "PATH": "relative:/usr/local/bin"}, "linux",
         {"/opt/other/bash", "/usr/local/bin/bash", "/bin/bash"}, "/usr/local/bin/bash"),
        ({"PATH": "/nowhere"}, "linux", {"/usr/bin/bash"}, "/usr/bin/bash"),
        ({"PATH": "/nowhere"}, "darwin", set(), None),
    ],
    ids=["win-override", "win-override-relay", "win-path-skips-relays", "win-none", "posix-ignores-override",
         "posix-fallback", "posix-none"],
)
def test_resolve_bash_follows_exec_bash_order(env, platform, present, expected):
    import collect as collect_module

    assert collect_module.resolve_bash(env, platform, exists=present.__contains__) == expected
