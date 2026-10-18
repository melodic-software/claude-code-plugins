// The collector's unit rules from docs/conventions/pr-pipeline/README.md,
// "The lane sweep": slice A takes the four workflows with the most failed
// runs, slice D the two lane workflows with the most runs, slice C open PRs by
// listed authors in tens, fork runs never count, at most 8 units, and the
// collector stops at its call budget.
import assert from "node:assert/strict";
import { test } from "node:test";

import { createBudget, selectUnits, tailLog } from "./collect.mjs";

const run = (id, path, conclusion, over = {}) => ({
  id,
  path,
  conclusion,
  head_repository: { full_name: "o/r" },
  ...over,
});

test("slice A takes the four workflows with the most failed same-repository runs", () => {
  const runs = [
    ...[1, 2, 3].map((id) => run(id, ".github/workflows/a.yml", "failure")),
    ...[4, 5].map((id) => run(id, ".github/workflows/b.yml", "failure")),
    run(6, ".github/workflows/c.yml", "failure"),
    run(7, ".github/workflows/d.yml", "failure"),
    run(8, ".github/workflows/e.yml", "success"),
    ...[9, 10, 11, 12].map((id) =>
      run(id, ".github/workflows/fork.yml", "failure", {
        head_repository: { full_name: "x/r" },
      }),
    ),
  ];
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls: [],
    trusted: new Set(),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "A").map((u) => [u.workflow, u.runIds]),
    [
      [".github/workflows/a.yml", [1, 2, 3]],
      [".github/workflows/b.yml", [4, 5]],
      [".github/workflows/c.yml", [6]],
      [".github/workflows/d.yml", [7]],
    ],
  );
});

test("slice D takes the two lane workflows with the most runs, successes included", () => {
  const runs = [
    ...[1, 2, 3].map((id) => run(id, ".github/workflows/pr-merge.yml", "success")),
    ...[4, 5].map((id) => run(id, ".github/workflows/work-unblock.yml", "skipped")),
    run(6, ".github/workflows/pr-refine.yml", "failure"),
    ...[7, 8, 9, 10].map((id) => run(id, ".github/workflows/release-publish-plugins.yml", "success")),
  ];
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls: [],
    trusted: new Set(),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "D").map((u) => [u.workflow, u.runIds.length]),
    [
      [".github/workflows/pr-merge.yml", 3],
      [".github/workflows/work-unblock.yml", 2],
    ],
  );
});

test("slice C takes listed authors' open PRs in tens, and units stop at 8", () => {
  const pulls = Array.from({ length: 25 }, (_, i) => ({
    number: i + 1,
    user: { id: i % 5 === 0 ? 99 : 1 },
  }));
  const runs = Array.from({ length: 6 }, (_, i) => run(i + 1, `.github/workflows/w${i}.yml`, "failure"));
  const units = selectUnits({
    repo: "o/r",
    runs,
    pulls,
    trusted: new Set(["1"]),
  });
  assert.deepEqual(
    units.filter((u) => u.slice === "C").map((u) => u.pulls.length),
    [10, 10],
  );
  assert.equal(units.length, 6);
  assert.ok(units.every((u, i) => u.id === `${u.slice.toLowerCase()}${i + 1}`));
  const many = selectUnits({
    repo: "o/r",
    runs: [...runs, ...[1, 2, 3].map((id) => run(100 + id, `.github/workflows/pr-x${id}.yml`, "success"))],
    pulls: Array.from({ length: 40 }, (_, i) => ({
      number: i + 1,
      user: { id: 1 },
    })),
    trusted: new Set(["1"]),
  });
  assert.equal(many.length, 8);
});

test("the budget refuses the call past its limit", () => {
  const budget = createBudget(2);
  budget.spend();
  budget.spend();
  assert.throws(() => budget.spend(), /call budget of 2/);
  assert.equal(budget.used, 2);
});

test("a log tail keeps the last lines without ANSI codes or timestamps", () => {
  const log = ["2026-10-17T21:13:05.1234567Z one", "2026-10-17T21:13:06.0000000Z \u001b[31mtwo\u001b[0m", "three"].join(
    "\n",
  );
  assert.equal(tailLog(log, 2), "two\nthree");
});
