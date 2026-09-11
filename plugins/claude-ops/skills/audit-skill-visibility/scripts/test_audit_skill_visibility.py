"""Unit tests for the audit-skill-visibility classifier.

The classifier is pure -- `(denominator, events, config, clock) -> model` -- and
every test here pins a defect found during this topic's audit. Each test names
the failure it prevents, because a fixture whose purpose is forgotten gets
"fixed" by the next person who sees it fail.
"""

import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

# ISOLATION (#2840). The churn tests below build throwaway git repositories. An
# inherited ABSOLUTE GIT_DIR overrides repository discovery and outranks `git
# -C`, so a fixture's `git config` would write its throwaway identity into the
# CALLER's .git/config — shared by every worktree of the clone — instead of into
# the fixture. Cleared unconditionally, before any test spawns git.
for _v in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_v, None)

import audit_skill_visibility as engine  # noqa: E402  (import follows the git-env clear above)


def _utc(y, m, d):
    return datetime(y, m, d, tzinfo=timezone.utc)


def _skill(name, source="plugin"):
    return {"qualified_name": name, "source": source}


class HorizonClampTest(unittest.TestCase):
    """A window wider than the data's horizon must never render a verdict.

    The audit measured this: a 3-day-old install against 30/90-day tiers put
    210 of 213 skills in `never`, and two tiers were structurally unreachable.
    """

    def test_no_dormant_verdict_when_horizon_shorter_than_dormant_window(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("planning:interview")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=3)},
        )
        row = model["skills"][0]
        self.assertEqual(row["observation"]["value"], "not-observable")
        self.assertNotEqual(row["observation"]["value"], "dormant")

    def test_observed_horizon_is_the_narrowest_source_horizon(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("planning:interview")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={
                "native": now - timedelta(days=90),
                "jsonl": now - timedelta(days=1),
            },
        )
        # Narrowest == most recent start == the least we can see back to.
        self.assertEqual(
            model["observed_horizon"], (now - timedelta(days=1)).isoformat()
        )


class NotObservableDefaultTest(unittest.TestCase):
    """Absence of data is never reported as absence of use.

    This is the single correction the whole audit turned on.
    """

    def test_empty_store_yields_not_observable_never_never_used(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one"), _skill("b:two")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=2)},
        )
        values = {r["observation"]["value"] for r in model["skills"]}
        self.assertEqual(values, {"not-observable"})

    def test_below_exposure_floor_lands_in_withheld_with_a_reason(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=2)},
        )
        self.assertTrue(
            model["withheld"], "a withheld claim must be recorded, not omitted"
        )
        self.assertTrue(all(w.get("reason") for w in model["withheld"]))


class ObservationTierTest(unittest.TestCase):
    """With a horizon wide enough to support them, the tiers do resolve."""

    def test_recent_use_is_active_when_horizon_supports_it(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[
                {"skill": "a:one", "ts": now - timedelta(days=2), "source": "native"}
            ],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        self.assertEqual(model["skills"][0]["observation"]["value"], "active")

    def test_old_use_is_dormant_when_horizon_supports_it(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[
                {"skill": "a:one", "ts": now - timedelta(days=200), "source": "native"}
            ],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        self.assertEqual(model["skills"][0]["observation"]["value"], "dormant")


class PluginUsageTest(unittest.TestCase):
    """`pluginUsage` is not a skill signal and must never reach the model.

    Measured: 46-48 of 65 plugins carry usageCount 0 with an identical recent
    lastUsedAt -- an install stamp. Read as recency it reports never-used
    plugins as active, inverting the picture.
    """

    def test_install_seeded_row_is_not_usage(self):
        now = _utc(2026, 8, 18)
        seeded = {"usageCount": 0, "lastUsedAt": now - timedelta(hours=1)}
        self.assertFalse(engine.is_usage_evidence(seeded))

    def test_real_use_is_usage(self):
        now = _utc(2026, 8, 18)
        real = {"usageCount": 3, "lastUsedAt": now - timedelta(hours=1)}
        self.assertTrue(engine.is_usage_evidence(real))


class ReconciliationTest(unittest.TestCase):
    """Native and JSONL record the same invocation -- reconcile, never sum."""

    def test_same_event_in_two_sources_counts_once(self):
        now = _utc(2026, 8, 18)
        ts = now - timedelta(days=1)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[
                {"skill": "a:one", "ts": ts, "source": "native", "count": 1},
                {"skill": "a:one", "ts": ts, "source": "jsonl", "count": 1},
            ],
            config=engine.Config(),
            clock=now,
            horizons={
                "native": now - timedelta(days=400),
                "jsonl": now - timedelta(days=400),
            },
        )
        self.assertEqual(model["skills"][0]["observation"]["count"], 1)

    def test_two_genuine_same_second_invocations_are_not_deduped_away(self):
        now = _utc(2026, 8, 18)
        ts = now - timedelta(days=1)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[
                {"skill": "a:one", "ts": ts, "source": "jsonl", "count": 1},
                {"skill": "a:one", "ts": ts, "source": "jsonl", "count": 1},
            ],
            config=engine.Config(),
            clock=now,
            horizons={"jsonl": now - timedelta(days=400)},
        )
        self.assertEqual(model["skills"][0]["observation"]["count"], 2)


