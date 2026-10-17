"""migrate.py brings a session file to the current schemaVersion and refuses one it cannot read."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import sys
import unittest
from pathlib import Path
from unittest import mock

from support import call, tmpdir

SHARED = Path(__file__).resolve().parent.parent
FIXTURES = Path(__file__).resolve().parent / "fixtures"
if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))
# Appended, as session.py does: prepended, surface/test_server.py would shadow ours at discovery.
if str(SHARED.parent / "surface") not in sys.path:
    sys.path.append(str(SHARED.parent / "surface"))

import migrate  # noqa: E402  (sys.path is set just above)
import schema  # noqa: E402  (sys.path is set just above)
import server  # noqa: E402  (sys.path is set just above)
import session  # noqa: E402  (sys.path is set just above)

STATE = schema.load("state", SHARED / "schema")


class TestChain(unittest.TestCase):
    def test_every_versions_fixture_migrates_to_a_valid_current_document(self):
        for version in range(1, migrate.CURRENT + 1):
            doc = json.loads((FIXTURES / f"state-v{version}.json").read_text(encoding="utf-8"))
            self.assertEqual(doc["schemaVersion"], version)
            out = migrate.migrate(doc)
            self.assertEqual(out["schemaVersion"], migrate.CURRENT)
            self.assertIsNone(schema.first_error(out, STATE), f"state-v{version}.json")

    def test_the_v1_chain_is_the_identity_while_v1_is_current(self):
        doc = json.loads((FIXTURES / "state-v1.json").read_text(encoding="utf-8"))
        self.assertEqual(migrate.CURRENT, 1)
        self.assertEqual(migrate.migrate(doc), doc)


class TestMigrate(unittest.TestCase):
    def test_current_version_comes_back_unchanged(self):
        doc = {"schemaVersion": 1, "rev": 3}
        self.assertEqual(migrate.migrate(doc), {"schemaVersion": 1, "rev": 3})

    def test_newer_version_is_refused_naming_both_versions(self):
        with self.assertRaises(migrate.MigrationError) as ctx:
            migrate.migrate({"schemaVersion": 2})
        self.assertIn("schemaVersion 2", str(ctx.exception))
        self.assertIn("newer than 1", str(ctx.exception))

    def test_missing_or_non_integer_version_is_refused(self):
        for doc in (
            {},
            {"schemaVersion": "1"},
            {"schemaVersion": True},
            {"schemaVersion": 0},
        ):
            with self.assertRaises(migrate.MigrationError):
                migrate.migrate(doc)

    def test_steps_run_in_order_and_stamp_each_version_without_touching_the_input(self):
        steps = {
            1: lambda d, ctx: {**d, "trail": d.get("trail", []) + ["1to2"]},
            2: lambda d, ctx: {**d, "trail": d["trail"] + ["2to3"]},
        }
        doc = {"schemaVersion": 1}
        with (
            mock.patch.object(migrate, "CURRENT", 3),
            mock.patch.dict(migrate.MIGRATIONS, steps),
        ):
            out = migrate.migrate(doc)
        self.assertEqual(out, {"schemaVersion": 3, "trail": ["1to2", "2to3"]})
        self.assertEqual(doc, {"schemaVersion": 1})

    def test_a_gap_in_the_chain_is_refused(self):
        with (
            mock.patch.object(migrate, "CURRENT", 2),
            self.assertRaises(migrate.MigrationError) as ctx,
        ):
            migrate.migrate({"schemaVersion": 1})
        self.assertIn("no migration from schemaVersion 1 to 2", str(ctx.exception))


PROTO = FIXTURES / "state-v0-prototype.json"
NOW = 5000.0
ANN, BO, CY, DEE = "pidAnn001", "pidBo0002", "pidCy0003", "pidOld0004"
SECRET = {
    ANN: "fixture-guest-secret-ann-not-a-real-secret-000",
    BO: "fixture-guest-secret-bo-not-a-real-secret-0000",
    CY: "fixture-guest-secret-cy-not-a-real-secret-0000",
}
HOST_SECRET = "fixture-host-session-secret-not-a-real-one-000"  # the fixture's secret the prototype mapped to "host"
OWNER_TOKEN = "fixture-owner-token-0001"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16


class TestFromPrototype(unittest.TestCase):
    """0 -> 1 on a synthetic prototype state (made-up names and secrets). Each expected value is
    read off the fixture and mapped by hand per PLAN Phase 3b item 1 and the Design's Contracts."""

    @classmethod
    def setUpClass(cls):
        cls.raw = PROTO.read_text(encoding="utf-8")
        cls.notes = []
        cls.doc = migrate.migrate(json.loads(cls.raw), cls.notes, NOW)

    def q(self, qid):
        return next(q for q in self.doc["questions"] if q["id"] == qid)

    def test_a_file_without_schema_version_is_version_0_only_with_the_prototype_keys(self):
        self.assertEqual(migrate.version_of(json.loads(self.raw)), 0)
        with self.assertRaises(migrate.MigrationError):
            migrate.migrate({"title": "x", "people": {}})

    def test_the_result_is_a_valid_version_1_document(self):
        self.assertEqual(self.doc["schemaVersion"], 1)
        self.assertIsNone(schema.first_error(self.doc, STATE))

    def test_people_keep_their_pid_name_and_standing(self):
        people = self.doc["people"]
        self.assertEqual({p: v["name"] for p, v in people.items()}, {"host": "Hana Host", ANN: "Ann Example", BO: "Bo Sample", CY: "Cy Removed", DEE: "Dee Former"})
        self.assertEqual((people["host"]["role"], people[ANN]["role"], people[BO]["role"]), ("owner", "leader", "guest"))
        self.assertEqual((people[ANN]["trusted"], people[BO]["trusted"]), (False, True))
        self.assertEqual(people[CY]["status"], {"kind": "removed", "at": NOW, "by": "host"})
        self.assertEqual(people[ANN]["joinedAt"], 1010.0)

    def test_guest_secrets_are_kept_as_the_sha256_of_the_browser_secret(self):
        hashed = {hashlib.sha256(s.encode()).hexdigest(): p for p, s in SECRET.items()}
        self.assertEqual(self.doc["credentials"]["secrets"], hashed)  # the secret for a pid with no record is dropped
        self.assertNotIn(SECRET[ANN], json.dumps(self.doc))

    def test_the_owner_token_is_kept_as_its_hash_rotated_at_import_time(self):
        self.assertEqual(self.doc["credentials"]["owner"], {"tokenHash": hashlib.sha256(OWNER_TOKEN.encode()).hexdigest(), "rotatedAt": NOW})
        self.assertNotIn(OWNER_TOKEN, json.dumps(self.doc))

    def test_questions_keep_text_round_options_dependencies_and_claude_cards(self):
        q1 = self.q("Q1")
        self.assertEqual((q1["text"], q1["round"], q1["recommendation"], q1["basis"]), ("How many columns should the payment step use?", 1, "Two columns", "Checked against: the existing grid"))
        self.assertEqual(q1["alternatives"], [{"key": "a", "text": "One column"}, {"key": "b", "text": "Three columns"}])
        self.assertEqual(q1["references"], [{"kind": "image", "asset": "0123456789abcdef.png", "caption": "Today's layout"}])
        self.assertEqual(q1["lockedText"], "Use a two-column layout")
        q2 = self.q("Q2")
        self.assertEqual(q2["format"], {"kind": "choice", "options": [{"id": "opt-1", "label": "Tabs"}, {"id": "opt-2", "label": "Accordion"}]})
        self.assertEqual(q2["dependsOn"], ["Q1"])
        self.assertEqual(q2["needsReview"], [{"because": "Q1", "at": 1550.0, "why": {"kind": "lock-changed"}}])
        self.assertEqual(self.q("Q3")["origin"], {"kind": "host", "proposal": "P1", "by": "host"})
        self.assertEqual(self.q("Q4")["origin"], {"kind": "proposal", "proposal": "P2"})

    def test_answers_picks_and_votes_keep_who_wrote_and_who_voted(self):
        cards = self.doc["cards"]
        self.assertEqual([card_key(c) for c in cards["Q1"]], ["c:rec", "c:a", "c:b", f"p:{ANN}", "p:host"])
        ann = cards["Q1"][3]
        self.assertEqual((ann["text"], ann["at"], ann["cites"], ann["editedAfterVotes"], ann["view"]), ("Use a two-column layout", 1200.0, ["X1"], 1, "compare"))
        self.assertEqual([card_key(c) for c in cards["Q2"]], ["o:opt-1", "o:opt-2", f"p:{ANN}"])
        self.assertEqual(cards["Q2"][2]["pick"], "opt-1")
        self.assertEqual(self.doc["votes"], {"Q1": {BO: "c:rec", "host": f"p:{ANN}"}, "Q2": {ANN: "o:opt-1"}, "Q4": {ANN: f"p:{BO}"}})

    def test_locks_and_suggestions(self):
        self.assertEqual(self.doc["locks"]["Q1"], {"at": 1500.0, "by": "host", "source": {"kind": "card", "card": f"p:{ANN}", "text": "Use a two-column layout"}})
        self.assertEqual(self.doc["suggestions"]["Q1"], [{"id": "S1", "pid": BO, "text": "Two columns with a sidebar", "note": "Room for filters", "at": 1600.0, "status": {"kind": "open"}}])
        self.assertEqual(self.doc["suggestionVotes"], {"Q1": {ANN: "S1"}})

    def test_ideas_become_proposals_with_their_placements(self):
        got = {p["id"]: (p["pid"], p["text"], p["status"], p["via"]) for p in self.doc["proposals"]}
        self.assertEqual(
            got,
            {
                "P1": (BO, "Should we add a dark theme?", {"kind": "question", "question": "Q3"}, {"kind": "direct"}),
                "P2": (ANN, "Offline mode", {"kind": "question", "question": "Q4"}, {"kind": "direct"}),
                "P3": (BO, "Bigger buttons", {"kind": "later", "reason": "Off this session's goal"}, {"kind": "chat", "message": "M2", "by": ANN}),
            },
        )

    def test_chat_keeps_replies_and_the_proposal_a_message_became(self):
        chat = {m["id"]: m for m in self.doc["chat"]}
        self.assertEqual(chat["M1"], {"id": "M1", "pid": ANN, "text": "Hello all", "at": 1050.0})
        self.assertEqual(chat["M2"]["replyTo"], {"id": "M1", "pid": ANN, "excerpt": "Hello all"})
        self.assertEqual(chat["M2"]["proposed"], "P3")
        self.assertEqual(chat["M3"]["pid"], DEE)  # a writer the prototype no longer listed becomes a person again

    def test_requests_and_research_become_published_results(self):
        reqs = {r["id"]: r for r in self.doc["requests"]}
        self.assertEqual(reqs["R1"]["status"], {"kind": "done", "at": 1180.0, "result": "X1"})
        self.assertEqual((reqs["R2"]["status"], reqs["R2"]["edited"], reqs["R2"]["kind"], reqs["R2"]["runner"]), ({"kind": "pending"}, True, "ask", "host"))
        x1 = self.doc["results"]["Q1"][0]
        self.assertEqual((x1["id"], x1["request"], x1["published"], x1["summary"]), ("X1", "R1", True, "Two columns test well."))
        self.assertEqual(x1["used"], [{"name": "/discovery:research", "type": "skill"}])
        self.assertEqual(x1["sources"], [{"title": "A made-up study", "url": "https://example.org/study"}])

    def test_prefs_notifications_and_merge_requests(self):
        self.assertEqual(self.doc["prefs"], {ANN: {"sort": {"value": "votes", "at": 1210.0}}})
        n1, n2 = self.doc["notifications"][ANN]
        self.assertEqual(n1["rollup"], {"key": "votes:Q1", "since": 1240.0, "n": 2})
        self.assertEqual((n2["by"], n2["msg"], n2["read"]), (BO, "M2", True))
        self.assertEqual(self.doc["mergeRequests"], [{"id": "G1", "from": BO, "to": ANN, "at": 2000.0, "status": {"kind": "declined", "at": 2000.0, "why": "host"}}])

    def test_session_title_goal_settings_share_and_counters(self):
        s = self.doc["session"]
        self.assertEqual((s["title"], s["goal"], s["guestKey"]), ("Fixture checkout session", "Pick the payment step layout", "fixture-guest-key-1"))
        self.assertEqual(s["share"], {"url": "https://fixture-quiet-lake.trycloudflare.com"})
        self.assertEqual(s["phase"], {"kind": "live"})
        st = s["settings"]
        self.assertEqual((st["names"], st["claudeTake"], st["digestNames"], st["theme"]), ("initials", "always", True, {"mode": "dark", "accent": "violet"}))
        self.assertEqual(s["seq"], {"P": 3, "S": 1, "R": 2, "X": 1, "M": 3, "G": 1, "U": 0, "N": 2, "A": 0})

    def test_rounds_up_to_the_current_one_which_stays_open(self):
        rounds = self.doc["rounds"]
        self.assertEqual([(r["n"], r["status"]["kind"]) for r in rounds], [(1, "closed"), (2, "open")])
        self.assertEqual(rounds[1]["status"]["ready"], {"by": ANN, "at": 2500.0})

    def test_a_round_sent_to_claude_opens_again(self):
        doc = json.loads(self.raw)
        doc["round"] = {"current": 2, "status": "sent", "sentAt": 2800.0}
        notes = []
        out = migrate.migrate(doc, notes, NOW)
        self.assertEqual(out["rounds"][-1]["status"], {"kind": "open"})
        self.assertTrue(any("send it once more" in n for n in notes))

    def test_fields_with_no_counterpart_are_noted_by_name_never_by_value(self):
        for name in ("state.legacyWidget", "settings.legacyToggle", "questions.legacyHint", "answers.att", "answers.ctx.browser", "prefs.legacyPref"):
            self.assertTrue(any(f" {name} " in n for n in self.notes), name)
        text = "\n".join(self.notes)
        for value in ("made-up field", "MadeUpBrowser", "example.org/offline", '"up"', OWNER_TOKEN, *SECRET.values()):
            self.assertNotIn(value, text)

    def test_a_secret_the_prototype_mapped_to_the_host_is_dropped_and_counted(self):
        self.assertNotIn(hashlib.sha256(HOST_SECRET.encode()).hexdigest(), self.doc["credentials"]["secrets"])
        self.assertNotIn("host", self.doc["credentials"]["secrets"].values())
        self.assertIn("import: 1 session secrets held by the host were dropped; the owner link carries owner identity", self.notes)

    def test_a_secret_naming_no_person_is_counted(self):
        self.assertIn("import: 1 session secrets name no person; dropped", self.notes)

    def notes_for(self, change):
        doc = json.loads(self.raw)
        change(doc)
        notes = []
        out = migrate.migrate(doc, notes, NOW)
        self.assertIsNone(session.document_error(out))
        return out, notes

    def test_fields_the_prototype_kept_that_have_no_counterpart_are_noted(self):
        _, notes = self.notes_for(lambda d: d["round"].update(sentAt=2600.0, ackAt=2610.0))
        for name in ("research.ask", "research.askedAt", "research.by", "research.byCid", "questions.byHost", "round.sentAt", "round.ackAt"):
            self.assertIn(f"import: {name} has no counterpart in schemaVersion 1; dropped", notes)

    def test_records_naming_no_known_question_or_person_are_counted_per_collection(self):
        def change(d):
            d["answers"]["Q9"] = {ANN: {"name": "Ann Example", "text": "x", "ts": 1.0, "votes": []}}
            d["answers"]["Q1"][""] = {"name": "Nobody", "text": "x", "ts": 1.0, "votes": []}
            d["suggestions"]["Q9"] = [{"id": "S9", "cid": ANN, "text": "x", "ts": 1.0, "status": "open"}]
            d["suggestions"]["Q1"].append({"id": "S8", "text": "no author", "ts": 1.0, "status": "open"})
            d["locks"]["Q9"] = {"by": "Hana Host", "text": "x", "ts": 1.0}
            d["chat"].append({"id": "M9", "text": "no author", "ts": 1.0})
            d["ideas"].append({"id": "I9", "text": "no author", "ts": 1.0, "status": "new"})
            d["research"]["Q9"] = [{"id": "X9", "summary": "x", "ts": 1.0}]
            d["requests"].append({"id": "R9", "qid": "Q9", "cid": ANN, "text": "x", "ts": 1.0, "status": "pending"})
            d["mergeRequests"].append({"id": "G9", "from": "pidNobody", "to": ANN, "ts": 1.0, "status": "pending"})
            d["prefs"]["pidNobody"] = {"sort": {"value": "votes", "ts": 1.0}}
            d["notifications"]["pidNobody"] = [{"id": "N9", "kind": "reply", "title": "x", "ts": 1.0}]

        _, notes = self.notes_for(change)
        counts = {"answers": 2, "suggestions": 2, "locks": 1, "chat": 1, "ideas": 1, "research": 1, "requests": 1, "mergeRequests": 1, "prefs": 1, "notifications": 1}
        for collection, n in counts.items():
            self.assertIn(f"import: {n} {collection} records named no known question or person, or had no id; dropped", notes)

    def test_links_and_asset_names_a_write_route_refuses_are_dropped_and_noted(self):
        def change(d):
            q1, q2 = d["questions"][0], d["questions"][1]
            q1["references"] += [
                {"kind": "link", "url": "javascript:alert(1)", "title": "Bad link"},
                {"kind": "quote", "text": "Quoted", "source": "Someone", "url": "file:///etc/passwd"},
                {"kind": "image", "asset": "../../outside.png"},
            ]
            q2["options"][0]["image"] = "../outside.png"
            d["questions"].append({"id": "Q5", "text": "Is this right?", "round": 2, "format": "confirm", "image": "outside.svg", "rect": {"x": 0, "y": 0, "w": 1, "h": 1}})
            d["research"]["Q1"][0]["sources"].append({"title": "Bad source", "url": "ftp://example.org/x"})
            d["shareUrl"] = "javascript:void(0)"

        out, notes = self.notes_for(change)
        q = {x["id"]: x for x in out["questions"]}
        self.assertEqual(q["Q1"]["references"], [{"kind": "image", "asset": "0123456789abcdef.png", "caption": "Today's layout"}, {"kind": "quote", "text": "Quoted", "source": "Someone"}])
        self.assertEqual(q["Q2"]["format"]["options"][0], {"id": "opt-1", "label": "Tabs"})
        self.assertEqual(q["Q5"]["format"], {"kind": "text"})
        self.assertEqual(out["results"]["Q1"][0]["sources"], [{"title": "A made-up study", "url": "https://example.org/study"}])
        self.assertEqual(out["session"]["share"], {"url": ""})
        for field, what in (
            ("questions.references.url", "an http(s) link"),
            ("questions.references.asset", "an image asset name"),
            ("questions.options.image", "an image asset name"),
            ("questions.image", "an image asset name"),
            ("research.sources.url", "an http(s) link"),
            ("shareUrl", "an http(s) link"),
        ):
            self.assertIn(f"import: {field} is not {what}; dropped", notes)
        text = "\n".join(notes)
        for value in ("javascript", "passwd", "outside", "ftp:"):
            self.assertNotIn(value, text)

    def test_the_input_is_left_as_it_was(self):
        doc = json.loads(self.raw)
        migrate.migrate(doc, None, NOW)
        self.assertEqual(doc, json.loads(self.raw))

    def test_a_second_migration_of_the_result_changes_nothing(self):
        self.assertEqual(migrate.migrate(self.doc), self.doc)


