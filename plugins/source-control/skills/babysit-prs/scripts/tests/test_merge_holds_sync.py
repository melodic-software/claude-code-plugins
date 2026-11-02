# test-scope: scripts/sync-hold-floor.py .github/scripts/pr-merge/merge-holds.mjs .github/scripts/pr-merge/enable-auto-merge.mjs .github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml .github/workflows/pr-require-checks.yml docs/conventions/pr-pipeline.yaml
"""The native auto-merge holds (`.github/scripts/pr-merge/merge-holds.mjs`,
run here under node) cover the merge gate's cost paths, so a lane pull
request native auto-merge merges cannot skip them. The gate's other cost
reasons (Pulumi project files, workflow and pipeline lines) are not mirrored:
the lanes App's token never carries the `workflows` permission
(request-lane-token checks the grant is contents, pull-requests, issues and
at most actions), so no lanes App push changes a workflow file. That covers
lanes App pushes only: another identity with write access can still push a
workflow change after auto-merge is armed.

- The copies: `scripts/sync-hold-floor.py --check` finds `HOLD_PATH_CLASSES`,
  `COST_PATHS`, the review callers' `hold-paths` and ci-status's
  `hold_patterns` as it writes them from the effective floor and
  `COST_PATHS`.
- The floor (owner decisions Q-FLOOR (B), Q-ENFORCE (A) and Q26 option B):
  `pathHold` holds, with no configured glob, exactly the paths `glob_match`
  matches over `babysit_risk.Floor.high` (its `trust` and `gate` globs), case
  variants included; an `enforcement` path is the gate's (`review-path:`),
  and a trusted path off the floor holds only for a configured glob. Every module the floor actions load is on the
  floor, every pr-merge script as `gate` or, for the scripts that apply the
  holds, `trust`, and of babysit-prs/scripts/ exactly the Python that decides
  the holds, `babysit_merge*` as `trust`. The review
  callers' `hold-paths` and ci-status's exempt-author `hold_patterns` each
  match every floor entry, whatever its class. The gate's trusted-author
  lift (`babysit_risk.Floor.author_review`) is exactly the `gate` class, and
  `pathHold`, which judges only lanes App pull requests, holds all of it.
- The cost paths: the same paths matched as `babysit_risk.COST_PATHS` (`glob_match` folds case and covers what sits under a glob).
- The cost decision: `costDecision` accepts the same comments as
  `babysit_merge_policy.cost_decision`, with the owner a trusted person in
  place of an admin, a linked-issue comment counting only when it names the
  pull request as `#<number>` (`namesPull`, `names_pull`), and both carry it
  to the same heads: the decided head, read from the review lanes' check-run
  notices (`noticedHead`, `_noticed_head`) while the head branch's push
  history shows a run of every review lane on each head pushed since it
  (`unranHead`, `unran_head`), or a later one with the same net change
  against the base branch (`sameNetChange`).
- The high-path lift: `pathLifters` over `fromRest` and
  `babysit_merge_policy.path_lifters` name the same trusted approvers of the
  head on the same REST review lists.
"""

from __future__ import annotations

import ast
import importlib.util
import fnmatch
import json
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import unittest
from datetime import datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_risk as risk

ROOT = pathlib.Path(__file__).resolve().parents[6]
# This repository's effective floor: the built-in rows joined to its config.
ROWS = policy.floor_paths_in(
    (ROOT / "docs/conventions/pr-pipeline.yaml").read_text(encoding="utf-8")
)
FLOOR = risk.floor_for(ROWS)
MODULE = ROOT / ".github/scripts/pr-merge/merge-holds.mjs"
# The floor actions' entry points and the floored scripts that enforce the
# floor (owner decision Q-ENFORCE (A)): every module they load is code main
# runs with their verdict, so the floor holds it too.
FLOOR_ENTRIES = (
    ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
    ".github/actions/resolve-config/resolve-config.mjs",
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/enable-auto-merge.mjs",
    ".github/scripts/pr-merge/superseded.mjs",
    ".github/scripts/pr-merge/clear-escalations.mjs",
    ".github/scripts/pr-merge/refire-refused.mjs",
)
# The scripts that act on a pr-unblock stop's route: report-escalation.sh adds
# `needs-human` for a held reason, adjudicate-feedback.mjs decides which threads
# a model verdict may settle, publish-feedback.mjs resolves threads, and
# apply-patch.mjs decides which fix-ci escalations hold. fix-ci-context.mjs,
# feedback-dispatch.mjs and limit-stop.mjs decide `stop-resolved`, which
# clears a failing pr-unblock/* status that ci-status enforces. Flooring the
# routing table alone would let an edit to one of them drop a hold.
ROUTE_ENTRIES = (
    ".github/scripts/pr-unblock/report-escalation.sh",
    ".github/scripts/pr-unblock/adjudicate-feedback.mjs",
    ".github/scripts/pr-unblock/publish-feedback.mjs",
    ".github/scripts/apply-patch/apply-patch.mjs",
    ".github/scripts/pr-unblock/fix-ci-context.mjs",
    ".github/scripts/pr-unblock/feedback-dispatch.mjs",
    ".github/scripts/pr-unblock/limit-stop.mjs",
)
# A relative import, or a module-relative file a module reads at load
# (`new URL("./x.json", import.meta.url)`): data such as a routing table
# decides as much as the code that reads it.
IMPORT = re.compile(
    r"""(?:(?:from|import)\s*\(?|new\s+URL\()\s*["'](\.{1,2}/[^"']+)["']"""
)


# The trusted-actor list is held outside the floor table: the trust gate
# rates it HIGH, and every review caller's hold-paths lists it first.
def floor_or_trust_gate(path: str) -> bool:
    return path == risk.TRUSTED_ACTORS_PATH or any(
        risk.glob_match(g, path) for g in FLOOR.all
    )


def import_closure(entries: tuple[str, ...]) -> list[str]:
    seen: set[str] = set()
    todo = [ROOT / entry for entry in entries]
    while todo:
        file = todo.pop().resolve()
        name = file.relative_to(ROOT).as_posix()
        if name in seen:
            continue
        # A directory URL (admit.mjs lists `../../workflows/` for their
        # names) loads no code; each gated workflow is floored by name.
        if file.is_dir():
            continue
        seen.add(name)
        for spec in IMPORT.findall(file.read_text(encoding="utf-8")):
            todo.append(file.parent / spec)
    return sorted(seen)


# The Python that decides the holds: babysit_risk, and every script a floored
# JS module runs (enable-auto-merge.mjs's VERIFY_SCRIPT), with every module of
# babysit-prs/scripts/ they import.
SCRIPTS = pathlib.Path(risk.__file__).resolve().parent
# A script path in a quoted string, or a bare one a `python`/`python3` command
# runs, with or without a `.base/` checkout prefix.
PY_RUN = re.compile(
    r"""["'`][^"'`\s]*?(plugins/[^"'`\s]+\.py)["'`]"""
    r"""|\bpython3?\s+(?:-\S+\s+)*(?:\.base/)?(plugins/[^"'`\s;)]+\.py)"""
)
# A script a shell step names through a variable (`scripts=<dir>` then
# `"$scripts/<name>.py"`), resolved from the same file's assignments.
PY_VAR = re.compile(r"""\$\{?([A-Za-z_]\w*)\}?/([A-Za-z0-9_.-]+\.py)""")
PY_DIR = re.compile(r"""^\s*([A-Za-z_]\w*)=["']?(?:\.base/)?(plugins/[^"'\s]+)""", re.M)


def py_runs(text: str) -> list[str]:
    dirs = dict(PY_DIR.findall(text))
    return [
        *(quoted or bare for quoted, bare in PY_RUN.findall(text)),
        *(f"{dirs[var]}/{name}" for var, name in PY_VAR.findall(text) if var in dirs),
    ]


def python_closure(js_files: list[str]) -> list[str]:
    todo = [SCRIPTS / "babysit_risk.py"]
    # A floor entry for a script not in this tree yet runs nothing here.
    floored = {g for g in FLOOR.all if g.endswith(".mjs") and (ROOT / g).is_file()}
    for name in sorted(floored | set(js_files)):
        # Quoted paths only: a floored module's strings, not its prose.
        for path, _ in PY_RUN.findall((ROOT / name).read_text(encoding="utf-8")):
            if path:
                todo.append(ROOT / path)
    seen: set[str] = set()
    while todo:
        file = todo.pop()
        name = file.relative_to(ROOT).as_posix()
        if name in seen:
            continue
        seen.add(name)
        for node in ast.walk(ast.parse(file.read_text(encoding="utf-8"))):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and not node.level and node.module:
                names = [node.module]
            else:
                continue
            todo.extend(
                SCRIPTS / f"{n}.py" for n in names if (SCRIPTS / f"{n}.py").is_file()
            )
    return sorted(seen)


