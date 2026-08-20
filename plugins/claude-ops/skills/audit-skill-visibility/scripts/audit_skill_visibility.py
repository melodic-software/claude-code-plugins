#!/usr/bin/env python3
"""Skill-visibility audit: can the model see each skill, and if not, why.

Claude Code budgets the model-visible skill listing at a fraction of the context
window and, on overflow, drops descriptions starting with the skills you invoke
least. A skill at zero usage loses its description, loses the keywords a request
would match against, and stays at zero. This engine separates skills suppressed
by that loop from skills genuinely not wanted -- and, above all, from skills it
simply cannot see.

The third category is the point. A usage store that is younger than the window
being asked about cannot distinguish "never invoked" from "never observed", and
reporting the second as the first libels most of a fleet on a fresh install.
Every verdict here is therefore gated by the horizon of the source backing it,
and a claim the data cannot support is withheld with its reason rather than
guessed.

`classify` is pure: it takes the fleet, the events, the config, an injected
clock, and per-source horizons, and returns a model. Nothing inside reads the
wall clock, the filesystem, or the environment -- which is what makes the
failure modes above testable at all.

Three independent fields per skill: `reachability` (can the model select it),
`observation` (what was actually recorded, horizon-qualified), and `starvation`
(is it losing the description-budget contest). They are kept orthogonal because
collapsing them produces the libel above -- "cannot be selected" and "has not
been seen" demand opposite actions.

Run it live (the default) and it collects from the installation: the fleet and
its frontmatter by walking a plugins root, the native counters from
`~/.claude.json`, and the plugin's own store when its path is supplied. Each
source is optional -- a missing one narrows the reported tier rather than
failing the run. `--fixture` replays a prepared bundle instead, for tests and
reproductions.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime

MIN_PYTHON = (3, 11)

SCHEMA_VERSION = "1.0.0"


@dataclass(frozen=True)
class Config:
    """Windows and floors. All in days.

    `exposure_floor_days` is the minimum observable span before ANY cold verdict
    is rendered; below it every row is `not-observable`. Named for what it
    guards rather than for its number, because the number is tunable and the
    guard is not.
    """

    active_days: int = 30
    dormant_days: int = 90
    exposure_floor_days: int = 30


def is_usage_evidence(entry: dict) -> bool:
    """True only when a counter entry evidences an actual invocation.

    `pluginUsage` rows are seeded at install with `usageCount: 0` and a current
    `lastUsedAt`; on this machine 46 of 65 plugins looked "used today" while
    none had been used. `lastUsedAt` alone is therefore never evidence -- the
    count is the gate.
    """
    return int(entry.get("usageCount", 0) or 0) > 0


# What each tier can actually answer. A claim is rendered only where it is
# supported -- the alternative is a report whose confidence silently varies with
# whichever sources happened to be present on the machine.
TIER_CAPABILITIES = {
    "T-full": {"invocation_trigger", "windowed_count", "per_repo", "lifetime_count"},
    "T-local": {"windowed_count", "per_repo", "lifetime_count"},
    # Native counters are lifetime-since-install and never windowed, so no
    # windowed claim is honest at this tier.
    "T-baseline": {"lifetime_count"},
    "T-none": set(),
}

REDACTED_SKILL_NAME = "custom_skill"


def resolve_tier(sources: set[str]) -> str:
    """Richest tier the present sources can support."""
    if "otel" in sources:
        return "T-full"
    if "jsonl" in sources:
        return "T-local"
    if "native" in sources:
        return "T-baseline"
    return "T-none"


def tier_supports(tier: str, claim: str) -> bool:
    return claim in TIER_CAPABILITIES.get(tier, set())


def parse_native(
    skill_usage: dict, first_start: datetime
) -> tuple[list[dict], datetime]:
    """Native `~/.claude.json` counters -> events.

    Horizon is `firstStartTime`: these counters cannot see before the config
    file existed. Rows are gated on `usageCount > 0` because `lastUsedAt` alone
    is an install stamp, not evidence of use.
    """
    events: list[dict] = []
    for name, entry in (skill_usage or {}).items():
        if not is_usage_evidence(entry):
            continue
        stamp = entry.get("lastUsedAt")
        if stamp is None:
            continue
        events.append(
            {
                "skill": name,
                "ts": datetime.fromtimestamp(stamp / 1000, tz=UTC),
                "source": "native",
                "count": int(entry.get("usageCount", 0)),
            }
        )
    return events, first_start


def parse_jsonl(rows: list[str]) -> tuple[list[dict], datetime | None]:
    """The plugin's own `skill-usage.jsonl` -> events.

    A malformed row is skipped rather than fatal: this is an observability
    store, and one bad line must not cost the whole report.
    """
    events: list[dict] = []
    for raw in rows:
        try:
            record = json.loads(raw)
        except (ValueError, TypeError):
            continue
        if not record.get("skill") or not record.get("ts"):
            continue
        events.append(
            {
                "skill": record["skill"],
                "ts": _parse_ts(record["ts"]),
                "source": "jsonl",
                "count": 1,
                "emitter": record.get("source"),
                "project_id": record.get("project_id"),
            }
        )
    horizon = min((e["ts"] for e in events), default=None)
    return events, horizon


def parse_otel(records: list[dict]) -> tuple[list[dict], datetime | None]:
    """`claude_code.skill_activated` -> events, carrying invocation_trigger.

    `custom_skill` is the redaction placeholder for user-defined and
    third-party skills, not a skill name. Attributing it would pile every
    third-party skill's usage onto one fictional row, so such events are flagged
    and left unattributed.
    """
    events: list[dict] = []
    for record in records:
        name = record.get("skill.name")
        redacted = name == REDACTED_SKILL_NAME
        events.append(
            {
                "skill": None if redacted else name,
                "redacted": redacted,
                "ts": _parse_ts(record["ts"]),
                "source": "otel",
                "count": 1,
                "invocation_trigger": record.get("invocation_trigger"),
            }
        )
    horizon = min((e["ts"] for e in events), default=None)
    return events, horizon


def parse_frontmatter(text: str) -> dict:
    """Minimal YAML-frontmatter read for the fields reachability needs.

    Deliberately not a YAML parser: this reads five scalar keys out of a fenced
    block, and anything it cannot parse is reported as `_malformed` rather than
    guessed. A real parser would be a third-party dependency the sibling engines
    do not take, and a wrong-but-confident parse is worse here than an honest
    "cannot tell" -- `misconfigured` is a fix-me, not a delete-me.
    """
    if not text.startswith("---"):
        return {"_malformed": True}
    end = text.find("\n---", 3)
    if end == -1:
        return {"_malformed": True}
    block = text[3:end]

    out: dict = {}
    key = None
    for raw in block.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[:1] not in (" ", "\t") and ":" in raw:
            key, _, value = raw.partition(":")
            key = key.strip()
            value = value.strip()
            if value:
                out[key] = value.strip('"').strip("'")
                key = None
        elif key and raw.strip():
            # A folded/continued scalar; keep the first line's worth.
            out.setdefault(key, raw.strip().strip('"').strip("'"))
            key = None
    if not out:
        return {"_malformed": True}

    return {
        "description": out.get("description", ""),
        "when_to_use": out.get("when_to_use", ""),
        "disable_model_invocation": str(
            out.get("disable-model-invocation", out.get("disable_model_invocation", ""))
        ).lower()
        == "true",
        "user_invocable": out.get("user-invocable", out.get("user_invocable", "")),
    }


def collect_fleet(plugins_root: str) -> list[dict]:
    """Walk a plugins root into denominator entries with frontmatter attached.

    `inventory.py` owns "what is installed" but emits bare leaf names with no
    frontmatter and no paths, so reachability cannot be answered from it alone
    (a gap the design recorded). This walk supplies the frontmatter for the
    skills it finds; it does not re-implement enablement, which stays `None` ->
    `unknown` until a source can answer it.
    """
    import os

    entries: list[dict] = []
    if not os.path.isdir(plugins_root):
        return entries
    for plugin in sorted(os.listdir(plugins_root)):
        entries += collect_fleet_at(os.path.join(plugins_root, plugin), plugin)
    return entries


def collect_fleet_at(plugin_root: str, plugin: str) -> list[dict]:
    """Walk ONE plugin directory into denominator entries.

    Split out of `collect_fleet` because the installed manifest resolves each
    plugin to its own root: the installs are scattered across versioned cache
    paths rather than sitting side by side under a single parent, so there is
    no one directory to walk for a real installation.
    """
    import os

    entries: list[dict] = []
    skills_dir = os.path.join(plugin_root, "skills")
    if not os.path.isdir(skills_dir):
        return entries
    for leaf in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, leaf, "SKILL.md")
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as handle:
                frontmatter = parse_frontmatter(handle.read())
        except OSError:
            frontmatter = {"_malformed": True}
        entries.append(
            {
                "qualified_name": f"{plugin}:{leaf}",
                "source": "plugin",
                # Enablement is not knowable from the filesystem alone, and
                # guessing it would libel a disabled plugin's skills.
                "plugin_enabled": None,
                "frontmatter": frontmatter,
                "path": path,
            }
        )
    return entries


# Scope precedence, highest first. NOT a guess and NOT re-derived here: the
# rule is stated in this same plugin's
# `skills/plugins/context/scope-semantics.md`, which verified it against the
# official plugins-reference docs -- "the record that actually loads for a
# given directory is the one at the highest-precedence scope present, never
# simply 'the newest version installed.'"
SCOPE_PRECEDENCE = ("local", "project", "user")


def _scope_rank(scope: str) -> int:
    try:
        return SCOPE_PRECEDENCE.index(scope)
    except ValueError:
        return len(SCOPE_PRECEDENCE)


def _install_applies(entry: dict, current_project: str | None) -> bool:
    """Can this install record load for the project being audited?

    `user` scope always applies. `project` and `local` records carry the
    `projectPath` they belong to and load ONLY there -- a project-scope record
    for a different repository is real state, but it cannot load here, so
    counting its skills would inflate the denominator with a fleet the model
    can never see.
    """
    scope = entry.get("scope", "")
    if scope not in ("project", "local"):
        return True
    if not current_project:
        return False
    return os.path.normpath(entry.get("projectPath") or "") == os.path.normpath(
        current_project
    )


def _catalog_source(marketplace_entry: dict, plugin: str) -> str:
    """Where a directory-source marketplace declares this plugin lives.

    The catalog (`.claude-plugin/marketplace.json`) gives each plugin a
    `source` path relative to the marketplace root. `plugins/<name>` is the
    common layout but not a rule -- an entry may declare `.` or any other
    directory -- so the declared value wins and the conventional layout is
    only the fallback for a catalog that could not be read.
    """
    for row in marketplace_entry.get("_catalog") or []:
        if isinstance(row, dict) and row.get("name") == plugin:
            source = row.get("source")
            if isinstance(source, str) and source:
                return source
            break
    return os.path.join("plugins", plugin)


def resolve_installed(
    manifest: dict, marketplaces: dict, current_project: str | None = None
) -> dict:
    """Resolve an installed-plugin manifest into ONE entry per plugin identity.

    Pure: takes the two parsed JSON blobs, touches no filesystem, so the
    resolution rules are testable without a populated install.

    The manifest lists one entry per (plugin, scope), NOT one per plugin. On
    the machine this was written against, 67 plugins carried 134 entries -- a
    `project` and a `user` install of the same marketplace, bound to the same
    projectPath. Summing them would double the fleet, and because the fleet is
    the denominator the listing budget is measured against, a doubled fleet
    roughly doubles the reported overflow. That is the same class of error the
    usage sources already guard against by reconciling rather than summing.

    Where the scopes disagree the honest answer is not to pick. Measured on
    that same install: 7 plugins carried DIFFERENT skill sets between scopes
    and 19 skills carried different `description` text, so the choice moves
    real numbers. One case resolves cleanly and is marked `certain`: a
    marketplace whose source is a local `directory` loads from that directory,
    verified by a skill executing out of the marketplace checkout rather than
    either cache path. Everything else is reported `ambiguous` with both
    candidates named, so the reader sees the fork instead of inheriting a
    silent guess.
    """
    resolved: list[dict] = []
    superseded: list[dict] = []
    not_applicable: list[dict] = []
    entry_count = 0
    for key, installs in sorted((manifest.get("plugins") or {}).items()):
        if not installs:
            continue
        entry_count += len(installs)
        name, _, market = key.partition("@")
        entry = (marketplaces or {}).get(market) or {}
        location = entry.get("installLocation")

        applicable = [e for e in installs if _install_applies(e, current_project)]
        if not applicable:
            # Every record is a project/local install belonging to a DIFFERENT
            # project. Real state, but it cannot load here, so it is reported
            # and excluded rather than counted into the denominator.
            not_applicable.append(
                {
                    "plugin": name,
                    "marketplace": market,
                    "scopes": sorted(
                        {e.get("scope", "unknown") for e in installs},
                    ),
                }
            )
            continue

        winner = min(
            applicable,
            key=lambda e: (_scope_rank(e.get("scope", "")), e.get("scope", "")),
        )
        # A directory-source marketplace loads the CHECKOUT, so neither cached
        # record is what runs and a "loads project X, superseding user Y" line
        # would name two versions that are both beside the point.
        from_directory = (entry.get("source") or {}).get(
            "source"
        ) == "directory" and bool(location)
        losers = [e for e in applicable if e is not winner]
        if losers and not from_directory:
            superseded.append(
                {
                    "plugin": name,
                    "marketplace": market,
                    "winner": {
                        "scope": winner.get("scope", "unknown"),
                        "version": winner.get("version", ""),
                    },
                    "superseded": [
                        {
                            "scope": e.get("scope", "unknown"),
                            "version": e.get("version", ""),
                        }
                        for e in losers
                    ],
                }
            )

        # A directory-source marketplace loads from the checkout rather than
        # from the cached installPath, so the catalog -- not a hardcoded
        # layout -- names where each plugin lives. `source` there is a path
        # relative to installLocation; a plugin may legitimately declare `.`
        # or a custom directory, so guessing `plugins/<name>` would silently
        # miss it.
        root = winner.get("installPath", "")
        scope = winner.get("scope", "unknown")
        version = winner.get("version", "")
        if from_directory:
            declared = _catalog_source(entry, name)
            root = os.path.normpath(os.path.join(location, declared))
            # The checkout is the code; the cached versions describe copies
            # that are not being loaded, so neither is reported as running.
            scope, version = "marketplace-directory", ""

        resolved.append(
            {
                "plugin": name,
                "marketplace": market,
                "root": root,
                "scope": scope,
                "version": version,
            }
        )

    return {
        "plugins": resolved,
        # Same plugin, several applicable scopes: resolved by the documented
        # precedence rule, and the losing records are reported so the reader
        # can see a project pin being outranked rather than wonder why a
        # version they installed is not the one measured.
        "superseded": superseded,
        # Project/local records owned by another project. Excluded from the
        # denominator because they cannot load here.
        "not_applicable": not_applicable,
        # Both numbers are reported so the collapse is auditable: a reader can
        # see that N installs became M plugins rather than trusting that it did.
        "manifest_entries": entry_count,
        "plugins_resolved": len(resolved),
    }


def collect_installed(
    plugins_dir: str, current_project: str | None = None
) -> tuple[list[dict], dict]:
    """Read the installed manifest + marketplace registry into a denominator.

    Returns the denominator entries and the resolution report, so the caller
    can surface superseded and inapplicable records rather than absorbing them.
    """

    def _load_json(path: str) -> dict:
        try:
            with open(path, encoding="utf-8") as handle:
                blob = json.load(handle)
        except (OSError, ValueError):
            return {}
        return blob if isinstance(blob, dict) else {}

    def _load(name: str) -> dict:
        return _load_json(os.path.join(plugins_dir, name))

    marketplaces = _load("known_marketplaces.json")
    # Attach each directory-source marketplace's catalog so the resolver can
    # honour the plugin's DECLARED source path instead of assuming a layout.
    for entry in marketplaces.values():
        if not isinstance(entry, dict):
            continue
        location = entry.get("installLocation")
        if (entry.get("source") or {}).get("source") == "directory" and location:
            catalog = _load_json(
                os.path.join(location, ".claude-plugin", "marketplace.json")
            )
            entry["_catalog"] = catalog.get("plugins") or []

    resolution = resolve_installed(
        _load("installed_plugins.json"), marketplaces, current_project
    )
    denominator: list[dict] = []
    for row in resolution["plugins"]:
        denominator += collect_fleet_at(row["root"], row["plugin"])
    return denominator, resolution


def collect_native(claude_json_path: str) -> tuple[list[dict], datetime | None]:
    """Read `~/.claude.json` -> events + horizon, or nothing if absent."""
    try:
        with open(claude_json_path, encoding="utf-8") as handle:
            blob = json.load(handle)
    except (OSError, ValueError):
        return [], None
    first_start = blob.get("firstStartTime")
    if not first_start:
        return [], None
    return parse_native(blob.get("skillUsage") or {}, _parse_ts(first_start))


def collect_jsonl(store_path: str) -> tuple[list[dict], datetime | None]:
    """Read the plugin's own skill-usage store, if it exists."""
    try:
        with open(store_path, encoding="utf-8") as handle:
            return parse_jsonl(handle.read().splitlines())
    except OSError:
        return [], None


