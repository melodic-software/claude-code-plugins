// Expected values come from the invariant in clear-escalations.mjs's LANE_CAUSES
// comment: the causes the lanes lift are never ones only a person clears. The
// person sets are read from babysit_risk.py (PERSON_CODES, PERSON_PREFIXES) and
// babysit_verify_evidence.py (NEEDS_HUMAN), the lists the merge gate reads.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { LANE_CAUSES } from "./clear-escalations.mjs";

const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
const read =
  "import json,sys\nsys.path.insert(0, sys.argv[1])\nimport babysit_risk as b\nimport babysit_verify_evidence as v\n" +
  "print(json.dumps({'codes': sorted(b.PERSON_CODES), 'prefixes': list(b.PERSON_PREFIXES), 'verdicts': list(v.NEEDS_HUMAN)}))";

function personSets() {
  const python = spawnSync("python3", ["-I", "-c", read, scripts], { encoding: "utf8" });
  assert.equal(python.status, 0, python.stderr);
  return JSON.parse(python.stdout);
}

test("the person set was read from babysit_risk", () => {
  const { codes, prefixes } = personSets();
  assert.ok(codes.length > 0 && codes.every((code) => code !== ""), "PERSON_CODES is empty");
  assert.ok(prefixes.length > 0 && prefixes.every((prefix) => prefix !== ""), "PERSON_PREFIXES is empty");
});

test("no LANE_CAUSES.risk entry is a reason only a person clears", () => {
  const { codes, prefixes } = personSets();
  assert.ok(LANE_CAUSES.risk.length > 0, "LANE_CAUSES.risk is empty");
  for (const entry of LANE_CAUSES.risk) {
    if (entry.endsWith(":")) {
      // A prefix entry matches every code that starts with it.
      const overlapping = [...codes, ...prefixes].filter((person) => person.startsWith(entry) || entry.startsWith(person));
      assert.deepEqual(overlapping, [], `lane prefix ${entry} overlaps person ${overlapping}`);
    } else {
      assert.ok(!codes.includes(entry), `lane cause ${entry} is a person code`);
      const covering = prefixes.filter((prefix) => entry.startsWith(prefix));
      assert.deepEqual(covering, [], `lane cause ${entry} starts with person prefix ${covering}`);
    }
  }
});

test("no LANE_CAUSES.verdict entry is a verifier refusal only a person clears", () => {
  const { verdicts } = personSets();
  // Owner rule 2026-10-27: an untrusted spec is a trust boundary, a person's.
  assert.ok(verdicts.includes("verify:untrusted-spec"), "NEEDS_HUMAN lost verify:untrusted-spec");
  const overlapping = LANE_CAUSES.verdict.filter((entry) => verdicts.includes(entry));
  assert.deepEqual(overlapping, [], `lane verdicts ${overlapping} are in NEEDS_HUMAN`);
});

test("the repeated-FAIL cap and an old pull request are a person's, not lane causes", () => {
  // Owner decision 2026-10-29: neither clears for the head, so the gate
  // escalates them and the clear never lifts their label at the same head.
  const { verdicts } = personSets();
  for (const refusal of ["verify:repeated-fail", "verify:too-old"]) {
    assert.ok(verdicts.includes(refusal), `${refusal} is not in NEEDS_HUMAN`);
    assert.ok(!LANE_CAUSES.verdict.includes(refusal), `${refusal} is a lane cause`);
  }
});