NODE = """
import { costHold, pathHold } from %s;
const [paths, globs] = JSON.parse(process.argv[1]);
console.log(JSON.stringify({
  cost: paths.map((path) => costHold([path], null) !== null),
  held: paths.map((path) => pathHold([path], []) !== null),
  configured: paths.map((path) => pathHold([path], globs) !== null),
}));
"""
# A configured denied-paths list, for the presence case.
CONFIGURED = ["Docs/Conventions/PR-Pipeline.yaml", ".github/workflows/**"]
PATHS = [
    "plugins/multi-agent/reference/defaults.yaml",
    "Plugins/Multi-Agent/Reference/Defaults.YAML",
    "plugins/multi-agent/reference/defaults.yml",
    "Pulumi.yaml",
    "infra/Pulumi.yaml",
    "infra/Pulumi.yml",
    "infra/Pulumi.json",
    "infra/pulumi.PROD.yaml",
    "infra/Pulumi.prod.yml",
    "infra/Pulumi.prod.json",
    "infra/Pulumi.md",
    "main.tf",
    "infra/main.tf.json",
    "infra/terraform.tfvars.json",
    "infra/main.json",
    "deploy/azuredeploy.json",
    "deploy/AzureDeploy.Parameters.json",
    "deploy/prereq.azuredeploy.json",
    "deploy/prereqs/prereq.azuredeploy.parameters.json",
    "deploy/azuredeploy.md",
    ".infra/net/main.TF",
    "a.tf/inside.txt",
    ".tf",
    "infra/.tf",
    "x/.tfvars",
    ".bicep",
    "a/.bicepparam",
    "infra/.x.tf",
    "infra/.terraform/x.tf",
    "vars.tfvars",
    "deploy/main.bicep",
    "deploy/main.bicepparam",
    "deploy/main.bicep.md",
    "docs/a.md",
]
FLOOR_PATHS = [
    ".github/actions/resolve-config/resolve.mjs",
    ".github/actions/Resolve-Config/resolve.mjs",
    ".github/actions/request-lane-token/action.yml",
    ".github/actions/Request-Lane-Token/index.mjs",
    ".github/actions/check-kill-switch/check-kill-switch.mjs",
    ".github/actions/CHECK-KILL-SWITCH/action.yml",
    ".github/actions/log-api-budget/rate-guard.mjs",
    ".github/actions/log-api-budget/Rate-Guard.MJS",
    ".github/actions/log-api-budget/action.yml",
    ".github/actions/log-api-budget/rate-guard.test.mjs",
    ".github/actions/log-api-budget/rate-limits.json",
    ".github/actions/log-api-budget/Rate-Limits.JSON",
    ".github/CODEOWNERS",
    ".github/codeowners",
    "CODEOWNERS",
    "docs/CodeOwners",
    ".gitmodules",
    "vendor/.GitModules",
    ".github/standards/trusted-actors/trusted-actors.json",
    ".github/Standards/trusted-actors/trusted-actors.json",
    ".github/actions/check-trusted-trigger/action.yml",
    ".github/actions/Check-Trusted-Trigger/action.yml",
    ".github/scripts/pr-merge/rotation.mjs",
    ".github/scripts/pr-merge/rotation.test.mjs",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
    ".github/scripts/work-resolve-issue/report-outcome.mjs",
    "Docs/Conventions/PR-Pipeline.yaml",
    ".github/actions/other/action.yml",
    ".github/workflows/x.yml",
    "docs/CODEOWNERS.md",
    "plugins/foo/.claude-plugin/plugin.json",
]


