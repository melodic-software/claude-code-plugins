#!/usr/bin/env python3
"""Tests for the bundled managed-state owner registry."""

from __future__ import annotations

import ast
import fnmatch
import importlib.util
import inspect
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from contextlib import ExitStack, redirect_stdout
from pathlib import Path, PurePosixPath
from typing import Any
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent
ENGINE_PATH = SCRIPTS / "hygiene.py"
_spec = importlib.util.spec_from_file_location("hygiene", ENGINE_PATH)
assert _spec and _spec.loader
hygiene = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hygiene)

REFERENCE = Path(__file__).resolve().parents[1] / "reference"
REGISTRY = json.loads((REFERENCE / "owner-registry.json").read_text(encoding="utf-8"))
SCHEMA = json.loads(
    (REFERENCE / "owner-registry.schema.json").read_text(encoding="utf-8")
)
POLICY = json.loads((REFERENCE / "baseline-policy.json").read_text(encoding="utf-8"))

EXPECTED_IDS = {
    "docker-desktop",
    "nvidia-shader-cache",
    "cursor",
    "openai-codex-cli",
    "chezmoi",
    "pulumi",
}
JSON_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "null": type(None),
}


def validate(value: Any, schema: dict[str, Any], where: str = "$") -> list[str]:
    """Check the JSON Schema keywords the registry schema uses; return errors."""
    errors: list[str] = []
    if "const" in schema and value != schema["const"]:
        errors.append(f"{where}: expected {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: {value!r} not in {schema['enum']}")
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(isinstance(value, JSON_TYPES[name]) for name in names):
            return [*errors, f"{where}: expected type {names}"]
    if isinstance(value, str) and len(value) < schema.get("minLength", 0):
        errors.append(f"{where}: shorter than {schema['minLength']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{where}: fewer than {schema['minItems']} items")
        if schema.get("uniqueItems") and len({json.dumps(v) for v in value}) != len(
            value
        ):
            errors.append(f"{where}: items not unique")
        for index, item in enumerate(value):
            errors += validate(item, schema.get("items", {}), f"{where}[{index}]")
    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            errors.append(f"{where}: fewer than {schema['minProperties']} properties")
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{where}: missing {key!r}")
        properties = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if "propertyNames" in schema:
                errors += validate(key, schema["propertyNames"], f"{where}.<{key}>")
            if key in properties:
                errors += validate(item, properties[key], f"{where}.{key}")
            elif extra is False:
                errors.append(f"{where}: unexpected {key!r}")
            elif isinstance(extra, dict):
                errors += validate(item, extra, f"{where}.{key}")
    return errors


def pattern_segments(entry: dict[str, Any]) -> list[str]:
    return [
        segment
        for patterns in entry["path_patterns"].values()
        for pattern in patterns
        for segment in pattern.replace("\\", "/").split("/")
    ]


class OwnerRegistryTest(unittest.TestCase):
    def test_registry_validates_against_schema(self) -> None:
        self.assertEqual(validate(REGISTRY, SCHEMA), [])

    def test_validator_rejects_a_malformed_entry(self) -> None:
        bad = json.loads(json.dumps(REGISTRY))
        del bad["entries"][0]["tool"]
        bad["entries"][1]["platforms"] = ["beos"]
        self.assertEqual(len(validate(bad, SCHEMA)), 2)

    def test_seeds_the_six_owners(self) -> None:
        ids = [entry["id"] for entry in REGISTRY["entries"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), EXPECTED_IDS)

    def test_note_states_hint_is_not_authorization(self) -> None:
        self.assertIn("never authorization", REGISTRY["note"])

    def test_path_patterns_cover_only_declared_platforms(self) -> None:
        for entry in REGISTRY["entries"]:
            self.assertLessEqual(
                set(entry["path_patterns"]), set(entry["platforms"]), entry["id"]
            )

    def test_no_path_pattern_touches_a_protected_name(self) -> None:
        exact = {name.casefold() for name in POLICY["protected_exact_names"]}
        globs = POLICY["protected_name_globs"]
        for entry in REGISTRY["entries"]:
            for segment in pattern_segments(entry):
                self.assertNotIn(segment.casefold(), exact, entry["id"])
                for glob in globs:
                    self.assertFalse(fnmatch.fnmatchcase(segment, glob), entry["id"])


REGISTRY_TOOLS = {entry["tool"] for entry in REGISTRY["entries"]}
REGISTRY_FRAGMENTS = (
    "owner-registry",
    "owner_registry",
    "destructive_native_command",
    "read_only_command",
)
NATIVE_EVIDENCE = {"command": "fixture-manager prune --dry-run", "result": "eligible"}


