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
import subprocess
import sys
from collections import defaultdict
from collections.abc import Mapping
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime

MIN_PYTHON = (3, 11)

# 1.1.0: `listing` gains `inputs` (settings and environment provenance) and,
# when no window or bytes-per-token pin is given, a `band` array with the
# top-level numbers nulled. Every 1.0.0 field is still present.
SCHEMA_VERSION = "1.2.0"


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


# Claude Code's own listing-budget scorer, mirrored so the starvation band can
# predict which descriptions the product will actually drop. Before this existed
# the band sorted on a field nothing populated, so it rendered alphabetical order
# dressed as usage-informed.
#
# -- Verification stamp (docs/conventions/upstream-drift) ----------------------
# Claim: the product ranks skills for description truncation by
#   `usageCount * max(0.5 ** (daysSinceUse / 7), 0.1)`, sorts that score
#   descending, then walks EVERY competing entry with a running description
#   budget, granting whatever fits and rendering the rest name-only. The walk is
#   greedy first-fit with no early exit, so it is not a score-ordered prefix and
#   description length is a second ranking input.
# Basis: string extraction of `claude.exe`, first at Claude Code 2.1.251 (`zPe`
#   the scorer, `Ymt` the truncator, plus the scorer's two other call sites, the
#   slash-menu top-5 pin and the command-search score boost), then RE-VERIFIED
#   unchanged at 2.1.252 and again at 2.1.263, where the truncation runs in two
#   places with identical semantics (the system-prompt listing, which collects
#   grants, and `budgetTruncatedSkills`, which collects refusals). Evidence in
#   reference/listing-scorer.md, beside this skill.
# As-of: 2026-09-11, re-verified against Claude Code 2.1.263.
# Locate it by SHAPE, never by name. The minified identifier is not stable across
#   builds: the scorer was `zPe` in 2.1.251, `WPe` in 2.1.252 and `t$e` in
#   2.1.263, with a byte-identical body. Grep for the arithmetic instead, e.g.
#   `grep -a -o -E '.{0,180}Math\.pow\(0\.5,.{0,180}' <claude binary>`, and for
#   the truncator `budgetTruncatedSkills`.
# Reasoning and the counters' own semantics: reference/listing-scorer.md and
#   reference/usage-counters.md, beside this skill.
# Recheck trigger: a release note naming the skill listing, its character budget,
#   or skill usage counters; or the counters changing shape in `~/.claude.json`.
# On mismatch: the report must degrade to `score_basis: "unscored"` and say the
#   ordering is unknown. A confidently wrong band is worse than no band.
# -----------------------------------------------------------------------------
LISTING_SCORE_HALF_LIFE_DAYS = 7.0
LISTING_SCORE_FLOOR = 0.1


def listing_score(count: int, last_used: datetime | None, clock: datetime) -> float:
    """Mirror of the product's scorer. Zero when there is no usage to weigh."""
    if count <= 0 or last_used is None:
        return 0.0
    days = (clock - last_used).total_seconds() / 86400.0
    decay = 0.5 ** (days / LISTING_SCORE_HALF_LIFE_DAYS)
    return count * max(decay, LISTING_SCORE_FLOOR)


def resolve_event_keys(
    denominator: list[dict], events: list[dict]
) -> tuple[dict[str, list[dict]], list[tuple[str, list[str]]]]:
    """Group events by the qualified skill they belong to.

    The stores record a skill's usage under either its qualified `<plugin>:<leaf>`
    name or its bare leaf, and the two land as separate rows. This machine holds
    both `babysit-prs` and `source-control:babysit-prs`. Looking events up by
    qualified name alone silently discarded every bare-key row, which is a
    reported count that is simply too low with nothing saying so.

    A bare key is attributed only when exactly one skill in the fleet carries
    that leaf. Piling an ambiguous leaf onto one plugin would invent usage, the
    same failure the `custom_skill` redaction guard exists to prevent, so an
    ambiguous key is returned for the withheld section instead of being spent.
    """
    qualified = {entry["qualified_name"] for entry in denominator}
    # Owners are counted per ENTRY, not per distinct qualified name. Two
    # marketplaces shipping the same plugin produce two denominator rows with an
    # identical qualified name, which the report already marks
    # `ambiguous-attribution`. Collapsing them into a set would let a bare key
    # pass the single-owner test and then be reported on BOTH rows, inventing
    # usage for an attribution the audit already knows it cannot make.
    leaf_owners: dict[str, list[str]] = defaultdict(list)
    for entry in denominator:
        name = entry["qualified_name"]
        leaf = name.split(":", 1)[1] if ":" in name else name
        leaf_owners[leaf].append(name)

    by_skill: dict[str, list[dict]] = defaultdict(list)
    ambiguous: dict[str, list[str]] = {}
    for event in events:
        key = event.get("skill")
        if key is None:
            continue
        if key in qualified:
            by_skill[key].append(event)
            continue
        owners = leaf_owners.get(key, [])
        if len(owners) == 1:
            by_skill[owners[0]].append(event)
        elif len(owners) > 1:
            ambiguous[key] = sorted(set(owners))
    return by_skill, sorted(ambiguous.items())


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
    skills it finds. It does not assess enablement: a checkout is not an
    install, so `enabledPlugins` has nothing to say about it, and every entry
    is marked `not-assessed` rather than `unknown`.
    """
    entries: list[dict] = []
    if not os.path.isdir(plugins_root):
        return entries
    for plugin in sorted(os.listdir(plugins_root)):
        entries += collect_fleet_at(os.path.join(plugins_root, plugin), plugin)
    return entries


# The evidence marker a checkout walk carries instead of a settings path:
# enablement is a property of an install, and a checkout is not one.
ENABLEMENT_NOT_ASSESSED = "not-assessed"


def collect_fleet_at(
    plugin_root: str,
    plugin: str,
    plugin_enabled: bool | None = None,
    plugin_enabled_evidence: str = ENABLEMENT_NOT_ASSESSED,
) -> list[dict]:
    """Walk ONE plugin directory into denominator entries.

    Separate from `collect_fleet` because the installed manifest resolves each
    plugin to its own root: the installs are scattered across versioned cache
    paths rather than sitting side by side under a single parent, so there is
    no one directory to walk for a real installation.

    `plugin_enabled` and `plugin_enabled_evidence` are the caller's answer to
    "does this plugin load", resolved from `enabledPlugins` by
    `collect_installed`. The defaults are the checkout answer: not assessed,
    because the filesystem alone cannot say, and guessing would libel a
    disabled plugin's skills as reachable.
    """
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
                "plugin_enabled": plugin_enabled,
                "plugin_enabled_evidence": plugin_enabled_evidence,
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

    Where the scopes disagree, the winner is the highest-precedence
    APPLICABLE record per `SCOPE_PRECEDENCE` (`local > project > user`) -- not
    the newest version, which is the wrong answer `scope-semantics.md` names
    explicitly. Applicability matters first: `project` and `local` records
    load only in the `projectPath` they name, so a record owned by another
    project is dropped into `not_applicable` rather than counted. Getting
    either wrong moves real numbers -- measured on that same install, 7
    plugins carried DIFFERENT skill sets between scopes and 19 skills carried
    different `description` text.

    Returns one row per plugin plus two report lists: `superseded` (the
    outranked records, so a pin losing to a higher scope stays visible) and
    `not_applicable` (records belonging to another project). Nothing is
    withheld or hedged -- the rule decides.

    A marketplace whose source is a local `directory` is the exception to
    where the code comes from: it loads that CHECKOUT rather than either
    cached `installPath`, verified by a skill executing out of the marketplace
    directory. Its root comes from the catalog's declared `source`, its scope
    reports as `marketplace-directory`, and it emits no `superseded` pair --
    naming two cached versions when neither is running would mislead.
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
    plugins_dir: str,
    current_project: str | None = None,
    enabled_plugins: dict | None = None,
) -> tuple[list[dict], dict]:
    """Read the installed manifest + marketplace registry into a denominator.

    Returns the denominator entries and the resolution report, so the caller
    can surface superseded and inapplicable records rather than absorbing them.

    `enabled_plugins` is `merge_enabled_plugins` over the settings layers; it
    decides `plugin_enabled` per `plugin@marketplace` key. Omitted, no scope
    was consulted, and every plugin resolves to the product's default,
    enabled, with `default` as its evidence.
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
    # Attach EVERY marketplace's catalog (`<installLocation>/.claude-plugin/
    # marketplace.json`, the same file `plugins/scripts/fleet-state.sh`
    # reads). A directory-source marketplace needs it so the resolver honours
    # the plugin's DECLARED source path instead of assuming a layout; every
    # marketplace needs it because the entry's `defaultEnabled` is the first
    # fallback for a plugin no settings scope mentions. A missing or
    # unparsable catalog attaches an empty list and the fallback moves on.
    for entry in marketplaces.values():
        if not isinstance(entry, dict):
            continue
        location = entry.get("installLocation")
        if location:
            catalog = _load_json(
                os.path.join(location, ".claude-plugin", "marketplace.json")
            )
            plugins = catalog.get("plugins")
            entry["_catalog"] = plugins if isinstance(plugins, list) else []

    resolution = resolve_installed(
        _load("installed_plugins.json"), marketplaces, current_project
    )
    enablement = enabled_plugins or merge_enabled_plugins([])
    denominator: list[dict] = []
    for row in resolution["plugins"]:
        state = enablement_for(
            enablement,
            f"{row['plugin']}@{row['marketplace']}",
            default_enabled_sources(
                marketplaces.get(row["marketplace"]) or {}, row["plugin"], row["root"]
            ),
        )
        denominator += collect_fleet_at(
            row["root"], row["plugin"], state["value"], state["evidence"]
        )
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

    The budget is computed in CHARACTERS, not tokens:
    `floor(window * bytes_per_token * fraction)`, minimum 1.

    Four-part record for the documented defaults (0.01 fraction, 1536 per-entry
    cap, 3-char joiner): basis https://code.claude.com/docs/en/settings
    (skillListingBudgetFraction, skillListingMaxDescChars) and
    https://code.claude.com/docs/en/skills#frontmatter-reference; verified
    2026-09-11. Recheck trigger: either page moving a default re-derives the
    matching field here; each fleet audit re-runs this record.

    Four-part record for the two per-model inputs: `bytes_per_token` is 4 or 3
    BY MODEL in the product, and 200k is only the arithmetic's fallback when no
    window reaches it; the live call passes the active model's window, which
    is 1M for current models on the Anthropic API. Basis: the budget
    arithmetic in the shipped binary, verified 2026-09-11 at Claude Code
    2.1.263 (reference/listing-scorer.md), and
    https://code.claude.com/docs/en/model-config for the window. Recheck
    trigger: the settings page documenting either value, or the binary's
    budget arithmetic changing shape.

    The two per-model fields keep the binary's fallback and the 4-byte estimate
    as defaults so a pinned single-row computation and a replayed fixture stay
    expressible. An unpinned live run never reports either default as a
    session claim: it computes every combination in `ListingAxes` and reports
    a band.
    """

    context_window_tokens: int = 200_000
    budget_fraction: float = 0.01
    max_desc_chars: int = 1536
    bytes_per_token: int = 4
    # The literal " - " the harness inserts between description and when_to_use.
    joiner_chars: int = 3
    env_char_budget: int | None = None
    # Where `budget_fraction` came from: "fraction" for the documented default,
    # "settings:<path>" for the settings file that supplied it, or
    # "pin:--budget-fraction" for a command-line pin. Rendered as
    # `budget_basis` unless the env override short-circuits the arithmetic.
    fraction_basis: str = "fraction"


def listing_budget_chars(cfg: ListingConfig) -> int:
    """Budget in characters -- DERIVED, never a constant.

    The familiar "8,000" is this formula at a 200k-token window and 4 bytes per
    token; a 1M-token window gets 40,000 and a 3-byte model a quarter less.
    Hardcoding 8,000 would be wrong for most current models, and hardcoding it
    as a floor would be wrong too, because `SLASH_COMMAND_TOOL_CHAR_BUDGET`
    overrides everything unconditionally.
    """
    if cfg.env_char_budget is not None:
        return cfg.env_char_budget
    return max(
        1, int(cfg.context_window_tokens * cfg.budget_fraction * cfg.bytes_per_token)
    )


def budget_basis(cfg: ListingConfig) -> str:
    """The `budget_basis` label one budget computation carries."""
    return "env-override" if cfg.env_char_budget is not None else cfg.fraction_basis


# --- Settings scopes ---------------------------------------------------------
#
# The two listing keys are `Any file` scope keys, merged PER KEY across the
# settings scopes with the precedence user < project < local < flag < policy:
# the last scope that defines a key wins it. The flag scope (`--settings` on the
# command line) lives inside the running session and cannot be observed from an
# out-of-process script, so it is recorded as unread rather than as absent.
# Environment variables are not a level in this stack. Basis:
# https://code.claude.com/docs/en/settings (precedence) and the settings schema
# text in the shipped binary; verified 2026-09-11 at Claude Code 2.1.263.

LISTING_SETTINGS_KEYS = ("skillListingBudgetFraction", "skillListingMaxDescChars")

SETTINGS_SCOPE_ORDER = ("user", "project", "local", "flag", "policy")

FLAG_SCOPE_NOTE = (
    "the command-line --settings scope lives inside the session and is not "
    "observable from outside it"
)


def _valid_listing_setting(key: str, value: object) -> bool:
    """A value the product would actually use; anything else is left alone.

    The product falls back to the default only for a null or missing key, so a
    wrong-typed value there produces nonsense rather than the default. Treating
    it as absent here, with a note, is the honest report: the audit cannot
    reproduce nonsense the product itself would not budget with.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    if key == "skillListingBudgetFraction":
        return value > 0
    return value >= 0


