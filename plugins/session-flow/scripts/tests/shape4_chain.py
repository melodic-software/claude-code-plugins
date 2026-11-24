from __future__ import annotations

from pathlib import Path

from test_save_point import (
    SID_A,
    SID_B,
    SID_C,
    SID_D,
    SID_E,
    hop_file,
    s3_hop,
)

SHAPE4_SECTIONS = [
    "Original goal",
    "Resumption brief",
    "Remaining actions, in order",
    "Completion criteria",
    "Open questions",
    "Current rules",
    "Standing preferences",
    "Decisions in force",
    "Pending commands",
    "Environment to re-establish",
    "This session",
    "Review before you continue",
    "Direction changes",
    "Observations",
    "Suggested skills",
    "Prior sessions",
    "Resume prompt",
]
SIDS = [SID_A, SID_B, SID_C, SID_D, SID_E]


def split_sections(text: str) -> tuple[str, dict[str, str]]:
    head, *chunks = text.split("\n## ")
    bodies = {}
    for chunk in chunks:
        title, _, body = chunk.partition("\n")
        bodies[title] = body
    return head, bodies


def join_sections(head: str, bodies: dict[str, str], order: list[str]) -> str:
    return head + "".join(f"\n## {title}\n{bodies[title]}" for title in order)


def to_shape4(path: Path) -> None:
    head, bodies = split_sections(path.read_text(encoding="utf-8"))
    assert "handoff_shape: 3\n" in head
    head = head.replace("handoff_shape: 3\n", "handoff_shape: 4\n", 1)
    path.write_text(
        join_sections(head, bodies, SHAPE4_SECTIONS), encoding="utf-8", newline="\n"
    )


def hop_values(k: int) -> dict[str, str]:
    """Slot values that tell hop `k` apart from every other hop."""
    values = {
        "observations": f"- Hop {k} observation: the run took {k} minutes.",
        "did": f"did hop {k}",
        "left": f"left after hop {k}",
    }
    if k > 1:
        values["trail-new"] = f"- [h{k}] turn {k}: narrowed the scope (agent-initiated)"
    return values


def pointer(root: str, k: int, sid: str, title: str) -> str:
    return f"- Moved: archive/{root[:-3]}/h{k}-{sid[:8]}.md#{title} (h{k})"


def move(hot: Path, root: str, k: int, sid: str, title: str) -> None:
    """Move hop `k`'s `title` section to its hop file, and point the copy the
    next hop's file holds at it, as a writer that moved it before the next hop
    copied the hot file would leave both."""
    handoffs = hot.parent
    head, bodies = split_sections(hot.read_text(encoding="utf-8"))
    moved = bodies[title].strip("\n")
    line = pointer(root, k, sid, title)
    bodies[title] = f"\n{line}\n"
    hot.write_text(
        join_sections(head, bodies, list(bodies)), encoding="utf-8", newline="\n"
    )
    own = hop_file(handoffs, root, k, sid)
    with own.open("a", encoding="utf-8", newline="\n") as fh:
        fh.write(f"\n## {title} (h{k})\n\n{moved}\n")
    nxt = next(iter((handoffs / "archive" / root[:-3]).glob(f"h{k + 1}-*.md")), None)
    if nxt is not None:
        head, bodies = split_sections(nxt.read_text(encoding="utf-8"))
        bodies[title] = f"\n{line}\n"
        nxt.write_text(
            join_sections(head, bodies, list(bodies)), encoding="utf-8", newline="\n"
        )


def s4_chain(
    repo: Path,
    tmp_path: Path,
    hops: int,
    *,
    moves: tuple[str, ...] = ("Observations",),
    shape3_hops: int = 0,
) -> list[Path]:
    """A chain of `hops` hot files: the first `shape3_hops` stay shape 3, the
    rest are shape 4 with `moves` moved to their hop files."""
    paths: list[Path] = []
    for k in range(1, hops + 1):
        paths.append(
            s3_hop(
                repo,
                tmp_path,
                paths[-1] if paths else None,
                sid=SIDS[k - 1],
                now=f"2026-09-0{k}T10:00:00Z",
                values=hop_values(k),
            )
        )
    root = paths[0].name
    for k, path in enumerate(paths, 1):
        if k <= shape3_hops:
            continue
        to_shape4(path)
        for title in moves:
            move(path, root, k, SIDS[k - 1], title)
    return paths
