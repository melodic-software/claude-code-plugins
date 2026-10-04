"""Find lint and type-checker suppressions in source files and say which carry a reason.

Usage:
  suppression-scan.py [options] [--] [<path>...]

With no option the output is a JSON array, one object per suppression, sorted
by file then line: `file`, `line`, `tool`, `rules` (the rule ids the line
names), `justified` and `reason` (the reason text, or null).

A suppression is justified when its line carries a reason and, for a tool
whose syntax can name a rule, at least one rule id. TypeScript's directives
cannot name an error, so a reason alone justifies them. Where the tool has no
reason slot of its own (TypeScript, markdownlint, Java annotations, and most
comment pragmas), a further comment on the same line is the reason.

Options:
  --diff <base>              report only lines that `git diff <base>...HEAD` adds,
                             read from HEAD; renames are followed, so a renamed
                             file's existing lines are not reported
  --count                    print `suppressions=<n>` and `unjustified=<n>`
                             (plus `correctness=<n>` with --correctness-rules)
                             instead of the JSON array
  --correctness-rules <file> one rule id per line (`#` comments and blank lines
                             ignored); each record gains `correctness`, true when
                             it names a listed rule (compared case-insensitively)
  --paths-from <file>        read paths from <file>, one per line, in addition
                             to any on the command line
  --help                     print this text

Paths: a file is scanned; a directory is expanded through `git ls-files`
(tracked plus untracked files that are not ignored) inside a repository, or
walked outside one. With no path, the whole repository is scanned, or the
working directory outside one. Under --diff, paths only narrow the changed
files. Inside a repository every reported path is relative to its top level.

The scanner is read-only: it reads git and the files it is given, and nothing
else. A file name is only ever passed to git as one argument after `--`, with
pathspec magic turned off.

Exit 0 on success; 2 for a usage error or an input that cannot be read, with
nothing printed on stdout.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

MIN_PYTHON = (3, 11)

# ---- file kinds -------------------------------------------------------------

EXTENSIONS = {
    "js": "clike-js",
    "jsx": "clike-js",
    "mjs": "clike-js",
    "cjs": "clike-js",
    "ts": "clike-js",
    "tsx": "clike-js",
    "mts": "clike-js",
    "cts": "clike-js",
    "vue": "clike-js",
    "svelte": "clike-js",
    "py": "python",
    "pyi": "python",
    "sh": "shell",
    "bash": "shell",
    "ksh": "shell",
    "bats": "shell",
    "cs": "csharp",
    "go": "go",
    "ps1": "powershell",
    "psm1": "powershell",
    "psd1": "powershell",
    "md": "markdown",
    "markdown": "markdown",
    "rb": "ruby",
    "rake": "ruby",
    "gemspec": "ruby",
    "java": "java",
}
BASENAMES = {"Gemfile": "ruby", "Rakefile": "ruby"}
SHEBANGS = (
    (re.compile(r"\b(?:ba|k)?sh\b"), "shell"),
    (re.compile(r"\bpython[0-9.]*\b"), "python"),
    (re.compile(r"\bpwsh\b"), "powershell"),
    (re.compile(r"\bruby\b"), "ruby"),
    (re.compile(r"\bnode\b"), "clike-js"),
)


def kind_of(path: str, first_line: str) -> str | None:
    name = os.path.basename(path)
    if name in BASENAMES:
        return BASENAMES[name]
    stem, dot, ext = name.rpartition(".")
    if dot and stem:
        return EXTENSIONS.get(ext.lower())
    if first_line.startswith("#!"):
        for pattern, kind in SHEBANGS:
            if pattern.search(first_line):
                return kind
    return None


# ---- lexing -----------------------------------------------------------------
#
# Each line is split into its code (string contents blanked, comments removed)
# and its comment segments. A marker only counts inside a comment segment, or,
# for the attribute and pragma forms, in the code outside any string literal.


@dataclass
class Segment:
    opener: str  # "//", "/*", "#", "<!--", or "" for a block comment's continuation
    text: str


@dataclass
class Line:
    code: str
    segments: list[Segment] = field(default_factory=list)


@dataclass
class LexState:
    block: str | None = None  # the closer of an open block comment
    string: str | None = None  # the closer of a string that spans lines
    fence: str | None = None  # an open Markdown fence


def _quotes(kind: str) -> tuple[str, ...]:
    if kind == "python":
        return ('"""', "'''", '"', "'")
    if kind == "clike-js":
        return ("`", '"', "'")
    if kind in ("csharp", "java"):
        return ('"', "'")
    if kind == "go":
        return ("`", '"', "'")
    if kind == "markdown":
        return ()
    return ('"', "'")


