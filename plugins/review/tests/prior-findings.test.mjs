// lib/prior-findings.mjs: which earlier posts count as a CI review lane's own
// findings (bot author and lane footer, never text alone), whether the lines a
// finding names changed since the head it was posted on (a real git diff), and
// the lane's round count against the repo-owned cap.
import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import {
  collect,
  isLanePost,
  readCap,
  render,
  touchesOriginal,
} from "../lib/prior-findings.mjs";

const LANE = "claude-security-review";
// github-actions[bot]'s numeric id; GraphQL reports its login without "[bot]".
const BOT = { __typename: "Bot", login: "github-actions", databaseId: 41898282 };
const PERSON = { __typename: "User", login: "mallory" };

// A throwaway repository: v1 is the head a finding was posted on, `shifted`
// inserts lines above the finding (it moves, its text does not change), and
// `edited` rewrites the finding's own line.
const repo = mkdtempSync(join(tmpdir(), "prior-findings-"));
after(() => rmSync(repo, { recursive: true, force: true }));
const git = (...args) =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", ...args], {
    cwd: repo,
    encoding: "utf8",
    env: { PATH: process.env.PATH, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", HOME: repo },
  }).trim();
const commit = (text) => {
  writeFileSync(join(repo, "gate.mjs"), text);
  git("add", "gate.mjs");
  git("commit", "--quiet", "-m", "c");
  return git("rev-parse", "HEAD");
};
git("init", "--quiet");
const lines = ["a", "b", "c", "d", "if (author === trusted) merge();", "f", "g"];
// The finding names line 5 of v1.
const v1 = commit(`${lines.join("\n")}\n`);
const shifted = commit(`x\ny\n${lines.join("\n")}\n`);
const edited = commit(`x\ny\n${lines.slice(0, 4).join("\n")}\nif (isTrusted(author)) merge();\nf\ng\n`);
const diff = (from, to, path) =>
  execFileSync("git", ["diff", "-U0", "--no-color", from, to, "--", path], { cwd: repo, encoding: "utf8" });

const FINDING = "Trust control: the merge hold narrowed.\n\nseverity: CRITICAL";
const thread = (author, body = `${FINDING}\n\nclaude-lane: ${LANE}`, extra = {}) => ({
  isResolved: false,
  path: "gate.mjs",
  originalLine: 5,
  originalStartLine: null,
  diffSide: "RIGHT",
  comments: {
    nodes: [
      { url: "https://example.test/r1", body, lastEditedAt: null, editor: null, originalCommit: { oid: v1 }, author, ...extra },
    ],
  },
});
const run = (threads, head) => collect({ threads, reviews: [], comments: [], lane: LANE, head, diff });

