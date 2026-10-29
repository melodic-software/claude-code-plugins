#!/usr/bin/env python3
"""Generate the lane hold-floor copies from babysit_risk.

    python3 -I scripts/sync-hold-floor.py           rewrite every copy
    python3 -I scripts/sync-hold-floor.py --check   print the diff and exit 1 if a copy is stale

The table is `babysit_risk.FLOOR_CLASSES` (with `COST_PATHS`), whose workflow rows this script
derives from the workflow files with `babysit_risk.gated_workflow` and writes into its
`GATE_WORKFLOWS` block. Each copy below sits between
`BEGIN hold-floor <name>` and `END hold-floor <name>` comment lines and is never edited by
hand: change the table, then run this script. test_merge_holds_sync.py runs `--check`.

- merge-holds.mjs `COST_PATHS` and `HOLD_PATH_CLASSES` rows: literals, because ci-status
  runs that file alone and it imports no repository file.
- the review callers' `hold-paths`: the trusted-actor list, every floor glob, then the
  security review's own files (scrutiny only).
- ci-status's exempt-author `hold_patterns`: the same less those two, as bash patterns
  (`**/X` is `X` and `*/X`; a trailing `/**` is `/*`).
- babysit_risk.py and merge-holds.mjs `LANE_ARM`: `merge.lane-arm-gate` (on only when it
  reads exactly `true`), the lane-armed rows (the merge gate's own code, `lane_armable`, less
  `merge.person-held`) and every other `trust` and `gate` row as person-held, read from
  docs/conventions/pr-pipeline.yaml through the shared YAML reader. A person-held entry that
  is not a `trust` or `gate` floor row, a repeated one, a file the reader rejects, or a `gate`
  row outside the merge gate's code that is neither listed nor a gated workflow stops the
  script.
- `.github/trust-path-hold.json`, the whole file, which ci-workflows'
  pr-require-checks-trust-paths reads at the base SHA: `.github/**`, then the `hold_patterns`
  outside `.github/`, and `merge.trust-path-hold-apps` from pr-pipeline.yaml as `apps`. Its
  globs match whole paths case-insensitively with `*` crossing `/`, as bash patterns under
  nocasematch do, so the bash forms carry over unchanged.
"""

from __future__ import annotations

import difflib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugins/source-control/skills/babysit-prs/scripts"))

import babysit_risk  # noqa: E402

WORKFLOWS = ROOT / ".github/workflows"
RISK = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py"


def gate_workflows() -> list[str]:
    """Each top-level workflow `babysit_risk.gated_workflow` gates, read from
    the files, so a workflow that gains a secret joins the gate."""
    return sorted(
        f".github/workflows/{f.name}"
        for f in WORKFLOWS.iterdir()
        if f.is_file()
        and f.suffix in (".yml", ".yaml")
        and babysit_risk.gated_workflow(f.stem, f.read_text(encoding="utf-8"))
    )


def floor_classes() -> list[tuple[str, str]]:
    """The floor as the generated copies hold it: `FLOOR_CLASSES` with its
    workflow rows derived again from the files."""
    rows = [
        (g, c)
        for g, c in babysit_risk.FLOOR_CLASSES
        if not (c == "gate" and g.startswith(".github/workflows/") and "*" not in g)
    ]
    return rows + [(g, "gate") for g in gate_workflows()]


def gate_workflow_rows(indent: str) -> list[str]:
    return [f'{indent}({json.dumps(g)}, "gate"),' for g in gate_workflows()]


TRUSTED_ACTORS = ".github/standards/trusted-actors/**"
SCRUTINY_ONLY = (
    "plugins/review/skills/security-review/**",
    "plugins/review/evals/security-review-*/**",
)
HOLD_PATHS = (TRUSTED_ACTORS, *(g for g, _ in floor_classes()), *SCRUTINY_ONLY)


def bash_patterns(glob: str) -> list[str]:
    if glob.endswith("/**"):
        glob = glob[:-3] + "/*"
    found = [glob[3:], "*/" + glob[3:]] if glob.startswith("**/") else [glob]
    # Bash's `*` crosses `/`, which Python's and Node's `*` never do, so a
    # glob whose `*` is not the leading `**/` or trailing `/**` has no form
    # that matches the same paths.
    core = glob.removeprefix("**/").removesuffix("/*")
    if any(c in core for c in "*?[") or "'" in glob:
        raise SystemExit(f"sync-hold-floor: no bash form for {glob!r}")
    return found


