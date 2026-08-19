#!/usr/bin/env python3
"""Skill-starvation diagnostic: starved vs genuinely unwanted vs not observable.

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

Phase 1 scope: the `observation` field. `reachability` and `starvation` arrive
in later phases per docs/topics/skills-discovery-plugin/PLAN.md.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime

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
) -> dict:
    """Pure. Fleet + events + config + clock + horizons -> report model."""
    # Narrowest horizon = the most recent start = the least we can see back to.
    observed_horizon = max(horizons.values()) if horizons else clock
    observable_days = (clock - observed_horizon).days

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
        f"- Skills: {len(model['skills'])}",
        f"- Withheld claims: {len(model['withheld'])}",
        "",
    ]
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
    args = parser.parse_args(argv)

    if not args.fixture:
        print("error: --fixture is required at this phase", file=sys.stderr)
        return 2

    bundle = _load_fixture(args.fixture)
    clock = _parse_ts(args.now) if args.now else _parse_ts(bundle["now"])
    horizons = {k: _parse_ts(v) for k, v in bundle.get("horizons", {}).items()}
    events = [dict(e, ts=_parse_ts(e["ts"])) for e in bundle.get("events", [])]
    cfg = Config(**bundle.get("config", {}))

    model = classify(
        denominator=bundle["denominator"],
        events=events,
        config=cfg,
        clock=clock,
        horizons=horizons,
    )

    if args.render == "json":
        print(json.dumps(model, indent=2))
    else:
        print(_render_markdown(model))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