def merge_listing_settings(layers: list[dict]) -> dict:
    """Per-key merge over settings layers given in ASCENDING precedence.

    Each layer is `{"scope", "path", "status", "settings"}`; only a layer whose
    `settings` is a dict contributes. Returns, per listing key, the winning
    value and the provenance that supplied it: `settings:<path>` or `default`.
    Pure, so the precedence rule is testable without a settings tree.
    """
    merged = {
        key: {"value": None, "provenance": "default"} for key in LISTING_SETTINGS_KEYS
    }
    ignored: list[str] = []
    for layer in layers:
        settings = layer.get("settings")
        if not isinstance(settings, dict):
            continue
        for key in LISTING_SETTINGS_KEYS:
            if key not in settings or settings[key] is None:
                continue
            if not _valid_listing_setting(key, settings[key]):
                ignored.append(
                    f"{key} in {layer.get('path')} is {settings[key]!r}, "
                    "not a usable number; left out of the merge"
                )
                continue
            merged[key] = {
                "value": settings[key],
                "provenance": f"settings:{layer.get('path')}",
            }
    merged["ignored"] = ignored
    return merged


ENABLED_PLUGINS_KEY = "enabledPlugins"


def merge_enabled_plugins(layers: list[dict]) -> dict:
    """Per-key merge of `enabledPlugins` over layers given in ASCENDING precedence.

    The same walk as `merge_listing_settings`, over the same layer shape, for
    one more key: the object mapping `plugin-name@marketplace-name` to a
    Boolean. The product merges it per key, user < project < local < flag <
    policy, last defined scope wins, and a key absent from every scope means
    enabled. Verified 2026-09-11 against the settings reference and Claude
    Code 2.1.263; recheck trigger: https://code.claude.com/docs/en/settings
    changing the `enabledPlugins` shape or its stated precedence.

    Returns `plugins` (per key, the winning `value` and the `evidence` path
    that supplied it), `unreadable` (settings FILES that exist but could not
    be read or parsed) and `ignored` (non-Boolean values left out, named). An
    unreadable file could have set any key at its own precedence, so a key
    whose winning value comes from below one resolves to `None` with the
    unreadable file as evidence. The in-session flag scope and a managed scope
    that could not be enumerated carry no file path; they are reported in the
    inputs list rather than poisoning the merge, as the listing keys do.
    """
    plugins: dict[str, dict] = {}
    unreadable: list[tuple[int, str]] = []
    ignored: list[str] = []
    for index, layer in enumerate(layers):
        path = layer.get("path")
        if layer.get("status") == "unreadable" and path:
            unreadable.append((index, path))
            continue
        settings = layer.get("settings")
        if not isinstance(settings, dict):
            continue
        block = settings.get(ENABLED_PLUGINS_KEY)
        if block is None:
            continue
        if not isinstance(block, dict):
            ignored.append(
                f"{ENABLED_PLUGINS_KEY} in {path} is not an object; left out of "
                "the merge"
            )
            continue
        for key, value in block.items():
            if not isinstance(value, bool):
                ignored.append(
                    f"{ENABLED_PLUGINS_KEY}[{key!r}] in {path} is {value!r}, not "
                    "a Boolean; left out of the merge"
                )
                continue
            plugins[key] = {"value": value, "evidence": path, "rank": index}
    resolved: dict[str, dict] = {}
    for key, row in plugins.items():
        above = [path for rank, path in unreadable if rank > row["rank"]]
        if above:
            resolved[key] = {"value": None, "evidence": ", ".join(above)}
        else:
            resolved[key] = {"value": row["value"], "evidence": row["evidence"]}
    return {
        "plugins": resolved,
        "unreadable": [path for _, path in unreadable],
        "ignored": ignored,
    }


