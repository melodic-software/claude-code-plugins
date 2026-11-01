// review-precision.mjs over a hand-built snapshot. Every expected count below is counted by hand
// from the fixture: the answer shapes are the D5 table (review-discipline.md), pr-unblock's bold
// reply line (publish-feedback.mjs renderReply) and prose; the sample text is written for this
// file. PR 101's security repost follows a real shape (a manifest flag re-raised on the next head
// with a reworded first line, answered "Same flag as on <sha>"); PR 102's line-347 pair follows a
// Codex finding and a claude-review finding on one line, which is no repost.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { answerBucket, bucketOf, compute, normalizeFirstLine, parseArgs, renderMarkdown, stableStringify } from "./review-precision.mjs";

const SCRIPT = fileURLToPath(new URL("./review-precision.mjs", import.meta.url));
const TMP = mkdtempSync(join(tmpdir(), "review-precision-"));
after(() => rmSync(TMP, { recursive: true, force: true }));

const sha = (c) => c.repeat(40);
const [A, B, C, D, E, F, H, I] = ["a", "b", "c", "d", "e", "f", "8", "9"].map(sha);
const CR = "claude-review";
const SR = "claude-security-review";
const notice = (lane, head, at, findings, inline) => ({
  lane,
  run: 0,
  completedAt: at,
  text:
    findings === undefined
      ? `claude-lane-review-complete lane=${lane} sha=${head} skip=no-change through=${head}`
      : `claude-lane-review-complete lane=${lane} sha=${head} findings=${findings} inline=${inline} scope=whole`,
});
let nextId = 3000;
const thread = (path, head, root, ...replies) => ({
  path,
  line: 1,
  originalLine: 1,
  comments: [root, ...replies].map(([author, createdAt, body], i) => ({ id: nextId++, author, createdAt, body, commit: head, replyTo: i ? "root" : null })),
});
const lane = (name, first, at) => ["github-actions", at, `${first}\n\nDetail of the finding.\n\nclaude-lane: ${name}`];
const human = (at, body) => ["kyle-sexton", at, body];
const T = (hh, mm = "00") => `2026-10-28T${hh}:${mm}:00Z`;