def registry_matches() -> list[tuple[str, str]]:
    """Every registry path pattern with the id of the entry that owns it."""
    return sorted(
        {
            (pattern, entry["id"])
            for entry in REGISTRY["entries"]
            for patterns in entry["path_patterns"].values()
            for pattern in patterns
        }
    )


def plan_for(path: str, owner: str = "unmanaged", tier: str = "high") -> dict[str, Any]:
    item: dict[str, Any] = {
        "path": path,
        "tier": tier,
        "provenance": "fixture convention documents this as abandoned staging",
        "reason": "fixture provenance identifies an abandoned temporary",
        "evidence": ["name matches fixture convention", "owner process is absent"],
        "why_not_work_product": "fixture content is generated and has no consumer",
        "risk": "low: fixture residue with no live consumer",
        "owner": owner,
    }
    if owner != "unmanaged":
        item["native_gc_evidence"] = NATIVE_EVIDENCE
    return {"version": 1, "tier": tier, "candidates": [item]}


class RegistryGrantsNoApprovalTest(unittest.TestCase):
    """A registry match changes nothing about what the engine may delete."""

    def setUp(self) -> None:
        stack = ExitStack()
        self.addCleanup(stack.close)
        for name, value in (
            ("standing_policy_paths", []),
            ("execution_blockers", []),
            ("handle_state", ("clear", None)),
            ("tracked_blocker", None),
        ):
            stack.enter_context(mock.patch.object(hygiene, name, return_value=value))
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.home = self.base / "home"
        # Each registry path gets a control: same parent, same content shape,
        # a name no registry entry mentions.
        self.controls: dict[str, str] = {}
        for index, (path, _) in enumerate(registry_matches()):
            control = str(PurePosixPath(path).parent / f"control-{index}")
            self.controls[path] = control
            for relative in (path, control):
                directory = self.home.joinpath(*PurePosixPath(relative).parts)
                directory.mkdir(parents=True)
                (directory / "state.dat").write_text("state", encoding="utf-8")
        self.snapshot = hygiene.scan_tree(
            self.home.resolve(), hygiene.load_policy(None)
        )

    def run_apply(self, plan: dict[str, Any], *flags: str) -> tuple[int, str]:
        snapshot_path = self.base / "snapshot.json"
        plan_path = self.base / "plan.json"
        snapshot_path.write_text(json.dumps(self.snapshot), encoding="utf-8")
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        output = io.StringIO()
        with (
            mock.patch.object(hygiene, "apply_plan") as apply_plan,
            redirect_stdout(output),
        ):
            code = hygiene.main(
                [
                    "apply",
                    "--snapshot",
                    str(snapshot_path),
                    "--plan",
                    str(plan_path),
                    "--report",
                    str(self.base / "report.json"),
                    *flags,
                ]
            )
        apply_plan.assert_not_called()
        return code, output.getvalue()

    def test_registry_paths_are_classified_like_neutral_paths(self) -> None:
        entries = hygiene.entry_map(self.snapshot)
        for path, control in self.controls.items():
            for suffix in ("", "/state.dat"):
                seen, expected = entries[path + suffix], entries[control + suffix]
                for field in ("hints", "protected_reasons"):
                    self.assertEqual(expected[field], seen[field], path + suffix)

    def test_preview_gives_a_registry_path_the_verdict_a_neutral_path_gets(
        self,
    ) -> None:
        for path, control in self.controls.items():
            seen = hygiene.preview(self.snapshot, plan_for(path))
            expected = hygiene.preview(self.snapshot, plan_for(control))
            for field in ("status", "outcome"):
                self.assertEqual(expected[field], seen[field], path)
            self.assertEqual(
                expected["candidates"][0]["blockers"],
                seen["candidates"][0]["blockers"],
                path,
            )
            self.assertEqual(
                expected["approval_token"] is None, seen["approval_token"] is None
            )

    def test_a_plan_claiming_the_registry_owner_stays_report_only(self) -> None:
        for path, owner in registry_matches():
            result = hygiene.preview(self.snapshot, plan_for(path, owner))
            self.assertIn(
                "native-managed-report-only", result["candidates"][0]["blockers"]
            )
            self.assertEqual("blocked", result["status"], path)
            self.assertIsNone(result["approval_token"], path)

    def test_token_is_a_function_of_snapshot_and_plan_alone(self) -> None:
        self.assertEqual(
            ["snapshot", "plan"],
            list(inspect.signature(hygiene.approval_token).parameters),
        )
        path = registry_matches()[0][0]
        plan = plan_for(path)
        token = hygiene.preview(self.snapshot, plan)["approval_token"]
        self.assertEqual(hygiene.approval_token(self.snapshot, plan), token)
        self.assertNotEqual(
            token, hygiene.approval_token(self.snapshot, plan_for(path, tier="medium"))
        )

    def test_the_plan_list_is_bound_to_the_snapshot_not_the_registry(self) -> None:
        path = registry_matches()[0][0]
        self.snapshot["entries"] = [
            entry for entry in self.snapshot["entries"] if entry["path"] != path
        ]
        with self.assertRaises(hygiene.HygieneError):
            hygiene.preview(self.snapshot, plan_for(path))

    def test_apply_refuses_without_execute_a_matching_tier_and_a_fresh_token(
        self,
    ) -> None:
        path = registry_matches()[0][0]
        plan = plan_for(path)
        fresh = hygiene.preview(self.snapshot, plan)["approval_token"]
        for flags, message in (
            (("--confirm-tier", "high", "--approval-token", fresh), "--execute"),
            (
                ("--execute", "--confirm-tier", "medium", "--approval-token", fresh),
                "confirm-tier",
            ),
            (
                ("--execute", "--confirm-tier", "high", "--approval-token", "0" * 24),
                "approval token",
            ),
        ):
            code, output = self.run_apply(plan, *flags)
            self.assertEqual(2, code, flags)
            self.assertIn(message, output)
            self.assertTrue(self.home.joinpath(*PurePosixPath(path).parts).exists())

    def test_engine_reads_no_registry_file_and_runs_no_registry_tool(self) -> None:
        real_read_text = Path.read_text
        reads: list[str] = []

        def spy(self: Path, *args: Any, **kwargs: Any) -> str:
            reads.append(self.name)
            return real_read_text(self, *args, **kwargs)

        with (
            mock.patch.object(Path, "read_text", spy),
            mock.patch.object(hygiene.subprocess, "run", wraps=subprocess.run) as run,
            mock.patch.object(
                hygiene.subprocess, "Popen", wraps=subprocess.Popen
            ) as popen,
        ):
            snapshot = hygiene.scan_tree(self.home.resolve(), hygiene.load_policy(None))
            for path, owner in registry_matches():
                hygiene.preview(snapshot, plan_for(path))
                hygiene.preview(snapshot, plan_for(path, owner))
        self.assertIn("baseline-policy.json", reads)
        self.assertNotIn("owner-registry.json", reads)
        for call in (*run.call_args_list, *popen.call_args_list):
            argv = call.args[0] if call.args else call.kwargs.get("args", [])
            argv = [argv] if isinstance(argv, str) else list(argv)
            self.assertNotIn(Path(str(argv[0])).name if argv else "", REGISTRY_TOOLS)


