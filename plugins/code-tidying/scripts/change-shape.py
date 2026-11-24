#!/usr/bin/env python3
"""Classify an edit by what it did to the code, ignoring comments.

Compares the comment-stripped sequence of parse-tree leaves of a file before
and after an edit. The verdict is a proof about tokens, which is the claim a
comment-dissolving edit has to make and a test suite can only sample:

  COMMENT-ONLY   no code token changed. A deletion with this verdict is safe
                 to apply in a repository with no tests at all.
  DOCSTRING-ONLY Python only: the one difference is removed docstrings of the
                 module or of functions defined outside any class (top level
                 or nested in a function), every kept one unchanged and in
                 place. A class or method docstring removal is CODE-CHANGED.
                 Also CODE-CHANGED when the file holds `__doc__` or
                 `__dict__` in any token, or one of the identifiers `vars`,
                 `help`, `getdoc`, `getmembers`, `__init_subclass__`, `pydoc`
                 or `doctest`; when the docstring holds `>>>`; when the
                 function is decorated; when its name appears anywhere but
                 its own def line or directly before `(`; or when removal
                 leaves a body empty. It reads this one file only.
  RENAME-ONLY    every differing leaf is an identifier and the old->new mapping
                 is consistent. A SHAPE claim, not a safety claim: it knows
                 nothing about shadowing, outer-scope collisions, reflection or
                 string-keyed access, so it earns a lighter review, never an
                 unattended apply.
  CODE-CHANGED   some non-identifier token differs, or the token count moved.
                 Also, in place of COMMENT-ONLY or DOCSTRING-ONLY, when a code
                 line changed other than by losing whole comments (a trailing
                 one with the whitespace before it): a reindent, `x = (` to
                 `x =(`, or a line split or joined.
  UNPROVABLE     a side failed to parse cleanly (ERROR/MISSING nodes), so no
                 token-level claim can be made. Treated as CODE-CHANGED by any
                 gate.

Exit codes carry the verdict so a shell gate can branch on them without
parsing text: 0 COMMENT-ONLY, 11 DOCSTRING-ONLY, 10 RENAME-ONLY,
20 CODE-CHANGED, 21 UNPROVABLE, 3 tree-sitter or the grammar for this
language is unavailable, 2 usage, an
unmapped extension, or no PowerShell host for a `.ps1`/`.psm1` file.

`.ps1` and `.psm1` are read by PowerShell's own tokenizer through
`ps-tokens.ps1` under `pwsh`, not by a tree-sitter grammar: the maintained
grammar returns ERROR nodes on ordinary PowerShell, which would make every
real file UNPROVABLE. With no `pwsh` on PATH the answer is exit 2, an
*unproven* edit.

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
from typing import NamedTuple

EXIT_COMMENT_ONLY = 0
EXIT_RENAME_ONLY = 10
EXIT_DOCSTRING_ONLY = 11
EXIT_CODE_CHANGED = 20
EXIT_UNPROVABLE = 21
EXIT_NO_TOOLING = 3
EXIT_USAGE = 2

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
        "Variable",
        "SplattedVariable",
        "InterpolatedVariable",
    }
)

PS_SCRIPT = Path(__file__).with_name("ps-tokens.ps1")
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
            if out and out[-1][0] != "NewLine":
                out.append(("NewLine", "\n"))
        elif kind != "EndOfInput":
            out.append((kind, text))
    while out and out[-1][0] == "NewLine":
        out.pop()
    return out


def powershell_layout(record: dict) -> tuple[str, list[tuple[int, int]]]:
    """The text pwsh parsed, with CRLF and CR as LF, and the comment spans in it.

    pwsh offsets count UTF-16 code units; `at` maps each unit to its index in
    the returned text, so a non-BMP character or a CRLF does not shift a span."""
    raw = record["text"]
    out: list[str] = []
    at: list[int] = []
    for i, ch in enumerate(raw):
        if ch == "\n" and raw[i - 1 : i] == "\r":
            at.append(len(out) - 1)
            continue
        at.extend([len(out)] * (2 if ord(ch) > 0xFFFF else 1))
        out.append("\n" if ch == "\r" else ch)
    at.append(len(out))
    return "".join(out), [(at[s], at[e]) for s, e in record["spans"]]


def powershell_rename_defect(mapping: dict[str, str], reserved: set[str]) -> str | None:
    """A rename may not change a variable's scope or touch a reserved name.

    Both are token-shaped and neither preserves meaning. `reserved` is the set
    ps-tokens.ps1 read out of a live runspace, so it tracks the language rather
    than a list maintained here.
    """
    for old, new in mapping.items():
        for name in (old, new):
            if name.lstrip("$@").lower() in reserved:
                return f"rename touches the reserved variable {name}"
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


class Docstring(NamedTuple):
    """A docstring statement's leaves sit at `start:end` of the leaf stream."""

    start: int
    end: int
    text: str
    line: int
    refusal: str | None
    owner: str | None


