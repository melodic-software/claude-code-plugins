# test-scope: plugins/session-flow/scripts/tests/fixtures/* plugins/session-flow/scripts/dialect.py plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/handoff_fit.py plugins/session-flow/scripts/io_streams.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/scripts/save_point.py
"""A role chain's Decisions in force live in its standing-rules file, and its
retire pointers in one retired-entries index beside it. Expected values come
from reference/structure.md ("Role chains: the standing-rules file" and "The
retired-entries index"): the handoff file holds one pointer line for each, a
decision leaves only through `retire`, and no earlier retire pointer is lost."""

from __future__ import annotations

import json
import os
from pathlib import Path

from shape4_chain import SIDS
from test_save_point import (
    FILL_RE,
    SHAPE3_VALUES,
    _save_point_module,
    err,
    hop_file,
    make_repo,
    new_args,
    out,
    run,
)
from test_save_point_shape4_writer import body, standing_file, validate

D1 = "- [D1] The thing over the other thing."
D2 = "- [D2] Ship the small fix first."
INDEX_PREFIX = "- Retired entries index: "


def role_new(
    repo: Path, tmp_path: Path, previous: Path | None, *, k: int, flag: bool
):
    return run(
        *new_args(
            repo,
            tmp_path,
            *(["--previous", str(previous)] if previous else ["--no-previous"]),
            *(["--standing-rules"] if flag else []),
            sid=SIDS[k - 1],
            now=f"2026-09-0{k}T10:00:00Z",
            shape="4",
        )
    )


def slots_for(
    path: Path,
    tmp_path: Path,
    values: dict[str, str] | None = None,
    retire: list[dict[str, str]] | None = None,
) -> Path:
    held = {name for name, _ in FILL_RE.findall(path.read_text(encoding="utf-8"))}
    merged = {**SHAPE3_VALUES, **(values or {})}
    payload: dict[str, object] = {k: v for k, v in merged.items() if k in held}
    if retire:
        payload["retire"] = retire
    slots = tmp_path / f"{path.stem}.slots.json"
    slots.write_text(json.dumps(payload), encoding="utf-8")
    return slots


def role_hop(
    repo: Path,
    tmp_path: Path,
    previous: Path | None = None,
    *,
    k: int = 1,
    flag: bool = True,
    values: dict[str, str] | None = None,
    retire: list[dict[str, str]] | None = None,
) -> Path:
    made = role_new(repo, tmp_path, previous, k=k, flag=flag)
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    slots = slots_for(path, tmp_path, values, retire)
    filled = run("fill", str(path), "--slots", str(slots))
    assert filled.returncode == 0, err(filled) + out(filled)
    return path


def in_process(*argv: str) -> int:
    module = _save_point_module()
    args = module.build_parser().parse_args(list(argv))
    return int(args.func(args))


def fail_replace_onto(monkeypatch, target: Path) -> None:
    """Every `os.replace` onto `target` raises, as a full disk would."""
    real = os.replace

    def replace(src, dst):
        if Path(dst) == target:
            raise OSError("no space left on device")
        return real(src, dst)

    monkeypatch.setattr(os, "replace", replace)


def index_file(path: Path, root: Path | None = None) -> Path:
    return path.parent / "archive" / (root or path).stem / "retired-index.md"


def pointer_lines(text: str) -> list[str]:
    return [line for line in text.split("\n") if line.startswith("- Retired entries: ")]


def fails(result) -> list[str]:
    return [line for line in out(result).splitlines() if line.startswith("FAIL: ")]


def test_decisions_leave_the_hot_file_for_the_standing_file(tmp_path):
    path = role_hop(make_repo(tmp_path), tmp_path)
    rel = f"standing-rules/{path.stem}.md"
    assert body(path, "Decisions in force") == f"- Standing rules: {rel}#Decisions in force"
    assert body(standing_file(path), "Decisions in force") == D1
    result = validate(path)
    assert result.returncode == 0, out(result)
    read = run("read", str(path), "--section", "Decisions in force")
    assert out(read).strip("\n") == D1


def test_decisions_carry_to_the_next_hop_through_the_standing_file(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo, tmp_path, first, k=2, flag=False, values={"decisions-new": D2}
    )
    assert body(second, "Decisions in force").startswith("- Standing rules: standing-rules/")
    held = body(standing_file(second, first), "Decisions in force")
    assert held == f"{D1}\n\n{D2}" or held == f"{D1}\n{D2}", held
    archived = hop_file(second.parent, first.name, 2, SIDS[1]).read_text(
        encoding="utf-8"
    )
    assert D1 in archived
    for path in (first, second):
        result = validate(path)
        assert result.returncode == 0, out(result)


def test_a_dropped_decision_without_a_retire_listing_fails_validation(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo, tmp_path, first, k=2, flag=False, values={"decisions-new": D2}
    )
    standing = standing_file(second, first)
    standing.write_text(
        standing.read_text(encoding="utf-8").replace(D1 + "\n", ""), encoding="utf-8"
    )
    result = validate(second)
    assert result.returncode == 1, out(result)
    assert any("[D1]" in line for line in fails(result)), out(result)


