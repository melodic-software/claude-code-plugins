#!/usr/bin/env python3
"""Assert every surface that restates a contract clause carries its qualifiers.

The review-disposition-and-resolution contract (D4.6 grounding, D4.6
provenance, D7.5 thread eligibility, and the authorization rule for a
resolution that ships no fix) is canonical in ONE file and restated across
half a dozen others. Nothing checked that the copies agreed, and the failure
mode is silent: every surface is individually well-formed, so a restatement
that quietly drops a qualifier reads as correct while instructing a lane to do
what another surface — or a Python guard — forbids.

#1633 is the controlled demonstration (see #1659). Seven defects across five
automated review rounds, every one an agreement failure between surfaces. A
clause patch failed. A deliberate whole-section rewrite failed. Only a
mechanical cross-surface sweep converged — and then the HAND-RUN sweep itself
produced a false "no remaining gaps", because it asked whether the carve-out
appeared ANYWHERE in a file rather than whether the passage that restates the
rule carries it. A file could pass on "has the carve-out somewhere" while
carrying an uncarved copy elsewhere, which is exactly what
`pull-request/SKILL.md` did.

So this gate is SPAN-scoped, never file-scoped. A restatement declares itself:

    <!-- contract-restatement: <clause-id> -->                  one line
    <!-- contract-restatement-begin: <clause-id> --> ... lines ...
    <!-- contract-restatement-end: <clause-id> -->

Both marker forms may sit trailing on a content line, so tagging a markdown
list item needs no structural change to the list. Qualifiers are matched
against the span's own text — a qualifier satisfied three paragraphs away no
longer clears it.

The canonical surface is held to the SAME span-scoped standard: it declares
where the clause it owns lives, and must carry every qualifier inside those
bounds. Checking the canonical file-wide instead would reproduce, in the one
place it matters most, the exact defect the gate rejects everywhere else.

What the gate guarantees is therefore PER SPAN, not per sentence: every
qualifier appears somewhere inside each declared span. A span should bound ONE
restatement. Widening a span to swallow neighbouring prose weakens the check on
that prose, because the original restatement's qualifiers now clear it — the
#1633 false negative re-admitted at smaller scale. Tag tightly.

The gate also teaches, which is the point of keying on declared intent rather
than phrasing: text that restates a clause OUTSIDE every span tagged for it is
itself reported. That half is best-effort and phrasing-dependent — a paraphrase
that dodges the `restates` vocabulary is neither detected nor flagged, and
widening those patterns as new phrasings appear is ordinary maintenance of the
registry. The qualifier check inside a declared span is the hard guarantee; the
untagged sweep is the net that makes an undeclared copy expensive. The author's two exits are both improvements — tag the
passage (and then it is held to the qualifiers), or reduce it to a pointer at
the canonical file. Pointer-not-copy is the stronger fix, and a gate that
makes a NEW restatement visible enough to argue about is what makes that
argument possible.

The in-scope surface set is DERIVED, never hand-maintained: every tracked
markdown file whose text matches a clause's `detect` vocabulary is a surface
for that clause. A hardcoded surface list would reintroduce the same
agreement defect one level up — a new restatement would simply not be
checked.

DEFERRED, deliberately: the prose/Python agreement direction. Round 2's defect
was prose contradicting `babysit_classify.thread_is_open`'s actual per-thread
behavior. This gate cannot catch that class and must not be presented as
though it could — tagging a comment in `babysit_resolve_thread.py` would prove
only that a COMMENT restates the clause with its qualifiers, never that the
code behaves the way the prose claims. Closing that direction needs the
Python's own tests to pin the behavior each clause asserts, and then a check
that the clause id and the test are linked; the marker vocabulary here is
comment-syntax-agnostic (`# contract-restatement: <id>` is recognized) so that
work has a seam to land on, but the DERIVED scope stays markdown-only until
it exists.

Usage:

    scripts/check-contract-clause-coverage.py            check the repo
    scripts/check-contract-clause-coverage.py --root DIR --registry FILE

Exit codes: 0 clean, 1 gaps found, 2 the gate could not run (fail closed).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

MIN_PYTHON = (3, 7)

if sys.version_info < MIN_PYTHON:  # pragma: no cover - guarded by the wrapper
    sys.stderr.write(
        "check-contract-clause-coverage: Python "
        f"{MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required.\n"
    )
    raise SystemExit(2)

DEFAULT_REGISTRY = "scripts/contract-clause-registry.json"

CLAUSE_ID = r"[A-Za-z0-9][A-Za-z0-9._-]*"

# A marker is a COMPLETE comment, never a loose substring: an HTML comment that
# closes on the same line, or a `#`/`//` line comment that runs to end of line.
# Anchoring this way keeps a prose mention of the vocabulary ("tag the passage
# with contract-restatement") from registering as a tag, and keeps this file's
# own docstring out of its own scan.
def _marker_body(suffix: str) -> str:
    return (
        r"contract-restatement(?P<kind" + suffix + r">-begin|-end)?:"
        r"\s*(?P<id" + suffix + r">" + CLAUSE_ID + r")"
    )


MARKER_RE = re.compile(
    r"<!--\s*" + _marker_body("_html") + r"\s*-->"
    r"|(?:^|\s)(?:\#|//)\s*" + _marker_body("_line") + r"\s*$"
)


class GateError(Exception):
    """The gate cannot answer the question it exists to answer."""


@dataclass(frozen=True)
class Qualifier:
    name: str
    pattern: "re.Pattern[str]"
    hint: str


@dataclass(frozen=True)
class Clause:
    id: str
    title: str
    canonical: str
    detect: "re.Pattern[str]"
    restates: "re.Pattern[str]"
    qualifiers: "tuple[Qualifier, ...]"


@dataclass
class Span:
    clause_id: str
    start: int  # 1-based, inclusive
    end: int  # 1-based, inclusive
    text: str = ""


@dataclass
class Finding:
    path: str
    clause: str
    line: int
    kind: str
    detail: str
    remedy: str


@dataclass
class Report:
    findings: "list[Finding]" = field(default_factory=list)
    owned: int = 0
    restatements: int = 0
    pointers: int = 0


def _compile(pattern: str, where: str) -> "re.Pattern[str]":
    try:
        return re.compile(pattern, re.IGNORECASE)
    except re.error as exc:
        raise GateError(f"{where}: invalid regex {pattern!r} ({exc})") from exc


def load_registry(path: Path) -> "tuple[Clause, ...]":
    """Read the clause registry, or fail closed."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise GateError(f"registry {path} is missing") from exc
    except (OSError, ValueError) as exc:
        raise GateError(f"registry {path} is unreadable: {exc}") from exc

    entries = raw.get("clauses")
    if not isinstance(entries, list) or not entries:
        raise GateError(f"registry {path} declares no clauses")

    clauses: "list[Clause]" = []
    seen: "set[str]" = set()
    for entry in entries:
        try:
            clause_id = entry["id"]
            canonical = entry["canonical"]
            qualifiers = entry["qualifiers"]
            detect = entry["detect"]
            restates = entry["restates"]
            title = entry["title"]
        except (KeyError, TypeError) as exc:
            raise GateError(f"registry {path}: malformed clause entry ({exc})") from exc
        if not re.fullmatch(CLAUSE_ID, str(clause_id)):
            raise GateError(f"registry {path}: clause id {clause_id!r} is not a marker-safe token")
        if clause_id in seen:
            raise GateError(f"registry {path}: duplicate clause id {clause_id!r}")
        seen.add(clause_id)
        if not qualifiers:
            raise GateError(f"registry {path}: clause {clause_id} declares no qualifiers")
        clauses.append(
            Clause(
                id=clause_id,
                title=title,
                canonical=canonical,
                detect=_compile(detect, f"clause {clause_id} detect"),
                restates=_compile(restates, f"clause {clause_id} restates"),
                qualifiers=tuple(
                    Qualifier(
                        name=q["name"],
                        pattern=_compile(q["pattern"], f"clause {clause_id} qualifier {q['name']}"),
                        hint=q["hint"],
                    )
                    for q in qualifiers
                ),
            )
        )
    return tuple(clauses)


