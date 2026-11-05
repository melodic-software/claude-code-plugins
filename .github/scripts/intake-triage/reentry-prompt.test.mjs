// The RE-ENTRY rules of intake-triage.yml's triage prompt: a question a
// recorded decision settled is never flagged again, while cost and security
// still flag (owner Q4).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// The prompt as flowing text, one space between its lines.
const PROMPT = readFileSync(new URL("../../workflows/intake-triage.yml", import.meta.url), "utf8")
  .split("\n")
  .map((line) => line.trim())
  .join(" ");
const REENTRY = /RE-ENTRY AFTER A RECORDED DECISION\.(.*?)DECISION REPLY\./.exec(PROMPT)?.[1] ?? "";

test("a question the recorded decision settled is never asked or flagged again, whatever an earlier verdict flagged", () => {
  assert.match(REENTRY, /One the decision answers, calls no owner question, defers or leaves to the issue lane is settled: never ask it again or flag intent for it, whatever an earlier verdict flagged\./);
  assert.doesNotMatch(REENTRY, /Treat any assumption, unknown or gap in intent the decision does not settle as an open question too/);
});

test("only an intent question as ESCALATION defines it stays open after a decision, including one later text raises", () => {
  assert.match(
    REENTRY,
    /Treat as open too only an intent question, as ESCALATION defines one, that the decision leaves open or text written after it raises: an outcome or done-when still not exact \(such as a term the decision uses but does not define\) or a primary-design choice still unpicked\./,
  );
});

test("the narrowing settles intent only: cost and security still flag after a decision", () => {
  assert.match(REENTRY, /This settles intent only: COST, the security rules above and \(d\) still flag as written\./);
  assert.match(REENTRY, /with `Flags: security` only at the CRITICAL tier Flags describes/);
  assert.match(PROMPT, /When the work an issue asks for would add or raise a charge that no diff shows .* set `Flags: cost`/);
});