def module(paths: list[str]) -> dict[str, Any]:
    script = NODE % json.dumps(MODULE.as_uri())
    proc = subprocess.run(
        ["node", "--input-type=module", "-e", script, json.dumps([paths, CONFIGURED])],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


# What ci-status's hold_patterns add beside the floor (sync-hold-floor.py).
TRUSTED_ACTORS_GLOB = ".github/standards/trusted-actors/**"


def _glob_samples(glob: str) -> list[str]:
    """Paths a floor glob should and should not match: its literal core at
    the root and nested under it, deeper below a trailing `**`, and near
    misses that share its prefix or suffix."""
    core = glob.removeprefix("**/").removesuffix("/**")
    found = [core, f"{core}x", f"x{core}", f"{core}/a", f"{core}/a/b/c.md"]
    if glob.startswith("**/"):
        found += [f"a/{core}", f"a/b/{core}/c", f"a{core}"]
    # A sibling and a deeper file in its directory, with its extension: where
    # a `*` that crosses `/` would reach and one that does not would not.
    parent, _, name = core.rpartition("/")
    ext = name[name.rfind(".") :] if "." in name.lstrip(".") else ""
    if parent:
        found += [f"{parent}/other{ext}", f"{parent}/x/y{ext}"]
    return found


@unittest.skipUnless(shutil.which("node"), "node not installed")
@unittest.skipUnless(shutil.which("bash"), "bash not installed")
class TheThreeMatchersHoldTheSamePaths(unittest.TestCase):
    """merge-holds.mjs's matchesHoldPath and ci-status's bash `hold_patterns`
    judge each sample path alike (bash's `*` crosses `/`, Node's does not),
    and neither holds a path Python's glob_match lets through. glob_match
    also covers what sits under a pattern and `X` for `X/**` (its docstring),
    so the merge gate is the widest of the three, never the narrowest."""

    def test_each_sample_path_is_held_by_all_three_or_none(self) -> None:
        globs = [TRUSTED_ACTORS_GLOB, *FLOOR.all]
        paths = sorted({p for g in globs for p in _glob_samples(g)})
        python = [any(risk.glob_match(g, p) for g in globs) for p in paths]
        node = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                "import { HOLD_PATH_CLASSES, matchesHoldPath } from %s;"
                " const [paths, extra] = JSON.parse(process.argv[1]);"
                " const globs = [...extra, ...HOLD_PATH_CLASSES.map(([g]) => g)];"
                " console.log(JSON.stringify(paths.map((p) => globs.some((g) => matchesHoldPath(p, g)))));"
                % json.dumps(MODULE.as_uri()),
                json.dumps([paths, [TRUSTED_ACTORS_GLOB]]),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        line = _hold_patterns_line()
        bash = subprocess.run(
            [
                "bash",
                "-c",
                line + "\nshopt -s nocasematch\nwhile IFS= read -r path; do"
                ' held=false; for pattern in "${hold_patterns[@]}"; do'
                ' [[ $path != $pattern ]] || held=true; done; echo "$held";'
                " done",
            ],
            input="\n".join(paths) + "\n",
            capture_output=True,
            text=True,
            check=True,
        )
        node_held = json.loads(node.stdout)
        bash_held = [v == "true" for v in bash.stdout.split()]
        for path, py, js, sh in zip(paths, python, node_held, bash_held, strict=True):
            with self.subTest(path):
                self.assertEqual(js, sh)
                self.assertTrue(py or not js, "held natively, not by the merge gate")
        self.assertIn(True, node_held)
        self.assertIn(False, node_held)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheNativeHoldsCoverTheGate(unittest.TestCase):
    def test_the_cost_paths_are_the_same(self) -> None:
        answer = module(PATHS)
        for path, held in zip(PATHS, answer["cost"], strict=True):
            with self.subTest(path):
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in risk.COST_PATHS)
                )
        self.assertIn(True, answer["cost"])
        self.assertIn(False, answer["cost"])

    def test_the_floor_holds_the_same_paths_on_both_sides(self) -> None:
        answer = module(FLOOR_PATHS)
        self.assertEqual(
            {kind for _, kind in FLOOR.classes}, {"trust", "gate", "enforcement"}
        )
        for path, held, configured in zip(
            FLOOR_PATHS, answer["held"], answer["configured"], strict=True
        ):
            with self.subTest(path):
                on_floor = any(risk.glob_match(g, path) for g in FLOOR.high)
                self.assertEqual(held, on_floor)
                self.assertEqual(
                    configured,
                    on_floor or any(risk.glob_match(g, path) for g in CONFIGURED),
                )
        self.assertIn(True, answer["held"])
        self.assertIn(False, answer["held"])
        self.assertIn(False, answer["configured"])
        self.assertNotEqual(answer["held"], answer["configured"])

    def test_the_author_lift_is_the_gate_class_and_the_lanes_app_never_gets_it(
        self,
    ) -> None:
        # Owner direction 2026-10-27: the Python gate lets a trusted person's
        # own gate-path lines clear on a clean security review
        # (FLOOR.author_review). The native holds judge only the lanes
        # App's pull requests (ci-status skips every other author), so they
        # keep holding every one of those globs for a person.
        # Owner decision Q11 (A) keeps the review's own surface (the gated
        # workflows, the main-run review's scripts, the agent settings and
        # instruction files) out of the lift.
        gate = [g for g, kind in FLOOR.classes if kind == "gate"]
        surface = {
            ".github/scripts/pr-review-main/**",
            "**/.claude/**",
            "**/.claude-lane/**",
            "docs/conventions/instruction-exception-register/**",
            "docs/conventions/untrusted-content/**",
            "**/.mcp.json",
            "**/CLAUDE.md",
            "**/CLAUDE.local.md",
            "**/AGENTS.md",
            "REVIEW.md",
            "docs/standards/**",
            "docs/review/**",
        }
        self.assertEqual(
            list(FLOOR.author_review),
            [
                g
                for g in gate
                if g not in surface and not g.startswith(".github/workflows/")
            ],
        )
        self.assertEqual(len(FLOOR.author_review), 15)
        samples = [g.removeprefix("**/").replace("**", "x.mjs") for g in gate]
        self.assertEqual(module(samples)["held"], [True] * len(samples))
        step = (ROOT / ".github/workflows/pr-require-checks.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("is not the lanes App's; pr-merge's gate or a person", step)

    def test_the_person_floor_is_the_same_list(self) -> None:
        # HOLD_PATH_FLOOR (merge-holds.mjs) is babysit_risk `Floor.high`, entry
        # for entry and in order: the trust and gate globs a person clears.
        script = (
            "import { HOLD_PATH_FLOOR } from %s; console.log(JSON.stringify(HOLD_PATH_FLOOR));"
            % json.dumps(MODULE.as_uri())
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(tuple(json.loads(proc.stdout)), FLOOR.high)
        self.assertEqual(len(FLOOR.high), 71)

    def test_the_floor_holds_what_its_actions_load(self) -> None:
        files = import_closure(FLOOR_ENTRIES)
        self.assertIn(".github/actions/check-kill-switch/check-kill-switch.mjs", files)
        self.assertIn(".github/actions/log-api-budget/rate-guard.mjs", files)
        # The rate-limit defaults rate-guard.mjs reads decide when the lanes
        # stop short of GitHub's limits, so they are held like the module.
        self.assertIn(".github/actions/log-api-budget/rate-limits.json", files)
        # The routing table escalation-routes.mjs reads decides hold or fail
        # per stop reason, so it is held like the module.
        self.assertIn(".github/scripts/pr-unblock/escalation-routes.json", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(floor_or_trust_gate(path))
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in FLOOR.high)
                )

    def test_the_floor_holds_the_code_that_acts_on_a_stop_route(self) -> None:
        files = import_closure(ROUTE_ENTRIES)
        self.assertIn(".github/scripts/apply-patch/protected-paths.mjs", files)
        # report-stop-status, the job that posts the clear, lives in pr-unblock.yml.
        files = sorted({*files, ".github/workflows/pr-unblock.yml"})
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(floor_or_trust_gate(path))
                self.assertEqual(
                    held, any(risk.glob_match(g, path) for g in FLOOR.high)
                )

    def test_every_pr_merge_script_is_held_for_a_person(self) -> None:
        # Owner decision Q26 option B: the merge gate's own code stays a
        # person's, every script pr-merge.yml runs from that directory
        # (`gate`, or `trust` for merge-holds.mjs, which applies the holds).
        folder = ROOT / ".github/scripts/pr-merge"
        scripts = sorted(
            f".github/scripts/pr-merge/{f.name}"
            for f in folder.iterdir()
            if f.is_file()
            and f.suffix in {".mjs", ".bash"}
            and ".test." not in f.name
            and ".fixture." not in f.name
        )
        self.assertIn(".github/scripts/pr-merge/who.mjs", scripts)
        held = {g for g, kind in FLOOR.classes if kind in risk.PERSON_CLASSES}
        for path in scripts:
            with self.subTest(path):
                self.assertIn(path, held)

    def test_the_floor_holds_the_python_that_decides_the_holds(self) -> None:
        files = python_closure(import_closure(FLOOR_ENTRIES))
        scripts = SCRIPTS.relative_to(ROOT).as_posix()
        self.assertIn(f"{scripts}/babysit_verify_evidence.py", files)
        self.assertIn(f"{scripts}/babysit_merge.py", files)
        answer = module(files)
        for path, held in zip(files, answer["held"], strict=True):
            with self.subTest(path):
                self.assertTrue(any(risk.glob_match(g, path) for g in FLOOR.all))
                # babysit_merge*, and the scorer and binder that compute the
                # security review's clear condition, are the gate's own code,
                # a person's; the rest is enforcement, which a clean security
                # review clears.
                name = pathlib.PurePosixPath(path).name
                gate = name.startswith("babysit_merge") or name in {
                    "babysit_risk.py",
                    "babysit_review_evidence.py",
                }
                self.assertEqual(held, gate)
                self.assertEqual(path in FLOOR.review, not gate)
        # Nothing else of that directory: the floor tracks the closure.
        self.assertEqual(
            sorted(g for g in FLOOR.all if g.startswith(f"{scripts}/")), files
        )


class TheCopiesAreGenerated(unittest.TestCase):
    def test_every_copy_is_what_the_generator_writes(self) -> None:
        proc = subprocess.run(
            [sys.executable, "-I", str(ROOT / "scripts/sync-hold-floor.py"), "--check"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


def _hold_paths(workflow: str) -> list[str]:
    text = (ROOT / ".github/workflows" / workflow).read_text(encoding="utf-8")
    block = re.search(r"^      hold-paths: \|\n((?:        \S.*\n)+)", text, re.M)
    assert block, workflow
    return block[1].split()


def _sync_hold_floor() -> Any:
    spec = importlib.util.spec_from_file_location(
        "sync_hold_floor", ROOT / "scripts/sync-hold-floor.py"
    )
    assert spec and spec.loader
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def _hold_patterns_line() -> str:
    """ci-status's exempt-author `hold_patterns` as the generator writes them
    with `merge.diff-check.path-holds` true: the hardened list. While the
    switch is false a guard line after it empties the list for every author
    but Dependabot (test_the_workflow_list_follows_the_path_holds_switch)."""
    return _sync_hold_floor().hold_patterns("", holds=True)[0]


def _workflow_hold_patterns() -> list[str]:
    text = (ROOT / ".github/workflows/pr-require-checks.yml").read_text(
        encoding="utf-8"
    )
    found = re.search(r"^ *hold_patterns=\((.*)\)$", text, re.M)
    assert found
    return shlex.split(found[1])


def _hold_patterns() -> list[str]:
    found = re.fullmatch(r"hold_patterns=\((.*)\)", _hold_patterns_line())
    assert found
    return shlex.split(found[1])


class TheScrutinyListsNameTheFloor(unittest.TestCase):
    """The review callers' `hold-paths` (prompt globs) and ci-status's
    exempt-author `hold_patterns` (bash patterns, `*` crossing `/`) each match
    every floor entry."""

    def test_the_workflow_list_follows_the_path_holds_switch(self) -> None:
        # Owner decisions Q21 and Q24 (2026-10-29): with
        # merge.diff-check.path-holds false a guard empties the list for every
        # author but Dependabot, whose action-pin bumps bring in third-party
        # code; true holds every exempt author.
        sync = _sync_hold_floor()
        actors = json.loads(
            (ROOT / ".github/standards/trusted-actors/trusted-actors.json").read_text(
                encoding="utf-8"
            )
        )["actors"]
        dependabot = [str(a["id"]) for a in actors if a["login"] == "dependabot[bot]"]
        self.assertEqual(dependabot, [sync.DEPENDABOT_ID])
        on = sync.hold_patterns("", holds=True)
        self.assertEqual(on, [_hold_patterns_line()])
        off = sync.hold_patterns("", holds=False)
        self.assertEqual(off[0], on[0])
        self.assertEqual(
            off[-1], f'[ "$AUTHOR_ID" = {sync.DEPENDABOT_ID} ] || hold_patterns=()'
        )
        self.assertTrue(all(line.startswith("#") for line in off[1:-1]))
        text = (ROOT / ".github/workflows/pr-require-checks.yml").read_text(
            encoding="utf-8"
        )
        block = re.search(
            r"BEGIN hold-floor hold_patterns.*?\n(.*?)\n *# END hold-floor hold_patterns",
            text,
            re.S,
        )
        assert block
        self.assertEqual(
            [line.strip() for line in block[1].split("\n")],
            sync.hold_patterns("", sync.path_holds()),
        )
        self.assertEqual(_workflow_hold_patterns(), _hold_patterns())
        self.assertTrue(_hold_patterns())

    def test_each_list_covers_every_floor_entry(self) -> None:
        lists = {
            workflow: (_hold_paths(workflow), risk.glob_match)
            for workflow in ("pr-review-hosted.yml", "pr-review-security-hosted.yml")
        }
        lists["hold_patterns"] = (
            _hold_patterns(),
            lambda pattern, entry: fnmatch.fnmatchcase(entry, pattern),
        )
        for name, (patterns, match) in lists.items():
            self.assertTrue(patterns, name)
            for entry in FLOOR.all:
                with self.subTest(list=name, entry=entry):
                    self.assertTrue(any(match(p, entry) for p in patterns))


NODE_ACTORS = """
import { actorsWidened } from %s;
const cases = JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map(([status, previous, contents]) => actorsWidened({ status, previous, contents }))));
"""
_KYLE = {"id": 1, "login": "kyle", "kind": "human"}
_BOT = {"id": 2, "login": "lanes[bot]", "kind": "bot"}


def _list(*actors: Any, version: Any = 1) -> str:
    return json.dumps({"version": version, "actors": list(actors)}, indent=2)


_BASE_LIST = _list(_KYLE, _BOT)
# Each case: status, renamed-from path, then [base text, head text] or None.
ACTOR_CASES = {
    "an entry added": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, {"id": 3})]),
    "an entry's kind changed": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT | {"kind": "human"})]),
    "a removal beside an addition": ("modified", None, [_BASE_LIST, _list(_KYLE, {"id": 5})]),
    "an entry repeated": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, _BOT)]),
    "another key changed": ("modified", None, [_BASE_LIST, _list(_KYLE, _BOT, version=2)]),
    "unparsable head": ("modified", None, [_BASE_LIST, "{"]),
    "a repeated key": ("modified", None, [_BASE_LIST, _BASE_LIST.replace('"version": 1', '"version": 1, "version": 1')]),
    "actors not a list": ("modified", None, [_BASE_LIST, '{"version": 1, "actors": {}}']),
    "an array at the root": ("modified", None, [_BASE_LIST, "[]"]),
    "contents unread": ("modified", None, None),
    "added": ("added", None, [None, _BASE_LIST]),
    "removed": ("removed", None, [_BASE_LIST, None]),
    "renamed": ("renamed", "a.json", [_BASE_LIST, _BASE_LIST]),
    "an entry removed": ("modified", None, [_BASE_LIST, _list(_KYLE)]),
    "every entry removed": ("modified", None, [_BASE_LIST, _list()]),
    "reformatted and reordered": ("modified", None, [_BASE_LIST, json.dumps({"actors": [_BOT, _KYLE], "version": 1})]),
    "keys reordered in an entry": ("modified", None, [_BASE_LIST, _list({"kind": "human", "login": "kyle", "id": 1}, _BOT)]),
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheHoldLabelsAreTheGates(unittest.TestCase):
    def test_both_hold_the_same_labels(self) -> None:
        module = ROOT / ".github/scripts/pr-merge/enable-auto-merge.mjs"
        script = (
            f"const {{ HOLD_LABELS }} = await import({json.dumps(module.as_uri())});"
            "console.log(JSON.stringify(HOLD_LABELS));"
        )
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(json.loads(proc.stdout), list(policy.MERGE_HOLD_LABELS))


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheWideningHoldIsTheGates(unittest.TestCase):
    def test_both_hold_the_same_trusted_actor_list_changes(self) -> None:
        cases = list(ACTOR_CASES.values())
        script = NODE_ACTORS % json.dumps(MODULE.as_uri())
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", script, json.dumps(cases)],
            capture_output=True,
            text=True,
            check=True,
        )
        answers = json.loads(proc.stdout)
        for (name, (status, previous, contents)), js in zip(
            ACTOR_CASES.items(), answers, strict=True
        ):
            changed = risk.ChangedFile(
                path=risk.TRUSTED_ACTORS_PATH,
                previous_path=previous,
                status=status,
                additions=1,
                deletions=1,
                has_patch=True,
                mode="100644",
                previous_mode=None if status == "added" else "100644",
                contents=None if contents is None else tuple(contents),
            )
            py = risk._actors_widened(risk._check_file(changed), changed)
            with self.subTest(name):
                self.assertEqual(js is None, py is None, (js, py))
        held = [js is not None for js in answers]
        self.assertIn(True, held)
        self.assertIn(False, held)