def cost_rows(indent: str) -> list[str]:
    return [f"{indent}{json.dumps(g)}," for g in babysit_risk.COST_PATHS]


def class_rows(indent: str) -> list[str]:
    return [f"{indent}[{json.dumps(g)}, {json.dumps(c)}]," for g, c in floor_classes()]


def hold_paths(indent: str) -> list[str]:
    return [f"{indent}hold-paths: |", *(f"{indent}  {g}" for g in HOLD_PATHS)]


def hold_patterns(indent: str) -> list[str]:
    globs = [g for g in HOLD_PATHS if g not in SCRUTINY_ONLY]
    quoted = " ".join(f"'{p}'" for g in globs for p in bash_patterns(g))
    return [f"{indent}hold_patterns=({quoted})"]


PIPELINE = ROOT / "docs/conventions/pr-pipeline.yaml"
SWITCH_KEY = "merge.lane-arm-gate"
HELD_KEY = "merge.person-held"


# The merge gate's own code, the only rows the switch may lane-arm (owner
# decision Q5): babysit_risk.py and the pr-merge scripts, `trust` rows
# included. Every other `trust` row is person-held.
LANE_ARMABLE_FILE = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py"
LANE_ARMABLE_DIR = ".github/scripts/pr-merge/"


def lane_armable(glob: str) -> bool:
    return glob == LANE_ARMABLE_FILE or (
        glob.startswith(LANE_ARMABLE_DIR) and "/" not in glob[len(LANE_ARMABLE_DIR) :]
    )


def lane_arm() -> tuple[bool, list[str], list[str]]:
    """(`merge.lane-arm-gate` is exactly `true`, the person-held globs, the
    lane-armed globs). The lane-armed globs are the `lane_armable` floor rows
    not in `merge.person-held`, none with the switch off; the person-held
    globs are every other `trust` and `gate` row. Each `merge.person-held`
    entry must be a `trust` or `gate` floor row, and every `gate` row outside
    `lane_armable` must be in it or be a gated workflow (`gate_workflows`), so
    a workflow that gains a credential is person-held at once."""
    import babysit_merge_policy  # noqa: PLC0415

    text = PIPELINE.read_text(encoding="utf-8")
    values = babysit_merge_policy._concern_values(
        text, [(SWITCH_KEY, False), (HELD_KEY, True)]
    )
    if values is None:
        raise SystemExit(f"sync-hold-floor: the shared YAML reader rejects {PIPELINE}")
    held = values[HELD_KEY]
    rows = dict(floor_classes())
    bad = [g for g in held if rows.get(g) not in ("trust", "gate")]
    if bad or len(set(held)) != len(held):
        raise SystemExit(
            f"sync-hold-floor: {HELD_KEY} holds a repeated entry or one that is not a "
            f"trust or gate floor row: {bad or held}"
        )
    on = values[SWITCH_KEY] == ["true"]
    listed = {*held, *gate_workflows()}
    loose = [
        g
        for g, c in floor_classes()
        if c == "gate" and not lane_armable(g) and g not in listed
    ]
    if loose:
        raise SystemExit(
            f"sync-hold-floor: {loose} are `gate` rows outside the merge gate's own "
            f"code: add them to {HELD_KEY}"
        )
    armed = [
        g
        for g, c in floor_classes()
        if on and c in ("trust", "gate") and lane_armable(g) and g not in held
    ]
    person = [
        g for g, c in floor_classes() if c in ("trust", "gate") and g not in armed
    ]
    return on, person, armed


def risk_lane_arm(indent: str) -> list[str]:
    on, held, armed = lane_arm()
    return [
        f"{indent}LANE_ARM_GATE = {on}",
        f"{indent}LANE_ARMED: tuple[str, ...] = (",
        *(f"{indent}    {json.dumps(g)}," for g in armed),
        f"{indent})",
        f"{indent}PERSON_HELD: tuple[str, ...] = (",
        *(f"{indent}    {json.dumps(g)}," for g in held),
        f"{indent})",
    ]


