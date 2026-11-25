from __future__ import annotations

import os
import re
from dataclasses import dataclass, field, replace
from pathlib import Path

ARCHIVE_DIR = "archive"
HANDOFF_NAME_RE = re.compile(r"^\d{8}T\d{6}Z-handoff-[^/\\]+\.md$")
H2_RE = re.compile(r"^## (.+?)\s*$")
CHAIN_ITEM_RE = re.compile(r"^\s+-\s+")
BULLET_RE = re.compile(r"^(?:[-*+]|\d+[.)])\s+")
RETIRED_PREFIX = "Retired:"


@dataclass(frozen=True)
class SectionSpec:
    """One handoff-file section. `binding` never leaves the handoff file to meet the
    cap, `movable` may move to the archive file, `carried` is written by `new`
    alone; `id_prefix` names the `[<prefix><n>]` ids its entries carry and
    `retire_heading` the archive-file heading an entry leaving it is listed under."""

    name: str
    binding: bool = False
    movable: bool = False
    carried: bool = False
    id_prefix: str | None = None
    retire_heading: str | None = None
    size_class: str | None = None

    def __post_init__(self) -> None:
        if self.binding and self.movable:
            raise ValueError(f"{self.name}: a section is binding or movable, not both")
        if self.carried and self.size_class is not None:
            raise ValueError(f"{self.name}: a carried section takes no size class")


@dataclass(frozen=True)
class IdSpec:
    """One family of `[<prefix><n>]` ids: the sections holding them, the
    archive-file heading listing each id that leaves with why, and the frontmatter
    key holding the next unused id."""

    prefix: str
    sections: tuple[str, ...]
    retired_heading: str
    floor_key: str


ID_FLOOR_KEYS = (
    ("R", "next_rule_id"),
    ("Q", "next_question_id"),
    ("D", "next_decision_id"),
)


@dataclass(frozen=True)
class ShapeSpec:
    """A handoff shape's sections in file order. `legacy_omits` names sections
    an older file of this shape may lack. `id_specs` follows ID_FLOOR_KEYS, the
    order `new` writes the id floors in."""

    shape: int
    sections: tuple[SectionSpec, ...]
    cap_bytes: int | None = None
    legacy_omits: tuple[str, ...] = ()
    id_specs: tuple[IdSpec, ...] = field(init=False, repr=False, compare=False)

    def __post_init__(self) -> None:
        specs: list[IdSpec] = []
        for prefix, floor_key in ID_FLOOR_KEYS:
            owned = [s for s in self.sections if s.id_prefix == prefix]
            if not owned:
                continue
            headings = {s.retire_heading for s in owned}
            if len(headings) != 1 or None in headings:
                raise ValueError(
                    f"shape {self.shape}: [{prefix}<n>] sections need one retire heading"
                )
            specs.append(
                IdSpec(
                    prefix,
                    tuple(s.name for s in owned),
                    owned[0].retire_heading or "",
                    floor_key,
                )
            )
        object.__setattr__(self, "id_specs", tuple(specs))

    @property
    def names(self) -> tuple[str, ...]:
        return tuple(s.name for s in self.sections)

    @property
    def legacy_names(self) -> tuple[str, ...]:
        return tuple(n for n in self.names if n not in self.legacy_omits)

    @property
    def binding(self) -> tuple[str, ...]:
        return tuple(s.name for s in self.sections if s.binding)

    @property
    def carried(self) -> tuple[str, ...]:
        return tuple(s.name for s in self.sections if s.carried)

    @property
    def movable(self) -> tuple[str, ...]:
        return tuple(s.name for s in self.sections if s.movable)

    @property
    def retired_entry_sections(self) -> dict[str, str]:
        """Sections whose id-less entries leave only when listed under their
        retire heading, to that heading."""
        return {
            s.name: s.retire_heading
            for s in self.sections
            if s.retire_heading and not s.id_prefix
        }

    def id_spec(self, prefix: str) -> IdSpec:
        return next(spec for spec in self.id_specs if spec.prefix == prefix)


