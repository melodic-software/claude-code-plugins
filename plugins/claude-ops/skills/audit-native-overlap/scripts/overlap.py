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

Requires Python 3.11+ and nothing else - stdlib only, matching the sibling
inventory extractor's no-third-party discipline.

EXIT CODES - a deliberate divergence, stated so it never reads as an accident.
The repo's shell gates use 0 clean / 1 findings / 2 usage-or-environment error.
This script instead follows the sibling `inventory.py --self-check` contract,
because a consumer wiring both into one lane needs one taxonomy for "the data
is stale but honest":

  0  ok        - everything checked passed
  1  broken    - a defect the registry owns: malformed store, missing trigger,
                 view drift, baked line with no store row
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
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

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
    "plugin-backed-builtin",
    "session-skill",
)
OBSERVATION_CLASSES = ("extraction", "live-roster")
COMPONENT_KINDS = ("skill", "agent")
NATIVE_MARKERS = ("hidden", "gated")

# Lane order in the generated view: (class, section heading, singular noun used
# in a row's own prose). Provenance classes are never merged into one list -
# they carry different disable switches and different rosters per host.
LANES: tuple[tuple[str, str, str], ...] = (
    ("builtin-command", "Built-in CLI commands", "built-in command"),
    ("bundled-skill", "Bundled skills", "bundled skill"),
    ("plugin-backed-builtin", "Plugin-backed built-ins", "plugin-backed built-in"),
    (
        "session-skill",
        "Session-provided skills (observation-only)",
        "session-provided skill",
    ),
)

# The canonical presence-gate token owned by docs/conventions/native-references.
# A baked description phrase carries it; the reverse-parity scan keys on it.
GATE_TOKEN = "resolves in your session"

START_MARKER = "<!-- native-surfaces:start -->"
END_MARKER = "<!-- native-surfaces:end -->"

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# A trigger that is nothing but a date (however spelled) fails the observability
# bar: a date alone is not an observable event.
BARE_DATE_TRIGGER_RE = re.compile(
    r"^\W*(?:by|after|before|on|from)?\W*\d{4}(?:-\d{2}(?:-\d{2})?)?\W*$", re.IGNORECASE
)
VERSION_RE = re.compile(r"(\d+\.\d+\.\d+)")

VIEW_HEADER = """# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI
— **never hand-edit it**. Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when — see [`docs/conventions/native-references/`](conventions/native-references/README.md).
"""


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)


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