function fixture() {
  nextId = 3000;
  const t4root = 3006;
  return {
    schema: 1,
    repo: "example/repo",
    window: { since: "2026-10-27T00:00:00Z", until: "2026-10-29T00:00:00Z" },
    earliest_supported: "2026-10-24T00:00:00Z",
    rounds_cap: { value: 3, source: "docs/conventions/pr-pipeline.yaml loop.review-rounds" },
    truncated: [],
    prs: [
      {
        number: 101,
        headRefName: "feat/one",
        createdAt: T("08"),
        mergedAt: T("13"),
        notices: [
          notice(CR, A, T("10"), 2, 1),
          notice(SR, A, T("10", "05"), 1, 1),
          notice(CR, B, T("11"), 1, 1),
          notice(SR, B, T("11", "05"), 1, 1),
          notice(CR, C, T("12"), 0, 0),
          notice(SR, C, T("12", "05")),
        ],
        threads: [
          // 3000-3001: the table shape, VALID, fixed.
          thread("x.sh", A, lane(CR, "**Quoting bug in `x.sh:12`**", T("10")), human(T("10", "30"), "| Finding | Verdict | Evidence |\n|---|---|---|\n| quoting | VALID, fixed | Fixed in abc1234. |")),
          // 3002-3003: the pr-unblock line, INCORRECT.
          thread("y.sh", B, lane(CR, "**Off-by-one in the loop**", T("11")), ["melodic-lanes[bot]", T("11", "30"), "**pr-unblock / address-feedback: INCORRECT, left open**\n\nEvidence: `y.sh:4`\n\n```text\nThe loop is inclusive on purpose.\n```"]),
          // 3004-3005: prose with no label.
          thread("m.json", A, lane(SR, "manifest flag: removing the default turns the check on", T("10", "05")), human(T("10", "40"), "Acknowledged, no change. The owner chose the new default.")),
          // 3006-3007: the same flag on the next head, reworded, answered by citing the earlier one.
          thread("m.json", B, lane(SR, "manifest flag: the removed default switches the check on for everyone", T("11", "05")), human(T("11", "40"), `Same flag as on aaaaaaa, same disposition: no change. Reasons: https://github.com/example/repo/pull/101#discussion_r${t4root - 1}`)),
          // 3008: a Codex thread: no lane footer, so no finding.
          thread("y.sh", B, ["chatgpt-codex-connector", T("11", "10"), "**P2: Guard the loop**\n\n<!-- codex-code-review-finding:v1 -->"]),
        ],
        comments: [
          { author: "kyle-sexton", createdAt: T("10", "50"), body: "| claude-review finding (aaaaaaa) | Verdict | Evidence |\n|---|---|---|\n| The description omits the default | INTENTIONAL | The owner's decision. |" },
          { author: "melodic-lanes[bot]", createdAt: T("11", "45"), body: "<!-- pr-unblock:address-feedback-round -->\nRound 1." },
          { author: "melodic-lanes[bot]", createdAt: "2026-10-29T01:00:00Z", body: "<!-- pr-unblock:address-feedback-round -->\nAfter the window." },
        ],
      },
      {
        number: 102,
        headRefName: "feat/two",
        createdAt: T("08"),
        mergedAt: T("14"),
        notices: [notice(CR, D, T("10"), 1, 1), notice(SR, D, T("10", "05"), 1, 1), notice(CR, E, T("11"), 2, 2), notice(SR, E, T("11", "05"), 0, 0), notice(CR, F, T("12"), 0, 0)],
        threads: [
          // 3009-3010: prose UNCERTAIN.
          thread("p.md", D, lane(CR, "**The `docs` link at line 5 is broken**", T("10")), human(T("10", "20"), "UNCERTAIN: it depends on the renderer.")),
          // 3011-3012: the same lane, path and first line on a later head: a repost.
          thread("p.md", E, lane(CR, "**The docs link at line 7 is broken**", T("11")), human(T("11", "20"), "VALID (defer), filed #250.")),
          // 3013-3014 and 3015-3016: Codex and claude-review on one line; prose VALID.
          thread("q.sh", E, ["chatgpt-codex-connector", T("11", "01"), "**P2: Guard the clock read**"], human(T("11", "25"), "| Finding | Verdict |\n|---|---|\n| clock | VALID, fixed |")),
          thread("q.sh", E, lane(CR, "**The clock fallback fails under set -u**", T("11")), human(T("11", "26"), "Same defect as the Codex thread on this line: VALID, fixed in f2fc66f.")),
          // 3017-3018: a Classification column, VALID (defer) with a forward tracker id.
          thread("s.yml", D, lane(SR, "token scope wider than the job needs", T("10", "05")), human(T("10", "30"), "| # | Finding | Classification | Evidence |\n|---|---|---|---|\n| 1 | scope | VALID (defer) | Structural; filed #250. |")),
        ],
        comments: [],
      },
      {
        number: 103,
        headRefName: "feat/three",
        createdAt: T("08"),
        mergedAt: T("15"),
        notices: [notice(CR, H, T("10"), 1, 1), notice(SR, H, T("10", "05"), 1, 1), notice(CR, I, "2026-10-29T02:00:00Z", 0, 0)],
        threads: [
          // 3019-3020: answered only after `until`: unanswered.
          thread("r.sh", H, lane(CR, "**Unchecked exit status**", T("10")), human("2026-10-29T03:00:00Z", "VALID, fixed in 1234567.")),
          // 3021-3022: VALID (defer) citing only an older item: answered, unlabeled.
          thread("t.sh", H, lane(SR, "secret echoed to the log", T("10", "05")), human(T("10", "30"), "VALID (defer): tracked in #50.")),
        ],
        comments: [],
      },
      // Merged outside the window: left out.
      { number: 90, headRefName: "old", createdAt: T("01"), mergedAt: "2026-10-26T12:00:00Z", notices: [notice(CR, A, T("02"), 5, 5)], threads: [], comments: [] },
    ],
  };
}