DOC_READERS = frozenset(
    {"getdoc", "getmembers", "help", "pydoc", "doctest", "vars", "__init_subclass__"}
)


def is_docstring(stmt, src: bytes) -> bool:
    """A lone str literal: no f-, t- or b-prefix, which would not become `__doc__`."""
    if stmt.type != "expression_statement" or stmt.named_child_count != 1:
        return False
    value = stmt.named_children[0]
    parts = [value] if value.type == "string" else []
    if value.type == "concatenated_string":
        parts = [c for c in value.named_children if c.type == "string"]
    if not parts:
        return False
    for part in parts:
        opener = src[part.children[0].start_byte : part.children[0].end_byte]
        if not set(opener.decode().rstrip("'\"").lower()) <= {"r", "u"}:
            return False
    return True


def python_docstrings(
    root, src: bytes
) -> dict[int, tuple[str, int, str | None, str | None]]:
    """Docstring statement node id -> (text, line, why its removal is refused,
    the owner's name, None for the module)."""
    found: dict[int, tuple[str, int, str | None, str | None]] = {}
    stack = [root]
    while stack:
        node = stack.pop()
        stack.extend(node.named_children)
        if node.type == "module":
            body = node
        elif node.type in ("function_definition", "class_definition"):
            body = node.child_by_field_name("body")
        else:
            continue
        statements = (
            [c for c in body.named_children if c.type != "comment"] if body else []
        )
        if not statements or not is_docstring(statements[0], src):
            continue
        stmt = statements[0]
        text = src[stmt.start_byte : stmt.end_byte].decode(errors="replace")
        refusal = None
        if node.type != "module" and len(statements) == 1:
            refusal = "removal leaves an empty body"
        elif ">>>" in text:
            refusal = "the docstring holds doctest examples"
        else:
            refusal = owner_refusal(node)
        name = node.child_by_field_name("name")
        owner = src[name.start_byte : name.end_byte].decode() if name else None
        found[stmt.id] = (text, stmt.start_point[0] + 1, refusal, owner)
    return found


def referenced_as_value(stream, name: str) -> bool:
    """Whether `name` appears other than as its own def/class name or as the
    callee of a direct call, which is how a library or a table reaches it."""
    for i, (kind, text) in enumerate(stream):
        if kind != "identifier" or text != name:
            continue
        defined = i > 0 and stream[i - 1][1] in ("def", "class")
        called = i + 1 < len(stream) and stream[i + 1][1] == "("
        if not (defined or called):
            return True
    return False


def owner_refusal(owner) -> str | None:
    """Why the owner's docstring is out of the verdict's scope, or None.

    A class docstring rides on the class and every instance, and a method's
    on its class, so any value reference to the class reaches them; only
    module and class-free function docstrings are in scope."""
    if owner.type == "class_definition":
        return "a class docstring is reachable through the class and its instances"
    node = owner.parent
    while node is not None:
        if node.type == "class_definition":
            return "a method docstring is reachable through its class"
        node = node.parent
    if owner.parent is not None and owner.parent.type == "decorated_definition":
        return "a decorator can read the docstring"
    return None


