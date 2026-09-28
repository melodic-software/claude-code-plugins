#!/usr/bin/env python3
"""Report which native-overlap epic units are present in a checkout.

Read-only. Prints one line per unit and exits 1 when any unit is still open.
It does not edit the store or a skill body.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

INTEGRATIONS = frozenset({"route", "wrap", "suggest"})

DOCTOR_SENTENCE = "If /doctor is available in your session ("
SKILL_DOCTOR_SENTENCE = "If /skill-doctor is available in your session ("
EXPORT_SENTENCE = "If /export is available in your session ("
SIMPLIFY_HEADING = "## Native step: simplify (bundled skill)"
RUN_HEADING = "## Native step: run (bundled skill)"
AXIS = "settings or environment, plan, platform or provider, host surface"
ROUTE_TOKEN = "resolves in your session"


def load_rows(root: Path) -> list[dict[str, object]]:
    path = root / "docs" / "native-surfaces" / "records.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("rows")
    if not isinstance(rows, list):
        raise ValueError(f"{path} has no rows list")
    return rows


def file_has(root: Path, relative: str, needle: str) -> bool:
    path = root / relative
    if not path.is_file():
        return False
    return needle in path.read_text(encoding="utf-8")


def baked_flag(rows: list[dict[str, object]], native: str, plugin: str, skill: str, flag: str) -> bool:
    for row in rows:
        native_obj = row.get("native")
        component = row.get("component")
        if not isinstance(native_obj, dict) or not isinstance(component, dict):
            continue
        if native_obj.get("name") != native:
            continue
        if component.get("plugin") != plugin or component.get("skill") != skill:
            continue
        baked = row.get("baked")
        if not isinstance(baked, dict):
            return False
        return baked.get(flag) is True
    return False


def integration_problems(rows: list[dict[str, object]]) -> list[str]:
    problems: list[str] = []
    if not rows:
        problems.append("store has no rows")
    for index, row in enumerate(rows):
        native_obj = row.get("native")
        if not isinstance(native_obj, dict):
            problems.append(f"row {index} has no native object")
            continue
        integration = row.get("integration")
        if integration not in INTEGRATIONS:
            problems.append(f"row {index} integration={integration!r}")
            continue
        if native_obj.get("class") == "builtin-command" and integration == "wrap":
            problems.append(f"row {index} builtin-command wrap")
        if row.get("verdict") == "defer" and integration != "route":
            problems.append(f"row {index} defer integration={integration}")
    return problems


def evaluate(root: Path) -> list[dict[str, str]]:
    rows = load_rows(root)
    units: list[dict[str, str]] = []

    phase4 = integration_problems(rows)
    units.append(
        {
            "id": "phase4",
            "issue": "4049",
            "status": "ok" if not phase4 else "open",
            "detail": "integration axis" if not phase4 else "; ".join(phase4),
        }
    )

    phase5_gaps = []
    if not file_has(root, "plugins/claude-ops/skills/audit-install-state/SKILL.md", DOCTOR_SENTENCE):
        phase5_gaps.append("audit-install-state doctor sentence")
    if not file_has(root, "plugins/claude-ops/skills/audit-skill-visibility/SKILL.md", SKILL_DOCTOR_SENTENCE):
        phase5_gaps.append("audit-skill-visibility skill-doctor sentence")
    if not file_has(root, "plugins/claude-ops/skills/audit-skill-visibility/SKILL.md", DOCTOR_SENTENCE):
        phase5_gaps.append("audit-skill-visibility doctor sentence")
    if not file_has(root, "plugins/claude-ops/skills/audit-performance/SKILL.md", DOCTOR_SENTENCE):
        phase5_gaps.append("audit-performance doctor sentence")
    if not baked_flag(rows, "doctor", "claude-ops", "audit-install-state", "suggest_sentence"):
        phase5_gaps.append("audit-install-state suggest_sentence")
    units.append(
        {
            "id": "phase5",
            "issue": "4050",
            "status": "ok" if not phase5_gaps else "open",
            "detail": "doctor suggest sentences" if not phase5_gaps else "; ".join(phase5_gaps),
        }
    )

    phase6_gaps = []
    simplify = "plugins/code-tidying/skills/batch-simplify/SKILL.md"
    if not file_has(root, simplify, SIMPLIFY_HEADING):
        phase6_gaps.append("batch-simplify native step heading")
    if not file_has(root, simplify, AXIS):
        phase6_gaps.append("batch-simplify axis line")
    if not baked_flag(rows, "simplify", "code-tidying", "batch-simplify", "native_step"):
        phase6_gaps.append("batch-simplify native_step")
    units.append(
        {
            "id": "phase6",
            "issue": "4051",
            "status": "ok" if not phase6_gaps else "open",
            "detail": "simplify native step" if not phase6_gaps else "; ".join(phase6_gaps),
        }
    )

    run_e2e = "plugins/testing/skills/run-e2e/SKILL.md"
    phase7_ok = (
        file_has(root, run_e2e, RUN_HEADING)
        and file_has(root, run_e2e, AXIS)
        and baked_flag(rows, "run", "testing", "run-e2e", "native_step")
    )
    units.append(
        {
            "id": "phase7",
            "issue": "4052",
            "status": "ok" if phase7_ok else "open",
            "detail": "run native step" if phase7_ok else "run-e2e native step or baked flag missing",
        }
    )

    review_ok = file_has(
        root, "plugins/review/skills/code-review/SKILL.md", ROUTE_TOKEN
    ) and file_has(root, "plugins/review/skills/security-review/SKILL.md", ROUTE_TOKEN)
    units.append(
        {
            "id": "phase8",
            "issue": "4053",
            "status": "ok" if review_ok else "open",
            "detail": "route phrases" if review_ok else "review route phrase missing",
        }
    )

    visualize_ok = file_has(root, "plugins/visualization/skills/visualize/SKILL.md", ROUTE_TOKEN)
    units.append(
        {
            "id": "phase9",
            "issue": "4054",
            "status": "ok" if visualize_ok else "open",
            "detail": "design route phrase" if visualize_ok else "visualize route phrase missing",
        }
    )

    prototype_ok = file_has(
        root, "plugins/prototype/skills/explore-directions/SKILL.md", ROUTE_TOKEN
    )
    units.append(
        {
            "id": "phase10",
            "issue": "4055",
            "status": "ok" if prototype_ok else "open",
            "detail": "design route phrase" if prototype_ok else "explore-directions route phrase missing",
        }
    )

    export_files = (
        "plugins/session-flow/skills/clean-stop/SKILL.md",
        "plugins/session-flow/skills/handoff/SKILL.md",
        "plugins/session-flow/skills/retro/SKILL.md",
    )
    export_skills = ("clean-stop", "handoff", "retro")
    phase11_gaps = [rel for rel in export_files if not file_has(root, rel, EXPORT_SENTENCE)]
    for skill in export_skills:
        if not baked_flag(rows, "export", "session-flow", skill, "suggest_sentence"):
            phase11_gaps.append(f"{skill} suggest_sentence")
    units.append(
        {
            "id": "phase11",
            "issue": "4056",
            "status": "ok" if not phase11_gaps else "open",
            "detail": "export suggest sentences" if not phase11_gaps else "; ".join(phase11_gaps),
        }
    )
    return units


def render(units: list[dict[str, str]]) -> str:
    lines = [f"{unit['id']} issue={unit['issue']} status={unit['status']} detail={unit['detail']}" for unit in units]
    open_ids = [unit["id"] for unit in units if unit["status"] != "ok"]
    lines.append(f"summary open={len(open_ids)} units={','.join(open_ids) if open_ids else 'none'}")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report native-overlap epic unit presence.")
    parser.add_argument("--root", default=".", help="checkout to read")
    args = parser.parse_args(argv)
    root = Path(args.root)
    try:
        units = evaluate(root)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    sys.stdout.write(render(units))
    return 1 if any(unit["status"] != "ok" for unit in units) else 0


if __name__ == "__main__":
    raise SystemExit(main())
