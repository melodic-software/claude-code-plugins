import assert from "node:assert/strict";
import { test } from "node:test";

import { MIN_FAILURES, compute, readMarker, readRecord, renderMarkdown, revertsOf, squashRating } from "./merge-risk-failures.mjs";

const sha = (c) => c.repeat(40);
const BOT = "melodic-automation-lanes";
const APP = { __typename: "Bot", login: BOT };
const said = (body, extra = {}) => ({ author: APP, body, createdAt: "2026-11-01T00:00:00Z", lastEditedAt: null, ...extra });
const RATED_HIGH = `Merge-Risk: max=HIGH demote=true head=${sha("a")} rubric=9.2.0 rater=claude-opus-5-5 checker=claude-opus-5-5`;
const RATED_LOW = `Merge-Risk: max=LOW demote=false head=${sha("a")} rubric=9.2.0 rater=claude-opus-5-5 checker=claude-opus-5-5`;

test("readMarker takes the lanes App's newest unedited marker for the head, with its lane run when named", () => {
  const head = sha("a");
  const old = said(`<!-- merge-risk-line head=${head} -->\nMerge-Risk: unrated reason=pending`);
  const current = said(`<!-- merge-risk-line head=${head} lane=work-resolve-issue run=43643331000 -->\n${RATED_HIGH}`, { createdAt: "2026-11-02T00:00:00Z" });
  assert.deepEqual(readMarker([current, old], BOT, head), { demote: true, lane: "work-resolve-issue", run: "43643331000" });
  assert.deepEqual(readMarker([said(`<!-- merge-risk-line head=${head} -->\n${RATED_LOW}`)], BOT, head), { demote: false, lane: null, run: null });
  assert.deepEqual(readMarker([old], BOT, head), { demote: null, lane: null, run: null });
  assert.equal(readMarker([current], BOT, sha("b")), null);
  assert.equal(readMarker([{ ...current, author: { __typename: "User", login: BOT } }], BOT, head), null);
  assert.equal(readMarker([{ ...current, lastEditedAt: "2026-11-03T00:00:00Z", editor: { __typename: "User", login: "someone" } }], BOT, head), null);
  assert.deepEqual(readMarker([{ ...current, lastEditedAt: "2026-11-03T00:00:00Z", editor: APP }], BOT, head), { demote: true, lane: "work-resolve-issue", run: "43643331000" });
});

test("squashRating joins a Merge-Risk line GitHub wrapped at 72 columns, and finds none in a body without one", () => {
  const body = `## Related\n\n#1\n\nMerge-Risk: max=CRITICAL demote=true\nhead=${sha("c")} rubric=8.4.11\nrater=claude-opus-5-5 checker=claude-opus-5-5\n\n---------\n\nCo-authored-by: x`;
  assert.equal(squashRating(body), true);
  assert.equal(squashRating("Merge-Risk: max=LOW demote=false"), false);
  assert.equal(squashRating("Merge-Risk: unrated reason=no-run"), null);
  assert.equal(squashRating("no rating here"), null);
});

test("revertsOf applies measure-delivery's three forms, in its order", () => {
  assert.deepEqual(revertsOf({ subject: "anything", body: `This reverts commit ${sha("d")}.` }), { shas: [sha("d")], prs: [], subjects: [] });
  assert.deepEqual(revertsOf({ subject: 'Revert "fix: x (#12)" (#20)', body: "Reverts #12\nReverts owner/repo#13" }), { shas: [], prs: [12, 13], subjects: [] });
  assert.deepEqual(revertsOf({ subject: 'Revert "fix: x"', body: "" }), { shas: [], prs: [], subjects: ["fix: x"] });
  assert.deepEqual(revertsOf({ subject: "revert(ci): fix: y (#9)", body: "" }), { shas: [], prs: [], subjects: ["fix: y (#9)", "fix: y"] });
  assert.equal(revertsOf({ subject: "fix: Reverts #12 in prose", body: "Reverts #12" }), null);
});

test("readRecord reads a demotion record's marker, its pull request line and its range, and no author", () => {
  const single = `<!-- babysit-merge-demotion sha=${sha("e")} signal=canary -->\n\nlead\n\n- Pull request: https://github.com/o/r/pull/31\n- Merge commit: \`${sha("e")}\``;
  assert.deepEqual(readRecord(single), { signal: "canary", sha: sha("e"), prs: [31], range: [] });
  const range = `<!-- post-merge-failure sha=${sha("f")} signal=schedule -->\n\n- Commits in the range, oldest first:\n  - https://github.com/o/r/pull/40, merge commit \`${sha("1")}\`, by someone\n  - https://github.com/o/r/pull/41, merge commit \`${sha("f")}\`, by someone\n- Main at the failing run: \`${sha("f")}\``;
  assert.deepEqual(readRecord(range), { signal: "schedule", sha: sha("f"), prs: [], range: [sha("1"), sha("f")] });
  assert.equal(readRecord(`quoted\n${single}`), null);
  assert.equal(readRecord(`<!-- babysit-merge-demotion sha=${sha("e")} signal=nonsense -->`), null);
});

