"""session.py holds the shared interview session's domain rules; each test names one invariant.

Expected values come from the Design's Contracts (state shape, error codes, round transitions,
limits) and the Brief's acceptance criteria, never from running the code under test.
"""

from __future__ import annotations

import collections
import json
import os
import shutil
import stat
import sys
import tempfile
import threading
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


def options_q(qid, kind, labels, *, purpose="decide"):
    return {
        "id": qid,
        "text": f"Pick for {qid}?",
        "alternatives": [],
        "dependsOn": [],
        "purpose": purpose,
        "format": {"kind": kind, "options": [{"id": f"opt-{i}", "label": label} for i, label in enumerate(labels, 1)]},
    }


def scale_q(qid, *, purpose="poll", top=5):
    labels = {"min": "Never", "max": "Always", "mid": "Sometimes"}
    return {"id": qid, "text": f"How often, {qid}?", "alternatives": [], "dependsOn": [], "purpose": purpose, "format": {"kind": "scale", "min": 1, "max": top, "labels": labels}}


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

        def step(doc, ctx):
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

        def step(doc, ctx):
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

    def test_was_never_reveals_a_name_the_session_hides(self):
        self.join("Ann")
        for names in ("initials", "someone"):
            with self.subTest(names=names):
                self.act("update_settings", HOST, {"names": names})
                self.s._presence.clear()
                self.assertNotIn("was", self.s.join(None, {"name": "ann"}))

    def test_rotated_addresses_cannot_pass_the_join_limit_for_one_guest_key(self):
        self.assertGreater(session.JOINS_PER_KEY, session.JOINS_PER_WINDOW)
        for i in range(session.JOINS_PER_KEY):
            self.clock.tick(1)
            self.s.join(None, {"name": f"P{i}"}, address=f"198.51.100.{i}")
        err = self.refused("join-rate", "join", None, {"name": "One more"})
        self.assertEqual(err.http, 429)
        with self.assertRaises(session.DomainError):
            self.s.join(None, {"name": "Fresh address"}, address="203.0.113.250")
        key = self.act("rotate_guest_link", HOST, {})["guestKey"]
        self.assertTrue(self.s.join(None, {"name": "New link", "key": key}, address="203.0.113.251")["pid"])

    def test_join_records_are_forgotten_once_their_window_passes(self):
        for i in range(50):
            self.s.join(None, {"name": f"P{i}"}, address=f"198.51.100.{i}")
        self.clock.tick(session.JOIN_KEY_WINDOW)
        self.s.join(None, {"name": "Later"}, address="203.0.113.9")
        self.assertEqual(list(self.s._joins), [("", "203.0.113.9")])
        self.assertEqual(len(self.s._key_joins[""]), 1)

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

    def test_a_pid_from_the_snapshot_sent_as_the_secret_is_refused(self):
        ann, _ = self.join("Ann")
        pids = [p["pid"] for p in self.s.snapshot(ann)["people"]]
        self.assertIn(ann, pids)
        for pid in pids:
            with self.assertRaises(session.DomainError) as ctx:
                self.s.resolve(secret=pid)
            self.assertEqual((ctx.exception.http, ctx.exception.code), (401, "unknown-session"))

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

    def test_a_body_naming_a_leaders_pid_grants_nothing(self):
        leader, _ = self.join("Lee")
        guest, _ = self.join("Gus")
        self.act("set_role", HOST, {"pid": leader, "role": "leader"})
        self.open_round(text_q("Q1"))
        for body in ({"qid": "Q1", "card": "c:rec", "pid": leader}, {"qid": "Q1", "card": "c:rec", "pid": HOST, "by": leader}):
            self.refused("moderator-only", "lock", guest, body, http=403)
        self.act("answer", guest, {"qid": "Q1", "text": "Mine", "view": "focus", "pid": leader})
        authors = [c["pid"] for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual(authors, [guest])

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

    def test_the_rotated_token_reaches_its_keeper_before_the_hash_is_written(self):
        seen = []
        self.s.on_owner_token = lambda token, at: seen.append((token, at, self.disk()["credentials"]["owner"]["tokenHash"]))
        new = self.act("rotate_owner_link", HOST, {})["token"]
        self.assertEqual(seen, [(new, self.clock.t, session.sha256(self.owner_token))])

    def test_a_keeper_that_fails_leaves_the_old_token_in_force(self):
        def fail(token, at):
            raise OSError("disk full")

        self.s.on_owner_token = fail
        with self.assertRaises(OSError):
            self.act("rotate_owner_link", HOST, {})
        self.assertEqual(self.disk()["credentials"]["owner"]["tokenHash"], session.sha256(self.owner_token))

    def test_reset_refuses_a_token_issued_before_the_last_rotation(self):
        issued = self.clock.t
        self.act("rotate_owner_link", HOST, {})
        rotated = self.s.state["credentials"]["owner"]
        with self.assertRaises(session.DomainError) as ctx:
            self.s.reset_owner_token(self.owner_token, issued)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (409, "owner-token-stale"))
        self.assertEqual(self.disk()["credentials"]["owner"], rotated)
        self.assertTrue(self.s.reset_owner_token("tok-newer", rotated["rotatedAt"] + 1))
        self.assertEqual(self.s.resolve(owner_token="tok-newer"), HOST)

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

    def test_only_the_owner_trusts_and_untrusts_a_person(self):
        ann, lee = self.people("Ann", "Lee")
        self.act("set_role", HOST, {"pid": lee, "role": "leader"})
        self.act("set_trust", HOST, {"pid": ann, "on": True})
        self.assertIs(self.s.state["people"][ann]["trusted"], True)
        self.assertEqual([n["kind"] for n in self.notes(ann)], ["role"])
        self.act("set_trust", HOST, {"pid": ann, "on": False})
        self.assertIs(self.s.state["people"][ann]["trusted"], False)
        for actor in (lee, ann):
            self.refused("owner-only", "set_trust", actor, {"pid": ann, "on": True}, http=403)
        self.assertIs(self.s.state["people"][ann]["trusted"], False)

    def test_the_owner_cannot_be_removed(self):
        self.refused("bad-field", "set_removed", HOST, {"pid": HOST, "on": True})

    def test_rename_is_one_write_and_keeps_names_unique(self):
        ann, bo = self.people("Ann", "Bo")
        self.assertEqual(self.act("rename", bo, {"name": "ann"})["name"], "ann 2")
        self.refused("empty", "rename", bo, {"name": "  "})
        self.refused("too-long", "rename", bo, {"name": "z" * 41})

    def test_a_rename_shows_on_everything_the_person_wrote(self):
        ann, _ = self.join("Ann")
        self.open_round(text_q("Q1"))
        self.act("answer", ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        rev = self.s.state["rev"]
        self.act("rename", ann, {"name": "Annabel"})
        self.assertEqual(self.s.state["rev"], rev + 1)
        snap = self.s.snapshot(HOST)
        self.assertEqual({p["pid"]: p["name"] for p in snap["people"]}[ann], "Annabel")
        self.assertNotIn('"Ann"', json.dumps(snap))

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

    def test_approving_an_imported_merge_request_that_names_the_owner_declines_it(self):
        for src, dst in ((self.old, HOST), (HOST, self.old)):
            mid = self.s._next("G")
            self.s.state["mergeRequests"].append({"id": mid, "from": src, "to": dst, "at": 1.0, "status": {"kind": "pending"}})
            self.assertEqual(self.act("act_on_merge_request", HOST, {"id": mid, "action": "approve"})["status"], "declined")
        self.assertIn(HOST, self.s.state["people"])
        self.assertNotIn(HOST, self.s.state["credentials"]["secrets"].values())
        self.assertEqual(self.s.resolve(secret=self.old_secret), self.old)

    def test_merge_itself_refuses_the_owner_on_either_side(self):
        for src, dst in ((self.old, HOST), (HOST, self.old)):
            with self.assertRaises(session.DomainError):
                self.s._merge(src, dst)

    def test_a_write_that_would_map_a_secret_to_the_owner_is_not_saved(self):
        self.s.validate_writes = False
        self.s.state["credentials"]["secrets"]["f" * 64] = HOST
        with self.assertRaises(session.DomainError) as ctx:
            self.s._commit()
        self.assertEqual(ctx.exception.code, "state-invalid")

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


# ---------------------------------------------------------------------------------------------
# Item 4: questions, input parsing, purpose, references
# ---------------------------------------------------------------------------------------------


class TestQuestionParsing(SessionCase):
    def test_a_text_question_gets_claude_cards_for_the_recommendation_and_each_alternative(self):
        self.open_round(text_q("Q1"))
        self.assertEqual([session.card_ref(c) for c in self.s.state["cards"]["Q1"]], ["c:rec", "c:a", "c:b"])

    def test_a_choice_question_gets_one_option_card_per_option(self):
        self.open_round(choice_q("Q1"))
        self.assertEqual([session.card_ref(c) for c in self.s.state["cards"]["Q1"]], ["o:opt-1", "o:opt-2", "o:opt-3"])

    def test_a_confirm_question_gets_yes_and_no_cards(self):
        q = {**text_q("Q1", rec=False), "format": {"kind": "confirm", "image": PNG, "rect": {"x": 1, "y": 2, "w": 30, "h": 4}}}
        self.open_round(q)
        self.assertEqual([session.card_ref(c) for c in self.s.state["cards"]["Q1"]], ["o:yes", "o:no"])

    def test_text_is_trimmed_and_refused_over_2000_never_cut(self):
        self.open_round({**text_q("Q1"), "text": "  Where?  "})
        self.assertEqual(self.question("Q1")["text"], "Where?")
        err = self.refused_ops("too-long", {"op": "open-round", "questions": [{**text_q("Q2"), "text": "x" * 2001}]})
        self.assertEqual(err.details["op"], 0)

    def test_empty_text_is_refused(self):
        self.refused_ops("empty", {"op": "open-round", "questions": [{**text_q("Q1"), "text": "   "}]})

    def test_depends_on_an_earlier_question_in_the_same_op_is_accepted(self):
        self.open_round(text_q("Q1"), text_q("Q2", depends=["Q1"]))
        self.assertEqual(self.question("Q2")["dependsOn"], ["Q1"])

    def test_depends_on_a_later_question_is_refused(self):
        err = self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q1", depends=["Q2"]), text_q("Q2")]})
        self.assertEqual(err.details["field"], "questions[0].dependsOn")
        self.assertEqual(self.s.state["questions"], [])

    def test_depends_on_an_unknown_question_is_refused(self):
        self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q1", depends=["Q99"])]})

    def test_a_reused_question_id_is_refused(self):
        self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q1"), text_q("Q1")]})

    def test_a_question_id_must_look_like_q_n(self):
        self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Z1")]})

    def test_one_to_eight_questions_per_open_round(self):
        self.refused_ops("bad-field", {"op": "open-round", "questions": []})
        nine = [text_q(f"Q{i}") for i in range(1, 10)]
        self.refused_ops("too-long", {"op": "open-round", "questions": nine})
        self.open_round(*nine[:8])
        self.assertEqual(len(self.s.state["questions"]), 8)

    def test_the_shared_lane_takes_two_or_three_alternatives(self):
        one = text_q("Q1")
        one["alternatives"] = one["alternatives"][:1]
        self.refused_ops("bad-field", {"op": "open-round", "questions": [one]})
        four = text_q("Q1")
        four["alternatives"] = [{"key": k, "text": k.upper()} for k in "abcd"]
        self.refused_ops("bad-field", {"op": "open-round", "questions": [four]})
        three = text_q("Q1")
        three["alternatives"] = [{"key": k, "text": k.upper()} for k in "abc"]
        self.open_round(three)

    def test_a_recommendation_only_on_text_questions(self):
        q = {**choice_q("Q1", purpose="decide"), "recommendation": "Card."}
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})

    def test_alternatives_only_on_text_questions(self):
        q = {**choice_q("Q1", purpose="decide"), "alternatives": [{"key": "a", "text": "A"}, {"key": "b", "text": "B"}]}
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})

    def test_a_recommendation_comes_with_alternatives(self):
        q = {**text_q("Q1", rec=False), "recommendation": "Lonely."}
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})

    def test_a_poll_needs_options(self):
        self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q1", purpose="poll", rec=False)]})

    def test_an_image_must_be_an_existing_asset(self):
        q = choice_q("Q1")
        q["format"]["options"][0]["image"] = "9999999999999999.png"
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})
        q["format"]["options"][0]["image"] = "1111222233334444.png"
        self.open_round(q)

    def test_device_scope_on_a_prototype_is_refused(self):
        q = {
            **text_q("Q1", rec=False),
            "purpose": "gather",
            "answerScope": "device",
            "format": {"kind": "prototype", "variants": [{"id": "v-1", "label": "A", "asset": HTML}, {"id": "v-2", "label": "B", "asset": PNG}]},
        }
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})
        q["answerScope"] = "person"
        self.open_round(q)

    def test_references_take_at_most_eight_and_only_web_links(self):
        q = text_q("Q1", references=[{"kind": "link", "url": "javascript:alert(1)"}])
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})
        q = text_q("Q1", references=[{"kind": "link", "url": f"https://example.com/{i}"} for i in range(9)])
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})

    def test_the_deferred_fixture_later_depends_on_is_refused(self):
        doc = json.loads((FIXTURES / "invalid-ops-later-depends-on.json").read_text(encoding="utf-8"))
        self.assertIsNone(session.ops_error(doc))
        self.clock.tick()
        with self.assertRaises(session.DomainError) as ctx:
            self.s.apply(doc)
        self.assertEqual((ctx.exception.code, ctx.exception.details["field"]), ("bad-field", "questions[0].dependsOn"))

    def test_eight_questions_per_round_counts_questions_already_placed_there(self):
        ann, _ = self.join("Ann")
        self.open_round(text_q("Q1"))
        prop = self.act("propose", ann, {"text": "Ask about refunds"})["id"]
        self.act("act_on_proposal", HOST, {"id": prop, "action": "question"})
        self.send()
        self.ack(1)
        self.refused_ops("round-full", {"op": "open-round", "questions": [text_q(f"Q{i}") for i in range(10, 18)]})
        self.open_round(*[text_q(f"Q{i}") for i in range(10, 17)])
        self.assertEqual(sum(1 for q in self.s.state["questions"] if q["round"] == 2), 8)