def tracked_markdown(root: Path) -> "list[str]":
    """Every tracked *.md path, repo-relative and sorted.

    Tracked-file discovery, not a filesystem walk: an untracked scratch file
    is not a surface anyone reads, and a build tree is not authored prose.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "*.md"],
            check=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise GateError(f"could not list tracked files under {root}: {exc}") from exc
    return sorted(p for p in out.decode("utf-8").split("\0") if p)


def _markers_on(line: str) -> "list[tuple[str | None, str]]":
    """Every marker on one line, in order.

    All of them, not the first: a single-line passage that restates two
    clauses carries two tags, and stopping at the first would silently leave
    the second unchecked — the exact "well-formed but uninspected" shape this
    gate exists to close.
    """
    found: "list[tuple[str | None, str]]" = []
    for match in MARKER_RE.finditer(line):
        groups = match.groupdict()
        kind = groups.get("kind_html") or groups.get("kind_line")
        clause_id = groups.get("id_html") or groups.get("id_line")
        if clause_id is None:  # pragma: no cover - one id group always binds
            raise GateError("marker matched with no clause id")
        found.append((kind, clause_id))
    return found


def _strip_markers(line: str) -> str:
    return MARKER_RE.sub(" ", line)


def flatten(numbered: "list[tuple[int, str]]") -> "tuple[str, list[int]]":
    """Marker-stripped text with every whitespace run collapsed to one space.

    Prose wraps wherever the column limit falls, so a qualifier phrase is
    routinely split across a newline ("a defect this\\nchange is shipping").
    Matching the raw text would then miss the phrase and report a gap the
    surface does not have — a false positive that teaches authors to distrust
    the gate. Normalizing first makes a match independent of where the line
    happened to break.

    The parallel `origins` list maps each character of the normalized text
    back to the line it came from, so a finding still cites a real line.
    """
    parts: "list[str]" = []
    origins: "list[int]" = []
    for lineno, line in numbered:
        collapsed = re.sub(r"\s+", " ", _strip_markers(line)).strip()
        if not collapsed:
            continue
        if parts:
            parts.append(" ")
            origins.append(lineno)
        parts.append(collapsed)
        origins.extend([lineno] * len(collapsed))
    return "".join(parts), origins


def collect_spans(path: str, lines: "list[str]", known: "set[str]") -> "list[Span]":
    """Build every declared restatement span, or fail closed on a malformed one."""
    spans: "list[Span]" = []
    open_spans: "dict[str, int]" = {}
    for index, line in enumerate(lines, start=1):
        for kind, clause_id in _markers_on(line):
            if clause_id not in known:
                raise GateError(
                    f"{path}:{index}: marker names clause {clause_id!r}, which the registry "
                    "does not declare — a tag no clause backs is never checked"
                )
            if kind is None:
                spans.append(Span(clause_id=clause_id, start=index, end=index))
            elif kind == "-begin":
                if clause_id in open_spans:
                    raise GateError(
                        f"{path}:{index}: nested contract-restatement-begin for {clause_id!r} "
                        f"(already open at line {open_spans[clause_id]})"
                    )
                open_spans[clause_id] = index
            else:
                start = open_spans.pop(clause_id, None)
                if start is None:
                    raise GateError(
                        f"{path}:{index}: contract-restatement-end for {clause_id!r} with no "
                        "matching begin"
                    )
                spans.append(Span(clause_id=clause_id, start=start, end=index))
    if open_spans:
        clause_id, start = sorted(open_spans.items())[0]
        raise GateError(
            f"{path}:{start}: contract-restatement-begin for {clause_id!r} is never closed"
        )
    for span in spans:
        numbered = list(enumerate(lines[span.start - 1 : span.end], start=span.start))
        span.text, _ = flatten(numbered)
    return spans


def residual_chunks(lines: "list[str]", spans: "list[Span]") -> "list[tuple[str, list[int]]]":
    """Every contiguous run of lines covered by no span, normalized.

    Chunked rather than concatenated: a `restates` pattern spanning the seam
    between two non-adjacent runs would report a restatement that no passage
    actually makes.
    """
    covered: "set[int]" = set()
    for span in spans:
        covered.update(range(span.start, span.end + 1))
    chunks: "list[tuple[str, list[int]]]" = []
    current: "list[tuple[int, str]]" = []
    for index, line in enumerate(lines, start=1):
        if index in covered:
            if current:
                chunks.append(flatten(current))
                current = []
            continue
        current.append((index, line))
    if current:
        chunks.append(flatten(current))
    return [chunk for chunk in chunks if chunk[0]]


def check_clause(
    clause: Clause,
    path: str,
    text: str,
    lines: "list[str]",
    all_spans: "list[Span]",
    report: Report,
) -> None:
    spans = [s for s in all_spans if s.clause_id == clause.id]

    if path == clause.canonical:
        # The canonical surface OWNS the clause, and is held to the SAME
        # span-scoped standard as every copy: it declares where the clause
        # lives and must carry every qualifier inside those bounds. Checking
        # the canonical file-wide instead would reproduce the exact defect
        # this gate rejects everywhere else — a qualifier three sections away
        # clearing a passage that does not carry it.
        #
        # The one asymmetry, deliberate: the untagged-restatement check does
        # not run here. A canonical's other passages referring to its own
        # clause ARE the clause, not copies of it, so reporting them would
        # demand the owner tag every mention of what it owns.
        report.owned += 1
        if not spans:
            report.findings.append(
                Finding(
                    path=path,
                    clause=clause.id,
                    line=1,
                    kind="canonical-declares-no-span",
                    detail=(
                        f"the canonical surface for {clause.id} declares no "
                        "`contract-restatement` span, so there is nothing to measure "
                        "restatements against"
                    ),
                    remedy=(
                        f"wrap the passage that DEFINES {clause.id} in "
                        f"`<!-- contract-restatement-begin: {clause.id} -->` / `-end:`"
                    ),
                )
            )
            return
        for span in spans:
            for qualifier in clause.qualifiers:
                if not qualifier.pattern.search(span.text):
                    report.findings.append(
                        Finding(
                            path=path,
                            clause=clause.id,
                            line=span.start,
                            kind="canonical-missing-qualifier",
                            detail=f"the canonical passage no longer carries `{qualifier.name}`",
                            remedy=qualifier.hint,
                        )
                    )
        return

    if not clause.detect.search(text):
        return

    for span in spans:
        report.restatements += 1
        for qualifier in clause.qualifiers:
            if not qualifier.pattern.search(span.text):
                report.findings.append(
                    Finding(
                        path=path,
                        clause=clause.id,
                        line=span.start,
                        kind="missing-qualifier",
                        detail=(
                            f"this restatement omits `{qualifier.name}`, which the canonical "
                            f"({clause.canonical}) carries"
                        ),
                        remedy=qualifier.hint,
                    )
                )

    for chunk, origins in residual_chunks(lines, spans):
        match = clause.restates.search(chunk)
        if match is None:
            continue
        report.findings.append(
            Finding(
                path=path,
                clause=clause.id,
                line=origins[match.start()],
                kind="untagged-restatement",
                detail=(
                    "this passage restates the clause but declares no span, so its "
                    "qualifiers are never checked"
                ),
                remedy=(
                    f"either wrap it in `<!-- contract-restatement: {clause.id} -->` "
                    f"(one line) / `-begin:` + `-end:` (a block) and carry every qualifier, "
                    f"or reduce it to a pointer at {clause.canonical} — the pointer is the "
                    "stronger fix"
                ),
            )
        )

    if not spans:
        report.pointers += 1


def run(root: Path, registry_path: Path, excludes: "tuple[str, ...]") -> Report:
    clauses = load_registry(registry_path)
    known = {clause.id for clause in clauses}
    report = Report()

    for clause in clauses:
        canonical = root / clause.canonical
        if not canonical.is_file():
            raise GateError(
                f"clause {clause.id}: canonical surface {clause.canonical} does not exist"
            )

    for path in tracked_markdown(root):
        if any(path == e or path.startswith(e.rstrip("/") + "/") for e in excludes):
            continue
        if Path(path).name == "CHANGELOG.md":
            # A changelog records what changed; it is not an instruction
            # surface a lane reads to decide what to do.
            continue
        try:
            text = (root / path).read_text(encoding="utf-8")
        except OSError as exc:
            raise GateError(f"could not read {path}: {exc}") from exc
        lines = text.splitlines()
        flat_text, _ = flatten(list(enumerate(lines, start=1)))
        # Spans are collected ONCE per file against the full clause set: a
        # per-clause pass would see a sibling clause's marker as a tag no
        # clause backs and fail closed on a correctly tagged file.
        all_spans = collect_spans(path, lines, known)
        for clause in clauses:
            check_clause(clause, path, flat_text, lines, all_spans, report)

    return report


def main(argv: "list[str] | None" = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=None, help="repository root (default: this checkout)")
    parser.add_argument("--registry", default=None, help=f"clause registry (default: {DEFAULT_REGISTRY})")
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="repo-relative path or directory prefix to skip (repeatable)",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    registry_path = Path(args.registry) if args.registry else root / DEFAULT_REGISTRY

    try:
        report = run(root, registry_path, tuple(args.exclude))
    except GateError as exc:
        print(f"check-contract-clause-coverage: {exc}", file=sys.stderr)
        print(
            "Refusing to report a result the gate could not actually compute.",
            file=sys.stderr,
        )
        return 2

    if report.findings:
        print(
            f"Contract-clause coverage gate FAILED — {len(report.findings)} gap(s):",
            file=sys.stderr,
        )
        for finding in sorted(report.findings, key=lambda f: (f.path, f.line, f.clause)):
            print("", file=sys.stderr)
            print(f"  {finding.path}:{finding.line}  [{finding.clause}] {finding.kind}", file=sys.stderr)
            print(f"    {finding.detail}", file=sys.stderr)
            print(f"    fix: {finding.remedy}", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "A restatement that drops a qualifier instructs a lane to do what another "
            "surface forbids, and every surface stays individually well-formed — which is "
            "why this is a gate and not a review checklist (#1659).",
            file=sys.stderr,
        )
        return 1

    print(
        "Contract-clause coverage gate passed — "
        f"{report.owned} canonical surface(s), {report.restatements} tagged restatement(s), "
        f"{report.pointers} surface(s) that point rather than restate."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
