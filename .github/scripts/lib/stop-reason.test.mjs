// Expected values come from the owner's rule: a person only for an intent,
// design, security or cost reason, and `none` never to a person.
import assert from "node:assert/strict";
import { test } from "node:test";

import { isPersonReason, parseReason, PERSON_REASONS, personReasonLines, reasonLine, reasonMarker, STOP_REASONS, stopReason } from "./stop-reason.mjs";

test("the codes are the owner's four reasons for a person, and none", () => {
  assert.deepEqual([...STOP_REASONS], ["intent", "design", "security", "cost", "none"]);
  assert.deepEqual([...PERSON_REASONS], ["intent", "design", "security", "cost"]);
  assert.equal(isPersonReason("none"), false);
  assert.equal(isPersonReason("security"), true);
});

test("a code outside the list is refused", () => {
  for (const code of ["", "intent-change", "Intent", undefined, "other"]) {
    assert.throws(() => stopReason(code), /is not one of/, String(code));
    assert.throws(() => reasonLine(code), /is not one of/, String(code));
  }
});

test("the marker and the line name the code, and the marker reads back", () => {
  assert.equal(reasonMarker("work-resolve-issue", "design"), "<!-- stop-reason lane=work-resolve-issue reason=design -->");
  assert.equal(reasonLine("cost"), "Reason: `cost`");
  assert.deepEqual(parseReason(`<!-- other -->\n${reasonMarker("intake-triage", "none")}\ntext`), { lane: "intake-triage", reason: "none" });
  assert.equal(parseReason("<!-- stop-reason lane=x reason=other -->"), null);
  assert.equal(parseReason("quoting <!-- stop-reason lane=x reason=cost --> inline"), null);
  assert.throws(() => reasonMarker("Bad Lane", "cost"), /lane name/);
});

test("a comment that hands work to a person carries a person reason, never none", () => {
  assert.deepEqual(personReasonLines("work-resolve-issue", "intent"), ["<!-- stop-reason lane=work-resolve-issue reason=intent -->", "Reason: `intent`"]);
  assert.throws(() => personReasonLines("work-resolve-issue", "none"), /never hands work to a person/);
});
