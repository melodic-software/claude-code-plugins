// lib/prior-findings.mjs: which earlier posts count as a CI review lane's own
// findings (bot author and lane footer, never text alone), whether the lines a
// finding names changed since the head it was posted on (a real git diff), and
// whether the lane already reviewed an earlier head, which makes it blocking only.
import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { laneChecker } from "../lib/lane-binding.mjs";
import { bound, fakeActions, laneRun, RUN, recordEntry } from "../lib/lane-binding.fixtures.mjs";
import {
  bindPosts,
  collect,
  isLanePost,
  main,
  readAfterFirstReview,
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
    assert.equal(forged.reviewed, 0);
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

describe("earlier reviews and blocking only", () => {
  test("the count is the distinct earlier heads the lane posted findings on, never the head under review", () => {
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
    assert.equal(result.reviewed, 2);
  });

  test("a reviewed-head summary comment counts its head when it reports a review, clean or not, never a skip", () => {
    // The status line ci-workflows publish-review/publish.cjs statusLine writes.
    const summary = (sha, findings, author = BOT, read = "2 of 2") => ({
      url: "u",
      lastEditedAt: null,
      author,
      body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${sha} -->\n<!-- claude-lane-reviewed-base ref=main merge-base=${v1} -->\n**${LANE}** reviewed \`${sha}\`: read ${read} changed file(s); ${findings} finding(s), 0 as inline comments.\n\nA finding.\n\ncritical-findings: 0`,
    });
    const skip = {
      url: "u",
      lastEditedAt: null,
      author: BOT,
      body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${v1} -->\n**${LANE}** needs no new review of \`${v1}\`: no file in scope changed.\n\n1 finding(s) carried forward.`,
    };
    const reviewed = (comments, head = edited) => collect({ threads: [], reviews: [], comments, lane: LANE, head, diff }).reviewed;
    assert.equal(reviewed([summary(v1, 1), summary(shifted, 2)]), 2);
    // A clean first review is still the first whole review.
    assert.equal(reviewed([summary(v1, 0)]), 1);
    // A partial read is not a whole review: files no review saw stay unreviewed.
    assert.equal(reviewed([summary(v1, 0, BOT, "3 of 18")]), 0);
    assert.equal(reviewed([summary(v1, 0, BOT, "0 of 18")]), 0);
    assert.equal(reviewed([skip]), 0);
    assert.equal(reviewed([summary(edited, 1)]), 0);
    assert.equal(reviewed([summary(v1, 1, PERSON)]), 0);
    assert.equal(collect({ threads: [], reviews: [], comments: [summary(v1, 1)], lane: LANE, head: edited, diff }).findings[0].posted, v1);
  });

  test("a partial read with an inline finding is still not a whole review of its head", () => {
    // publish.cjs posts a review whenever there is an inline finding, so a
    // partial first read leaves a lane thread and a review on v1 beside its
    // `read 3 of 18` summary; the summary decides for v1.
    const partialSummary = {
      url: "u",
      lastEditedAt: null,
      author: BOT,
      body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${v1} -->\n**${LANE}** reviewed \`${v1}\`: read 3 of 18 changed file(s); 1 finding(s), 1 as inline comments.`,
    };
    const review = { url: "u", body: `**${LANE}**: 1 inline finding(s) on \`${v1}\`.\n\nclaude-lane: ${LANE}`, lastEditedAt: null, author: BOT, commit: { oid: v1 } };
    const result = (comments) => collect({ threads: [thread(BOT)], reviews: [review], comments, lane: LANE, head: edited, diff }).reviewed;
    assert.equal(result([partialSummary]), 0);
    // The same thread and review with no partial summary still count v1.
    assert.equal(result([]), 1);
    // A skip's comment on v1 reports no read, so it does not mark v1 partial.
    const skip = { ...partialSummary, body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${v1} -->\n**${LANE}** needs no new review of \`${v1}\`: no file in scope changed.` };
    assert.equal(result([skip]), 1);
  });

  test("render states blocking only once the lane reviewed an earlier head", () => {
    assert.match(render({ lane: LANE, findings: [], reviewed: 0, more: false }), /^- blocking only: no$/mu);
    assert.match(render({ lane: LANE, findings: [], reviewed: 1, more: false }), /^- blocking only: yes$/mu);
    assert.match(render({ lane: LANE, findings: [], reviewed: 4, more: false }), /^- earlier heads this lane reviewed: 4$/mu);
    assert.doesNotMatch(render({ lane: LANE, findings: [], reviewed: 1, more: false }), /cap/u);
  });

  test("with findings-after-first-review all, blocking only is no on every head", () => {
    for (const reviewed of [0, 1, 4]) {
      assert.match(render({ lane: LANE, findings: [], reviewed, more: false, afterFirstReview: "all" }), /^- blocking only: no$/mu);
    }
    assert.match(render({ lane: LANE, findings: [], reviewed: 1, more: false, afterFirstReview: "blocking-only" }), /^- blocking only: yes$/mu);
  });

  test("the setting is read from the loop block, else blocking-only", () => {
    const loop = (line) => `merge:\n  rung: off\n\nloop:\n  review-rounds: 3\n  # a note\n${line}\n  fix-ci-rounds: 3\n`;
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: all")), "all");
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: \"all\" # every finding")), "all");
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: all").replaceAll("\n", "\r\n")), "all");
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: blocking-only")), "blocking-only");
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: everything")), "blocking-only");
    assert.equal(readAfterFirstReview(loop("  findings-after-first-review: all-findings")), "blocking-only");
    assert.equal(readAfterFirstReview(loop("")), "blocking-only");
    assert.equal(readAfterFirstReview("lanes:\n  x:\n    findings-after-first-review: all\nloop:\n  review-rounds: 3\n"), "blocking-only");
    assert.equal(readAfterFirstReview(""), "blocking-only");
    assert.equal(readAfterFirstReview(undefined), "blocking-only");
  });

  test("blank and whitespace-only lines in the loop block are skipped in linear time", () => {
    assert.equal(readAfterFirstReview("loop:\n\n  \t\n    \n  findings-after-first-review: all\n"), "all");
    const start = performance.now();
    assert.equal(readAfterFirstReview(`loop:\n${"  \n".repeat(40)}x`), "blocking-only");
    assert.equal(readAfterFirstReview(`loop:\n${"  \n".repeat(40)}  findings-after-first-review: all\n`), "all");
    assert.ok(performance.now() - start < 1000);
  });
});