COMPONENT = "audit-skill-visibility"

# One safe path segment. Mirrors the pattern lib/state-key.sh validates its own
# output against, so a hand-supplied key is held to the same bar as a derived
# one. `..` cannot match: the first character class excludes `.`.
SAFE_KEY_SEGMENT = re.compile(r"[a-z0-9][a-z0-9._-]*")


def report_path(data_root: str, state_key: str, stamp: str) -> str:
    """Where one run's JSON lands, per the plugin-data-report-keying convention.

    ``<data_root>/<component>/<state-key>/<stamp>.json`` -- one file per RUN,
    never a rolling ``latest.json``. ``${CLAUDE_PLUGIN_DATA}`` alone carries no
    project, worktree, or session segment, so a fixed filename there is one file
    per MACHINE: every repo overwrites the last, and a read-back can serve one
    project's findings as another's.

    Both inputs are required rather than defaulted. In a skill-spawned
    subprocess ``CLAUDE_PLUGIN_DATA`` was observed pointing at an *unrelated*
    installed plugin's data directory, so an empty value must fail loudly here
    rather than silently write somewhere surprising.
    """
    if not data_root:
        raise ValueError(
            "data_root is required: CLAUDE_PLUGIN_DATA is not a dependable "
            "per-plugin signal in a skill subprocess and must be resolved "
            "explicitly by the caller"
        )
    if not state_key:
        raise ValueError(
            "state_key is required: without it every run from every repository "
            "overwrites the last"
        )

    # The key becomes DIRECTORY COMPONENTS, and `makedirs` will happily build
    # whatever it is told to. `strip('/')` only trims the ends, so a value like
    # `../../../tmp/evil` would escape the plugin's namespace entirely and turn
    # a report writer into an arbitrary-directory-creation primitive.
    #
    # `lib/state-key.sh` already validates the identities it produces against a
    # strict segment pattern for exactly this reason, and `clean.sh` rejects the
    # same shape in `--skill-usage-dir`. A caller-supplied key gets the same
    # treatment here rather than trusting every future caller to pre-sanitize.
    segments = [s for s in state_key.strip("/").split("/") if s]
    if not segments or not all(SAFE_KEY_SEGMENT.fullmatch(s) for s in segments):
        raise ValueError(
            "state_key must be '/'-separated segments of [a-z0-9][a-z0-9._-]* "
            f"(got: {state_key!r}) — produce it with lib/state-key.sh"
        )
    return f"{data_root.rstrip('/')}/{COMPONENT}/{'/'.join(segments)}/{stamp}.json"


