"""session.py holds the shared interview session's domain rules; each test names one invariant.

Expected values come from the Design's Contracts (state shape, error codes, round transitions,
limits) and the Brief's acceptance criteria, never from running the code under test.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent
FIXTURES = HERE / "fixtures"
if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))

import session  # noqa: E402  (the module lives one directory up; sys.path is set just above)

HOST = "host"
PNG = "0123456789abcdef.png"
HTML = "fedcba9876543210.html"


class Clock:
    def __init__(self, t=1_760_600_000.0):
        self.t = t

    def __call__(self):
        return self.t

    def tick(self, seconds=2.0):
        self.t += seconds


class Ids:
    """Deterministic stand-in for secrets: every token and hex string is unique and predictable."""

    def __init__(self):
        self.n = 0

    def token(self, nbytes):
        self.n += 1
        return f"tok{self.n:04d}x{nbytes}"

    def hex(self, nbytes):
        self.n += 1
        return f"{self.n:0{nbytes * 2}x}"


def text_q(qid, *, depends=(), purpose="decide", scope_kind="person", rec=True, **extra):
    q = {
        "id": qid,
        "text": f"Question {qid}?",
        "alternatives": [],
        "dependsOn": list(depends),
        "purpose": purpose,
        "format": {"kind": "text"},
        "answerScope": scope_kind,
    }
    if rec:
        q["recommendation"] = f"Recommended for {qid}."
        q["alternatives"] = [
            {"key": "a", "text": f"Alternative A for {qid}."},
            {"key": "b", "text": f"Alternative B for {qid}."},
        ]
    q.update(extra)
    return q


def choice_q(qid, *, purpose="poll", labels=("Card", "Saved method", "None")):
    return {
        "id": qid,
        "text": f"Pick for {qid}?",
        "alternatives": [],
        "dependsOn": [],
        "purpose": purpose,
        "format": {
            "kind": "choice",
            "options": [{"id": f"opt-{i}", "label": label} for i, label in enumerate(labels, 1)],
        },
    }


class SessionCase(unittest.TestCase):
    """A fresh session in a temp folder, written with full schema validation on every write."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        (self.tmp / "assets").mkdir()
        for name in (PNG, HTML, "1111222233334444.png", "aaaabbbbccccdddd.webp"):
            (self.tmp / "assets" / name).write_bytes(b"x")
        self.path = self.tmp / "state.json"
        self.clock = Clock()
        self.ids = Ids()
        self.s, self.owner_token = session.Session.create(
            self.path,
            title="Checkout redesign",
            goal="Agree the payment step",
            owner_name="Kim",
            plugin_version="9.9.9",
            clock=self.clock,
            ids=self.ids,
            validate_writes=True,
        )

    # -- helpers -----------------------------------------------------------------------------

    def join(self, name, **body):
        self.clock.tick()
        out = self.s.join(None, {"name": name, "device": "computer", **body})
        return out["pid"], out["secret"]

    def people(self, *names):
        return [self.join(n)[0] for n in names]

    def apply(self, *ops):
        self.clock.tick()
        return self.s.apply({"ops": list(ops)})

    def open_round(self, *questions, placements=None):
        op = {"op": "open-round", "questions": list(questions)}
        if placements is not None:
            op["placements"] = placements
        return self.apply(op)

    def send(self):
        self.clock.tick()
        return self.s.send_round(HOST, {})

    def ack(self, n):
        return self.apply({"op": "ack-round", "round": n})

    def act(self, method, pid, body):
        self.clock.tick()
        return getattr(self.s, method)(pid, body)

    def refused(self, code, method, pid, body, http=None):
        self.clock.tick()
        with self.assertRaises(session.DomainError) as ctx:
            getattr(self.s, method)(pid, body)
        self.assertEqual(ctx.exception.code, code, ctx.exception.message)
        if http is not None:
            self.assertEqual(ctx.exception.http, http)
        return ctx.exception

    def refused_ops(self, code, *ops):
        self.clock.tick()
        with self.assertRaises(session.DomainError) as ctx:
            self.s.apply({"ops": list(ops)})
        self.assertEqual(ctx.exception.code, code, ctx.exception.message)
        return ctx.exception

    def disk(self):
        return json.loads(self.path.read_text(encoding="utf-8"))

    def question(self, qid):
        return next(q for q in self.s.state["questions"] if q["id"] == qid)

    def round_status(self, n=None):
        rounds = self.s.state["rounds"]
        r = rounds[-1] if n is None else rounds[n - 1]
        return r["status"]["kind"]

    def events(self, kind=None):
        evs = self.s.state["log"]["events"]
        return [e for e in evs if kind is None or e["kind"] == kind]

    def notes(self, pid, kind=None):
        return [n for n in self.s.state["notifications"].get(pid, []) if kind is None or n["kind"] == kind]


