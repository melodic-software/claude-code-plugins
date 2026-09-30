"""Classify the extracted built-in surface against the official command docs.

A separate lane from the binary extraction: the binary says what exists, the
docs say what is documented, and this module only compares the two. It never
adds a name to or removes one from a binary lane, and a fetch failure degrades
only its own block.

Python 3.11+, standard library only.
"""

from __future__ import annotations

import http.client
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

from registrations import registrations_of  # noqa: E402  (path set above)

COMMANDS_URL = "https://code.claude.com/docs/en/commands.md"
CHANGELOG_URL = (
    "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
)

STATUSES = (
    "documented",
    "undocumented",
    "alias",
    "docs_alias_but_registered",
    "removed_in_docs",
    "removed_in_docs_but_registered",
    "docs_only",
)

_SECTION = "## All commands"
# Only a table row's first cell is a regex (here and in _TOOL_ROW_RE); the rest
# is split with string methods, because a lazy `.*?` cell between `\s*` runs
# backtracks super-linearly on a long whitespace run.
_ROW_RE = re.compile(r"\|\s*`/(?P<name>[a-z0-9][a-z0-9:_-]*)(?P<args>[^`]*)`\s*\|")
_KIND_RE = re.compile(r"^\*\*\[?(Skill|Workflow)\]?(?:\([^)]*\))?\.?\*\*\.?\s*")
_ALIAS_OF_RE = re.compile(r"^Alias (?:for|of) \[?`/([a-z0-9:_-]+)")
_TOKENS = r"((?:`/[a-z0-9:_-]+`(?:,\s*|\s+and\s+|,\s*and\s+)?)+)"
_ALIAS_LIST_RE = re.compile(r"\bAlias(?:es)?:\s*" + _TOKENS)
_ARE_ALIASES_RE = re.compile(_TOKENS + r"\s+are aliases\b")
_IS_ALIAS_RE = re.compile(r"`/([a-z0-9:_-]+)` is an alias\b")
_REMOVED_RE = re.compile(r"^Removed(?: in v?(\d+\.\d+\.\d+))?\b")
_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")

TOOLS_URL = "https://code.claude.com/docs/en/tools-reference.md"
TOOL_STATUSES = ("documented", "alias", "undocumented", "docs_only")
_TOOL_HEADER_RE = re.compile(r"^\|\s*Tool\s*\|\s*Description\s*\|")
_TOOL_ROW_RE = re.compile(r"\|\s*`(?P<name>[A-Za-z][A-Za-z0-9_]*)`\s*\|")

_VERSION_RE = re.compile(r"^##\s+\[?v?(\d+\.\d+\.\d+)")
_EVENT_WORDS = (
    ("added", re.compile(r"\b(?:added|adds|introduc(?:ed|es))\b", re.I)),
    ("renamed", re.compile(r"\brenam(?:ed|es)\b", re.I)),
    ("removed", re.compile(r"\bremov(?:ed|es)\b", re.I)),
    ("deprecated", re.compile(r"\bdeprecat(?:ed|es|ion)\b", re.I)),
    ("alias", re.compile(r"\balias(?:es|ed)?\b", re.I)),
)
_EVENT_TEXT_MAX = 240
# Bounds on untrusted fetched text. _ROW_MAX is the longest table line parsed; a
# longer one is skipped. It caps how much text each row's parsing scans; it does
# not bound backtracking within that text, which is why the row parsers use no
# backtracking cell pattern. The fetch has no other size limit.
_ROW_MAX = 8_000
_FETCH_MAX = 16_000_000


