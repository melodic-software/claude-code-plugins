"""Unit tests for the friction parsing: transcript_reader's permission helpers and friction_scan's shapes.

Records are synthetic, written from the transcript shapes the reader documents. The end-to-end path
(collect.py writing a record's `friction` block) is covered by the audit-friction suite.
"""

from __future__ import annotations

import friction_scan
import pytest
import transcript_reader


def denial_record(text: str, *, kind: str | None, decision: dict | None, use_id: str = "toolu_1") -> dict:
    record = {
        "type": "user",
        "toolUseResult": text,
        "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": use_id, "is_error": True, "content": text}]},
    }
    if kind is not None:
        record["toolDenialKind"] = kind
    if decision is not None:
        record["permissionDecision"] = decision
    return record


CLASSIFIER_TEXT = (
    "Error: Permission for this action was denied by the Claude Code auto mode classifier. "
    "Reason: [Git Destructive]. If you have other tasks that don't depend on this action, continue."
)


def test_classifier_denial_keeps_the_bracketed_category():
    record = denial_record(
        CLASSIFIER_TEXT, kind="automode-blocked", decision={"decision": "reject", "source": "config", "reasonType": "classifier"}
    )
    event = transcript_reader.permission_event(record)
    assert event == {
        "tool_use_id": "toolu_1",
        "outcome": "denied",
        "source": "config",
        "reason_type": "classifier",
        "denial_kind": "automode-blocked",
        "cause": "classifier",
        "reason": "Git Destructive",
        "hook": None,
    }


def test_classifier_denial_without_a_category_reads_unexplained():
    text = (
        "Error: Permission for this action was denied by the Claude Code auto mode classifier. "
        "Reason: The server-side auto mode classifier judged this action dangerous (it gave no explanation)."
    )
    event = transcript_reader.permission_event(denial_record(text, kind="automode-blocked", decision=None))
    assert (event["cause"], event["reason"]) == ("classifier", "unexplained")


def test_hook_denial_names_the_plugin_and_drops_the_command_line():
    text = (
        "Error: PreToolUse:Bash hook error: [node /opt/hooks/run.mjs guard-a guard-b]: BLOCKED: file write through "
        "the shell. Use the Write tool.\n\nThis hook comes from the shellguard@example-market plugin."
    )
    record = denial_record(text, kind="permission-rule", decision={"decision": "reject", "source": "hook", "reasonType": "hook"})
    event = transcript_reader.permission_event(record)
    assert (event["cause"], event["hook"], event["reason"]) == (
        "hook",
        "shellguard",
        "BLOCKED: file write through the shell. Use the Write tool.",
    )


def test_hook_denial_without_a_plugin_line_takes_the_leading_label():
    text = "Error: PreToolUse:Bash hook error: disk-tidy: denied: the command contains an '&'."
    record = denial_record(text, kind="permission-rule", decision={"decision": "reject", "source": "hook", "reasonType": "hook"})
    event = transcript_reader.permission_event(record)
    assert (event["hook"], event["reason"]) == ("disk-tidy", "disk-tidy: denied: the command contains an '&'.")


def test_hook_denial_with_no_label_is_unattributed():
    text = "Error: PreToolUse:Bash hook error: Blocked: the command sets an arming variable."
    record = denial_record(text, kind="permission-rule", decision={"decision": "reject", "source": "hook", "reasonType": "hook"})
    assert transcript_reader.permission_event(record)["hook"] == "unattributed"


def test_rule_denial_reports_its_reason_type():
    text = "Error: Permission to use Bash with command git branch -D old has been denied."
    record = denial_record(text, kind="permission-rule", decision={"decision": "reject", "source": "config", "reasonType": "rule"})
    event = transcript_reader.permission_event(record)
    assert (event["cause"], event["reason"], event["hook"]) == ("rule", "rule", None)


def test_user_rejection_is_its_own_cause():
    record = denial_record("User rejected tool use", kind="user-rejected", decision=None)
    assert transcript_reader.permission_event(record)["cause"] == "user-rejected"


