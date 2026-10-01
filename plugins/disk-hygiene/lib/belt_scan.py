"""Decide which Bash commands the disk-hygiene session belt lets through.

The belt's ``if`` filters send deletion-shaped commands to the guard, and Claude
Code also runs every wildcard-led filter on some commands that carry ``$()``, a
backtick or ``$VAR``, so ordinary ``git`` and ``gh`` calls reach the guard too.
``defers`` is a deny-by-default allowlist, not a shell parser. It is True only
for a command that meets all of these:

(a) One simple command: no ``;``, ``&``, ``|``, newline or carriage return
    outside a heredoc body, quoted or not, and no unquoted redirection,
    parenthesis, comment, glob, brace or backslash.
(b) Its first word is exactly ``git`` or ``gh`` (unquoted), a repo-hygiene
    ``skills/clean/scripts`` script or discovery's
    ``scripts/check-dispatch-artifact.sh``, by path. No wrapper or assignment
    comes before it.
(c) No inline-exec vector. For git: no ``-c``, ``--config``, ``--config-env``,
    ``--exec``, ``--exec-path``, ``--upload-pack``, ``--receive-pack`` or
    ``--template`` word, no ``rebase -x``, and a subcommand from a fixed list of
    built-ins, so no alias, ``!`` alias included, can run (git ignores an alias
    that shadows a built-in). For gh: a command from a fixed list (no ``alias``
    or ``extension``), no ``--`` pass-through to git, and no ``api`` input read
    from a file (``--input``, ``@``).
(d) No ``$`` or backtick except a whole double-quoted ``"$(cat <<EOF`` or
    ``"$(cat <<'EOF'`` heredoc word that is the value of git ``-m`` or
    ``--message`` or of gh ``--body``, ``-b``, ``--title`` or ``-t``, ends in
    ``EOF``, a newline and ``)"``, and does not start with ``-``. An unquoted
    body holds no ``$``, backtick or backslash, and no body line starts with
    the delimiter unless it is the delimiter (bash ends a heredoc inside
    ``$()`` at ``EOF)``).
(e) No ``${`` anywhere, heredoc bodies included.

Every other command gets the belt's deny.
"""

from __future__ import annotations

import re
from typing import NamedTuple

# Left out: git's spellings of governed verbs (rm, mv, clean, worktree) and
# commands that run a command or tool they are given (bisect, submodule,
# difftool, mergetool, grep -O, archive, config, help, clone, init).
_GIT_SUBCOMMANDS = frozenset(
    {
        "add", "am", "apply", "blame", "branch", "cat-file", "check-ignore",
        "checkout", "cherry", "cherry-pick", "commit", "describe", "diff", "fetch",
        "for-each-ref", "format-patch", "log", "ls-files", "ls-remote", "ls-tree",
        "merge", "merge-base", "notes", "pull", "push", "range-diff", "rebase",
        "reflog", "remote", "reset", "restore", "rev-list", "rev-parse", "revert",
        "shortlog", "show", "show-ref", "stash", "status", "switch",
        "symbolic-ref", "tag",
    }
)  # fmt: skip
_GIT_VALUE_OPTIONS = frozenset({"-C", "--git-dir", "--work-tree", "--namespace"})
_GIT_EXEC_OPTIONS = (
    "-c", "--config", "--exec", "--upload-pack", "--receive-pack", "--template"
)  # fmt: skip
_REBASE_EXEC = re.compile(r"-[A-Za-z]*x")
# Left out: alias, extension, copilot, codespace, config, auth, browse and the rest.
_GH_COMMANDS = frozenset(
    {
        "api", "cache", "discussion", "gist", "issue", "label", "pr", "project",
        "release", "repo", "ruleset", "run", "search", "status", "variable",
        "workflow",
    }
)  # fmt: skip
_BODY_FLAGS = {"git": ("-m", "--message"), "gh": ("--body", "-b", "--title", "-t")}
_SCRIPT = re.compile(
    r"(?:.*/)?(?:repo-hygiene/(?:[^/]+/)?skills/clean/scripts/(?:clean-batch|"
    r"clean-build|clean-caches|git-branch-audit|git-branch-delete|git-prune|"
    r"git-stash-audit|git-tree-reset|git-tree-reset-batch|preflight|remove-path|"
    r"resolve-clean-action|scan)|discovery/(?:[^/]+/)?scripts/"
    r"check-dispatch-artifact)\.sh"
)
_HEREDOC = re.compile(r"\"\$\(cat <<('?)([A-Za-z_][A-Za-z0-9_]*)\1\n")
_UNQUOTED_REJECT = frozenset(";&|<>()$`#*?[]{}\\\n\r")
_QUOTED_REJECT = frozenset(";&|\n\r")


