#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

USAGE = """\
Judge the comments a change adds against a comment posture.

Reads NUL-separated repository paths on stdin. Each path's text is <root>/<path>, and
<ranges> holds the added lines as <path>TAB<first>TAB<last> rows. A comment token of
the pygments lexer for the path's name (for a shell script, a comment by POSIX and Bash
token rules, comment-census.py's tokens), on an added line, passes when it is one of the
allowed shapes or an extended regular expression in <allow> (one per line, matched with
grep -E) matches its text; every other one prints
  <path>:<line>: comment outside the <posture> posture: ...
on stdout. A path with no lexer is skipped with one notice on stderr.

A path the comment reader fails on is named on stderr and not judged; the others still are.

Exit: 0 judged; 2 usage; 3 pygments is not importable; 4 grep -E rejected an allow pattern;
5 every other path judged, findings printed, but at least one path not judged.
"""

MESSAGE = (
    "comment outside the {} posture: delete it, move the reason into the code or the commit "
    "message, or link the outside constraint; /code-tidying:remove-comments fixes it"
)

DIRECTIVE = re.compile(
    r"""
    \bnoqa\b | \btype:\s*ignore\b | \bpyright:\s*\w | \bpylint:\s*(?:disable|enable|skip-file)
    | \bmypy:\s*\w | \bpragma:\s*no\s*(?:cover|branch) | \bfmt:\s*(?:off|on|skip)\b | \bisort:\s*\w
    | \bruff:\s*(?:noqa|isort) | \bnosec\b | \bnosemgrep\b | \bgitleaks:allow\b
    | \bshellcheck\s+(?:disable|enable|source|shell|external-sources)=
    | \beslint(?:-disable|-enable)?(?:-next-line|-line)?\b(?=[\s:*]|$) | /\*\s*globals?\s[^*]*\*/
    | \bclang-format\s+(?:off|on)\b | \bcppcheck-suppress\b | \bluacheck:\s*\w | \bstylua:\s*ignore
    | ---@diagnostic\b | \bpragma:\s*allowlist\s+secret\b | \bpyre-(?:ignore|fixme)\b
    | ^\s*\#\s*typed:\s*\w | ^\s*\#:schema\s
    | @ts-(?:ignore|expect-error|nocheck|check)\b | \bprettier-ignore\b | \bbiome-ignore\b
    | \b(?:istanbul|c8|v8)\s+ignore\b | \bdeno-lint-ignore | \bNOLINT | //\s*nolint\b | \bnolint:
    | \brubocop:(?:disable|enable|todo)\b | \bStryker\s+(?:disable|restore)\b | \bNOSONAR\b
    | \bmarkdownlint-(?:disable|enable|capture|restore) | \bspellchecker:\s*(?:on|off|disable)
    | \bcspell:\s*\w | \btypos:\s*(?:on|off|ignore) | \bcodespell:\s*ignore | \bzizmor:\s*ignore
    | \bhadolint\s+ignore= | \byamllint\s+(?:disable|enable) | \bcheckov:skip= | \btfsec:ignore
    | \btrivy:ignore | \bdotnet_diagnostic | \bReSharper\s+(?:disable|restore)\b | \bnoinspection\b
    | \b@formatter:(?:off|on)\b | \blgtm\b | \bcoverage:\s*ignore
    | ^\s*//go:\w | ^\s*//\s*\+build\b | ^\s*//line\s | ^\s*/// <reference\b
    | ^\s*(?:\#|//|--|/\*)\s*\#?(?:end)?region\b | <editor-fold\b | </editor-fold> | \{\{\{\d*\s*$ | \}\}\}\d*\s*$
    | (?:^|\s)(?:vim?|ex):\s*(?:set?\s|[a-z]+=) | -\*-.*-\*- | \bLocal\s+Variables:
    | \byaml-language-server:\s*\$schema= | \bfrozen_string_literal:\s*(?:true|false) | ^\s*\#\s*syntax=
    """,
    re.VERBOSE,
)
COOKIE = re.compile(r"^[ \t\f]*#.*?coding[:=][ \t]*[-\w.]+")
LICENSE = re.compile(
    r"\bcopyright\b|\bSPDX-License-Identifier\b|\blicen[sc]ed\s+under\b|\ball\s+rights\s+reserved\b|©"
    r"|@license\b|\(c\)\s*\d{4}|\bpermission\s+is\s+hereby\s+granted\b"
    r"|\b(?:GNU\s+(?:Lesser\s+|Affero\s+)?General\s+Public|Apache|MIT|BSD|Mozilla\s+Public)\s+License\b",
    re.IGNORECASE,
)
TRACKED = re.compile(r"\b(?:TODO|FIXME)\((?:[\w.-]+/[\w.-]+)?#\d+\)")
TODO = re.compile(r"\bTODO\((?:[\w.-]+/[\w.-]+)?#\d+\)")
FIXME = re.compile(r"\bFIXME\((?:[\w.-]+/[\w.-]+)?#\d+\)")
PINNED_SHA = re.compile(
    r"^\s*(?:-\s+)?(?:uses:\s*[\"']?[^\s\"'#]+@|ref:\s*[\"']?)[0-9a-fA-F]{40}[\"']?\s*$"
)
IGNORE = "remove-comments-ignore"
DISSOLVE = "dissolve-comments-ignore"
LINK = re.compile(r"https?://\S|\bRFC[\s-]?\d+", re.IGNORECASE)
EXIT_HEADING = re.compile(r"^#+\s*(?:exit(?:\s+codes)?|exits)\s*:?(?:\s+(\d).*)?$", re.IGNORECASE)
EXIT_ENTRY = re.compile(r"^#+\s+\d+\b[^\w\n]*\w")
HASH_INDENT = re.compile(r"^#+(\s*)")
PS_HELP = re.compile(
    r"^\s*(?:#\s*)?\.(?:SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK|COMPONENT"
    r"|ROLE|FUNCTIONALITY|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE|EXTERNALHELP)\b",
    re.IGNORECASE,
)
PS_REQUIRES = re.compile(r"^\s*#Requires\s+-", re.IGNORECASE)
PS_SIGNATURE = re.compile(r"^\s*# SIG # ")
GO_EXPORTED = re.compile(r"^(?:func\s+(?:\([^)]*\)\s*)?|type\s+|var\s+|const\s+)[A-Z]")
GO_GROUP = re.compile(
    r"^\s*(?:type\s+\w+(?:\[[^\]]*\])?\s+(?:struct|interface)\s*\{|(?:const|var|type)\s*\()\s*$"
)
GO_MEMBER = re.compile(r"^\s+[A-Z]")
TYPESCRIPT_SUFFIXES = (".mts", ".cts")
CODE_WAIVER = re.compile(
    r"@SuppressWarnings\b|@Suppress\(|\bSuppressMessage(?:Attribute)?\b|#\s*pragma\s+warning\b"
    r"|\[Diagnostics\.CodeAnalysis\.|\bExcludeFromCodeCoverage\b"
)


