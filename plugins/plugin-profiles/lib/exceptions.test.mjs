import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir } from "../tests/temp.mjs";
import { appendExceptions, exceptionCounts, exceptionsToReview, readExceptions, SESSION_DAYS } from "./exceptions.mjs";

const NOW = Date.parse("2026-11-23T00:00:00Z");
const record = (sessionId, profile = "build", plugin = "extra@m") =>
  ({ kind: "exception", profile, plugin, sessionId, folder: "/project" });

test("#18318 AC5: reads an absent log without creating it and prunes expired and malformed records", () => {
  const dir = tempDir();
  const file = join(dir, "exceptions.jsonl");
  assert.deepEqual(readExceptions(dir, NOW), []);
  assert.equal(existsSync(file), false);
  const boundary = NOW - SESSION_DAYS * 86_400_000;
  appendExceptions(dir, [record("old")], boundary - 1);
  appendExceptions(dir, [record("edge")], boundary);
  const lines = readFileSync(file, "utf8").split("\n");
  writeFileSync(file, lines.join("\n") + 'garbage\nnull\n{"kind":"exception"}\n');
  assert.deepEqual(readExceptions(dir, NOW), [JSON.parse(lines[1])]);
  assert.equal(readFileSync(file, "utf8"), lines[1] + "\n");
});

test("#18318 AC5: distinct sessions count once and review resets just its pair", () => {
  const dir = tempDir();
  const reviewed = { kind: "reviewed", profile: "build", plugin: "extra@m" };
  appendExceptions(dir, [record("a"), record("a"), record("b"), record("c"), record("a", "review"), record("a", "build", "other@m")], NOW);
  assert.deepEqual(exceptionsToReview(readExceptions(dir, NOW), "build").map(({ plugin, count }) => [plugin, count]), [["extra@m", 3]]);
  appendExceptions(dir, [reviewed, record("a")], NOW + 1);
  const rows = exceptionCounts(readExceptions(dir, NOW + 1));
  assert.deepEqual(rows.map(({ profile, plugin, count }) => [profile, plugin, count]),
    [["build", "extra@m", 1], ["review", "extra@m", 1], ["build", "other@m", 1]]);
  assert.deepEqual(rows[0].sessions, ["a"]);
  assert.equal(rows[0].lastAt, new Date(NOW + 1).toISOString());
});
