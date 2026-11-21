"""Write-time sizing for save_point.py: the byte budget of each size-classed
slot, the shape-4 fit that moves whole movable sections to this hop's file
behind a pointer, and the paged-Read directive for a hot file past one Read
page. Stdlib only; this module imports nothing from `save_point`.

Slot budgets are the 95th percentile of each slot over the 143 shape-3 hot
files dated in the 7-day handoff audit window (2026-11-11T18:46Z to
2026-11-18T18:46Z): the Resumption brief (979 bytes) and, over the 31 files
that wrote one, the below-the-rails note (281 bytes).
"""

from __future__ import annotations

import json
from pathlib import Path

from handoff_chain import moved_heading, section_spans

SLOT_BUDGETS: dict[str, int] = {"brief": 979, "below-rail": 281}
SLOT_LABELS: dict[str, str] = {
    "brief": "Resumption brief",
    "below-rail": "below-the-rails note",
}
PURPOSE_PREFIX = "Purpose: "
REOPEN_PREFIX = "Or reopen the producing session in place: "
MOVE_ORDER = ("Observations", "Suggested skills", "Direction changes")
MOVED_PREFIX = "- Moved: "
PAGED_CLAUSE = (
    "in pages with the Read tool's offset and limit (this file is over one Read "
    "page), then "
)


def _bytes(text: str) -> int:
    return len(text.replace("\r\n", "\n").strip("\n").encode("utf-8"))


def _trim(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def slot_overruns(values: dict[str, str]) -> list[tuple[str, int, int]]:
    """`(slot, bytes, budget)` for each size-classed slot value over its budget."""
    return [
        (name, held, budget)
        for name, budget in SLOT_BUDGETS.items()
        if name in values and (held := _bytes(values[name])) > budget
    ]


def written_slot_bytes(
    brief: list[str] | None, prompt: list[str] | None
) -> dict[str, int]:
    """The bytes the session wrote into each size-classed slot of a filled hot
    file: the Resumption brief less the Purpose line `new` writes, and the
    Resume prompt's lines below the reopen line."""
    found: dict[str, int] = {}
    if brief is not None:
        lines = _trim(brief)
        if lines and lines[0].startswith(PURPOSE_PREFIX):
            lines = lines[1:]
        found["brief"] = _bytes("\n".join(_trim(lines)))
    if prompt is not None:
        at = next(
            (i for i, line in enumerate(prompt) if line.startswith(REOPEN_PREFIX)),
            None,
        )
        if at is not None:
            found["below-rail"] = _bytes("\n".join(_trim(prompt[at + 1 :])))
    return found


def overrun_text(name: str, held: int, budget: int) -> str:
    return (
        f"slot_size: {SLOT_LABELS[name]} (slot '{name}') holds {held} bytes, "
        f"{held - budget} bytes over its {budget}-byte budget; fill refuses an "
        "over-budget slot once and writes the second call anyway, so this FAIL is "
        "final: quote it, never edit around it"
    )


def refusal_text(overruns: list[tuple[str, int, int]], marker: Path) -> str:
    named = "; ".join(
        f"slot '{name}' ({SLOT_LABELS[name]}) is {held} bytes, {held - budget} bytes over its {budget}-byte budget"
        for name, held, budget in overruns
    )
    return (
        f"{named}; nothing written. Rewrite that slot once and re-run the same fill: "
        f"a second fill over the budget writes the file anyway, and validate then "
        f"FAILs it naming the slot (attempt recorded in {marker.name})"
    )


def over_budget_marker(hot: Path) -> Path:
    """Where `fill` records a refused first attempt; not a `.md` file, so no
    handoff reader globs it, and removed when the fill writes."""
    return hot.parent / f".{hot.name}.over-budget"


def refused_slots(marker: Path) -> set[str]:
    """The slots a refused first fill recorded in `marker`; empty when the
    file is absent or unreadable."""
    try:
        recorded = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    if not isinstance(recorded, list):
        return set()
    return {name for name in recorded if isinstance(name, str) and name in SLOT_BUDGETS}


def size_of(lines: list[str]) -> int:
    return len("".join(lines).encode("utf-8"))


def _content(line: str) -> str:
    return line.rstrip("\r\n")


def fit(
    hot: list[str],
    hop: list[str],
    *,
    movable: tuple[str, ...],
    cap: int,
    rel: str,
    hop_number: int,
    term: str,
) -> tuple[list[str], list[str], list[str]]:
    """Move whole movable sections, in MOVE_ORDER, out of the hot file's lines
    into this hop's file under `## <Section> (h<k>)`, each leaving a pointer,
    until the hot file is at or under `cap`. Lines keep their terminators;
    returns the hot lines, the hop lines and the moved section names."""
    hot, hop = list(hot), list(hop)
    moved: list[str] = []
    for title in sorted(movable, key=MOVE_ORDER.index):
        if size_of(hot) <= cap:
            break
        content = [_content(line) for line in hot]
        span = next(
            ((at, end) for name, at, end in section_spans(content, 0) if name == title),
            None,
        )
        if span is None:
            continue
        at, end = span
        body = _trim(content[at + 1 : end])
        if not body or (len(body) == 1 and body[0].startswith(MOVED_PREFIX)):
            continue
        heading = moved_heading(title, hop_number)
        hot[at + 1 : end] = [term, f"{MOVED_PREFIX}{rel}#{heading}{term}", term]
        if hop and not hop[-1].endswith(("\n", "\r")):
            hop[-1] += term
        hop += [term, f"## {heading}{term}", term, *(line + term for line in body)]
        moved.append(title)
    return hot, hop, moved


def paged(hot: list[str], read_cap: int) -> list[str]:
    """The hot lines with each Resume prompt `Read @` directive telling the
    reader to page, when the file is over `read_cap` bytes."""
    if size_of(hot) <= read_cap:
        return hot
    content = [_content(line) for line in hot]
    span = next(
        (
            (at, end)
            for name, at, end in section_spans(content, 0)
            if name == "Resume prompt"
        ),
        None,
    )
    if span is None:
        return hot
    out = list(hot)
    for i in range(span[0] + 1, span[1]):
        line = content[i]
        if not line.startswith("Read @") or PAGED_CLAUSE in line or ", " not in line:
            continue
        head, tail = line.split(", ", 1)
        out[i] = f"{head}, {PAGED_CLAUSE}{tail}{hot[i][len(line) :]}"
    return out
