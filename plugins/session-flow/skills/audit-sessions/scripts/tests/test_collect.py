"""Contract tests for collect.py: the CLI envelope and the store records it writes.

Runs the scripts by subprocess, testing the CLI interface, not internals. The tracer test also
drives sweep.py over the store and transcript_reader.py through collect.
"""

from __future__ import annotations

from conftest import envelope, run_cli

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