_RULES = dict(id_prefix="R", retire_heading="Retired rules")

SHAPES: dict[int, ShapeSpec] = {
    2: ShapeSpec(
        2,
        (
            *(
                SectionSpec(name)
                for name in (
                    "Original goal",
                    "Resumption brief",
                    "Completion criteria",
                    "Constraints that must hold",
                    "Environment to re-establish",
                    "Side effects already applied",
                    "File roles in this work",
                    "Decisions already settled",
                    "Approaches tried and abandoned",
                    "Findings that cost effort to discover",
                    "Remaining actions, in order",
                    "Open questions to investigate",
                    "Blockers needing an outside decision",
                    "Suggested skills",
                    "This session",
                )
            ),
            SectionSpec("Prior sessions", carried=True),
            SectionSpec("Resume prompt", carried=True),
        ),
    ),
    3: ShapeSpec(
        3,
        (
            SectionSpec(
                "Original goal", binding=True, retire_heading="Retired goal amendments"
            ),
            SectionSpec("Review before you continue"),
            SectionSpec(
                "Direction changes",
                binding=True,
                retire_heading="Retired direction changes",
            ),
            SectionSpec("Resumption brief", binding=True),
            SectionSpec("Completion criteria"),
            SectionSpec("Remaining actions, in order"),
            SectionSpec(
                "Open questions", id_prefix="Q", retire_heading="Retired open questions"
            ),
            SectionSpec("Current rules", binding=True, **_RULES),
            SectionSpec("Observations"),
            SectionSpec("Pending commands"),
            SectionSpec("Environment to re-establish"),
            SectionSpec(
                "Decisions in force", id_prefix="D", retire_heading="Retired decisions"
            ),
            SectionSpec("Suggested skills"),
            SectionSpec("This session"),
            SectionSpec("Prior sessions", carried=True),
            SectionSpec("Standing preferences", binding=True, **_RULES),
            SectionSpec("Resume prompt", carried=True),
        ),
        cap_bytes=24_600,
        legacy_omits=("Suggested skills",),
    ),
    4: ShapeSpec(
        4,
        (
            SectionSpec(
                "Original goal", binding=True, retire_heading="Retired goal amendments"
            ),
            *(
                SectionSpec(name, binding=True)
                for name in (
                    "Resumption brief",
                    "Remaining actions, in order",
                    "Completion criteria",
                )
            ),
            SectionSpec(
                "Open questions",
                binding=True,
                id_prefix="Q",
                retire_heading="Retired open questions",
            ),
            SectionSpec("Current rules", binding=True, **_RULES),
            SectionSpec("Standing preferences", binding=True, **_RULES),
            SectionSpec(
                "Decisions in force",
                binding=True,
                id_prefix="D",
                retire_heading="Retired decisions",
            ),
            *(
                SectionSpec(name, binding=True)
                for name in (
                    "Pending commands",
                    "Environment to re-establish",
                    "This session",
                    "Review before you continue",
                )
            ),
            SectionSpec(
                "Direction changes",
                movable=True,
                retire_heading="Retired direction changes",
            ),
            SectionSpec("Observations", movable=True),
            SectionSpec("Suggested skills", movable=True),
            SectionSpec("Prior sessions", carried=True),
            SectionSpec("Resume prompt", carried=True),
        ),
        cap_bytes=24_600,
    ),
}
HOP_FILE_SHAPES = tuple(shape for shape in SHAPES if shape >= 3)


