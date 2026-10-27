// Expected values come from the invariant in clear-escalations.mjs's LANE_CAUSES
// comment: the causes the lanes lift are never ones only a person clears. The
// person set is read from babysit_risk.py (PERSON_CODES, PERSON_PREFIXES), the
// one list the merge gate reads.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { LANE_CAUSES } from "./clear-escalations.mjs";

const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
const read = "import json,sys\nsys.path.insert(0, sys.argv[1])\nimport babysit_risk as b\nprint(json.dumps({'codes': sorted(b.PERSON_CODES), 'prefixes': list(b.PERSON_PREFIXES)}))";

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
