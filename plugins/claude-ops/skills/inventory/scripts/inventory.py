#!/usr/bin/env python3
"""Enumerate the Claude Code ecosystem on this machine.

Emits one JSON document describing what this machine can actually invoke:
built-in CLI commands, bundled skills, and every installed plugin component.

Two independent evidence sources, never conflated in the output:

  binary  - the shipped Claude Code executable. The only complete source for
            built-in commands and bundled skills, because the official docs do
            not publish either list (docs/en/slash-commands now serves the
            skills page). Read-only; the file is never modified.
  disk    - settings, marketplaces, and plugin trees under the config dir.

Requires Python 3.11+ and nothing else - no strings(1), no jq, no shell.
Every path is built with pathlib so Windows, macOS, and Linux behave alike.
"""

from __future__ import annotations

import argparse
import bisect
import functools
import itertools
import json
import math
import os
import platform
import re
import shutil
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

# Re-exported, not merely used: `registrations_of` is part of this extractor's
# surface (its own tests read it from here), and `lib/registrations.py` is
# shared with the sibling overlap consumer so the registration-shape rule the
# extractor writes and the consumer reads has exactly one home.
from registrations import registrations_of  # noqa: E402  (path set above; plugin-bundled module)

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
from docs_crosscheck import build_crosscheck  # noqa: E402  (sibling module)

MIN_PYTHON = (3, 11)

# The CLI release this extractor was last verified against by a human running
# the skill's evals. Drift from it is not an error - the extraction is designed
# to survive ordinary releases - but it downgrades every count from "verified"
# to "believed", which the report has to say out loud.
VALIDATED_AGAINST = "2.1.284"

# Commands that have shipped in every build observed. Their absence means the
# extraction broke, not that Anthropic deleted /help. This is the cheapest
# guard against the failure mode that matters: a layout change that yields a
# clean-looking but badly incomplete list instead of an error.
CANARY_COMMANDS = ("help", "clear", "config", "resume", "status")

# Registrar-shaped exports known to funnel into registerBundledSkill. A new
# name here is the signal that a fourth registration path appeared and this
# script may now be under-reporting silently.
KNOWN_REGISTRAR_EXPORTS = frozenset(
    {
        "registerBundledSkill",
        "registerBundledSkillSessionReset",
        "registerClaudeApiSkill",
        "registerClaudeCodeSkill",
        "registerCoworkSetupSkill",
        "registerLoopSkill",
        "registerRunSkill",
        "registerRunSkillGeneratorSkill",
        "registerScheduleRemoteAgentsSkill",
        "registerAgentProxyEnvFn",
        "registerDesignCanvasSkill",
        "registerSlidesSkill",
        "registerWorkflowAuthoringSkill",
    }
)

# Below this ratio of extracted commands to `type:"local…"` tokens present, the
# brace reader is failing to resolve enclosing objects and the list is partial.
MIN_COMMAND_YIELD = 0.40

# Plugin-backed built-ins that have shipped in every build observed. Absence
# means the `pluginName` scan broke, not that the product dropped the command.
PLUGIN_BACKED_CANARY = ("security-review",)

# The bundle is minified JS. These markers sit at the top of the embedded CLI
# chunk and are stable across the releases observed so far; each is tried in
# turn so one rename does not break discovery.
BUNDLE_MARKERS = (b"// @bun @bytecode @bun-cjs", b"// @bun @bun-cjs", b"// @bun")

# Region rule. A bytecode-fragmented bundle scatters its readable JavaScript
# across thousands of printable runs, some only a few kilobytes, with
# registrations in the small ones. From the first bundle marker to end of file,
# every printable run of at least this many bytes is taken and the runs are
# joined with newlines. The floor is what keeps the single regex pass cheap;
# below it the regex costs minutes and above it registrations go missing.
MIN_RUN_BYTES = 256
RUN_RE = re.compile(rb"[\t\n\r\x20-\x7e]{%d,}" % MIN_RUN_BYTES)
# Every registration literal, of any registrar, opens with `({name:`. Counting
# it in the raw region against the joined source is how a registration that
# sits in a run below the floor is counted rather than silently lost. Minified
# source puts the value flush against the colon; `({name: "` with a space is
# prose in a message string (the bytecode string table holds several), not code.
REGISTRATION_TOKEN_RE = re.compile(rb"\(\{name:(?=[\"`A-Za-z_$])")

# A single-character identifier is a function-local minifier name reused
# everywhere, so its nearest preceding string binding is only trusted when it
# lies within this many bytes of the registration; a longer identifier is a
# module-level constant and its nearest preceding binding is trusted at any
# distance (the constants are hoisted megabytes ahead of the registrations in
# the bytecode layout).
SHORT_IDENT_LOCALITY_BYTES = 65_536

# Extraction lanes, in the order the self-check prints them. Each lane carries
# its own status so one broken lane never silently voids the others' counts.
LANES = ("builtin_commands", "bundled_skills", "plugin_backed")
# Evaluated whenever the binary is read; optional in `check_integrity` so a
# caller that extracts no workflows is not reported as a broken lane.
WORKFLOW_LANE = "bundled_workflows"

# A bundled workflow that has shipped in every build since workflows gained a
# bundled roster. Absence means the workflow scan broke.
WORKFLOW_CANARY = ("deep-research",)

# Built-in subagent types and built-in tools, each its own lane. Like the
# workflow lane, each is optional in `check_integrity` so a caller that
# extracts neither is not reported as broken.
AGENT_LANE = "builtin_agents"
TOOL_LANE = "builtin_tools"

# Built-in subagents and tools that have shipped in every build observed and
# that the docs name (sub-agents.md, tools-reference.md). Absence means the
# scan broke, not that the product dropped them.
AGENT_CANARY = ("general-purpose", "Explore", "Plan", "statusline-setup")
TOOL_CANARY = ("Bash", "Read", "Edit", "Write", "WebFetch")

# Value shapes a name constant may hold. A subagent type is PascalCase or
# kebab-case (`Explore`, `claude-code-guide`); a tool is PascalCase, or
# snake_case for a few remote and memory tools.
AGENT_NAME_RE = r"[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*"
TOOL_NAME_RE = r"[A-Z][A-Za-z0-9]*|[a-z][a-z0-9]*(?:_[a-z0-9]+)+"

# A description or argument hint held in a single-character identifier is
# trusted only when its binding lies this close to the registration: such names
# are function-local, and a farther binding belongs to another function.
SHORT_VALUE_LOCALITY_BYTES = 4_096

# Component types a plugin may ship, from the plugin manifest schema and the
# standard plugin layout. Directory is the default location; the manifest may
# redirect most of them, which is why the manifest is read before the tree.
PLUGIN_COMPONENTS: dict[str, dict[str, str]] = {
    "skills": {"dir": "skills", "manifest": "skills", "kind": "dir-of-dirs"},
    "commands": {"dir": "commands", "manifest": "commands", "kind": "dir-of-files"},
    "agents": {"dir": "agents", "manifest": "agents", "kind": "dir-of-files"},
    "workflows": {"dir": "workflows", "manifest": "workflows", "kind": "dir-of-files"},
    "output-styles": {
        "dir": "output-styles",
        "manifest": "outputStyles",
        "kind": "dir-of-files",
    },
    "themes": {
        "dir": "themes",
        "manifest": "experimental.themes",
        "kind": "dir-of-files",
    },
    "monitors": {
        "dir": "monitors",
        "manifest": "experimental.monitors",
        "kind": "dir-of-files",
    },
    "hooks": {"dir": "hooks", "manifest": "hooks", "kind": "dir-of-files"},
    "bin": {"dir": "bin", "manifest": "", "kind": "dir-of-files"},
    "mcp-servers": {
        "dir": "",
        "manifest": "mcpServers",
        "kind": "file",
        "file": ".mcp.json",
    },
    "lsp-servers": {
        "dir": "",
        "manifest": "lspServers",
        "kind": "file",
        "file": ".lsp.json",
    },
    "settings": {"dir": "", "manifest": "", "kind": "file", "file": "settings.json"},
}


# --------------------------------------------------------------------------
# Locating the binary
# --------------------------------------------------------------------------


def candidate_binaries() -> list[Path]:
    """Ordered candidates for the Claude Code executable."""
    out: list[Path] = []

    resolved = shutil.which("claude")
    if resolved:
        out.append(Path(resolved))

    home = Path.home()
    names = ("claude.exe", "claude") if os.name == "nt" else ("claude",)
    roots = [
        home / ".local" / "bin",
        home / ".claude" / "local",
        Path("/usr/local/bin"),
        Path("/opt/homebrew/bin"),
    ]
    for root in roots:
        for name in names:
            out.append(root / name)

    seen: set[str] = set()
    uniq: list[Path] = []
    for p in out:
        try:
            key = str(p.resolve())
        except OSError:
            key = str(p)
        if key not in seen:
            seen.add(key)
            uniq.append(p)
    return uniq


def pick_binary(explicit: str | None) -> tuple[Path | None, str]:
    """Return the executable to read, plus a note on how it was chosen.

    A native build is a large single file. An npm install resolves to a small
    launcher script instead; that is reported rather than parsed, because the
    JS bundle it loads lives elsewhere and carries no embedded section.
    """
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            return None, f"--binary {explicit} is not a file"
        return p, "explicit --binary"

    candidates = candidate_binaries()
    for p in candidates:
        try:
            if not p.is_file():
                continue
            size = p.stat().st_size
        except OSError:
            continue
        if size > 20_000_000:
            return p, "auto-detected native build"
        # Keep looking; a shim may precede the real binary on PATH.
    for p in candidates:
        try:
            if p.is_file():
                return (
                    p,
                    "auto-detected (small file - likely an npm launcher, not a native build)",
                )
        except OSError:
            continue
    return None, "no claude executable found on PATH or in the usual install roots"


def read_bundle(binary: Path) -> tuple[str | None, dict[str, Any]]:
    """Pull the embedded JS bundle out of the executable.

    Deliberately format-agnostic. Parsing the PE section table (or Mach-O load
    commands, or ELF section headers) would work but ties the script to each
    container format and to the section name the packer happens to use. The
    bundle announces itself with a marker comment, so the marker is located and
    the surrounding printable run is taken. That behaves the same whether the
    host is Windows, macOS, or Linux.
    """
    meta: dict[str, Any] = {"path": str(binary), "size": binary.stat().st_size}
    try:
        data = binary.read_bytes()
    except OSError as exc:
        meta["error"] = f"cannot read binary: {exc}"
        return None, meta

    meta["container"] = detect_container(data)
    return _select_region(data, meta)


def _select_region(
    data: bytes, meta: dict[str, Any]
) -> tuple[str | None, dict[str, Any]]:
    """Apply the region rule to raw bytes; the legacy longest-run path is the fallback.

    Region rule: from the first bundle marker to end of file, every printable
    run of at least `MIN_RUN_BYTES`, joined with newlines. A build with no
    marker at all falls back to the largest printable run around a known
    anchor, which is what every build before the bytecode layout needed.
    """
    started = time.perf_counter()
    first = -1
    marker_used = ""
    for marker in BUNDLE_MARKERS:
        pos = data.find(marker)
        if pos >= 0 and (first < 0 or pos < first):
            first, marker_used = pos, marker.decode("ascii")
    if first < 0:
        return _select_longest_run(data, meta)

    runs = [m.group(0) for m in RUN_RE.finditer(data, first)]
    joined = b"\n".join(runs)
    meta["anchor"] = marker_used
    meta["bundle_offset"] = first
    meta["region_rule"] = (
        f"first bundle marker to end of file; printable runs of at least "
        f"{MIN_RUN_BYTES} bytes joined with newlines"
    )
    meta["runs"] = len(runs)
    meta["joined_bytes"] = len(joined)
    in_region = sum(1 for _ in REGISTRATION_TOKEN_RE.finditer(data, first))
    in_joined = sum(1 for _ in REGISTRATION_TOKEN_RE.finditer(joined))
    meta["runs_below_floor"] = max(0, in_region - in_joined)
    meta["elapsed_seconds"] = round(time.perf_counter() - started, 3)
    if len(joined) < 1_000_000:
        meta["error"] = (
            f"joined printable region is only {len(joined)} bytes - "
            "this build does not embed the CLI bundle where expected"
        )
        return None, meta
    return joined.decode("latin1"), meta


def _select_longest_run(
    data: bytes, meta: dict[str, Any]
) -> tuple[str | None, dict[str, Any]]:
    """Legacy region selection: the largest printable run around a known anchor."""
    meta["region_rule"] = (
        "no bundle marker found; largest printable run around an anchor"
    )
    printable = bytearray(256)
    for c in b"\t\n\r":
        printable[c] = 1
    for c in range(0x20, 0x7F):
        printable[c] = 1

    def run_bounds(pos: int) -> tuple[int, int]:
        n = len(data)
        end = pos
        while end < n and printable[data[end]]:
            end += 1
        begin = pos
        while begin > 0 and printable[data[begin - 1]]:
            begin -= 1
        return begin, end

    # Anchor on the export name the extraction needs rather than on the chunk
    # header. The header appears several times (small helper chunks carry it
    # too), so the first hit is routinely a few hundred bytes of the wrong
    # chunk; the export name occurs only in the CLI bundle. Markers stay as a
    # fallback for a build that renames the export.
    anchors: list[bytes] = [b"registerBundledSkill", *BUNDLE_MARKERS]

    best: tuple[int, int] | None = None
    best_anchor = ""
    for anchor in anchors:
        pos = data.find(anchor)
        while pos >= 0:
            begin, end = run_bounds(pos)
            if best is None or (end - begin) > (best[1] - best[0]):
                best = (begin, end)
                best_anchor = anchor.decode("ascii", "replace")
            pos = data.find(anchor, end if end > pos else pos + 1)
        if best is not None and (best[1] - best[0]) > 1_000_000:
            break

    if best is None:
        meta["error"] = "no embedded JS bundle found - unsupported build layout"
        return None, meta

    begin, end = best
    if end - begin < 1_000_000:
        meta["error"] = (
            f"largest candidate bundle is only {end - begin} bytes - "
            "this build does not embed the CLI bundle where expected"
        )
        return None, meta

    meta["anchor"] = best_anchor
    meta["bundle_offset"] = begin
    meta["bundle_bytes"] = end - begin
    return data[begin:end].decode("latin1"), meta


def detect_container(data: bytes) -> str:
    if data[:2] == b"MZ":
        return "PE"
    if data[:4] == b"\x7fELF":
        return "ELF"
    if data[:4] in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
        return "Mach-O"
    return "unknown"


# --------------------------------------------------------------------------
# Minified-JS scanning
# --------------------------------------------------------------------------

_ID_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$")
_REGEX_PRECEDERS = set("(,=:[!&|?{};+-*%^~<>") | {"\n"}
_REGEX_KEYWORDS = {
    "return",
    "typeof",
    "instanceof",
    "in",
    "of",
    "new",
    "delete",
    "void",
    "case",
    "do",
    "else",
    "yield",
    "await",
}


@dataclass
class BraceMap:
    """Positions of every matched {...} pair in the source."""

    pairs: dict[int, int] = field(default_factory=dict)
    opens: list[int] = field(default_factory=list)

    def enclosing(self, pos: int) -> tuple[int, int] | None:
        k = bisect.bisect_right(self.opens, pos) - 1
        while k >= 0:
            o = self.opens[k]
            if self.pairs[o] > pos:
                return o, self.pairs[o]
            k -= 1
        return None


def build_brace_map(s: str) -> BraceMap:
    """Match braces while skipping strings, templates, regex literals, comments.

    Minified JS packs object literals against each other, so a fixed-width
    window around a match routinely spans two neighboring objects and mixes
    their fields. Tracking real brace depth is what keeps each command's fields
    attributed to that command.
    """
    stack: list[int] = []
    pairs: dict[int, int] = {}
    # Brace depth at which each open template `${` substitution began. The
    # substitution is ordinary code (it can hold regex literals, nested
    # templates, and object literals), so the main loop tokenizes it; the `}`
    # that returns to that depth resumes the template's literal text.
    templates: list[int] = []
    i, n = 0, len(s)
    prev_sig = "\n"
    prev_word = ""

    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c in "\"'":
            q = c
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            prev_sig, prev_word = q, ""
            continue
        if c == "`":
            i, opened = _scan_template_text(s, i + 1, n)
            if opened:
                templates.append(len(stack))
                prev_sig, prev_word = "{", ""
            else:
                prev_sig, prev_word = "`", ""
            continue
        if c == "}" and templates and templates[-1] == len(stack):
            templates.pop()
            i, opened = _scan_template_text(s, i + 1, n)
            if opened:
                templates.append(len(stack))
                prev_sig, prev_word = "{", ""
            else:
                prev_sig, prev_word = "`", ""
            continue
        if c == "/":
            if prev_word in _REGEX_KEYWORDS or prev_sig in _REGEX_PRECEDERS:
                i = _skip_regex(s, i, n)
            else:
                i += 1
            prev_sig, prev_word = "/", ""
            continue
        if c in _ID_CHARS:
            j = i
            while j < n and s[j] in _ID_CHARS:
                j += 1
            prev_word = s[i:j]
            prev_sig = s[j - 1]
            i = j
            continue
        if c == "{":
            stack.append(i)
        elif c == "}":
            if stack:
                pairs[stack.pop()] = i
        prev_sig, prev_word = c, ""
        i += 1

    return BraceMap(pairs=pairs, opens=sorted(pairs))


def _scan_template_text(s: str, i: int, n: int) -> tuple[int, bool]:
    """Skip a template literal's text from `i`; True when it stopped at a `${`.

    Returns the index just past the closing backtick, or just past the `${`
    that opens a substitution the caller must tokenize as code.
    """
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "`":
            return i + 1, False
        if s[i] == "$" and i + 1 < n and s[i + 1] == "{":
            return i + 2, True
        i += 1
    return i, False