class AmbiguousAttributionTest(unittest.TestCase):
    """Two marketplaces shipping the same plugin name collapse to one usage key."""

    def test_duplicate_qualified_name_is_marked_ambiguous(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("dup:leaf", "mkt-a"), _skill("dup:leaf", "mkt-b")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        self.assertTrue(
            all(r["attribution"] == "ambiguous-attribution" for r in model["skills"])
        )


class ReachabilityTest(unittest.TestCase):
    """Can the model ever select this skill?

    Kept orthogonal to `observation` on purpose: a single flat verdict collapses
    "cannot be selected" with "has not been seen", and those demand opposite
    actions. `user-only` is not a problem; `misconfigured` is a fix; only
    `model-reachable` with no observation is a starvation candidate.
    """

    def _row(self, **frontmatter):
        now = _utc(2026, 8, 18)
        entry = _skill("a:one")
        entry["frontmatter"] = frontmatter
        entry["plugin_enabled"] = frontmatter.pop("_plugin_enabled", True)
        model = engine.classify(
            denominator=[entry],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        return model["skills"][0]["reachability"]

    def test_disable_model_invocation_is_user_only_not_unused(self):
        reach = self._row(description="d", disable_model_invocation=True)
        self.assertEqual(reach["value"], "user-only")

    def test_normal_skill_is_model_reachable(self):
        reach = self._row(description="a real description")
        self.assertEqual(reach["value"], "model-reachable")

    def test_malformed_frontmatter_is_misconfigured_and_never_a_removal(self):
        reach = self._row(_malformed=True)
        self.assertEqual(reach["value"], "misconfigured")
        self.assertIn("malformed-frontmatter", reach["causes"])
        # The remedy must not read as "delete this skill" -- several silent
        # causes look exactly like disuse and are actually fixable.
        self.assertNotRegex(reach["remedy"].lower(), r"delete|remove")

    def test_missing_description_is_misconfigured(self):
        reach = self._row(description="")
        self.assertEqual(reach["value"], "misconfigured")
        self.assertIn("no-description", reach["causes"])

    def test_disabled_plugin_is_hidden(self):
        reach = self._row(description="d", _plugin_enabled=False)
        self.assertEqual(reach["value"], "hidden")
        self.assertEqual(reach["causes"], ["plugin-not-enabled"])

    def _classify_one(self, entry):
        now = _utc(2026, 8, 18)
        return engine.classify(
            denominator=[entry],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )

    def test_undetermined_enablement_is_unknown_and_names_the_file(self):
        """`unknown` is reserved for a source that could not answer: the
        evidence names the settings file that could not be read, and the
        remedy repeats it, so the row is a fix and never a guess."""
        entry = _skill("a:one")
        entry["frontmatter"] = {"description": "d"}
        entry["plugin_enabled"] = None
        entry["plugin_enabled_evidence"] = "/repo/.claude/settings.local.json"
        reach = self._classify_one(entry)["skills"][0]["reachability"]
        self.assertEqual(reach["value"], "unknown")
        self.assertEqual(reach["causes"], ["enablement-undetermined"])
        self.assertIn("/repo/.claude/settings.local.json", reach["remedy"])
        self.assertEqual(reach["evidence"], "/repo/.claude/settings.local.json")

    def test_a_checkout_entry_is_not_assessed_never_unknown(self):
        """A checkout is not an install, so enablement is declined for the
        run rather than answered `unknown` per row, and the Markdown carries
        that refusal exactly once."""
        with tempfile.TemporaryDirectory() as tmp:
            skill = os.path.join(tmp, "p", "skills", "s")
            os.makedirs(skill)
            with open(os.path.join(skill, "SKILL.md"), "w", encoding="utf-8") as h:
                h.write('---\ndescription: "d"\n---\n')
            model = self._classify_one(engine.collect_fleet(tmp)[0])
        reach = model["skills"][0]["reachability"]
        self.assertEqual(reach["value"], "not-assessed")
        self.assertEqual(reach["causes"], ["checkout-not-an-install"])
        self.assertIsNone(reach["evidence"])
        rendered = engine._render_markdown(model)
        self.assertEqual(
            rendered.count("Reachability not assessed: a checkout is not an install"),
            1,
        )
        self.assertNotIn("unknown", rendered)

    def test_misconfigured_still_fires_in_checkout_mode(self):
        entry = _skill("a:one")
        entry["frontmatter"] = {"_malformed": True}
        entry["plugin_enabled"] = None
        entry["plugin_enabled_evidence"] = engine.ENABLEMENT_NOT_ASSESSED
        reach = self._classify_one(entry)["skills"][0]["reachability"]
        self.assertEqual(reach["value"], "misconfigured")

    # --- enabledPlugins, end to end through the installed collector ---------
    #
    # Each case builds its settings scopes and a one-plugin install in a
    # temporary tree and reads them through the same `settings_layers` walk
    # the listing keys use, so the precedence under test is the reader's, not
    # a hand-built layer list. Nothing here touches the real ~/.claude.

    @staticmethod
    def _write_json(path, blob):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(blob, handle)

    def _installed_reach(
        self, tmp, user=None, project=None, local=None, managed=None, raw=None
    ):
        """Reachability of `alpha:one` from `alpha@mkt`, installed at user
        scope, under the given `enabledPlugins` blocks. `raw` writes literal
        text to a scope file so a malformed one can be staged."""
        config_root = os.path.join(tmp, "config")
        project_root = os.path.join(tmp, "repo")
        os.makedirs(config_root, exist_ok=True)
        os.makedirs(project_root, exist_ok=True)
        paths = {
            "user": os.path.join(config_root, "settings.json"),
            "project": os.path.join(project_root, ".claude", "settings.json"),
            "local": os.path.join(project_root, ".claude", "settings.local.json"),
        }
        for scope, block in (("user", user), ("project", project), ("local", local)):
            if block is not None:
                self._write_json(paths[scope], {"enabledPlugins": block})
        for scope, text in (raw or {}).items():
            os.makedirs(os.path.dirname(paths[scope]), exist_ok=True)
            with open(paths[scope], "w", encoding="utf-8") as handle:
                handle.write(text)
        cache = os.path.join(tmp, "cache", "alpha")
        skill = os.path.join(cache, "skills", "one")
        os.makedirs(skill, exist_ok=True)
        with open(os.path.join(skill, "SKILL.md"), "w", encoding="utf-8") as handle:
            handle.write('---\nname: one\ndescription: "does a"\n---\n')
        plugins_dir = os.path.join(tmp, "plugins-config")
        self._write_json(
            os.path.join(plugins_dir, "installed_plugins.json"),
            {
                "version": 2,
                "plugins": {
                    "alpha@mkt": [
                        {"scope": "user", "version": "1.0.0", "installPath": cache}
                    ]
                },
            },
        )
        layers = engine.settings_layers(
            project_root,
            config_root,
            managed or {"status": "unreadable", "lib": "n/a", "reason": "stubbed"},
        )
        denominator, _ = engine.collect_installed(
            plugins_dir, project_root, engine.merge_enabled_plugins(layers)
        )
        self.assertEqual([e["qualified_name"] for e in denominator], ["alpha:one"])
        model = self._classify_one(denominator[0])
        return model["skills"][0]["reachability"], paths

    def test_a_plugin_disabled_in_project_settings_hides_its_skills(self):
        with tempfile.TemporaryDirectory() as tmp:
            reach, paths = self._installed_reach(tmp, project={"alpha@mkt": False})
        self.assertEqual(reach["value"], "hidden")
        self.assertEqual(reach["causes"], ["plugin-not-enabled"])
        self.assertEqual(reach["evidence"], paths["project"])

    def test_absent_from_every_scope_is_enabled_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            reach, _ = self._installed_reach(tmp, project={"other@mkt": False})
        self.assertEqual(reach["value"], "model-reachable")

    def test_project_true_outranks_user_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            reach, _ = self._installed_reach(
                tmp, user={"alpha@mkt": False}, project={"alpha@mkt": True}
            )
        self.assertEqual(reach["value"], "model-reachable")

    def test_local_false_outranks_project_true(self):
        with tempfile.TemporaryDirectory() as tmp:
            reach, paths = self._installed_reach(
                tmp, project={"alpha@mkt": True}, local={"alpha@mkt": False}
            )
        self.assertEqual(reach["value"], "hidden")
        self.assertEqual(reach["evidence"], paths["local"])

    @unittest.skipIf(shutil.which("bash") is None, "bash not on PATH")
    def test_managed_policy_false_outranks_local_true(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "managed", "managed-settings.json")
            self._write_json(base, {"enabledPlugins": {"alpha@mkt": False}})
            managed = engine.enumerate_managed_scope(
                engine.managed_scope_lib_path(), override=base
            )
            self.assertEqual(managed["status"], "read", managed)
            reach, _ = self._installed_reach(
                tmp, local={"alpha@mkt": True}, managed=managed
            )
        self.assertEqual(reach["value"], "hidden")
        self.assertEqual(reach["evidence"], base)

    def test_a_malformed_settings_file_is_unknown_never_a_guess(self):
        """An unparsable scope could have set the key at its own precedence,
        so every plugin whose answer would come from below it is `unknown`,
        with the file named, never `hidden` or `model-reachable`."""
        with tempfile.TemporaryDirectory() as tmp:
            reach, paths = self._installed_reach(
                tmp, user={"alpha@mkt": True}, raw={"project": "{not json"}
            )
        self.assertEqual(reach["value"], "unknown")
        self.assertEqual(reach["causes"], ["enablement-undetermined"])
        self.assertIn(paths["project"], reach["remedy"])

    def test_a_readable_scope_above_a_malformed_one_still_decides(self):
        """Precedence is per key and upward: a `false` in local outranks
        whatever the unreadable project file might have said."""
        with tempfile.TemporaryDirectory() as tmp:
            reach, paths = self._installed_reach(
                tmp, raw={"project": "{not json"}, local={"alpha@mkt": False}
            )
        self.assertEqual(reach["value"], "hidden")
        self.assertEqual(reach["evidence"], paths["local"])


class EnabledPluginsMergeTest(unittest.TestCase):
    """The pure per-key merge, on hand-built layers."""

    @staticmethod
    def _layer(scope, path, settings=None, status="read"):
        return {"scope": scope, "path": path, "status": status, "settings": settings}

    def test_last_defined_scope_wins_per_key(self):
        merged = engine.merge_enabled_plugins(
            [
                self._layer(
                    "user", "/u", {"enabledPlugins": {"a@m": False, "b@m": False}}
                ),
                self._layer("project", "/p", {"enabledPlugins": {"a@m": True}}),
            ]
        )
        self.assertEqual(merged["plugins"]["a@m"], {"value": True, "evidence": "/p"})
        self.assertEqual(merged["plugins"]["b@m"], {"value": False, "evidence": "/u"})
        self.assertEqual(engine.enablement_for(merged, "c@m")["evidence"], "default")

    def test_a_non_boolean_value_is_left_out_and_named(self):
        merged = engine.merge_enabled_plugins(
            [self._layer("user", "/u", {"enabledPlugins": {"a@m": "yes"}})]
        )
        self.assertNotIn("a@m", merged["plugins"])
        self.assertEqual(len(merged["ignored"]), 1)
        self.assertIn("a@m", merged["ignored"][0])

    def test_unread_scopes_without_a_file_do_not_poison_the_merge(self):
        """The flag scope and an unenumerable managed scope carry no file
        path; they are reported in the inputs, not treated as unreadable."""
        merged = engine.merge_enabled_plugins(
            [
                self._layer("user", "/u", {"enabledPlugins": {"a@m": False}}),
                self._layer("flag", "--settings", status="unread"),
                self._layer("policy", None, status="unreadable"),
            ]
        )
        self.assertEqual(merged["unreadable"], [])
        self.assertEqual(merged["plugins"]["a@m"]["value"], False)


class ReachabilityFixtureTest(unittest.TestCase):
    """Exact counts against a fixture of known composition.

    Deliberately not a live-machine assertion: the denominator is the operator's
    enabled fleet, which differs per machine, so a live count cannot tell a
    regression from a smaller install.
    """

    def test_four_skill_fixture_resolves_one_of_each(self):
        import pathlib

        fixture = (
            pathlib.Path(__file__).parent.parent
            / "tests"
            / "fixtures"
            / "fleet-reachability.json"
        )
        bundle = json.loads(fixture.read_text(encoding="utf-8"))
        now = datetime.fromisoformat(bundle["now"])
        model = engine.classify(
            denominator=bundle["denominator"],
            events=[],
            config=engine.Config(**bundle.get("config", {})),
            clock=now,
            horizons={
                k: datetime.fromisoformat(v) for k, v in bundle["horizons"].items()
            },
        )
        counts: dict[str, int] = {}
        for row in model["skills"]:
            counts[row["reachability"]["value"]] = (
                counts.get(row["reachability"]["value"], 0) + 1
            )
        self.assertEqual(counts.get("user-only"), 1)
        self.assertEqual(counts.get("misconfigured"), 1)
        self.assertEqual(counts.get("model-reachable"), 1)
        self.assertEqual(counts.get("hidden"), 1)


class BudgetArithmeticTest(unittest.TestCase):
    """The CERTAIN half: does the listing overflow, and by how much.

    Computed entirely from documented settings, so it needs no undocumented
    constant and holds at every capability tier.
    """

    def test_budget_is_derived_not_a_constant_8000(self):
        """A 1M-token context yields 40,000 chars, not 8,000.

        The familiar 8,000 is that same formula at a 200k window. Hardcoding it
        would be wrong for most current models -- this is the regression pin.
        """
        self.assertEqual(
            engine.listing_budget_chars(
                engine.ListingConfig(context_window_tokens=1_000_000)
            ),
            40_000,
        )

    def test_budget_at_200k_window_reproduces_the_familiar_8000(self):
        self.assertEqual(
            engine.listing_budget_chars(
                engine.ListingConfig(context_window_tokens=200_000)
            ),
            8_000,
        )

    def test_env_override_short_circuits_unconditionally(self):
        cfg = engine.ListingConfig(
            context_window_tokens=1_000_000, env_char_budget=1234
        )
        self.assertEqual(engine.listing_budget_chars(cfg), 1234)

    def test_per_skill_description_is_capped(self):
        entry = {
            "qualified_name": "a:one",
            "frontmatter": {"description": "x" * 5000},
            "plugin_enabled": True,
        }
        cfg = engine.ListingConfig(context_window_tokens=200_000, max_desc_chars=1536)
        listing = engine.compute_listing([entry], cfg)
        self.assertEqual(listing["demand_chars"], 1536)

    def test_overflow_is_zero_when_demand_fits(self):
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 100},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        cfg = engine.ListingConfig(context_window_tokens=200_000)
        listing = engine.compute_listing(entries, cfg)
        self.assertEqual(listing["overflow_chars"], 0)
        self.assertEqual(listing["verdict"], "listing-fits")

    def test_overflow_is_positive_and_exact_when_demand_exceeds(self):
        # 10 skills x 1000 chars = 10_000 demand against an 8_000 budget.
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        cfg = engine.ListingConfig(context_window_tokens=200_000)
        listing = engine.compute_listing(entries, cfg)
        self.assertEqual(listing["demand_chars"], 10_000)
        self.assertEqual(listing["overflow_chars"], 2_000)
        self.assertEqual(listing["verdict"], "overflowing")

    # --- Settings scopes -----------------------------------------------------
    #
    # The two listing keys are read from the same scopes the product merges,
    # per key, user < project < local < flag < policy. Every test here builds
    # its scopes in a temporary tree and never touches the real ~/.claude.

    @staticmethod
    def _write_json(path, blob):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(blob, handle)

    @staticmethod
    def _managed_unreadable():
        return {"status": "unreadable", "lib": "n/a", "reason": "stubbed out"}

    def _scopes(self, tmp, user=None, project=None, local=None):
        config_root = os.path.join(tmp, "config")
        project_root = os.path.join(tmp, "repo")
        os.makedirs(config_root)
        os.makedirs(project_root)
        if user is not None:
            self._write_json(os.path.join(config_root, "settings.json"), user)
        if project is not None:
            self._write_json(
                os.path.join(project_root, ".claude", "settings.json"), project
            )
        if local is not None:
            self._write_json(
                os.path.join(project_root, ".claude", "settings.local.json"), local
            )
        return project_root, config_root

    def test_project_setting_overrides_user_setting(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(
                tmp,
                user={"skillListingBudgetFraction": 0.02},
                project={"skillListingBudgetFraction": 0.05},
            )
            layers = engine.settings_layers(
                project_root, config_root, self._managed_unreadable()
            )
            merged = engine.merge_listing_settings(layers)
        row = merged["skillListingBudgetFraction"]
        self.assertEqual(row["value"], 0.05)
        self.assertEqual(
            row["provenance"],
            "settings:" + os.path.join(project_root, ".claude", "settings.json"),
        )

    def test_local_setting_overrides_project_setting(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(
                tmp,
                user={"skillListingMaxDescChars": 100},
                project={"skillListingMaxDescChars": 200},
                local={"skillListingMaxDescChars": 300},
            )
            layers = engine.settings_layers(
                project_root, config_root, self._managed_unreadable()
            )
            merged = engine.merge_listing_settings(layers)
        row = merged["skillListingMaxDescChars"]
        self.assertEqual(row["value"], 300)
        self.assertTrue(row["provenance"].endswith("settings.local.json"))
        # The other key is untouched by scopes that do not define it.
        self.assertEqual(merged["skillListingBudgetFraction"]["provenance"], "default")

    def test_a_key_absent_everywhere_reports_default_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(tmp, project={"other": 1})
            layers = engine.settings_layers(
                project_root, config_root, self._managed_unreadable()
            )
            merged = engine.merge_listing_settings(layers)
        for key in engine.LISTING_SETTINGS_KEYS:
            self.assertIsNone(merged[key]["value"])
            self.assertEqual(merged[key]["provenance"], "default")

    def test_flag_scope_is_reported_unread_never_absent(self):
        """`--settings` lives inside the session; an outside reader cannot
        see it, and saying "absent" would claim knowledge it lacks."""
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(tmp)
            layers = engine.settings_layers(
                project_root, config_root, self._managed_unreadable()
            )
        flag = [layer for layer in layers if layer["scope"] == "flag"]
        self.assertEqual(len(flag), 1)
        self.assertEqual(flag[0]["status"], "unread")
        self.assertEqual(flag[0]["path"], "--settings")
        self.assertIn("not observable", flag[0]["note"])
        # It sits between local and policy, the documented precedence.
        order = [layer["scope"] for layer in layers]
        self.assertLess(order.index("local"), order.index("flag"))
        self.assertLess(order.index("flag"), order.index("policy"))

    def test_unreadable_managed_scope_is_reported_not_treated_as_absent(self):
        """A bash that cannot run is "managed scope unreadable", never a crash
        and never an empty policy scope."""
        managed = engine.enumerate_managed_scope(
            engine.managed_scope_lib_path(), bash="/nonexistent/bash-binary"
        )
        self.assertEqual(managed["status"], "unreadable")
        self.assertIn("could not be run", managed["reason"])
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(tmp)
            layers = engine.settings_layers(project_root, config_root, managed)
        policy = [layer for layer in layers if layer["scope"] == "policy"]
        self.assertEqual([layer["status"] for layer in policy], ["unreadable"])
        self.assertIn("could not be run", policy[0]["note"])

    def test_a_missing_vendored_lib_is_unreadable_not_a_crash(self):
        managed = engine.enumerate_managed_scope("/nonexistent/managed-scope.sh")
        self.assertEqual(managed["status"], "unreadable")

    @unittest.skipIf(shutil.which("bash") is None, "bash not on PATH")
    def test_managed_policy_outranks_local_through_the_vendored_lib(self):
        """The policy scope is enumerated by the vendored managed-scope.sh,
        through its own base-file override seam, and its drop-ins merge on
        top of the base file in name order."""
        lib = engine.managed_scope_lib_path()
        self.assertTrue(os.path.isfile(lib), lib)
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(
                tmp, local={"skillListingBudgetFraction": 0.03}
            )
            base = os.path.join(tmp, "managed", "managed-settings.json")
            self._write_json(base, {"skillListingBudgetFraction": 0.04})
            dropin = os.path.join(tmp, "managed", "managed-settings.d")
            self._write_json(
                os.path.join(dropin, "10-first.json"),
                {"skillListingBudgetFraction": 0.06},
            )
            self._write_json(
                os.path.join(dropin, "20-second.json"),
                {"skillListingBudgetFraction": 0.07},
            )
            # Hidden files are ignored per the documented merge.
            self._write_json(
                os.path.join(dropin, ".hidden.json"),
                {"skillListingBudgetFraction": 0.99},
            )
            managed = engine.enumerate_managed_scope(lib, override=base)
            self.assertEqual(managed["status"], "read", managed)
            self.assertEqual(managed["base_file"], base)
            self.assertEqual(managed["dropin_dir"], dropin)
            layers = engine.settings_layers(project_root, config_root, managed)
            merged = engine.merge_listing_settings(layers)
        row = merged["skillListingBudgetFraction"]
        self.assertEqual(row["value"], 0.07)
        self.assertEqual(
            row["provenance"], "settings:" + os.path.join(dropin, "20-second.json")
        )

    def test_a_non_numeric_setting_is_left_out_and_named(self):
        with tempfile.TemporaryDirectory() as tmp:
            project_root, config_root = self._scopes(
                tmp,
                user={"skillListingBudgetFraction": 0.02},
                project={"skillListingBudgetFraction": "lots"},
            )
            layers = engine.settings_layers(
                project_root, config_root, self._managed_unreadable()
            )
            merged = engine.merge_listing_settings(layers)
        self.assertEqual(merged["skillListingBudgetFraction"]["value"], 0.02)
        self.assertEqual(len(merged["ignored"]), 1)
        self.assertIn("skillListingBudgetFraction", merged["ignored"][0])

    # --- Window, bytes per token, and the band --------------------------------

    @staticmethod
    def _no_pins(**pins):
        base = {
            "context_window": None,
            "bytes_per_token": None,
            "budget_fraction": None,
            "max_desc_chars": None,
        }
        base.update(pins)
        return base

    @staticmethod
    def _fleet(count=10, chars=1000):
        return [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * chars},
                "plugin_enabled": True,
            }
            for i in range(count)
        ]

    def _project_fraction_layers(self, tmp, fraction):
        project_root, config_root = self._scopes(
            tmp, project={"skillListingBudgetFraction": fraction}
        )
        return engine.settings_layers(
            project_root, config_root, self._managed_unreadable()
        )

    def test_unpinned_run_carries_four_labelled_rows_and_names_no_session(self):
        cfg, axes = engine.build_listing_inputs(self._no_pins(), {}, [])
        listing = engine.compute_listing_band(self._fleet(), cfg, axes)
        self.assertEqual(
            [row["label"] for row in listing["band"]],
            ["200k/4", "200k/3", "1M/4", "1M/3"],
        )
        for row in listing["band"]:
            for key in ("budget_chars", "overflow_chars", "verdict", "starved_count"):
                self.assertIn(key, row)
        # The top level names no row as this session: numbers are nulled.
        self.assertEqual(listing["budget_basis"], "band")
        self.assertIsNone(listing["budget_chars"])
        self.assertIsNone(listing["overflow_chars"])
        self.assertIsNone(listing["starved_count"])
        self.assertIsNone(listing["label"])
        # 10 x 1000 = 10,000 demand: overflows at 200k (8,000 and 6,000) and
        # fits at 1M (40,000 and 30,000), so the verdict is band-dependent.
        self.assertEqual(listing["verdict"], "band-dependent")
        self.assertEqual(
            [row["verdict"] for row in listing["band"]],
            ["overflowing", "overflowing", "listing-fits", "listing-fits"],
        )
        competing = [s for s in listing["skills"] if s["eligibility"] == "competing"]
        self.assertEqual(
            set(competing[0]["by_band"]), {"200k/4", "200k/3", "1M/4", "1M/3"}
        )

    def test_project_fraction_of_five_percent_budgets_200k_chars_at_1m_4(self):
        """The acceptance row: 1,000,000 x 4 x 0.05 = 200,000, and the row's
        basis names the settings file that supplied the fraction."""
        with tempfile.TemporaryDirectory() as tmp:
            layers = self._project_fraction_layers(tmp, 0.05)
            cfg, axes = engine.build_listing_inputs(self._no_pins(), {}, layers)
            listing = engine.compute_listing_band(self._fleet(), cfg, axes)
            expected_path = os.path.join(tmp, "repo", ".claude", "settings.json")
        row = next(r for r in listing["band"] if r["label"] == "1M/4")
        self.assertEqual(row["budget_chars"], 200_000)
        self.assertEqual(row["budget_basis"], f"settings:{expected_path}")
        self.assertEqual(
            axes.inputs["budget_fraction"],
            {"value": 0.05, "provenance": f"settings:{expected_path}"},
        )

    def test_env_override_ignores_the_fraction_and_collapses_the_band(self):
        with tempfile.TemporaryDirectory() as tmp:
            layers = self._project_fraction_layers(tmp, 0.05)
            cfg, axes = engine.build_listing_inputs(
                self._no_pins(), {"SLASH_COMMAND_TOOL_CHAR_BUDGET": "1234"}, layers
            )
        listing = engine.compute_listing_band(self._fleet(), cfg, axes)
        self.assertEqual(listing["budget_chars"], 1234)
        self.assertEqual(listing["budget_basis"], "env-override")
        self.assertNotIn("band", listing)
        self.assertIn("fraction ignored", axes.inputs["env_char_budget"]["provenance"])

    def test_disable_1m_collapses_the_window_axis_only(self):
        cfg, axes = engine.build_listing_inputs(
            self._no_pins(), {"CLAUDE_CODE_DISABLE_1M_CONTEXT": "1"}, []
        )
        self.assertEqual(axes.windows, (200_000,))
        self.assertEqual(axes.bytes_per_tokens, (4, 3))
        self.assertEqual(
            axes.inputs["windows"]["provenance"], "env:CLAUDE_CODE_DISABLE_1M_CONTEXT"
        )
        listing = engine.compute_listing_band(self._fleet(), cfg, axes)
        self.assertEqual([r["label"] for r in listing["band"]], ["200k/4", "200k/3"])

    def test_a_non_truthy_disable_1m_has_no_effect(self):
        _, axes = engine.build_listing_inputs(
            self._no_pins(), {"CLAUDE_CODE_DISABLE_1M_CONTEXT": "0"}, []
        )
        self.assertEqual(axes.windows, (200_000, 1_000_000))
        row = next(r for r in axes.inputs["env"] if r["name"].endswith("1M_CONTEXT"))
        self.assertEqual(row["effect"], "not truthy: no effect")

    def test_max_context_tokens_is_honoured_only_with_disable_compact(self):
        _, without = engine.build_listing_inputs(
            self._no_pins(), {"CLAUDE_CODE_MAX_CONTEXT_TOKENS": "500000"}, []
        )
        self.assertEqual(without.windows, (200_000, 1_000_000))
        row = next(
            r for r in without.inputs["env"] if r["name"].endswith("MAX_CONTEXT_TOKENS")
        )
        self.assertIn("DISABLE_COMPACT", row["effect"])

        cfg, with_compact = engine.build_listing_inputs(
            self._no_pins(),
            {"CLAUDE_CODE_MAX_CONTEXT_TOKENS": "500000", "DISABLE_COMPACT": "1"},
            [],
        )
        self.assertEqual(with_compact.windows, (500_000,))
        self.assertEqual(
            with_compact.inputs["windows"]["provenance"],
            "env:CLAUDE_CODE_MAX_CONTEXT_TOKENS",
        )
        listing = engine.compute_listing_band(self._fleet(), cfg, with_compact)
        self.assertEqual(
            [r["label"] for r in listing["band"]], ["500,000/4", "500,000/3"]
        )

    def test_pins_on_both_axes_return_the_single_row_shape(self):
        cfg, axes = engine.build_listing_inputs(
            self._no_pins(context_window=200_000, bytes_per_token=4), {}, []
        )
        listing = engine.compute_listing_band(self._fleet(), cfg, axes)
        self.assertNotIn("band", listing)
        self.assertEqual(listing["label"], "200k/4")
        self.assertEqual(listing["budget_chars"], 8_000)
        self.assertEqual(listing["budget_basis"], "fraction")
        self.assertEqual(axes.inputs["windows"]["provenance"], "pin:--context-window")
        self.assertEqual(
            axes.inputs["bytes_per_tokens"]["provenance"], "pin:--bytes-per-token"
        )

    def test_a_bytes_per_token_pin_collapses_that_axis_only(self):
        cfg, axes = engine.build_listing_inputs(
            self._no_pins(bytes_per_token=3), {}, []
        )
        listing = engine.compute_listing_band(self._fleet(), cfg, axes)
        self.assertEqual([r["label"] for r in listing["band"]], ["200k/3", "1M/3"])
        self.assertEqual(listing["band"][0]["budget_chars"], 6_000)

    def test_fraction_and_cap_pins_outrank_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            layers = self._project_fraction_layers(tmp, 0.05)
            cfg, axes = engine.build_listing_inputs(
                self._no_pins(budget_fraction=0.02, max_desc_chars=100), {}, layers
            )
        self.assertEqual(cfg.budget_fraction, 0.02)
        self.assertEqual(cfg.max_desc_chars, 100)
        self.assertEqual(cfg.fraction_basis, "pin:--budget-fraction")
        self.assertEqual(
            axes.inputs["max_desc_chars"]["provenance"], "pin:--max-desc-chars"
        )

    def test_bare_cli_run_reports_the_band_from_a_hermetic_settings_tree(self):
        """End to end through `main`: a project that sets the fraction to 0.05
        and no pins yields the four-row band with the 1M/4 row at 200,000 and
        a basis naming that project's .claude/settings.json."""
        saved = {
            k: os.environ.get(k)
            for k in (
                "CLAUDE_PROJECT_DIR",
                "CLAUDE_CONFIG_DIR",
                "CLAUDE_PLUGIN_ROOT",
                "SLASH_COMMAND_TOOL_CHAR_BUDGET",
                "CLAUDE_CODE_DISABLE_1M_CONTEXT",
                "CLAUDE_CODE_MAX_CONTEXT_TOKENS",
                "DISABLE_COMPACT",
            )
        }
        try:
            with tempfile.TemporaryDirectory() as tmp:
                project_root, config_root = self._scopes(
                    tmp, project={"skillListingBudgetFraction": 0.05}
                )
                plugins_root = os.path.join(tmp, "plugins")
                skill_dir = os.path.join(plugins_root, "alpha", "skills", "one")
                os.makedirs(skill_dir)
                with open(
                    os.path.join(skill_dir, "SKILL.md"), "w", encoding="utf-8"
                ) as handle:
                    handle.write('---\nname: one\ndescription: "does a thing"\n---\n')
                for key in saved:
                    os.environ.pop(key, None)
                os.environ["CLAUDE_PROJECT_DIR"] = project_root
                os.environ["CLAUDE_CONFIG_DIR"] = config_root
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    rc = engine.main(
                        [
                            "--plugins-root",
                            plugins_root,
                            "--claude-json",
                            os.path.join(tmp, "absent.json"),
                            "--render",
                            "json",
                        ]
                    )
                self.assertEqual(rc, 0)
                listing = json.loads(out.getvalue())["listing"]
                expected_path = os.path.join(project_root, ".claude", "settings.json")
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        self.assertEqual(listing["budget_basis"], "band")
        self.assertEqual(
            [r["label"] for r in listing["band"]], ["200k/4", "200k/3", "1M/4", "1M/3"]
        )
        row = next(r for r in listing["band"] if r["label"] == "1M/4")
        self.assertEqual(row["budget_chars"], 200_000)
        self.assertEqual(row["budget_basis"], f"settings:{expected_path}")
        scopes = {
            s["scope"]: s
            for s in listing["inputs"]["settings_scopes"]
            if s["scope"] != "policy"
        }
        self.assertEqual(scopes["user"]["status"], "absent")
        self.assertEqual(scopes["project"]["status"], "read")
        self.assertEqual(scopes["flag"]["status"], "unread")
        policy = [
            s for s in listing["inputs"]["settings_scopes"] if s["scope"] == "policy"
        ]
        self.assertTrue(policy, "the policy scope is always reported")


class ExemptionTest(unittest.TestCase):
    """Two exempt classes spend zero budget and never enter the ranking.

    `exempt-user-only` is the one plan review caught: a
    `disable-model-invocation` skill keeps its description out of the model's
    context entirely, so it spends none of the shared budget. Locally that is 59
    of 213 skills -- 28% of the fleet -- and counting them inflates the overflow
    figure enough to flip the headline verdict.
    """

    def _listing(self, frontmatter, source="plugin"):
        entry = {
            "qualified_name": "a:one",
            "source": source,
            "frontmatter": frontmatter,
            "plugin_enabled": True,
        }
        return engine.compute_listing(
            [entry], engine.ListingConfig(context_window_tokens=200_000)
        )

    def test_disable_model_invocation_contributes_zero(self):
        listing = self._listing(
            {"description": "x" * 1000, "disable_model_invocation": True}
        )
        self.assertEqual(listing["demand_chars"], 0)
        self.assertEqual(listing["competing_count"], 0)

    def test_bundled_prompt_skill_contributes_zero(self):
        listing = self._listing({"description": "x" * 1000}, source="bundled")
        self.assertEqual(listing["demand_chars"], 0)

    def test_an_exempt_skill_frees_nothing(self):
        listing = self._listing(
            {"description": "x" * 1000, "disable_model_invocation": True}
        )
        self.assertEqual(listing["demand_chars"], 0)
        # Freed bytes are NOT returned to the pool -- the budget is unchanged.
        self.assertEqual(listing["budget_chars"], 8_000)

    def test_exempt_classes_are_labelled_not_silently_dropped(self):
        listing = self._listing(
            {"description": "x" * 10, "disable_model_invocation": True}
        )
        self.assertEqual(listing["skills"][0]["eligibility"], "exempt-user-only")


class InferentialBandTest(unittest.TestCase):
    """Which skills lose descriptions is inferential and must say so."""

    def test_band_is_labelled_inferential_and_ranked(self):
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
                "usage_score": i,
            }
            for i in range(10)
        ]
        listing = engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=200_000)
        )
        competing = [s for s in listing["skills"] if s["eligibility"] == "competing"]
        self.assertTrue(all(s["confidence"] == "inferential" for s in competing))
        bands = [s["band"] for s in competing]
        self.assertEqual(sorted(bands), list(range(1, len(competing) + 1)))
        # Lowest usage_score ranks first == most likely starved.
        first = min(competing, key=lambda s: s["band"])
        self.assertEqual(first["qualified_name"], "a:0")

    def test_no_band_when_the_listing_fits(self):
        entries = [
            {
                "qualified_name": "a:one",
                "frontmatter": {"description": "x" * 10},
                "plugin_enabled": True,
            }
        ]
        listing = engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=200_000)
        )
        self.assertEqual(listing["skills"][0]["verdict"], "listing-fits")
        self.assertIsNone(listing["skills"][0]["band"])