class _No(Exception):
    """The command is not on the allowlist."""


class _Word(NamedTuple):
    raw: str
    value: str
    heredoc: bool


def defers(command: str) -> bool:
    """True when ``command`` is on the belt's allowlist (module docstring)."""
    if "${" in command:
        return False
    try:
        words = _words(command)
    except _No:
        return False
    if not words or words[0].heredoc:
        return False
    head = words[0].raw
    flags = _BODY_FLAGS.get(head, ())
    for before, word in zip(words, words[1:]):
        if word.heredoc and (before.raw not in flags or word.value.startswith("-")):
            return False
    if head == "git":
        return _git(words[1:])
    if head == "gh":
        return _gh(words[1:])
    return _SCRIPT.fullmatch(words[0].value.replace("\\", "/")) is not None and not any(
        word.heredoc for word in words
    )


def _git(words: list[_Word]) -> bool:
    values = [word.value for word in words]
    if any(value.startswith(_GIT_EXEC_OPTIONS) for value in values):
        return False
    i = 0
    while i < len(values) and values[i].startswith("-"):
        i += 2 if values[i] in _GIT_VALUE_OPTIONS else 1
    if i >= len(words) or words[i].raw not in _GIT_SUBCOMMANDS:
        return False
    return words[i].raw != "rebase" or not any(map(_REBASE_EXEC.match, values))


def _gh(words: list[_Word]) -> bool:
    values = [word.value for word in words]
    if not words or words[0].raw not in _GH_COMMANDS or "--" in values:
        return False
    return words[0].raw != "api" or not any(
        value.startswith(("--input", "@")) or "=@" in value for value in values
    )


def _words(s: str) -> list[_Word]:
    words: list[_Word] = []
    i, n = 0, len(s)
    while i < n:
        if s[i] in " \t":
            i += 1
            continue
        start, value, heredoc = i, [], False
        while i < n and s[i] not in " \t":
            c = s[i]
            match = _HEREDOC.match(s, i) if c == '"' else None
            if match:
                if i != start:
                    raise _No
                i, body = _heredoc(s, match)
                value.append(body)
                heredoc = True
                if i < n and s[i] not in " \t":
                    raise _No
            elif c == "'":
                end = s.find("'", i + 1)
                if end < 0 or _QUOTED_REJECT & set(s[i + 1 : end]):
                    raise _No
                value.append(s[i + 1 : end])
                i = end + 1
            elif c == '"':
                i = _double(s, i + 1, value)
            elif c in _UNQUOTED_REJECT:
                raise _No
            else:
                value.append(c)
                i += 1
        words.append(_Word(s[start:i], "".join(value), heredoc))
    return words


def _double(s: str, i: int, value: list[str]) -> int:
    """Read a double-quoted string whose opening quote ends just before ``i``."""
    while i < len(s):
        c = s[i]
        if c == '"':
            return i + 1
        if c in "$`" or c in _QUOTED_REJECT:
            raise _No
        if c == "\\":
            nxt = s[i + 1 : i + 2]
            if not nxt or nxt in "$`" or nxt in _QUOTED_REJECT:
                raise _No
            value.append(nxt if nxt in '"\\' else c + nxt)
            i += 2
        else:
            value.append(c)
            i += 1
    raise _No


def _heredoc(s: str, match: re.Match[str]) -> tuple[int, str]:
    """Read a ``"$(cat <<EOF`` heredoc word; return (its end, the body)."""
    quoted, delim = match[1] == "'", match[2]
    lines: list[str] = []
    i = match.end()
    while True:
        end = s.find("\n", i)
        if end < 0:
            raise _No
        line, i = s[i:end], end + 1
        if line == delim:
            break
        if line.startswith(delim) or (not quoted and set("$`\\") & set(line)):
            raise _No
        lines.append(line)
    if not s.startswith(')"', i):
        raise _No
    return i + 2, "\n".join(lines)
