#!/usr/bin/env python3
# test-scope: plugins/disk-hygiene/skills/clean/reference/baseline-policy.json plugins/disk-hygiene/lib/*.py
"""A synthetic home holding every home-root leftover class the baseline hints
name, and every neighbor that must stay, scanned end to end through the engine.

Each verdict below is the cleanup decision a careful manual pass reached on a
WSL2 home; the engine must reach the same one by itself.

REMOVED maps a home-root name to (the file or directory to create under it, or
None for the name itself; its content; the hint that must name it; that hint's
confidence ceiling). KEPT names entries no hint may name; a real dotfile keeps
its content. SCANDIR_CEILING is counted by hand from REMOVED, KEPT and the empty
tmp: one os.scandir per directory the walk enters, the target included, with no
directory cut.
"""

from __future__ import annotations

import os
import socket
import sys
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from typing import Any
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import hygiene  # noqa: E402  (path set above)
import hint_conditions  # noqa: E402  (lib path set by the engine import)

ZERO = ""
PLACEHOLDERS = {
    ".bash_aliases": "claude-sandbox-placeholder-bash-aliases",
    ".zshrc": "claude-sandbox-placeholder-zshrc",
    ".npmrc": "claude-sandbox-placeholder-npmrc",
    ".yarnrc": "claude-sandbox-placeholder-yarnrc",
    ".yarnrc.yml": "claude-sandbox-placeholder-yarnrc",
    ".bunfig.toml": "claude-sandbox-placeholder-bunfig",
    "bunfig.toml": "claude-sandbox-placeholder-bunfig",
    ".netrc": "claude-sandbox-placeholder-netrc",
    ".gitmodules": "claude-sandbox-placeholder-gitmodules",
    "package.json": "claude-sandbox-placeholder-package-json",
    "package-lock.json": "claude-sandbox-placeholder-package-lock-json",
    "yarn.lock": "claude-sandbox-placeholder-yarn-lock",
    "pnpm-lock.yaml": "claude-sandbox-placeholder-pnpm-lock-yaml",
    ".env": "claude-sandbox-placeholder-env",
    ".env.local": "claude-sandbox-placeholder-env-variant",
    ".env.development": "claude-sandbox-placeholder-env-variant",
    ".env.development.local": "claude-sandbox-placeholder-env-variant",
    ".env.test": "claude-sandbox-placeholder-env-variant",
    ".env.test.local": "claude-sandbox-placeholder-env-variant",
    ".env.production": "claude-sandbox-placeholder-env-variant",
    ".env.production.local": "claude-sandbox-placeholder-env-variant",
}

REMOVED: dict[str, tuple[str | None, str, str, str]] = {
    **{name: (None, ZERO, hint_id, "medium") for name, hint_id in PLACEHOLDERS.items()},
    "node_modules": (
        ".bin/",
        ZERO,
        "claude-sandbox-placeholder-node-modules",
        "medium",
    ),
    ".claude.json.tmp.4242.9bfba4e83eaa": (
        None,
        "{}",
        "claude-json-failed-atomic-write",
        "medium",
    ),
    ".claude.json.pre-onboarding.bak": (
        None,
        "{}",
        "claude-json-pre-onboarding-backup",
        "low",
    ),
    ".pytest_cache": ("v/cache/lastfailed", "{}", "pytest-cache", "medium"),
    ".ruff_cache": ("0.8.0/123", "x", "ruff-cache", "medium"),
    ".n": ("n/versions/node/20.0.0/bin/node", "x", "n-node-prefix", "low"),
    ".pip": ("selfcheck.json", "{}", "pip-legacy-config-dir", "medium"),
    ".biome": ("state", "x", "biome-legacy-home-dir", "low"),
    ".semgrep": ("semgrep.log", "x", "semgrep-user-data", "medium"),
    ".playwright-cli": ("page.yml", "x", "playwright-cli-output", "medium"),
    ".storybook": ("settings.json", "{}", "storybook-user-settings", "medium"),
    ".nv": ("ComputeCache/index", "x", "nvidia-cuda-compute-cache", "medium"),
    ".templateengine": (
        "dotnet/settings.json",
        "{}",
        "dotnet-template-engine-cache",
        "low",
    ),
    ".mcp-auth": ("mcp-remote-0.1.0/tokens.json", "{}", "mcp-remote-auth-store", "low"),
    ".motd_shown": (None, ZERO, "ubuntu-motd-shown-stamp", "medium"),
    ".landscape": ("sysinfo.log", "x", "ubuntu-landscape-sysinfo-log", "medium"),
    ".docker-link-swap.lock": (None, ZERO, "evals-legacy-docker-link-lock", "medium"),
}

