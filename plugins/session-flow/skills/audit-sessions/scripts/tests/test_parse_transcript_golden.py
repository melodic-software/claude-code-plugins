# test-scope: plugins/session-flow/skills/audit-sessions/scripts/tests/fixtures/golden/*
"""Golden-output seam for retro's parse_transcript.py on the shared transcript reader.

`fixtures/golden/expected/*.json` hold the parser's output over `fixtures/golden/proj/` captured
before it moved onto transcript_reader. Every field, exit code and CLI form must still match,
except the #5818 values: tokens counted once per message and `human_messages` counting only typed
turns. Those are hand-computed below from `gold-0001.jsonl` and `gold-0002.jsonl`. Full-output
equality also pins `data.plugin_usage`, which counts the typed `/session-flow:retro` command (an
injected record, not a typed turn) beside the model's Skill call.
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys

import pytest
from conftest import FIXTURES, SCRIPTS

PARSER = SCRIPTS.parents[1] / "retro" / "scripts" / "parse_transcript.py"
GOLDEN = FIXTURES / "golden"
CASES = sorted(p.stem for p in (GOLDEN / "expected").glob("*.json"))

# gold-0001: msg_01 streams three records (input 10, output 5/30/60, cache 100 + 1000 each; the
# last wins) and msg_02 one (4, 8, 0 + 2000). Typed turns: "Please fix the login bug" and "Looks
# good, carry on"; the command, task notification, peer message, interrupt and meta caveat are not.
# gold-0002: msg_10 streams two records (3, 2/9, 0 + 50); one typed turn.
DEDUPED = {
    "gold-0001": {"human_messages": 2, "tokens": (14, 68, 100, 3000)},
    "gold-0002": {"human_messages": 1, "tokens": (3, 9, 0, 50)},
}


def _apply_dedup(data: dict) -> int:
    """Rewrite one session's `data` block to the deduped values; return its old human count."""
    fixed = DEDUPED[data["session"]["id"]]
    total_input, total_output, creation, read = fixed["tokens"]
    data["tokens"] = {
        "total_input": total_input,
        "total_output": total_output,
        "cache_creation": creation,
        "cache_read": read,
        "total_context": total_input + creation + read,
    }
    old = data["turns"]["human_messages"]
    data["turns"]["human_messages"] = fixed["human_messages"]
    return old


def expected_output(golden: dict) -> dict:
    out = copy.deepcopy(golden)
    if "sessions" in out:
        present = [s["data"] for s in out["sessions"] if "data" in s]
        old_human = sum(_apply_dedup(d) for d in present)
        aggregate = out["aggregate"]
        aggregate["total_human_messages"] = sum(d["turns"]["human_messages"] for d in present)
        aggregate["total_input_tokens"] = sum(d["tokens"]["total_input"] for d in present)
        aggregate["total_output_tokens"] = sum(d["tokens"]["total_output"] for d in present)
        new_human = aggregate["total_human_messages"]
    elif out.get("data", {}).get("session"):
        old_human = _apply_dedup(out["data"])
        new_human = out["data"]["turns"]["human_messages"]
    else:
        return out
    out["summary"] = out["summary"].replace(f"{old_human} human messages", f"{new_human} human messages")
    return out


@pytest.mark.parametrize("case", CASES)
def test_parser_matches_golden_except_5818_values(case):
    golden = json.loads((GOLDEN / "expected" / f"{case}.json").read_text(encoding="utf-8"))
    run = subprocess.run(
        [sys.executable, str(PARSER), *golden["argv"]],
        cwd=GOLDEN,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    assert run.returncode == golden["exit"], run.stderr
    assert json.loads(run.stdout) == expected_output(golden["output"])
