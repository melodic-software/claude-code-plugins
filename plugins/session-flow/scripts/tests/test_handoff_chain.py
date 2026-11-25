from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import handoff_chain as hc  # noqa: E402

ROOT = "20260901T100000Z-handoff-widget.md"
HOP2 = "20260902T100000Z-handoff-widget.md"
HOP3 = "20260903T100000Z-handoff-widget.md"
SID_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
SID_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
SID_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
STANDING_NEW = "standing-rules/20260901T100000Z-handoff-widget.md"
STANDING_LEGACY = "archive/20260901T100000Z-handoff-widget/standing-rules.md"


def hot(
    directory: Path, name: str, sid: str, hop: int, previous: str | None, body: str = ""
) -> Path:
    lines = [
        "---",
        "type: handoff",
        "handoff_shape: 3",
        f"session_id: {sid}",
        *([f"previous_handoff: {previous}"] if previous else []),
        f"chain_root: {ROOT}",
        f"hop: {hop}",
        "---",
        "",
        body,
    ]
    path = directory / name
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def hop_file(directory: Path, hop: int, sid: str, body: str) -> Path:
    path = hc.hop_file_path(directory, ROOT, hop, sid)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"---\ntype: handoff-archive\nhop: {hop}\n---\n{body}", encoding="utf-8"
    )
    return path


@pytest.mark.parametrize(
    "kwargs",
    [{"binding": True, "movable": True}, {"carried": True, "size_class": "brief"}],
    ids=["binding-and-movable", "carried-with-size-class"],
)
def test_section_spec_rejects_a_contradictory_placement(kwargs):
    with pytest.raises(ValueError):
        hc.SectionSpec("Observations", **kwargs)


def test_section_spec_accepts_each_placement_alone():
    assert hc.SectionSpec("Observations", movable=True).movable
    assert hc.SectionSpec("Resume prompt", carried=True).carried


def test_shape_3_id_families_follow_the_floor_order():
    specs = hc.SHAPES[3].id_specs
    assert [(s.prefix, s.floor_key) for s in specs] == [
        ("R", "next_rule_id"),
        ("Q", "next_question_id"),
        ("D", "next_decision_id"),
    ]
    assert specs[0].sections == ("Current rules", "Standing preferences")


def test_move_pointer_parses_the_design_form():
    pointer = hc.MovePointer.parse(
        "- Moved: archive/20260901T100000Z-handoff-widget/h3-abcdef12.md#Remaining actions, in order"
    )
    assert pointer == hc.MovePointer(
        "archive/20260901T100000Z-handoff-widget/h3-abcdef12.md",
        "Remaining actions, in order",
    )


@pytest.mark.parametrize(
    "text",
    [
        "archive/20260901T100000Z-handoff-widget/h3-abcdef12.md",
        "archive/20260901T100000Z-handoff-widget/notes.md#Observations",
        "See the hop file for Observations.",
    ],
    ids=["no-heading", "not-a-hop-file", "prose"],
)
def test_move_pointer_refuses_other_text(text):
    assert hc.MovePointer.parse(text) is None


def test_read_chain_walks_newest_first_and_ends_at_a_missing_link(tmp_path):
    hot(tmp_path, HOP2, SID_B, 2, ROOT)
    newest = hot(tmp_path, HOP3, SID_C, 3, HOP2)
    chain = hc.read_chain(newest)
    assert [(link.path.name, link.status) for link in chain.links] == [
        (HOP3, "ok"),
        (HOP2, "ok"),
        (ROOT, "missing"),
    ]
    assert chain.links[1].frontmatter["session_id"] == SID_B
    assert chain.stop is None


def test_read_chain_stops_on_a_cycle(tmp_path):
    hot(tmp_path, HOP2, SID_B, 2, HOP3)
    newest = hot(tmp_path, HOP3, SID_C, 3, HOP2)
    chain = hc.read_chain(newest)
    assert [link.path.name for link in chain.links] == [HOP3, HOP2]
    assert chain.stop is not None and "cycle" in chain.stop