describe("main reads the setting from CAP_CONFIG", () => {
  const dir = mkdtempSync(join(tmpdir(), "prior-findings-main-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  // The lane reviewed an earlier head whole, so the default is blocking only.
  const earlier = "a".repeat(40);
  const summary = {
    url: "https://example.test/c1",
    body: `<!-- claude-lane-reviewed-head lane=${LANE} sha=${earlier} -->\n**${LANE}** reviewed \`${earlier}\`: read 2 of 2 changed file(s); 0 finding(s), done.`,
    lastEditedAt: null,
    editor: null,
    author: BOT,
  };
  const page = (nodes) => ({ pageInfo: { hasNextPage: false }, nodes });
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    json: async () => ({ data: { repository: { pullRequest: { reviewThreads: page([]), reviews: page([]), comments: page([summary]) } } } }),
  });
  const blockingOnly = async (name, capConfig) => {
    const output = join(dir, `${name}.md`);
    const env = { REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: "b".repeat(40), LANE, OUTPUT_PATH: output, GITHUB_TOKEN: "t" };
    if (capConfig !== undefined) env.CAP_CONFIG = capConfig;
    await main({ env, fetchImpl, git: () => "" });
    const text = readFileSync(output, "utf8");
    assert.match(text, /^- earlier heads this lane reviewed: 1$/mu);
    return /^- blocking only: (yes|no)$/mu.exec(text)[1];
  };
  const config = (name, text) => {
    const path = join(dir, name);
    writeFileSync(path, text);
    return path;
  };

  test("no CAP_CONFIG, an unreadable one, or no key: blocking only", async () => {
    assert.equal(await blockingOnly("unset"), "yes");
    assert.equal(await blockingOnly("missing", join(dir, "absent.yaml")), "yes");
    assert.equal(await blockingOnly("nokey", config("nokey.yaml", "loop:\n  review-rounds: 3\n")), "yes");
  });

  test("blocking-only keeps blocking only; all turns it off", async () => {
    assert.equal(await blockingOnly("blocking", config("blocking.yaml", "loop:\n  findings-after-first-review: blocking-only\n")), "yes");
    assert.equal(await blockingOnly("all", config("all.yaml", "loop:\n  findings-after-first-review: all\n")), "no");
  });
});