def append_history(path: str, entry: dict) -> None:
    """Append one line to the run history. Never rewrites prior lines."""
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, sort_keys=True) + "\n")


def read_churn(repo_root: str, rel_path: str, follow: bool = True) -> dict | None:
    """Authoring churn for one file, from git history.

    Two mechanics are deliberate, and both were verified defects during design:

    - **`--follow`**, because a rename severs a path's history and this repo
      demonstrably ports skills between plugins. Without it a ported skill
      reports only the commits since its move.
    - **committer date, never filesystem mtime.** In a fresh clone every file's
      mtime is the checkout time, which would report the whole fleet as authored
      today.

    Returns ``None`` -- blank, not zero -- when the path has no history here. A
    skill authored in another repo has no measurement; it has not been "touched
    zero times".
    """
    import subprocess

    args = ["git", "-C", repo_root, "log", "--format=%cI"]
    if follow:
        args.append("--follow")
    args += ["--", rel_path]
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=False)
    except OSError:
        return None
    if result.returncode != 0:
        return None
    dates = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not dates:
        return None
    return {"commits": len(dates), "authored_at": dates[0]}


@dataclass(frozen=True)
class ListingConfig:
    """Inputs to the skill-listing budget, all documented.

    `bytes_per_token` is the product's own hardcoded estimate; the budget is
    computed in CHARACTERS, not tokens.
    """

    context_window_tokens: int = 200_000
    budget_fraction: float = 0.01
    max_desc_chars: int = 1536
    bytes_per_token: int = 4
    # The literal " - " the harness inserts between description and when_to_use.
    joiner_chars: int = 3
    env_char_budget: int | None = None