PLUGIN = Path(__file__).resolve().parents[3]
TELEMETRY_PATH = PLUGIN / "lib" / "hook_telemetry.py"
EXECUTORS = {ENGINE_PATH, TELEMETRY_PATH}
# The engine's apply lane: the only code that may delete or name a registry command.
APPLY_LANE = {"apply_plan", "anchored_remove"}
FENCED = ("apply_plan", "anchored_remove")
CODE_SUFFIXES = {".py", ".sh", ".mjs", ".js", ".ps1"}
DELETIONS = {"unlink", "rmdir", "rmtree", "removedirs"}
RUNNERS = (
    "subprocess",
    "os.system",
    "os.popen",
    "os.exec",
    "os.spawn",
    "os.posix_spawn",
    "pty.spawn",
    "asyncio.create_subprocess",
)
REGISTRY_COMMANDS = tuple(
    part.strip()
    for entry in REGISTRY["entries"]
    for command in (entry["read_only_command"], entry["destructive_native_command"])
    for part in (command or "").split(";")
    if part.strip()
)
SHIPPED = sorted(
    path
    for path in PLUGIN.rglob("*")
    if path.suffix in CODE_SUFFIXES
    and "__pycache__" not in path.parts
    and not path.name.startswith("test_")
    and ".test." not in path.name
)


def without_apply_lane(tree: ast.Module) -> ast.Module:
    keep = [
        node
        for node in tree.body
        if not (isinstance(node, ast.FunctionDef) and node.name in APPLY_LANE)
    ]
    return ast.Module(body=keep, type_ignores=[])


def uses(tree: ast.AST) -> set[str]:
    """Dotted names a module imports or calls."""
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            names.update(f"{node.module}.{alias.name}" for alias in node.names)
        elif isinstance(node, ast.Call):
            names.add(ast.unparse(node.func))
    return names