# Quotes whose string may continue onto the next line.
MULTILINE_QUOTES = {
    "python": ('"""', "'''"),
    "clike-js": ("`",),
    "go": ("`",),
    # A shell string is not carried to the next line: an apostrophe in a
    # heredoc body would otherwise hide every directive after it.
    "ruby": ('"', "'"),
    "powershell": ('"', "'"),
}
HASH_KINDS = ("python", "shell", "ruby", "powershell")
SLASH_KINDS = ("clike-js", "csharp", "go", "java")


def _no_escape(kind: str, quote: str) -> bool:
    return (kind == "shell" and quote == "'") or quote == "`" and kind == "go"


def _close_string(line: str, i: int, quote: str, kind: str, out: list[str]) -> int:
    """Index just past the string's closer, or -1 when it stays open.

    The string's contents reach `out` as spaces, so the code keeps the line's
    column positions.
    """
    closer = re.escape(quote) if _no_escape(kind, quote) else r"\\|" + re.escape(quote)
    while True:
        found = re.compile(closer).search(line, i)
        if not found:
            out.append(" " * (len(line) - i))
            return -1
        out.append(" " * (found.start() - i))
        if found.group() == "\\":
            escaped = line[found.start() : found.start() + 2]
            out.append(" " * len(escaped))
            i = found.start() + len(escaped)
            continue
        out.append(quote)
        return found.end()


def _special(kind: str) -> re.Pattern[str]:
    """The characters that can start a string, a comment or an escape."""
    chars = {q[0] for q in _quotes(kind)}
    if kind in SLASH_KINDS:
        chars.add("/")
    if kind in HASH_KINDS:
        chars |= {"#", "\\"}
    if kind == "powershell":
        chars.add("<")
    return re.compile("[" + re.escape("".join(sorted(chars))) + "]")


SPECIAL: dict[str, re.Pattern[str]] = {}
MARKDOWN_SPECIAL = re.compile(r"`|<!--")


def _markdown(line: str, state: LexState) -> Line:
    stripped = line.lstrip()
    fence = re.match(r"(`{3,}|~{3,})", stripped)
    if state.fence:
        if (
            fence
            and fence.group(1)[0] == state.fence[0]
            and len(fence.group(1)) >= len(state.fence)
        ):
            state.fence = None
        return Line("")
    if fence:
        state.fence = fence.group(1)
        return Line("")
    result = Line("")
    i = 0
    if state.block:
        end = line.find("-->")
        if end < 0:
            result.segments.append(Segment("", line))
            return result
        result.segments.append(Segment("", line[:end]))
        state.block = None
        i = end + 3
    while i < len(line):
        found = MARKDOWN_SPECIAL.search(line, i)
        if not found:
            result.code += line[i:]
            break
        result.code += line[i : found.start()]
        i = found.start()
        if line[i] == "`":
            run = re.match(r"`+", line[i:]).group(0)
            close = line.find(run, i + len(run))
            i = len(line) if close < 0 else close + len(run)
            continue
        if line.startswith("<!--", i):
            end = line.find("-->", i + 4)
            if end < 0:
                result.segments.append(Segment("<!--", line[i + 4 :]))
                state.block = "-->"
                return result
            result.segments.append(Segment("<!--", line[i + 4 : end]))
            i = end + 3
    return result


