"""Contract tests for reading shape 4 (PLAN.md Phase 6: AC6, AC12, AC14). Expected
values come from the Design's shape-4 table and check rules: binding sections stay
whole, a move or history pointer names a hop file and heading on disk, a binding
overflow FAILs naming the section instead of passing UNVALIDATED, an UNVERIFIED
mark names what settles it, and a missing predecessor still lets the handoff write
and emit."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest
from shape4_chain import (
    SHAPE4_SECTIONS,
    SIDS,
    move,
    pointer,
    s4_chain,
    split_sections,
    to_shape4,
)
from test_save_point import (
    FILL_RE,
    HOP1,
    SHAPE3_VALUES,
    _save_point_module,
    edit,
    err,
    hop_file,
    make_repo,
    model_fill,
    new_args,
    out,
    run,
    s3_hop,
    shape3_fill,
)

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import handoff_chain as hc  # noqa: E402


def validate(path: Path):
    return run("validate", str(path))


def fails(result) -> list[str]:
    return [line for line in out(result).splitlines() if line.startswith("FAIL: ")]


def test_the_shape4_table_is_the_plans():
    spec = hc.SHAPES[4]
    assert list(spec.names) == SHAPE4_SECTIONS
    assert list(spec.binding) == SHAPE4_SECTIONS[:12]
    assert list(spec.movable) == [
        "Direction changes",
        "Observations",
        "Suggested skills",
    ]
    assert list(spec.carried) == ["Prior sessions", "Resume prompt"]
    assert spec.cap_bytes == 24_600


def test_shape4_ids_and_retire_headings_match_shape3():
    assert hc.SHAPES[4].id_specs == hc.SHAPES[3].id_specs
    assert hc.SHAPES[4].retired_entry_sections == hc.SHAPES[3].retired_entry_sections


def test_shape4_validates_while_handoff_shape_is_3(tmp_path):
    assert _save_point_module().HANDOFF_SHAPE == 3
    paths = s4_chain(make_repo(tmp_path), tmp_path, 3)
    for path in paths:
        result = validate(path)
        assert result.returncode == 0, out(result)
        assert "UNSUPPORTED" not in out(result)


def test_every_movable_section_moved_validates_hops_1_to_5(tmp_path):
    movable = ("Direction changes", "Observations", "Suggested skills")
    paths = s4_chain(make_repo(tmp_path), tmp_path, 5, moves=movable)
    for k, path in enumerate(paths, 1):
        result = validate(path)
        assert result.returncode == 0, f"hop {k}: {out(result)}"


def test_a_3_to_4_transition_validates(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 3, shape3_hops=2)
    assert "handoff_shape: 3" in paths[1].read_text(encoding="utf-8")
    result = validate(paths[2])
    assert result.returncode == 0, out(result)


def test_a_2_to_4_transition_validates(tmp_path):
    repo = make_repo(tmp_path)
    made = run(*new_args(repo, tmp_path, "--no-previous", shape="2"))
    assert made.returncode == 0, err(made)
    hop1 = Path(out(made).strip())
    hop1.write_text(model_fill(hop1.read_text(encoding="utf-8")), encoding="utf-8")
    assert validate(hop1).returncode == 0, out(validate(hop1))
    hop2 = s3_hop(repo, tmp_path, hop1, sid=SIDS[1], now="2026-09-02T10:00:00Z")
    to_shape4(hop2)
    result = validate(hop2)
    assert result.returncode == 0, out(result)


def test_a_moved_section_whose_heading_is_gone_fails_as_a_pointer(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 2)
    own = hop_file(paths[0].parent, HOP1, 2, SIDS[1])
    edit(own, "## Observations (h2)", "## Notes (h2)")
    result = validate(paths[1])
    assert result.returncode == 1, out(result)
    assert any("Observations (h2)" in f and "not on disk" in f for f in fails(result))


def test_a_history_pointer_to_a_missing_hop_file_fails(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 2)
    ghost = f"archive/{HOP1[:-3]}/h9-99999999.md#Observations"
    edit(
        paths[1],
        "## Review before you continue\n\n",
        f"## Review before you continue\n\n- Earlier findings: {ghost}\n",
    )
    result = validate(paths[1])
    assert result.returncode == 1, out(result)
    assert any("h9-99999999.md" in f and "not on disk" in f for f in fails(result))


def test_a_binding_section_never_moves(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 2, moves=())
    move(paths[1], HOP1, 2, SIDS[1], "Decisions in force")
    result = validate(paths[1])
    assert result.returncode == 1, out(result)
    assert any(
        f.startswith("FAIL: Decisions in force: a binding section stays whole")
        for f in fails(result)
    ), out(result)


def over_cap_binding(tmp_path: Path) -> Path:
    """A shape-4 hop 1 whose Decisions in force alone passes the cap."""
    paths = s4_chain(make_repo(tmp_path), tmp_path, 1, moves=())
    head, bodies = split_sections(paths[0].read_text(encoding="utf-8"))
    big = "\n".join(f"- [D{n}] Keep decision {n} " + "x" * 80 for n in range(2, 300))
    bodies["Decisions in force"] = (
        bodies["Decisions in force"].rstrip("\n") + "\n" + big + "\n"
    )
    paths[0].write_text(
        head + "".join(f"\n## {t}\n{b}" for t, b in bodies.items()),
        encoding="utf-8",
        newline="\n",
    )
    return paths[0]


def test_binding_content_over_the_cap_fails_naming_the_section(tmp_path):
    paths = [over_cap_binding(tmp_path)]
    result = validate(paths[0])
    assert result.returncode == 1, out(result)
    assert any(
        f.startswith("FAIL: OVER-CAP: Decisions in force holds ") for f in fails(result)
    ), out(result)
    assert "UNVALIDATED" not in out(result)


def test_movable_content_over_the_cap_fails_as_size(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 1, moves=())
    head, bodies = split_sections(paths[0].read_text(encoding="utf-8"))
    big = "\n".join(f"- Observation {n} " + "y" * 80 for n in range(300))
    bodies["Observations"] = big + "\n"
    paths[0].write_text(
        head + "".join(f"\n## {t}\n{b}" for t, b in bodies.items()),
        encoding="utf-8",
        newline="\n",
    )
    result = validate(paths[0])
    assert result.returncode == 1, out(result)
    flagged = fails(result)
    assert any(f.startswith("FAIL: size: ") and "Observations" in f for f in flagged)
    assert not any("OVER-CAP" in f for f in flagged)


UNSETTLED = "- UNVERIFIED: the cache still holds stale rows."
SETTLED = UNSETTLED + " (settle: sqlite3 cache.db 'select count(*) from rows')"


@pytest.mark.parametrize("shape4", [True, False], ids=["shape-4", "shape-3"])
def test_an_unverified_mark_must_name_what_settles_it(tmp_path, shape4):
    repo = make_repo(tmp_path)
    if shape4:
        hot = s4_chain(repo, tmp_path, 1, moves=())[0]
    else:
        hot = s3_hop(repo, tmp_path)
    edit(hot, "## Observations\n\n", f"## Observations\n\n{UNSETTLED}\n")
    result = validate(hot)
    assert result.returncode == 1, out(result)
    assert any("UNVERIFIED" in f and "(settle:" in f for f in fails(result))
    edit(hot, UNSETTLED, SETTLED)
    assert validate(hot).returncode == 0, out(validate(hot))


def test_a_file_stamped_below_3_keeps_its_verdict_on_an_unsettled_mark(tmp_path):
    hot = s3_hop(make_repo(tmp_path), tmp_path)
    edit(hot, "## Observations\n\n", f"## Observations\n\n{UNSETTLED}\n")
    edit(hot, "checks: 3\n", "checks: 2\n")
    assert validate(hot).returncode == 0, out(validate(hot))


def test_new_refuses_to_continue_a_shape4_chain_as_shape3(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s4_chain(repo, tmp_path, 1)[0]
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SIDS[1],
            now="2026-09-02T10:00:00Z",
            shape=None,
        )
    )
    assert made.returncode == 1, out(made)
    assert "never continued as shape 3" in err(made)
    assert len(list(hop1.parent.glob("*-handoff-*.md"))) == 1


@pytest.mark.parametrize("shape", ["3", "2"])
@pytest.mark.parametrize("status", ["missing", "unreadable"])
def test_new_fill_emit_validate_past_a_lost_predecessor(tmp_path, shape, status):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path) if shape == "3" else None
    if hop1 is None:
        made = run(*new_args(repo, tmp_path, "--no-previous", shape="2"))
        hop1 = Path(out(made).strip())
    if status == "missing":
        hop1.unlink()
    else:
        hop1.write_bytes(b"---\ntype: handoff\n\xff\xfe broken\n")
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SIDS[1],
            now="2026-09-02T10:00:00Z",
            shape=shape,
        )
    )
    assert made.returncode == 0, err(made)
    warned = [line for line in err(made).splitlines() if line.startswith("WARN:")]
    assert len(warned) == 1 and HOP1 in warned[0] and status in warned[0]
    hop2 = Path(out(made).strip())
    text = hop2.read_text(encoding="utf-8")
    assert f"previous_handoff: {HOP1}\n" in text
    assert f"previous_status: {status}\n" in text
    filled = shape3_fill(text) if shape == "3" else model_fill(text)
    hop2.write_text(filled, encoding="utf-8", newline="\n")
    emitted = run("emit", str(hop2))
    assert emitted.returncode == 0, err(emitted)
    assert f"Read @{Path(hop2).resolve().as_posix()}" in out(emitted)
    checked = validate(hop2)
    assert checked.returncode == 0, out(checked)
    assert any(
        line.startswith("WARN: ") and HOP1 in line and status in line
        for line in out(checked).splitlines()
    ), out(checked)


def test_fill_proceeds_past_a_lost_predecessor(tmp_path):
    repo = make_repo(tmp_path)
    hop1 = s3_hop(repo, tmp_path)
    hop1.unlink()
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(hop1),
            sid=SIDS[1],
            now="2026-09-02T10:00:00Z",
            shape="3",
        )
    )
    hop2 = Path(out(made).strip())
    names = set(FILL_RE.findall(hop2.read_text(encoding="utf-8")))
    payload = {
        name: SHAPE3_VALUES[name]
        for name, instruction in names
        if not instruction.startswith("optional:")
    }
    slots = tmp_path / "slots.json"
    slots.write_text(json.dumps(payload), encoding="utf-8")
    filled = run("fill", str(hop2), "--slots", str(slots))
    assert filled.returncode == 0, err(filled)
    assert validate(hop2).returncode == 0, out(validate(hop2))
    assert run("emit", str(hop2)).returncode == 0


def test_read_prints_a_moved_section_from_its_hop_file(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 2)
    result = run("read", str(paths[1]), "--section", "Observations")
    assert result.returncode == 0, err(result)
    assert out(result) == "- Hop 2 observation: the run took 2 minutes.\n"
    kept = run("read", str(paths[1]), "--section", "Current rules")
    assert kept.returncode == 0 and "[R1]" in out(kept)


def test_read_names_an_absent_section_and_an_unreachable_move(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 2)
    absent = run("read", str(paths[1]), "--section", "Constraints that must hold")
    assert absent.returncode == 1 and "no '## Constraints" in err(absent)
    hop_file(paths[0].parent, HOP1, 2, SIDS[1]).unlink()
    gone = run("read", str(paths[1]), "--section", "Observations")
    assert gone.returncode == 1 and "not on disk" in err(gone)


def test_read_and_chain_refuse_a_newer_shape(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 1)
    edit(paths[0], "handoff_shape: 4\n", "handoff_shape: 5\n")
    for args in (
        ("read", str(paths[0]), "--section", "Current rules"),
        ("chain", str(paths[0])),
    ):
        result = run(*args)
        assert result.returncode == 3, err(result)


def test_chain_json_lists_every_link_and_hop(tmp_path):
    paths = s4_chain(make_repo(tmp_path), tmp_path, 3)
    result = run("chain", str(paths[2]), "--json")
    assert result.returncode == 0, err(result)
    report = json.loads(out(result))
    assert [link["hop"] for link in report["links"]] == [3, 2, 1]
    assert all(link["status"] == "ok" for link in report["links"])
    assert report["session_ids"] == [SIDS[2], SIDS[1], SIDS[0]]
    hop2 = next(h for h in report["hops"] if h["hop"] == 2)
    assert hop2["sections"]["Observations"] == [
        "- Hop 2 observation: the run took 2 minutes."
    ]


def test_emit_prints_a_shape4_prompt_over_the_cap_with_its_over_cap_notice(tmp_path):
    hot = over_cap_binding(tmp_path)
    result = run("emit", str(hot))
    assert result.returncode == 0, err(result)
    assert re.search(r"^Read @.*\.md, ", out(result), re.M)
    notice = [
        line for line in err(result).splitlines() if line.startswith("OVER-CAP: ")
    ]
    assert len(notice) == 1 and "Decisions in force holds" in notice[0], err(result)
    assert "the prompt is emitted" in notice[0]


def test_the_moved_pointer_form_is_the_design_form():
    line = pointer(HOP1, 4, SIDS[3], "Observations")
    parsed = hc.MovePointer.parse(line)
    assert parsed == hc.MovePointer(
        f"archive/{HOP1[:-3]}/h4-{SIDS[3][:8]}.md", "Observations (h4)"
    )
    assert parsed.moves("Observations") and not parsed.moves("Observation")