NODE_LIFTERS = """
import { fromRest, pathLifters } from %s;
const [cases, humans, head] = JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map((rows) => pathLifters(rows.map(fromRest), new Set(humans), head))));
"""
_HEAD = "a" * 40


def _review(
    state: str,
    user: int = 1,
    sha: str = _HEAD,
    at: str = "2026-10-26T16:41:00Z",
    kind: str = "User",
) -> dict[str, Any]:
    return {
        "user": {"id": user, "login": f"u{user}", "type": kind},
        "state": state,
        "commit_id": sha,
        "submitted_at": at,
    }


_LATER = "2026-10-26T17:20:00Z"
# REST review lists, kyle (id 1) and id 3 trusted, at head _HEAD.
LIFTER_CASES = {
    "approved at the head": [_review("APPROVED")],
    "approved at another head": [_review("APPROVED", sha="b" * 40)],
    "an untrusted approver": [_review("APPROVED", user=2)],
    "a bot account": [_review("APPROVED", kind="Bot")],
    "changes requested since": [_review("APPROVED"), _review("CHANGES_REQUESTED", at=_LATER)],
    "dismissed since": [_review("APPROVED"), _review("DISMISSED", at=_LATER)],
    "approved after changes requested": [_review("CHANGES_REQUESTED"), _review("APPROVED", at=_LATER)],
    "a comment after the approval": [_review("APPROVED"), _review("COMMENTED", at=_LATER)],
    "two people, one blocks": [_review("APPROVED", user=3), _review("APPROVED"), _review("CHANGES_REQUESTED", at=_LATER)],
    "no reviews": [],
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheHighPathLiftIsTheGates(unittest.TestCase):
    def test_both_name_the_same_lifters(self) -> None:
        script = NODE_LIFTERS % json.dumps(MODULE.as_uri())
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                script,
                json.dumps([list(LIFTER_CASES.values()), [1, 3], _HEAD]),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        answers = json.loads(proc.stdout)
        for (name, rows), js in zip(LIFTER_CASES.items(), answers, strict=True):
            with self.subTest(name):
                self.assertEqual(policy.path_lifters(rows, {1, 3}, _HEAD), js)
        self.assertIn([], answers)
        self.assertIn(["u1"], answers)
        self.assertIn(["u3"], answers)


REPO = "o/r"
HEAD = "0123456789abcdef0123456789abcdef01234567"
BASE = "89abcdef0123456789abcdef0123456789abcdef"
OLD = "fedcba9876543210fedcba9876543210fedcba98"
PR = {
    "number": 7,
    "created_at": "2026-01-02T00:00:00Z",
    "head": {"sha": HEAD, "ref": "b", "repo": {"full_name": REPO}},
    "base": {"sha": BASE, "ref": "main"},
}
ISSUE = 5
OWNER = {"login": "owner", "id": 1, "type": "User"}
OTHER = {"login": "other", "id": 2, "type": "User"}
DECISION = "**Decision recorded.** Cost: approved"


def _comment(target: int, **fields: Any) -> dict[str, Any]:
    return {
        "issue_url": f"https://api.github.com/repos/{REPO}/issues/{target}",
        "user": OWNER,
        "performed_via_github_app": None,
        "body": DECISION,
        "created_at": "2026-01-03T00:00:00Z",
        "node_id": "N",
        "edited": None,
    } | fields


def _link(target: int, kind: str = "pull", repo: str = REPO) -> str:
    return f"https://github.com/{repo}/{kind}/{target}#issuecomment-11"


# Each case: the body, then the comment its link names.
DECISIONS = {
    "on the pull request": (_link(7), _comment(7)),
    "on the closing issue after the pull request, naming it": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7."),
    ),
    "on the closing issue, naming it in parentheses": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} (#7)"),
    ),
    "on the closing issue, naming no pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE),
    ),
    "on the closing issue, naming another pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #70."),
    ),
    "on the closing issue, naming another repository's": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for x/r#7."),
    ),
    "on the closing issue, naming it only as an entity": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for &#7;"),
    ),
    "on the closing issue, naming it only after a #": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for ##7."),
    ),
    "on the closing issue, naming it, by someone else": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7.", user=OTHER),
    ),
    "on the closing issue before the pull request": (
        _link(ISSUE, "issues"),
        _comment(ISSUE, body=f"{DECISION} for #7.", created_at="2026-01-01T00:00:00Z"),
    ),
    "on another issue": (_link(9, "issues"), _comment(9)),
    "in another repository": (_link(7, repo="x/r"), _comment(7)),
    "inside an HTML comment": (f"<!-- {_link(7)} -->", _comment(7)),
    "inside an unclosed HTML comment": (f"<!-- {_link(7)}", _comment(7)),
    "a comment on another issue": (_link(7), _comment(9)),
    "by a bot": (_link(7), _comment(7, user=OWNER | {"type": "Bot"})),
    "through an App": (_link(7), _comment(7, performed_via_github_app={"id": 1})),
    "by someone else": (_link(7), _comment(7, user=OTHER)),
    "edited": (_link(7), _comment(7, edited="2026-01-04T00:00:00Z")),
    "another decision": (_link(7), _comment(7, body="**Decision recorded.** Ship")),
    "indented": (_link(7), _comment(7, body=f"  {DECISION}")),
}
CHECKS = dict(policy.REVIEW_LANES)


def _run(
    sha: str,
    at: str = "2026-01-02T12:00:00Z",
    *,
    criteria: str = "cost",
    lane: str = "pr-review-hosted.yml",
    job: str | None = None,
    notice: str | None = None,
    created: str = "2026-01-02T11:00:00Z",
    repo: str | None = "o/r",
) -> dict[str, Any]:
    """A review lane's run on `sha` with its head in `repo`, started at
    `created`, whose status job (or `job`) finished at `at` with a hold notice
    naming `notice`."""
    message = f"claude-lane-hold lane=claude-review sha={notice or sha} criteria={criteria} label=needs-human"
    return {
        "lane": lane,
        "sha": sha,
        "at": at,
        "job": job or CHECKS[lane],
        "created": created,
        "repo": repo,
        "notes": [{"annotation_level": "notice", "message": message}],
    }


def _push(after: str, timestamp: str) -> dict[str, Any]:
    return {"after": after, "timestamp": timestamp, "activity_type": "push"}


