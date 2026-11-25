# test-scope: plugins/session-flow/scripts/tests/fixtures/* plugins/session-flow/scripts/dialect.py plugins/session-flow/scripts/handoff_chain.py plugins/session-flow/scripts/handoff_fit.py plugins/session-flow/scripts/io_streams.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/scripts/save_point.py
"""Shape 5: `## Reminders` takes shape 4's `## Pending commands` place. Expected
values come from reference/structure.md ("Reminders"): one entry per line,
`- [M<n>] <actor> · <trigger> · <what to do> · added h<k> <date>`, ids floored by
`next_reminder_id`, an entry leaving only through `retire` (listed under
`## Retired reminders` in the archive file), a shape-4 predecessor's Pending
commands converted to `user · when now` reminders, and a closed handoff that
still holds reminders warned about, not failed."""

from __future__ import annotations

import json
from pathlib import Path

from shape4_chain import SHAPE4_SECTIONS, SIDS
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
from test_save_point_shape4_writer import CLOSED, body, headings, validate

M1 = "- [M1] user · when the v1 tag exists · run `gh release view v1` · added h1 2026-09-01"
M2 = "- [M2] agent · at close · delete the scratch branch · added h2 2026-09-02"
SHAPE5_SECTIONS = [
    "Reminders" if title == "Pending commands" else title for title in SHAPE4_SECTIONS
]


def hop5(
    repo: Path,
    tmp_path: Path,
    previous: Path | None = None,
    *,
    k: int = 1,
    shape: str | None = None,
    values: dict[str, str] | None = None,
    retire: list[dict[str, str]] | None = None,
) -> Path:
    made = run(
        *new_args(
            repo,
            tmp_path,
            *(["--previous", str(previous)] if previous else ["--no-previous"]),
            sid=SIDS[k - 1],
            now=f"2026-09-0{k}T10:00:00Z",
            shape=shape,
        )
    )
    assert made.returncode == 0, err(made)
    path = Path(out(made).strip())
    held = {name for name, _ in FILL_RE.findall(path.read_text(encoding="utf-8"))}
    merged = {**SHAPE3_VALUES, "reminders": M1, **(values or {})}
    payload: dict[str, object] = {n: v for n, v in merged.items() if n in held}
    if retire:
        payload["retire"] = retire
    slots = tmp_path / f"{path.stem}.slots.json"
    slots.write_text(json.dumps(payload), encoding="utf-8")
    filled = run("fill", str(path), "--slots", str(slots))
    assert filled.returncode == 0, err(filled) + out(filled)
    return path


def fails(result) -> list[str]:
    return [line for line in out(result).splitlines() if line.startswith("FAIL: ")]


def test_shape5_is_the_default_and_holds_reminders_where_pending_commands_was(
    tmp_path,
):
    path = hop5(make_repo(tmp_path), tmp_path)
    text = path.read_text(encoding="utf-8")
    assert "handoff_shape: 5\n" in text
    assert "next_reminder_id: 1\n" in text
    assert headings(path) == SHAPE5_SECTIONS
    assert body(path, "Reminders") == M1
    result = validate(path)
    assert result.returncode == 0, out(result)


