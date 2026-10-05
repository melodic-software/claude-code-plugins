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
import shutil
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
# 1.3.0: reachability gains `not-enabled` (cause `plugin-never-enabled`);
# consumers keyed on `hidden` for "plugin off" must also accept it.
# 1.4.0: `hidden` gains cause `settings-file-rejected`.
# 1.5.0: `overflow_chars` is the whole rendered listing (`listing_chars`)
# over budget, not descriptions alone; `listing` and every band row gain
# `floor_chars` and `listing_chars` (band rows also `demand_chars`), `listing`
# gains `coverage` and, with --listing-capture, `capture`; eligibility gains
# `exempt-name-only`; rows may be user or project skills, plugin commands or
# workflows (`kind`).
# 1.6.0: `listing.verdict` and band rows gain `overflow-unconfirmed`;
# `listing.capture` gains `not_in_fleet`; a withheld starvation row may carry
# reason `capture-mismatch`.
SCHEMA_VERSION = "1.6.0"


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
#   reference/listing-scorer.md, beside this skill. Re-verified at 2.1.289,
#   together with the fit check `compute_listing` mirrors (the whole rendered
#   listing against the budget) and the 3-bytes-per-token default for every
#   model outside the product's 4-byte list.
# As-of: 2026-10-04, re-verified against Claude Code 2.1.289.
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


BLOCK_SCALAR = re.compile(r"^([|>])[+-]?\d*(?:\s+#.*)?$")
DOUBLE_QUOTED = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$', re.DOTALL)
SINGLE_QUOTED = re.compile(r"^'((?:[^']|'')*)'\s*(?:#.*)?$", re.DOTALL)
DOUBLE_QUOTED_ESCAPES = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "/": "/"}


def _fold_lines(lines: list[str], separator: str) -> str:
    """Join scalar lines the way YAML does: a blank line is a kept newline."""
    text = ""
    pending = 0
    for line in lines:
        if not line.strip():
            pending += 1
            continue
        if text:
            text += "\n" * pending if pending else separator
        text += line
        pending = 0
    return text


def _yaml_scalar(value: str, continuation: list[str]) -> str:
    """One scalar value as YAML loads it, for the forms skill files use.

    Block scalars (`>`, `|`, any chomping), quoted scalars with their
    escapes, and plain scalars continued on indented lines. The listing is
    charged for the loaded text, so measuring the raw source (`>-`, or each
    `\\"` as two characters) misstates what a description costs.
    """
    block = BLOCK_SCALAR.match(value)
    if block:
        indents = [len(ln) - len(ln.lstrip()) for ln in continuation if ln.strip()]
        cut = min(indents, default=0)
        body = [line[cut:] for line in continuation]
        # No trailing newline whatever the chomping indicator: Claude Code
        # 2.1.289 listed a `description: |` skill without the newline YAML
        # keeps, one character shorter than a literal YAML load.
        if block.group(1) == ">":
            return _fold_lines(body, " ")
        return "\n".join(body).rstrip("\n")
    joined = _fold_lines([value] + [line.strip() for line in continuation], " ")
    double = DOUBLE_QUOTED.match(joined)
    if double:
        return re.sub(
            r"\\(.)",
            lambda m: DOUBLE_QUOTED_ESCAPES.get(m.group(1), m.group(0)),
            double.group(1),
        )
    single = SINGLE_QUOTED.match(joined)
    if single:
        return single.group(1).replace("''", "'")
    return re.sub(r"\s+#.*$", "", joined)


def parse_frontmatter(text: str) -> dict:
    """Minimal YAML-frontmatter read for the fields reachability needs.

    Deliberately not a YAML parser: this reads five scalar keys out of a fenced
    block, and anything it cannot parse is reported as `_malformed` rather than
    guessed. A real parser would be a third-party dependency the sibling engines
    do not take, and a wrong-but-confident parse is worse here than an honest
    "cannot tell" -- `misconfigured` is a fix-me, not a delete-me. Scalar
    values are read in the forms `_yaml_scalar` names, so a description is
    measured at the length the listing charges for it.
    """
    if not text.startswith("---"):
        return {"_malformed": True}
    end = text.find("\n---", 3)
    if end == -1:
        return {"_malformed": True}
    block = text[3:end]

    out: dict = {}
    lines = block.splitlines()
    index = 0
    while index < len(lines):
        raw = lines[index]
        index += 1
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[:1] in (" ", "\t") or ":" not in raw:
            continue
        key, _, value = raw.partition(":")
        continuation: list[str] = []
        while index < len(lines) and (
            not lines[index].strip() or lines[index][:1] in (" ", "\t")
        ):
            continuation.append(lines[index])
            index += 1
        out[key.strip()] = _yaml_scalar(value.strip(), continuation)
    if not out:
        return {"_malformed": True}

    return {
        "name": out.get("name", ""),
        "description": out.get("description", ""),
        "when_to_use": out.get("when_to_use", ""),
        "disable_model_invocation": str(
            out.get("disable-model-invocation", out.get("disable_model_invocation", ""))
        ).lower()
        == "true",
        "user_invocable": out.get("user-invocable", out.get("user_invocable", "")),
    }


