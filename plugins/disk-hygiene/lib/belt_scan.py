"""Decide whether a Bash command may skip the disk-hygiene session belt.

The belt's ``if`` filters send a command to the guard when a deletion verb is a
command in it, and Claude Code also runs every wildcard-led filter on some commands
that contain ``$()``, a backtick or ``$VAR``, so ordinary ``git`` and ``gh`` calls
reach the guard too. ``defers`` reads the command's words, including what sits
inside ``$()``, backticks, subshells, ``${}``, process substitution and unquoted
heredoc bodies, and is True only when none of them names a deletion verb or a
bundled script where a command could run it:

- as a command, bare or by path;
- as a whole word anywhere, so a wrapper (``sudo``, ``env``, ``timeout``,
  ``xargs``, ``git rm``) cannot hide it;
- as the last part of a path inside any word, which the ``*/rm *`` filters match;
- as any unquoted part of a word (``{rm,-rf}``);
- as any part of a word after a command that runs a string as code
  (``bash -c``, ``eval``, ``ssh``, ``python3 -c``) or in a here-string.

Anything this reader cannot follow to the end is not deferred, so the belt denies
it: an unbalanced quote, an unterminated ``$(`` or heredoc, a heredoc read by a
command that may run it, a heredoc line that starts with its delimiter and goes on
(bash ends a heredoc in ``$()`` at ``EOF)``), an unquoted heredoc line ending in a
backslash, ``$'..'`` with an escape, a command name built by an expansion or a
glob, and ``case``, ``function`` and ``coproc``. The heredoc body of ``cat``,
``git`` and ``gh`` is data apart from an unquoted body's expansions, so a commit
message may name ``rm``.
"""

from __future__ import annotations

import re

DELETION_VERBS = frozenset({"rm", "rmdir", "unlink", "shred", "truncate", "mv", "find"})
BUNDLED_SCRIPTS = frozenset({"hygiene.py", "kill_switch_probe.py", "release_belt.py"})
_NAMES = DELETION_VERBS | BUNDLED_SCRIPTS
# Commands that run a string as code; python* also counts (``_runs_code``).
_CODE_RUNNERS = frozenset(
    {
        "sh", "bash", "zsh", "dash", "ksh", "mksh", "ash", "fish", "csh", "tcsh",
        "eval", "trap", "source", ".", "parallel", "watch", "su", "ssh", "script",
        "flock", "py", "perl", "ruby", "node", "php", "pwsh", "powershell",
    }
)  # fmt: skip

# Words after which the next word is a command again.
_KEYWORDS = frozenset(
    {"!", "{", "then", "do", "else", "elif", "if", "while", "until", "time"}
)
# Compound commands this reader does not follow: their bodies read as arguments.
_UNREAD_HEADS = frozenset({"case", "function", "coproc"})
# Commands whose heredoc body is data, not code.
_HEREDOC_DATA_HEADS = frozenset({"cat", "git", "gh"})
_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=")
_REDIRECT = re.compile(r"<<<|<<-?|<\(|>\(|&>>?|>>|<>|>&|<&|>\||[<>]")
_PATH_SPLIT = re.compile(r"[/\\:]")
_TOKEN = re.compile(r"[A-Za-z0-9._\-/\\:]+")
_WORD_END = frozenset(" \t\r\n;&|()<>")
# Stand-ins in a word's literal text for an expansion: unquoted, or inside quotes.
_UNQUOTED = "\x01"
_QUOTED = "\x00"


class _Unreadable(Exception):
    """The command is not one this reader will vouch for."""


def _stem(name: str) -> str:
    return name.casefold().removesuffix(".exe")


def _names(text: str, *, paths_only: bool = False) -> set[str]:
    return {
        _stem(_PATH_SPLIT.split(token)[-1])
        for token in _TOKEN.findall(text)
        if not paths_only or _PATH_SPLIT.search(token)
    }


def _runs_code(stem: str) -> bool:
    return stem in _CODE_RUNNERS or stem.startswith("python")


def defers(command: str) -> bool:
    """True when no word in ``command`` names a deletion verb or a bundled script
    where a command could run it."""
    try:
        _Scan(command).commands(0, None)
    except (_Unreadable, RecursionError):
        return False
    return True