describe("which posts are the lane's own", () => {
  test("a forged lookalike from another account is not a prior finding, so the finding is still reported", () => {
    // Right footer and severity line, wrong author: the same thread from the
    // lane's bot is listed (paired presence case below), this one is not.
    const forged = run([thread(PERSON)], shifted);
    assert.deepEqual(forged.findings, []);
    assert.equal(forged.rounds, 0);
    assert.equal(run([thread(BOT)], shifted).findings.length, 1);
  });

  test("a lookalike bot with another id or a User named github-actions is not the lane", () => {
    assert.equal(isLanePost({ author: { ...BOT, databaseId: 1 }, body: `x\n\nclaude-lane: ${LANE}`, lastEditedAt: null }, LANE), false);
    assert.equal(isLanePost({ author: { __typename: "User", login: "github-actions", databaseId: 41898282 }, body: `x\n\nclaude-lane: ${LANE}`, lastEditedAt: null }, LANE), false);
    assert.equal(isLanePost({ author: BOT, body: `x\n\nclaude-lane: ${LANE}`, lastEditedAt: null }, LANE), true);
  });

  test("the other lane's footer, a footer not on the last line, and an edit by another account are not this lane's", () => {
    assert.equal(isLanePost({ author: BOT, body: "x\n\nclaude-lane: claude-review", lastEditedAt: null }, LANE), false);
    assert.equal(isLanePost({ author: BOT, body: `claude-lane: ${LANE}\n\nmore text`, lastEditedAt: null }, LANE), false);
    const edit = { author: BOT, body: `x\n\nclaude-lane: ${LANE}`, lastEditedAt: "2026-11-01T00:00:00Z" };
    assert.equal(isLanePost({ ...edit, editor: PERSON }, LANE), false);
    assert.equal(isLanePost({ ...edit, editor: BOT }, LANE), true);
  });

  test("a footer wrapped in backticks, the form the other lane parsers accept, is the lane's and is stripped", () => {
    // clear-escalations.mjs LANE_TAG and babysit_review_evidence.py LANE_TAG_RE
    // read `claude-lane: <lane>` with optional backticks.
    const ticked = `x\n\n\`claude-lane: ${LANE}\``;
    assert.equal(isLanePost({ author: BOT, body: ticked, lastEditedAt: null }, LANE), true);
    assert.equal(isLanePost({ author: BOT, body: "x\n\n`claude-lane: claude-review`", lastEditedAt: null }, LANE), false);
    const [found] = run([thread(BOT, `${FINDING}\n\n\`claude-lane: ${LANE}\``)], shifted).findings;
    assert.equal(found.body, FINDING);
  });

  test("the lane's reviewed-head marker comment counts as the lane's own post", () => {
    const marker = `<!-- claude-lane-reviewed-head lane=${LANE} sha=${v1} -->\nsummary`;
    assert.equal(isLanePost({ author: BOT, body: marker, lastEditedAt: null }, LANE), true);
    assert.equal(isLanePost({ author: PERSON, body: marker, lastEditedAt: null }, LANE), false);
  });
});