def card_key(c):
    return {"person": lambda: f"p:{c['pid']}", "claude": lambda: f"c:{c['key']}", "option": lambda: f"o:{c['option']}"}[c["kind"]]()


class TestImportedSession(unittest.TestCase):
    """End to end: the server creates a session from the prototype fixture and serves it on loopback."""

    def setUp(self):
        self.src = tmpdir(self) / "proto"
        (self.src / "assets").mkdir(parents=True)
        (self.src / "assets" / "0123456789abcdef.png").write_bytes(PNG)
        self.state_file = self.src / "state-9999.json"
        shutil.copy(PROTO, self.state_file)
        self.d = tmpdir(self) / "po"
        self.app = self.start(initial_state=self.state_file)

    def start(self, **kw):
        app = server.App(self.d, watch_tunnel=False, **kw)
        app.serve()
        self.addCleanup(app.shutdown)
        return app

    def get_state(self, headers):
        return call(self.app.guest_port, "GET", "/api/state?since=0", headers=headers)

    def log_text(self):
        for h in self.app.log.handlers:
            h.flush()
        return (self.d / "server.log").read_text(encoding="utf-8")

    def test_v0_guest_secret_resolves_to_same_pid(self):
        code, _, snap = self.get_state({"X-Session-Secret": SECRET[ANN]})
        self.assertEqual(code, 200, snap)
        self.assertEqual((snap["me"]["pid"], snap["me"]["name"], snap["me"]["role"]), (ANN, "Ann Example", "leader"))
        code, _, out = call(self.app.guest_port, "POST", "/api/answer", {"qid": "Q4", "text": "Me too", "device": "computer", "view": "focus"}, {"X-Session-Secret": SECRET[BO]})
        self.assertEqual(code, 200, out)
        self.assertEqual(out["card"], f"p:{BO}")

    def test_the_fixture_owner_token_opens_the_owner_view_and_survives_a_restart(self):
        code, _, snap = self.get_state({"X-Owner-Token": OWNER_TOKEN})
        self.assertEqual((code, snap["me"]["pid"], snap["me"]["role"]), (200, "host", "owner"))
        self.assertIn("requests", snap)  # owner-only
        self.app.shutdown()
        self.app = self.start()
        self.assertEqual(self.get_state({"X-Owner-Token": OWNER_TOKEN})[2]["me"]["role"], "owner")

    def test_a_secret_the_prototype_mapped_to_the_host_does_not_resolve(self):
        code, _, out = self.get_state({"X-Session-Secret": HOST_SECRET})
        self.assertEqual((code, out["error"]), (401, "unknown-session"))
        self.assertIn("1 session secrets held by the host were dropped", self.log_text())

    def test_a_removed_persons_secret_reads_nothing(self):
        code, _, out = self.get_state({"X-Session-Secret": SECRET[CY]})
        self.assertEqual((code, out["error"]), (403, "removed"))

    def test_the_original_is_kept_as_state_v0_json(self):
        kept = self.d / "state.v0.json"
        self.assertEqual(kept.read_text(encoding="utf-8"), PROTO.read_text(encoding="utf-8"))
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(kept.stat().st_mode), 0o600)

    def test_the_assets_its_questions_show_are_copied(self):
        self.assertEqual((self.d / "assets" / "0123456789abcdef.png").read_bytes(), PNG)
        code, _, body = call(self.app.guest_port, "GET", "/assets/0123456789abcdef.png")
        self.assertEqual((code, body), (200, PNG))

    def test_unknown_fields_are_logged_by_name_and_no_value_or_secret_reaches_the_log(self):
        log = self.log_text()
        for name in ("state.legacyWidget", "settings.legacyToggle", "questions.legacyHint", "answers.att", "prefs.legacyPref"):
            self.assertIn(name, log)
        for value in ("made-up field", "MadeUpBrowser", OWNER_TOKEN, HOST_SECRET, *SECRET.values()):
            self.assertNotIn(value, log)

    def test_a_second_start_with_the_import_keeps_the_session_it_made(self):
        call(self.app.guest_port, "POST", "/api/answer", {"qid": "Q4", "text": "Changed my mind", "device": "computer", "view": "focus"}, {"X-Session-Secret": SECRET[BO]})
        self.app.shutdown()
        self.app = self.start(initial_state=self.state_file)
        cards = self.get_state({"X-Session-Secret": SECRET[BO]})[2]["cards"]["Q4"]
        self.assertEqual([c["text"] for c in cards if c["kind"] == "person"], ["Changed my mind"])


