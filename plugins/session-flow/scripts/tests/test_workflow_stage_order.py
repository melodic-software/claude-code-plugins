# test-scope: plugins/session-flow/skills/workflow/SKILL.md
"""Tripwire: the workflow skill's stage list and detection list agree with steps.md, interview first."""

from __future__ import annotations

import re
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[2] / "skills" / "workflow"
SKILL = WORKFLOW / "SKILL.md"
STEPS = WORKFLOW / "context" / "steps.md"


def _stage_names() -> dict[int, str]:
    headings = re.findall(r"^## (\d+)\. (\w+)", STEPS.read_text(encoding="utf-8"), re.M)
    return {int(number): name for number, name in headings}


def _section(text: str, heading: str) -> str:
    start = text.index(heading)
    end = text.find("\n### ", start + len(heading))
    return text[start : end if end != -1 else len(text)]


def test_steps_headings_run_in_order_from_interview():
    names = _stage_names()

    assert list(names) == list(range(1, len(names) + 1))
    assert names[1] == "Interview"


def test_at_a_glance_block_matches_steps_and_names_no_contract_stage():
    glance = _section(
        SKILL.read_text(encoding="utf-8"), "### 1. Show the workflow at a glance"
    )
    block = glance.split("```text", 1)[1].split("```", 1)[0]
    listed = {int(n): name for n, name in re.findall(r"(\d+)\. (\w+)", block)}

    assert "Contract" not in block
    assert listed == _stage_names()


def test_detection_list_names_stages_in_steps_order():
    detect = _section(
        SKILL.read_text(encoding="utf-8"), "### 2. Detect current position"
    )
    numbers = [int(n) for n in re.findall(r"→ Stage (\d+)", detect)]

    assert numbers
    assert numbers == sorted(numbers)
    assert numbers[0] == 1
    assert set(numbers) <= set(_stage_names())