def test_a_prompt_the_person_approved_is_an_allowed_event():
    record = {
        "type": "user",
        "permissionDecision": {"decision": "accept", "source": "user_temporary"},
        "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_9", "content": "ok"}]},
    }
    assert transcript_reader.permission_event(record) == {
        "tool_use_id": "toolu_9",
        "outcome": "allowed",
        "source": "user_temporary",
        "reason_type": None,
        "denial_kind": None,
    }


def test_a_record_without_a_decision_has_no_event():
    record = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t", "content": "ok"}]}}
    assert transcript_reader.permission_event(record) is None
    assert transcript_reader.permission_event({"type": "assistant", "toolDenialKind": "x"}) is None


def test_tool_result_text_reads_block_text_when_tool_use_result_is_not_a_string():
    record = {
        "type": "user",
        "toolUseResult": {"stdout": "x"},
        "message": {"content": [{"type": "tool_result", "tool_use_id": "t7", "content": [{"type": "text", "text": "line one"}]}]},
    }
    assert transcript_reader.tool_result_id(record) == "t7"
    assert transcript_reader.tool_result_text(record) == "line one"


def test_permission_denials_reads_a_stream_json_result_record():
    record = {
        "type": "result",
        "permission_denials": [
            {"tool_name": "Bash", "tool_use_id": "t1", "tool_input": {"command": "git push --force"}, "decision_reason_type": "rule"},
            {"tool_name": "Write", "tool_use_id": "t2"},
            "not a denial",
        ],
    }
    assert transcript_reader.permission_denials(record) == [
        {"tool_name": "Bash", "tool_use_id": "t1", "tool_input": {"command": "git push --force"}, "reason_type": "rule"},
        {"tool_name": "Write", "tool_use_id": "t2", "tool_input": {}, "reason_type": None},
    ]
    assert transcript_reader.permission_denials({"type": "user", "permission_denials": [{}]}) == []
    assert transcript_reader.record_kind(record) == "result"


@pytest.mark.parametrize(
    ("command", "shape", "flags"),
    [
        ("git push origin main", "git push origin", []),
        ("git -C /w/repo push", "git push", []),
        ("cd /w/repo && npm test", "npm test", ["cd-prefix"]),
        ("FOO=1 BAR=2 make build", "make build", ["env-prefix"]),
        ("gh pr merge 12 --squash", "gh pr merge", []),
        ("python3 tools/run.py --fast", "python3", []),
        ("cat > out.txt <<'EOF'\nx\nEOF", "cat", ["multiline", "heredoc", "redirect"]),
        ("echo $(date) | tee log", "echo", ["substitution", "compound"]),
        ("/usr/bin/rg -n pattern", "rg", []),
        ("", "", []),
    ],
)
def test_command_shape(command, shape, flags):
    assert friction_scan.command_shape(command) == (shape, flags)


def test_tool_shape_flags_claude_config_and_paths_outside_the_working_directory():
    shape, flags, target = friction_scan.tool_shape("Edit", {"file_path": "/srv/u/.claude/settings.json"}, "/w/repo")
    assert (shape, flags, target) == ("Edit .json", ["claude-config", "outside-cwd"], "/srv/u/.claude/settings.json")
    shape, flags, _ = friction_scan.tool_shape("Write", {"file_path": "/w/repo/src/a.py"}, "/w/repo")
    assert (shape, flags) == ("Write .py", [])
    assert friction_scan.tool_shape("WebFetch", {"url": "https://docs.example.com/a/b"}, None) == ("WebFetch docs.example.com", [], None)
    assert friction_scan.tool_shape("Agent", {"subagent_type": "Explore"}, None) == ("Agent Explore", [], None)


def test_event_key_skips_empty_parts():
    assert friction_scan.event_key({"kind": "denied", "cause": "hook", "hook": "g", "reason": "BLOCKED: x"}) == "denied/hook/g/BLOCKED: x"
    assert friction_scan.event_key({"kind": "agent-ask", "reply": "approve"}) == "agent-ask/approve"
