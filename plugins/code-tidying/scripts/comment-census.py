#!/usr/bin/env python3
"""Count the comment burden of a code tree, with an honest token estimate.

Answers the question a comment-removal pass has to be able to answer before
and after it runs: how many comment lines and bytes are here, what is that in
tokens, and did the last pass move the number.

Two reading layers, each named in the output so a reader knows how the count
was made:

  scc       per-file comment and code LINES plus a complexity estimate, in one
            pass over 300+ languages. No byte counts.
  pygments  per-file comment BYTES and lines from the token stream, so the
            token estimate is real text, not a line-count multiplied by a
            guess. Correct on trailing comments, block comments, and
            documentation strings (`String.Doc`, including Python docstrings).
            Ordinary string literals are not comments. Shell scripts are read
            by POSIX and Bash token rules (`tokens`) in place of pygments'
            Bash lexer, so here-document bodies and a quoted or mid-word '#'
            are not comments.

Both present: lines and complexity from scc, bytes from pygments. Neither
present: exit 3 naming what to install. A line-prefix grep is never used,
because it counts heredoc bodies and string data as comments.

Byte-identical files count once in the deduplicated totals: a vendored copy
kept in sync by a gate is one authored file, however many times it is
instantiated. Both totals are printed because they answer different
questions (authoring effort versus what an agent pays to read).

Tokens are estimated as bytes / 4 and labeled as an estimate throughout.

Usage: comment-census.py [PATH ...] [--top N] [--json] [--baseline FILE]
                         [--layer auto|scc|pygments]
Code files are those whose extension is in code-extensions.txt beside this
script, the list the code-tidying scoping scripts share.

Exit: 0 counted; 3 no reading layer available; 2 usage; 4 the extension list
cannot be read (its path is named on stderr).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

CODE_EXT_FILE = Path(__file__).with_name("code-extensions.txt")
EXIT_NO_LAYER = 3
EXIT_USAGE = 2
EXIT_NO_EXTENSION_LIST = 4


def code_extensions() -> set[str]:
    """The shared extension list, dotted and lowercased; OSError when unreadable or empty."""
    exts = {
        "." + line.strip().lower()
        for line in CODE_EXT_FILE.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    if not exts:
        raise OSError(f"{CODE_EXT_FILE} lists no extension")
    return exts


def tracked_files(roots: list[Path], code_ext: set[str] | None = None) -> list[Path]:
    """Code files under each root: git-tracked when inside a repo, else walked."""
    code_ext = code_ext or code_extensions()
    out: list[Path] = []
    for root in roots:
        if root.is_file():
            if root.suffix.lower() in code_ext:
                out.append(root)
            continue
        try:
            listing = subprocess.run(
                ["git", "ls-files", "-z", "--", "."],
                capture_output=True,
                check=True,
                cwd=str(root),
            ).stdout
            names = [n for n in listing.decode(errors="replace").split("\0") if n]
            # Pathspec `.` with cwd=root: a repo-relative pathspec run from
            # inside that directory would look for root/root and match nothing.
            found = [root / n for n in names]
        except (subprocess.CalledProcessError, FileNotFoundError):
            found = [p for p in root.rglob("*") if p.is_file()]
        out.extend(p for p in found if p.suffix.lower() in code_ext and p.is_file())
    seen: set[Path] = set()
    uniq = []
    for p in out:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            uniq.append(p)
    return sorted(uniq, key=lambda p: str(p))


def argv_safe(path: Path) -> str:
    """A path spelling no flag parser can mistake for an option."""
    return str(path) if path.is_absolute() else os.path.join(".", str(path))


def scc_counts(files: list[Path]) -> dict[str, dict] | None:
    exe = shutil.which("scc")
    if not exe or not files:
        return None
    # `git ls-files` names are attacker-chosen (`-o=evil.json`): `--` ends scc's flag
    # parsing, and the `./` prefix keeps a bare relative name from reading as a flag.
    proc = subprocess.run(
        [
            exe,
            "--by-file",
            "--format",
            "json",
            "--no-cocomo",
            "--",
            *map(argv_safe, files),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    by_path: dict[str, dict] = {}
    for lang in json.loads(proc.stdout or "[]"):
        for f in lang.get("Files", []):
            by_path[os.path.normpath(f["Location"])] = {
                "language": lang.get("Name", f.get("Language", "?")),
                "comment_lines": f.get("Comment", 0),
                "code_lines": f.get("Code", 0),
                "lines": f.get("Lines", 0),
                "complexity": f.get("Complexity", 0),
            }
    return by_path


def pygments_available() -> bool:
    """Whether the pygments layer can be used at all, independent of any file.

    `pygments_counts` answers this only as a side effect of reading a file, so a
    scope with no readable files cannot distinguish "nothing to read" from "no
    analyzer installed" without asking separately.
    """
    try:
        import pygments  # noqa: F401
    except ImportError:
        return False
    return True


def scc_available() -> bool:
    """Whether the scc layer can be used at all, independent of any file.

    The counterpart to `pygments_available`, and needed for the same reason:
    `scc_counts` returns None both when the binary is missing AND when the file
    list is empty, so its result cannot answer "is scc installed" on an empty
    scope. Reusing it as that proxy reports an installed scc as unavailable.
    """
    return shutil.which("scc") is not None


def is_comment_token(tok) -> bool:
    """True for pygments tokens the census counts as comment burden.

    Comment subtypes except Hashbang and Preproc, plus String.Doc (documentation
    strings, including Python docstrings). Ordinary String / String.Double /
    String.Single tokens are data. rank-comment-targets.comment_line_numbers
    uses this same predicate so drift extraction cannot drift from the census.
    """
    from pygments.token import Comment, String

    if tok in Comment and tok not in (Comment.Hashbang, Comment.Preproc):
        return True
    return tok in String.Doc


def tokens(text: str, lexer) -> list:
    """(token type, text) pairs for <text>: pygments' own, except for its Bash lexer.

    pygments' BashLexer ends a here-document at the first place its delimiter
    appears, inside a word included, misses a quoted delimiter (<<"EOF"), and
    takes a '#' inside a word for a comment; each mistake can flip its quote
    state for the rest of the file. Shell files are read by _ShellComments.
    """
    if lexer.name == "Bash":
        return _ShellComments(text).tokens()
    from pygments import lex

    return list(lex(text, lexer))


class _ShellComments:
    """Comments and here-document bodies of a shell script, by the shell's own rules.

    POSIX Shell Command Language, 2.3 Token Recognition, 2.4 Reserved Words and
    2.7.4 Here-Document
    (https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html):
    "If the previous character was part of a word, the current character shall
    be appended to that word"; only otherwise does "a '#'" start a comment that
    runs "up to, but excluding, the next <newline>". Quotes, $'...', parameter
    expansion, command substitution and arithmetic expansion belong to the word
    they sit in. A reserved word such as case, esac or [[ counts only as the
    first word of a command. A here-document "begins after the next NEWLINE
    token and continues until there is a line containing only the delimiter",
    the delimiter being the word after quote removal, leading tabs stripped for
    <<-, and several on one line are read in order. Bash additions, per the Bash
    reference manual (https://www.gnu.org/software/bash/manual/bash.html): a
    (( )) arithmetic command, whose << is a shift; [[ ]], where parentheses and
    << belong to the expression; <( ) and >( ) process substitution; $"...";
    and an ANSI-C quoted $'...' delimiter, read after its escapes.

    A construct left open at the end of the text (a quote, an expansion, a
    substitution, a here-document with no delimiter line) or an arithmetic
    expression with an unmatched ')' is one this reader got wrong or the shell
    rejects. It never hides the rest of the file: everything read from its start
    is dropped and reading starts again on the next line (a here-document's on
    its first body line), so the lines after it are read as code and a comment
    there is still found.
    """

    OPERATOR = frozenset(";&|<>()")
    COMMAND_BREAK = frozenset(";&|()")
    BLANK = frozenset(" \t")
    KEYWORD_END = frozenset(" \t\n;&|<>()")
    PRE_COMMAND = frozenset(("!", "{", "do", "elif", "else", "if", "then", "time", "until", "while"))
    WORD = re.compile(r"[^\s;&|<>()\"'`$\\]*")
    ASSIGNMENT = re.compile(r"[A-Za-z_]\w*\+?=")
    ANSI_ESCAPE = re.compile(r"\\(x[0-9A-Fa-f]{1,2}|[0-7]{1,3}|.)", re.DOTALL)
    ANSI_CHAR = {
        "a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n",
        "r": "\r", "t": "\t", "v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?",
    }

    def __init__(self, text: str):
        self.s = text
        self.i = 0
        self.n = len(text)
        self.spans: list[tuple[str, int, int]] = []
        self.pending: list[tuple[str, bool]] = []
        self.lost: tuple[int, int] | None = None

    def tokens(self) -> list:
        from pygments.token import Comment, String, Text

        at = 0
        if self.s.startswith("#!"):
            at = self._line_end(0)
            self.spans.append(("hashbang", 0, at))
        while True:
            self.i, self.pending, self.lost = at, [], None
            self._command(None, at)
            if self.lost is None:
                break
            start, resume = self.lost
            self.spans = [span for span in self.spans if span[1] < start]
            at = resume if resume > at else self._line_end(at) + 1
        kinds = {"hashbang": Comment.Hashbang, "comment": Comment.Single, "heredoc": String}
        out, at = [], 0
        for kind, start, end in sorted(self.spans, key=lambda span: span[1]):
            if start > at:
                out.append((Text, self.s[at:start]))
            out.append((kinds[kind], self.s[start:end]))
            at = end
        if at < self.n:
            out.append((Text, self.s[at:]))
        return out

    def _line_end(self, at: int) -> int:
        end = self.s.find("\n", at)
        return self.n if end < 0 else end

    def _lose(self, start: int, resume: int | None = None) -> None:
        if resume is None:
            resume = self._line_end(start) + 1
        if self.lost is None or start < self.lost[0]:
            self.lost = (start, resume)
        self.i = self.n

    def _command(self, close: str | None, start: int) -> None:
        s, in_word, at_command, cond, depth, cases = self.s, False, True, False, 0, 0
        while self.i < self.n:
            c = s[self.i]
            if c == close and (close == "`" or (depth == 0 and cases == 0)):
                self.i += 1
                return
            if c == "\n":
                self.i += 1
                in_word, at_command = False, True
                self._bodies()
            elif c in self.BLANK:
                self.i += 1
                in_word = False
            elif c == "#" and not in_word:
                end = self._line_end(self.i)
                if close == "`":
                    tick = s.find("`", self.i, end)
                    end = end if tick < 0 else tick
                self.spans.append(("comment", self.i, end))
                self.i = end
            elif c == "\\":
                in_word = in_word or s[self.i + 1 : self.i + 2] != "\n"
                self.i += 2
            elif s.startswith("<<<", self.i):
                self.i += 3
                in_word = False
            elif s.startswith(("<(", ">("), self.i):
                self.i += 2
                self._command(")", self.i - 2)
                in_word, at_command = True, False
            elif s.startswith("<<", self.i) and not cond:
                self._heredoc()
                in_word = False
            elif s.startswith("((", self.i) and at_command and not in_word:
                self.i += 2
                self._arithmetic(self.i - 2)
                at_command = False
            elif c in self.OPERATOR:
                if c == "(":
                    depth += 1
                elif c == ")" and depth:
                    depth -= 1
                self.i += 1
                in_word = False
                at_command = at_command or c in self.COMMAND_BREAK
            else:
                if not in_word:
                    end = self.WORD.match(s, self.i).end()
                    word = s[self.i : end] if end >= self.n or s[end] in self.KEYWORD_END else None
                    if at_command and word == "[[":
                        cond = True
                    elif cond and word == "]]":
                        cond = False
                    elif at_command and close == ")" and word == "case":
                        cases += 1
                    elif at_command and cases and word == "esac":
                        cases -= 1
                    at_command = at_command and (
                        word in self.PRE_COMMAND or bool(self.ASSIGNMENT.match(s, self.i))
                    )
                self._word_part(quoted=False)
                in_word = True
        if close is not None:
            self._lose(start)

    def _word_part(self, quoted: bool) -> None:
        s, c, start = self.s, self.s[self.i], self.i
        if c == "'" and not quoted:
            end = s.find("'", self.i + 1)
            if end < 0:
                self._lose(start)
            else:
                self.i = end + 1
        elif c == '"':
            self.i += 1
            self._double(start)
        elif c == "$":
            self._dollar(quoted)
        elif c == "`":
            self.i += 1
            self._command("`", start)
        elif c == "\\":
            self.i += 2
        else:
            self.i += 1

    def _double(self, start: int) -> None:
        while self.i < self.n:
            if self.s[self.i] == '"':
                self.i += 1
                return
            self._word_part(quoted=True)
        self._lose(start)

    def _dollar(self, quoted: bool) -> None:
        s, start = self.s, self.i
        if s.startswith("$((", start):
            self.i += 3
            self._arithmetic(start)
        elif s.startswith("$(", start):
            self.i += 2
            self._command(")", start)
        elif s.startswith("${", start):
            self.i += 2
            self._braces(start)
        elif s.startswith("$'", start) and not quoted:
            self.i = self._ansi_end(start + 2)
            if self.i > self.n:
                self._lose(start)
        else:
            self.i += 1

    def _ansi_end(self, at: int) -> int:
        while at < self.n and self.s[at] != "'":
            at += 2 if self.s[at] == "\\" else 1
        return at + 1

    def _braces(self, start: int) -> None:
        while self.i < self.n:
            if self.s[self.i] == "}":
                self.i += 1
                return
            self._word_part(quoted=False)
        self._lose(start)

    def _arithmetic(self, start: int) -> None:
        depth = 0
        while self.i < self.n:
            if self.s.startswith("))", self.i) and depth == 0:
                self.i += 2
                return
            c = self.s[self.i]
            if c == ")" and depth == 0:
                break
            if c in "()":
                depth += 1 if c == "(" else -1
                self.i += 1
            else:
                self._word_part(quoted=False)
        self._lose(start)

    def _heredoc(self) -> None:
        s = self.s
        self.i += 2
        strip = s.startswith("-", self.i)
        self.i += strip
        while self.i < self.n and s[self.i] in self.BLANK:
            self.i += 1
        word = []
        while self.i < self.n and s[self.i] not in self.KEYWORD_END:
            c = s[self.i]
            if s.startswith("$'", self.i):
                end = self._ansi_end(self.i + 2)
                word.append(self._ansi(s[self.i + 2 : end - 1]))
                self.i = end
            elif s.startswith('$"', self.i):
                self.i += 1
            elif c == "'":
                end = s.find("'", self.i + 1)
                end = self.n if end < 0 else end
                word.append(s[self.i + 1 : end])
                self.i = end + 1
            elif c == '"':
                self.i += 1
                while self.i < self.n and s[self.i] != '"':
                    if s[self.i] == "\\" and s[self.i + 1 : self.i + 2] in ('"', "\\", "$", "`"):
                        self.i += 1
                    word.append(s[self.i : self.i + 1])
                    self.i += 1
                self.i += 1
            elif c == "\\":
                word.append(s[self.i + 1 : self.i + 2])
                self.i += 2
            else:
                word.append(c)
                self.i += 1
        if word:
            self.pending.append(("".join(word), strip))

    def _ansi(self, body: str) -> str:
        def one(match: re.Match) -> str:
            code = match.group(1)
            if code[0] == "x" and len(code) > 1:
                return chr(int(code[1:], 16))
            if code[0] in "01234567":
                return chr(int(code, 8))
            return self.ANSI_CHAR.get(code, "\\" + code)

        return self.ANSI_ESCAPE.sub(one, body)

    def _bodies(self) -> None:
        for delimiter, strip in self.pending:
            start = self.i
            while self.i < self.n:
                end = self._line_end(self.i)
                line = self.s[self.i : end]
                self.i = min(end + 1, self.n)
                if (line.lstrip("\t") if strip else line) == delimiter:
                    break
            else:
                self.pending = []
                self._lose(start, start)
                return
            self.spans.append(("heredoc", start, self.i))
        self.pending = []


def pygments_counts(path: Path) -> dict | None:
    try:
        from pygments.lexers import get_lexer_for_filename
        from pygments.util import ClassNotFound
    except ImportError:
        return None
    try:
        lexer = get_lexer_for_filename(str(path), stripnl=False)
    except ClassNotFound:
        return {
            "language": "?",
            "comment_lines": 0,
            "comment_bytes": 0,
            "lines": 0,
            "lexed": False,
        }
    src = path.read_text(encoding="utf-8", errors="replace")
    line = 1
    comment_lines: set[int] = set()
    comment_bytes = 0
    for tok, text in tokens(src, lexer):
        if is_comment_token(tok):
            body = text.strip("\n")
            if body.strip():
                comment_bytes += len(body.encode("utf-8"))
                for i, part in enumerate(text.split("\n")):
                    if part.strip():
                        comment_lines.add(line + i)
        line += text.count("\n")
    return {
        "language": lexer.name,
        "comment_lines": len(comment_lines),
        "comment_bytes": comment_bytes,
        "lines": src.count("\n") + (0 if src.endswith("\n") or not src else 1),
        "lexed": True,
    }


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def census(files: list[Path], layer: str) -> tuple[list[dict], dict]:
    use_scc = layer in ("auto", "scc")
    scc = scc_counts(files) if use_scc else None
    use_pygments = layer in ("auto", "pygments")
    records = []
    sources = {"lines": None, "bytes": None, "complexity": None}
    for p in files:
        rec = {"path": str(p), "sha256": sha256_of(p), "size": p.stat().st_size}
        s = scc.get(os.path.normpath(str(p))) if scc else None
        g = pygments_counts(p) if use_pygments else None
        if g is None and layer == "pygments":
            return [], {"error": "pygments is not installed (pip install pygments)"}
        if s:
            rec.update(
                language=s["language"],
                comment_lines=s["comment_lines"],
                code_lines=s["code_lines"],
                lines=s["lines"],
                complexity=s["complexity"],
            )
            sources["lines"] = sources["lines"] or "scc"
            sources["complexity"] = "scc"
        if g and g.get("lexed"):
            rec.setdefault("language", g["language"])
            rec.setdefault("comment_lines", g["comment_lines"])
            rec.setdefault("lines", g["lines"])
            rec["comment_bytes"] = g["comment_bytes"]
            sources["bytes"] = "pygments"
            sources["lines"] = sources["lines"] or "pygments"
        if "comment_lines" not in rec:
            rec.update(
                language=(g or {}).get("language", "?"),
                comment_lines=0,
                lines=0,
                unread=True,
            )
        records.append(rec)
    # Probe each layer for INSTALLED-ness directly: a missing analyzer reported as a clean
    # zero makes every later count read as an improvement. Neither `sources["lines"]` nor
    # `scc_counts` can tell, since both come back None on an empty scope too.
    have_layer = (use_scc and scc_available()) or (
        use_pygments and pygments_available()
    )
    if sources["lines"] is None and not have_layer:
        return [], {
            "error": "neither scc nor pygments is available (install scc, or pip install pygments)"
        }
    return records, sources


def totals(records: list[dict], dedupe: bool) -> dict:
    chosen = records
    duplicates = 0
    if dedupe:
        by_hash: dict[str, dict] = {}
        for r in records:
            by_hash.setdefault(r["sha256"], r)
        chosen = list(by_hash.values())
        duplicates = len(records) - len(chosen)
    cl = sum(r.get("comment_lines", 0) for r in chosen)
    lines = sum(r.get("lines", 0) for r in chosen)
    cb = sum(r.get("comment_bytes", 0) for r in chosen)
    return {
        "files": len(chosen),
        "duplicate_copies_collapsed": duplicates,
        "comment_lines": cl,
        "lines": lines,
        "comment_ratio": round(cl / lines, 4) if lines else 0.0,
        "comment_bytes": cb,
        "approx_tokens": cb // 4,
        # Unreadable files count 0, indistinguishable from comment-free ones in the totals,
        # so carry the count and let the report say coverage is partial.
        "unread_files": sum(1 for r in chosen if r.get("unread")),
    }


def by_language(records: list[dict]) -> list[dict]:
    agg: dict[str, dict] = defaultdict(
        lambda: {"files": 0, "comment_lines": 0, "lines": 0, "comment_bytes": 0}
    )
    for r in records:
        a = agg[r.get("language", "?")]
        a["files"] += 1
        a["comment_lines"] += r.get("comment_lines", 0)
        a["lines"] += r.get("lines", 0)
        a["comment_bytes"] += r.get("comment_bytes", 0)
    rows = [
        {
            "language": lang,
            **a,
            "comment_ratio": round(a["comment_lines"] / a["lines"], 4)
            if a["lines"]
            else 0.0,
        }
        for lang, a in agg.items()
    ]
    return sorted(rows, key=lambda r: (-r["comment_lines"], r["language"]))


def render(report: dict, top: int) -> str:
    out = []
    src = report["sources"]
    out.append(
        f"layers: lines={src.get('lines') or 'n/a'} bytes={src.get('bytes') or 'n/a (pip install pygments)'} "
        f"complexity={src.get('complexity') or 'n/a (install scc)'}"
    )
    for key, label in (("raw", "raw   "), ("deduped", "deduped")):
        t = report[key]
        out.append(
            f"{label}: files={t['files']} comment_lines={t['comment_lines']} lines={t['lines']} "
            f"ratio={t['comment_ratio']:.1%} comment_bytes={t['comment_bytes']} approx_tokens={t['approx_tokens']}"
            + (
                f" (collapsed {t['duplicate_copies_collapsed']} byte-identical copies)"
                if key == "deduped"
                else ""
            )
        )
    out.append("tokens are an estimate: comment_bytes / 4")
    unread = report["deduped"].get("unread_files", 0)
    if unread:
        out.append(
            f"NOTE: {unread} file(s) no analyzer could read are counted as 0 comments — "
            "the totals above are a floor, not a measurement, for those files"
        )
    out.append("")
    out.append("language\tfiles\tcomment_lines\tlines\tratio\tcomment_bytes")
    for r in report["by_language"]:
        out.append(
            f"{r['language']}\t{r['files']}\t{r['comment_lines']}\t{r['lines']}\t{r['comment_ratio']:.1%}\t{r['comment_bytes']}"
        )
    if top:
        out.append("")
        out.append(f"top {top} files by comment_lines (deduplicated)")
        seen: set[str] = set()
        shown = 0
        for r in sorted(
            report["files"], key=lambda r: (-r.get("comment_lines", 0), r["path"])
        ):
            if r["sha256"] in seen:
                continue
            seen.add(r["sha256"])
            out.append(f"{r.get('comment_lines', 0)}\t{r.get('lines', 0)}\t{r['path']}")
            shown += 1
            if shown >= top:
                break
    if "delta" in report:
        d = report["delta"]
        out.append("")
        out.append(
            f"delta vs baseline (deduped): comment_lines {d['comment_lines']:+d}, "
            f"comment_bytes {d['comment_bytes']:+d}, approx_tokens {d['approx_tokens']:+d}"
        )
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="files or directories; default: the current directory",
    )
    ap.add_argument(
        "--top", type=int, default=10, help="top-N files by comment lines (0 to omit)"
    )
    ap.add_argument(
        "--json",
        action="store_true",
        help="emit the full report as JSON (usable as a later --baseline)",
    )
    ap.add_argument(
        "--baseline",
        type=Path,
        help="a prior --json report to diff the deduplicated totals against",
    )
    ap.add_argument("--layer", choices=("auto", "scc", "pygments"), default="auto")
    args = ap.parse_args(argv)

    roots = args.paths or [Path(".")]
    for r in roots:
        if not r.exists():
            print(f"comment-census: no such path {r}", file=sys.stderr)
            return EXIT_USAGE
    try:
        code_ext = code_extensions()
    except (OSError, UnicodeDecodeError):
        print(
            f"comment-census: cannot read the extension list {CODE_EXT_FILE}",
            file=sys.stderr,
        )
        return EXIT_NO_EXTENSION_LIST
    files = tracked_files(roots, code_ext)
    records, sources = census(files, args.layer)
    if "error" in sources:
        print(f"comment-census: UNAVAILABLE: {sources['error']}", file=sys.stderr)
        return EXIT_NO_LAYER
    report = {
        "sources": sources,
        "raw": totals(records, dedupe=False),
        "deduped": totals(records, dedupe=True),
        "by_language": by_language(records),
        "files": records,
        "token_estimate": "comment_bytes / 4",
    }
    if args.baseline:
        try:
            base = json.loads(args.baseline.read_text(encoding="utf-8"))["deduped"]
        except (OSError, ValueError, KeyError) as exc:
            print(f"comment-census: baseline unreadable: {exc}", file=sys.stderr)
            return EXIT_USAGE
        cur = report["deduped"]
        report["delta"] = {
            k: cur[k] - base.get(k, 0)
            for k in ("comment_lines", "comment_bytes", "approx_tokens")
        }
    if args.json:
        print(json.dumps(report, indent=1, sort_keys=True))
    else:
        print(render(report, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
