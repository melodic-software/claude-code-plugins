#!/usr/bin/env python3
"""Report exec-form hook objects declared in skill/agent YAML frontmatter.

Helper for `scripts/check-hook-exec-form.sh`, which owns the RULE (what makes a
`command` unacceptable) and applies it to both declaration surfaces. This script
owns only the READING of the frontmatter surface, and emits what it finds as
tab-separated records on stdout:

    V<TAB><file><TAB><line><TAB><command>   an exec-form hook object
    X<TAB><file><TAB><line><TAB><reason>    frontmatter that could not be read

Why a real YAML parser, and why Python
--------------------------------------
This started as an awk walk over block-style YAML. Review found four ways past
it in three rounds -- a quoted key (`"hooks":`), an escaped key
(`"\\u0068ooks":`, then `"\\U00000068ooks":`), an alias under the key, and a
brace inside an ordinary scalar read as flow style. Each fix enlarged the
hand-rolled parser and invited the next case, because "which spellings does YAML
permit" has no natural end. A gate that misparses is worse than no gate: it
either blocks valid frontmatter or waves through the very defect it exists to
catch, and this one had done both.

PyYAML settles the class by construction. Quoted and escaped keys arrive already
decoded by the scanner; anchors, aliases, and merge keys resolve; flow and block
style are the same document. Nothing here pattern-matches YAML text.

The sibling `check-hook-userconfig-argv.sh` stays in shell because its surface is
JSON, which `jq` -- already a hard dependency of that gate and this one -- parses
completely. No such tool ships for YAML, so this surface takes the dependency
instead of a parser we would have to keep patching. PyYAML is pinned in
`.github/requirements-ci.txt`; a missing module is an environment error (exit 2),
never a silent pass.

Scope: `hooks` is read only as a TOP-LEVEL frontmatter key, the one position
Claude Code loads a skill or agent hook from. A `hooks:` mapping nested under
another key is data, not a registration, and prose or a fenced example in the
body is never frontmatter at all.
"""

import os
import sys

try:
    import yaml
except ModuleNotFoundError:
    print(
        "check-hook-exec-form: PyYAML is required to read skill/agent frontmatter "
        "but is not installed (pip install pyyaml; CI pins it in "
        ".github/requirements-ci.txt)",
        file=sys.stderr,
    )
    sys.exit(2)

FRONTMATTER_OPEN = "---"
FRONTMATTER_CLOSE = ("---", "...")


def emit(kind: str, path: str, line: int, detail: str) -> None:
    """Write one record. Tabs and newlines in detail would break the framing."""
    flat = detail.replace("\t", " ").replace("\r", "").replace("\n", " ").strip()
    print(f"{kind}\t{path}\t{line}\t{flat}")


def frontmatter_of(text: str) -> tuple[str, int] | None:
    """Return (frontmatter body, 1-based line number of its first line).

    None when the file does not open with a frontmatter delimiter, or opens one
    it never closes -- an unterminated block is not frontmatter to any reader.
    """
    lines = text.split("\n")
    if not lines or lines[0].rstrip("\r") != FRONTMATTER_OPEN:
        return None
    for index in range(1, len(lines)):
        if lines[index].rstrip("\r") in FRONTMATTER_CLOSE:
            return "\n".join(lines[1:index]), 2
    return None


def mapping_entries(node, seen):
    """Yield (key, value_node, key_node) for a mapping, expanding merge keys.

    An explicit key wins over one arriving through `<<`, which is the merge
    key's defined precedence. `seen` guards the recursion against a document
    that merges a cycle. Duplicate explicit keys are NOT resolved here -- see
    duplicate_keys(); a caller that interprets a mapping must refuse an
    ambiguous one rather than pick a winner.
    """
    explicit = {}
    merged = {}
    for key_node, value_node in node.value:
        key = getattr(key_node, "value", None)
        if not isinstance(key, str):
            continue
        if key == "<<":
            for source in value_node.value if isinstance(value_node, yaml.SequenceNode) else [value_node]:
                if not isinstance(source, yaml.MappingNode) or id(source) in seen:
                    continue
                seen.add(id(source))
                for merged_key, merged_value, _ in mapping_entries(source, seen):
                    merged.setdefault(merged_key, merged_value)
                seen.discard(id(source))
            continue
        explicit[key] = (value_node, key_node)
    for key, (value_node, key_node) in explicit.items():
        yield key, value_node, key_node
    for key, value_node in merged.items():
        if key not in explicit:
            yield key, value_node, node