test("each answer shape reaches each labeled bucket", () => {
  const cases = [
    ["table", "| Finding | Verdict |\n|---|---|\n| x | VALID, fixed |", "valid-fixed"],
    ["table", "| Finding | Verdict |\n|---|---|\n| x | VALID (defer) filed #900 |", "valid-follow-up"],
    ["table", "| Finding | Classification |\n|---|---|\n| x | INTENTIONAL |", "intentional"],
    ["table", "| Finding | Verdict |\n|---|---|\n| x | INCORRECT |", "incorrect"],
    ["table", "| Finding | Verdict |\n|---|---|\n| x | UNCERTAIN |", "uncertain"],
    ["pr-unblock", "**pr-unblock / address-feedback: VALID, fixed**\n\nFix: 1234567", "valid-fixed"],
    ["pr-unblock", "**pr-unblock / address-feedback: VALID (defer), left open**\n\nFiled #900.", "valid-follow-up"],
    ["pr-unblock", "**pr-unblock / address-feedback: INCORRECT, left open**", "incorrect"],
    ["pr-unblock", "**pr-unblock / address-feedback: UNCERTAIN, left open**", "uncertain"],
    ["prose", "VALID, fixed in 1234567.", "valid-fixed"],
    ["prose", "Fixed in 1234567.", "valid-fixed"],
    ["prose", "VALID (defer), tracked in #900.", "valid-follow-up"],
    ["prose", "INTENTIONAL: the default is the owner's decision.", "intentional"],
    ["prose", "INCORRECT: the guard is two lines up.", "incorrect"],
    ["prose", "UNCERTAIN until the renderer is checked.", "uncertain"],
    ["prose", "Acknowledged, no change.", "answered-unlabeled"],
    ["prose", "This looks valid and the fix is incorrect to skip.", "answered-unlabeled"],
  ];
  for (const [shape, text, bucket] of cases) {
    assert.equal(answerBucket(text, 500).bucket, bucket, `${shape}: ${text}`);
  }
  // The verdict column decides even when another column holds a label word.
  assert.equal(answerBucket("| Finding | Verdict | Evidence |\n|---|---|---|\n| INCORRECT claim? | VALID, fixed | f |", 500).bucket, "valid-fixed");
  assert.deepEqual(bucketOf("VALID (defer): see #50", 500), { bucket: "answered-unlabeled", deferUnlinked: true });
});

test("first lines normalize past case, backticks and line numbers", () => {
  assert.equal(normalizeFirstLine("**The `docs` link at line 5 is broken**\nmore"), normalizeFirstLine("  **The docs link at line 7 is   broken**"));
  assert.notEqual(normalizeFirstLine("manifest flag: removing the default turns the check on"), normalizeFirstLine("manifest flag: the removed default switches the check on for everyone"));
});

test("per-lane counts, outcomes and precision over the fixture", () => {
  const result = compute(fixture());
  assert.deepEqual(result.lanes[CR], {
    findings: 7,
    reposts: 1,
    outcomes: { "valid-fixed": 2, "valid-follow-up": 0, intentional: 1, incorrect: 1, uncertain: 1, "answered-unlabeled": 0, unanswered: 1 },
    labeled: 5,
    precision: 0.4,
    defer_unlinked: 0,
    inline_mismatch: 0,
    heads_reviewed: 7,
  });
  assert.deepEqual(result.lanes[SR], {
    findings: 4,
    reposts: 1,
    outcomes: { "valid-fixed": 0, "valid-follow-up": 1, intentional: 0, incorrect: 0, uncertain: 0, "answered-unlabeled": 2, unanswered: 0 },
    labeled: 1,
    precision: 1,
    defer_unlinked: 1,
    inline_mismatch: 0,
    heads_reviewed: 5,
  });
  assert.deepEqual(result.prs.map((pr) => pr.number), [101, 102, 103]);
});

test("the Codex thread is no finding, and a Codex finding on the same line is no repost", () => {
  const pr102 = compute(fixture()).prs.find((pr) => pr.number === 102).lanes[CR];
  assert.equal(pr102.findings, 3);
  assert.equal(pr102.reposts, 1);
  assert.equal(pr102.outcomes["valid-fixed"], 1);
  const pr101 = compute(fixture()).prs.find((pr) => pr.number === 101).lanes[CR];
  assert.equal(pr101.findings, 3);
});

test("a repost is caught by path and first line, and by a citation of the earlier finding", () => {
  const prs = compute(fixture()).prs;
  assert.equal(prs.find((pr) => pr.number === 102).lanes[CR].reposts, 1);
  assert.equal(prs.find((pr) => pr.number === 101).lanes[SR].reposts, 1);
  // Without the citation the reworded flag is a fresh finding.
  const snap = fixture();
  const reply = snap.prs[0].threads[3].comments[1];
  reply.body = "Acknowledged again, no change.";
  const pr101 = compute(snap).prs.find((pr) => pr.number === 101).lanes[SR];
  assert.equal(pr101.reposts, 0);
  assert.equal(pr101.outcomes["answered-unlabeled"], 2);
  // A link to the earlier thread's reply alone resolves to that thread's finding.
  reply.body = "No change; see https://github.com/example/repo/pull/101#discussion_r3005";
  assert.equal(compute(snap).prs.find((pr) => pr.number === 101).lanes[SR].reposts, 1);
});

test("a summary-only finding takes its answer from the lane's issue-comment table", () => {
  const pr101 = compute(fixture()).prs.find((pr) => pr.number === 101).lanes[CR];
  assert.equal(pr101.outcomes.intentional, 1);
  const snap = fixture();
  snap.prs[0].comments.shift();
  assert.equal(compute(snap).prs.find((pr) => pr.number === 101).lanes[CR].outcomes.unanswered, 1);
});

