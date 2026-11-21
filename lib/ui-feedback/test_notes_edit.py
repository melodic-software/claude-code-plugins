# test-scope: lib/ui-feedback/test_notes_bridge.py lib/ui-feedback/notes_bridge.py lib/session-bridge/session_bridge.py lib/session-bridge/view_bridge.py
# test-scope: lib/ui-feedback/controls.js lib/ui-feedback/controls.schema.json lib/ui-feedback/fixtures/controls.json
# test-scope: lib/ui-feedback/fixtures/notes.json lib/ui-feedback/note.schema.json lib/ui-feedback/proto-pin.js
"""Tests for editing and withdrawing a sent note through notes-bridge: an edit keeps the note's seq,
a withdraw is logged as its own event, and status and the watcher drop a withdrawn note.

    python3 -m unittest test_notes_edit     (from lib/ui-feedback/)
"""

import contextlib
import io
import json
import unittest

from test_notes_bridge import FIXTURES, MOVED, NOTE, REGION, NotesCase, nb


class TestEditAndWithdraw(NotesCase):
    """POST /api/note/edit and /api/note/withdraw: a sent note corrected or taken back."""

    def edit(self, msg, **kw):
        return self.request("POST", "/api/note/edit", msg, **kw)

    def withdraw(self, msg, **kw):
        return self.request("POST", "/api/note/withdraw", msg, **kw)

    def wait(self, after):
        code, body = self.request(
            "GET",
            f"/api/wait?after={after}&timeout=5",
            headers={"X-Notes-Token": self.hub.watch_token},
            token=False,
        )
        self.assertEqual(code, 200)
        return body

    def status(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            nb.cmd_status(self.dir, None)
        return json.loads(out.getvalue())["events"]

    def test_every_fixture_edit_and_withdraw_is_judged_as_the_fixtures_say(self):
        for kind in ("edit", "withdraw"):
            node = nb.SCHEMA["$defs"][kind]
            for case in FIXTURES[f"{kind}s"]["valid"]:
                self.assertEqual(nb.problems(case[kind], node, kind), [], case["why"])
            for case in FIXTURES[f"{kind}s"]["invalid"]:
                self.assertNotEqual(nb.problems(case[kind], node, kind), [], case["why"])

    def test_an_edit_replaces_the_text_and_reaches_the_session_naming_the_note(self):
        self.note()
        self.assertEqual([e["seq"] for e in self.wait(0)["events"]], [1])
        code, body = self.edit({"edit": 1, "text": "Bolder, and larger."})
        self.assertEqual((code, body["seq"]), (200, 2))
        first, second = self.hub.read_log()["events"]
        self.assertEqual((first["seq"], first["text"]), (1, "Bolder, and larger."))
        self.assertEqual({k: second[k] for k in ("seq", "edit", "text")}, {"seq": 2, "edit": 1, "text": "Bolder, and larger."})
        self.assertNotIn("kind", second)
        events = self.wait(1)["events"]
        self.assertEqual([(e["seq"], e["edit"], e["text"]) for e in events], [(2, 1, "Bolder, and larger.")])
        state, _ = self.hub.read_state()
        self.assertEqual([n["seq"] for n in state["notes"]], [1])

    def test_an_edited_note_reloads_as_a_note_the_contract_admits(self):
        self.note()
        self.edit({"edit": 1, "text": "Bolder, and larger."})
        _, body = self.request("GET", "/api/notes")
        notes = [n for n in body["notes"] if not nb.problems({k: v for k, v in n.items() if k not in ("seq", "at")})]
        self.assertEqual([(n["seq"], n["text"]) for n in notes], [(1, "Bolder, and larger.")])

    def test_a_withdraw_marks_the_note_withdrawn_and_tells_the_session(self):
        self.note()
        self.note({**NOTE, "text": "Second."})
        code, body = self.withdraw({"withdraw": 1})
        self.assertEqual((code, body["seq"]), (200, 3))
        self.assertEqual(self.hub.read_log()["events"][2]["withdraw"], 1)
        state, _ = self.hub.read_state()
        self.assertEqual([(n["seq"], n.get("withdrawn")) for n in state["notes"]], [(1, True), (2, None)])
        self.assertEqual([e["seq"] for e in self.wait("handled")["events"]], [2, 3])
        self.assertEqual([e["seq"] for e in self.status()], [2, 3])

    def test_a_withdrawn_note_is_not_edited_moved_or_withdrawn_again(self):
        self.note(REGION)
        self.withdraw({"withdraw": 1})
        self.assertEqual(self.edit({"edit": 1, "text": "x"})[0], 400)
        self.assertEqual(self.withdraw({"withdraw": 1})[0], 400)
        self.assertEqual(self.request("POST", "/api/note/change", {"change": 1, **MOVED})[0], 400)
        self.assertEqual(len(self.hub.read_log()["events"]), 2)

    def test_an_edit_or_withdraw_is_refused_unless_it_names_a_sent_note(self):
        self.note()
        self.edit({"edit": 1, "text": "x"})
        for why, call, msg in (
            ("no such note", self.edit, {"edit": 9, "text": "x"}),
            ("an edit, not a note", self.edit, {"edit": 2, "text": "x"}),
            ("empty text", self.edit, {"edit": 1, "text": ""}),
            ("no such note", self.withdraw, {"withdraw": 9}),
            ("an edit, not a note", self.withdraw, {"withdraw": 2}),
            ("a field a withdraw does not carry", self.withdraw, {"withdraw": 1, "text": "x"}),
        ):
            self.assertEqual(call(msg)[0], 400, why)
        self.assertEqual(len(self.hub.read_log()["events"]), 2)
        self.assertEqual(self.edit({"edit": 1, "text": "x"}, token=False)[0], 403)
        self.assertEqual(self.withdraw({"withdraw": 1}, token=False)[0], 403)

    def test_a_log_written_before_edits_and_withdraws_still_loads(self):
        old = {"seq": 1, "events": [{"seq": 1, "at": "2026-11-01T00:00:00Z", **NOTE}]}
        (self.dir / "actions.json").write_text(json.dumps(old), encoding="utf-8")
        state, _ = self.hub.read_state()
        self.assertEqual([n["seq"] for n in state["notes"]], [1])
        self.assertEqual([e["text"] for e in self.status()], [NOTE["text"]])


if __name__ == "__main__":
    unittest.main()