def listing_budget_chars(cfg: ListingConfig) -> int:
    """Budget in characters -- DERIVED, never a constant.

    The familiar "8,000" is this formula at a 200k-token window; a 1M-token
    model gets ~40,000. Hardcoding 8,000 would be wrong for most current models,
    and hardcoding it as a floor would be wrong too, because
    `SLASH_COMMAND_TOOL_CHAR_BUDGET` overrides everything unconditionally.
    """
    if cfg.env_char_budget is not None:
        return cfg.env_char_budget
    return max(
        1, int(cfg.context_window_tokens * cfg.budget_fraction * cfg.bytes_per_token)
    )


def _eligibility(entry: dict) -> str:
    """Which skills actually contend for description budget.

    Three exempt classes, and the third is easy to miss: a
    `disable-model-invocation` skill keeps its description out of the model's
    context entirely, so it spends none of the shared budget. Locally that is 59
    of 213 skills -- counting them would inflate the overflow figure enough to
    flip the headline verdict.
    """
    frontmatter = entry.get("frontmatter") or {}
    if entry.get("source") == "bundled":
        return "exempt-bundled"
    if frontmatter.get("skill_override") == "name-only":
        return "exempt-name-only"
    if frontmatter.get("disable_model_invocation"):
        return "exempt-user-only"
    return "competing"


