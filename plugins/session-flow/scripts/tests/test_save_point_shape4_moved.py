"""Sections a shape-4 `fill` moved to this hop's file stay whole and checked: a
retry `new` refuses to erase them, `amend` appends into the moved body, and the
UNVERIFIED settle check reads the moved body. Expected values come from the
Writer contract: a moved section's body lives in this hop's file under
`## <Section> (h<k>)` behind a lone `- Moved: ` pointer, which `read` follows."""

from __future__ import annotations

import json
from pathlib import Path

from shape4_chain import SIDS
from test_save_point import err, hop_file, make_repo, new_args, out, run
from test_save_point_shape4_writer import body, hop, prose


def test_retry_new_refuses_to_erase_a_moved_section(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path)
    notes = prose("observation", 26_000)
    second = hop(repo, tmp_path, first, k=2, values={"observations": notes})
    assert body(second, "Observations").startswith("- Moved: archive/")
    own = hop_file(second.parent, first.name, 2, SIDS[1])
    before = own.read_bytes()

    retry = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(first),
            sid=SIDS[1],
            now="2026-09-03T10:00:00Z",
            shape="4",
        )
    )

    assert retry.returncode == 1, err(retry) + out(retry)
    assert "Observations (h2)" in err(retry), err(retry)
    assert own.read_bytes() == before
    read = run("read", str(second), "--section", "Observations")
    assert read.returncode == 0, err(read)
    assert out(read).strip("\n") == notes


def test_retry_new_rewrites_a_hop_file_with_nothing_moved(tmp_path):
    repo = make_repo(tmp_path)
    first = hop(repo, tmp_path)
    hop(repo, tmp_path, first, k=2)
    retry = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(first),
            sid=SIDS[1],
            now="2026-09-03T10:00:00Z",
            shape="4",
        )
    )
    assert retry.returncode == 0, err(retry)
    assert Path(out(retry).strip()).is_file()


TRAIL = [
    f"- [h1] turn {n}: narrowed the scope again (agent-initiated)" for n in range(400)
]


def moved_trail_hop(tmp_path: Path) -> Path:
    path = hop(
        make_repo(tmp_path),
        tmp_path,
        values={
            "observations": prose("observation", 9_000),
            "skills": prose("skill", 9_000),
            "trail": "\n".join(TRAIL),
        },
    )
    assert body(path, "Direction changes").startswith("- Moved: archive/")
    return path


def amend(path: Path, tmp_path: Path, payload: dict):
    file = tmp_path / "amend.json"
    file.write_text(json.dumps(payload), encoding="utf-8")
    return run("amend", str(path), "--json", str(file), "--now", "2026-09-01T11:00:00Z")


def test_amend_appends_into_a_moved_direction_changes_body(tmp_path):
    path = moved_trail_hop(tmp_path)
    pointer = body(path, "Direction changes")
    late = "- [h1] turn 400: the owner dropped the export step (user-initiated)"

    result = amend(path, tmp_path, {"append": {"Direction changes": [late]}})

    assert result.returncode == 0, err(result) + out(result)
    assert body(path, "Direction changes") == pointer
    read = run("read", str(path), "--section", "Direction changes")
    assert out(read).strip("\n").split("\n") == [*TRAIL, late]
    assert run("validate", str(path)).returncode == 0


CLAIM = "- UNVERIFIED: the migration is safe"
SETTLED = f"{CLAIM} (settle: `uv run pytest tests/test_migration.py`)"


def unverified_fails(path: Path) -> list[str]:
    return [
        line
        for line in out(run("validate", str(path))).splitlines()
        if line.startswith("FAIL: ") and "UNVERIFIED" in line
    ]


def observations_hop(tmp_path: Path, first: str, *, size: int) -> Path:
    notes = f"{first}\n{prose('observation', size)}" if size else first
    return hop(make_repo(tmp_path), tmp_path, values={"observations": notes})