def parse_command_frontmatter(text: str) -> dict:
    """`parse_frontmatter` for a plugin command, whose frontmatter is optional.

    A command file with no `---` block carries no metadata rather than broken
    metadata: Claude Code describes it by the prompt's first line, so that line
    is what the listing charges. An opened block left unterminated is still
    malformed.
    """
    if text.startswith("---"):
        return parse_frontmatter(text)
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return {
        "name": "",
        "description": first,
        "when_to_use": "",
        "disable_model_invocation": False,
        "user_invocable": "",
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
    plugin_key: str | None = None,
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
    disabled plugin's skills as reachable. `plugin_key` is the
    `plugin@marketplace` id an install carries, so a remedy can name it.
    """
    entries: list[dict] = []
    for kind, leaf, path, frontmatter in _plugin_listing_files(plugin_root):
        entries.append(
            {
                "qualified_name": f"{plugin}:{leaf}",
                "source": "plugin",
                "kind": kind,
                "plugin_enabled": plugin_enabled,
                "plugin_enabled_evidence": plugin_enabled_evidence,
                "plugin_key": plugin_key,
                "frontmatter": frontmatter,
                "path": path,
            }
        )
    return entries


def _read_text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return None


def _plugin_listing_files(plugin_root: str) -> list[tuple[str, str, str, dict]]:
    """Every file a plugin contributes to the skill listing, as (kind, leaf,
    path, frontmatter).

    The listing names a plugin's `commands/*.md` and its `workflows/*.js`
    beside its skills, each charged like a skill, so all three are counted.
    """
    found: list[tuple[str, str, str, dict]] = []
    skills_dir = os.path.join(plugin_root, "skills")
    if os.path.isdir(skills_dir):
        for leaf in sorted(os.listdir(skills_dir)):
            path = os.path.join(skills_dir, leaf, "SKILL.md")
            if os.path.isfile(path):
                text = _read_text(path)
                frontmatter = (
                    {"_malformed": True} if text is None else parse_frontmatter(text)
                )
                found.append(("skill", leaf, path, frontmatter))
    commands_dir = os.path.join(plugin_root, "commands")
    if os.path.isdir(commands_dir):
        for name in sorted(os.listdir(commands_dir)):
            path = os.path.join(commands_dir, name)
            if name.endswith(".md") and os.path.isfile(path):
                text = _read_text(path)
                frontmatter = (
                    {"_malformed": True}
                    if text is None
                    else parse_command_frontmatter(text)
                )
                found.append(("command", name[: -len(".md")], path, frontmatter))
    workflows_dir = os.path.join(plugin_root, "workflows")
    if os.path.isdir(workflows_dir):
        for name in sorted(os.listdir(workflows_dir)):
            path = os.path.join(workflows_dir, name)
            if name.endswith(".js") and os.path.isfile(path):
                meta = parse_workflow_meta(_read_text(path) or "")
                if meta is not None:
                    leaf = meta.pop("name", "") or name[: -len(".js")]
                    found.append(("workflow", leaf, path, meta))
    return found


SKILL_OVERRIDE_VALUES = ("on", "name-only", "user-invocable-only", "off")


def collect_local_skills(
    skills_dir: str, source: str, overrides: Mapping[str, str]
) -> list[dict]:
    """User (`~/.claude/skills`) or project (`.claude/skills`) skills.

    Listed beside plugin skills and charged the same way, but governed by
    `skillOverrides` rather than `enabledPlugins`; the entry carries its
    override so eligibility and reachability can apply it. Subfolders without
    a `SKILL.md` (such as the claude.ai `synced` tree) are not walked. A user
    or project skill is listed under its frontmatter `name` when it sets one,
    else under its folder name.
    """
    entries: list[dict] = []
    if not os.path.isdir(skills_dir):
        return entries
    for leaf in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, leaf, "SKILL.md")
        if not os.path.isfile(path):
            continue
        text = _read_text(path)
        frontmatter = {"_malformed": True} if text is None else parse_frontmatter(text)
        configured = frontmatter.get("name")
        name = (
            configured
            if source in ("user", "project")
            and isinstance(configured, str)
            and configured
            else leaf
        )
        # Two folders declaring one `name` list once; the first in folder
        # order is the one counted.
        if any(e["qualified_name"] == name for e in entries):
            continue
        entries.append(
            {
                "qualified_name": name,
                "source": source,
                "kind": "skill",
                "skill_override": overrides.get(name, "on"),
                "frontmatter": frontmatter,
                "path": path,
            }
        )
    return entries


def _project_skill_dirs(project: str) -> list[str]:
    """Every `.claude/skills` loaded at startup, the repository root's first.

    Claude Code loads project skills from the starting directory and each
    parent up to the repository root. Skills under directories below the
    starting one load only once the session works there, so no static walk
    can count them.
    """
    chain = []
    current = os.path.abspath(project)
    while True:
        chain.append(current)
        if os.path.exists(os.path.join(current, ".git")):
            break
        parent = os.path.dirname(current)
        if parent == current:
            # No repository above: only the starting directory loads.
            chain = chain[:1]
            break
        current = parent
    return [os.path.join(d, ".claude", "skills") for d in reversed(chain)]


def collect_user_and_project_skills(
    config_root: str, project: str, overrides: Mapping[str, str]
) -> list[dict]:
    """User skills, then the project's, resolved the way Claude Code resolves
    a shared name: personal over project, and a nested project skill whose
    name a skill nearer the root already took listed as `<relative path>:<name>`.
    """
    user_dir = os.path.join(config_root, "skills")
    entries = collect_local_skills(user_dir, "user", overrides)
    taken = {e["qualified_name"] for e in entries}
    user_names = set(taken)
    root = None
    for skills_dir in _project_skill_dirs(project):
        if os.path.normcase(os.path.abspath(skills_dir)) == os.path.normcase(
            os.path.abspath(user_dir)
        ):
            continue
        base = os.path.dirname(os.path.dirname(skills_dir))
        root = root or base
        for entry in collect_local_skills(skills_dir, "project", overrides):
            name = entry["qualified_name"]
            if name in user_names:
                continue
            if name in taken:
                prefix = os.path.relpath(base, root).replace(os.sep, "/")
                name = f"{prefix}:{name}"
                entry["qualified_name"] = name
                entry["skill_override"] = overrides.get(name, "on")
            taken.add(name)
            entries.append(entry)
    return entries


SYNCED_PREFIX = "anthropic-skills:"


def synced_skills_folder(config_root: str, claude_json_path: str) -> str | None:
    """The signed-in account's synced-skills folder, or None with no account."""
    try:
        with open(claude_json_path, encoding="utf-8") as handle:
            account = (json.load(handle) or {}).get("oauthAccount") or {}
    except (OSError, ValueError, AttributeError):
        return None
    org, user = account.get("organizationUuid"), account.get("accountUuid")
    if not (isinstance(org, str) and isinstance(user, str) and org and user):
        return None
    return os.path.join(config_root, "skills", "synced", f"{org}_{user}")


def collect_synced_skills(
    config_root: str, claude_json_path: str, overrides: Mapping[str, str]
) -> list[dict]:
    """The signed-in account's claude.ai-synced skills.

    They sync under `<config>/skills/synced/<organizationUuid>_<accountUuid>/`,
    one folder per account that has signed in, and list as
    `anthropic-skills:<name>`; only the folder of the account in
    `~/.claude.json` (`oauthAccount`) is the one loaded. Verified against
    Claude Code 2.1.289 (the `anthropic-skills:` prefix in the shipped binary,
    the folder of the signed-in account matching the nine synced entries a
    session listed); recheck when a release note names synced skills. With no
    signed-in account readable, nothing is enumerated and a capture is the
    only way to count them.
    """
    folder = synced_skills_folder(config_root, claude_json_path)
    if folder is None:
        return []
    entries = collect_local_skills(folder, "synced", {})
    for entry in entries:
        leaf = entry["qualified_name"]
        entry["qualified_name"] = SYNCED_PREFIX + leaf
        entry["skill_override"] = overrides.get(
            entry["qualified_name"], overrides.get(leaf, "on")
        )
    return entries


def merge_skill_overrides(layers: list[dict]) -> dict[str, str]:
    """`skillOverrides` merged per skill name, a later scope winning.

    A file Claude Code rejects for a non-Boolean `enabledPlugins` value
    contributes nothing, as in `merge_listing_settings`.
    """
    merged: dict[str, str] = {}
    for layer in layers:
        settings = layer.get("settings")
        if not isinstance(settings, dict) or _non_boolean_plugins(settings):
            continue
        block = settings.get("skillOverrides")
        if not isinstance(block, dict):
            continue
        for name, value in block.items():
            if value in SKILL_OVERRIDE_VALUES:
                merged[name] = value
    return merged


JS_STRING = r"""('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)"""
WORKFLOW_META = re.compile(r"export\s+const\s+meta\s*=\s*\{")


def _js_string_field(block: str, key: str) -> str:
    match = re.search(rf"(?m)^\s*{key}\s*:\s*{JS_STRING}", block)
    if not match:
        return ""
    return re.sub(
        r"\\(.)",
        lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)),
        match.group(1)[1:-1],
    )


