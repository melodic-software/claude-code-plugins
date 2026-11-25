# test-scope: plugins/session-flow/scripts/tests/fixtures/* plugins/session-flow/scripts/dialect.py plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/handoff_fit.py plugins/session-flow/scripts/io_streams.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/scripts/save_point.py plugins/session-flow/reference/resume.md
"""The resume procedure and the recurring entries a handoff carries for it.

Expected values come from the design's Q47 and Q48 (one `[loop]`, `[cron]`, `[monitor]` or
`[off-thread]` entry per item under Environment to re-establish; a redacted command or prompt ends
with `restore: manual`), from the plan's Phase 7 (resume.md under 8,000 characters; the per-kind
fallback re-lists and prints only what is still missing, decision D6), and from Q47's fallback
directive clause for a session the prompt hook does not reach.
"""

from __future__ import annotations

from pathlib import Path

from test_save_point import make_repo, out
from test_save_point_shape4_writer import validate
from test_save_point_shape5_reminders import fails, hop5

RESUME_MD = Path(__file__).resolve().parents[2] / "reference" / "resume.md"
RESUME_MD_LIMIT = 8000
LOOP = "- [loop] every 10m · since 2026-11-24T10:00:00Z · prompt (1 lines):\n  check the deploy and report"
REDACTED_MONITOR = "- [monitor] deploy log · since 2026-11-24T10:00:00Z · command: `tail -f log --token <REDACTED:token>`"


def env_values(*entries: str) -> dict[str, str]:
    return {"environment": "\n".join(["Branch feat/x; no services.", *entries])}


def test_resume_md_size():
    size = len(RESUME_MD.read_text(encoding="utf-8"))
    assert size < RESUME_MD_LIMIT, (
        f"resume.md is {size} characters, the limit is {RESUME_MD_LIMIT}"
    )


def test_partial_rearm_relists():
    text = RESUME_MD.read_text(encoding="utf-8")
    fallback = text.split("## When a re-arm cannot run", 1)[1].split("\n## ", 1)[0]
    assert "list again" in fallback, (
        "after a failed or partial re-arm the kind is listed again"
    )
    assert "still missing" in fallback, "only what is still missing is printed"


def test_recurring_entries_validate(tmp_path):
    path = hop5(
        make_repo(tmp_path),
        tmp_path,
        values=env_values(LOOP, "- Off-thread work: none recorded."),
    )
    result = validate(path)
    assert result.returncode == 0, out(result)


def test_redacted_entry_requires_restore_manual(tmp_path):
    path = hop5(make_repo(tmp_path), tmp_path, values=env_values(REDACTED_MONITOR))
    result = validate(path)
    assert result.returncode == 1, out(result)
    assert any("restore: manual" in line for line in fails(result)), out(result)
    fixed = (
        REDACTED_MONITOR
        + " · restore: manual (held a secret; re-create from the deploy runbook)"
    )
    ok = hop5(make_repo(tmp_path / "ok"), tmp_path / "ok", values=env_values(fixed))
    assert validate(ok).returncode == 0, out(validate(ok))


def test_redacted_loop_prompt_line_requires_restore_manual(tmp_path):
    loop = "- [loop] every 10m · since 2026-11-24T10:00:00Z · prompt (1 lines):\n  call the API with <REDACTED:key>"
    path = hop5(make_repo(tmp_path), tmp_path, values=env_values(loop))
    assert any("restore: manual" in line for line in fails(validate(path)))


def test_indented_line_outside_a_recurring_entry_is_not_checked(tmp_path):
    block = "- TaskList: recreate with\n  TaskCreate(subject='token <REDACTED:token> rotation')"
    path = hop5(make_repo(tmp_path), tmp_path, values=env_values(LOOP, block))
    assert not any("restore: manual" in line for line in fails(validate(path))), (
        "only a [loop], [cron], [monitor] or [off-thread] entry needs restore: manual"
    )


def test_loop_entry_without_line_count_warns(tmp_path):
    loop = "- [loop] every 10m · since 2026-11-24T10:00:00Z · prompt: check the deploy"
    path = hop5(make_repo(tmp_path), tmp_path, values=env_values(loop))
    result = validate(path)
    assert result.returncode == 0, out(result)
    assert any(
        line.startswith("WARN: ") and "[loop]" in line
        for line in out(result).splitlines()
    )


def test_directive_carries_the_fallback_clause(tmp_path):
    path = hop5(make_repo(tmp_path), tmp_path)
    directive = next(
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.startswith("Read @")
    )
    assert "raise its due Reminders" in directive, (
        "a session the hook misses still raises reminders"
    )
    assert "re-establish its Environment" in directive