class TestLoadRefuses(unittest.TestCase):
    """Every load runs the cross-field rules, so no path brings back what the import drops."""

    def load(self, change):
        doc = json.loads((FIXTURES / "state-v1.json").read_text(encoding="utf-8"))
        change(doc)
        path = tmpdir(self) / "state.json"
        path.write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaises(session.DomainError) as ctx:
            session.Session.load(path)
        self.assertEqual(ctx.exception.code, "state-invalid")
        return ctx.exception.message

    def test_a_state_whose_session_secret_names_the_owner_is_refused(self):
        def change(doc):
            doc["credentials"]["secrets"][hashlib.sha256(HOST_SECRET.encode()).hexdigest()] = "host"

        self.assertIn("names the owner", self.load(change))

    def test_a_state_with_a_link_that_is_not_http_is_refused(self):
        def change(doc):
            next(q for q in doc["questions"] if q["id"] == "Q2")["references"][0]["url"] = "javascript:alert(1)"

        self.assertIn("questions[Q2].references.url", self.load(change))

    def test_a_state_with_an_asset_name_outside_the_assets_folder_is_refused(self):
        def change(doc):
            next(q for q in doc["questions"] if q["id"] == "Q1")["references"][0]["asset"] = "../../outside.png"

        self.assertIn("questions[Q1].references.asset", self.load(change))

    def test_the_v1_fixture_loads(self):
        path = tmpdir(self) / "state.json"
        shutil.copy(FIXTURES / "state-v1.json", path)
        self.assertEqual(session.Session.load(path).state["schemaVersion"], 1)


if __name__ == "__main__":
    unittest.main()