def _demand_chars(entry: dict, cfg: ListingConfig) -> int:
    """Characters one skill contributes to the listing.

    The harness inserts a literal " - " between `description` and `when_to_use`,
    so a two-field entry costs three characters more than the concatenation.
    `skill-quality/scripts/check-listing-budget.sh` models the same joiner as
    `JOINER_CHARS=3`; the two implementations are deliberate duplicates (the
    cross-plugin boundary bars importing) and must stay reconciled.
    """
    frontmatter = entry.get("frontmatter") or {}
    description = frontmatter.get("description") or ""
    when_to_use = frontmatter.get("when_to_use") or ""
    joiner = cfg.joiner_chars if (description and when_to_use) else 0
    return min(len(description) + joiner + len(when_to_use), cfg.max_desc_chars)


def compute_listing(denominator: list[dict], cfg: ListingConfig) -> dict:
    """Budget arithmetic, split by confidence.

    CERTAIN: whether the listing overflows and by how much -- pure arithmetic
    over documented settings against summed description lengths.

    INFERENTIAL: which particular skills lose their descriptions. That ordering
    comes from an undocumented scorer pinned to one build, so it is rendered as
    a ranked band and labelled, never as an exact cutoff.
    """
    budget = listing_budget_chars(cfg)

    rows: list[dict] = []
    demand = 0
    for entry in denominator:
        eligibility = _eligibility(entry)
        chars = _demand_chars(entry, cfg) if eligibility == "competing" else 0
        demand += chars
        rows.append(
            {
                "qualified_name": entry["qualified_name"],
                "eligibility": eligibility,
                "demand_chars": chars,
                "usage_score": entry.get("usage_score", 0),
            }
        )

    overflow = max(0, demand - budget)
    verdict = "overflowing" if overflow > 0 else "listing-fits"

    competing = [r for r in rows if r["eligibility"] == "competing"]
    # Least-used first: that is the order the product drops descriptions in, so
    # rank 1 is the most likely to have already lost its description.
    competing.sort(key=lambda r: (r["usage_score"], r["qualified_name"]))
    # Descriptions are dropped least-invoked-first only UNTIL the listing fits,
    # so the starved set is the prefix whose demand covers the overflow -- not
    # the whole fleet. Marking every competing row starved on a one-character
    # overflow would libel exactly the skills the mechanism protects longest,
    # and the renderer would tell the user they are running name-only.
    remaining = overflow
    for rank, row in enumerate(competing, start=1):
        row["band"] = rank if overflow > 0 else None
        row["confidence"] = "inferential" if overflow > 0 else "certain"
        if overflow <= 0:
            row["verdict"] = "listing-fits"
        elif remaining > 0:
            row["verdict"] = "likely-starved"
            remaining -= row["demand_chars"]
        else:
            row["verdict"] = "likely-retained"
    for row in rows:
        if row["eligibility"] != "competing":
            row["band"] = None
            row["verdict"] = "not-assessable"
            row["confidence"] = "certain"

    return {
        "budget_chars": budget,
        "budget_basis": "env-override"
        if cfg.env_char_budget is not None
        else "fraction",
        "demand_chars": demand,
        "overflow_chars": overflow,
        "verdict": verdict,
        "competing_count": len(competing),
        "starved_count": sum(1 for r in competing if r["verdict"] == "likely-starved"),
        "exempt_count": len(rows) - len(competing),
        "skills": rows,
    }


# Remedies are phrased as fixes on purpose. Several of these causes are SILENT
# -- the skill looks fine, can never be selected, and nothing surfaces outside
# --debug -- which makes them read exactly like disuse. Recommending removal for
# a skill that is merely misconfigured is the failure this table prevents.
MISCONFIGURED_REMEDIES = {
    "malformed-frontmatter": (
        "The frontmatter YAML does not parse, so the skill loads with empty "
        "metadata and no description to match against; the parse error surfaces "
        "only under --debug. Fix the YAML."
    ),
    "no-description": (
        "No description, so the listing falls back to the first body paragraph, "
        "which may carry none of the keywords a request would match. Add one."
    ),
}


def reachability(entry: dict) -> dict:
    """Structural: can the model ever select this skill?

    Independent of whether it has been *observed* -- see the module docstring.
    Returns a value plus the causes and evidence behind it, never a bare label,
    because the remedy differs per cause.
    """
    frontmatter = entry.get("frontmatter") or {}
    enabled = entry.get("plugin_enabled")

    causes: list[str] = []
    if frontmatter.get("_malformed"):
        causes.append("malformed-frontmatter")
    elif not frontmatter.get("description"):
        causes.append("no-description")

    if causes:
        return {
            "value": "misconfigured",
            "causes": causes,
            "remedy": " ".join(MISCONFIGURED_REMEDIES[c] for c in causes),
            "evidence": "frontmatter",
            # Provenance matters: this catalogue is assembled from scattered doc
            # sections plus binary strings. There is no official list of reasons
            # a skill is never auto-invoked, and claiming otherwise to a user
            # would cite something that does not exist.
            "provenance": "assembled-from-docs-and-binary, not an official list",
        }

    if frontmatter.get("skill_override") == "off":
        return {
            "value": "hidden",
            "causes": ["skill-override-off"],
            "remedy": "Hidden from both the model and the user by skillOverrides.",
            "evidence": "settings",
            "provenance": "documented",
        }

    if enabled is None:
        # Never guess enablement. An unknown is reported as unknown.
        return {
            "value": "unknown",
            "causes": ["enablement-undetermined"],
            "remedy": "Enablement could not be determined from the available sources.",
            "evidence": None,
            "provenance": "n/a",
        }

    if not enabled:
        return {
            "value": "hidden",
            "causes": ["plugin-not-enabled"],
            "remedy": "The owning plugin is installed but not enabled.",
            "evidence": "plugin_loaded",
            "provenance": "documented",
        }

    if frontmatter.get("disable_model_invocation"):
        # Not a defect and not disuse: the operator typed it by design.
        return {
            "value": "user-only",
            "causes": ["disable-model-invocation"],
            "remedy": "By design: the description is kept out of the model's context.",
            "evidence": "frontmatter",
            "provenance": "documented",
        }

    return {
        "value": "model-reachable",
        "causes": [],
        "remedy": "",
        "evidence": "frontmatter",
        "provenance": "documented",
    }


