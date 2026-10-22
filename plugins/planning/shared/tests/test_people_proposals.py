# test-scope: plugins/planning/shared/session.py plugins/planning/shared/schema/ops.schema.json plugins/planning/shared/schema/state.schema.json plugins/planning/shared/schema/event.schema.json
"""Claude proposes a duplicate-person merge or a join admit; only the owner's tap carries it out.

Expected values come from issue #8697 and the owner's decision on it (Claude proposes with its
reasons, the host approves with one tap, nothing merges or admits without that tap, the owner is
never a merge source and never a proposal's target), from the existing merge's contract in
test_session.TestMerge (the merged person's secret resolves to the kept one), and from the
error codes the owner routes already use (owner-only, wrong-status, not-found, bad-field).
"""

from __future__ import annotations

import json

import test_session as ts

HOST = ts.HOST
session = ts.session


def mock_cap(n):
    return ts.mock.patch.object(session, "MAX_CLAUDE_PROPOSALS", n)


class ProposalCase(ts.SessionCase):
    def setUp(self):
        super().setUp()
        self.open_round(ts.text_q("Q1"))

    def offline(self):
        self.clock.tick(session.OFFLINE_AFTER + 10)

    def merge_op(self, src, dst, reasons=("same-name", "was-offline"), **extra):
        return {"op": "propose-merge", "from": src, "to": dst, "reasons": list(reasons), **extra}

    def admit_op(self, pid, reasons=("expected",), **extra):
        return {"op": "propose-admit", "pid": pid, "reasons": list(reasons), **extra}

    def propose(self, op):
        return self.apply(op)["results"][0]["id"]

    def record(self, kid):
        return next(p for p in self.s.state["claudeProposals"] if p["id"] == kid)

    def owner_items(self):
        return [p["id"] for p in self.s.snapshot(HOST)["claudeProposals"]]


class TestTheJoinEvent(ProposalCase):
    def test_a_second_ann_joining_while_the_first_is_offline_tells_claude_without_names(self):
        ann, _ = self.join("Ann")
        self.offline()
        twin, _ = self.join("Ann", device="phone")
        ev = self.events("person-joined")
        self.assertEqual(len(ev), 1)
        self.assertEqual((ev[0]["person"], ev[0]["waiting"], [m["pid"] for m in ev[0]["sameName"]]), (twin, False, [ann]))
        # the join's own device, and the first Ann's device and last beat (her join, before the offline gap)
        self.assertEqual((ev[0]["device"], ev[0]["sameName"][0]["device"]), ("phone", "computer"))
        self.assertEqual(ev[0]["sameName"][0]["lastSeen"], session.iso(ts.Clock().t + 4.0))
        self.assertNotIn("Ann", json.dumps(ev[0]))  # digestNames is off by default

    def test_with_digest_names_on_the_event_carries_both_names(self):
        self.s.update_settings(HOST, {"digestNames": True})
        self.join("Ann")
        self.offline()
        self.join("ann")
        ev = self.events("person-joined")[0]
        # the joiner's name as the session shows it: a taken name gets " 2" (_unique_name)
        self.assertEqual((ev["name"], [m["name"] for m in ev["sameName"]]), ("ann 2", ["Ann"]))

    def test_a_different_name_or_a_person_still_here_wakes_no_one(self):
        self.join("Ann")
        self.join("Bo")  # a different name
        self.join("Ann")  # the first Ann is still here
        self.assertEqual(self.events("person-joined"), [])

    def test_a_join_waiting_under_approve_new_joins_tells_claude(self):
        self.s.update_settings(HOST, {"approveJoins": True})
        pid, _ = self.join("Jib")
        ev = self.events("person-joined")
        self.assertEqual([(e["person"], e["waiting"], e["sameName"]) for e in ev], [(pid, True, [])])

    def test_a_name_that_only_shares_a_trailing_number_pattern_is_not_the_same(self):
        self.join("Room 101")
        self.offline()
        self.join("Room 7")
        self.assertEqual(self.events("person-joined"), [])

    def test_the_owner_is_never_offered_as_the_same_person(self):
        self.join("Kim")  # the owner's name
        self.assertEqual(self.events("person-joined"), [])