# The head reads: the review lanes' runs on the head branch (a cost notice at
# the head before the decision by default), their jobs and annotations, a
# compare per head (a run's head answers {"files": [TF]} unless `compares`
# names it), and the head branch's push history, newest first (`activity`,
# by default each run's head pushed five minutes before its first status job
# finished).
DEFAULT_HEADS = {"runs": [_run(HEAD)], "compares": {}}
TF = {"filename": "a.tf", "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}
MORE = {"filename": "b.sh", "status": "added", "patch": "+c"}
LATE = "2026-01-02T18:00:00Z"
NEW = "1" * 40
# A base commit a merge of the base names as its second parent.
MAIN = "5" * 40
# The base branch's tip commit, which its full ref resolves to.
_TIP = "3" * 40
# The decided head OLD, then NEW pushed before the decision; HEAD carries
# OLD's net change.
SINCE = [_push(NEW, "2026-01-02T13:00:00Z"), _push(OLD, "2026-01-02T10:00:00Z")]
SAME = {OLD: {"files": [TF]}, HEAD: {"files": [TF]}}


def _plain(lane: str) -> dict[str, Any]:
    """A run on NEW before the decision whose status job noticed no cost."""
    return _run(
        NEW,
        "2026-01-02T13:10:00Z",
        criteria="trust-gate",
        lane=lane,
        created="2026-01-02T13:05:00Z",
    )


# Each case: the heads world for a decision on the pull request (_link(7)).
CARRIES = {
    "a notice at the head": DEFAULT_HEADS,
    "a base merge since the decided head": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF]}},
    },
    "a commit of its own since": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a rename since": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {"files": [TF | {"status": "renamed", "previous_filename": "z.tf"}]},
        },
    },
    "300 files": {
        "runs": [_run(OLD)],
        "compares": {
            sha: {"files": [TF | {"filename": f"f{i}"} for i in range(300)]}
            for sha in (OLD, HEAD)
        },
    },
    "a file with no patch": {
        "runs": [_run(OLD)],
        "compares": {
            sha: {"files": [{"filename": "a.png", "status": "added"}]}
            for sha in (OLD, HEAD)
        },
    },
    "an unreadable compare": {"runs": [_run(OLD)], "compares": {OLD: {"files": [TF]}}},
    "the latest notice before it, not an older one at the head": {
        "runs": [
            _run(HEAD, "2026-01-02T06:00:00Z", created="2026-01-02T05:00:00Z"),
            _run(OLD),
        ],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a notice from the security lane": {
        "runs": [_run(HEAD, lane="pr-review-security-hosted.yml")]
    },
    "a job done after it": {"runs": [_run(HEAD, "2026-01-04T00:00:00Z")]},
    "a run started after it": {
        "runs": [_run(HEAD, LATE, created="2026-01-03T01:00:00Z")]
    },
    "a job other than the status job": {
        "runs": [_run(HEAD, job="pr-review / review-key")]
    },
    "a notice naming another head than its run's": {"runs": [_run(OLD, notice=HEAD)]},
    "a notice without cost": {"runs": [_run(HEAD, criteria="trust-gate")]},
    "a run whose head is in another repository": {"runs": [_run(HEAD, repo="f/r")]},
    "a run with no head repository": {"runs": [_run(HEAD, repo=None)]},
    "two heads at the newest time": {
        "runs": [_run(HEAD), _run(OLD, lane="pr-review-security-hosted.yml")]
    },
    "no notice": {"runs": []},
    "a run on a head that changes a review-lane workflow": {
        "compares": {
            HEAD: {"files": [{"filename": ".github/workflows/pr-review-hosted.yml"}]}
        }
    },
    "a run on a head whose compare has no file list": {
        "compares": {HEAD: {"status": "diverged"}}
    },
    "a filename listed twice": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF, TF]}, HEAD: {"files": [TF, TF]}},
    },
    "a newer head pushed before it with a run of every lane": {
        "runs": [
            _run(OLD),
            _plain("pr-review-hosted.yml"),
            _plain("pr-review-security-hosted.yml"),
        ],
        "compares": SAME,
        "activity": SINCE,
    },
    "a newer head pushed before it whose lane runs were deleted": {
        "runs": [_run(OLD)],
        "compares": SAME,
        "activity": SINCE,
    },
    "a newer head pushed before it with one lane's run deleted": {
        "runs": [_run(OLD), _plain("pr-review-security-hosted.yml")],
        "compares": SAME,
        "activity": SINCE,
    },
    "a history with no push of the decided head": {
        "runs": [
            _run(OLD),
            _plain("pr-review-hosted.yml"),
            _plain("pr-review-security-hosted.yml"),
        ],
        "compares": SAME,
        "activity": SINCE[:1],
    },
    "a non-merge commit since with the same net change": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}]},
                ],
                "total_commits": 2,
            },
        },
    },
    "a merge of a branch other than the base": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": NEW, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": NEW}]},
                ],
                "total_commits": 3,
            },
        },
    },
    "a merge that also edits a file": {
        "runs": [_run(OLD)],
        "compares": {OLD: {"files": [TF]}, HEAD: {"files": [TF, MORE]}},
    },
    "a force push that rewrote the decided head": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": NEW, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": NEW}, {"sha": MAIN}]},
                ],
                "total_commits": 2,
            },
        },
    },
    "a history longer than the compare lists": {
        "runs": [_run(OLD)],
        "compares": {
            OLD: {"files": [TF]},
            HEAD: {
                "files": [TF],
                "commits": [
                    {"sha": OLD, "parents": [{"sha": MAIN}]},
                    {"sha": HEAD, "parents": [{"sha": OLD}, {"sha": MAIN}]},
                ],
                "total_commits": 251,
            },
        },
    },
    "a patchless pure rename": {
        "runs": [_run(OLD)],
        "compares": {
            sha: {
                "files": [
                    {"filename": "b", "status": "renamed", "previous_filename": "a"}
                ]
            }
            for sha in (OLD, HEAD)
        },
    },
}


def _history(sha: str, answer: Any) -> Any:
    """`answer` (a compare of base...sha) with the commits a history of base
    merges lists unless it names its own: OLD alone for OLD, OLD and a merge
    HEAD of the base for HEAD, the head alone for any other."""
    if not isinstance(answer, dict) or "commits" in answer or "files" not in answer:
        return answer
    commits = [{"sha": OLD if sha == HEAD else sha, "parents": [{"sha": MAIN}]}]
    if sha == HEAD:
        commits.append({"sha": HEAD, "parents": [{"sha": OLD}, {"sha": MAIN}]})
    return answer | {"commits": commits, "total_commits": len(commits)}


def _answers(heads: dict[str, Any]) -> dict[str, Any]:
    answers = {r["sha"]: {"files": [TF]} for r in heads["runs"]} | heads["compares"]
    return {sha: _history(sha, answer) for sha, answer in answers.items()}


def _activity(heads: dict[str, Any]) -> list[dict[str, Any]]:
    if "activity" in heads:
        return heads["activity"]
    first: dict[str, str] = {}
    for r in heads["runs"]:
        first[r["sha"]] = min(first.get(r["sha"], r["at"]), r["at"])
    pushes = [
        _push(
            sha,
            (datetime.fromisoformat(at) - timedelta(minutes=5)).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
        )
        for sha, at in first.items()
    ]
    return sorted(pushes, key=lambda m: m["timestamp"], reverse=True)


NODE_DECISION = """
import { costDecision } from %s;
const [body, comment, issue, heads, answers, activity] = JSON.parse(process.argv[1]);
const github = async (method, path, data) => {
  if (method === "GET" && path === "/repos/o/r/activity?ref=refs%%2Fheads%%2Fb&direction=desc&per_page=100") return activity;
  const tip = "3".repeat(40);
  if (method === "GET" && path.startsWith("/repos/o/r/git/ref/heads/")) return { object: { sha: tip } };
  if (method === "GET" && path.endsWith(`...${tip}`)) return { status: path.includes(`/compare/${"5".repeat(40)}...`) ? "ahead" : "diverged" };
  if (method === "GET" && path.includes("/compare/")) {
    const sha = path.split("...")[1];
    if (!(sha in answers)) throw new Error("no such commit");
    return answers[sha];
  }
  const runs = /\\/actions\\/workflows\\/([a-z-]+\\.yml)\\/runs\\?event=pull_request&branch=b&per_page=100&page=1$/.exec(path);
  if (method === "GET" && runs) {
    return { workflow_runs: heads.runs.flatMap((r, i) => (r.lane === runs[1] ? [{ id: i + 1, head_sha: r.sha, created_at: r.created, head_repository: r.repo && { full_name: r.repo } }] : [])) };
  }
  const jobs = /\\/actions\\/runs\\/([0-9]+)\\/jobs\\?filter=all&per_page=100&page=1$/.exec(path);
  if (method === "GET" && jobs) {
    const r = heads.runs[Number(jobs[1]) - 1];
    return { jobs: [{ id: Number(jobs[1]), name: r.job, completed_at: r.at }] };
  }
  const notes = /\\/check-runs\\/([0-9]+)\\/annotations\\?per_page=100&page=1$/.exec(path);
  if (method === "GET" && notes) return heads.runs[Number(notes[1]) - 1].notes;
  if (method === "GET") return comment;
  if (data.variables.number !== undefined) {
    return { data: { repository: { pullRequest: { createdAt: "2026-01-02T00:00:00Z", baseRefName: "main", headRefName: "b",
      closingIssuesReferences: { totalCount: 1, nodes: [{ number: issue, repository: { nameWithOwner: "o/r" } }] } } } } };
  }
  return { data: { node: { lastEditedAt: comment.edited } } };
};
console.log(JSON.stringify(await costDecision(github, "o/r", 7, body, new Set([1]), %s)));
"""


def js_decision(
    body: str, comment: dict[str, Any], heads: dict[str, Any] = DEFAULT_HEADS
) -> str | None:
    script = NODE_DECISION % (json.dumps(MODULE.as_uri()), json.dumps(HEAD))
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            json.dumps(
                [
                    body,
                    comment,
                    ISSUE,
                    DEFAULT_HEADS | heads,
                    _answers(DEFAULT_HEADS | heads),
                    _activity(DEFAULT_HEADS | heads),
                ]
            ),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def py_decision(
    body: str, comment: dict[str, Any], heads: dict[str, Any] = DEFAULT_HEADS
) -> str | None:
    heads = DEFAULT_HEADS | heads
    answers = _answers(heads)

    def graphql(query: str, what: str, **variables: Any) -> dict[str, Any]:
        return {"node": {"lastEditedAt": comment["edited"]}}

    def get(endpoint: str, env: Any = None) -> tuple[int | None, Any]:
        if "/git/ref/heads/" in endpoint:
            return 200, {"object": {"sha": _TIP}}
        if endpoint.endswith(f"...{_TIP}"):
            parent = endpoint.split("/compare/", 1)[1].split("...")[0]
            return 200, {"status": "ahead" if parent == MAIN else "diverged"}
        if "/compare/" in endpoint:
            sha = endpoint.rsplit("...", 1)[1]
            return (200, answers[sha]) if sha in answers else (404, None)
        return 200, comment

    def get_pages(endpoint: str, env: Any = None) -> tuple[int | None, Any]:
        assert endpoint == (
            "repos/o/r/activity?ref=refs%2Fheads%2Fb&direction=desc&per_page=100"
        ), endpoint
        return 200, [_activity(heads)]

    def paginated(
        endpoint: str, _label: str, items_key: str | None = None, env: Any = None
    ) -> list[dict[str, Any]]:
        if "/actions/workflows/" in endpoint:
            lane = endpoint.split("/actions/workflows/", 1)[1].split("/", 1)[0]
            assert endpoint.endswith(
                "/runs?event=pull_request&branch=b&per_page=100"
            ), endpoint
            return [
                {
                    "id": i + 1,
                    "head_sha": r["sha"],
                    "created_at": r["created"],
                    "head_repository": r["repo"] and {"full_name": r["repo"]},
                }
                for i, r in enumerate(heads["runs"])
                if r["lane"] == lane
            ]
        if "/jobs?" in endpoint:
            n = int(endpoint.split("/actions/runs/", 1)[1].split("/", 1)[0])
            r = heads["runs"][n - 1]
            return [{"id": n, "name": r["job"], "completed_at": r["at"]}]
        n = int(endpoint.split("/check-runs/", 1)[1].split("/", 1)[0])
        return heads["runs"][n - 1]["notes"]

    with (
        mock.patch.object(policy, "_get", side_effect=get),
        mock.patch.object(policy, "_get_pages", side_effect=get_pages),
        mock.patch.object(policy, "_paginated", side_effect=paginated),
        mock.patch.object(policy, "_graphql", graphql),
    ):
        return policy.cost_decision(
            REPO,
            PR | {"body": body},
            ISSUE,
            permission=lambda login: "admin" if login == OWNER["login"] else "write",
            agent_identity=None,
        )


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheCostDecisionIsTheGates(unittest.TestCase):
    def test_both_accept_the_same_comments(self) -> None:
        answers = {}
        for case, (body, comment) in DECISIONS.items():
            with self.subTest(case):
                answers[case] = py_decision(body, comment)
                self.assertEqual(js_decision(body, comment), answers[case])
        self.assertIsNotNone(answers["on the pull request"])
        self.assertIsNotNone(
            answers["on the closing issue after the pull request, naming it"]
        )
        self.assertIsNone(answers["on the closing issue, naming no pull request"])
        self.assertIsNone(answers["on the closing issue, naming it only as an entity"])
        self.assertIsNone(answers["on the closing issue, naming it only after a #"])
        self.assertIsNone(answers["edited"])

    def test_both_carry_a_decision_to_the_same_heads(self) -> None:
        answers = {}
        for case, heads in CARRIES.items():
            with self.subTest(case):
                answers[case] = py_decision(_link(7), _comment(7), heads)
                self.assertEqual(
                    js_decision(_link(7), _comment(7), heads), answers[case]
                )
        carried = {
            "a notice at the head",
            "a base merge since the decided head",
            "a notice from the security lane",
            "a newer head pushed before it with a run of every lane",
        }
        for case in carried:
            self.assertEqual(answers[case], _link(7), case)
        for case in set(CARRIES) - carried:
            self.assertIsNone(answers[case], case)