# ---------------------------------------------------------------------------------------------
# Item 1: load, validate, atomic write, rev, seq, migration hook, state-invalid
# ---------------------------------------------------------------------------------------------


class TestPersistence(SessionCase):
    def test_create_writes_a_schema_valid_file_with_version_and_rev_zero(self):
        doc = self.disk()
        self.assertEqual(doc["schemaVersion"], 1)
        self.assertEqual(doc["rev"], 0)
        self.assertEqual(doc["pluginVersion"], "9.9.9")
        self.assertEqual(doc["people"][HOST]["role"], "owner")
        self.assertEqual(doc["people"][HOST]["name"], "Kim")
        self.assertIsNone(session.state_error(doc))

    def test_owner_token_is_stored_only_as_its_sha256(self):
        raw = self.path.read_text(encoding="utf-8")
        self.assertNotIn(self.owner_token, raw)
        self.assertEqual(
            self.disk()["credentials"]["owner"]["tokenHash"],
            session.hashlib.sha256(self.owner_token.encode()).hexdigest(),
        )

    def test_each_persisted_change_adds_one_to_rev(self):
        self.join("Ann")
        self.assertEqual(self.disk()["rev"], 1)
        self.act("set_title", HOST, {"title": "New title"})
        self.assertEqual(self.disk()["rev"], 2)

    def test_heartbeat_is_memory_only_and_leaves_rev(self):
        ann, _ = self.join("Ann")
        self.act("heartbeat", ann, {"q": "", "typing": True, "chatTyping": False})
        self.assertEqual(self.disk()["rev"], 1)

    def test_a_refused_write_changes_neither_memory_nor_disk(self):
        before = self.path.read_bytes()
        self.refused("too-long", "set_title", HOST, {"title": "x" * 81})
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(self.s.state["session"]["title"], "Checkout redesign")

    def test_state_invalid_writes_nothing_and_rolls_back(self):
        before = self.path.read_bytes()

        def corrupt(st):
            st["session"]["title"] = "x" * 81

        with self.assertRaises(session.DomainError) as ctx:
            self.s._mutate(corrupt)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (500, "state-invalid"))
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(self.s.state["session"]["title"], "Checkout redesign")

    @unittest.skipIf(os.name == "nt", "POSIX file modes")
    def test_state_file_is_private_0600(self):
        self.join("Ann")
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_write_leaves_no_temp_file_behind(self):
        self.join("Ann")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["assets", "state.json"])

    def test_load_round_trips_the_written_state(self):
        ann, secret = self.join("Ann")
        again = session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual(again.state, self.s.state)
        self.assertEqual(again.resolve(secret=secret), ann)

    def test_load_refuses_a_schema_invalid_file(self):
        doc = self.disk()
        doc["people"][HOST]["role"] = "emperor"
        self.path.write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaises(session.DomainError) as ctx:
            session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual(ctx.exception.code, "state-invalid")

    def test_load_accepts_the_full_v1_fixture(self):
        shutil.copy(FIXTURES / "state-v1.json", self.path)
        s = session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual(s.state["rev"], 42)

    def test_load_refuses_a_newer_schema_naming_both_versions(self):
        doc = self.disk()
        doc["schemaVersion"] = 2
        self.path.write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaises(session.migrate.MigrationError) as ctx:
            session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertIn("schemaVersion 2", str(ctx.exception))
        self.assertIn("newer than 1", str(ctx.exception))

    def test_migration_copies_the_old_file_once_then_writes_the_migrated_state(self):
        original = self.path.read_bytes()

        def step(doc):
            return {**doc, "writtenBy": "migrated"}

        with (
            mock.patch.object(session.migrate, "CURRENT", 2),
            mock.patch.dict(session.migrate.MIGRATIONS, {1: step}),
            mock.patch.object(session, "state_error", return_value=None),
        ):
            s = session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual((self.tmp / "state.v1.json").read_bytes(), original)
        self.assertEqual(s.state["writtenBy"], "migrated")
        self.assertEqual(self.disk()["schemaVersion"], 2)

    def test_a_failed_migration_leaves_the_original_file(self):
        original = self.path.read_bytes()

        def step(doc):
            raise session.migrate.MigrationError("step 1 to 2 failed")

        with (
            mock.patch.object(session.migrate, "CURRENT", 2),
            mock.patch.dict(session.migrate.MIGRATIONS, {1: step}),
            self.assertRaises(session.migrate.MigrationError),
        ):
            session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual(self.path.read_bytes(), original)

    def test_counters_never_reuse_an_id(self):
        ann, _ = self.join("Ann")
        first = self.act("propose", ann, {"text": "Ask about refunds."})["id"]
        self.act("act_on_proposal", HOST, {"id": first, "action": "park"})
        second = self.act("propose", ann, {"text": "Ask about taxes."})["id"]
        self.assertEqual((first, second), ("P1", "P2"))
        self.assertEqual(self.s.state["session"]["seq"]["P"], 2)

    def test_create_refuses_to_overwrite_an_existing_session(self):
        with self.assertRaises(FileExistsError):
            session.Session.create(self.path, title="Again", clock=self.clock, ids=self.ids)

    def test_defaults_set_the_initial_settings(self):
        path = self.tmp / "other.json"
        s, _ = session.Session.create(
            path, title="T", settings={"uploads": True, "names": "initials"}, clock=self.clock, ids=self.ids
        )
        self.assertTrue(s.state["session"]["settings"]["uploads"])
        self.assertEqual(s.state["session"]["settings"]["names"], "initials")
        self.assertTrue(s.state["session"]["settings"]["voting"])


