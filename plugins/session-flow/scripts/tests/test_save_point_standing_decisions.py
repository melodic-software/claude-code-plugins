# test-scope: plugins/session-flow/scripts/tests/fixtures/*
"""A role chain's Decisions in force live in its standing-rules file, and its
retire pointers in one retired-entries index beside it. Expected values come
from reference/structure.md ("Role chains: the standing-rules file" and "The
retired-entries index"): the hot file holds one pointer line for each, a
decision leaves only through `retire`, and no earlier retire pointer is lost."""

from __future__ import annotations

import json
from pathlib import Path

from shape4_chain import SIDS
from test_save_point import (
    FILL_RE,
    SHAPE3_VALUES,
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
    made = run(
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
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    held = {name for name, _ in FILL_RE.findall(path.read_text(encoding="utf-8"))}
    merged = {**SHAPE3_VALUES, **(values or {})}
    payload: dict[str, object] = {k: v for k, v in merged.items() if k in held}
    if retire:
        payload["retire"] = retire
    slots = tmp_path / f"{path.stem}.slots.json"
    slots.write_text(json.dumps(payload), encoding="utf-8")
    filled = run("fill", str(path), "--slots", str(slots))
    assert filled.returncode == 0, err(filled) + out(filled)
    return path


def index_file(path: Path, root: Path | None = None) -> Path:
    return path.parent / "archive" / (root or path).stem / "retired-index.md"


def pointer_lines(text: str) -> list[str]:
    return [line for line in text.split("\n") if line.startswith("- Retired entries: ")]


def fails(result) -> list[str]:
    return [line for line in out(result).splitlines() if line.startswith("FAIL: ")]


def test_decisions_leave_the_hot_file_for_the_standing_file(tmp_path):
    path = role_hop(make_repo(tmp_path), tmp_path)
    rel = f"archive/{path.stem}/standing-rules.md"
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
    assert body(second, "Decisions in force").startswith("- Standing rules: archive/")
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
    assert body(path, "Decisions in force").startswith("- Standing rules: archive/")
    own = hop_file(path.parent, path.name, 1, SIDS[0]).read_text(encoding="utf-8")
    assert f"{D1}\nRetired: no longer bears" in own
    assert pointer_lines(path.read_text(encoding="utf-8")) == []
    assert len(pointer_lines(index_file(path).read_text(encoding="utf-8"))) == 1
    assert validate(path).returncode == 0, out(validate(path))


def test_a_role_chain_written_before_decisions_moved_still_validates(tmp_path):
    repo = make_repo(tmp_path)
    first = role_hop(repo, tmp_path)
    rel = f"archive/{first.stem}/standing-rules.md"
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
    assert not (archive / "standing-rules.md").exists()
    assert not (archive / "retired-index.md").exists()
    for path in (first, second):
        assert validate(path).returncode == 0, out(validate(path))