def _reconcile(events: list[dict]) -> int:
    """Count invocations without summing sources that recorded the same one.

    Native counters and the JSONL store both record the same invocation -- this
    was demonstrated live, with matching sub-second timestamps -- so adding them
    double-counts. But two genuine invocations inside one second are also
    indistinguishable by timestamp, and collapsing those would undercount.

    The rule that satisfies both: at a given instant, take the MAX across
    sources rather than the sum. Two sources reporting one event each yield 1;
    one source reporting two events yields 2.
    """
    by_instant: dict[datetime, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for event in events:
        by_instant[event["ts"]][event.get("source", "unknown")] += int(
            event.get("count", 1)
        )
    return sum(max(per_source.values()) for per_source in by_instant.values())


def classify(
    denominator: list[dict],
    events: list[dict],
    config: Config,
    clock: datetime,
    horizons: dict[str, datetime],
    listing_config: ListingConfig | None = None,
) -> dict:
    """Pure. Fleet + events + config + clock + horizons -> report model."""
    tier = resolve_tier(set(horizons))
    listing = compute_listing(denominator, listing_config or ListingConfig())
    starvation_by_name = {r["qualified_name"]: r for r in listing["skills"]}
    # Narrowest horizon = the most recent start = the least we can see back to.
    # Two different questions, two different horizons.
    #
    # `observed_horizon` is the NARROWEST (most recent start) — it answers "what
    # is the least this run can see", and belongs in the run header.
    #
    # A per-row "nothing was recorded" claim is backed by the WIDEST coverage
    # available, because a source that looked across a year and saw nothing
    # supports the claim regardless of another source's short retention. Gating
    # every row on the narrowest span let a 7-day OTEL retention erase a year of
    # native history and pin the whole fleet to `not-observable`.
    observed_horizon = max(horizons.values()) if horizons else clock
    widest_horizon = min(horizons.values()) if horizons else clock
    observable_days = (clock - widest_horizon).days

    seen: dict[str, int] = defaultdict(int)
    for entry in denominator:
        seen[entry["qualified_name"]] += 1

    events_by_skill: dict[str, list[dict]] = defaultdict(list)
    for event in events:
        events_by_skill[event["skill"]].append(event)

    skills: list[dict] = []
    withheld: list[dict] = []

    for entry in denominator:
        name = entry["qualified_name"]
        own_events = events_by_skill.get(name, [])
        count = _reconcile(own_events)
        last_used = max((e["ts"] for e in own_events), default=None)

        value, backed_by = _observation_value(
            count=count,
            last_used=last_used,
            clock=clock,
            config=config,
            observable_days=observable_days,
            own_events=own_events,
        )

        if value == "not-observable":
            withheld.append(
                {
                    "skill": name,
                    "claim": "observation",
                    "reason": (
                        f"observable span is {observable_days}d, below the "
                        f"{config.exposure_floor_days}d exposure floor"
                    ),
                }
            )

        skills.append(
            {
                "qualified_name": name,
                "attribution": (
                    "ambiguous-attribution" if seen[name] > 1 else "unambiguous"
                ),
                "reachability": reachability(entry),
                # Blank, not zero: a skill authored elsewhere has no
                # measurement, which is a different fact from never-touched.
                "churn": entry.get("churn"),
                "starvation": {
                    k: v
                    for k, v in starvation_by_name.get(name, {}).items()
                    if k != "qualified_name"
                },
                "observation": {
                    "value": value,
                    "count": count,
                    "last_used": last_used.isoformat() if last_used else None,
                    "backed_by": backed_by,
                },
            }
        )

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": clock.isoformat(),
        "observed_horizon": observed_horizon.isoformat(),
        "tier": tier,
        "tier_basis": (
            f"sources present: {', '.join(sorted(horizons)) or 'none'}; "
            f"claims supported: {', '.join(sorted(TIER_CAPABILITIES[tier])) or 'none'}"
        ),
        "listing": {k: v for k, v in listing.items() if k != "skills"},
        "sources": [
            {"source": name, "horizon_start": start.isoformat()}
            for name, start in sorted(horizons.items())
        ],
        "skills": skills,
        "withheld": withheld,
    }


def _observation_value(
    *,
    count: int,
    last_used: datetime | None,
    clock: datetime,
    config: Config,
    observable_days: int,
    own_events: list[dict],
) -> tuple[str, str | None]:
    """Resolve one observation value, refusing any verdict the span cannot back."""
    backed_by = own_events[0].get("source") if own_events else None

    # A span shorter than the floor cannot support a cold verdict at all.
    if observable_days < config.exposure_floor_days and count == 0:
        return "not-observable", backed_by

    if count == 0:
        return "no-observation-in-horizon", backed_by

    age_days = (clock - last_used).days
    # Never render a window wider than the span that could have observed it.
    if age_days <= config.active_days:
        return "active", backed_by
    if observable_days < config.dormant_days:
        return "not-observable", backed_by
    if age_days <= config.dormant_days:
        return "cooling", backed_by
    return "dormant", backed_by


def _plural(count: int, noun: str) -> str:
    """Regular-plural helper for counted nouns in the rendered report.

    A report that says "1 plugins" undercuts the care the rest of it claims,
    and every counted noun here is regular, so the -s rule is sufficient.
    """
    return noun if count == 1 else f"{noun}s"