def test_read_chain_strict_refuses_a_parent_directory_predecessor(tmp_path):
    inner = tmp_path / "handoffs"
    inner.mkdir()
    hot(tmp_path, ROOT, SID_A, 1, None)
    newest = hot(inner, HOP2, SID_B, 2, ROOT)
    assert [link.status for link in hc.read_chain(newest).links] == ["ok", "ok"]
    assert [link.status for link in hc.read_chain(newest, strict=True).links] == [
        "ok",
        "missing",
    ]


def test_read_chain_marks_a_newer_shape_unsupported_and_keeps_walking(tmp_path):
    hot(tmp_path, HOP2, SID_B, 2, None)
    newest = tmp_path / HOP3
    newest.write_text(
        f"---\ntype: handoff\nhandoff_shape: 9\nsession_id: {SID_C}\nprevious_handoff: {HOP2}\n---\n",
        encoding="utf-8",
    )
    links = hc.read_chain(newest).links
    assert [(link.status, link.shape) for link in links] == [
        ("unsupported_shape", 9),
        ("ok", 3),
    ]


def test_link_section_follows_a_move_pointer_to_the_hop_file(tmp_path):
    pointer = f"archive/{ROOT[:-3]}/h2-bbbbbbbb.md#Observations"
    path = hot(
        tmp_path, HOP2, SID_B, 2, None, f"## Observations\n\n- Moved: {pointer}\n"
    )
    hop_file(tmp_path, 2, SID_B, "\n## Observations\n\n- The run takes a minute.\n")
    link = hc.read_chain(path).links[0]
    assert link.section("Observations") == ["", "- The run takes a minute."]


def test_link_section_is_none_when_the_pointed_heading_is_gone(tmp_path):
    pointer = f"archive/{ROOT[:-3]}/h2-bbbbbbbb.md#Observations"
    path = hot(
        tmp_path, HOP2, SID_B, 2, None, f"## Observations\n\n- Moved: {pointer}\n"
    )
    hop_file(tmp_path, 2, SID_B, "\n## Notes\n\n- Something else.\n")
    assert hc.read_chain(path).links[0].section("Observations") is None


def standing_hot(directory: Path, rel: str) -> Path:
    target = directory / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "---\ntype: handoff-standing-rules\n---\n\n## Current rules\n\n- [R1] Ship small.\n",
        encoding="utf-8",
    )
    return hot(
        directory,
        HOP2,
        SID_B,
        2,
        None,
        f"## Current rules\n\n- Standing rules: {rel}#Current rules\n",
    )


def test_standing_rules_new_path_sits_in_a_subfolder_beside_the_handoff_file(
    tmp_path,
):
    assert hc.standing_rel(ROOT) == STANDING_NEW
    path = standing_hot(tmp_path, STANDING_NEW)
    link = hc.read_chain(path).links[0]
    assert link.section("Current rules") == ["", "- [R1] Ship small."]


def test_standing_rules_legacy_path_still_resolves_for_an_existing_chain(tmp_path):
    path = standing_hot(tmp_path, STANDING_LEGACY)
    link = hc.read_chain(path).links[0]
    assert link.section("Current rules") == ["", "- [R1] Ship small."]


def test_retired_ids_read_every_hop_file_with_the_oldest_retirement_winning(tmp_path):
    hot(tmp_path, HOP2, SID_B, 2, None)
    newest = hot(tmp_path, HOP3, SID_C, 3, HOP2)
    hop_file(
        tmp_path,
        2,
        SID_B,
        "\n## Current rules\n\n- [R3] Ship small.\n"
        "\n## Retired rules\n\n- [R2] Never push to main.\nRetired: branch rule now.\n"
        "- [R3] superseded by the review rule\n"
        "\n## Retired decisions\n\n- [D1] Paint first.\nRetired: painted.\n",
    )
    hop_file(
        tmp_path,
        3,
        SID_C,
        "\n## Retired rules\n\n- [R2] Rebase first.\nRetired: gone.\n- [R4] no copy kept\n",
    )
    assert hc.read_chain(newest).retired_ids() == {
        "R": {2: "Never push to main.", 3: "Ship small.", 4: None},
        "Q": {},
        "D": {1: "Paint first."},
    }