def test_a_retired_decision_lands_in_the_hop_file(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"decisions-new": D2},
        retire=[{"ref": "[D1]", "reason": "superseded by D2"}],
    )
    assert "[D1]" not in body(standing_file(second, first), "Decisions in force")
    own = hop_file(second.parent, first.name, 2, SIDS[1]).read_text(encoding="utf-8")
    retired = own.split("\n## Retired decisions\n", 1)[1]
    assert retired.lstrip("\n").startswith(f"{D1}\nRetired: superseded by D2\n")
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_amend_retires_a_decision_from_the_standing_file(tmp_path):
    path = role_hop(make_repo(tmp_path), tmp_path)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"retire": [{"ref": "[D1]", "reason": "no longer bears"}]}),
        encoding="utf-8",
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    assert "[D1]" not in body(standing_file(path), "Decisions in force")
    assert body(path, "Decisions in force").startswith("- Standing rules: standing-rules/")
    own = hop_file(path.parent, path.name, 1, SIDS[0]).read_text(encoding="utf-8")
    assert f"{D1}\nRetired: no longer bears" in own
    assert pointer_lines(path.read_text(encoding="utf-8")) == []
    assert len(pointer_lines(index_file(path).read_text(encoding="utf-8"))) == 1
    assert validate(path).returncode == 0, out(validate(path))


def test_a_role_chain_written_before_decisions_moved_still_validates(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    rel = f"standing-rules/{first.stem}.md"
    first.write_text(
        first.read_text(encoding="utf-8").replace(
            f"- Standing rules: {rel}#Decisions in force", D1
        ),
        encoding="utf-8",
    )
    standing = standing_file(first)
    text = standing.read_text(encoding="utf-8")
    standing.write_text(text.split("\n## Decisions in force\n")[0] + "\n", "utf-8")
    assert validate(first).returncode == 0, out(validate(first))
    second = role_hop(repo, tmp_path, first, k=2, flag=False)
    assert body(second, "Decisions in force").startswith("- Standing rules: ")
    assert body(standing_file(second, first), "Decisions in force") == D1
    for path in (first, second):
        assert validate(path).returncode == 0, out(validate(path))


def three_hops(tmp_path: Path) -> list[Path]:
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"decisions-new": D2},
        retire=[{"ref": "[D1]", "reason": "superseded by D2"}],
    )
    third = role_hop(
        repo,
        tmp_path,
        second,
        k=3,
        flag=False,
        retire=[{"ref": "[R2]", "reason": "moved to AGENTS.md"}],
    )
    return [first, second, third]


def test_retire_pointers_collapse_into_one_index_that_grows_each_hop(tmp_path):
    first, second, third = three_hops(tmp_path)
    index = index_file(second, first)
    rel = f"archive/{first.stem}/retired-index.md"
    h2 = hop_file(second.parent, first.name, 2, SIDS[1]).name
    h3 = hop_file(second.parent, first.name, 3, SIDS[2]).name
    for path in (second, third):
        text = path.read_text(encoding="utf-8")
        assert pointer_lines(text) == [], path
        review = body(path, "Review before you continue").split("\n")
        assert [line for line in review if line.startswith(INDEX_PREFIX)] == [
            f"{INDEX_PREFIX}{rel}"
        ]
    held = pointer_lines(index.read_text(encoding="utf-8"))
    assert held == [
        f"- Retired entries: archive/{first.stem}/{h2} § Retired decisions",
        f"- Retired entries: archive/{first.stem}/{h3} § Retired rules",
    ]
    for path in (first, second, third):
        result = validate(path)
        assert result.returncode == 0, out(result)


def test_the_index_never_repeats_a_pointer(tmp_path):
    first, _, third = three_hops(tmp_path)
    index = index_file(third, first)
    before = index.read_text(encoding="utf-8")
    fourth = role_hop(tmp_path / "repo", tmp_path, third, k=4, flag=False)
    assert index.read_text(encoding="utf-8") == before
    held = pointer_lines(before)
    assert len(held) == len(set(held)) == 2
    assert validate(fourth).returncode == 0, out(validate(fourth))


def test_a_lost_earlier_pointer_fails_validation(tmp_path):
    first, second, third = three_hops(tmp_path)
    index = index_file(third, first)
    text = index.read_text(encoding="utf-8")
    lost = pointer_lines(text)[0]
    index.write_text(text.replace(lost + "\n", ""), encoding="utf-8")
    result = validate(third)
    assert result.returncode == 1, out(result)
    assert any("retire pointer is missing" in line for line in fails(result)), out(
        result
    )


def test_a_missing_index_fails_validation(tmp_path):
    first, second, _ = three_hops(tmp_path)
    index_file(second, first).unlink()
    result = validate(second)
    assert result.returncode == 1, out(result)
    assert any("retired-index.md" in line for line in fails(result)), out(result)


