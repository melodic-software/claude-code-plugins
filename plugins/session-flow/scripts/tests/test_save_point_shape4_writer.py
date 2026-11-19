"""Contract tests for the shape-4 writer, shape-4 `amend` and the slot budgets
(PLAN.md Phase 7: AC3, AC4, AC5, AC6). Expected values come from the Design's
Writer contract and shape-4 table, the 24,600-byte cap (C4), the Read tool's
58,500-byte page cap, and the slot budgets: the 95th percentile of the Resumption
brief (979 bytes) and of a non-empty below-the-rails note (281 bytes) over the
143 shape-3 hot files dated in the 7-day audit window (2026-11-11T18:46Z to
2026-11-18T18:46Z)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from shape4_chain import SHAPE4_SECTIONS, SIDS
from test_save_point import (
    FILL_RE,
    SHAPE3_VALUES,
    err,
    hop_file,
    make_repo,
    model_fill,
    new_args,
    out,
    run,
)

CAP = 24_600
READ_CAP = 58_500
BRIEF_BUDGET = 979
NOTE_BUDGET = 281
CLOSED = "Next: none (closed)"


def new(
    repo: Path, tmp_path: Path, previous: Path | None, *, k: int, shape: str | None
):
    flag = ["--previous", str(previous)] if previous else ["--no-previous"]
    return run(
        *new_args(
            repo,
            tmp_path,
            *flag,
            sid=SIDS[k - 1],
            now=f"2026-09-0{k}T10:00:00Z",
            shape=shape,
        )
    )


def fill(path: Path, tmp_path: Path, values: dict[str, str] | None = None):
    names = set(FILL_RE.findall(path.read_text(encoding="utf-8")))
    held = {name for name, _ in names}
    merged = {**SHAPE3_VALUES, **(values or {})}
    slots = tmp_path / f"{path.stem}.slots.json"
    slots.write_text(
        json.dumps({k: v for k, v in merged.items() if k in held}), encoding="utf-8"
    )
    return run("fill", str(path), "--slots", str(slots))


def hop(
    repo: Path,
    tmp_path: Path,
    previous: Path | None = None,
    *,
    k: int = 1,
    shape: str | None = "4",
    values: dict[str, str] | None = None,
) -> Path:
    made = new(repo, tmp_path, previous, k=k, shape=shape)
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    filled = fill(path, tmp_path, values)
    assert filled.returncode == 0, err(filled) + out(filled)
    return path


def headings(path: Path) -> list[str]:
    return [
        line[3:]
        for line in path.read_text(encoding="utf-8").split("\n")
        if line.startswith("## ")
    ]


def body(path: Path, title: str) -> str:
    text = path.read_text(encoding="utf-8")
    chunk = text.split(f"\n## {title}\n", 1)[1]
    return chunk.split("\n## ", 1)[0].strip("\n")


def validate(path: Path):
    return run("validate", str(path))


def rules(total: int) -> str:
    lines, size, n = [], 0, 1
    while size < total:
        line = f"- [R{n}] Rule {n} holds for every hop of this chain, verbatim as the owner gave it."
        lines.append(line)
        size += len(line) + 1
        n += 1
    return "\n".join(lines)


def prose(label: str, total: int) -> str:
    unit = f"- {label}: the build took four minutes and the cache missed twice."
    return "\n".join([unit] * (total // (len(unit) + 1) + 1))


def test_shape4_new_writes_the_shape4_order_and_prints_the_budget(tmp_path):
    made = new(make_repo(tmp_path), tmp_path, None, k=1, shape="4")
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    assert out(made).strip().endswith(".md")
    assert "handoff_shape: 4\n" in path.read_text(encoding="utf-8")
    assert headings(path) == SHAPE4_SECTIONS
    budget = err(made)
    assert "budget:" in budget
    assert f"{CAP}-byte cap" in budget
    assert f"brief {BRIEF_BUDGET} bytes" in budget
    assert f"below-rail {NOTE_BUDGET} bytes" in budget


def test_shape4_fill_writes_validates_and_prints_the_verdict_and_prompt(tmp_path):
    repo = make_repo(tmp_path)
    made = new(repo, tmp_path, None, k=1, shape="4")
    path = Path(out(made).strip())
    filled = fill(path, tmp_path)
    assert filled.returncode == 0, err(filled)
    printed = out(filled)
    assert f"validate: PASS {path.as_posix()}" in printed or "validate: WARN" in printed
    assert f"Read @{path.resolve().as_posix()}" in printed
    assert validate(path).returncode == 0, out(validate(path))


def test_shape4_bare_new_previous_continues_a_shape4_chain_while_default_is_3(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path)
    second = hop(repo, tmp_path, first, k=2, shape=None)
    assert "handoff_shape: 4\n" in second.read_text(encoding="utf-8")
    assert headings(second) == SHAPE4_SECTIONS
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_shape4_bare_new_on_a_fresh_chain_still_writes_shape3(tmp_path):
    made = new(make_repo(tmp_path), tmp_path, None, k=1, shape=None)
    assert "handoff_shape: 3\n" in Path(out(made).strip()).read_text(encoding="utf-8")


@pytest.mark.parametrize("pred_shape", ["2", "3"])
def test_shape4_new_carries_an_older_chain_forward(tmp_path, pred_shape):
    repo = make_repo(tmp_path)
    if pred_shape == "3":
        first = hop(repo, tmp_path, shape="3")
    else:
        made = new(repo, tmp_path, None, k=1, shape="2")
        first = Path(out(made).strip())
        first.write_text(
            model_fill(first.read_text(encoding="utf-8")), encoding="utf-8"
        )
    second = hop(repo, tmp_path, first, k=2, shape="4")
    assert headings(second) == SHAPE4_SECTIONS
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_shape4_fit_moves_observations_first_and_keeps_skills(tmp_path):
    repo = make_repo(tmp_path)
    notes = prose("observation", 14_000)
    skills = prose("skill", 9_000)
    path = hop(repo, tmp_path, values={"observations": notes, "skills": skills})
    size = len(path.read_bytes())
    assert size <= CAP < size + len(notes), size
    root = path.name
    own = hop_file(path.parent, root, 1, SIDS[0])
    assert body(path, "Observations") == (
        f"- Moved: archive/{root[:-3]}/h1-{SIDS[0][:8]}.md#Observations (h1)"
    )
    assert body(own, "Observations (h1)") == notes
    assert body(path, "Suggested skills") == skills
    result = validate(path)
    assert result.returncode == 0, out(result)
    read = run("read", str(path), "--section", "Observations")
    assert out(read).strip("\n") == notes


def test_shape4_fit_moves_every_movable_section_in_order_until_under_the_cap(tmp_path):
    repo = make_repo(tmp_path)
    values = {
        "observations": prose("observation", 9_000),
        "skills": prose("skill", 9_000),
        "trail": "\n".join(
            f"- [h1] turn {n}: narrowed the scope again (agent-initiated)"
            for n in range(400)
        ),
    }
    path = hop(repo, tmp_path, values=values)
    assert len(path.read_bytes()) <= CAP
    for title in ("Observations", "Suggested skills", "Direction changes"):
        assert body(path, title).startswith("- Moved: archive/"), title
    result = validate(path)
    assert result.returncode == 0, out(result)


def test_shape4_fill_over_cap_binding_writes_and_prints_one_over_cap_line(tmp_path):
    repo = make_repo(tmp_path)
    made = new(repo, tmp_path, None, k=1, shape="4")
    path = Path(out(made).strip())
    filled = fill(
        path, tmp_path, {"rules": rules(30_000), "observations": prose("o", 2_000)}
    )
    assert filled.returncode == 0, err(filled)
    over = [line for line in out(filled).splitlines() if "OVER-CAP: " in line]
    assert len(over) == 1, out(filled)
    assert "OVER-CAP: Current rules holds" in over[0]
    assert "shrink Current rules" in over[0]
    assert "<!-- FILL" not in path.read_text(encoding="utf-8")
    assert body(path, "Observations").startswith("- Moved: archive/")
    assert run("emit", str(path)).returncode == 0


def test_shape4_over_the_read_cap_directs_a_paged_read(tmp_path):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path, values={"rules": rules(READ_CAP + 2_000)})
    assert len(path.read_bytes()) > READ_CAP
    prompt = body(path, "Resume prompt")
    directive = next(line for line in prompt.splitlines() if line.startswith("Read @"))
    assert "offset and limit" in directive
    result = validate(path)
    warns = [line for line in out(result).splitlines() if line.startswith("WARN: ")]
    assert any(f"{READ_CAP}-byte Read page cap" in line for line in warns), out(result)
    assert not any(
        "Read @" in line
        for line in out(result).splitlines()
        if line.startswith("FAIL: ")
    )


def test_shape4_under_the_read_cap_keeps_the_plain_read_directive(tmp_path):
    path = hop(make_repo(tmp_path), tmp_path)
    prompt = body(path, "Resume prompt")
    assert "offset and limit" not in prompt


@pytest.mark.parametrize("shape", ["3", "4"])
def test_shape4_two_call_slot_path_refuses_once_then_writes_with_a_slot_fail(
    tmp_path, shape
):
    repo = make_repo(tmp_path)
    made = new(repo, tmp_path, None, k=1, shape=shape)
    path = Path(out(made).strip())
    skeleton = path.read_bytes()
    first = fill(path, tmp_path, {"brief": "b" * 2_000})
    assert first.returncode == 1, out(first)
    assert "'brief'" in err(first)
    assert f"{2_000 - BRIEF_BUDGET} bytes over" in err(first)
    assert path.read_bytes() == skeleton
    second = fill(path, tmp_path, {"brief": "b" * 1_500})
    assert second.returncode == 0, err(second)
    assert "<!-- FILL" not in path.read_text(encoding="utf-8")
    result = validate(path)
    assert result.returncode == 1
    slot = [line for line in out(result).splitlines() if "slot_size:" in line]
    assert len(slot) == 1 and slot[0].startswith("FAIL: "), out(result)
    assert "Resumption brief" in slot[0]
    assert f"{1_500 - BRIEF_BUDGET} bytes over" in slot[0]
    assert not list(path.parent.glob(".*over-budget*"))


@pytest.mark.parametrize("shape", ["3", "4"])
def test_shape4_rewritten_slot_within_budget_passes_on_the_second_call(tmp_path, shape):
    repo = make_repo(tmp_path)
    made = new(repo, tmp_path, None, k=1, shape=shape)
    path = Path(out(made).strip())
    assert fill(path, tmp_path, {"brief": "b" * 2_000}).returncode == 1
    second = fill(path, tmp_path, {"brief": "b" * BRIEF_BUDGET})
    assert second.returncode == 0, err(second)
    result = validate(path)
    assert result.returncode == 0, out(result)


def test_shape4_below_rail_note_over_its_budget_fails_naming_the_note(tmp_path):
    repo = make_repo(tmp_path)
    made = new(repo, tmp_path, None, k=1, shape="4")
    path = Path(out(made).strip())
    note = "n" * 400
    assert fill(path, tmp_path, {"below-rail": note}).returncode == 1
    assert fill(path, tmp_path, {"below-rail": note}).returncode == 0
    slot = [line for line in out(validate(path)).splitlines() if "slot_size:" in line]
    assert len(slot) == 1 and "below-the-rails note" in slot[0], slot
    assert f"{400 - NOTE_BUDGET} bytes over" in slot[0]


def test_shape3_oversized_brief_fails_naming_the_slot_never_unvalidated(tmp_path):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path, shape="3")
    text = path.read_text(encoding="utf-8")
    brief = body(path, "Resumption brief")
    path.write_text(text.replace(brief, "x" * 29_000, 1), encoding="utf-8")
    result = validate(path)
    printed = out(result)
    assert result.returncode == 1
    assert "UNVALIDATED" not in printed
    assert printed.splitlines()[-1].startswith("validate: FAIL")
    assert any(
        line.startswith("FAIL: slot_size: Resumption brief")
        for line in printed.splitlines()
    ), printed


def test_shape3_file_stamped_below_3_keeps_its_verdict_on_an_oversized_brief(tmp_path):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path, shape="3")
    text = path.read_text(encoding="utf-8").replace("checks: 3\n", "checks: 2\n", 1)
    brief = body(path, "Resumption brief")
    path.write_text(text.replace(brief, "x" * 2_000, 1), encoding="utf-8")
    assert "slot_size" not in out(validate(path))


@pytest.mark.parametrize("shape", ["3", "4"])
def test_amend_growing_the_brief_past_its_budget_still_writes(tmp_path, shape):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path, shape=shape)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"sections": {"Resumption brief": "y" * 2_000}}), encoding="utf-8"
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result) + out(result)
    assert body(path, "Resumption brief") == "y" * 2_000
    assert any(
        line.startswith("FAIL: slot_size: Resumption brief")
        for line in out(result).splitlines()
    ), out(result)


def test_shape4_amend_folds_a_late_event_and_keeps_the_shape(tmp_path):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"next": ["Run the late check first"]}), encoding="utf-8"
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    assert "Run the late check first" in body(path, "Resume prompt")
    assert headings(path) == SHAPE4_SECTIONS
    own = hop_file(path.parent, path.name, 1, SIDS[0])
    assert "## Amended 2026-09-01T11:00:00Z Resume prompt Next:" in own.read_text(
        encoding="utf-8"
    )
    assert validate(path).returncode == 0, out(validate(path))


def test_shape4_amend_retires_a_rule_into_the_hop_file(tmp_path):
    repo = make_repo(tmp_path)
    path = hop(repo, tmp_path)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"retire": [{"ref": "[R2]", "reason": "moved to AGENTS.md"}]}),
        encoding="utf-8",
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    assert "[R2]" not in body(path, "Current rules")
    own = hop_file(path.parent, path.name, 1, SIDS[0])
    assert "- [R2] Never push to main." in own.read_text(encoding="utf-8")


def closed_chain(tmp_path: Path, shape: str) -> list[Path]:
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path, shape=shape)
    second = hop(repo, tmp_path, first, k=2, shape=shape, values={"next": CLOSED})
    return [first, second]


@pytest.mark.parametrize("shape", ["3", "4"])
def test_validate_warns_when_a_shrunk_finished_chain_lost_its_predecessor(
    tmp_path, shape
):
    first, second = closed_chain(tmp_path, shape)
    assert validate(second).returncode == 0, out(validate(second))
    first.unlink()
    result = validate(second)
    assert result.returncode == 0, out(result)
    warns = [line for line in out(result).splitlines() if line.startswith("WARN: ")]
    assert any(first.name in line and "h2-" in line for line in warns), out(result)


def test_validate_still_fails_an_open_chain_whose_predecessor_is_gone(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path, shape="3")
    second = hop(repo, tmp_path, first, k=2, shape="3")
    first.unlink()
    result = validate(second)
    assert result.returncode == 1
    assert "not found beside this file" in out(result)


def test_validate_fails_a_closed_file_whose_hop_file_names_another_predecessor(
    tmp_path,
):
    first, second = closed_chain(tmp_path, "3")
    own = hop_file(second.parent, first.name, 2, SIDS[1])
    text = own.read_text(encoding="utf-8")
    own.write_text(
        text.replace(
            f"moved_from: {first.name}", "moved_from: 20260101T000000Z-handoff-other.md"
        ),
        encoding="utf-8",
    )
    first.unlink()
    result = validate(second)
    assert result.returncode == 1
    assert "not found beside this file" in out(result)
