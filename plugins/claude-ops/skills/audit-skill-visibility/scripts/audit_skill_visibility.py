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

**Fixture-driven today.** The CLI reads a prepared bundle; the live collectors
that would assemble one from a real installation are not wired yet. The parsers
for each source exist and are unit-tested, but nothing calls them from disk.
"""

from __future__ import annotations

import argparse
import json
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


def _render_markdown(model: dict) -> str:
    lines = [
        "# Skill starvation report",
        "",
        f"- Observed horizon: `{model['observed_horizon']}`",
        f"- Sources: {', '.join(s['source'] for s in model['sources']) or 'none'}",
        f"- Capability tier: `{model.get('tier', 'T-none')}` "
        f"({model.get('tier_basis', '')})",
        f"- Skills: {len(model['skills'])}",
        f"- Withheld claims: {len(model['withheld'])}",
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
                f"{listing['competing_count']} skills are competing for "
                f"{listing['budget_chars']:,} characters of description budget, "
                f"and descriptions are dropped least-invoked-first — so the "
                f"skills below are running name-only, which is why the model "
                f"stops matching requests to them.",
                "",
                "Which *particular* skills lost their descriptions is inferential:",
                "the ordering comes from an undocumented scorer. Treat the ranking",
                "as a likelihood band, not a cutoff line.",
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
    parser.add_argument("--fixture", help="path to a fixture JSON bundle")
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

    if not args.fixture:
        print("error: --fixture is required at this phase", file=sys.stderr)
        return 2

    bundle = _load_fixture(args.fixture)
    clock = _parse_ts(args.now) if args.now else _parse_ts(bundle["now"])
    horizons = {k: _parse_ts(v) for k, v in bundle.get("horizons", {}).items()}
    events = [dict(e, ts=_parse_ts(e["ts"])) for e in bundle.get("events", [])]
    cfg = Config(**bundle.get("config", {}))
    listing_cfg = ListingConfig(**bundle.get("listing_config", {}))

    model = classify(
        denominator=bundle["denominator"],
        events=events,
        config=cfg,
        clock=clock,
        horizons=horizons,
        listing_config=listing_cfg,
    )

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