def violations(path: Path, source: str) -> list[str]:
    """What a shipped file does that only the engine's apply lane may do.

    Deleting, running a registry command, naming the registry, and reaching the
    apply lane without the CLI's gates are all found by name. Outside the engine
    a process runner is also a violation.
    """
    text, found = source, set()
    if path.suffix == ".py":
        tree = ast.parse(source)
        if path == ENGINE_PATH:
            tree = without_apply_lane(tree)
        text, found = ast.unparse(tree), uses(tree)
    hits = {
        name
        for name in found
        if name == "os.remove" or name.rpartition(".")[2] in DELETIONS
    }
    if path not in EXECUTORS:
        hits |= {name for name in found if name.startswith(RUNNERS)}
    hits |= {name for name in (*REGISTRY_FRAGMENTS, *REGISTRY_COMMANDS) if name in text}
    if path != ENGINE_PATH:
        hits |= {name for name in FENCED if name in text}
    return sorted(hits)


class OnlyTheApplyLaneDestroysTest(unittest.TestCase):
    """Any destructive path is the engine's: its tier, exact-list and token gates.

    The scan is static. It reads every shipped file, test files excepted; a
    non-Python file is checked by name only. It cannot see `getattr`, `eval`,
    `importlib` or a command assembled at run time. Widening what a file may do
    is an edit to the constants above, in review.
    """

    def test_no_shipped_file_deletes_names_the_registry_or_reaches_the_apply_lane(
        self,
    ) -> None:
        self.assertLessEqual({ENGINE_PATH, TELEMETRY_PATH}, set(SHIPPED))
        for path in SHIPPED:
            self.assertEqual(
                [],
                violations(path, path.read_text(encoding="utf-8")),
                str(path.relative_to(PLUGIN)),
            )

    def test_a_parallel_path_is_flagged(self) -> None:
        elsewhere = SCRIPTS / "parallel.py"
        for source in (
            "import subprocess\nsubprocess.run(entry['destructive_native_command'])\n",
            "import subprocess as sp\nsp.run(['pulumi'])\n",
            "from os import unlink\nunlink(path)\n",
            "import shutil\nshutil.rmtree(path)\n",
            "import hygiene\nhygiene.apply_plan(snapshot, plan)\n",
        ):
            self.assertNotEqual([], violations(elsewhere, source), source)
        for source in (
            "jq -r '.entries[].destructive_native_command' owner-registry.json | sh\n",
            "docker image prune --force\n",
        ):
            self.assertNotEqual([], violations(SCRIPTS / "parallel.sh", source), source)

    def test_the_apply_lane_and_the_telemetry_emitter_are_not(self) -> None:
        lane = (
            "def apply_plan(snapshot, plan):\n"
            "    subprocess.run(entry['destructive_native_command'])\n"
            "    anchored_remove(fd, name)\n"
            "    os.unlink(name)\n"
        )
        self.assertEqual([], violations(ENGINE_PATH, lane))
        self.assertNotEqual(
            [], violations(ENGINE_PATH, lane.replace("apply_plan", "preview"))
        )
        self.assertEqual(
            [],
            violations(TELEMETRY_PATH, "import subprocess\nsubprocess.Popen(['x'])\n"),
        )


class EngineSourceTest(unittest.TestCase):
    tree = ast.parse(ENGINE_PATH.read_text(encoding="utf-8"))

    def references(self, name: str) -> int:
        return sum(
            isinstance(node, ast.Name) and node.id == name
            for node in ast.walk(self.tree)
        )

    def callers(self, name: str) -> list[str]:
        return [
            function.name
            for function in ast.walk(self.tree)
            if isinstance(function, ast.FunctionDef)
            for node in ast.walk(function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == name
        ]

    def test_apply_plan_has_exactly_one_caller_and_it_is_the_cli_apply_lane(
        self,
    ) -> None:
        self.assertEqual(1, self.references("apply_plan"))
        self.assertEqual(["main"], self.callers("apply_plan"))

    def test_the_only_removal_is_reached_from_apply_plan(self) -> None:
        self.assertEqual(1, self.references("anchored_remove"))
        self.assertEqual(["apply_plan"], self.callers("anchored_remove"))


class BaselinePolicyUnchangedTest(unittest.TestCase):
    def test_baseline_policy_loads_identically_without_the_registry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "baseline-policy.json"
            shutil.copyfile(REFERENCE / "baseline-policy.json", bundle)
            with mock.patch.object(hygiene, "standing_policy_paths", return_value=[]):
                with_registry = hygiene.load_policy(None)
                with mock.patch.object(hygiene, "BASELINE_POLICY", bundle):
                    without_registry = hygiene.load_policy(None)
        self.assertEqual(without_registry, with_registry)
        self.assertEqual(["baseline"], with_registry["policy_sources"])
        for key in ("protected_exact_names", "protected_name_globs", "hints"):
            self.assertEqual(POLICY[key], with_registry[key], key)


if __name__ == "__main__":
    unittest.main()
