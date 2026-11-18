#!/usr/bin/env python3
"""Check that a line naming a claim cites it, keeps its label and, in a sidecar, quotes it.

Reads the claims: list in the front matter of every <slice>/RESEARCH-*.md
sidecar (no recursion into sub-slices), with check-source-applicability.py's
parser, and collects each claim's id: and confidence:. A claim at
HIGH (single source), MEDIUM or LOW is a labeled claim. Then it reads every
line of <slice>/RESEARCH.md and of each sidecar, outside a sidecar's claims:
block, and finds each labeled claim's ID on it. The line must carry that
claim's confidence label verbatim. A summary line, a Settled or handoff
bullet, a table row and a sidecar abstract are each one line here, so a
restatement that dropped its label is caught wherever it sits. A plain HIGH
claim needs no label, and a claim with no id: is not looked for.

A line of RESEARCH.md that names any claim's ID must not also carry a sweep
word (every, all, none, only, any case): the index points at claims, and a
sweep word on a pointer line widens the claim it names.

A sidecar line that names a claim's ID, outside the claims: block, must quote
that claim's text verbatim, in one form: the ID, its label in parentheses when
the line puts it there, a colon, and the claim: text in double quotes, as in
M1 (HIGH (single source)): "<claim>". The quote must match the claim: value
byte for byte, so a sidecar line that drops a condition or turns "prefer" into
a rule fails here, though it carries no sweep word and keeps its label. A
quote in that form on any line read, index included, must match its claim. A
header line whose value is a quoted YAML scalar is read as its unquoted value,
so a sidecar abstract can carry a quote. Words inside a matching quote are the
claim's own: they neither cite an ID nor count as a sweep word.

A sidecar that declares a claim with an id: must quote one of its own claims,
in that form, in its abstract: an abstract that names no ID escapes every
rule above. The index mirrors each such abstract on one body line,
- <section>: <abstract>, where <section> is the sidecar's filename between
RESEARCH- and .md, and on at least one line with that prefix the text after it
must equal the sidecar's unquoted abstract: value byte for byte. A table row or a lead-in that names
no ID is not graded here: the verifier grades it.

Lines under a heading that names the fetch log are skipped, down to the next
heading at the same or a higher level: the fetch log keys its rows by claim
and restates nothing.

--sub-slice <dir>, repeatable, is for a slice-root synthesis that cites its
sub-slices' claims by ID. The claims declared in each named sub-slice's
sidecars (again no recursion) join the root's own, so a root line that points
at a sub-slice claim must carry that claim's label, and a root index line that
names one must carry no sweep word. Only the root's RESEARCH.md and the root's
own sidecars are read for lines; each sub-slice was graded on its own before
synthesis. With --sub-slice the root needs no sidecar of its own, and each
named sub-slice must hold at least one.

Each sub-slice's IDs are namespaced by its directory name, since its
researcher numbered them without seeing the others: two sub-slices may each
declare X1. A root line may cite <sub-slice name>/X1, graded against that one
sub-slice's claim, or the bare X1, which names every claim declaring it, so
the line must carry each one's label and a quote of it may quote any of them.
An ID declared twice in one sub-slice, or declared in a sub-slice and the
root, stays ungradeable like any duplicate, as do two sub-slices that share a
directory name.

Rule: skills/research/context/artifact-shape.md, "Restatements cite; they do
not restate". The researcher runs this check before hand-back and fixes every
line it reports; the research parent re-runs it in the acceptance gate.

Exit 0 = every line naming a labeled claim carries its label, no index line
         naming a claim carries a sweep word, every sidecar line naming a
         claim quotes it verbatim, and every claim-bearing sidecar's abstract
         quotes one of its claims and is mirrored verbatim (status=pass)
Exit 1 = at least one violation (status=fail), each on stderr as
         <file>:<line>: <id> (<label>) appears without its label
         <file>:<line>: <id>[, <id>...] cited beside the sweep word "<word>"
         <file>:<line>: <id> cited without its claim quoted verbatim
         <file>:<line>: <id> quote does not match its claim
         <sidecar>:<line>: abstract quotes none of its claims
         <index>:<line>: abstract line differs from <sidecar name>'s abstract
         <index>: no "- <section>: " abstract line for <sidecar name>
Exit 2 = ungradeable, FAIL CLOSED: missing slice or sub-slice dir, no
         RESEARCH.md, no sidecar (at the root without --sub-slice, or in a
         named sub-slice), a sidecar header the parser cannot read, an id:
         that is not a claim ID, a claim with an id: and no claim: text, one
         ID declared twice at the root or in one sub-slice, a root ID a
         sub-slice also declares, two sub-slices sharing a directory name,
         an unreadable or non-UTF-8 file, a parser that cannot be loaded, or a
         usage error (status=ungradeable)

Usage:
  python3 check-restatement-labels.py <slice-dir>
  python3 check-restatement-labels.py <slice-root> --sub-slice <dir> [--sub-slice <dir>]...
  python3 check-restatement-labels.py --help
"""

