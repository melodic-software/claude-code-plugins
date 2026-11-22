import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { recordText, rollbackRecord } from "./record.mjs";
import { tempDir } from "../tests/temp.mjs";

const A = { schema: 1, profile: "a" };
const B = { schema: 1, profile: "b" };
const PREVIOUS = { schema: 1, profile: "previous" };

function recordFile(record) {
  const path = join(tempDir(), "record.json");
  writeFileSync(path, recordText(record));
  return path;
}

test("rollback puts the previous record back while the file still holds this apply's", () => {
  const path = recordFile(B);
  assert.equal(rollbackRecord(path, recordText(B), PREVIOUS), true);
  assert.equal(readFileSync(path, "utf8"), recordText(PREVIOUS));
});

test("rollback deletes a record it created while the file still holds it", () => {
  const path = recordFile(B);
  assert.equal(rollbackRecord(path, recordText(B), null), true);
  assert.equal(existsSync(path), false);
});

test("a rollback after another apply saved its record leaves that record in place", () => {
  for (const previous of [PREVIOUS, null]) {
    const path = recordFile(A);
    assert.equal(rollbackRecord(path, recordText(B), previous), false);
    assert.equal(readFileSync(path, "utf8"), recordText(A));
  }
});