class TestQuestionBehavior(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")

    def test_owner_overrides_the_purpose(self):
        self.open_round(text_q("Q1"))
        self.act("set_purpose", HOST, {"qid": "Q1", "purpose": "gather"})
        self.assertEqual(self.question("Q1")["purpose"], "gather")
        self.refused("owner-only", "set_purpose", self.ann, {"qid": "Q1", "purpose": "decide"})
        self.refused("bad-field", "set_purpose", HOST, {"qid": "Q1", "purpose": "poll"})

    def test_gather_refuses_votes_and_lock_with_wrong_purpose(self):
        self.open_round(text_q("Q1", purpose="gather"))
        self.refused("wrong-purpose", "vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True}, http=409)
        self.refused("wrong-purpose", "lock", HOST, {"qid": "Q1", "card": "c:rec"}, http=409)

    def test_poll_takes_one_pick_per_person_and_only_the_owner_closes_it(self):
        self.open_round(choice_q("Q1"))
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})
        self.act("pick", self.bo, {"qid": "Q1", "option": "opt-1", "view": "focus"})
        self.act("pick", self.bo, {"qid": "Q1", "option": "opt-2", "view": "focus"})
        self.assertEqual(self.s.state["votes"]["Q1"], {self.bo: "o:opt-2"})
        self.refused("wrong-purpose", "answer", self.bo, {"qid": "Q1", "text": "Free text", "view": "focus"})
        self.refused("owner-only", "lock", self.ann, {"qid": "Q1"}, http=403)
        self.act("lock", HOST, {"qid": "Q1"})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"]["text"], "Saved method")

    def test_owner_adds_and_removes_references(self):
        self.open_round(text_q("Q1"))
        self.act("edit_reference", HOST, {"qid": "Q1", "reference": {"kind": "quote", "text": "I never find it.", "source": "Ticket"}})
        self.act("edit_reference", HOST, {"qid": "Q1", "reference": {"kind": "image", "asset": PNG, "caption": "Now"}})
        self.assertEqual([r["kind"] for r in self.question("Q1")["references"]], ["quote", "image"])
        self.act("edit_reference", HOST, {"qid": "Q1", "remove": 0})
        self.assertEqual([r["kind"] for r in self.question("Q1")["references"]], ["image"])
        self.refused("not-found", "edit_reference", HOST, {"qid": "Q1", "remove": 5})
        self.refused("owner-only", "edit_reference", self.ann, {"qid": "Q1", "remove": 0})

    def test_a_rect_holding_nan_or_infinity_is_refused(self):
        variants = [{"id": "v-1", "label": "A", "asset": HTML}, {"id": "v-2", "label": "B", "asset": PNG}]
        self.open_round({**text_q("Q1", rec=False), "purpose": "gather", "format": {"kind": "prototype", "variants": variants}})
        for raw in ('{"x": NaN, "y": 0, "w": 10, "h": 10}', '{"x": 0, "y": 0, "w": Infinity, "h": 10}'):
            rect = json.loads(raw)
            anchor = {"selector": "#pay", "rect": rect}
            self.refused("bad-field", "annotate", self.ann, {"qid": "Q1", "variant": "v-1", "text": "Here", "anchor": anchor}, http=400)
            ref = {"kind": "image", "asset": PNG, "rect": rect}
            self.refused("bad-field", "edit_reference", HOST, {"qid": "Q1", "reference": ref}, http=400)
        self.assertEqual(self.s.state["annotations"], [])
        self.assertEqual(self.question("Q1")["references"], [])

    def test_a_question_in_a_round_not_yet_open_takes_no_answers(self):
        self.open_round(text_q("Q1"))
        prop = self.act("propose", self.ann, {"text": "Ask about refunds"})["id"]
        qid = self.act("act_on_proposal", HOST, {"id": prop, "action": "question"})["question"]
        self.refused("round-not-open", "answer", self.bo, {"qid": qid, "text": "Early", "view": "focus"}, http=409)


# ---------------------------------------------------------------------------------------------
# Item 5: cards, votes, reactions, go-with, picks, view and deviceInfo
# ---------------------------------------------------------------------------------------------


