#!/usr/bin/env python3
"""Classify an edit by what it did to the code, ignoring comments.

Compares the comment-stripped sequence of parse-tree leaves of a file before
and after an edit. The verdict is a proof about tokens, which is the claim a
comment-dissolving edit has to make and a test suite can only sample:

  COMMENT-ONLY   no code token changed. A deletion with this verdict is safe
                 to apply in a repository with no tests at all.
  RENAME-ONLY    every differing leaf is an identifier and the old->new mapping
                 is consistent. A SHAPE claim, not a safety claim: it knows
                 nothing about shadowing, outer-scope collisions, reflection or
                 string-keyed access, so it earns a lighter review, never an
                 unattended apply.
  CODE-CHANGED   some non-identifier token differs, or the token count moved.
  UNPROVABLE     a side failed to parse cleanly (ERROR/MISSING nodes), so no
                 token-level claim can be made. Treated as CODE-CHANGED by any
                 gate.

Exit codes carry the verdict so a shell gate can branch on them without
parsing text: 0 COMMENT-ONLY, 10 RENAME-ONLY, 20 CODE-CHANGED, 21 UNPROVABLE,
3 tree-sitter or the grammar for this language is unavailable, 2 usage.

The shebang is the one comment the proof must not ignore: tree-sitter's bash
grammar types `#!/usr/bin/env bash` as a comment, and dropping it would let a
shebang deletion pass as COMMENT-ONLY.

Usage: change-shape.py [--lang <name>] [--json] BEFORE AFTER
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from importlib import import_module
from pathlib import Path

EXIT_COMMENT_ONLY = 0
EXIT_RENAME_ONLY = 10
EXIT_CODE_CHANGED = 20
EXIT_UNPROVABLE = 21
EXIT_NO_TOOLING = 3
EXIT_USAGE = 2

# Extension -> (grammar language name, per-language wheel module, attribute
# on that module that returns the language pointer).
EXT_LANG = {
    ".py": ("python", "tree_sitter_python", "language"),
    ".pyi": ("python", "tree_sitter_python", "language"),
    ".ts": ("typescript", "tree_sitter_typescript", "language_typescript"),
    ".mts": ("typescript", "tree_sitter_typescript", "language_typescript"),
    ".cts": ("typescript", "tree_sitter_typescript", "language_typescript"),
    ".tsx": ("tsx", "tree_sitter_typescript", "language_tsx"),
    ".js": ("javascript", "tree_sitter_javascript", "language"),
    ".mjs": ("javascript", "tree_sitter_javascript", "language"),
    ".cjs": ("javascript", "tree_sitter_javascript", "language"),
    ".jsx": ("javascript", "tree_sitter_javascript", "language"),
    ".sh": ("bash", "tree_sitter_bash", "language"),
    ".bash": ("bash", "tree_sitter_bash", "language"),
    ".cs": ("csharp", "tree_sitter_c_sharp", "language"),
    ".yml": ("yaml", "tree_sitter_yaml", "language"),
    ".yaml": ("yaml", "tree_sitter_yaml", "language"),
}

# Leaf kinds that count as identifiers for the RENAME-ONLY verdict. Anything
# else that differs is a code change.
IDENTIFIER_KINDS = frozenset(
    {
        "identifier",
        "type_identifier",
        "property_identifier",
        "field_identifier",
        "variable_name",
        "word",
        "shorthand_property_identifier",
        "shorthand_property_identifier_pattern",
        "statement_identifier",
    }
)


def language_for(name: str, module: str, attr: str):
    """Load a grammar from its per-language wheel, else the language pack.

    Returns (Language, source) or (None, reason).
    """
    try:
        from tree_sitter import Language
    except ImportError:
        return None, "tree-sitter is not installed (pip install tree-sitter)"
    try:
        mod = import_module(module)
        return Language(getattr(mod, attr)()), module
    except (ImportError, AttributeError):
        pass
    try:
        from tree_sitter_language_pack import get_language

        return get_language(name), "tree_sitter_language_pack"
    except Exception:  # noqa: BLE001 - the pack downloads at runtime and can fail any way
        return None, f"no grammar for {name} (pip install {module})"


def leaves(src: bytes, lang) -> tuple[list[tuple[str, str]], bool]:
    """Terminal tokens minus comments, plus whether the parse had errors."""
    from tree_sitter import Parser

    tree = Parser(lang).parse(src)
    out: list[tuple[str, str]] = []
    broken = False
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type in ("ERROR", "MISSING") or node.is_missing:
            broken = True
        if "comment" in node.type:
            is_shebang = (
                node.start_point[0] == 0
                and src[node.start_byte : node.start_byte + 2] == b"#!"
            )
            if not is_shebang:
                continue
            out.append(
                (
                    "shebang",
                    src[node.start_byte : node.end_byte].decode(errors="replace"),
                )
            )
            continue
        if node.child_count == 0:
            text = src[node.start_byte : node.end_byte].decode(errors="replace")
            if text.strip():
                out.append((node.type, text))
        else:
            stack.extend(reversed(node.children))
    return out, broken


def classify(before: bytes, after: bytes, lang) -> tuple[str, int, dict]:
    a, a_broken = leaves(before, lang)
    b, b_broken = leaves(after, lang)
    if a_broken or b_broken:
        side = "before" if a_broken else "after"
        return (
            "UNPROVABLE",
            EXIT_UNPROVABLE,
            {"reason": f"{side} side has parse errors"},
        )
    if a == b:
        return "COMMENT-ONLY", EXIT_COMMENT_ONLY, {"tokens": len(a)}
    if len(a) != len(b):
        return (
            "CODE-CHANGED",
            EXIT_CODE_CHANGED,
            {"tokens_before": len(a), "tokens_after": len(b)},
        )
    diffs = [(x, y) for x, y in zip(a, b) if x != y]
    if all(x[0] in IDENTIFIER_KINDS and y[0] in IDENTIFIER_KINDS for x, y in diffs):
        mapping: dict[str, str] = {}
        reverse: dict[str, str] = {}
        for (_, old), (_, new) in diffs:
            if mapping.setdefault(old, new) != new:
                return (
                    "CODE-CHANGED",
                    EXIT_CODE_CHANGED,
                    {"reason": "inconsistent identifier mapping", "at": old},
                )
            if reverse.setdefault(new, old) != old:
                # Two renamed identifiers collapsing onto one name is a merge,
                # not a rename: the mapping must be injective as well as consistent.
                return (
                    "CODE-CHANGED",
                    EXIT_CODE_CHANGED,
                    {"reason": "two identifiers collapse to one name", "at": new},
                )
        # The diff only sees positions that changed. An old name still present
        # at an unchanged position is a rename that missed a reference; a new
        # name already present at one is a rename onto an existing identifier.
        unchanged = {
            text
            for (kind, text), y in zip(a, b)
            if kind in IDENTIFIER_KINDS and (kind, text) == y
        }
        stale = sorted(old for old in mapping if old in unchanged)
        if stale:
            return (
                "CODE-CHANGED",
                EXIT_CODE_CHANGED,
                {
                    "reason": "incomplete rename: old name still referenced",
                    "at": stale[0],
                },
            )
        collision = sorted(new for new in reverse if new in unchanged)
        if collision:
            return (
                "CODE-CHANGED",
                EXIT_CODE_CHANGED,
                {
                    "reason": "rename collides with an existing identifier",
                    "at": collision[0],
                },
            )
        return "RENAME-ONLY", EXIT_RENAME_ONLY, {"mapping": mapping}
    kinds = sorted({x[0] for x, _ in diffs})
    return (
        "CODE-CHANGED",
        EXIT_CODE_CHANGED,
        {"differing_leaves": len(diffs), "kinds": kinds},
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument(
        "--lang", help="grammar name; default is derived from AFTER's extension"
    )
    parser.add_argument(
        "--json", action="store_true", help="emit the verdict as one JSON object"
    )
    args = parser.parse_args(argv)

    ext = args.after.suffix.lower() or args.before.suffix.lower()
    entry = EXT_LANG.get(ext)
    if args.lang:
        entry = next((e for e in EXT_LANG.values() if e[0] == args.lang), None)
        if entry is None:
            print(f"change-shape: unknown --lang {args.lang!r}", file=sys.stderr)
            return EXIT_USAGE
    if entry is None:
        print(
            f"change-shape: no grammar mapping for extension {ext!r}; pass --lang",
            file=sys.stderr,
        )
        return EXIT_USAGE

    lang, source = language_for(*entry)
    if lang is None:
        print(f"change-shape: UNAVAILABLE: {source}", file=sys.stderr)
        return EXIT_NO_TOOLING

    try:
        before = args.before.read_bytes()
        after = args.after.read_bytes()
    except OSError as exc:
        print(f"change-shape: {exc}", file=sys.stderr)
        return EXIT_USAGE

    verdict, code, detail = classify(before, after, lang)
    if args.json:
        print(
            json.dumps(
                {"verdict": verdict, "language": entry[0], "grammar": source, **detail},
                sort_keys=True,
            )
        )
    else:
        extra = " ".join(f"{k}={v}" for k, v in detail.items())
        print(f"{verdict} ({entry[0]} via {os.path.basename(source)}) {extra}".rstrip())
    return code


if __name__ == "__main__":
    sys.exit(main())
