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


if __name__ == "__main__":
    unittest.main()
