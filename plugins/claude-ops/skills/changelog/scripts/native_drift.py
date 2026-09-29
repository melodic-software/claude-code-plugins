#!/usr/bin/env python3
"""Native-surface drift after a changelog apply: summarize one extraction, diff it
against the previous one, evaluate the overlap store's recheck triggers, and list
the work items to file.

Subcommands (standard library only; every input is a file the caller produced):

  summarize --inventory <inventory.json> [--detect <detect.json>] --out <summary.json>
      Reduce an `inventory.py --binary-only --docs` extraction and an
      `overlap.py detect` report to the fields the diff reads.

  diff --current <summary.json> [--previous <summary.json>] [--store <records.json>]
       [--detect <detect.json>] --self-check-exit <0|1|3> [--out <drift.json>]
      Compare two summaries, evaluate each extraction-evidence store row against
      the current summary, and emit the drift report with its `items`: one per
      work item to file, each carrying a stable dedupe `key`
      (native-drift:<kind>:<surface>:<component>). A candidate is an item only
      when it is new since the previous summary, at or over detect's threshold,
      re-derivable, and without a store row. A missing previous summary is a
      baseline run: no surface diff, no new candidates, triggers on state still
      evaluated.

Exit: 0 report written; 2 usage error or an unreadable or malformed input.
Nothing here files, fetches, or edits: the skill body owns the filing.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

MIN_PYTHON = (3, 11)
SCHEMA = 1
KEY_PREFIX = "native-drift"
LANE_CLASS = {
    "builtin_commands": "builtin-command",
    "bundled_skills": "bundled-skill",
    "bundled_workflows": "bundled-workflow",
    "plugin_backed": "plugin-backed-builtin",
}
MARKERS = ("hidden", "gated", "model-invocation-disabled")
VERSION_DRIFT = re.compile(r"^cli (\S+) differs from the last validated build (\S+)")
RENAME_MIN_SIMILARITY = 0.6
DESCRIPTION_CHARS = 300


class InputError(Exception):
    pass


def load(path: str | None, *, required: bool = True) -> Any:
    if path is None or not Path(path).is_file():
        if required:
            raise InputError(f"missing input: {path}")
        return None
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError(f"unreadable input {path}: {exc}") from exc


def registrations(entry: Any) -> list[dict[str, Any]]:
    items = entry if isinstance(entry, list) else [entry]
    return [e for e in items if isinstance(e, dict)]


def invocability(regs: list[dict[str, Any]]) -> tuple[bool | None, str]:
    """Model invocability and the invocable-by label, read the way
    audit-native-overlap reads them: `model_invocable` wins, an older
    extraction's `disable_model_invocation` stands in, and registrations that
    disagree (a name collision) are unknown."""

    def agreed(values: list[Any]) -> Any:
        return values[0] if values and all(v == values[0] for v in values) else None

    model = agreed(
        [
            r["model_invocable"]
            if isinstance(r.get("model_invocable"), bool)
            else (not r["disable_model_invocation"])
            if isinstance(r.get("disable_model_invocation"), bool)
            else None
            for r in regs
        ]
    )
    user = agreed(
        [
            r.get("user_invocable")
            if isinstance(r.get("user_invocable"), bool)
            else None
            for r in regs
        ]
    )
    label = {
        (True, True): "model+user",
        (False, True): "user-only",
        (True, False): "model-only",
    }.get((model, user), "unknown")
    return model, label


def surface_record(klass: str, regs: list[dict[str, Any]]) -> dict[str, Any]:
    model, who = invocability(regs)
    markers = {m for m in ("hidden", "gated") if any(r.get(m) for r in regs)}
    if model is False:
        markers.add("model-invocation-disabled")
    aliases = sorted(
        {a for r in regs for a in (r.get("aliases") or []) if isinstance(a, str)}
    )
    description = next(
        (r["description"] for r in regs if isinstance(r.get("description"), str)), ""
    )
    return {
        "class": klass,
        "markers": [m for m in MARKERS if m in markers],
        "model_invocable": model,
        "invocable_by": who,
        "aliases": aliases,
        "description": description[:DESCRIPTION_CHARS],
    }


def summarize(inventory: Any, detect: Any) -> dict[str, Any]:
    if not isinstance(inventory, dict) or inventory.get("schema") != 1:
        raise InputError("inventory is not a schema-1 inventory.py extraction")
    integrity = (
        inventory.get("integrity")
        if isinstance(inventory.get("integrity"), dict)
        else {}
    )
    surfaces: dict[str, dict[str, Any]] = {}
    for lane, klass in LANE_CLASS.items():
        payload = inventory.get(lane)
        if not isinstance(payload, dict):
            continue
        if lane == "plugin_backed":
            # The registration of a plugin-backed name sits in the command or
            # skill lane; its fields describe the plugin-backed surface.
            other = {
                **(inventory.get("builtin_commands") or {}),
                **(inventory.get("bundled_skills") or {}),
            }
            surfaces[lane] = {
                n: surface_record(klass, registrations(other.get(n))) for n in payload
            }
        else:
            surfaces[lane] = {
                n: surface_record(klass, registrations(e))
                for n, e in payload.items()
                if n not in (inventory.get("plugin_backed") or {})
            }
    docs = inventory.get("docs_crosscheck")
    docs_block = None
    if isinstance(docs, dict):
        names = docs.get("names") if isinstance(docs.get("names"), dict) else {}
        docs_block = {
            "status": docs.get("status"),
            "names": {
                n: v.get("status") for n, v in names.items() if isinstance(v, dict)
            },
        }
    candidates = []
    detect_block = None
    if isinstance(detect, dict):
        threshold = (detect.get("discovery") or {}).get("threshold")
        detect_block = {
            "status": (detect.get("integrity") or {}).get("status"),
            "threshold": threshold,
        }
        for c in detect.get("candidates") or []:
            if isinstance(c, dict):
                candidates.append(candidate_key(c))
    lanes = integrity.get("lanes") if isinstance(integrity.get("lanes"), dict) else {}
    return {
        "schema": SCHEMA,
        "cli_version": integrity.get("cli_version"),
        "validated_against": integrity.get("validated_against"),
        "integrity": {
            "status": integrity.get("status", "unknown"),
            "lanes": {k: (v or {}).get("status") for k, v in lanes.items()},
            "advisories": [
                a for a in integrity.get("advisories") or [] if isinstance(a, str)
            ],
        },
        "surfaces": surfaces,
        "docs": docs_block,
        "detect": detect_block,
        "candidates": sorted(set(candidates)),
    }


def token(text: Any) -> str:
    return re.sub(r"\s+", "_", str(text).strip())


def component_id(component: dict[str, Any]) -> str:
    ident = f"{token(component.get('plugin'))}:{token(component.get('skill'))}"
    return ident + ("@agent" if component.get("kind") == "agent" else "")


def drift_key(kind: str, surface: Any, component: str) -> str:
    return f"{KEY_PREFIX}:{kind}:{token(surface)}:{component}"


def candidate_key(candidate: dict[str, Any]) -> str:
    native = candidate.get("native") or {}
    return drift_key(
        "candidate", native.get("name"), component_id(candidate.get("component") or {})
    )


def version_tuple(version: Any) -> tuple[int, ...] | None:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", str(version or ""))
    return tuple(int(p) for p in match.groups()) if match else None


def _words(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]{3,}", text.lower()))


def similarity(a: str, b: str) -> float:
    left, right = _words(a), _words(b)
    return len(left & right) / len(left | right) if left and right else 0.0


def diff_surfaces(
    prev: dict[str, Any], cur: dict[str, Any]
) -> dict[str, list[dict[str, Any]]]:
    """Added, removed, renamed, reclassified, invocability and marker changes.

    A name that leaves one lane and appears in another is reclassified, not
    removed and added. A removed name pairs with an added one in the same lane
    as a rename when the added one lists it as an alias, or their descriptions
    share at least RENAME_MIN_SIMILARITY of their words.
    """

    def flat(summary: dict[str, Any]) -> dict[str, tuple[str, dict[str, Any]]]:
        out: dict[str, tuple[str, dict[str, Any]]] = {}
        for lane, names in (summary.get("surfaces") or {}).items():
            for name, rec in (names or {}).items():
                out.setdefault(name, (lane, rec))
        return out

    before, after = flat(prev), flat(cur)
    changes: dict[str, list[dict[str, Any]]] = {
        k: []
        for k in (
            "added",
            "removed",
            "renamed",
            "reclassified",
            "invocability",
            "markers",
        )
    }
    for name in sorted(before.keys() & after.keys()):
        (lane_a, a), (lane_b, b) = before[name], after[name]
        if lane_a != lane_b:
            changes["reclassified"].append(
                {"name": name, "from": a.get("class"), "to": b.get("class")}
            )
        if a.get("invocable_by") != b.get("invocable_by"):
            changes["invocability"].append(
                {
                    "name": name,
                    "from": a.get("invocable_by"),
                    "to": b.get("invocable_by"),
                }
            )
        if a.get("markers") != b.get("markers"):
            changes["markers"].append(
                {"name": name, "from": a.get("markers"), "to": b.get("markers")}
            )
    removed = {n: before[n] for n in before.keys() - after.keys()}
    added = {n: after[n] for n in after.keys() - before.keys()}
    for old in sorted(removed):
        lane, rec = removed[old]
        best, best_score = None, 0.0
        for new in sorted(added):
            new_lane, new_rec = added[new]
            if new_lane != lane:
                continue
            score = (
                1.0
                if old in new_rec.get("aliases", [])
                else similarity(
                    rec.get("description", ""), new_rec.get("description", "")
                )
            )
            if score > best_score:
                best, best_score = new, score
        if best is not None and best_score >= RENAME_MIN_SIMILARITY:
            changes["renamed"].append(
                {
                    "lane": lane,
                    "from": old,
                    "to": best,
                    "similarity": round(best_score, 2),
                }
            )
            del added[best]
        else:
            changes["removed"].append({"lane": lane, "name": old})
    changes["added"] = [{"lane": added[n][0], "name": n} for n in sorted(added)]
    return changes


def diff_docs(prev: dict[str, Any], cur: dict[str, Any]) -> dict[str, Any]:
    a, b = prev.get("docs") or {}, cur.get("docs") or {}
    names_a, names_b = a.get("names") or {}, b.get("names") or {}
    return {
        "status": None
        if a.get("status") == b.get("status")
        else {"from": a.get("status"), "to": b.get("status")},
        "names": [
            {"name": n, "from": names_a.get(n), "to": names_b.get(n)}
            for n in sorted(names_a.keys() | names_b.keys())
            if names_a.get(n) != names_b.get(n)
        ],
    }


def find(summary: dict[str, Any] | None, name: Any) -> dict[str, Any] | None:
    for names in ((summary or {}).get("surfaces") or {}).values():
        if name in (names or {}):
            return names[name]
    return None


def evaluate_row(
    row: dict[str, Any],
    cur: dict[str, Any],
    prev: dict[str, Any] | None,
    renames: dict[str, str],
) -> list[str] | None:
    """Why an extraction-evidence store row's recheck trigger fired: a list of
    reasons, empty when it did not fire, None when this extraction cannot judge
    the row.

    Presence, provenance class, and the hidden, gated and model-invocation-
    disabled markers are compared with the row. Removal and rename are events,
    so they fire only when the previous extraction held the name and this one
    does not; a name neither extraction holds (a CLI subcommand, a surface read
    by a targeted search) is outside what the lanes observe. A row whose lane
    is broken this run is not re-derivable.
    """
    native = row.get("native") or {}
    name, klass = native.get("name"), native.get("class")
    lanes = cur.get("integrity", {}).get("lanes") or {}
    home = {c: lane for lane, c in LANE_CLASS.items()}.get(klass)
    if home is None or lanes.get(home) == "broken":
        return None
    rec = find(cur, name)
    if rec is None:
        if find(prev, name) is None:
            return None
        if name in renames:
            return [f"renamed: `{name}` is now `{renames[name]}`"]
        return [
            f"removed: `{name}` was in the previous extraction and is absent from this one"
        ]
    reasons = []
    if rec.get("class") != klass:
        reasons.append(
            f"reclassified: recorded as {klass}, extracted as {rec.get('class')}"
        )
    recorded = set(native.get("markers") or [])
    observed = set(rec.get("markers") or [])
    if rec.get("model_invocable") is None:
        recorded.discard("model-invocation-disabled")
        observed.discard("model-invocation-disabled")
    if recorded != observed:
        reasons.append(
            "markers differ: recorded "
            + (", ".join(sorted(recorded)) or "none")
            + ", extracted "
            + (", ".join(sorted(observed)) or "none")
        )
    return reasons


def inventory_verdict(
    cur: dict[str, Any], exit_code: int, surface_changes: dict[str, Any] | None
) -> dict[str, Any]:
    status = {0: "ok", 1: "broken", 3: "degraded"}.get(exit_code, "unknown")
    integrity = cur.get("integrity") or {}
    advisories = integrity.get("advisories") or []
    lanes_ok = bool(integrity.get("lanes")) and all(
        s == "ok" for s in integrity["lanes"].values()
    )
    drift = [VERSION_DRIFT.match(a) for a in advisories]
    only_version = bool(advisories) and all(drift)
    moved_past = only_version and (version_tuple(cur.get("cli_version")) or ()) > (
        version_tuple(cur.get("validated_against")) or ()
    )
    unchanged = surface_changes is not None and not any(surface_changes.values())
    if status == "degraded" and lanes_ok and moved_past and unchanged:
        verdict = "revalidate"
    else:
        verdict = status
    return {
        "status": status,
        "verdict": verdict,
        "cli_version": cur.get("cli_version"),
        "validated_against": cur.get("validated_against"),
        "surface_changes_known": surface_changes is not None,
        "advisories": advisories,
    }


def diff(
    cur: dict[str, Any],
    prev: dict[str, Any] | None,
    store: Any,
    detect: Any,
    self_check_exit: int,
) -> dict[str, Any]:
    surface = diff_surfaces(prev, cur) if prev else None
    renames = {r["from"]: r["to"] for r in (surface or {}).get("renamed", [])}
    items: list[dict[str, Any]] = []

    threshold = ((detect or {}).get("discovery") or {}).get("threshold")
    prev_candidates = set((prev or {}).get("candidates") or [])
    new_candidates = []
    for c in (detect or {}).get("candidates") or []:
        key = candidate_key(c)
        new = prev is not None and key not in prev_candidates
        if new:
            new_candidates.append(key)
        score = c.get("score")
        fileable = (
            new
            and c.get("store_verdict") is None
            and c.get("re_derivable") is not False
            and c.get("component_present") is not False
            and isinstance(score, (int, float))
            and isinstance(threshold, (int, float))
            and score >= threshold
        )
        if fileable:
            native = c.get("native") or {}
            items.append(
                {
                    "kind": "candidate",
                    "key": key,
                    "native": native.get("name"),
                    "class": native.get("class"),
                    "component": component_id(c.get("component") or {}),
                    "facts": [
                        f"origin {c.get('origin')}, score {score} (threshold {threshold})"
                    ]
                    + [e for e in c.get("evidence") or [] if isinstance(e, str)],
                }
            )

    fired, not_evaluable = [], 0
    rows = store.get("rows") if isinstance(store, dict) else None
    for row in rows if isinstance(rows, list) else []:
        if (
            not isinstance(row, dict)
            or (row.get("observation") or {}).get("class") != "extraction"
        ):
            not_evaluable += 1
            continue
        reasons = evaluate_row(row, cur, prev, renames)
        if reasons is None:
            not_evaluable += 1
        if not reasons:
            continue
        native = row.get("native") or {}
        component = component_id(row.get("component") or {})
        key = drift_key("recheck", native.get("name"), component)
        fired.append(
            {
                "key": key,
                "native": native.get("name"),
                "component": component,
                "reasons": reasons,
            }
        )
        items.append(
            {
                "kind": "recheck",
                "key": key,
                "native": native.get("name"),
                "class": native.get("class"),
                "component": component,
                "facts": reasons
                + [f"row trigger: {(row.get('recheck') or {}).get('trigger')}"],
            }
        )

    inventory = inventory_verdict(cur, self_check_exit, surface)
    if inventory["verdict"] != "ok":
        kind = (
            "revalidate"
            if inventory["verdict"] == "revalidate"
            else f"inventory-{inventory['verdict']}"
        )
        facts = list(inventory["advisories"])
        if not inventory["surface_changes_known"]:
            facts.append(
                "no previous extraction summary: surface changes since the last run are unknown"
            )
        items.append(
            {
                "kind": kind,
                "key": drift_key(
                    kind, cur.get("cli_version") or "unknown", "inventory"
                ),
                "native": None,
                "class": None,
                "component": "inventory",
                "facts": facts,
            }
        )

    return {
        "schema": SCHEMA,
        "baseline": prev is None,
        "cli_version": {
            "previous": (prev or {}).get("cli_version"),
            "current": cur.get("cli_version"),
        },
        "surface_changes": surface,
        "docs_changes": diff_docs(prev, cur) if prev else None,
        "new_candidates": new_candidates if prev is not None else None,
        "fired_triggers": fired,
        "rows_not_evaluable": not_evaluable,
        "store_present": isinstance(rows, list),
        "inventory": inventory,
        "items": items,
    }


def write(payload: Any, out: str | None) -> None:
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if out:
        Path(out).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(f"python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("summarize")
    s.add_argument("--inventory", required=True)
    s.add_argument("--detect")
    s.add_argument("--out")
    d = sub.add_parser("diff")
    d.add_argument("--current", required=True)
    d.add_argument("--previous")
    d.add_argument("--store")
    d.add_argument("--detect")
    d.add_argument("--self-check-exit", type=int, required=True, choices=(0, 1, 3))
    d.add_argument("--out")
    args = parser.parse_args(argv)
    try:
        if args.command == "summarize":
            write(
                summarize(load(args.inventory), load(args.detect, required=False)),
                args.out,
            )
        else:
            write(
                diff(
                    load(args.current),
                    load(args.previous, required=False),
                    load(args.store, required=False),
                    load(args.detect, required=False),
                    args.self_check_exit,
                ),
                args.out,
            )
    except InputError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
