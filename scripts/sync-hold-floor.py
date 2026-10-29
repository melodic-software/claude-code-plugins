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
  (`**/X` is `X` and `*/X`; a trailing `/**` is `/*`), while pr-pipeline.yaml's
  `merge.diff-check.path-holds` is true. Absent or false writes an empty list, so no author's pull
  request is held for its paths (owner decision Q21, 2026-10-29).
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


def path_holds() -> bool:
    """pr-pipeline.yaml's `merge.diff-check.path-holds`: absent is false."""
    found = subprocess.run(
        ["bash", str(ROOT / "lib/parse-concern-value.sh"), "--strict"]
        + [str(ROOT / PIPELINE), "merge.diff-check.path-holds", "false"],
        capture_output=True,
        text=True,
        check=False,
    )
    value = found.stdout.strip()
    if found.returncode != 0 or value not in ("true", "false"):
        raise SystemExit(
            f"sync-hold-floor: merge.diff-check.path-holds in {PIPELINE} is not true or false: {found.stderr}"
        )
    return value == "true"


def hold_patterns(indent: str, holds: bool | None = None) -> list[str]:
    globs = [g for g in HOLD_PATHS if g not in SCRUTINY_ONLY]
    if not (path_holds() if holds is None else holds):
        globs = []
    quoted = " ".join(f"'{p}'" for g in globs for p in bash_patterns(g))
    return [f"{indent}hold_patterns=({quoted})"]


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


PIPELINE = "docs/conventions/pr-pipeline.yaml"
MERGE_HOLDS = ".github/scripts/pr-merge/merge-holds.mjs"
BLOCKS = {
    RISK: {"GATE_WORKFLOWS": gate_workflow_rows},
    MERGE_HOLDS: {"COST_PATHS": cost_rows, "HOLD_PATH_CLASSES": class_rows},
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
