// Expected values come from the requested behavior: a status-label change on an issue
// mirrors the state the issue's labels collapse to into its Work status
// field; a pull request or a non-status label writes nothing; a field that
// already holds the state, set by a trusted account, is not written again;
// the hourly sweep counts what it wrote, left and failed.
import assert from "node:assert/strict";
import { test } from "node:test";

import { isStatusLabel, mirrorIssue, onLabelEvent, sweep } from "./sync-status.mjs";

const REPO = "o/r";
const FIELD = 7;
// A two-state stand-in for models.issue-status: agent-ready outranks the
// needs-triage floor.
const CONFIG = {
  "field-id": FIELD,
  options: { 101: "agent-ready", 102: "needs-triage" },
  labels: { "agent-ready": ["agent-ready"], "needs-triage": ["needs-triage"] },
  order: ["agent-ready", "needs-triage"],
};
const TRUSTED_ID = 1;
const UNTRUSTED_ID = 2;
const fold = (label) => String(typeof label === "string" ? label : label.name).toLowerCase();
// collapseStatus, issueStatus and writeStatus as issue-status.mjs and
// write-status.mjs define them, over CONFIG; a setter counts only when it is
// TRUSTED_ID.
const statusFor = ({ writes, fail = false }) => ({
  collapseStatus: (labels, config) =>
    config.order.find((state) => config.labels[state].some((name) => labels.map(fold).includes(name))) ?? config.order.at(-1),
  issueStatus: (facts, config) => {
    const row = facts.fieldValues.find((value) => value.field === config["field-id"]);
    return row && facts.fieldSetters[String(config["field-id"])] === TRUSTED_ID ? config.options[row.option] : null;
  },
  fieldSetters: async (github, repository, number) => github("SETTERS", number),
  writeStatus: async ({ number, labels }) => {
    writes.push([number, labels.map(fold)]);
    return fail ? { outcome: "failed" } : { outcome: "written" };
  },
});