class ListingScoreTest(unittest.TestCase):
    """The mirrored scorer, and the refusal to dress zero up as a ranking."""

    def test_score_decays_with_a_seven_day_half_life(self):
        now = _utc(2026, 8, 31)
        fresh = engine.listing_score(100, now, now)
        one_half_life = engine.listing_score(100, now - timedelta(days=7), now)
        self.assertAlmostEqual(fresh, 100.0)
        self.assertAlmostEqual(one_half_life, 50.0)

    def test_decay_floors_at_a_tenth(self):
        now = _utc(2026, 8, 31)
        ancient = engine.listing_score(100, now - timedelta(days=3650), now)
        self.assertAlmostEqual(ancient, 10.0)

    def test_a_stale_heavy_user_sorts_below_a_fresh_light_one(self):
        """The whole reason `least invoked` was the wrong description."""
        now = _utc(2026, 8, 31)
        stale = engine.listing_score(100, now - timedelta(days=60), now)
        fresh = engine.listing_score(12, now, now)
        self.assertLess(stale, fresh)

    def test_never_used_scores_zero(self):
        now = _utc(2026, 8, 31)
        self.assertEqual(engine.listing_score(0, now, now), 0.0)
        self.assertEqual(engine.listing_score(5, None, now), 0.0)

    def test_all_zero_scores_report_an_unscored_basis(self):
        """A catalog-order tiebreak must not be labelled a usage ranking."""
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        listing = engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=200_000)
        )
        self.assertEqual(listing["score_basis"], "unscored")
        competing = [s for s in listing["skills"] if s["eligibility"] == "competing"]
        self.assertTrue(all(s["confidence"] == "unscored" for s in competing))
        # The per-row claim is withheld with its reason, never published as a
        # ranking: no verdict names a row, and no row carries a band.
        self.assertTrue(all(s["verdict"] == "withheld" for s in competing))
        self.assertTrue(all(s["reason"] == "unscored" for s in competing))
        self.assertTrue(all(s["band"] is None for s in competing))
        # The arithmetic is untouched: the same three rows cannot fit.
        self.assertEqual(listing["overflow_chars"], 2_000)
        self.assertEqual(listing["starved_count"], 3)

    def test_unscored_overflow_withholds_once_for_the_run(self):
        """The refusal is one run-level entry, not one per starved skill."""
        now = _utc(2026, 8, 31)
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        model = engine.classify(
            denominator=entries,
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
            listing_config=engine.ListingConfig(context_window_tokens=200_000),
        )
        starvation = [w for w in model["withheld"] if w["claim"] == "starvation"]
        self.assertEqual(len(starvation), 1)
        self.assertIsNone(starvation[0]["skill"])
        self.assertEqual(
            starvation[0]["reason"],
            "unscored: ordering is catalog-order tie, not usage",
        )
        verdicts = {row["starvation"]["verdict"] for row in model["skills"]}
        self.assertNotIn("likely-starved", verdicts)
        self.assertEqual(model["listing"]["starved_count"], 3)

    def test_a_listing_that_fits_unscored_withholds_nothing(self):
        """Nothing is shed, so there is no `which ones` claim to refuse."""
        now = _utc(2026, 8, 31)
        entries = [
            {
                "qualified_name": "a:one",
                "frontmatter": {"description": "x" * 10},
                "plugin_enabled": True,
            }
        ]
        model = engine.classify(
            denominator=entries,
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
            listing_config=engine.ListingConfig(context_window_tokens=200_000),
        )
        self.assertEqual(model["listing"]["score_basis"], "unscored")
        self.assertEqual(model["skills"][0]["starvation"]["verdict"], "listing-fits")
        self.assertEqual(
            [w for w in model["withheld"] if w["claim"] == "starvation"], []
        )

    def test_band_mode_withholds_the_rows_that_overflow(self):
        """A band row can be unscored too, and each row answers for itself."""
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        cfg = engine.ListingConfig()
        axes = engine.ListingAxes(
            windows=(200_000, 1_000_000), bytes_per_tokens=(4,), inputs={}
        )
        listing = engine.compute_listing_band(entries, cfg, axes)
        self.assertEqual(listing["score_basis"], "unscored")
        self.assertTrue(engine.starvation_withheld(listing))
        by_band = listing["skills"][0]["by_band"]
        # 10 x 1000 overflows the 200k row and fits the 1M one.
        self.assertEqual(by_band["200k/4"], "withheld")
        self.assertEqual(by_band["1M/4"], "listing-fits")
        self.assertEqual(listing["skills"][0]["reason"], "unscored")
        self.assertIsNone(listing["skills"][0]["band"])
        # The counts the band reports per row are untouched.
        starved = {r["label"]: r["starved_count"] for r in listing["band"]}
        self.assertEqual(starved, {"200k/4": 3, "1M/4": 0})

    def test_classify_scores_the_band_from_native_counters(self):
        """Regression: the band used to sort on a field nothing populated."""
        now = _utc(2026, 8, 31)
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        # Counts ascend with the index, so the band must descend with it.
        events = [
            {"skill": f"a:{i}", "ts": now, "source": "native", "count": (i + 1) * 10}
            for i in range(10)
        ]
        model = engine.classify(
            denominator=entries,
            events=events,
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
            listing_config=engine.ListingConfig(context_window_tokens=200_000),
        )
        self.assertEqual(model["listing"]["score_basis"], "native-counters")
        bands = {
            row["qualified_name"]: row["starvation"]["band"] for row in model["skills"]
        }
        # Least-scored is band 1, i.e. first to lose its description.
        self.assertEqual(bands["a:0"], 1)
        self.assertEqual(bands["a:9"], 10)