describe("lines changed since the finding was posted", () => {
  test("a lane-authored prior finding on unchanged lines is suppressible: lines changed no", () => {
    // Lines were inserted above it, so its line number moved; its text did not change.
    const [found] = run([thread(BOT)], shifted).findings;
    assert.equal(found.changed, "no");
    assert.equal(found.path, "gate.mjs");
    assert.equal(found.posted, v1);
    assert.equal(found.body, FINDING);
  });

  test("the same finding on changed lines is re-posted: lines changed yes", () => {
    const [found] = run([thread(BOT)], edited).findings;
    assert.equal(found.changed, "yes");
  });

  test("a resolved thread is never suppressible: only a thread still open is listed unchanged", () => {
    // Same thread and unchanged lines as the case above, which answers no.
    const [found] = run([{ ...thread(BOT), isResolved: true }], shifted).findings;
    assert.match(found.changed, /^yes \(the thread is resolved/u);
    assert.equal(run([{ ...thread(BOT), isResolved: undefined }], shifted).findings[0].changed.startsWith("yes"), true);
  });

  test("a finding on the head it was posted at is unchanged", () => {
    assert.equal(run([thread(BOT)], v1).findings[0].changed, "no");
  });

  test("a finding the job cannot judge is never suppressible", () => {
    const failing = collect({
      threads: [thread(BOT)],
      reviews: [],
      comments: [],
      lane: LANE,
      head: shifted,
      diff: () => {
        throw new Error("no such commit");
      },
    });
    assert.match(failing.findings[0].changed, /^yes \(/u);
    const left = run([{ ...thread(BOT), diffSide: "LEFT" }], shifted);
    assert.match(left.findings[0].changed, /^yes \(/u);
    const review = collect({
      threads: [],
      reviews: [{ url: "u", body: `Summary finding\n\nclaude-lane: ${LANE}`, lastEditedAt: null, author: BOT, commit: { oid: v1 } }],
      comments: [],
      lane: LANE,
      head: v1,
      diff,
    });
    assert.equal(review.findings[0].path, null);
    assert.match(review.findings[0].changed, /^yes \(no line anchor/u);
  });

  test("touchesOriginal reads the old side of each hunk", () => {
    // Old line 5 replaced: touches 5, not 1-3 or 7.
    assert.equal(touchesOriginal("@@ -5 +7 @@\n", 5, 5), true);
    assert.equal(touchesOriginal("@@ -5 +7 @@\n", 1, 3), false);
    assert.equal(touchesOriginal("@@ -5 +7 @@\n", 7, 7), false);
    // Two lines inserted after old line 0 border a range starting at 1 only.
    assert.equal(touchesOriginal("@@ -0,0 +1,2 @@\n", 1, 1), true);
    assert.equal(touchesOriginal("@@ -0,0 +1,2 @@\n", 5, 5), false);
  });
});

describe("rounds and the cap", () => {
  test("rounds count the distinct earlier heads the lane posted findings on, never the head under review", () => {
    const second = { ...thread(BOT), comments: { nodes: [{ ...thread(BOT).comments.nodes[0], originalCommit: { oid: shifted } }] } };
    // A rerun on `edited` already holds the lane's posts on it; they are not a
    // round before this review.
    const onHead = { ...thread(BOT), comments: { nodes: [{ ...thread(BOT).comments.nodes[0], originalCommit: { oid: edited } }] } };
    const result = collect({
      threads: [thread(BOT), thread(BOT), second, onHead, thread(PERSON, `x\n\nclaude-lane: ${LANE}`, { originalCommit: { oid: edited } })],
      reviews: [
        { url: "u", body: `**${LANE}**: 1 inline finding(s) on \`${edited}\`; the summary is in this lane's pull request comment.\n\nclaude-lane: ${LANE}`, lastEditedAt: null, author: BOT, commit: { oid: edited } },
      ],
      comments: [],
      lane: LANE,
      head: edited,
      diff,
    });
    assert.equal(result.rounds, 2);
  });

  test("a reviewed-head summary comment counts its head as a round only when it states a finding", () => {
    // The status line ci-workflows publish-review/publish.cjs statusLine writes.
    const summary = (sha, findings, author = BOT) => ({
      url: "u",
      lastEditedAt: null,
      author,
      body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${sha} -->\n<!-- claude-lane-reviewed-base ref=main merge-base=${v1} -->\n**${LANE}** reviewed \`${sha}\`: read 2 of 2 changed file(s); ${findings} finding(s), 0 as inline comments.\n\nA finding.\n\ncritical-findings: 0`,
    });
    const skip = {
      url: "u",
      lastEditedAt: null,
      author: BOT,
      body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${v1} -->\n**${LANE}** needs no new review of \`${v1}\`: no file in scope changed.\n\n1 finding(s) carried forward.`,
    };
    const rounds = (comments, head = edited) => collect({ threads: [], reviews: [], comments, lane: LANE, head, diff }).rounds;
    assert.equal(rounds([summary(v1, 1), summary(shifted, 2)]), 2);
    assert.equal(rounds([summary(v1, 0)]), 0);
    assert.equal(rounds([skip]), 0);
    assert.equal(rounds([summary(edited, 1)]), 0);
    assert.equal(rounds([summary(v1, 1, PERSON)]), 0);
    assert.equal(collect({ threads: [], reviews: [], comments: [summary(v1, 1)], lane: LANE, head: edited, diff }).findings[0].posted, v1);
  });

  test("readCap reads loop.review-rounds and nothing else", () => {
    assert.equal(readCap("version: 2\nloop:\n  review-rounds: 3\n  dependency-review-rounds: 2\n"), 3);
    assert.equal(readCap("version: 2\nloop:\n  dependency-review-rounds: 2\n"), null);
    assert.equal(readCap("review-rounds: 9\n"), null);
  });

  test("render states past the cap only once the rounds reach it", () => {
    const at = render({ lane: LANE, findings: [], rounds: 3, cap: 3, more: false });
    assert.match(at, /^- past the cap: yes$/mu);
    assert.match(render({ lane: LANE, findings: [], rounds: 2, cap: 3, more: false }), /^- past the cap: no$/mu);
    assert.match(render({ lane: LANE, findings: [], rounds: 9, cap: null, more: false }), /^- past the cap: no \(no cap/mu);
  });
});