// Issues by number: { labels, field (option id or null), setter, pr }.
function fakeGitHub(issues) {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (method === "SETTERS") return { [String(FIELD)]: issues[path].setter ?? null };
    let m;
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\/(\d+)$/.exec(path))) {
      const issue = issues[m[1]];
      return { number: Number(m[1]), labels: issue.labels.map((name) => ({ name })), ...(issue.pr ? { pull_request: {} } : {}) };
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\/(\d+)\/issue-field-values$/.exec(path))) {
      const { field } = issues[m[1]];
      if (field === "broken") throw new Error("GET field values answered 500");
      return field ? [{ issue_field_id: FIELD, single_select_option: { id: field } }] : [];
    }
    if (method === "GET" && /^\/repos\/o\/r\/issues\?state=open/.test(path)) {
      return Object.entries(issues).map(([number, issue]) => ({ number: Number(number), labels: issue.labels.map((name) => ({ name })), ...(issue.pr ? { pull_request: {} } : {}) }));
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

const args = (github, writes, extra = {}) => ({ github, repository: REPO, config: CONFIG, trustedActors: {}, status: statusFor({ writes, ...extra }), log: () => {} });
const labelEvent = (name, issue = { number: 5 }) => ({ action: "labeled", label: { name }, issue });

test("only models.issue-status labels count as status labels, without case", () => {
  assert.equal(isStatusLabel("Agent-Ready", CONFIG), true);
  assert.equal(isStatusLabel("priority: high", CONFIG), false);
  assert.equal(isStatusLabel(undefined, CONFIG), false);
});

test("a status-label event writes the state the issue's labels, read fresh, collapse to", async () => {
  // The payload names needs-triage; the fresh read finds agent-ready too.
  const { github, calls } = fakeGitHub({ 5: { labels: ["needs-triage", "agent-ready"], field: 102, setter: TRUSTED_ID } });
  const writes = [];
  const result = await onLabelEvent({ ...args(github, writes), event: labelEvent("needs-triage") });
  assert.equal(result.outcome, "written");
  assert.deepEqual(writes, [[5, ["needs-triage", "agent-ready"]]]);
  assert.ok(calls.includes("GET /repos/o/r/issues/5"));
});

test("a non-status label event and a pull request's label event exit with no read or write", async () => {
  for (const event of [labelEvent("priority: high"), labelEvent("agent-ready", { number: 5, pull_request: { url: "x" } })]) {
    const { github, calls } = fakeGitHub({ 5: { labels: ["agent-ready"], field: null } });
    const writes = [];
    assert.equal((await onLabelEvent({ ...args(github, writes), event })).outcome, "skipped");
    assert.deepEqual(writes, []);
    assert.deepEqual(calls, []);
  }
});

test("a pull request that the fresh read shows is skipped with no field read", async () => {
  const { github, calls } = fakeGitHub({ 5: { labels: ["agent-ready"], field: null, pr: true } });
  const writes = [];
  assert.equal((await mirrorIssue({ ...args(github, writes), number: 5 })).outcome, "skipped");
  assert.deepEqual(writes, []);
  assert.deepEqual(calls, ["GET /repos/o/r/issues/5"]);
});

test("a stale or unset field is written; one a trusted account set to the state is left", async () => {
  const cases = [
    [{ labels: ["agent-ready"], field: 102, setter: TRUSTED_ID }, "written"],
    [{ labels: ["agent-ready"], field: null }, "written"],
    [{ labels: ["agent-ready"], field: 101, setter: TRUSTED_ID }, "unchanged"],
    // The reader ignores a value an untrusted account set, so it is written again.
    [{ labels: ["agent-ready"], field: 101, setter: UNTRUSTED_ID }, "written"],
  ];
  for (const [issue, outcome] of cases) {
    const { github } = fakeGitHub({ 5: issue });
    const writes = [];
    assert.equal((await mirrorIssue({ ...args(github, writes), number: 5 })).outcome, outcome, JSON.stringify(issue));
    assert.equal(writes.length, outcome === "written" ? 1 : 0, JSON.stringify(issue));
  }
});

test("the sweep mirrors every open issue but pull requests, and counts wrote, unchanged and failed", async () => {
  const { github } = fakeGitHub({
    1: { labels: ["agent-ready"], field: 102, setter: TRUSTED_ID },
    2: { labels: ["needs-triage"], field: 102, setter: TRUSTED_ID },
    3: { labels: [], field: "broken" },
    4: { labels: ["agent-ready"], field: null, pr: true },
  });
  const writes = [];
  const lines = [];
  const result = await sweep({ ...args(github, writes), pause: async () => {}, log: (line) => lines.push(line) });
  assert.deepEqual([result.swept, result.wrote, result.unchanged, result.failed], [3, 1, 1, 1]);
  assert.deepEqual(writes, [[1, ["agent-ready"]]]);
  assert.ok(lines.includes("swept 3: wrote 1, unchanged 1, failed 1 (6 calls)"), lines.join("\n"));
});

test("a failed field write counts as failed, and the sweep stops at its call budget", async () => {
  const issues = { 1: { labels: ["agent-ready"], field: null }, 2: { labels: ["agent-ready"], field: null } };
  const failing = fakeGitHub(issues);
  const writes = [];
  const failed = await sweep({ ...args(failing.github, writes, { fail: true }), pause: async () => {} });
  assert.deepEqual([failed.wrote, failed.failed], [0, 2]);

  // One list call and two per issue: a budget of 4 reads the first issue only.
  const capped = fakeGitHub(issues);
  const lines = [];
  const result = await sweep({ ...args(capped.github, []), budget: 4, pause: async () => {}, log: (line) => lines.push(line) });
  assert.equal(result.swept, 1);
  assert.match(lines.at(-1), /^swept 1: wrote 1, unchanged 0, failed 0; stopped at #2: call budget of 4 spent/);
});