# Evidence labels for the two `defaultEnabled` fallbacks, in precedence order.
DEFAULT_ENABLED_MARKETPLACE = "default: marketplace entry defaultEnabled"
DEFAULT_ENABLED_MANIFEST = "default: plugin.json defaultEnabled"


def default_enabled_sources(
    marketplace_entry: dict, plugin: str, root: str
) -> list[tuple[str, object]]:
    """The `defaultEnabled` values that decide a plugin no settings scope names.

    Highest precedence first: the MARKETPLACE ENTRY's `defaultEnabled` (from
    the catalog attached as `_catalog`) outranks the plugin's own
    `.claude-plugin/plugin.json` field, the rule this same plugin states in
    `skills/plugins/context/sync-install-enable.md` and applies in
    `skills/plugins/scripts/fleet-state.sh`. Only sources that carry the key
    are returned, with the value as written, so the caller can name a
    non-Boolean rather than silently coerce it. A catalog that could not be
    read, a manifest that is absent or unparsable, or an entry without the key
    contributes nothing.
    """
    sources: list[tuple[str, object]] = []
    for row in marketplace_entry.get("_catalog") or []:
        if isinstance(row, dict) and row.get("name") == plugin:
            if "defaultEnabled" in row:
                sources.append((DEFAULT_ENABLED_MARKETPLACE, row["defaultEnabled"]))
            break
    manifest_path = os.path.join(root or "", ".claude-plugin", "plugin.json")
    try:
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
    except (OSError, ValueError):
        manifest = None
    if isinstance(manifest, dict) and "defaultEnabled" in manifest:
        sources.append((DEFAULT_ENABLED_MANIFEST, manifest["defaultEnabled"]))
    return sources


def enablement_for(
    merged: dict, key: str, defaults: list[tuple[str, object]] | None = None
) -> dict:
    """The enablement answer for one `plugin@marketplace` key.

    `merged` is `merge_enabled_plugins` output. A key it names is answered
    from the scope that set it, or is `None` naming the unreadable file above
    that scope. When any settings file was unreadable an absence is not
    knowable, so the answer is `None` naming the file, never a guess.

    A key absent from every readable scope falls back to `defaults`, the
    `(evidence, value)` pairs `default_enabled_sources` returns in precedence
    order: the marketplace entry's `defaultEnabled`, then the plugin's own
    manifest field. An `enabledPlugins` entry at any scope outranks both; the
    official plugins reference calls `defaultEnabled` "the fallback when
    nothing else has decided the plugin's state". The first Boolean wins with
    its label as evidence; a non-Boolean value is skipped and named in the
    evidence of whatever decides instead. With no Boolean anywhere the answer
    is the product's default, enabled, with `default` as evidence.
    """
    row = merged["plugins"].get(key)
    if row is not None:
        return dict(row)
    if merged["unreadable"]:
        return {"value": None, "evidence": ", ".join(merged["unreadable"])}
    ignored: list[str] = []
    for evidence, value in defaults or []:
        if isinstance(value, bool):
            return {"value": value, "evidence": _with_ignored(evidence, ignored)}
        ignored.append(
            f"{evidence.removeprefix('default: ')} is {value!r}, not a Boolean; ignored"
        )
    return {"value": True, "evidence": _with_ignored("default", ignored)}


def _with_ignored(evidence: str, ignored: list[str]) -> str:
    return f"{evidence} ({'; '.join(ignored)})" if ignored else evidence


def _read_settings_file(path: str) -> tuple[str, dict | None, str | None]:
    """One settings file -> (status, parsed object or None, note)."""
    if not os.path.isfile(path):
        return "absent", None, None
    try:
        with open(path, encoding="utf-8") as handle:
            blob = json.load(handle)
    except OSError as exc:
        return "unreadable", None, f"cannot read: {exc.strerror or exc}"
    except ValueError as exc:
        return "unreadable", None, f"not valid JSON: {exc}"
    if not isinstance(blob, dict):
        return "unreadable", None, "top level is not an object"
    return "read", blob, None


def _settings_layer(scope: str, path: str) -> dict:
    status, settings, note = _read_settings_file(path)
    return {
        "scope": scope,
        "path": path,
        "status": status,
        "settings": settings,
        "note": note,
    }


# The bash shim the managed-scope enumeration runs. `$1` is the vendored
# library, `$2` an optional base-file override (the library's own test seam,
# passed through so a fixture can relocate the whole managed tree). The three
# groups are separated by a bare `--` line so an empty group still parses.
MANAGED_SCOPE_SHIM = (
    'source "$1" || exit 3; '
    'mscope::base_file "$2"; mscope::dropin_dir "$2"; '
    'printf -- "--\\n"; mscope::registry_keys; '
    'printf -- "--\\n"; mscope::plist_domain'
)