KEPT: dict[str, tuple[str | None, str]] = {
    ".ev": ("run1/claude-eval-a/out", "x"),
    ".ev-legacy": ("claude-eval-b/out", "x"),
    ".ServiceHub": ("hub.log", "x"),
    ".work": ("notes.md", "x"),
    ".observability": ("events.jsonl", "x"),
    ".dcp": ("kubeconfig", "x"),
    ".hushlogin": (None, ZERO),
    **{
        name: (None, "# real config\n")
        for name in (
            ".bashrc",
            ".profile",
            ".bash_profile",
            ".bash_logout",
            ".zshenv",
            ".gitconfig",
            ".viminfo",
            ".wget-hsts",
            ".markdownlint-cli2.jsonc",
        )
    },
    ".claude.json": (None, '{"mcpServers": {}}'),
    ".cache": ("pip/http", "x"),
    ".npm": ("_cacache/index", "x"),
    ".nuget": ("packages/pkg", "x"),
    ".dotnet": ("sdk-telemetry", "x"),
    ".bun": ("install/cache", "x"),
    ".claude": ("settings.json", "{}"),
    ".config": ("git/config", "x"),
    ".local": ("share/data", "x"),
    ".vscode-server": ("data/x", "x"),
    ".cursor": ("mcp.json", '{"mcpServers": {}}'),
    ".docker": ("config.json", "{}"),
    ".gnupg": ("pubring.kbx", "x"),
    ".ssh": ("known_hosts", "x"),
}

SCANDIR_CEILING = 56


def build(home: Path, spec: dict[str, tuple[Any, ...]]) -> None:
    for name, (inner, content, *_) in spec.items():
        path = home / name
        if inner is None:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        elif inner.endswith("/"):
            (path / inner).mkdir(parents=True)
        else:
            (path / inner).parent.mkdir(parents=True, exist_ok=True)
            (path / inner).write_text(content, encoding="utf-8")


def hint_ids(entry: dict[str, Any]) -> set[str]:
    return {hint["id"] for hint in entry["hints"]}