def fetch_text(url: str, timeout: float = 20.0) -> tuple[str | None, str | None]:
    """The body at `url`, or None and the reason. Never raises."""
    req = urllib.request.Request(url, headers={"User-Agent": "claude-ops-inventory"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read(_FETCH_MAX + 1)
            if len(body) > _FETCH_MAX:
                return None, f"response exceeds {_FETCH_MAX} bytes"
            return body.decode("utf-8", "replace"), None
    except (
        urllib.error.URLError,
        http.client.HTTPException,
        TimeoutError,
        OSError,
        ValueError,
    ) as exc:
        return None, f"{type(exc).__name__}: {exc}"


def _read_source(
    file: str | None, url: str
) -> tuple[str | None, str | None, dict[str, Any]]:
    """Text from `file` when given, else fetched from `url`: (text, error, source)."""
    if file:
        try:
            return Path(file).read_text(encoding="utf-8"), None, {"file": file}
        except OSError as exc:
            return None, f"{type(exc).__name__}: {exc}", {"file": file}
    text, err = fetch_text(url)
    return text, err, {"url": url}


def _row_rest(pattern: re.Pattern[str], line: str) -> tuple[re.Match[str], str] | None:
    """The first-cell match and the text between it and the row's closing pipe,
    or None when `line` is not such a row."""
    m = pattern.match(line)
    rest = line[m.end() :].rstrip() if m else ""
    return (m, rest[:-1]) if m and rest.endswith("|") else None


def parse_tools_table(text: str) -> dict[str, dict[str, Any]]:
    """Rows of the tools reference's table (`| Tool | Description | Permission
    required |`), keyed by tool name. Stops where the table ends."""
    rows: dict[str, dict[str, Any]] = {}
    in_table = False
    for line in text.splitlines():
        if len(line) > _ROW_MAX:
            continue
        if not in_table:
            in_table = bool(_TOOL_HEADER_RE.match(line))
            continue
        if not line.startswith("|"):
            if rows:
                break
            continue
        row = _row_rest(_TOOL_ROW_RE, line)
        if row and "|" in row[1]:
            m, rest = row
            text, _, perm = rest.rpartition("|")
            rows[m.group("name")] = {
                "summary": _LINK_RE.sub(r"\1", text.strip())[:_EVENT_TEXT_MAX],
                "permission_required": perm.strip(),
            }
    return rows


def build_tools_crosscheck(
    report: dict[str, Any], tools_file: str | None = None
) -> dict[str, Any]:
    """The `docs_crosscheck.tools` block: the `builtin_tools` lane against the
    tools reference table. Its own status; it never changes the parent's."""
    block: dict[str, Any] = {
        "status": "ok",
        "problems": [],
        "advisories": [],
        "statuses": list(TOOL_STATUSES),
    }
    tools = report.get("builtin_tools")
    if not isinstance(tools, dict):
        block["status"] = "unavailable"
        block["problems"].append("no builtin_tools lane was extracted")
        return block
    text, err, block["source"] = _read_source(tools_file, TOOLS_URL)
    if text is None:
        block["status"] = "unavailable"
        block["problems"].append(f"tools reference unavailable: {err}")
        return block
    rows = parse_tools_table(text)
    block["source"]["rows"] = len(rows)
    if not rows:
        block["status"] = "broken"
        block["problems"].append(
            "no rows parsed from the tools table - the tools reference layout changed"
        )
        return block
    alias_of = {
        alias: name
        for name, rec in tools.items()
        for alias in (rec.get("aliases") or [])
    }
    names: dict[str, dict[str, Any]] = {}
    for name in tools:
        names[name] = {
            "status": "documented" if name in rows else "undocumented",
            "docs_summary": rows.get(name, {}).get("summary"),
        }
    for name, row in rows.items():
        if name in names:
            continue
        names[name] = {
            "status": "alias" if name in alias_of else "docs_only",
            "binary_alias_of": alias_of.get(name),
            "docs_summary": row["summary"],
        }
    block["counts"] = {
        s: sum(1 for e in names.values() if e["status"] == s) for s in TOOL_STATUSES
    }
    block["names"] = names
    lane = ((report.get("integrity") or {}).get("lanes") or {}).get("builtin_tools")
    if lane and lane.get("status") != "ok":
        block["advisories"].append(
            "the builtin_tools lane is not ok - an undocumented or docs_only status "
            "may reflect extraction, not the product"
        )
        block["status"] = "degraded"
    return block


def _slashes(tokens: str) -> list[str]:
    return re.findall(r"`/([a-z0-9:_-]+)`", tokens)


def parse_commands_table(text: str) -> dict[str, dict[str, Any]]:
    """Rows of the commands page's "All commands" table, keyed by name.

    Each row records its argument synopsis, kind (command, skill, workflow),
    whether the row itself is an alias (and of what), the aliases it declares,
    and whether it is marked removed. "Removed" counts only at the start of
    the row text: a row that says skills were "added or removed" is not.
    """
    start = text.find(_SECTION)
    if start < 0:
        return {}
    end = text.find("\n## ", start + len(_SECTION))
    rows: dict[str, dict[str, Any]] = {}
    for line in text[start : end if end > 0 else len(text)].splitlines():
        if len(line) > _ROW_MAX:
            continue
        parsed = _row_rest(_ROW_RE, line)
        if not parsed:
            continue
        m, rest = parsed
        name = m.group("name")
        body = rest.strip().replace("\\|", "|")
        kind_m = _KIND_RE.match(body)
        kind = kind_m.group(1).lower() if kind_m else "command"
        body = body[kind_m.end() :] if kind_m else body
        row: dict[str, Any] = {
            "args": m.group("args").replace("\\|", "|").strip() or None,
            "kind": kind,
            "alias_of": None,
            "is_alias": False,
            "aliases": [],
            "removed": False,
            "removed_version": None,
            "summary": _LINK_RE.sub(r"\1", body).split(". ")[0].strip()[:300],
        }
        alias_of = _ALIAS_OF_RE.match(body)
        if alias_of:
            row["is_alias"], row["alias_of"] = True, alias_of.group(1)
        removed = _REMOVED_RE.match(body)
        if removed:
            row["removed"], row["removed_version"] = True, removed.group(1)
        declared: list[str] = []
        for pattern in (_ALIAS_LIST_RE, _ARE_ALIASES_RE):
            for hit in pattern.finditer(body):
                declared += _slashes(hit.group(1))
        for hit in _IS_ALIAS_RE.finditer(body):
            if hit.group(1) == name:
                row["is_alias"] = True
            else:
                declared.append(hit.group(1))
        row["aliases"] = sorted(set(declared) - {name})
        rows[name] = row
    return rows


def _vkey(version: str) -> tuple[int, ...]:
    return tuple(int(p) for p in version.split("."))


def parse_changelog(text: str, names: set[str]) -> dict[str, dict[str, Any]]:
    """Per name: the earliest version whose entry mentions `/name`, and the
    lines that also use an add, rename, remove, deprecate, or alias word.

    A heuristic: a mention is not proof of introduction, and a word match is
    not proof the line is about that change.
    """
    if not names:
        return {}
    token = re.compile(
        r"(?<![\w/.~:-])/("
        + "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
        + r")(?![\w/-])"
    )
    out: dict[str, dict[str, Any]] = {}
    version: str | None = None
    for line in text.splitlines():
        v = _VERSION_RE.match(line)
        if v:
            version = v.group(1)
            continue
        if version is None:
            continue
        hits = set(token.findall(line))
        if not hits:
            continue
        kinds = [k for k, rx in _EVENT_WORDS if rx.search(line)]
        for name in hits:
            entry = out.setdefault(
                name, {"first_mentioned": version, "mentions": 0, "events": []}
            )
            entry["mentions"] += 1
            if _vkey(version) < _vkey(entry["first_mentioned"]):
                entry["first_mentioned"] = version
            if kinds:
                entry["events"].append(
                    {
                        "version": version,
                        "kinds": kinds,
                        "text": line.strip().lstrip("-* ").strip()[:_EVENT_TEXT_MAX],
                    }
                )
    for entry in out.values():
        entry["events"].sort(key=lambda e: _vkey(e["version"]))
    return out


def _binary_index(
    report: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, str]]:
    """Registered names with their lane facts, and each binary alias's owner."""
    names: dict[str, dict[str, Any]] = {}
    alias_owner: dict[str, str] = {}
    lanes = (
        ("builtin_commands", "command"),
        ("bundled_skills", "skill"),
        ("bundled_workflows", "workflow"),
    )
    for lane, kind in lanes:
        for name, entry in (report.get(lane) or {}).items():
            regs = registrations_of(entry)
            if not regs:
                continue
            aliases = sorted({a for r in regs for a in r.get("aliases") or []})
            names[name] = {
                "kind": kind,
                "aliases": aliases,
                "internal": all(r.get("internal") for r in regs),
                "hidden": any(r.get("hidden") for r in regs),
                "user_invocable": regs[0].get("user_invocable"),
                "model_invocable": regs[0].get("model_invocable"),
            }
            for a in aliases:
                alias_owner.setdefault(a, name)
    for name in report.get("plugin_backed") or {}:
        names.setdefault(
            name,
            {
                "kind": "command",
                "aliases": [],
                "internal": False,
                "hidden": False,
                "plugin_backed": True,
            },
        )
    return names, alias_owner


def classify(
    report: dict[str, Any],
    rows: dict[str, dict[str, Any]],
    changelog: dict[str, dict[str, Any]] | None = None,
) -> dict[str, dict[str, Any]]:
    """One entry per name the binary registers or the docs list.

    An internal registration (never user-typed) counts as registered when the
    docs name it, and is otherwise left out rather than listed undocumented.
    """
    binary, alias_owner = _binary_index(report)
    docs_aliases: dict[str, str] = {}
    for name, row in rows.items():
        for a in row["aliases"]:
            docs_aliases.setdefault(a, name)
        if row["alias_of"]:
            docs_aliases.setdefault(name, row["alias_of"])

    out: dict[str, dict[str, Any]] = {}
    for name in sorted(set(binary) | set(rows) | set(docs_aliases)):
        row = rows.get(name)
        reg = binary.get(name)
        if reg and reg["internal"] and row is None and name not in docs_aliases:
            continue
        bin_alias_of = alias_owner.get(name)
        docs_alias_of = (
            docs_aliases.get(name) if not (row and not row["is_alias"]) else None
        )
        if row and row["removed"]:
            registered = reg is not None or bin_alias_of is not None
            status = (
                "removed_in_docs_but_registered" if registered else "removed_in_docs"
            )
        elif (row and row["is_alias"]) or (row is None and name in docs_aliases):
            if reg is not None:
                status = "docs_alias_but_registered"
            elif bin_alias_of is not None:
                status = "alias"
            else:
                status = "docs_only"
        elif row is not None:
            status = "documented" if reg is not None or bin_alias_of else "docs_only"
        else:
            status = "undocumented"
        entry: dict[str, Any] = {
            "status": status,
            "binary_kind": reg["kind"] if reg else ("alias" if bin_alias_of else None),
            "binary_alias_of": bin_alias_of,
            "docs_kind": (
                "alias"
                if (row and row["is_alias"]) or (row is None and name in docs_aliases)
                else (row["kind"] if row else None)
            ),
            "docs_args": row["args"] if row else None,
            "docs_alias_of": docs_alias_of,
            "docs_summary": row["summary"] if row else None,
        }
        if row and row["removed_version"]:
            entry["docs_removed_version"] = row["removed_version"]
        if reg and reg.get("plugin_backed"):
            entry["plugin_backed"] = True
        entry["kind_mismatch"] = bool(
            row and reg and not row["is_alias"] and row["kind"] != reg["kind"]
        )
        if reg:
            documented_aliases = set(row["aliases"]) if row else set()
            documented_aliases |= {
                a for a, owner in docs_aliases.items() if owner == name
            }
            only_docs = sorted(documented_aliases - set(reg["aliases"]))
            only_binary = sorted(set(reg["aliases"]) - documented_aliases)
            if row and (only_docs or only_binary):
                entry["alias_disagreement"] = {
                    "docs_only": only_docs,
                    "binary_only": only_binary,
                }
        if docs_alias_of and bin_alias_of and docs_alias_of != bin_alias_of:
            entry["alias_target_disagreement"] = {
                "docs": docs_alias_of,
                "binary": bin_alias_of,
            }
        entry["changelog"] = changelog.get(name) if changelog is not None else None
        out[name] = entry
    return out


def build_crosscheck(
    report: dict[str, Any],
    docs_file: str | None = None,
    changelog_file: str | None = None,
    tools_file: str | None = None,
) -> dict[str, Any]:
    """The `docs_crosscheck` block: statuses per name plus its own health.

    `tools` is a nested block for the built-in tools lane with a status of its
    own, so a tools-page failure never changes the commands verdict.
    """
    block: dict[str, Any] = {
        "status": "ok",
        "problems": [],
        "advisories": [],
        "method": {
            "source_of_truth": "the binary lanes decide what exists; the docs only classify it",
            "statuses": list(STATUSES),
            "changelog": "heuristic: earliest version whose entry mentions /name, and "
            "lines using an add, rename, remove, deprecate, or alias word; a mention "
            "is not proof of introduction",
        },
        "sources": {},
    }
    block["tools"] = build_tools_crosscheck(report, tools_file)
    if not report.get("sources", {}).get("binary", {}).get("available"):
        block["status"] = "unavailable"
        block["problems"].append(
            "the binary was not read; there is nothing to cross-check"
        )
        return block

    if docs_file:
        try:
            docs_text, err = Path(docs_file).read_text(encoding="utf-8"), None
        except OSError as exc:
            docs_text, err = None, f"{type(exc).__name__}: {exc}"
        block["sources"]["commands"] = {"file": docs_file}
    else:
        docs_text, err = fetch_text(COMMANDS_URL)
        block["sources"]["commands"] = {"url": COMMANDS_URL}
    if docs_text is None:
        block["status"] = "unavailable"
        block["sources"]["commands"]["error"] = err
        block["problems"].append(f"commands page unavailable: {err}")
        return block

    rows = parse_commands_table(docs_text)
    block["sources"]["commands"]["rows"] = len(rows)
    if not rows:
        block["status"] = "broken"
        block["problems"].append(
            f"no rows parsed under '{_SECTION}' - the commands page layout changed"
        )
        return block

    changelog: dict[str, dict[str, Any]] | None = None
    if changelog_file:
        try:
            cl_text, cl_err = Path(changelog_file).read_text(encoding="utf-8"), None
        except OSError as exc:
            cl_text, cl_err = None, f"{type(exc).__name__}: {exc}"
        block["sources"]["changelog"] = {"file": changelog_file}
    else:
        cl_text, cl_err = fetch_text(CHANGELOG_URL)
        block["sources"]["changelog"] = {"url": CHANGELOG_URL}
    if cl_text is None:
        block["sources"]["changelog"]["error"] = cl_err
        block["advisories"].append(
            f"changelog unavailable, no version history attached: {cl_err}"
        )
    else:
        binary, _ = _binary_index(report)
        names = (
            set(binary) | set(rows) | {a for r in rows.values() for a in r["aliases"]}
        )
        changelog = parse_changelog(cl_text, names)

    names_block = classify(report, rows, changelog)
    lanes = (report.get("integrity") or {}).get("lanes") or {}
    unhealthy = sorted(lane for lane, e in lanes.items() if e.get("status") != "ok")
    if unhealthy:
        block["advisories"].append(
            "binary lane(s) not ok: "
            + ", ".join(unhealthy)
            + " - an undocumented or docs_only status may reflect extraction, not the product"
        )
    counts = {s: 0 for s in STATUSES}
    for entry in names_block.values():
        counts[entry["status"]] += 1
    block["counts"] = counts
    block["kind_mismatches"] = sorted(
        n for n, e in names_block.items() if e["kind_mismatch"]
    )
    block["alias_disagreements"] = sorted(
        n
        for n, e in names_block.items()
        if "alias_disagreement" in e or "alias_target_disagreement" in e
    )
    block["names"] = names_block
    if block["advisories"]:
        block["status"] = "degraded"
    return block