def _census():
    here = Path(__file__).resolve().parent
    for candidate in (
        here / "comment-census.py",
        here.parent / "scripts" / "comment-census.py",
    ):
        if candidate.is_file():
            spec = importlib.util.spec_from_file_location("comment_census", candidate)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    raise FileNotFoundError(
        "comment-census.py is neither beside comment-lint.py nor at ../scripts"
    )


_CENSUS = _census()


def _is_comment(tok) -> bool:
    from pygments.token import Comment

    return (
        _CENSUS.is_comment_token(tok)
        and tok not in Comment.Preproc
        and tok not in Comment.PreprocFile
    )


def _lex(path: str, text: str):
    from pygments.lexers import get_lexer_by_name, get_lexer_for_filename
    from pygments.util import ClassNotFound

    try:
        lexer = get_lexer_for_filename(path, stripnl=False)
    except ClassNotFound:
        if not path.lower().endswith(TYPESCRIPT_SUFFIXES):
            return None, None
        lexer = get_lexer_by_name("typescript", stripnl=False)
    return lexer, _CENSUS.tokens(text, lexer)


class _Line:
    __slots__ = ("comment", "code", "covered", "doc")

    def __init__(self):
        self.comment = ""
        self.code = False
        self.covered = False
        self.doc = False


def _layout(tokens, count: int) -> list[_Line]:
    from pygments.token import String

    lines = [_Line() for _ in range(count + 2)]
    line = 1
    for tok, text in tokens:
        parts = text.split("\n")
        comment = _is_comment(tok)
        doc = tok in String.Doc or (
            comment and text.lstrip().startswith(("/**", "///", "//!"))
        )
        for i, part in enumerate(parts):
            n = line + i
            if n >= len(lines):
                break
            if comment and i and i == len(parts) - 1 and not part:
                continue
            if comment:
                lines[n].covered = True
                lines[n].doc |= doc
                if part.strip():
                    lines[n].comment = (lines[n].comment + " " + part.strip()).strip()
            elif part.strip():
                lines[n].code = True
        line += len(parts) - 1
    return lines


