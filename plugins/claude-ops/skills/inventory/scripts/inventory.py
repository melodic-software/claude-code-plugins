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
import json
import os
import platform
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

MIN_PYTHON = (3, 11)

# The CLI release this extractor was last verified against by a human running
# the skill's evals. Drift from it is not an error - the extraction is designed
# to survive ordinary releases - but it downgrades every count from "verified"
# to "believed", which the report has to say out loud.
VALIDATED_AGAINST = "2.1.228"

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
    }
)

# Below this ratio of extracted commands to `type:"local…"` tokens present, the
# brace reader is failing to resolve enclosing objects and the list is partial.
MIN_COMMAND_YIELD = 0.40

# The bundle is minified JS. These markers sit at the top of the embedded CLI
# chunk and are stable across the releases observed so far; each is tried in
# turn so one rename does not break discovery.
BUNDLE_MARKERS = (b"// @bun @bytecode @bun-cjs", b"// @bun @bun-cjs", b"// @bun")

# Component types a plugin may ship, from the plugin manifest schema and the
# standard plugin layout. Directory is the default location; the manifest may
# redirect most of them, which is why the manifest is read before the tree.
PLUGIN_COMPONENTS: dict[str, dict[str, str]] = {
    "skills": {"dir": "skills", "manifest": "skills", "kind": "dir-of-dirs"},
    "commands": {"dir": "commands", "manifest": "commands", "kind": "dir-of-files"},
    "agents": {"dir": "agents", "manifest": "agents", "kind": "dir-of-files"},
    "workflows": {"dir": "workflows", "manifest": "workflows", "kind": "dir-of-files"},
    "output-styles": {"dir": "output-styles", "manifest": "outputStyles", "kind": "dir-of-files"},
    "themes": {"dir": "themes", "manifest": "experimental.themes", "kind": "dir-of-files"},
    "monitors": {"dir": "monitors", "manifest": "experimental.monitors", "kind": "dir-of-files"},
    "hooks": {"dir": "hooks", "manifest": "hooks", "kind": "dir-of-files"},
    "bin": {"dir": "bin", "manifest": "", "kind": "dir-of-files"},
    "mcp-servers": {"dir": "", "manifest": "mcpServers", "kind": "file", "file": ".mcp.json"},
    "lsp-servers": {"dir": "", "manifest": "lspServers", "kind": "file", "file": ".lsp.json"},
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

    for p in candidate_binaries():
        try:
            if not p.is_file():
                continue
            size = p.stat().st_size
        except OSError:
            continue
        if size > 20_000_000:
            return p, "auto-detected native build"
        # Keep looking; a shim may precede the real binary on PATH.
    for p in candidate_binaries():
        try:
            if p.is_file():
                return p, "auto-detected (small file - likely an npm launcher, not a native build)"
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
    if data[:4] in (b"\x7fELF",):
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
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "case", "do", "else", "yield", "await",
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
    window around a match routinely spans two neighbouring objects and mixes
    their fields. Tracking real brace depth is what keeps each command's fields
    attributed to that command.
    """
    stack: list[int] = []
    pairs: dict[int, int] = {}
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
            i = _skip_template(s, i, n)
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


def _skip_template(s: str, i: int, n: int) -> int:
    i += 1
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "`":
            return i + 1
        if s[i] == "$" and i + 1 < n and s[i + 1] == "{":
            depth = 1
            i += 2
            while i < n and depth:
                if s[i] in "\"'`":
                    q = s[i]
                    i += 1
                    while i < n:
                        if s[i] == "\\":
                            i += 2
                            continue
                        if s[i] == q:
                            i += 1
                            break
                        i += 1
                    continue
                if s[i] == "{":
                    depth += 1
                elif s[i] == "}":
                    depth -= 1
                i += 1
            continue
        i += 1
    return i


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
# Extracting the registries
# --------------------------------------------------------------------------

_TYPE_RE = re.compile(r'type:"(local|local-jsx|prompt)"')
_NAME_RE = re.compile(r'(?:^|[,{])name:' + _STR)
_UFN_RE = re.compile(r"userFacingName\(\)\{return" + _STR)
_DESC_RE = re.compile(r'(?:^|[,{])description:' + _STR)
_MENUDESC_RE = re.compile(r"(?:menuDescription|description):" + _STR)
_ALIAS_RE = re.compile(r"aliases:\[([^\]]*)\]")
_NAME_OK = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9:_-]{0,40}")

# Names that exist in the build but are never typed by a user.
INTERNAL_NAMES = {"mcp__", "workflow-launch-exec", "pro-trial-expired", "rate-limit-options", "stub"}


def extract_builtin_commands(src: str, braces: BraceMap) -> dict[str, dict[str, Any]]:
    """Built-in CLI commands, keyed by name.

    Each command is a small object literal carrying `type` and `name`. The
    enclosing object is resolved by brace depth, then its own fields are read,
    so an adjacent command's description cannot bleed in.
    """
    out: dict[str, dict[str, Any]] = {}
    for m in _TYPE_RE.finditer(src):
        enc = braces.enclosing(m.start())
        if not enc:
            continue
        open_i, close_i = enc
        if close_i - open_i > 4000:
            # Too large to be a command literal - this is some enclosing scope.
            continue
        body = src[open_i : close_i + 1]
        nm = _NAME_RE.search(body) or _UFN_RE.search(body)
        if not nm:
            continue
        name = _unescape(nm.group(1))
        if not _NAME_OK.fullmatch(name or ""):
            continue
        desc = _DESC_RE.search(body)
        aliases = _read_aliases(body)
        rec = {
            "name": name,
            "source": "builtin",
            "type": m.group(1),
            "description": _unescape(desc.group(1)) if desc else "",
            "aliases": aliases,
            "hidden": "isHidden" in body,
            "gated": "isEnabled" in body,
            "internal": name in INTERNAL_NAMES,
        }
        prev = out.get(name)
        if prev is None or (not prev["description"] and rec["description"]):
            if prev is not None:
                rec["aliases"] = sorted(set(prev["aliases"]) | set(aliases))
            out[name] = rec
        elif aliases:
            prev["aliases"] = sorted(set(prev["aliases"]) | set(aliases))
    return out


def _read_aliases(body: str) -> list[str]:
    m = _ALIAS_RE.search(body)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


def discover_registrar(src: str, export_name: str) -> str | None:
    """Resolve a minified registrar function via its readable export name.

    Minified identifiers are regenerated every release, so hardcoding one dates
    the script immediately. The bundle's export maps keep the original names
    (`registerBundledSkill:()=>xu`), which makes them a stable way in.
    """
    m = re.search(re.escape(export_name) + r":\(\)=>([A-Za-z_$][A-Za-z0-9_$]*)", src)
    return m.group(1) if m else None


def build_const_map(src: str) -> dict[str, str]:
    """Map single-valued identifiers to their kebab-case string literal.

    Several bundled skills are registered as `xu({name:gme,...})` where `gme`
    is a hoisted constant, so a literal-only scan silently misses them.
    """
    seen: dict[str, set[str]] = {}
    for m in re.finditer(
        r'\b([A-Za-z_$][A-Za-z0-9_$]{0,8})\s*=\s*"([a-z][a-z0-9]*(?:-[a-z0-9]+)*)"', src
    ):
        seen.setdefault(m.group(1), set()).add(m.group(2))
    return {k: next(iter(v)) for k, v in seen.items() if len(v) == 1}


def extract_bundled_skills(src: str) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Bundled skills, keyed by name, plus notes about resolution."""
    notes: dict[str, Any] = {}
    fn = discover_registrar(src, "registerBundledSkill")
    notes["registrar"] = fn
    if not fn:
        notes["error"] = "registerBundledSkill export not found - build layout changed"
        return {}, notes

    consts = build_const_map(src)
    out: dict[str, dict[str, Any]] = {}
    unresolved: list[str] = []

    for m in re.finditer(re.escape(fn) + r"\(\{", src):
        window = src[m.start() : m.start() + 4000]
        nm = re.search(r"name:(?:" + _STR + r"|([A-Za-z_$][A-Za-z0-9_$]{0,8}))", window)
        if not nm:
            continue
        if nm.group(1) is not None:
            name = _unescape(nm.group(1))
        else:
            ident = nm.group(2)
            if ident not in consts:
                unresolved.append(ident)
                continue
            name = consts[ident]
        desc = _MENUDESC_RE.search(window)
        out[name] = {
            "name": name,
            "source": "bundled-skill",
            "description": _unescape(desc.group(1)) if desc else "",
            "aliases": _read_aliases(window[:1500]),
            "gated": "isEnabled" in window[:1500],
            "hidden": "isHidden" in window[:1500],
        }

    notes["registrations_seen"] = len(re.findall(re.escape(fn) + r"\(\{", src))
    notes["resolved"] = len(out)
    if unresolved:
        notes["unresolved_dynamic_names"] = sorted(set(unresolved))
    return out, notes


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


def check_integrity(
    src: str,
    commands: dict[str, Any],
    skills: dict[str, Any],
    skill_notes: dict[str, Any],
) -> dict[str, Any]:
    """Decide whether this extraction can be trusted, and say why.

    A drifted build usually degrades quietly: the script still returns rows,
    just fewer than exist. Every check here exists to convert that quiet
    shortfall into a stated one, so a downstream reader is never handed a
    confident short list.
    """
    problems: list[str] = []
    advisories: list[str] = []

    version = detect_cli_version(src)
    if version and version != VALIDATED_AGAINST:
        advisories.append(
            f"cli {version} differs from the last validated build {VALIDATED_AGAINST}; "
            "counts are believed, not verified - re-run the skill's evals to revalidate"
        )

    missing = [c for c in CANARY_COMMANDS if c not in commands]
    if missing:
        problems.append(
            f"canary commands absent: {', '.join(missing)} - extraction is broken, "
            "not merely drifted"
        )

    type_tokens = len(_TYPE_RE.findall(src))
    yield_ratio = (len(commands) / type_tokens) if type_tokens else 0.0
    if type_tokens and yield_ratio < MIN_COMMAND_YIELD:
        problems.append(
            f"resolved {len(commands)} commands from {type_tokens} type tokens "
            f"({yield_ratio:.0%}); the brace reader is not resolving enclosing objects"
        )

    found_registrars = set(re.findall(r"\b(register[A-Za-z]*)\s*:\(\)=>", src))
    registrar_like = {
        r for r in found_registrars if re.search(r"(Skill|Command|Agent)", r)
    }
    unknown = sorted(registrar_like - KNOWN_REGISTRAR_EXPORTS)
    if unknown:
        advisories.append(
            "unrecognised registrar-shaped exports: "
            + ", ".join(unknown)
            + " - a new registration path may exist and this run may under-report"
        )

    seen = skill_notes.get("registrations_seen")
    resolved = skill_notes.get("resolved")
    if isinstance(seen, int) and isinstance(resolved, int) and seen > resolved:
        advisories.append(
            f"{seen - resolved} bundled-skill registration(s) used a computed name and "
            "were not resolved; the bundled-skill list is a floor, not a total"
        )

    if not skills:
        problems.append("no bundled skills resolved - the registrar lookup failed")

    status = "broken" if problems else ("degraded" if advisories else "ok")
    return {
        "status": status,
        "cli_version": version,
        "validated_against": VALIDATED_AGAINST,
        "command_yield": round(yield_ratio, 3),
        "type_tokens": type_tokens,
        "registrars_seen": sorted(registrar_like),
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

    known = _load_json(root / "plugins" / "known_marketplaces.json") or {}
    marketplaces: dict[str, Any] = {}
    for name, meta in known.items() if isinstance(known, dict) else []:
        loc = (meta or {}).get("installLocation")
        marketplaces[name] = {
            "install_location": loc,
            "last_updated": (meta or {}).get("lastUpdated"),
            "plugins": scan_marketplace(Path(loc)) if loc else {},
        }
    out["marketplaces"] = marketplaces

    out["config_scope_components"] = scan_config_scope(root)
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
        names = _scan_component(root, spec)
        if names:
            info["components"][comp] = names
    return info


def _scan_component(root: Path, spec: dict[str, str]) -> list[str]:
    kind = spec["kind"]
    if kind == "file":
        target = root / spec["file"]
        return [spec["file"]] if target.is_file() else []

    directory = root / spec["dir"]
    if not directory.is_dir():
        return []
    out: list[str] = []
    if kind == "dir-of-dirs":
        for entry in sorted(directory.iterdir()):
            if entry.is_dir() and (entry / "SKILL.md").is_file():
                out.append(entry.name)
    else:
        for entry in sorted(directory.iterdir()):
            if entry.is_file() and not entry.name.startswith("."):
                out.append(entry.name)
    return out


def scan_config_scope(root: Path) -> dict[str, Any]:
    """Components installed directly in the config dir, outside any plugin."""
    out: dict[str, Any] = {}
    skills = root / "skills"
    if skills.is_dir():
        out["skills"] = sorted(
            e.name for e in skills.iterdir() if e.is_dir() and (e / "SKILL.md").is_file()
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
                skills, skill_notes = extract_bundled_skills(src)
                plugin_backed = extract_plugin_backed(src)

                for name, plugin in plugin_backed.items():
                    if name in commands:
                        commands[name]["plugin_name"] = plugin
                        commands[name]["source"] = "plugin-backed-builtin"
                    elif name in skills:
                        skills[name]["plugin_name"] = plugin
                        skills[name]["source"] = "plugin-backed-builtin"

                # A name registered as a bundled skill is a skill, not a command.
                for name in list(commands):
                    if name in skills:
                        del commands[name]

                report["sources"]["binary"] = {"available": True, **meta}
                report["builtin_commands"] = commands
                report["bundled_skills"] = skills
                report["bundled_skill_notes"] = skill_notes
                report["plugin_backed"] = plugin_backed
                report["integrity"] = check_integrity(src, commands, skills, skill_notes)

    if not args.binary_only:
        report["sources"]["disk"] = {"available": True}
        report["disk"] = scan_disk(Path(args.config_dir) if args.config_dir else config_dir())

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
    ap.add_argument("--binary", help="path to the claude executable (default: auto-detect)")
    ap.add_argument("--config-dir", help="config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)")
    ap.add_argument("--binary-only", action="store_true", help="skip the disk scan")
    ap.add_argument("--disk-only", action="store_true", help="skip reading the binary")
    ap.add_argument("--out", help="write JSON here instead of stdout")
    ap.add_argument(
        "--self-check",
        action="store_true",
        help="print only the integrity verdict; exit 1 if extraction is broken, "
        "2 if it is degraded. For CI and scheduled drift checks.",
    )
    args = ap.parse_args(argv)

    if args.binary_only and args.disk_only:
        print("--binary-only and --disk-only are mutually exclusive", file=sys.stderr)
        return 2

    if args.self_check:
        args.disk_only = False
        args.binary_only = True

    report = build_report(args)

    if args.self_check:
        integrity = report.get("integrity")
        if integrity is None:
            reason = report.get("sources", {}).get("binary", {}).get(
                "error", "binary source unavailable"
            )
            print(f"BROKEN: {reason}")
            return 1
        print(f"{integrity['status'].upper()}: cli {integrity['cli_version']}, "
              f"validated against {integrity['validated_against']}")
        for p in integrity["problems"]:
            print(f"  problem:  {p}")
        for a in integrity["advisories"]:
            print(f"  advisory: {a}")
        return {"ok": 0, "broken": 1, "degraded": 2}[integrity["status"]]

    text = json.dumps(report, indent=1, sort_keys=True)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out}", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
