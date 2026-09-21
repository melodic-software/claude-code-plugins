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
3 tree-sitter or the grammar for this language is unavailable, 2 usage, an
unmapped extension, or no PowerShell host for a `.ps1`/`.psm1` file.

`.ps1` and `.psm1` are read by PowerShell's own tokenizer through
`ps-tokens.ps1` under `pwsh`, not by a tree-sitter grammar: the maintained
grammar returns ERROR nodes on ordinary PowerShell, which would make every
real file UNPROVABLE. With no `pwsh` on PATH the answer is exit 2, an
*unproven* edit, never the exit 3 that lets a coarser reading layer apply
deletions anyway.

Two comments the proof must not ignore: a shebang on line 1, which both
tree-sitter's bash grammar and PowerShell type as a comment, and `#Requires`,
which PowerShell also does. Dropping either would let deleting a directive pass
as COMMENT-ONLY.

Usage: change-shape.py [--lang <name>] [--json] BEFORE AFTER
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
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
# on that module that returns the language pointer). A None module marks the
# native PowerShell backend, which loads no grammar.
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
    ".toml": ("toml", "tree_sitter_toml", "language"),
    ".ps1": ("powershell", None, None),
    ".psm1": ("powershell", None, None),
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
        # PowerShell. Not `Identifier`, which is both member names and type
        # names, so `[string]` -> `[int]` would read as a rename; not `Generic`,
        # which is command names and bare-word arguments; not `Parameter`, which
        # is a cross-file call-site contract.
        "Variable",
        "SplattedVariable",
        # A variable read out of an expandable string, normalized to `$name`.
        "InterpolatedVariable",
    }
)

PS_SCRIPT = Path(__file__).with_name("ps-tokens.ps1")
# `#requires` is accepted in any case and must survive stripping as the shebang
# does: deleting it leaves the token stream identical.
PS_REQUIRES = re.compile(r"^\s*#requires\b", re.IGNORECASE)


class PowerShellUnavailable(Exception):
    """No usable PowerShell host, so no token-level claim can be made."""


def powershell_records(*args: str) -> list[dict]:
    """Run ps-tokens.ps1 under pwsh; one JSON object per output line."""
    host = shutil.which("pwsh")
    if host is None:
        raise PowerShellUnavailable("no PowerShell host: pwsh is not on PATH")
    cmd = [host, "-NoProfile", "-NonInteractive"]
    if os.name == "nt":
        # A Windows client's default policy is Restricted, where -File refuses
        # to run at all and the failure would read as a tooling absence.
        cmd += ["-ExecutionPolicy", "Bypass"]
    # ponytail: one pwsh process per verdict (~0.5 s of startup plus ~1 s per
    # megabyte of source). Batch N pairs per process if a large run measures
    # badly; do not build the batch before it does.
    proc = subprocess.run(
        [*cmd, "-File", str(PS_SCRIPT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if proc.returncode != 0:
        raise PowerShellUnavailable(
            f"ps-tokens.ps1 exited {proc.returncode}: {proc.stderr.strip()[:300]}"
        )
    try:
        return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    except json.JSONDecodeError as exc:
        raise PowerShellUnavailable(f"ps-tokens.ps1 output is not JSON: {exc}") from exc


def powershell_leaves(record: dict) -> list[tuple[str, str]]:
    """Tokens minus comments, with the directive comments kept as leaves."""
    flat = record["tokens"]
    # Tokens read out of an expandable string, keyed on that string's position.
    triples = record["nested"]
    extra: dict[int, list[tuple[str, str]]] = {}
    for j in range(0, len(triples), 3):
        extra.setdefault(int(triples[j]), []).append(
            (triples[j + 1], triples[j + 2])
        )

    def stream():
        for i in range(0, len(flat), 2):
            yield i, flat[i], flat[i + 1]
            for kind, text in extra.get(i // 2, ()):
                yield -1, kind, text

    out: list[tuple[str, str]] = []
    for i, kind, text in stream():
        if kind == "Comment":
            if PS_REQUIRES.match(text):
                out.append(("requires", text))
            elif i == 0 and text.startswith("#!"):
                out.append(("shebang", text))
        elif kind == "NewLine":
            # A newline separates statements, so dropping it would let
            # `cmd $a # c` and the line under it merge into one call behind a
            # comment deletion. A run collapses to one leaf and the ends are
            # trimmed, which keeps blank lines and reflow invisible.
            if out and out[-1][0] != "NewLine":
                out.append(("NewLine", "\n"))
        elif kind != "EndOfInput":
            out.append((kind, text))
    while out and out[-1][0] == "NewLine":
        out.pop()
    return out


# A rename may not change a variable's scope or bind it to an automatic one:
# both are token-shaped but neither preserves meaning.
PS_AUTOMATIC = frozenset({"$_", "$psitem", "$args", "$input", "$this"})


def powershell_rename_defect(mapping: dict[str, str]) -> str | None:
    for old, new in mapping.items():
        for name in (old, new):
            if name.lower() in PS_AUTOMATIC:
                return f"rename touches the automatic variable {name}"
        # `$x` -> `$global:x` and `$x` -> `$env:PATH` are scope changes, so the
        # sigil-to-last-colon prefix has to match on both sides.
        if old.rpartition(":")[0].lower() != new.rpartition(":")[0].lower():
            return f"scope prefix changed: {old} -> {new}"
    return None


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
    return classify_leaves(a, b, a_broken, b_broken)


def classify_leaves(a, b, a_broken: bool, b_broken: bool) -> tuple[str, int, dict]:
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

    if entry[1] is None:
        try:
            records = powershell_records(str(args.before), str(args.after))
            if len(records) != 2:
                raise PowerShellUnavailable(
                    f"ps-tokens.ps1 returned {len(records)} records, expected 2"
                )
        except PowerShellUnavailable as exc:
            print(f"change-shape: {exc}", file=sys.stderr)
            return EXIT_USAGE
        source = "pwsh"
        verdict, code, detail = classify_leaves(
            powershell_leaves(records[0]),
            powershell_leaves(records[1]),
            records[0]["errors"] > 0,
            records[1]["errors"] > 0,
        )
        if verdict == "RENAME-ONLY":
            defect = powershell_rename_defect(detail["mapping"])
            if defect:
                verdict, code, detail = (
                    "CODE-CHANGED",
                    EXIT_CODE_CHANGED,
                    {"reason": defect},
                )
    else:
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