NODE_CARRY = """
import { approvalCarry, autoDismissed, baseMergeCarry, fromRest, liftsOf } from %s;
let text = "";
for await (const chunk of process.stdin) text += chunk;
const [lifts, carries, from] = JSON.parse(text);
console.log(JSON.stringify([
  lifts.map(([reviews, events]) =>
    liftsOf(reviews.map(fromRest), new Set([1, 3]), autoDismissed(events)).map(({ login, sha, dismissal }) => [login, sha, dismissal]),
  ),
  carries.map(([then, now, inBase, merges, based, dismissal, trees]) => [
    baseMergeCarry(then, now, from, inBase),
    approvalCarry(then, now, from, inBase, merges, based, dismissal, trees),
  ]),
]));
"""
_OLD = "c" * 40
_BASE_SHA = "5" * 40
_HELD = ".github/actions/resolve-config/live-config.test.mjs"
_PATCH = {"filename": _HELD, "status": "modified", "patch": "@@ -1 +1 @@\n-a\n+b"}
_DOC = {"filename": "docs/a.md", "status": "modified", "patch": "+x"}
_LIFTED = "2026-10-27T23:26:14Z"
# The merge bases of the approved head and of the head with the base's tip.
_MB_OLD = "1" * 40
_MB_HEAD = "2" * 40


def _moved(*commits: tuple[str, list[str]]) -> dict[str, Any]:
    return {
        "commits": [
            {"sha": sha, "parents": [{"sha": p} for p in parents]}
            for sha, parents in commits
        ],
        "total_commits": len(commits),
    }


_THEN = {
    "files": [_PATCH],
    "merge_base_commit": {"sha": _MB_OLD},
    **_moved((_OLD, [_BASE_SHA])),
}
_MERGED = {
    "merge_base_commit": {"sha": _MB_HEAD},
    **_moved((_OLD, [_BASE_SHA]), (_HEAD, [_OLD, _BASE_SHA])),
}
_OTHER = "e" * 40
_REWRITTEN = "f" * 40


def _dismissal(review: int = 41, **change: Any) -> dict[str, Any]:
    """GitHub's stale-review dismissal on the base merge's push, as #10224's
    timeline shows it, with `change` applied to it or to its actor."""
    actor = {"login": "lanes[bot]", "type": "Bot"} | change.pop("actor", {})
    return {
        "event": "review_dismissed",
        "actor": actor,
        "dismissed_review": {
            "review_id": review,
            "state": "approved",
            "dismissal_message": None,
            "dismissal_commit_id": _HEAD,
        }
        | change,
    }


def _dismissed(sha: str = _OLD, user: int = 1, review: int = 41) -> dict[str, Any]:
    return _review("DISMISSED", user, sha, _LIFTED) | {"id": review}


# (REST reviews, timeline events): whose approval stands, as (login, sha,
# dismissal commit or None).
LIFT_CASES = {
    "an approval of an earlier head": ([_review("APPROVED", sha=_OLD, at=_LIFTED)], []),
    "an approval by an untrusted account": ([_review("APPROVED", 2, _OLD, _LIFTED)], []),
    "an approval by a bot": ([_review("APPROVED", 1, _OLD, _LIFTED, "Bot")], []),
    "an approval then changes requested on another head": ([
        _review("APPROVED", sha=_OLD, at=_LIFTED),
        _review("CHANGES_REQUESTED", sha="d" * 40, at="2026-10-27T23:40:00Z"),
    ], []),
    "a dismissed approval": ([_dismissed()], []),
    "an approval dismissed after a newer approval": ([
        _review("APPROVED", sha=_OLD, at=_LIFTED),
        _review("DISMISSED", sha=_HEAD, at="2026-10-27T23:40:00Z"),
    ], []),
    "a comment after an approval": ([_review("APPROVED", sha=_OLD, at=_LIFTED), _review("COMMENTED", sha=_HEAD, at="2026-10-27T23:40:00Z")], []),
    "two people": ([_review("APPROVED", 1, _OLD, _LIFTED), _review("APPROVED", 3, _HEAD, _LIFTED)], []),
    # The owner's decision of 2026-10-28 (part a).
    "an approval GitHub dismissed as stale": ([_dismissed()], [_dismissal()]),
    "a review id read as a string": ([_dismissed()], [_dismissal("41")]),
    "a dismissal with a message": ([_dismissed()], [_dismissal(dismissal_message="stale")]),
    "a dismissal with an empty message": ([_dismissed()], [_dismissal(dismissal_message="")]),
    "a dismissal with no message field": ([_dismissed()], [{"event": "review_dismissed", "actor": {"type": "Bot"}, "dismissed_review": {"review_id": 41, "state": "approved", "dismissal_commit_id": _HEAD}}]),
    "a dismissal by a person": ([_dismissed()], [_dismissal(actor={"type": "User"})]),
    "a dismissal with no actor": ([_dismissed()], [_dismissal() | {"actor": None}]),
    "a dismissed request for changes": ([_dismissed()], [_dismissal(state="changes_requested")]),
    "a dismissal of another review": ([_dismissed()], [_dismissal(42)]),
    "a second dismissal event with a message": ([_dismissed()], [_dismissal(), _dismissal(dismissal_message="no")]),
    "a dismissal commit that is no sha": ([_dismissed()], [_dismissal(dismissal_commit_id=None)]),
    "a stale dismissal by an untrusted account": ([_dismissed(user=2)], [_dismissal()]),
    "changes requested after a stale dismissal": ([_dismissed(), _review("CHANGES_REQUESTED", sha=_HEAD, at="2026-10-27T23:40:00Z")], [_dismissal()]),
}  # fmt: skip
_IN_BASE = [_BASE_SHA]
_HELPER = {
    "filename": "scripts/helper.sh",
    "status": "modified",
    "patch": "@@ -1 +1 @@\n-x\n+y",
}
# What the merges brought into the approved head (compare _OLD..._HEAD) and
# what the base changed between the merge bases (_MB_OLD..._MB_HEAD).
_BASE_DOC = {
    "filename": "docs/base.md",
    "status": "modified",
    "patch": "@@ -1 +1 @@\n-p\n+q",
}
# #10224's shape: the base changed a file the pull request also changes, so
# its net change moved by hunk headers, while the base's hunk applies the same.
_SHARED = ".github/actions/collect-base-activity/collect-base-activity.test.mjs"
_SHARED_OLD = {
    "filename": _SHARED,
    "status": "modified",
    "patch": "@@ -93,6 +93,13 @@ let root;\n context\n+mine",
}
_SHARED_HEAD = _SHARED_OLD | {"patch": "@@ -98,6 +98,13 @@ let root;\n context\n+mine"}
_SHARED_BASE = {
    "filename": _SHARED,
    "status": "modified",
    "patch": "@@ -10,6 +10,11 @@ import\n+theirs",
}


def _brought(files: list[dict[str, Any]], **extra: Any) -> dict[str, Any]:
    return {
        "status": "ahead",
        "behind_by": 0,
        "files": files,
        **_moved((_BASE_SHA, []), (_HEAD, [])),
    } | extra


def _based(files: list[dict[str, Any]], **extra: Any) -> dict[str, Any]:
    return {
        "status": "ahead",
        "behind_by": 0,
        "files": files,
        **_moved((_MB_HEAD, [])),
    } | extra


_CLEAN = (_brought([_BASE_DOC]), _based([_BASE_DOC]))


def _tree(*entries: tuple[str, str], truncated: Any = False) -> dict[str, Any]:
    """A recursive git/trees answer of (path, mode) blobs."""
    return {
        "truncated": truncated,
        "tree": [{"path": p, "mode": m, "type": "blob"} for p, m in entries],
    }