def test_unsettled_claim_fails_the_same_moved_or_not(tmp_path):
    kept = observations_hop(tmp_path / "kept", CLAIM, size=0)
    moved = observations_hop(tmp_path / "moved", CLAIM, size=26_000)
    assert not body(kept, "Observations").startswith("- Moved: ")
    assert body(moved, "Observations").startswith("- Moved: ")

    for path in (kept, moved):
        fails = unverified_fails(path)
        assert len(fails) == 1, (path, fails)
        assert fails[0].startswith("FAIL: Observations: "), fails[0]


def test_settled_claim_passes_moved(tmp_path):
    moved = observations_hop(tmp_path, SETTLED, size=26_000)
    assert body(moved, "Observations").startswith("- Moved: ")
    assert run("validate", str(moved)).returncode == 0
    assert unverified_fails(moved) == []


def test_amend_refuses_an_unsettled_claim_appended_to_a_moved_body(tmp_path):
    path = moved_trail_hop(tmp_path)
    own = hop_file(path.parent, path.name, 1, SIDS[0])
    before = (path.read_bytes(), own.read_bytes())
    late = "- [h1] turn 400: UNVERIFIED the owner dropped the export (user-initiated)"

    result = amend(path, tmp_path, {"append": {"Direction changes": [late]}})

    assert result.returncode == 1, err(result) + out(result)
    assert "FAIL: Direction changes: " in err(result), err(result)
    assert (path.read_bytes(), own.read_bytes()) == before


def test_amend_retires_a_trail_entry_from_a_moved_direction_changes_body(tmp_path):
    path = moved_trail_hop(tmp_path)
    pointer = body(path, "Direction changes")
    own = hop_file(path.parent, path.name, 1, SIDS[0])

    result = amend(
        path,
        tmp_path,
        {"retire": [{"ref": "[h1]#1", "reason": "reverted by the owner"}]},
    )

    assert result.returncode == 0, err(result) + out(result)
    assert body(path, "Direction changes") == pointer
    read = run("read", str(path), "--section", "Direction changes")
    assert out(read).strip("\n").split("\n") == TRAIL[1:]
    assert body(own, "Retired direction changes").split("\n") == [
        TRAIL[0],
        "Retired: reverted by the owner",
    ]
    assert run("validate", str(path)).returncode == 0


def test_amend_rewrites_a_moved_observations_body_behind_its_pointer(tmp_path):
    notes = prose("observation", 26_000)
    path = observations_hop(tmp_path, "- First observation.", size=26_000)
    pointer = body(path, "Observations")
    assert pointer.startswith("- Moved: ")
    own = hop_file(path.parent, path.name, 1, SIDS[0])

    result = amend(path, tmp_path, {"sections": {"Observations": "- Rewritten."}})

    assert result.returncode == 0, err(result) + out(result)
    assert body(path, "Observations") == pointer
    read = run("read", str(path), "--section", "Observations")
    assert out(read).strip("\n") == "- Rewritten."
    amended = body(own, "Amended 2026-09-01T11:00:00Z Observations")
    assert amended == f"- First observation.\n{notes}"
    assert run("validate", str(path)).returncode == 0


def test_amend_rewrites_a_moved_trail_keeping_its_entries(tmp_path):
    path = moved_trail_hop(tmp_path)
    pointer = body(path, "Direction changes")
    late = "- [h1] turn 400: the owner dropped the export step (user-initiated)"

    result = amend(
        path, tmp_path, {"sections": {"Direction changes": "\n".join([*TRAIL, late])}}
    )

    assert result.returncode == 0, err(result) + out(result)
    assert body(path, "Direction changes") == pointer
    read = run("read", str(path), "--section", "Direction changes")
    assert out(read).strip("\n").split("\n") == [*TRAIL, late]


def test_amend_refuses_a_moved_trail_rewrite_that_drops_an_entry(tmp_path):
    path = moved_trail_hop(tmp_path)
    own = hop_file(path.parent, path.name, 1, SIDS[0])
    before = (path.read_bytes(), own.read_bytes())

    result = amend(
        path, tmp_path, {"sections": {"Direction changes": "\n".join(TRAIL[1:])}}
    )

    assert result.returncode == 1, err(result) + out(result)
    assert "removes an entry added this hop" in err(result), err(result)
    assert TRAIL[0][:40] in err(result), err(result)
    assert (path.read_bytes(), own.read_bytes()) == before