def parse_workflow_meta(text: str) -> dict | None:
    """The `name`, `description` and `whenToUse` of a workflow's `meta` export.

    Reads string literals only; a workflow without a `meta` export is not
    listed and returns None. The listing renders a workflow's
    `description - whenToUse` exactly as it renders a skill's two fields.
    """
    start = WORKFLOW_META.search(text)
    if not start:
        return None
    block = text[start.end() :]
    return {
        "name": _js_string_field(block, "name"),
        "description": _js_string_field(block, "description"),
        "when_to_use": _js_string_field(block, "whenToUse"),
        "disable_model_invocation": False,
        "user_invocable": "",
    }


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
    current_project: str | None,
    enabled_plugins: dict,
) -> tuple[list[dict], dict]:
    """Read the installed manifest + marketplace registry into a denominator.

    Returns the denominator entries and the resolution report, so the caller
    can surface superseded and inapplicable records rather than absorbing them.

    `enabled_plugins` is `merge_enabled_plugins` over the settings layers; it
    decides `plugin_enabled` per `plugin@marketplace` key. It is required:
    a key no scope names resolves to not enabled, so a caller that skipped
    the settings read would report every plugin off.
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
    # reads). A directory-source marketplace needs it so the resolver honors
    # the plugin's DECLARED source path instead of assuming a layout. A
    # missing or unparsable catalog attaches an empty list.
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
    denominator: list[dict] = []
    for row in resolution["plugins"]:
        key = f"{row['plugin']}@{row['marketplace']}"
        state = enablement_for(enabled_plugins, key)
        denominator += collect_fleet_at(
            row["root"], row["plugin"], state["value"], state["evidence"], key
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


# -- Verification stamp (docs/conventions/upstream-drift) ----------------------
# Claim: a session transcript (`~/.claude/projects/<project>/<session>.jsonl`)
#   records the listing the model received as an `attachment` line of type
#   `skill_listing` carrying `content` (the rendered listing, entries joined by
#   newlines), `names` (entry names in order), `skillCount` and `isInitial`; a
#   `model` attachment carries `identity.modelId`.
# Basis: observed in a Claude Code 2.1.289 transcript, where `content` was
#   149,934 characters for 289 names and matched the rendered entries plus
#   288 newlines exactly. Not a published format.
# As-of: 2026-10-04, Claude Code 2.1.289.
# Recheck trigger: a release note naming transcripts or the skill listing, or
#   this reader returning `not-read` on a fresh transcript.
# On mismatch: the capture reports `not-read` with its reason and the verdict
#   falls back to enumerated coverage; nothing is guessed from a partial parse.
# -----------------------------------------------------------------------------
def parse_listing_capture(lines: list[str]) -> dict:
    """The last full skill listing in a transcript, split into entries.

    Only an initial listing (`isInitial` not false) is read: a later delta
    names the skills added since, not the whole listing.
    """
    listing = None
    model = None
    for raw in lines:
        try:
            record = json.loads(raw)
        except ValueError:
            continue
        attachment = record.get("attachment") if isinstance(record, dict) else None
        if not isinstance(attachment, dict):
            continue
        if attachment.get("type") == "model":
            model = (attachment.get("identity") or {}).get("modelId") or model
        elif (
            attachment.get("type") == "skill_listing"
            and attachment.get("isInitial") is not False
        ):
            listing = attachment
    if listing is None:
        return {"status": "not-read", "reason": "no skill_listing attachment found"}
    content, names = listing.get("content"), listing.get("names")
    if not isinstance(content, str) or not isinstance(names, list) or not names:
        return {"status": "not-read", "reason": "skill_listing lacks content or names"}
    entries: list[dict] = []
    position = 0
    for index, name in enumerate(names):
        head = f"- {name}"
        if not content.startswith(head, position):
            return {
                "status": "not-read",
                "reason": f"entry {index + 1} does not start with {head!r}",
            }
        end = (
            content.find(f"\n- {names[index + 1]}", position + len(head))
            if index + 1 < len(names)
            else len(content)
        )
        if end == -1:
            return {"status": "not-read", "reason": f"entry {index + 2} not found"}
        text = content[position:end]
        if text != head and not text.startswith(head + ": "):
            return {"status": "not-read", "reason": f"entry {head!r} is malformed"}
        entries.append(
            {"name": name, "rendered_chars": len(text), "name_only": text == head}
        )
        position = end + 1
    return {
        "status": "read",
        "model": model,
        "skill_count": len(entries),
        "chars": len(content),
        "entries": entries,
    }


def read_listing_capture(path: str) -> dict:
    """Read an operator-supplied transcript; never launches Claude Code."""
    try:
        with open(path, encoding="utf-8") as handle:
            capture = parse_listing_capture(handle.read().splitlines())
    except OSError as exc:
        capture = {"status": "not-read", "reason": str(exc)}
    capture["path"] = path
    return capture


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
        result = subprocess.run(
            args, capture_output=True, text=True, check=False, timeout=15
        )
    except (OSError, subprocess.TimeoutExpired):
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
    Pure, so the precedence rule is testable without a settings tree. A file
    Claude Code rejects for a non-Boolean `enabledPlugins` value contributes
    nothing (record at `merge_enabled_plugins`).
    """
    merged = {
        key: {"value": None, "provenance": "default"} for key in LISTING_SETTINGS_KEYS
    }
    ignored: list[str] = []
    for layer in layers:
        settings = layer.get("settings")
        if not isinstance(settings, dict):
            continue
        offending = _non_boolean_plugins(settings)
        if offending:
            if any(key in settings for key in LISTING_SETTINGS_KEYS):
                ignored.append(
                    f"listing settings in {layer.get('path')} left out of the "
                    f"merge: Claude Code rejects the file, whose "
                    f"{ENABLED_PLUGINS_KEY} holds a non-Boolean value "
                    f"({', '.join(offending)})"
                )
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


def _non_boolean_plugins(settings: dict) -> list[str]:
    """Each non-Boolean `enabledPlugins` entry, as `'key' is value`."""
    block = settings.get(ENABLED_PLUGINS_KEY)
    if not isinstance(block, dict):
        return []
    return [f"{k!r} is {v!r}" for k, v in block.items() if not isinstance(v, bool)]