def leaves(
    src: bytes, lang, docstrings: bool = False
) -> tuple[list[tuple[str, str]], bool, list[Docstring], list[tuple[int, int]], list[tuple[int, int]]]:
    """Terminal tokens minus comments, whether the parse had errors, the
    docstrings among them when `docstrings` is set, and the byte spans of the
    comments and of those docstrings."""
    from tree_sitter import Parser

    tree = Parser(lang).parse(src)
    owners = python_docstrings(tree.root_node, src) if docstrings else {}
    out: list[tuple[str, str]] = []
    docs: list[Docstring] = []
    comments: list[tuple[int, int]] = []
    doc_spans: list[tuple[int, int]] = []
    broken = False

    def walk(top) -> None:
        nonlocal broken
        stack = [top]
        while stack:
            node = stack.pop()
            found = owners.pop(node.id, None)
            if found is not None:
                begin = len(out)
                walk(node)
                docs.append(Docstring(begin, len(out), *found))
                doc_spans.append((node.start_byte, node.end_byte))
                continue
            if node.type in ("ERROR", "MISSING") or node.is_missing:
                broken = True
            if node.child_count and "comment" not in node.type:
                stack.extend(reversed(node.children))
                continue
            text = src[node.start_byte : node.end_byte].decode(errors="replace")
            if "comment" in node.type:
                comments.append((node.start_byte, node.end_byte))
                if node.start_point[0] == 0 and text.startswith("#!"):
                    out.append(("shebang", text))
            elif text.strip():
                out.append((node.type, text))

    walk(tree.root_node)
    return out, broken, docs, comments, doc_spans


def code_changed(**detail) -> tuple[str, int, dict]:
    return "CODE-CHANGED", EXIT_CODE_CHANGED, detail


def without_docstrings(stream, docs: list[Docstring]):
    """The stream with every docstring cut out, and each docstring keyed by
    where it sat in that cut stream, so the two sides' docstrings compare by
    position as well as text."""
    kept, anchors, cursor, removed = [], {}, 0, 0
    for doc in sorted(docs):
        kept.extend(stream[cursor : doc.start])
        anchors[(doc.start - removed, doc.text)] = doc
        removed += doc.end - doc.start
        cursor = doc.end
    kept.extend(stream[cursor:])
    return kept, anchors


def classify_docstrings(a, b, a_docs, b_docs) -> tuple[str, int, dict] | None:
    """DOCSTRING-ONLY, a refusal, or None when docstrings do not explain the diff."""
    a_kept, a_anchors = without_docstrings(a, a_docs)
    b_kept, b_anchors = without_docstrings(b, b_docs)
    if a_kept != b_kept or not b_anchors.keys() <= a_anchors.keys():
        return None
    removed = [doc for key, doc in a_anchors.items() if key not in b_anchors]
    if not removed:
        return None
    reader = next(
        (
            text
            for kind, text in a + b
            if "__doc__" in text
            or "__dict__" in text
            or (kind == "identifier" and text in DOC_READERS)
        ),
        None,
    )
    if reader is not None:
        return code_changed(
            reason="the file can read docstrings at run time", at=reader
        )
    for doc in removed:
        if doc.refusal:
            return code_changed(reason=doc.refusal, line=doc.line)
        if doc.owner and referenced_as_value(a, doc.owner):
            return code_changed(
                reason="the owner is referenced as a value", at=doc.owner, line=doc.line
            )
    return (
        "DOCSTRING-ONLY",
        EXIT_DOCSTRING_ONLY,
        {"removed_lines": [doc.line for doc in removed]},
    )


def classify(
    before: bytes, after: bytes, lang, docstrings: bool = False
) -> tuple[str, int, dict]:
    a, a_broken, a_docs, a_comments, a_doc_spans = leaves(before, lang, docstrings)
    b, b_broken, b_docs, b_comments, b_doc_spans = leaves(after, lang, docstrings)
    verdict = classify_leaves(a, b, a_broken, b_broken)
    if verdict[0] == "CODE-CHANGED" and a_docs:
        verdict = classify_docstrings(a, b, a_docs, b_docs) or verdict
        if verdict[0] == "DOCSTRING-ONLY":
            a_comments += a_doc_spans
            b_comments += b_doc_spans
    if verdict[0] in ("COMMENT-ONLY", "DOCSTRING-ONLY"):
        return layout_change(before, a_comments, after, b_comments) or verdict
    return verdict