def test_shape5_reminder_carries_to_the_next_hop(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(repo, tmp_path)
    second = hop5(repo, tmp_path, first, k=2, values={"reminders-new": M2})
    assert [line for line in body(second, "Reminders").split("\n") if line] == [M1, M2]
    assert "next_reminder_id: 2\n" in second.read_text(encoding="utf-8")
    for path in (first, second):
        result = validate(path)
        assert result.returncode == 0, out(result)


def test_shape5_reminder_dropped_without_retire_fails_validation(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(repo, tmp_path)
    second = hop5(repo, tmp_path, first, k=2)
    second.write_text(
        second.read_text(encoding="utf-8").replace(M1, "None. Nothing to remind."),
        encoding="utf-8",
    )
    result = validate(second)
    assert result.returncode == 1, out(result)
    assert any("[M1]" in line for line in fails(result)), out(result)


def test_shape5_reminder_rewritten_in_place_with_its_mark_validates(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(repo, tmp_path)
    second = hop5(repo, tmp_path, first, k=2)
    rewritten = (
        "- [M1] user · when the v2 tag exists · run `gh release view v2` · added h1 2026-09-01"
        " Rewritten h2: the release moved to v2"
    )
    second.write_text(
        second.read_text(encoding="utf-8").replace(M1, rewritten), encoding="utf-8"
    )
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_shape5_reminder_retired_with_a_reason_lands_in_the_archive_file(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(repo, tmp_path)
    second = hop5(
        repo,
        tmp_path,
        first,
        k=2,
        values={"reminders-new": "None. The release ran."},
        retire=[{"ref": "[M1]", "reason": "ran h2"}],
    )
    assert "[M1]" not in body(second, "Reminders")
    own = hop_file(second.parent, first.name, 2, SIDS[1]).read_text(encoding="utf-8")
    retired = own.split("\n## Retired reminders\n", 1)[1]
    assert retired.lstrip("\n").startswith(f"{M1}\nRetired: ran h2\n")
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_shape5_amend_retires_a_reminder(tmp_path):
    path = hop5(make_repo(tmp_path), tmp_path)
    payload = tmp_path / "amend.json"
    payload.write_text(
        json.dumps(
            {
                "sections": {"Reminders": "None. Raised to the owner."},
                "retire": [{"ref": "[M1]", "reason": "raised h1"}],
            }
        ),
        encoding="utf-8",
    )
    result = run(
        "amend", str(path), "--json", str(payload), "--now", "2026-09-01T11:00:00Z"
    )
    assert result.returncode == 0, err(result)
    assert "[M1]" not in body(path, "Reminders")
    own = hop_file(path.parent, path.name, 1, SIDS[0]).read_text(encoding="utf-8")
    assert f"{M1}\nRetired: raised h1" in own
    assert validate(path).returncode == 0, out(validate(path))


def test_shape5_converts_a_shape4_predecessors_pending_commands(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(
        repo,
        tmp_path,
        shape="4",
        values={"commands": "- Run `make release` once CI is green."},
    )
    made = run(
        *new_args(
            repo,
            tmp_path,
            "--previous",
            str(first),
            sid=SIDS[1],
            now="2026-09-02T10:00:00Z",
            shape=None,
        )
    )
    assert made.returncode == 0, err(made)
    second = Path(out(made).strip())
    text = second.read_text(encoding="utf-8")
    assert "handoff_shape: 5\n" in text
    assert "next_reminder_id: 2\n" in text
    assert (
        "- [M1] user · when now · Run `make release` once CI is green. · added h2 2026-09-02"
        in body(second, "Reminders")
    )


def test_shape5_skips_a_none_line_when_converting_pending_commands(tmp_path):
    repo = make_repo(tmp_path)
    first = hop5(repo, tmp_path, shape="4")
    second = hop5(repo, tmp_path, first, k=2)
    assert "None. No command waits" not in body(second, "Reminders")
    assert "next_reminder_id: 1\n" in second.read_text(encoding="utf-8")
    result = validate(second)
    assert result.returncode == 0, out(result)


def test_shape5_reminder_without_an_id_fails_validation(tmp_path):
    path = hop5(
        make_repo(tmp_path),
        tmp_path,
        values={
            "reminders": "- user · at close · tell the owner · added h1 2026-09-01"
        },
    )
    result = validate(path)
    assert result.returncode == 1, out(result)
    assert any("[M<n>]" in line for line in fails(result)), out(result)


def test_shape5_malformed_reminder_fails_validation(tmp_path):
    path = hop5(
        make_repo(tmp_path),
        tmp_path,
        values={"reminders": "- [M1] remember to run the release"},
    )
    result = validate(path)
    assert result.returncode == 1, out(result)
    assert any("[M1]" in line and "Reminders" in line for line in fails(result))


def test_shape5_closed_handoff_holding_reminders_warns_without_failing(tmp_path):
    path = hop5(make_repo(tmp_path), tmp_path, values={"next": CLOSED})
    result = validate(path)
    assert result.returncode == 0, out(result)
    warns = [line for line in out(result).splitlines() if line.startswith("WARN: ")]
    assert any("[M1]" in line and "closed" in line for line in warns), out(result)


def test_shape5_closed_handoff_with_no_reminders_does_not_warn(tmp_path):
    path = hop5(
        make_repo(tmp_path),
        tmp_path,
        values={"next": CLOSED, "reminders": "None. Nothing waits."},
    )
    result = validate(path)
    assert result.returncode == 0, out(result)
    assert not any("Reminders" in line for line in out(result).splitlines())


def test_shape5_a_newer_shape_names_the_session_flow_update(tmp_path):
    path = hop5(make_repo(tmp_path), tmp_path)
    path.write_text(
        path.read_text(encoding="utf-8").replace(
            "handoff_shape: 5\n", "handoff_shape: 9\n"
        ),
        encoding="utf-8",
    )
    result = validate(path)
    assert result.returncode == 3, out(result) + err(result)
    assert "update session-flow" in out(result) + err(result)
    made = run(
        *new_args(
            path.parent.parent.parent,
            tmp_path,
            "--previous",
            str(path),
            sid=SIDS[1],
            now="2026-09-02T10:00:00Z",
            shape=None,
        )
    )
    assert made.returncode == 1, err(made)
    assert "update session-flow" in err(made)
