#!/usr/bin/env python3
"""Tests for the inventory extractor's `--skills-index` mode.

Each case builds a config dir, a project and a marketplace checkout in a
temporary directory, so the suite never reads this machine's plugins.

Run: python3 test_skills_index.py
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import tempfile
import unittest

import inventory as inv


def _skill(path: pathlib.Path, name: str, description: str, extra: str = "") -> None:
    path.mkdir(parents=True)
    (path / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {description}\n{extra}---\n\nBody.\n",
        encoding="utf-8",
    )


class TestSkillsIndex(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = pathlib.Path(tmp.name)
        self.root = base / "config"
        self.project = base / "repo"
        self.market = base / "checkout"
        (self.project / ".claude").mkdir(parents=True)
        (self.market / ".claude-plugin").mkdir(parents=True)
        (self.root / "plugins").mkdir(parents=True)
        self.write(
            self.root / "plugins" / "known_marketplaces.json",
            {"mkt": {"installLocation": str(self.market)}},
        )
        self.entries: list[dict] = []

    def write(self, path: pathlib.Path, data: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def add_entry(self, entry: dict) -> None:
        self.entries.append(entry)
        self.write(
            self.market / ".claude-plugin" / "marketplace.json",
            {"name": "mkt", "owner": {"name": "o"}, "plugins": self.entries},
        )

    def install(self, plugin: str, skill: str, manifest: dict | None = None) -> None:
        """A cached copy of `plugin@mkt` at version 1.0.0 with one skill."""
        version = self.root / "plugins" / "cache" / "mkt" / plugin / "1.0.0"
        self.write(
            version / ".claude-plugin" / "plugin.json",
            {"name": plugin, **(manifest or {})},
        )
        _skill(version / "skills" / skill, skill, f"cached {skill}")

    def settings(self, scope: str, data: dict) -> None:
        path = {
            "user": self.root / "settings.json",
            "project": self.project / ".claude" / "settings.json",
            "local": self.project / ".claude" / "settings.local.json",
        }[scope]
        self.write(path, data)

    def index(self) -> dict[tuple[str, str | None], dict]:
        records = inv.skills_index(self.root, self.project)
        return {(r["plugin"], r["skill"]): r for r in records}

    def run_main(self, *args: str) -> list[dict]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = inv.main(
                [
                    "--skills-index",
                    "--config-dir",
                    str(self.root),
                    "--project-dir",
                    str(self.project),
                    *args,
                ]
            )
        self.assertEqual(code, 0)
        return json.loads(out.getvalue())

    def add_three_states(self) -> None:
        """One installed, one disabled and one not-installed plugin skill."""
        self.add_entry({"name": "on", "source": "./plugins/on"})
        self.add_entry({"name": "off", "source": "./plugins/off"})
        self.add_entry({"name": "absent", "source": "./plugins/absent"})
        self.install("on", "go")
        self.install("off", "stop")
        absent = self.market / "plugins" / "absent" / "skills" / "later"
        _skill(absent, "later", "later")
        self.settings("user", {"enabledPlugins": {"on@mkt": True, "off@mkt": False}})

    def test_installed_disabled_and_not_installed_skills(self) -> None:
        self.add_three_states()
        got = self.index()
        self.assertEqual(
            got[("on@mkt", "go")],
            {
                "plugin": "on@mkt",
                "skill": "go",
                "name": "go",
                "description": "cached go",
                "when_to_use": None,
                "state": "enabled",
                "source": "cache",
            },
        )
        self.assertEqual(got[("off@mkt", "stop")]["state"], "disabled")
        absent = got[("absent@mkt", "later")]
        self.assertEqual(
            (absent["state"], absent["source"]), ("not-installed", "checkout")
        )

    def test_root_skill_md_without_a_name_takes_the_plugin_name(self) -> None:
        self.add_entry({"name": "solo", "source": "./plugins/solo"})
        self.add_entry({"name": "bare", "source": "./plugins/bare"})
        cache = self.root / "plugins" / "cache" / "mkt"
        for plugin, manifest in (("solo", {"name": "solo-tool"}), ("bare", {})):
            version = cache / plugin / "1.0.0"
            self.write(version / ".claude-plugin" / "plugin.json", manifest)
            (version / "SKILL.md").write_text(
                "---\ndescription: root skill\n---\n\nBody.\n", encoding="utf-8"
            )
        got = self.index()
        solo = got[("solo@mkt", "solo-tool")]
        self.assertEqual(
            (solo["name"], solo["description"], solo["source"]),
            ("solo-tool", "root skill", "cache"),
        )
        # No name in plugin.json: the plugin directory above the version one.
        self.assertEqual(got[("bare@mkt", "bare")]["name"], "bare")
        self.assertNotIn("1.0.0", {r["skill"] for r in got.values()})

    def test_cached_copy_wins_over_checkout_copy(self) -> None:
        self.add_entry({"name": "on", "source": "./plugins/on"})
        _skill(self.market / "plugins" / "on" / "skills" / "go", "go", "checkout go")
        self.install("on", "go")
        rec = self.index()[("on@mkt", "go")]
        self.assertEqual((rec["source"], rec["description"]), ("cache", "cached go"))

    def test_remote_source_plugin_is_one_plugin_level_row(self) -> None:
        self.add_entry(
            {
                "name": "far",
                "source": {"source": "github", "repo": "o/far"},
                "description": "a remote plugin",
            }
        )
        got = self.index()
        self.assertEqual(
            got[("far@mkt", None)],
            {
                "plugin": "far@mkt",
                "skill": None,
                "name": "far",
                "description": "a remote plugin",
                "when_to_use": None,
                "state": "not-installed",
                "source": "marketplace-manifest",
            },
        )
        self.assertEqual([k for k in got if k[0] == "far@mkt"], [("far@mkt", None)])

    def test_no_enabled_plugins_entry_follows_default_enabled(self) -> None:
        self.add_entry({"name": "entry-off", "source": "./p", "defaultEnabled": False})
        self.add_entry({"name": "manifest-off", "source": "./q"})
        self.add_entry({"name": "plain", "source": "./r"})
        self.add_entry({"name": "overridden", "source": "./s", "defaultEnabled": True})
        self.install("entry-off", "a")
        self.install("manifest-off", "b", {"defaultEnabled": False})
        self.install("plain", "c")
        self.install("overridden", "d", {"defaultEnabled": False})
        got = self.index()
        self.assertEqual(got[("entry-off@mkt", "a")]["state"], "disabled")
        self.assertEqual(got[("manifest-off@mkt", "b")]["state"], "disabled")
        self.assertEqual(got[("plain@mkt", "c")]["state"], "enabled")
        # The marketplace entry's defaultEnabled overrides plugin.json's.
        self.assertEqual(got[("overridden@mkt", "d")]["state"], "enabled")

    def test_local_scope_overrides_user_scope(self) -> None:
        self.add_entry({"name": "on", "source": "./plugins/on"})
        self.install("on", "go")
        self.settings("user", {"enabledPlugins": {"on@mkt": True}})
        self.settings("local", {"enabledPlugins": {"on@mkt": False}})
        self.assertEqual(self.index()[("on@mkt", "go")]["state"], "disabled")

    def test_scope_with_a_non_boolean_value_decides_nothing(self) -> None:
        self.add_entry({"name": "on", "source": "./plugins/on"})
        self.install("on", "go")
        self.settings("user", {"enabledPlugins": {"on@mkt": False}})
        self.settings("local", {"enabledPlugins": {"on@mkt": True, "x@mkt": "yes"}})
        self.assertEqual(self.index()[("on@mkt", "go")]["state"], "disabled")

    def test_config_scope_skills_and_skill_overrides(self) -> None:
        personal = self.root / "skills" / "mine"
        _skill(personal, "mine", "personal", "when_to_use: daily\n")
        _skill(self.project / ".claude" / "skills" / "team", "team", "project")
        self.settings("local", {"skillOverrides": {"team": "off", "mine": "name-only"}})
        got = self.index()
        mine = got[("user", "mine")]
        self.assertEqual(
            (mine["state"], mine["source"], mine["when_to_use"]),
            ("enabled", "config-scope", "daily"),
        )
        self.assertEqual(got[("project", "team")]["state"], "disabled")

    def test_exclude_drops_disabled_and_not_installed_records(self) -> None:
        self.add_three_states()
        self.add_entry({"name": "far", "source": {"source": "github", "repo": "o/far"}})
        all_states = {r["state"] for r in self.run_main()}
        self.assertEqual(all_states, {"enabled", "disabled", "not-installed"})
        kept = self.run_main("--exclude", "disabled,not-installed")
        self.assertEqual([(r["plugin"], r["skill"]) for r in kept], [("on@mkt", "go")])

    def test_exclude_rejects_an_unknown_state(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(inv.main(["--skills-index", "--exclude", "gone"]), 2)
            self.assertEqual(inv.main(["--exclude", "disabled"]), 2)


if __name__ == "__main__":
    unittest.main()
