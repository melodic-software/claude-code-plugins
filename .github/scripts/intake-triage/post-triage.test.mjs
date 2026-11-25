// test-scope: plugins/work-items/skills/triage/scripts/check-ci-verdict.mjs plugins/work-items/skills/triage/schemas/ci-verdict.schema.json
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { verdictLines } from "../../../plugins/work-items/skills/triage/scripts/check-ci-verdict.mjs";
import { MARKER as APPLY_MARKER, parseVerdict } from "./apply-verdict.mjs";
import { CREDENTIAL, DEFERRED, ESCALATED_NOTE, laneBody, main, MARKER, plan, readDenials } from "./post-triage.mjs";

const dir = mkdtempSync(join(tmpdir(), "post-triage-"));
after(() => rmSync(dir, { recursive: true, force: true }));
let files = 0;
const file = (content) => {
  const path = join(dir, `f${(files += 1)}`);
  writeFileSync(path, typeof content === "string" ? content : JSON.stringify(content));
  return path;
};

const verdict = (overrides = {}) => {
  const base = { labels: ["priority: medium"], needs_human: false, size: "small", complexity: "low", uncertainty: "known", flags: [], blocked_by: [], type: "Task", ...overrides };
  return { ...base, comment: overrides.comment ?? [...verdictLines(base), "Blast radius: one file.", "Reversible: yes; revert."].join("\n") };
};

const REPO = "/repos/o/r";
function fakeGitHub({ labels = ["priority: medium", "priority: high", "needs-human", "needs-triage", "duplicate"], issueLabels = [], type = null, comments = [], fieldValue = "" } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET" && path === `${REPO}/issues/7`) return { number: 7, node_id: "I_7", labels: issueLabels.map((name) => ({ name })), type };
    if (method === "GET" && path.startsWith(`${REPO}/labels?`)) return labels.map((name) => ({ name }));
    if (method === "GET" && path.startsWith(`${REPO}/labels/`)) return { name: decodeURIComponent(path.split("/").pop()) };
    if (method === "GET" && path.startsWith(`${REPO}/issues/7/comments`)) return comments;
    if (method === "GET" && path.startsWith(`${REPO}/issues/7/issue-field-values`)) return fieldValue ? [{ issue_field_id: 49622037, single_select_option: { name: fieldValue } }] : [];
    if (method === "POST" && path === `${REPO}/issues/7/issue-field-values`) return [{ issue_field_id: 49622037, single_select_option: { name: body.issue_field_values[0].value } }];
    if (method === "POST" && path === "/graphql" && body.query.includes("issueTypes")) return { data: { repository: { issueTypes: { nodes: [{ id: "T1", name: "Task", isEnabled: true }, { id: "T2", name: "Bug", isEnabled: true }] } } } };
    if (method === "POST" && path === "/graphql" && body.query.includes("updateIssue")) return { data: { updateIssue: { issue: { issueType: { name: "Task" } } } } };
    if (method === "POST" || method === "PATCH" || method === "DELETE") return {};
    throw new Error(`unexpected ${method} ${path}`);
  };
  github.calls = calls;
  return github;
}

const run = async ({ v = verdict(), turns = { denied_total: 0 }, github = fakeGitHub(), env = {} } = {}) => {
  const output = file("");
  const lines = [];
  const code = await main({
    env: {
      GITHUB_REPOSITORY: "o/r",
      ISSUE_NUMBER: "7",
      VERDICT_FILE: file(v),
      ACT_TURNS_FILE: turns === null ? join(dir, "missing") : file(turns),
      ALLOWED_LABELS: "priority: critical\npriority: high\npriority: medium\npriority: low\nneeds-human\nduplicate\nagent-ready",
      ESCALATION_LABEL: "needs-human",
      FLOOR_LABEL: "needs-triage",
      PRIORITY_FIELD_ID: "49622037",
      AUTHOR_IDS: "153232337",
      GITHUB_OUTPUT: output,
      ...env,
    },
    github,
    log: (line) => lines.push(line),
  });
  return { code, lines, calls: github.calls, output: readFileSync(output, "utf8") };
};
const writes = (calls) => calls.filter((c) => c.method !== "GET" && !(c.method === "POST" && c.path === "/graphql" && !c.body.query.includes("updateIssue")));