def _skip_regex(s: str, i: int, n: int) -> int:
    i += 1
    in_class = False
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "[":
            in_class = True
        elif s[i] == "]":
            in_class = False
        elif s[i] == "/" and not in_class:
            i += 1
            break
        elif s[i] == "\n":
            break
        i += 1
    while i < n and s[i] in "gimsuyvd":
        i += 1
    return i


_STR = r'"((?:[^"\\]|\\.)*)"'


def _unescape(raw: str) -> str:
    try:
        return json.loads('"' + raw + '"')
    except Exception:
        return raw


# --------------------------------------------------------------------------
# Static values: descriptions and argument hints
# --------------------------------------------------------------------------

_QUOTES = "\"'`"
_ELLIPSIS = "\u2026"
_ID_START = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_$")
_NON_STRING_WORDS = frozenset(
    {"void", "null", "undefined", "true", "false", "typeof", "new", "await", "this"}
)
_JS_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v"}
_ESCAPE_RE = re.compile(r"\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|[\s\S])")
_MAX_HOPS = 6
_MAX_COMBINATIONS = 16
# The names a function body cannot read from the bundle: each parameter maps
# to None (a runtime value) or to the values its call site passed.
Scope = Mapping[str, "list[str] | None"]
NO_SCOPE: Scope = MappingProxyType({})
_NONSTRING = object()
_NULLISH_WORDS = ("null", "undefined", "void")
_NUMBER_RE = re.compile(
    r"[-+]?(?:0[xX][0-9a-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+"
    r"|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][-+]?\d[\d_]*)?)n?(?![\w$])"
)


_FUNCTION_KEYWORD_RE = re.compile(r"function\s*\*?\s*[\w$]*\s*\Z")


def _open_paren(src: str, close: int) -> int | None:
    """The `(` matching the `)` at `close`, within 4 KiB, or None."""
    depth, k = 0, close
    while k >= 0 and close - k < 4096:
        depth += (src[k] == ")") - (src[k] == "(")
        if depth == 0:
            return k
        k -= 1
    return None


def _opens_function(src: str, braces: BraceMap, brace: int) -> bool:
    """Whether the `{` at `brace` opens a `function` body. The parameter
    list is matched by depth with quoted text blanked, so a default holding
    a call (`a=g()`) or a quoted paren (`s=")"`) counts. Raises ValueError
    when the head cannot be read, so the caller's value stays unresolved."""
    j = brace - 1
    while j >= 0 and src[j] in " \t\r\n":
        j -= 1
    if j < 0 or src[j] != ")":
        return False
    k = _head_open(src, braces, j)
    return bool(_FUNCTION_KEYWORD_RE.search(src, max(0, k - 200), k))


def _catch_params(src: str, braces: BraceMap, brace: int) -> Scope:
    """The parameters of the `catch (...)` whose block opens at `brace`, each
    a runtime value; empty when the block is not a catch block."""
    j = brace - 1
    while j >= 0 and src[j] in " \t\r\n":
        j -= 1
    if j < 0 or src[j] != ")":
        return NO_SCOPE
    k = _head_open(src, braces, j)
    if not re.search(r"(?<![\w$.])catch\s*$", src[max(0, k - 16) : k]):
        return NO_SCOPE
    return _param_names(src[k + 1 : j])


_FOR_KEYWORD_RE = re.compile(r"(?<![\w$.])for\s*(?:await\s*)?$")
_FOR_DECL_RE = re.compile(r"\s*(?:let|const)(?![\w$])\s*((?:(?!\b(?:of|in)\b)[^;])*)")


def _for_params(src: str, braces: BraceMap, brace: int) -> Scope:
    """The `let`/`const` names of the `for (...)` head whose body opens at
    `brace`, each a runtime value; empty for any other block."""
    j = brace - 1
    while j >= 0 and src[j] in " \t\r\n":
        j -= 1
    if j < 0 or src[j] != ")":
        return NO_SCOPE
    k = _head_open(src, braces, j)
    if not _FOR_KEYWORD_RE.search(src[max(0, k - 24) : k]):
        return NO_SCOPE
    decl = _FOR_DECL_RE.match(_mask_strings(src[k + 1 : j]))
    return _param_names(decl.group(1)) if decl else NO_SCOPE


def _head_open(src: str, braces: BraceMap, close: int) -> int:
    """The `(` matching the `)` at `close`, matched with quoted text blanked
    from the enclosing block's start. Raises ValueError when unmatched."""
    outer = braces.enclosing(close)
    lo = outer[0] + 1 if outer else max(_chunk_span(src, close)[0], close - 4096)
    k = _open_paren(_mask_strings(src[lo : close + 1]), close - lo)
    if k is None:
        raise ValueError("unmatched parameter list")
    return lo + k


def _mask_strings(text: str) -> str:
    """`text` with the quoted text of each string and template literal
    blanked to spaces, so a search for code (a parameter write) never matches
    it; a template substitution's `${...}` is code and is kept."""
    out, i, n = [], 0, len(text)
    while i < n:
        q = text[i]
        if q not in _QUOTES:
            out.append(q)
            i += 1
            continue
        j = i + 1
        out.append(" ")
        while j < n and text[j] != q:
            if text[j] == "\\":
                out.append("  ")
                j += 2
            elif q == "`" and text.startswith("${", j):
                try:
                    end = _skip_substitution(text, j + 2, n)
                except ValueError:
                    end = n
                out.append("  " + _mask_strings(text[j + 2 : end - 1]) + " ")
                j = end
            else:
                out.append(" ")
                j += 1
        out.append(" ")
        i = j + 1
    return "".join(out)[:n]


def _primitive_text(text: str, *, joined: bool) -> str | None:
    """How a template (or, `joined`, `Array.join`) renders a known
    primitive literal: `true`, `false`, `null`, `undefined`, or a plain
    decimal integer. None for anything else, which stays a runtime value."""
    text = text.strip()
    if text in ("null", "undefined") or text.startswith("void "):
        return "" if joined else ("null" if text == "null" else "undefined")
    if text in ("true", "false"):
        return text
    # 15 digits stay below 2**53, where a JS double renders them exactly.
    if re.fullmatch(r"-?(?:0|[1-9]\d{0,14})", text):
        return str(int(text))
    return None


def _unparen(text: str) -> str:
    """`text` without whitespace and wrapping parentheses: `((1))` is `1`."""
    text = text.strip()
    while text.startswith("(") and text.endswith(")"):
        depth = 0
        for k, ch in enumerate(text):
            depth += (ch == "(") - (ch == ")")
            if depth == 0 and k < len(text) - 1:
                return text  # `(a)||(b)`: the first group closes early
        text = text[1:-1].strip()
    return text


def _literal_truthy(text: str) -> bool | None:
    """How `||` sees a non-string literal: truthy, falsy, or None (unknown)."""
    text = _unparen(text)
    if text.startswith("!"):
        inner = _literal_truthy(text[1:])
        return None if inner is None else not inner
    if text == "true":
        return True
    if text == "false" or text.startswith(_NULLISH_WORDS):
        return False
    number = _number_value(text)
    return None if number is None else number != 0


def _literal_nullish(text: str) -> bool | None:
    """How `??` sees a non-string literal: nullish, not, or None (unknown)."""
    text = _unparen(text)
    if text.startswith(_NULLISH_WORDS):
        return True
    if (
        text.startswith("!")
        or text in ("true", "false")
        or _number_value(text) is not None
    ):
        return False
    return None


def _number_value(text: str) -> int | float | None:
    """The value of a JavaScript numeric literal, or None for anything else.
    A radix literal stays an exact integer, however large."""
    if not _NUMBER_RE.fullmatch(text):
        return None
    text = text.replace("_", "").rstrip("n")
    try:
        return int(text, 0) if re.match(r"[-+]?0[xXoObB]", text) else float(text)
    except (ValueError, OverflowError):
        return None


def _js_unescape(raw: str) -> str:
    def sub(m: re.Match[str]) -> str:
        e = m.group(1)
        if e.startswith("u{"):
            return chr(int(e[2:-1], 16))
        if e[0] in "ux" and len(e) > 1:
            return chr(int(e[1:], 16))
        if e == "\n":
            return ""
        return _JS_ESCAPES.get(e, e)

    text = _ESCAPE_RE.sub(sub, raw)
    return text.encode("utf-16", "surrogatepass").decode("utf-16", "replace")