test("a comment or notice at or after until is ignored", () => {
  const pr103 = compute(fixture()).prs.find((pr) => pr.number === 103);
  assert.equal(pr103.lanes[CR].outcomes.unanswered, 1);
  assert.equal(pr103.lanes[CR].heads_reviewed, 1);
  assert.equal(pr103.lane_review_rounds[CR], null);
  assert.equal(compute(fixture()).prs.find((pr) => pr.number === 101).fix_rounds, 1);
});

test("both round counts", () => {
  const result = compute(fixture());
  const rounds = Object.fromEntries(result.prs.map((pr) => [pr.number, [pr.lane_review_rounds[CR], pr.lane_review_rounds[SR], pr.fix_rounds]]));
  assert.deepEqual(rounds, { 101: [3, null, 1], 102: [3, 2, null], 103: [null, null, null] });
  assert.deepEqual(result.rounds, {
    cap: 3,
    cap_source: "docs/conventions/pr-pipeline.yaml loop.review-rounds",
    lane_review_rounds: { [CR]: { prs: 2, never_clean: 1, over_cap: 0 }, [SR]: { prs: 1, never_clean: 2, over_cap: 0 } },
    fix_rounds: { prs: 1, over_cap: 0 },
  });
  const snap = fixture();
  snap.rounds_cap.value = 2;
  assert.equal(compute(snap).rounds.lane_review_rounds[CR].over_cap, 2);
  // A clean head followed by new findings does not end the count.
  snap.prs[1].notices = [notice(CR, D, T("10"), 1, 1), notice(CR, E, T("11"), 0, 0), notice(CR, F, T("12"), 1, 0), notice(CR, A, T("13"), 0, 0)];
  assert.equal(compute(snap).prs.find((pr) => pr.number === 102).lane_review_rounds[CR], 4);
  snap.prs[1].notices.pop();
  assert.equal(compute(snap).prs.find((pr) => pr.number === 102).lane_review_rounds[CR], null);
});

// Reverse every array and every object's key order: input order must not reach the output.
function permute(value) {
  if (Array.isArray(value)) return value.map(permute).reverse();
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).reverse().map((k) => [k, permute(value[k])]));
  return value;
}

test("compute is deterministic: twice, and over a permuted copy, the same bytes", () => {
  const once = stableStringify(compute(fixture()));
  assert.equal(stableStringify(compute(fixture())), once);
  const reordered = fixture();
  for (const pr of reordered.prs) {
    pr.notices.reverse();
    pr.comments.reverse();
    pr.threads = pr.threads.reverse().map((t) => ({ ...t, comments: [...t.comments] }));
  }
  assert.equal(stableStringify(compute(permute(reordered))), once);
  assert.doesNotMatch(once, /"(generated|now|runAt)"/);
});

test("the CLI computes from a saved snapshot in both formats", () => {
  const file = join(TMP, "snap.json");
  writeFileSync(file, JSON.stringify(fixture()));
  const json = spawnSync(process.execPath, [SCRIPT, "--snapshot", file], { encoding: "utf8" });
  assert.equal(json.status, 0, json.stderr);
  assert.equal(json.stdout, stableStringify(compute(fixture())));
  const md = spawnSync(process.execPath, [SCRIPT, "--snapshot", file, "--format", "md"], { encoding: "utf8" });
  assert.equal(md.status, 0, md.stderr);
  assert.match(md.stdout, /\| claude-review \| 7 \| 1 \| 2 \| 0 \| 1 \| 1 \| 1 \| 40\.0% \(5\) \| 0 \| 1 \|/);
  assert.equal(md.stdout, renderMarkdown(compute(fixture())));
});

test("arguments: the default window, and windows before the format are refused", () => {
  const opts = parseArgs([], Date.parse("2026-11-01T03:25:00Z"));
  assert.deepEqual([opts.since, opts.until], ["2026-10-25T00:00:00Z", "2026-11-01T00:00:00Z"]);
  assert.throws(() => parseArgs(["--since", "2026-10-20", "--until", "2026-10-22"], Date.parse("2026-11-01T00:00:00Z")), /not supported/);
  const run = spawnSync(process.execPath, [SCRIPT, "--since", "2026-10-01", "--until", "2026-10-05"], { encoding: "utf8" });
  assert.equal(run.status, 2);
  assert.throws(() => parseArgs(["fetch"]), /--out/);
});
