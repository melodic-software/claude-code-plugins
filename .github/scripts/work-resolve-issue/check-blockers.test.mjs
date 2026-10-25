import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { main } from "./check-blockers.mjs";

const HUMAN = { id: 101, login: "person" };
const STRANGER = { id: 202, login: "stranger" };
const APP = { id: 303, login: "melodic-automation-lanes[bot]" };
const UNTRUSTED = "work-class: untrusted-provenance";
const dir = mkdtempSync(join(tmpdir(), "check-blockers-"));
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
      return { number: 42, state: "open", labels: (subject.labels ?? []).map((name) => ({ name })) };
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
      return { data: { repository: { issue: { timelineItems: { nodes: [{ closer: null }] } } } } };
    }
    throw new Error(`unexpected ${method} ${path} ${JSON.stringify(body)}`);
  };
  const code = await main({ env, github, log: (line) => lines.push(line), write: (values) => Object.assign(outputs, values) });
  return { code, calls, lines, outputs };
}

const SKIP = { proceed: "false", untrusted: "false" };
const RUN = { proceed: "true", untrusted: "false" };
const FINAL = { proceed: "false", untrusted: "true" };

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
    return path.includes("/events") ? [] : { number: 42, labels: [] };
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