def test_legacy_pointers_in_the_hot_file_move_into_the_index_once(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"decisions-new": D2},
        retire=[{"ref": "[D1]", "reason": "superseded"}],
    )
    index = index_file(second, first)
    (line,) = pointer_lines(index.read_text(encoding="utf-8"))
    text = second.read_text(encoding="utf-8")
    second.write_text(
        "\n".join(
            f"{line}\n{line}" if row.startswith(INDEX_PREFIX) else row
            for row in text.split("\n")
        ),
        encoding="utf-8",
    )
    index.unlink()
    assert validate(second).returncode == 0, out(validate(second))
    third = role_hop(repo, tmp_path, second, k=3, flag=False)
    assert pointer_lines(third.read_text(encoding="utf-8")) == []
    assert pointer_lines(index.read_text(encoding="utf-8")) == [line]
    assert validate(third).returncode == 0, out(validate(third))


def test_a_chain_without_standing_rules_is_unchanged(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path, flag=False)
    second = role_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"decisions-new": D2},
        retire=[{"ref": "[D1]", "reason": "superseded"}],
    )
    for path in (first, second):
        assert "standing_rules:" not in path.read_text(encoding="utf-8")
    assert body(first, "Decisions in force") == D1
    h2 = hop_file(second.parent, first.name, 2, SIDS[1]).name
    assert pointer_lines(second.read_text(encoding="utf-8")) == [
        f"- Retired entries: archive/{first.stem}/{h2} § Retired decisions"
    ]
    archive = second.parent / "archive" / first.stem
    assert not standing_file(second, first).exists()
    assert not (archive / "retired-index.md").exists()
    for path in (first, second):
        assert validate(path).returncode == 0, out(validate(path))


def test_a_dropped_index_line_fails_validation(tmp_path):
    _, _, third = three_hops(tmp_path)
    text = third.read_text(encoding="utf-8")
    third.write_text(
        "\n".join(row for row in text.split("\n") if not row.startswith(INDEX_PREFIX)),
        encoding="utf-8",
    )
    result = validate(third)
    assert result.returncode == 1, out(result)
    assert any("retire pointer is missing" in line for line in fails(result)), out(
        result
    )


def test_amend_appends_to_an_existing_index_and_keeps_its_other_lines(tmp_path):
    first, _, third = three_hops(tmp_path)
    index = index_file(third, first)
    note = "Owner note: read h2 first."
    index.write_text(index.read_text(encoding="utf-8") + note + "\n", encoding="utf-8")
    before = pointer_lines(index.read_text(encoding="utf-8"))
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"retire": [{"ref": "[D2]", "reason": "shipped"}]}),
        encoding="utf-8",
    )
    result = run(
        "amend", str(third), "--json", str(payload), "--now", "2026-09-03T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    text = index.read_text(encoding="utf-8")
    h3 = hop_file(third.parent, first.name, 3, SIDS[2]).name
    assert pointer_lines(text) == [
        *before,
        f"- Retired entries: archive/{first.stem}/{h3} § Retired decisions",
    ]
    assert note in text
    assert pointer_lines(third.read_text(encoding="utf-8")) == []
    assert validate(third).returncode == 0, out(validate(third))


def test_amend_leaves_no_index_when_the_hot_file_write_fails(tmp_path, monkeypatch):
    path = role_hop(make_repo(tmp_path), tmp_path)
    index = index_file(path)
    others = [path, standing_file(path), hop_file(path.parent, path.name, 1, SIDS[0])]
    before = [p.read_bytes() for p in others]
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps({"retire": [{"ref": "[D1]", "reason": "no longer bears"}]}),
        encoding="utf-8",
    )
    fail_replace_onto(monkeypatch, path)
    code = in_process(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert code == 2
    assert not index.exists()
    assert [p.read_bytes() for p in others] == before


def test_fill_leaves_no_index_when_the_hot_file_write_fails(tmp_path, monkeypatch):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    made = role_new(repo, tmp_path, first, k=2, flag=False)
    assert made.returncode == 0, err(made)
    second = Path(out(made).strip())
    slots = slots_for(
        second,
        tmp_path,
        {"decisions-new": D2},
        [{"ref": "[D1]", "reason": "superseded"}],
    )
    others = [
        second,
        standing_file(second, first),
        hop_file(second.parent, first.name, 2, SIDS[1]),
    ]
    before = [p.read_bytes() for p in others]
    fail_replace_onto(monkeypatch, second)
    code = in_process("fill", str(second), "--slots", str(slots))
    assert code == 2
    assert not index_file(second, first).exists()
    assert [p.read_bytes() for p in others] == before


def test_new_refuses_a_predecessor_naming_another_chains_index(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    second = role_hop(
        repo,
        tmp_path,
        first,
        k=2,
        flag=False,
        values={"decisions-new": D2},
        retire=[{"ref": "[D1]", "reason": "superseded"}],
    )
    text = second.read_text(encoding="utf-8")
    rel = f"archive/{first.stem}/retired-index.md"
    second.write_text(
        text.replace(INDEX_PREFIX + rel, INDEX_PREFIX + "archive/other/retired-index.md"),
        encoding="utf-8",
    )
    made = role_new(repo, tmp_path, second, k=3, flag=False)
    assert made.returncode == 1, err(made)
    assert "retired-entries index archive/other/retired-index.md" in err(made)