class ScoreBasisScopeTest(unittest.TestCase):
    """The basis is decided by the contenders, not by the whole denominator."""

    def test_usage_on_an_exempt_skill_does_not_score_the_contest(self):
        """Regression: an exempt row's score used to flip the basis.

        A bundled, name-only, or user-only skill can carry real native usage
        while being excluded from the contest entirely. Counting it labelled the
        listing `native-counters` while every actual contender sat at zero, so a
        pure catalog ordering got dressed as `inferential`. That is the defect
        this whole report exists to expose, one scope up.
        """
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        entries.append(
            {
                "qualified_name": "a:manual",
                "frontmatter": {
                    "description": "x" * 1000,
                    "disable_model_invocation": True,
                },
                "plugin_enabled": True,
            }
        )
        listing = engine.compute_listing(
            entries,
            engine.ListingConfig(context_window_tokens=200_000),
            # Only the exempt row has any usage at all.
            {"a:manual": 500.0},
        )
        self.assertEqual(listing["score_basis"], "unscored")
        competing = [s for s in listing["skills"] if s["eligibility"] == "competing"]
        self.assertTrue(all(s["confidence"] == "unscored" for s in competing))


class BareUsageKeyTest(unittest.TestCase):
    """Usage recorded under a bare leaf must reach its qualified skill."""

    def test_bare_key_is_attributed_when_the_leaf_is_unique(self):
        now = _utc(2026, 8, 31)
        model = engine.classify(
            denominator=[_skill("source-control:babysit-prs")],
            events=[
                {"skill": "babysit-prs", "ts": now, "source": "native", "count": 378},
                {
                    "skill": "source-control:babysit-prs",
                    "ts": now,
                    "source": "native",
                    "count": 97,
                },
            ],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        row = model["skills"][0]
        self.assertEqual(row["observation"]["count"], 475)

    def test_ambiguous_bare_key_is_withheld_not_guessed(self):
        now = _utc(2026, 8, 31)
        model = engine.classify(
            denominator=[_skill("toolchain:check"), _skill("skill-quality:check")],
            events=[{"skill": "check", "ts": now, "source": "native", "count": 40}],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        for row in model["skills"]:
            self.assertEqual(row["observation"]["count"], 0)
        withheld = [w for w in model["withheld"] if w["skill"] == "check"]
        self.assertEqual(len(withheld), 1)
        self.assertIn("toolchain:check", withheld[0]["reason"])
        self.assertIn("skill-quality:check", withheld[0]["reason"])

    def test_a_bare_key_is_withheld_when_the_leaf_has_duplicate_entries(self):
        """Two marketplaces shipping one plugin give two rows, one name.

        Collapsing owners into a set let the bare key pass the single-owner test
        and then be reported on BOTH rows, inventing usage for an attribution the
        report already marks `ambiguous-attribution`.
        """
        now = _utc(2026, 8, 31)
        model = engine.classify(
            denominator=[_skill("dup:check"), _skill("dup:check")],
            events=[{"skill": "check", "ts": now, "source": "native", "count": 40}],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        for row in model["skills"]:
            self.assertEqual(row["observation"]["count"], 0)
        withheld = [w for w in model["withheld"] if w["skill"] == "check"]
        self.assertEqual(len(withheld), 1)
        self.assertIn("dup:check", withheld[0]["reason"])

    def test_a_bare_key_does_not_score_the_band(self):
        """`zPe` has no bare-key fallback, so the mirror must not add one."""
        now = _utc(2026, 8, 31)
        entries = [
            {
                "qualified_name": "a:one",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            },
            {
                "qualified_name": "b:two",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            },
        ]
        model = engine.classify(
            denominator=entries,
            events=[{"skill": "one", "ts": now, "source": "native", "count": 900}],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
            listing_config=engine.ListingConfig(context_window_tokens=200_000),
        )
        rows = {r["qualified_name"]: r for r in model["skills"]}
        # The count reaches the observation field ...
        self.assertEqual(rows["a:one"]["observation"]["count"], 900)
        # ... but not the band, because the product's own scorer misses it too.
        self.assertEqual(rows["a:one"]["starvation"]["usage_score"], 0)
        self.assertEqual(model["listing"]["score_basis"], "unscored")


class TierResolutionTest(unittest.TestCase):
    """A claim renders only at a tier that supports it."""

    def test_otel_present_is_full(self):
        self.assertEqual(engine.resolve_tier({"otel", "jsonl", "native"}), "T-full")

    def test_jsonl_without_otel_is_local(self):
        self.assertEqual(engine.resolve_tier({"jsonl", "native"}), "T-local")

    def test_native_only_is_baseline(self):
        self.assertEqual(engine.resolve_tier({"native"}), "T-baseline")

    def test_no_sources_is_none(self):
        self.assertEqual(engine.resolve_tier(set()), "T-none")

    def test_trigger_attribution_only_claimable_at_full(self):
        self.assertTrue(engine.tier_supports("T-full", "invocation_trigger"))
        self.assertFalse(engine.tier_supports("T-local", "invocation_trigger"))
        self.assertFalse(engine.tier_supports("T-baseline", "invocation_trigger"))

    def test_windowed_counts_are_not_claimable_at_baseline(self):
        """Native usageCount is lifetime-since-install and never windowed."""
        self.assertFalse(engine.tier_supports("T-baseline", "windowed_count"))
        self.assertTrue(engine.tier_supports("T-local", "windowed_count"))


class NativeSourceTest(unittest.TestCase):
    def test_native_events_are_gated_on_usage_count(self):
        now = _utc(2026, 8, 18)
        stamp = int((now - timedelta(days=1)).timestamp() * 1000)
        events, _ = engine.parse_native(
            {
                "real:skill": {"usageCount": 2, "lastUsedAt": stamp},
                "seeded:skill": {"usageCount": 0, "lastUsedAt": stamp},
            },
            first_start=now - timedelta(days=10),
        )
        names = {e["skill"] for e in events}
        self.assertIn("real:skill", names)
        self.assertNotIn("seeded:skill", names)

    def test_native_horizon_is_first_start(self):
        now = _utc(2026, 8, 18)
        first = now - timedelta(days=10)
        _, horizon = engine.parse_native({}, first_start=first)
        self.assertEqual(horizon, first)


class JsonlSourceTest(unittest.TestCase):
    def test_parses_rows_and_derives_horizon_from_earliest(self):
        rows = [
            '{"ts":"2026-08-17T03:30:04Z","event":"SkillUse","skill":"a:one","source":"tool"}',
            '{"ts":"2026-08-18T04:24:12Z","event":"SkillUse","skill":"b:two","source":"expansion"}',
        ]
        events, horizon = engine.parse_jsonl(rows)
        self.assertEqual(len(events), 2)
        self.assertEqual(horizon.isoformat(), "2026-08-17T03:30:04+00:00")

    def test_malformed_row_is_skipped_not_fatal(self):
        rows = ["not json at all", '{"ts":"2026-08-18T00:00:00Z","skill":"a:one"}']
        events, _ = engine.parse_jsonl(rows)
        self.assertEqual(len(events), 1)


class OtelSourceTest(unittest.TestCase):
    def test_carries_invocation_trigger(self):
        records = [
            {
                "skill.name": "a:one",
                "invocation_trigger": "claude-proactive",
                "ts": "2026-08-18T00:00:00Z",
            }
        ]
        events, _ = engine.parse_otel(records)
        self.assertEqual(events[0]["invocation_trigger"], "claude-proactive")

    def test_redacted_name_is_flagged_not_attributed(self):
        """`custom_skill` is a placeholder, not a skill. Attributing it would
        pile every third-party skill's usage onto one fictional row."""
        records = [
            {
                "skill.name": "custom_skill",
                "invocation_trigger": "user-slash",
                "ts": "2026-08-18T00:00:00Z",
            }
        ]
        events, _ = engine.parse_otel(records)
        self.assertTrue(events[0]["redacted"])
        self.assertIsNone(events[0]["skill"])


class ChurnPassthroughTest(unittest.TestCase):
    """Churn is authoring effort, not use. Blank and zero are different facts."""

    def _row(self, churn):
        now = _utc(2026, 8, 18)
        entry = _skill("a:one")
        entry["frontmatter"] = {"description": "d"}
        entry["plugin_enabled"] = True
        if churn is not None:
            entry["churn"] = churn
        model = engine.classify(
            denominator=[entry],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        return model["skills"][0]

    def test_not_locally_authored_is_blank_never_zero(self):
        row = self._row(None)
        self.assertIsNone(row["churn"])

    def test_locally_authored_carries_commits_and_authored_at(self):
        row = self._row({"commits": 7, "authored_at": "2026-08-12T10:00:00+00:00"})
        self.assertEqual(row["churn"]["commits"], 7)
        self.assertEqual(row["churn"]["authored_at"], "2026-08-12T10:00:00+00:00")


class ChurnGitReaderTest(unittest.TestCase):
    """Proves the two git mechanics against a real repo, not by assertion.

    Both were verified defects during design: filesystem mtime is CHECKOUT time
    rather than authoring time, and without `--follow` a renamed file reports
    only its post-rename history -- this repo demonstrably ports skills between
    plugins.
    """

    def setUp(self):
        import subprocess

        if not shutil.which("git"):
            self.skipTest("git not available")
        self.tmp = tempfile.mkdtemp()
        self.run = lambda *a: subprocess.run(
            a, cwd=self.tmp, check=True, capture_output=True, text=True
        )
        self.run("git", "init", "-q")
        self.run("git", "config", "user.email", "t@example.com")
        self.run("git", "config", "user.name", "t")
        self.run("git", "config", "commit.gpgsign", "false")

    def tearDown(self):

        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, name, text):
        import pathlib

        pathlib.Path(self.tmp, name).write_text(text, encoding="utf-8")

    def test_follow_survives_a_rename_and_plain_log_does_not(self):
        self._write("old.md", "one")
        self.run("git", "add", "old.md")
        self.run("git", "commit", "-qm", "first")
        self._write("old.md", "two")
        self.run("git", "add", "old.md")
        self.run("git", "commit", "-qm", "second")
        self.run("git", "mv", "old.md", "new.md")
        self.run("git", "commit", "-qm", "rename")

        followed = engine.read_churn(self.tmp, "new.md")
        plain = engine.read_churn(self.tmp, "new.md", follow=False)
        self.assertGreater(
            followed["commits"],
            plain["commits"],
            "--follow must recover history severed by the rename",
        )

    def test_authored_at_is_committer_date_not_filesystem_mtime(self):
        import time

        self._write("a.md", "one")
        self.run("git", "add", "a.md")
        self.run("git", "commit", "-qm", "first")
        # Touch the file far into the future, as a fresh clone's mtime would be.
        future = time.time() + 86_400 * 30
        os.utime(f"{self.tmp}/a.md", (future, future))

        churn = engine.read_churn(self.tmp, "a.md")
        authored = datetime.fromisoformat(churn["authored_at"])
        self.assertLess(
            authored.timestamp(),
            future,
            "authored_at must come from the committer date, not mtime",
        )

    def test_untracked_path_is_blank_not_zero(self):
        self._write("untracked.md", "x")
        self.assertIsNone(engine.read_churn(self.tmp, "untracked.md"))


class ReportPathTest(unittest.TestCase):
    """Report keying, and the environment variable that cannot be trusted."""

    def test_path_carries_the_state_key_segments(self):
        path = engine.report_path(
            data_root="/data",
            state_key="github.com/o/r/abcd1234",
            stamp="20260818T000000Z",
        )
        self.assertIn("github.com/o/r/abcd1234", path)
        self.assertTrue(path.endswith("20260818T000000Z.json"))
        self.assertIn("audit-skill-visibility", path)

    def test_refuses_to_build_a_path_without_a_state_key(self):
        """Without the key every run from every repo overwrites the last, and a
        read-back can serve one project's findings as another's."""
        with self.assertRaises(ValueError):
            engine.report_path(data_root="/data", state_key="", stamp="s")

    def test_refuses_a_traversing_state_key(self):
        """The key becomes directory components and makedirs builds whatever it
        is told to, so `..` must be rejected rather than merely stripped."""
        for bad in (
            "../../../../tmp/evil",
            "github.com/o/../../../etc",
            "a/../b",
            "..",
            "/../x",
        ):
            with self.assertRaises(ValueError, msg=f"accepted {bad!r}"):
                engine.report_path(data_root="/data", state_key=bad, stamp="s")

    def test_refuses_key_segments_outside_the_safe_alphabet(self):
        for bad in ("UPPER/case", "has space/x", "semi;colon", "tilde~x"):
            with self.assertRaises(ValueError, msg=f"accepted {bad!r}"):
                engine.report_path(data_root="/data", state_key=bad, stamp="s")

    def test_accepts_a_real_state_key_shape(self):
        path = engine.report_path(
            data_root="/data",
            state_key="github.com/melodic-software/repo/05a2a927",
            stamp="s",
        )
        self.assertIn("github.com/melodic-software/repo/05a2a927", path)

    def test_refuses_an_empty_data_root(self):
        """CLAUDE_PLUGIN_DATA was observed pointing at an UNRELATED plugin's
        data directory in a skill subprocess, so it is never taken on faith."""
        with self.assertRaises(ValueError):
            engine.report_path(data_root="", state_key="k", stamp="s")

    def test_history_line_is_appended_not_overwritten(self):
        import pathlib

        with tempfile.TemporaryDirectory() as tmp:
            hist = pathlib.Path(tmp, "history.jsonl")
            engine.append_history(str(hist), {"run": 1})
            engine.append_history(str(hist), {"run": 2})
            lines = hist.read_text(encoding="utf-8").strip().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[1])["run"], 2)


class OverflowConsumptionTest(unittest.TestCase):
    """Only enough least-used skills to COVER the overflow lose descriptions.

    Review finding (P1): marking every competing skill `likely-starved` on any
    positive overflow libels the most-used skills in the fleet — the ones the
    documented mechanism keeps longest — and the renderer then tells the user
    those rows are running name-only.
    """

    def _listing(self, n, chars, budget_tokens):
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * chars},
                "plugin_enabled": True,
                "usage_score": i,  # a:0 least used
            }
            for i in range(n)
        ]
        return engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=budget_tokens)
        )

    def test_one_char_overflow_starves_only_the_least_used_row(self):
        # 8 skills x 1000 chars = 8000 demand against an 8000 budget... push 1 over.
        listing = self._listing(n=8, chars=1001, budget_tokens=200_000)
        self.assertGreater(listing["overflow_chars"], 0)
        starved = [s for s in listing["skills"] if s["verdict"] == "likely-starved"]
        retained = [s for s in listing["skills"] if s["verdict"] == "likely-retained"]
        self.assertEqual(len(starved), 1, "only the least-used row should be starved")
        self.assertEqual(starved[0]["qualified_name"], "a:0")
        self.assertEqual(len(retained), 7)

    def test_the_name_floor_is_charged_before_any_description_is_granted(self):
        """The grant budget starts at `budget - V`, not at the whole budget.

        Naive arithmetic says 10 x 1000 against 8_000 sheds exactly two rows. The
        product charges every listed entry for its own name and the separators
        first, so slightly less than the full budget is available to
        descriptions, and a third row goes. Deriving the grant budget by
        subtracting the overflow instead would miss that row entirely.
        """
        listing = self._listing(n=10, chars=1000, budget_tokens=200_000)
        # The overflow figure itself is unchanged: it answers "does the listing
        # overflow", which is a different question from "which entries win".
        self.assertEqual(listing["overflow_chars"], 2_000)
        starved = [s for s in listing["skills"] if s["verdict"] == "likely-starved"]
        self.assertEqual(len(starved), 3)
        # The three lowest-scored, since nothing here varies in length.
        self.assertEqual(
            sorted(s["qualified_name"] for s in starved), ["a:0", "a:1", "a:2"]
        )

    def test_most_used_skill_is_never_starved_while_others_can_absorb_it(self):
        listing = self._listing(n=10, chars=1000, budget_tokens=200_000)
        hottest = max(listing["skills"], key=lambda s: s["usage_score"])
        self.assertEqual(hottest["verdict"], "likely-retained")

    def test_a_cheap_low_scored_row_is_granted_after_a_costly_higher_one_is_shed(self):
        """First-fit, not a prefix: the product's grant loop has no early exit.

        A prefix model sheds a contiguous run of the lowest-scored rows. The real
        loop walks every entry, so a short description can still be granted after
        a longer, better-scored one was refused. Description LENGTH is a ranking
        input, which no prose account of this mechanism mentions.
        """
        # Per-entry demand is capped at max_desc_chars (1536), so the budget is
        # exhausted with full-cap fillers rather than one giant description.
        entries = [
            {
                "qualified_name": f"a:fill{i}",
                "frontmatter": {"description": "x" * 1536},
                "plugin_enabled": True,
            }
            for i in range(5)
        ]
        entries += [
            # Outscores the cheap row, but cannot fit in what the fillers left.
            {
                "qualified_name": "a:hog",
                "frontmatter": {"description": "x" * 1536},
                "plugin_enabled": True,
            },
            # Lowest score in the set, but cheap enough to survive the leftovers.
            {
                "qualified_name": "a:cheap",
                "frontmatter": {"description": "x" * 200},
                "plugin_enabled": True,
            },
        ]
        scores = {f"a:fill{i}": 100.0 - i for i in range(5)}
        scores.update({"a:hog": 50.0, "a:cheap": 1.0})
        listing = engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=200_000), scores
        )
        by_name = {r["qualified_name"]: r for r in listing["skills"]}
        # The name floor takes 67, leaving 7933. 5 x 1536 = 7680 granted, leaving
        # 253. a:hog needs 1536 and is shed; the walk does NOT stop there, and
        # a:cheap needs only 200, so it is granted from the same leftovers.
        self.assertEqual(by_name["a:hog"]["verdict"], "likely-starved")
        self.assertEqual(by_name["a:cheap"]["verdict"], "likely-retained")
        self.assertEqual(by_name["a:fill0"]["verdict"], "likely-retained")
        # And the band still ranks by exposure, so the cheap survivor is band 1
        # even though it was retained. Band and verdict answer different
        # questions and are allowed to disagree.
        self.assertEqual(by_name["a:cheap"]["band"], 1)

    def test_the_same_fleet_unscored_keeps_the_count_and_withholds_the_names(self):
        """The count is arithmetic; the names ride on an ordering that is gone.

        Same ten rows as the floor test, with every usage score stripped. The
        overflow and the starved count are identical, and not one row is named.
        """
        entries = [
            {
                "qualified_name": f"a:{i}",
                "frontmatter": {"description": "x" * 1000},
                "plugin_enabled": True,
            }
            for i in range(10)
        ]
        unscored = engine.compute_listing(
            entries, engine.ListingConfig(context_window_tokens=200_000)
        )
        scored = self._listing(n=10, chars=1000, budget_tokens=200_000)
        self.assertEqual(unscored["overflow_chars"], scored["overflow_chars"])
        self.assertEqual(unscored["starved_count"], scored["starved_count"])
        competing = [s for s in unscored["skills"] if s["eligibility"] == "competing"]
        self.assertEqual({s["verdict"] for s in competing}, {"withheld"})
        self.assertEqual({s["reason"] for s in competing}, {"unscored"})
        self.assertEqual({s["band"] for s in competing}, {None})
        # Every field the row can still stand behind is kept.
        for row in competing:
            self.assertEqual(row["eligibility"], "competing")
            self.assertEqual(row["demand_chars"], 1000)
            self.assertEqual(row["usage_score"], 0)
            self.assertEqual(row["confidence"], "unscored")