def _render_markdown(model: dict) -> str:
    lines = [
        "# Skill visibility report",
        "",
        f"- Observed horizon: `{model['observed_horizon']}`",
        f"- Sources: {', '.join(s['source'] for s in model['sources']) or 'none'}",
        f"- Capability tier: `{model.get('tier', 'T-none')}` "
        f"({model.get('tier_basis', '')})",
        f"- Skills: {len(model['skills'])}",
        f"- Withheld claims: {len(model['withheld'])}",
        "",
    ]
    fleet = model.get("fleet")
    if fleet:
        lines += [
            "## Fleet resolution",
            "",
            f"Resolved **{fleet['plugins_resolved']} "
            f"{_plural(fleet['plugins_resolved'], 'plugin')}** from "
            f"{fleet['manifest_entries']} manifest entries — the manifest lists "
            "one entry per install SCOPE, so counting entries would inflate the "
            "fleet and, with it, the listing overflow below.",
            "",
        ]
        superseded = fleet.get("superseded") or []
        if superseded:
            lines += [
                f"**{len(superseded)} "
                f"{_plural(len(superseded), 'plugin')} "
                f"{'is' if len(superseded) == 1 else 'are'} installed at more "
                "than one applicable scope.** Resolved by the documented "
                "precedence `local > project > user` — the record that loads is "
                "the highest-precedence one present, never the newest version "
                "installed. The superseded records are listed so a pin that is "
                "being outranked is visible rather than silently ignored.",
                "",
            ]
            for row in superseded[:10]:
                win = f"{row['winner']['scope']} {row['winner']['version']}".strip()
                lost = ", ".join(
                    f"{c['scope']} {c['version']}".strip() for c in row["superseded"]
                )
                lines += [f"- `{row['plugin']}` — loads **{win}**, superseding {lost}"]
            if len(superseded) > 10:
                lines += [f"- …and {len(superseded) - 10} more"]
            lines += [""]

        inapplicable = fleet.get("not_applicable") or []
        if inapplicable:
            lines += [
                f"**{len(inapplicable)} "
                f"{_plural(len(inapplicable), 'plugin')} excluded**: every "
                "install record is project- or local-scope belonging to a "
                "different project, so it cannot load here. Counting those "
                "would inflate the fleet with skills the model can never see.",
                "",
            ]
            for row in inapplicable[:10]:
                lines += [f"- `{row['plugin']}` — {', '.join(row['scopes'])} elsewhere"]
            if len(inapplicable) > 10:
                lines += [f"- …and {len(inapplicable) - 10} more"]
            lines += [""]

        if not superseded and not inapplicable:
            lines += [
                "Every plugin resolved to a single applicable install.",
                "",
            ]

    listing = model.get("listing", {})
    if listing:
        lines += ["## Listing budget", ""]
        if listing["overflow_chars"] > 0:
            # The certain half: documented settings vs summed description
            # lengths. No undocumented constant is involved, so this is stated
            # plainly rather than hedged.
            lines += [
                f"**Your skill listing is over budget by "
                f"{listing['overflow_chars']:,} characters.** "
                f"{listing['competing_count']} skills compete for "
                f"{listing['budget_chars']:,} characters of description budget, "
                f"and descriptions are dropped least-invoked-first — so roughly "
                f"**{listing['starved_count']}** of them are running name-only, "
                f"which is why the model stops matching requests to those.",
                "",
                f"The other {listing['competing_count'] - listing['starved_count']} "
                f"competing skills keep their descriptions: only enough of the "
                f"least-used tail is dropped to close the gap, not the whole set.",
                "",
                "*Which* particular skills lost theirs is inferential — the ordering",
                "comes from an undocumented scorer. Treat the ranking as a likelihood",
                "band, not a cutoff line.",
                "",
            ]
        else:
            lines += [
                f"Listing fits: {listing['demand_chars']:,} of "
                f"{listing['budget_chars']:,} characters used by "
                f"{listing['competing_count']} competing skills. No description "
                f"is being dropped, so starvation is not the reason any skill "
                f"here goes unused.",
                "",
            ]
        lines += [
            f"- Exempt from the contest: {listing['exempt_count']} "
            f"(bundled, name-only, and user-only skills spend no budget)",
            "",
        ]
    authored = [s for s in model["skills"] if s.get("churn")]
    if authored:
        lines += ["## Authoring churn (cross-reference)", ""]
        # The label is load-bearing. In a public marketplace, skills are
        # authored FOR CONSUMERS, so the author's own non-use of a skill they
        # wrote is the expected case -- not effort thrown away. Reading this
        # quadrant as waste would invert what it means.
        lines += [
            "How much each skill was *authored* here, cross-referenced with how",
            "much it is *used* here. These measure different things: in a",
            "marketplace repo a skill is written for the people who install it,",
            "so high authoring effort beside low local use is the normal case and",
            "not effort thrown away. Read it as a prompt to check the skill is",
            "reachable, not as a scrap heap.",
            "",
            "Skills authored in another repo show blank rather than zero — no",
            "measurement is a different fact from never touched.",
            "",
        ]
        for row in sorted(authored, key=lambda r: -r["churn"]["commits"])[:10]:
            churn = row["churn"]
            lines.append(
                f"- `{row['qualified_name']}` — {churn['commits']} commits, "
                f"last authored {churn['authored_at'][:10]}, "
                f"observation: {row['observation']['value']}"
            )
        lines.append("")

    if model["withheld"]:
        lines += [
            "## Withheld",
            "",
            "Claims this run refused to make, and why. A declined verdict is",
            "reported rather than omitted.",
            "",
        ]
        reasons = {w["reason"] for w in model["withheld"]}
        lines += [f"- {reason}" for reason in sorted(reasons)] + [""]
    return "\n".join(lines)