def duplicate_keys(node):
    """Return (key, second key_node) for each explicit key repeated in a mapping.

    A repeated key makes the document ambiguous, and readers disagree about it:
    PyYAML's loader keeps the last value, js-yaml rejects the document outright.
    This repo has already shipped a duplicate key through a fully green suite
    (#1492, which is why scripts/check-manifest-duplicate-keys.py exists), so
    this is a shape that reaches production, not a spec curiosity. A gate must
    not pick the reading that clears the file, so callers report instead.
    """
    first = set()
    repeated = []
    for key_node, _ in node.value:
        key = getattr(key_node, "value", None)
        if not isinstance(key, str) or key == "<<":
            continue
        if key in first:
            repeated.append((key, key_node))
        else:
            first.add(key)
    return repeated


def scan_node(node, path: str, offset: int, seen: set) -> None:
    """Report every mapping in this subtree carrying both `command` and `args`."""
    if node is None or id(node) in seen:
        return
    seen.add(id(node))
    if isinstance(node, yaml.SequenceNode):
        for item in node.value:
            scan_node(item, path, offset, seen)
    elif isinstance(node, yaml.MappingNode):
        for key, key_node in duplicate_keys(node):
            emit(
                "X",
                path,
                key_node.start_mark.line + offset,
                f"duplicate `{key}` key inside the hooks declaration; readers disagree on which wins",
            )
            return
        entries = {key: (value, key_node) for key, value, key_node in mapping_entries(node, set())}
        if "command" in entries and "args" in entries:
            command_node, command_key_node = entries["command"]
            line = command_key_node.start_mark.line + offset
            if isinstance(command_node, yaml.ScalarNode):
                emit("V", path, line, command_node.value)
            else:
                emit("X", path, line, "an exec-form hook whose `command` is not a scalar")
        for _, value_node, _ in mapping_entries(node, set()):
            scan_node(value_node, path, offset, seen)
    seen.discard(id(node))


def scan_file(path: str) -> None:
    try:
        with open(path, encoding="utf-8", errors="strict") as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError) as error:
        emit("X", path, 1, f"could not be read as UTF-8 text ({error.__class__.__name__})")
        return

    block = frontmatter_of(text)
    if block is None:
        return
    body, offset = block
    try:
        root = yaml.compose(body, Loader=yaml.SafeLoader)
    except yaml.YAMLError as error:
        mark = getattr(error, "problem_mark", None)
        line = (mark.line + offset) if mark is not None else offset
        emit("X", path, line, "the YAML frontmatter does not parse, so this gate cannot clear it")
        return

    if not isinstance(root, yaml.MappingNode):
        return
    for key, key_node in duplicate_keys(root):
        if key == "hooks":
            emit(
                "X",
                path,
                key_node.start_mark.line + offset,
                "duplicate top-level `hooks` key; readers disagree on which declaration wins",
            )
            return
    for key, value_node, _ in mapping_entries(root, set()):
        if key == "hooks":
            scan_node(value_node, path, offset, set())


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: check-hook-exec-form-frontmatter.py <root> [<root> ...]", file=sys.stderr)
        return 2
    for root in argv[1:]:
        for directory, _, filenames in os.walk(root):
            for filename in sorted(filenames):
                if filename.endswith(".md"):
                    scan_file(os.path.join(directory, filename).replace(os.sep, "/"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
