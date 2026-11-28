"""Contract tests for tidy_work.py's open-chain rule: a handoff chain whose newest handoff
file is not closed keeps every file, whatever its age or PR state."""

from __future__ import annotations

from pathlib import Path

import test_tidy_work
from test_tidy_work import (
    CLOSED_NEXT,
    HOP3_2,
    ROOT3,
    SHIPPED,
    age,
    hot_file,
    links,
    report,
    resume_prompt,
    run_tidy,
    three_chain,
    tree,
    write,
)

env = test_tidy_work.env
OPEN_NEXT = "Next:\nShip the fix"
MERGED = {"#7": "merged"}
ROOT2 = "20250101T100000Z-handoff-two.md"
HOP2_2 = "20250102T100000Z-handoff-two.md"
HOP2_3 = "20250103T100000Z-handoff-two.md"
HOP3_3 = "20260103T100000Z-handoff-three.md"


def chain2(path: Path, chain: list[str], next_lines: str) -> None:
    """A shape-2 handoff file whose `chain:` lists the chain oldest first."""
    previous = f"previous_handoff: {chain[-2]}\n" if len(chain) > 1 else ""
    entries = "".join(f"  - {name}\n" for name in chain)
    write(
        path,
        "---\ntype: handoff\nhandoff_shape: 2\ndate: 2025-01-01T10:00:00Z\n"
        "topic: two\nsession_id: 00000000-0000-4000-8000-000000000000\n"
        f"transcript: /t.jsonl\n{previous}chain:\n{entries}---\n\n"
        f"## Remaining actions, in order\n\n{SHIPPED}\n\n{resume_prompt(next_lines)}",
    )


def two_chain(env, nexts: tuple[str, str]) -> list[Path]:
    """A two-hop shape-2 chain, 400 days old, one `next` per hop; the root has a
    sidecar."""
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    chain2(handoffs / ROOT2, [ROOT2], nexts[0])
    chain2(handoffs / HOP2_2, [ROOT2, HOP2_2], nexts[1])
    sidecar = handoffs / ROOT2.replace(".md", ".slots.json")
    write(sidecar, "{}")
    paths = [handoffs / ROOT2, sidecar, handoffs / HOP2_2]
    for path in paths:
        age(path, 400)
    return paths


def open_three_chain(env, nexts: tuple[str, str]) -> list[Path]:
    """The shape-3 chain of `three_chain`, 400 days old, with a Resume prompt per hop."""
    archive = three_chain(env, newest_days=400)
    handoffs = archive.parent.parent
    for name, next_lines in zip((ROOT3, HOP3_2), nexts):
        hot_file(handoffs / name, ROOT3, f"{SHIPPED}\n\n{resume_prompt(next_lines)}")
        age(handoffs / name, 400)
    age(archive, 400)
    return [handoffs / ROOT3, handoffs / HOP3_2, archive]


def test_an_old_open_chain_with_merged_prs_is_kept_whole_under_clean_apply(env):
    _, home, repo = env
    two = two_chain(env, (OPEN_NEXT, OPEN_NEXT))
    three = open_three_chain(env, (OPEN_NEXT, OPEN_NEXT))
    state = links(env[0], MERGED)
    before = tree(repo, home)

    dry = run_tidy(env, "clean", *state)
    assert dry.returncode == 0, dry.stderr
    assert "would remove" not in dry.stdout, dry.stdout
    kept = [
        line for line in dry.stdout.splitlines() if line.startswith("kept open chain: ")
    ]
    assert any(ROOT2 in line and HOP2_2 in line for line in kept), dry.stdout
    assert any(ROOT3 in line and HOP3_2 in line for line in kept), dry.stdout

    result = run_tidy(env, "clean", *state, "--apply")
    assert result.returncode == 0, result.stderr
    assert not any(
        line.startswith("removed: ") for line in result.stdout.splitlines()
    ), result.stdout
    assert tree(repo, home) == before
    assert all(path.exists() for path in (*two, *three))


def test_every_hot_file_of_an_open_chain_carries_the_open_chain_reason(env):
    two_chain(env, (OPEN_NEXT, OPEN_NEXT))
    open_three_chain(env, (OPEN_NEXT, OPEN_NEXT))
    items = report(env, *links(env[0], MERGED))
    for root, newest, members in (
        (ROOT2, HOP2_2, (ROOT2, HOP2_2)),
        (ROOT3, HOP3_2, (ROOT3, HOP3_2)),
    ):
        for name in members:
            assert items[name]["keep"], items[name]
            assert any(
                root in reason and newest in reason and "open" in reason
                for reason in items[name]["reasons"]
            ), items[name]
            assert items[name]["links"] == {}, (
                f"an open chain is kept before any link is looked up: {items[name]}"
            )
    assert items[ROOT3[:-3]]["keep"]


def test_a_finished_chain_still_leaves_by_the_age_and_pr_rules(env):
    two = two_chain(env, (OPEN_NEXT, CLOSED_NEXT))
    root3, newest3, archive = open_three_chain(env, (OPEN_NEXT, CLOSED_NEXT))
    state = links(env[0], MERGED)
    dry = run_tidy(env, "clean", *state)
    assert "kept open chain: " not in dry.stdout, dry.stdout
    result = run_tidy(env, "clean", *state, "--apply")
    assert result.returncode == 0, result.stdout
    assert not any(path.exists() for path in (*two, root3)), result.stdout
    assert newest3.exists() and archive.is_dir(), result.stdout


def test_only_the_newest_hot_file_decides_whether_a_chain_is_open(env):
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    two = two_chain(env, (CLOSED_NEXT, CLOSED_NEXT))
    chain2(handoffs / HOP2_3, [ROOT2, HOP2_2, HOP2_3], OPEN_NEXT)
    age(handoffs / HOP2_3, 400)
    three = open_three_chain(env, (CLOSED_NEXT, OPEN_NEXT))
    result = run_tidy(env, "clean", *links(env[0], MERGED), "--apply")
    assert result.returncode == 0, result.stdout
    assert all(path.exists() for path in (*two, handoffs / HOP2_3, *three))


def test_a_hot_file_without_a_next_line_leaves_its_chain_open(env):
    _, _, repo = env
    handoffs = repo / ".work" / "handoffs"
    two = two_chain(env, (CLOSED_NEXT, CLOSED_NEXT))
    write(
        handoffs / HOP3_3,
        "---\ntype: handoff\nhandoff_shape: 3\n"
        f"previous_handoff: {HOP2_2}\nchain_root: {ROOT2}\nhop: 3\n---\n\n{SHIPPED}\n",
    )
    age(handoffs / HOP3_3, 400)
    result = run_tidy(env, "clean", *links(env[0], MERGED), "--apply")
    assert result.returncode == 0, result.stdout
    assert all(path.exists() for path in (*two, handoffs / HOP3_3))