describe("a footed post counts only when the run its binding names recorded it", () => {
  const POSTED = "2026-11-01T00:00:00Z";
  const boundBody = bound(FINDING, { lane: LANE });
  const boundThread = (body = boundBody, author = BOT) => {
    const t = thread(author, body);
    t.comments.nodes[0] = { ...t.comments.nodes[0], databaseId: 11, createdAt: POSTED, updatedAt: POSTED };
    return t;
  };
  const entry = (body = boundBody, extra = {}) => recordEntry(body, { lane: LANE, ...extra });
  const bindThreads = async (threads, runs) => {
    const actions = fakeActions(runs);
    const check = laneChecker({ pr: 7, ...actions });
    const posts = await bindPosts({ threads, reviews: [], comments: [], lane: LANE, check });
    return { found: run(posts.threads, shifted).findings, calls: actions.calls };
  };

  test("a bound post its run recorded is the lane's, and is read without its binding line", async () => {
    // The severity line sits right above the binding: the finding reads as it did before bindings.
    const { found } = await bindThreads([boundThread()], { [RUN]: laneRun([entry()], { lane: LANE }) });
    assert.equal(found.length, 1);
    assert.equal(found[0].body, FINDING);
  });

  test("a bound post its run did not record, or whose run is another workflow, is not the lane's", async () => {
    const missing = await bindThreads([boundThread()], { [RUN]: laneRun([entry(boundBody, { id: 12 })], { lane: LANE }) });
    assert.deepEqual(missing.found, []);
    const otherWorkflow = await bindThreads([boundThread()], { [RUN]: { ...laneRun([entry()], { lane: LANE }), path: ".github/workflows/other.yml" } });
    assert.deepEqual(otherWorkflow.found, []);
    const tampered = await bindThreads([boundThread(bound("Nothing to see.", { lane: LANE }))], { [RUN]: laneRun([entry()], { lane: LANE }) });
    assert.deepEqual(tampered.found, []);
  });

  test("a re-run attempt's record binds its posts", async () => {
    const runs = {
      [RUN]: {
        path: laneRun([], { lane: LANE }).path,
        artifacts: [
          { name: `claude-lane-comments-${LANE}-1`, entries: [] },
          { name: `claude-lane-comments-${LANE}-2`, entries: [entry()] },
        ],
      },
    };
    assert.equal((await bindThreads([boundThread()], runs)).found.length, 1);
  });

  test("a post with no binding still counts and reads no artifact", async () => {
    const { found, calls } = await bindThreads([boundThread(`${FINDING}\n\nclaude-lane: ${LANE}`)], {});
    assert.equal(found.length, 1);
    assert.deepEqual(calls, []);
  });

  test("only the bot's footed posts are checked; another account's lookalike reads nothing", async () => {
    const { found, calls } = await bindThreads([boundThread(boundBody, PERSON)], {});
    assert.deepEqual(found, []);
    assert.deepEqual(calls, []);
  });

  test("a review and an issue comment are checked as their own kinds: a record of another kind binds nothing", async () => {
    const reviewBody = bound("Summary finding", { lane: LANE });
    const review = { url: "u", databaseId: 21, createdAt: POSTED, body: reviewBody, lastEditedAt: null, author: BOT, commit: { oid: v1 } };
    const comment = { url: "c", databaseId: 31, createdAt: POSTED, body: bound("Comment finding", { lane: LANE }), lastEditedAt: null, author: BOT };
    const actions = fakeActions({
      [RUN]: laneRun([entry(reviewBody, { kind: "review", id: 21 }), entry(comment.body, { kind: "review_comment", id: 31 })], { lane: LANE }),
    });
    const posts = await bindPosts({ threads: [], reviews: [review], comments: [comment], lane: LANE, check: laneChecker({ pr: 7, ...actions }) });
    const { findings } = collect({ ...posts, lane: LANE, head: v1, diff });
    assert.deepEqual(
      findings.map((f) => [f.source, f.body]),
      [["review", "Summary finding"]],
    );
  });

  test("a failed read fails the job rather than dropping the post", async () => {
    await assert.rejects(bindThreads([boundThread()], {}), /Not Found/u);
  });

  test("main reads the run, its artifacts and the record zip with the job token, never sending it to the download host", async () => {
    const dir = mkdtempSync(join(tmpdir(), "prior-findings-bound-"));
    after(() => rmSync(dir, { recursive: true, force: true }));
    const actions = fakeActions({ [RUN]: laneRun([entry()], { lane: LANE }) });
    const page = (nodes) => ({ pageInfo: { hasNextPage: false }, nodes });
    const seen = [];
    const json = (body) => ({ ok: true, status: 200, json: async () => body });
    const fetchImpl = async (url, init = {}) => {
      seen.push([url, init.headers?.authorization ?? null]);
      if (url.endsWith("/graphql")) {
        return json({ data: { repository: { pullRequest: { reviewThreads: page([boundThread()]), reviews: page([]), comments: page([]) } } } });
      }
      let m = /\/repos\/o\/r\/pulls\/(\d+)$/u.exec(url);
      if (m) return json(await actions.getPull(Number(m[1])));
      m = /\/repos\/o\/r\/actions\/runs\/(\d+)$/u.exec(url);
      if (m) return json(await actions.getRun(m[1]));
      m = /\/repos\/o\/r\/actions\/runs\/(\d+)\/artifacts\?per_page=100&page=(\d+)$/u.exec(url);
      if (m) {
        const artifacts = m[2] === "1" ? await actions.listArtifacts(m[1]) : [];
        return json({ total_count: artifacts.length, artifacts });
      }
      m = /\/repos\/o\/r\/actions\/artifacts\/(\d+)\/zip$/u.exec(url);
      if (m) return { ok: false, status: 302, headers: new Headers({ location: `https://blob.example.test/${m[1]}` }) };
      m = /^https:\/\/blob\.example\.test\/(\d+)$/u.exec(url);
      if (m) {
        const bytes = await actions.download(Number(m[1]));
        return { ok: true, status: 200, arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };
    const output = join(dir, "out.md");
    const env = { REPOSITORY: "o/r", PR_NUMBER: "7", HEAD_SHA: shifted, LANE, OUTPUT_PATH: output, GITHUB_TOKEN: "t" };
    await main({ env, fetchImpl, git: () => "" });
    const text = readFileSync(output, "utf8");
    assert.match(text, /^Trust control: the merge hold narrowed\.$/mu);
    assert.doesNotMatch(text, /claude-lane-run/u);
    assert.deepEqual(
      seen.filter(([url]) => url.startsWith("https://blob.")).map(([, auth]) => auth),
      [null],
    );
    assert.ok(seen.filter(([url]) => url.includes("/actions/")).every(([, auth]) => auth === "Bearer t"));
  });
});