def _runs(lines: list[_Line]) -> dict[int, list[int]]:
    run_of: dict[int, list[int]] = {}
    current: list[int] = []
    for n in range(1, len(lines)):
        ln = lines[n]
        if ln.covered and not ln.code:
            current.append(n)
            run_of[n] = current
            continue
        current = []
        if ln.covered:
            run_of[n] = [n]
    return run_of


def _paragraphs(
    lines: list[_Line], run_of: dict[int, list[int]]
) -> dict[int, list[int]]:
    block_of: dict[int, list[int]] = {}
    current: list[int] = []
    last = 0
    for n in range(1, len(lines)):
        run = run_of.get(n)
        if run is None or lines[n].code:
            continue
        if n == run[0] and not (current and n - last == 2 and not lines[n - 1].code):
            current = []
        current.append(n)
        block_of[n] = current
        last = n
    return block_of


def _has_prose(line: _Line) -> bool:
    return bool(line.comment.strip("*/ \t"))


def _link_span(n: int, run: list[int], lines: list[_Line]) -> list[int]:
    if n not in run or not _has_prose(lines[n]):
        return run
    low = high = run.index(n)
    while low > 0 and _has_prose(lines[run[low - 1]]):
        low -= 1
    while high < len(run) - 1 and _has_prose(lines[run[high + 1]]):
        high += 1
    return run[low : high + 1]


def _passes(n, lines, run_of, block_of, source, posture, lexer_name) -> bool:
    ln = lines[n]
    text = ln.comment
    run = run_of.get(n, [n])
    run_text = [lines[m].comment for m in run]
    if any(LICENSE.search(lines[m].comment) for m in block_of.get(n, [])):
        return True
    src = source[n - 1] if n - 1 < len(source) else ""
    nxt = source[n] if n < len(source) else ""

    if n == 1 and text.startswith("#!"):
        return True
    if n <= 2 and COOKIE.match(text):
        return True
    if DIRECTIVE.search(text):
        return True
    if any(LICENSE.search(t) for t in run_text):
        return True
    if TRACKED.search(text) or (TRACKED.search(run_text[0]) and not ln.code):
        return True
    if ln.code and PINNED_SHA.match(_code_part(src, text)):
        return True
    if IGNORE in text or DISSOLVE in text:
        return True
    if ln.doc:
        return True
    if lexer_name == "PowerShell" and any(PS_HELP.match(t) for t in run_text):
        return True
    if lexer_name == "Go" and not ln.code and _go_doc(run, source):
        return True
    if posture == "necessary" and any(
        LINK.search(lines[m].comment) for m in _link_span(n, run, lines)
    ):
        return True
    if posture == "necessary" and n in _exit_doc(_header(lines, run_of, source), lines):
        return True
    prev = lines[n - 1].comment if n > 1 else ""
    if IGNORE in prev or DISSOLVE in prev:
        return True
    if lexer_name == "PowerShell" and (
        PS_REQUIRES.match(text) or any(PS_SIGNATURE.match(t) for t in run_text)
    ):
        return True
    if ln.code and CODE_WAIVER.search(src):
        return True
    following = lines[n + 1].comment if n + 1 < len(lines) else ""
    return bool(DIRECTIVE.search(following) or CODE_WAIVER.search(nxt))


def _header(lines: list[_Line], run_of: dict[int, list[int]], source: list[str]) -> list[int]:
    start = 2 if source and source[0].startswith("#!") else 1
    while start <= len(source) and not source[start - 1].strip():
        start += 1
    if start >= len(lines) or lines[start].code or not lines[start].covered:
        return []
    return run_of.get(start, [])


def _hash_indent(comment: str) -> int:
    match = HASH_INDENT.match(comment)
    return len(match.group(1)) if match else -1


def _exit_doc(header: list[int], lines: list[_Line]) -> set[int]:
    passing: set[int] = set()
    listing, entry_indent = False, None
    for m in header:
        text = lines[m].comment
        heading = EXIT_HEADING.match(text)
        if heading:
            listing = True
            entry_indent = None
            if heading.group(1):
                entry_indent = heading.start(1) - (len(text) - len(text.lstrip("#")))
        elif listing and EXIT_ENTRY.match(text):
            entry_indent = _hash_indent(text)
        elif not (
            listing and entry_indent is not None and _hash_indent(text) > entry_indent
        ):
            listing = False
            continue
        passing.add(m)
    return passing


