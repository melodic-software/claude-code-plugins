#!/usr/bin/env python3
"""case_skills - extract skill and agent references from an eval case.

Shared between `validate-cases.py` and other eval tooling so every caller
reads a case's skill-under-test and reference signals by one rule:

  - leading `/plugin:skill` or bare `/skill` at the start of the prompt
  - `plugin:skill` or bare `skill` tags
  - `tool_used` graders on `Skill` or `Agent` whose `input_match` holds a
    literal `plugin:name` token, an optional-prefix `(?:plugin:)?name` form,
    or (for `Skill`) a bare `"skill":"name"` JSON-ish value

Python 3.8+, standard library only.
"""

import collections
import re

MIN_PYTHON = (3, 8)

LEADING_REFERENCE = re.compile(
    r"^\s*/([A-Za-z][\w-]*):([A-Za-z][\w-]*)(?=[\s:,.;]|$)"
)
LEADING_BARE_REFERENCE = re.compile(
    r"^\s*/([A-Za-z][\w-]*)(?=[\s,.;]|:(?![\w-])|$)"
)
TAG_REFERENCE = re.compile(r"^([A-Za-z][\w-]*):([A-Za-z][\w-]*)$")
TAG_BARE_REFERENCE = re.compile(r"^([A-Za-z][\w-]*)$")
HOLE = "\x00"
LITERAL_REFERENCE = re.compile(
    r"(?<![\w.:\x00-])(/?)([A-Za-z][\w-]*):([A-Za-z][\w-]*)(?![\w:(\[.?*+{\x00-])"
)
OPTIONAL_PREFIX_REFERENCE = re.compile(
    r"(?<![\w.:\x00-])(/?)([A-Za-z][\w-]*):\x00\?([A-Za-z][\w-]*)(?![\w:(\[.?*+{\x00-])"
)
_OPT_WS = r"(?:\s|\x00(?:[?*+]|\{[0-9,]+\})?)*"
BARE_SKILL_REFERENCE = re.compile(
    r'"skill"' + _OPT_WS + r":" + _OPT_WS + r'"(/?)([A-Za-z][\w-]*)(?![\w:(\[.?*+{\x00-])'
)
LOOKAROUNDS = ("(?=", "(?!", "(?<=", "(?<!")
GROUP_OPENER = re.compile(r"\((?:\?:|\?P?<[A-Za-z_]\w*>)?(?!\?)")
QUANTIFIERS = ("?", "*", "+", "{")
NAME_CONTINUES = re.compile(r"[\w.(\[-]|\\[^bB]")
REFERENCE_KINDS = {
    "skill": lambda plugin, name: (plugin, "skills", name, "SKILL.md"),
    "agent": lambda plugin, name: (plugin, "agents", name + ".md"),
}
TOOL_KINDS = {"Skill": "skill", "Agent": "agent"}

Reference = collections.namedtuple(
    "Reference",
    ("source", "file", "plugin", "name", "kind", "prefix", "form"),
    defaults=("literal",),
)


def _class_end(pattern, start):
    index = start + 1
    if pattern.startswith("^", index):
        index += 1
    if pattern.startswith("]", index):
        index += 1
    while index < len(pattern):
        if pattern[index] == "\\":
            index += 2
            continue
        if pattern[index] == "]":
            return index + 1
        index += 1
    return len(pattern)


def _group_end(pattern, start):
    depth = 0
    index = start
    while index < len(pattern):
        char = pattern[index]
        if char == "\\":
            index += 2
            continue
        if char == "[":
            index = _class_end(pattern, index)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return len(pattern)


def literal_text(pattern):
    """The pattern with only the characters it matches literally, and for
    each output character the source index just past it: an escaped symbol
    becomes itself, `\\b` and `\\B` a space, a group's parentheses nothing
    unless a quantifier follows the close, and any other escape, a character
    class, a quantified group's close or a lookaround or flag group a HOLE."""
    out = []
    starts = []
    ends = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        start = index
        if char == "\\" and index + 1 < len(pattern):
            escaped = pattern[index + 1]
            if escaped in "bB":
                piece = " "
            elif escaped.isalnum() or escaped == "_":
                piece = HOLE
            else:
                piece = escaped
            index += 2
        elif char == "[":
            piece = HOLE
            index = _class_end(pattern, index)
        elif pattern.startswith(LOOKAROUNDS, index):
            piece = HOLE
            index = _group_end(pattern, index)
        elif char == "(":
            opener = GROUP_OPENER.match(pattern, index)
            if opener:
                piece = ""
                index = opener.end()
            else:
                piece = HOLE
                index = _group_end(pattern, index)
        elif char == ")":
            piece = HOLE if pattern[index + 1 : index + 2] in QUANTIFIERS else ""
            index += 1
        else:
            piece = char
            index += 1
        if piece:
            out.append(piece)
            starts.append(start)
            ends.append(index)
    return "".join(out), starts, ends


def _enclosing_close(pattern, index):
    """The index of the `)` closing the group around `index`, else None."""
    depth = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "\\":
            index += 2
            continue
        if char == "[":
            index = _class_end(pattern, index)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                return index
            depth -= 1
        index += 1
    return None


def alternation_groups(pattern):
    """The (open, close) source indices of each group holding a top-level `|`."""
    spans = []
    stack = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "\\":
            index += 2
            continue
        if char == "[":
            index = _class_end(pattern, index)
            continue
        if char == "(":
            stack.append([index, False])
        elif char == "|" and stack:
            stack[-1][1] = True
        elif char == ")" and stack:
            opened, alternation = stack.pop()
            if alternation:
                spans.append((opened, index))
        index += 1
    return spans