class TestProposeOps(ProposalCase):
    def setUp(self):
        super().setUp()
        self.ann, _ = self.join("Ann")
        self.bo, _ = self.join("Bo")
        self.offline()
        self.twin, self.twin_secret = self.join("Ann")

    def test_a_merge_proposal_waits_for_the_owner_and_merges_nothing(self):
        kid = self.propose(self.merge_op(self.twin, self.ann, note="Same phone kind, joined a minute after Ann left."))
        self.assertEqual(kid, "K1")
        rec = self.record(kid)
        self.assertEqual((rec["kind"], rec["from"], rec["to"], rec["status"]), ("merge", self.twin, self.ann, {"kind": "pending"}))
        self.assertIn(self.twin, self.s.state["people"])
        self.assertEqual(self.s.resolve(secret=self.twin_secret), self.twin)
        self.assertEqual(self.owner_items(), [kid])
        self.assertIn(f"people:{kid}", [i["key"] for i in self.s.snapshot(HOST)["inbox"]])

    def test_the_owner_is_never_a_merge_source_or_target(self):
        self.refused_ops("bad-field", self.merge_op(HOST, self.ann))
        self.refused_ops("bad-field", self.merge_op(self.twin, HOST))
        self.refused_ops("bad-field", self.merge_op(self.ann, self.ann))
        self.refused_ops("bad-field", self.admit_op(HOST))
        self.assertEqual(self.s.state.get("claudeProposals", []), [])

    def test_unknown_people_and_a_person_not_waiting_are_refused(self):
        self.refused_ops("not-found", self.merge_op("nobody", self.ann))
        self.refused_ops("wrong-status", self.admit_op(self.bo))

    def test_reasons_come_from_the_fixed_list_and_at_least_one_is_given(self):
        self.refused_ops("bad-field", self.merge_op(self.twin, self.ann, reasons=()))
        self.refused_ops("bad-field", self.merge_op(self.twin, self.ann, reasons=("same-ip",)))

    def test_one_open_proposal_per_pair_and_a_dismissed_pair_is_not_proposed_again(self):
        kid = self.propose(self.merge_op(self.twin, self.ann))
        self.refused_ops("wrong-status", self.merge_op(self.twin, self.ann))
        self.act("act_on_claude_proposal", HOST, {"id": kid, "action": "dismiss"})
        self.refused_ops("dismissed", self.merge_op(self.twin, self.ann))

    def test_only_the_pair_a_join_reported_can_be_proposed(self):
        # person-joined named the twin as the joiner and Ann as the match: no other pair, and not the reverse
        self.refused_ops("not-reported", self.merge_op(self.ann, self.twin))
        self.refused_ops("not-reported", self.merge_op(self.bo, self.ann))
        self.refused_ops("not-reported", self.merge_op(self.twin, self.bo))

    def test_a_guest_claim_is_not_a_reason(self):
        self.refused_ops("bad-field", self.merge_op(self.twin, self.ann, reasons=("said-so",)))

    def test_a_leader_or_trusted_person_is_never_a_merge_target(self):
        self.act("set_trust", HOST, {"pid": self.ann, "on": True})
        self.refused_ops("wrong-status", self.merge_op(self.twin, self.ann))

    def test_answered_proposals_do_not_use_up_the_cap(self):
        with mock_cap(1):
            kid = self.propose(self.merge_op(self.twin, self.ann))
            self.act("act_on_claude_proposal", HOST, {"id": kid, "action": "dismiss"})
            self.s.update_settings(HOST, {"approveJoins": True})
            jib, _ = self.join("Jib")
            self.propose(self.admit_op(jib))
            self.assertEqual([p["status"]["kind"] for p in self.s.state["claudeProposals"]], ["pending"])

    def test_no_op_merges_or_admits_on_claudes_word(self):
        self.refused_ops("bad-field", {"op": "approve-proposal", "id": "K1"})
        self.refused_ops("bad-field", {"op": "merge", "from": self.twin, "to": self.ann})


