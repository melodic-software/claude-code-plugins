#!/usr/bin/env python3
"""Find commented-out code by reparsing each comment with the file's own grammar.

A comment is commented-out code when its body, markers stripped, parses
cleanly in the language of the file it sits in AND shows structure that prose
does not: an assignment, a call, a block, an expansion, a mapping. The second
condition is what keeps this precise, because a bare word parses as an
identifier in most grammars and any sentence parses as a command in Bash.

This is the cross-language class-A input beside Ruff's Python-only ERA001.
Findings are advisory: rows are printed and the exit code is 0 either way, so
the caller decides. Consecutive single-line comments are grouped into one
block before reparsing, since commented-out code usually spans lines.

Directive comments (shellcheck, noqa, type:, pragma, eslint, region markers,
`#Requires`, PowerShell comment-based-help keywords) are skipped before
reparsing: they are machine input, not candidates.

`.ps1` and `.psm1` are read by PowerShell's own parser through `ps-tokens.ps1`
under `pwsh`; those files are skipped when no host resolves.

Usage: commented-out-code.py [--json] FILE ...
Exit: 0 ran (findings or none); 3 tree-sitter or the grammar unavailable; 2 usage.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from importlib import import_module
from pathlib import Path

EXIT_NO_TOOLING = 3
EXIT_USAGE = 2

# A None module marks the native PowerShell backend, which loads no grammar.
EXT_LANG = {
    ".py": ("python", "tree_sitter_python", "language"),
    ".ts": ("typescript", "tree_sitter_typescript", "language_typescript"),
    ".tsx": ("tsx", "tree_sitter_typescript", "language_tsx"),
    ".js": ("javascript", "tree_sitter_javascript", "language"),
    ".mjs": ("javascript", "tree_sitter_javascript", "language"),
    ".cjs": ("javascript", "tree_sitter_javascript", "language"),
    ".sh": ("bash", "tree_sitter_bash", "language"),
    ".bash": ("bash", "tree_sitter_bash", "language"),
    ".cs": ("csharp", "tree_sitter_c_sharp", "language"),
    ".yml": ("yaml", "tree_sitter_yaml", "language"),
    ".yaml": ("yaml", "tree_sitter_yaml", "language"),
    ".toml": ("toml", "tree_sitter_toml", "language"),
    ".ps1": ("powershell", None, None),
    ".psm1": ("powershell", None, None),
}

# Node kinds that prose cannot produce. A reparse must contain at least one.
EVIDENCE = {
    "python": {
        "assignment",
        "augmented_assignment",
        "call",
        "function_definition",
        "class_definition",
        "import_statement",
        "import_from_statement",
        "return_statement",
        "if_statement",
        "for_statement",
        "while_statement",
        "with_statement",
        "try_statement",
        "subscript",
        "attribute",
        "list",
        "dictionary",
        "decorator",
        "raise_statement",
        "assert_statement",
    },
    "bash": {
        "variable_assignment",
        "redirected_statement",
        "pipeline",
        "if_statement",
        "for_statement",
        "while_statement",
        "case_statement",
        "function_definition",
        "command_substitution",
        "simple_expansion",
        "expansion",
        "subshell",
        "test_command",
        "declaration_command",
        "list",
        "heredoc_redirect",
        "process_substitution",
        "unset_command",
    },
    "javascript": {
        "variable_declaration",
        "lexical_declaration",
        "call_expression",
        "assignment_expression",
        "function_declaration",
        "arrow_function",
        "return_statement",
        "if_statement",
        "for_statement",
        "import_statement",
        "export_statement",
        "member_expression",
        "object",
        "array",
        "new_expression",
        "class_declaration",
        "await_expression",
    },
    "csharp": {
        "local_declaration_statement",
        "invocation_expression",
        "assignment_expression",
        "method_declaration",
        "class_declaration",
        "return_statement",
        "if_statement",
        "for_statement",
        "foreach_statement",
        "using_directive",
        "object_creation_expression",
        "member_access_expression",
        "property_declaration",
        "field_declaration",
    },
    "yaml": {
        "block_mapping_pair",
        "block_sequence_item",
        "flow_mapping",
        "flow_sequence",
    },
    "toml": {
        "pair",
        "table",
        "table_array_element",
        "array",
        "inline_table",
    },
}
EVIDENCE["typescript"] = EVIDENCE["javascript"] | {
    "type_alias_declaration",
    "interface_declaration",
}
EVIDENCE["tsx"] = EVIDENCE["typescript"]

DIRECTIVE = re.compile(
    r"^\s*(?:#!|shellcheck\b|noqa\b|type:|pragma\b|eslint|prettier|ruff:|pylint:|fmt:|nolint\b|"
    r"region\b|endregion\b|yaml-language-server|mypy:|pyright:|@ts-|TODO\b|FIXME\b|XXX\b|"
    r"requires\b|"
    r"\.(?:SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK|COMPONENT|ROLE|"
    r"FUNCTIONALITY|EXTERNALHELP|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE)\b)",
    re.IGNORECASE,
)
MARKER = re.compile(r"^\s*(?:///?|<#|#+|/\*+|\*+/?|<!--|-->)\s?")
# PowerShell's block-comment close, stripped before the opener so that a `#>`
# line is emptied rather than left as a stray `>`. Without it a one-line
# `<# $x = 1 #>` never reaches the parser as code.
BLOCK_END = re.compile(r"\s*#>\s*$")

PS_SCRIPT = Path(__file__).with_name("ps-tokens.ps1")
# Comment-based help is documentation, whole. Splitting it into directive-free
# runs would reparse its prose, and prose that names a `-Switch` reads as a
# command with a parameter. A keyword standing alone on its line marks the block.
PS_HELP = re.compile(
    r"^[ \t]*#?[ \t]*\.(?:SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK|"
    r"COMPONENT|ROLE|FUNCTIONALITY|EXTERNALHELP|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|"
    r"REMOTEHELPRUNSPACE)(?:[ \t]+\S+)?[ \t]*\r?$",
    re.IGNORECASE | re.MULTILINE,
)


class PowerShellUnavailable(Exception):
    """No usable PowerShell host, so `.ps1`/`.psm1` cannot be read."""


def run_ps_tokens(*args: str) -> list[dict]:
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


def powershell_code_like(bodies: list[str]) -> list[bool]:
    """Reparse every candidate body in one pwsh process."""
    if not bodies:
        return []
    with tempfile.TemporaryDirectory() as tmp:
        listing = Path(tmp, "bodies.json")
        listing.write_text(json.dumps(bodies), encoding="utf-8")
        records = run_ps_tokens("-Bodies", str(listing))
    if len(records) != 1:
        raise PowerShellUnavailable("ps-tokens.ps1 -Bodies returned no result")
    return records[0]["results"]


def load_language(entry):
    name, module, attr = entry
    try:
        from tree_sitter import Language
    except ImportError:
        return None, "tree-sitter is not installed (pip install tree-sitter)"
    try:
        return Language(getattr(import_module(module), attr)()), module
    except (ImportError, AttributeError):
        return None, f"no grammar for {name} (pip install {module})"


def merge_comment_runs(comments):
    """(start_row, end_row, start_col, text), 0-based -> merged 1-based blocks."""
    blocks: list[list] = []
    for row, end_row, col, text in comments:
        # Runs of single-line comments merge without a length cap; a block
        # comment (/* */, <# #>) never joins a run, on either side of it. The
        # test is on the incoming comment and the previous one, never on the
        # merged text, which contains a newline as soon as two lines have joined.
        single_line = "\n" not in text
        if (
            blocks
            and blocks[-1][1] == row - 1
            and blocks[-1][3] == col
            and blocks[-1][4]
            and single_line
        ):
            blocks[-1][1] = end_row
            blocks[-1][2] += "\n" + text
        else:
            blocks.append([row, end_row, text, col, single_line])
    for start, end, text, _, _ in blocks:
        yield start + 1, end + 1, text


def comment_blocks(src: bytes, lang):
    """Yield (start_line, end_line, text) for comment nodes, adjacent lines merged."""
    from tree_sitter import Parser

    nodes = []
    stack = [Parser(lang).parse(src).root_node]
    while stack:
        n = stack.pop()
        if "comment" in n.type:
            nodes.append(n)
        else:
            stack.extend(reversed(n.children))
    nodes.sort(key=lambda n: n.start_byte)
    return merge_comment_runs(
        (
            n.start_point[0],
            n.end_point[0],
            n.start_point[1],
            src[n.start_byte : n.end_byte].decode(errors="replace"),
        )
        for n in nodes
    )


def strip_markers(text: str) -> str:
    return "\n".join(
        MARKER.sub("", BLOCK_END.sub("", line), count=1) for line in text.split("\n")
    )


def looks_like_code(body: str, lang, lang_name: str) -> bool:
    from tree_sitter import Parser

    src = body.encode()
    if not src.strip():
        return False
    tree = Parser(lang).parse(src)
    evidence = EVIDENCE.get(lang_name, set())
    found = False
    leaves = 0
    stack = [tree.root_node]
    while stack:
        n = stack.pop()
        if n.type in ("ERROR", "MISSING") or n.is_missing:
            return False
        if "comment" in n.type:
            continue
        if n.type in evidence:
            found = True
        if n.child_count == 0 and src[n.start_byte : n.end_byte].strip():
            leaves += 1
        stack.extend(n.children)
    return found and leaves >= 2


def directive_free_runs(lines: list[str]) -> list[list[int]]:
    """Indexes of consecutive non-directive lines, one list per run."""
    runs: list[list[int]] = []
    current: list[int] = []
    for i, line in enumerate(lines):
        if DIRECTIVE.match(line):
            if current:
                runs.append(current)
                current = []
        else:
            current.append(i)
    if current:
        runs.append(current)
    return runs


def scan(path: Path):
    entry = EXT_LANG.get(path.suffix.lower())
    if entry is None:
        return None, f"no grammar mapping for {path.suffix!r}"
    if entry[1] is None:
        try:
            records = run_ps_tokens(str(path))
            if len(records) != 1:
                raise PowerShellUnavailable(
                    f"ps-tokens.ps1 returned {len(records)} records, expected 1"
                )
            blocks = [
                b
                for b in merge_comment_runs(
                    (s - 1, e - 1, c - 1, text)
                    for s, e, c, text in records[0]["comments"]
                )
                if not PS_HELP.search(b[2])
            ]
            # First pass answers "not code" to everything, which collects the
            # superset of bodies the real pass can ask about; one process then
            # classifies them all.
            bodies: list[str] = []

            def collect(body: str) -> bool:
                bodies.append(body)
                return False

            findings_for(path, blocks, collect)
            table = dict(zip(bodies, powershell_code_like(bodies)))
        except PowerShellUnavailable as exc:
            return None, str(exc)
        return findings_for(path, blocks, table.__getitem__), "pwsh"
    lang, source = load_language(entry)
    if lang is None:
        return None, source
    blocks = comment_blocks(path.read_bytes(), lang)
    return findings_for(
        path, blocks, lambda body: looks_like_code(body, lang, entry[0])
    ), source


def findings_for(path: Path, blocks, is_code):
    findings = []
    for start, end, text in blocks:
        stripped_lines = strip_markers(text).split("\n")
        raw_lines = text.split("\n")
        # A directive line is never code and splits the block into runs. Each
        # run is reparsed whole first; a prose line inside a run breaks that
        # parse, so fall back to each line and merge adjacent hits into ranges.
        hits: list[int] = []
        for run in directive_free_runs(stripped_lines):
            if is_code("\n".join(stripped_lines[i] for i in run)):
                hits.extend(run)
            else:
                hits.extend(i for i in run if is_code(stripped_lines[i]))
        run_start = None
        for idx, i in enumerate(hits):
            if run_start is None:
                run_start = i
            last = idx == len(hits) - 1
            if last or hits[idx + 1] != i + 1:
                findings.append(
                    {
                        "path": str(path),
                        "start": start + run_start,
                        "end": start + i,
                        "excerpt": raw_lines[run_start].strip()[:80],
                    }
                )
                run_start = None
    return findings


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    all_findings = []
    unavailable = []
    for f in args.files:
        if not f.is_file():
            print(f"commented-out-code: not a file: {f}", file=sys.stderr)
            return EXIT_USAGE
        findings, note = scan(f)
        if findings is None:
            unavailable.append(f"{f}: {note}")
            continue
        all_findings.extend(findings)
    if len(unavailable) == len(args.files):
        print(
            "commented-out-code: UNAVAILABLE: " + "; ".join(unavailable),
            file=sys.stderr,
        )
        return EXIT_NO_TOOLING
    for u in unavailable:
        print(f"commented-out-code: skipped {u}", file=sys.stderr)
    if args.json:
        print(json.dumps(all_findings, indent=1))
    else:
        for r in all_findings:
            span = (
                f"{r['start']}"
                if r["start"] == r["end"]
                else f"{r['start']}-{r['end']}"
            )
            print(f"{r['path']}:{span}: {r['excerpt']}")
        if not all_findings:
            print("no commented-out code found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