// Six rated merges, three per group: each failure signal hits one merge
// alone, and one demotion record names a range.
const commit = (c, ct, pr, subject = `feat: change ${pr} (#${pr})`, extra = {}) => ({ sha: sha(c), ct, pr, subject, demote: null, reverts: null, ...extra });
const SNAPSHOT = {
  since: 100,
  until: 1000,
  commits: [
    commit("1", 110, 1),
    commit("2", 120, 2),
    commit("3", 130, 3, undefined, { demote: true }),
    commit("4", 140, 4),
    commit("5", 150, 5),
    commit("6", 160, 6, undefined, { demote: false }),
    commit("7", 170, 7),
    commit("9", 1100, 9, 'Revert "feat: change 4 (#4)" (#9)', { reverts: { shas: [], prs: [4], subjects: [] } }),
    commit("8", 50, 8, "feat: before the window (#8)", { demote: true }),
  ],
  markers: [
    { pr: 1, merge: sha("1"), demote: true, lane: "work-resolve-issue", run: "11" },
    { pr: 2, merge: sha("2"), demote: true, lane: "work-resolve-issue", run: "12" },
    { pr: 4, merge: sha("4"), demote: false, lane: "work-resolve-issue", run: "14" },
    { pr: 5, merge: sha("5"), demote: false, lane: null, run: null },
    { pr: 7, merge: sha("7"), demote: null, lane: null, run: null },
  ],
  records: [
    { signal: "dispatch", sha: sha("1"), prs: [], range: [] },
    { signal: "canary", sha: sha("9"), prs: [5], range: [] },
    { signal: "schedule", sha: sha("3"), prs: [], range: [sha("2"), sha("3")] },
    { signal: "revert", sha: sha("9"), prs: [], range: [] },
  ],
};

test("compute joins each rated merge to the failure signals and counts them per demote group", () => {
  const result = compute(SNAPSHOT);
  assert.equal(result.rated, 6);
  assert.equal(result.unrated, 1);
  assert.deepEqual(result.groups.true, { rated: 3, demotion: 1, demotion_in_range: 2, canary: 0, canary_in_range: 0, revert: 0, any: 1 });
  assert.deepEqual(result.groups.false, { rated: 3, demotion: 0, demotion_in_range: 0, canary: 1, canary_in_range: 0, revert: 1, any: 2 });
  for (const signal of ["demotion", "canary", "revert", "any"]) {
    assert.equal(result.compare[signal], "not enough failures to compare", signal);
  }
  assert.deepEqual(result.by_lane, {
    "work-resolve-issue": {
      true: { rated: 2, demotion: 1, demotion_in_range: 1, canary: 0, canary_in_range: 0, revert: 0, any: 1 },
      false: { rated: 1, demotion: 0, demotion_in_range: 0, canary: 0, canary_in_range: 0, revert: 1, any: 1 },
    },
  });
  assert.equal(result.without_lane, 3);
});

test("compute prints a rate only when both groups reach the minimum failure count", () => {
  const commits = [];
  const records = [];
  for (let i = 0; i < 2 * MIN_FAILURES + 4; i += 1) {
    const hex = i.toString(16).padStart(40, "0");
    commits.push({ sha: hex, ct: 200 + i, pr: 100 + i, subject: `s ${i}`, demote: i % 2 === 0, reverts: null });
    if (i < 2 * MIN_FAILURES) records.push({ signal: "dispatch", sha: hex, prs: [], range: [] });
  }
  const result = compute({ since: 100, until: 1000, commits, markers: [], records });
  const rate = Math.round((MIN_FAILURES / (MIN_FAILURES + 2)) * 10000) / 10000;
  assert.deepEqual(result.compare.demotion, { true: rate, false: rate });
  assert.equal(result.compare.canary, "not enough failures to compare");
});

test("the report names no person and renders every group", () => {
  const result = compute(SNAPSHOT);
  const text = `${JSON.stringify(result)}\n${renderMarkdown(result)}`;
  assert.equal(/someone|author|committer|login/i.test(text), false);
  assert.match(renderMarkdown(result), /\| demote=true \| 3 \| 1 \| 2 \| 0 \| 0 \| 0 \| 1 \|/);
  assert.match(renderMarkdown(result), /not enough failures to compare/);
});