def reference_reach(pattern, start, end):
    """For a token spanning source [start, end): None when it is not one
    literal name (it crosses a group with alternatives, or such a group it
    ends in is followed by more of a name), else whether it is open on the
    right, so a prefix of a real name resolves it."""
    for opened, closed in alternation_groups(pattern):
        if start < opened < end or start < closed < end:
            return None
    index = end
    while index < len(pattern):
        char = pattern[index]
        if char == ")":
            index += 1
        elif char == "|":
            close = _enclosing_close(pattern, index)
            if close is None:
                return True
            if NAME_CONTINUES.match(pattern, close + 1):
                return None
            index = close + 1
        else:
            return False
    return True


def _is_escaped(pattern, index):
    backslashes = 0
    pos = index - 1
    while pos >= 0 and pattern[pos] == "\\":
        backslashes += 1
        pos -= 1
    return (backslashes % 2) == 1


def _optional_prefix_open(pattern, inner_start, close_pos):
    """The `(` index when pattern[open:close_pos+1] is a single group wrapping
    only the prefix ending at close_pos and followed by `?`, else None."""
    if pattern[close_pos : close_pos + 2] != ")?":
        return None
    open_pos = pattern.rfind("(", 0, inner_start)
    if open_pos < 0 or _is_escaped(pattern, open_pos):
        return None
    opener = GROUP_OPENER.match(pattern, open_pos)
    if not opener or opener.end() != inner_start:
        return None
    if _group_end(pattern, open_pos) != close_pos + 1:
        return None
    return open_pos


def _grader_references(pattern, kind, path):
    """Deduplicated Reference list extracted from one tool_used input_match."""
    text, starts, ends = literal_text(pattern)
    found = []
    for match in LITERAL_REFERENCE.finditer(text):
        reach = reference_reach(
            pattern, starts[match.start()], ends[match.end() - 1]
        )
        if reach is not None:
            slash, plugin, target = match.groups()
            found.append(
                (
                    match.start(),
                    Reference(
                        "grader",
                        path,
                        plugin,
                        target,
                        "skill" if slash else kind,
                        reach,
                        "literal",
                    ),
                )
            )
    for match in OPTIONAL_PREFIX_REFERENCE.finditer(text):
        close_pos = starts[match.end(2) + 1]
        open_pos = _optional_prefix_open(pattern, starts[match.start(2)], close_pos)
        if open_pos is None and match.group(1) == "/":
            open_pos = _optional_prefix_open(
                pattern, starts[match.start(1)], close_pos
            )
        if open_pos is None:
            continue
        reach = reference_reach(pattern, open_pos, ends[match.end() - 1])
        if reach is not None:
            slash, plugin, target = match.groups()
            found.append(
                (
                    match.start(),
                    Reference(
                        "grader",
                        path,
                        plugin,
                        target,
                        "skill" if slash else kind,
                        reach,
                        "optional-prefix",
                    ),
                )
            )
    if kind == "skill":
        for match in BARE_SKILL_REFERENCE.finditer(text):
            reach = reference_reach(
                pattern, starts[match.start()], ends[match.end() - 1]
            )
            if reach is not None:
                found.append(
                    (
                        match.start(),
                        Reference(
                            "grader",
                            path,
                            None,
                            match.group(2),
                            "skill",
                            reach,
                            "bare",
                        ),
                    )
                )
    found.sort(key=lambda item: item[0])
    return list(dict.fromkeys(ref for _, ref in found))


def references(prompt, prompt_file, tag_sources, graders):
    """Extract Reference items from a case in order: prompt, tags, graders."""
    result = []
    if isinstance(prompt, str):
        match = LEADING_REFERENCE.match(prompt)
        if match:
            result.append(
                Reference(
                    "prompt",
                    prompt_file,
                    match.group(1),
                    match.group(2),
                    "skill",
                    False,
                    "literal",
                )
            )
        else:
            bare = LEADING_BARE_REFERENCE.match(prompt)
            if bare:
                result.append(
                    Reference(
                        "prompt",
                        prompt_file,
                        None,
                        bare.group(1),
                        "skill",
                        False,
                        "bare",
                    )
                )
    for tags, path in tag_sources or ():
        for tag in tags:
            text = str(tag)
            match = TAG_REFERENCE.match(text)
            if match:
                result.append(
                    Reference(
                        "tag",
                        path,
                        match.group(1),
                        match.group(2),
                        "skill",
                        False,
                        "literal",
                    )
                )
            else:
                bare = TAG_BARE_REFERENCE.match(text)
                if bare:
                    result.append(
                        Reference(
                            "tag",
                            path,
                            None,
                            bare.group(1),
                            "skill",
                            False,
                            "bare",
                        )
                    )
    for _, options, path in graders or ():
        if not isinstance(options, dict) or options.get("type") != "tool_used":
            continue
        kind = TOOL_KINDS.get(options.get("tool"))
        pattern = options.get("input_match")
        if not kind or not isinstance(pattern, str):
            continue
        result.extend(_grader_references(pattern, kind, path))
    return result


def resolve(reference, suite_plugin):
    """Resolve a Reference to (plugin, name), defaulting bare names to suite_plugin."""
    return (
        suite_plugin if reference.plugin is None else reference.plugin,
        reference.name,
    )


def skills_under_test(prompt, prompt_file, tag_sources, graders, suite_plugin):
    """Set of resolved (plugin, name) pairs for every skill reference in a case."""
    return {
        resolve(ref, suite_plugin)
        for ref in references(prompt, prompt_file, tag_sources, graders)
        if ref.kind == "skill"
    }