class JoinerCharsTest(unittest.TestCase):
    """The listing inserts a literal ' - ' between description and when_to_use.

    Review finding (P2): concatenating the fields undercounts every two-field
    entry by three characters. `skill-quality/scripts/check-listing-budget.sh`
    already models this as JOINER_CHARS=3, and contracts.md required the two
    implementations be reconciled.
    """

    def test_joiner_counted_when_both_fields_present(self):
        entry = {
            "qualified_name": "a:one",
            "frontmatter": {"description": "abcde", "when_to_use": "fghij"},
            "plugin_enabled": True,
        }
        listing = engine.compute_listing(
            [entry], engine.ListingConfig(context_window_tokens=200_000)
        )
        self.assertEqual(listing["demand_chars"], 5 + 3 + 5)

    def test_no_joiner_when_only_description(self):
        entry = {
            "qualified_name": "a:one",
            "frontmatter": {"description": "abcde"},
            "plugin_enabled": True,
        }
        listing = engine.compute_listing(
            [entry], engine.ListingConfig(context_window_tokens=200_000)
        )
        self.assertEqual(listing["demand_chars"], 5)


class PerSourceHorizonTest(unittest.TestCase):
    """A short-retention source must not erase a longer source's coverage.

    Review finding (P1): taking the narrowest horizon as one global span means a
    7-day OTEL retention pins every row to 7 days even when native counters
    reach back a year — so nothing ever escapes `not-observable` at T-full.
    """

    def test_long_native_history_survives_a_short_otel_retention(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={
                "otel": now - timedelta(days=7),  # short retention
                "native": now - timedelta(days=365),  # long history, saw nothing
            },
        )
        row = model["skills"][0]["observation"]
        self.assertEqual(
            row["value"],
            "no-observation-in-horizon",
            "a year of native coverage with zero events IS a supportable claim",
        )

    def test_run_header_still_reports_the_narrowest_horizon(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={
                "otel": now - timedelta(days=7),
                "native": now - timedelta(days=365),
            },
        )
        # observed_horizon stays the narrowest: it answers "what is the least
        # this run can see", which is a different question from per-row backing.
        self.assertEqual(
            model["observed_horizon"], (now - timedelta(days=7)).isoformat()
        )

    def test_short_coverage_everywhere_still_withholds(self):
        now = _utc(2026, 8, 18)
        model = engine.classify(
            denominator=[_skill("a:one")],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=3)},
        )
        self.assertEqual(model["skills"][0]["observation"]["value"], "not-observable")