def lex(line: str, kind: str, state: LexState) -> Line:
    if kind == "markdown":
        return _markdown(line, state)
    quotes = _quotes(kind)
    code: list[str] = []
    result = Line("")
    i = 0
    if state.string:
        end = _close_string(line, 0, state.string, kind, code)
        if end < 0:
            return Line("".join(code))
        state.string = None
        i = end
    if state.block:
        end = line.find(state.block)
        if end < 0:
            result.segments.append(Segment("", line))
            return result
        result.segments.append(Segment("", line[:end]))
        i = end + len(state.block)
        state.block = None
    special = SPECIAL.get(kind) or SPECIAL.setdefault(kind, _special(kind))
    while i < len(line):
        found = special.search(line, i)
        if not found:
            code.append(line[i:])
            break
        code.append(line[i : found.start()])
        i = found.start()
        ch = line[i]
        quote = next((q for q in quotes if line.startswith(q, i)), None)
        if quote:
            code.append(quote)
            end = _close_string(line, i + len(quote), quote, kind, code)
            if end < 0:
                if quote in MULTILINE_QUOTES.get(kind, ()):
                    state.string = quote
                break
            i = end
            continue
        if kind in SLASH_KINDS and line.startswith("//", i):
            # `//nolint:x // reason` is one directive and one reason.
            for part in re.split(r"(?<=\S)\s+//", line[i + 2 :]):
                result.segments.append(Segment("//", part))
            break
        if kind in SLASH_KINDS and line.startswith("/*", i):
            end = line.find("*/", i + 2)
            if end < 0:
                result.segments.append(Segment("/*", line[i + 2 :]))
                state.block = "*/"
                break
            result.segments.append(Segment("/*", line[i + 2 : end]))
            i = end + 2
            continue
        if kind == "powershell" and line.startswith("<#", i):
            end = line.find("#>", i + 2)
            if end < 0:
                result.segments.append(Segment("#", line[i + 2 :]))
                state.block = "#>"
                break
            result.segments.append(Segment("#", line[i + 2 : end]))
            i = end + 2
            continue
        if kind in HASH_KINDS and ch == "#":
            if (
                kind == "shell"
                and i > 0
                and not line[i - 1].isspace()
                and line[i - 1] not in ";|&("
            ):
                code.append(ch)
                i += 1
                continue
            # Every further hash starts a new segment: a mypy pragma followed by
            # a flake8 one on the same line is two pragmas, and a ShellCheck
            # directive followed by a hash and prose is a pragma and its reason.
            for part in line[i + 1 :].split("#"):
                result.segments.append(Segment("#", part))
            break
        if kind in HASH_KINDS and ch == "\\":
            escaped = line[i : i + 2]
            code.append(" " * len(escaped))
            i += len(escaped)
            continue
        code.append(ch)
        i += 1
    result.code = "".join(code)
    return result


# ---- the catalog ------------------------------------------------------------
#
# Comment markers: a pattern matched at the start of a comment segment, the
# kinds it applies to, whether the tool's syntax can name a rule, and how the
# rule ids are read from the text after the marker. The remainder after the
# rule ids, once separators are stripped, is the marker's own reason.

RULE_LIST = r"[^\s,]+(?:\s*,\s*[^\s,]+)*"


@dataclass(frozen=True)
class CommentMarker:
    tool: str
    kinds: tuple[str, ...]
    pattern: re.Pattern[str]
    names_rules: bool
    rules: re.Pattern[str] | None  # matched at the start of the text after the marker


def _m(tool, kinds, pattern, rules=None, names_rules=True, lead=r"\s*\*?\s*"):
    return CommentMarker(
        tool,
        kinds,
        re.compile(lead + pattern),
        names_rules,
        re.compile(rules) if rules else None,
    )


COMMENT_MARKERS = (
    _m(
        "eslint",
        ("clike-js",),
        r"eslint-disable(?:-next-line|-line)?\b",
        r"\s+(?P<r>[^\s,]+(?:\s*,\s*[^\s,]+)*?)(?=\s+--|\s*$)",
    ),
    _m(
        "typescript",
        ("clike-js",),
        r"@ts-(?:ignore|expect-error|nocheck)\b",
        names_rules=False,
    ),
    _m(
        "ruff",
        ("python",),
        r"ruff\s*:\s*noqa\b",
        r"\s*:\s*(?P<r>[A-Z]+[0-9]+(?:\s*,\s*[A-Z]+[0-9]+)*)",
    ),
    _m(
        "noqa",
        ("python",),
        r"noqa\b",
        r"\s*:\s*(?P<r>[A-Z]+[0-9]+(?:[\s,]+[A-Z]+[0-9]+)*)",
    ),
    _m("mypy", ("python",), r"type\s*:\s*ignore\b", r"\[(?P<r>[^\]]*)\]"),
    _m("pyright", ("python",), r"pyright\s*:\s*ignore\b", r"\[(?P<r>[^\]]*)\]"),
    _m(
        "pylint",
        ("python",),
        r"pylint\s*:\s*disable(?:-next|-line)?\b",
        r"\s*=\s*(?P<r>[\w-]+(?:\s*,\s*[\w-]+)*)",
    ),
    _m(
        "shellcheck",
        ("shell",),
        r"shellcheck\s+disable\b",
        r"\s*=\s*(?P<r>[\w-]+(?:\s*,\s*[\w-]+)*)",
    ),
    # golangci-lint reads the directive only with no space after the slashes.
    _m("golangci-lint", ("go",), r"nolint\b", r":(?P<r>[\w-]+(?:,[\w-]+)*)", lead=""),
    _m(
        "markdownlint",
        ("markdown",),
        r"markdownlint-disable(?:-line|-next-line|-file)?\b",
        r"\s+(?P<r>[\w-]+(?:\s+(?!--)[\w-]+)*)",
    ),
    _m(
        "rubocop",
        ("ruby",),
        r"rubocop\s*:\s*(?:disable|todo)\b",
        r"\s+(?P<r>[\w/]+(?:\s*,\s*[\w/]+)*)",
    ),
)

