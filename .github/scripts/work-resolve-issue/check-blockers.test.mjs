import assert from "node:assert/strict";
import { rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { renderSplitRecord, SIZE_SPLIT_MARKER } from "../intake-triage/admit.mjs";
import { main } from "./check-blockers.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HUMAN = { id: 101, login: "person" };
const STRANGER = { id: 202, login: "stranger" };
const APP = { id: 303, login: "melodic-automation-lanes[bot]" };
const UNTRUSTED = "work-class: untrusted-provenance";
const dir = tempDir("check-blockers-");
after(() => rmSync(dir, { recursive: true, force: true }));
const TRUSTED = join(dir, "trusted-actors.json");
writeFileSync(TRUSTED, JSON.stringify({ version: 1, actors: [{ kind: "human", id: HUMAN.id, login: HUMAN.login }] }));
const ENV = { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: "42", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(APP.id) };

const issue = (number, state, { repo = "o/r", reason = state === "closed" ? "completed" : null, closer = HUMAN } = {}) => ({
  number,
  state,
  state_reason: reason,
  closed_by: state === "closed" ? closer : null,
  repository_url: `https://api.github.com/repos/${repo}`,
});
const pull = (number, merged) => ({ ...issue(number, "closed"), pull_request: { merged_at: merged ? "2026-10-01T00:00:00Z" : null } });
const labelEvent = (kind, actor) => ({ event: kind, label: { name: UNTRUSTED }, actor });

// One GraphQL answer for both reads: no merged pull request closed a blocker
// (timelineItems), and the issue's text a listed human wrote (specOf).
const GRAPHQL = {
  data: {
    repository: {
      issue: {
        timelineItems: { nodes: [{ closer: null }] },
        body: "Plain issue.",
        lastEditedAt: null,
        author: { __typename: "User", databaseId: HUMAN.id },
        editor: null,
        comments: { totalCount: 0, nodes: [] },
      },
    },
  },
};

// The issue itself answers `subject`: its labels and its events. A function
// `blockers` answers every read.
async function run(blockers, { env = ENV, subject = {} } = {}) {
  const calls = [];
  const lines = [];
  const outputs = {};
  const github = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (typeof blockers === "function") {
      return blockers(path);
    }
    if (path === "/repos/o/r/issues/42") {
      if (subject.issue instanceof Error) {
        throw subject.issue;
      }
      return {
        number: 42,
        state: "open",
        ...("author" in subject ? subject.author !== undefined && { user: subject.author } : { user: HUMAN }),
        labels: (subject.labels ?? []).map((name) => ({ name })),
        ...(subject.summary && { sub_issues_summary: subject.summary }),
      };
    }
    if (path.startsWith("/repos/o/r/issues/42/sub_issues")) {
      return subject.subs ?? [];
    }
    if (path.startsWith("/repos/o/r/issues/42/events")) {
      if (subject.events instanceof Error) {
        throw subject.events;
      }
      return subject.events ?? [];
    }
    if (path.includes("/dependencies/blocked_by")) {
      return blockers;
    }
    const match = path.match(/^\/repos\/([^/]+\/[^/]+)\/issues\/(\d+)$/);
    if (match) {
      return blockers.find((item) => String(item.number) === match[2] && item.repository_url.endsWith(`/repos/${match[1]}`));
    }
    if (method === "POST" && path === "/graphql") {
      // No merged pull request closed it.
      return GRAPHQL;
    }
    throw new Error(`unexpected ${method} ${path} ${JSON.stringify(body)}`);
  };
  const code = await main({ env, github, log: (line) => lines.push(line), write: (values) => Object.assign(outputs, values) });
  return { code, calls, lines, outputs };
}