def mjs_lane_arm(indent: str) -> list[str]:
    on, held, armed = lane_arm()
    return [
        f"{indent}export const LANE_ARM_GATE = {json.dumps(on)};",
        f"{indent}export const LANE_ARMED = Object.freeze([",
        *(f"{indent}  {json.dumps(g)}," for g in armed),
        f"{indent}]);",
        f"{indent}export const PERSON_HELD = Object.freeze([",
        *(f"{indent}  {json.dumps(g)}," for g in held),
        f"{indent}]);",
    ]


def trust_path_hold() -> str:
    found = subprocess.run(
        ["bash", str(ROOT / "lib/parse-concern-value.sh"), "--strict", "--list"]
        + [str(ROOT / PIPELINE), "merge.trust-path-hold-apps"],
        capture_output=True,
        text=True,
        check=False,
    )
    apps = found.stdout.split()
    if found.returncode != 0 or not apps:
        raise SystemExit(
            f"sync-hold-floor: no merge.trust-path-hold-apps in {PIPELINE}: {found.stderr}"
        )
    globs = [g for g in HOLD_PATHS if g not in SCRUTINY_ONLY]
    patterns = [p for g in globs for p in bash_patterns(g)]
    paths = [".github/**", *(p for p in patterns if not p.startswith(".github/"))]
    return json.dumps({"paths": paths, "apps": apps}, indent=2) + "\n"


MERGE_HOLDS = ".github/scripts/pr-merge/merge-holds.mjs"
BLOCKS = {
    RISK: {"GATE_WORKFLOWS": gate_workflow_rows, "LANE_ARM": risk_lane_arm},
    MERGE_HOLDS: {
        "COST_PATHS": cost_rows,
        "HOLD_PATH_CLASSES": class_rows,
        "LANE_ARM": mjs_lane_arm,
    },
    ".github/workflows/pr-review-hosted.yml": {"hold-paths": hold_paths},
    ".github/workflows/pr-review-security-hosted.yml": {"hold-paths": hold_paths},
    ".github/workflows/pr-require-checks.yml": {"hold_patterns": hold_patterns},
}
WHOLE = {".github/trust-path-hold.json": trust_path_hold}


def marker(lines: list[str], text: str, path: str) -> int:
    found = [i for i, line in enumerate(lines) if line.lstrip("/# ").startswith(text)]
    if len(found) != 1:
        raise SystemExit(
            f"sync-hold-floor: {path} has {len(found)} '{text}' lines, not 1"
        )
    return found[0]


def generate(path: str, text: str) -> str:
    if path in WHOLE:
        return WHOLE[path]()
    lines = text.split("\n")
    for name, render in BLOCKS[path].items():
        begin = marker(lines, f"BEGIN hold-floor {name}", path)
        end = marker(lines, f"END hold-floor {name}", path)
        if end < begin:
            raise SystemExit(f"sync-hold-floor: {path} ends {name} before it begins")
        indent = lines[begin][: len(lines[begin]) - len(lines[begin].lstrip())]
        lines[begin + 1 : end] = render(indent)
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    check = argv == ["--check"]
    if argv and not check:
        print(__doc__, file=sys.stderr)
        return 2
    stale = 0
    for path in (*BLOCKS, *WHOLE):
        file = ROOT / path
        text = ""
        if file.exists() or path not in WHOLE:
            with open(file, encoding="utf-8", newline="") as handle:
                text = handle.read()
        want = generate(path, text)
        if want == text:
            continue
        stale += 1
        if check:
            sys.stdout.writelines(
                difflib.unified_diff(
                    text.splitlines(keepends=True),
                    want.splitlines(keepends=True),
                    f"a/{path}",
                    f"b/{path}",
                )
            )
        else:
            with open(file, "w", encoding="utf-8", newline="") as handle:
                handle.write(want)
            print(f"sync-hold-floor: rewrote {path}")
    if check and stale:
        print(
            f"sync-hold-floor: {stale} file(s) stale; run python3 -I scripts/sync-hold-floor.py"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
