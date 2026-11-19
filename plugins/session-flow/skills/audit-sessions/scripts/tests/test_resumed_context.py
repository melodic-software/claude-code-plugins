"""resumed_context.py: context at the 10th assistant message after a handoff resume, grouped by plugin version."""

from __future__ import annotations

from conftest import envelope, run_cli


def sessions_by_id(env: dict) -> dict[str, dict]:
    return {s["session_id"]: s for s in env["data"]["sessions"]}


def test_tenth_message_after_resume_takes_max_usage_and_skips_sidechain_and_zero(copy_fixture):
    root = copy_fixture("resumed")
    result = run_cli("resumed_context.py", "--projects-root", str(root))
    assert result.returncode == 0, result.stderr
    row = sessions_by_id(envelope(result))["res-0001"]
    assert row["ctx_msg10"] == 111241, f"m5 (zero) and the sidechain skipped, m11's larger record 7 + 1234 + 110000: {row}"
    assert row["plugin_version"] == "9.9.0", row
    assert row["handoff"] == "20261109T200000Z-handoff-topic.md", row


def test_short_resume_has_no_value_and_a_late_resume_is_not_a_resume(copy_fixture):
    env = envelope(run_cli("resumed_context.py", "--projects-root", str(copy_fixture("resumed"))))
    rows = sessions_by_id(env)
    assert rows["res-0002"]["ctx_msg10"] is None, "3 messages after the resume never reach the 10th"
    assert rows["res-0002"]["plugin_version"] == "9.10.0", "the version is read from the first path after the resume"
    assert "fresh-0003" not in rows, "a Read @ directive on the 4th typed turn is not a resume"
    counts = env["data"]["counts"]
    assert (counts["transcripts"], counts["resumed"], counts["reached_10"]) == (5, 4, 3), counts


def test_cwd_prefix_keeps_only_sessions_under_it(copy_fixture):
    env = envelope(run_cli("resumed_context.py", "--projects-root", str(copy_fixture("resumed")), "--cwd-prefix", "/repo"))
    assert "out-0004" not in sessions_by_id(env), "a session in /elsewhere is outside the prefix"
    assert env["data"]["counts"]["in_scope"] == 4, env["data"]["counts"]


def test_groups_by_version_and_compares_two_versions(copy_fixture):
    root = copy_fixture("resumed")
    args = ("--projects-root", str(root), "--cwd-prefix", "/repo", "--baseline", "9.9.0", "--candidate", "9.10.0")
    result = run_cli("resumed_context.py", *args, "--min-per-side", "1")
    assert result.returncode == 0, result.stderr
    data = envelope(result)["data"]
    groups = {g["plugin_version"]: (g["median"], g["n"]) for g in data["groups"]}
    assert groups == {"9.9.0": (111241, 1), "9.10.0": (90010, 1)}, f"res-0001 and res-0005 (90000 + 10); res-0002 short: {groups}"
    assert data["overall"] == {"n": 2, "median": 100625.5}, f"median of 111241 and 90010 over every version: {data['overall']}"
    comparison = data["comparison"]
    assert (comparison["baseline"]["median"], comparison["candidate"]["median"]) == (111241, 90010)
    assert comparison["rise"] is False and comparison["miss_count"] is None, comparison

    short = run_cli("resumed_context.py", *args)
    assert short.returncode == 1, "below the default 10 sessions per side the comparison is a warning"
    assert envelope(short)["data"]["comparison"]["rise"] is None