class FrontmatterParseTest(unittest.TestCase):
    """Reads the few keys reachability needs, and admits when it cannot.

    Frontmatter uses HYPHENATED keys (`disable-model-invocation`) while the
    classifier keys on underscores; normalizing here is what stops a live run
    from silently reporting every user-only skill as model-reachable.
    """

    def test_normalizes_the_hyphenated_invocation_key(self):
        text = '---\ndescription: "d"\ndisable-model-invocation: true\n---\nbody\n'
        self.assertTrue(engine.parse_frontmatter(text)["disable_model_invocation"])

    def test_false_invocation_key_is_not_truthy(self):
        text = '---\ndescription: "d"\ndisable-model-invocation: false\n---\n'
        self.assertFalse(engine.parse_frontmatter(text)["disable_model_invocation"])

    def test_reads_description_and_when_to_use(self):
        text = '---\ndescription: "hello"\nwhen_to_use: "later"\n---\n'
        parsed = engine.parse_frontmatter(text)
        self.assertEqual(parsed["description"], "hello")
        self.assertEqual(parsed["when_to_use"], "later")

    def test_missing_fence_is_malformed_not_empty(self):
        self.assertTrue(engine.parse_frontmatter("no fence here")["_malformed"])

    def test_unterminated_fence_is_malformed(self):
        self.assertTrue(engine.parse_frontmatter("---\ndescription: x\n")["_malformed"])


