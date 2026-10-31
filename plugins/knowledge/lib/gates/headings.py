"""Heading and code-fence recognizers for markdown and HTML snapshots.

One source for the line patterns the gates and the node extractor split a
snapshot on. Each caller picks the options that give its own rules (the gates
read text, the extractor reads bytes), so callers that need different answers
still share one definition of each form. Every builder returns a compiled
pattern for ``str`` or, with ``binary=True``, for ``bytes``.

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import re
from typing import AnyStr, Match, Optional, Pattern, Union

# Leading whitespace a fence opener may carry.
INDENT_ANY = "any"  # any run of whitespace
INDENT_SPACES_TABS = "spaces-tabs"  # any run of spaces and tabs
INDENT_COMMONMARK = "commonmark"  # at most three spaces

_FENCE_INDENT = {
    INDENT_ANY: r"\s*",
    INDENT_SPACES_TABS: r"[ \t]*",
    INDENT_COMMONMARK: r" {0,3}",
}

# What may follow an ATX heading's text.
TRAIL_BLANK = "blank"  # spaces and tabs
TRAIL_CLOSING = "closing"  # spaces and tabs around an optional run of `#`
TRAIL_WHITESPACE = "whitespace"  # any whitespace, a trailing \r included

_ATX_TRAIL = {
    TRAIL_BLANK: r"[ \t]*",
    TRAIL_CLOSING: r"[ \t]*#*[ \t]*",
    TRAIL_WHITESPACE: r"\s*",
}


def _compile(pattern: str, binary: bool, flags: int = 0) -> Pattern:
    return re.compile(pattern.encode("ascii") if binary else pattern, flags)


def atx_heading(
    *,
    level: Optional[int] = None,
    max_indent: int = 3,
    title_required: bool = False,
    trail: str = TRAIL_BLANK,
    binary: bool = False,
) -> Pattern:
    """An ATX heading line: group 1 the `#` run, group 2 the text (or None).

    ``level`` fixes the heading level; without it any of 1 to 6 matches.
    ``max_indent`` is how many leading spaces are allowed. With
    ``title_required`` a bare `##` is not a heading. ``trail`` names what may
    follow the text; a closing `#` run kept in the text is
    ``closing_sequence``'s to remove.
    """
    hashes = "#{1,6}" if level is None else "#" * level
    indent = f" {{0,{max_indent}}}" if max_indent else ""
    text = r"[ \t]+(.+?)" if title_required else r"(?:[ \t]+(.*?))?"
    return _compile(f"^{indent}({hashes})(?!#){text}{_ATX_TRAIL[trail]}$", binary)


def closing_sequence(*, binary: bool = False) -> Pattern:
    """A CommonMark closing sequence at the end of ATX heading text: blanks, then `#`s."""
    return _compile(r"[ \t]+#+[ \t]*$", binary)


def setext_underline(*, binary: bool = False) -> Pattern:
    """A setext underline: group 1 the `=` (level 1) or `-` (level 2) run."""
    return _compile(r"^ {0,3}(=+|-+)[ \t]*$", binary)


def html_heading(
    *, line_start: bool = False, require_id: bool = False, binary: bool = False
) -> Pattern:
    """An HTML heading open tag, case-insensitive: group 1 the level.

    With ``line_start`` the tag must open the line (after whitespace) and
    group 2 is the rest of the line; otherwise the tag matches anywhere. With
    ``require_id`` the tag must carry an ``id`` attribute.
    """
    attrs = r"\s[^>]*(?<![\w-])id\s*=[^>]*" if require_id else r"(?:\s[^>]*)?"
    pattern = f"<h([1-6]){attrs}>"
    if line_start:
        pattern = rf"^\s*{pattern}(.*)$"
    return _compile(pattern, binary, re.IGNORECASE)


def fence(
    *, chars: str = "`~", indent: str = INDENT_ANY, binary: bool = False
) -> Pattern:
    """A code-fence line: group 1 the run of three or more fence characters,
    group 2 the rest of the line. An opener is any match; whether a line closes
    an open fence is ``closes_fence``'s. ``match.start(1) > 0`` means indented.
    """
    runs = "|".join(f"{re.escape(c)}{{3,}}" for c in chars)
    return _compile(f"^{_FENCE_INDENT[indent]}({runs})(.*)$", binary)


def closes_fence(
    match: Optional[Match[AnyStr]],
    opener: AnyStr,
    *,
    blank: Union[str, bytes, None] = None,
) -> bool:
    """True when ``match`` (a ``fence`` match, or None) closes a fence opened by
    the run ``opener``: the same character, a run at least as long, and nothing
    after it but characters in ``blank`` (None: any whitespace).
    """
    if match is None:
        return False
    run = match.group(1)
    return (
        run[:1] == opener[:1]
        and len(run) >= len(opener)
        and not match.group(2).strip(blank)
    )