# Code markers: an attribute, annotation or pragma found in the code outside
# any string, whose rule ids and reason come from its own arguments.
PRAGMA = re.compile(r"^\s*#\s*pragma\s+warning\s+disable\b")
CS_ATTRIBUTE = re.compile(r"\b(?:Unconditional)?SuppressMessage(?:Attribute)?\s*\(")
PS_ATTRIBUTE = re.compile(r"\bSuppressMessage(?:Attribute)?\s*\(", re.IGNORECASE)
JAVA_ANNOTATION = re.compile(r"@(?:java\.lang\.)?SuppressWarnings\s*\(")
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'')
JUSTIFICATION = re.compile(
    r"\bJustification\s*=\s*(?:\"((?:[^\"\\]|\\.)*)\"|'([^']*)')", re.IGNORECASE
)
# Separators stripped from a reason's ends: punctuation plus the en and em dash.
SEPARATORS = " \t:-/#*,;.>" + chr(0x2013) + chr(0x2014)
# A file holding none of these words has no suppression, so it is not lexed.
ANY_MARKER = re.compile(
    r"eslint-disable|@ts-|noqa|(?:type|pyright)\s*:\s*ignore|pylint\s*:"
    r"|shellcheck\s+disable|pragma\s+warning|SuppressMessage|nolint"
    r"|markdownlint-disable|rubocop\s*:|SuppressWarnings",
    re.IGNORECASE,
)


def _reason(text: str) -> str | None:
    text = text.strip().strip(SEPARATORS).strip()
    return text if re.search(r"[^\W\d_]", text) else None


def _split_rules(text: str) -> list[str]:
    return [r for r in re.split(r"[\s,]+", text.strip()) if r]


@dataclass
class Record:
    line: int
    tool: str
    rules: list[str]
    names_rules: bool
    reason: str | None


def _comment_records(lineno: int, kind: str, segments: list[Segment]) -> list[Record]:
    records: list[Record] = []
    trailing: list[str] = []
    for segment in segments:
        text = segment.text
        marker = next(
            (m for m in COMMENT_MARKERS if kind in m.kinds and m.pattern.match(text)),
            None,
        )
        if marker is None:
            reason = _reason(text)
            if reason:
                trailing.append(reason)
            continue
        rest = text[marker.pattern.match(text).end() :]
        rules: list[str] = []
        if marker.rules:
            found = marker.rules.match(rest)
            if found:
                rules = _split_rules(found.group("r"))
                rest = rest[found.end() :]
        records.append(
            Record(lineno, marker.tool, rules, marker.names_rules, _reason(rest))
        )
    if trailing:
        for record in records:
            if record.reason is None:
                record.reason = "; ".join(trailing)
    return records


def _call_text(lines: list[str], index: int, start: int) -> str:
    """The attribute's text from its opening parenthesis to the balancing one."""
    text = lines[index][start:]
    for extra in lines[index + 1 : index + 10]:
        if text.count("(") <= text.count(")"):
            break
        text += " " + extra.strip()
    return text


def _code_records(
    lineno: int, kind: str, lexed: Line, lines: list[str]
) -> list[Record]:
    comment_reason = (
        "; ".join(r for r in (_reason(s.text) for s in lexed.segments) if r) or None
    )
    if kind == "csharp" and PRAGMA.match(lexed.code):
        rest = lexed.code[PRAGMA.match(lexed.code).end() :]
        return [Record(lineno, "csharp", _split_rules(rest), True, comment_reason)]
    patterns = {
        "csharp": CS_ATTRIBUTE,
        "powershell": PS_ATTRIBUTE,
        "java": JAVA_ANNOTATION,
    }
    pattern = patterns.get(kind)
    found = pattern.search(lexed.code) if pattern else None
    if not found:
        return []
    call = _call_text(lines, lineno - 1, found.start())
    justification = JUSTIFICATION.search(call)
    args = JUSTIFICATION.sub("", call)
    strings = [a or b for a, b in STRING_LITERAL.findall(args)]
    if kind == "java":
        rules = [s for s in strings if s]
        reason = comment_reason
    else:
        ids = strings[1:2] if kind == "csharp" else strings[:1]
        rules = [s.split(":", 1)[0].strip() for s in ids if s.strip()]
        reason = None
        if justification:
            reason = _reason(justification.group(1) or justification.group(2) or "")
        reason = reason or comment_reason
    return [Record(lineno, kind, rules, True, reason)]