def code_lines(text, spans) -> list[tuple[int, str]]:
    """Each line holding code, by line number, with `spans` cut out and the
    end of the line trimmed. A cut keeps its newlines so numbering holds."""
    nl = "\n" if isinstance(text, str) else b"\n"
    parts, cursor = [], 0
    for start, end in sorted(spans):
        parts += [text[cursor:start], nl * text.count(nl, start, end)]
        cursor = end
    parts.append(text[cursor:])
    joined = text[:0].join(parts)
    return [(n, s.rstrip()) for n, s in enumerate(joined.split(nl), 1) if s.strip()]


def layout_change(before, a_spans, after, b_spans) -> tuple[str, int, dict] | None:
    """CODE-CHANGED when a code line changed other than by losing a whole
    trailing comment and the whitespace before it. The tokens cannot see this:
    `x = (` and `x =(` are the same leaves."""
    a, b = code_lines(before, a_spans), code_lines(after, b_spans)
    if len(a) != len(b):
        return code_changed(reason="code lines were split or joined")
    for (_, x), (line, y) in zip(a, b):
        if x != y:
            return code_changed(reason="whitespace changed on a code line", line=line)
    return None


def classify_leaves(
    a, b, a_broken: bool, b_broken: bool, fold=None
) -> tuple[str, int, dict]:
    """`fold` canonicalizes an identifier for the name bookkeeping only.

    A language whose names are case-insensitive passes `str.lower` here, so the
    mapping, the collision check and the stale-name check all agree with the
    language. The leaves themselves stay verbatim, so a case-only edit is still
    a visible difference rather than nothing at all.
    """
    key = fold or (lambda s: s)
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
        return code_changed(tokens_before=len(a), tokens_after=len(b))
    diffs = [(x, y) for x, y in zip(a, b) if x != y]
    if all(x[0] in IDENTIFIER_KINDS and y[0] in IDENTIFIER_KINDS for x, y in diffs):
        mapping: dict[str, str] = {}
        folded: dict[str, str] = {}
        reverse: dict[str, str] = {}
        for (_, old), (_, new) in diffs:
            if key(old) == key(new):
                return code_changed(reason="one name respelled, not renamed", at=old)
            if folded.setdefault(key(old), key(new)) != key(new):
                return code_changed(reason="inconsistent identifier mapping", at=old)
            if reverse.setdefault(key(new), key(old)) != key(old):
                return code_changed(
                    reason="two identifiers collapse to one name", at=new
                )
            mapping[old] = new
        unchanged = {
            key(text)
            for (kind, text), y in zip(a, b)
            if kind in IDENTIFIER_KINDS and (kind, text) == y
        }
        stale = sorted(old for old in mapping if key(old) in unchanged)
        if stale:
            return code_changed(
                reason="incomplete rename: old name still referenced", at=stale[0]
            )
        collision = sorted(new for new in mapping.values() if key(new) in unchanged)
        if collision:
            return code_changed(
                reason="rename collides with an existing identifier", at=collision[0]
            )
        return "RENAME-ONLY", EXIT_RENAME_ONLY, {"mapping": mapping}
    kinds = sorted({x[0] for x, _ in diffs})
    return code_changed(differing_leaves=len(diffs), kinds=kinds)


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
            fold=str.lower,
        )
        if verdict == "COMMENT-ONLY":
            verdict, code, detail = layout_change(
                *powershell_layout(records[0]), *powershell_layout(records[1])
            ) or (verdict, code, detail)
        if verdict == "RENAME-ONLY":
            reserved = {n.lower() for n in records[1]["reserved"]}
            defect = powershell_rename_defect(detail["mapping"], reserved)
            if defect:
                verdict, code, detail = code_changed(reason=defect)
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

        verdict, code, detail = classify(
            before, after, lang, docstrings=entry[0] == "python"
        )
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