def _code_part(src: str, comment: str) -> str:
    code = src.rstrip()
    return code[: -len(comment)] if comment and code.endswith(comment) else code


def _go_doc(run: list[int], source: list[str]) -> bool:
    after = run[-1]
    if after >= len(source):
        return False
    member = source[after]
    if GO_EXPORTED.match(member):
        return True
    if not GO_MEMBER.match(member):
        return False
    indent = len(member) - len(member.lstrip())
    for m in range(run[0] - 2, -1, -1):
        line = source[m]
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            return bool(GO_GROUP.match(line))
    return False


def _inside_word(src: str, comment: str) -> bool:
    at = src.find(comment)
    return at > 0 and not src[at - 1].isspace()


def _allowed(texts: list[str], allow: list[str]) -> set[int]:
    if not allow or not texts:
        return set()
    args = ["grep", "-E", "-n"]
    for pattern in allow:
        args += ["-e", pattern]
    proc = subprocess.run(
        args, input="\n".join(texts) + "\n", capture_output=True, text=True, check=False
    )
    if proc.returncode > 1:
        raise ValueError(
            proc.stderr.strip() or "grep -E exited " + str(proc.returncode)
        )
    return {int(row.split(":", 1)[0]) - 1 for row in proc.stdout.splitlines() if row}


def findings(path: str, text: str, added, posture: str, allow: list[str]):
    """The finding lines for the comments on <added> lines of <path>; None when no lexer reads it."""
    lexer, tokens = _lex(path, text)
    if lexer is None:
        return None
    source = text.split("\n")
    lines = _layout(tokens, len(source))
    run_of = _runs(lines)
    block_of = _paragraphs(lines, run_of)
    candidates = []
    for first, last in added:
        for n in range(max(first, 1), min(last, len(lines) - 1) + 1):
            if not lines[n].comment:
                continue
            if lexer.name == "PowerShell" and _inside_word(
                source[n - 1] if n - 1 < len(source) else "", lines[n].comment
            ):
                continue
            if not _passes(n, lines, run_of, block_of, source, posture, lexer.name):
                candidates.append(n)
    candidates = sorted(set(candidates))
    kept = _allowed([lines[n].comment for n in candidates], allow)
    return [
        f"{path}:{n}: {MESSAGE.format(posture)}"
        for i, n in enumerate(candidates)
        if i not in kept
    ]


def _ranges(path: Path) -> dict[str, list[tuple[int, int]]]:
    out: dict[str, list[tuple[int, int]]] = {}
    for row in path.read_text(encoding="utf-8", errors="surrogateescape").splitlines():
        parts = row.split("\t")
        if len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
            out.setdefault(parts[0], []).append((int(parts[1]), int(parts[2])))
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="comment-lint.py",
        description=USAGE,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--posture", required=True, choices=("necessary", "none"))
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--ranges", required=True, type=Path)
    parser.add_argument("--allow", type=Path)
    args = parser.parse_args(argv)
    try:
        import pygments  # noqa: F401
    except ImportError:
        print(
            "comment-lint: pygments is not importable by " + sys.executable,
            file=sys.stderr,
        )
        return 3
    allow = []
    if args.allow:
        allow = [p for p in args.allow.read_text(encoding="utf-8").splitlines() if p]
    ranges = _ranges(args.ranges)
    paths = [
        p
        for p in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0")
        if p
    ]
    out, unjudged = [], False
    for path in paths:
        text = (args.root / path).read_text(encoding="utf-8", errors="replace")
        try:
            got = findings(path, text, ranges.get(path, []), args.posture, allow)
        except ValueError as err:
            print(
                f"comment-lint: grep -E rejected a comment_lint_allow pattern: {err}",
                file=sys.stderr,
            )
            return 4
        except Exception as err:  # noqa: BLE001 - one unreadable file must not drop the others' findings
            print(
                f"comment-lint: {path}: not judged, the comment reader failed: {err}",
                file=sys.stderr,
            )
            unjudged = True
            continue
        if got is None:
            print(
                f"comment-lint: {path}: no pygments lexer for this name, skipped",
                file=sys.stderr,
            )
            continue
        out.extend(got)
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 5 if unjudged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