# ---------------------------------------------------------------------------------------------
# Item 2: people and identity
# ---------------------------------------------------------------------------------------------


class TestJoin(SessionCase):
    def test_join_returns_a_pid_and_secret_and_stores_only_the_secrets_sha256(self):
        pid, secret = self.join("Ann")
        raw = self.path.read_text(encoding="utf-8")
        self.assertNotIn(secret, raw)
        self.assertEqual(self.disk()["credentials"]["secrets"], {session.sha256(secret): pid})
        self.assertEqual(self.s.resolve(secret=secret), pid)

    def test_a_joiner_is_a_guest_untrusted_and_active(self):
        pid, _ = self.join("Ann")
        p = self.s.state["people"][pid]
        self.assertEqual((p["role"], p["trusted"], p["status"]), ("guest", False, {"kind": "active"}))

    def test_blank_name_becomes_guest_n(self):
        self.join("Ann")
        pid, _ = self.join("   ")
        self.assertEqual(self.s.state["people"][pid]["name"], "Guest 2")

    def test_names_are_trimmed_and_refused_over_40_never_cut(self):
        pid, _ = self.join("  Ann  ")
        self.assertEqual(self.s.state["people"][pid]["name"], "Ann")
        err = self.refused("too-long", "join", None, {"name": "x" * 41})
        self.assertEqual(err.details, {"field": "name", "max": 40})
        self.join("y" * 40)

    def test_names_are_unique_case_folded(self):
        self.join("Ann")
        pid, _ = self.join("ANN")
        self.assertEqual(self.s.state["people"][pid]["name"], "ANN 2")

    def test_a_name_matching_an_offline_person_offers_was(self):
        ann, _ = self.join("Ann")
        self.s._presence.clear()
        out = self.s.join(None, {"name": "ann"})
        self.assertEqual(out["was"], {"pid": ann, "name": "Ann"})

    def test_joiners_get_the_first_unused_color(self):
        a, b = self.people("Ann", "Bo")
        colors = [self.s.state["people"][p]["color"] for p in (HOST, a, b)]
        self.assertEqual(colors, ["c1", "c2", "c3"])

    def test_join_is_refused_after_the_session_ends(self):
        self.act("end_session", HOST, {"on": True})
        err = self.refused("ended", "join", None, {"name": "Ann"})
        self.assertEqual(err.http, 403)

    def test_join_needs_the_current_guest_key_once_one_was_issued(self):
        key = self.act("rotate_guest_link", HOST, {})["guestKey"]
        self.refused("bad-guest-key", "join", None, {"name": "Ann"}, http=403)
        self.refused("bad-guest-key", "join", None, {"name": "Ann", "key": "old"}, http=403)
        self.assertTrue(self.s.join(None, {"name": "Ann", "key": key})["pid"])

    def test_join_rate_is_limited_per_address(self):
        for i in range(session.JOINS_PER_WINDOW):
            self.s.join(None, {"name": f"P{i}"}, address="203.0.113.7")
        with self.assertRaises(session.DomainError) as ctx:
            self.s.join(None, {"name": "Late"}, address="203.0.113.7")
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "join-rate"))
        self.s.join(None, {"name": "Elsewhere"}, address="198.51.100.2")
        self.clock.tick(session.JOIN_WINDOW)
        self.s.join(None, {"name": "Later"}, address="203.0.113.7")

    def test_a_full_session_forgets_an_idle_person_or_refuses(self):
        with mock.patch.object(session, "MAX_PEOPLE", 3):
            idle, _ = self.join("Idle")
            busy, _ = self.join("Busy")
            self.act("propose", busy, {"text": "Something"})
            self.s._presence.clear()
            newcomer, _ = self.join("New")
            self.assertNotIn(idle, self.s.state["people"])
            self.act("propose", newcomer, {"text": "Mine"})
            self.s._presence.clear()
            err = self.refused("full", "join", None, {"name": "One more"})
            self.assertEqual(err.http, 503)

    def test_owner_join_keeps_pid_host_and_sets_the_name(self):
        out = self.s.join(HOST, {"name": "Kimberly"})
        self.assertEqual(out, {"pid": HOST, "name": "Kimberly"})
        self.assertNotIn("secret", out)