def _load_fixture(path: str) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _parse_ts(raw: str) -> datetime:
    return datetime.fromisoformat(raw)


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(
            f"error: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required", file=sys.stderr
        )
        return 2

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--fixture",
        help="path to a prepared JSON bundle (tests and reproductions); omit to "
        "collect from the live installation",
    )
    parser.add_argument(
        "--plugins-root",
        help="plugins directory to enumerate (default: ./plugins)",
    )
    parser.add_argument(
        "--installed",
        nargs="?",
        const="",
        metavar="PLUGINS_DIR",
        help="audit the INSTALLED fleet via the plugin manifest rather than a "
        "plugins directory (default dir: ~/.claude/plugins). Resolves one "
        "entry per plugin, never one per install scope",
    )
    parser.add_argument(
        "--claude-json",
        help="path to ~/.claude.json for the native counters",
    )
    parser.add_argument(
        "--skill-usage",
        help="path to a skill-usage.jsonl store (resolve it with the hooks' "
        "scope policy; it is not guessed here)",
    )
    parser.add_argument(
        "--context-window",
        type=int,
        default=200_000,
        help="context window in TOKENS for the listing-budget arithmetic "
        "(default 200000; the budget is derived from this, never hardcoded)",
    )
    parser.add_argument("--render", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--now", help="RFC3339 instant to use as the clock")
    parser.add_argument(
        "--write",
        metavar="DATA_ROOT",
        help=(
            "persist the JSON report under DATA_ROOT, keyed per the "
            "plugin-data-report-keying convention. Pass the root explicitly — "
            "CLAUDE_PLUGIN_DATA is not a dependable per-plugin signal here."
        ),
    )
    parser.add_argument(
        "--state-key",
        help="repo-identity/worktree-discriminator, from lib/state-key.sh",
    )
    args = parser.parse_args(argv)

    resolution: dict | None = None
    if args.fixture:
        bundle = _load_fixture(args.fixture)
        clock = _parse_ts(args.now) if args.now else _parse_ts(bundle["now"])
        horizons = {k: _parse_ts(v) for k, v in bundle.get("horizons", {}).items()}
        events = [dict(e, ts=_parse_ts(e["ts"])) for e in bundle.get("events", [])]
        denominator = bundle["denominator"]
        cfg = Config(**bundle.get("config", {}))
        listing_cfg = ListingConfig(**bundle.get("listing_config", {}))
    else:
        # Live collection. Each source is optional: a missing one narrows the
        # tier rather than failing the run, which is the same honesty the
        # verdicts themselves apply.
        import os

        clock = _parse_ts(args.now) if args.now else datetime.now(tz=UTC)
        if args.installed is not None:
            plugins_dir = args.installed or os.path.expanduser("~/.claude/plugins")
            # CLAUDE_PROJECT_DIR is the project Claude Code itself resolved;
            # cwd is the fallback. Project/local install records are matched
            # against it, since those load only in their own project.
            current_project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
            denominator, resolution = collect_installed(plugins_dir, current_project)
            if not denominator:
                print(
                    f"error: no installed skills resolved from {plugins_dir!r}; "
                    "expected installed_plugins.json there",
                    file=sys.stderr,
                )
                return 2
        else:
            plugins_root = args.plugins_root or os.path.join(os.getcwd(), "plugins")
            denominator = collect_fleet(plugins_root)
            if not denominator:
                print(
                    f"error: no skills found under {plugins_root!r}; "
                    "pass --plugins-root <path> to point at a plugins directory",
                    file=sys.stderr,
                )
                return 2

        events, horizons = [], {}
        native_path = args.claude_json or os.path.expanduser("~/.claude.json")
        native_events, native_horizon = collect_native(native_path)
        if native_horizon:
            events += native_events
            horizons["native"] = native_horizon
        if args.skill_usage:
            jsonl_events, jsonl_horizon = collect_jsonl(args.skill_usage)
            if jsonl_horizon:
                events += jsonl_events
                horizons["jsonl"] = jsonl_horizon

        cfg = Config()
        listing_cfg = ListingConfig(
            context_window_tokens=args.context_window,
            env_char_budget=(
                int(os.environ["SLASH_COMMAND_TOOL_CHAR_BUDGET"])
                if os.environ.get("SLASH_COMMAND_TOOL_CHAR_BUDGET", "").isdigit()
                else None
            ),
        )

    model = classify(
        denominator=denominator,
        events=events,
        config=cfg,
        clock=clock,
        horizons=horizons,
        listing_config=listing_cfg,
    )

    if resolution is not None:
        model["fleet"] = {
            "mode": "installed",
            "manifest_entries": resolution["manifest_entries"],
            "plugins_resolved": resolution["plugins_resolved"],
            "superseded": resolution["superseded"],
            "not_applicable": resolution["not_applicable"],
        }

    if args.write:
        import os

        stamp = clock.strftime("%Y%m%dT%H%M%SZ")
        try:
            path = report_path(args.write, args.state_key or "", stamp)
        except ValueError as exc:
            # A missing key is an operator-fixable mistake, not a crash: say
            # what to run rather than printing a traceback.
            print(f"error: {exc}", file=sys.stderr)
            print(
                'hint: pass --state-key "$(bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh")"',
                file=sys.stderr,
            )
            return 2
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(model, handle, indent=2)
        # One file per run PLUS an appended history line: a rolling latest.json
        # would hand any future scheduled run an overwrite defect on day one.
        append_history(
            os.path.join(os.path.dirname(path), "history.jsonl"),
            {
                "stamp": stamp,
                "tier": model["tier"],
                "skills": len(model["skills"]),
                "withheld": len(model["withheld"]),
                "overflow_chars": model["listing"]["overflow_chars"],
            },
        )
        print(path)
        return 0

    if args.render == "json":
        print(json.dumps(model, indent=2))
    else:
        print(_render_markdown(model))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
