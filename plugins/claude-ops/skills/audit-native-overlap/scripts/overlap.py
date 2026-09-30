#!/usr/bin/env python3
"""Native-overlap detection, registry generation, and freshness self-check.

Three subcommands over one committed store:

  detect      Merge an inventory JSON (native side) with a repo-tree scan of
              plugin components (target side) and the seeded candidate pairs,
              and emit candidate rows. Emits candidates only - never verdicts.
  generate    Render the store into the marker-fenced registry view.
              `--check` regenerates and diffs instead of writing.
  self-check  Deterministic freshness gate over the store, the view, and the
              baked lines in components.
  dismiss     Record a human's ruling that a candidate pair is not an overlap,
              fingerprinting both sides' scored text so `detect` suppresses
              the pair until either side's text changes.

Requires Python 3.11+ and nothing else - stdlib only, matching the sibling
inventory extractor's no-third-party discipline.

EXIT CODES - a deliberate divergence, stated so it never reads as an accident.
The repo's shell gates use 0 clean / 1 findings / 2 usage-or-environment error.
This script instead follows the sibling `inventory.py --self-check` contract,
because a consumer wiring both into one lane needs one taxonomy for "the data
is stale but honest":

  0  ok        - everything checked passed
  1  broken    - a defect the registry owns: malformed store, missing trigger,
                 view drift, baked line with no store row, non-defer extraction
                 row whose component carries no Boundary section naming it
  3  degraded  - checked what could be checked; something was not locally
                 decidable (no CLI on PATH) or is stale-but-honest (recorded
                 extraction version differs from the current build)
  2  argparse  - reserved for usage errors, so a mistyped flag can never be
                 mistaken for a degraded run

A degraded run is a passing run for gate purposes. The conditions it reports -
an upstream release the registry does not own, an absent CLI - are not defects
in the data, and a chronically red gate on a condition nobody can fix here is
worse than an annotated pass.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

# `lib/registrations.py` is shared with the sibling extractor that writes the
# shape, so a consumer can never read it by a rule of its own.
from registrations import registrations_of  # noqa: E402  (path set above; plugin-bundled module)

import discover  # noqa: E402  (sibling module; the script's own directory is on sys.path)

MIN_PYTHON = (3, 11)

STORE_SCHEMA = 1
PAIRS_SCHEMA = 1
INVENTORY_SCHEMA = 1

# Keys the detector reads out of the inventory JSON. The extractor's integrity
# block guards extraction-level drift, NOT its own top-level key names, so a
# renamed key would read here as an empty surface rather than an error. Each
# one is presence-checked and a miss is reported as broken, consumer-side.
INVENTORY_KEYS = ("builtin_commands", "bundled_skills", "plugin_backed", "integrity")

VERDICTS = ("prefer-native", "prefer-ours", "complementary", "superseded", "defer")
NATIVE_CLASSES = (
    "builtin-command",
    "bundled-skill",
    "bundled-workflow",
    "plugin-backed-builtin",
    "builtin-agent",
    "builtin-tool",
    "session-skill",
    "marketplace-plugin",
)
OBSERVATION_CLASSES = ("extraction", "live-roster", "upstream-source")
COMPONENT_KINDS = ("skill", "agent")
NATIVE_MARKERS = ("hidden", "gated", "model-invocation-disabled")
INTEGRATIONS = ("route", "wrap", "suggest")
# Classes that may take route or wrap when the row is not defer and, for a
# bundled skill, not model-invocation-disabled. The marker and defer rules
# below replace this set rather than adding to it.
ROUTE_OR_WRAP_CLASSES = (
    "bundled-skill",
    "plugin-backed-builtin",
    "marketplace-plugin",
)
# A wrap or suggest row names how the surface is actually invoked. The class
# rules are a floor; Skill-tool reach is per surface, so the evidence line is
# what a later reader re-derives from.
INVOCATION_MODE_RE = re.compile(
    r"model[- ]invoc|disableModelInvocation|Skill[- ]tool|local-jsx|"
    r"invocation mode|non-prompt|command type",
    re.IGNORECASE,
)
# Suggest parity keys on this sentence shape, never the bare phrase
# "available in your session": that phrase already occurs in unrelated prose
# (claude-ops:changelog) and must not count as a baked suggestion.
SUGGEST_SHAPE_RE = re.compile(
    r"If /([A-Za-z0-9][A-Za-z0-9-]*) is available in your session \("
)
NATIVE_STEP_HEADING_RE = re.compile(
    r"^## Native step: (.+?) \(([^)\n]+)\)\s*$",
    re.MULTILINE,
)
BAKED_FLAGS = (
    "description_phrase",
    "boundary_section",
    "native_step",
    "suggest_sentence",
)

# Extraction lanes the sibling extractor reports integrity for, and the
# native class each one carries. Session-provided and marketplace classes have
# no lane: nothing about them is derivable from the binary.
# `bundled_workflows`, `builtin_agents`, and `builtin_tools` are optional: an
# extraction that predates a lane lacks its key, and the lane is then not
# scored or reported rather than read as broken.
LANE_ORDER = (
    "builtin_commands",
    "bundled_skills",
    "bundled_workflows",
    "plugin_backed",
    "builtin_agents",
    "builtin_tools",
)
LANE_OF_CLASS = {
    "builtin-command": "builtin_commands",
    "bundled-skill": "bundled_skills",
    "bundled-workflow": "bundled_workflows",
    "plugin-backed-builtin": "plugin_backed",
    "builtin-agent": "builtin_agents",
    "builtin-tool": "builtin_tools",
}
# Classes the model reaches by name (a subagent type, a tool) rather than
# through the Skill tool: nothing wraps them and no user types them as a
# command, so a component only routes to them.
ROUTE_ONLY_CLASSES = ("session-skill", "builtin-agent", "builtin-tool")
CLASS_OF_LANE = {lane: klass for klass, lane in LANE_OF_CLASS.items()}


# Lane order in the generated view: (class, section heading, singular noun used
# in a row's own prose). Provenance classes are never merged into one list -
# they carry different disable switches and different rosters per host.
LANES: tuple[tuple[str, str, str], ...] = (
    ("builtin-command", "Built-in CLI commands", "built-in command"),
    ("bundled-skill", "Bundled skills", "bundled skill"),
    ("bundled-workflow", "Bundled workflows", "bundled workflow"),
    ("plugin-backed-builtin", "Plugin-backed built-ins", "plugin-backed built-in"),
    ("builtin-agent", "Built-in subagents", "built-in subagent"),
    ("builtin-tool", "Built-in tools", "built-in tool"),
    (
        "session-skill",
        "Session-provided skills (observation-only)",
        "session-provided skill",
    ),
    (
        "marketplace-plugin",
        "First-party marketplace plugins",
        "first-party marketplace plugin",
    ),
)

# The canonical presence-gate token owned by docs/conventions/native-references.
# A baked description phrase carries it; the reverse-parity scan keys on it.
GATE_TOKEN = "resolves in this session"

# The parity token for marketplace-plugin rows (a first-party plugin skill is
# not a native surface, so its routing lines phrase per seam-phrasing, not
# native-references). A baked description phrase for that class carries this
# token instead; the reverse-parity scan keys on both, per class.
MARKETPLACE_GATE_TOKEN = "installed from its marketplace"

# A description that names a native surface by class and kind inside a
# presence clause (`when|where|if ... the bundled design skill is available`)
# without the gate token is routing on a presence condition the registry
# cannot see: no store row records it and no parity check protects it. The
# availability word is what separates a presence condition from a plain
# mention ("Not for: the bundled doctor skill's fix pass").
PRESENCE_MENTION_RE = re.compile(
    r"\b(?:when|where|if)\b[^.;()]{0,80}?"
    r"\b(?:bundled|built-in|plugin-backed built-in|session-provided)\s+"
    r"(?:[\w/-]+\s+){0,3}?(?:skill|command)s?\b"
    r"[^.;()]{0,40}?\b(?:available|present|installed|enabled|resolves?|exists?|ships)\b",
    re.IGNORECASE,
)

START_MARKER = "<!-- native-surfaces:start -->"
END_MARKER = "<!-- native-surfaces:end -->"

# Every pattern below is applied with `fullmatch`, so a trailing newline fails.
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
AS_OF_RE = re.compile(r"\d+\.\d+\.\d+")
# One plugin or component name segment: never `.`/`..`, never a path separator.
SEGMENT_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
# A dismissed native surface name, rendered into a generated markdown table.
NATIVE_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._: -]*")
REASON_MAX = 300
# A fingerprint: the first 32 hex chars of the SHA-256 of the whitespace-collapsed
# text, so a reflowed line never resurfaces a pair. The native side hashes the
# text detection scores (discover.scored_text); the component side, its description.
# Shorter digests trip the typos spell check on word-like hex fragments.
FINGERPRINT_LEN = 32
FINGERPRINT_RE = re.compile(rf"[0-9a-f]{{{FINGERPRINT_LEN}}}")
RESURFACED = "resurfaced: description changed"
# A trigger that is nothing but a date (however spelled) fails the observability
# bar: a date alone is not an observable event.
BARE_DATE_TRIGGER_RE = re.compile(
    r"^\W*(?:by|after|before|on|from)?\W*\d{4}(?:-\d{2}(?:-\d{2})?)?\W*$", re.IGNORECASE
)
VERSION_RE = re.compile(r"(\d+\.\d+\.\d+)")
# An upstream commit in an observation detail: 8-40 hex chars with at least one
# letter, so a bare numeric run (a date, a count) never reads as a commit. A
# genuinely all-digit real SHA prefix is possible in principle; cite more of
# the SHA in the detail and the lookahead is satisfied.
UPSTREAM_SHA_RE = re.compile(r"\b(?=[0-9a-f]*[a-f])[0-9a-f]{8,40}\b")

VIEW_HEADER = """# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI.
**Never hand-edit it.** Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when. See [`docs/conventions/native-references/`](conventions/native-references/README.md).
"""


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)


def fingerprint(text: str | None) -> str | None:
    """Short digest of a description; None when that side was not observed."""
    if text is None:
        return None
    normalized = " ".join(text.split())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:FINGERPRINT_LEN]


def pair_key(name: Any, component: dict[str, Any]) -> tuple[str, str, str, str]:
    """Store identity of a (native surface, component) pair."""
    return (
        str(name),
        str(component.get("plugin")),
        str(component.get("skill")),
        str(component.get("kind", "skill")),
    )


def load_json(path: Path) -> tuple[Any | None, str | None]:
    """Read a JSON file, returning (data, error-message)."""
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle), None
    except FileNotFoundError:
        return None, f"no such file: {path}"
    except OSError as exc:
        return None, f"cannot read {path}: {exc}"
    except json.JSONDecodeError as exc:
        return None, f"{path} is not valid JSON: {exc}"


def split_frontmatter(text: str) -> tuple[str, str]:
    """Split a markdown file into (frontmatter, body).

    Deliberately minimal: enough to read a description and find headings, not a
    YAML parser. A file with no frontmatter yields an empty first element.
    """
    if not text.startswith("---"):
        return "", text
    end = text.find("\n---", 3)
    if end == -1:
        return "", text
    return text[3:end], text[end + 4 :]


def frontmatter_description(frontmatter: str) -> str:
    """Extract the `description:` scalar from a frontmatter block.

    Line-based on purpose: PyYAML is not provisioned here (stdlib-only, matching
    the sibling extractor), and the parity check needs one field's value, not a
    document model. Handles the scalar styles this repo's SKILL.md files use -
    quoted, plain, and block (`|`, `>`, with chomping/indent indicators) - and
    reads only a TOP-LEVEL `description` key, so a nested one under `metadata:`
    is never mistaken for the routing-effective field.

    The returned value is whitespace-normalized to a single line, so a phrase
    that wraps across a folded or literal block still reads as one string.
    Returns "" when the block carries no top-level description.
    """
    lines = frontmatter.split("\n")
    for index, line in enumerate(lines):
        if not re.match(r"^description[ \t]*:", line):
            continue
        remainder = line.split(":", 1)[1].strip()
        rest = lines[index + 1 :]

        def _indented_block() -> list[str]:
            collected: list[str] = []
            for candidate in rest:
                if candidate.strip() and not candidate[:1].isspace():
                    break
                collected.append(candidate.strip())
            return collected

        if remainder[:1] in ("|", ">"):
            # Block scalar: the header line carries only style/chomping/indent
            # indicators; the value is the more-indented lines beneath it.
            parts = _indented_block()
        elif remainder[:1] in ('"', "'"):
            quote = remainder[0]
            body = remainder[1:].rstrip()
            if body.endswith(quote):
                parts = [body[:-1]]
            else:
                # A quoted scalar may span lines; consume until the closing quote.
                parts = [body]
                for candidate in rest:
                    stripped = candidate.strip()
                    if stripped.endswith(quote):
                        parts.append(stripped[:-1])
                        break
                    parts.append(stripped)
        elif remainder:
            # Plain scalar, possibly continued on more-indented lines.
            parts = [remainder, *_indented_block()]
        else:
            parts = _indented_block()
        return " ".join(" ".join(parts).split())
    return ""


def boundary_sections(body: str) -> list[str]:
    """Every `## Boundary...` section in a body, heading line included.

    A section runs from its heading to the next `## ` heading. All of them are
    collected rather than the first one taken: a component that overlaps several
    native surfaces may carry one section covering them all, and it may also
    carry a Boundary section written for something this registry has no row for.
    """
    sections: list[str] = []
    current: list[str] | None = None
    for line in body.split("\n"):
        if line.startswith("## "):
            if current is not None:
                sections.append("\n".join(current))
            current = [line] if line.startswith("## Boundary") else None
        elif current is not None:
            current.append(line)
    if current is not None:
        sections.append("\n".join(current))
    return sections


def boundary_names_surface(sections: list[str], name: str) -> bool:
    """Does any Boundary section name this native surface as a code span?

    Identity, not presence. The heading alone proves nothing about the row being
    checked: a component can carry a `## Boundary` section for an unrelated
    surface, and a component with several rows carries one section that must
    name each of them. The code span is the marker the convention's heading
    shape and every worked example already use, and it keeps a native name that
    is also a common English word (`run`, `design`) from being satisfied by
    ordinary prose. A leading slash is accepted so a surface written as a
    command (`/skill-doctor`) counts for a row whose name carries no slash.
    """
    pattern = re.compile(r"`/?" + re.escape(name) + r"`")
    return any(pattern.search(section) for section in sections)


def component_path(repo: Path, plugin: str, name: str, kind: str) -> Path:
    if kind == "agent":
        return repo / "plugins" / plugin / "agents" / f"{name}.md"
    return repo / "plugins" / plugin / "skills" / name / "SKILL.md"


def scan_components(repo: Path) -> dict[str, list[str]]:
    """Target-side substrate: this repo's own plugin tree.

    The sibling extractor scans INSTALLED trees, which are not necessarily the
    repository being audited - using it here would audit the wrong fleet.
    """
    found: dict[str, list[str]] = {"skills": [], "agents": []}
    plugins_dir = repo / "plugins"
    if not plugins_dir.is_dir():
        return found
    for plugin_dir in sorted(p for p in plugins_dir.iterdir() if p.is_dir()):
        plugin = plugin_dir.name
        skills_dir = plugin_dir / "skills"
        if skills_dir.is_dir():
            for skill_dir in sorted(s for s in skills_dir.iterdir() if s.is_dir()):
                if (skill_dir / "SKILL.md").is_file():
                    found["skills"].append(f"{plugin}:{skill_dir.name}")
        agents_dir = plugin_dir / "agents"
        if agents_dir.is_dir():
            for agent in sorted(agents_dir.glob("*.md")):
                found["agents"].append(f"{plugin}:{agent.stem}")
    return found


def load_components(repo: Path) -> list[discover.Component]:
    """The target side with its routing text, for discovery scoring."""
    found = scan_components(repo)
    corpus: list[discover.Component] = []
    for kind, ids in (("skill", found["skills"]), ("agent", found["agents"])):
        for ident in ids:
            plugin, name = ident.split(":", 1)
            path = component_path(repo, plugin, name, kind)
            try:
                frontmatter, _body = split_frontmatter(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError):
                frontmatter = ""
            corpus.append(
                discover.Component.build(
                    plugin, name, kind, frontmatter_description(frontmatter)
                )
            )
    return corpus


def native_surfaces(lane_payloads: dict[str, Any]) -> list[discover.Surface]:
    """Every scorable native surface. An `internal` registration is skipped:
    it is plumbing the product never offers anyone to type or call."""
    plugin_backed = lane_payloads.get("plugin_backed") or {}
    surfaces: list[discover.Surface] = []
    seen: set[str] = set()
    for lane, payload in lane_payloads.items():
        if lane == "plugin_backed":
            continue
        for name, entry in payload.items():
            seen.add(name)
            registrations = registrations_of(entry)
            if not registrations or any(r.get("internal") for r in registrations):
                continue
            # A plugin-backed name the extractor enriched in this lane is one
            # surface, scored once, under the plugin-backed class.
            klass, source = (
                (CLASS_OF_LANE["plugin_backed"], "plugin_backed")
                if name in plugin_backed
                else (CLASS_OF_LANE[lane], lane)
            )
            surfaces.append(discover.Surface.build(name, klass, source, registrations))
    for name, plugin in plugin_backed.items():
        if name not in seen:
            registrations = [{"name": name, "plugin_name": plugin}]
            surfaces.append(
                discover.Surface.build(
                    name, CLASS_OF_LANE["plugin_backed"], "plugin_backed", registrations
                )
            )
    return surfaces


def registration_evidence(registrations: list[dict[str, Any]]) -> list[str]:
    """Per-registration evidence lines: markers, aliases, description, invocability."""
    evidence: list[str] = []
    if len(registrations) > 1:
        evidence.append(
            f"name collision: {len(registrations)} distinct registrations share "
            "this name in the extraction; a per-registration property (model "
            "invocability, gating) is read from the registration the row's "
            "evidence names, never from the bare name"
        )
    for position, entry in enumerate(registrations, start=1):
        tag = f"[{position}] " if len(registrations) > 1 else ""
        markers = [m for m in NATIVE_MARKERS if entry.get(m)]
        if markers:
            evidence.append(f"{tag}markers: {', '.join(markers)}")
        if entry.get("aliases"):
            evidence.append(f"{tag}aliases: {', '.join(entry['aliases'])}")
        if entry.get("description"):
            evidence.append(f"{tag}native description: {entry['description']}")
        if entry.get("roster"):
            evidence.append(f"{tag}agent roster: {entry['roster']}")
        if isinstance(entry.get("deferred"), bool):
            evidence.append(
                f"{tag}tool loading: {'deferred' if entry['deferred'] else 'up front'}"
            )
        model = discover.invocability([entry])["model_invocable"]
        if model is not None:
            flagged = {"disable_model_invocation", "model_invocable"} & set(
                entry.get("flag_driven") or []
            )
            evidence.append(
                f"{tag}model invocation: {'enabled' if model else 'disabled'}"
                + (" (flag-driven at runtime)" if flagged else "")
            )
    return evidence


def _store_verdicts(store_path: Path) -> dict[tuple[str, str, str, str], Any]:
    """Store identity -> verdict. An absent or unreadable store yields none:
    detect then reports every pair as NEW, and self-check owns store health."""
    store, _error = load_json(store_path)
    rows = store.get("rows") if isinstance(store, dict) else None
    verdicts: dict[tuple[str, str, str, str], Any] = {}
    for row in rows if isinstance(rows, list) else []:
        try:
            component = row["component"]
            key = (
                str(row["native"]["name"]),
                str(component["plugin"]),
                str(component["skill"]),
                str(component.get("kind", "skill")),
            )
        except (KeyError, TypeError):
            continue
        verdicts[key] = row.get("verdict")
    return verdicts


def _store_dismissals(store_path: Path) -> dict[tuple[str, str, str, str], Any]:
    """Store identity -> dismissal record. Malformed entries are skipped here;
    self-check owns store health."""
    store, _error = load_json(store_path)
    entries = store.get("dismissals") if isinstance(store, dict) else None
    dismissals: dict[tuple[str, str, str, str], Any] = {}
    for entry in entries if isinstance(entries, list) else []:
        try:
            key = pair_key(entry["native"]["name"], entry["component"])
        except (KeyError, TypeError, AttributeError):
            continue
        dismissals[key] = entry
    return dismissals


def dismissal_drift(
    dismissal: dict[str, Any], native_text: str | None, component_text: str | None
) -> list[str]:
    """The sides whose fingerprint moved since the dismissal.

    A side this run did not observe (None) is not comparable and never counts
    as drift: absence from an extraction proves nothing about the product.
    """
    recorded = dismissal.get("fingerprint")
    recorded = recorded if isinstance(recorded, dict) else {}
    drift: list[str] = []
    for side, text in (("native", native_text), ("component", component_text)):
        current = fingerprint(text)
        if current is not None and current != recorded.get(side):
            drift.append(side)
    return drift


def current_cli_version() -> tuple[str | None, str]:
    """Best-effort current CLI version from a cheap `claude --version` call.

    Never re-extracts the binary: a gate run that costs a 323 MB read is a gate
    nobody keeps. Returns (version, how) where a None version carries the reason.
    """
    exe = shutil.which("claude")
    if exe is None:
        return None, "claude not on PATH"
    try:
        proc = subprocess.run(  # noqa: S603 - fixed argv, no shell
            [exe, "--version"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"claude --version failed: {exc}"
    if proc.returncode != 0:
        return None, f"claude --version exited {proc.returncode}"
    match = VERSION_RE.search(proc.stdout or "")
    if match is None:
        return None, "no version found in `claude --version` output"
    return match.group(1), f"claude --version ({exe})"


# ---------------------------------------------------------------------------
# Store validation
# ---------------------------------------------------------------------------


def _row_label(row: Any, index: int) -> str:
    try:
        native = row["native"]["name"]
        component = row["component"]
        return f"row {index} ({native} -> {component['plugin']}:{component['skill']})"
    except (KeyError, TypeError):
        return f"row {index}"


def _native_problems(native: Any, label: str, *, markers: bool) -> list[str]:
    """Well-formedness of a `native` block. A store row also carries markers."""
    if not isinstance(native, dict):
        return [f"{label}: missing or malformed `native`"]
    problems: list[str] = []
    if not isinstance(native.get("name"), str) or not native.get("name"):
        problems.append(f"{label}: `native.name` must be a non-empty string")
    if native.get("class") not in NATIVE_CLASSES:
        problems.append(
            f"{label}: `native.class` must be one of {', '.join(NATIVE_CLASSES)}"
        )
    if markers:
        recorded = native.get("markers", [])
        if not isinstance(recorded, list) or any(
            m not in NATIVE_MARKERS for m in recorded
        ):
            problems.append(
                f"{label}: `native.markers` must be a list drawn from "
                f"{', '.join(NATIVE_MARKERS)}"
            )
    return problems


def valid_segment(value: Any) -> bool:
    return (
        isinstance(value, str)
        and value not in (".", "..")
        and SEGMENT_RE.fullmatch(value) is not None
    )


def _component_problems(
    component: Any, label: str, *, kind_required: bool
) -> list[str]:
    """Well-formedness of a `component` block.

    A store row must name its kind; a seeded pair need not, because the detect
    loop defaults it to "skill" - but a kind present in either must name a kind
    this repo actually has.
    """
    if not isinstance(component, dict):
        return [f"{label}: missing or malformed `component`"]
    problems: list[str] = []
    for key in ("plugin", "skill"):
        if not valid_segment(component.get(key)):
            problems.append(
                f"{label}: `component.{key}` must be one name segment matching "
                f"{SEGMENT_RE.pattern}"
            )
    if kind_required:
        if component.get("kind") not in COMPONENT_KINDS:
            problems.append(
                f"{label}: `component.kind` must be one of {', '.join(COMPONENT_KINDS)}"
            )
    elif "kind" in component and component.get("kind") not in COMPONENT_KINDS:
        problems.append(
            f"{label}: `component.kind` must be one of "
            f"{', '.join(COMPONENT_KINDS)} when present"
        )
    return problems


def validate_row(row: Any, index: int) -> list[str]:
    """Well-formedness of one store row. Returns a list of problems."""
    label = _row_label(row, index)
    problems: list[str] = []
    if not isinstance(row, dict):
        return [f"{label}: not an object"]

    problems.extend(_native_problems(row.get("native"), label, markers=True))
    problems.extend(
        _component_problems(row.get("component"), label, kind_required=True)
    )

    verdict = row.get("verdict")
    if verdict not in VERDICTS:
        problems.append(f"{label}: `verdict` must be one of {', '.join(VERDICTS)}")
    if not isinstance(row.get("reason"), str) or not row.get("reason", "").strip():
        # Required for every verdict, not only prefer-ours: a verdict with no
        # stated reason cannot be re-derived when its trigger fires.
        problems.append(f"{label}: `reason` must be a non-empty string")

    evidence = row.get("evidence")
    if (
        not isinstance(evidence, list)
        or not evidence
        or any(not isinstance(item, str) or not item.strip() for item in evidence)
    ):
        problems.append(f"{label}: `evidence` must be a non-empty list of strings")

    observation = row.get("observation")
    if not isinstance(observation, dict):
        problems.append(f"{label}: missing or malformed `observation`")
    else:
        if observation.get("class") not in OBSERVATION_CLASSES:
            problems.append(
                f"{label}: `observation.class` must be one of "
                f"{', '.join(OBSERVATION_CLASSES)} - an observation record states its "
                "evidence class, never a bare availability assertion"
            )
        if not isinstance(observation.get("detail"), str) or not observation.get(
            "detail"
        ):
            problems.append(f"{label}: `observation.detail` must be a non-empty string")
        elif observation.get(
            "class"
        ) == "upstream-source" and not UPSTREAM_SHA_RE.search(observation["detail"]):
            problems.append(
                f"{label}: an `upstream-source` observation names the upstream commit "
                "in its `detail` (8+ hex chars) - source evidence without a pin cannot "
                "be re-derived when its trigger fires"
            )
        if not DATE_RE.fullmatch(str(observation.get("date", ""))):
            problems.append(f"{label}: `observation.date` must be YYYY-MM-DD")

    recheck = row.get("recheck")
    if not isinstance(recheck, dict):
        problems.append(f"{label}: missing or malformed `recheck`")
    else:
        trigger = recheck.get("trigger")
        if not isinstance(trigger, str) or not trigger.strip():
            problems.append(
                f"{label}: `recheck.trigger` is required - no trigger-less rows"
            )
        elif BARE_DATE_TRIGGER_RE.match(trigger.strip()):
            problems.append(
                f"{label}: `recheck.trigger` is a bare date - a trigger names an "
                "observable event (upstream-drift observability bar)"
            )
        if not DATE_RE.fullmatch(str(recheck.get("verified", ""))):
            problems.append(f"{label}: `recheck.verified` must be YYYY-MM-DD")

    baked = row.get("baked")
    if not isinstance(baked, dict) or not all(
        isinstance(baked.get(key), bool) for key in BAKED_FLAGS
    ):
        problems.append(f"{label}: `baked` must carry boolean {', '.join(BAKED_FLAGS)}")
    if not isinstance(row.get("budget_caveat"), bool):
        problems.append(f"{label}: `budget_caveat` must be a boolean")

    problems.extend(_integration_problems(row, label))

    if (
        isinstance(observation, dict)
        and observation.get("class") == "live-roster"
        and isinstance(baked, dict)
        and any(baked.get(key) for key in ("description_phrase", "boundary_section"))
    ):
        problems.append(
            f"{label}: a live-roster observation is never baked - one environment's "
            "roster on one day is not a basis for a shipped routing line"
        )
    return problems


def _integration_problems(row: dict[str, Any], label: str) -> list[str]:
    """The runtime-relationship axis. Separate from `verdict`.

    `defer` forces `route` and wins over the model-disabled `suggest`-only
    rule: nothing is baked from a defer row, and a suggest sentence would be
    baked. `design-sync` is the row that carries both (model-disabled and
    defer); the confirmed verdict table records `route`.
    """
    integration = row.get("integration")
    if integration not in INTEGRATIONS:
        return [f"{label}: `integration` must be one of {', '.join(INTEGRATIONS)}"]
    problems: list[str] = []
    native = row.get("native") if isinstance(row.get("native"), dict) else {}
    klass = native.get("class")
    markers = native.get("markers") if isinstance(native.get("markers"), list) else []
    verdict = row.get("verdict")
    if verdict == "defer":
        if integration != "route":
            problems.append(
                f"{label}: a `defer` verdict takes `integration` `route` "
                "(nothing is baked from a defer row)"
            )
        return problems
    if klass in ROUTE_ONLY_CLASSES:
        if integration != "route":
            problems.append(f"{label}: a `{klass}` row takes `integration` `route`")
    elif klass in ("builtin-command", "bundled-workflow"):
        if integration not in ("route", "suggest"):
            problems.append(
                f"{label}: a `{klass}` row takes `route` or `suggest`, never `wrap`"
            )
    elif klass == "bundled-skill" and "model-invocation-disabled" in markers:
        if integration != "suggest":
            problems.append(
                f"{label}: a bundled skill marked `model-invocation-disabled` "
                "takes `integration` `suggest` (a route phrase on a surface the "
                "model never lists is dead text)"
            )
        baked = row.get("baked")
        if isinstance(baked, dict) and baked.get("description_phrase") is True:
            problems.append(
                f"{label}: a `suggest` row for a bundled skill marked "
                "`model-invocation-disabled` never bakes a description phrase "
                "(the model never lists the surface, so a route phrase is dead "
                "text)"
            )
    elif klass in ROUTE_OR_WRAP_CLASSES:
        if integration not in ("route", "wrap"):
            problems.append(f"{label}: a `{klass}` row takes `route` or `wrap`")
    if integration in ("wrap", "suggest"):
        evidence = row.get("evidence") if isinstance(row.get("evidence"), list) else []
        if not any(
            isinstance(item, str) and INVOCATION_MODE_RE.search(item)
            for item in evidence
        ):
            problems.append(
                f"{label}: a `{integration}` row carries an evidence line naming "
                "the observed invocation mode"
            )
    baked = row.get("baked") if isinstance(row.get("baked"), dict) else {}
    if baked.get("native_step") is True and integration != "wrap":
        problems.append(
            f"{label}: `baked.native_step` is true only when `integration` is `wrap`"
        )
    if baked.get("suggest_sentence") is True and integration != "suggest":
        problems.append(
            f"{label}: `baked.suggest_sentence` is true only when `integration` "
            "is `suggest`"
        )
    return problems


def validate_store(store: Any) -> list[str]:
    problems: list[str] = []
    if not isinstance(store, dict):
        return ["store is not a JSON object"]
    if store.get("schema") != STORE_SCHEMA:
        problems.append(
            f"store `schema` must be {STORE_SCHEMA}, got {store.get('schema')!r}"
        )
    rows = store.get("rows")
    if not isinstance(rows, list):
        return problems + ["store `rows` must be a list"]
    # Identity includes `component.kind`: a skill and an agent may share a name
    # inside one plugin, and they are distinct components resolving to distinct
    # paths (`skills/<name>/SKILL.md` vs `agents/<name>.md`). Keying without kind
    # would report two legitimate rows as a duplicate.
    seen: set[tuple[str, str, str, str]] = set()
    for index, row in enumerate(rows):
        problems.extend(validate_row(row, index))
        if isinstance(row, dict):
            try:
                key = (
                    row["native"]["name"],
                    row["component"]["plugin"],
                    row["component"]["skill"],
                    # `.get` so a row whose kind is missing (already reported by
                    # validate_row) still participates in duplicate detection.
                    str(row["component"].get("kind", "")),
                )
            except (KeyError, TypeError):
                continue
            if key in seen:
                problems.append(
                    f"duplicate row for {key[0]} -> {key[1]}:{key[2]} ({key[3]})"
                )
            seen.add(key)

    # A dismissal is a ruling that a pair is NOT an overlap; a verdict row is a
    # ruling that it is. One pair never carries both.
    dismissals = store.get("dismissals", [])
    if not isinstance(dismissals, list):
        return problems + ["store `dismissals` must be a list when present"]
    dismissed: set[tuple[str, str, str, str]] = set()
    for index, entry in enumerate(dismissals):
        problems.extend(validate_dismissal(entry, index))
        try:
            key = pair_key(entry["native"]["name"], entry["component"])
        except (KeyError, TypeError, AttributeError):
            continue
        label = f"{key[0]} -> {key[1]}:{key[2]} ({key[3]})"
        if key in dismissed:
            problems.append(f"duplicate dismissal for {label}")
        if key in seen:
            problems.append(
                f"dismissal for {label} coexists with a verdict row for the same "
                "pair; a pair is either an overlap or dismissed, never both"
            )
        dismissed.add(key)
    return problems


def validate_dismissal(entry: Any, index: int) -> list[str]:
    """Well-formedness of one dismissal record."""
    label = f"dismissal {index}"
    if not isinstance(entry, dict):
        return [f"{label}: not an object"]
    try:
        component = entry["component"]
        label += f" ({entry['native']['name']} -> {component['plugin']}:{component['skill']})"
    except (KeyError, TypeError):
        pass
    problems = _native_problems(entry.get("native"), label, markers=False)
    problems.extend(
        _component_problems(entry.get("component"), label, kind_required=True)
    )
    native = entry.get("native")
    if isinstance(native, dict) and isinstance(native.get("name"), str):
        if not NATIVE_NAME_RE.fullmatch(native["name"]):
            problems.append(
                f"{label}: `native.name` must match {NATIVE_NAME_RE.pattern}"
            )
    if not isinstance(entry.get("reason"), str) or not entry["reason"].strip():
        problems.append(f"{label}: `reason` must be a non-empty string")
    elif len(entry["reason"]) > REASON_MAX:
        problems.append(
            f"{label}: `reason` is {len(entry['reason'])} characters; the limit is "
            f"{REASON_MAX}"
        )
    if not AS_OF_RE.fullmatch(str(entry.get("as_of", ""))):
        problems.append(
            f"{label}: `as_of` must be the Claude Code version the ruling was made "
            "against (X.Y.Z)"
        )
    if not DATE_RE.fullmatch(str(entry.get("date", ""))):
        problems.append(f"{label}: `date` must be YYYY-MM-DD")
    prints = entry.get("fingerprint")
    if not isinstance(prints, dict) or not all(
        FINGERPRINT_RE.fullmatch(str(prints.get(side, "")))
        for side in ("native", "component")
    ):
        problems.append(
            f"{label}: `fingerprint` must carry `native` and `component`, each 16 "
            "lowercase hex chars (use `overlap.py dismiss` to compute them)"
        )
    return problems


def validate_pairs(pairs_data: dict[str, Any]) -> list[str]:
    """Well-formedness of a schema-checked canonical-pairs payload.

    Runs before the detect loop reads it. A `"pairs": null`, a non-list, or an
    entry that is not an object would otherwise pass the schema gate and then
    surface as an uncaught TypeError/AttributeError mid-loop - a traceback is
    never this script's contract, so every violation is reported here as broken
    and names the offending entry's index.
    """
    problems: list[str] = []
    pairs = pairs_data.get("pairs")
    if not isinstance(pairs, list):
        return [
            f"canonical-pairs `pairs` must be a list, got "
            f"{type(pairs).__name__ if pairs is not None else 'null'}"
        ]
    for index, pair in enumerate(pairs):
        label = f"pair {index}"
        if not isinstance(pair, dict):
            problems.append(f"{label}: not an object")
            continue
        problems.extend(_native_problems(pair.get("native"), label, markers=False))
        problems.extend(
            _component_problems(pair.get("component"), label, kind_required=False)
        )
    return problems


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


_CELL_BREAKS = re.compile("[\r\n  ]")
_CELL_SPECIALS = re.compile(r"([\\`<>\[\]|])")


def _escape_cell(text: str) -> str:
    """Neutralize text for one markdown table cell: no line break, and no
    character that can end the cell or open a code span, link, or HTML tag."""
    return _CELL_SPECIALS.sub(r"\\\1", _CELL_BREAKS.sub(" ", str(text))).strip()


def render_block(
    rows: list[dict[str, Any]], dismissals: list[dict[str, Any]] | None = None
) -> str:
    """Render the marker-fenced body: a summary table, per-lane sections, and
    the dismissed pairs."""
    dismissals = dismissals or []
    lines: list[str] = []
    lines.append("## Summary")
    lines.append("")
    lines.append("| Lane | Rows | Baked | Integration | Verdicts |")
    lines.append("|---|---|---|---|---|")
    for lane, heading, _noun in LANES:
        lane_rows = [r for r in rows if r["native"]["class"] == lane]
        baked = sum(
            1
            for r in lane_rows
            if r["baked"]["description_phrase"]
            or r["baked"]["boundary_section"]
            or r["baked"]["native_step"]
            or r["baked"]["suggest_sentence"]
        )
        tally: dict[str, int] = {}
        integrations: dict[str, int] = {}
        for row in lane_rows:
            tally[row["verdict"]] = tally.get(row["verdict"], 0) + 1
            integrations[row["integration"]] = (
                integrations.get(row["integration"], 0) + 1
            )
        verdicts = ", ".join(f"{k} {v}" for k, v in sorted(tally.items())) or "none"
        integration = (
            ", ".join(f"{k} {v}" for k, v in sorted(integrations.items())) or "none"
        )
        lines.append(
            f"| {_escape_cell(heading)} | {len(lane_rows)} | {baked} | "
            f"{_escape_cell(integration)} | {_escape_cell(verdicts)} |"
        )
    lines.append("")

    for lane, heading, noun in LANES:
        lane_rows = sorted(
            (r for r in rows if r["native"]["class"] == lane),
            key=lambda r: (
                r["native"]["name"],
                r["component"]["plugin"],
                r["component"]["skill"],
                # Same identity tuple validation keys on, so a same-named
                # skill/agent pair renders in a stable, total order.
                r["component"]["kind"],
            ),
        )
        lines.append(f"## {heading}")
        lines.append("")
        if not lane_rows:
            lines.append("No rows recorded in this lane.")
            lines.append("")
            continue
        for row in lane_rows:
            native = row["native"]
            component = row["component"]
            target = f"{component['plugin']}:{component['skill']}"
            lines.append(f"### `{native['name']}` → `{target}`")
            lines.append("")
            markers = ", ".join(native.get("markers") or []) or "none"
            lines.append(f"- **Verdict:** `{row['verdict']}`: {row['reason']}")
            lines.append(f"- **Integration:** `{row['integration']}`")
            lines.append(
                f"- **Native surface:** `{native['name']}` ({noun}; markers: {markers})"
            )
            lines.append(f"- **Our component:** `{target}` ({component['kind']})")
            lines.append("- **Evidence:**")
            for item in row["evidence"]:
                lines.append(f"  - {item}")
            observation = row["observation"]
            lines.append(
                f"- **Observation:** {observation['class']}: {observation['detail']} "
                f"({observation['date']})"
            )
            recheck = row["recheck"]
            lines.append(
                f"- **Recheck trigger:** {recheck['trigger']} "
                f"(verified {recheck['verified']})"
            )
            baked = row["baked"]
            lines.append(
                "- **Baked:** description phrase "
                f"{'yes' if baked['description_phrase'] else 'no'} · Boundary section "
                f"{'yes' if baked['boundary_section'] else 'no'} · Native step "
                f"{'yes' if baked['native_step'] else 'no'} · suggest sentence "
                f"{'yes' if baked['suggest_sentence'] else 'no'}"
            )
            if row["budget_caveat"]:
                lines.append(
                    "- **Budget caveat:** the baked phrase may be dropped from the skill "
                    "listing under budget pressure. It is the best available routing "
                    "surface, not a guaranteed one"
                )
            lines.append("")

    lines.extend(render_dismissals(dismissals))
    return "\n".join(lines).rstrip() + "\n"


def render_dismissals(dismissals: list[dict[str, Any]]) -> list[str]:
    """The Dismissed section: pairs a human ruled are not an overlap."""
    lines = [
        "## Dismissed",
        "",
        "Pairs a human ruled are not an overlap. `detect` suppresses each one until either "
        "side's fingerprint changes, then lists it again flagged "
        f'"{RESURFACED}".',
        "",
    ]
    if not dismissals:
        return [*lines, "No dismissals recorded.", ""]
    lines.append("| Native surface | Class | Component | Reason | As of | Date |")
    lines.append("|---|---|---|---|---|---|")
    for entry in sorted(
        dismissals, key=lambda d: pair_key(d["native"]["name"], d["component"])
    ):
        component = entry["component"]
        target = (
            f"{_escape_cell(component['plugin'])}:{_escape_cell(component['skill'])}"
        )
        if component["kind"] == "agent":
            target += " (agent)"
        lines.append(
            f"| `{_escape_cell(entry['native']['name'])}` | "
            f"{_escape_cell(entry['native']['class'])} | `{target}` | "
            f"{_escape_cell(entry['reason'])} | {_escape_cell(entry['as_of'])} | "
            f"{_escape_cell(entry['date'])} |"
        )
    lines.append("")
    return lines


def render_view(
    rows: list[dict[str, Any]],
    existing: str | None,
    dismissals: list[dict[str, Any]] | None = None,
) -> tuple[str | None, str | None]:
    """Compose the full view text. Returns (text, error)."""
    block = render_block(rows, dismissals or [])
    if existing is None:
        return f"{VIEW_HEADER}\n{START_MARKER}\n\n{block}\n{END_MARKER}\n", None
    start = existing.find(START_MARKER)
    end = existing.find(END_MARKER)
    if start == -1 or end == -1 or end < start:
        return None, (
            f"the view is missing the markers ({START_MARKER} … {END_MARKER}); "
            "add them once, or delete the file and regenerate it"
        )
    head = existing[: start + len(START_MARKER)]
    tail = existing[end:]
    return f"{head}\n\n{block}\n{tail}", None


# ---------------------------------------------------------------------------
# Baked-line parity
# ---------------------------------------------------------------------------


def check_baked_parity(repo: Path, rows: list[dict[str, Any]]) -> list[str]:
    """Store <-> component parity, direction-sensitively.

    Forward: a row claiming a baked line must have that line in the component.
    A claimed Boundary section must also NAME this row's native surface, because
    a generic `## Boundary` heading is satisfied by any prose: one component may
    carry a section for a surface this registry has no row for, and a component
    with several rows carries one section that owes each of them a mention.
    Reverse: a description carrying the gate token must have a store row.

    The reverse scan keys on the frontmatter description ONLY. `## Boundary` is
    an organic pattern that predates this registry - several skills carry one
    for reasons the registry has no row for - so a reverse scan on headings
    would flag legitimate prose. The description is the routing-effective
    surface and is the thing this parity exists to protect.

    Both directions parse the `description` field out of the frontmatter rather
    than searching the frontmatter text: the gate token is only load-bearing
    where the router reads it, so the same token sitting in `argument-hint` or
    `metadata` neither satisfies a baked claim nor counts as an orphan.
    """
    problems: list[str] = []
    # Parity is keyed per token: native rows bake the native-references gate,
    # marketplace-plugin rows bake the seam-phrasing marketplace gate. One
    # description may legitimately carry both (one skill, two rows of the two
    # classes), so each token's orphan scan consults its own claimed set.
    baked_desc: dict[str, set[tuple[str, str]]] = {
        GATE_TOKEN: set(),
        MARKETPLACE_GATE_TOKEN: set(),
    }

    for index, row in enumerate(rows):
        component = row["component"]
        path = component_path(
            repo, component["plugin"], component["skill"], component["kind"]
        )
        label = _row_label(row, index)
        row_token = (
            MARKETPLACE_GATE_TOKEN
            if row["native"].get("class") == "marketplace-plugin"
            else GATE_TOKEN
        )
        wants_desc = row["baked"]["description_phrase"]
        wants_boundary = row["baked"]["boundary_section"]
        wants_step = row["baked"]["native_step"]
        wants_suggest = row["baked"]["suggest_sentence"]
        if not (wants_desc or wants_boundary or wants_step or wants_suggest):
            continue
        if component["kind"] == "agent":
            problems.append(
                f"{label}: agents are registry-rows-only - a role prompt loads after "
                "dispatch, too late to route - so no agent row may be baked"
            )
            continue
        if not path.is_file():
            problems.append(
                f"{label}: baked row names a component with no file at {path}"
            )
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            problems.append(f"{label}: cannot read {path}: {exc}")
            continue
        frontmatter, body = split_frontmatter(text)
        native_name = row["native"]["name"]
        if wants_desc:
            # Scoped to the description field, never the whole frontmatter: the
            # description is the routing-effective surface, so the same token in
            # `argument-hint` or `metadata` must not satisfy a baked claim.
            if row_token not in frontmatter_description(frontmatter):
                problems.append(
                    f"{label}: `baked.description_phrase` is true but the description in "
                    f'{path} carries no presence gate ("{row_token}")'
                )
            else:
                baked_desc[row_token].add((component["plugin"], component["skill"]))
        if wants_boundary:
            sections = boundary_sections(body)
            if not sections:
                problems.append(
                    f"{label}: `baked.boundary_section` is true but {path} has no "
                    "`## Boundary` section"
                )
            elif not boundary_names_surface(sections, native_name):
                problems.append(
                    f"{label}: `baked.boundary_section` is true but no `## Boundary` "
                    f"section in {path} names `{native_name}` - a section written for "
                    "another surface does not carry this row's verdict"
                )
        if wants_step and not _body_has_native_step(body, native_name):
            problems.append(
                f"{label}: `baked.native_step` is true but {path} has no "
                f"`## Native step: {native_name} (<class>)` heading"
            )
        if wants_suggest and not _body_has_suggest_sentence(body, native_name):
            problems.append(
                f"{label}: `baked.suggest_sentence` is true but {path} has no "
                f"suggest sentence for `/{native_name}`"
            )

    claimed_suggest = {
        (
            row["component"]["plugin"],
            row["component"]["skill"],
            row["native"]["name"],
        )
        for row in rows
        if isinstance(row, dict)
        and isinstance(row.get("baked"), dict)
        and row["baked"].get("suggest_sentence")
        and isinstance(row.get("component"), dict)
        and isinstance(row.get("native"), dict)
    }

    plugins_dir = repo / "plugins"
    if plugins_dir.is_dir():
        for skill_md in sorted(plugins_dir.glob("*/skills/*/SKILL.md")):
            try:
                text = skill_md.read_text(encoding="utf-8")
                frontmatter, body = split_frontmatter(text)
            except OSError:
                continue
            description = frontmatter_description(frontmatter)
            plugin = skill_md.parents[2].name
            skill = skill_md.parent.name
            for token, claimed in baked_desc.items():
                if token not in description:
                    continue
                if (plugin, skill) not in claimed:
                    problems.append(
                        f'{plugin}:{skill} carries a baked presence gate ("{token}") in '
                        "its description with no store row claiming it - every baked "
                        "line traces to a row (a row without a baked line is legal "
                        "pending-sweep state; the reverse is not)"
                    )
            for match in SUGGEST_SHAPE_RE.finditer(body):
                name = match.group(1)
                if (plugin, skill, name) not in claimed_suggest:
                    problems.append(
                        f"{plugin}:{skill} carries a suggest sentence for `/{name}` "
                        "with no store row claiming it - parity keys on the sentence "
                        "shape `If /<name> is available in your session (`, never the "
                        "bare phrase"
                    )
    return problems


def _body_has_native_step(body: str, name: str) -> bool:
    """True when the body has `## Native step: <name> (<class>)` for this surface."""
    for match in NATIVE_STEP_HEADING_RE.finditer(body):
        if match.group(1).strip() == name:
            return True
    return False


def _body_has_suggest_sentence(body: str, name: str) -> bool:
    """True when the body has the suggest sentence shape for this surface."""
    for match in SUGGEST_SHAPE_RE.finditer(body):
        if match.group(1) == name:
            return True
    return False


def _presence_descriptions(plugins_dir: Path) -> list[tuple[str, str]]:
    """(label, description) for every skill and plugin manifest under plugins/."""
    found: list[tuple[str, str]] = []
    for skill_md in sorted(plugins_dir.glob("*/skills/*/SKILL.md")):
        try:
            frontmatter, _ = split_frontmatter(skill_md.read_text(encoding="utf-8"))
        except OSError:
            continue
        description = frontmatter_description(frontmatter)
        if description:
            found.append(
                (f"{skill_md.parents[2].name}:{skill_md.parent.name}", description)
            )
    for manifest in sorted(plugins_dir.glob("*/.claude-plugin/plugin.json")):
        try:
            description = json.loads(manifest.read_text(encoding="utf-8")).get(
                "description"
            )
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(description, str) and description:
            found.append((f"{manifest.parents[1].name} (plugin.json)", description))
    return found


def check_presence_mentions(repo: Path) -> list[str]:
    """Descriptions routing on a native surface's presence without the gate token.

    Scans skill descriptions and plugin manifest descriptions. Advisory, never
    a break: the two shapes it catches on a real tree are legitimate pending
    rows, and the fix is a store row plus a baked phrase (or dropping the
    condition), not a red gate. A description carrying a gate token anywhere
    is left to the parity checks, which own it.
    """
    advisories: list[str] = []
    plugins_dir = repo / "plugins"
    if not plugins_dir.is_dir():
        return advisories
    for label, description in _presence_descriptions(plugins_dir):
        for match in PRESENCE_MENTION_RE.finditer(description):
            # Token presence is judged per clause, not per description: one
            # skill may carry a gated marketplace clause and an ungated native
            # clause, and the second is the one this check exists to find.
            clause_end = len(description)
            for stop in ".;)":
                at = description.find(stop, match.start())
                if at != -1:
                    clause_end = min(clause_end, at)
            clause = description[match.start() : clause_end]
            if GATE_TOKEN in clause or MARKETPLACE_GATE_TOKEN in clause:
                continue
            advisories.append(
                f"{label} names a native surface behind a presence condition "
                f'without a gate token ("{match.group(0).strip()}"); add a store row '
                f'and bake the phrase with "{GATE_TOKEN}", or drop the condition'
            )
    return advisories


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def build_native_index(
    inventory: dict[str, Any], lane_payloads: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    """Native name -> {class, entry}, first lane wins in workflow, skill,
    command, agent, tool order; plugin-backed built-ins override."""
    native_index: dict[str, dict[str, Any]] = {}
    for lane in (
        "bundled_workflows",
        "bundled_skills",
        "builtin_commands",
        "builtin_agents",
        "builtin_tools",
    ):
        for name, entry in (lane_payloads.get(lane) or {}).items():
            native_index.setdefault(
                name, {"class": CLASS_OF_LANE[lane], "entry": entry}
            )
    for name, plugin in (inventory.get("plugin_backed") or {}).items():
        # The extractor enriches a same-named command or skill with the plugin;
        # reclassify that registration rather than replace it with a bare one.
        enriched = native_index.get(name)
        native_index[name] = {
            "class": "plugin-backed-builtin",
            "entry": enriched["entry"]
            if enriched
            else {"name": name, "plugin_name": plugin},
        }
    return native_index


def _lane_payloads(inventory: dict[str, Any]) -> dict[str, Any]:
    # The workflow lane is optional: an extraction that predates it simply
    # has no such lane, which is not a missing consumed key.
    return {
        lane: inventory.get(lane)
        for lane in LANE_ORDER
        if isinstance(inventory.get(lane), dict)
    }


def cmd_detect(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    inventory, error = load_json(Path(args.inventory))
    if error is not None:
        _fail(error)
        return 1
    if not isinstance(inventory, dict) or inventory.get("schema") != INVENTORY_SCHEMA:
        _fail(
            f"inventory `schema` must be {INVENTORY_SCHEMA}, got "
            f"{inventory.get('schema') if isinstance(inventory, dict) else 'non-object'!r}"
        )
        return 1
    missing = [key for key in INVENTORY_KEYS if key not in inventory]
    if missing:
        _fail(
            "inventory is missing key(s) this consumer reads: "
            + ", ".join(missing)
            + " - the extractor's integrity block guards extraction drift, not its own "
            "key names, so a missing key is reported as broken rather than read as an "
            "empty surface"
        )
        return 1

    pairs_data, error = load_json(Path(args.pairs))
    if error is not None:
        _fail(error)
        return 1
    if not isinstance(pairs_data, dict) or pairs_data.get("schema") != PAIRS_SCHEMA:
        _fail(f"canonical-pairs `schema` must be {PAIRS_SCHEMA}")
        return 1
    pair_problems = validate_pairs(pairs_data)
    if pair_problems:
        for problem in pair_problems:
            _fail(problem)
        return 1

    # A malformed integrity block reads as an empty one: every field below then
    # falls back to the same "unknown" it would have reported field by field.
    integrity = inventory["integrity"]
    if not isinstance(integrity, dict):
        integrity = {}
    status = integrity.get("status", "unknown")
    # Per-lane floors, when the extractor reports them. An older inventory
    # without `lanes` is read through the top-level status alone, so a
    # consumer on a newer plugin against an older extraction still parses.
    lanes = integrity.get("lanes")
    if not isinstance(lanes, dict):
        lanes = None

    def lane_state(lane: str | None) -> dict[str, Any] | None:
        if lane is None or lanes is None:
            return None
        entry = lanes.get(lane)
        return entry if isinstance(entry, dict) else None

    components = scan_components(repo)
    known_skills = set(components["skills"])
    known_agents = set(components["agents"])

    lane_payloads = _lane_payloads(inventory)
    native_index = build_native_index(inventory, lane_payloads)

    store_verdicts = _store_verdicts(Path(args.store))
    store_dismissals = _store_dismissals(Path(args.store))
    suppressed: list[dict[str, Any]] = []
    orphaned: list[dict[str, Any]] = []
    examined: set[tuple[str, str, str, str]] = set()

    def broken_lane_evidence(lanes_in_play: set[str]) -> tuple[bool | None, list[str]]:
        if not lanes_in_play:
            return None, []  # session-provided and marketplace rows have no lane
        notes: list[str] = []
        broken = [
            lane
            for lane in sorted(lanes_in_play)
            if (lane_state(lane) or {}).get("status") == "broken"
        ]
        for lane in broken:
            problems = (lane_state(lane) or {}).get("problems") or []
            notes.append(
                f"the `{lane}` lane of this extraction is broken"
                + (f" ({'; '.join(problems)})" if problems else "")
                + " - presence or absence in that lane is not re-derivable from "
                "this run"
            )
        return not broken, notes

    def native_block(
        name: str, klass: str, seen: dict[str, Any] | None
    ) -> dict[str, Any]:
        registrations = registrations_of(seen["entry"]) if seen else []
        who = discover.invocability(registrations)
        markers = [m for m in NATIVE_MARKERS if any(r.get(m) for r in registrations)]
        if who["model_invocable"] is False:
            markers.append("model-invocation-disabled")
        return {
            "name": name,
            "class": klass,
            "observed": seen is not None,
            "markers": sorted(set(markers), key=NATIVE_MARKERS.index),
            "model_invocable": who["model_invocable"],
            "user_invocable": who["user_invocable"],
            "argument_hint": who["argument_hint"],
            "invocable_by": who["invocable_by"],
        }

    key_of = pair_key
    corpus = load_components(repo)
    surfaces = native_surfaces(lane_payloads)
    component_text = {(c.plugin, c.name, c.kind): c.description for c in corpus}

    def fingerprints(
        key: tuple[str, str, str, str], registrations: list[dict[str, Any]] | None
    ) -> dict[str, str | None]:
        native_text = (
            discover.scored_text(registrations) if registrations is not None else None
        )
        return {
            "native": fingerprint(native_text),
            "component": fingerprint(component_text.get(key[1:])),
        }

    def dismissal_state(
        key: tuple[str, str, str, str],
        klass: str,
        registrations: list[dict[str, Any]] | None,
    ) -> tuple[bool, dict[str, Any] | None]:
        """(suppress, resurfaced). A verdict row always wins over a dismissal:
        a ruled overlap is reported as such and never resurfaces."""
        entry = store_dismissals.get(key)
        if entry is None or key in store_verdicts:
            return False, None
        examined.add(key)
        native_text = (
            discover.scored_text(registrations) if registrations is not None else None
        )
        drift = dismissal_drift(entry, native_text, component_text.get(key[1:]))
        dismissed = {
            "reason": entry.get("reason"),
            "as_of": entry.get("as_of"),
            "date": entry.get("date"),
        }
        if not drift:
            suppressed.append(
                {
                    "native": key[0],
                    "class": klass,
                    "component": {"plugin": key[1], "skill": key[2], "kind": key[3]},
                    **dismissed,
                }
            )
            return True, None
        return False, {"flag": RESURFACED, "sides": drift, "dismissed": dismissed}

    def resurfaced_evidence(resurfaced: dict[str, Any] | None) -> list[str]:
        if resurfaced is None:
            return []
        dismissed = resurfaced["dismissed"]
        return [
            f"{RESURFACED} ({' and '.join(resurfaced['sides'])} side) since the "
            f"dismissal of {dismissed['date']} against {dismissed['as_of']}: "
            f"{str(dismissed['reason'])[:REASON_MAX]}"
        ]

    def keyed(scored: list[discover.Scored]) -> dict[tuple[str, str, str, str], Any]:
        return {
            key_of(s.name, {"plugin": c.plugin, "skill": c.name, "kind": c.kind}): (
                s,
                score,
                matched,
            )
            for s, c, score, matched in scored
        }

    # Seeds read their score from every scored pair, so a seed below the
    # discovery cut still shows how far lexical evidence alone would carry it.
    all_scored = discover.score_all(surfaces, corpus)
    seed_scores = keyed(all_scored)
    scores = keyed(
        discover.select(all_scored, threshold=args.threshold, top_k=args.top_k)
    )

    candidates: list[dict[str, Any]] = []
    for pair in pairs_data["pairs"]:  # shape guaranteed by validate_pairs above
        native = pair.get("native", {})
        component = pair.get("component", {})
        target = f"{component.get('plugin')}:{component.get('skill')}"
        seen = native_index.get(native.get("name"))
        evidence: list[str] = []
        if seen is None:
            evidence.append(
                f"`{native.get('name')}` is absent from this extraction - absence from "
                "the extraction is a statement about the extraction, not the product"
            )
        else:
            evidence.append(
                f"`{native.get('name')}` present in the extraction as {seen['class']}"
            )
            evidence.extend(registration_evidence(registrations_of(seen["entry"])))
        # The lane a candidate's re-derivability depends on: the seeded class
        # when the name is absent from the extraction, the observed class when
        # present, and both when the two disagree (a class collision), so a
        # broken lane on either side marks the candidate.
        seeded_lane = LANE_OF_CLASS.get(native.get("class"))
        observed_lane = LANE_OF_CLASS.get(seen["class"]) if seen else None
        re_derivable, notes = broken_lane_evidence(
            {lane for lane in (seeded_lane, observed_lane) if lane}
        )
        evidence.extend(notes)
        kind = component.get("kind", "skill")
        pool = known_agents if kind == "agent" else known_skills
        target_present = target in pool
        if not target_present:
            evidence.append(f"target `{target}` not found in the repo tree at {repo}")
        if pair.get("why"):
            evidence.append(f"seeded rationale: {pair['why']}")
        key = key_of(native.get("name"), component)
        scores.pop(key, None)
        _surface, score, matched = seed_scores.get(key, (None, None, None))
        klass = (seen or {}).get("class", native.get("class"))
        registrations = registrations_of(seen["entry"]) if seen else None
        suppress, resurfaced = dismissal_state(key, klass, registrations)
        if suppress:
            continue
        evidence.extend(resurfaced_evidence(resurfaced))
        block = native_block(native.get("name"), klass, seen)
        block["seeded_class"] = native.get("class")
        candidates.append(
            {
                "origin": "seeded",
                "native": block,
                "component": component,
                "component_present": target_present,
                "re_derivable": re_derivable,
                "score": score,
                "matched_tokens": matched,
                "recommended_integration": discover.recommended_integration(
                    klass, block["invocable_by"]
                ),
                "store_verdict": store_verdicts.get(key),
                "verdict": None,
                "fingerprints": fingerprints(key, registrations),
                "resurfaced": resurfaced,
                "evidence": evidence,
            }
        )

    def discovered_candidate(
        key: tuple[str, str, str, str],
        klass: str,
        lane: str | None,
        registrations: list[dict[str, Any]],
        score: Any,
        matched: list[str] | None,
        scored_line: str,
        resurfaced: dict[str, Any] | None,
    ) -> None:
        name, plugin, skill, kind = key
        block = native_block(name, klass, {"class": klass, "entry": registrations})
        re_derivable, notes = broken_lane_evidence({lane} if lane else set())
        candidates.append(
            {
                "origin": "discovered",
                "native": block,
                "component": {"plugin": plugin, "skill": skill, "kind": kind},
                "component_present": True,
                "re_derivable": re_derivable,
                "score": score,
                "matched_tokens": matched,
                "recommended_integration": discover.recommended_integration(
                    klass, block["invocable_by"]
                ),
                "store_verdict": None,
                "verdict": None,
                "fingerprints": fingerprints(key, registrations),
                "resurfaced": resurfaced,
                "evidence": [
                    f"`{name}` present in the extraction as {klass}",
                    *registration_evidence(registrations),
                    scored_line,
                    *notes,
                    *resurfaced_evidence(resurfaced),
                ],
            }
        )

    existing: list[dict[str, Any]] = []
    for key, (surface, score, matched) in sorted(
        scores.items(), key=lambda item: (item[0][0], -item[1][1], item[0][1:])
    ):
        name, plugin, skill, kind = key
        component = {"plugin": plugin, "skill": skill, "kind": kind}
        if key in store_verdicts:
            existing.append(
                {
                    "native": name,
                    "class": surface.klass,
                    "component": component,
                    "score": score,
                    "store_verdict": store_verdicts[key],
                }
            )
            continue
        suppress, resurfaced = dismissal_state(
            key, surface.klass, surface.registrations
        )
        if suppress:
            continue
        discovered_candidate(
            key,
            surface.klass,
            surface.lane,
            surface.registrations,
            score,
            matched,
            f"discovered: score {score} from shared tokens {', '.join(matched[:8])}",
            resurfaced,
        )

    # Every dismissal is checked against the current descriptions, not only the
    # pairs that scored above the cut: a description that drifted far enough to
    # drop a pair out of discovery is exactly the change a dismissal must catch.
    for key, entry in sorted(store_dismissals.items()):
        if key in examined or key in store_verdicts:
            continue
        seen = native_index.get(key[0])
        missing = [
            side
            for side, present in (
                ("native", seen is not None),
                ("component", key[1:] in component_text),
            )
            if not present
        ]
        if missing:
            orphaned.append(
                {
                    "native": key[0],
                    "component": {"plugin": key[1], "skill": key[2], "kind": key[3]},
                    "missing": missing,
                    "as_of": entry.get("as_of"),
                    "date": entry.get("date"),
                }
            )
            continue
        registrations = registrations_of(seen["entry"])
        suppress, resurfaced = dismissal_state(key, seen["class"], registrations)
        if suppress:
            continue
        _surface, score, matched = seed_scores.get(key, (None, None, None))
        discovered_candidate(
            key,
            seen["class"],
            LANE_OF_CLASS.get(seen["class"]),
            registrations,
            score,
            matched,
            "below the discovery cut"
            + (f": score {score}" if score is not None else ": not scored"),
            resurfaced,
        )

    report_integrity: dict[str, Any] = {
        "status": status,
        "cli_version": integrity.get("cli_version"),
        "validated_against": integrity.get("validated_against"),
        "counts_are": "floors" if status != "ok" else "totals",
    }
    if lanes is not None:
        # A run-wide advisory (an unvalidated CLI version) applies to every
        # lane's numbers, so an ok lane under it still reports floors. A lane
        # -attributed advisory (prefixed with the lane name by the extractor)
        # degrades only its own lane: a healthy lane beside a broken one keeps
        # its totals, which is the point of reporting per lane.
        lane_prefixes = tuple(f"{lane}:" for lane in LANE_ORDER) + tuple(
            f"{lane} lane broken:" for lane in LANE_ORDER
        )
        run_wide = [
            advisory
            for advisory in (integrity.get("advisories") or [])
            if isinstance(advisory, str) and not advisory.startswith(lane_prefixes)
        ]
        report_integrity["lanes"] = {
            lane: {
                "status": (lane_state(lane) or {}).get("status", "unknown"),
                "counts_are": (
                    "not reportable"
                    if (lane_state(lane) or {}).get("status") == "broken"
                    else "floors"
                    if (lane_state(lane) or {}).get("status") != "ok" or run_wide
                    else "totals"
                ),
            }
            for lane in LANE_ORDER
            if lane_state(lane) is not None
        }

    report = {
        "schema": 1,
        "repo": str(repo),
        "integrity": report_integrity,
        "target_scan": {
            "skills": len(components["skills"]),
            "agents": len(components["agents"]),
        },
        "discovery": {
            "threshold": args.threshold,
            "top_k": args.top_k,
            "lanes_scored": sorted(lane_payloads),
            "surfaces_scored": len(surfaces),
            "components_scored": len(corpus),
            "seeded": sum(1 for c in candidates if c["origin"] == "seeded"),
            "discovered": sum(1 for c in candidates if c["origin"] == "discovered"),
            "existing": existing,
            "suppressed": suppressed,
            "resurfaced": sum(1 for c in candidates if c["resurfaced"]),
            "dismissals_orphaned": orphaned,
        },
        "candidates": candidates,
        "note": (
            "Candidates only. No verdict is assigned here: every verdict is a human's, "
            "recorded in the store."
        ),
    }
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        sys.stdout.write(text)
    if status == "broken":
        _fail("inventory integrity is broken - no native-side counts are reportable")
        return 1
    if status != "ok":
        broken_lanes = [
            lane
            for lane in LANE_ORDER
            if (lane_state(lane) or {}).get("status") == "broken"
        ]
        detail = (
            f"; lane(s) {', '.join(broken_lanes)} broken, their counts are not "
            "reportable and their candidates are marked re_derivable: false"
            if broken_lanes
            else "; every native-side count is a floor"
        )
        print(f"degraded: inventory integrity is {status}{detail}", file=sys.stderr)
        return 3
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    store_path = Path(args.store)
    view_path = Path(args.view)
    store, error = load_json(store_path)
    if error is not None:
        _fail(error)
        return 1
    problems = validate_store(store)
    if problems:
        for problem in problems:
            _fail(problem)
        return 1
    rows = store["rows"]
    dismissals = store.get("dismissals") or []
    counts = f"{len(rows)} row(s), {len(dismissals)} dismissal(s)"
    existing = view_path.read_text(encoding="utf-8") if view_path.is_file() else None
    text, error = render_view(rows, existing, dismissals)
    if error is not None:
        _fail(error)
        return 1
    if args.check:
        if existing is None:
            _fail(f"{view_path} does not exist; run `generate` to create it")
            return 1
        if existing != text:
            _fail(
                f"{view_path} is out of sync with {store_path}; run "
                "`overlap.py generate` and commit the result"
            )
            return 1
        print(f"{view_path} is in sync with {store_path} ({counts})")
        return 0
    view_path.parent.mkdir(parents=True, exist_ok=True)
    view_path.write_text(text, encoding="utf-8")
    print(f"wrote {view_path} ({counts})")
    return 0


def cmd_self_check(args: argparse.Namespace) -> int:
    store_path = Path(args.store)
    view_path = Path(args.view)
    repo = Path(args.repo).resolve()
    problems: list[str] = []
    advisories: list[str] = []

    if not store_path.is_file():
        # Foreign-repo posture: a repository with no store is not a broken
        # repository, it is one that never adopted the registry.
        print(
            f"degraded: no store at {store_path} - nothing to check "
            "(report-only mode; the apply machinery is unavailable here)"
        )
        return 3

    store, error = load_json(store_path)
    if error is not None:
        _fail(error)
        return 1
    problems.extend(validate_store(store))
    if problems:
        for problem in problems:
            _fail(problem)
        print(f"SELF-CHECK broken: {len(problems)} problem(s) in {store_path}")
        return 1

    rows = store["rows"]

    existing = view_path.read_text(encoding="utf-8") if view_path.is_file() else None
    if existing is None:
        problems.append(
            f"the generated view {view_path} does not exist; run `generate`"
        )
    else:
        text, error = render_view(rows, existing, store.get("dismissals") or [])
        if error is not None:
            problems.append(error)
        elif text != existing:
            problems.append(
                f"{view_path} is out of sync with {store_path}; run `overlap.py generate`"
            )

    problems.extend(check_baked_parity(repo, rows))
    advisories.extend(check_presence_mentions(repo))

    # A verdict lives for the model only once the component's body carries its
    # Boundary section; the store alone ships to nobody. Broken, not degraded:
    # degraded is reserved for what this repository cannot fix by editing its
    # own files (an upstream release it does not own, a comparison with no local
    # basis), and a consumer gate passes a degraded run for exactly that reason.
    # A missing section is repairable in the change that adds the row, and the
    # section is invocation-loaded, so it spends no listing budget and moves no
    # routing: nothing the description phrase's separate gate protects against
    # applies to it.
    unbaked_boundary = [
        _row_label(row, index)
        for index, row in enumerate(rows)
        if row["verdict"] != "defer"
        and row["observation"]["class"] == "extraction"
        and row["component"].get("kind") != "agent"
        and not row["baked"]["boundary_section"]
    ]
    if unbaked_boundary:
        problems.append(
            f"{len(unbaked_boundary)} non-defer extraction row(s) carry no Boundary "
            "section in their component (the verdict is recorded but the model never "
            "reads it; the section lands with the row, in the same change): "
            f"{', '.join(unbaked_boundary)}"
        )

    recorded = sorted(
        {
            match.group(1)
            for row in rows
            if row["observation"]["class"] == "extraction"
            for match in [VERSION_RE.search(row["observation"]["detail"])]
            if match
        }
    )
    if args.cli_version:
        current, how = args.cli_version, "--cli-version"
    else:
        current, how = current_cli_version()
    if current is None:
        advisories.append(
            f"CLI version comparison not locally decidable ({how}); the recorded "
            f"extraction version(s) {', '.join(recorded) or 'none'} were not checked"
        )
    elif not recorded:
        advisories.append(
            f"no extraction-evidence row records a version to compare against {current}"
        )
    else:
        stale = [version for version in recorded if version != current]
        if stale:
            advisories.append(
                f"recorded extraction version(s) {', '.join(stale)} differ from the "
                f"current build {current} (read via {how}); rows sourced from them are "
                "stale-but-honest until re-derived"
            )

    recorded_shas = sorted(
        {
            match.group(0)
            for row in rows
            if row["observation"]["class"] == "upstream-source"
            for match in [UPSTREAM_SHA_RE.search(row["observation"]["detail"])]
            if match
        }
    )
    if recorded_shas:
        # Mirrors the --cli-version seam: the registry never fetches upstream
        # itself, so without the flag the comparison is honestly undecidable.
        # The flag repeats, one value per upstream repository the store cites
        # (a changelog commit in one repository, a plugin commit in another),
        # and a recorded commit matches when any provided value matches it.
        current_shas: list[str] = []
        for raw in args.upstream_sha or []:
            candidate = raw.strip().lower()
            if not re.fullmatch(r"[0-9a-f]{8,40}", candidate):
                # A malformed value must not silently pass: an empty or short
                # prefix would match every recorded SHA via startswith.
                advisories.append(
                    f"--upstream-sha {raw!r} is not an 8-40 character "
                    "hex commit prefix; the recorded upstream commit(s) "
                    f"{', '.join(recorded_shas)} were not checked against it"
                )
                continue
            current_shas.append(candidate)
        if current_shas:
            drifted = [
                sha
                for sha in recorded_shas
                if not any(
                    sha.startswith(current) or current.startswith(sha)
                    for current in current_shas
                )
            ]
            if drifted:
                advisories.append(
                    f"recorded upstream commit(s) {', '.join(drifted)} differ from "
                    f"--upstream-sha {', '.join(current_shas)}; rows sourced from them "
                    "are stale-but-honest until re-derived"
                )
        elif not args.upstream_sha:
            advisories.append(
                "upstream commit comparison not locally decidable (no --upstream-sha); "
                f"the recorded upstream commit(s) {', '.join(recorded_shas)} were not "
                "checked"
            )

    if problems:
        for problem in problems:
            _fail(problem)
        print(
            f"SELF-CHECK broken: {len(problems)} problem(s), {len(rows)} row(s) checked"
        )
        return 1
    if advisories:
        for advisory in advisories:
            print(f"advisory: {advisory}")
        print(
            f"SELF-CHECK degraded: {len(advisories)} advisory(ies), {len(rows)} row(s) checked"
        )
        return 3
    print(f"SELF-CHECK ok: {len(rows)} row(s) checked")
    return 0


def cmd_dismiss(args: argparse.Namespace) -> int:
    """Record (or refresh) a human's ruling that a pair is not an overlap."""
    store_path = Path(args.store)
    if not store_path.is_file():
        _fail(f"no store at {store_path}; a dismissal is recorded in an adopted store")
        return 1
    store, error = load_json(store_path)
    if error is not None:
        _fail(error)
        return 1
    problems = validate_store(store)
    if problems:
        for problem in problems:
            _fail(problem)
        return 1
    inventory, error = load_json(Path(args.inventory))
    if error is not None:
        _fail(error)
        return 1
    if not isinstance(inventory, dict) or inventory.get("schema") != INVENTORY_SCHEMA:
        _fail(f"inventory `schema` must be {INVENTORY_SCHEMA}")
        return 1
    seen = build_native_index(inventory, _lane_payloads(inventory)).get(args.native)
    if seen is None:
        _fail(
            f"`{args.native}` is absent from this extraction; a dismissal fingerprints "
            "the native registration text, so the surface must be observed"
        )
        return 1
    if not NATIVE_NAME_RE.fullmatch(args.native):
        _fail(f"--native must match {NATIVE_NAME_RE.pattern}")
        return 1
    reason = args.reason.strip()
    if not reason or len(reason) > REASON_MAX:
        _fail(f"--reason must be 1 to {REASON_MAX} characters, got {len(reason)}")
        return 1
    plugin, _sep, skill = args.component.partition(":")
    if not valid_segment(plugin) or not valid_segment(skill):
        _fail(
            "--component must be <plugin>:<name>, each segment matching "
            f"{SEGMENT_RE.pattern}"
        )
        return 1
    repo = Path(args.repo).resolve()
    group = "agents" if args.kind == "agent" else "skills"
    if f"{plugin}:{skill}" not in scan_components(repo)[group]:
        _fail(f"component {plugin}:{skill} ({args.kind}) is not in this repo")
        return 1
    path = component_path(repo, plugin, skill, args.kind)
    try:
        frontmatter, _body = split_frontmatter(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError):
        _fail(f"component {plugin}:{skill} ({args.kind}) is unreadable")
        return 1
    component = {"plugin": plugin, "skill": skill, "kind": args.kind}
    key = pair_key(args.native, component)
    if any(pair_key(r["native"]["name"], r["component"]) == key for r in store["rows"]):
        _fail(
            f"{args.native} -> {args.component} already has a verdict row; a ruled "
            "overlap is never dismissed (change the row instead)"
        )
        return 1
    as_of = str(
        args.as_of or (inventory.get("integrity") or {}).get("cli_version") or ""
    ).strip()
    entry = {
        "native": {"name": args.native, "class": seen["class"]},
        "component": component,
        "reason": reason,
        "as_of": as_of,
        "date": (args.date or datetime.date.today().isoformat()).strip(),
        "fingerprint": {
            "native": fingerprint(
                discover.scored_text(registrations_of(seen["entry"]))
            ),
            "component": fingerprint(frontmatter_description(frontmatter)),
        },
    }
    previous = store.get("dismissals") or []
    dismissals = [
        d for d in previous if pair_key(d["native"]["name"], d["component"]) != key
    ]
    dismissals.append(entry)
    dismissals.sort(key=lambda d: pair_key(d["native"]["name"], d["component"]))
    store["dismissals"] = dismissals
    problems = validate_store(store)
    if problems:
        for problem in problems:
            _fail(problem)
        return 1
    store_path.write_text(
        json.dumps(store, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    action = "refreshed" if len(dismissals) == len(previous) else "recorded"
    print(
        f"{action} dismissal {args.native} -> {args.component} ({args.kind}) in "
        f"{store_path}; run `overlap.py generate`"
    )
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser(default_repo: Path, default_pairs: Path) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Native-overlap detection, registry generation, and freshness self-check "
            "(exit 0 ok, 1 broken, 3 degraded; 2 is argparse's usage error)."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_paths(sub: argparse.ArgumentParser) -> None:
        sub.add_argument(
            "--repo",
            default=str(default_repo),
            help="repository root to scan (default: cwd)",
        )
        sub.add_argument(
            "--store",
            default=None,
            help="verdict/record store (default: <repo>/docs/native-surfaces/records.json)",
        )
        sub.add_argument(
            "--view",
            default=None,
            help="generated registry view (default: <repo>/docs/native-surfaces.md)",
        )

    detect = subparsers.add_parser(
        "detect", help="emit overlap candidates (never verdicts)"
    )
    detect.add_argument("--inventory", required=True, help="inventory.py JSON output")
    detect.add_argument(
        "--pairs", default=str(default_pairs), help="seeded canonical-pairs JSON"
    )
    detect.add_argument(
        "--out", help="write the candidate report here instead of stdout"
    )
    detect.add_argument(
        "--threshold",
        type=float,
        default=discover.DEFAULT_THRESHOLD,
        help=(
            "lowest similarity score a discovered pair needs, 0-1 "
            f"(default: {discover.DEFAULT_THRESHOLD})"
        ),
    )
    detect.add_argument(
        "--top-k",
        type=int,
        default=discover.DEFAULT_TOP_K,
        help=(
            "most discovered components kept per native surface; 0 turns "
            f"discovery off (default: {discover.DEFAULT_TOP_K})"
        ),
    )
    add_paths(detect)

    generate = subparsers.add_parser(
        "generate", help="render the store into the registry view"
    )
    generate.add_argument(
        "--check", action="store_true", help="fail on drift instead of writing"
    )
    add_paths(generate)

    self_check = subparsers.add_parser(
        "self-check",
        help="deterministic freshness gate over store, view, and baked lines",
    )
    self_check.add_argument(
        "--cli-version",
        default=None,
        help=(
            "compare recorded extraction versions against this value instead of probing "
            "`claude --version` (test and offline-CI seam; neither path ever re-extracts "
            "the binary)"
        ),
    )
    self_check.add_argument(
        "--upstream-sha",
        action="append",
        default=None,
        help=(
            "compare upstream-source rows' recorded commits against this SHA; repeat "
            "the flag once per upstream repository the store cites (offline seam; the "
            "registry never fetches upstream itself - without the flag the comparison "
            "is reported as not locally decidable)"
        ),
    )
    add_paths(self_check)

    dismiss = subparsers.add_parser(
        "dismiss",
        help=(
            "record a human's ruling that a candidate pair is not an overlap; detect "
            "suppresses it until either side's description changes"
        ),
    )
    dismiss.add_argument("--inventory", required=True, help="inventory.py JSON output")
    dismiss.add_argument("--native", required=True, help="native surface name")
    dismiss.add_argument(
        "--component", required=True, help="our component as <plugin>:<name>"
    )
    dismiss.add_argument("--kind", choices=COMPONENT_KINDS, default="skill")
    dismiss.add_argument(
        "--reason", required=True, help="one line: why the pair is not an overlap"
    )
    dismiss.add_argument(
        "--as-of",
        default=None,
        help="Claude Code version ruled against (default: the inventory's cli_version)",
    )
    dismiss.add_argument(
        "--date", default=None, help="ruling date, YYYY-MM-DD (default: today)"
    )
    add_paths(dismiss)
    return parser


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(
            f"python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required, running "
            f"{'.'.join(str(part) for part in sys.version_info[:3])}",
            file=sys.stderr,
        )
        return 1

    here = Path(__file__).resolve().parent
    default_pairs = here.parent / "reference" / "canonical-pairs.json"
    parser = build_parser(Path.cwd(), default_pairs)
    args = parser.parse_args(argv)

    repo = Path(args.repo)
    if args.store is None:
        args.store = str(repo / "docs" / "native-surfaces" / "records.json")
    if args.view is None:
        args.view = str(repo / "docs" / "native-surfaces.md")

    if args.command == "detect":
        return cmd_detect(args)
    if args.command == "generate":
        return cmd_generate(args)
    if args.command == "dismiss":
        return cmd_dismiss(args)
    return cmd_self_check(args)


if __name__ == "__main__":
    sys.exit(main())