from __future__ import annotations

import fnmatch
import importlib.util
import re
import sys
from pathlib import Path

USAGE = (
    __doc__
    + """
Claim ID grammar: one or more capital letters, an optional hyphen, digits, and
an optional lowercase letter: M1, K9, CI-02, S2a. IDs are unique across the
slice; with --sub-slice, within each sub-slice and against the root. An ID
matches on a line only as a whole token: M1 is not found in M10, and S2 is not
found in S2a.

Output (stdout, one line):
  status=pass ids=<n> labeled=<n> mentions=<n> quoted=<n>
  status=fail violations=<n> ids=<n> labeled=<n> mentions=<n> quoted=<n>
  status=ungradeable
"""
)

LABELS = ("HIGH (single source)", "MEDIUM", "LOW")
CLAIM_ID = re.compile(r"^[A-Z]+-?[0-9]+[a-z]?$")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*)$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
FETCH_LOG = re.compile(r"\bfetch log\b", re.IGNORECASE)
LABEL_ON_LINE = {
    label: re.compile(r"(?<![A-Za-z])" + re.escape(label) + r"(?![A-Za-z])")
    for label in LABELS
}
SWEEP = re.compile(r"(?<![A-Za-z])(?:every|all|none|only)(?![A-Za-z])", re.IGNORECASE)
QUOTE_LABEL = r"(?: \((?:HIGH \(single source\)|HIGH|MEDIUM|LOW)\))?"


def id_pattern(ids) -> re.Pattern:
    """Match any of ids as a whole token, longest first."""
    alternatives = "|".join(map(re.escape, sorted(ids, key=len, reverse=True)))
    return re.compile(r"(?<![A-Za-z0-9_])(" + alternatives + r")(?![A-Za-z0-9_])")


def quote_pattern(ids) -> re.Pattern:
    """Match the opening of a quote, <id>[ (<label>)]: ", up to its first quote mark."""
    return re.compile(id_pattern(ids).pattern + QUOTE_LABEL + r': "')


def header_value(csa, line: str) -> str:
    """A front-matter line, its value unquoted when it is a quoted YAML scalar."""
    found = csa.KEY.match(line)
    if not found or not found.group(2) or found.group(2).strip()[:1] not in ("'", '"'):
        return line
    return f"{found.group(1)}: {csa.scalar(found.group(2))}"