const SKIP = { proceed: "false", untrusted: "false" };
// A run that proceeds also says whether the issue is a trusted size-split
// sub-issue (admit.mjs trustedSplitChild); a listed human wrote this one.
const RUN = { proceed: "true", untrusted: "false", "split-child": "false" };
const FINAL = { proceed: "false", untrusted: "true" };
// The outside-author stop: FINAL, plus the mark report-skip reads to tell the
// issue's author is outside the trusted list.
const OUTSIDER = { ...FINAL, outsider: "true" };

test("an open blocker skips the run with a notice naming it, and writes nothing", async () => {
  const { code, calls, lines, outputs } = await run([issue(7, "open"), issue(8, "closed"), issue(9, "open", { repo: "o/other" })]);
  assert.equal(code, 0);
  assert.deepEqual(outputs, SKIP);
  assert.ok(calls.every((call) => call.startsWith("GET ")));
  const notice = lines.find((line) => line.startsWith("::notice"));
  assert.match(notice, /#7/);
  assert.match(notice, /o\/other#9/);
  assert.doesNotMatch(notice, /#8\b/);
});

test("a blocker no listed human or merge here closed still blocks: an unmerged pull request, one merged elsewhere, a close by someone unlisted", async () => {
  for (const blocker of [
    pull(7, false),
    { ...pull(7, true), repository_url: "https://api.github.com/repos/o/other" },
    issue(7, "closed", { reason: "not_planned", closer: STRANGER }),
    issue(7, "closed", { repo: "o/other", closer: STRANGER }),
  ]) {
    const { code, lines, outputs } = await run([blocker]);
    assert.equal(code, 0);
    assert.deepEqual(outputs, SKIP, JSON.stringify(blocker));
    assert.match(lines.find((line) => line.startsWith("::notice")), /#7/);
  }
});

test("an issue a listed human closed for any reason, here or in another repository, no longer blocks (admission's rule)", async () => {
  for (const blocker of [
    issue(7, "closed", { reason: "not_planned" }),
    issue(7, "closed", { reason: "duplicate" }),
    issue(7, "closed", { repo: "o/other" }),
  ]) {
    assert.deepEqual((await run([blocker])).outputs, RUN, JSON.stringify(blocker));
  }
});

test("an issue closed as completed by someone not on the trusted list still blocks", async () => {
  const { outputs, lines } = await run([issue(7, "closed", { closer: STRANGER })]);
  assert.deepEqual(outputs, SKIP);
  assert.match(lines.find((line) => line.startsWith("::notice")), /#7/);
});

test("every blocker done, or none, runs: a merged pull request, an issue a listed human closed as completed", async () => {
  assert.deepEqual((await run([issue(8, "closed"), pull(9, true)])).outputs, RUN);
  assert.deepEqual((await run([])).outputs, RUN);
});

test("a merged pull request blocker costs no trust read, so a read that would fail never crashes the run", async () => {
  const blockers = [issue(8, "closed"), pull(9, true)];
  const { code, calls, outputs } = await run((path) => {
    if (path === "/repos/o/r/issues/9") {
      throw new Error("GET failed: 502");
    }
    if (path === "/repos/o/r/issues/42") {
      return { number: 42, state: "open", user: HUMAN, labels: [], sub_issues_summary: { total: 0, completed: 0, percent_completed: 0 } };
    }
    if (path.includes("/events")) {
      return [];
    }
    if (path.includes("/dependencies/blocked_by")) {
      return blockers;
    }
    if (path === "/repos/o/r/issues/8") {
      return blockers[0];
    }
    if (path === "/graphql") {
      return GRAPHQL;
    }
    throw new Error(`unexpected ${path}`);
  });
  // Let any unawaited read settle before checking.
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(code, 0);
  assert.deepEqual(outputs, RUN);
  assert.ok(!calls.includes("GET /repos/o/r/issues/9"));
});

test("an untrusted-provenance label on the issue stops the run for good, with a notice, before any blocker read", async () => {
  const { code, calls, lines, outputs } = await run([], { subject: { labels: ["agent-ready", UNTRUSTED] } });
  assert.equal(code, 0);
  assert.deepEqual(outputs, FINAL);
  assert.ok(!calls.some((call) => call.includes("/dependencies/")));
  assert.match(lines.find((line) => line.startsWith("::notice")), /untrusted-provenance/);
});

test("the label removed by someone neither a listed human nor the App still stops the run; their removal does not", async () => {
  const added = labelEvent("labeled", APP);
  assert.deepEqual((await run([], { subject: { events: [added, labelEvent("unlabeled", STRANGER)] } })).outputs, FINAL);
  assert.deepEqual((await run([], { subject: { events: [added, labelEvent("unlabeled", HUMAN)] } })).outputs, RUN);
  assert.deepEqual((await run([], { subject: { events: [added, labelEvent("unlabeled", APP)] } })).outputs, RUN);
});

test("an issue neither a listed human nor the lanes App wrote stops the run for good, before its events or blockers are read, and marks it for report-skip", async () => {
  for (const author of [STRANGER, undefined]) {
    const { code, calls, lines, outputs } = await run([], { subject: { author } });
    assert.equal(code, 0);
    assert.deepEqual(outputs, OUTSIDER, JSON.stringify(author));
    assert.deepEqual(calls, ["GET /repos/o/r/issues/42"]);
    const notice = lines.find((line) => line.startsWith("::notice"));
    assert.match(notice, /neither a listed human nor the lanes App/);
    assert.match(notice, /re-file/);
  }
});

test("an issue a listed human or the lanes App wrote still runs", async () => {
  for (const author of [HUMAN, APP]) {
    assert.deepEqual((await run([], { subject: { author } })).outputs, RUN, author.login);
  }
});

test("labels or events it cannot read skip the run with a warning, not for good", async () => {
  const failed = new Error("GET failed: 502");
  for (const subject of [{ issue: failed }, { events: failed }]) {
    const { code, lines, outputs } = await run([], { subject });
    assert.equal(code, 0);
    assert.deepEqual(outputs, SKIP);
    assert.ok(lines.some((line) => line.startsWith("::warning")));
  }
});

test("a blocker list it cannot read skips the run with a warning and exits 0", async () => {
  const { code, lines, outputs } = await run((path) => {
    if (path.includes("/dependencies/")) {
      throw new Error("GET failed: 502");
    }
    return path.includes("/events") ? [] : { number: 42, user: HUMAN, labels: [] };
  });
  assert.equal(code, 0);
  assert.deepEqual(outputs, SKIP);
  assert.ok(lines.some((line) => line.startsWith("::warning")));
});

test("an issue number that is not one, no trusted list, or no App id skips the run with a warning and reads nothing", async () => {
  for (const env of [{ ...ENV, ISSUE_NUMBER: "1; rm" }, { ...ENV, TRUSTED_ACTORS_PATH: join(dir, "missing.json") }, { ...ENV, LANES_APP_ID: "" }]) {
    const { code, calls, lines, outputs } = await run([], { env });
    assert.equal(code, 0);
    assert.deepEqual(calls, []);
    assert.deepEqual(outputs, SKIP);
    assert.ok(lines.some((line) => line.startsWith("::warning")));
  }
});

// Admission counts a split parent the lanes App closed once a listed human
// closed every sub-issue (admit.mjs closedByTrusted); the run gate must too.
test("a split parent the lanes App closed after a listed human closed every part no longer blocks; an open part keeps it blocking", async () => {
  const record = { id: 61, user: APP, body: `${SIZE_SPLIT_MARKER}\n${renderSplitRecord({ items: "a".repeat(64), parts: [[1], [2]], order: [], filed: [50, 51] })}` };
  const world = (partState) => (path) => {
    if (path === "/repos/o/r/issues/42") return { number: 42, state: "open", user: HUMAN, labels: [], sub_issues_summary: { total: 0, completed: 0, percent_completed: 0 } };
    if (path.startsWith("/repos/o/r/issues/42/events")) return [];
    if (path.includes("/42/dependencies/blocked_by")) return [issue(7, "closed", { closer: APP })];
    if (path === "/repos/o/r/issues/7") return issue(7, "closed", { closer: APP });
    if (path.startsWith("/repos/o/r/issues/7/comments")) return [record];
    if (path.startsWith("/repos/o/r/issues/7/sub_issues")) return [issue(50, "closed"), issue(51, partState)];
    if (path === "/repos/o/r/issues/50") return issue(50, "closed");
    if (path === "/repos/o/r/issues/51") return issue(51, partState);
    if (path === "/graphql") return GRAPHQL;
    throw new Error(`unexpected ${path}`);
  };
  assert.deepEqual((await run(world("closed"))).outputs, RUN);
  assert.deepEqual((await run(world("open"))).outputs, SKIP);
});

// An umbrella's work is its sub-issues' (owner Q93, intake admission's wait):
// the run gate skips it, agent-ready kept, while one is open, and never hands
// it to a person. The issue read's sub_issues_summary decides whether the
// sub-issues are listed at all.
describe("an umbrella issue", () => {
  const summary = (total, completed) => ({ total, completed, percent_completed: total ? Math.round((completed * 100) / total) : 0 });

  test("with an open sub-issue skips the run, agent-ready kept, with a notice naming each open one", async () => {
    const subs = [issue(9691, "open"), issue(9692, "closed"), issue(9693, "open")];
    const { code, calls, lines, outputs } = await run([], { subject: { summary: summary(3, 1), subs } });
    assert.equal(code, 0);
    assert.deepEqual(outputs, SKIP);
    assert.ok(calls.every((call) => call.startsWith("GET ")));
    const notice = lines.find((line) => line.startsWith("::notice"));
    assert.match(notice, /#9691/);
    assert.match(notice, /#9693/);
    assert.doesNotMatch(notice, /#9692/);
    assert.doesNotMatch(notice, /needs-human/);
  });

  test("whose sub-issues are all closed, as completed or not planned, runs", async () => {
    assert.deepEqual((await run([], { subject: { summary: summary(2, 2), subs: [issue(9691, "closed"), issue(9692, "closed")] } })).outputs, RUN);
    // A close as not planned may not count as completed, so the list decides.
    const notPlanned = [issue(9691, "closed"), issue(9692, "closed", { reason: "not_planned" })];
    assert.deepEqual((await run([], { subject: { summary: summary(2, 1), subs: notPlanned } })).outputs, RUN);
  });

  test("costs no call past the issue read when the summary shows none open", async () => {
    for (const subject of [{ summary: summary(0, 0) }, { summary: summary(4, 4) }]) {
      const { calls, outputs } = await run([], { subject });
      assert.deepEqual(outputs, RUN, JSON.stringify(subject));
      assert.ok(!calls.some((call) => call.includes("/sub_issues")), JSON.stringify(subject));
    }
  });

  test("an issue read with no summary lists the sub-issues, and an open one skips the run", async () => {
    const { calls, outputs } = await run([], { subject: { subs: [issue(9691, "open")] } });
    assert.deepEqual(outputs, SKIP);
    assert.ok(calls.some((call) => call.includes("/sub_issues")));
    assert.deepEqual((await run([], { subject: { subs: [] } })).outputs, RUN);
  });

  test("a sub-issue list it cannot read skips the run with a warning, not for good", async () => {
    const { code, lines, outputs } = await run((path) => {
      if (path.includes("/sub_issues")) {
        throw new Error("GET failed: 502");
      }
      if (path === "/repos/o/r/issues/42") {
        return { number: 42, state: "open", user: HUMAN, labels: [], sub_issues_summary: summary(2, 0) };
      }
      return [];
    });
    assert.equal(code, 0);
    assert.deepEqual(outputs, SKIP);
    assert.ok(lines.some((line) => line.startsWith("::warning")));
  });
});