def managed_scope_lib_path() -> str:
    """The vendored `lib/managed-scope.sh` beside this skill.

    Resolved the way the sibling shell consumers resolve it: `CLAUDE_PLUGIN_ROOT`
    when the harness set it, else this file's own plugin root. The env value is
    checked for the file before it is trusted, because in a skill subprocess it
    has been observed pointing at a different plugin's root.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    own_root = os.path.normpath(os.path.join(here, "..", "..", ".."))
    for root in (os.environ.get("CLAUDE_PLUGIN_ROOT"), own_root):
        if root:
            candidate = os.path.join(root, "lib", "managed-scope.sh")
            if os.path.isfile(candidate):
                return candidate
    return os.path.join(own_root, "lib", "managed-scope.sh")


def enumerate_managed_scope(
    lib_path: str, bash: str = "bash", override: str | None = None
) -> dict:
    """Ask the vendored `managed-scope.sh` where managed policy lives.

    Never hand-rolls a managed path: the per-OS locations are the library's
    to know, and a copy here would drift from it. A missing bash, a failing
    source, a timeout, or output of the wrong shape all come back as
    `status: "unreadable"` with the reason, so the settings merge can say the
    policy scope was NOT read rather than reporting it absent.
    """
    if not os.path.isfile(lib_path):
        return {
            "status": "unreadable",
            "lib": lib_path,
            "reason": "vendored lib/managed-scope.sh is missing",
        }
    try:
        result = subprocess.run(
            [bash, "-c", MANAGED_SCOPE_SHIM, "managed-scope", lib_path, override or ""],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
    except OSError as exc:
        return {
            "status": "unreadable",
            "lib": lib_path,
            "reason": f"{bash} could not be run: {exc.strerror or exc}",
        }
    except subprocess.TimeoutExpired:
        return {
            "status": "unreadable",
            "lib": lib_path,
            "reason": f"{bash} did not finish enumerating managed scope",
        }
    if result.returncode != 0:
        return {
            "status": "unreadable",
            "lib": lib_path,
            "reason": (
                f"{bash} exited {result.returncode} sourcing the lib: "
                f"{result.stderr.strip() or 'no stderr'}"
            ),
        }
    groups: list[list[str]] = [[]]
    for line in result.stdout.splitlines():
        line = line.rstrip("\r")
        if line == "--":
            groups.append([])
        elif line:
            groups[-1].append(line)
    if len(groups) != 3 or len(groups[0]) != 2:
        return {
            "status": "unreadable",
            "lib": lib_path,
            "reason": "managed-scope output was not the expected shape",
        }
    return {
        "status": "read",
        "lib": lib_path,
        "base_file": groups[0][0],
        "dropin_dir": groups[0][1],
        # Registry keys and the preferences domain are policy surfaces this
        # reader does not open; they are named so an empty file list is never
        # mistaken for "no managed policy deployed".
        "unread_surfaces": groups[1] + groups[2],
    }


def settings_layers(project_root: str, config_root: str, managed: dict) -> list[dict]:
    """Every settings scope, lowest precedence first, each read or explained.

    `config_root` is the `~/.claude` tree (`CLAUDE_CONFIG_DIR` relocates it),
    `project_root` the project whose `.claude/` holds the project and local
    files, and `managed` the result of `enumerate_managed_scope`. The managed
    drop-in directory is merged base file first and then every non-hidden
    `*.json` in name order, later files winning, which is the documented order.
    """
    layers = [
        _settings_layer("user", os.path.join(config_root, "settings.json")),
        _settings_layer(
            "project", os.path.join(project_root, ".claude", "settings.json")
        ),
        _settings_layer(
            "local", os.path.join(project_root, ".claude", "settings.local.json")
        ),
        {
            "scope": "flag",
            "path": "--settings",
            "status": "unread",
            "settings": None,
            "note": FLAG_SCOPE_NOTE,
        },
    ]
    if managed.get("status") != "read":
        layers.append(
            {
                "scope": "policy",
                "path": None,
                "status": "unreadable",
                "settings": None,
                "note": managed.get("reason")
                or "managed scope could not be enumerated",
            }
        )
        return layers
    layers.append(_settings_layer("policy", managed["base_file"]))
    dropin = managed["dropin_dir"]
    if os.path.isdir(dropin):
        names = sorted(
            n
            for n in os.listdir(dropin)
            if n.endswith(".json") and not n.startswith(".")
        )
        for name in names:
            layers.append(_settings_layer("policy", os.path.join(dropin, name)))
        if not names:
            layers.append(
                {
                    "scope": "policy",
                    "path": dropin,
                    "status": "absent",
                    "settings": None,
                    "note": "drop-in directory holds no *.json",
                }
            )
    else:
        layers.append(
            {
                "scope": "policy",
                "path": dropin,
                "status": "absent",
                "settings": None,
                "note": None,
            }
        )
    for surface in managed.get("unread_surfaces") or []:
        layers.append(
            {
                "scope": "policy",
                "path": surface,
                "status": "unread",
                "settings": None,
                "note": "policy surface this reader does not open",
            }
        )
    return layers


# --- Context window and bytes per token ---------------------------------------
#
# Both are per model, and this script never resolves the model from disk: the
# session's model is not written anywhere an out-of-process reader can trust.
# The honest static report is a band over every combination, collapsed only by
# an operator pin or by an environment variable the product itself honours.
#
# Window resolution order mirrors the binary: `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
# wins, but only when `DISABLE_COMPACT` is also set; else a truthy
# `CLAUDE_CODE_DISABLE_1M_CONTEXT` forces 200k; else the active model decides,
# which from outside the session means both windows. Verified 2026-09-11 at
# Claude Code 2.1.263 (reference/listing-scorer.md); recheck trigger:
# https://code.claude.com/docs/en/model-config changing what sets the window.

WINDOW_BAND: tuple[int, ...] = (200_000, 1_000_000)
BYTES_PER_TOKEN_BAND: tuple[int, ...] = (4, 3)
ENV_TRUTHY = frozenset({"1", "true", "yes", "on"})


def _env_truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in ENV_TRUTHY


def resolve_windows(pin: int | None, env: Mapping[str, str]) -> dict:
    """Which context windows the budget is computed for, and why.

    Returns `{"windows": (...), "basis": str, "env": [...]}`. `env` records
    each variable consulted with its effect, so the report can state what was
    honoured, what was ignored, and why. A pin is the operator's own statement
    about the session and outranks the process environment, which may not be
    the session's.
    """
    consulted: list[dict] = []
    max_tokens = env.get("CLAUDE_CODE_MAX_CONTEXT_TOKENS")
    disable_compact = env.get("DISABLE_COMPACT")
    disable_1m = env.get("CLAUDE_CODE_DISABLE_1M_CONTEXT")

    max_tokens_value: int | None = None
    if max_tokens is not None:
        if not _env_truthy(disable_compact):
            effect = "ignored: honoured only when DISABLE_COMPACT is also set"
        elif not max_tokens.strip().isdigit() or int(max_tokens) <= 0:
            effect = "ignored: not a positive integer"
        else:
            max_tokens_value = int(max_tokens)
            effect = f"window {max_tokens_value:,}"
        consulted.append(
            {
                "name": "CLAUDE_CODE_MAX_CONTEXT_TOKENS",
                "value": max_tokens,
                "effect": effect,
            }
        )
    else:
        consulted.append(
            {"name": "CLAUDE_CODE_MAX_CONTEXT_TOKENS", "value": None, "effect": "unset"}
        )
    if disable_compact is not None:
        consulted.append(
            {
                "name": "DISABLE_COMPACT",
                "value": disable_compact,
                "effect": "set" if _env_truthy(disable_compact) else "not truthy",
            }
        )
    if disable_1m is not None:
        if _env_truthy(disable_1m):
            effect = "window 200,000"
        else:
            effect = "not truthy: no effect"
        consulted.append(
            {
                "name": "CLAUDE_CODE_DISABLE_1M_CONTEXT",
                "value": disable_1m,
                "effect": effect,
            }
        )
    else:
        consulted.append(
            {"name": "CLAUDE_CODE_DISABLE_1M_CONTEXT", "value": None, "effect": "unset"}
        )

    if pin is not None:
        for row in consulted:
            if row["effect"].startswith("window"):
                row["effect"] += " (not applied: --context-window pinned)"
        return {"windows": (pin,), "basis": "pin:--context-window", "env": consulted}
    if max_tokens_value is not None:
        return {
            "windows": (max_tokens_value,),
            "basis": "env:CLAUDE_CODE_MAX_CONTEXT_TOKENS",
            "env": consulted,
        }
    if _env_truthy(disable_1m):
        return {
            "windows": (200_000,),
            "basis": "env:CLAUDE_CODE_DISABLE_1M_CONTEXT",
            "env": consulted,
        }
    return {
        "windows": WINDOW_BAND,
        "basis": "band: the window is per model and the model is not resolved from disk",
        "env": consulted,
    }


def _window_label(window: int) -> str:
    if window == 200_000:
        return "200k"
    if window == 1_000_000:
        return "1M"
    return f"{window:,}"


def band_label(window: int, bytes_per_token: int) -> str:
    """The row label a band entry carries, e.g. `1M/4`."""
    return f"{_window_label(window)}/{bytes_per_token}"


@dataclass(frozen=True)
class ListingAxes:
    """The window and bytes-per-token values one run computes the budget for.

    One value on each axis is a pinned single row; more is a band. `inputs`
    carries the provenance of every budget input for the report and is not
    part of the arithmetic.
    """

    windows: tuple[int, ...] = WINDOW_BAND
    bytes_per_tokens: tuple[int, ...] = BYTES_PER_TOKEN_BAND
    inputs: dict = field(default_factory=dict)


def build_listing_inputs(
    pins: Mapping[str, object], env: Mapping[str, str], layers: list[dict]
) -> tuple[ListingConfig, ListingAxes]:
    """Turn pins, environment, and settings layers into the budget inputs.

    `pins` holds the four command-line values (`context_window`,
    `bytes_per_token`, `budget_fraction`, `max_desc_chars`), each None when
    not given. A pin outranks a settings value, which outranks the default;
    every choice is recorded in `ListingAxes.inputs` with its provenance.
    """
    merged = merge_listing_settings(layers)

    fraction_pin = pins.get("budget_fraction")
    fraction_row = merged["skillListingBudgetFraction"]
    if fraction_pin is not None:
        fraction, fraction_basis = float(fraction_pin), "pin:--budget-fraction"
    elif fraction_row["value"] is not None:
        fraction, fraction_basis = (
            float(fraction_row["value"]),
            fraction_row["provenance"],
        )
    else:
        fraction, fraction_basis = ListingConfig.budget_fraction, "fraction"

    cap_pin = pins.get("max_desc_chars")
    cap_row = merged["skillListingMaxDescChars"]
    if cap_pin is not None:
        max_desc, cap_basis = int(cap_pin), "pin:--max-desc-chars"
    elif cap_row["value"] is not None:
        max_desc, cap_basis = int(cap_row["value"]), cap_row["provenance"]
    else:
        max_desc, cap_basis = ListingConfig.max_desc_chars, "default"

    raw_env_budget = env.get("SLASH_COMMAND_TOOL_CHAR_BUDGET")
    env_budget: int | None = None
    if raw_env_budget is None:
        env_budget_note = "unset"
    elif raw_env_budget.strip().isdigit() and int(raw_env_budget) > 0:
        env_budget = int(raw_env_budget)
        env_budget_note = f"budget {env_budget:,} characters, fraction ignored"
    else:
        env_budget_note = "ignored: not a positive integer"

    windows = resolve_windows(pins.get("context_window"), env)
    bpt_pin = pins.get("bytes_per_token")
    if bpt_pin is not None:
        bytes_per_tokens: tuple[int, ...] = (int(bpt_pin),)
        bpt_basis = "pin:--bytes-per-token"
    else:
        bytes_per_tokens = BYTES_PER_TOKEN_BAND
        bpt_basis = "band: 4 or 3 bytes per token by model, not resolved from disk"

    cfg = ListingConfig(
        budget_fraction=fraction,
        max_desc_chars=max_desc,
        env_char_budget=env_budget,
        fraction_basis=fraction_basis,
    )
    inputs = {
        "budget_fraction": {"value": fraction, "provenance": fraction_basis},
        "max_desc_chars": {"value": max_desc, "provenance": cap_basis},
        "env_char_budget": {
            "value": env_budget,
            "provenance": f"SLASH_COMMAND_TOOL_CHAR_BUDGET {env_budget_note}",
        },
        "windows": {"values": list(windows["windows"]), "provenance": windows["basis"]},
        "bytes_per_tokens": {"values": list(bytes_per_tokens), "provenance": bpt_basis},
        "env": windows["env"],
        "settings_scopes": [
            {k: v for k, v in layer.items() if k != "settings"} for layer in layers
        ],
        "settings_ignored": merged["ignored"],
    }
    return cfg, ListingAxes(windows["windows"], bytes_per_tokens, inputs)


def _eligibility(entry: dict) -> str:
    """Which skills actually contend for description budget.

    Three exempt classes, and two are easy to miss. A
    `disable-model-invocation` skill keeps its description out of the model's
    context entirely, so it spends none of the shared budget. Locally that is 59
    of 213 skills -- counting them would inflate the overflow figure enough to
    flip the headline verdict. A skill whose owning plugin resolves to
    `plugin_enabled: False` is never loaded at all, so its description spends
    nothing either; only a settled `False` exempts, because `None` (not
    assessed, or undetermined) is not hidden and keeps competing.
    `skillOverrides` is not a fourth class: it never applies to plugin skills,
    the only kind this audit enumerates.
    """
    frontmatter = entry.get("frontmatter") or {}
    if entry.get("source") == "bundled":
        return "exempt-bundled"
    if entry.get("plugin_enabled") is False:
        return "exempt-hidden"
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
    return min(_description_chars(entry, cfg), cfg.max_desc_chars)


def _description_chars(entry: dict, cfg: ListingConfig) -> int:
    """The uncapped length the listing would charge, joiner included.

    Kept beside the capped charge because the two answer different questions:
    the charge is what the budget counts, and the source length is what an
    author has to trim, which only lowers the charge once it crosses the cap.
    """
    frontmatter = entry.get("frontmatter") or {}
    description = frontmatter.get("description") or ""
    when_to_use = frontmatter.get("when_to_use") or ""
    joiner = cfg.joiner_chars if (description and when_to_use) else 0
    return len(description) + joiner + len(when_to_use)


def compute_listing(
    denominator: list[dict],
    cfg: ListingConfig,
    scores: dict[str, float] | None = None,
) -> dict:
    """Budget arithmetic, split by confidence.

    CERTAIN: whether the listing overflows and by how much -- pure arithmetic
    over documented settings against summed description lengths.

    INFERENTIAL: which particular skills lose their descriptions. That ordering
    comes from a scorer recovered from one build of the product (see
    `listing_score`), so it is rendered as a ranked band and labelled, never as
    an exact cutoff.

    `scores` carries the mirrored scorer's output per qualified name. When it is
    absent or empty the ordering has no usage signal behind it, and the returned
    `score_basis` says so rather than letting the catalog-order tiebreaker pass
    for a usage ranking.
    """
    budget = listing_budget_chars(cfg)
    scores = scores or {}

    rows: list[dict] = []
    demand = 0
    # The grant loop's budget is computed FORWARD from a floor, never backward
    # from the overflow: the product starts at `budget - V`, where V is what the
    # listing costs before any description is granted. Every entry that appears
    # at all pays for its own name; the exempt classes pay their full rendering
    # because they are never candidates.
    floor = 0
    listed = 0
    for entry in denominator:
        eligibility = _eligibility(entry)
        desc_chars = _demand_chars(entry, cfg)
        chars = desc_chars if eligibility == "competing" else 0
        demand += chars
        # A `disable-model-invocation` skill and a disabled plugin's skill are
        # absent from the listing ENTIRELY, so unlike the bundled class they
        # cost nothing and take no separator.
        if eligibility not in ("exempt-user-only", "exempt-hidden"):
            listed += 1
            name_chars = len(entry["qualified_name"])
            if eligibility == "exempt-bundled":
                # Keeps its description unconditionally, so it is charged for it.
                floor += name_chars + 4 + desc_chars
            else:
                floor += name_chars + 2
        rows.append(
            {
                "qualified_name": entry["qualified_name"],
                "eligibility": eligibility,
                "demand_chars": chars,
                "description_chars": _description_chars(entry, cfg),
                "usage_score": scores.get(
                    entry["qualified_name"], entry.get("usage_score", 0)
                ),
            }
        )

    overflow = max(0, demand - budget)
    verdict = "overflowing" if overflow > 0 else "listing-fits"

    floor += max(0, listed - 1)

    competing = [r for r in rows if r["eligibility"] == "competing"]

    # Basis is decided by whether any score survived AMONG THE CONTENDERS, not
    # by whether a scores argument arrived and not over the whole denominator. A
    # bundled or disable-model-invocation skill can carry real native
    # usage while being excluded from the contest entirely; counting its score
    # here would label a listing `native-counters` whose every actual contender
    # is at zero, so a pure catalog ordering would be dressed as `inferential`.
    # That is the exact defect this report exists to stop, one scope up.
    score_basis = (
        "native-counters" if any(r["usage_score"] for r in competing) else "unscored"
    )

    # WHICH rows are shed is a GREEDY FIRST-FIT walk, not a score-ordered
    # prefix. The product sorts descending by score and then walks EVERY
    # competing entry with a running description budget, granting whatever still
    # fits and shedding whatever does not. Crucially its loop has no early exit,
    # so a cheap low-scored description can still be granted after an expensive
    # higher-scored one was refused. Modelling this as a prefix understated the
    # protection long descriptions lose and overstated it for short ones.
    #
    # Consequence worth stating plainly: description LENGTH is a ranking input,
    # which no prose description of this mechanism mentions.
    #
    # Ties keep CATALOG ORDER, not alphabetical. The product's sort is stable, so
    # equal scores stay in input order; Python's is too, which is why this sorts
    # on the score alone. It matters most in the `unscored` case, where every
    # score is 0 and the tiebreaker IS the whole ordering: an alphabetical one
    # would disagree with the product on every row.
    competing.sort(key=lambda r: -r["usage_score"])
    remaining = max(0, budget - floor)
    for row in competing:
        if overflow <= 0:
            row["verdict"] = "listing-fits"
        elif row["demand_chars"] <= remaining:
            remaining -= row["demand_chars"]
            row["verdict"] = "likely-retained"
        else:
            row["verdict"] = "likely-starved"

    # The band is a separate question from the verdict: it ranks how exposed a
    # row is, lowest score first, so band 1 is the row the mechanism protects
    # least. It can disagree with the verdict, and that disagreement is real
    # rather than a bug -- a band-1 row with a very short description can survive
    # a first-fit pass that sheds a better-scored row with a long one.
    by_exposure = sorted(competing, key=lambda r: r["usage_score"])
    for rank, row in enumerate(by_exposure, start=1):
        row["band"] = rank if overflow > 0 else None
        # An unscored ordering is catalog order, so its band carries no signal
        # at all. That is a weaker claim than an inferential one and must not
        # wear the same label.
        if overflow <= 0:
            row["confidence"] = "certain"
        elif score_basis == "unscored":
            row["confidence"] = "unscored"
        else:
            row["confidence"] = "inferential"
    for row in rows:
        if row["eligibility"] != "competing":
            row["band"] = None
            row["verdict"] = "not-assessable"
            row["confidence"] = "certain"

    # HOW MANY descriptions cannot fit is arithmetic and survives whatever the
    # ordering is worth. WHICH ones is a separate claim, settled next.
    starved_count = sum(1 for r in competing if r["verdict"] == "likely-starved")

    # WHILE no contender carries any usage, every score is 0 and the ordering
    # above is the catalog-order tie a stable sort leaves behind. Naming the
    # rows it sheds would publish catalog position as a usage ranking, which is
    # the defect this report exists to expose, one scope up. So the per-row
    # claim is withheld with its reason and the count above still stands.
    if overflow > 0 and score_basis == "unscored":
        for row in competing:
            row["verdict"] = "withheld"
            row["reason"] = "unscored"
            row["band"] = None

    return {
        "label": band_label(cfg.context_window_tokens, cfg.bytes_per_token),
        "context_window_tokens": cfg.context_window_tokens,
        "bytes_per_token": cfg.bytes_per_token,
        "budget_chars": budget,
        "budget_basis": budget_basis(cfg),
        "demand_chars": demand,
        "overflow_chars": overflow,
        "verdict": verdict,
        "score_basis": score_basis,
        "competing_count": len(competing),
        "starved_count": starved_count,
        "exempt_count": len(rows) - len(competing),
        "skills": rows,
    }


BAND_ROW_FIELDS = (
    "label",
    "context_window_tokens",
    "bytes_per_token",
    "budget_chars",
    "budget_basis",
    "overflow_chars",
    "verdict",
    "starved_count",
)


def compute_listing_band(
    denominator: list[dict],
    cfg: ListingConfig,
    axes: ListingAxes,
    scores: dict[str, float] | None = None,
) -> dict:
    """The listing budget over every window x bytes-per-token combination.

    One combination (a pin on both axes, or the env override, which makes both
    axes moot) returns the single-row shape `compute_listing` produces, so
    consumers of that shape are unaffected. More than one returns the same
    top-level keys with the per-row numbers nulled, `budget_basis: "band"`,
    and the rows under `band`, each labelled and carrying its own numbers. No
    row is named as this session's: that is the claim the band exists to
    withhold.

    Per skill, the fields that do not depend on the row (eligibility, demand,
    score) are kept as they are. The verdict is kept when every row agrees and
    is `band-dependent` otherwise, with the per-row verdicts under `by_band`;
    the exposure rank and its confidence come from the most exposed row, since
    a rank exists in any row that overflows and the ordering is the same in
    all of them.
    """
    if cfg.env_char_budget is not None:
        return compute_listing(denominator, cfg, scores)
    rows = [
        compute_listing(
            denominator,
            replace(cfg, context_window_tokens=window, bytes_per_token=bpt),
            scores,
        )
        for window in axes.windows
        for bpt in axes.bytes_per_tokens
    ]
    if len(rows) == 1:
        return rows[0]

    most_exposed = max(rows, key=lambda r: r["overflow_chars"])
    skills: list[dict] = []
    for index, base in enumerate(rows[0]["skills"]):
        merged = {
            k: v
            for k, v in base.items()
            if k not in ("verdict", "band", "confidence", "reason")
        }
        per_row = [r["skills"][index] for r in rows]
        verdicts = {r["verdict"] for r in per_row}
        merged["verdict"] = verdicts.pop() if len(verdicts) == 1 else "band-dependent"
        exposed = most_exposed["skills"][index]
        merged["band"] = exposed["band"]
        merged["confidence"] = exposed["confidence"]
        # A row that withholds its starvation verdict carries the reason with
        # it, so the merged row does too: a band whose rows disagree still has
        # to say why the overflowing ones name nobody.
        if any(r.get("reason") for r in per_row):
            merged["reason"] = next(r["reason"] for r in per_row if r.get("reason"))
        if base["eligibility"] == "competing":
            merged["by_band"] = {
                r["label"]: r["skills"][index]["verdict"] for r in rows
            }
        skills.append(merged)

    verdicts = {r["verdict"] for r in rows}
    return {
        "label": None,
        "context_window_tokens": None,
        "bytes_per_token": None,
        "budget_chars": None,
        "budget_basis": "band",
        "demand_chars": rows[0]["demand_chars"],
        "overflow_chars": None,
        "verdict": verdicts.pop() if len(verdicts) == 1 else "band-dependent",
        "score_basis": rows[0]["score_basis"],
        "competing_count": rows[0]["competing_count"],
        "starved_count": None,
        "exempt_count": rows[0]["exempt_count"],
        "band": [{k: r[k] for k in BAND_ROW_FIELDS} for r in rows],
        "skills": skills,
    }


STARVATION_WITHHELD_REASON = "unscored: ordering is catalog-order tie, not usage"


def starvation_withheld(listing: dict) -> bool:
    """Whether this run refused to name WHICH descriptions the budget sheds.

    True exactly when something overflows with no usage behind the ordering:
    the contest is then decided by the catalog-order tie the product's stable
    sort leaves, and catalog position is not a preference. Reads the same for a
    pinned single row and for a band, where one overflowing row is enough.
    """
    if listing.get("score_basis") != "unscored":
        return False
    return listing_overflows(listing)


def listing_overflows(listing: dict) -> bool:
    """Whether any budget row overflows: one row is enough for a band."""
    band = listing.get("band")
    if band:
        return any(row["overflow_chars"] > 0 for row in band)
    return bool(listing.get("overflow_chars"))


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
    enabled_evidence = entry.get("plugin_enabled_evidence")

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

    # `skillOverrides` is deliberately not consulted: plugin skills are
    # governed by `enabledPlugins` alone, and the product's listing resolver
    # returns "on" for every plugin-sourced skill before it reads the override
    # map. Non-plugin skills, which it does govern, are not enumerated here.
    if enabled is None and enabled_evidence == ENABLEMENT_NOT_ASSESSED:
        # A checkout is not an install: there is no enablement to read, so
        # the question is declined rather than answered `unknown`.
        return {
            "value": "not-assessed",
            "causes": ["checkout-not-an-install"],
            "remedy": (
                "Enablement is a property of an install, not a checkout. Run "
                "with --installed to assess whether the owning plugin loads."
            ),
            "evidence": None,
            "provenance": "n/a",
        }

    if enabled is None:
        # The sources genuinely could not answer. Never guess; name the file.
        named = (
            f"{enabled_evidence} could not be read or parsed, and a setting "
            "there would outrank every readable scope"
            if enabled_evidence
            else "the available sources do not carry it"
        )
        return {
            "value": "unknown",
            "causes": ["enablement-undetermined"],
            "remedy": (
                f"Enablement could not be determined: {named}. Fix or remove "
                "that file and rerun."
            ),
            "evidence": enabled_evidence or None,
            "provenance": "n/a",
        }

    if not enabled:
        return {
            "value": "hidden",
            "causes": ["plugin-not-enabled"],
            "remedy": (
                "The owning plugin is installed but resolves to disabled, so "
                "none of its skills load: an `enabledPlugins` entry set it to "
                "false, or no scope names it and its `defaultEnabled` is "
                "false. Set `enabledPlugins` to true in a scope that outranks "
                "the evidence, or remove a false entry, to enable it."
            ),
            "evidence": enabled_evidence,
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
    listing_axes: ListingAxes | None = None,
) -> dict:
    """Pure. Fleet + events + config + clock + horizons -> report model.

    `listing_axes` names the window and bytes-per-token values to budget for
    and carries the provenance of every budget input; without it the listing
    is the single row `listing_config` describes, which is the replay path.
    """
    tier = resolve_tier(set(horizons))
    events_by_skill, ambiguous_keys = resolve_event_keys(denominator, events)

    # The band mirrors the product, so it is scored the way the product scores:
    # from the NATIVE counters only, under the EXACT qualified key. `zPe` does no
    # bare-key fallback of its own -- when usage was recorded under a bare leaf
    # the product's own scorer sees zero for that listing entry too, so scoring
    # the merged total here would predict a truncation the product will not
    # perform. The merge below is for the observation count, which asks a
    # different question and wants every event.
    native_scores: dict[str, float] = {}
    for entry in denominator:
        name = entry["qualified_name"]
        native = [
            e
            for e in events_by_skill.get(name, [])
            if e.get("source") == "native" and e.get("skill") == name
        ]
        if not native:
            continue
        native_scores[name] = listing_score(
            sum(int(e.get("count", 1)) for e in native),
            max(e["ts"] for e in native),
            clock,
        )

    listing_cfg = listing_config or ListingConfig()
    if listing_axes is None:
        listing = compute_listing(denominator, listing_cfg, native_scores)
    else:
        listing = compute_listing_band(
            denominator, listing_cfg, listing_axes, native_scores
        )
        listing["inputs"] = listing_axes.inputs
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

    skills: list[dict] = []
    withheld: list[dict] = []

    # One entry for the run, not one per skill: the refusal is a property of the
    # ordering, and repeating it per row would bury the observation claims that
    # really are per skill.
    if starvation_withheld(listing):
        withheld.append(
            {
                "skill": None,
                "claim": "starvation",
                "reason": STARVATION_WITHHELD_REASON,
            }
        )

    for key, owners in ambiguous_keys:
        withheld.append(
            {
                "skill": key,
                "claim": "observation",
                "reason": (
                    f"bare usage key `{key}` matches {len(owners)} skills "
                    f"({', '.join(owners)}); attributing it would invent usage "
                    "for whichever one was picked"
                ),
            }
        )

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

    lines += _render_reachability(model["skills"])

    listing = model.get("listing", {})
    if listing:
        lines += ["## Listing budget", ""]
        band = listing.get("band")
        if band:
            lines += _render_band(listing)
            any_overflow = any(r["overflow_chars"] > 0 for r in band)
        else:
            lines += _render_single_budget(listing)
            any_overflow = listing["overflow_chars"] > 0
        if any_overflow:
            # An unscored run has no usage behind its ordering at all. Saying
            # "inferential" there would repeat the exact defect this report
            # exists to expose, one level up, so the two cases get different
            # prose rather than a shared hedge.
            if listing.get("score_basis") == "unscored":
                lines += [
                    "**No usage signal was available for any competing skill, so "
                    "*which* particular skills lost their descriptions is "
                    "withheld.** At all-zero scores the product's ordering is "
                    "the catalog position each skill happens to hold, which "
                    "carries no information about starvation likelihood. The "
                    "over-budget figure above is unaffected and still holds.",
                    "",
                ]
            else:
                lines += [
                    "*Which* particular skills lost theirs is inferential: the "
                    "ordering mirrors a scorer recovered from the shipped binary, "
                    "not a documented interface. Treat the ranking as a likelihood "
                    "band, not a cutoff line.",
                    "",
                ]
        lines += [
            f"- Exempt from the contest: {listing['exempt_count']} "
            f"(bundled, user-only, and disabled-plugin skills spend no budget)",
            "",
        ]
        if any_overflow:
            inputs = listing.get("inputs") or {}
            cap = (inputs.get("max_desc_chars") or {}).get("value")
            lines += _render_longest(model["skills"], cap)
        if listing.get("inputs"):
            lines += _render_inputs(listing["inputs"])
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

    lines += _render_next_actions(model)

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


def _render_reachability(skills: list[dict]) -> list[str]:
    """Per-value counts, the one checkout line, and the hidden table.

    A checkout run declines enablement once, for the run, rather than once
    per row. An installed run groups the hidden rows by owning plugin, since
    the cause is per plugin and the evidence is the scope file that set it.
    """
    counts: dict[str, int] = defaultdict(int)
    for row in skills:
        counts[row["reachability"]["value"]] += 1
    lines = ["## Reachability", ""]
    if counts.get("not-assessed"):
        lines += ["Reachability not assessed: a checkout is not an install.", ""]
    shown = [f"{value} {counts[value]}" for value in sorted(counts)]
    lines += ["- " + " · ".join(shown), ""]

    hidden: dict[str, dict] = {}
    for row in skills:
        reach = row["reachability"]
        if reach["value"] != "hidden":
            continue
        plugin = row["qualified_name"].partition(":")[0]
        bucket = hidden.setdefault(plugin, {"skills": 0, "evidence": reach["evidence"]})
        bucket["skills"] += 1
    if hidden:
        lines += [
            "Hidden: the owning plugin is installed but resolves to disabled "
            "(an `enabledPlugins` entry, or its `defaultEnabled` when no scope "
            "names it), so none of its skills load.",
            "",
            "| Plugin | Skills | Evidence |",
            "|---|---|---|",
        ]
        for plugin in sorted(hidden)[:10]:
            bucket = hidden[plugin]
            lines.append(
                f"| `{plugin}` | {bucket['skills']} | `{bucket['evidence']}` |"
            )
        lines.append("")
        if len(hidden) > 10:
            lines += [f"…and {len(hidden) - 10} more", ""]
    lines += _render_misconfigured(skills)
    return lines


def _render_misconfigured(skills: list[dict]) -> list[str]:
    """The misconfigured table, with each cause's remedy stated once.

    Every row here is a fix, never a removal candidate: the causes are silent,
    so a misconfigured skill reads exactly like an unwanted one until it is
    named. The remedy is keyed by cause rather than repeated per row, because
    two rows with the same cause need the same fix.
    """
    rows = sorted(
        (r for r in skills if r["reachability"]["value"] == "misconfigured"),
        key=lambda r: r["qualified_name"],
    )
    if not rows:
        return []
    lines = [
        "Misconfigured: the frontmatter gives the listing nothing reliable to "
        "match. Malformed frontmatter loads with no metadata at all; a missing "
        "description falls back to the first body paragraph, which may carry "
        "none of the keywords a request would use. Each row is a fix, not a "
        "removal candidate.",
        "",
        "| Skill | Cause |",
        "|---|---|",
    ]
    for row in rows[:10]:
        causes = ", ".join(row["reachability"]["causes"])
        lines.append(f"| `{row['qualified_name']}` | {causes} |")
    lines.append("")
    if len(rows) > 10:
        lines += [f"…and {len(rows) - 10} more", ""]
    causes_seen = sorted({c for r in rows for c in r["reachability"]["causes"]})
    lines += [f"- `{cause}`: {MISCONFIGURED_REMEDIES[cause]}" for cause in causes_seen]
    lines.append("")
    return lines


def _render_longest(skills: list[dict], cap: int | None) -> list[str]:
    """The longest competing descriptions by source length, with their charge.

    Rendered only when something overflows, because on a listing that fits
    there is nothing to trim. Ranked by the uncapped source length rather than
    the charge, since the charge saturates at `skillListingMaxDescChars` and
    would order every over-cap description by name; the charge is shown beside
    it because trimming lowers the overflow only once the source length is
    under the cap. It is arithmetic over length and is labelled that way:
    which skills LOSE their descriptions is a separate, usage-ordered claim
    that an unscored run withholds, and this table must not be read as that
    ranking.
    """
    competing = [r for r in skills if r["starvation"].get("eligibility") == "competing"]
    if not competing:
        return []

    def _source(row: dict) -> int:
        starvation = row["starvation"]
        return starvation.get("description_chars", starvation["demand_chars"])

    ranked = sorted(competing, key=lambda r: (-_source(r), r["qualified_name"]))
    cap_text = f"{cap:,}" if cap else "`skillListingMaxDescChars`"
    lines = [
        "Longest competing descriptions, ranked by source length. The listing "
        f"charges each description at most {cap_text} characters "
        "(`skillListingMaxDescChars`), shown as Charged, so trimming lowers the "
        "overflow only once a description is under that cap. This ranks "
        "length, not starvation, so it says nothing about which skills lose "
        "theirs.",
        "",
        "| Skill | Description chars | Charged |",
        "|---|---|---|",
    ]
    for row in ranked[:10]:
        lines.append(
            f"| `{row['qualified_name']}` | {_source(row):,} | "
            f"{row['starvation']['demand_chars']:,} |"
        )
    lines.append("")
    if len(ranked) > 10:
        lines += [f"…and {len(ranked) - 10} more competing", ""]
    return lines


def _budget_control(listing: dict) -> str:
    """The one budget input a reader can actually move, read from provenance.

    The fraction is the documented control, but it is not always the effective
    one: `SLASH_COMMAND_TOOL_CHAR_BUDGET` overrides it outright, a
    `--budget-fraction` pin changes this report and not the session, and a
    managed-policy value outranks every scope a user edits. Recommending the
    fraction in those cases would send the reader to a setting that cannot
    move the overflow they were shown.
    """
    inputs = listing.get("inputs") or {}
    if (inputs.get("env_char_budget") or {}).get("value") is not None:
        return (
            "raise `SLASH_COMMAND_TOOL_CHAR_BUDGET`, which overrides "
            "`skillListingBudgetFraction` in this environment"
        )
    fraction = inputs.get("budget_fraction") or {}
    provenance = str(fraction.get("provenance", ""))
    if provenance.startswith("pin:"):
        return (
            "raise `skillListingBudgetFraction` in settings; this run's "
            "`--budget-fraction` pin changes the report, not the session"
        )
    if provenance.startswith("settings:"):
        path = provenance.partition(":")[2]
        scope = next(
            (
                layer.get("scope")
                for layer in inputs.get("settings_scopes", [])
                if layer.get("path") == path
            ),
            None,
        )
        if scope == "policy":
            return (
                f"raise `skillListingBudgetFraction` in the managed policy at "
                f"`{path}`, which outranks every scope a user edits"
            )
        return (
            f"raise `skillListingBudgetFraction` above {fraction.get('value')} "
            f"in `{path}`"
        )
    return "raise `skillListingBudgetFraction` in settings"


def _render_next_actions(model: dict) -> list[str]:
    """One line naming the actions this run's findings support, and no other.

    Built only from conditions present in the model, so a clean run says there
    is nothing to fix rather than listing generic advice. Usage and token cost
    per skill belong to the bundled `/skill-doctor` and are not pointed at.
    """
    counts: dict[str, int] = defaultdict(int)
    for row in model["skills"]:
        counts[row["reachability"]["value"]] += 1
    listing = model.get("listing") or {}
    steps: list[str] = []
    if counts.get("misconfigured"):
        steps.append(
            f"fix the frontmatter of the {counts['misconfigured']} misconfigured "
            f"{_plural(counts['misconfigured'], 'skill')} listed under Reachability"
        )
    if counts.get("hidden"):
        steps.append(
            "enable the hidden plugins in the scope that disables them, or "
            "leave them off on purpose"
        )
    if listing and listing_overflows(listing):
        steps.append(
            "trim the longest competing descriptions, or " + _budget_control(listing)
        )
        if listing.get("score_basis") == "unscored":
            steps.append(
                "collect usage through the skill-usage hooks before trusting "
                "any per-skill starvation ranking"
            )
    lines = ["## Next actions", ""]
    if not steps:
        return lines + ["Nothing to fix from this run.", ""]
    joined = "; ".join(steps)
    return lines + [joined[0].upper() + joined[1:] + ".", ""]


def _render_single_budget(listing: dict) -> list[str]:
    """The pinned single-row paragraph."""
    if listing["overflow_chars"] > 0 and listing.get("score_basis") == "unscored":
        # The count is the whole claim here. Saying which skills are running
        # name-only would name the ones the catalog happens to list last.
        return [
            f"**Your skill listing is over budget by "
            f"{listing['overflow_chars']:,} characters** at "
            f"{listing['label']} (window {listing['context_window_tokens']:,} "
            f"tokens, {listing['bytes_per_token']} bytes per token). "
            f"{listing['competing_count']} skills compete for "
            f"{listing['budget_chars']:,} characters of description budget, "
            f"and **{listing['starved_count']}** of "
            f"{listing['competing_count']} competing descriptions cannot fit; "
            f"which ones is withheld because no usage has been observed, so "
            f"the ordering is catalog position, not preference.",
            "",
        ]
    if listing["overflow_chars"] > 0:
        # The certain half: documented settings vs summed description
        # lengths. No undocumented constant is involved, so this is stated
        # plainly rather than hedged.
        return [
            f"**Your skill listing is over budget by "
            f"{listing['overflow_chars']:,} characters** at "
            f"{listing['label']} (window {listing['context_window_tokens']:,} "
            f"tokens, {listing['bytes_per_token']} bytes per token). "
            f"{listing['competing_count']} skills compete for "
            f"{listing['budget_chars']:,} characters of description budget, "
            f"and descriptions are shed lowest-score-first, so roughly "
            f"**{listing['starved_count']}** of them are running name-only, "
            f"which is why the model stops matching requests to those.",
            "",
            f"The other {listing['competing_count'] - listing['starved_count']} "
            f"competing skills keep their descriptions. The score is "
            f"decay-weighted, not a raw invocation count, and the walk grants "
            f"whatever still fits rather than shedding a clean tail, so "
            f"description length matters too.",
            "",
        ]
    return [
        f"Listing fits at {listing['label']}: {listing['demand_chars']:,} of "
        f"{listing['budget_chars']:,} characters used by "
        f"{listing['competing_count']} competing skills. No description "
        f"is being dropped, so starvation is not the reason any skill "
        f"here goes unused.",
        "",
    ]


def _render_band(listing: dict) -> list[str]:
    """The unpinned band table. No row is named as this session's."""
    lines = [
        "The budget is `window x bytes-per-token x fraction`, and both the "
        "window and the bytes-per-token are per model. This run does not "
        "resolve the session's model, so every combination is reported and "
        "**no row below is this session**; pin one with `--context-window` "
        "and `--bytes-per-token` to collapse the band.",
        "",
        f"{listing['competing_count']} competing skills demand "
        f"{listing['demand_chars']:,} characters of description.",
        "",
        "| Row | Window | Bytes/token | Budget | Overflow | Verdict | Starved |",
        "|---|---|---|---|---|---|---|",
    ]
    for row in listing["band"]:
        lines.append(
            f"| {row['label']} | {row['context_window_tokens']:,} | "
            f"{row['bytes_per_token']} | {row['budget_chars']:,} | "
            f"{row['overflow_chars']:,} | {row['verdict']} | "
            f"{row['starved_count']} |"
        )
    lines.append("")
    return lines