def load_parser():
    """Load check-source-applicability.py, the one sidecar-header parser."""
    path = Path(__file__).resolve().with_name("check-source-applicability.py")
    spec = importlib.util.spec_from_file_location("check_source_applicability", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def claims_block(csa, lines: list[str]) -> range:
    """Front-matter indexes of the claims: block, by the parser's own stop rule."""
    found = csa.top_level(lines, "claims", "front matter")
    if found is None:
        return range(0)
    start = found[0]
    end = start + 1
    while end < len(lines):
        body = lines[end].strip()
        if (
            body
            and not body.startswith("#")
            and csa.indent(lines[end]) == 0
            and not csa.DASH.match(body)
        ):
            break
        end += 1
    return range(start, end)


def body_start(lines: list[str]) -> int:
    """Index of the first line after the front matter, or 0 when there is none."""
    if not lines or lines[0].rstrip() != "---":
        return 0
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return i + 1
    return len(lines)


def sidecars_in(directory: Path) -> list[Path]:
    """The RESEARCH-*.md sidecars directly in directory, sorted."""
    # fnmatchcase, not glob: pathlib's glob is case-insensitive on Windows and
    # would take the lowercase research-checklist.md ledger for a sidecar.
    return sorted(
        p
        for p in directory.iterdir()
        if fnmatch.fnmatchcase(p.name, "RESEARCH-*.md") and p.is_file()
    )


def abstract_violations(csa, index: Path, sidecars, headers, declared, opener) -> list[str]:
    """Each sidecar declaring an id'd claim quotes one in its abstract, mirrored verbatim."""
    lines = csa.read_text(index).splitlines()
    start = body_start(lines)
    body = list(enumerate(lines[start:], start=start + 1))
    violations: list[str] = []
    for sidecar in sidecars:
        own = {cid for cid, where in declared.items() if where == sidecar}
        if not own:
            continue
        entry = csa.top_level(headers[sidecar], "abstract", f"{sidecar}: front matter")
        value = csa.scalar(entry[1]) if entry else None
        # Front-matter index j is file line j + 2: line 1 is the opening ---.
        line_no = entry[0] + 2 if entry else 1
        if not value or not any(m.group(1) in own for m in opener.finditer(value)):
            violations.append(f"{sidecar}:{line_no}: abstract quotes none of its claims")
        if not value:
            continue
        key = f"- {sidecar.name.removeprefix('RESEARCH-').removesuffix('.md')}: "
        mirrors = [(n, line) for n, line in body if line.startswith(key)]
        if not mirrors:
            violations.append(f'{index}: no "{key}" abstract line for {sidecar.name}')
        # Another bullet may open with the same prefix, so one exact copy suffices.
        if any(line[len(key) :] == value for _, line in mirrors):
            continue
        violations.extend(
            f"{index}:{n}: abstract line differs from {sidecar.name}'s abstract"
            for n, _ in mirrors
        )
    return violations


def grade(csa, slice_dir: Path, sub_slices: list[Path] | None = None) -> tuple[int, str]:
    """Grade the slice's lines against the claims it and its sub-slices declare.

    A sub-slice's sidecars declare claims only: their lines were graded in the
    sub-slice's own run, so only the root's files are read for lines. A root claim
    is keyed by its bare ID and a sub-slice claim by <sub-slice name>/<id>, so two
    sub-slices may each declare X1. A root claim and a sub-slice claim sharing a
    bare ID leave a root pointer unable to tell its own claim from the other, so
    that is ungradeable.

    A token on a line is a bare ID or a qualified one, and keys_of resolves it to
    keys. A bare ID names every claim declaring it, so the line carries each one's
    label, and its quote may match either claim; a qualified ID names its one
    claim. A matching quote's words are the claim's own, so they are blanked
    before IDs and sweep words are looked for, and ID tokens are blanked before
    the sweep search so a sub-slice name such as all-hooks is no sweep word.
    """
    sub_slices = sub_slices or []
    if not slice_dir.is_dir():
        raise csa.Ungradeable(f"slice directory not found: {slice_dir}")
    index = slice_dir / "RESEARCH.md"
    if not index.is_file():
        raise csa.Ungradeable(f"no index: {index}")
    sidecars = sidecars_in(slice_dir)
    if not sidecars and not sub_slices:
        raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in {slice_dir}")
    declaring = list(sidecars)
    namespace = {sidecar: "" for sidecar in sidecars}
    names: set[str] = set()
    for sub in sub_slices:
        if not sub.is_dir():
            raise csa.Ungradeable(f"sub-slice directory not found: {sub}")
        found = sidecars_in(sub)
        if not found:
            raise csa.Ungradeable(f"no RESEARCH-*.md sidecar in sub-slice {sub}")
        name = sub.resolve().name
        if not name or name in names:
            raise csa.Ungradeable(
                f"sub-slice {sub}: directory name {name!r} is empty or already used"
            )
        names.add(name)
        declaring.extend(found)
        namespace.update(dict.fromkeys(found, name))

    declared: dict[str, Path] = {}
    texts: dict[str, str] = {}
    labeled: dict[str, str] = {}
    keys_of: dict[str, list[str]] = {}
    skip: dict[Path, range] = {}
    headers: dict[Path, list[str]] = {}
    for sidecar in declaring:
        header = csa.front_matter(sidecar, required=True)
        headers[sidecar] = header
        claims = csa.parse_claims(sidecar, header)
        skip[sidecar] = claims_block(csa, header)
        for c_no, claim in enumerate(claims, start=1):
            if "id" not in claim:
                continue
            cid = claim["id"]
            if cid is None or not CLAIM_ID.match(cid):
                raise csa.Ungradeable(
                    f"{sidecar}: claim {c_no}: id is not a claim ID: {cid}"
                )
            name = namespace[sidecar]
            key = f"{name}/{cid}" if name else cid
            clash = key if key in declared else None
            if clash is None:
                owners = keys_of.get(cid, [])
                clash = next((k for k in owners if not name or "/" not in k), None)
            if clash is not None:
                raise csa.Ungradeable(
                    f"{sidecar}: claim {c_no}: id {cid} is already declared in {declared[clash]}"
                )
            if not claim.get("claim"):
                raise csa.Ungradeable(f"{sidecar}: claim {c_no}: id {cid} has no claim: text")
            declared[key] = sidecar
            texts[key] = claim["claim"]
            if claim.get("confidence") in LABELS:
                labeled[key] = claim["confidence"]
            keys_of.setdefault(cid, []).append(key)
            if name:
                keys_of[key] = [key]

    violations: list[str] = []
    mentions = quoted = 0
    if declared:
        pattern = id_pattern(keys_of)
        opener = quote_pattern(keys_of)
        for path in [index, *sidecars]:
            lines = csa.read_text(path).splitlines()
            block = skip.get(path, range(0))
            start = body_start(lines)
            fence: str | None = None
            fetch_level = 0
            for i, line in enumerate(lines):
                if i - 1 in block:
                    continue
                if i >= start:
                    fence_mark = FENCE.match(line)
                    heading = HEADING.match(line) if fence is None else None
                    if fence_mark:
                        if fence is None:
                            fence = fence_mark.group(1)
                        elif line.strip().startswith(fence):
                            fence = None
                    elif heading:
                        level = len(heading.group(1))
                        if fetch_level and level <= fetch_level:
                            fetch_level = 0
                        if not fetch_level and FETCH_LOG.search(heading.group(2)):
                            fetch_level = level
                if fetch_level:
                    continue
                text = header_value(csa, line) if i < start else line
                outside = text
                matched: set[str] = set()
                mismatched: set[str] = set()
                for found in opener.finditer(text):
                    token = found.group(1)
                    wants = (texts[key] + '"' for key in keys_of[token])
                    want = next((w for w in wants if text.startswith(w, found.end())), None)
                    if want is not None:
                        matched.add(token)
                        quoted += 1
                        end = found.end() + len(want) - 1
                        outside = outside[: found.end()] + " " * (end - found.end()) + outside[end:]
                    elif token not in mismatched:
                        mismatched.add(token)
                        violations.append(f"{path}:{i + 1}: {token} quote does not match its claim")
                cited = sorted({m.group(1) for m in pattern.finditer(outside)})
                tokens_blanked = pattern.sub(lambda m: " " * len(m.group(0)), outside)
                sweep = SWEEP.search(tokens_blanked) if path == index and cited else None
                if sweep:
                    violations.append(
                        f"{path}:{i + 1}: {', '.join(cited)} cited beside the sweep word "
                        f'"{sweep.group(0)}"'
                    )
                checked: set[str] = set()
                for token in cited:
                    if path != index and token not in matched and token not in mismatched:
                        violations.append(
                            f"{path}:{i + 1}: {token} cited without its claim quoted verbatim"
                        )
                    keys = keys_of[token]
                    for key in keys:
                        if key in checked or key not in labeled:
                            continue
                        checked.add(key)
                        mentions += 1
                        label = labeled[key]
                        if not LABEL_ON_LINE[label].search(outside):
                            shown = token if len(keys) == 1 else key
                            violations.append(
                                f"{path}:{i + 1}: {shown} ({label}) appears without its label"
                            )
        violations.extend(abstract_violations(csa, index, sidecars, headers, declared, opener))

    counts = (
        f"ids={len(declared)} labeled={len(labeled)} mentions={mentions} quoted={quoted}"
    )
    for line in violations:
        print(line, file=sys.stderr)
    if violations:
        return 1, f"status=fail violations={len(violations)} {counts}"
    return 0, f"status=pass {counts}"


def main(argv: list[str]) -> int:
    slice_arg: str | None = None
    sub_args: list[str] = []
    usage_error: str | None = None
    args = iter(argv[1:])
    for arg in args:
        if arg in ("--help", "-h"):
            print(USAGE, end="")
            return 0
        if arg == "--sub-slice":
            value = next(args, None)
            if value is None or value.startswith("-"):
                usage_error = "--sub-slice needs a directory"
                break
            sub_args.append(value)
        elif arg.startswith("-"):
            usage_error = f"unknown argument: {arg}"
        elif slice_arg is not None:
            usage_error = f"expected exactly one slice directory, got a second: {arg}"
        else:
            slice_arg = arg
    if usage_error is None and slice_arg is None:
        usage_error = "a slice directory is required"
    if usage_error is not None:
        print(f"error: {usage_error}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    try:
        csa = load_parser()
    except (ImportError, OSError, SyntaxError) as exc:
        print(f"error: cannot load the header parser: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    try:
        code, summary = grade(csa, Path(slice_arg), [Path(s) for s in sub_args])
    except csa.Ungradeable as exc:
        print(f"error: {exc}", file=sys.stderr)
        print("status=ungradeable")
        return 2
    print(summary)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