describe("post-triage", () => {
  test("the lane marker is apply-verdict's, and a posted comment parses there", () => {
    assert.equal(MARKER, APPLY_MARKER);
    const dims = { fields: { size: { options: { 1: "small" } }, complexity: { options: { 2: "low" } }, uncertainty: { options: { 3: "known" } } } };
    const v = verdict();
    const parsed = parseVerdict(laneBody(v.comment), dims, JSON.stringify({ size: v.size, complexity: v.complexity, uncertainty: v.uncertainty, flags: v.flags, blocked_by: v.blocked_by }));
    assert.deepEqual(parsed.problems, []);
  });

  test("a clean verdict posts the comment, writes the priority field, sets the type, clears the floor and outputs the typed fields", async () => {
    const { code, calls, output } = await run();
    assert.equal(code, 0);
    const posted = calls.find((c) => c.method === "POST" && c.path === `${REPO}/issues/7/comments`);
    assert.ok(posted.body.body.startsWith(`${MARKER}\n\nSize: small`));
    assert.ok(calls.some((c) => c.method === "POST" && c.path === `${REPO}/issues/7/issue-field-values`));
    assert.ok(calls.some((c) => c.path === "/graphql" && c.body.query.includes("updateIssue") && c.body.variables.type === "T1"));
    assert.ok(calls.some((c) => c.method === "DELETE" && c.path === `${REPO}/issues/7/labels/needs-triage`));
    assert.equal(output, `verdict=${JSON.stringify({ size: "small", complexity: "low", uncertainty: "known", flags: [], blocked_by: [] })}\n`);
  });

  test("a rerun edits the lane's earlier comment", async () => {
    const github = fakeGitHub({ comments: [{ id: 55, user: { login: "github-actions[bot]" }, body: `${MARKER}\n\nold` }] });
    const { calls } = await run({ github });
    assert.ok(calls.some((c) => c.method === "PATCH" && c.path === `${REPO}/issues/comments/55`));
    assert.ok(!calls.some((c) => c.method === "POST" && c.path === `${REPO}/issues/7/comments`));
  });

  test("needs_human escalates: only the escalation label and the fixed note, the type kept, no verdict output", async () => {
    const { code, calls, output } = await run({ v: verdict({ needs_human: true }) });
    assert.equal(code, 0);
    const posted = calls.find((c) => c.method === "POST" && c.path === `${REPO}/issues/7/comments`);
    assert.equal(posted.body.body, laneBody(ESCALATED_NOTE));
    assert.deepEqual(calls.find((c) => c.method === "POST" && c.path === `${REPO}/issues/7/labels`).body, { labels: ["needs-human"] });
    assert.ok(calls.some((c) => c.path === "/graphql" && c.body.query.includes("updateIssue")));
    assert.equal(output, "");
  });

  test("a label outside the allowlist, or an admission label, is dropped", () => {
    const allowed = new Set(["priority: medium"]);
    const result = plan({ verdict: verdict({ labels: ["priority: medium", "agent-ready", "work-class: code"] }), allowed, escalationLabel: "needs-human" });
    assert.deepEqual([...result.labels], ["priority: medium"]);
    assert.deepEqual(result.rejected, ["agent-ready", "work-class: code"]);
  });

  test("a credential-shaped comment escalates and @mentions are broken", () => {
    const allowed = new Set();
    const token = `gh${"p"}_${"a".repeat(30)}`;
    assert.ok(CREDENTIAL.test(token));
    const leaky = verdict();
    assert.equal(plan({ verdict: { ...leaky, comment: `${leaky.comment}\n${token}` }, allowed, escalationLabel: "needs-human" }).escalated, true);
    assert.match(plan({ verdict: { ...leaky, comment: `${leaky.comment}\ncc @someone` }, allowed, escalationLabel: "needs-human" }).comment, /@​someone/u);
  });

  test("a permission denial applies nothing and defers; an unreadable count escalates", async () => {
    const denied = await run({ turns: { denied_total: 2 } });
    assert.equal(denied.code, 0);
    assert.deepEqual(writes(denied.calls), []);
    assert.equal(denied.output, "deferred=true\n");
    assert.ok(denied.lines.some((line) => line.includes(DEFERRED)));
    const unknown = await run({ turns: null });
    assert.deepEqual(unknown.calls.find((c) => c.method === "POST" && c.path === `${REPO}/issues/7/labels`).body, { labels: ["needs-human"] });
    assert.equal(unknown.output, "");
    assert.ok(Number.isNaN(readDenials(join(dir, "missing"))));
  });

  test("a verdict check-ci-verdict refuses applies nothing and fails", async () => {
    const bad = verdict();
    const { code, calls, lines } = await run({ v: { ...bad, comment: bad.comment.replace("Size: small", "Size: large") } });
    assert.equal(code, 1);
    assert.deepEqual(calls, []);
    assert.ok(lines.some((line) => line.includes("fails check-ci-verdict")));
  });

  test("a priority a listed person set stands over the pick", async () => {
    const github = fakeGitHub({ fieldValue: "high" });
    const base = github;
    const withHistory = async (method, path, body) => {
      if (path === "/graphql" && body.query.includes("timelineItems")) {
        return { data: { repository: { issue: { timelineItems: { nodes: [{ actor: { __typename: "User", databaseId: 153232337 }, issueField: { fullDatabaseId: "49622037" } }] } } } } };
      }
      return base(method, path, body);
    };
    withHistory.calls = base.calls;
    const { calls } = await run({ github: withHistory });
    assert.ok(!calls.some((c) => c.method === "POST" && c.path === `${REPO}/issues/7/issue-field-values`));
  });

  test("an issue that already has a type keeps it", async () => {
    const { calls } = await run({ github: fakeGitHub({ type: { name: "Bug" } }) });
    assert.ok(!calls.some((c) => c.path === "/graphql" && c.body.query.includes("updateIssue")));
  });

  test("a type the repository does not enable is not set, and the floor stays", async () => {
    const { calls } = await run({ v: verdict({ type: "Epic" }) });
    assert.ok(!calls.some((c) => c.path === "/graphql" && c.body.query.includes("updateIssue")));
    assert.ok(calls.some((c) => c.method === "POST" && c.path === `${REPO}/issues/7/labels` && c.body.labels[0] === "needs-triage"));
  });

  test("a malformed issue number writes nothing", async () => {
    const { code, calls } = await run({ env: { ISSUE_NUMBER: "7; rm" } });
    assert.equal(code, 1);
    assert.deepEqual(calls, []);
  });
});