_PATHS = [_HELD, _SHARED, "docs/base.md", "docs/a.md", "scripts/helper.sh"]
_ALL = _tree(*((p, "100644") for p in _PATHS))
# The trees of the head and of its merge base with the tip.
_TREES = [_ALL, _ALL]
_GONE = {"filename": "docs/gone.md", "status": "removed", "patch": "-x"}
_REPLAY_THEN = _THEN | {"files": [_PATCH, _SHARED_OLD]}
_REPLAY_NOW = {"files": [_PATCH, _SHARED_HEAD], **_MERGED}
_REPLAY_BASE = _based([_SHARED_BASE, _BASE_DOC])
_MANY = [
    {"filename": f"docs/{i}.md", "status": "modified", "patch": "+x"}
    for i in range(300)
]
# (then, now, in_base, merges, based, dismissal): whether the approval at _OLD
# carries to _HEAD, by base_merge_carry (the cost carry) and approval_carry.
CARRY_CASES = {
    "a base merge": (_THEN, {"files": [_PATCH], **_MERGED}, _IN_BASE, *_CLEAN, None, _TREES),
    "a base merge with a non-hold file unchanged": ({"files": [_PATCH, _HELPER], **_moved((_OLD, [_BASE_SHA]))}, {"files": [_HELPER, _PATCH], **_MERGED}, _IN_BASE, *_CLEAN, None, _TREES),
    "a merge that rewrites scripts/helper.sh": ({"files": [_PATCH, _HELPER], **_moved((_OLD, [_BASE_SHA]))}, {"files": [_PATCH, _HELPER | {"patch": "+evil"}], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, _HELPER | {"patch": "+evil"}]), _based([_BASE_DOC]), None, _TREES),
    "a merge that adds a file the base touched": (_THEN, {"files": [_PATCH, _DOC], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, _DOC]), _based([_BASE_DOC]), None, _TREES),
    "a base merge after which the base holds a hold path's change": (
        {"files": [_PATCH, _PATCH | {"filename": ".github/actions/resolve-config/b.mjs"}], **_moved((_OLD, [_BASE_SHA]))},
        {"files": [_PATCH], **_MERGED},
        _IN_BASE,
        _brought([_BASE_DOC]),
        _based([_BASE_DOC, _PATCH | {"filename": ".github/actions/resolve-config/b.mjs"}]),
        None,
        _TREES,
    ),
    "a merge of a parent the base does not hold": (_REPLAY_THEN, {"files": [_PATCH, _SHARED_HEAD], **_moved((_OLD, [_BASE_SHA]), (_OTHER, [_BASE_SHA, _BASE_SHA]), (_HEAD, [_OLD, _OTHER]))}, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, _TREES),
    "a merge read with no base answers": (_THEN, {"files": [_PATCH], **_MERGED}, [], *_CLEAN, None, _TREES),
    "an evil merge": (_THEN, {"files": [_PATCH | {"patch": "+evil"}], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, _PATCH | {"patch": "+evil"}]), _based([_BASE_DOC]), None, _TREES),
    "a merge that adds a hold path": (_THEN, {"files": [_PATCH, _PATCH | {"filename": ".github/actions/resolve-config/c.mjs"}], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, _PATCH | {"filename": ".github/actions/resolve-config/c.mjs"}]), _based([_BASE_DOC]), None, _TREES),
    "a rename off a hold path": (_THEN, {"files": [_PATCH, _DOC | {"status": "renamed", "previous_filename": _HELD.replace("live", "old")}], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, _DOC | {"status": "renamed", "previous_filename": _HELD.replace("live", "old")}]), _based([_BASE_DOC]), None, _TREES),
    "a non-merge commit": (_THEN, {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]), (_HEAD, [_OLD]))}, _IN_BASE, *_CLEAN, None, _TREES),
    "a merge of another branch": (_THEN, {"files": [_PATCH], **_moved((_OLD, [_BASE_SHA]), (_OTHER, [_BASE_SHA]), (_HEAD, [_OLD, _OTHER]))}, _IN_BASE, *_CLEAN, None, _TREES),
    "a force push": (_THEN, {"files": [_PATCH], **_moved((_REWRITTEN, [_BASE_SHA]), (_HEAD, [_REWRITTEN, _BASE_SHA]))}, _IN_BASE, *_CLEAN, None, _TREES),
    "a cut commit list": (_THEN, {"files": [_PATCH], **_MERGED, "total_commits": 251}, _IN_BASE, *_CLEAN, None, _TREES),
    "a hold-path file with no patch": (_THEN, {"files": [{"filename": _HELD, "status": "modified"}], **_MERGED}, _IN_BASE, _brought([_BASE_DOC, {"filename": _HELD, "status": "modified"}]), _based([_BASE_DOC]), None, _TREES),
    # The owner's decision of 2026-10-28 (part b): the exact carry.
    "#10224's shape": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, _TREES),
    "#10224's shape, dismissed as stale on the merge's push": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, _HEAD, _TREES),
    "#10224's shape, dismissed by a commit the merges did not push": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, _OTHER, _TREES),
    "#10224's shape, dismissed at the approved head": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, _OLD, _TREES),
    "#10224's shape with no range read": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, None, None, None, _TREES),
    "a merge that also edits a hold path": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE, _PATCH | {"patch": "+evil"}]), _REPLAY_BASE, None, _TREES),
    "a merge that also edits a non-hold file": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE, _HELPER]), _REPLAY_BASE, None, _TREES),
    "a merge that changes the base's hunk": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE | {"patch": "+evil"}]), _REPLAY_BASE, None, _TREES),
    "a base change reverted inside the merge": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_SHARED_BASE]), _REPLAY_BASE, None, _TREES),
    "300 files brought": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought(_MANY), _based(_MANY), None, _TREES),
    "a base range of 300 files": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _based(_MANY), None, _TREES),
    "a brought commit list cut short": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE], total_commits=251), _REPLAY_BASE, None, _TREES),
    "a base range commit list cut short": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE | {"total_commits": 251}, None, _TREES),
    "a head range that is not ahead": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE], status="diverged", behind_by=1), _REPLAY_BASE, None, _TREES),
    "a base range that goes backwards": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE | {"status": "behind", "behind_by": 1}, None, _TREES),
    "a base range listed ahead and behind": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE | {"behind_by": 1}, None, _TREES),
    "a base range with no behind count": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), {k: v for k, v in _REPLAY_BASE.items() if k != "behind_by"}, None, _TREES),
    "a base that did not move": (_THEN, {"files": [_PATCH], **_MERGED}, _IN_BASE, _brought([]), {"status": "identical", "behind_by": 0, "files": [], "commits": [], "total_commits": 0}, None, _TREES),
    # The independent security review of #10671: the trees decide modes.
    "a merge that also flips a base file's mode": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, [_tree(*((p, "100755" if p == "docs/base.md" else "100644") for p in _PATHS)), _ALL]),
    "a brought file missing from the head's tree": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, [_tree(*((p, "100644") for p in _PATHS if p != "docs/base.md")), _ALL]),
    "a truncated tree": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, [_ALL, _ALL | {"truncated": True}]),
    "a tree with no truncated flag": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, [{"tree": _ALL["tree"]}, _ALL]),
    "a removed base file in neither tree": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE, _GONE]), _based([_BASE_DOC, _SHARED_BASE, _GONE]), None, _TREES),
    "a removed base file still in the head's tree": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE, _GONE]), _based([_BASE_DOC, _SHARED_BASE, _GONE]), None, [_tree(*((p, "100644") for p in [*_PATHS, "docs/gone.md"])), _ALL]),
    "no trees read": (_REPLAY_THEN, _REPLAY_NOW, _IN_BASE, _brought([_BASE_DOC, _SHARED_BASE]), _REPLAY_BASE, None, None),
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheCarriedLiftIsTheGates(unittest.TestCase):
    def test_both_readers_carry_the_same_lifts(self) -> None:
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                NODE_CARRY % json.dumps(MODULE.as_uri()),
            ],
            input=json.dumps(
                [list(LIFT_CASES.values()), list(CARRY_CASES.values()), _OLD]
            ),
            capture_output=True,
            text=True,
            check=True,
        )
        lifts, carries = json.loads(proc.stdout)
        for (name, (reviews, events)), js in zip(
            LIFT_CASES.items(), lifts, strict=True
        ):
            with self.subTest(name):
                self.assertEqual(
                    [
                        list(x)
                        for x in policy.lifts_of(
                            reviews, {1, 3}, policy.auto_dismissed(events)
                        )
                    ],
                    js,
                )
        for (name, (then, now, in_base, merges, based, dismissal, trees)), js in zip(
            CARRY_CASES.items(), carries, strict=True
        ):
            with self.subTest(name):
                self.assertEqual(
                    [
                        policy.base_merge_carry(then, now, _OLD, set(in_base)),
                        policy.approval_carry(
                            then,
                            now,
                            _OLD,
                            set(in_base),
                            merges,
                            based,
                            dismissal,
                            trees,
                            floor=FLOOR,
                        ),
                    ],
                    js,
                )
        # The rule's answers: a trusted person's newest review approves a
        # commit, or is an approval GitHub dismissed as stale (with its
        # dismissal commit); it carries over merges of base commits alone that
        # leave the whole net change the same (both carries), or that brought
        # exactly the base's changes (the approval carry alone), and a stale
        # dismissal must be by a commit the merges pushed.
        self.assertEqual(
            dict(zip(LIFT_CASES, lifts, strict=True)),
            dict.fromkeys(LIFT_CASES, [])
            | {
                "an approval of an earlier head": [["u1", _OLD, None]],
                "a comment after an approval": [["u1", _OLD, None]],
                "two people": [["u1", _OLD, None], ["u3", _HEAD, None]],
                "an approval GitHub dismissed as stale": [["u1", _OLD, _HEAD]],
                "a review id read as a string": [["u1", _OLD, _HEAD]],
            },
        )
        answers = dict(zip(CARRY_CASES, carries, strict=True))
        self.assertEqual(
            {name for name, (cost, _) in answers.items() if cost},
            {
                "a base merge",
                "a base merge with a non-hold file unchanged",
                "a base that did not move",
            },
        )
        self.assertEqual(
            {name for name, (_, approval) in answers.items() if approval},
            {
                "a base merge",
                "a base merge with a non-hold file unchanged",
                "a base that did not move",
                "#10224's shape",
                "#10224's shape, dismissed as stale on the merge's push",
                "a removed base file in neither tree",
            },
        )