def scan_text(path: str, text: str) -> list[Record]:
    lines = text.splitlines()
    kind = kind_of(path, lines[0] if lines else "")
    if kind is None or not ANY_MARKER.search(text):
        return []
    state = LexState()
    records: list[Record] = []
    for index, line in enumerate(lines):
        lexed = lex(line, kind, state)
        records.extend(_comment_records(index + 1, kind, lexed.segments))
        if kind in ("csharp", "powershell", "java"):
            records.extend(_code_records(index + 1, kind, lexed, lines))
    return records


# ---- inputs -----------------------------------------------------------------


class UsageError(Exception):
    pass


def git(args: list[str], cwd: str | None = None) -> bytes:
    command = ["git", "--literal-pathspecs", "-c", "core.quotePath=false", *args]
    try:
        done = subprocess.run(command, cwd=cwd, capture_output=True, check=False)
    except OSError as exc:
        raise UsageError(f"cannot run git: {exc}") from exc
    if done.returncode != 0:
        message = done.stderr.decode("utf-8", "replace").strip().splitlines()
        raise UsageError(
            f"git {args[0]} failed: {message[0] if message else 'no message'}"
        )
    return done.stdout


def repo_top() -> str | None:
    try:
        done = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, check=False
        )
    except OSError:
        return None
    top = done.stdout.decode("utf-8", "replace").strip()
    return top if done.returncode == 0 and top else None


def decode(data: bytes) -> str | None:
    if b"\0" in data[:8192]:
        return None
    return data.decode("utf-8", "replace")


def display(path: str, top: str | None) -> str:
    """Root-relative inside a repository, else the normalized path as given."""
    if top:
        path = os.path.relpath(os.path.abspath(path), top)
    return os.path.normpath(path).replace(os.sep, "/")


def expand(paths: list[str], top: str | None) -> list[str]:
    files: list[str] = []
    for path in paths:
        if os.path.isfile(path):
            files.append(path)
        elif os.path.isdir(path):
            if top:
                listing = git(
                    [
                        "ls-files",
                        "-z",
                        "--cached",
                        "--others",
                        "--exclude-standard",
                        "--",
                        path,
                    ]
                )
                files.extend(
                    p
                    for p in listing.decode("utf-8", "surrogateescape").split("\0")
                    if p
                )
            else:
                for root, dirs, names in os.walk(path):
                    dirs[:] = sorted(d for d in dirs if d != ".git")
                    files.extend(os.path.join(root, n) for n in sorted(names))
        else:
            raise UsageError(f"path does not exist: {path}")
    return files


def inventory(paths: list[str]) -> list[tuple[str, Record]]:
    top = repo_top()
    if not paths:
        paths = [top or "."]
    found: list[tuple[str, Record]] = []
    seen: set[str] = set()
    for path in expand(paths, top):
        if not os.path.isfile(path):
            continue  # a listed file deleted from the working tree
        shown = display(path, top)
        if shown in seen:
            continue
        seen.add(shown)
        try:
            with open(path, "rb") as handle:
                text = decode(handle.read())
        except OSError as exc:
            raise UsageError(f"cannot read {path}: {exc.strerror}") from exc
        if text is not None:
            found.extend((shown, r) for r in scan_text(shown, text))
    return found


HUNK = re.compile(rb"^@@ -[0-9,]+ \+([0-9]+)(?:,([0-9]+))? @@")


def added_lines(base: str, paths: tuple[str, ...], top: str) -> set[int]:
    out = git(
        [
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--no-color",
            "-M",
            "-U0",
            f"{base}...HEAD",
            "--",
            *paths,
        ],
        cwd=top,
    )
    lines: set[int] = set()
    for raw in out.split(b"\n"):
        hunk = HUNK.match(raw)
        if not hunk:
            continue
        start = hunk.group(1).decode()
        count = (hunk.group(2) or b"1").decode()
        if not (start.isdigit() and count.isdigit()):
            continue
        lines.update(range(int(start), int(start) + int(count)))
    return lines