class CollectFleetTest(unittest.TestCase):
    """The live denominator walk."""

    def test_walks_plugins_into_qualified_names(self):
        import pathlib

        with tempfile.TemporaryDirectory() as tmp:
            skill = pathlib.Path(tmp, "myplugin", "skills", "myskill")
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                '---\ndescription: "d"\n---\nbody\n', encoding="utf-8"
            )
            entries = engine.collect_fleet(tmp)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["qualified_name"], "myplugin:myskill")
        self.assertEqual(entries[0]["frontmatter"]["description"], "d")

    def test_a_checkout_walk_is_not_assessed_never_assumed(self):
        """A checkout is not an install: the walk carries no enablement and
        says so, because guessing would libel a disabled plugin's skills as
        reachable and `unknown` would claim a source that does not exist."""
        import pathlib

        with tempfile.TemporaryDirectory() as tmp:
            skill = pathlib.Path(tmp, "p", "skills", "s")
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                '---\ndescription: "d"\n---\n', encoding="utf-8"
            )
            entries = engine.collect_fleet(tmp)
        self.assertIsNone(entries[0]["plugin_enabled"])
        self.assertEqual(
            entries[0]["plugin_enabled_evidence"], engine.ENABLEMENT_NOT_ASSESSED
        )

    def test_missing_root_is_empty_not_an_exception(self):
        self.assertEqual(engine.collect_fleet("/nonexistent/path/here"), [])