class TestCardsAndVotes(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")
        self.open_round(text_q("Q1"), text_q("Q2", scope_kind="device"), text_q("Q3", purpose="gather"))

    def test_one_answer_per_person_per_question(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "First", "view": "focus"})
        self.act("answer", self.ann, {"qid": "Q1", "text": "Second", "view": "compare"})
        mine = [c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual([(c["pid"], c["text"], c["view"]) for c in mine], [(self.ann, "Second", "compare")])

    def test_empty_text_clears_ones_own_card_and_the_votes_on_it(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("answer", self.ann, {"qid": "Q1", "text": "", "view": "focus"})
        self.assertEqual([c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"], [])
        self.assertEqual(self.s.state["votes"]["Q1"], {})

    def test_answer_text_over_2000_is_refused(self):
        self.refused("too-long", "answer", self.ann, {"qid": "Q1", "text": "x" * 2001, "view": "focus"}, http=400)

    def test_one_vote_per_person_per_question_and_voting_again_moves_it(self):
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True})
        out = self.act("vote", self.ann, {"qid": "Q1", "card": "c:a", "on": True})
        self.assertTrue(out["moved"])
        self.assertEqual(self.s.state["votes"]["Q1"], {self.ann: "c:a"})

    def test_vote_off_removes_only_a_matching_vote(self):
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True})
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:a", "on": False})
        self.assertEqual(self.s.state["votes"]["Q1"], {self.ann: "c:rec"})
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": False})
        self.assertEqual(self.s.state["votes"]["Q1"], {})

    def test_no_vote_for_ones_own_card(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.refused("cannot-vote-own", "vote", self.ann, {"qid": "Q1", "card": f"p:{self.ann}", "on": True}, http=400)

    def test_a_vote_for_a_missing_card_is_refused(self):
        self.refused("no-such-card", "vote", self.ann, {"qid": "Q1", "card": "p:nobody", "on": True}, http=404)

    def test_voting_off_refuses_votes(self):
        self.act("update_settings", HOST, {"voting": False})
        self.refused("voting-off", "vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True}, http=403)

    def test_go_with_withdraws_ones_answer_and_moves_the_vote_in_one_action(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.act("answer", self.bo, {"qid": "Q1", "text": "Bo's", "view": "focus"})
        self.act("vote", self.cy, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:rec", "on": True})
        out = self.act("go_with", self.ann, {"qid": "Q1", "card": f"p:{self.bo}"})
        self.assertTrue(out["moved"])
        authors = [c["pid"] for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual(authors, [self.bo])
        self.assertEqual(self.s.state["votes"]["Q1"], {self.ann: f"p:{self.bo}"})

    def test_editing_an_answer_after_votes_records_how_many_votes_it_had(self):
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("vote", self.cy, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine, changed", "view": "focus"})
        (card,) = [c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual(card["editedAfterVotes"], 2)

    def test_device_scope_holds_one_card_per_device_kind_and_one_vote_per_person(self):
        self.act("answer", self.ann, {"qid": "Q2", "text": "On my phone", "device": "phone", "view": "focus"})
        self.act("answer", self.ann, {"qid": "Q2", "text": "On my laptop", "device": "computer", "view": "focus"})
        refs = sorted(session.card_ref(c) for c in self.s.state["cards"]["Q2"] if c["kind"] == "person")
        self.assertEqual(refs, [f"p:{self.ann}:computer", f"p:{self.ann}:phone"])
        self.refused("bad-field", "answer", self.ann, {"qid": "Q2", "text": "Which device?", "view": "focus"})
        self.act("vote", self.bo, {"qid": "Q2", "card": f"p:{self.ann}:phone", "on": True})
        self.act("vote", self.bo, {"qid": "Q2", "card": f"p:{self.ann}:computer", "on": True})
        self.assertEqual(self.s.state["votes"]["Q2"], {self.bo: f"p:{self.ann}:computer"})

    def test_device_info_keeps_only_kind_browser_and_a_rounded_screen(self):
        info = {"kind": "phone", "browser": "safari", "screen": {"w": 393, "h": 852}, "userAgent": "secret"}
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus", "deviceInfo": info})
        (card,) = [c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual(card["deviceInfo"], {"kind": "phone", "browser": "safari", "screen": {"w": 390, "h": 850}})

    def test_reactions_are_thumbs_heart_idea_on_gather_questions_only(self):
        self.act("answer", self.ann, {"qid": "Q3", "text": "The address form", "view": "focus"})
        self.act("react", self.bo, {"qid": "Q3", "card": f"p:{self.ann}", "reaction": "heart"})
        self.assertEqual(self.s.state["reactions"]["Q3"], {f"p:{self.ann}": {self.bo: "heart"}})
        self.refused("bad-field", "react", self.bo, {"qid": "Q3", "card": f"p:{self.ann}", "reaction": "agree"})
        self.refused("wrong-purpose", "react", self.bo, {"qid": "Q1", "card": "c:rec", "reaction": "thumbs"})
        self.act("react", self.bo, {"qid": "Q3", "card": f"p:{self.ann}", "reaction": None})
        self.assertNotIn("Q3", self.s.state["reactions"])

    def test_cites_must_name_a_shown_result_on_the_question(self):
        self.refused("bad-field", "answer", self.ann, {"qid": "Q1", "text": "See X1", "view": "focus", "cites": ["X1"]})

    def test_answers_are_throttled_to_one_write_per_second_per_route(self):
        self.s.answer(self.ann, {"qid": "Q1", "text": "One", "view": "focus"})
        with self.assertRaises(session.DomainError) as ctx:
            self.s.answer(self.ann, {"qid": "Q1", "text": "Two", "view": "focus"})
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "slow-down"))
        self.s.chat(self.ann, {"text": "Other route is fine"})

    def test_a_removed_persons_vote_no_longer_counts(self):
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:a", "on": True})
        self.act("set_removed", HOST, {"pid": self.ann, "on": True})
        self.refused("no-votes", "lock", HOST, {"qid": "Q1"})


class TestPicks(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        conf = {**text_q("Q2", rec=False), "answerScope": "device", "format": {"kind": "confirm", "image": PNG, "rect": {"x": 1, "y": 1, "w": 5, "h": 5}}}
        self.open_round(choice_q("Q1", purpose="decide"), conf)

    def test_the_pick_is_the_vote_and_carries_an_optional_comment(self):
        self.act("pick", self.ann, {"qid": "Q1", "option": "opt-3", "comment": "Least surprise", "view": "compare"})
        self.assertEqual(self.s.state["votes"]["Q1"], {self.ann: "o:opt-3"})
        (card,) = [c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"]
        self.assertEqual((card["pick"], card["text"]), ("opt-3", "Least surprise"))

    def test_a_pick_of_an_unknown_option_is_refused(self):
        self.refused("no-such-option", "pick", self.ann, {"qid": "Q1", "option": "opt-9", "view": "focus"}, http=400)

    def test_voting_on_a_choice_question_goes_through_pick(self):
        self.refused("bad-action", "vote", self.ann, {"qid": "Q1", "card": "o:opt-1", "on": True})

    def test_a_written_answer_on_a_choice_question_replaces_the_pick(self):
        self.act("pick", self.ann, {"qid": "Q1", "option": "opt-1", "view": "focus"})
        self.act("answer", self.ann, {"qid": "Q1", "text": "Something else", "view": "focus"})
        self.assertEqual(self.s.state["votes"]["Q1"], {})

    def test_a_confirm_pick_is_yes_or_no_and_one_vote_across_devices(self):
        self.act("pick", self.ann, {"qid": "Q2", "option": "yes", "device": "phone", "view": "focus"})
        self.act("pick", self.ann, {"qid": "Q2", "option": "no", "device": "computer", "view": "focus"})
        self.assertEqual(self.s.state["votes"]["Q2"], {self.ann: "o:no"})

    def test_an_empty_pick_clears_the_pick(self):
        self.act("pick", self.ann, {"qid": "Q1", "option": "opt-1", "view": "focus"})
        self.act("pick", self.ann, {"qid": "Q1", "option": "", "view": "focus"})
        self.assertEqual(self.s.state["votes"]["Q1"], {})
        self.assertEqual([c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"], [])


# ---------------------------------------------------------------------------------------------
# Item 6: locks, sign-off, suggestions, unlock, Needs review
# ---------------------------------------------------------------------------------------------


class TestLocks(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})
        self.open_round(text_q("Q1"), text_q("Q2", depends=["Q1"]), text_q("Q3", depends=["Q1"]))

    def test_lock_top_answer_is_unavailable_until_some_card_has_a_vote(self):
        self.refused("no-votes", "lock", self.ann, {"qid": "Q1"}, http=409)

    def test_lock_top_answer_locks_the_most_voted_card(self):
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:a", "on": True})
        out = self.act("lock", self.ann, {"qid": "Q1"})
        self.assertEqual(out["text"], "Alternative A for Q1.")
        self.assertEqual(self.s.state["locks"]["Q1"]["source"], {"kind": "card", "card": "c:a", "text": "Alternative A for Q1."})
        self.assertEqual(self.s.state["locks"]["Q1"]["by"], self.ann)

    def test_a_tie_asks_the_owner_to_pick_naming_the_tied_cards(self):
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:a", "on": True})
        self.act("vote", self.cy, {"qid": "Q1", "card": "c:b", "on": True})
        err = self.refused("tie", "lock", self.ann, {"qid": "Q1"}, http=409)
        self.assertEqual(sorted(err.details["tied"]), ["c:a", "c:b"])
        self.act("lock", HOST, {"qid": "Q1", "card": "c:b"})

    def test_the_owners_lock_this_one_always_works(self):
        self.act("update_settings", HOST, {"signoff": True})
        self.act("heartbeat", self.bo, {})
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"]["card"], "c:rec")

    def test_the_owners_lock_this_one_works_with_no_votes(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:b"})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"]["card"], "c:b")

    def test_a_leaders_lock_this_one_is_unavailable_until_some_card_has_a_vote(self):
        self.refused("no-votes", "lock", self.ann, {"qid": "Q1", "card": "c:b"}, http=409)
        self.assertNotIn("Q1", self.s.state["locks"])
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:a", "on": True})
        self.act("lock", self.ann, {"qid": "Q1", "card": "c:b"})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"]["card"], "c:b")

    def test_sign_off_refuses_a_lock_until_everyone_present_agrees(self):
        self.act("update_settings", HOST, {"signoff": True})
        self.clock.tick(session.OFFLINE_AFTER)  # whoever joined earlier but sends no heartbeat is offline
        for p in (HOST, self.ann, self.bo):
            self.s.heartbeat(p, {})
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:a", "on": True})
        err = self.refused("not-agreed", "lock", self.ann, {"qid": "Q1"}, http=409)
        self.assertEqual((err.details["agree"], err.details["total"]), (1, 3))
        self.act("vote", self.ann, {"qid": "Q1", "card": "c:a", "on": True})
        self.act("vote", HOST, {"qid": "Q1", "card": "c:a", "on": True})
        self.act("lock", self.ann, {"qid": "Q1"})

    def test_guests_cannot_lock(self):
        self.refused("moderator-only", "lock", self.bo, {"qid": "Q1", "card": "c:rec"}, http=403)

    def test_a_locked_question_refuses_answers_and_votes(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.refused("locked", "answer", self.bo, {"qid": "Q1", "text": "Too late", "view": "focus"}, http=409)
        self.refused("locked", "vote", self.bo, {"qid": "Q1", "card": "c:a", "on": True}, http=409)
        self.refused("locked", "lock", HOST, {"qid": "Q1", "card": "c:a"}, http=409)

    def test_suggest_a_change_on_a_locked_question(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        out = self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse on narrow screens", "note": "Laptops"})
        self.assertEqual(out["id"], "S1")
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["status"], {"kind": "open"})
        self.assertEqual([n["kind"] for n in self.notes(self.ann, "queue")], ["queue"])

    def test_suggest_is_refused_on_an_open_unlocked_question(self):
        self.refused("not-locked", "suggest", self.bo, {"qid": "Q1", "text": "Answer instead"}, http=409)

    def test_suggest_is_allowed_on_an_unlocked_question_of_a_closed_round(self):
        self.send()
        self.ack(1)
        self.open_round(text_q("Q4"))
        self.act("suggest", self.bo, {"qid": "Q1", "text": "Reconsider this"})
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["text"], "Reconsider this")

    def test_a_suggestion_note_over_200_is_refused(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.refused("too-long", "suggest", self.bo, {"qid": "Q1", "text": "Change", "note": "n" * 201})

    def test_use_locks_the_suggestion_in_and_the_question_stays_locked(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        sid = self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse it"})["id"]
        out = self.act("act_on_suggestion", self.ann, {"qid": "Q1", "id": sid, "action": "use"})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"], {"kind": "suggestion", "suggestion": sid, "text": "Collapse it"})
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["status"]["kind"], "used")
        self.assertEqual(out["flagged"], ["Q2", "Q3"])

    def test_dismiss_keeps_the_lock(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        sid = self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse it"})["id"]
        self.act("act_on_suggestion", self.ann, {"qid": "Q1", "id": sid, "action": "dismiss"})
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["status"]["kind"], "dismissed")
        self.assertEqual(self.s.state["locks"]["Q1"]["source"]["card"], "c:rec")
        self.refused("wrong-status", "act_on_suggestion", self.ann, {"qid": "Q1", "id": sid, "action": "use"})

    def test_guests_cannot_act_on_suggestions(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        sid = self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse it"})["id"]
        self.refused("moderator-only", "act_on_suggestion", self.cy, {"qid": "Q1", "id": sid, "action": "use"})

    def test_edit_in_replaces_the_locked_text_and_marks_the_source_suggestion_used(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        sid = self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse it"})["id"]
        self.act("edit_lock", self.ann, {"qid": "Q1", "text": "Collapse it under 1280 px", "from": sid})
        self.assertEqual(self.s.state["locks"]["Q1"]["source"], {"kind": "edited", "text": "Collapse it under 1280 px", "from": sid})
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["status"]["kind"], "used")

    def test_unlock_closes_suggestions_without_deleting_them_and_flags_dependents(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("suggest", self.bo, {"qid": "Q1", "text": "Collapse it"})
        out = self.act("unlock", self.ann, {"qid": "Q1"})
        self.assertEqual(out, {"closed": 1, "flagged": ["Q2", "Q3"]})
        (s,) = self.s.state["suggestions"]["Q1"]
        self.assertEqual((s["status"]["kind"], s["status"]["by"]), ("closed", "unlock"))
        self.assertEqual(self.question("Q2")["needsReview"][-1]["why"], {"kind": "unlocked"})
        self.assertNotIn("Q1", self.s.state["locks"])

    def test_unlock_needs_a_lock(self):
        self.refused("not-locked", "unlock", self.ann, {"qid": "Q1"}, http=409)

    def test_a_changed_locked_answer_flags_dependents_naming_the_changed_question(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.assertEqual(self.question("Q2")["needsReview"], [])
        self.act("edit_lock", HOST, {"qid": "Q1", "text": "Something different"})
        flag = self.question("Q2")["needsReview"][-1]
        self.assertEqual((flag["because"], flag["why"]), ("Q1", {"kind": "lock-changed"}))
        self.assertEqual(self.question("Q1")["needsReview"], [])

    def test_relocking_the_same_text_flags_nothing_new(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("edit_lock", HOST, {"qid": "Q1", "text": "Recommended for Q1."})
        self.assertEqual(self.question("Q2")["needsReview"], [])

    def test_no_two_flags_share_because_and_why_and_the_newest_is_last(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("edit_lock", HOST, {"qid": "Q1", "text": "Two"})
        self.act("unlock", HOST, {"qid": "Q1"})
        self.act("lock", HOST, {"qid": "Q1", "card": "c:a"})
        flags = self.question("Q2")["needsReview"]
        self.assertEqual([f["why"]["kind"] for f in flags], ["unlocked", "lock-changed"])
        self.assertEqual(len({(f["because"], json.dumps(f["why"])) for f in flags}), len(flags))

    def test_review_clear_drops_the_flags(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("unlock", HOST, {"qid": "Q1"})
        self.assertEqual(self.act("clear_review", self.ann, {"qid": "Q2"})["cleared"], 1)
        self.assertEqual(self.question("Q2")["needsReview"], [])
        self.refused("moderator-only", "clear_review", self.bo, {"qid": "Q3"})

    def test_suggestion_votes_are_one_per_person_and_never_ones_own(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        s1 = self.act("suggest", self.bo, {"qid": "Q1", "text": "One"})["id"]
        s2 = self.act("suggest", self.cy, {"qid": "Q1", "text": "Two"})["id"]
        self.act("vote", self.ann, {"qid": "Q1", "suggestion": s1, "on": True})
        self.act("vote", self.ann, {"qid": "Q1", "suggestion": s2, "on": True})
        self.assertEqual(self.s.state["suggestionVotes"]["Q1"], {self.ann: s2})
        self.refused("cannot-vote-own", "vote", self.bo, {"qid": "Q1", "suggestion": s1, "on": True})

    def test_unlock_keeps_suggestions_and_a_relock_does_not_reopen_them(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("suggest", self.bo, {"qid": "Q1", "text": "One"})
        self.act("unlock", HOST, {"qid": "Q1"})
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.assertEqual(self.s.state["suggestions"]["Q1"][0]["status"]["kind"], "closed")

    def test_the_deferred_fixture_duplicate_flag_is_refused_by_the_session_checks(self):
        doc = json.loads((FIXTURES / "invalid-state-duplicate-flag.json").read_text(encoding="utf-8"))
        self.assertIsNone(session.state_error(doc))
        self.assertIn("Q3", session.cross_field_errors(doc)[0])
        self.path.write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaises(session.DomainError) as ctx:
            session.Session.load(self.path, clock=self.clock, ids=self.ids)
        self.assertEqual(ctx.exception.code, "state-invalid")


# ---------------------------------------------------------------------------------------------
# Item 7: proposals and placements, chat, @mentions, notifications
# ---------------------------------------------------------------------------------------------


class TestProposals(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})

    def propose(self, pid, text):
        return self.act("propose", pid, {"text": text})["id"]

    def to_working_round(self):
        self.open_round(text_q("Q1"), text_q("Q2"))
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        props = [self.propose(self.bo, f"Idea {i}") for i in range(1, 7)]
        self.send()
        self.ack(1)
        return props

    def test_a_proposal_waits_as_new_and_reaches_the_moderators_queue(self):
        pid = self.propose(self.bo, "Ask about refunds")
        self.assertEqual(self.s.state["proposals"][0]["status"], {"kind": "new"})
        self.assertEqual(pid, "P1")
        self.assertEqual(len(self.notes(self.ann, "queue")), 1)

    def test_queue_notifications_roll_up_into_one_unread_line(self):
        self.propose(self.bo, "One")
        self.propose(self.bo, "Two")
        (note,) = self.notes(HOST, "queue")
        self.assertEqual((note["title"], note["rollup"]["n"]), ("2 new items in the queue.", 2))

    def test_all_six_placements_land_together(self):
        p = self.to_working_round()
        placements = [
            {"proposal": p[0], "as": "question", "question": text_q("Q10")},
            {"proposal": p[1], "as": "later-round", "after": ["Q10"], "question": text_q("Q11", rec=False, purpose="gather")},
            {"proposal": p[2], "as": "suggestion", "target": "Q1", "text": "Collapse it", "reason": "Narrow laptops"},
            {"proposal": p[3], "as": "merge", "target": "Q2", "reason": "Same as Q2"},
            {"proposal": p[4], "as": "later", "reason": "Needs the payments team"},
            {"proposal": p[5], "as": "not-placed", "reason": "Not about checkout"},
        ]
        out = self.open_round(text_q("Q3"), placements=placements)["results"][0]
        status = {x["id"]: x["status"] for x in self.s.state["proposals"]}
        self.assertEqual(status[p[0]], {"kind": "question", "question": "Q10"})
        self.assertEqual(status[p[1]], {"kind": "question", "question": "Q11"})
        self.assertEqual(status[p[2]]["kind"], "suggested")
        self.assertEqual(status[p[3]], {"kind": "merged", "question": "Q2", "reason": "Same as Q2"})
        self.assertEqual(status[p[4]], {"kind": "later", "reason": "Needs the payments team"})
        self.assertEqual(status[p[5]], {"kind": "not-placed", "reason": "Not about checkout"})
        self.assertEqual((self.question("Q10")["round"], self.question("Q11")["round"]), (2, 3))
        self.assertEqual(self.question("Q11")["dependsOn"], ["Q10"])
        self.assertEqual(self.question("Q10")["origin"], {"kind": "proposal", "proposal": p[0]})
        self.assertEqual(len(out["placed"]), 6)
        sug = self.s.state["suggestions"]["Q1"][0]
        self.assertEqual((sug["pid"], sug["fromProposal"], sug["note"]), (self.bo, p[2], "Narrow laptops"))
        self.assertEqual([n["kind"] for n in self.notes(self.bo, "proposal")], ["proposal"] * 6)

    def test_a_suggestion_placement_needs_a_locked_target_and_flags_dependents(self):
        self.open_round(text_q("Q1"), text_q("Q2", depends=["Q1"]))
        prop = self.propose(self.bo, "Collapse it")
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.send()
        self.ack(1)
        bad = {"op": "open-round", "questions": [text_q("Q3")], "placements": [{"proposal": prop, "as": "suggestion", "target": "Q2"}]}
        self.refused_ops("not-locked", bad)
        self.open_round(text_q("Q3"), placements=[{"proposal": prop, "as": "suggestion", "target": "Q1"}])
        flag = self.question("Q2")["needsReview"][-1]
        self.assertEqual(flag["why"], {"kind": "suggested", "suggestion": "S1"})

    def test_a_placement_for_a_non_new_proposal_refuses_the_whole_op(self):
        p = self.to_working_round()
        self.act("act_on_proposal", self.ann, {"id": p[0], "action": "park"})
        rest = [{"proposal": x, "as": "later", "reason": "Later"} for x in p[1:]]
        before = copy_state(self.s)
        err = self.refused_ops("wrong-status", {"op": "open-round", "questions": [text_q("Q3")], "placements": [{"proposal": p[0], "as": "later", "reason": "x"}, *rest]})
        self.assertEqual(err.details["status"], "parked")
        self.assertEqual(self.s.state, before)

    def test_two_placements_for_one_proposal_refuse_the_whole_op(self):
        p = self.to_working_round()
        twice = [{"proposal": p[0], "as": "later", "reason": "a"}, {"proposal": p[0], "as": "not-placed", "reason": "b"}]
        rest = [{"proposal": x, "as": "later", "reason": "Later"} for x in p[1:]]
        self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q3")], "placements": twice + rest})
        self.assertEqual(len(self.s.state["rounds"]), 1)

    def test_every_proposal_in_the_sent_digest_needs_a_placement(self):
        p = self.to_working_round()
        err = self.refused_ops("bad-field", {"op": "open-round", "questions": [text_q("Q3")]})
        self.assertIn(p[0], err.message)

    def test_a_proposal_made_after_the_send_may_wait_for_the_next_digest(self):
        p = self.to_working_round()
        late = self.propose(self.bo, "Arrived while Claude worked")
        self.open_round(text_q("Q3"), placements=[{"proposal": x, "as": "later", "reason": "Later"} for x in p])
        self.assertEqual(next(x for x in self.s.state["proposals"] if x["id"] == late)["status"], {"kind": "new"})

    def test_close_round_takes_placements_only(self):
        p = self.to_working_round()
        self.apply({"op": "close-round", "placements": [{"proposal": x, "as": "not-placed", "reason": "Done"} for x in p]})
        self.assertEqual({x["status"]["kind"] for x in self.s.state["proposals"]}, {"not-placed"})

    def test_moderator_actions_question_park_restore_later(self):
        self.open_round(text_q("Q1"))
        prop = self.propose(self.bo, "Ask about refunds")
        self.act("act_on_proposal", self.ann, {"id": prop, "action": "park"})
        self.refused("wrong-status", "act_on_proposal", self.ann, {"id": prop, "action": "park"})
        self.act("act_on_proposal", self.ann, {"id": prop, "action": "restore"})
        self.act("act_on_proposal", self.ann, {"id": prop, "action": "later", "reason": "Not today"})
        out = self.act("act_on_proposal", self.ann, {"id": prop, "action": "question"})
        q = self.question(out["question"])
        self.assertEqual((q["round"], q["origin"]["kind"], q["origin"]["by"]), (2, "host", self.ann))
        self.assertNotIn("recommendation", q)
        self.refused("moderator-only", "act_on_proposal", self.bo, {"id": prop, "action": "park"})

    def test_make_question_from_relays_the_owners_override(self):
        self.open_round(text_q("Q1"))
        prop = self.propose(self.bo, "Ask about refunds")
        self.apply({"op": "make-question-from", "proposal": prop, "question": text_q("Q20", rec=False)})
        q = self.question("Q20")
        self.assertEqual((q["round"], q["origin"]), (2, {"kind": "host", "proposal": prop, "by": HOST}))
        self.refused_ops("bad-field", {"op": "make-question-from", "proposal": self.propose(self.ann, "Other"), "question": text_q("Q21")})

    def test_guests_see_only_their_own_proposals(self):
        self.propose(self.bo, "Bo's")
        self.propose(self.ann, "Ann's")
        cy, _ = self.join("Cy")
        self.propose(cy, "Cy's")
        self.assertEqual([p["text"] for p in self.s.snapshot(cy)["proposals"]], ["Cy's"])
        self.assertEqual(len(self.s.snapshot(self.ann)["proposals"]), 3)


def copy_state(s):
    return json.loads(json.dumps(s.state))


class TestChatAndNotifications(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")

    def test_chat_with_reply_to_quotes_an_excerpt_and_notifies_the_author(self):
        m1 = self.act("chat", self.ann, {"text": "Could we see both layouts? " + "x" * 200})["id"]
        self.act("chat", self.bo, {"text": "Yes", "replyTo": m1})
        reply = self.s.state["chat"][1]["replyTo"]
        self.assertEqual((reply["id"], reply["pid"], len(reply["excerpt"])), (m1, self.ann, 140))
        self.assertEqual([n["kind"] for n in self.notes(self.ann)], ["reply"])

    def test_chat_is_refused_when_chat_is_off_and_text_over_2000(self):
        self.refused("too-long", "chat", self.ann, {"text": "x" * 2001})
        self.act("update_settings", HOST, {"chat": False})
        self.refused("chat-off", "chat", self.ann, {"text": "Hello"}, http=403)

    def test_chat_is_never_in_the_digest(self):
        self.open_round(text_q("Q1"))
        self.act("chat", self.ann, {"text": "A private aside"})
        self.send()
        self.assertNotIn("A private aside", json.dumps(self.events("round-sent")[0]))

    def test_a_moderator_turns_a_chat_message_into_its_authors_proposal(self):
        mid = self.act("chat", self.bo, {"text": "Compare both layouts"})["id"]
        prop = self.act("propose_from_chat", HOST, {"id": mid})["proposal"]
        p = self.s.state["proposals"][0]
        self.assertEqual((p["id"], p["pid"], p["via"]), (prop, self.bo, {"kind": "chat", "message": mid, "by": HOST}))
        self.refused("wrong-status", "propose_from_chat", HOST, {"id": mid})

    def test_mentions_notify_the_named_person_once_and_never_the_actor(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "@Bo what do you think? @ann", "view": "focus"})
        self.act("answer", self.ann, {"qid": "Q1", "text": "@Bo what do you think now?", "view": "focus"})
        self.assertEqual(len(self.notes(self.bo, "mention")), 1)
        self.assertEqual(self.notes(self.ann, "mention"), [])

    def test_a_longer_name_wins_over_its_prefix(self):
        bo2, _ = self.join("Bo Smith")
        self.act("chat", self.ann, {"text": "thanks @Bo Smith"})
        self.assertEqual(len(self.notes(bo2, "mention")), 1)
        self.assertEqual(self.notes(self.bo, "mention"), [])

    def test_a_mention_in_a_suggestion_notifies_the_named_person_never_the_actor(self):
        self.open_round(text_q("Q1"))
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("suggest", self.ann, {"qid": "Q1", "text": "Collapse it, @Bo?", "note": "@Ann thinks so"})
        self.assertEqual(len(self.notes(self.bo, "mention")), 1)
        self.assertEqual(self.notes(self.ann, "mention"), [])
        self.assertEqual(self.notes(self.cy, "mention"), [])

    def test_a_mention_in_a_request_notifies_the_named_person_never_the_actor(self):
        self.open_round(text_q("Q1"))
        self.act("request", self.ann, {"qid": "Q1", "kind": "ask", "text": "@Bo and @Ann asked: which step drops most?"})
        self.assertEqual(len(self.notes(self.bo, "mention")), 1)
        self.assertEqual(self.notes(self.ann, "mention"), [])
        self.assertEqual(self.notes(self.cy, "mention"), [])

    def test_votes_roll_up_to_one_line_per_answer_per_hour(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.act("vote", self.cy, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        (note,) = self.notes(self.ann, "votes")
        self.assertEqual(note["rollup"]["n"], 2)
        self.clock.tick(3601)
        self.act("vote", HOST, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.assertEqual(len(self.notes(self.ann, "votes")), 2)

    def test_a_muted_kind_is_not_notified(self):
        self.act("set_prefs", self.ann, {"set": {"mute": ["reply"]}})
        m1 = self.act("chat", self.ann, {"text": "Hello"})["id"]
        self.act("chat", self.bo, {"text": "Hi", "replyTo": m1})
        self.assertEqual(self.notes(self.ann), [])

    def test_a_removed_person_gets_no_notifications(self):
        self.act("set_removed", HOST, {"pid": self.bo, "on": True})
        self.act("chat", self.ann, {"text": "@Bo are you there?"})
        self.assertEqual(self.notes(self.bo), [])

    def test_notifications_cap_at_500_and_the_wire_shows_the_newest_100(self):
        for i in range(session.NOTIFY_CAP + 5):
            self.s._mutate(lambda st, i=i: self.s._notify(self.ann, "mention", f"n{i}"))
        lst = self.s.state["notifications"][self.ann]
        self.assertEqual(len(lst), 500)
        self.assertEqual(lst[0]["title"], "n5")
        wire = self.s.snapshot(self.ann)["me"]["notifications"]
        self.assertEqual((len(wire), wire[-1]["title"], wire[0]["title"]), (100, "n504", "n405"))

    def test_marking_notifications_read(self):
        m1 = self.act("chat", self.ann, {"text": "Hello"})["id"]
        self.act("chat", self.bo, {"text": "Hi", "replyTo": m1})
        self.act("chat", self.cy, {"text": "Hey", "replyTo": m1})
        first = self.notes(self.ann)[0]["id"]
        self.assertEqual(self.act("read_notifications", self.ann, {"ids": [first]})["read"], 1)
        self.assertEqual(self.act("read_notifications", self.ann, {"all": True})["read"], 1)
        self.assertEqual(self.s.snapshot(self.ann)["me"]["unread"], 0)

    def test_notification_titles_carry_no_names(self):
        m1 = self.act("chat", self.ann, {"text": "Hello"})["id"]
        self.act("chat", self.bo, {"text": "@Ann hi", "replyTo": m1})
        self.act("chat", self.cy, {"text": "@Ann hey"})
        for n in self.notes(self.ann):
            self.assertNotIn("Bo", n["title"])
            self.assertNotIn("Cy", n["title"])


# ---------------------------------------------------------------------------------------------
# Item 8: requests (host runner), results stored unpublished until the owner publishes
# ---------------------------------------------------------------------------------------------


class TestWriteLimits(SessionCase):
    """Every route a person can write through is held to one write a second (Contracts, "Body caps
    and limits"), the heartbeat to about one a second, and stored chat, notes and suggestions are
    capped so state.json cannot grow without bound."""

    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.open_round(text_q("Q1"), text_q("Q3", purpose="gather"))
        self.act("answer", self.bo, {"qid": "Q1", "text": "Bo's", "view": "focus"})
        self.act("answer", self.bo, {"qid": "Q3", "text": "Bo's idea", "view": "focus"})

    def twice(self, method, first, second):
        self.clock.tick(5)
        getattr(self.s, method)(self.ann, first)
        with self.assertRaises(session.DomainError) as ctx:
            getattr(self.s, method)(self.ann, second)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "slow-down"))

    def test_every_persisting_person_route_takes_one_write_a_second(self):
        cases = {
            "rename": ({"name": "Ann A"}, {"name": "Ann B"}),
            "set_color": ({"color": "c5"}, {"color": "c6"}),
            "set_prefs": ({"set": {"sort": "new"}}, {"set": {"sort": "votes"}}),
            "set_about_you": ({"techComfort": "ok"}, {"techComfort": "high"}),
            "vote": ({"qid": "Q1", "card": "c:a", "on": True}, {"qid": "Q1", "card": "c:b", "on": True}),
            "react": ({"qid": "Q3", "card": f"p:{self.bo}", "reaction": "thumbs"}, {"qid": "Q3", "card": f"p:{self.bo}", "reaction": "heart"}),
            "go_with": ({"qid": "Q1", "card": f"p:{self.bo}"}, {"qid": "Q1", "card": f"p:{self.bo}"}),
            "read_notifications": ({"all": True}, {"all": True}),
        }
        for method, (first, second) in cases.items():
            with self.subTest(method=method):
                rev = self.s.state["rev"]
                self.twice(method, first, second)
                self.assertEqual(self.s.state["rev"], rev + 1, "the refused write reached the disk")

    def test_the_heartbeat_takes_about_one_a_second(self):
        q_of = lambda: next(p["q"] for p in self.s.snapshot(HOST)["presence"] if p["pid"] == self.ann)  # noqa: E731
        self.twice("heartbeat", {"q": "Q1"}, {"q": "Q3"})
        self.assertEqual(q_of(), "Q1")
        self.clock.tick(session.HEARTBEAT_INTERVAL)
        self.s.heartbeat(self.ann, {"q": "Q3"})
        self.assertEqual(q_of(), "Q3")

    def test_write_records_are_dropped_once_they_can_throttle_nothing(self):
        self.act("propose", self.ann, {"text": "One"})
        self.clock.tick(5)
        self.s.chat(self.bo, {"text": "Later"})
        self.assertEqual(list(self.s._last_write), [(self.bo, "chat")])

    def test_a_forgotten_person_leaves_no_write_record(self):
        self.act("set_trust", HOST, {"pid": self.ann, "on": True})  # trusted, so never the one forgotten
        with mock.patch.object(session, "MAX_PEOPLE", 4):
            idle, _ = self.join("Idle")
            self.s.rename(idle, {"name": "Idle Too"})
            self.s.request_merge(idle, {"to": self.bo})  # a write record, but no content that keeps a person
            self.s._presence.clear()
            self.join("New")
        self.assertNotIn(idle, self.s.state["people"])
        self.assertFalse([k for k in self.s._last_write if k[0] == idle])

    def test_chat_keeps_the_newest_messages(self):
        with mock.patch.object(session, "MAX_CHAT", 3):
            ids = [self.act("chat", self.ann, {"text": f"Message {i}"})["id"] for i in range(5)]
        self.assertEqual([m["id"] for m in self.s.state["chat"]], ids[-3:])

    def test_notes_keep_the_newest(self):
        variants = [{"id": "v-1", "label": "A", "asset": HTML}, {"id": "v-2", "label": "B", "asset": PNG}]
        self.send()
        self.ack(1)
        self.open_round({**text_q("Q4", rec=False), "purpose": "gather", "format": {"kind": "prototype", "variants": variants}})
        anchor = {"selector": "#pay", "rect": {"x": 0, "y": 0, "w": 10, "h": 10}}
        with mock.patch.object(session, "MAX_ANNOTATIONS", 2):
            ids = [self.act("annotate", self.ann, {"qid": "Q4", "variant": "v-1", "text": f"Note {i}", "anchor": anchor})["id"] for i in range(4)]
        self.assertEqual([a["id"] for a in self.s.state["annotations"]], ids[-2:])

    def test_suggestions_keep_the_newest_and_drop_votes_on_the_dropped(self):
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        with mock.patch.object(session, "MAX_SUGGESTIONS", 2):
            first = self.act("suggest", self.bo, {"qid": "Q1", "text": "One"})["id"]
            self.act("vote", self.ann, {"qid": "Q1", "suggestion": first, "on": True})
            ids = [first] + [self.act("suggest", self.bo, {"qid": "Q1", "text": f"More {i}"})["id"] for i in range(2)]
        self.assertEqual([s["id"] for s in self.s.state["suggestions"]["Q1"]], ids[-2:])
        self.assertEqual(self.s.state["suggestionVotes"]["Q1"], {})


class HeldLock:
    """An RLock that knows whether the calling thread holds it."""

    def __init__(self):
        self._lock, self._owner, self._depth = threading.RLock(), None, 0

    def __enter__(self):
        self._lock.acquire()
        self._owner, self._depth = threading.get_ident(), self._depth + 1
        return self

    def __exit__(self, *exc):
        self._depth -= 1
        if not self._depth:
            self._owner = None
        self._lock.release()

    def held(self):
        return self._owner == threading.get_ident()


def guarded(base, lock, case):
    """A `base` mapping that fails `case` whenever it is changed without `lock` held."""

    class Guarded(base):
        def _check(self):
            case.assertTrue(lock.held(), "changed outside the session lock")

        def __setitem__(self, k, v):
            self._check()
            super().__setitem__(k, v)

        def __delitem__(self, k):
            self._check()
            super().__delitem__(k)

        def pop(self, *a):
            self._check()
            return super().pop(*a)

        def popitem(self, *a, **kw):
            self._check()
            return super().popitem(*a, **kw)

    return Guarded()


class TestInMemoryRecordsUnderTheLock(SessionCase):
    """The write and join records another request thread reads are changed only under the session
    lock, so a concurrent request never iterates one mid-change and answers 500 for a write that landed."""

    def setUp(self):
        super().setUp()
        self.ann = self.join("Ann")[0]
        lock = HeldLock()
        self.s._lock = lock
        self.s._last_write = guarded(collections.OrderedDict, lock, self)
        self.s._joins = guarded(collections.OrderedDict, lock, self)
        self.s._key_joins = guarded(dict, lock, self)
        self.s._presence = guarded(dict, lock, self)

    def test_a_join_records_itself_under_the_lock(self):
        self.join("Bo")
        self.assertEqual(len(self.s._joins), 1)

    def test_an_accepted_write_records_itself_under_the_lock(self):
        self.act("chat", self.ann, {"text": "Hello"})
        self.assertIn((self.ann, "chat"), self.s._last_write)


class TestRequests(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.open_round(text_q("Q1"), text_q("Q2"))

    def ask(self, pid, text="How do other shops do it?", **extra):
        return self.act("request", pid, {"qid": "Q1", "kind": "research", "text": text, **extra})["id"]

    def result_op(self, rid, qid="Q1", summary="Most shops pin it right."):
        return {"op": "result", "qid": qid, "request": rid, "kind": "research", "used": [{"name": "discovery:research", "type": "skill"}], "why": "Outside comparison.", "summary": summary, "sources": [{"title": "Patterns", "url": "https://example.com/p"}], "report": "Seven of ten."}

    def test_a_request_waits_pending_in_the_owners_queue(self):
        rid = self.ask(self.ann)
        r = self.s.state["requests"][0]
        self.assertEqual((rid, r["status"], r["runner"], r["edited"]), ("R1", {"kind": "pending"}, "host", False))
        self.assertEqual(len(self.notes(HOST, "queue")), 1)

    def test_at_most_ten_pending_requests_per_person(self):
        for i in range(10):
            self.ask(self.ann, f"Question {i}")
        self.refused("too-many-pending", "request", self.ann, {"qid": "Q1", "kind": "ask", "text": "Eleventh"}, http=429)

    def test_only_the_owner_runs_and_only_the_ids_shown_that_are_still_pending(self):
        r1, r2, r3 = self.ask(self.ann, "one"), self.ask(self.bo, "two"), self.ask(self.ann, "three")
        self.act("act_on_request", HOST, {"action": "decline", "id": r2})
        self.refused("owner-only", "act_on_request", self.ann, {"action": "run", "ids": [r1]}, http=403)
        out = self.act("act_on_request", HOST, {"action": "run", "ids": [r1, r2]})
        self.assertEqual(out["ran"], [r1])
        status = {r["id"]: r["status"]["kind"] for r in self.s.state["requests"]}
        self.assertEqual(status, {r1: "running", r2: "declined", r3: "pending"})
        (ev,) = self.events("request-run")
        self.assertEqual([x["id"] for x in ev["requests"]], [r1])
        self.assertEqual(ev["requests"][0]["question"], "Question Q1?")

    def test_edit_marks_the_request_edited(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "edit", "id": rid, "text": "Sharper wording"})
        r = self.s.state["requests"][0]
        self.assertEqual((r["text"], r["edited"]), ("Sharper wording", True))

    def test_decline_tells_the_requester(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "decline", "id": rid})
        self.assertEqual(self.s.state["requests"][0]["status"]["kind"], "declined")
        self.assertEqual(len(self.notes(self.ann, "request")), 1)

    def test_fail_cancels_a_running_request_and_tells_claude_and_the_requester(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        self.act("act_on_request", HOST, {"action": "fail", "id": rid})
        st = self.s.state["requests"][0]["status"]
        self.assertEqual((st["kind"], st["cancelled"]), ("failed", True))
        self.assertEqual([e["request"] for e in self.events("request-cancelled")], [rid])

    def test_rerun_runs_a_failed_request_again(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        self.act("act_on_request", HOST, {"action": "fail", "id": rid})
        self.act("act_on_request", HOST, {"action": "rerun", "id": rid})
        self.assertEqual(self.s.state["requests"][0]["status"]["kind"], "running")
        self.assertEqual(len(self.events("request-run")), 2)

    def test_wrong_status_actions_are_refused(self):
        rid = self.ask(self.ann)
        self.refused("wrong-status", "act_on_request", HOST, {"action": "fail", "id": rid}, http=409)
        self.refused("no-such-request", "act_on_request", HOST, {"action": "decline", "id": "R99"}, http=404)

    def test_a_result_is_stored_unpublished_and_hidden_from_everyone_but_the_owner(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        out = self.apply(self.result_op(rid))["results"][0]
        res = self.s.state["results"]["Q1"][0]
        self.assertEqual((out["published"], res["published"], res["by"]), (False, False, {"kind": "host-claude"}))
        self.assertEqual(self.s.state["requests"][0]["status"], {"kind": "done", "at": self.clock.t, "result": res["id"]})
        for viewer in (self.ann, self.bo):
            snap = json.dumps(self.s.snapshot(viewer))
            self.assertNotIn("Most shops pin it right.", snap)
        self.assertIn("Most shops pin it right.", json.dumps(self.s.snapshot(HOST)))
        self.assertEqual(self.notes(self.ann, "request"), [])

    def test_publish_shows_the_result_and_tells_the_requester(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        xid = self.apply(self.result_op(rid))["results"][0]["id"]
        self.act("act_on_request", HOST, {"action": "publish", "id": xid})
        self.assertEqual(self.s.snapshot(self.bo)["results"]["Q1"][0]["summary"], "Most shops pin it right.")
        self.assertEqual(len(self.notes(self.ann, "request")), 1)

    def test_a_result_keeps_used_and_why_as_given_on_the_published_card(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        used = [{"name": "discovery:research", "type": "skill"}, {"name": "context7", "type": "mcp"}]
        xid = self.apply({**self.result_op(rid), "used": used, "why": "Needed outside evidence."})["results"][0]["id"]
        res = self.s.state["results"]["Q1"][0]
        self.assertEqual((res["used"], res["why"]), (used, "Needed outside evidence."))
        self.act("act_on_request", HOST, {"action": "publish", "id": xid})
        (card,) = self.s.snapshot(self.bo)["results"]["Q1"]
        self.assertEqual((card["used"], card["why"]), (used, "Needed outside evidence."))

    def test_discard_drops_the_result_and_fails_the_request(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        xid = self.apply(self.result_op(rid))["results"][0]["id"]
        self.act("act_on_request", HOST, {"action": "discard", "id": xid})
        self.assertNotIn("Q1", self.s.state["results"])
        self.assertEqual(self.s.state["requests"][0]["status"]["kind"], "failed")

    def test_a_result_needs_a_running_request_on_its_question(self):
        rid = self.ask(self.ann)
        self.refused_ops("wrong-status", self.result_op(rid))
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        self.refused_ops("bad-field", self.result_op(rid, qid="Q2"))

    def test_others_see_counts_only_while_a_request_is_pending(self):
        self.ask(self.ann, "Private wording")
        snap = self.s.snapshot(self.bo)
        self.assertNotIn("Private wording", json.dumps(snap))
        self.assertEqual(snap["requestCounts"], {"open": 1, "byQ": {"Q1": 1}})
        self.assertEqual(self.s.snapshot(self.ann)["myRequests"][0]["text"], "Private wording")

    def test_fail_request_op_fails_a_running_request(self):
        rid = self.ask(self.ann)
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        self.apply({"op": "fail-request", "request": rid, "reason": "No sources found."})
        st = self.s.state["requests"][0]["status"]
        self.assertEqual((st["kind"], st["reason"], st["cancelled"]), ("failed", "No sources found.", False))


class TestSelfRunner(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.open_round(text_q("Q1"))
        self.rid = self.act("request", self.ann, {"qid": "Q1", "kind": "ask", "text": "Which step drops most?", "runner": "self"})["id"]

    def test_a_self_request_never_enters_the_owners_queue_or_the_event_log(self):
        self.assertEqual(self.notes(HOST, "queue"), [])
        self.assertEqual(self.s.snapshot(HOST)["requests"], [])
        self.refused("no-such-request", "act_on_request", HOST, {"action": "decline", "id": self.rid})
        self.act("claim_my_request", self.ann, {"id": self.rid})
        self.assertEqual(self.events(), [])

    def test_only_the_requesters_own_secret_posts_its_result_which_shows_at_once(self):
        self.act("claim_my_request", self.ann, {"id": self.rid})
        body = {"id": self.rid, "summary": "The address step.", "sources": [], "report": "", "used": [{"name": "claude", "type": "cli"}], "why": "Own Claude."}
        self.refused("no-such-request", "post_my_result", self.bo, body, http=404)
        self.act("post_my_result", self.ann, body)
        res = self.s.state["results"]["Q1"][0]
        self.assertEqual((res["published"], res["by"]), (True, {"kind": "guest-claude", "pid": self.ann}))
        self.assertEqual(self.s.snapshot(self.bo)["results"]["Q1"][0]["summary"], "The address step.")

    def test_my_requests_lists_only_ones_own_self_requests(self):
        self.act("request", self.bo, {"qid": "Q1", "kind": "ask", "text": "Bo's own", "runner": "self"})
        out = self.s.my_requests(self.ann, {"status": "pending"})["requests"]
        self.assertEqual([r["id"] for r in out], [self.rid])

    def test_fail_my_request(self):
        self.act("fail_my_request", self.ann, {"id": self.rid, "reason": "My Claude is offline."})
        self.assertEqual(self.s.state["requests"][0]["status"]["kind"], "failed")


# ---------------------------------------------------------------------------------------------
# Item 9: settings, prefs, title, goal, end, links
# ---------------------------------------------------------------------------------------------


class TestSessionControls(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")

    def test_settings_take_a_partial_object_and_refuse_unknown_keys_and_values(self):
        out = self.act("update_settings", HOST, {"names": "initials", "theme": {"accent": "amber"}})
        self.assertEqual((out["settings"]["names"], out["settings"]["theme"]), ("initials", {"mode": "system", "accent": "amber"}))
        self.refused("bad-field", "update_settings", HOST, {"colour": "red"})
        self.refused("bad-field", "update_settings", HOST, {"voting": "yes"})
        self.refused("bad-field", "update_settings", HOST, {"theme": {"accent": "pink"}})
        self.refused("owner-only", "update_settings", self.ann, {"voting": False})

    def test_prefs_have_one_validator_per_key_and_belong_to_their_person(self):
        out = self.act("set_prefs", self.ann, {"set": {"sort": "votes", "expandedRounds": [1, 2]}})
        self.assertEqual(out["prefs"], {"sort": "votes", "expandedRounds": [1, 2]})
        self.refused("bad-field", "set_prefs", self.ann, {"set": {"sort": "random"}})
        self.refused("bad-field", "set_prefs", self.ann, {"set": {"unknown": 1}})
        self.act("set_prefs", self.ann, {"set": {"sort": None, "expandedRounds": None}})
        self.assertNotIn(self.ann, self.s.state["prefs"])
        self.assertNotIn("prefs", json.dumps(self.s.snapshot(self.bo)["people"]))

    def test_title_is_1_to_80_and_goal_up_to_200(self):
        self.act("set_title", HOST, {"title": "  Payment step  "})
        self.assertEqual(self.s.state["session"]["title"], "Payment step")
        self.refused("empty", "set_title", HOST, {"title": " "})
        self.refused("too-long", "set_title", HOST, {"title": "t" * 81})
        self.act("set_goal", HOST, {"goal": ""})
        self.refused("too-long", "set_goal", HOST, {"goal": "g" * 201})

    def test_set_title_and_goal_ops_follow_the_same_rules(self):
        self.apply({"op": "set-title", "title": "From Claude"}, {"op": "set-goal", "goal": "Decide"})
        self.assertEqual((self.s.state["session"]["title"], self.s.state["session"]["goal"]), ("From Claude", "Decide"))
        self.refused_ops("empty", {"op": "set-title", "title": "  "})

    def test_ending_refuses_guest_writes_except_heartbeat_prefs_and_notifications_read(self):
        self.open_round(text_q("Q1"))
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})
        self.act("end_session", HOST, {"on": True})
        self.refused("ended", "answer", self.bo, {"qid": "Q1", "text": "Late", "view": "tree"}, http=403)
        self.refused("ended", "chat", self.bo, {"text": "Hello?"}, http=403)
        self.refused("ended", "propose", self.ann, {"text": "One more"}, http=403)
        self.refused("ended", "lock", self.ann, {"qid": "Q1", "card": "c:rec"}, http=403)
        self.s.heartbeat(self.bo, {})
        self.act("set_prefs", self.bo, {"set": {"theme": "dark"}})
        self.act("read_notifications", self.bo, {"all": True})
        self.act("set_title", HOST, {"title": "Owner still writes"})

    def test_ending_writes_session_ended_with_the_later_list(self):
        prop = self.act("propose", self.ann, {"text": "Refunds"})["id"]
        self.act("act_on_proposal", HOST, {"id": prop, "action": "later", "reason": "Payments team"})
        self.assertEqual(self.act("end_session", HOST, {"on": True})["later"], 1)
        (ev,) = self.events("session-ended")
        self.assertEqual(ev["later"], [{"id": prop, "text": "Refunds", "reason": "Payments team"}])
        self.assertEqual(self.s.state["session"]["phase"]["kind"], "ended")

    def test_the_owner_can_reopen_an_ended_session(self):
        self.act("end_session", HOST, {"on": True})
        self.act("end_session", HOST, {"on": False})
        self.act("chat", self.ann, {"text": "Back again"})

    def test_link_rotation_is_owner_only(self):
        self.refused("owner-only", "rotate_guest_link", self.ann, {})
        self.refused("owner-only", "rotate_owner_link", self.ann, {})


# ---------------------------------------------------------------------------------------------
# Item 10: digest and event log
# ---------------------------------------------------------------------------------------------


class TestDigest(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")

    def digest(self):
        self.send()
        return self.events("round-sent")[-1]["digest"]

    def by_id(self, digest):
        return {q["id"]: q for q in digest["questions"]}

    def test_a_locked_question_reports_its_text_and_source_without_names_by_default(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Right column", "view": "focus"})
        self.act("lock", HOST, {"qid": "Q1", "card": f"p:{self.ann}"})
        d = self.digest()
        self.assertFalse(d["names"])
        self.assertEqual(self.by_id(d)["Q1"]["outcome"], {"kind": "locked", "text": "Right column", "source": "person"})
        self.assertNotIn("Ann", json.dumps(d))

    def test_digest_names_adds_by_for_answers_and_about_you(self):
        self.act("update_settings", HOST, {"digestNames": True})
        self.act("set_about_you", self.bo, {"techComfort": "low"})
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Right column", "view": "focus"})
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        d = self.digest()
        top = self.by_id(d)["Q1"]["outcome"]["top"][0]
        self.assertEqual(top, {"text": "Right column", "votes": 1, "source": "person", "by": "Ann"})
        self.assertEqual(d["aboutYou"], [{"name": "Bo", "techComfort": "low"}])

    def test_about_you_is_absent_without_digest_names(self):
        self.act("set_about_you", self.bo, {"techComfort": "low"})
        self.open_round(text_q("Q1"))
        self.assertNotIn("aboutYou", self.digest())

    def test_an_open_question_reports_its_top_three_answers_by_votes(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Ann's", "view": "focus"})
        self.act("answer", self.bo, {"qid": "Q1", "text": "Bo's", "view": "focus"})
        self.act("answer", self.cy, {"qid": "Q1", "text": "Cy's", "view": "focus"})
        self.act("answer", HOST, {"qid": "Q1", "text": "Kim's", "view": "host"})
        self.act("vote", self.ann, {"qid": "Q1", "card": f"p:{self.bo}", "on": True})
        self.act("vote", self.cy, {"qid": "Q1", "card": f"p:{self.bo}", "on": True})
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:rec", "on": True})
        top = self.by_id(self.digest())["Q1"]["outcome"]["top"]
        self.assertEqual([(t["text"], t["votes"], t["source"]) for t in top], [("Bo's", 2, "person"), ("Recommended for Q1.", 1, "claude-rec"), ("Ann's", 0, "person")])

    def test_an_untouched_question_is_unanswered(self):
        self.open_round(text_q("Q1"))
        self.assertEqual(self.by_id(self.digest())["Q1"]["outcome"], {"kind": "unanswered"})

    def test_a_gather_question_reports_each_answer_with_reaction_counts(self):
        self.open_round(text_q("Q1", purpose="gather"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Address form", "view": "focus"})
        self.act("react", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "reaction": "thumbs"})
        self.act("react", self.cy, {"qid": "Q1", "card": f"p:{self.ann}", "reaction": "idea"})
        out = self.by_id(self.digest())["Q1"]["outcome"]
        self.assertEqual(out, {"kind": "gathered", "answers": [{"text": "Address form", "reactions": {"thumbs": 1, "down": 0, "heart": 0, "idea": 1}}]})

    def test_a_poll_reports_counts_per_option_and_whether_it_closed(self):
        self.open_round(choice_q("Q1"))
        self.act("pick", self.ann, {"qid": "Q1", "option": "opt-2", "view": "focus"})
        self.act("pick", self.bo, {"qid": "Q1", "option": "opt-2", "view": "focus"})
        self.act("pick", self.cy, {"qid": "Q1", "option": "opt-1", "view": "focus"})
        out = self.by_id(self.digest())["Q1"]["outcome"]
        self.assertEqual(out, {"kind": "poll", "closed": False, "counts": [{"option": "Card", "votes": 1}, {"option": "Saved method", "votes": 2}, {"option": "None", "votes": 0}]})

    def test_late_answers_go_with_the_next_send(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.ack(1)
        self.open_round(text_q("Q2"))
        self.act("answer", self.bo, {"qid": "Q1", "text": "Thought of it later", "view": "tree"})
        d = self.digest()
        self.assertEqual(d["late"], [{"id": "Q1", "round": 1, "text": "Thought of it later"}])

    def test_needs_review_names_the_changed_question_and_its_state_now(self):
        self.open_round(text_q("Q1"), text_q("Q2", depends=["Q1"]))
        self.act("lock", HOST, {"qid": "Q1", "card": "c:rec"})
        self.act("edit_lock", HOST, {"qid": "Q1", "text": "Changed"})
        self.assertEqual(self.digest()["needsReview"], [{"id": "Q2", "because": "Q1", "now": {"kind": "locked", "text": "Changed"}}])

    def test_results_and_pending_proposals_are_in_the_digest(self):
        self.open_round(text_q("Q1"))
        rid = self.act("request", self.ann, {"qid": "Q1", "kind": "research", "text": "Look it up"})["id"]
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        xid = self.apply(TestRequests.result_op(None, rid))["results"][0]["id"]
        self.act("act_on_request", HOST, {"action": "publish", "id": xid})
        prop = self.act("propose", self.bo, {"text": "Ask about refunds"})["id"]
        d = self.digest()
        self.assertEqual(d["results"], [{"qid": "Q1", "id": xid, "kind": "research", "summary": "Most shops pin it right."}])
        self.assertEqual(d["proposals"], [{"id": prop, "text": "Ask about refunds"}])

    def test_an_unpublished_result_stays_out_of_the_digest(self):
        self.open_round(text_q("Q1"))
        rid = self.act("request", self.ann, {"qid": "Q1", "kind": "research", "text": "Look it up"})["id"]
        self.act("act_on_request", HOST, {"action": "run", "ids": [rid]})
        self.apply(TestRequests.result_op(None, rid))
        self.assertEqual(self.digest()["results"], [])

    def test_a_removed_persons_content_is_absent(self):
        self.act("update_settings", HOST, {"digestNames": True})
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Ann's secret idea", "view": "focus"})
        self.act("propose", self.ann, {"text": "Ann's proposal"})
        self.act("set_removed", HOST, {"pid": self.ann, "on": True})
        d = self.digest()
        self.assertNotIn("Ann", json.dumps(d))
        self.assertEqual(d["people"]["joined"], 2)

    def test_people_counts_who_joined_and_who_answered(self):
        self.open_round(text_q("Q1"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus", "deviceInfo": {"kind": "phone", "browser": "safari", "screen": {"w": 390, "h": 844}}})
        self.act("vote", self.bo, {"qid": "Q1", "card": "c:rec", "on": True})
        self.assertEqual(self.digest()["people"], {"joined": 3, "answered": 2, "devices": {"phone": 1, "tablet": 0, "computer": 0}})

    def test_every_digest_is_schema_valid(self):
        self.act("update_settings", HOST, {"digestNames": True})
        self.open_round(text_q("Q1"), choice_q("Q2"), text_q("Q3", purpose="gather"))
        self.act("answer", self.ann, {"qid": "Q1", "text": "Mine", "view": "focus"})
        self.act("pick", self.bo, {"qid": "Q2", "option": "opt-1", "view": "focus"})
        self.act("answer", self.cy, {"qid": "Q3", "text": "Slow", "view": "focus"})
        self.send()
        ev = self.events("round-sent")[-1]
        self.assertIsNone(session.schema.first_error(ev, session.schema.load("event", session.SCHEMA_DIR)))

    def test_handle_marks_events_handled_and_refuses_unknown_seqs(self):
        self.open_round(text_q("Q1"))
        self.send()
        seq = self.events("round-sent")[0]["seq"]
        self.apply({"op": "handle", "seqs": [seq]})
        self.assertEqual(self.s.state["log"]["handled"], [seq])
        self.refused_ops("not-found", {"op": "handle", "seqs": [seq + 5]})

    def test_events_carry_increasing_seqs_and_utc_times(self):
        self.open_round(text_q("Q1"))
        self.send()
        self.act("cancel_round", HOST, {})
        evs = self.events()
        self.assertEqual([e["seq"] for e in evs], [1, 2])
        self.assertRegex(evs[0]["at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(self.s.state["log"]["seq"], 2)


# ---------------------------------------------------------------------------------------------
# Item 11: apply ops all or nothing
# ---------------------------------------------------------------------------------------------


class TestApply(SessionCase):
    def test_ops_land_all_or_none(self):
        before = copy_state(self.s)
        disk = self.path.read_bytes()
        err = self.refused_ops("wrong-status", {"op": "set-title", "title": "Changed"}, {"op": "ack-round", "round": 1})
        self.assertEqual(err.details["op"], 1)
        self.assertEqual(self.s.state, before)
        self.assertEqual(self.path.read_bytes(), disk)

    def test_a_schema_invalid_op_is_refused_naming_its_index(self):
        err = self.refused_ops("bad-field", {"op": "set-title", "title": "Fine"}, {"op": "drop-session"})
        self.assertEqual(err.details["op"], 1)

    def test_add_asset_copies_a_png_from_the_data_folder_under_its_content_id(self):
        png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
        src = self.tmp / "shot.png"
        src.write_bytes(png)
        meta = self.apply({"op": "add-asset", "path": str(src), "scale": 2})["results"][0]
        self.assertRegex(meta["id"], r"^[0-9a-f]{16}\.png$")
        self.assertEqual((meta["kind"], meta["bytes"], meta["scale"]), ("image", len(png), 2))
        self.assertEqual((self.tmp / "assets" / meta["id"]).read_bytes(), png)

    def test_add_asset_reads_from_the_staging_folder(self):
        (self.tmp / "staging").mkdir()
        src = self.tmp / "staging" / "diagram.svg"
        src.write_text('<svg xmlns="http://www.w3.org/2000/svg"></svg>', encoding="utf-8")
        meta = self.apply({"op": "add-asset", "path": str(src)})["results"][0]
        self.assertTrue(meta["id"].endswith(".svg"))
        self.assertEqual(meta["scale"], 1)

    def test_add_asset_refuses_the_system_temp_folder_and_names_the_staging_folder(self):
        other = Path(tempfile.mkdtemp())  # under the system temp folder, beside the data folder
        self.addCleanup(shutil.rmtree, other, ignore_errors=True)
        src = other / "shot.png"
        src.write_bytes(b"\x89PNG\r\n\x1a\n")
        err = self.refused_ops("bad-field", {"op": "add-asset", "path": str(src)})
        self.assertEqual(err.details["field"], "path")
        self.assertIn(str((self.tmp / "staging").resolve()), err.message)

    def test_add_asset_refuses_a_file_inside_a_hidden_folder(self):
        (self.tmp / ".cache").mkdir()
        src = self.tmp / ".cache" / "shot.png"
        src.write_bytes(b"\x89PNG\r\n\x1a\nhidden")
        self.refused_ops("bad-field", {"op": "add-asset", "path": str(src)})

    def test_a_refused_apply_puts_back_the_scale_an_earlier_apply_recorded(self):
        src = self.tmp / "shot.png"
        src.write_bytes(b"\x89PNG\r\n\x1a\nscaled")
        aid = self.apply({"op": "add-asset", "path": str(src), "scale": 2})["results"][0]["id"]
        self.refused_ops("wrong-status", {"op": "add-asset", "path": str(src), "scale": 1}, {"op": "ack-round", "round": 1})
        self.assertEqual(json.loads((self.tmp / "assets" / f".{aid}.json").read_text(encoding="utf-8"))["scale"], 2)

    def test_add_asset_refuses_a_file_whose_bytes_are_not_an_allowed_type(self):
        src = self.tmp / "notes.png"
        src.write_text("just text", encoding="utf-8")
        self.refused_ops("bad-field", {"op": "add-asset", "path": str(src)})

    def test_add_asset_refuses_hidden_files_such_as_the_secrets_file(self):
        src = self.tmp / ".shared-secrets.json"
        src.write_text("<html>", encoding="utf-8")
        self.refused_ops("bad-field", {"op": "add-asset", "path": str(src), "as": "html"})

    def test_a_refused_apply_removes_the_asset_it_copied(self):
        src = self.tmp / "shot.png"
        src.write_bytes(b"\x89PNG\r\n\x1a\nrefused")
        self.refused_ops("wrong-status", {"op": "add-asset", "path": str(src)}, {"op": "ack-round", "round": 1})
        self.assertEqual(sorted(p.name for p in (self.tmp / "assets").iterdir() if p.name.endswith(".png") and p.name not in (PNG, "1111222233334444.png")), [])

    def test_assets_from_add_asset_are_usable_only_in_a_later_apply(self):
        q = choice_q("Q1")
        q["format"]["options"][0]["image"] = "abcdefabcdefabcd.png"
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})

    def test_add_and_remove_reference_ops(self):
        self.open_round(text_q("Q1"))
        self.apply({"op": "add-reference", "qid": "Q1", "reference": {"kind": "link", "url": "https://example.com/a"}})
        self.apply({"op": "remove-reference", "qid": "Q1", "index": 0})
        self.assertEqual(self.question("Q1")["references"], [])

    def test_the_phase_one_ops_samples_parse(self):
        for name in ("ops-open-round.json", "ops-result.json", "ops-handle.json"):
            self.assertIsNone(session.ops_error(json.loads((FIXTURES / name).read_text(encoding="utf-8"))), name)

    def test_one_apply_can_ack_and_open_the_next_round(self):
        self.open_round(text_q("Q1"))
        self.send()
        out = self.apply({"op": "ack-round", "round": 1}, {"op": "open-round", "questions": [text_q("Q2")]}, {"op": "handle", "seqs": [1]})
        self.assertEqual([r.get("round") for r in out["results"][:2]], [1, 2])
        self.assertEqual([r["status"]["kind"] for r in self.s.state["rounds"]], ["closed", "open"])


# ---------------------------------------------------------------------------------------------
# Snapshots: anonymous view, per-viewer view, Show names masking
# ---------------------------------------------------------------------------------------------


class TestSnapshots(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})
        self.open_round(text_q("Q1"))
        self.act("answer", self.bo, {"qid": "Q1", "text": "Bo's answer", "view": "focus", "deviceInfo": {"kind": "phone", "browser": "safari", "screen": {"w": 390, "h": 844}}})
        self.act("vote", self.cy, {"qid": "Q1", "card": f"p:{self.bo}", "on": True})
        self.act("vote", self.ann, {"qid": "Q1", "card": f"p:{self.bo}", "on": True})

    def card(self, snap, ref):
        return next(c for c in snap["cards"]["Q1"] if c["ref"] == ref)

    def test_the_anonymous_view_has_exactly_four_keys(self):
        self.assertEqual(self.s.anonymous_view(), {"title": "Checkout redesign", "ended": False, "joinNeedsKey": False, "schemaVersion": 1})
        self.act("rotate_guest_link", HOST, {})
        self.assertTrue(self.s.anonymous_view()["joinNeedsKey"])

    def test_a_removed_person_reads_nothing(self):
        self.act("set_removed", HOST, {"pid": self.cy, "on": True})
        with self.assertRaises(session.DomainError) as ctx:
            self.s.snapshot(self.cy)
        self.assertEqual(ctx.exception.code, "removed")

    def test_full_names_show_names_and_voter_ids(self):
        snap = self.s.snapshot(self.cy)
        self.assertIn("Bo", [p["name"] for p in snap["people"]])
        self.assertEqual(self.card(snap, f"p:{self.bo}")["votes"], sorted([self.ann, self.cy]))

    def test_initials_send_initials_and_counts_keeping_only_the_viewers_own_vote(self):
        self.act("update_settings", HOST, {"names": "initials"})
        snap = self.s.snapshot(self.cy)
        names = {p["name"] for p in snap["people"]}
        self.assertNotIn("Bo", names)
        self.assertIn("B", names)
        votes = self.card(snap, f"p:{self.bo}")["votes"]
        self.assertEqual(sorted(votes), sorted(["", self.cy]))
        self.assertNotIn(self.ann, json.dumps(snap["cards"]))

    def test_someone_shows_guests_someone(self):
        self.act("update_settings", HOST, {"names": "someone"})
        snap = self.s.snapshot(self.cy)
        self.assertEqual({p["name"] for p in snap["people"]}, {"Someone"})
        for name in ("Ann", "Bo", "Kim"):
            self.assertNotIn(f'"{name}"', json.dumps(snap))

    def test_owner_and_leaders_always_get_full_names(self):
        self.act("update_settings", HOST, {"names": "someone"})
        for viewer in (HOST, self.ann):
            snap = self.s.snapshot(viewer)
            self.assertIn("Bo", [p["name"] for p in snap["people"]])
            self.assertIn(self.cy, self.card(snap, f"p:{self.bo}")["votes"])

    def test_credentials_log_and_others_prefs_and_notifications_never_appear(self):
        self.act("set_prefs", self.bo, {"set": {"theme": "dark"}})
        self.act("chat", self.ann, {"text": "@Bo hello"})
        self.send()
        for viewer in (HOST, self.ann, self.cy):
            snap = self.s.snapshot(viewer)
            self.assertFalse({"credentials", "log"} & set(snap))
            text = json.dumps(snap)
            self.assertNotIn(self.owner_token, text)
            self.assertNotIn("tokenHash", text)
            if viewer != self.bo:
                self.assertNotIn("mentioned you", json.dumps(snap["me"]))

    def test_view_and_device_info_reach_only_the_owner(self):
        self.assertNotIn("deviceInfo", json.dumps(self.s.snapshot(self.cy)))
        self.assertNotIn("deviceInfo", json.dumps(self.s.snapshot(self.ann)))
        details = self.s.snapshot(HOST)["cardDetails"]["Q1"][f"p:{self.bo}"]
        self.assertEqual(details["deviceInfo"]["kind"], "phone")

    def test_a_removed_persons_content_is_hidden_until_restored(self):
        self.act("set_removed", HOST, {"pid": self.bo, "on": True})
        snap = self.s.snapshot(self.cy)
        self.assertNotIn("Bo's answer", json.dumps(snap))
        self.assertNotIn(self.bo, [p["pid"] for p in snap["people"]])
        self.assertIn(self.bo, [p["pid"] for p in self.s.snapshot(HOST)["removed"]])
        self.act("set_removed", HOST, {"pid": self.bo, "on": False})
        self.assertIn("Bo's answer", json.dumps(self.s.snapshot(self.cy)))

    def test_moderators_see_who_is_behind(self):
        self.assertEqual(self.s.snapshot(self.ann)["behind"], {self.ann: 0, self.bo: 0, self.cy: 0})
        self.assertNotIn("behind", self.s.snapshot(self.cy))

    def test_a_snapshot_carries_schema_version_and_rev(self):
        snap = self.s.snapshot(self.cy)
        self.assertEqual((snap["schemaVersion"], snap["rev"]), (1, self.s.state["rev"]))

    def test_the_shared_part_is_built_once_per_rev(self):
        first = self.s._base()
        self.assertIs(self.s._base(), first)
        self.act("chat", self.cy, {"text": "New rev"})
        self.assertIsNot(self.s._base(), first)

    def test_a_snapshot_does_not_change_when_state_changes_later(self):
        snap = self.s.snapshot(self.cy)
        text = json.dumps(snap)
        self.act("answer", self.bo, {"qid": "Q1", "text": "Edited later", "view": "focus"})
        self.assertEqual(json.dumps(snap), text)

    def test_guests_still_read_the_session_after_it_ends(self):
        self.act("end_session", HOST, {"on": True})
        snap = self.s.snapshot(self.cy)
        self.assertTrue(snap["ended"])
        self.assertIn("Bo's answer", json.dumps(snap))
        self.assertTrue(self.s.anonymous_view()["ended"])

    def test_presence_shows_who_is_here_until_they_go_offline(self):
        self.clock.tick(session.OFFLINE_AFTER)  # the joins' own presence has lapsed
        self.s.heartbeat(self.bo, {"q": "Q1", "typing": True})
        self.assertEqual([p["pid"] for p in self.s.snapshot(self.cy)["presence"]], [self.bo])
        self.clock.tick(session.OFFLINE_AFTER + 1)
        self.assertEqual(self.s.snapshot(self.cy)["presence"], [])


# ---------------------------------------------------------------------------------------------
# Phase 4b: formats (multi, scale, rank), Something else, Disagree, the down reaction, diagrams.
# Expected values come from the amendments "Reactions and formats" and "Presence" and triage 22;
# digest numbers are worked by hand in each test's comment.
# ---------------------------------------------------------------------------------------------


class FormatCase(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo, self.cy = self.people("Ann", "Bo", "Cy")
        self.open_round(
            options_q("Q1", "multi", ("Card", "PayPal", "Bank transfer")),
            scale_q("Q2"),
            options_q("Q3", "rank", ("Speed", "Trust", "Fewer fields")),
            choice_q("Q4", purpose="decide"),
            text_q("Q5"),
            text_q("Q6", purpose="gather"),
        )

    def pick(self, pid, qid, **body):
        return self.act("pick", pid, {"qid": qid, "view": "focus", **body})

    def mine(self, qid, pid):
        return next(c for c in self.s.state["cards"][qid] if c["kind"] == "person" and c["pid"] == pid)

    def outcome(self, qid):
        self.send()
        digest = self.events("round-sent")[-1]["digest"]
        self.assertIsNone(session.schema.first_error(digest, session.schema.load("event", session.SCHEMA_DIR)["$defs"]["digest"], "$", session.schema.load("event", session.SCHEMA_DIR)))
        return next(q for q in digest["questions"] if q["id"] == qid)


class TestFormatPicks(FormatCase):
    def test_multi_pick_is_a_subset_of_the_option_ids(self):
        self.assertEqual(self.pick(self.ann, "Q1", options=["opt-3", "opt-1"]), {"picks": ["opt-1", "opt-3"]})
        self.assertEqual(self.mine("Q1", self.ann)["picks"], ["opt-1", "opt-3"])
        self.assertNotIn(self.ann, self.s.state["votes"].get("Q1", {}))
        self.refused("bad-field", "pick", self.ann, {"qid": "Q1", "options": ["opt-1", "opt-1"], "view": "focus"}, http=400)
        self.refused("no-such-option", "pick", self.ann, {"qid": "Q1", "options": ["opt-1", "opt-9"], "view": "focus"}, http=400)

    def test_multi_pick_of_an_empty_subset_withdraws_the_pick(self):
        self.pick(self.ann, "Q1", options=["opt-2"])
        self.pick(self.ann, "Q1", options=[])
        self.assertEqual([c for c in self.s.state["cards"]["Q1"] if c["kind"] == "person"], [])

    def test_multi_takes_two_to_eight_options_from_claude(self):
        self.send()
        self.ack(1)
        nine = options_q("Q7", "multi", [f"Way {i}" for i in range(1, 10)])
        self.refused_ops("bad-field", {"op": "open-round", "questions": [nine]})
        self.refused_ops("bad-field", {"op": "open-round", "questions": [options_q("Q7", "rank", ("Only", "Two"))]})
        self.refused_ops("bad-field", {"op": "open-round", "questions": [options_q("Q7", "choice", ("A", "B", "C", "D", "E"))]})

    def test_scale_value_must_be_in_range(self):
        for bad in (0, 6, 2.5, "3", True):
            with self.subTest(value=bad):
                self.refused("bad-field", "pick", self.ann, {"qid": "Q2", "value": bad, "view": "focus"}, http=400)
        self.pick(self.ann, "Q2", value=5, comment="Every time")
        card = self.mine("Q2", self.ann)
        self.assertEqual((card["value"], card["text"]), (5, "Every time"))

    def test_rank_needs_a_full_order_of_the_options(self):
        self.refused("bad-field", "pick", self.ann, {"qid": "Q3", "order": ["opt-2", "opt-1"], "view": "focus"}, http=400)
        self.refused("bad-field", "pick", self.ann, {"qid": "Q3", "order": ["opt-2", "opt-2", "opt-1", "opt-3"], "view": "focus"}, http=400)
        self.pick(self.ann, "Q3", order=["opt-2", "opt-3", "opt-1"])
        self.assertEqual(self.mine("Q3", self.ann)["order"], ["opt-2", "opt-3", "opt-1"])

    def test_multi_scale_and_rank_take_a_pick_not_a_written_answer(self):
        for qid in ("Q1", "Q3"):  # Q2 is a poll, which refuses a written answer as wrong-purpose first
            with self.subTest(qid=qid):
                self.refused("bad-action", "answer", self.ann, {"qid": qid, "text": "Words", "view": "focus"}, http=400)

    def test_scale_options_are_its_values_with_the_end_and_middle_labels(self):
        cards = [c["option"] for c in self.s.state["cards"]["Q2"]]
        self.assertEqual(cards, ["1", "2", "3", "4", "5"])
        self.act("lock", HOST, {"qid": "Q2", "card": "o:3"})
        self.assertEqual(self.s.state["locks"]["Q2"]["source"]["text"], "3 (Sometimes)")


class TestFormatDigest(FormatCase):
    def test_multi_digest_counts_each_option_picked(self):
        # Ann Card+Bank, Bo Card, Cy PayPal and her own option: Card 2, PayPal 1, Bank 1; 3 people.
        self.pick(self.ann, "Q1", options=["opt-1", "opt-3"])
        self.pick(self.bo, "Q1", options=["opt-1"])
        self.pick(self.cy, "Q1", options=["opt-2", "other"], other="Apple Pay")
        out = self.outcome("Q1")["outcome"]
        self.assertEqual(out["counts"], [{"option": "Card", "picks": 2}, {"option": "PayPal", "picks": 1}, {"option": "Bank transfer", "picks": 1}])
        self.assertEqual((out["kind"], out["people"], out["others"]), ("multi", 3, [{"text": "Apple Pay", "backers": 1}]))

    def test_scale_digest_gives_counts_mean_and_median(self):
        # Values 1, 2, 2, 5: mean 10 / 4 = 2.5, median (2 + 2) / 2 = 2.
        for pid, v in ((self.ann, 1), (self.bo, 2), (self.cy, 2), (HOST, 5)):
            self.pick(pid, "Q2", value=v)
        out = self.outcome("Q2")["outcome"]
        self.assertEqual(out["counts"], [{"value": 1, "people": 1}, {"value": 2, "people": 2}, {"value": 3, "people": 0}, {"value": 4, "people": 0}, {"value": 5, "people": 1}])
        self.assertEqual((out["mean"], out["median"], out["people"], out["closed"]), (2.5, 2, 4, False))

    def test_scale_mean_is_rounded_to_two_places_and_the_odd_median_is_the_middle(self):
        # Values 1, 4, 5: mean 10 / 3 = 3.33, median 4.
        for pid, v in ((self.ann, 1), (self.bo, 4), (self.cy, 5)):
            self.pick(pid, "Q2", value=v)
        out = self.outcome("Q2")["outcome"]
        self.assertEqual((out["mean"], out["median"]), (3.33, 4))

    def test_rank_digest_gives_borda_totals_and_full_order_counts(self):
        # 3 options: first 2 points, second 1, last 0. Ann and Bo Trust > Speed > Fewer, Cy Speed > Trust > Fewer:
        # Trust 2 + 2 + 1 = 5, Speed 1 + 1 + 2 = 4, Fewer fields 0.
        self.pick(self.ann, "Q3", order=["opt-2", "opt-1", "opt-3"])
        self.pick(self.bo, "Q3", order=["opt-2", "opt-1", "opt-3"])
        self.pick(self.cy, "Q3", order=["opt-1", "opt-2", "opt-3"])
        out = self.outcome("Q3")["outcome"]
        self.assertEqual(out["borda"], [{"option": "Trust", "points": 5}, {"option": "Speed", "points": 4}, {"option": "Fewer fields", "points": 0}])
        self.assertEqual(out["orders"], [{"order": ["Trust", "Speed", "Fewer fields"], "people": 2}, {"order": ["Speed", "Trust", "Fewer fields"], "people": 1}])

    def test_lock_top_answer_on_a_rank_takes_the_borda_winner(self):
        # Ann Speed > Trust > Fewer (Speed 2), Bo Trust > Fewer > Speed (Trust 2, Speed 0), Cy Trust > Speed > Fewer:
        # Trust 1 + 2 + 2 = 5, Speed 2 + 0 + 1 = 3.
        self.pick(self.ann, "Q3", order=["opt-1", "opt-2", "opt-3"])
        self.pick(self.bo, "Q3", order=["opt-2", "opt-3", "opt-1"])
        self.pick(self.cy, "Q3", order=["opt-2", "opt-1", "opt-3"])
        self.assertEqual(self.act("lock", HOST, {"qid": "Q3"})["text"], "Trust")

    def test_an_untouched_format_question_is_unanswered(self):
        self.assertEqual(self.outcome("Q1")["outcome"], {"kind": "unanswered"})

    def test_a_late_multi_pick_reads_as_its_option_names(self):
        self.send()
        self.ack(1)
        self.apply({"op": "open-round", "questions": [text_q("Q7")]})
        self.pick(self.ann, "Q1", options=["opt-1", "opt-2"])
        self.send()
        late = self.events("round-sent")[-1]["digest"]["late"]
        self.assertEqual(late, [{"id": "Q1", "round": 1, "text": "Card, PayPal"}])


class TestSomethingElse(FormatCase):
    def test_the_server_adds_one_something_else_option_to_choice_multi_and_rank(self):
        for qid in ("Q1", "Q3", "Q4"):
            options = self.question(qid)["format"]["options"]
            self.assertEqual(options[-1], {"id": "other", "label": "Something else…", "other": True})
            self.assertEqual(sum(1 for o in options if o.get("other")), 1)
            self.assertNotIn("o:other", [session.card_ref(c) for c in self.s.state["cards"][qid]])
        self.assertNotIn("options", self.question("Q2")["format"])

    def test_claude_cannot_write_the_something_else_option(self):
        q = options_q("Q7", "choice", ("A", "B"))
        q["format"]["options"].append({"id": "other", "label": "Other", "other": True})
        self.send()
        self.ack(1)
        rev = self.s.state["rev"]
        self.refused_ops("bad-field", {"op": "open-round", "questions": [q]})
        self.assertEqual(self.s.state["rev"], rev)

    def test_picking_something_else_needs_text(self):
        self.refused("empty", "pick", self.ann, {"qid": "Q4", "option": "other", "view": "focus"}, http=400)
        self.refused("bad-field", "pick", self.ann, {"qid": "Q4", "option": "opt-1", "other": "Mine", "view": "focus"}, http=400)
        self.pick(self.ann, "Q4", option="other", other="Pay by bank app")
        card = self.mine("Q4", self.ann)
        self.assertEqual((card["pick"], card["text"]), ("other", "Pay by bank app"))
        self.assertNotIn(self.ann, self.s.state["votes"]["Q4"])

    def test_others_pick_a_persons_own_option_on_a_choice_question(self):
        # Ann's own option, backed by Bo (whose pick moves off Card) and by Cy: 3 with Ann herself.
        self.pick(self.ann, "Q4", option="other", other="Pay by bank app")
        self.pick(self.bo, "Q4", option="opt-1")
        self.act("vote", self.bo, {"qid": "Q4", "card": f"p:{self.ann}", "on": True})
        self.act("vote", self.cy, {"qid": "Q4", "card": f"p:{self.ann}", "on": True})
        self.assertEqual(self.s.state["votes"]["Q4"], {self.bo: f"p:{self.ann}", self.cy: f"p:{self.ann}"})
        top = self.outcome("Q4")["outcome"]["top"]
        self.assertEqual(top[0], {"text": "Pay by bank app", "votes": 3, "source": "person", "other": True})

    def test_others_vote_on_a_persons_own_option_on_multi_and_rank(self):
        self.pick(self.ann, "Q1", options=["other"], other="Apple Pay")
        self.pick(self.bo, "Q1", options=["opt-1"])
        self.act("vote", self.bo, {"qid": "Q1", "card": f"p:{self.ann}", "on": True})
        self.assertEqual(self.mine("Q1", self.bo)["picks"], ["opt-1"])
        self.pick(self.cy, "Q3", order=["opt-1", "other", "opt-2", "opt-3"], other="Accessibility")
        self.act("vote", self.ann, {"qid": "Q3", "card": f"p:{self.cy}", "on": True})
        self.assertEqual(self.s.state["votes"]["Q3"], {self.ann: f"p:{self.cy}"})

    def test_a_plain_answer_on_an_option_question_takes_no_vote(self):
        self.pick(self.ann, "Q4", option="opt-1", comment="Fastest")
        self.refused("bad-action", "vote", self.bo, {"qid": "Q4", "card": f"p:{self.ann}", "on": True}, http=400)

    def test_scale_and_confirm_take_a_comment_not_something_else(self):
        self.refused("bad-field", "pick", self.ann, {"qid": "Q2", "value": 3, "other": "Mine", "view": "focus"}, http=400)
        self.assertNotIn("options", self.question("Q2")["format"])

    def test_leaving_something_else_drops_the_votes_for_it(self):
        self.pick(self.ann, "Q4", option="other", other="Pay by bank app")
        self.act("vote", self.bo, {"qid": "Q4", "card": f"p:{self.ann}", "on": True})
        self.pick(self.ann, "Q4", option="opt-2")
        self.assertEqual(self.s.state["votes"]["Q4"], {self.ann: "o:opt-2"})

    def test_rewording_your_own_option_marks_it_edited_after_votes(self):
        self.pick(self.ann, "Q4", option="other", other="Pay by bank app")
        self.act("vote", self.bo, {"qid": "Q4", "card": f"p:{self.ann}", "on": True})
        self.pick(self.ann, "Q4", option="other", other="Pay from my banking app")
        self.assertEqual(self.mine("Q4", self.ann)["editedAfterVotes"], 1)
        self.assertEqual(self.s.state["votes"]["Q4"], {self.bo: f"p:{self.ann}"})


class TestDisagree(FormatCase):
    def test_disagree_needs_a_reason_of_1_to_200_characters(self):
        self.refused("empty", "disagree", self.ann, {"qid": "Q5", "card": "c:rec"}, http=400)
        self.refused("empty", "disagree", self.ann, {"qid": "Q5", "card": "c:rec", "reason": "   "}, http=400)
        self.refused("too-long", "disagree", self.ann, {"qid": "Q5", "card": "c:rec", "reason": "x" * 201}, http=400)
        self.act("disagree", self.ann, {"qid": "Q5", "card": "c:rec", "reason": "x" * 200})
        self.assertEqual(self.s.state["disagreements"]["Q5"], [{"pid": self.ann, "card": "c:rec", "reason": "x" * 200, "at": self.clock.t}])

    def test_disagree_is_for_decide_questions_only(self):
        self.act("answer", self.ann, {"qid": "Q6", "text": "Slow form", "view": "focus"})
        self.refused("wrong-purpose", "disagree", self.bo, {"qid": "Q6", "card": f"p:{self.ann}", "reason": "Not for me"}, http=409)
        self.refused("wrong-purpose", "disagree", self.bo, {"qid": "Q2", "card": "o:3", "reason": "Not for me"}, http=409)

    def test_a_disagreement_leaves_the_vote_counts_and_shows_in_the_digest(self):
        self.act("vote", self.ann, {"qid": "Q5", "card": "c:rec", "on": True})
        self.act("disagree", self.bo, {"qid": "Q5", "card": "c:rec", "reason": "Too costly to build"})
        self.assertEqual(self.s._tally("Q5")["c:rec"], 1)
        q = self.outcome("Q5")
        self.assertEqual(q["disagreements"], [{"text": "Recommended for Q5.", "reason": "Too costly to build"}])
        self.assertEqual(q["outcome"]["top"][0], {"text": "Recommended for Q5.", "votes": 1, "source": "claude-rec"})

    def test_one_disagreement_per_person_per_answer_and_on_false_takes_it_back(self):
        self.act("disagree", self.bo, {"qid": "Q5", "card": "c:a", "reason": "First"})
        self.act("disagree", self.bo, {"qid": "Q5", "card": "c:a", "reason": "Second"})
        self.assertEqual([d["reason"] for d in self.s.state["disagreements"]["Q5"]], ["Second"])
        self.act("disagree", self.bo, {"qid": "Q5", "card": "c:a", "on": False})
        self.assertNotIn("Q5", self.s.state["disagreements"])

    def test_disagreeing_with_your_own_answer_is_refused(self):
        self.act("answer", self.ann, {"qid": "Q5", "text": "Mine", "view": "focus"})
        self.refused("cannot-vote-own", "disagree", self.ann, {"qid": "Q5", "card": f"p:{self.ann}", "reason": "Changed my mind"}, http=400)

    def test_a_withdrawn_answer_takes_its_disagreements_with_it(self):
        self.act("answer", self.ann, {"qid": "Q5", "text": "Mine", "view": "focus"})
        self.act("disagree", self.bo, {"qid": "Q5", "card": f"p:{self.ann}", "reason": "No"})
        self.act("answer", self.ann, {"qid": "Q5", "text": "", "view": "focus"})
        self.assertNotIn("Q5", self.s.state["disagreements"])

    def test_who_disagreed_is_masked_where_names_are(self):
        self.act("update_settings", HOST, {"names": "someone"})
        self.act("disagree", self.bo, {"qid": "Q5", "card": "c:a", "reason": "No"})
        self.assertEqual([d["pid"] for d in self.s.snapshot(self.cy)["disagreements"]["Q5"]], [""])
        self.assertEqual([d["pid"] for d in self.s.snapshot(self.bo)["disagreements"]["Q5"]], [self.bo])

    def test_a_merge_moves_the_merged_persons_disagreement(self):
        self.act("disagree", self.cy, {"qid": "Q5", "card": "c:a", "reason": "No"})
        self.act("merge_people", HOST, {"from": self.cy, "to": self.bo})
        self.assertEqual([d["pid"] for d in self.s.state["disagreements"]["Q5"]], [self.bo])

    def test_down_refused_on_decide_and_counted_on_gather(self):
        self.act("answer", self.ann, {"qid": "Q5", "text": "Mine", "view": "focus"})
        self.refused("wrong-purpose", "react", self.bo, {"qid": "Q5", "card": f"p:{self.ann}", "reaction": "down"}, http=409)
        self.act("answer", self.ann, {"qid": "Q6", "text": "Slow form", "view": "focus"})
        self.act("react", self.bo, {"qid": "Q6", "card": f"p:{self.ann}", "reaction": "down"})
        answers = self.outcome("Q6")["outcome"]["answers"]
        self.assertEqual(answers, [{"text": "Slow form", "reactions": {"thumbs": 0, "down": 1, "heart": 0, "idea": 0}}])


class TestDiagramReference(SessionCase):
    SVG = "abcdefabcdef0123.svg"

    def setUp(self):
        super().setUp()
        (self.tmp / "assets" / self.SVG).write_bytes(b"<svg/>")
        self.open_round(text_q("Q1"))

    def test_a_diagram_reference_needs_an_svg_asset_and_alt_text(self):
        self.refused_ops("bad-field", {"op": "add-reference", "qid": "Q1", "reference": {"kind": "diagram", "asset": self.SVG}})
        self.refused_ops("empty", {"op": "add-reference", "qid": "Q1", "reference": {"kind": "diagram", "asset": self.SVG, "alt": "  "}})
        self.refused_ops("bad-field", {"op": "add-reference", "qid": "Q1", "reference": {"kind": "diagram", "asset": PNG, "alt": "Chart"}})
        self.apply({"op": "add-reference", "qid": "Q1", "reference": {"kind": "diagram", "asset": self.SVG, "alt": "Funnel: most people leave at payment."}})
        self.assertEqual(self.question("Q1")["references"], [{"kind": "diagram", "asset": self.SVG, "alt": "Funnel: most people leave at payment."}])


class TestPresenceStates(SessionCase):
    def setUp(self):
        super().setUp()
        self.ann, self.bo = self.people("Ann", "Bo")
        self.clock.tick(session.OFFLINE_AFTER)  # the joins' own presence has lapsed

    def state_of(self, pid):
        return next((p for p in self.s.snapshot(HOST)["presence"] if p["pid"] == pid), None)

    def beat(self, pid, **body):
        return self.s.heartbeat(pid, body)

    def test_presence_thresholds_offline_after_90_seconds_without_a_beat(self):
        self.beat(self.ann)
        self.clock.tick(89)
        self.assertEqual(self.state_of(self.ann)["state"], "active")
        self.clock.tick(1)
        self.assertIsNone(self.state_of(self.ann))

    def test_presence_thresholds_away_after_5_minutes_without_input(self):
        self.beat(self.ann, lastInput=299)
        self.assertEqual(self.state_of(self.ann), {"pid": self.ann, "q": "", "typing": False, "chatTyping": False, "state": "active"})
        self.clock.tick(2)
        self.beat(self.ann, lastInput=301)
        self.assertEqual(self.state_of(self.ann)["state"], "away")
        self.assertEqual(self.state_of(self.ann)["since"], self.clock.t - 1)

    def test_presence_thresholds_hidden_is_away_since_it_hid(self):
        self.beat(self.ann, visible=True)
        self.clock.tick(10)
        hid = self.clock.t
        self.beat(self.ann, visible=False)
        self.clock.tick(30)
        self.beat(self.ann, visible=False)
        self.assertEqual((self.state_of(self.ann)["state"], self.state_of(self.ann)["since"]), ("away", hid))
        self.clock.tick(30)
        self.beat(self.ann, visible=True)
        self.assertEqual(self.state_of(self.ann)["state"], "active")

    def test_a_visibility_change_beats_at_once(self):
        self.beat(self.ann, visible=True)
        self.beat(self.ann, visible=False)
        self.assertEqual(self.state_of(self.ann)["state"], "away")
        with self.assertRaises(session.DomainError) as ctx:
            self.beat(self.ann, visible=False)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "slow-down"))

    def test_flipping_visibility_is_limited_to_one_change_a_second(self):
        self.beat(self.ann, visible=True)
        self.clock.tick(2)
        self.beat(self.ann, visible=False)
        with self.assertRaises(session.DomainError) as ctx:
            self.beat(self.ann, visible=True)
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "slow-down"))
        self.clock.tick(1)
        self.beat(self.ann, visible=True)
        self.assertEqual(self.state_of(self.ann)["state"], "active")

    def test_manual_away_lasts_while_sent_and_ends_with_the_next_input_beat(self):
        self.beat(self.ann, away=True)
        set_at = self.clock.t
        self.clock.tick(5)
        self.beat(self.ann, away=True, lastInput=5)
        self.assertEqual((self.state_of(self.ann)["state"], self.state_of(self.ann)["since"]), ("away", set_at))
        self.clock.tick(5)
        self.beat(self.ann, lastInput=0)
        self.assertEqual(self.state_of(self.ann)["state"], "active")

    def test_typing_shows_for_5_seconds_after_the_beat_that_set_it(self):
        self.beat(self.ann, typing=True, chatTyping=True)
        self.clock.tick(4)
        self.assertEqual((self.state_of(self.ann)["typing"], self.state_of(self.ann)["chatTyping"]), (True, True))
        self.clock.tick(1)
        self.assertEqual((self.state_of(self.ann)["typing"], self.state_of(self.ann)["chatTyping"]), (False, False))

    def test_heartbeat_fields_are_checked(self):
        bad = (({"visible": "no"}, "visible"), ({"lastInput": -3}, "lastInput"), ({"lastInput": float("inf")}, "lastInput"), ({"away": "yes"}, "away"))
        for body, field in bad:
            with self.subTest(body=body):
                with self.assertRaises(session.DomainError) as ctx:
                    self.s.heartbeat(self.bo, body)
                self.assertEqual((ctx.exception.code, ctx.exception.details["field"]), ("bad-field", field))

    def test_two_tabs_of_one_person_each_beat_once_a_second(self):
        self.beat(self.ann, tab="laptop")
        self.beat(self.ann, tab="phone")  # same instant, another tab: not a second beat of the first
        with self.assertRaises(session.DomainError) as ctx:
            self.beat(self.ann, tab="laptop")
        self.assertEqual((ctx.exception.http, ctx.exception.code), (429, "slow-down"))
        self.beat(self.ann, tab="phone", visible=False)  # a change beat on its own tab
        with self.assertRaises(session.DomainError):
            self.beat(self.ann, tab="phone", visible=True)

    def test_a_hidden_tab_does_not_make_a_person_in_use_elsewhere_away(self):
        self.beat(self.ann, tab="a", visible=True)
        self.beat(self.ann, tab="b", visible=False)
        self.assertEqual(self.state_of(self.ann)["state"], "active")
        for _ in range(3):  # the hidden tab's throttled beats, one a minute, change nothing
            self.clock.tick(20)
            self.beat(self.ann, tab="a", visible=True)
            self.beat(self.ann, tab="b", visible=False)
            self.assertEqual(self.state_of(self.ann)["state"], "active")
        self.clock.tick(5)
        hid = self.clock.t
        self.beat(self.ann, tab="a", visible=False)
        self.assertEqual((self.state_of(self.ann)["state"], self.state_of(self.ann)["since"]), ("away", hid))

    def test_away_only_when_every_live_tab_is_hidden_idle_or_snoozed(self):
        self.beat(self.ann, tab="a", away=True)
        self.beat(self.ann, tab="b", lastInput=0)
        self.assertEqual(self.state_of(self.ann)["state"], "active")
        self.clock.tick(2)
        self.beat(self.ann, tab="b", lastInput=301)
        self.assertEqual(self.state_of(self.ann)["state"], "away")

    def test_a_tab_that_stopped_beating_no_longer_counts(self):
        self.beat(self.ann, tab="closed", visible=True)
        self.beat(self.ann, tab="hidden", visible=False)
        self.clock.tick(60)
        self.beat(self.ann, tab="hidden", visible=False)
        self.assertEqual(self.state_of(self.ann)["state"], "active")  # the visible tab's last beat is 60 s old
        self.clock.tick(30)  # 90 s since the visible tab last beat: it is gone, the hidden one remains
        self.assertEqual(self.state_of(self.ann)["state"], "away")
        self.clock.tick(60)  # 90 s since any tab beat: offline
        self.assertIsNone(self.state_of(self.ann))

    def test_question_and_typing_come_from_the_latest_beat(self):
        self.beat(self.ann, tab="a", q="Q1", typing=True)
        self.clock.tick(1)
        self.beat(self.ann, tab="b", q="Q3", typing=False)
        self.assertEqual((self.state_of(self.ann)["q"], self.state_of(self.ann)["typing"]), ("Q3", False))

    def test_a_person_keeps_at_most_8_tabs_the_oldest_dropped(self):
        self.beat(self.ann, tab="t0", visible=True)  # the only visible tab
        for i in range(1, 8):
            self.clock.tick(1)
            self.beat(self.ann, tab=f"t{i}", visible=False)
        self.assertEqual(self.state_of(self.ann)["state"], "active")
        self.clock.tick(1)
        self.beat(self.ann, tab="t8", visible=False)  # a ninth tab: t0, the least recent, is forgotten
        self.assertEqual(self.state_of(self.ann)["state"], "away")

    def test_the_tab_id_is_a_short_string(self):
        for body in ({"tab": "x" * 33}, {"tab": 7}, {"tab": ""}, {"tab": "\u0000‮<img src=x>"}, {"tab": "../../etc"}, {"tab": " "}):
            with self.subTest(body=body):
                with self.assertRaises(session.DomainError) as ctx:
                    self.s.heartbeat(self.bo, body)
                self.assertEqual((ctx.exception.code, ctx.exception.details["field"]), ("bad-field", "tab"))
        self.beat(self.bo, tab="x" * 32)

    def test_new_tab_ids_cannot_raise_one_persons_beat_rate_past_eight_a_second(self):
        accepted = 0
        for i in range(20):
            try:
                self.s.heartbeat(self.bo, {"tab": f"t{i}"})
                accepted += 1
            except session.DomainError as exc:
                self.assertEqual(exc.http, 429)
        self.assertEqual(accepted, session.MAX_TABS)
        self.clock.tick(session.HEARTBEAT_INTERVAL)
        self.s.heartbeat(self.bo, {"tab": "t99"})

    def test_presence_entries_match_the_wire_shape(self):
        self.beat(self.ann, q="Q1", typing=True)
        self.beat(self.ann, tab="other", visible=False)
        self.beat(self.bo, visible=False)
        entries = self.s.snapshot(HOST)["presence"]
        self.assertEqual(len(entries), 2)
        for e in entries:
            self.assertIsNone(session.wire_error(e, "presence"), e)


if __name__ == "__main__":
    unittest.main()
