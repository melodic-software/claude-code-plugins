import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { checkActivityName, checkLaneName } from "./vocabulary.mjs";

const vocabulary = JSON.parse(
  readFileSync(new URL("./fixtures/vocabulary.json", import.meta.url)),
);

test("a lane named <stage>-<function> from the vocabulary passes", () => {
  assert.equal(checkLaneName("pr-run-checks", vocabulary), undefined);
  assert.equal(
    checkLaneName("post-merge-sweep-comments", vocabulary),
    undefined,
  );
});

test("a lane may add a modifier after its function", () => {
  assert.equal(checkLaneName("pr-review-docs", vocabulary), undefined);
});

test("a lane whose stage or function the vocabulary lacks is reported", () => {
  assert.match(checkLaneName("release-tag", vocabulary), /release-tag/);
  assert.match(checkLaneName("pr-deploy", vocabulary), /pr-deploy/);
  assert.match(checkLaneName("pr", vocabulary), /pr/);
});

test("a verb-first activity passes, and a review engine passes by name", () => {
  assert.equal(checkActivityName("run-tests", vocabulary), undefined);
  assert.equal(checkActivityName("claude", vocabulary), undefined);
});

test("an activity that does not start with a vocabulary verb is reported", () => {
  assert.match(
    checkActivityName("coverage-report", vocabulary),
    /accepted verb/,
  );
});

test("an activity starting with a stage word is reported", () => {
  assert.match(checkActivityName("pr-explainer", vocabulary), /stage word/);
});

test("an activity with a mode suffix is reported, even a vocabulary mode", () => {
  assert.match(checkActivityName("simplify#diff", vocabulary), /args/);
  assert.match(checkActivityName("simplify#fast", vocabulary), /args/);
});