class TestIdentity(SessionCase):
    def test_owner_token_resolves_to_host_and_a_wrong_one_is_refused(self):
        self.assertEqual(self.s.resolve(owner_token=self.owner_token), HOST)
        with self.assertRaises(session.DomainError) as ctx:
            self.s.resolve(owner_token="forged")
        self.assertEqual((ctx.exception.http, ctx.exception.code), (401, "unknown-session"))

    def test_an_unknown_secret_is_refused(self):
        with self.assertRaises(session.DomainError) as ctx:
            self.s.resolve(secret="made-up")
        self.assertEqual(ctx.exception.code, "unknown-session")

    def test_removal_disables_the_secret_and_restore_brings_it_back(self):
        ann, secret = self.join("Ann")
        self.act("set_removed", HOST, {"pid": ann, "on": True})
        with self.assertRaises(session.DomainError) as ctx:
            self.s.resolve(secret=secret)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (403, "removed"))
        self.refused("removed", "propose", ann, {"text": "Still here?"})
        self.act("set_removed", HOST, {"pid": ann, "on": False})
        self.assertEqual(self.s.resolve(secret=secret), ann)

    def test_a_forged_pid_is_refused(self):
        self.refused("unknown-session", "propose", "not-a-person", {"text": "Hi"}, http=401)

    def test_a_guest_cannot_act_as_the_owner_or_a_moderator(self):
        ann, _ = self.join("Ann")
        self.refused("owner-only", "set_title", ann, {"title": "Mine now"}, http=403)
        self.refused("owner-only", "set_role", ann, {"pid": ann, "role": "leader"}, http=403)
        self.refused("moderator-only", "unlock", ann, {"qid": "Q1"}, http=403)

    def test_rotating_the_owner_link_retires_the_old_token(self):
        new = self.act("rotate_owner_link", HOST, {})["token"]
        self.assertEqual(self.s.resolve(owner_token=new), HOST)
        with self.assertRaises(session.DomainError):
            self.s.resolve(owner_token=self.owner_token)

    def test_rotating_the_guest_link_never_returns_the_key_to_empty(self):
        first = self.act("rotate_guest_link", HOST, {})["guestKey"]
        second = self.act("rotate_guest_link", HOST, {})["guestKey"]
        self.assertTrue(first and second and first != second)