def validate_row(row: Any, index: int) -> list[str]:
    """Well-formedness of one store row. Returns a list of problems."""
    label = _row_label(row, index)
    problems: list[str] = []
    if not isinstance(row, dict):
        return [f"{label}: not an object"]

    native = row.get("native")
    if not isinstance(native, dict):
        problems.append(f"{label}: missing or malformed `native`")
    else:
        if not isinstance(native.get("name"), str) or not native.get("name"):
            problems.append(f"{label}: `native.name` must be a non-empty string")
        if native.get("class") not in NATIVE_CLASSES:
            problems.append(
                f"{label}: `native.class` must be one of {', '.join(NATIVE_CLASSES)}"
            )
        markers = native.get("markers", [])
        if not isinstance(markers, list) or any(
            m not in NATIVE_MARKERS for m in markers
        ):
            problems.append(
                f"{label}: `native.markers` must be a list drawn from "
                f"{', '.join(NATIVE_MARKERS)}"
            )

    component = row.get("component")
    if not isinstance(component, dict):
        problems.append(f"{label}: missing or malformed `component`")
    else:
        for key in ("plugin", "skill"):
            if not isinstance(component.get(key), str) or not component.get(key):
                problems.append(
                    f"{label}: `component.{key}` must be a non-empty string"
                )
        if component.get("kind") not in COMPONENT_KINDS:
            problems.append(
                f"{label}: `component.kind` must be one of {', '.join(COMPONENT_KINDS)}"
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
        if not DATE_RE.match(str(observation.get("date", ""))):
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
        if not DATE_RE.match(str(recheck.get("verified", ""))):
            problems.append(f"{label}: `recheck.verified` must be YYYY-MM-DD")

    baked = row.get("baked")
    if not isinstance(baked, dict) or not all(
        isinstance(baked.get(key), bool)
        for key in ("description_phrase", "boundary_section")
    ):
        problems.append(
            f"{label}: `baked` must carry boolean `description_phrase` and `boundary_section`"
        )
    if not isinstance(row.get("budget_caveat"), bool):
        problems.append(f"{label}: `budget_caveat` must be a boolean")

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
    seen: set[tuple[str, str, str]] = set()
    for index, row in enumerate(rows):
        problems.extend(validate_row(row, index))
        if isinstance(row, dict):
            try:
                key = (
                    row["native"]["name"],
                    row["component"]["plugin"],
                    row["component"]["skill"],
                )
            except (KeyError, TypeError):
                continue
            if key in seen:
                problems.append(f"duplicate row for {key[0]} -> {key[1]}:{key[2]}")
            seen.add(key)
    return problems


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def _escape_cell(text: str) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ").strip()


def render_block(rows: list[dict[str, Any]]) -> str:
    """Render the marker-fenced body: a summary table, then per-lane sections."""
    lines: list[str] = []
    lines.append("## Summary")
    lines.append("")
    lines.append("| Lane | Rows | Baked | Verdicts |")
    lines.append("|---|---|---|---|")
    for lane, heading, _noun in LANES:
        lane_rows = [r for r in rows if r["native"]["class"] == lane]
        baked = sum(
            1
            for r in lane_rows
            if r["baked"]["description_phrase"] or r["baked"]["boundary_section"]
        )
        tally: dict[str, int] = {}
        for row in lane_rows:
            tally[row["verdict"]] = tally.get(row["verdict"], 0) + 1
        verdicts = ", ".join(f"{k} {v}" for k, v in sorted(tally.items())) or "—"
        lines.append(
            f"| {_escape_cell(heading)} | {len(lane_rows)} | {baked} | {_escape_cell(verdicts)} |"
        )
    lines.append("")

    for lane, heading, noun in LANES:
        lane_rows = sorted(
            (r for r in rows if r["native"]["class"] == lane),
            key=lambda r: (
                r["native"]["name"],
                r["component"]["plugin"],
                r["component"]["skill"],
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
            lines.append(f"- **Verdict:** `{row['verdict']}` — {row['reason']}")
            lines.append(
                f"- **Native surface:** `{native['name']}` ({noun}; markers: {markers})"
            )
            lines.append(f"- **Our component:** `{target}` ({component['kind']})")
            lines.append("- **Evidence:**")
            for item in row["evidence"]:
                lines.append(f"  - {item}")
            observation = row["observation"]
            lines.append(
                f"- **Observation:** {observation['class']} — {observation['detail']} "
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
                f"{'yes' if baked['boundary_section'] else 'no'}"
            )
            if row["budget_caveat"]:
                lines.append(
                    "- **Budget caveat:** the baked phrase may be dropped from the skill "
                    "listing under budget pressure — it is the best available routing "
                    "surface, not a guaranteed one"
                )
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_view(
    rows: list[dict[str, Any]], existing: str | None
) -> tuple[str | None, str | None]:
    """Compose the full view text. Returns (text, error)."""
    block = render_block(rows)
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
    Reverse: a description carrying the gate token must have a store row.

    The reverse scan keys on the frontmatter description ONLY. `## Boundary` is
    an organic pattern that predates this registry - several skills carry one
    for reasons the registry has no row for - so a reverse scan on headings
    would flag legitimate prose. The description is the routing-effective
    surface and is the thing this parity exists to protect.
    """
    problems: list[str] = []
    baked_desc: set[tuple[str, str]] = set()

    for index, row in enumerate(rows):
        component = row["component"]
        path = component_path(
            repo, component["plugin"], component["skill"], component["kind"]
        )
        label = _row_label(row, index)
        wants_desc = row["baked"]["description_phrase"]
        wants_boundary = row["baked"]["boundary_section"]
        if not (wants_desc or wants_boundary):
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
        if wants_desc:
            if GATE_TOKEN not in frontmatter:
                problems.append(
                    f"{label}: `baked.description_phrase` is true but the description in "
                    f'{path} carries no presence gate ("{GATE_TOKEN}")'
                )
            else:
                baked_desc.add((component["plugin"], component["skill"]))
        if wants_boundary and not re.search(r"^## Boundary", body, re.MULTILINE):
            problems.append(
                f"{label}: `baked.boundary_section` is true but {path} has no "
                "`## Boundary` section"
            )

    plugins_dir = repo / "plugins"
    if plugins_dir.is_dir():
        for skill_md in sorted(plugins_dir.glob("*/skills/*/SKILL.md")):
            try:
                frontmatter, _ = split_frontmatter(skill_md.read_text(encoding="utf-8"))
            except OSError:
                continue
            if GATE_TOKEN not in frontmatter:
                continue
            plugin = skill_md.parents[2].name
            skill = skill_md.parent.name
            if (plugin, skill) not in baked_desc:
                problems.append(
                    f"{plugin}:{skill} carries a baked presence gate in its description "
                    "with no store row claiming it - every baked line traces to a row "
                    "(a row without a baked line is legal pending-sweep state; the "
                    "reverse is not)"
                )
    return problems


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


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

    integrity = inventory["integrity"]
    status = (
        integrity.get("status", "unknown") if isinstance(integrity, dict) else "unknown"
    )
    components = scan_components(repo)
    known_skills = set(components["skills"])
    known_agents = set(components["agents"])

    native_index: dict[str, dict[str, Any]] = {}
    for name, entry in (inventory.get("bundled_skills") or {}).items():
        native_index[name] = {"class": "bundled-skill", "entry": entry}
    for name, entry in (inventory.get("builtin_commands") or {}).items():
        native_index.setdefault(name, {"class": "builtin-command", "entry": entry})
    for name, plugin in (inventory.get("plugin_backed") or {}).items():
        native_index[name] = {
            "class": "plugin-backed-builtin",
            "entry": {"name": name, "plugin_name": plugin},
        }

    candidates: list[dict[str, Any]] = []
    for pair in pairs_data.get("pairs", []):
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
            entry = seen["entry"]
            if isinstance(entry, dict):
                markers = [m for m in NATIVE_MARKERS if entry.get(m)]
                if markers:
                    evidence.append(f"markers: {', '.join(markers)}")
                if entry.get("aliases"):
                    evidence.append(f"aliases: {', '.join(entry['aliases'])}")
                if entry.get("description"):
                    evidence.append(f"native description: {entry['description']}")
        kind = component.get("kind", "skill")
        pool = known_agents if kind == "agent" else known_skills
        target_present = target in pool
        if not target_present:
            evidence.append(f"target `{target}` not found in the repo tree at {repo}")
        if pair.get("why"):
            evidence.append(f"seeded rationale: {pair['why']}")
        candidates.append(
            {
                "native": {
                    "name": native.get("name"),
                    "class": (seen or {}).get("class", native.get("class")),
                    "seeded_class": native.get("class"),
                    "observed": seen is not None,
                },
                "component": component,
                "component_present": target_present,
                "verdict": None,
                "evidence": evidence,
            }
        )

    report = {
        "schema": 1,
        "repo": str(repo),
        "integrity": {
            "status": status,
            "cli_version": integrity.get("cli_version")
            if isinstance(integrity, dict)
            else None,
            "validated_against": (
                integrity.get("validated_against")
                if isinstance(integrity, dict)
                else None
            ),
            "counts_are": "floors" if status != "ok" else "totals",
        },
        "target_scan": {
            "skills": len(components["skills"]),
            "agents": len(components["agents"]),
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
        print(
            f"degraded: inventory integrity is {status}; every native-side count is a floor",
            file=sys.stderr,
        )
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
    existing = view_path.read_text(encoding="utf-8") if view_path.is_file() else None
    text, error = render_view(rows, existing)
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
        print(f"{view_path} is in sync with {store_path} ({len(rows)} row(s))")
        return 0
    view_path.parent.mkdir(parents=True, exist_ok=True)
    view_path.write_text(text, encoding="utf-8")
    print(f"wrote {view_path} ({len(rows)} row(s))")
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
        text, error = render_view(rows, existing)
        if error is not None:
            problems.append(error)
        elif text != existing:
            problems.append(
                f"{view_path} is out of sync with {store_path}; run `overlap.py generate`"
            )

    problems.extend(check_baked_parity(repo, rows))

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
            help="generated registry view (default: <repo>/docs/NATIVE-SURFACES.md)",
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
    add_paths(self_check)
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
    parser = build_parser(Path(os.getcwd()), default_pairs)
    args = parser.parse_args(argv)

    repo = Path(args.repo)
    if args.store is None:
        args.store = str(repo / "docs" / "native-surfaces" / "records.json")
    if args.view is None:
        args.view = str(repo / "docs" / "NATIVE-SURFACES.md")

    if args.command == "detect":
        return cmd_detect(args)
    if args.command == "generate":
        return cmd_generate(args)
    return cmd_self_check(args)


if __name__ == "__main__":
    sys.exit(main())