def changed(base: str, paths: list[str]) -> list[tuple[str, Record]]:
    top = repo_top()
    if top is None:
        raise UsageError("--diff needs a git repository")
    if base.startswith("-"):
        raise UsageError(f"--diff base must not start with '-': {base}")
    git(
        ["rev-parse", "--verify", "--quiet", "--end-of-options", f"{base}^{{commit}}"],
        cwd=top,
    )
    wanted = [display(p, top) for p in paths]
    status = git(
        [
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "-M",
            "--name-status",
            "-z",
            "--diff-filter=AMR",
            f"{base}...HEAD",
        ],
        cwd=top,
    )
    fields = status.decode("utf-8", "surrogateescape").split("\0")
    entries: list[tuple[str, tuple[str, ...]]] = []
    i = 0
    while i < len(fields) and fields[i]:
        letter = fields[i][:1]
        if letter == "R":
            entries.append((fields[i + 2], (fields[i + 1], fields[i + 2])))
            i += 3
        else:
            entries.append((fields[i + 1], (fields[i + 1],)))
            i += 2
    found: list[tuple[str, Record]] = []
    for path, pathspec in entries:
        if wanted and not any(
            path == w or w in (".", "") or path.startswith(w.rstrip("/") + "/")
            for w in wanted
        ):
            continue
        lines = added_lines(base, pathspec, top)
        if not lines:
            continue
        text = decode(git(["cat-file", "blob", f"HEAD:{path}"], cwd=top))
        if text is None:
            continue
        found.extend((path, r) for r in scan_text(path, text) if r.line in lines)
    return found


def read_list(path: str, comments: bool) -> list[str]:
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise UsageError(f"cannot read {path}: {exc}") from exc
    if comments:
        lines = [line.split("#", 1)[0].strip() for line in lines]
    return [line for line in lines if line]


# ---- command line -----------------------------------------------------------


def parse(argv: list[str]) -> dict:
    options = {
        "diff": None,
        "count": False,
        "rules": None,
        "paths_from": None,
        "paths": [],
    }
    takes_value = {
        "--diff": "diff",
        "--correctness-rules": "rules",
        "--paths-from": "paths_from",
    }
    i = 0
    while i < len(argv):
        arg = argv[i]
        name, eq, value = arg.partition("=")
        if arg == "--":
            options["paths"].extend(argv[i + 1 :])
            break
        if arg in ("--help", "-h"):
            options["help"] = True
        elif arg == "--count":
            options["count"] = True
        elif name in takes_value:
            if not eq:
                if i + 1 >= len(argv):
                    raise UsageError(f"{name} needs a value")
                i += 1
                value = argv[i]
            options[takes_value[name]] = value
        elif arg.startswith("-") and arg != "-":
            raise UsageError(f"unknown option: {arg}")
        else:
            options["paths"].append(arg)
        i += 1
    return options


def main(argv: list[str]) -> int:
    try:
        options = parse(argv)
        if options.get("help"):
            print(__doc__.strip())
            return 0
        paths = list(options["paths"])
        if options["paths_from"]:
            paths.extend(read_list(options["paths_from"], comments=False))
        listed = None
        if options["rules"] is not None:
            listed = {r.casefold() for r in read_list(options["rules"], comments=True)}
        if options["diff"] is not None:
            found = changed(options["diff"], paths)
        else:
            found = inventory(paths)
    except UsageError as exc:
        print(f"suppression-scan.py: {exc}", file=sys.stderr)
        return 2
    found.sort(key=lambda item: (item[0], item[1].line, item[1].tool))
    records = []
    for path, r in found:
        record = {
            "file": path,
            "line": r.line,
            "tool": r.tool,
            "rules": r.rules,
            "justified": r.reason is not None and (bool(r.rules) or not r.names_rules),
            "reason": r.reason,
        }
        if listed is not None:
            record["correctness"] = any(rule.casefold() in listed for rule in r.rules)
        records.append(record)
    if options["count"]:
        print(f"suppressions={len(records)}")
        print(f"unjustified={sum(1 for r in records if not r['justified'])}")
        if listed is not None:
            print(f"correctness={sum(1 for r in records if r['correctness'])}")
    else:
        print(json.dumps(records, indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "suppression-scan.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