class TestRolesAndPeople(SessionCase):
    def test_owner_makes_and_unmakes_a_leader_who_is_notified(self):
        ann, _ = self.join("Ann")
        self.act("set_role", HOST, {"pid": ann, "role": "leader"})
        self.assertEqual(self.s.state["people"][ann]["role"], "leader")
        self.assertEqual([n["kind"] for n in self.notes(ann)], ["role"])
        self.act("set_role", HOST, {"pid": ann, "role": "guest"})
        self.assertEqual(self.s.state["people"][ann]["role"], "guest")

    def test_the_owner_role_cannot_be_granted_or_taken(self):
        ann, _ = self.join("Ann")
        self.refused("bad-field", "set_role", HOST, {"pid": ann, "role": "owner"})
        self.refused("bad-field", "set_role", HOST, {"pid": HOST, "role": "guest"})

    def test_removing_a_person_clears_leader_and_trust(self):
        ann, _ = self.join("Ann")
        self.act("set_role", HOST, {"pid": ann, "role": "leader"})
        self.act("set_trust", HOST, {"pid": ann, "on": True})
        self.act("set_removed", HOST, {"pid": ann, "on": True})
        p = self.s.state["people"][ann]
        self.assertEqual((p["role"], p["trusted"], p["status"]["kind"]), ("guest", False, "removed"))
        self.act("set_removed", HOST, {"pid": ann, "on": False})
        self.assertEqual(self.s.state["people"][ann]["role"], "guest")

    def test_the_owner_cannot_be_removed(self):
        self.refused("bad-field", "set_removed", HOST, {"pid": HOST, "on": True})

    def test_rename_is_one_write_and_keeps_names_unique(self):
        ann, bo = self.people("Ann", "Bo")
        self.assertEqual(self.act("rename", bo, {"name": "ann"})["name"], "ann 2")
        self.refused("empty", "rename", bo, {"name": "  "})
        self.refused("too-long", "rename", bo, {"name": "z" * 41})

    def test_color_takes_one_of_c1_to_c10(self):
        ann, _ = self.join("Ann")
        self.assertEqual(self.act("set_color", ann, {"color": "c7"})["color"], "c7")
        self.refused("bad-field", "set_color", ann, {"color": "c11"})

    def test_about_you_is_stored_for_the_person(self):
        ann, _ = self.join("Ann")
        self.act("set_about_you", ann, {"techComfort": "low", "note": "Prefers phone"})
        self.assertEqual(self.s.state["aboutYou"][ann]["techComfort"], "low")
        self.refused("too-long", "set_about_you", ann, {"techComfort": "ok", "note": "n" * 201})