def _render_inputs(inputs: dict) -> list[str]:
    """What was consulted for the budget, with provenance, as one short list."""

    def _prov(row: dict) -> str:
        provenance = row.get("provenance", "")
        if provenance == "default":
            return "documented default"
        if provenance == "fraction":
            return "documented default"
        return provenance

    lines = [
        "Inputs consulted:",
        "",
        f"- `skillListingBudgetFraction`: {inputs['budget_fraction']['value']} "
        f"({_prov(inputs['budget_fraction'])})",
        f"- `skillListingMaxDescChars`: {inputs['max_desc_chars']['value']} "
        f"({_prov(inputs['max_desc_chars'])})",
        f"- `SLASH_COMMAND_TOOL_CHAR_BUDGET`: "
        f"{inputs['env_char_budget']['provenance'].partition(' ')[2]}",
    ]
    for row in inputs.get("env", []):
        shown = (
            "unset" if row["value"] is None else f"`{row['value']}`: {row['effect']}"
        )
        lines.append(f"- `{row['name']}`: {shown}")
    lines.append(
        f"- Context window: {', '.join(f'{w:,}' for w in inputs['windows']['values'])} "
        f"({inputs['windows']['provenance']})"
    )
    lines.append(
        f"- Bytes per token: "
        f"{', '.join(str(b) for b in inputs['bytes_per_tokens']['values'])} "
        f"({inputs['bytes_per_tokens']['provenance']})"
    )
    scopes = []
    for layer in inputs.get("settings_scopes", []):
        detail = layer["status"]
        if layer.get("note"):
            detail += f": {layer['note']}"
        scopes.append(f"{layer['scope']} `{layer['path']}` ({detail})")
    lines.append(
        "- Settings scopes, lowest precedence first: " + "; ".join(scopes)
        if scopes
        else "- Settings scopes: none consulted"
    )
    for note in inputs.get("settings_ignored", []):
        lines.append(f"- Ignored: {note}")
    lines.append("")
    return lines


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
        default=None,
        help="pin the context window in TOKENS for the listing-budget "
        "arithmetic. Unpinned, the report carries both 200000 and 1000000 as "
        "a band unless CLAUDE_CODE_DISABLE_1M_CONTEXT or "
        "CLAUDE_CODE_MAX_CONTEXT_TOKENS (with DISABLE_COMPACT) settles it",
    )
    parser.add_argument(
        "--bytes-per-token",
        type=int,
        choices=(3, 4),
        default=None,
        help="pin the per-model bytes-per-token estimate (4 or 3). Unpinned, "
        "the band carries both",
    )
    parser.add_argument(
        "--budget-fraction",
        type=float,
        default=None,
        help="pin skillListingBudgetFraction instead of reading it from the "
        "settings scopes",
    )
    parser.add_argument(
        "--max-desc-chars",
        type=int,
        default=None,
        help="pin skillListingMaxDescChars instead of reading it from the "
        "settings scopes",
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
        # A replay is a recorded collection: the bundle's listing_config is
        # the single row it describes, and no settings or environment are
        # consulted on top of it.
        listing_axes = None
    else:
        # Live collection. Each source is optional: a missing one narrows the
        # tier rather than failing the run, which is the same honesty the
        # verdicts themselves apply.
        clock = _parse_ts(args.now) if args.now else datetime.now(tz=UTC)
        # CLAUDE_PROJECT_DIR is the project Claude Code itself resolved; cwd
        # is the fallback. Project/local install records are matched against
        # it, since those load only in their own project, and the project and
        # local settings scopes are read from its `.claude/`.
        current_project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
        # The settings scopes feed two consumers: the listing keys below, and
        # `enabledPlugins` for the installed fleet. One read, one merge walk,
        # the managed locations from the vendored managed-scope.sh, never
        # from a path written here. CLAUDE_CONFIG_DIR relocates the whole
        # ~/.claude tree, user settings included.
        config_root = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser(
            "~/.claude"
        )
        layers = settings_layers(
            current_project,
            config_root,
            enumerate_managed_scope(managed_scope_lib_path()),
        )
        if args.installed is not None:
            plugins_dir = args.installed or os.path.expanduser("~/.claude/plugins")
            denominator, resolution = collect_installed(
                plugins_dir, current_project, merge_enabled_plugins(layers)
            )
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
        listing_cfg, listing_axes = build_listing_inputs(
            {
                "context_window": args.context_window,
                "bytes_per_token": args.bytes_per_token,
                "budget_fraction": args.budget_fraction,
                "max_desc_chars": args.max_desc_chars,
            },
            os.environ,
            layers,
        )

    model = classify(
        denominator=denominator,
        events=events,
        config=cfg,
        clock=clock,
        horizons=horizons,
        listing_config=listing_cfg,
        listing_axes=listing_axes,
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