class TestWaitingDuplicate(ProposalCase):
    def test_a_waiting_join_is_let_in_before_any_merge_as_the_owners_merge_requires(self):
        ann, _ = self.join("Ann")
        self.offline()
        self.s.update_settings(HOST, {"approveJoins": True})
        twin, _ = self.join("Ann")
        self.refused_ops("wrong-status", self.merge_op(twin, ann))
        kid = self.propose(self.admit_op(twin, reasons=("same-name",)))
        self.act("act_on_claude_proposal", HOST, {"id": kid, "action": "approve"})
        self.assertEqual(self.propose(self.merge_op(twin, ann)), "K2")


class TestApprove(ProposalCase):
    def setUp(self):
        super().setUp()
        self.ann, _ = self.join("Ann")
        self.act("answer", self.ann, {"qid": "Q1", "text": "Ann's first answer", "view": "focus"})
        self.offline()
        self.twin, self.twin_secret = self.join("Ann")
        self.kid = self.propose(self.merge_op(self.twin, self.ann))

    def test_approve_merges_the_new_browser_into_the_earlier_person_and_tells_them(self):
        self.act("chat", self.twin, {"text": "Hi from my phone"})
        out = self.act("act_on_claude_proposal", HOST, {"id": self.kid, "action": "approve"})
        self.assertEqual(out["status"], "approved")
        st = self.s.state
        self.assertNotIn(self.twin, st["people"])
        self.assertEqual([c["pid"] for c in st["cards"]["Q1"] if c["kind"] == "person"], [self.ann])
        self.assertEqual([m["pid"] for m in st["chat"]], [self.ann])
        self.assertEqual(self.s.resolve(secret=self.twin_secret), self.ann)
        self.assertEqual([n["kind"] for n in self.notes(self.ann, "merge")], ["merge"])
        self.assertEqual(self.owner_items(), [])
        self.assertEqual(session.cross_field_errors(st), [])

    def test_dismiss_keeps_both_people(self):
        self.assertEqual(self.act("act_on_claude_proposal", HOST, {"id": self.kid, "action": "dismiss"})["status"], "dismissed")
        self.assertIn(self.twin, self.s.state["people"])
        self.assertEqual(self.owner_items(), [])
        self.refused("wrong-status", "act_on_claude_proposal", HOST, {"id": self.kid, "action": "approve"}, http=409)
        self.assertIn(self.twin, self.s.state["people"])

    def test_only_the_owner_can_approve(self):
        self.refused("owner-only", "act_on_claude_proposal", self.twin, {"id": self.kid, "action": "approve"}, http=403)
        self.act("set_role", HOST, {"pid": self.ann, "role": "leader"})
        self.refused("owner-only", "act_on_claude_proposal", self.ann, {"id": self.kid, "action": "approve"}, http=403)
        self.assertIn(self.twin, self.s.state["people"])

    def test_a_guest_never_sees_a_proposal(self):
        for pid in (self.ann, self.twin):
            snap = self.s.snapshot(pid)
            self.assertNotIn("claudeProposals", snap)
            self.assertNotIn(self.kid, json.dumps(snap))

    def test_an_unknown_proposal_is_not_found(self):
        self.refused("not-found", "act_on_claude_proposal", HOST, {"id": "K99", "action": "approve"}, http=404)