def _read_literal(src: str, i: int, n: int) -> tuple[str, int, bool]:
    """A string or template literal at `i`: (text, index past it, has substitution).

    A template substitution renders as an ellipsis: its value exists only at
    runtime. Raises ValueError on an unterminated literal.
    """
    q = src[i]
    j = i + 1
    if q != "`":
        while j < n:
            ch = src[j]
            if ch == "\\":
                j += 2
                continue
            if ch == q:
                return _js_unescape(src[i + 1 : j]), j + 1, False
            if ch == "\n":
                break
            j += 1
        raise ValueError("unterminated string")
    parts: list[str] = []
    seg, subst = j, False
    while j < n:
        ch = src[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "`":
            parts.append(_js_unescape(src[seg:j]))
            return "".join(parts), j + 1, subst
        if ch == "$" and src.startswith("{", j + 1):
            parts.append(_js_unescape(src[seg:j]) + _ELLIPSIS)
            subst = True
            j = _skip_substitution(src, j + 2, n)
            seg = j
            continue
        j += 1
    raise ValueError("unterminated template")


def _skip_substitution(src: str, i: int, n: int) -> int:
    depth = 1
    while i < n:
        ch = src[i]
        if ch in _QUOTES:
            i = _read_literal(src, i, n)[1]
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unterminated substitution")


def _skip_ws(src: str, i: int, n: int) -> int:
    while i < n and src[i] in " \t\r\n":
        i += 1
    return i


def _ident_end(src: str, i: int) -> int:
    n = len(src)
    while i < n and src[i] in _ID_CHARS:
        i += 1
    return i


def _match_close(src: str, braces: BraceMap, i: int, n: int) -> int:
    """Index past the `(` or `[` group opening at `i`."""
    depth = 0
    while i < n:
        ch = src[i]
        if ch in _QUOTES:
            i = _read_literal(src, i, n)[1]
            continue
        if ch == "{":
            close = braces.pairs.get(i)
            if close is None:
                raise ValueError("unmatched brace")
            i = close + 1
            continue
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unterminated group")


@dataclass
class _Values:
    """String values an expression can take, collected in source order."""

    variants: list[str] = field(default_factory=list)
    unresolved: int = 0
    via: set[str] = field(default_factory=set)

    def add(self, value: str) -> None:
        if value in self.variants:
            self.variants.remove(value)
        self.variants.append(value)


def _object_fields(
    src: str, braces: BraceMap, open_i: int, *, methods: bool = False
) -> dict[str, tuple[str, int]]:
    """Top-level fields of the object literal at `open_i`.

    Maps each key to ("value", offset of its value) or ("getter", offset of
    the getter body's `{`); with `methods`, a method or async method
    (`description(){...}`) maps to ("method", offset of its body's `{`).
    Nested objects, strings, and groups are skipped, so a nested object's
    field never answers for the outer one.
    """
    close = braces.pairs.get(open_i)
    if close is None:
        return {}
    fields: dict[str, tuple[str, int]] = {}
    head = re.compile(r"(?:(get|set|async)\s+)?(" + _IDENT + r")\s*(:|\()")
    i, expect_key = open_i + 1, True
    while i < close:
        ch = src[i]
        if ch in " \t\r\n":
            i += 1
            continue
        if ch == ",":
            expect_key = True
            i += 1
            continue
        if expect_key and ch in _ID_START:
            m = head.match(src, i, close)
            if m:
                key = m.group(2)
                if m.group(3) == ":" and not m.group(1):
                    fields.setdefault(key, ("value", m.end()))
                    i, expect_key = m.end(), False
                    continue
                j = _skip_ws(src, _match_close(src, braces, m.end() - 1, close), close)
                if m.group(1) == "get" and src.startswith("{", j):
                    fields.setdefault(key, ("getter", j))
                elif methods and m.group(1) != "set" and src.startswith("{", j):
                    fields.setdefault(key, ("method", j))
                i, expect_key = j, False
                continue
        expect_key = False
        if ch in _QUOTES:
            i = _read_literal(src, i, close)[1]
        elif ch == "{":
            end = braces.pairs.get(i)
            if end is None:
                break
            i = end + 1
        elif ch in "([":
            i = _match_close(src, braces, i, close)
        else:
            i += 1
    return fields


def _scan(
    src: str,
    braces: BraceMap,
    i: int,
    end: int,
    acc: _Values,
    *,
    block: bool,
    hops: int,
    anchor: int | None,
    shadow: Scope = NO_SCOPE,
    deferred: bool = False,
) -> int:
    """Collect the string values an expression (or a function body) yields.

    Expression mode reads one expression from `i`, stopping at a top-level
    `,`, `;`, or closing bracket. Block mode reads a function body and
    collects what each `return` yields. Within a yielded expression, the
    operands in value position (the start, after a ternary `?` or `:`, and
    after a `||` or `??` fallback) are the candidates; an operand followed by
    `?` is a condition, not a value. `shadow` names the enclosing function's
    parameters: their values exist only at runtime, so they never resolve
    to a same-named binding elsewhere in the bundle.
    """
    active = at_value = not block
    depth = 0
    prev, prev_word = "", ""
    n = min(end, len(src))
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if (
            active
            and at_value
            and depth == 0
            and (
                c in _QUOTES
                or c in _ID_START
                or c in "([!"
                or _NUMBER_RE.match(src, i, n) is not None
            )
        ):
            i = _operand(
                src,
                braces,
                i,
                n,
                acc,
                hops=hops,
                anchor=anchor,
                shadow=shadow,
                deferred=deferred,
            )
            at_value, prev, prev_word = False, "x", ""
            continue
        if c in _QUOTES:
            i = _read_literal(src, i, n)[1]
            at_value, prev = False, c
            continue
        if c == "{":
            close = braces.pairs.get(i)
            if close is None:
                raise ValueError("unmatched brace")
            if (
                block
                and depth == 0
                and (prev == ")" or prev_word in ("else", "try", "finally"))
                # A nested function declaration is not a branch of this body.
                and not _opens_function(src, braces, i)
            ):
                _scan(
                    src,
                    braces,
                    i + 1,
                    close,
                    acc,
                    block=True,
                    hops=hops,
                    anchor=anchor,
                    shadow=shadow
                    | _catch_params(src, braces, i)
                    | _for_params(src, braces, i),
                    deferred=deferred,
                )
            i, at_value, prev, prev_word = close + 1, False, "}", ""
            continue
        if c == "}":
            break
        if c in "([":
            depth += 1
        elif c in ")]":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and c in ",;":
            if not block:
                break
            if c == ";":
                active = False
        elif depth == 0 and (c == "?" or src.startswith("||", i)):
            if src.startswith(("??", "||"), i):
                # A fallback: its right side is what shows when the left is
                # empty, unless it is an empty string itself (`x??""`), which
                # says nothing.
                i = _skip_ws(src, i + 2, n)
                after = _skip_ws(src, i + 2, n)
                empty = src[i : i + 2] in ('""', "''", "``") and (
                    after >= n or src[after] in ",;})]:"
                )
                at_value, prev = active and not empty, "?"
                continue
            if src.startswith("?.", i):
                i += 2
                at_value, prev = False, "?"
                continue
            at_value = active
            i, prev = i + 1, c
            continue
        elif depth == 0 and c == ":":
            at_value = active
            i, prev = i + 1, c
            continue
        elif c in _ID_START:
            j = _ident_end(src, i)
            word = src[i:j]
            if block and depth == 0 and word == "return":
                active = at_value = True
            else:
                at_value = False
            i, prev, prev_word = j, "x", word
            continue
        at_value, prev, prev_word = False, c, ""
        i += 1
    return i


def _operand(
    src: str,
    braces: BraceMap,
    i: int,
    n: int,
    acc: _Values,
    *,
    hops: int,
    anchor: int | None,
    shadow: Scope = NO_SCOPE,
    deferred: bool = False,
) -> int:
    """Read one operand in value position; record it when it is a string value.

    An operand is a `+` concatenation of string or template literals,
    identifiers, member reads and calls, parenthesized expressions, and
    `[...].join(sep)` arrays. A part whose value exists only at runtime (a
    parameter, a call the reader cannot follow) renders as an ellipsis, and
    a result with no static word left in it is unresolved, never recorded.
    """
    kw = {"hops": hops, "anchor": anchor, "shadow": shadow, "deferred": deferred}
    if src[i] == "(":
        close = _match_close(src, braces, i, n)
        k = _skip_ws(src, close, n)
        if src.startswith("=>", k):
            params = shadow | _param_names(src[i + 1 : close - 1])
            return _arrow_body(src, braces, k + 2, n, acc, **{**kw, "shadow": params})
    start = i
    parts: list[Any] = []
    # A call or a group can also yield a non-string (`void 0`, `null`) this
    # reader does not record, so its values never settle a fallback.
    computed = False
    quoted = True  # every part a string or template literal: never nullish
    while True:
        i = _skip_ws(src, i, n)
        if i >= n:
            break
        c = src[i]
        quoted = quoted and c in _QUOTES
        if c in _QUOTES:
            texts, i, via = _read_string(src, braces, i, n, **kw)
            parts.append(texts if len(texts) > 1 else texts[0])
            acc.via |= via
        elif c == "(":
            close = _match_close(src, braces, i, n)
            # `(x()?a:b)` yields both branches.
            group = _sub_value(src, braces, i + 1, close - 1, acc, **kw)
            computed = computed or bool(group and group.partial)
            inner = src[i + 1 : close - 1]
            known = _literal_truthy(inner) is not None or _literal_nullish(inner)
            # `(true)`: a known primitive stays one, for the fallback below.
            parts.append(_NONSTRING if group is None and known else group)
            i = close
        elif c == "[":
            joined, i = _array_join(src, braces, i, n, acc, **kw)
            parts.append(joined)
        elif c in _ID_START:
            j = _ident_end(src, i)
            word = src[i:j]
            k = _skip_ws(src, j, n)
            if word == "async" and k < n and (src[k] == "(" or src[k] in _ID_START):
                # `async()=>...` or `async x=>...`: the keyword, not a callee.
                return _operand(src, braces, k, n, acc, **kw)
            if src.startswith("=>", k):
                return _arrow_body(
                    src,
                    braces,
                    k + 2,
                    n,
                    acc,
                    **{**kw, "shadow": shadow | {word: None}},
                )
            if word in _NON_STRING_WORDS:
                i = _skip_ws(src, j, n)
                if (
                    word in ("void", "typeof", "new", "await")
                    and i < n
                    and src[i] in _ID_CHARS
                ):
                    i = _ident_end(src, i)
                parts.append(_NONSTRING)
            else:
                chain, i = _read_chain(src, braces, i, n)
                computed = computed or any(e[0] == "call" for e in chain)
                parts.append(_resolve_chain(src, braces, chain, i, acc, **kw))
        elif number := _NUMBER_RE.match(src, i, n):
            i = number.end()
            parts.append(_NONSTRING)
        elif c == "!":
            j = i
            while src.startswith("!", j):
                j += 1
            number = _NUMBER_RE.match(src, j, n)
            i = number.end() if number else _ident_end(src, j)
            parts.append(_NONSTRING)
        else:
            break
        k = _skip_ws(src, i, n)
        if src.startswith("+", k) and not src.startswith(("++", "+="), k):
            i = k + 1
            continue
        i = k
        break
    t = src[i] if i < n else ""
    if t == "?" and not src.startswith(("??", "?."), i):
        return i
    fallback = src.startswith(("||", "??"), i)
    if t and t not in ":,;})]" and not fallback:
        return i
    values: list[str] | None = []
    if len(parts) == 1:
        p = parts[0]
        values = p if isinstance(p, list) else [p] if isinstance(p, str) else None
        if p is _NONSTRING:
            # A non-string (`void 0`, `null`, a number): nothing to record,
            # but the expression is not a string for certain.
            values = []
            acc.unresolved += 1
    elif len(parts) > 1 and any(isinstance(p, (str, list)) and p for p in parts):
        values = _combine(
            [
                [p]
                if isinstance(p, str)
                else (p if isinstance(p, list) and p else [_ELLIPSIS])
                for p in parts
            ]
        )
    if fallback:
        # `a||b`: when every value `a` can take is a non-empty string, `b`
        # never shows, so it is skipped; otherwise `b` is read as a value
        # after the values of `a` that are non-empty strings.
        # `a??b` tests only null and undefined, so any string `a` keeps it.
        # A non-string literal settles it by its own truthiness.
        literal = src[start:i].strip() if parts == [_NONSTRING] else None
        or_op = src.startswith("||", i)
        kept = (not or_op and quoted and bool(parts)) or (
            bool(literal)
            and (
                _literal_truthy(literal) is True
                if or_op
                else _literal_nullish(literal) is False
            )
        )
        if kept:
            values = values if quoted else []
        elif (
            computed
            or not values
            or _ELLIPSIS in values  # a bare runtime value settles nothing
            or (or_op and not all(values))
        ):
            for v in values or []:
                if v:
                    _add_static(acc, v)
            return i
        while src.startswith(("||", "??"), i):
            i = _operand(src, braces, _skip_ws(src, i + 2, n), n, _Values(), **kw)
            i = _skip_ws(src, i, n)
    if values is None:
        acc.unresolved += 1
    for v in values or []:
        _add_static(acc, v)
    return i


def _combine(choices: list[list[str]], sep: str = "") -> list[str]:
    """Every way to pick one value per part, joined by `sep`, with the
    fallthrough (each part's last value) last; past `_MAX_COMBINATIONS`, the
    fallthrough alone."""
    if math.prod(len(c) for c in choices) > _MAX_COMBINATIONS:
        choices = [[c[-1]] for c in choices]
    return [sep.join(combo) for combo in itertools.product(*choices)]


class _Alternatives(list):
    """An expression's string values; `partial` when it may also yield a
    value this reader did not record (a non-string or an unresolved part)."""

    partial = False


_STATIC_WORD_RE = re.compile(r"[A-Za-z0-9]")


def _add_static(acc: _Values, text: str) -> None:
    """Record `text` unless its runtime substitutions left no static word in it.

    `${a}\\n\\n${b}` with neither part resolved reads as an ellipsis pair; that
    is not a description, so it counts as unresolved rather than as a value.
    """
    if _ELLIPSIS in text and not _STATIC_WORD_RE.search(text.replace(_ELLIPSIS, "")):
        acc.unresolved += 1
    else:
        acc.add(text)


def _param_names(text: str) -> Scope:
    """Every identifier in a parameter list: each is a runtime value.

    Destructuring keys (`{tools:n}`) and default-value callees are included
    too; shadowing an extra name only leaves more unresolved, never less.
    """
    return {name: None for name in re.findall(_IDENT, text)}


def _params_before(src: str, braces: BraceMap, body_open: int) -> Scope:
    """The parameters of the method or function whose body opens at `body_open`."""
    j = body_open - 1
    while j >= 0 and src[j] in " \t\r\n":
        j -= 1
    if j < 0 or src[j] != ")":
        return NO_SCOPE
    return _param_names(src[_head_open(src, braces, j) + 1 : j])


def _sub_value(
    src: str,
    braces: BraceMap,
    start: int,
    end: int,
    acc: _Values,
    **kw: Any,
) -> _Alternatives | None:
    """The values of the one expression spanning `[start, end)`, or None.

    None when it yields nothing or does not span the range (a comma
    expression, a trailing member read), so a partial read never stands in
    for the whole.
    """
    sub = _Values()
    stop = _scan(src, braces, start, end, sub, block=False, **kw)
    if not sub.variants or _skip_ws(src, stop, end) < end:
        return None
    acc.via |= sub.via
    out = _Alternatives(sub.variants)
    out.partial = sub.unresolved > 0
    return out


def _read_string(
    src: str,
    braces: BraceMap,
    i: int,
    n: int,
    *,
    hops: int,
    anchor: int | None,
    shadow: Scope,
    deferred: bool = False,
) -> tuple[list[str], int, set[str]]:
    """A string or template literal: (its values, index past it, how it was read).

    Each template substitution is resolved like any other expression and
    contributes each of its values, the texts combined (see `_combine`); one
    that does not resolve renders as an ellipsis and marks the text
    `template`.
    """
    if src[i] != "`":
        text, end, _ = _read_literal(src, i, n)
        return [text], end, {"literal"}
    via: set[str] = set()
    parts: list[list[str]] = []
    j = seg = i + 1
    while j < n:
        ch = src[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "`":
            parts.append([_js_unescape(src[seg:j])])
            return _combine(parts), j + 1, via or {"literal"}
        if ch == "$" and src.startswith("{", j + 1):
            parts.append([_js_unescape(src[seg:j])])
            end = _skip_substitution(src, j + 2, n)
            acc = _Values()
            value = (
                _sub_value(
                    src,
                    braces,
                    j + 2,
                    end - 1,
                    acc,
                    hops=hops - 1,
                    anchor=anchor,
                    shadow=shadow,
                    deferred=deferred,
                )
                if hops > 1
                else None
            )
            primitive = _primitive_text(src[j + 2 : end - 1], joined=False)
            if value is None and primitive is not None:
                parts.append([primitive])
            elif value is None:
                parts.append([_ELLIPSIS])
                via.add("template")
            else:
                # A branch that may yield something unrecorded stays a runtime
                # alternative ahead of the resolved ones.
                parts.append(([_ELLIPSIS] if value.partial else []) + list(value))
                if value.partial:
                    via.add("template")
                via |= acc.via
            j = seg = end
            continue
        j += 1
    raise ValueError("unterminated template")


def _array_join(
    src: str, braces: BraceMap, i: int, n: int, acc: _Values, **kw: Any
) -> tuple[list[str] | None, int]:
    """`[a, ...[b, c], d].join(sep)` as its joined values; None for any other array.

    An element that does not resolve renders as an ellipsis.
    """
    close = _match_close(src, braces, i, n)
    m = re.compile(r"\s*\.join\(\s*").match(src, close, n)
    if not m:
        return None, close
    k = m.end()
    sep = ","
    if k < n and src[k] in _QUOTES:
        sep, k, subst = _read_literal(src, k, n)
        if subst:
            return None, close
        k = _skip_ws(src, k, n)
    if not src.startswith(")", k):
        return None, close

    def elements(open_i: int, end: int) -> list[list[str]]:
        out: list[list[str]] = []
        starts = _split_args(src, braces, open_i + 1)
        for idx, start in enumerate(starts):
            stop = (starts[idx + 1] if idx + 1 < len(starts) else end) - 1
            while stop > start and src[stop] in " \t\r\n,":
                stop -= 1
            if src.startswith("]", start):
                continue
            if start > stop or src.startswith(",", start):
                out.append([""])  # a hole joins as the empty string
                continue
            if src.startswith("...[", start):
                inner = _match_close(src, braces, start + 3, n)
                out.extend(elements(start + 3, inner - 1))
                continue
            value = _sub_value(src, braces, start, stop + 1, acc, **kw)
            primitive = _primitive_text(src[start : stop + 1], joined=True)
            if value is None and primitive is not None:
                out.append([primitive])
                continue
            # A partial element keeps a runtime alternative ahead of its values.
            partial = not value or value.partial
            out.append(([_ELLIPSIS] if partial else []) + list(value or []))
            if partial:
                acc.via.add("template")
        return out

    acc.via.add("literal")
    return _combine(elements(i, close - 1), sep), k + 1


def _arrow_body(
    src: str,
    braces: BraceMap,
    k: int,
    n: int,
    acc: _Values,
    *,
    hops: int,
    anchor: int | None,
    shadow: Scope = NO_SCOPE,
    deferred: bool = False,
) -> int:
    acc.via.add("arrow")
    kw = {"hops": hops, "anchor": anchor, "shadow": shadow, "deferred": True}
    k = _skip_ws(src, k, n)
    if src.startswith("{", k):
        close = braces.pairs.get(k)
        if close is None:
            raise ValueError("unmatched brace")
        _scan(src, braces, k + 1, close, acc, block=True, **kw)
        return close + 1
    return _scan(src, braces, k, n, acc, block=False, **kw)


def _read_chain(
    src: str, braces: BraceMap, i: int, n: int
) -> tuple[list[tuple[str, str]], int]:
    """An identifier with its member reads and calls: `a`, `f()`, `a.b`, `a.b()`."""
    j = _ident_end(src, i)
    chain = [("id", src[i:j])]
    i = j
    while i < n:
        if src.startswith("?.", i):
            i += 1
        if src.startswith(".", i) and i + 1 < n and src[i + 1] in _ID_START:
            j = _ident_end(src, i + 1)
            chain.append(("prop", src[i + 1 : j]))
            i = j
        elif src.startswith("(", i):
            j = _match_close(src, braces, i, n)
            chain.append(("call", src[i + 1 : j - 1].strip(), i))
            i = j
        elif src.startswith("[", i):
            j = _match_close(src, braces, i, n)
            chain.append(("index", ""))
            i = j
        else:
            break
    return chain, i


_CHUNK_MARKER = "\n// @bun"


@functools.lru_cache(maxsize=4)
def _chunk_starts(src: str) -> tuple[int, ...]:
    """Where each bundled module begins: the bytecode layout concatenates
    modules, each opening with its own `// @bun` header."""
    starts, i = [0], src.find(_CHUNK_MARKER)
    while i >= 0:
        starts.append(i + 1)
        i = src.find(_CHUNK_MARKER, i + 1)
    return tuple(starts)


def _chunk_span(src: str, at: int) -> tuple[int, int]:
    """The `[start, end)` of the module holding offset `at`."""
    starts = _chunk_starts(src)
    k = bisect.bisect_right(starts, at) - 1
    return starts[k], starts[k + 1] if k + 1 < len(starts) else len(src)


# A module's statements that link it to others: its header comment lines, its
# leading imports, and its closing export list. Only these positions count,
# so `import{x}` quoted in a string or comment elsewhere links nothing.
_HEADER_LINE_RE = re.compile(r"[ \t]*(?://[^\n]*)?\n")
_IMPORT_STMT_RE = re.compile(r'\s*import\s*(?:\{([^{}]*)\}\s*from\s*)?"[^"\n]*"\s*;?')
_EXPORT_TAIL_RE = re.compile(r"export\s*\{([^{}]*)\}\s*;?\s*\Z")


@functools.lru_cache(maxsize=4096)
def _chunk_imports(src: str, lo: int, hi: int) -> dict[str, str]:
    """A module's imported names: local name to the name its exporter uses."""
    i = lo
    while (m := _HEADER_LINE_RE.match(src, i, hi)) and m.end() > i:
        i = m.end()
    out: dict[str, str] = {}
    while (m := _IMPORT_STMT_RE.match(src, i, hi)) and m.end() > i:
        i = m.end()
        for part in (m.group(1) or "").split(","):
            exported, _, local = part.strip().partition(" as ")
            if exported.strip():
                out[(local or exported).strip()] = exported.strip()
    return out


@functools.lru_cache(maxsize=4)
def _export_index(src: str) -> dict[str, list[tuple[int, str]]]:
    """Every exported name: the start of each module exporting it, and the
    local name it has there."""
    out: dict[str, list[tuple[int, str]]] = {}
    starts = _chunk_starts(src)
    for k, lo in enumerate(starts):
        hi = starts[k + 1] if k + 1 < len(starts) else len(src)
        tail = max(lo, hi - 65_536)
        m = _EXPORT_TAIL_RE.search(src[tail:hi])
        if not m:
            continue
        for part in m.group(1).split(","):
            local, _, exported = part.strip().partition(" as ")
            if local.strip():
                out.setdefault((exported or local).strip(), []).append(
                    (lo, local.strip())
                )
    return out


_CONTROL_HEAD_RE = re.compile(r"(?<![\w$.])(?:if|for|while|switch|catch|with)\s*\Z")
_KEYWORD_START_RE = re.compile(r"\s*(var|let|const)\s")


def _function_block(src: str, braces: BraceMap, pos: int) -> tuple[int, int] | None:
    """The body of the function that holds `pos`, or None at module level:
    a `var` belongs to it whatever blocks sit in between."""
    block = braces.enclosing(max(pos - 1, 0))
    while block is not None:
        j = block[0] - 1
        while j >= 0 and src[j] in " \t\r\n":
            j -= 1
        if src.startswith("=>", j - 1):
            return block
        if j >= 0 and src[j] == ")":
            try:
                k = _head_open(src, braces, j)
            except ValueError:
                return block
            if not _CONTROL_HEAD_RE.search(src, max(0, k - 16), k):
                return block
        block = braces.enclosing(block[0] - 1) if block[0] > 0 else None
    return None


def _statement_keyword(src: str, pos: int) -> str | None:
    """`var`, `let`, or `const` when the statement holding `pos` starts with
    it, else None. The walk back skips balanced brackets, so an earlier
    declarator's initializer (`var a=f(1),x=`) does not hide the keyword."""
    start = _statement_start(src, pos)
    m = None if start is None else _KEYWORD_START_RE.match(src, start)
    return m.group(1) if m else None


def _for_scope(src: str, braces: BraceMap, pos: int) -> tuple[int, int] | None:
    """For a `let` or `const` declared in a `for (...)` head, the span it is
    visible in, from the head's `(` to the end of a braced body. Raises
    ValueError for an unbraced body, whose end is not read."""
    start = _statement_start(src, pos)
    if not start or src[start - 1] != "(":
        return None
    if not re.search(r"\bfor\s*(?:await\s*)?$", src[max(0, start - 16) : start - 1]):
        return None
    if _statement_keyword(src, pos) not in ("let", "const"):
        return None
    body = _skip_ws(src, _match_close(src, braces, start - 1, len(src)), len(src))
    end = braces.pairs.get(body) if body < len(src) and src[body] == "{" else None
    if end is None:
        raise ValueError("unbraced loop body")
    return start - 1, end


def _statement_start(src: str, pos: int) -> int | None:
    """Offset just past the `;` or unmatched opener starting the statement
    that holds `pos`, or None when that is more than 4 KiB back."""
    lo = max(0, pos - 4096)
    text = _mask_strings(src[lo:pos])
    depth, k = 0, len(text) - 1
    while k >= 0:
        c = text[k]
        if c in ")]}":
            depth += 1
        elif c in "([{":
            if depth == 0:
                break
            depth -= 1
        elif c == ";" and depth == 0:
            break
        k -= 1
    if k < 0 and lo > 0:
        return None
    return lo + k + 1


def _is_var(src: str, pos: int) -> bool:
    """Whether the binding at `pos` is declared by a `var` statement."""
    return _statement_keyword(src, pos) == "var"


def _declares(src: str, pos: int) -> bool:
    """Whether the name at `pos` is a declarator: right after `var`, `let`,
    or `const`, or after a `,` in such a statement."""
    head = src[max(0, pos - 8) : pos]
    if re.search(r"\b(?:var|let|const)\s+$", head):
        return True
    return bool(re.search(r",\s*$", head)) and _statement_keyword(src, pos) is not None


def _redeclared_later(src: str, braces: BraceMap, ident: str, at: int) -> bool:
    """Whether the function reading `ident` at `at` declares it again after
    `at`: a `var` there hoists, and a `let` or `const` in a block holding the
    read is not yet initialized, so an earlier binding is not what it reads."""
    reader = _function_block(src, braces, at)
    if reader is None:
        return False
    name = re.compile(r"(?<![\w$.])" + re.escape(ident) + r"(?![\w$])")
    for m in name.finditer(_mask_strings(src[at : reader[1]])):
        pos = at + m.start()
        if not _declares(src, pos):
            continue
        if _is_var(src, pos):
            if _function_block(src, braces, pos) == reader:
                return True
        elif _visible(braces, pos, at):
            return True
    return False


def _unset_between(src: str, braces: BraceMap, ident: str, lo: int, at: int) -> bool:
    """Whether, after the binding at `lo`, the read at `at` sees a newer
    declaration of `ident` with no initializer (`let x;`, `var a,x`) or a
    `catch (x)` parameter: its value is not that binding's."""
    name = re.compile(r"(?<![\w$.])" + re.escape(ident) + r"(?![\w$])")
    for m in name.finditer(_mask_strings(src[lo:at]), 1):
        pos = lo + m.start()
        if re.search(r"catch\s*\(\s*$", src[max(0, pos - 12) : pos]):
            if _visible(braces, pos, at):
                return True
        elif (
            _declares(src, pos)
            and not re.match(r"\s*=(?![=>])", src[m.end() + lo : m.end() + lo + 8])
            and _visible(braces, pos, at, src)
        ):
            return True
    return False


def _visible(braces: BraceMap, pos: int, at: int, src: str | None = None) -> bool:
    """Whether a declaration at `pos` is visible from a reader at `at`: at
    the top level, or in a block that also holds the reader; with `src`, a
    `var` is visible throughout its function. A binding local to an
    unrelated function is not the one `at` reads; with `src`, a `let` or
    `const` in a `for` head is visible only in that loop."""
    if src is not None and (loop := _for_scope(src, braces, pos)) is not None:
        return loop[0] < at <= loop[1]
    block = braces.enclosing(pos)
    if block is None or block[0] < at <= block[1]:
        return True
    if src is None or not _is_var(src, pos):
        return False
    scope = _function_block(src, braces, pos)
    return scope is not None and scope[0] < at <= scope[1]


def _declaration(
    src: str,
    braces: BraceMap,
    ident: str,
    at: int,
    pattern_for: Any,
    later_ok: Any = lambda _m: True,
) -> re.Match[str] | None:
    """The declaration of `ident` that the code at `at` reads.

    In a bundle of concatenated modules, where minified names repeat from
    module to module: a name the module imports is declared at the top level
    of the one module exporting it (anything else is unresolved); any other
    name is declared in the module itself (nearest before `at`, else first
    after when `later_ok` allows it), and a name neither imported nor
    declared there is unresolved.
    A single-module source keeps the plain rule: nearest before `at`.
    """
    if len(_chunk_starts(src)) == 1:
        found = None
        for m in pattern_for(ident).finditer(src, 0, at):
            if _visible(braces, m.start(), at, src):
                found = m
        return found
    lo, hi = _chunk_span(src, at)
    exported = _chunk_imports(src, lo, hi).get(ident)
    if exported is not None and any(
        braces.enclosing(m.start()) is not None and _visible(braces, m.start(), at, src)
        for m in pattern_for(ident).finditer(src, lo, hi)
    ):
        exported = None
    if exported is not None:
        homes = _export_index(src).get(exported, [])
        if len(homes) != 1:
            return None
        home, local = homes[0]
        top = [
            m
            for m in pattern_for(local).finditer(src, home, _chunk_span(src, home)[1])
            if braces.enclosing(m.start()) is None
        ]
        return top[0] if len(top) == 1 else None
    pattern = pattern_for(ident)
    if pattern_for is _function_pattern:
        # A function declaration is hoisted through its whole block, so the
        # innermost visible one wins wherever it sits, then the nearest.
        visible = [
            m for m in pattern.finditer(src, lo, hi) if _visible(braces, m.start(), at)
        ]
        if not visible:
            return None

        def rank(m: re.Match[str]) -> tuple[int, int]:
            block = braces.enclosing(m.start())
            return (block[0] if block else -1, -abs(m.start() - at))

        return max(visible, key=rank)
    found = None
    for m in pattern.finditer(src, lo, at):
        if _visible(braces, m.start(), at, src):
            found = m
    if found is not None:
        # A declaration later in a scope nearer the reader shadows `found`
        # and is not yet initialized when read: the value is not static.
        # A `var` hoists to its function, so one anywhere in the reader's
        # function counts, however deeply it is nested there.
        outer = braces.enclosing(found.start())
        outer_open = outer[0] if outer else -1
        reader = _function_block(src, braces, at)
        for m in pattern.finditer(src, at, hi):
            block = braces.enclosing(m.start())
            if (
                block
                and block[0] > outer_open
                and (
                    _visible(braces, m.start(), at, src)
                    or (
                        reader is not None
                        and reader[0] < m.start() < reader[1]
                        and _is_var(src, m.start())
                    )
                )
                and re.search(
                    r"(?:\b(?:var|let|const)\s+|,\s*)$",
                    src[max(0, m.start() - 8) : m.start()],
                )
            ):
                return None
    if found is None:
        found = next(
            (
                m
                for m in pattern.finditer(src, at, hi)
                if _visible(braces, m.start(), at, src)
            ),
            None,
        )
        if found is not None and not later_ok(found):
            found = None
    return found


def _write_pattern(ident: str) -> re.Pattern[str]:
    """Any write to `ident`: plain or compound assignment, `++` or `--`, a
    destructuring target at any depth (`[x]=`, `{a:{b:x}}=`), or a
    `for (x of|in ...)` head. A pattern is not parsed: `x` followed in its
    statement by `]=` or `}=` counts, which can only over-report a write."""
    name = re.escape(ident)
    return re.compile(
        r"(?<![\w$.])(?:(?:\+\+|--)\s*"
        + name
        + r"(?![\w$])|"
        + name
        + r"\s*(?:\+\+|--|(?:\*\*|<<|>>>?|&&|\|\||\?\?|[-+*/%&|^])?=(?![=>])))"
        + r"|(?<![\w$.])"
        + name
        + r"(?![\w$])[^;]*?[\]}]\s*=(?![=>])"
        + r"|for\s*\(\s*"
        + name
        + r"\s+(?:of|in)\b"
    )


def _binding_pattern(ident: str) -> re.Pattern[str]:
    name = re.escape(ident)
    return re.compile(name + r"(?<![\w$.]" + name + r")\s*=(?![=>])\s*")


def _binding_value(
    src: str, braces: BraceMap, ident: str, at: int, *, deferred: bool = False
) -> int | None:
    """Offset of the `ident=` value `at` reads.

    A single-character name is function-local: the nearest binding before
    `at` in `at`'s own module, within `SHORT_VALUE_LOCALITY_BYTES`. A longer
    one follows the module rule in `_declaration`. A binding after `at` is
    taken only when the read is `deferred`, reached through a getter, a
    method, an arrow, or a function-valued field, which run after the module
    has loaded, and only when that binding is at the module's top level: an
    eager read, such as a field's `f()` call at load time, sees no later
    initializer.
    """
    if len(ident) == 1:
        lo = max(_chunk_span(src, at)[0], at - SHORT_VALUE_LOCALITY_BYTES)
        found = None
        for m in _binding_pattern(ident).finditer(src, lo, at):
            if _visible(braces, m.start(), at, src):
                found = m
    else:
        found = _declaration(
            src,
            braces,
            ident,
            at,
            _binding_pattern,
            lambda later: deferred and braces.enclosing(later.start()) is None,
        )
    if found is None:
        return None
    # An imported binding lives in another module: what can shadow it is
    # declared in the reader's own module.
    home = _chunk_span(src, at)[0]
    lo = found.start() if home <= found.start() < at else home
    if _redeclared_later(src, braces, ident, at) or _unset_between(
        src, braces, ident, lo, at
    ):
        return None
    return found.end()


def _function_pattern(ident: str) -> re.Pattern[str]:
    return re.compile(r"function\s+" + re.escape(ident) + r"\s*\(([^()]*)\)\s*\{")


def _function_body(
    src: str, braces: BraceMap, ident: str, at: int
) -> tuple[int, Scope, str] | None:
    """The `{` of `function ident(...){...}` and its parameter names.

    A single-character name is usually function-local; it resolves only to
    the one top-level declaration in `at`'s own module, and only when the
    source is split into modules. A declaration of `ident` in `at`'s module
    whose parameter list holds parentheses is not read, so any such
    declaration leaves the name unresolved rather than skipped.
    """
    lo, hi = _chunk_span(src, at)
    head = re.compile(r"function\s+" + re.escape(ident) + r"\s*\(")
    if len(head.findall(src, lo, hi)) != len(
        _function_pattern(ident).findall(src, lo, hi)
    ):
        return None
    if len(ident) == 1:
        if len(_chunk_starts(src)) == 1:
            return None
        lo, hi = _chunk_span(src, at)
        top = [
            m
            for m in _function_pattern(ident).finditer(src, lo, hi)
            if braces.enclosing(m.start()) is None
        ]
        if len(top) != 1:
            return None
        return top[0].end() - 1, _param_names(top[0].group(1)), top[0].group(1)
    if len(_chunk_starts(src)) == 1:
        found = _declaration(src, braces, ident, at, _function_pattern)
        found = found or _function_pattern(ident).search(src, at)
    else:
        found = _declaration(src, braces, ident, at, _function_pattern)
    if found is None:
        return None
    return found.end() - 1, _param_names(found.group(1)), found.group(1)


def _bound_arguments(
    src: str,
    braces: BraceMap,
    params: str,
    open_paren: int,
    *,
    hops: int,
    shadow: Scope,
    deferred: bool = False,
) -> dict[str, list[str]]:
    """Each plain parameter mapped to the values its call-site argument
    resolves to; a destructured or defaulted list binds nothing."""
    names = [p.strip() for p in params.split(",")] if params.strip() else []
    if hops <= 0 or not all(re.fullmatch(_IDENT, p) for p in names):
        return {}
    close = _match_close(src, braces, open_paren, len(src)) - 1
    starts = _split_args(src, braces, open_paren + 1)
    out: dict[str, list[str]] = {}
    for k, name in enumerate(names[: len(starts)]):
        stop = (starts[k + 1] if k + 1 < len(starts) else close) - 1
        while stop >= starts[k] and src[stop] in " \t\r\n,":
            stop -= 1
        if stop < starts[k]:
            continue
        value = _sub_value(
            src,
            braces,
            starts[k],
            stop + 1,
            _Values(),
            hops=hops,
            anchor=None,
            shadow=shadow,
            deferred=deferred,
        )
        if value:
            # A partial argument keeps a runtime alternative ahead of its values.
            out[name] = ([_ELLIPSIS] if value.partial else []) + list(value)
    return out


def _resolve_chain(
    src: str,
    braces: BraceMap,
    chain: list[tuple[str, str]],
    pos: int,
    acc: _Values,
    *,
    hops: int,
    anchor: int | None,
    shadow: Scope = NO_SCOPE,
    deferred: bool = False,
) -> list[str] | None:
    """The string values a constant, a call, or a member read yields.

    A call is followed into its function declaration whatever its arguments.
    A plain parameter takes the values its argument resolves to at the call
    site; every other parameter is a runtime value, so what depends on it
    stays unresolved while the rest of the body resolves.
    """
    ident = chain[0][1]
    if ident in shadow:
        bound = shadow[ident]
        return bound if bound is not None and len(chain) == 1 else None
    if hops <= 0:
        return None
    at = anchor if anchor is not None else pos
    sub = _Values()
    # A bare identifier naming a function declaration is a function-valued
    # field, which the registrars read through a getter: resolve it as a call
    # when the declaration is nearer than any `ident=` binding.
    v = (
        _binding_value(src, braces, ident, at, deferred=deferred)
        if len(chain) == 1
        else None
    )
    fn = _function_body(src, braces, ident, at) if len(chain) == 1 else None
    if fn is not None and v is not None and (fn[0] > at or fn[0] < v):
        fn = None
    if len(chain) == 1 and fn is None:
        if v is None:
            return None
        # A local binding (inside a function) reads that function's scope.
        local = braces.enclosing(v) is not None
        _scan(
            src,
            braces,
            v,
            len(src),
            sub,
            block=False,
            hops=hops - 1,
            anchor=None,
            shadow=shadow if local else NO_SCOPE,
            deferred=deferred and local,
        )
        acc.via.add("constant")
    elif (len(chain) == 2 and chain[1][0] == "call") or fn is not None:
        fn = fn or _function_body(src, braces, ident, at)
        close = None if fn is None else braces.pairs.get(fn[0])
        if fn is None or close is None:
            return None
        # A nested function closes over its caller's parameters; a top-level
        # one sees none of them.
        nested = braces.enclosing(fn[0] - 1) is not None
        scope = {**shadow, **fn[1]} if nested else fn[1]
        if len(chain) == 2:
            body = _mask_strings(src[fn[0] : close])
            scope = {
                **scope,
                **{
                    # A parameter the body reassigns is not its argument.
                    name: values
                    for name, values in _bound_arguments(
                        src,
                        braces,
                        fn[2],
                        chain[1][2],
                        hops=hops - 1,
                        shadow=shadow,
                        deferred=deferred,
                    ).items()
                    if not _write_pattern(name).search(body)
                },
            }
        _scan(
            src,
            braces,
            fn[0] + 1,
            close,
            sub,
            block=True,
            hops=hops - 1,
            anchor=None,
            shadow=scope,
            # A function-valued field is read through a getter: deferred.
            deferred=deferred or len(chain) == 1,
        )
        acc.via.add("call")
    elif len(chain) == 2 and chain[1][0] == "prop":
        if len(ident) == 1:
            return None
        # The object the reader sees: the visible binding holding a literal,
        # following aliases (`let t=c`) through each one's own visible
        # binding; no visible binding at all is unresolved.
        obj, target, where, hop_deferred = None, ident, at, deferred
        for _ in range(_MAX_HOPS):
            v = _binding_value(src, braces, target, where, deferred=hop_deferred)
            if v is None:
                break
            close_v = braces.pairs.get(v)
            if close_v is not None:
                obj = (v, src[v : close_v + 1])
                break
            alias = re.match(_IDENT + r"(?=[;,)\s])", src[v : v + 64])
            if not alias:
                break
            # An alias initializer runs when its own scope does: a top-level
            # one at load time, so it reads no later binding.
            hop_deferred = hop_deferred and braces.enclosing(v) is not None
            target, where = alias.group(0), v
        if obj is None:
            return None
        found = _eval_field(
            src,
            braces,
            obj[0],
            chain[1][1],
            sub,
            hops=hops - 1,
            anchor=None,
            # A local object literal reads the enclosing function's scope.
            shadow=shadow if braces.enclosing(obj[0] - 1) is not None else NO_SCOPE,
        )
        if found is None:
            return None
        acc.via.add("constant")
    else:
        return None
    acc.via |= sub.via
    # A branch the reader could not settle stays visible to the caller, so a
    # substitution or argument built from this value keeps its runtime part.
    acc.unresolved += sub.unresolved
    return sub.variants or None


def _eval_field(
    src: str,
    braces: BraceMap,
    open_i: int,
    key: str,
    acc: _Values,
    *,
    hops: int = _MAX_HOPS,
    anchor: int | None = None,
    methods: bool = False,
    shadow: Scope = NO_SCOPE,
) -> str | None:
    """Evaluate one top-level field into `acc`; returns its form, or None when absent."""
    entry = _object_fields(src, braces, open_i, methods=methods).get(key)
    if entry is None:
        return None
    kind, pos = entry
    if kind in ("getter", "method"):
        if kind == "method":
            acc.via.add("call")
        close = braces.pairs.get(pos)
        if close is None:
            return kind
        _scan(
            src,
            braces,
            pos + 1,
            close,
            acc,
            block=True,
            hops=hops,
            anchor=anchor,
            # A getter or method closes over the scope it was read in.
            shadow={**shadow, **_params_before(src, braces, pos)},
            deferred=True,
        )
        return kind
    close = braces.pairs.get(open_i, len(src))
    _scan(
        src,
        braces,
        pos,
        close,
        acc,
        block=False,
        hops=hops,
        anchor=anchor,
        shadow=shadow,
    )
    return "value"


def resolve_field(
    src: str,
    braces: BraceMap,
    open_i: int,
    key: str,
    anchor: int | None = None,
    *,
    methods: bool = False,
) -> dict[str, Any] | None:
    """Statically resolve one string field of an object literal.

    Returns None when the object has no such field. Otherwise `value` is the
    fallthrough variant (the else branch of a ternary, the last `return` of a
    getter), which is what a default session shows; `variants` lists every
    alternative when there is more than one; `source` names the form:
    literal, template (a runtime substitution rendered as an ellipsis),
    constant, call, getter, arrow, or unresolved. With `methods`, a method
    (`description(){return x}`) is read like a getter and labeled `call`.
    """
    acc = _Values()
    try:
        form = _eval_field(
            src, braces, open_i, key, acc, anchor=anchor, methods=methods
        )
    except (ValueError, IndexError, RecursionError):
        form, acc = "value", _Values()
    if form is None:
        return None
    if not acc.variants:
        source = "unresolved"
    elif form == "getter":
        source = "getter"
    else:
        source = next(
            (s for s in ("arrow", "call", "constant", "template") if s in acc.via),
            "literal",
        )
    out: dict[str, Any] = {
        "value": acc.variants[-1] if acc.variants else None,
        "source": source,
    }
    if len(acc.variants) > 1:
        out["variants"] = acc.variants
    return out


def _apply_field(
    rec: dict[str, Any], key: str, resolved: dict[str, Any] | None
) -> None:
    """Write a resolved field as `<key>`, `<key>_source`, and `<key>_variants`."""
    rec[key] = resolved["value"] if resolved else None
    rec[f"{key}_source"] = resolved["source"] if resolved else "absent"
    if resolved and "variants" in resolved:
        rec[f"{key}_variants"] = resolved["variants"]


# --------------------------------------------------------------------------
# Extracting the registries
# --------------------------------------------------------------------------

_TYPE_RE = re.compile(r'type:"(local|local-jsx|prompt)"')
_NAME_RE = re.compile(r"(?:^|[,{])name:" + _STR)
_NAME_IDENT_RE = re.compile(r"(?:^\{|,)name:([A-Za-z_$][A-Za-z0-9_$]*)(?=[,}])")
_UFN_RE = re.compile(r"userFacingName\(\)\{return" + _STR)
_ALIAS_RE = re.compile(r"aliases:\[([^\]]*)\]")
_NAME_OK = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9:_-]{0,40}")

# Names that exist in the build but are never typed by a user.
INTERNAL_NAMES = {
    "mcp__",
    "workflow-launch-exec",
    "pro-trial-expired",
    "rate-limit-options",
    "stub",
}


def extract_builtin_commands(src: str, braces: BraceMap) -> dict[str, dict[str, Any]]:
    """Built-in CLI commands, keyed by name.

    Each command is a small object literal carrying `type` and `name`. The
    enclosing object is resolved by brace depth, then its own fields are read,
    so an adjacent command's description cannot bleed in.
    """
    literals: list[tuple[re.Match[str], int, str]] = []
    for m in _TYPE_RE.finditer(src):
        enc = braces.enclosing(m.start())
        if not enc:
            continue
        open_i, close_i = enc
        if close_i - open_i > 4000:
            # Too large to be a command literal - this is some enclosing scope.
            continue
        literals.append((m, open_i, src[open_i : close_i + 1]))

    # A name held in a hoisted constant (`name:EMr` where `EMr="commit-push-pr"`)
    # resolves by the same nearest-preceding rule as a bundled skill. A
    # single-character identifier here is a factory's parameter
    # (`function t1t(e,...){return{type:...,name:e}}`), not one command, so it
    # is never resolved.
    idents = {
        c.group(1)
        for _, _, body in literals
        if not _NAME_RE.search(body)
        for c in [_NAME_IDENT_RE.search(body)]
        if c and len(c.group(1)) > 1
    }
    index = build_const_index(src, idents)

    out: dict[str, dict[str, Any]] = {}
    for m, open_i, body in literals:
        nm = _NAME_RE.search(body) or _UFN_RE.search(body)
        if nm:
            name = _unescape(nm.group(1))
        else:
            c = _NAME_IDENT_RE.search(body)
            if not c or c.group(1) not in idents:
                continue
            name = resolve_name_ident(c.group(1), open_i, index)
        if not name or not _NAME_OK.fullmatch(name):
            continue
        aliases = _read_aliases(body)
        rec = {
            "name": name,
            "source": "builtin",
            "type": m.group(1),
            "aliases": aliases,
            "hidden": "isHidden" in body,
            "gated": "isEnabled" in body,
            "internal": name in INTERNAL_NAMES,
        }
        _apply_field(
            rec, "description", resolve_field(src, braces, open_i, "description")
        )
        rec["description"] = rec["description"] or ""
        _apply_field(
            rec, "argument_hint", resolve_field(src, braces, open_i, "argumentHint")
        )
        rec.update(read_invocation_fields(body))
        origin = resolve_field(src, braces, open_i, "source")
        rec.update(command_invocability(rec, origin["value"] if origin else None))
        prev = out.get(name)
        if prev is None or (not prev["description"] and rec["description"]):
            if prev is not None:
                rec["aliases"] = sorted(set(prev["aliases"]) | set(aliases))
            out[name] = rec
        elif aliases:
            prev["aliases"] = sorted(set(prev["aliases"]) | set(aliases))
    return out


def command_invocability(rec: dict[str, Any], origin: str | None) -> dict[str, Any]:
    """Who can invoke a built-in command, as far as the bundle decides it.

    The Skill tool admits a command only when it is `type:"prompt"`, not
    `disableModelInvocation`, and (for a built-in) declares `source:"builtin"`;
    `local` and `local-jsx` commands never reach it. A function-valued field
    is decided at runtime, so it reads null rather than a guess. A per-machine
    skill override in settings can still turn a command off; that is config,
    not the bundle, and is not read here.
    """
    flag_driven = set(rec.get("flag_driven") or [])
    if "user_invocable" in flag_driven:
        user: bool | None = None
    else:
        user = rec.get("user_invocable", True)
    if rec["type"] != "prompt":
        model: bool | None = False
    elif "disable_model_invocation" in flag_driven:
        model = None
    elif rec.get("disable_model_invocation"):
        model = False
    elif origin == "builtin":
        model = True
    else:
        model = None
    return {"user_invocable": user, "model_invocable": model}


def skill_invocability(rec: dict[str, Any]) -> dict[str, Any]:
    """Who can invoke a bundled skill: `userInvocable` defaults true and
    `disableModelInvocation` false in the bundled registrar; a function-valued
    field becomes a runtime getter and reads null."""
    flag_driven = set(rec.get("flag_driven") or [])
    user = None if "user_invocable" in flag_driven else rec.get("user_invocable", True)
    if "disable_model_invocation" in flag_driven:
        model = None
    else:
        model = not rec.get("disable_model_invocation", False)
    return {"user_invocable": user, "model_invocable": model}


def _read_aliases(body: str) -> list[str]:
    m = _ALIAS_RE.search(body)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


_IDENT = r"[A-Za-z_$][A-Za-z0-9_$]*"
# The canary registration: `doctor` has shipped in every build observed and its
# alias makes the literal unambiguous. The callee immediately before it is the
# registrar when no export map names one.
_CANARY_REGISTRATION = r'\(\{name:"doctor",aliases:\["checkup"\]'


def discover_registrar_route(
    src: str, export_name: str
) -> tuple[str | None, str | None]:
    """Resolve a minified registrar function, and say which route resolved it.

    Minified identifiers are regenerated every release, so hardcoding one dates
    the script immediately. Three routes, tried in order, each keyed on
    something the bundle keeps readable:

      export-map   the CJS getter `registerBundledSkill:()=>xu`
      esm-export   the ESM export list `xu as registerBundledSkill`
      canary       the callee immediately preceding the `doctor` registration
                   (only for the bundled-skill registrar)

    Returns (identifier, route), or (None, None) when no route resolves.
    """
    m = re.search(re.escape(export_name) + r":\(\)=>(" + _IDENT + ")", src)
    if m:
        return m.group(1), "export-map"
    m = re.search(r"\b(" + _IDENT + r") as " + re.escape(export_name) + r"\b", src)
    if m:
        return m.group(1), "esm-export"
    if export_name == "registerBundledSkill":
        m = re.search(r"\b(" + _IDENT + r")" + _CANARY_REGISTRATION, src)
        if m:
            return m.group(1), "canary"
    return None, None


def discover_registrar(src: str, export_name: str) -> str | None:
    """The registrar identifier alone; see `discover_registrar_route`."""
    return discover_registrar_route(src, export_name)[0]


_KEBAB_BINDING_RE = re.compile(
    r"\b(" + _IDENT + r')\s*=\s*"([a-z][a-z0-9]*(?:-[a-z0-9]+)*)"'
)


def build_const_index(
    src: str, idents: set[str] | None = None, value_re: str | None = None
) -> dict[str, list[tuple[int, str]]]:
    """Every `ident="kebab-case"` binding, keyed by identifier, in source order.

    Several bundled skills are registered as `xu({name:gme,...})` where `gme`
    is a hoisted constant, so a literal-only scan silently misses them. The
    positions are kept because a name is resolved by locality, never by a
    single global value: the same identifier is bound to other strings in
    unrelated modules, and in the bytecode layout the real binding sits
    megabytes ahead of the registration. Passing the identifiers that need
    resolving narrows the scan to those names, which is a fraction of the cost
    of indexing every binding in a 37 MB source.
    """
    value = value_re or r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
    if idents is not None:
        if not idents:
            return {}
        # `(?<![\w$])`, not `\b`: minified names may start with `$`, before
        # which `\b` needs a word character and so never matches a real start.
        pattern = re.compile(
            r"(?<![\w$])("
            + "|".join(re.escape(i) for i in sorted(idents, key=len, reverse=True))
            + r')\s*=\s*"('
            + value
            + r')"'
        )
    elif value_re:
        pattern = re.compile(r"(?<![\w$])(" + _IDENT + r')\s*=\s*"(' + value + r')"')
    else:
        pattern = _KEBAB_BINDING_RE
    index: dict[str, list[tuple[int, str]]] = {}
    for m in pattern.finditer(src):
        index.setdefault(m.group(1), []).append((m.start(), m.group(2)))
    return index


def resolve_name_ident(
    ident: str, at: int, index: dict[str, list[tuple[int, str]]]
) -> str | None:
    """Resolve a registration's name identifier by its nearest preceding binding.

    Locality rule, stated exactly: the binding is the nearest `ident="..."`
    before the registration; a farther binding never wins over a nearer one,
    which is what keeps an unrelated module's `oO="ehrpd"` from shadowing the
    real `oO="artifact-design"` bound closer in. A single-character identifier
    is trusted only when that nearest binding lies within
    `SHORT_IDENT_LOCALITY_BYTES`, because such names are function-local and a
    far binding belongs to some other function. No preceding binding at all is
    unresolved, never guessed.
    """
    bindings = index.get(ident)
    if not bindings:
        return None
    k = bisect.bisect_left(bindings, (at, "")) - 1
    if k < 0:
        return None
    pos, value = bindings[k]
    if len(ident) == 1 and at - pos > SHORT_IDENT_LOCALITY_BYTES:
        return None
    return value


def _nearest_binding(src: str, ident: str, at: int) -> int | None:
    """Offset of the value in the nearest `ident=<value>` binding before `at`.

    The same locality rule as `resolve_name_ident`: nearest preceding wins, and
    a single-character identifier is only looked for within
    `SHORT_IDENT_LOCALITY_BYTES`.
    """
    lo = max(0, at - SHORT_IDENT_LOCALITY_BYTES) if len(ident) == 1 else 0
    # The identifier leads and the boundary check trails it: a pattern that
    # opens with a lookbehind loses the regex engine's literal-prefix scan and
    # runs about thirty times slower over a 45 MB source.
    name = re.escape(ident)
    pattern = re.compile(name + r"(?<![\w$.]" + name + r")\s*=(?![=>])\s*")
    last = None
    for m in pattern.finditer(src, lo, at):
        last = m
    return last.end() if last else None


def _resolve_object(
    src: str, braces: BraceMap, ident: str, at: int, hops: int = 4
) -> tuple[int, str] | None:
    """The object literal an identifier is bound to, following `a=b` aliases.

    Returns the literal's open-brace offset and its text, or None when the
    nearest binding is anything else.
    """
    for _ in range(hops):
        v = _nearest_binding(src, ident, at)
        if v is None:
            return None
        if src.startswith("{", v):
            close = braces.pairs.get(v)
            return None if close is None else (v, src[v : close + 1])
        alias = re.match(_IDENT + r"(?=[;,)\s])", src[v : v + 64])
        if not alias:
            return None
        ident, at = alias.group(0), v
    return None


def _resolve_descriptor_name(
    src: str, braces: BraceMap, ident: str, at: int
) -> tuple[str, int] | None:
    """Resolve `name:x.name`: the registration reads its fields from a descriptor.

    `let t=c;registrar({name:t.name,description:t.description,...})` where
    `c={name:o,...}` and `o="slides"`. Returns the name and the descriptor's
    offset, whose fields stand in for the registration's member reads.
    """
    obj = _resolve_object(src, braces, ident, at)
    if obj is None:
        return None
    open_i, body = obj
    m = re.search(r"(?:^\{|,)name:(?:" + _STR + r"|(" + _IDENT + r")\b)", body)
    if not m:
        return None
    if m.group(1) is not None:
        return _unescape(m.group(1)), open_i
    v = _nearest_binding(src, m.group(2), open_i)
    lit = re.match(_STR, src[v : v + 256]) if v is not None else None
    return (_unescape(lit.group(1)), open_i) if lit else None


_ROSTER_HEAD_RE = re.compile(
    r"for\(\s*(?:let|const|var)\s*\{(?P<pattern>[^{}]*)\}\s*of\s*(?P<table>"
    + _IDENT
    + r")\s*\)\s*\{?\s*$"
)


def _resolve_roster(
    src: str, braces: BraceMap, call_start: int
) -> tuple[str, dict[str, str], list[str]] | None:
    """A registration looping over a literal table: the table and its rows.

    `for(let{kind:e,description:n}of Qi)registrar({name:\\`artifact-${e}\\`,...})`
    where `Qi=[{kind:"table",description:"..."},...]` is enumerable without
    running the binary. Returns the table identifier, the destructuring map
    (local variable to row key), and each row's text. None when the loop, the
    table binding, or any row is not a plain literal.
    """
    pre = src[max(0, call_start - 300) : call_start]
    head = _ROSTER_HEAD_RE.search(pre)
    if not head:
        return None
    var_to_key: dict[str, str] = {}
    for part in head.group("pattern").split(","):
        key, _, var = part.strip().partition(":")
        if not re.fullmatch(_IDENT, key) or (var and not re.fullmatch(_IDENT, var)):
            return None
        var_to_key[var or key] = key
    table = head.group("table")
    v = _nearest_binding(src, table, call_start - len(pre) + head.start())
    if v is None or not src.startswith("[", v):
        return None
    rows: list[str] = []
    i = v + 1
    while True:
        while i < len(src) and src[i] in " \t\r\n,":
            i += 1
        if src.startswith("]", i):
            return table, var_to_key, rows
        close = braces.pairs.get(i) if src.startswith("{", i) else None
        if close is None:
            return None
        rows.append(src[i : close + 1])
        i = close + 1


def _row_field(row: str, key: str) -> str | None:
    m = re.search(r"(?:^\{|,)" + re.escape(key) + ":" + _STR, row)
    return _unescape(m.group(1)) if m else None


_FOR_HEAD_RE = re.compile(r"for\((?P<head>[^()]*)\)\s*\{?\s*$")
_INVOCATION_FIELDS: tuple[tuple[str, str], ...] = (
    ("user_invocable", "userInvocable"),
    ("disable_model_invocation", "disableModelInvocation"),
    ("terminal_oriented", "terminalOriented"),
    ("survives_kill_switch", "survivesBundledKillSwitch"),
)


def _is_loop_registration(src: str, call_start: int, ident: str) -> bool:
    """True when the registration sits inside a `for(... of ...)` whose head binds `ident`.

    Such a registration is a dynamic roster (one call registering many
    skills from a table), not one skill with a computed name.
    """
    pre = src[max(0, call_start - 300) : call_start]
    m = _FOR_HEAD_RE.search(pre)
    if not m:
        return False
    head = m.group("head")
    return bool(
        re.search(r"\bof\b", head) and re.search(r"\b" + re.escape(ident) + r"\b", head)
    )


def read_invocation_fields(body: str) -> dict[str, Any]:
    """The invocation-control fields a registration carries, when present.

    `!0` is true and `!1` false in the minified source. A function-valued
    field (`disableModelInvocation:()=>...`) is recorded as true with
    `flag_driven`, matching the binary's own serializer, which treats any
    function as disabled.
    """
    out: dict[str, Any] = {}
    for key, field_name in _INVOCATION_FIELDS:
        m = re.search(
            r"\b" + field_name + r":(!0|!1|\(\)=>|function\b|[A-Za-z_$])", body
        )
        if not m:
            continue
        token = m.group(1)
        if token == "!0":
            out[key] = True
        elif token == "!1":
            out[key] = False
        else:
            out[key] = True
            out.setdefault("flag_driven", []).append(key)
    return out


def extract_bundled_skills(
    src: str, braces: BraceMap
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Bundled skills, keyed by name, plus notes about resolution.

    Each registration's fields are bound to its own `{...}` via the brace map,
    for the same reason command extraction is: registrations sit flush against
    one another, so a fixed-width window around one silently adopts the next
    one's description or aliases whenever a field is absent.

    Two distinct registrations sharing one name are both kept, as a list under
    that name with a `collision` note, never merged and never last-writer-wins:
    a consumer deciding a per-registration property such as model
    invocability would otherwise read whichever the bundle happened to place
    last.
    """
    notes: dict[str, Any] = {}
    fn, route = discover_registrar_route(src, "registerBundledSkill")
    notes["registrar"] = fn
    notes["registrar_route"] = route
    if not fn:
        notes["error"] = "registerBundledSkill export not found - build layout changed"
        return {}, notes

    # First pass: bound every call and read its name expression. A call whose
    # object carries no `name:` is another module's function that happens to
    # share the minified identifier, not a registration, so it is counted
    # apart and never inflates the resolved-versus-seen gap.
    calls: list[tuple[int, int, str, re.Match[str]]] = []
    unbounded = 0
    same_ident_calls = 0
    name_re = re.compile(
        r"\bname:(?:" + _STR + r"|(" + _IDENT + r")(\.name\b)?|(`[^`]*`))"
    )
    # A call is the registrar identifier standing alone: `xps({` is another
    # function whose name merely ends in the registrar's.
    for m in re.finditer(r"(?<![\w$.])" + re.escape(fn) + r"\(\{", src):
        open_i = m.end() - 1  # the '{' captured by the pattern
        close_i = braces.pairs.get(open_i)
        if close_i is None:
            # An unmatched brace means the tokenizer desynced; skipping is the
            # honest response, and the count difference surfaces it.
            unbounded += 1
            continue
        body = src[open_i : close_i + 1]
        nm = name_re.search(body)
        if not nm:
            same_ident_calls += 1
            continue
        calls.append((m.start(), open_i, body, nm))

    idents = {nm.group(2) for *_, nm in calls if nm.group(2) and not nm.group(3)}
    index = build_const_index(src, idents)
    out: dict[str, Any] = {}
    unresolved: list[str] = []
    dynamic_rosters = 0
    dynamic_patterns: list[str] = []
    rosters: dict[str, int] = {}
    seen = 0
    resolved_calls = 0
    collisions: list[str] = []

    def add(rec: dict[str, Any]) -> None:
        name = rec["name"]
        prev = out.get(name)
        if prev is None:
            out[name] = rec
            return
        existing = registrations_of(prev)
        if any(_same_registration(e, rec) for e in existing):
            return
        # A genuine collision: keep every registration, keyed by name.
        for e in existing:
            e["collision"] = True
        rec["collision"] = True
        out[name] = [*existing, rec]
        if name not in collisions:
            collisions.append(name)

    for call_start, open_i, body, nm in calls:
        seen += 1
        descriptor: int | None = None
        if nm.group(1) is not None:
            name = _unescape(nm.group(1))
        elif nm.group(4) is not None or _is_loop_registration(
            src, call_start, nm.group(2)
        ):
            # A template literal or a loop variable: one call registering a
            # family, enumerable statically only when the loop walks a
            # literal table.
            roster = _resolve_roster(src, braces, call_start)
            rows = _roster_records(src, braces, open_i, nm, roster) if roster else None
            if roster is None or rows is None:
                dynamic_rosters += 1
                dynamic_patterns.append(
                    nm.group(4) or f"for(... of ...) over {nm.group(2)}"
                )
                continue
            resolved_calls += 1
            rosters[roster[0]] = len(rows)
            for rec in rows:
                add(rec)
            continue
        elif nm.group(3) is not None:
            found = _resolve_descriptor_name(src, braces, nm.group(2), call_start)
            if found is None:
                unresolved.append(f"{nm.group(2)}.name")
                continue
            name, descriptor = found
        else:
            resolved = resolve_name_ident(nm.group(2), call_start, index)
            if resolved is None:
                unresolved.append(nm.group(2))
                continue
            name = resolved
        resolved_calls += 1
        add(_skill_record(src, braces, name, open_i, descriptor))

    # Counted per call, not per row: a roster call is one registration however
    # many rows it expands to, so it can never mask an unresolved one.
    notes["registrations_seen"] = seen
    notes["resolved"] = resolved_calls
    if rosters:
        notes["rosters_resolved"] = rosters
    if unresolved:
        notes["unresolved_dynamic_names"] = sorted(set(unresolved))
    if dynamic_rosters:
        notes["dynamic_roster"] = dynamic_rosters
        notes["dynamic_roster_patterns"] = dynamic_patterns
    if unbounded:
        notes["unbounded_registrations"] = unbounded
    if same_ident_calls:
        notes["same_identifier_calls_skipped"] = same_ident_calls
    if collisions:
        notes["collisions"] = sorted(collisions)
    return out, notes


def _skill_record(
    src: str,
    braces: BraceMap,
    name: str,
    open_i: int,
    descriptor: int | None = None,
    row: dict[str, str | None] | None = None,
) -> dict[str, Any]:
    """One bundled-skill row from its registration literal at `open_i`.

    `descriptor` is the offset of the object a `name:x.name` registration
    reads its fields from; a field the literal does not resolve is read
    there. `row` maps a looped registration's variables to one table row's
    values, which answer for a field that reads a loop variable.
    """
    close = braces.pairs[open_i]
    body = src[open_i : close + 1]
    rec: dict[str, Any] = {
        "name": name,
        "source": "bundled-skill",
        "aliases": _read_aliases(body),
        "gated": "isEnabled" in body,
        "hidden": "isHidden" in body,
    }

    def field_of(key: str) -> dict[str, Any] | None:
        if row:
            m = re.search(r"(?:^\{|,)" + key + r":(" + _IDENT + r")(?=[,}])", body)
            if m and m.group(1) in row:
                value = row[m.group(1)]
                return {"value": value, "source": "roster"} if value else None
        found = resolve_field(src, braces, open_i, key)
        if (found is None or found["value"] is None) and descriptor is not None:
            found = resolve_field(src, braces, descriptor, key) or found
        return found

    desc = field_of("description")
    menu = field_of("menuDescription")
    if (desc is None or desc["value"] is None) and menu and menu["value"]:
        desc = menu
    _apply_field(rec, "description", desc)
    rec["description"] = rec["description"] or ""
    if menu and menu["value"]:
        rec["menu_description"] = menu["value"]
    _apply_field(rec, "argument_hint", field_of("argumentHint"))
    rec.update(read_invocation_fields(body))
    rec.update(skill_invocability(rec))
    return rec


def _roster_records(
    src: str,
    braces: BraceMap,
    open_i: int,
    nm: re.Match[str],
    roster: tuple[str, dict[str, str], list[str]],
) -> list[dict[str, Any]] | None:
    """Expand a looped registration over its table's rows; None if any row fails."""
    _, var_to_key, rows = roster
    template = nm.group(4)
    out: list[dict[str, Any]] = []
    for row in rows:
        values = {var: _row_field(row, key) for var, key in var_to_key.items()}
        if template:
            parts = re.split(r"\$\{(" + _IDENT + r")\}", template[1:-1])
            if any(values.get(v) is None for v in parts[1::2]):
                return None
            name = "".join(
                p if k % 2 == 0 else str(values[p]) for k, p in enumerate(parts)
            )
        else:
            name = values.get(nm.group(2)) or ""
        if not _NAME_OK.fullmatch(name):
            return None
        out.append(_skill_record(src, braces, name, open_i, row=values))
    return out


def _same_registration(a: dict[str, Any], b: dict[str, Any]) -> bool:
    # `flag_driven` is part of the identity: a constant-true invocation field
    # and a function-valued one read as the same boolean, and the difference
    # (decided at runtime versus fixed) is exactly the evidence a collision
    # exists to preserve.
    keys = (
        "description",
        "argument_hint",
        "aliases",
        "gated",
        "hidden",
        "flag_driven",
    ) + tuple(k for k, _ in _INVOCATION_FIELDS)
    return all(a.get(k) == b.get(k) for k in keys)


def extract_plugin_backed(src: str) -> dict[str, str]:
    """Commands the build registers as plugin-backed (`pluginName`)."""
    out: dict[str, str] = {}
    pattern = re.compile(
        r'name:"([a-z0-9][a-z0-9:_-]{1,40})"'
        r'((?:(?!name:")[\s\S]){0,900}?)'
        r'pluginName:"([a-z0-9-]+)"'
    )
    for m in pattern.finditer(src):
        out[m.group(1)] = m.group(3)
    return out


_WORKFLOW_PUSH = ".bundledWorkflows.push("
_FUNC_HEAD_RE = re.compile(r"function\s+(" + _IDENT + r")\s*\(([^()]*)\)\s*\{")


def _split_args(src: str, braces: BraceMap, i: int) -> list[int]:
    """Start offsets of each top-level argument of the call whose `(` ends at `i`."""
    n = len(src)
    starts = [_skip_ws(src, i, n)]
    depth = 0
    while i < n:
        ch = src[i]
        if ch in _QUOTES:
            i = _read_literal(src, i, n)[1]
            continue
        if ch == "{":
            close = braces.pairs.get(i)
            if close is None:
                raise ValueError("unmatched brace")
            i = close + 1
            continue
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                return starts
            depth -= 1
        elif ch == "," and depth == 0:
            starts.append(_skip_ws(src, i + 1, n))
        i += 1
    raise ValueError("unterminated call")


def _workflow_registrars(src: str) -> dict[str, tuple[int | None, int | None]]:
    """Each function that pushes onto `bundledWorkflows`, with its argument layout.

    The registrar has no readable export name, so it is found by what it
    does: `function f(script,meta,opts){...bundledWorkflows.push({...meta,
    script, disableModelInvocation: opts?.disableModelInvocation})}`. Returns
    the index of the spread (meta) argument and of the options argument.
    """
    out: dict[str, tuple[int | None, int | None]] = {}
    for m in re.finditer(re.escape(_WORKFLOW_PUSH), src):
        heads = list(_FUNC_HEAD_RE.finditer(src, max(0, m.start() - 400), m.start()))
        if not heads:
            continue
        head = heads[-1]
        params = [p.strip() for p in head.group(2).split(",")]
        tail = src[m.end() : m.end() + 400]
        spread = re.search(r"\.\.\.(" + _IDENT + r")", tail)
        opts = re.search(r"(" + _IDENT + r")\?\.disableModelInvocation", tail)
        out[head.group(1)] = (
            params.index(spread.group(1))
            if spread and spread.group(1) in params
            else None,
            params.index(opts.group(1)) if opts and opts.group(1) in params else None,
        )
    return out


def _array_titles(src: str, braces: BraceMap, ident: str, at: int) -> list[str] | None:
    """`title` of each row of the array literal an identifier is bound to."""
    v = _binding_value(src, braces, ident, at)
    if v is None or not src.startswith("[", v):
        return None
    titles: list[str] = []
    i = v + 1
    while True:
        i = _skip_ws(src, i, len(src))
        if src.startswith(",", i):
            i += 1
            continue
        if src.startswith("]", i):
            return titles
        close = braces.pairs.get(i) if src.startswith("{", i) else None
        if close is None:
            return None
        title = resolve_field(src, braces, i, "title")
        if title and title["value"]:
            titles.append(title["value"])
        i = close + 1


def extract_bundled_workflows(
    src: str, braces: BraceMap
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Bundled workflows (`/deep-research`), keyed by name, plus resolution notes.

    A registration is `registrar(\\`<script>\\`,{name,description,whenToUse,
    phases},{disableModelInvocation})`. Its fields are resolved from the call
    site, never from the script text, whose own identifiers would shadow the
    real bindings under the nearest-preceding rule.
    """
    notes: dict[str, Any] = {"registrar": None, "registrar_route": None}
    registrars = _workflow_registrars(src)
    if not registrars:
        notes["error"] = (
            "no function pushes onto bundledWorkflows - build layout changed"
        )
        return {}, notes
    callees = {r: r for r in registrars}
    for r in registrars:
        for alias in re.findall(r"\b" + re.escape(r) + r" as (" + _IDENT + r")\b", src):
            callees[alias] = r
    notes["registrar"] = sorted(registrars)
    notes["registrar_route"] = "push-site"

    out: dict[str, dict[str, Any]] = {}
    seen = 0
    unresolved: list[str] = []
    for callee, target in callees.items():
        meta_i, opts_i = registrars[target]
        for m in re.finditer(r"(?<![\w$.])" + re.escape(callee) + r"\(", src):
            if src[max(0, m.start() - 9) : m.start()].endswith("function "):
                continue
            seen += 1
            try:
                args = _split_args(src, braces, m.end())
            except (ValueError, IndexError):
                unresolved.append(f"{callee}(...) at {m.start()}")
                continue
            if meta_i is None or meta_i >= len(args):
                unresolved.append(f"{callee}(...) at {m.start()}")
                continue
            meta = args[meta_i]
            if not src.startswith("{", meta):
                obj = _resolve_object(
                    src, braces, src[meta : _ident_end(src, meta)], m.start()
                )
                meta = obj[0] if obj else -1
            name = (
                resolve_field(src, braces, meta, "name", anchor=m.start())
                if meta >= 0
                else None
            )
            if not name or not name["value"] or not _NAME_OK.fullmatch(name["value"]):
                unresolved.append(f"{callee}(...) at {m.start()}")
                continue
            rec: dict[str, Any] = {"name": name["value"], "source": "bundled-workflow"}
            _apply_field(
                rec,
                "description",
                resolve_field(src, braces, meta, "description", anchor=m.start()),
            )
            rec["description"] = rec["description"] or ""
            when = resolve_field(src, braces, meta, "whenToUse", anchor=m.start())
            rec["when_to_use"] = when["value"] if when else None
            _apply_field(
                rec,
                "argument_hint",
                resolve_field(src, braces, meta, "argumentHint", anchor=m.start()),
            )
            phases = _object_fields(src, braces, meta).get("phases")
            if phases and phases[0] == "value" and src[phases[1]] in _ID_START:
                ident = src[phases[1] : _ident_end(src, phases[1])]
                rec["phases"] = _array_titles(src, braces, ident, m.start())
            rec.update(_workflow_invocation(src, braces, args, opts_i))
            out[rec["name"]] = rec
    notes["registrations_seen"] = seen
    notes["resolved"] = len(out)
    if unresolved:
        notes["unresolved"] = unresolved
    return out, notes


def _workflow_invocation(
    src: str, braces: BraceMap, args: list[int], opts_i: int | None
) -> dict[str, Any]:
    """Invocation fields of a workflow registration.

    A bundled workflow becomes a `type:"prompt"` command with no
    `userInvocable` field, so users can always type it. Its
    `disableModelInvocation` is a function the command loader calls at load
    time, which makes model invocability a runtime decision (null) unless the
    registration passes a constant.
    """
    rec: dict[str, Any] = {"user_invocable": True, "model_invocable": True}
    if opts_i is None or opts_i >= len(args) or not src.startswith("{", args[opts_i]):
        return rec
    entry = _object_fields(src, braces, args[opts_i]).get("disableModelInvocation")
    if entry is None:
        return rec
    token = src[entry[1] : entry[1] + 2]
    if entry[0] == "value" and token in ("!0", "!1"):
        rec["disable_model_invocation"] = token == "!0"
        rec["model_invocable"] = token == "!1"
    else:
        rec["disable_model_invocation"] = True
        rec["flag_driven"] = ["disable_model_invocation"]
        rec["model_invocable"] = None
    return rec


# --------------------------------------------------------------------------
# Built-in subagents and tools
# --------------------------------------------------------------------------

_PASCAL_RE = re.compile(r"[A-Z][A-Za-z0-9]*")
_NAME_EXPR_RE = re.compile(_STR + r"|(" + _IDENT + r")(\.[A-Za-z_$][\w$]*)?(?=\s*[,}])")
_BINDING_HEAD_RE = re.compile(r"(?<![\w$.])(" + _IDENT + r")\s*=\s*$")
_EXPORT_RE = re.compile(r"export\{([^{}]*)\}")
_ELEM_LITERAL_RE = re.compile(_STR + r"(?=\s*[,\]])")
_ELEM_SPREAD_RE = re.compile(r"\.\.\.(" + _IDENT + r")(?=\s*[,\]])")
_ELEM_IDENT_RE = re.compile(_IDENT + r"(?=\s*[,\]])")


def resolve_tool_ident(
    ident: str, at: int, index: dict[str, list[tuple[int, str]]]
) -> str | None:
    """Resolve a tool-name identifier by its nearest preceding PascalCase binding.

    Tool names are PascalCase, and in the bytecode layout their constants sit
    megabytes ahead of use, with unrelated modules rebinding the same minified
    identifier in between (`no="SendMessage"`, then `no="column"`). The index
    holds only tool-shaped values; among them the nearest PascalCase binding
    wins, and a snake_case one is taken only when no PascalCase binding
    precedes. A single-character identifier keeps the usual locality limit.
    """
    bindings = index.get(ident)
    if not bindings:
        return None
    before = bindings[: bisect.bisect_left(bindings, (at, ""))]
    if len(ident) == 1:
        before = [b for b in before if at - b[0] <= SHORT_IDENT_LOCALITY_BYTES]
    for _, value in reversed(before):
        if _PASCAL_RE.fullmatch(value):
            return value
    return before[-1][1] if before else None


def _name_expr(
    src: str, fields: dict[str, tuple[str, int]], key: str
) -> tuple[str, str | None]:
    """How a name field is written: ("literal", text), ("ident", name),
    ("member", name) for `e.name`, or ("expr", None) for anything else."""
    entry = fields.get(key)
    if entry is None or entry[0] != "value":
        return "expr", None
    m = _NAME_EXPR_RE.match(src, entry[1])
    if not m:
        return "expr", None
    if m.group(1) is not None:
        return "literal", _unescape(m.group(1))
    return ("member" if m.group(3) else "ident"), m.group(2)


def _literal_flag(
    src: str, fields: dict[str, tuple[str, int]], key: str, default: bool
) -> bool | None:
    """A boolean field: `!0`/`!1` read as written, absent is `default`, and
    anything else (a getter, a method, a call) is decided at runtime: None."""
    entry = fields.get(key)
    if entry is None:
        return default
    if entry[0] == "value" and src.startswith(("!0", "!1"), entry[1]):
        return src.startswith("!0", entry[1])
    return None


def _array_names(
    src: str,
    braces: BraceMap,
    open_i: int,
    index: dict[str, list[tuple[int, str]]],
    at: int,
    hops: int = 2,
) -> tuple[list[str], bool]:
    """Tool names in the array literal at `open_i`, and whether all resolved.

    Elements are string literals, tool-name constants, or a `...spread` of
    another array constant, which is followed `hops` deep.
    """
    names: list[str] = []
    complete = True
    for start in _split_args(src, braces, open_i + 1):
        if src.startswith("]", start):
            continue
        lit = _ELEM_LITERAL_RE.match(src, start)
        spread = _ELEM_SPREAD_RE.match(src, start)
        ident = _ELEM_IDENT_RE.match(src, start)
        if lit:
            names.append(_unescape(lit.group(1)))
        elif spread and hops > 0:
            v = _nearest_binding(src, spread.group(1), at)
            if v is not None and src.startswith("[", v):
                more, ok = _array_names(src, braces, v, index, v, hops - 1)
                names.extend(more)
                complete = complete and ok
            else:
                complete = False
        elif ident and not spread:
            value = resolve_tool_ident(ident.group(0), at, index)
            if value is None:
                complete = False
            else:
                names.append(value)
        else:
            complete = False
    return names, complete


def _tool_list(
    src: str,
    braces: BraceMap,
    open_i: int,
    fields: dict[str, tuple[str, int]],
    key: str,
    index: dict[str, list[tuple[int, str]]],
) -> tuple[list[str] | None, str]:
    """A subagent's tool list and how it was read: `literal`, `partial` (some
    element did not resolve; the list is a floor), `getter` (decided per
    session), `reference` (another object's field), or `absent`."""
    entry = fields.get(key)
    if entry is None:
        return None, "absent"
    if entry[0] != "value":
        return None, "getter"
    if not src.startswith("[", entry[1]):
        return None, "reference"
    try:
        names, complete = _array_names(src, braces, entry[1], index, open_i)
    except (ValueError, IndexError):
        return None, "partial"
    return names, "literal" if complete else "partial"


def _binding_ident(src: str, open_i: int) -> str | None:
    """The identifier an object literal is assigned to (`var X={...}`)."""
    m = _BINDING_HEAD_RE.search(src, max(0, open_i - 80), open_i)
    return m.group(1) if m else None


def _export_names(src: str, ident: str, close_i: int) -> list[str]:
    """Names an `export{...}` gives `ident`.

    The chunk's closing export statement is always read. A one- or
    two-character identifier is chunk-local, so only that statement can
    speak for it; a longer one may be re-exported under another name by a
    later statement (`export{qHe}` then `export{qHe as CLAUDE_AGENT}`), so
    every export statement naming it is read.
    """
    statements = []
    first = _EXPORT_RE.search(src, close_i, close_i + 262_144)
    if first:
        statements.append(first.group(1))
    if len(ident) > 2:
        pattern = re.compile(
            r"export\{([^{}]*(?<![\w$])" + re.escape(ident) + r"(?![\w$])[^{}]*)\}"
        )
        statements.extend(m.group(1) for m in pattern.finditer(src))
    out: list[str] = []
    for statement in statements:
        for part in statement.split(","):
            local, _, exported = part.strip().partition(" as ")
            if local == ident and (exported or local) not in out:
                out.append(exported or local)
    return out


def _agent_roster(
    src: str, braces: BraceMap, refs: dict[str, str]
) -> tuple[dict[str, str], bool]:
    """Which built-in agents the default roster registers, and how.

    `refs` maps each identifier or export name an agent is reachable by to its
    agent name. The roster is the function whose array initializer holds a
    known agent and whose pushes add more: `let n=[GP];if(c)n.push(SL);...`.
    An agent in the initializer is `default`; one pushed is `conditional`
    (the push sits under a runtime condition). An agent loaded from another
    chunk is pushed through a destructured export (`{CLAUDE_AGENT:s}=...`).
    Returns (name -> status, roster found).
    """
    best: tuple[int, dict[str, str]] | None = None
    long_refs = {r: n for r, n in refs.items() if len(r) > 1}
    if not long_refs:
        return {}, False
    init_re = re.compile(r"(?<![\w$.])(" + _IDENT + r")=\[([^\[\]]*)\]")
    for m in init_re.finditer(src):
        elems = [e.strip() for e in m.group(2).split(",") if e.strip()]
        if not elems or not any(e in long_refs for e in elems):
            continue
        enc = braces.enclosing(m.start())
        if enc is None or enc[1] - enc[0] > 8_192:
            continue
        body = src[enc[0] : enc[1] + 1]
        status = {long_refs[e]: "default" for e in elems if e in long_refs}
        local = {
            d.group(2): long_refs[d.group(1)]
            for d in re.finditer(r"\{(" + _IDENT + r"):(" + _IDENT + r")\}", body)
            if d.group(1) in long_refs
        }
        push_re = re.compile(re.escape(m.group(1)) + r"\.push\(([^()]*)\)")
        for push in push_re.finditer(body):
            for arg in push.group(1).split(","):
                arg = arg.strip()
                name = local.get(arg) or long_refs.get(arg)
                if name:
                    status.setdefault(name, "conditional")
        if len(status) >= 2 and (best is None or len(status) > best[0]):
            best = (len(status), status)
    return (best[1], True) if best else ({}, False)


def extract_builtin_agents(
    src: str, braces: BraceMap
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Built-in subagent types, keyed by name, plus resolution notes.

    A definition is an object literal carrying `agentType` and
    `source:"built-in"`; its name is a literal or a constant resolved by the
    nearest-preceding rule. Fields are read from the literal itself, so the
    registration path (a roster function, a chunk export, a feature's own
    spawn) does not matter for finding it; the roster says which ones a
    default session registers.
    """
    notes: dict[str, Any] = {}
    found: list[tuple[int, dict[str, tuple[str, int]]]] = []
    opens: set[int] = set()
    for m in re.finditer(r"[{,]agentType:", src):
        enc = braces.enclosing(m.start() + 1)
        if enc is None or enc[0] in opens:
            continue
        fields = _object_fields(src, braces, enc[0], methods=True)
        # A definition carries its prompt or its routing text; a runtime
        # context object that merely copies `agentType` and `source` from a
        # definition carries neither.
        if "agentType" not in fields or not {"whenToUse", "getSystemPrompt"} & set(
            fields
        ):
            continue
        origin = resolve_field(src, braces, enc[0], "source")
        if not origin or origin["value"] != "built-in":
            continue
        opens.add(enc[0])
        found.append((enc[0], fields))

    exprs = [(o, f, _name_expr(src, f, "agentType")) for o, f in found]
    idents = {e[1] for *_, e in exprs if e[0] == "ident" and e[1]}
    name_index = build_const_index(src, idents, AGENT_NAME_RE)
    tools_index = build_const_index(src, None, TOOL_NAME_RE)

    out: dict[str, dict[str, Any]] = {}
    refs: dict[str, str] = {}
    unresolved: list[str] = []
    for open_i, fields, (kind, text) in exprs:
        if kind == "literal":
            name = text
        elif kind == "ident" and text:
            name = resolve_name_ident(text, open_i, name_index)
        else:
            name = None
        if not name or not re.fullmatch(AGENT_NAME_RE, name):
            unresolved.append(text or f"agentType at {open_i}")
            continue
        if name in out:
            out[name]["definitions"] += 1
            continue
        ident = _binding_ident(src, open_i)
        if ident:
            refs.setdefault(ident, name)
            for exported in _export_names(src, ident, braces.pairs[open_i]):
                refs.setdefault(exported, name)
        rec: dict[str, Any] = {"name": name, "source": "builtin-agent"}
        _apply_field(
            rec, "description", resolve_field(src, braces, open_i, "whenToUse")
        )
        rec["description"] = rec["description"] or ""
        for key, field_name in (
            ("tools", "tools"),
            ("disallowed_tools", "disallowedTools"),
        ):
            names, how = _tool_list(
                src, braces, open_i, fields, field_name, tools_index
            )
            rec[key], rec[f"{key}_source"] = names, how
        for key, field_name in (
            ("model", "model"),
            ("permission_mode", "permissionMode"),
        ):
            got = resolve_field(src, braces, open_i, field_name)
            rec[key] = (
                got["value"]
                if got and got["source"] in ("literal", "constant")
                else None
            )
        turns = fields.get("maxTurns")
        digits = re.match(r"\d+", src[turns[1] : turns[1] + 8]) if turns else None
        rec["max_turns"] = int(digits.group(0)) if digits else None
        rec["omit_claude_md"] = _literal_flag(src, fields, "omitClaudeMd", False)
        rec["definitions"] = 1
        out[name] = rec

    roster, roster_found = _agent_roster(src, braces, refs)
    for name, rec in out.items():
        status = roster.get(name, "absent")
        rec["roster"] = status
        rec["gated"] = status != "default"
        # Users reach a registered subagent by @-mention or --agent, the model
        # by the Agent tool's subagent_type; one outside the default roster is
        # registered only when a runtime feature adds it.
        who: bool | None = None if status == "absent" else True
        rec["user_invocable"] = who
        rec["model_invocable"] = who

    notes["definitions_seen"] = len(found)
    notes["resolved"] = len(found) - len(unresolved)
    notes["roster_found"] = roster_found
    notes["roster"] = {
        s: sorted(n for n, r in out.items() if r["roster"] == s)
        for s in ("default", "conditional", "absent")
    }
    if unresolved:
        notes["unresolved_names"] = sorted(set(unresolved))
    return out, notes


def extract_builtin_tools(
    src: str, braces: BraceMap
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Built-in tools, keyed by name, plus resolution notes.

    A tool definition is an object literal with top-level `name` and
    `maxResultSizeChars`, whether passed to the tool builder or assigned
    directly, so the builder's minified name is never needed. A name held in
    a function parameter (`name:e.name`, or a lone `e` with no binding in
    reach) is a factory that builds tools at runtime: counted in
    `factory_definitions`, never guessed. An `isMcp:!0` literal is the MCP
    tool template and is skipped.
    """
    notes: dict[str, Any] = {}
    found: list[tuple[int, dict[str, tuple[str, int]]]] = []
    opens: set[int] = set()
    templates = 0
    for m in re.finditer(r"[{,](?:get\s+)?maxResultSizeChars\b", src):
        enc = braces.enclosing(m.start() + 1)
        if enc is None or enc[0] in opens:
            continue
        opens.add(enc[0])
        fields = _object_fields(src, braces, enc[0], methods=True)
        if "maxResultSizeChars" not in fields or "name" not in fields:
            continue
        if _literal_flag(src, fields, "isMcp", False):
            templates += 1
            continue
        found.append((enc[0], fields))

    exprs = [(o, f, _name_expr(src, f, "name")) for o, f in found]
    index = build_const_index(src, None, TOOL_NAME_RE)
    out: dict[str, dict[str, Any]] = {}
    unresolved: list[str] = []
    factories = 0
    for open_i, fields, (kind, text) in exprs:
        name = None
        if kind == "literal":
            name = text
        elif kind == "ident" and text:
            name = resolve_tool_ident(text, open_i, index)
        if name is None and (
            kind == "member" or (kind == "ident" and len(text or "") == 1)
        ):
            factories += 1
            continue
        if not name or not re.fullmatch(TOOL_NAME_RE, name):
            unresolved.append(text or f"name at {open_i}")
            continue
        rec: dict[str, Any] = {"name": name, "source": "builtin-tool"}
        desc = resolve_field(src, braces, open_i, "description", methods=True)
        _apply_field(rec, "description", desc)
        rec["description"] = rec["description"] or ""
        hint = resolve_field(src, braces, open_i, "searchHint", methods=True)
        rec["search_hint"] = hint["value"] if hint else None
        ufn = resolve_field(src, braces, open_i, "userFacingName", methods=True)
        if ufn and ufn["value"] and ufn["value"] != name:
            rec["user_facing_name"] = ufn["value"]
        aliases = fields.get("aliases")
        rec["aliases"] = (
            _array_names(src, braces, aliases[1], index, open_i)[0]
            if aliases and aliases[0] == "value" and src.startswith("[", aliases[1])
            else []
        )
        rec["deferred"] = _literal_flag(src, fields, "shouldDefer", False)
        rec["always_load"] = _literal_flag(src, fields, "alwaysLoad", False)
        rec["flag_driven"] = [
            k for k in ("deferred", "always_load") if rec[k] is None
        ] or None
        if rec["flag_driven"] is None:
            del rec["flag_driven"]
        rec["gated"] = "isEnabled" in fields
        # A tool is called by the model; no user types one.
        rec["user_invocable"] = False
        rec["model_invocable"] = True
        prev = out.get(name)
        if prev is None:
            rec["definitions"] = 1
            out[name] = rec
        else:
            prev["definitions"] += 1
            if not prev["description"] and rec["description"]:
                rec["definitions"] = prev["definitions"]
                out[name] = rec

    notes["definitions_seen"] = len(found)
    notes["resolved"] = len(found) - len(unresolved) - factories
    if factories:
        notes["factory_definitions"] = factories
    if templates:
        notes["templates_skipped"] = templates
    if unresolved:
        notes["unresolved_names"] = sorted(set(unresolved))
    notes["description_unresolved"] = sum(
        1 for r in out.values() if r["description_source"] in ("unresolved", "absent")
    )
    return out, notes


def detect_cli_version(src: str) -> str | None:
    """Best-effort CLI version from the bundle.

    The build stamps its own version far more often than any dependency's, so
    the most frequent version-shaped literal is a reliable read without having
    to execute the binary.
    """
    counts: dict[str, int] = {}
    for m in re.finditer(r'"(\d+\.\d+\.\d+)"', src):
        counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    if not counts:
        return None
    best = max(counts.items(), key=lambda kv: kv[1])
    return best[0] if best[1] >= 20 else None


def _lane_status(problems: list[str], advisories: list[str]) -> str:
    return "broken" if problems else ("degraded" if advisories else "ok")


def check_integrity(
    src: str,
    commands: dict[str, Any],
    skills: dict[str, Any],
    skill_notes: dict[str, Any],
    plugin_backed: dict[str, str] | None = None,
    runs_below_floor: int = 0,
    workflows: dict[str, Any] | None = None,
    workflow_notes: dict[str, Any] | None = None,
    *,
    agents: dict[str, Any] | None = None,
    agent_notes: dict[str, Any] | None = None,
    tools: dict[str, Any] | None = None,
    tool_notes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Decide whether this extraction can be trusted, per lane, and say why.

    A drifted build usually degrades quietly: the script still returns rows,
    just fewer than exist. Every check here exists to convert that quiet
    shortfall into a stated one, so a downstream reader is never handed a
    confident short list.

    One rule for one state: each lane (`builtin_commands`, `bundled_skills`,
    `plugin_backed`) carries its own status, and the top-level status is the
    worst lane. `broken` at the top level means every lane is broken or the
    binary is unreadable; a run with at least one healthy lane is at most
    `degraded`, with each broken lane's problems restated as top-level
    advisories prefixed by the lane name, so the healthy lanes' counts stay
    reportable and the broken lane is named rather than hidden.
    """
    present = LANES + tuple(
        lane
        for lane, payload in (
            (WORKFLOW_LANE, workflows),
            (AGENT_LANE, agents),
            (TOOL_LANE, tools),
        )
        if payload is not None
    )
    lanes: dict[str, dict[str, Any]] = {
        lane: {"status": "ok", "problems": [], "advisories": []} for lane in present
    }
    top_advisories: list[str] = []

    version = detect_cli_version(src)
    if version is None:
        top_advisories.append(
            "could not read a CLI version from the bundle; drift against the last "
            f"validated build {VALIDATED_AGAINST} cannot be checked"
        )
    elif version != VALIDATED_AGAINST:
        top_advisories.append(
            f"cli {version} differs from the last validated build {VALIDATED_AGAINST}; "
            "counts are believed, not verified - re-run the skill's evals to revalidate"
        )

    builtin = lanes["builtin_commands"]
    missing = [c for c in CANARY_COMMANDS if c not in commands]
    if missing:
        builtin["problems"].append(
            f"canary commands absent: {', '.join(missing)} - extraction is broken, "
            "not merely drifted"
        )
    type_tokens = len(_TYPE_RE.findall(src))
    yield_ratio = (len(commands) / type_tokens) if type_tokens else 0.0
    if type_tokens and yield_ratio < MIN_COMMAND_YIELD:
        builtin["problems"].append(
            f"resolved {len(commands)} commands from {type_tokens} type tokens "
            f"({yield_ratio:.0%}); the brace reader is not resolving enclosing objects"
        )

    bundled = lanes["bundled_skills"]
    # Both export shapes: the CJS getter and the ESM export list. A
    # registrar-shaped name in either that this script does not know is the
    # signal of a registration path it is not reading.
    found_registrars = set(re.findall(r"\b(register[A-Za-z]*)\s*:\(\)=>", src))
    found_registrars |= set(
        re.findall(
            r"\b" + _IDENT + r" as (register[A-Za-z]*(?:Skill|Command|Agent))\b", src
        )
    )
    registrar_like = {
        r for r in found_registrars if re.search(r"(Skill|Command|Agent)", r)
    }
    unknown = sorted(registrar_like - KNOWN_REGISTRAR_EXPORTS)
    if unknown:
        bundled["advisories"].append(
            "unrecognized registrar-shaped exports: "
            + ", ".join(unknown)
            + " - a new registration path may exist and this run may under-report"
        )
    seen = skill_notes.get("registrations_seen")
    resolved = skill_notes.get("resolved")
    dynamic = skill_notes.get("dynamic_roster", 0)
    if isinstance(seen, int) and isinstance(resolved, int):
        gap = seen - resolved - (dynamic if isinstance(dynamic, int) else 0)
        if gap > 0:
            bundled["advisories"].append(
                f"{gap} bundled-skill registration(s) used a computed name and "
                "were not resolved; the bundled-skill list is a floor, not a total"
            )
    if isinstance(dynamic, int) and dynamic > 0:
        bundled["advisories"].append(
            f"{dynamic} registration(s) register a dynamic roster (a loop over a "
            "table); those names are not enumerable statically and the "
            "bundled-skill list is a floor, not a total"
        )
    if not skills:
        bundled["problems"].append(
            "no bundled skills resolved - the registrar lookup failed"
        )

    if runs_below_floor > 0:
        # A registration literal in a run under the floor was never read by
        # any lane. It is attributed to the bundled-skill lane, where the
        # small runs sit, so the roster is labeled a floor rather than a
        # total; the literal is generic, so the command lane may be short too.
        bundled["advisories"].append(
            f"{runs_below_floor} registration literal(s) sit in printable runs shorter "
            f"than the {MIN_RUN_BYTES}-byte floor and were not read; the bundled-skill "
            "list (and possibly the command list) is a floor, not a total"
        )

    backed = lanes["plugin_backed"]
    if plugin_backed is not None:
        missing_backed = [c for c in PLUGIN_BACKED_CANARY if c not in plugin_backed]
        if missing_backed:
            backed["problems"].append(
                f"canary plugin-backed built-in(s) absent: {', '.join(missing_backed)} - "
                "the pluginName scan resolved nothing it should have"
            )

    if workflows is not None:
        flow = lanes[WORKFLOW_LANE]
        wnotes = workflow_notes or {}
        if wnotes.get("error"):
            flow["problems"].append(wnotes["error"])
        missing_flows = [w for w in WORKFLOW_CANARY if w not in workflows]
        if missing_flows and not wnotes.get("error"):
            flow["problems"].append(
                f"canary bundled workflow(s) absent: {', '.join(missing_flows)} - the "
                "workflow scan resolved nothing it should have"
            )
        if wnotes.get("unresolved"):
            flow["advisories"].append(
                f"{len(wnotes['unresolved'])} bundled-workflow registration(s) did not "
                "resolve a name; the bundled-workflow list is a floor, not a total"
            )

    for lane, payload, lane_notes, canary, noun in (
        (AGENT_LANE, agents, agent_notes, AGENT_CANARY, "built-in agent"),
        (TOOL_LANE, tools, tool_notes, TOOL_CANARY, "built-in tool"),
    ):
        if payload is None:
            continue
        entry, lnotes = lanes[lane], lane_notes or {}
        if not payload:
            entry["problems"].append(
                f"no {noun} definition resolved - the {noun} scan found nothing"
            )
        else:
            missing_names = [c for c in canary if c not in payload]
            if missing_names:
                entry["problems"].append(
                    f"canary {noun}(s) absent: {', '.join(missing_names)} - the scan "
                    "resolved nothing it should have"
                )
        if lnotes.get("unresolved_names"):
            entry["advisories"].append(
                f"{len(lnotes['unresolved_names'])} {noun} definition(s) did not "
                f"resolve a name; the {noun} list is a floor, not a total"
            )
    if agents and not (agent_notes or {}).get("roster_found"):
        lanes[AGENT_LANE]["advisories"].append(
            "the default agent roster was not located; every agent reads roster "
            "`absent`, so which agents a default session registers is unknown"
        )

    problems: list[str] = []
    advisories: list[str] = list(top_advisories)
    for lane in present:
        lanes[lane]["status"] = _lane_status(
            lanes[lane]["problems"], lanes[lane]["advisories"]
        )
    all_broken = all(lanes[lane]["status"] == "broken" for lane in present)
    for lane in present:
        entry = lanes[lane]
        if entry["status"] == "broken" and all_broken:
            problems.extend(f"{lane}: {p}" for p in entry["problems"])
        elif entry["status"] == "broken":
            advisories.extend(
                f"{lane} lane broken: {p} (its counts are not reportable; the other "
                "lanes' counts stand)"
                for p in entry["problems"]
            )
        advisories.extend(f"{lane}: {a}" for a in entry["advisories"])

    status = "broken" if all_broken else ("degraded" if advisories else "ok")
    return {
        "status": status,
        "lanes": lanes,
        "cli_version": version,
        "validated_against": VALIDATED_AGAINST,
        "command_yield": round(yield_ratio, 3),
        "type_tokens": type_tokens,
        "registrars_seen": sorted(registrar_like),
        "registrar_route": skill_notes.get("registrar_route"),
        "problems": problems,
        "advisories": advisories,
    }


# --------------------------------------------------------------------------
# Disk inventory
# --------------------------------------------------------------------------


def config_dir() -> Path:
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(env) if env else Path.home() / ".claude"


def _load_json(path: Path) -> Any | None:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def scan_disk(root: Path) -> dict[str, Any]:
    """Enumerate installed plugins, their components, and config-scope surfaces."""
    out: dict[str, Any] = {"config_dir": str(root), "exists": root.is_dir()}

    settings = _load_json(root / "settings.json") or {}
    enabled = settings.get("enabledPlugins")
    if isinstance(enabled, dict):
        out["enabled_plugins"] = {
            "total_entries": len(enabled),
            "enabled": sorted(k for k, v in enabled.items() if v),
            "disabled": sorted(k for k, v in enabled.items() if not v),
        }
    else:
        out["enabled_plugins"] = {"total_entries": 0, "enabled": [], "disabled": []}
        out["enabled_plugins_note"] = "no enabledPlugins map in settings.json"

    known = _load_json(root / "plugins" / "known_marketplaces.json")
    if not isinstance(known, dict):
        known = {}
    marketplaces: dict[str, Any] = {}
    for name, entry in known.items():
        meta = entry or {}
        loc = meta.get("installLocation")
        marketplaces[name] = {
            "install_location": loc,
            "last_updated": meta.get("lastUpdated"),
            "plugins": scan_marketplace(Path(loc)) if loc else {},
        }
    out["marketplaces"] = marketplaces

    out["installed_plugins"] = scan_installed(root)
    out["config_scope_components"] = scan_config_scope(root)
    return out


def scan_installed(root: Path) -> dict[str, Any]:
    """Plugins actually installed under the config dir's plugin cache.

    A marketplace checkout is a catalog of what is *available*; this is what is
    present locally. The two can disagree - a plugin can be installed from a
    marketplace that is no longer cached - so neither substitutes for the other.
    """
    cache = root / "plugins" / "cache"
    out: dict[str, Any] = {}
    if not cache.is_dir():
        return out
    for marketplace in sorted(p for p in cache.iterdir() if p.is_dir()):
        plugins: dict[str, Any] = {}
        for entry in sorted(p for p in marketplace.iterdir() if p.is_dir()):
            # Installs may nest one version directory below the plugin name.
            candidate = entry
            if (
                not (entry / ".claude-plugin").is_dir()
                and not (entry / "skills").is_dir()
            ):
                subdirs = [d for d in sorted(entry.iterdir()) if d.is_dir()]
                if len(subdirs) == 1:
                    candidate = subdirs[0]
            plugins[entry.name] = scan_plugin(candidate)
        if plugins:
            out[marketplace.name] = plugins
    return out


def scan_marketplace(loc: Path) -> dict[str, Any]:
    """Every plugin a marketplace checkout offers, with its component counts."""
    found: dict[str, Any] = {}
    if not loc.is_dir():
        return found
    for parent in ("plugins", "external_plugins"):
        base = loc / parent
        if not base.is_dir():
            continue
        for entry in sorted(base.iterdir()):
            if entry.is_dir() and not entry.name.startswith("."):
                found[entry.name] = scan_plugin(entry) | {"catalog_section": parent}
    return found


def scan_plugin(root: Path) -> dict[str, Any]:
    """Component inventory for one plugin directory."""
    manifest = _load_json(root / ".claude-plugin" / "plugin.json") or {}
    info: dict[str, Any] = {
        "version": manifest.get("version"),
        "has_manifest": bool(manifest),
        "components": {},
    }
    if isinstance(manifest.get("dependencies"), list):
        info["dependencies"] = manifest["dependencies"]

    for comp, spec in PLUGIN_COMPONENTS.items():
        names = _scan_component(root, spec, manifest)
        if names:
            info["components"][comp] = names
    return info


def _manifest_paths(manifest: dict[str, Any], key: str) -> list[str] | None:
    """Component locations a manifest declares, or None if it declares none.

    A declared path *replaces* the default directory rather than adding to it,
    so scanning the default tree regardless would report components a plugin
    does not actually ship. Dotted keys address the `experimental` block.
    """
    if not key:
        return None
    node: Any = manifest
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    if isinstance(node, str):
        return [node]
    if isinstance(node, list):
        return [p for p in node if isinstance(p, str)]
    return None


def _scan_component(
    root: Path, spec: dict[str, str], manifest: dict[str, Any]
) -> list[str]:
    declared = _manifest_paths(manifest, spec.get("manifest", ""))
    kind = spec["kind"]

    if kind == "file":
        if declared:
            return [d for d in declared if (root / d).is_file()]
        target = root / spec["file"]
        return [spec["file"]] if target.is_file() else []

    targets = [root / d for d in declared] if declared else [root / spec["dir"]]

    out: list[str] = []
    for target in targets:
        # A declared entry may point at a single file rather than a directory.
        if target.is_file():
            out.append(target.name)
            continue
        if not target.is_dir():
            continue
        for entry in sorted(target.iterdir()):
            if kind == "dir-of-dirs":
                if entry.is_dir() and (entry / "SKILL.md").is_file():
                    out.append(entry.name)
            elif entry.is_file() and not entry.name.startswith("."):
                out.append(entry.name)
    return sorted(set(out))


def scan_config_scope(root: Path) -> dict[str, Any]:
    """Components installed directly in the config dir, outside any plugin."""
    out: dict[str, Any] = {}
    skills = root / "skills"
    if skills.is_dir():
        out["skills"] = sorted(
            e.name
            for e in skills.iterdir()
            if e.is_dir() and (e / "SKILL.md").is_file()
        )
    for name, sub in (("agents", "agents"), ("commands", "commands")):
        d = root / sub
        if d.is_dir():
            out[name] = sorted(e.name for e in d.iterdir() if e.is_file())
    settings = _load_json(root / "settings.json") or {}
    if isinstance(settings.get("hooks"), dict):
        out["hooks_events"] = sorted(settings["hooks"].keys())
    mcp = _load_json(root / ".mcp.json")
    if isinstance(mcp, dict) and isinstance(mcp.get("mcpServers"), dict):
        out["mcp_servers"] = sorted(mcp["mcpServers"].keys())
    return out


# --------------------------------------------------------------------------
# Assembly
# --------------------------------------------------------------------------


_BINARY_LANES = (
    ("builtin_commands", "command"),
    ("bundled_skills", "skill"),
    ("bundled_workflows", "workflow"),
    (AGENT_LANE, "agent"),
    (TOOL_LANE, "tool"),
)


def undetermined_fields(report: dict[str, Any]) -> dict[str, Any]:
    """Names whose invocability or text the bundle does not settle statically.

    Informational, not a lane problem: a runtime-decided field is a real
    property of the build, not an extraction failure.
    """
    out: dict[str, list[str]] = {
        "model_invocable_null": [],
        "user_invocable_null": [],
        "description_unresolved": [],
        "argument_hint_unresolved": [],
    }
    for lane, _ in _BINARY_LANES:
        for name, entry in (report.get(lane) or {}).items():
            for rec in registrations_of(entry):
                if rec.get("internal"):
                    continue
                if rec.get("model_invocable") is None:
                    out["model_invocable_null"].append(name)
                if rec.get("user_invocable") is None:
                    out["user_invocable_null"].append(name)
                if rec.get("description_source") == "unresolved":
                    out["description_unresolved"].append(name)
                if rec.get("argument_hint_source") == "unresolved":
                    out["argument_hint_unresolved"].append(name)
    return {k: {"count": len(v), "names": sorted(set(v))} for k, v in out.items()}


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    report: dict[str, Any] = {
        "schema": 1,
        "host": {
            "platform": platform.system(),
            "python": platform.python_version(),
        },
        "sources": {},
    }

    if not args.disk_only:
        binary, how = pick_binary(args.binary)
        if binary is None:
            report["sources"]["binary"] = {"available": False, "reason": how}
        else:
            src, meta = read_bundle(binary)
            meta["selected_by"] = how
            if src is None:
                report["sources"]["binary"] = {"available": False, **meta}
            else:
                braces = build_brace_map(src)
                meta["brace_pairs"] = len(braces.pairs)
                commands = extract_builtin_commands(src, braces)
                skills, skill_notes = extract_bundled_skills(src, braces)
                workflows, workflow_notes = extract_bundled_workflows(src, braces)
                agents, agent_notes = extract_builtin_agents(src, braces)
                tools, tool_notes = extract_builtin_tools(src, braces)
                plugin_backed = extract_plugin_backed(src)

                for name, plugin in plugin_backed.items():
                    if name in commands:
                        commands[name]["plugin_name"] = plugin
                        commands[name]["source"] = "plugin-backed-builtin"
                    elif name in skills:
                        for registration in registrations_of(skills[name]):
                            registration["plugin_name"] = plugin
                            registration["source"] = "plugin-backed-builtin"

                # A name registered as a bundled skill is a skill, not a command.
                for name in list(commands):
                    if name in skills:
                        del commands[name]

                report["sources"]["binary"] = {"available": True, **meta}
                report["builtin_commands"] = commands
                report["bundled_skills"] = skills
                report["bundled_skill_notes"] = skill_notes
                report["bundled_workflows"] = workflows
                report["bundled_workflow_notes"] = workflow_notes
                report[AGENT_LANE] = agents
                report["builtin_agent_notes"] = agent_notes
                report[TOOL_LANE] = tools
                report["builtin_tool_notes"] = tool_notes
                report["plugin_backed"] = plugin_backed
                report["integrity"] = check_integrity(
                    src,
                    commands,
                    skills,
                    skill_notes,
                    plugin_backed,
                    int(meta.get("runs_below_floor", 0) or 0),
                    workflows,
                    workflow_notes,
                    agents=agents,
                    agent_notes=agent_notes,
                    tools=tools,
                    tool_notes=tool_notes,
                )
                report["integrity"]["undetermined"] = undetermined_fields(report)

    if getattr(args, "docs", False):
        report["docs_crosscheck"] = build_crosscheck(
            report,
            docs_file=args.docs_file,
            changelog_file=args.changelog_file,
            tools_file=getattr(args, "tools_docs_file", None),
        )

    if not args.binary_only:
        report["sources"]["disk"] = {"available": True}
        report["disk"] = scan_disk(
            Path(args.config_dir) if args.config_dir else config_dir()
        )

        # Project scope is a third place components come from, and it is the one
        # that changes as you move between repos: a project's .claude tree adds
        # skills, agents, and hooks that no machine-scope scan would ever see.
        project_root = Path(args.project_dir) if args.project_dir else Path.cwd()
        project_claude = project_root / ".claude"
        report["project"] = {
            "root": str(project_root),
            "present": project_claude.is_dir(),
            "components": scan_config_scope(project_claude)
            if project_claude.is_dir()
            else {},
        }

    return report


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(
            f"python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required, running "
            f"{platform.python_version()}",
            file=sys.stderr,
        )
        return 2

    ap = argparse.ArgumentParser(
        description="Enumerate the Claude Code ecosystem on this machine (read-only)."
    )
    ap.add_argument(
        "--binary", help="path to the claude executable (default: auto-detect)"
    )
    ap.add_argument(
        "--config-dir", help="config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)"
    )
    ap.add_argument(
        "--project-dir", help="project root whose .claude tree to scan (default: cwd)"
    )
    ap.add_argument("--binary-only", action="store_true", help="skip the disk scan")
    ap.add_argument("--disk-only", action="store_true", help="skip reading the binary")
    ap.add_argument("--out", help="write JSON here instead of stdout")
    ap.add_argument(
        "--docs",
        action="store_true",
        help="cross-check the built-in surface against the live commands page and "
        "changelog (network; a fetch failure degrades the docs_crosscheck block only)",
    )
    ap.add_argument(
        "--docs-file", help="read the commands page from this file (implies --docs)"
    )
    ap.add_argument(
        "--changelog-file", help="read the changelog from this file (implies --docs)"
    )
    ap.add_argument(
        "--tools-docs-file",
        help="read the tools reference from this file (implies --docs)",
    )
    ap.add_argument(
        "--self-check",
        action="store_true",
        help="print only the integrity verdict; exit 0 ok, 1 broken, 3 degraded "
        "(2 stays argparse's usage error). For CI and scheduled drift checks.",
    )
    args = ap.parse_args(argv)

    if args.binary_only and args.disk_only:
        print("--binary-only and --disk-only are mutually exclusive", file=sys.stderr)
        return 2

    args.docs = bool(
        args.docs or args.docs_file or args.changelog_file or args.tools_docs_file
    )
    if args.self_check:
        args.disk_only = False
        args.binary_only = True
        args.docs = False

    report = build_report(args)

    if args.self_check:
        integrity = report.get("integrity")
        if integrity is None:
            binsrc = report.get("sources", {}).get("binary", {})
            reason = (
                binsrc.get("error")
                or binsrc.get("reason")
                or "binary source unavailable"
            )
            print(f"BROKEN: {reason}")
            return 1
        print(
            f"{integrity['status'].upper()}: cli {integrity['cli_version']}, "
            f"validated against {integrity['validated_against']}"
        )
        for lane, entry in (integrity.get("lanes") or {}).items():
            print(f"  lane {lane}: {entry['status']}")
        for p in integrity["problems"]:
            print(f"  problem:  {p}")
        for a in integrity["advisories"]:
            print(f"  advisory: {a}")
        return {"ok": 0, "broken": 1, "degraded": 3}[integrity["status"]]

    text = json.dumps(report, indent=1, sort_keys=True)
    if args.out:
        try:
            Path(args.out).write_text(text, encoding="utf-8")
        except OSError as exc:
            print(f"error: cannot write --out {args.out}: {exc}", file=sys.stderr)
            return 2
        print(f"wrote {args.out}", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