class _Scan:
    def __init__(self, text: str) -> None:
        self.s = text

    def commands(self, i: int, closer: str | None) -> int:
        """Scan commands from ``i`` through ``closer`` (None: the end of the text)."""
        s, n = self.s, len(self.s)
        at_head, head, target, code = True, "", False, False
        pending: list[tuple[str, bool, bool]] = []
        while i < n:
            c = s[i]
            if c in " \t\r":
                i += 1
            elif c == "\n":
                i = self.bodies(i + 1, pending)
                pending, at_head, head, target, code = [], True, "", False, False
            elif c == "#" and closer != "}":
                end = s.find("\n", i)
                i = n if end < 0 else end
            elif c == closer:
                if pending:
                    raise _Unreadable
                return i + 1
            elif c == ")":
                raise _Unreadable
            elif c in ";&|" and not s.startswith("&>", i):
                while i < n and s[i] in ";&|":
                    i += 1
                at_head, head, target, code = True, "", False, False
            elif c == "(":
                i = self.commands(i + 1, ")")
                at_head, head, code = True, "", False
            elif c in "<>&":
                match = _REDIRECT.match(s, i)
                op = match[0] if match else c
                i += len(op)
                if op in ("<(", ">("):
                    i = self.commands(i, ")")
                elif op in ("<<", "<<-"):
                    i = self.heredoc(i, head, op == "<<-", pending)
                elif op == "<<<":
                    while i < n and s[i] in " \t":
                        i += 1
                    i, lit, bare, _ = self.word(i, closer)
                    if _names(lit) & _NAMES:
                        raise _Unreadable  # a here-string may be a shell's script
                    code = self.argument(lit, bare, code)
                else:
                    target = True
            else:
                j, lit, bare, _ = self.word(i, closer)
                if j == i:
                    raise _Unreadable
                i = j
                if target:
                    target = False
                elif closer == "}":
                    pass  # a parameter expansion's words are data; its $() still scanned
                elif lit.isdigit() and s[i : i + 1] in ("<", ">"):
                    continue  # a file descriptor in front of a redirection
                elif at_head:
                    if not (lit in _KEYWORDS or _ASSIGNMENT.match(lit)):
                        head, at_head = self.head(lit), False
                        code = _runs_code(head)
                else:
                    code = self.argument(lit, bare, code)
        if closer is not None or pending:
            raise _Unreadable
        return n

    def word(self, i: int, closer: str | None) -> tuple[int, str, str, bool]:
        """Read one word; return (end, literal text, its unquoted part, quoted)."""
        s, n = self.s, len(self.s)
        out: list[str] = []
        bare: list[str] = []
        quoted = False
        while i < n and s[i] not in _WORD_END and s[i] != closer:
            c = s[i]
            if c == "\\":
                quoted = True
                nxt = s[i + 1 : i + 2]
                out.append("" if nxt == "\n" else nxt)
                i += 2
            elif c == "'":
                end = s.find("'", i + 1)
                if end < 0:
                    raise _Unreadable
                out.append(s[i + 1 : end])
                quoted = True
                i = end + 1
            elif c == '"':
                i, text = self.double(i + 1)
                out.append(text)
                quoted = True
            elif c in "`$":
                i, text = self.expansion(i, _UNQUOTED)
                out.append(text)
                bare.append(text)
            else:
                out.append(c)
                bare.append(c)
                i += 1
        return i, "".join(out), "".join(bare), quoted

    def double(self, i: int) -> tuple[int, str]:
        """Read a double-quoted string whose opening quote ends just before ``i``."""
        s, n = self.s, len(self.s)
        out: list[str] = []
        while i < n:
            c = s[i]
            if c == '"':
                return i + 1, "".join(out)
            if c == "\\":
                nxt = s[i + 1 : i + 2]
                out.append("" if nxt == "\n" else nxt if nxt in '$`"\\' else "\\" + nxt)
                i += 2
            elif c in "`$":
                i, text = self.expansion(i, _QUOTED)
                out.append(text)
            else:
                out.append(c)
                i += 1
        raise _Unreadable

    def expansion(self, i: int, mark: str) -> tuple[int, str]:
        """Scan the backtick or ``$`` at ``i``; return (end, the stand-in text)."""
        s = self.s
        if s[i] == "`":
            return self.backtick(i + 1), mark
        nxt = s[i + 1 : i + 2]
        if nxt == "(":
            return self.commands(i + 2, ")"), mark
        if nxt == "{":
            return self.commands(i + 2, "}"), mark
        if nxt == "'" and mark == _UNQUOTED:
            end = s.find("'", i + 2)
            if "\\" in s[i + 2 : end if end >= 0 else None]:
                raise _Unreadable  # $'\x72m' spells a name no literal shows
            return i + 1, ""  # the quote is read next
        if nxt == '"' and mark == _UNQUOTED:
            return i + 1, ""
        if not (nxt.isalnum() or (nxt and nxt in "_@*#?$!-")):
            return i + 1, "$"  # a `$` that starts no expansion is itself
        return i + 1, mark

    def backtick(self, i: int) -> int:
        """Scan a backtick body that starts at ``i``; return the index after it."""
        s, n = self.s, len(self.s)
        inner: list[str] = []
        while i < n:
            c = s[i]
            if c == "`":
                _Scan("".join(inner)).commands(0, None)
                return i + 1
            if c == "\\" and s[i + 1 : i + 2] in ("`", "\\", "$"):
                inner.append(s[i + 1])
                i += 2
            else:
                inner.append(c)
                i += 1
        raise _Unreadable

    def heredoc(
        self, i: int, head: str, strip: bool, pending: list[tuple[str, bool, bool]]
    ) -> int:
        """Read a heredoc delimiter at ``i``; only a body read as data counts."""
        s, n = self.s, len(self.s)
        if head not in _HEREDOC_DATA_HEADS:
            raise _Unreadable
        while i < n and s[i] in " \t":
            i += 1
        end, delim, _, quoted = self.word(i, None)
        if not delim or _UNQUOTED in delim or _QUOTED in delim:
            raise _Unreadable
        rest = end
        while rest < n and s[rest] in " \t":
            rest += 1
        if rest >= n or s[rest] != "\n":
            raise _Unreadable  # more on the opening line could run the body
        pending.append((delim, strip, quoted))
        return end

    def bodies(self, i: int, pending: list[tuple[str, bool, bool]]) -> int:
        """Skip the heredoc bodies opened on the line that just ended, scanning the
        expansions of an unquoted one."""
        s, n = self.s, len(self.s)
        for delim, strip, quoted in pending:
            body: list[str] = []
            while True:
                if i >= n:
                    raise _Unreadable
                end = s.find("\n", i)
                line = s[i:] if end < 0 else s[i:end]
                i = n if end < 0 else end + 1
                text = line.lstrip("\t") if strip else line
                if text == delim:
                    break
                if text.startswith(delim):
                    raise _Unreadable  # bash ends a heredoc in $() at `EOF)`
                if not quoted and (len(line) - len(line.rstrip("\\"))) % 2:
                    raise _Unreadable  # the backslash joins the next line to it
                body.append(line)
            if not quoted:
                _Scan("\n".join(body)).expansions()
        return i

    def expansions(self) -> None:
        """Scan the ``$`` and backtick expansions of an unquoted heredoc body."""
        s, n, i = self.s, len(self.s), 0
        while i < n:
            if s[i] == "\\":
                i += 2
            elif s[i] in "`$":
                i = self.expansion(i, _QUOTED)[0]
            else:
                i += 1

    @staticmethod
    def head(lit: str) -> str:
        """The command name ``lit`` runs; raise when it cannot be told or is denied."""
        name = _PATH_SPLIT.split(lit)[-1]
        if _UNQUOTED in lit or _QUOTED in name:
            raise _Unreadable
        if name not in ("[", "[[", "{", "}") and any(ch in name for ch in "*?[{}"):
            raise _Unreadable
        stem = _stem(name)
        if stem in _NAMES or stem in _UNREAD_HEADS:
            raise _Unreadable
        return stem

    @staticmethod
    def argument(lit: str, bare: str, code: bool) -> bool:
        """Reject an argument that names a verb or script where a command could run
        it; return whether the words after it are code."""
        whole = _stem(_PATH_SPLIT.split(lit)[-1])
        if (
            whole in _NAMES
            or _names(lit, paths_only=True) & _NAMES
            or _names(bare) & _NAMES
            or (code and _names(lit) & _NAMES)
        ):
            raise _Unreadable
        if code:
            # A shell parses the string again: `r\m`, `r""m` and `r${x}m` are rm.
            _Scan(lit.replace(_QUOTED, "").replace(_UNQUOTED, "")).commands(0, None)
        return code or _runs_code(whole)