if __name__ == "__main__":
    unittest.main()


# The owner's decision Q10 of 2026-10-28 ("go w/ recommendations"): an
# approval of H0 carries to H1 when the diff H0...H1 touches no hold path and
# no file a hold path loads. Each case: (changed files, configured hold paths,
# compare overrides).
NODE_Q10 = """
import { CARRY_REFUSES, ungatedSince } from %s;
let text = "";
for await (const chunk of process.stdin) text += chunk;
const cases = JSON.parse(text);
console.log(JSON.stringify([CARRY_REFUSES, cases.map(([merges, holdPaths]) => ungatedSince(merges, holdPaths))]));
"""
_H1 = "b" * 40


def _pushed(files: list[str], **extra: Any) -> dict[str, Any]:
    return {
        "status": "ahead",
        "behind_by": 0,
        "files": [{"filename": f, "status": "modified", "patch": "+x"} for f in files],
        "commits": [{"sha": _H1}],
        "total_commits": 1,
    } | extra


_SCRIPTS_DIR = "plugins/source-control/skills/babysit-prs/scripts"
Q10_CASES = {
    "a docs-only push": ([_pushed(["docs/a.md", "plugins/work-items/README.md"]), []], True),
    "a gated file": ([_pushed([".github/scripts/pr-merge/merge-holds.mjs"]), []], False),
    "a test-only edit beside a gated file": ([_pushed([".github/scripts/pr-merge/merge-holds.test.mjs"]), []], False),
    "a comment-only edit to a gated file": ([_pushed([f"{_SCRIPTS_DIR}/babysit_merge_policy.py"]), []], False),
    "a helper a gated file imports": ([_pushed([f"{_SCRIPTS_DIR}/babysit_util.py"]), []], False),
    "a helper babysit_postmerge.py imports": ([_pushed([f"{_SCRIPTS_DIR}/babysit_gh.py"]), []], False),
    "a script ci-status runs": ([_pushed(["scripts/check-stale-base-overlap.sh"]), []], False),
    "an action a hold-path workflow uses": ([_pushed([".github/actions/report-check-run/report-check-run.mjs"]), []], False),
    "a trusted-actor list edit": ([_pushed([".github/standards/trusted-actors/trusted-actors.json"]), []], False),
    "a configured hold path": ([_pushed(["docs/conventions/held.md"]), ["docs/conventions/**"]], False),
    "a rename off a gated file": ([_pushed(["docs/moved.md"]) | {"files": [{"filename": "docs/moved.md", "status": "renamed", "previous_filename": ".github/actions/request-lane-token/action.yml"}]}, []], False),
    "300 files": ([_pushed([f"docs/{i}.md" for i in range(300)]), []], False),
    "a cut commit list": ([_pushed(["docs/a.md"], total_commits=251), []], False),
    "a diverged head": ([_pushed(["docs/a.md"], status="diverged", behind_by=1), []], False),
    "an unread compare": ([None, []], False),
    "unread hold paths": ([_pushed(["docs/a.md"]), None], False),
}  # fmt: skip


@unittest.skipUnless(shutil.which("node"), "node not installed")
class TheUngatedCarryIsTheGates(unittest.TestCase):
    def test_both_carry_over_the_same_pushes(self) -> None:
        proc = subprocess.run(
            [
                "node",
                "--input-type=module",
                "-e",
                NODE_Q10 % json.dumps(MODULE.as_uri()),
            ],
            input=json.dumps([args for args, _ in Q10_CASES.values()]),
            capture_output=True,
            text=True,
            check=True,
        )
        refuses, answers = json.loads(proc.stdout)
        self.assertEqual(tuple(refuses), policy.CARRY_REFUSES)
        for (name, ((merges, hold_paths), expected)), js in zip(
            Q10_CASES.items(), answers, strict=True
        ):
            with self.subTest(name):
                self.assertEqual(js, expected)
                self.assertEqual(policy.ungated_since(merges, hold_paths, floor=FLOOR), expected)
                self.assertEqual(
                    policy.approval_carry(
                        None, None, _OLD, set(), merges, None, None, None, hold_paths, floor=FLOOR),
                    expected,
                )
        # A stale dismissal must be by a commit the push made.
        docs = _pushed(["docs/a.md"])
        self.assertTrue(
            policy.approval_carry(None, None, _OLD, set(), docs, None, _H1, None, [], floor=FLOOR)
        )
        self.assertFalse(
            policy.approval_carry(
                None, None, _OLD, set(), docs, None, "c" * 40, None, [], floor=FLOOR)
        )
        # No hold paths read: only the base-merge path decides.
        self.assertFalse(policy.approval_carry(None, None, _OLD, set(), docs, None, floor=FLOOR))


# Every local file a hold-path file loads: the floor entries' JS closure and
# the Python it runs, and each hold-path workflow's local actions (every
# file of the action) and the scripts its steps name, with their closures.
USES = re.compile(r"uses:\s*\./(?:\.base/)?(\.github/actions/[A-Za-z0-9_.-]+)")
# Any repository path to a script a workflow names, from the head checkout or
# `.base/`, whatever its directory: only a tracked file counts.
RUNS = re.compile(
    r"(?<![\w./-])(?:\./)?(?:\.base/)?((?:[A-Za-z0-9_-][A-Za-z0-9_.-]*/)+[A-Za-z0-9_.-]+\.(?:mjs|js|sh|bash|py))"
)


def tracked() -> set[str]:
    proc = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True, check=True
    )
    return set(proc.stdout.splitlines())


def loaded_closure() -> list[str]:
    workflows = sorted(
        g
        for g in FLOOR.all
        if g.startswith(".github/workflows/") and (ROOT / g).is_file()
    )
    files: set[str] = set(workflows)
    entries: set[str] = set(FLOOR_ENTRIES) | set(ROUTE_ENTRIES)
    in_git = tracked()
    for workflow in workflows:
        text = (ROOT / workflow).read_text(encoding="utf-8")
        for action in USES.findall(text):
            # The action's own files; its tests and fixtures run in CI, not
            # when a workflow uses it.
            for f in (ROOT / action).iterdir():
                if f.is_file() and ".test." not in f.name:
                    name = f.relative_to(ROOT).as_posix()
                    files.add(name)
                    if f.suffix == ".mjs":
                        entries.add(name)
        for script in RUNS.findall(text):
            if script in in_git:
                files.add(script)
                if script.endswith(".mjs"):
                    entries.add(script)
    # import_closure's walk, where a module that reads a whole directory
    # (`new URL("../../workflows/", import.meta.url)`) stands for a file in it.
    js: set[str] = set()
    todo = [ROOT / e for e in entries if e.endswith(".mjs")]
    while todo:
        file = todo.pop().resolve()
        # A spec that names no file beside the module (a repository-root
        # path in a string) loads nothing from here.
        if not file.exists():
            continue
        name = file.relative_to(ROOT).as_posix()
        if name in js:
            continue
        if file.is_dir():
            js.add(f"{name}/any.yml" if name != "." else "any.yml")
            continue
        js.add(name)
        todo.extend(
            file.parent / spec
            for spec in IMPORT.findall(file.read_text(encoding="utf-8"))
        )
    # The Python those modules and the workflows run, as python_closure
    # walks it, from the scripts that exist (a module's string can name an
    # example path).
    run = [
        ROOT / p
        for n in sorted(files | js)
        if n.endswith((".mjs", ".yml")) and (ROOT / n).is_file()
        for p in py_runs((ROOT / n).read_text(encoding="utf-8"))
        if (ROOT / p).is_file()
    ]
    py: set[str] = set()
    todo = [SCRIPTS / "babysit_risk.py", *run]
    while todo:
        file = todo.pop()
        name = file.relative_to(ROOT).as_posix()
        if name in py:
            continue
        py.add(name)
        for node in ast.walk(ast.parse(file.read_text(encoding="utf-8"))):
            names = (
                [a.name for a in node.names]
                if isinstance(node, ast.Import)
                else [node.module]
                if isinstance(node, ast.ImportFrom) and not node.level and node.module
                else []
            )
            todo.extend(
                file.parent / f"{n}.py"
                for n in names
                if (file.parent / f"{n}.py").is_file()
            )
    return sorted(files | js | py)


class TheCarryRefusesWhatHoldPathsLoad(unittest.TestCase):
    def test_every_file_a_hold_path_loads_stops_the_carry(self) -> None:
        files = loaded_closure()
        # The peer review's own example: babysit_postmerge.py's imports.
        for name in ("babysit_merge_policy.py", "babysit_gh.py", "babysit_util.py"):
            self.assertIn(f"{_SCRIPTS_DIR}/{name}", files)
        self.assertIn(".github/workflows/pr-require-checks.yml", files)
        for path in files:
            with self.subTest(path):
                self.assertTrue(
                    any(
                        risk.glob_match(g, path)
                        for g in (*FLOOR.all, *policy.CARRY_REFUSES)
                    ),
                    f"{path} is loaded by a hold path but neither held nor in CARRY_REFUSES",
                )
                self.assertFalse(policy.ungated_since(_pushed([path]), [], floor=FLOOR), path)

    def test_the_carry_reads_the_config_rows_from_its_floor(self) -> None:
        # The caller's hold paths are empty, and CARRY_REFUSES does not cover
        # this path: only `floor` holds a config row.
        path = "docs/standards/REVIEW.md"
        self.assertFalse(policy.ungated_since(_pushed([path]), [], floor=FLOOR))
        self.assertTrue(
            policy.ungated_since(_pushed([path]), [], floor=risk.floor_for())
        )