@unittest.skipUnless(
    sys.platform.startswith("linux"), "the fixture's verdicts are the Linux/WSL2 ones"
)
class HomeLeftoverCatalogTest(unittest.TestCase):
    def setUp(self) -> None:
        stack = ExitStack()
        self.addCleanup(stack.close)
        temporary = stack.enter_context(tempfile.TemporaryDirectory())
        self.base = Path(temporary)
        self.home = self.base / "home"
        self.home.mkdir()
        stack.enter_context(mock.patch.dict(os.environ, {"HOME": str(self.home)}))
        stack.enter_context(
            mock.patch.object(hygiene, "standing_policy_paths", return_value=[])
        )
        self.stack = stack

    def scan(self, policy: dict[str, Any] | None = None) -> dict[str, Any]:
        return hygiene.scan_tree(
            self.home.resolve(), policy or hygiene.load_policy(None)
        )

    def build_today(self) -> None:
        build(self.home, REMOVED)
        build(self.home, KEPT)
        (self.home / "tmp").mkdir()

    def test_every_removed_item_is_a_candidate_and_every_kept_item_is_not(self) -> None:
        self.build_today()
        entries = hygiene.entry_map(self.scan())
        verdicts = []
        for name, (_, _, hint_id, ceiling) in REMOVED.items():
            matched = {h["id"]: h["confidence_ceiling"] for h in entries[name]["hints"]}
            got = (
                f"candidate {hint_id}@{matched[hint_id]}"
                if hint_id in matched
                else "not a candidate"
            )
            verdicts.append((name, f"candidate {hint_id}@{ceiling}", got))
        for name in KEPT:
            got = (
                "not a candidate"
                if not entries[name]["hints"]
                else f"candidate {sorted(hint_ids(entries[name]))}"
            )
            verdicts.append((name, "not a candidate", got))
        self.assertEqual([(name, want, want) for name, want, _ in verdicts], verdicts)

    def test_no_rule_preselects_a_baseline_hint(self) -> None:
        self.build_today()
        for entry in self.scan()["entries"]:
            self.assertNotIn("preselected", entry, entry["path"])

    def test_kept_contents_stay_unhinted_below_the_home_root(self) -> None:
        self.build_today()
        hinted = {
            entry["path"]
            for entry in self.scan()["entries"]
            if entry["hints"] and entry["path"].split("/", 1)[0] in KEPT
        }
        self.assertEqual(set(), hinted)

    def test_empty_directories_stay_visible(self) -> None:
        self.build_today()
        snapshot = self.scan()
        self.assertEqual(
            ["node_modules/.bin", "tmp"], snapshot["empty_directory_paths"]
        )
        self.assertEqual([], hygiene.entry_map(snapshot)["tmp"]["hints"])

    def test_a_real_dotfile_records_why_the_placeholder_hint_left_it(self) -> None:
        self.build_today()
        entry = hygiene.entry_map(self.scan())[".bashrc"]
        self.assertEqual(
            [
                {
                    "hint_id": "claude-sandbox-placeholder-bashrc",
                    "detail": "zero_bytes: file holds bytes",
                }
            ],
            entry["unmet_hint_conditions"],
        )

    def test_each_condition_keeps_the_real_neighbor(self) -> None:
        build(
            self.home,
            {
                ".npmrc": (None, "registry=https://registry.npmjs.org/\n"),
                ".env": (None, "KEY=value\n"),
                "node_modules": ("left-pad/index.js", "module.exports = 1\n"),
                ".storybook": ("main.ts", "export default {}\n"),
                ".pip": ("pip.conf", "[global]\n"),
                ".semgrep": ("settings.yml", "api_token: redacted\n"),
                ".mcp-auth": ("mcp-remote-0.1.0/tokens.json", "{}"),
                ".claude.json": (
                    None,
                    '{"mcpServers": {"x": {"command": "npx", "args": ["mcp-remote"]}}}',
                ),
                ".docker-link-swap.lock": (None, ZERO),
                ".docker-link-swap.json": (None, '{"links": [], "holders": []}'),
            },
        )
        entries = hygiene.entry_map(self.scan())
        expected = {
            ".npmrc": (
                "claude-sandbox-placeholder-npmrc",
                "zero_bytes: file holds bytes",
            ),
            ".env": ("claude-sandbox-placeholder-env", "zero_bytes: file holds bytes"),
            "node_modules": (
                "claude-sandbox-placeholder-node-modules",
                "zero_bytes: directory tree holds a file or an unwalked path",
            ),
            ".storybook": (
                "storybook-user-settings",
                "absent_children: main.ts is present",
            ),
            ".pip": ("pip-legacy-config-dir", "absent_children: pip.conf is present"),
            ".semgrep": (
                "semgrep-user-data",
                "absent_children: settings.yml is present",
            ),
            ".mcp-auth": (
                "mcp-remote-auth-store",
                "unreferenced: ~/.claude.json names mcp-remote",
            ),
            ".docker-link-swap.lock": (
                "evals-legacy-docker-link-lock",
                "absent_siblings: .docker-link-swap.json is present",
            ),
        }
        for name, (hint_id, detail) in expected.items():
            self.assertNotIn(hint_id, hint_ids(entries[name]), name)
            self.assertIn(
                {"hint_id": hint_id, "detail": detail},
                entries[name]["unmet_hint_conditions"],
                name,
            )
        self.assertEqual(
            {"common-lock-file"}, hint_ids(entries[".docker-link-swap.lock"])
        )
        self.assertEqual(set(), hint_ids(entries[".docker-link-swap.json"]))

    def test_an_unreadable_mcp_config_keeps_the_token_store(self) -> None:
        if hasattr(os, "geteuid") and os.geteuid() == 0:
            self.skipTest("root reads a mode-000 file")
        build(
            self.home,
            {".mcp-auth": ("tokens.json", "{}"), ".cursor": ("mcp.json", "{}")},
        )
        config = self.home / ".cursor" / "mcp.json"
        config.chmod(0)
        self.addCleanup(config.chmod, 0o600)
        entry = hygiene.entry_map(self.scan())[".mcp-auth"]
        self.assertEqual(set(), hint_ids(entry))
        self.assertEqual(
            [
                {
                    "hint_id": "mcp-remote-auth-store",
                    "detail": "unreferenced: cannot read ~/.cursor/mcp.json",
                }
            ],
            entry["unmet_hint_conditions"],
        )

    def test_a_live_socket_blocks_the_service_hub_preview(self) -> None:
        build(self.home, {".ServiceHub": ("hub.log", "x")})
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(server.close)
        server.bind(str(self.home / ".ServiceHub" / "hub.sock"))
        server.listen(1)
        snapshot = self.scan()
        self.assertEqual([], hygiene.entry_map(snapshot)[".ServiceHub"]["hints"])
        plan = {
            "version": 1,
            "tier": "low",
            "candidates": [
                {
                    "path": ".ServiceHub",
                    "tier": "low",
                    "provenance": "operator asked to remove it",
                    "reason": "C# Dev Kit service hub state",
                    "evidence": ["operator request"],
                    "why_not_work_product": "service state",
                    "risk": "a running host loses its pipes",
                    "owner": "unmanaged",
                }
            ],
        }
        result = hygiene.preview(snapshot, plan)
        self.assertEqual("blocked", result["status"])
        self.assertIsNone(result["approval_token"])
        self.assertTrue(
            {"live-handle", "handle-state-unverified"}
            & set(result["candidates"][0]["blockers"]),
            result["candidates"][0]["blockers"],
        )

    def test_scan_enters_each_directory_once_and_conditions_list_none(self) -> None:
        self.build_today()
        real = os.scandir
        calls: list[str] = []

        def counting(path: Any = ".") -> Any:
            calls.append(os.fspath(path))
            return real(path)

        policy = hygiene.load_policy(None)
        with mock.patch.object(hygiene.os, "scandir", counting):
            self.scan(policy)
        with_conditions = len(calls)
        calls.clear()
        unconditioned = {
            **policy,
            "hints": [
                {k: v for k, v in h.items() if k != "requires"} for h in policy["hints"]
            ],
        }
        with mock.patch.object(hygiene.os, "scandir", counting):
            self.scan(unconditioned)
        self.assertEqual(SCANDIR_CEILING, with_conditions)
        self.assertEqual(with_conditions, len(calls))