def merge_enabled_plugins(layers: list[dict]) -> dict:
    """Per-key merge of `enabledPlugins` over layers given in ASCENDING precedence.

    The same walk as `merge_listing_settings`, over the same layer shape, for
    one more key: the object mapping `plugin-name@marketplace-name` to a
    Boolean. The product merges it per key, user < project < local < flag <
    policy, last defined scope wins. Precedence basis: the settings reference,
    https://code.claude.com/docs/en/settings, verified 2026-09-11 at Claude
    Code 2.1.263; recheck trigger: that page changing the `enabledPlugins`
    shape or its stated precedence. A key absent from every scope means NOT
    enabled; `enablement_for` carries that record.

    Returns `plugins` (per key, the winning `value` and the `evidence` path
    that supplied it), `unreadable` (settings FILES that exist but could not
    be read or parsed), `unread` (scope names that carry no file to read: the
    in-session flag scope always, and the managed scope when it could not be
    enumerated), `ignored` (blocks left out, each naming the offending key)
    and `rejected` (per key a rejected file named, the evidence for it). An
    unreadable file could have set any key at its own precedence, so a key
    whose winning value comes from below one resolves to `None` with the
    unreadable file as evidence. An unread scope does not poison the merge,
    as with the listing keys; it is named in the evidence of a key no scope
    carries.

    One non-Boolean value leaves out the file's whole block, Boolean siblings
    included, and the other scopes still decide every key it named. Claim:
    Claude Code rejects a settings file whose `enabledPlugins` holds any
    non-Boolean value and reads its keys as if that file set none. Basis: a
    fixture probe on Claude Code 2.1.280 with `CLAUDE_CONFIG_DIR` pointed at
    a scratch directory: `claude plugin list --json` read `true` disabled
    beside a `"yes"` (or `1`) in the same user file, a project file holding
    one lost its `false` to the user file's `true`, and `claude doctor`
    listed the value under "Invalid settings". The settings reference types
    the key as an object of Booleans and says a value the schema rejects
    skips the file (https://code.claude.com/docs/en/settings#fix-a-broken-settings-file),
    without naming this key. Verified 2026-09-28. Recheck trigger: a release
    that changes `claude plugin list`'s answer for a `true` beside a
    non-Boolean value, or that doc section naming per-entry handling for
    `enabledPlugins`.
    """
    plugins: dict[str, dict] = {}
    unreadable: list[tuple[int, str]] = []
    unread: list[str] = []
    ignored: list[str] = []
    rejected: dict[str, str] = {}
    for index, layer in enumerate(layers):
        path = layer.get("path")
        status = layer.get("status")
        if status == "unreadable" and path:
            unreadable.append((index, path))
            continue
        if status == "unread" or (status == "unreadable" and not path):
            scope = layer.get("scope")
            if scope and scope not in unread:
                unread.append(scope)
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
        offending = _non_boolean_plugins(settings)
        if offending:
            note = f"{path}, where {', '.join(offending)}"
            ignored.append(
                f"{ENABLED_PLUGINS_KEY} in {path} holds a non-Boolean value "
                f"({', '.join(offending)}); every key in it left out of the merge"
            )
            for key in block:
                rejected[key] = REJECTED_FILE + note
            continue
        for key, value in block.items():
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
        "unread": unread,
        "ignored": ignored,
        "rejected": rejected,
    }


# The evidence a key no readable scope carries resolves to, the provenance
# of the rule behind it, and the shape a key must have before it is
# interpolated into a suggested shell command.
NEVER_ENABLED = "no enabledPlugins scope names this plugin"
NEVER_ENABLED_PROVENANCE = (
    "observed: claude plugin list --json fixture probe, Claude Code 2.1.280; "
    "the plugins reference's defaultEnabled states otherwise"
)
UNREAD_MARKER = "; scopes not read: "
REJECTED_FILE = "named only in a settings file Claude Code rejects: "
REJECTED_FILE_PROVENANCE = (
    "observed: claude plugin list --json fixture probe, Claude Code 2.1.280; "
    "the docs do not name this key's handling"
)
SAFE_PLUGIN_KEY = re.compile(r"[A-Za-z0-9._-]+@[A-Za-z0-9._-]+")


def enablement_for(merged: dict, key: str) -> dict:
    """The enablement answer for one `plugin@marketplace` key.

    `merged` is `merge_enabled_plugins` output. A key it names is answered
    from the scope that set it, or is `None` naming the unreadable file above
    that scope. When any settings file was unreadable an absence is not
    knowable, so the answer is `None` naming the file, never a guess.

    A key absent from every readable scope is NOT enabled, whatever
    `defaultEnabled` its marketplace entry or manifest carries. Claim: an
    installed plugin loads only when an `enabledPlugins` scope sets it true.
    Basis: a fixture probe of `claude plugin list --json` on Claude Code
    2.1.280 reported disabled every installed plugin no scope named, including
    one whose marketplace entry and one whose `plugin.json` set
    `defaultEnabled: true`; the settings reference `#enabledplugins` agrees
    for marketplace plugins, the plugins reference `#defaultenabled` states
    the opposite. Verified
    2026-09-23, re-measured 2026-09-28. Recheck trigger: a release that changes `claude plugin list`'s
    `enabled` answer for an absent key, or either doc section changing. The
    evidence names any scope that could not be read at all.

    A key only a rejected file named is not enabled either, and its evidence
    names that file and the non-Boolean value that got it rejected.
    """
    row = merged["plugins"].get(key)
    if row is not None:
        return dict(row)
    if merged["unreadable"]:
        return {"value": None, "evidence": ", ".join(merged["unreadable"])}
    if key in merged.get("rejected", {}):
        return {"value": False, "evidence": merged["rejected"][key]}
    evidence = NEVER_ENABLED
    if merged.get("unread"):
        evidence += UNREAD_MARKER + ", ".join(merged["unread"])
    return {"value": False, "evidence": evidence}


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