def fm_value(raw: str) -> str:
    """A scalar frontmatter value: inline ` # comment` and surrounding quotes
    stripped."""
    value = raw.strip()
    value = value.split(" #", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    return value


@dataclass
class Frontmatter:
    values: dict[str, str] = field(default_factory=dict)
    chain: list[str] = field(default_factory=list)
    present: bool = False
    body_start: int = 0


def read_frontmatter(lines: list[str]) -> Frontmatter:
    """The leading `---` block: scalar keys, the shape-2 `chain:` list, and the
    index of the first body line."""
    fm = Frontmatter()
    idx = 0
    if lines and lines[0].strip() == "---":
        idx = 1
        while idx < len(lines) and lines[idx].strip() != "---":
            line = lines[idx]
            if line.startswith("chain:"):
                inline = line[len("chain:") :].strip()
                if inline.startswith("[") and inline.endswith("]"):
                    fm.chain = [
                        fm_value(item)
                        for item in inline[1:-1].split(",")
                        if item.strip()
                    ]
                idx += 1
                while idx < len(lines) and CHAIN_ITEM_RE.match(lines[idx]):
                    fm.chain.append(fm_value(CHAIN_ITEM_RE.sub("", lines[idx])))
                    idx += 1
                continue
            if ":" in line and not line.startswith((" ", "\t")):
                key, raw = line.split(":", 1)
                fm.values[key.strip()] = fm_value(raw)
            idx += 1
        if idx < len(lines):
            fm.present = True
            idx += 1
    fm.body_start = idx
    return fm


def section_spans(lines: list[str], start: int) -> list[tuple[str, int, int]]:
    """`(title, heading index, end index)` for each `## ` section from `start`."""
    heads = [
        (m.group(1), i)
        for i in range(start, len(lines))
        if (m := H2_RE.match(lines[i]))
    ]
    return [
        (title, at, heads[n + 1][1] if n + 1 < len(heads) else len(lines))
        for n, (title, at) in enumerate(heads)
    ]


def _shape_of(values: dict[str, str]) -> int | None:
    try:
        return int(values["handoff_shape"])
    except (KeyError, ValueError):
        return None


def _stem(name: str) -> str:
    return name[: -len(".md")] if name.endswith(".md") else name


def hop_file_path(handoffs: Path, chain_root: str, hop: int, session_id: str) -> Path:
    """`<handoffs>/archive/<chain-root-stem>/h<N>-<session8>.md`."""
    return (
        handoffs
        / ARCHIVE_DIR
        / _stem(chain_root)
        / f"h{hop}-{session_id[:8].lower()}.md"
    )


def id_of(prefix: str, text: str) -> tuple[int | None, str]:
    """The `[<prefix><n>]` id leading `text` and the text after it."""
    m = re.match(rf"^\[{prefix}(\d+)\]\s*", text)
    return (int(m.group(1)), text[m.end() :]) if m else (None, text)


def retired_listings(
    archived: str, heading: str
) -> list[tuple[tuple[str, ...], str | None]]:
    """Each listing under `## <heading>` in an archive file: the entry's lines and the
    reason on the `Retired:` line closing it, or None for a line no `Retired:`
    line closes (the one-line `- [R<n>] <reason>` rule shape)."""
    found: list[tuple[tuple[str, ...], str | None]] = []
    pending: list[str] = []
    inside = False
    for line in [*archived.splitlines(), "## "]:
        if line.startswith("## ") or not line.strip():
            found.extend(((entry,), None) for entry in pending)
            pending = []
            if line.startswith("## "):
                inside = line[3:].strip() == heading
        elif not inside:
            continue
        elif line.startswith(RETIRED_PREFIX):
            if pending:
                found.append((tuple(pending), line[len(RETIRED_PREFIX) :].strip()))
            pending = []
        else:
            pending.append(line)
    return found


def entry_text(
    prefix: str, lines: tuple[str, ...] | list[str]
) -> tuple[int | None, str]:
    """An id-carrying entry's id and its text after the id, whitespace squashed."""
    joined = " ".join(line.strip() for line in lines if line.strip())
    n, rest = id_of(prefix, BULLET_RE.sub("", joined, count=1))
    return n, " ".join(rest.split())


def _archived_entry(lines: list[str], spec: IdSpec, n: int) -> str | None:
    for title, at, end in section_spans(lines, 0):
        if title not in spec.sections:
            continue
        body = lines[at + 1 : end]
        for i, line in enumerate(body):
            if not BULLET_RE.match(line):
                continue
            entry = [line]
            for more in body[i + 1 :]:
                if not more.startswith((" ", "\t")):
                    break
                entry.append(more)
            k, text = entry_text(spec.prefix, entry)
            if k == n:
                return text
    return None


MOVE_POINTER_RE = re.compile(
    rf"(?P<file>{ARCHIVE_DIR}/[^\s#/`]+/h\d+-[0-9a-f]{{8}}\.md)#(?P<heading>[^`\n]+?)`?\s*$"
)


@dataclass(frozen=True)
class MovePointer:
    """`archive/<chain>/h<k>-<sid8>.md#<Section heading>`: where a section moved
    out of the handoff file now lives, relative to the handoff file's directory."""

    file: str
    heading: str

    @classmethod
    def parse(cls, text: str) -> MovePointer | None:
        m = MOVE_POINTER_RE.search(text)
        return cls(m["file"], m["heading"].strip()) if m else None

    def moves(self, name: str) -> bool:
        """True when this pointer stands for section `name`: its heading is the
        name, or the name with the moving hop's tag (`moved_heading`)."""
        return self.heading == name or bool(
            re.fullmatch(rf"{re.escape(name)} \(h\d+\)", self.heading)
        )

    def target(self, base: Path) -> list[str] | None:
        """The pointed section's body, the file read relative to `base` (the
        handoffs directory); None when the file or the heading is not there."""
        try:
            text = (base / self.file).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
        lines = text.splitlines()
        return next(
            (
                lines[at + 1 : end]
                for title, at, end in section_spans(lines, 0)
                if title == self.heading
            ),
            None,
        )


def moved_heading(name: str, hop: int) -> str:
    """The heading a hop's own moved section takes in its archive file, which holds
    the predecessor's copy of that section under the plain name."""
    return f"{name} (h{hop})"


STANDING_DIR = "standing-rules"
STANDING_PREFIX = "- Standing rules: "
STANDING_SECTIONS = ("Current rules", "Standing preferences", "Decisions in force")
STANDING_INLINE_OK = ("Decisions in force",)
LEGACY_STANDING_FILE = "standing-rules.md"
STANDING_FILE_RE = re.compile(
    rf"^(?:{STANDING_DIR}/(?!\.)[^\s#/`]+\.md"
    rf"|{ARCHIVE_DIR}/(?!\.\.?/)[^\s#/`]+/{re.escape(LEGACY_STANDING_FILE)})$"
)


def standing_rels(chain_root: str) -> tuple[str, str]:
    """The paths, relative to the handoffs directory, a role chain's
    standing-rules file may take: the one new chains write, then
    `archive/<chain-root-stem>/standing-rules.md`, which hops written before
    the move still name; a later hop of such a chain writes the first."""
    stem = _stem(chain_root)
    return f"{STANDING_DIR}/{stem}.md", f"{ARCHIVE_DIR}/{stem}/{LEGACY_STANDING_FILE}"


def standing_rel(chain_root: str) -> str:
    """`standing-rules/<chain-root-stem>.md`, where a new role chain writes its
    standing-rules file: outside `archive/`, whose files never change once
    written, and outside the direct-child `*-handoff-*.md` listing."""
    return standing_rels(chain_root)[0]


def standing_pointer(body: list[str]) -> tuple[str, str] | None:
    """`(file, heading)` when a section body is only a standing-rules pointer,
    `- Standing rules: archive/<chain>/standing-rules.md#<heading>`."""
    content = [line.strip() for line in body if line.strip()]
    if len(content) != 1 or not content[0].startswith(STANDING_PREFIX):
        return None
    file, sep, heading = content[0][len(STANDING_PREFIX) :].partition("#")
    if not sep or not STANDING_FILE_RE.match(file.strip()):
        return None
    return file.strip(), heading.strip()


def section_of(text: str, heading: str) -> list[str] | None:
    """The body of `## <heading>` in `text`, None when it has no such heading."""
    lines = text.splitlines()
    return next(
        (
            lines[at + 1 : end]
            for title, at, end in section_spans(lines, 0)
            if title == heading
        ),
        None,
    )


def follow(body: list[str], name: str, base: Path) -> list[str] | None:
    """A section body, or, when the body is only a move pointer for `name` or a
    standing-rules pointer, the pointed body (None when unreachable)."""
    standing = standing_pointer(body) if name in STANDING_SECTIONS else None
    if standing is not None:
        try:
            text = (base / standing[0]).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
        return section_of(text, standing[1])
    content = [line for line in body if line.strip()]
    pointer = MovePointer.parse(content[0]) if len(content) == 1 else None
    if pointer is None or not pointer.moves(name):
        return body
    return pointer.target(base)


@dataclass(frozen=True)
class Link:
    """One handoff file on a chain. `status` is `ok`, `missing`, `unreadable` or
    `unsupported_shape` (a shape no table here describes; its frontmatter is
    still read)."""

    path: Path
    status: str
    shape: int | None = None
    frontmatter: dict[str, str] = field(default_factory=dict)
    sections: tuple[tuple[str, tuple[str, ...]], ...] = ()
    hop_files: tuple[Path, ...] = ()
    chain: tuple[str, ...] = ()

    def section(self, name: str) -> list[str] | None:
        """The section's body lines; a body that is only a move pointer to this
        heading is read from the archive file it names, None when that file or
        heading is not there."""
        body = next((list(b) for title, b in self.sections if title == name), None)
        return None if body is None else follow(body, name, self.path.parent)

    @property
    def hop(self) -> int | None:
        raw = self.frontmatter.get("hop", "")
        if raw.isdigit():
            return int(raw)
        return len(self.chain) if self.chain else None


@dataclass(frozen=True)
class Chain:
    """A chain's links, newest first. `stop` says why the walk ended early: a
    `previous_handoff` cycle or the length limit."""

    links: tuple[Link, ...]
    stop: str | None = None

    def retired_ids(self) -> dict[str, dict[int, str | None]]:
        """Per id prefix, each id listed under its retire heading in any archive
        file on the chain, to the retired entry's text (None when a one-line
        listing gives only a reason and the archive file holds no copy). The oldest
        retirement of an id wins."""
        found: dict[str, dict[int, str | None]] = {}
        for link in reversed(self.links):
            spec = SHAPES.get(link.shape) if link.shape is not None else None
            if spec is None or not spec.id_specs:
                continue
            for path in link.hop_files:
                try:
                    text = path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                for prefix, ids in retired_in(text, spec).items():
                    into = found.setdefault(prefix, {})
                    for n, retired in ids.items():
                        into.setdefault(n, retired)
        return found


def retired_in(text: str, spec: ShapeSpec) -> dict[str, dict[int, str | None]]:
    """Per id prefix of `spec`, each id one archive file's text lists under its
    retire heading, to the retired entry's text: the listed entry's, or for a
    one-line `- [<prefix><n>] <reason>` listing the archive file's own copy of the
    entry (None when it holds none)."""
    lines = text.splitlines()
    found: dict[str, dict[int, str | None]] = {}
    for ids in spec.id_specs:
        into = found.setdefault(ids.prefix, {})
        for entry, reason in retired_listings(text, ids.retired_heading):
            n, rest = entry_text(ids.prefix, entry)
            if n is not None and n not in into:
                into[n] = rest if reason is not None else _archived_entry(lines, ids, n)
    return found


def _resolve(cursor: Path, previous: str, strict: bool) -> Path | None:
    if strict:
        if not HANDOFF_NAME_RE.match(previous):
            return None
        path = cursor.parent / previous
        here = os.path.normcase(os.path.realpath(cursor.parent))
        there = os.path.normcase(os.path.dirname(os.path.realpath(path)))
        return path if there == here else None
    for candidate in (
        cursor.parent / previous,
        cursor.parent.parent / previous,
        cursor.parent / Path(previous).name,
    ):
        if candidate.is_file():
            return candidate
    return cursor.parent / Path(previous).name


def read_link(path: Path) -> Link:
    """One handoff file as a `Link`, its predecessor not followed."""
    if not path.is_file():
        return Link(path, "missing")
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return Link(path, "unreadable")
    fm = read_frontmatter(lines)
    shape = _shape_of(fm.values)
    spans = section_spans(lines, fm.body_start)
    sections = tuple((title, tuple(lines[at + 1 : end])) for title, at, end in spans)
    known = shape in (None, 1) or shape in SHAPES
    hops: tuple[Path, ...] = ()
    root, hop = fm.values.get("chain_root", ""), fm.values.get("hop", "")
    if (
        shape is not None
        and shape >= 3
        and hop.isdigit()
        and HANDOFF_NAME_RE.match(root)
    ):
        own = hop_file_path(
            path.parent, root, int(hop), fm.values.get("session_id", "")
        )
        hops = (own,) if own.is_file() else ()
    return Link(
        path,
        "ok" if known else "unsupported_shape",
        shape,
        fm.values,
        sections,
        hops,
        tuple(fm.chain),
    )


def read_chain(path: Path, *, strict: bool = False, limit: int = 1000) -> Chain:
    """Every file on `path`'s `previous_handoff` path, newest first. The walk
    ends at a file with no `previous_handoff`, at a missing or unreadable file
    (kept as the last link), on a cycle, or after `limit` files. `strict` holds
    each predecessor to a bare filename in the same real directory, the rule
    `validate` enforces."""
    links: list[Link] = []
    seen: set[Path] = set()
    cursor: Path | None = path
    while cursor is not None:
        resolved = cursor.resolve()
        if resolved in seen:
            return Chain(tuple(links), f"previous_handoff cycle at {cursor}")
        if len(links) >= limit:
            return Chain(tuple(links), f"longer than {limit} entries")
        seen.add(resolved)
        link = read_link(cursor)
        links.append(link)
        previous = link.frontmatter.get("previous_handoff")
        if link.status in ("missing", "unreadable") or not previous:
            break
        cursor = _resolve(cursor, previous, strict)
        if cursor is None:
            break
    return Chain(tuple(links))


JOURNEY_SECTIONS = ("Direction changes", "This session", "Observations")
HOP_FILE_RE = re.compile(r"^h(\d+)-[0-9a-f]{8}\.md$")


@dataclass(frozen=True)
class Hop:
    """One session of a chain as retro reads it: hop number (None for a shape-1
    file), session id, handoff-file name (empty when only its archive file is left),
    the file its sections were read from (its handoff file, else the next hop's
    file holding their copy) and those sections, whole moves followed."""

    hop: int | None
    session_id: str
    file: str
    source: Path
    sections: dict[str, list[str]] = field(default_factory=dict)
    date: str = ""


@dataclass(frozen=True)
class Journey:
    """Every hop of a chain on disk, newest first; `stop` as `Chain.stop`."""

    hops: tuple[Hop, ...]
    stop: str | None = None

    @property
    def session_ids(self) -> list[str]:
        ids: list[str] = []
        for hop in self.hops:
            if hop.session_id not in ("", "unknown", *ids):
                ids.append(hop.session_id)
        return ids


def _trimmed(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def _journey_sections(bodies: dict[str, list[str]], base: Path) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for name in JOURNEY_SECTIONS:
        body = bodies.get(name)
        got = None if body is None else follow(body, name, base)
        if got is not None:
            found[name] = _trimmed(got)
    return found


def _row_sessions(body: list[str] | None) -> dict[str, tuple[str, str]]:
    found: dict[str, tuple[str, str]] = {}
    for line in body or []:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.lstrip().startswith("|") and len(cells) == 5 and cells[0] != "date":
            if HANDOFF_NAME_RE.match(cells[4]):
                found.setdefault(cells[4], (cells[1], cells[0]))
    return found


def journey(path: Path, limit: int = 1000) -> Journey:
    """Every hop of `path`'s chain still on disk: the handoff files `read_chain`
    reaches, then, from the chain's archive files, each handoff file that is gone
    (read from the copy the next hop's file holds) and any older handoff file an
    archive file names that the walk did not reach. Only archive files at or below
    `path`'s hop and on its own branch count: a fork's branches share the
    archive directory, so an archive file is read only when its hop and session
    are one the walk reached, or the predecessor a read archive file moved from."""
    handoffs = path.parent
    chain = read_chain(path, limit=limit)
    found: dict[str, Hop] = {}
    rows: dict[str, tuple[str, str]] = {}

    def add(links: tuple[Link, ...]) -> None:
        for link in links:
            if link.status != "ok" or link.path.name in found:
                continue
            bodies = {title: list(body) for title, body in link.sections}
            rows.update(_row_sessions(bodies.get("Prior sessions")))
            found[link.path.name] = Hop(
                link.hop,
                link.frontmatter.get("session_id", ""),
                link.path.name,
                link.path,
                _journey_sections(bodies, handoffs),
                link.frontmatter.get("date", ""),
            )

    add(chain.links)
    root = next(
        (
            r
            for link in chain.links
            if HANDOFF_NAME_RE.match(r := link.frontmatter.get("chain_root", ""))
        ),
        "",
    )
    archive = handoffs / ARCHIVE_DIR / _stem(root)
    hop_files = sorted(
        (
            (int(m[1]), p)
            for p in (archive.glob("h*.md") if root else ())
            if (m := HOP_FILE_RE.match(p.name)) and p.is_file()
        ),
        reverse=True,
    )
    start = chain.links[0].hop if chain.links else None
    on_path = {
        (link.hop, link.frontmatter.get("session_id", "")[:8].lower())
        for link in chain.links
    }
    hop_sids: dict[int, tuple[str, Path]] = {}
    for k, hop_path in hop_files:
        sid8 = hop_path.stem.split("-", 1)[1]
        if (start is not None and k > start) or (k, sid8) not in on_path:
            continue
        try:
            lines = hop_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        fm = read_frontmatter(lines)
        hop_sids.setdefault(k, (fm.values.get("session_id", ""), hop_path))
        bodies = {
            title: lines[at + 1 : end]
            for title, at, end in section_spans(lines, fm.body_start)
        }
        rows.update(_row_sessions(bodies.get("Prior sessions")))
        moved = fm.values.get("moved_from", "")
        if not HANDOFF_NAME_RE.match(moved) or moved in found:
            continue
        if (handoffs / moved).is_file():
            links = read_chain(handoffs / moved, limit=limit).links
            add(links)
            on_path |= {
                (link.hop, link.frontmatter.get("session_id", "")[:8].lower())
                for link in links
            }
        else:
            on_path.add((k - 1, rows.get(moved, ("", ""))[0][:8].lower()))
            found[moved] = Hop(
                k - 1, "", moved, hop_path, _journey_sections(bodies, handoffs)
            )
    hops: list[Hop] = []
    for hop in found.values():
        sid, date = rows.get(hop.file, ("", ""))
        hops.append(
            replace(
                hop,
                session_id=hop.session_id
                or sid
                or hop_sids.get(hop.hop or 0, ("", None))[0],
                date=hop.date or date,
            )
        )
    numbered = {hop.hop for hop in hops}
    hops += [
        Hop(k, sid, "", source)
        for k, (sid, source) in hop_sids.items()
        if k not in numbered
    ]
    hops.sort(key=lambda hop: (hop.hop is None, -(hop.hop or 0)))
    return Journey(tuple(hops), chain.stop)