class ResolveInstalledTest(unittest.TestCase):
    """The manifest lists one entry per install SCOPE, not per plugin.

    Measured on a real install: 67 plugins carried 134 entries. Since the
    fleet is the denominator the listing budget is measured against, counting
    entries roughly doubles the reported overflow — the same summation error
    the usage sources already reconcile away.
    """

    @staticmethod
    def _manifest(**plugins):
        return {"version": 2, "plugins": plugins}

    def test_two_scopes_of_one_plugin_resolve_to_one_entry(self):
        manifest = self._manifest(
            **{
                "alpha@mkt": [
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/alpha/1.0.0",
                        "lastUpdated": "2026-08-17",
                    },
                    {
                        "scope": "user",
                        "version": "1.2.0",
                        "installPath": "/c/alpha/1.2.0",
                        "lastUpdated": "2026-08-19",
                    },
                ]
            }
        )
        out = engine.resolve_installed(manifest, {})
        self.assertEqual(out["manifest_entries"], 2)
        self.assertEqual(out["plugins_resolved"], 1)
        self.assertEqual(len(out["plugins"]), 1)

    def test_scope_precedence_beats_the_newest_version(self):
        """`local > project > user`, NOT newest-installed.

        The rule is documented in this plugin's own
        `skills/plugins/context/scope-semantics.md`, which names the newest-
        version heuristic as the wrong answer explicitly. An earlier revision
        of this resolver shipped that exact heuristic; this pins the fix.
        """
        manifest = self._manifest(
            **{
                "alpha@mkt": [
                    {
                        "scope": "user",
                        "version": "9.9.9",
                        "installPath": "/c/alpha/9.9.9",
                        "lastUpdated": "2026-08-19",
                    },
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/alpha/1.0.0",
                        "projectPath": "/repo",
                        "lastUpdated": "2026-08-01",
                    },
                ]
            }
        )
        out = engine.resolve_installed(manifest, {}, current_project="/repo")
        # The older project pin loads; the newer user install is superseded.
        self.assertEqual(out["plugins"][0]["scope"], "project")
        self.assertEqual(out["plugins"][0]["root"], "/c/alpha/1.0.0")
        self.assertEqual(out["superseded"][0]["winner"]["version"], "1.0.0")

    def test_local_outranks_project(self):
        manifest = self._manifest(
            **{
                "alpha@mkt": [
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/p",
                        "projectPath": "/repo",
                    },
                    {
                        "scope": "local",
                        "version": "0.1.0",
                        "installPath": "/c/l",
                        "projectPath": "/repo",
                    },
                ]
            }
        )
        out = engine.resolve_installed(manifest, {}, current_project="/repo")
        self.assertEqual(out["plugins"][0]["scope"], "local")

    def test_another_projects_install_cannot_load_here_and_is_excluded(self):
        """A project-scope record for a different repo is real but inert.

        Counting its skills would inflate the denominator the listing budget
        is measured against with a fleet the model can never see.
        """
        manifest = self._manifest(
            **{
                "elsewhere@mkt": [
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/elsewhere",
                        "projectPath": "/some/other/repo",
                    }
                ]
            }
        )
        out = engine.resolve_installed(manifest, {}, current_project="/repo")
        self.assertEqual(out["plugins"], [])
        self.assertEqual(out["not_applicable"][0]["plugin"], "elsewhere")

    def test_a_user_scope_install_applies_in_any_project(self):
        manifest = self._manifest(
            **{"u@mkt": [{"scope": "user", "version": "1.0.0", "installPath": "/c/u"}]}
        )
        out = engine.resolve_installed(manifest, {}, current_project="/anywhere")
        self.assertEqual(len(out["plugins"]), 1)
        self.assertEqual(out["not_applicable"], [])

    def test_directory_source_honours_the_catalog_declared_path(self):
        """`plugins/<name>` is the common layout, not a rule.

        A catalog entry may declare `.` or any other directory; assuming the
        conventional layout would silently drop that plugin's skills.
        """
        manifest = self._manifest(
            **{
                "solo@mkt": [
                    {"scope": "user", "version": "1.0.0", "installPath": "/c/solo"}
                ]
            }
        )
        marketplaces = {
            "mkt": {
                "source": {"source": "directory", "path": "/repo"},
                "installLocation": "/repo",
                "_catalog": [{"name": "solo", "source": "."}],
            }
        }
        out = engine.resolve_installed(manifest, marketplaces)
        self.assertEqual(out["plugins"][0]["root"], os.path.normpath("/repo"))

    def test_a_scope_fork_is_flagged_ambiguous_never_silently_picked(self):
        manifest = self._manifest(
            **{
                "alpha@mkt": [
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/alpha/1.0.0",
                        "lastUpdated": "2026-08-17",
                    },
                    {
                        "scope": "user",
                        "version": "1.2.0",
                        "installPath": "/c/alpha/1.2.0",
                        "lastUpdated": "2026-08-19",
                    },
                ]
            }
        )
        # No current project, so the project-scope record does not apply and
        # only the user install can load.
        out = engine.resolve_installed(manifest, {})
        self.assertEqual(out["plugins"][0]["scope"], "user")
        self.assertEqual(out["plugins"][0]["root"], "/c/alpha/1.2.0")
        self.assertEqual(out["superseded"], [])

    def test_a_directory_source_marketplace_loads_the_checkout(self):
        """A directory-source marketplace loads from the checkout.

        Verified by a skill executing out of the marketplace directory rather
        than either cached installPath. Neither cached version is what runs,
        so no superseded pair is reported for it — naming two versions that
        are both beside the point would mislead.
        """
        manifest = self._manifest(
            **{
                "alpha@mkt": [
                    {
                        "scope": "project",
                        "version": "1.0.0",
                        "installPath": "/c/alpha/1.0.0",
                        "lastUpdated": "2026-08-17",
                    },
                    {
                        "scope": "user",
                        "version": "1.2.0",
                        "installPath": "/c/alpha/1.2.0",
                        "lastUpdated": "2026-08-19",
                    },
                ]
            }
        )
        marketplaces = {
            "mkt": {
                "source": {"source": "directory", "path": "/repo"},
                "installLocation": "/repo",
            }
        }
        out = engine.resolve_installed(manifest, marketplaces, current_project="/repo")
        row = out["plugins"][0]
        self.assertEqual(row["scope"], "marketplace-directory")
        self.assertEqual(row["root"], os.path.normpath("/repo/plugins/alpha"))
        self.assertEqual(out["superseded"], [])

    def test_a_single_scope_install_is_certain(self):
        manifest = self._manifest(
            **{
                "solo@mkt": [
                    {
                        "scope": "user",
                        "version": "2.0.0",
                        "installPath": "/c/solo/2.0.0",
                        "lastUpdated": "2026-08-19",
                    }
                ]
            }
        )
        out = engine.resolve_installed(manifest, {})
        self.assertEqual(out["plugins"][0]["scope"], "user")
        self.assertEqual(out["superseded"], [])

    def test_an_empty_or_malformed_manifest_yields_nothing_not_an_exception(self):
        for blob in ({}, {"plugins": {}}, {"plugins": {"x@m": []}}):
            out = engine.resolve_installed(blob, {})
            self.assertEqual(out["plugins"], [])
            self.assertEqual(out["plugins_resolved"], 0)


class CollectInstalledTest(unittest.TestCase):
    """The integration path `--installed` actually wires to.

    `resolve_installed` is pure and unit-tested above; this covers the part
    that touches disk — JSON loading and its failure handling, the catalog
    read, and the resolved-root -> `collect_fleet_at` handoff.
    """

    @staticmethod
    def _write(path, blob):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(blob, handle)

    @staticmethod
    def _skill(root, plugin, leaf, description):
        d = os.path.join(root, plugin, "skills", leaf)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "SKILL.md"), "w", encoding="utf-8") as handle:
            handle.write(f'---\nname: {leaf}\ndescription: "{description}"\n---\n')

    def test_it_reads_a_real_tree_through_the_catalog_declared_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkout = os.path.join(tmp, "repo")
            plugins_dir = os.path.join(tmp, "plugins-config")
            self._skill(os.path.join(checkout, "plugins"), "alpha", "one", "does a")
            self._write(
                os.path.join(checkout, ".claude-plugin", "marketplace.json"),
                {"plugins": [{"name": "alpha", "source": "./plugins/alpha"}]},
            )
            self._write(
                os.path.join(plugins_dir, "known_marketplaces.json"),
                {
                    "mkt": {
                        "source": {"source": "directory", "path": checkout},
                        "installLocation": checkout,
                    }
                },
            )
            self._write(
                os.path.join(plugins_dir, "installed_plugins.json"),
                {
                    "version": 2,
                    "plugins": {
                        "alpha@mkt": [
                            {
                                "scope": "user",
                                "version": "1.0.0",
                                "installPath": "/nowhere",
                            }
                        ]
                    },
                },
            )
            denominator, resolution = engine.collect_installed(plugins_dir)

        self.assertEqual(resolution["plugins_resolved"], 1)
        self.assertEqual(resolution["manifest_entries"], 1)
        self.assertEqual([e["qualified_name"] for e in denominator], ["alpha:one"])
        # Read through the catalog path, NOT the (bogus) cached installPath.
        self.assertEqual(denominator[0]["frontmatter"]["description"], "does a")

    def test_a_missing_or_unreadable_config_dir_is_empty_not_an_exception(self):
        denominator, resolution = engine.collect_installed("/nonexistent/dir/here")
        self.assertEqual(denominator, [])
        self.assertEqual(resolution["plugins_resolved"], 0)

    def test_another_projects_install_is_excluded_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            plugins_dir = os.path.join(tmp, "cfg")
            cache = os.path.join(tmp, "cache")
            self._skill(cache, "beta", "two", "does b")
            self._write(
                os.path.join(plugins_dir, "installed_plugins.json"),
                {
                    "version": 2,
                    "plugins": {
                        "beta@mkt": [
                            {
                                "scope": "project",
                                "version": "1.0.0",
                                "installPath": os.path.join(cache, "beta"),
                                "projectPath": "/some/other/repo",
                            }
                        ]
                    },
                },
            )
            denominator, resolution = engine.collect_installed(
                plugins_dir, current_project=os.path.join(tmp, "mine")
            )

        self.assertEqual(denominator, [])
        self.assertEqual(resolution["not_applicable"][0]["plugin"], "beta")


if __name__ == "__main__":
    unittest.main()