def _stub_layer(scope: str, path: str | None, status: str, note: str | None) -> dict:
    """A scope that carries no settings, only the reason it carries none."""
    return {
        "scope": scope,
        "path": path,
        "status": status,
        "settings": None,
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

    def _unreadable(reason: str) -> dict:
        return {"status": "unreadable", "lib": lib_path, "reason": reason}

    if not os.path.isfile(lib_path):
        return _unreadable("vendored lib/managed-scope.sh is missing")
    if not os.path.dirname(bash):
        # Windows CreateProcess searches System32 before PATH and would run
        # the WSL relay bash.exe; resolve the name the way PATH does.
        resolved = shutil.which(bash)
        if resolved is None:
            return _unreadable(f"{bash} is not on PATH")
        bash = resolved
    try:
        result = subprocess.run(
            [bash, "-c", MANAGED_SCOPE_SHIM, "managed-scope", lib_path, override or ""],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
    except OSError as exc:
        return _unreadable(f"{bash} could not be run: {exc.strerror or exc}")
    except subprocess.TimeoutExpired:
        return _unreadable(f"{bash} did not finish enumerating managed scope")
    if result.returncode != 0:
        return _unreadable(
            f"{bash} exited {result.returncode} sourcing the lib: "
            f"{result.stderr.strip() or 'no stderr'}"
        )
    groups: list[list[str]] = [[]]
    for line in result.stdout.splitlines():
        line = line.rstrip("\r")
        if line == "--":
            groups.append([])
        elif line:
            groups[-1].append(line)
    if len(groups) != 3 or len(groups[0]) != 2:
        return _unreadable("managed-scope output was not the expected shape")
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
        _stub_layer("flag", "--settings", "unread", FLAG_SCOPE_NOTE),
    ]
    if managed.get("status") != "read":
        layers.append(
            _stub_layer(
                "policy",
                None,
                "unreadable",
                managed.get("reason") or "managed scope could not be enumerated",
            )
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
                _stub_layer(
                    "policy", dropin, "absent", "drop-in directory holds no *.json"
                )
            )
    else:
        layers.append(_stub_layer("policy", dropin, "absent", None))
    for surface in managed.get("unread_surfaces") or []:
        layers.append(
            _stub_layer(
                "policy", surface, "unread", "policy surface this reader does not open"
            )
        )
    return layers


# --- Context window and bytes per token ---------------------------------------
#
# Both are per model, and this script never resolves the model from disk: the
# session's model is not written anywhere an out-of-process reader can trust.
# The honest static report is a band over every combination, collapsed only by
# an operator pin or by an environment variable the product itself honors.
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
    honored, what was ignored, and why. A pin is the operator's own statement
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
            effect = "ignored: honored only when DISABLE_COMPACT is also set"
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
        consulted.append(
            {
                "name": "CLAUDE_CODE_DISABLE_1M_CONTEXT",
                "value": disable_1m,
                "effect": (
                    "window 200,000"
                    if _env_truthy(disable_1m)
                    else "not truthy: no effect"
                ),
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
    nothing either. `exempt-hidden` covers both not-loading answers, `hidden`
    and `not-enabled`; only a settled not-loading answer exempts, because
    `None` (not assessed, or undetermined) keeps competing.
    `skillOverrides` applies to non-plugin (user and project) skills only:
    `off` drops the entry, `user-invocable-only` keeps it out of the model's
    listing, and `name-only` lists the name and never competes for a
    description (`exempt-name-only`).
    """
    frontmatter = entry.get("frontmatter") or {}
    override = entry.get("skill_override")
    if entry.get("source") == "bundled":
        return "exempt-bundled"
    if entry.get("plugin_enabled") is False or override == "off":
        return "exempt-hidden"
    if frontmatter.get("disable_model_invocation") or override == "user-invocable-only":
        return "exempt-user-only"
    if override == "name-only":
        return "exempt-name-only"
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
    unenumerated: list[dict] | None = None,
    capture_covers: bool = True,
    capture_stale: bool = False,
) -> dict:
    """Budget arithmetic, split by confidence.

    CERTAIN: whether the listing overflows and by how much -- the whole
    rendered listing against the budget, the same comparison the product
    makes. Every listed entry renders `- <name>: <description>` (name + 4 +
    capped description) or, name-only, `- <name>` (name + 2), and entries are
    joined by one newline each. Comparing the descriptions alone against the
    budget left out every name, every `: ` and every newline, and on a fleet
    of about 290 skills that hid an over-budget listing behind "fits".

    `unenumerated` carries entries a captured listing showed that no disk walk
    found (built-in, bundled and claude.ai-synced skills), each at its captured
    rendered length. They are a fixed cost: the capture shows what they took,
    and a captured name-only entry's description length is unknown, so the
    total is a lower bound whenever one is present. `capture_stale` says the
    capture also named entries this fleet no longer has, so it came from a
    different fleet: an overflow that only its charges produce is then
    `overflow-unconfirmed`, never `overflowing`.

    INFERENTIAL: which particular skills lose their descriptions. That ordering
    comes from a scorer recovered from one build of the product (see
    `listing_score`), so it is rendered as a ranked band and labeled, never as
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
    # The full rendering, every description granted: what the product compares
    # with the budget to decide whether the listing fits at all.
    full = 0
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
                full += name_chars + 4 + desc_chars
            elif eligibility == "exempt-name-only":
                floor += name_chars + 2
                full += name_chars + 2
            else:
                floor += name_chars + 2
                full += name_chars + 4 + desc_chars
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

    # The counted entries alone, before any capture charge: an overflow here
    # holds whatever fleet the capture came from.
    enumerated_full = full + max(0, listed - 1)
    extra = unenumerated or []
    extra_chars = sum(e["rendered_chars"] for e in extra)
    listed += len(extra)
    floor += extra_chars
    full += extra_chars
    separators = max(0, listed - 1)
    floor += separators
    full += separators

    overflow = max(0, full - budget)
    # Overflow survives missing entries, since adding one only grows the
    # listing. A fit does not: without a capture the built-in and bundled
    # entries go uncounted, so the counted ones fitting is not the listing
    # fitting, and the verdict says so instead of claiming it. A capture
    # confirms a fit only when it covers the counted fleet (`capture_covers`):
    # one from a session that loaded a different fleet says nothing about this
    # one.
    fits = (
        "listing-fits"
        if unenumerated is not None and capture_covers
        else "fit-unconfirmed"
    )
    # The mirror image: a capture of another fleet cannot confirm an overflow
    # its own charges produce.
    unconfirmed = overflow > 0 and capture_stale and enumerated_full <= budget
    if unconfirmed:
        verdict = "overflow-unconfirmed"
    else:
        verdict = "overflowing" if overflow > 0 else fits

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
    # higher-scored one was refused. Modeling this as a prefix understated the
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
        # A grant costs the description plus its `: ` joiner: the entry grows
        # from `- <name>` to `- <name>: <description>`.
        grant = row["demand_chars"] + 2
        if overflow <= 0:
            row["verdict"] = fits
        elif grant <= remaining:
            remaining -= grant
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
    if unconfirmed or (overflow > 0 and score_basis == "unscored"):
        for row in competing:
            row["verdict"] = "withheld"
            row["reason"] = "capture-mismatch" if unconfirmed else "unscored"
            row["band"] = None

    return {
        # The env override sets the budget whatever the window and bytes per
        # token, so its row is named for the variable, not for those axes.
        "label": "SLASH_COMMAND_TOOL_CHAR_BUDGET"
        if cfg.env_char_budget is not None
        else band_label(cfg.context_window_tokens, cfg.bytes_per_token),
        "context_window_tokens": cfg.context_window_tokens,
        "bytes_per_token": cfg.bytes_per_token,
        "budget_chars": budget,
        "budget_basis": budget_basis(cfg),
        "demand_chars": demand,
        "floor_chars": floor,
        "listing_chars": full,
        "overflow_chars": overflow,
        "verdict": verdict,
        "coverage": "enumerated+capture"
        if unenumerated is not None
        else "enumerated-only",
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
    "demand_chars",
    "floor_chars",
    "listing_chars",
    "overflow_chars",
    "verdict",
    "starved_count",
)


def compute_listing_band(
    denominator: list[dict],
    cfg: ListingConfig,
    axes: ListingAxes,
    scores: dict[str, float] | None = None,
    unenumerated: list[dict] | None = None,
    capture_covers: bool = True,
    capture_stale: bool = False,
) -> dict:
    """The listing budget over every window x bytes-per-token combination.

    One combination (a pin on both axes, or the env override, which makes both
    axes moot) returns the single-row shape `compute_listing` produces, so
    consumers of that shape are unaffected. More than one returns the same
    top-level keys with the per-row numbers nulled, `budget_basis: "band"`,
    and the rows under `band`, each labeled and carrying its own numbers. No
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
        return compute_listing(
            denominator, cfg, scores, unenumerated, capture_covers, capture_stale
        )
    rows = [
        compute_listing(
            denominator,
            replace(cfg, context_window_tokens=window, bytes_per_token=bpt),
            scores,
            unenumerated,
            capture_covers,
            capture_stale,
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
        "floor_chars": rows[0]["floor_chars"],
        "listing_chars": rows[0]["listing_chars"],
        "overflow_chars": None,
        "verdict": verdicts.pop() if len(verdicts) == 1 else "band-dependent",
        "coverage": rows[0]["coverage"],
        "score_basis": rows[0]["score_basis"],
        "competing_count": rows[0]["competing_count"],
        "starved_count": None,
        "exempt_count": rows[0]["exempt_count"],
        "band": [{k: r[k] for k in BAND_ROW_FIELDS} for r in rows],
        "skills": skills,
    }


STARVATION_WITHHELD_REASON = "unscored: ordering is catalog-order tie, not usage"
CAPTURE_MISMATCH_REASON = (
    "capture-mismatch: the overflow rests on a capture of a different fleet"
)


def starvation_withheld(listing: dict) -> bool:
    """Whether this run refused to name WHICH descriptions the budget sheds.

    True exactly when something overflows with no usage behind the ordering:
    the contest is then decided by the catalog-order tie the product's stable
    sort leaves, and catalog position is not a preference. Reads the same for a
    pinned single row and for a band, where one overflowing row is enough.
    """
    return listing.get("score_basis") == "unscored" and listing_overflows(listing)


def listing_overflows(listing: dict) -> bool:
    """Whether any budget row overflows: one row is enough for a band.

    An `overflow-unconfirmed` row does not count: only a capture of another
    fleet makes it overflow.
    """
    return any(
        row.get("overflow_chars") and row.get("verdict") != "overflow-unconfirmed"
        for row in listing.get("band") or [listing]
    )


def listing_overflow_unconfirmed(listing: dict) -> bool:
    """Whether any budget row overflows only on a mismatched capture's charges."""
    return any(
        row.get("verdict") == "overflow-unconfirmed"
        for row in listing.get("band") or [listing]
    )


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


def _not_loaded(entry: dict, evidence: str) -> dict:
    """Reachability of a skill whose owning plugin settles to not loading.

    Three causes with different remedies: an `enabledPlugins` entry set the
    plugin false (`hidden`), only a settings file Claude Code rejects names
    it (`hidden`), or no scope names it at all (`not-enabled`).
    """
    if evidence.startswith(REJECTED_FILE):
        return {
            "value": "hidden",
            "causes": ["settings-file-rejected"],
            "remedy": (
                "The owning plugin is named only in a settings file whose "
                "`enabledPlugins` holds a non-Boolean value, and Claude Code "
                "skips every `enabledPlugins` entry in that file, so none of "
                "its skills load. Make each value in that block true or false."
            ),
            "evidence": evidence,
            "provenance": REJECTED_FILE_PROVENANCE,
        }
    if evidence.startswith(NEVER_ENABLED):
        key = entry.get("plugin_key") or ""
        if not SAFE_PLUGIN_KEY.fullmatch(key):
            key = "<plugin>@<marketplace>"
        return {
            "value": "not-enabled",
            "causes": ["plugin-never-enabled"],
            "remedy": (
                "The owning plugin is installed but no `enabledPlugins` scope "
                "names it, so none of its skills load. Run `claude plugin "
                f"enable {key}` to load it, or leave it off on purpose."
            ),
            "evidence": evidence,
            "provenance": NEVER_ENABLED_PROVENANCE,
        }
    return {
        "value": "hidden",
        "causes": ["plugin-not-enabled"],
        "remedy": (
            "The owning plugin is installed but an `enabledPlugins` entry sets "
            "it to false, so none of its skills load. Set it to true in a scope "
            "that outranks the evidence, or remove the false entry, to enable it."
        ),
        "evidence": evidence,
        "provenance": "documented",
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
    override = entry.get("skill_override")

    # A settled `False` comes first: a skill that never loads has no listing
    # entry for its frontmatter to misconfigure.
    if enabled is False:
        return _not_loaded(entry, enabled_evidence or "")
    if override == "off":
        return {
            "value": "hidden",
            "causes": ["skill-override-off"],
            "remedy": (
                "`skillOverrides` sets this skill to off, so it is not listed "
                "at all. Remove the entry or set it to on to show it."
            ),
            "evidence": "skillOverrides",
            "provenance": "documented",
        }

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

    # `skillOverrides` governs non-plugin skills only: the product's listing
    # resolver returns "on" for every plugin-sourced skill before it reads the
    # override map, so a plugin entry never carries one.
    if override is not None:
        if override == "user-invocable-only" or frontmatter.get(
            "disable_model_invocation"
        ):
            return {
                "value": "user-only",
                "causes": [
                    "skill-override-user-invocable-only"
                    if override == "user-invocable-only"
                    else "disable-model-invocation"
                ],
                "remedy": "By design: the description is kept out of the model's context.",
                "evidence": "skillOverrides"
                if override == "user-invocable-only"
                else "frontmatter",
                "provenance": "documented",
            }
        return {
            "value": "model-reachable",
            "causes": ["skill-override-name-only"] if override == "name-only" else [],
            "remedy": (
                "`skillOverrides` lists this skill by name only, so its "
                "description never reaches the model."
                if override == "name-only"
                else ""
            ),
            "evidence": "skillOverrides" if override == "name-only" else "frontmatter",
            "provenance": "documented",
        }

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


@dataclass(frozen=True)
class Walked:
    """Which sources this run enumerated from disk.

    `plugins` is None when every installed plugin and the user's and project's
    own skills were walked (an installed run), or the names of the only
    plugins walked (a checkout). `synced` is whether the signed-in account's
    synced folder was resolved, even when it held nothing.
    """

    plugins: frozenset[str] | None = None
    synced: bool = False


def _walkable_name(name: str, walked: Walked) -> bool:
    """Whether a disk walk would have found this captured name had it existed.

    A qualified name the walk covers but the fleet lacks belongs to a plugin
    uninstalled or a skill renamed since the capture. A checkout covers only
    its own plugins, and a claude.ai-synced name counts only when the synced
    folder was walked. An unqualified name may be built-in, which no walk
    sees, so it stays a fixed cost.
    """
    if ":" not in name:
        return False
    if name.startswith(SYNCED_PREFIX):
        return walked.synced
    return walked.plugins is None or name.split(":", 1)[0] in walked.plugins


def _capture_gap(
    denominator: list[dict], capture: dict, cfg: ListingConfig, walked: Walked
) -> dict[str, list[str]]:
    """Where a read capture fails to cover the counted fleet.

    `not_in_capture`: listed entries the capture does not name, as when a
    plugin was installed after the captured session started. `longer_in_capture`:
    entries the capture rendered in full at more characters than they are
    counted here, so the count is short. `not_in_fleet`: captured entries a
    walk would have found but the fleet lacks, as when a plugin was uninstalled
    after the captured session started; they are not charged. Any of the three
    means the capture came from a different fleet and cannot confirm a fit.
    """
    known = {entry["qualified_name"] for entry in denominator}
    stale = sorted(
        e["name"]
        for e in capture["entries"]
        if e["name"] not in known and _walkable_name(e["name"], walked)
    )
    captured = {e["name"]: e for e in capture["entries"]}
    missing: list[str] = []
    longer: list[str] = []
    for entry in denominator:
        eligibility = _eligibility(entry)
        if eligibility in ("exempt-user-only", "exempt-hidden"):
            continue
        name = entry["qualified_name"]
        seen = captured.get(name)
        if seen is None:
            missing.append(name)
            continue
        counted = (
            len(name) + 2
            if eligibility == "exempt-name-only"
            else len(name) + 4 + _demand_chars(entry, cfg)
        )
        if not seen["name_only"] and seen["rendered_chars"] > counted:
            longer.append(name)
    return {
        "not_in_capture": sorted(missing),
        "longer_in_capture": sorted(longer),
        "not_in_fleet": stale,
    }


def _capture_summary(
    listing: dict,
    capture: dict,
    unenumerated: list[dict] | None,
    gap: dict[str, list[str]] | None = None,
) -> dict:
    """What a captured listing adds to the verdict, and where it disagrees.

    A captured name-only entry that no override forces is a description the
    product shed, which is observed overflow. Any budget row that still says
    the listing fits disagrees with what the model actually received.
    """
    if capture.get("status") != "read":
        return {k: capture.get(k) for k in ("status", "reason", "path")}
    gap = gap or {}
    # A stale entry is not in this fleet, so its shedding is not reported.
    forced = {
        r["qualified_name"]
        for r in listing["skills"]
        if r["eligibility"] == "exempt-name-only"
    } | set(gap.get("not_in_fleet", []))
    shed = sorted(
        e["name"]
        for e in capture["entries"]
        if e["name_only"] and e["name"] not in forced
    )
    rows = listing.get("band") or [listing]
    extra = unenumerated or []
    return {
        "status": "read",
        "path": capture.get("path"),
        "model": capture.get("model"),
        "skill_count": capture["skill_count"],
        "chars": capture["chars"],
        "unenumerated_count": len(extra),
        "unenumerated_chars": sum(e["rendered_chars"] for e in extra),
        "unenumerated_names": sorted(e["name"] for e in extra),
        "lower_bound": any(e["name_only"] for e in extra),
        "observed_name_only": shed,
        "not_in_capture": gap.get("not_in_capture", []),
        "longer_in_capture": gap.get("longer_in_capture", []),
        "not_in_fleet": gap.get("not_in_fleet", []),
        "disagrees": [
            r["label"] for r in rows if shed and r["verdict"] == "listing-fits"
        ],
    }


def classify(
    denominator: list[dict],
    events: list[dict],
    config: Config,
    clock: datetime,
    horizons: dict[str, datetime],
    listing_config: ListingConfig | None = None,
    listing_axes: ListingAxes | None = None,
    listing_capture: dict | None = None,
    walked: Walked | None = None,
) -> dict:
    """Pure. Fleet + events + config + clock + horizons -> report model.

    `listing_axes` names the window and bytes-per-token values to budget for
    and carries the provenance of every budget input; without it the listing
    is the single row `listing_config` describes, which is the replay path.
    `listing_capture` is `read_listing_capture`'s result: its entries that the
    denominator does not name are charged at their captured length, unless
    `walked` says a disk walk would have found them. Without `walked`, as on
    replay, every plugin counts as walked and synced skills count as walked
    when the denominator holds one.
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
    captured = (listing_capture or {}).get("status") == "read"
    if walked is None:
        walked = Walked(synced=any(e.get("source") == "synced" for e in denominator))
    gap = (
        _capture_gap(denominator, listing_capture, listing_cfg, walked)
        if captured
        else {}
    )
    # Only what no walk could enumerate is a fixed cost; a captured entry the
    # walk would have found is stale and lands in the gap instead.
    known = {entry["qualified_name"] for entry in denominator}
    known.update(gap.get("not_in_fleet", []))
    unenumerated = (
        [e for e in listing_capture["entries"] if e["name"] not in known]
        if captured
        else None
    )
    covers = not any(gap.values())
    stale = bool(gap.get("not_in_fleet"))
    if listing_axes is None:
        listing = compute_listing(
            denominator, listing_cfg, native_scores, unenumerated, covers, stale
        )
    else:
        listing = compute_listing_band(
            denominator,
            listing_cfg,
            listing_axes,
            native_scores,
            unenumerated,
            covers,
            stale,
        )
        listing["inputs"] = listing_axes.inputs
    if listing_capture is not None:
        listing["capture"] = _capture_summary(
            listing, listing_capture, unenumerated, gap
        )
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
    if listing_overflow_unconfirmed(listing):
        withheld.append(
            {
                "skill": None,
                "claim": "starvation",
                "reason": CAPTURE_MISMATCH_REASON,
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
        if listing.get("band"):
            lines += _render_band(listing)
        else:
            lines += _render_single_budget(listing)
        lines += _render_coverage(listing)
        any_overflow = listing_overflows(listing)
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


def _hidden_by_override(row: dict) -> bool:
    """A non-plugin skill set off by `skillOverrides`, not a disabled plugin."""
    return "skill-override-off" in row["reachability"]["causes"]


def _render_reachability(skills: list[dict]) -> list[str]:
    """Per-value counts, the one checkout line, the hidden table, and the
    not-enabled summary.

    A checkout run declines enablement once, for the run, rather than once
    per row. An installed run groups the hidden rows by owning plugin, since
    the cause is per plugin and the evidence is the scope file that set it.
    Never-enabled plugins get one summary line and no table: they are the
    install-time default, not something to fix.
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
    overridden = [r for r in skills if _hidden_by_override(r)]
    if overridden:
        lines += [
            "Off by `skillOverrides`: "
            + ", ".join(f"`{r['qualified_name']}`" for r in overridden[:10])
            + (f" and {len(overridden) - 10} more" if len(overridden) > 10 else "")
            + ".",
            "",
        ]
    for row in skills:
        reach = row["reachability"]
        if reach["value"] != "hidden" or _hidden_by_override(row):
            continue
        plugin = row["qualified_name"].partition(":")[0]
        bucket = hidden.setdefault(plugin, {"skills": 0, "evidence": reach["evidence"]})
        bucket["skills"] += 1
    if hidden:
        lines += [
            "Hidden: the owning plugin is installed but an `enabledPlugins` "
            "entry sets it to false, so none of its skills load.",
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
    never = [r for r in skills if r["reachability"]["value"] == "not-enabled"]
    if never:
        plugins = {r["qualified_name"].partition(":")[0] for r in never}
        # The flag scope is never readable from outside a session; any other
        # unread scope (managed policy that could not be enumerated) might
        # enable these, which the line states without changing the verdict.
        unread = {
            name: None
            for r in never
            for name in str(r["reachability"]["evidence"])
            .partition(UNREAD_MARKER)[2]
            .split(", ")
            if name and name != "flag"
        }
        qualifier = (
            f", unless a scope not read ({', '.join(unread)}) enables them"
            if unread
            else ""
        )
        lines += [
            f"Not enabled: {len(plugins)} installed "
            f"{_plural(len(plugins), 'plugin')} ({len(never)} "
            f"{_plural(len(never), 'skill')}) that no `enabledPlugins` scope "
            f"names{qualifier}. They do not load, so they spend no listing "
            "budget and are not a finding.",
            "",
        ]
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
    under the cap. It is arithmetic over length and is labeled that way:
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
        if not _hidden_by_override(row):
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
    if listing["verdict"] == "overflow-unconfirmed":
        return [
            f"Overflow unconfirmed at {listing['label']}: "
            f"{listing['listing_chars']:,} of {listing['budget_chars']:,} "
            "characters, but the counted entries alone fit and the excess comes "
            "from a captured listing of a different fleet (see coverage). No "
            "skill is named as running name-only.",
            "",
        ]
    if listing["overflow_chars"] > 0:
        axes = (
            ""
            if listing["budget_basis"] == "env-override"
            else f" (window {listing['context_window_tokens']:,} tokens, "
            f"{listing['bytes_per_token']} bytes per token)"
        )
        over_budget = (
            f"**Your skill listing is over budget by "
            f"{listing['overflow_chars']:,} characters** at "
            f"{listing['label']}{axes}. "
            f"{listing['competing_count']} skills compete for "
            f"{listing['budget_chars']:,} characters of description budget, "
        )
        if listing.get("score_basis") == "unscored":
            # The count is the whole claim here. Saying which skills are running
            # name-only would name the ones the catalog happens to list last.
            return [
                over_budget + f"and **{listing['starved_count']}** of "
                f"{listing['competing_count']} competing descriptions cannot fit; "
                f"which ones is withheld because no usage has been observed, so "
                f"the ordering is catalog position, not preference.",
                "",
            ]
        # The certain half: documented settings vs summed description
        # lengths. No undocumented constant is involved, so this is stated
        # plainly rather than hedged.
        return [
            over_budget + f"and descriptions are shed lowest-score-first, so roughly "
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
    subject = (
        "Counted entries fit (unconfirmed, see coverage)"
        if listing["verdict"] == "fit-unconfirmed"
        else "Listing fits"
    )
    return [
        f"{subject} at {listing['label']}: {listing['listing_chars']:,} of "
        f"{listing['budget_chars']:,} characters, of which "
        f"{listing['demand_chars']:,} are the descriptions of "
        f"{listing['competing_count']} competing skills and "
        f"{listing['floor_chars']:,} the floor (names, exempt entries and "
        f"separators). No counted description is being dropped.",
        "",
    ]


def _render_coverage(listing: dict) -> list[str]:
    """What the verdict counted, and what a captured listing says about it."""
    capture = listing.get("capture") or {}
    if capture.get("status") != "read":
        counted = listing.get("counted") or ["the entries in the collection"]
        missing = listing.get("not_counted") or ["built-in and bundled skills"]
        lines = [
            f"**Counted: {'; '.join(counted)}. Not counted: "
            f"{'; '.join(missing)}**, which the session lists too, so a fit "
            "here is `fit-unconfirmed`, never `listing-fits`: the session can "
            "still be over budget. Pass `--listing-capture <transcript.jsonl>` to count "
            "them from the listing a session actually received.",
            "",
        ]
        if capture:
            lines[0:0] = [
                f"Listing capture `{capture.get('path')}` was not read: "
                f"{capture.get('reason')}.",
                "",
            ]
        return lines + [_SUBAGENT_NOTE, ""]
    lines = [
        f"Captured listing (`{capture['path']}`, model "
        f"`{capture.get('model') or 'unknown'}`): {capture['skill_count']} "
        f"entries, {capture['chars']:,} characters. "
        f"{capture['unenumerated_count']} of them are not on disk and are "
        f"counted at their captured length ({capture['unenumerated_chars']:,} "
        "characters)"
        + (
            "; some arrived name-only, so the total is a lower bound."
            if capture["lower_bound"]
            else "."
        ),
        "",
    ]
    absent, longer = capture["not_in_capture"], capture["longer_in_capture"]
    stale = capture.get("not_in_fleet", [])
    if absent or longer or stale:
        parts = []
        if stale:
            parts.append(
                f"{len(stale)} captured plugin {_plural(len(stale), 'skill')} "
                "this fleet no longer has, not counted ("
                + ", ".join(f"`{name}`" for name in stale[:10])
                + ("…" if len(stale) > 10 else "")
                + ")"
            )
        if absent:
            parts.append(
                f"{len(absent)} counted {_plural(len(absent), 'skill')} "
                "absent from it ("
                + ", ".join(f"`{name}`" for name in absent[:10])
                + ("…" if len(absent) > 10 else "")
                + ")"
            )
        if longer:
            parts.append(
                f"{len(longer)} rendered longer there than counted here ("
                + ", ".join(f"`{name}`" for name in longer[:10])
                + ("…" if len(longer) > 10 else "")
                + ")"
            )
        lines += [
            "**The capture does not cover the counted fleet**: "
            + " and ".join(parts)
            + ". It came from a session that loaded a different fleet, so a fit "
            "stays `fit-unconfirmed`"
            + (
                " and an overflow its charges alone produce is `overflow-unconfirmed`"
                if stale
                else ""
            )
            + ". Capture a session started after the last install or edit to "
            "confirm one.",
            "",
        ]
    shed = capture["observed_name_only"]
    if shed:
        lines += [
            f"The capture shows {len(shed)} "
            f"{_plural(len(shed), 'description')} shed: "
            + ", ".join(f"`{name}`" for name in shed[:10])
            + ("…" if len(shed) > 10 else "")
            + ".",
            "",
        ]
    if capture["disagrees"]:
        lines += [
            "**The captured listing disagrees with the arithmetic**: rows "
            + ", ".join(f"`{label}`" for label in capture["disagrees"])
            + " say the listing fits, but the session dropped descriptions.",
            "",
        ]
    return lines + [_SUBAGENT_NOTE, ""]


_SUBAGENT_NOTE = (
    "A verdict covers the main session at the stated window. A subagent gets a "
    "listing sized to its own window, so a smaller-window subagent can shed "
    "descriptions where this verdict says the listing fits."
)


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
        f"{listing['demand_chars']:,} characters of description. Before any "
        f"description, the listing's names, exempt entries and separators "
        f"(the floor) take {listing['floor_chars']:,}; rendered in full it is "
        f"{listing['listing_chars']:,} characters, and that total is what "
        f"must fit the budget.",
        "",
        "| Row | Window | Bytes/token | Demand | Floor | Budget | Overflow "
        "| Verdict | Starved |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for row in listing["band"]:
        lines.append(
            f"| {row['label']} | {row['context_window_tokens']:,} | "
            f"{row['bytes_per_token']} | {row['demand_chars']:,} | "
            f"{row['floor_chars']:,} | {row['budget_chars']:,} | "
            f"{row['overflow_chars']:,} | {row['verdict']} | "
            f"{row['starved_count']} |"
        )
    lines.append("")
    return lines


def _render_inputs(inputs: dict) -> list[str]:
    """What was consulted for the budget, with provenance, as one short list."""

    def _prov(row: dict) -> str:
        provenance = row.get("provenance", "")
        if provenance in ("default", "fraction"):
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
    parser.add_argument(
        "--listing-capture",
        metavar="TRANSCRIPT",
        help="a session transcript (.jsonl) whose recorded skill listing "
        "supplies the entries no disk walk sees (built-in, bundled, "
        "claude.ai-synced) and is checked against the verdict. Read only; "
        "Claude Code is never launched",
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
    if args.now:
        try:
            _parse_ts(args.now)
        except ValueError:
            parser.error(f"--now must be an RFC3339 instant, got {args.now!r}")

    resolution: dict | None = None
    if args.fixture:
        try:
            bundle = _load_fixture(args.fixture)
        except (OSError, ValueError) as exc:
            print(
                f"error: cannot read --fixture {args.fixture}: {exc}", file=sys.stderr
            )
            return 2
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
        walked = None
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
            # The listing also carries the user's and the project's own
            # skills, governed by `skillOverrides` instead of enabledPlugins.
            overrides = merge_skill_overrides(layers)
            denominator += collect_user_and_project_skills(
                config_root, current_project, overrides
            )
            account_json = args.claude_json or (
                os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".claude.json")
                if os.environ.get("CLAUDE_CONFIG_DIR")
                else os.path.expanduser("~/.claude.json")
            )
            denominator += collect_synced_skills(config_root, account_json, overrides)
            walked = Walked(
                synced=synced_skills_folder(config_root, account_json) is not None
            )
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
            walked = Walked(
                plugins=frozenset(
                    e["qualified_name"].split(":", 1)[0] for e in denominator
                )
            )

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
        listing_capture=(
            read_listing_capture(args.listing_capture) if args.listing_capture else None
        ),
        walked=walked,
    )

    if not args.fixture:
        local = "user, project and claude.ai-synced skills"
        model["listing"]["counted"] = ["plugin skills, commands and workflows"] + (
            [local] if resolution is not None else []
        )
        model["listing"]["not_counted"] = ["built-in and bundled skills"] + (
            [] if resolution is not None else [local]
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
        try:
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
        except OSError as exc:
            print(
                f"error: cannot write under --write {args.write}: {exc}",
                file=sys.stderr,
            )
            return 2
        print(path)
        return 0

    if args.render == "json":
        print(json.dumps(model, indent=2))
    else:
        print(_render_markdown(model))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