class WindowsPathPatternTest(unittest.TestCase):
    """The Windows variants, matched by pattern because the scan runs on Linux."""

    def matched(self, relative: str, kind: str, os_name: str) -> set[str]:
        policy = hygiene.load_policy(None)
        with mock.patch.object(hygiene, "os_key", return_value=os_name):
            name = relative.rsplit("/", 1)[-1]
            return {
                h["id"] for h in hygiene.matching_hints(relative, name, policy, kind)
            }

    def test_cross_platform_hints_match_under_the_windows_profile(self) -> None:
        for relative, kind, hint_id in (
            (
                ".claude.json.tmp.9552.9bfba4e83eaa",
                "file",
                "claude-json-failed-atomic-write",
            ),
            (
                ".claude.json.pre-onboarding.bak",
                "file",
                "claude-json-pre-onboarding-backup",
            ),
            (".pytest_cache", "directory", "pytest-cache"),
            (".ruff_cache", "directory", "ruff-cache"),
            (".playwright-cli", "directory", "playwright-cli-output"),
            (".templateengine", "directory", "dotnet-template-engine-cache"),
            (".mcp-auth", "directory", "mcp-remote-auth-store"),
            (".semgrep", "directory", "semgrep-user-data"),
            (".storybook", "directory", "storybook-user-settings"),
            (
                "AppData/Roaming/NVIDIA/ComputeCache",
                "directory",
                "nvidia-cuda-compute-cache-windows",
            ),
        ):
            self.assertIn(hint_id, self.matched(relative, kind, "windows"), relative)

    def test_linux_only_hints_stay_off_windows(self) -> None:
        for relative, kind in (
            (".npmrc", "file"),
            ("node_modules", "directory"),
            (".n", "directory"),
            (".pip", "directory"),
            (".nv", "directory"),
            (".motd_shown", "file"),
            (".landscape", "directory"),
            (".docker-link-swap.lock", "file"),
        ):
            self.assertEqual(
                set(),
                self.matched(relative, kind, "windows") - {"common-lock-file"},
                relative,
            )
            self.assertNotEqual(set(), self.matched(relative, kind, "linux"), relative)

    def test_the_cuda_cache_hint_names_only_its_profile_path(self) -> None:
        self.assertNotIn(
            "nvidia-cuda-compute-cache-windows",
            self.matched("AppData/Roaming/NVIDIA", "directory", "windows"),
        )


class RequiresValidationTest(unittest.TestCase):
    def test_malformed_requirements_are_rejected(self) -> None:
        for requires, message in (
            ({}, "non-empty object"),
            ({"zero_bytes": False}, "zero_bytes must be true"),
            ({"min_bytes": 1}, "unknown hint requirement"),
            ({"absent_siblings": ["a/b"]}, "bare names"),
            ({"absent_children": []}, "non-empty array"),
            (
                {"unreferenced": {"text": "x", "home_files": ["/etc/passwd"]}},
                "must be relative",
            ),
            (
                {"unreferenced": {"text": "x", "home_files": ["../x"]}},
                "must be relative",
            ),
            ({"unreferenced": {"text": "", "home_files": ["x"]}}, "text must be"),
            ({"unreferenced": {"text": "x"}}, "exactly text and home_files"),
        ):
            with self.assertRaisesRegex(hint_conditions.ConditionError, message):
                hint_conditions.validate_requires(requires)

    def test_an_overlay_hint_with_a_bad_requirement_fails_to_load(self) -> None:
        hint = {
            "id": "h",
            "os": ["all"],
            "kind": "name_glob",
            "pattern": "*.x",
            "confidence_ceiling": "low",
            "reason": "fixture",
        }
        hygiene.validate_hint({**hint, "requires": {"zero_bytes": True}})
        with self.assertRaisesRegex(hygiene.HygieneError, "unknown hint requirement"):
            hygiene.validate_hint({**hint, "requires": {"maybe": True}})


if __name__ == "__main__":
    unittest.main()
