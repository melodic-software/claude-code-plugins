#!/usr/bin/env python3
"""Unit tests for ``lib/install_authority.py`` and ``killswitch_config.probe_effective``."""

from __future__ import annotations

import ast
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

LIB_DIR = Path(__file__).resolve().parent
PLUGIN_ROOT = LIB_DIR.parent
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

import install_authority  # noqa: E402
import killswitch_config  # noqa: E402


class InstallAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def test_cache_layout_derives_data_root_settings_and_plugin_id(self) -> None:
        plugin_root = (
            self.base
            / "plugins"
            / "cache"
            / "melodic-software"
            / "disk-hygiene"
            / "1.2.3"
        )
        plugin_root.mkdir(parents=True)
        auth = install_authority.resolve_install_authority(
            plugin_root=str(plugin_root),
            config_dir=None,
        )
        self.assertEqual(
            str(self.base / "plugins" / "data" / "disk-hygiene-melodic-software"),
            auth.data_root,
        )
        self.assertEqual(install_authority.DATA_ROOT_CHANNEL_CACHE, auth.channel)
        self.assertEqual(self.base / "settings.json", auth.user_settings_path)
        self.assertEqual("disk-hygiene@melodic-software", auth.plugin_id)

    def test_direct_authorized_data_root_outranks_cache_layout(self) -> None:
        plugin_root = (
            self.base / "plugins" / "cache" / "acme" / "disk-hygiene" / "0.1.0"
        )
        plugin_root.mkdir(parents=True)
        direct = self.base / "direct-data"
        auth = install_authority.resolve_install_authority(
            plugin_root=str(plugin_root),
            authorized_data_root=str(direct),
            config_dir=None,
        )
        self.assertEqual(str(direct), auth.data_root)
        self.assertEqual(install_authority.DATA_ROOT_CHANNEL_DIRECT, auth.channel)
        self.assertEqual(self.base / "settings.json", auth.user_settings_path)
        self.assertEqual("disk-hygiene@acme", auth.plugin_id)

    def test_placeholders_and_env_vars_are_never_trusted(self) -> None:
        checkout = self.base / "checkout"
        checkout.mkdir()
        with mock.patch.dict(
            os.environ,
            {
                "CLAUDE_PLUGIN_DATA": str(self.base / "env-data"),
                "CLAUDE_CONFIG_DIR": str(self.base / "env-config"),
                "HOME": str(self.base / "env-home"),
                "USERPROFILE": str(self.base / "env-home"),
            },
            clear=False,
        ):
            auth = install_authority.resolve_install_authority(
                plugin_root="${CLAUDE_PLUGIN_ROOT}",
                authorized_data_root="${CLAUDE_PLUGIN_DATA}",
                config_dir=None,
            )
            self.assertIsNone(auth.data_root)
            self.assertIsNone(auth.channel)
            self.assertIsNone(auth.user_settings_path)
            self.assertIsNone(auth.plugin_id)

            auth2 = install_authority.resolve_install_authority(
                plugin_root=str(checkout),
                config_dir=None,
            )
            self.assertIsNone(auth2.data_root)

    def test_directory_marketplace_install_proves_data_root_and_settings(self) -> None:
        config_dir = self.base / "config"
        marketplace_root = self.base / "repo"
        plugin_root = marketplace_root / "plugins" / "disk-hygiene"
        (config_dir / "plugins").mkdir(parents=True)
        (marketplace_root / ".claude-plugin").mkdir(parents=True)
        (plugin_root / ".claude-plugin").mkdir(parents=True)

        (config_dir / "plugins" / "known_marketplaces.json").write_text(
            json.dumps(
                {
                    "local-mkt": {
                        "source": {"source": "directory", "path": str(marketplace_root)},
                        "installLocation": str(marketplace_root),
                    }
                }
            ),
            encoding="utf-8",
        )
        (marketplace_root / ".claude-plugin" / "marketplace.json").write_text(
            json.dumps(
                {
                    "name": "local-mkt",
                    "plugins": [
                        {"name": "disk-hygiene", "source": "./plugins/disk-hygiene"}
                    ],
                }
            ),
            encoding="utf-8",
        )
        (plugin_root / ".claude-plugin" / "plugin.json").write_text(
            json.dumps({"name": "disk-hygiene"}), encoding="utf-8"
        )

        auth = install_authority.resolve_install_authority(
            plugin_root=str(plugin_root),
            config_dir=config_dir,
        )
        self.assertEqual(
            str(config_dir / "plugins" / "data" / "disk-hygiene-local-mkt"),
            auth.data_root,
        )
        self.assertEqual(install_authority.DATA_ROOT_CHANNEL_DIRECTORY, auth.channel)
        self.assertEqual(config_dir / "settings.json", auth.user_settings_path)
        self.assertIsNone(auth.plugin_id)

    def test_launch_disclosure_formats_python_and_data_root(self) -> None:
        plugin_root = (
            self.base / "plugins" / "cache" / "acme" / "disk-hygiene" / "0.2.0"
        )
        plugin_root.mkdir(parents=True)
        disclosed = install_authority.launch_disclosure(
            str(plugin_root), config_dir=None
        )
        self.assertEqual(
            os.fspath(Path(sys.executable).resolve()).replace("\\", "/"),
            disclosed["hook_python"],
        )
        self.assertEqual(
            (self.base / "plugins" / "data" / "disk-hygiene-acme").as_posix(),
            disclosed["data_root"],
        )

    def test_engine_context_and_kill_switch_probe_do_not_import_destructive_guard(
        self,
    ) -> None:
        targets = (
            PLUGIN_ROOT / "skills" / "clean" / "scripts" / "engine_context.py",
            PLUGIN_ROOT / "skills" / "setup" / "scripts" / "kill_switch_probe.py",
        )
        for path in targets:
            with self.subTest(script=path.name):
                tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
                imported: set[str] = set()
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        imported.update(alias.name for alias in node.names)
                    elif isinstance(node, ast.ImportFrom) and node.module:
                        imported.add(node.module)
                self.assertNotIn("destructive_guard", imported)


class ProbeEffectiveParityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.user_settings = self.base / "user" / "settings.json"
        self.user_settings.parent.mkdir(parents=True)
        self.managed_dir = self.base / "managed"
        self.managed_dir.mkdir(parents=True)
        self.managed_settings = self.managed_dir / "managed-settings.json"

    @staticmethod
    def _write(path: Path, payload: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")

    def test_managed_false_overrides_user_true_in_probe_and_resolve(self) -> None:
        self._write(
            self.user_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": True}}
                }
            },
        )
        self._write(
            self.managed_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": False}}
                }
            },
        )
        report = killswitch_config.probe_effective(
            self.user_settings, self.managed_settings, "disk-hygiene@acme"
        )
        effective = killswitch_config.resolve_effective(
            self.user_settings, self.managed_settings, "disk-hygiene@acme"
        )
        self.assertFalse(report["effective"])
        self.assertFalse(effective)
        self.assertEqual("configured", report["source"])
        self.assertEqual(str(self.managed_settings), report["settings_path"])

    def test_managed_dropin_overrides_base_managed_file(self) -> None:
        self._write(
            self.user_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": True}}
                }
            },
        )
        self._write(self.managed_settings, {"pluginConfigs": {}})
        dropin = self.managed_dir / "managed-settings.d" / "10-disable.json"
        self._write(
            dropin,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": False}}
                }
            },
        )
        report = killswitch_config.probe_effective(
            self.user_settings, self.managed_settings, "disk-hygiene@acme"
        )
        self.assertFalse(report["effective"])
        self.assertEqual(str(dropin), report["settings_path"])
        self.assertEqual(
            report["effective"],
            killswitch_config.resolve_effective(
                self.user_settings, self.managed_settings, "disk-hygiene@acme"
            ),
        )

    def test_untrusted_managed_true_cannot_override_user_false_on_linux(self) -> None:
        if not sys.platform.startswith("linux") or os.geteuid() == 0:
            self.skipTest("requires non-root Linux")
        self._write(
            self.user_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": False}}
                }
            },
        )
        self._write(
            self.managed_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": True}}
                }
            },
        )
        report = killswitch_config.probe_effective(
            self.user_settings, self.managed_settings, "disk-hygiene@acme"
        )
        self.assertFalse(report["effective"])
        self.assertEqual(str(self.user_settings), report["settings_path"])
        self.assertFalse(
            killswitch_config.resolve_effective(
                self.user_settings, self.managed_settings, "disk-hygiene@acme"
            )
        )

    def test_plugin_id_narrows_probe_effective_to_matching_marketplace(self) -> None:
        self._write(
            self.user_settings,
            {
                "pluginConfigs": {
                    "disk-hygiene@acme": {"options": {"disk_hygiene_enabled": False}},
                    "disk-hygiene@other": {"options": {"disk_hygiene_enabled": True}},
                }
            },
        )
        report = killswitch_config.probe_effective(
            self.user_settings, self.managed_settings, "disk-hygiene@acme"
        )
        self.assertFalse(report["effective"])
        self.assertEqual("configured", report["source"])
        self.assertFalse(report["degraded"])

    def test_windows_managed_path_ignores_programfiles_env(self) -> None:
        with (
            mock.patch.object(killswitch_config.sys, "platform", "win32"),
            mock.patch.dict(
                os.environ, {"ProgramFiles": r"C:\EvilRepo\FakeProgramFiles"}
            ),
        ):
            path = killswitch_config.managed_settings_path()
        self.assertEqual(
            Path(r"C:\Program Files\ClaudeCode\managed-settings.json"), path
        )


if __name__ == "__main__":
    unittest.main()
