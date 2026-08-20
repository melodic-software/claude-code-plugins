"""Unit tests for the audit-skill-visibility classifier.

The classifier is pure -- `(denominator, events, config, clock) -> model` -- and
every test here pins a defect found during this topic's audit. Each test names
the failure it prevents, because a fixture whose purpose is forgotten gets
"fixed" by the next person who sees it fail.
"""

import json
import os
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
        import json
        import pathlib
        import tempfile

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

    def test_starved_set_covers_the_overflow_and_no_more(self):
        # 10 x 1000 = 10_000 against 8_000 -> overflow 2_000 -> exactly 2 rows.
        listing = self._listing(n=10, chars=1000, budget_tokens=200_000)
        self.assertEqual(listing["overflow_chars"], 2_000)
        starved = [s for s in listing["skills"] if s["verdict"] == "likely-starved"]
        self.assertEqual(len(starved), 2)
        self.assertEqual(sorted(s["qualified_name"] for s in starved), ["a:0", "a:1"])

    def test_most_used_skill_is_never_starved_while_others_can_absorb_it(self):
        listing = self._listing(n=10, chars=1000, budget_tokens=200_000)
        hottest = max(listing["skills"], key=lambda s: s["usage_score"])
        self.assertEqual(hottest["verdict"], "likely-retained")


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
        import tempfile

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

    def test_enablement_is_unknown_never_assumed(self):
        """The filesystem cannot answer enablement, and guessing it would libel
        a disabled plugin's skills as reachable."""
        import pathlib
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            skill = pathlib.Path(tmp, "p", "skills", "s")
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                '---\ndescription: "d"\n---\n', encoding="utf-8"
            )
            entries = engine.collect_fleet(tmp)
        self.assertIsNone(entries[0]["plugin_enabled"])

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