class TestMerge(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.ann_secret = self.join("Ann")
        self.bo, _ = self.join("Bo")
        self.old, self.old_secret = self.join("Old Ann")
        self.open_round(text_q("Q1"), text_q("Q2"))

    def test_merge_moves_answers_votes_and_secret_and_forgets_the_merged_person(self):
        self.act("answer", self.old, {"qid": "Q1", "text": "Old answer", "view": "focus"})
        self.act("vote", self.old, {"qid": "Q2", "card": "c:rec", "on": True})
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.old}", "on": True})
        self.act("merge_people", HOST, {"from": self.old, "to": self.ann})
        st = self.s.state
        self.assertNotIn(self.old, st["people"])
        self.assertEqual([c["pid"] for c in st["cards"]["Q1"] if c["kind"] == "person"], [self.ann])
        self.assertEqual(st["votes"]["Q1"][self.bo], f"p:{self.ann}")
        self.assertEqual(st["votes"]["Q2"][self.ann], "c:rec")
        self.assertEqual(self.s.resolve(secret=self.old_secret), self.ann)

    def test_merge_keeps_the_kept_persons_prefs_and_color_and_fills_unset_prefs(self):
        self.act("set_prefs", self.ann, {"set": {"theme": "dark"}})
        self.act("set_prefs", self.old, {"set": {"theme": "light", "sort": "votes"}})
        self.act("set_color", self.old, {"color": "c9"})
        color = self.s.state["people"][self.ann]["color"]
        self.act("merge_people", HOST, {"from": self.old, "to": self.ann})
        prefs = self.s.state["prefs"][self.ann]
        self.assertEqual((prefs["theme"]["value"], prefs["sort"]["value"]), ("dark", "votes"))
        self.assertEqual(self.s.state["people"][self.ann]["color"], color)

    def test_merge_drops_a_vote_that_would_be_for_ones_own_card(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "Ann's", "view": "focus"})
        self.act("vote", self.old, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("merge_people", HOST, {"from": self.old, "to": self.ann})
        self.assertNotIn(self.ann, self.s.state["votes"]["Q1"])

    def test_merge_refuses_the_owner_and_one_person_twice(self):
        self.refused("bad-field", "merge_people", HOST, {"from": HOST, "to": self.ann})
        self.refused("bad-field", "merge_people", HOST, {"from": self.ann, "to": self.ann})

    def test_merge_request_is_one_pending_per_person_and_never_to_self_or_host(self):
        out = self.act("request_merge", self.old, {"to": self.ann})
        self.assertEqual(out["id"], "G1")
        self.refused("wrong-status", "request_merge", self.old, {"to": self.bo}, http=409)
        self.refused("bad-field", "request_merge", self.bo, {"to": self.bo})
        self.refused("bad-field", "request_merge", self.bo, {"to": HOST})
        self.assertEqual([n["kind"] for n in self.notes(HOST, "queue")], ["queue"])

    def test_approving_a_merge_request_merges_and_notifies(self):
        mid = self.act("request_merge", self.old, {"to": self.ann})["id"]
        self.assertEqual(self.act("act_on_merge_request", HOST, {"id": mid, "action": "approve"})["status"], "approved")
        self.assertNotIn(self.old, self.s.state["people"])
        self.assertEqual([n["kind"] for n in self.notes(self.ann, "merge")], ["merge"])

    def test_a_merge_request_whose_person_is_gone_is_declined_as_gone(self):
        mid = self.act("request_merge", self.old, {"to": self.ann})["id"]
        self.act("set_removed", HOST, {"pid": self.ann, "on": True})
        self.assertEqual(self.act("act_on_merge_request", HOST, {"id": mid, "action": "approve"})["status"], "declined")
        self.assertEqual(self.s.state["mergeRequests"][0]["status"]["why"], "gone")
        self.assertIn(self.old, self.s.state["people"])


# ---------------------------------------------------------------------------------------------
# Item 3: rounds, the transition table, read-only rules, late answers
# ---------------------------------------------------------------------------------------------


class TestRounds(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})

    def test_the_first_open_round_opens_round_1(self):
        out = self.open_round(text_q("Q1"))
        self.assertEqual(out["results"][0]["round"], 1)
        self.assertEqual(self.round_status(), "open")

    def test_open_round_is_refused_while_a_round_is_open_or_sent(self):
        self.open_round(text_q("Q1"))
        self.refused_ops("wrong-status", {"op": "open-round", "questions": [text_q("Q2")]})
        self.send()
        self.refused_ops("wrong-status", {"op": "open-round", "questions": [text_q("Q2")]})

    def test_a_leader_marks_ready_and_only_the_owner_sends(self):
        self.open_round(text_q("Q1"))
        self.act("ready_round", self.ann, {"on": True})
        self.assertEqual(self.s.state["rounds"][0]["status"]["ready"]["by"], self.ann)
        self.refused("moderator-only", "ready_round", self.bo, {"on": True})
        self.refused("owner-only", "send_round", self.ann, {})
        self.send()
        self.assertEqual(self.round_status(), "sent")

    def test_send_writes_round_sent_with_the_digest_and_records_its_seq(self):
        self.open_round(text_q("Q1"))
        self.send()
        (ev,) = self.events("round-sent")
        self.assertEqual(ev["round"], 1)
        self.assertEqual(ev["digest"]["round"], 1)
        self.assertEqual(self.s.state["rounds"][0]["status"]["eventSeq"], ev["seq"])

    def test_owner_cancel_returns_a_sent_round_to_open_and_writes_round_cancelled(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.act("cancel_round", HOST, {})
        self.assertEqual(self.round_status(), "open")
        (ev,) = self.events("round-cancelled")
        self.assertEqual(ev["sentSeq"], self.events("round-sent")[0]["seq"])

    def test_cancel_is_refused_once_claude_is_working(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.assertEqual(self.round_status(), "working")
        self.refused("wrong-status", "cancel_round", HOST, {}, http=409)

    def test_ack_needs_the_matching_round_number(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.refused_ops("wrong-status", {"op": "ack-round", "round": 2})

    def test_ack_is_refused_unless_the_round_was_sent(self):
        self.open_round(text_q("Q1"))
        self.refused_ops("wrong-status", {"op": "ack-round", "round": 1})

    def test_open_round_from_working_closes_it_and_opens_the_next(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.open_round(text_q("Q2"))
        r1, r2 = self.s.state["rounds"]
        self.assertEqual((r1["status"]["kind"], r1["status"]["next"]), ("closed", 2))
        self.assertEqual((r2["n"], r2["status"]["kind"]), (2, "open"))
        self.assertEqual(self.question("Q2")["round"], 2)

    def test_close_round_ends_a_working_round_with_no_next(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.apply({"op": "close-round", "reason": "final reply"})
        self.assertEqual(self.s.state["rounds"][0]["status"]["next"], None)
        self.assertEqual(self.round_status(), "closed")

    def test_owner_reset_is_the_exit_from_working(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.refused("owner-only", "reset_round", self.ann, {})
        self.act("reset_round", HOST, {})
        self.assertEqual(self.round_status(), "open")

    def test_reset_is_refused_outside_working(self):
        self.open_round(text_q("Q1"))
        self.refused("wrong-status", "reset_round", HOST, {})

    def test_at_most_one_round_is_open_sent_or_working(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.open_round(text_q("Q2"))
        active = [r for r in self.s.state["rounds"] if r["status"]["kind"] != "closed"]
        self.assertEqual(len(active), 1)

    def test_a_sent_or_working_round_is_read_only_except_suggest(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.bo, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.send()
        for status in ("sent", "working"):
            if status == "working":
                self.ack(1)
            self.refused("round-sent", "answer", self.ann, {"qid": "Q1", "text": "Too late", "view": "focus"}, http=409)
            self.refused("round-sent", "vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True})
            self.refused("round-sent", "go_with", self.ann, {"qid": "Q1", "card": "c:rec"})
            self.refused("round-sent", "lock", HOST, {"qid": "Q1", "card": "c:rec"})
            self.act("suggest", self.ann, {"qid": "Q1", "text": f"Change while {status}"})
        self.assertEqual(len(self.s.state["suggestions"]["Q1"]), 2)

    def test_late_answers_on_closed_rounds_are_marked_late(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.open_round(text_q("Q2"))
        self.act("answer", self.bo, {"qid": "Q1", "text": "Late thought", "view": "tree"})
        (card,) = [c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual(card["late"], {"round": 1})

    def test_a_locked_question_of_a_closed_round_takes_no_late_answer(self):
        self.open_round(text_q("Q1"))
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.send()
        self.ack(1)
        self.open_round(text_q("Q2"))
        self.refused("locked", "answer", self.bo, {"qid": "Q1", "text": "Late", "view": "focus"})

    def test_ready_notifies_the_other_moderators(self):
        self.open_round(text_q("Q1"))
        self.act("ready_round", self.ann, {"on": True})
        self.assertEqual([n["kind"] for n in self.notes(HOST, "ready")], ["ready"])
        self.assertEqual(self.notes(self.ann, "ready"), [])

    def test_new_round_notifies_everyone(self):
        self.open_round(text_q("Q1"))
        self.assertEqual([n["title"] for n in self.notes(self.bo, "round")], ["Round 1 is here."])


if __name__ == "__main__":
    unittest.main()