class TestStale(ProposalCase):
    """A proposal names the people as Claude saw them; once they change, the tap merges nothing."""

    def setUp(self):
        super().setUp()
        self.ann, _ = self.join("Ann")
        self.bo, _ = self.join("Bo")
        self.offline()
        self.twin, _ = self.join("Ann")
        self.kid = self.propose(self.merge_op(self.twin, self.ann))

    def approve_is_stale(self):
        self.refused("stale", "act_on_claude_proposal", HOST, {"id": self.kid, "action": "approve"}, http=409)
        self.assertEqual(self.record(self.kid)["status"]["kind"], "stale")
        self.assertEqual(self.owner_items(), [])

    def test_a_rename_makes_it_stale(self):
        self.act("rename", self.twin, {"name": "Annie"})
        self.approve_is_stale()
        self.assertEqual({self.ann, self.twin} - set(self.s.state["people"]), set())

    def test_a_removal_makes_it_stale(self):
        self.act("set_removed", HOST, {"pid": self.ann, "on": True})
        self.approve_is_stale()
        self.assertIn(self.twin, self.s.state["people"])

    def test_a_manual_merge_of_either_person_makes_it_stale(self):
        self.act("merge_people", HOST, {"from": self.twin, "to": self.bo})
        self.approve_is_stale()
        self.assertEqual((self.ann in self.s.state["people"], self.bo in self.s.state["people"]), (True, True))


class TestAdmit(ProposalCase):
    def setUp(self):
        super().setUp()
        self.s.update_settings(HOST, {"approveJoins": True})
        self.jib, self.jib_secret = self.join("Jib")
        self.kid = self.propose(self.admit_op(self.jib, note="The owner said Jib from finance is coming."))

    def test_approve_lets_the_person_in(self):
        self.assertEqual(self.act("act_on_claude_proposal", HOST, {"id": self.kid, "action": "approve"})["status"], "approved")
        self.assertEqual(self.s.resolve(secret=self.jib_secret), self.jib)
        self.assertEqual(self.s.state["people"][self.jib]["status"], {"kind": "active"})

    def test_until_then_the_person_still_waits(self):
        with self.assertRaises(session.DomainError) as ctx:
            self.s.resolve(secret=self.jib_secret)
        self.assertEqual(ctx.exception.code, "waiting")

    def test_a_join_the_owner_already_answered_is_stale(self):
        self.act("act_on_join", HOST, {"pid": self.jib, "action": "decline"})
        self.refused("stale", "act_on_claude_proposal", HOST, {"id": self.kid, "action": "approve"}, http=409)
        self.assertEqual(self.s.state["people"][self.jib]["status"]["kind"], "removed")


class TestOldStates(ts.SessionCase):
    def test_a_state_without_claude_proposals_loads_and_takes_one(self):
        st = self.disk()
        self.assertNotIn("claudeProposals", st)
        loaded = session.Session.load(self.path, clock=self.clock, ids=self.ids, validate_writes=True)
        self.assertIsNone(session.document_error(loaded.state))
        self.assertEqual(loaded.snapshot(HOST)["claudeProposals"], [])

    def proposal_state(self, **rec):
        st = self.disk()
        st["session"]["seq"]["K"] = 1
        st["claudeProposals"] = [{"id": "K1", "reasons": ["same-name"], "at": 1.0, "status": {"kind": "pending"}, **rec}]
        return st

    def test_an_open_proposal_naming_the_owner_is_an_invalid_state(self):
        ok = self.proposal_state(kind="merge", **{"from": "abc", "to": "def"}, names={"abc": "Ann", "def": "Ann"})
        self.assertIsNone(session.document_error(ok))
        bad = self.proposal_state(kind="merge", **{"from": "abc", "to": HOST}, names={"abc": "Ann", HOST: "Kim"})
        self.assertIn("An open proposal of Claude's names the owner", session.document_error(bad))

    def test_each_kind_holds_the_people_it_names(self):
        self.assertIsNotNone(session.document_error(self.proposal_state(kind="merge", names={})))
        self.assertIsNotNone(session.document_error(self.proposal_state(kind="admit", pid="abc", to="def", names={"abc": "Jib"})))
        self.assertIsNone(session.document_error(self.proposal_state(kind="admit", pid="abc", names={"abc": "Jib"})))
