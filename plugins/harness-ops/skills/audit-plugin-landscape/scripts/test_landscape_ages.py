"""Tests for landscape_ages.py using recorded gh api responses; no network."""

import contextlib
import io
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

import landscape_ages as la

FIX = json.loads((Path(__file__).parent / "fixtures" / "gh-responses.json").read_text())
TODAY = date(2026, 10, 18)


def recorded(endpoint):
    rec = FIX.get(endpoint)
    return (rec["status"], rec["body"]) if rec else (404, "not recorded")


KNOWN = {
    "mk": {"source": {"source": "github", "repo": "acme/mk"}},
    "old": {"source": {"source": "github", "repo": "acme/old"}},
    "gone": {"source": {"source": "github", "repo": "acme/gone"}},
    "local": {"source": {"source": "directory", "path": "/x"}},
}
MANIFESTS = {
    "mk": {"plugins": [
        {"name": "fresh", "source": "./plugins/fresh"},
        {"name": "aging", "source": "./plugins/aging"},
        {"name": "boundary", "source": "./plugins/boundary"},
        {"name": "vanished", "source": "./plugins/vanished"},
    ]},
}
INSTALLED = {"plugins": {f"{n}@mk": [{}] for n in ("fresh", "aging", "boundary", "vanished")}}


class Ages(unittest.TestCase):
    def setUp(self):
        self.out = {r["id"]: r for r in la.run(INSTALLED, KNOWN, MANIFESTS, recorded, TODAY)}

    def test_fresh_plugin_has_no_flags(self):
        r = self.out["fresh@mk"]
        self.assertEqual((r["last_commit"], r["age_days"], r["flags"]), ("2026-10-10", 8, []))

    def test_stale_at_sixty_days_but_not_at_fifty_nine(self):
        self.assertEqual(self.out["boundary@mk"]["age_days"], 60)
        self.assertIn("stale", self.out["boundary@mk"]["flags"])
        self.assertEqual(self.out["aging@mk"]["age_days"], 59)
        self.assertNotIn("stale", self.out["aging@mk"]["flags"])

    def test_missing_source_path(self):
        self.assertEqual(self.out["vanished@mk"]["flags"], ["path-missing"])

    def test_archived_repository(self):
        r = self.out["old"]
        self.assertEqual(r["kind"], "marketplace")
        self.assertIn("archived", r["flags"])
        self.assertIn("stale", r["flags"])

    def test_moved_repository(self):
        r = self.out["gone"]
        self.assertIn("moved", r["flags"])
        self.assertEqual(r["moved_to"], "acme/gone-renamed")

    def test_missing_repository(self):
        row = {"kind": "marketplace", "id": "x", "repo": "acme/deleted", "path": la.MARKETPLACE_MANIFEST}
        res = la.evaluate(row, la.fetch_all([row], recorded), TODAY)
        self.assertEqual(res["flags"], ["repo-missing"])

    def test_non_github_source_is_unknown_not_flagged(self):
        r = self.out["local"]
        self.assertEqual(r["flags"], [])
        self.assertIsNotNone(r["unknown"])

    def test_plugin_root_prefixes_bare_source(self):
        manifests = {"mk": {"metadata": {"pluginRoot": "./plugins"}, "plugins": [{"name": "fresh", "source": "fresh"}]}}
        rows = la.build_rows({"plugins": {"fresh@mk": [{}]}}, KNOWN, manifests)
        self.assertEqual(rows[-1]["path"], "plugins/fresh")

    def test_non_github_plugin_source_is_unknown(self):
        manifests = {"mk": {"plugins": [{"name": "n", "source": {"source": "npm", "package": "n"}}]}}
        res = la.run({"plugins": {"n@mk": [{}]}}, KNOWN, manifests, recorded, TODAY)[-1]
        self.assertEqual((res["last_commit"], res["flags"]), (None, []))
        self.assertIn("not a GitHub", res["unknown"])

    def test_plugin_missing_from_manifest_is_unknown_not_marketplace_age(self):
        res = la.run({"plugins": {"ghost@mk": [{}]}}, KNOWN, MANIFESTS, recorded, TODAY)[-1]
        self.assertIsNone(res["last_commit"])
        self.assertIn("not listed", res["unknown"])

    def test_api_failure_is_unknown_not_a_flag(self):
        res = la.run(INSTALLED, {"mk": KNOWN["mk"]}, MANIFESTS, lambda e: (403, "rate limited"), TODAY)
        self.assertTrue(all(r["flags"] == [] and r["unknown"] for r in res))

    def test_each_endpoint_fetched_once(self):
        calls = []
        la.run(INSTALLED, KNOWN, MANIFESTS, lambda e: calls.append(e) or recorded(e), TODAY)
        self.assertEqual(len(calls), len(set(calls)))
        self.assertEqual(calls.count("repos/acme/mk"), 1)


class MainExitCodes(unittest.TestCase):
    def run_main(self, api):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mk = root / "mk"
            (mk / ".claude-plugin").mkdir(parents=True)
            (mk / la.MARKETPLACE_MANIFEST).write_text(json.dumps(MANIFESTS["mk"]))
            (root / "installed_plugins.json").write_text(json.dumps(INSTALLED))
            known = {"mk": {**KNOWN["mk"], "installLocation": str(mk)}}
            (root / "known_marketplaces.json").write_text(json.dumps(known))
            out, err = io.StringIO(), io.StringIO()
            with mock.patch.object(la, "gh_api", api), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = la.main(["--plugins-dir", tmp, "--today", TODAY.isoformat()])
        return code, out.getvalue(), err.getvalue()

    def test_total_outage_exits_three_with_empty_stdout(self):
        code, out, err = self.run_main(lambda e: (0, "gh: not logged in"))
        self.assertEqual(code, 3)
        self.assertEqual(out, "")
        self.assertIn("no repository could be checked", err)

    def test_partial_outage_still_reports_and_exits_zero(self):
        def api(endpoint):
            return recorded(endpoint) if endpoint == "repos/acme/mk" else (0, "offline")

        code, out, _ = self.run_main(api)
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(out))

    def test_all_repositories_answering_exits_zero(self):
        code, out, _ = self.run_main(recorded)
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(out))


if __name__ == "__main__":
    unittest.main()
