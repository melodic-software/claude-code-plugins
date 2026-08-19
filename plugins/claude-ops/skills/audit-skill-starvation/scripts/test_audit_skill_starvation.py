"""Unit tests for the audit-skill-starvation classifier.

The classifier is pure -- `(denominator, events, config, clock) -> model` -- and
every test here pins a defect found during this topic's audit. Each test names
the failure it prevents, because a fixture whose purpose is forgotten gets
"fixed" by the next person who sees it fail.
"""

import unittest
from datetime import datetime, timedelta, timezone

import audit_skill_starvation as engine


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

    def test_skill_overrides_off_is_hidden(self):
        reach = self._row(description="d", skill_override="off")
        self.assertEqual(reach["value"], "hidden")

    def test_disabled_plugin_is_hidden(self):
        reach = self._row(description="d", _plugin_enabled=False)
        self.assertEqual(reach["value"], "hidden")

    def test_undetermined_enablement_is_unknown_never_guessed(self):
        now = _utc(2026, 8, 18)
        entry = _skill("a:one")
        entry["frontmatter"] = {"description": "d"}
        entry["plugin_enabled"] = None  # genuinely undetermined
        model = engine.classify(
            denominator=[entry],
            events=[],
            config=engine.Config(),
            clock=now,
            horizons={"native": now - timedelta(days=400)},
        )
        self.assertEqual(model["skills"][0]["reachability"]["value"], "unknown")


class ReachabilityFixtureTest(unittest.TestCase):
    """Exact counts against a fixture of known composition.

    Deliberately not a live-machine assertion: the denominator is the operator's
    enabled fleet, which differs per machine, so a live count cannot tell a
    regression from a smaller install.
    """

    def test_four_skill_fixture_resolves_one_of_each(self):
        import json
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


class ExemptionTest(unittest.TestCase):
    """Three exempt classes spend zero budget and never enter the ranking.

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

    def test_name_only_override_contributes_zero_and_frees_nothing(self):
        listing = self._listing(
            {"description": "x" * 1000, "skill_override": "name-only"}
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
        import shutil
        import subprocess
        import tempfile

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
        import shutil

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
        import os
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


if __name__ == "__main__":
    unittest.main()
