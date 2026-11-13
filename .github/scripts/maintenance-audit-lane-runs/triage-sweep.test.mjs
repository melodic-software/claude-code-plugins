// The hourly triage sweep's rules, from the owner-approved design: an open
// issue qualifies when it is not a pull request, is over an hour old, its
// author is one the intake lane admits on open, and it has no `status:` label
// and no agent-ready, needs-human or needs-spec (the needs-triage floor label
// is not one), whatever comments intake left (owner 2026-10-24, rows S2 and
// S3); or it was born triaged in `status: ready` with nothing admitting it
// and nothing holding it (row S1). Each pass dispatches at most 5, and
// after 2 dispatches that reached intake and left the issue untriaged (or 6
// dispatches whatever reached intake) the sweep labels it
// needs-triage, says so in its comment on the issue, and stops dispatching it.
// Owner rule 2026-10-24: no new issues; comment on the original instead.
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { readRouting } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { ADMIT_MARKER, retriageNote } from "../intake-triage/admit.mjs";
import { HUMAN_ID, mirroredStatusOf, OPTION, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../../actions/resolve-config/read-status.fixtures.mjs";
import { statusReader } from "../../actions/resolve-config/read-status.mjs";
import { issuesByStatus } from "../../actions/resolve-config/resolve-config.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

import {
  decide,
  FILING,
  HANDED,
  handedInComments,
  MAX_DISPATCHES,
  reachedIntake,
  readState,
  renderState,
  RUN_LIMIT,
  runSweep,
  selectCandidates,
  statusListing,
} from "./triage-sweep.mjs";

const ROOT = new URL("../../..", import.meta.url).pathname;
const FIELD = STATUS_CONFIG["field-id"];

const NOW = new Date("2026-10-18T12:00:00Z");
const BOT = { login: "github-actions[bot]", id: 41898282 };
const HUMAN = 153232337;
const OUTSIDER = 555;

const issue = (number, over = {}) => ({
  number,
  user: { id: HUMAN },
  labels: [],
  body: "a report",
  created_at: "2026-10-18T09:00:00Z",
  ...over,
});

const APP = 337595936;
const authors = new Set([String(HUMAN), String(APP)]);

// The needs-triage floor label lands on open whether or not intake runs, so
// it does not mark an issue triaged. Priority and work-class labels are no
// verdict either: only a status label, agent-ready or a person's hold is.
test("a candidate has no status label, agent-ready or hold, is no PR, over an hour old, by an admitted author", () => {
  const issues = [
    issue(1),
    issue(2, { labels: [{ name: "needs-triage" }] }),
    issue(3, { labels: [{ name: "needs-reporter-info" }] }),
    issue(4, { labels: [{ name: "agent-ready" }] }),
    issue(5, { labels: [{ name: "needs-human" }] }),
    issue(6, { labels: [{ name: "priority: low" }] }),
    issue(7, { labels: [{ name: "work-class: scoped" }] }),
    issue(8, { labels: [{ name: "needs-spec" }] }),
    issue(9, { pull_request: { url: "x" } }),
    issue(10, { body: "text\n<!-- work-items:born-triaged -->\n" }),
    issue(11, { created_at: "2026-10-18T11:30:00Z" }),
    issue(12, { user: { id: OUTSIDER } }),
    issue(13, { labels: [{ name: "question" }, { name: "dependencies" }] }),
    issue(14, { user: { id: APP }, created_at: "2026-10-01T00:00:00Z" }),
    issue(15, { user: { id: BOT.id } }),
    issue(16, { labels: [{ name: "status: ready" }] }),
  ];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [14, 1, 2, 6, 7, 10, 13],
  );
});

// /work-items:decompose publishes an issue already triaged, so intake never
// ran admission on it: one in status: ready with nothing admitting or holding
// it, and no open blocker (work-unblock labels those when the blocker closes),
// is dispatched so intake's admission takes it.
test("a born-triaged issue in status: ready with no agent-ready, deferral, hold or open blocker is a candidate", () => {
  const born = (number, labels = [], over = {}) =>
    issue(number, { body: "Fix it.\n\n<!-- work-items:born-triaged -->", labels: [{ name: "status: ready" }, ...labels.map((name) => ({ name }))], ...over });
  const issues = [
    born(1),
    born(2, ["agent-ready"]),
    born(3, ["admission-deferred"]),
    born(4, ["needs-human"]),
    born(5, ["provenance: untrusted"]),
    born(6, [], { issue_dependencies_summary: { blocked_by: 1, total_blocked_by: 1, blocking: 0, total_blocking: 0 } }),
    born(7, [], { issue_dependencies_summary: { blocked_by: 0, total_blocked_by: 1, blocking: 0, total_blocking: 0 } }),
    born(8, ["priority: high"]),
    issue(9, { labels: [{ name: "status: ready" }] }),
    born(10, [], { user: { id: OUTSIDER } }),
    // A quoted marker mid-body is not the publisher's last line.
    born(11, [], { body: "<!-- work-items:born-triaged -->\nmore text" }),
    born(12, ["provenance: untrusted"]),
    // #14801: a tracker whose sub-issues are open waits in admission.
    born(13, [], { sub_issues_summary: { total: 3, completed: 1, percent_completed: 33 } }),
    born(14, [], { sub_issues_summary: { total: 2, completed: 2, percent_completed: 100 } }),
  ];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [1, 7, 8, 14],
  );
});

// /planning:wayfind and /work-items:decompose route an issue with a routing
// label (the binding's container label, default `spec-container`, or a label
// starting with its wayfind prefix, default `wayfind:`); intake skips it, so
// a dispatch would only count toward a needless hand-off.
test("an issue whose own labels hold a routing label is no candidate, as the binding names it", () => {
  const issues = [
    issue(1, { labels: [{ name: "wayfind: design" }] }),
    issue(2, { labels: [{ name: "spec-container" }] }),
    issue(3, { labels: [{ name: "epic" }] }),
    issue(4, { labels: [{ name: "fog: storage" }] }),
    issue(5),
  ];
  const select = (routing) => selectCandidates({ issues, now: NOW, authorIds: authors, routing }).map((i) => i.number);
  assert.deepEqual(select(undefined), [3, 4, 5], "the default labels");
  const dir = tempDir("triage-sweep-routing-");
  const binding = join(dir, "work-items.yaml");
  writeFileSync(binding, "tracker:\n  config:\n    container_label: epic\n    wayfind_label_prefix: 'fog:'\n");
  assert.deepEqual(select(readRouting(binding)), [1, 2, 5], "a remapped binding");
  assert.deepEqual(select(readRouting(join(dir, "absent.yaml"))), [3, 4, 5], "no binding file keeps the defaults");
});

test("the field never makes a routing-labeled issue a candidate", () => {
  const issues = [issue(1, { labels: [{ name: "wayfind: research" }] }), issue(2)];
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels: new Map([[1, []]]) }).map((i) => i.number), [2]);
});

// A GitHub whose Work status values live in `fields` (read-status.fixtures.mjs
// withFields' shape, setter defaulting to the listed human): a field POST sets
// one as github-actions[bot], the job token's account, and the open issues
// listing (resolve-config.mjs issuesByStatus) answers from them.
function fieldWorld(issues, fields = {}) {
  const field = { fullDatabaseId: String(FIELD) };
  const github = async (method, path, body) => {
    const posted = /\/issues\/([0-9]+)\/issue-field-values$/.exec(path);
    if (method === "POST" && posted) {
      const state = body.issue_field_values[0].value;
      fields[posted[1]] = { state, setter: BOT.id };
      return [{ issue_field_id: FIELD, single_select_option: { id: OPTION[state] } }];
    }
    if (method === "POST" && path === "/graphql" && /issues\(states: OPEN/.test(body.query)) {
      const nodes = issues.map((i) => {
        const entry = fields[i.number];
        return {
          number: i.number,
          createdAt: i.created_at,
          labels: { nodes: i.labels },
          issueFieldValues: { nodes: entry ? [{ name: entry.state, field }] : [] },
          timelineItems: { nodes: entry ? [{ __typename: "IssueFieldChangedEvent", newValue: entry.named ?? entry.state, actor: { databaseId: entry.setter ?? HUMAN_ID }, issueField: field }] : [] },
        };
      });
      return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return withFields(github, fields);
}
const listing = (issues, fields) =>
  statusListing({ github: fieldWorld(issues, fields), repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, issuesByStatus });

// The Work status field a trusted account set (read-status.mjs statusLabels):
// it decides the queue state, a hold label still holds, and unset, the labels decide.
const fieldSelect = async (issues, fields) =>
  selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels: await listing(issues, fields) }).map((i) => i.number);

test("a field that mirrors the labels chooses the same candidates", async () => {
  const born = (number, labels = [], over = {}) =>
    issue(number, { body: "Fix it.\n\n<!-- work-items:born-triaged -->", labels: [{ name: "status: ready" }, ...labels.map((name) => ({ name }))], ...over });
  const fixtures = [
    [issue(1), issue(2, { labels: [{ name: "needs-triage" }] }), issue(3, { labels: [{ name: "needs-reporter-info" }] }), issue(4, { labels: [{ name: "agent-ready" }] }), issue(5, { labels: [{ name: "needs-human" }] }), issue(6, { labels: [{ name: "priority: low" }] }), issue(8, { labels: [{ name: "needs-spec" }] }), issue(16, { labels: [{ name: "status: ready" }] }), issue(17, { labels: [{ name: "needs-owner-decision" }] }), issue(18, { labels: [{ name: "admission-deferred" }] })],
    [born(1), born(2, ["agent-ready"]), born(3, ["admission-deferred"]), born(4, ["needs-human"]), born(5, ["provenance: untrusted"]), born(8, ["priority: high"]), born(9, ["status: confirmed"])],
  ];
  for (const issues of fixtures) {
    const statusLabels = new Map();
    for (const i of issues) statusLabels.set(i.number, await mirroredStatusOf(i.number, i.labels.map((l) => l.name)));
    assert.deepEqual(
      selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels }).map((i) => i.number),
      selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    );
  }
});

test("the Work status field drops a candidate, adds one a stale label hid, and a hold label still holds", async () => {
  const born = { body: "Fix it.\n\n<!-- work-items:born-triaged -->", labels: [{ name: "status: ready" }] };
  const issues = [
    issue(1),
    issue(2),
    issue(3, born),
    issue(4, { labels: [{ name: "agent-ready" }] }),
    issue(5, { labels: [{ name: "status: confirmed" }] }),
    // Deferred on the field: its label set reads admission-deferred alone.
    issue(6, born),
    issue(7, { labels: [{ name: "needs-human" }] }),
  ];
  const fields = {
    1: { state: "ready" },
    2: { state: "needs-triage" },
    3: { state: "needs-human" },
    4: { state: "needs-triage" },
    5: { state: "needs-triage" },
    6: { state: "deferred" },
    7: { state: "needs-triage" },
  };
  // #4's agent-ready label is stale under a needs-triage field, so it is a candidate again.
  assert.deepEqual(await fieldSelect(issues, fields), [2, 4, 5]);
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number), [1, 2, 3, 6]);
});

// Plan case (b): flag.mjs writes needs-human with the job token.
test("a needs-human the job token writes to the field reads back and a later selection drops the issue", async () => {
  const issues = [issue(1)];
  const fields = {};
  const github = fieldWorld(issues, fields);
  assert.deepEqual(await fieldSelect(issues, fields), [1]);
  const { set } = await statusWriter({ env: { BASE_PATH: ROOT }, github, repository: "o/r" });
  await set(1, "needs-human");
  assert.deepEqual(fields[1], { state: "needs-human", setter: 41898282 });
  const names = await statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} })(1, []);
  assert.deepEqual(names, ["needs-human"]);
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels: new Map([[1, names]]) }), []);
  assert.deepEqual(await fieldSelect(issues, fields), []);
});

test("an issue the listing leaves out mid-write is not dispatched this pass, whatever its labels say", async () => {
  const issues = [issue(1), issue(2)];
  // #2's value and newest event disagree, in the listing and on its own read.
  const fields = { 1: { state: "needs-triage" }, 2: { state: "needs-triage", named: "ready" } };
  const noWait = (github, repository, states, options) => issuesByStatus(github, repository, states, { ...options, sleep: async () => {} });
  const original = console.log;
  console.log = () => {};
  let map;
  try {
    map = await statusListing({ github: fieldWorld(issues, fields), repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, issuesByStatus: noWait });
  } finally {
    console.log = original;
  }
  assert.deepEqual([...map.held], [2]);
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels: map }).map((i) => i.number), [1]);
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number), [1, 2], "by labels alone #2 would be dispatched");
});

test("with no models.issue-status the listing maps nothing and reads nothing", async () => {
  const map = await statusListing({ github: async () => assert.fail("read"), repository: "o/r", config: null, trustedActors: TRUSTED_ACTORS, issuesByStatus });
  assert.deepEqual(map, new Map());
});

// models.issue-status bot-setters: a hold the job token (github-actions[bot])
// set drops the issue; its agent-ready does not count, so its labels choose.
test("a hold github-actions[bot] set on the field drops the issue, and its agent-ready leaves the issue to its labels", async () => {
  const issues = [issue(1), issue(2)];
  const fields = { 1: { state: "needs-human", setter: BOT.id }, 2: { state: "agent-ready", setter: BOT.id } };
  assert.deepEqual(await fieldSelect(issues, fields), [2]);
});

// models.issue-status bot-setters: a hold the job token (github-actions[bot])
// set drops the issue; its agent-ready does not count, so its labels choose.
test("a hold github-actions[bot] set on the field drops the issue, and its agent-ready leaves the issue to its labels", async () => {
  const issues = [issue(1), issue(2)];
  const fields = { 1: { state: "needs-human", setter: BOT.id }, 2: { state: "agent-ready", setter: BOT.id } };
  assert.deepEqual(await fieldSelect(issues, fields), [2]);
});

test("an issue whose Work status field is unset, or set by another account, is chosen by its labels, the agent-ready label aside", async () => {
  const issues = [issue(1), issue(2, { labels: [{ name: "agent-ready" }] }), issue(3, { labels: [{ name: "needs-human" }] })];
  assert.deepEqual(await fieldSelect(issues, { 1: { state: "agent-ready", setter: STRANGER_ID } }), [1, 2]);
});

test("the agent-ready label with the Work status unset is no status: the listing drops it and the issue is dispatched", async () => {
  const issues = [issue(1, { labels: [{ name: "Agent-Ready" }, { name: "bug" }] }), issue(2, { labels: [{ name: "agent-ready" }] })];
  const map = await listing(issues, { 2: { state: "agent-ready" } });
  assert.deepEqual(map.get(1), ["bug"]);
  assert.deepEqual(map.get(2), ["agent-ready"]);
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors, statusLabels: map }).map((i) => i.number), [1]);
});

test("with no models.issue-status the agent-ready label alone still keeps an issue out", () => {
  const issues = [issue(1, { labels: [{ name: "agent-ready" }] }), issue(2)];
  assert.deepEqual(selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number), [2]);
});

test("the pass selects from the field listing: a field hold costs no read, a field floor under a stale label is dispatched", async () => {
  const reads = [];
  const gh = fakeGitHub({ issues: [issue(1), issue(2, { labels: [{ name: "status: confirmed" }] }), issue(3)] });
  const call = (method, path, body) => {
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const statusLabels = new Map([
    [1, ["needs-human"]],
    [2, ["needs-triage"]],
  ]);
  const result = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), statusLabels });
  assert.deepEqual(result.dispatched, [2, 3]);
  assert.ok(!reads.some((p) => p.startsWith("/repos/o/r/issues/1/")), reads.join("\n"));
});

test("the sweep state round-trips and is read only from the bot's comment", () => {
  const body = renderState({ runs: [11, 22], filed: null, runUrl: "https://github.com/o/r/actions/runs/22" });
  const comments = [
    { id: 1, user: { login: "someone", id: 9 }, body: renderState({ runs: [], filed: 5, runUrl: "u" }) },
    { id: 2, user: BOT, body },
  ];
  assert.deepEqual(readState(comments), { commentId: 2, runs: [11, 22], filed: null, reached: new Map() });
  assert.deepEqual(readState([{ id: 3, user: BOT, body: renderState({ runs: [11, 22], filed: 77, runUrl: "u" }) }]), {
    commentId: 3,
    runs: [11, 22],
    filed: 77,
    reached: new Map(),
  });
  assert.deepEqual(readState([]), { commentId: null, runs: [], filed: null, reached: new Map() });
  // Each run read records its mark; an unmarked id is unread.
  const marked = renderState({ runs: [11, 22, 33, 44], filed: null, runUrl: "u", reached: new Map([[11, "+"], [22, "-"], [44, "~"]]) });
  assert.ok(marked.startsWith("<!-- claude-lane triage-sweep runs=11+,22-,33,44~ filed= -->\n"));
  assert.deepEqual(readState([{ id: 7, user: BOT, body: marked }]), {
    commentId: 7,
    runs: [11, 22, 33, 44],
    filed: null,
    reached: new Map([[11, "+"], [22, "-"], [44, "~"]]),
  });
  assert.equal(readState([{ id: 4, user: BOT, body: renderState({ runs: [11, 22], filed: FILING }) }]).filed, FILING);
  assert.equal(readState([{ id: 6, user: BOT, body: renderState({ runs: [11, 22], filed: HANDED, repoUrl: "u" }) }]).filed, HANDED);
});

test("decide: dispatch first, wait on an unfinished run, dispatch again after one, hand off after two, stop once handed off", () => {
  const done = { status: "completed", conclusion: "failure" };
  assert.equal(decide({ state: { runs: [], filed: null }, latest: null }), "dispatch");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: { status: "in_progress" } }), "wait");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: { status: "queued" } }), "wait");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: done }), "dispatch");
  assert.equal(
    decide({ state: { runs: [1], filed: null }, latest: { status: "completed", conclusion: "success" } }),
    "dispatch",
  );
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: { status: "in_progress" } }), "wait");
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: done }), "hand");
  assert.equal(decide({ state: { runs: [1, 2], filed: HANDED }, latest: done }), "stop");
  assert.equal(decide({ state: { runs: [1, 2], filed: 9 }, latest: done }), "stop");
  assert.equal(decide({ state: { runs: [1, 2], filed: FILING }, latest: done }), "stop");
});

test("the hand-off comment names every dispatched run and asks a maintainer to triage the issue", () => {
  const body = renderState({
    runs: [11, 22],
    filed: HANDED,
    repoUrl: "https://github.com/o/r",
    details: [
      { id: 11, conclusion: "failure" },
      { id: 22, conclusion: "success" },
    ],
  });
  assert.ok(body.startsWith("<!-- claude-lane triage-sweep runs=11,22 filed=handed -->\n"));
  assert.ok(body.includes("after 2 dispatches"));
  assert.ok(body.includes("- https://github.com/o/r/actions/runs/11 (failure)"));
  assert.ok(body.includes("- https://github.com/o/r/actions/runs/22 (success)"));
  assert.ok(body.includes("Triage it by hand"));
});

// A fake GitHub holding issues, comments and runs, recording every write.
// `jobs` maps a run id to its job list; a run with none fails the jobs read.
function fakeGitHub({ issues, comments = {}, runs = {}, jobs = {}, annotations = {}, failPatch = () => false, filedIssues = [], handedIssues = [], graphqlError = false }) {
  const writes = [];
  let nextRun = 900;
  let nextIssue = 5000;
  let nextComment = 100;
  // The Work status write (statusWriter's set), recorded among the writes.
  const setStatus = async (number, state) => {
    writes.push({ method: "STATUS", path: `/repos/o/r/issues/${number}`, body: { state } });
  };
  const call = async (method, path, body) => {
    let m;
    if (method === "GET" && (m = /^\/search\/issues\?q=([^&]+)&per_page=100&page=(\d+)$/.exec(path))) {
      const found = {
        'repo:o/r is:issue author:app/github-actions in:title "Intake triage left"': filedIssues,
        'repo:o/r is:issue is:open commenter:app/github-actions in:comments "so the sweep no longer dispatches it"': handedIssues,
      }[decodeURIComponent(m[1])];
      assert.ok(found, decodeURIComponent(m[1]));
      return { incomplete_results: false, items: found.slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100) };
    }
    // The hand-off search: GitHub matches the phrase in any comment, so each
    // hit comes with its comments as GraphQL answers them.
    if (method === "POST" && path === "/graphql") {
      if (graphqlError) return { errors: [{ message: "Something went wrong" }] };
      assert.equal(body.variables.q, 'repo:o/r is:issue is:open commenter:app/github-actions in:comments "so the sweep no longer dispatches it"');
      const start = body.variables.after === null ? 0 : Number(body.variables.after);
      // GraphQL names an App's account `Bot`, drops the `[bot]` suffix and
      // gives its account id as databaseId.
      const author = (user) =>
        /\[bot\]$/.test(user?.login ?? "")
          ? { __typename: "Bot", login: user.login.replace(/\[bot\]$/, ""), databaseId: user.id }
          : { __typename: "User", login: user?.login };
      const nodes = handedIssues.slice(start, start + 50).map(({ number }) => ({
        number,
        comments: {
          nodes: (comments[number] ?? []).slice(0, 100).map((c) => ({ author: author(c.user), body: c.body, createdAt: c.created_at, updatedAt: c.updated_at })),
        },
      }));
      const next = start + 50 < handedIssues.length;
      return { data: { search: { pageInfo: { hasNextPage: next, endCursor: next ? String(start + 50) : null }, nodes } } };
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\?state=open&per_page=100&page=(\d+)$/.exec(path))) {
      return issues.slice((Number(m[1]) - 1) * 100, Number(m[1]) * 100);
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\/(\d+)\/comments\?per_page=100&page=(\d+)$/.exec(path))) {
      return (comments[m[1]] ?? []).slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100);
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/actions\/runs\/(\d+)$/.exec(path))) {
      return runs[m[1]] ?? null;
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/actions\/runs\/(\d+)\/jobs\?per_page=100$/.exec(path))) {
      if (!(m[1] in jobs)) throw new Error(`GET ${path}: HTTP 502`);
      return { total_count: jobs[m[1]].length, jobs: jobs[m[1]] };
    }
    // A check run with no annotations listed fails the read.
    if (method === "GET" && (m = /^\/repos\/o\/r\/check-runs\/(\d+)\/annotations\?per_page=100$/.exec(path))) {
      if (!(m[1] in annotations)) throw new Error(`GET ${path}: HTTP 502`);
      return annotations[m[1]];
    }
    writes.push({ method, path, body });
    // API version 2022-11-28 returns the run id only when return_run_details
    // is true, else 204, which `call` turns into null.
    if (method === "POST" && path === "/repos/o/r/actions/workflows/intake-triage.yml/dispatches") {
      if (body?.return_run_details !== true) return null;
      nextRun += 1;
      return { workflow_run_id: nextRun };
    }
    if (method === "POST" && path === "/repos/o/r/issues") return { number: (nextIssue += 1) };
    if (method === "PATCH" && failPatch(body)) throw new Error(`PATCH ${path}: HTTP 502`);
    if (method === "POST" || method === "PATCH") return { id: (nextComment += 1) };
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { call, writes, setStatus };
}

const sweep = (gh, statusLabels) =>
  runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), setStatus: gh.setStatus, statusLabels });

test("a pass dispatches at most 5 issues, oldest first, and records each run on the issue", async () => {
  // Listed newest first, as the issues API returns them.
  const issues = Array.from({ length: 7 }, (_, i) => issue(7 - i, { created_at: `2026-10-1${6 - i}T00:00:00Z` }));
  const gh = fakeGitHub({ issues });
  const result = await sweep(gh);
  assert.equal(MAX_DISPATCHES, 5);
  const dispatches = gh.writes.filter((w) => w.path.endsWith("/dispatches"));
  assert.deepEqual(
    dispatches.map((w) => w.body),
    [1, 2, 3, 4, 5].map((n) => ({ ref: "main", inputs: { "issue-number": String(n) }, return_run_details: true })),
  );
  const states = gh.writes.filter((w) => /\/issues\/\d+\/comments$/.test(w.path));
  assert.deepEqual(
    states.map((w) => [w.path, readState([{ id: 1, user: BOT, body: w.body.body }]).runs]),
    [1, 2, 3, 4, 5].map((n, i) => [`/repos/o/r/issues/${n}/comments`, [901 + i]]),
  );
  assert.deepEqual(result.dispatched, [1, 2, 3, 4, 5]);
});

// Row S3: an intake comment with no verdict label left the issue untriaged.
// Row S2: the lanes App opened the issue, so apply-verdict's --check refused
// the App as actor; a dispatch by this job's token passes it.
test("an issue with an intake comment but no status label is dispatched again, and so is one the lanes App opened", async () => {
  const gh = fakeGitHub({
    issues: [issue(1), issue(2, { user: { id: APP } })],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }] },
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1, 2]);
});

test("an issue with a status label is left alone, whatever its comments", async () => {
  const gh = fakeGitHub({
    issues: [issue(1, { labels: [{ name: "needs-owner-decision" }] })],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }] },
  });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.equal(result.candidates, 0);
});

test("a pass writes and dispatches nothing for a routing-labeled issue, as the pass's binding names it", async () => {
  const issues = [issue(1, { labels: [{ name: "wayfind: design" }] }), issue(2, { labels: [{ name: "spec-container" }] })];
  const gh = fakeGitHub({ issues });
  assert.equal((await sweep(gh)).candidates, 0);
  assert.deepEqual(gh.writes, []);
  const remapped = fakeGitHub({ issues });
  const result = await runSweep({ call: remapped.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, routing: { container: "epic", prefix: "fog:" } });
  assert.deepEqual(result.dispatched, [1, 2]);
});

test("a second dispatch edits the same state comment", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "failure" } },
  });
  await sweep(gh);
  assert.deepEqual(
    gh.writes.map((w) => [w.method, w.path]),
    [
      ["POST", "/repos/o/r/actions/workflows/intake-triage.yml/dispatches"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
    ],
  );
  assert.deepEqual(readState([{ id: 5, user: BOT, body: gh.writes[1].body.body }]).runs, [11, 901]);
});

test("after 2 untriaged dispatches the sweep sets its Work status and hands it off in its own comment, files no issue, and stops", async () => {
  const runs = {
    11: { status: "completed", conclusion: "failure" },
    22: { status: "completed", conclusion: "success" },
  };
  const first = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs,
  });
  const result = await sweep(first);
  assert.deepEqual(
    first.writes.map((w) => [w.method, w.path]),
    [
      ["STATUS", "/repos/o/r/issues/1"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
    ],
  );
  assert.deepEqual(first.writes[0].body, { state: "needs-triage" });
  const marked = first.writes[1].body.body;
  assert.equal(readState([{ id: 5, user: BOT, body: marked }]).filed, HANDED);
  assert.ok(marked.includes("- https://github.com/o/r/actions/runs/11 (failure)"));
  assert.deepEqual(result.handed, [1]);

  const second = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: marked }] },
    runs,
  });
  await sweep(second);
  assert.deepEqual(second.writes, []);
});

// The hand-off's field write lands, through the job token's writer, where the
// listing of the next pass reads it: the handed issue is skipped unread.
test("a hand-off at needs-triage on the field alone is skipped unread on the next pass", async () => {
  const issues = [issue(1)];
  const fields = {};
  const { set } = await statusWriter({ env: { BASE_PATH: ROOT }, github: fieldWorld(issues, fields), repository: "o/r" });
  const runs = { 11: { status: "completed", conclusion: "failure" }, 22: { status: "completed", conclusion: "success" } };
  const first = fakeGitHub({ issues, comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] }, runs });
  const result = await runSweep({ call: first.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), setStatus: set });
  assert.deepEqual(result.handed, [1]);
  assert.deepEqual(fields[1], { state: "needs-triage", setter: 41898282 });
  const marked = first.writes.at(-1).body.body;
  const second = fakeGitHub({ issues, comments: { 1: [{ id: 5, user: BOT, body: marked, created_at: "2026-10-18T10:00:00Z" }] }, runs, handedIssues: [{ number: 1 }] });
  const reads = [];
  const call = (method, path, body) => {
    if (method === "GET") reads.push(path);
    return second.call(method, path, body);
  };
  const next = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), statusLabels: await listing(issues, fields) });
  assert.equal(next.candidates, 0);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 0);
});

// A failed field write leaves no record, so the next pass hands the issue off again.
test("a hand-off whose field write fails writes no hand-off record", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "failure" }, 22: { status: "completed", conclusion: "success" } },
  });
  const setStatus = async () => {
    throw new Error("#1's Work status field was not set to `needs-triage`: HTTP 502");
  };
  const result = await runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), setStatus });
  assert.deepEqual(result.handed, []);
  assert.match(result.failed[0].error, /was not set/);
  assert.deepEqual(gh.writes, []);
});

test("a hand-off a person's late hold answers held writes no record and is not counted handed", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "failure" }, 22: { status: "completed", conclusion: "success" } },
  });
  const asked = [];
  const setStatus = async (number, state, options) => {
    asked.push([number, state, options]);
    return { outcome: "held", state: "needs-human" };
  };
  const result = await runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), setStatus });
  assert.deepEqual(asked, [[1, "needs-triage", { keepHold: true, from: [null, "needs-triage"] }]]);
  assert.deepEqual(result.handed, []);
  assert.deepEqual(result.held, [1]);
  assert.deepEqual(gh.writes, [], "no hand-off record");
});

// #14504: the listing read an agent-ready issue's field events stale, so the
// sweep took it for untriaged; intake left it as is, and the hand-off must not
// demote it. The hand-off's own field read decides, through the job's writer.
test("an agent-ready issue the listing read stale as needs-triage is left as is at hand-off, and a fresh needs-triage one is handed off", async () => {
  const runs = { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "success" } };
  const handOffPass = async (fields, listed = ["needs-triage"], extra = []) => {
    const issues = [issue(1, { body: "Fix it.\n\n<!-- work-items:born-triaged -->" })];
    const { set } = await statusWriter({ env: { BASE_PATH: ROOT }, github: fieldWorld(issues, fields), repository: "o/r" });
    const gh = fakeGitHub({ issues, comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }, ...extra] }, runs });
    const stale = new Map([[1, listed]]);
    const result = await runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP), setStatus: set, statusLabels: stale });
    return { result, writes: gh.writes };
  };
  // ready too: admission's wait and work-unblock write it after the listing.
  for (const state of ["agent-ready", "deferred", "confirmed", "ready"]) {
    const fields = { 1: { state, setter: APP } };
    const { result, writes } = await handOffPass(fields);
    assert.deepEqual(result.left, [1], state);
    assert.deepEqual(result.handed, [], state);
    assert.deepEqual(fields[1], { state, setter: APP }, `${state} is not demoted`);
    assert.deepEqual(writes, [], `${state}: no hand-off record`);
  }
  const fields = { 1: { state: "needs-triage", setter: APP } };
  const { result, writes } = await handOffPass(fields);
  assert.deepEqual(result.handed, [1]);
  assert.deepEqual(result.left, []);
  assert.equal(readState([{ id: 5, user: BOT, body: writes.at(-1).body.body }]).filed, HANDED);
  // A born-triaged issue the listing saw at status: ready, still ready, intake never admitted.
  const born = { 1: { state: "ready", setter: APP } };
  const handed = await handOffPass(born, ["status: ready"]);
  assert.deepEqual(handed.result.handed, [1]);
  assert.deepEqual(born[1].state, "needs-triage");
  // Listed at status: ready, admitted since after an old admission wait: still never demoted.
  const admitted = { 1: { state: "agent-ready", setter: APP } };
  const oldWait = { id: 6, user: { login: "melodic-automation-lanes[bot]", id: APP }, body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: sub-issue #9 is open.` };
  const late = await handOffPass(admitted, ["status: ready"], [oldWait]);
  assert.deepEqual(late.result.left, [1]);
  assert.deepEqual(late.result.handed, []);
  assert.deepEqual(admitted[1], { state: "agent-ready", setter: APP }, "agent-ready is not demoted");
  assert.deepEqual(late.writes, [], "no hand-off record");
});

test("a run still in progress holds the issue for a later pass", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "in_progress", conclusion: null } },
  });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.waiting, [1]);
});

// Job lists as the jobs API returns them: one where intake ran, one the kill
// switch stopped (run 41591527742: kill-switch succeeded, everything after it
// skipped), and one cancelled before intake.
const job = (name, conclusion) => ({ name, status: "completed", conclusion });
const RAN = [job("Kill Switch", "success"), job("Born Triaged", "success"), job("Intake Triage / claude-intake-triage", "success"), job("Intake Triage / claude-intake-triage-skipped", "skipped"), job("Apply Verdict", "success")];
const KILLED = [job("Born Triaged", "success"), job("Kill Switch", "success"), job("Intake Triage", "skipped"), job("Apply Verdict", "skipped")];
const CANCELLED = [job("Kill Switch", "success"), job("Born Triaged", "cancelled"), job("Intake Triage", "cancelled"), job("Apply Verdict", "skipped")];

test("reachedIntake: an intake job that ran counts; skipped, cancelled, unfinished or absent does not", () => {
  assert.equal(reachedIntake(RAN), true);
  assert.equal(reachedIntake([job("Intake Triage / claude-intake-triage", "failure")]), true);
  assert.equal(reachedIntake(KILLED), false);
  assert.equal(reachedIntake(CANCELLED), false);
  assert.equal(reachedIntake([{ name: "Intake Triage / claude-intake-triage", status: "in_progress", conclusion: null }]), false);
  assert.equal(reachedIntake([job("Kill Switch", "success"), job("Intake Triage Other", "success")]), false);
  assert.equal(reachedIntake([]), false);
});

test("reachedIntake reads a run from before the job rename by its job ids", () => {
  assert.equal(reachedIntake([job("kill-switch", "success"), job("intake-triage / claude-intake-triage", "success")]), true);
  assert.equal(reachedIntake([job("kill-switch", "success"), job("intake-triage", "skipped")]), false);
  assert.equal(reachedIntake([job("intake-triage-other", "success")]), false);
});

test("decide: only runs that reached intake count, and RUN_LIMIT dispatches hand off whatever reached it", () => {
  const done = { status: "completed", conclusion: "success" };
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: done, reached: 1 }), "dispatch");
  assert.equal(decide({ state: { runs: [1, 2, 3], filed: null }, latest: done, reached: 2 }), "hand");
  assert.equal(RUN_LIMIT, 6);
  assert.equal(decide({ state: { runs: [1, 2, 3, 4, 5], filed: null }, latest: done, reached: 0 }), "dispatch");
  assert.equal(decide({ state: { runs: [1, 2, 3, 4, 5, 6], filed: null }, latest: done, reached: 0 }), "hand");
});

const twoRuns = (jobs) =>
  fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "success" } },
    jobs,
  });

test("a run the kill switch skipped leaves an attempt: the sweep dispatches again and hands nothing off", async () => {
  const gh = twoRuns({ 11: RAN, 22: KILLED });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1]);
  assert.deepEqual(result.handed, []);
  assert.deepEqual(
    gh.writes.map((w) => [w.method, w.path]),
    [
      ["POST", "/repos/o/r/actions/workflows/intake-triage.yml/dispatches"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
    ],
  );
  assert.deepEqual(readState([{ id: 5, user: BOT, body: gh.writes[1].body.body }]).runs, [11, 22, 901]);
  assert.ok(gh.writes[1].body.body.startsWith("<!-- claude-lane triage-sweep runs=11+,22-,901 filed= -->"));
});

// Reading every run's jobs on every pass, before the dispatch cap demotes an
// issue to stop, cost 20 issues at 5 runs each about 140 calls, past the
// 120-call budget, so the newest issues starved. Each run's result is recorded
// once read, so a pass reads only the run that finished since. Every write
// records the runs read, so only the newest dispatch is unmarked; a state an
// older sweep wrote holds at most 2 runs, since it handed off at 2.
test("recorded runs are not read again: 20 issues at 5 killed runs fit one 120-call pass", async () => {
  const issues = Array.from({ length: 20 }, (_, i) => issue(i + 1));
  const ids = (n) => [1, 2, 3, 4, 5].map((k) => n * 10 + k);
  // As the sweep wrote it when it dispatched the fifth run: four read, one not.
  const recorded = (n) => new Map(ids(n).slice(0, 4).map((id) => [id, "-"]));
  const gh = fakeGitHub({
    issues,
    comments: Object.fromEntries(
      issues.map(({ number: n }) => [n, [{ id: n, user: BOT, body: renderState({ runs: ids(n), filed: null, runUrl: "u", reached: recorded(n) }) }]]),
    ),
    runs: Object.fromEntries(issues.flatMap(({ number: n }) => ids(n).map((id) => [id, { status: "completed", conclusion: "success" }]))),
    jobs: Object.fromEntries(issues.flatMap(({ number: n }) => ids(n).map((id) => [id, KILLED]))),
  });
  const reads = [];
  let left = 120;
  const call = async (method, path, body) => {
    if (left === 0) throw new Error("call budget of 120 reached");
    left -= 1;
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, remaining: () => left, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.equal(result.truncated, null);
  assert.deepEqual(result.dispatched, [1, 2, 3, 4, 5]);
  assert.ok(reads.includes("/repos/o/r/issues/20/comments?per_page=100&page=1"));
  const jobReads = reads.filter((p) => p.endsWith("/jobs?per_page=100"));
  assert.deepEqual(jobReads, issues.map(({ number: n }) => `/repos/o/r/actions/runs/${n * 10 + 5}/jobs?per_page=100`));
  // The capped issues record their fifth run, so the next pass reads no jobs.
  const capped = gh.writes.filter((w) => w.method === "PATCH" && Number(/comments\/(\d+)$/.exec(w.path)[1]) > 5);
  assert.equal(capped.length, 15);
  for (const w of capped) assert.deepEqual([...readState([{ id: 1, user: BOT, body: w.body.body }]).reached.values()], ["-", "-", "-", "-", "-"]);
  const next = fakeGitHub({
    issues: issues.slice(5),
    comments: Object.fromEntries(capped.map((w) => [Number(/comments\/(\d+)$/.exec(w.path)[1]), [{ id: 1, user: BOT, body: w.body.body }]])),
    runs: Object.fromEntries(issues.flatMap(({ number: n }) => ids(n).map((id) => [id, { status: "completed", conclusion: "success" }]))),
  });
  const again = [];
  await runSweep({
    call: (method, path, body) => (again.push(path), next.call(method, path, body)),
    repo: "o/r",
    serverUrl: "https://github.com",
    now: NOW,
    authorIds: authors,
    appId: String(APP),
  });
  assert.equal(again.filter((p) => p.endsWith("/jobs?per_page=100")).length, 0);
});

test("with the hand slots used up, an issue at RUN_LIMIT is not read: it could only stop", async () => {
  const issues = Array.from({ length: 6 }, (_, i) => issue(i + 1));
  const ids = (n) => Array.from({ length: RUN_LIMIT }, (_, k) => n * 10 + k);
  const gh = fakeGitHub({
    issues,
    comments: Object.fromEntries(issues.map(({ number: n }) => [n, [{ id: n, user: BOT, body: renderState({ runs: ids(n), filed: null, runUrl: "u" }) }]])),
    runs: Object.fromEntries(issues.flatMap(({ number: n }) => ids(n).map((id) => [id, { status: "completed", conclusion: "success" }]))),
    jobs: Object.fromEntries(issues.flatMap(({ number: n }) => ids(n).map((id) => [id, KILLED]))),
  });
  const reads = [];
  const result = await runSweep({
    call: (method, path, body) => (reads.push(path), gh.call(method, path, body)),
    repo: "o/r",
    serverUrl: "https://github.com",
    now: NOW,
    authorIds: authors,
    appId: String(APP),
  });
  assert.deepEqual(result.handed, [1, 2, 3, 4, 5]);
  assert.ok(reads.includes("/repos/o/r/issues/6/comments?per_page=100&page=1"));
  assert.ok(!reads.some((p) => p.startsWith("/repos/o/r/actions/runs/6") && p.endsWith("/jobs?per_page=100")));
  assert.ok(!gh.writes.some((w) => w.path.endsWith("/comments/6")));
});

test("two runs that reached intake still hand the issue off", async () => {
  const gh = twoRuns({ 11: RAN, 22: RAN });
  const result = await sweep(gh);
  assert.deepEqual(result.handed, [1]);
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(gh.writes[0].body, { state: "needs-triage" });
});

test("a run cancelled before intake does not count", async () => {
  const gh = twoRuns({ 11: CANCELLED, 22: RAN });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1]);
  assert.deepEqual(result.handed, []);
});

test("a failing jobs read counts the run, as before: two runs hand the issue off", async () => {
  const gh = twoRuns({});
  const result = await sweep(gh);
  assert.deepEqual(result.handed, [1]);
  assert.deepEqual(result.dispatched, []);
});

// Runs that reached a verdict and stopped for a reason a later run clears do
// not count: apply-verdict failed on a 500 (run 41814429466), it wrote the
// labels but missed edges and the status field on a 5xx (run 41814435576), or
// the reusable deferred an otherwise clean triage on a permission denial and
// apply-verdict skipped (run 41807993284). Annotations as the check-runs API
// returned them for those runs.
const cr = (id) => `https://api.github.com/repos/o/r/check-runs/${id}`;
const withUrl = (name, conclusion, id) => ({ ...job(name, conclusion), check_run_url: cr(id) });
const reachedWith = (...rest) => [job("Kill Switch", "success"), job("Intake Triage / claude-intake-triage", "success"), ...rest];
const note = (annotation_level, message) => ({ annotation_level, message });
const FAILED_500 = reachedWith(withUrl("Apply Verdict", "failure", 220));
const MISSED_502 = reachedWith(withUrl("Apply Verdict", "success", 220));
const DEFERRED = reachedWith(withUrl("Intake Triage / claude-intake-triage-apply", "success", 221), job("Apply Verdict", "skipped"));
const NOTES = {
  500: [note("notice", "api-calls lanes-app=6"), note("failure", "Process completed with exit code 1."), note("failure", "POST /repos/o/r/issues/1/issue-field-values failed with status 500")],
  502: [
    note("warning", "blocked-by edges not written: #2 not written (GitHub answered 500); the verdict's labels are written without status: ready"),
    note("warning", "#1's Work status field not written: POST /repos/o/r/issues/1/issue-field-values failed with status 502; its labels stand"),
  ],
  deferred: [note("notice", "api-calls github-token=3"), note("warning", "1 permission denial(s) on an otherwise clean triage: nothing applied, so a later triage run retries the issue.")],
};
const transientRuns = (jobs22, annotations) =>
  fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "failure" } },
    jobs: { 11: RAN, 22: jobs22 },
    annotations,
  });

for (const [shape, jobs22, annotations] of [
  ["apply-verdict failed on a 500", FAILED_500, { 220: NOTES[500] }],
  ["apply-verdict missed its writes on a 5xx", MISSED_502, { 220: NOTES[502] }],
  ["the triage deferred on a permission denial", DEFERRED, { 221: NOTES.deferred }],
  ["apply-verdict held green on a 503", MISSED_502, { 220: [note("notice", "api-calls lanes-app=6"), note("notice", "held: admission failed: GET /repos/o/r/issues/1 failed with status 503")] }],
]) {
  test(`a run where ${shape} does not count: the sweep dispatches again and marks it transient`, async () => {
    const gh = transientRuns(jobs22, annotations);
    const result = await sweep(gh);
    assert.deepEqual([result.dispatched, result.handed], [[1], []]);
    assert.ok(gh.writes[1].body.body.startsWith("<!-- claude-lane triage-sweep runs=11+,22~,901 filed= -->"));
  });
}

test("a run from before the job rename, its jobs named by id, is classified the same way", async () => {
  const old = (jobs) => jobs.map((j) => ({ ...j, name: j.name.replace("Kill Switch", "kill-switch").replace("Intake Triage", "intake-triage").replace("Apply Verdict", "apply-verdict") }));
  for (const [jobs22, annotations] of [
    [old(FAILED_500), { 220: NOTES[500] }],
    [old(DEFERRED), { 221: NOTES.deferred }],
  ]) {
    const result = await sweep(transientRuns(jobs22, annotations));
    assert.deepEqual([result.dispatched, result.handed], [[1], []], JSON.stringify(jobs22));
  }
});

test("a run whose apply failed for a reason a retry does not clear counts", async () => {
  for (const message of ["POST /repos/o/r/issues/1/labels failed with status 403", "admission failed: the rules file does not parse"]) {
    const gh = transientRuns(FAILED_500, { 220: [note("failure", "Process completed with exit code 1."), note("failure", message)] });
    const result = await sweep(gh);
    assert.deepEqual(result.handed, [1], message);
  }
  // A 5xx beside a failure of another kind counts too.
  const mixed = transientRuns(FAILED_500, { 220: [note("failure", "POST /x failed with status 500"), note("failure", "the reasons comment was not written: 403")] });
  assert.deepEqual((await sweep(mixed)).handed, [1]);
  // One edge annotation that joins a 500 and a 403 (apply-verdict's
  // missedAnnotation) counts: not every failure it reports is transient.
  const joined = transientRuns(MISSED_502, {
    220: [note("warning", "blocked-by edges not written: #2 not written (GitHub answered 500), #3 not written (GitHub answered 403); the verdict's labels are written without status: ready")],
  });
  assert.deepEqual((await sweep(joined)).handed, [1]);
  // A green hold on a 403 counts too.
  const held = transientRuns(MISSED_502, { 220: [note("notice", "held: POST /repos/o/r/issues/1/labels failed with status 403")] });
  assert.deepEqual((await sweep(held)).handed, [1]);
  // So does an apply-verdict that skipped with no deferral, or failed with no annotation.
  assert.deepEqual((await sweep(transientRuns(DEFERRED, { 221: [] }))).handed, [1]);
  assert.deepEqual((await sweep(transientRuns(FAILED_500, { 220: [] }))).handed, [1]);
});

test("a run whose outcome cannot be read counts: a failing annotations read, or no check run to read", async () => {
  const unread = transientRuns(FAILED_500, {});
  assert.deepEqual((await sweep(unread)).handed, [1]);
  const noUrl = transientRuns(reachedWith(job("Apply Verdict", "failure")), { 220: NOTES[500] });
  assert.deepEqual((await sweep(noUrl)).handed, [1]);
});

test("the first 24 transient runs do not count and the 25th does", async () => {
  const marked = (transient) => {
    const ids = Array.from({ length: transient + 1 }, (_, k) => 100 + k);
    const runs = `${ids.slice(0, -1).map((id) => `${id}~`).join(",")},${ids.at(-1)}+`;
    return fakeGitHub({
      issues: [issue(1)],
      comments: { 1: [{ id: 5, user: BOT, body: `<!-- claude-lane triage-sweep runs=${runs} filed= -->\nstate` }] },
      runs: Object.fromEntries(ids.map((id) => [id, { status: "completed", conclusion: "failure" }])),
    });
  };
  // 24 transient runs and one that counts: one attempt, so it dispatches.
  assert.deepEqual((await sweep(marked(24))).dispatched, [1]);
  // A 25th transient run counts: two attempts hand it off, without reading
  // the transient runs' conclusions.
  const gh = marked(25);
  const reads = [];
  const result = await runSweep({
    call: (method, path, body) => (method === "GET" && reads.push(path), gh.call(method, path, body)),
    repo: "o/r",
    serverUrl: "https://github.com",
    now: NOW,
    authorIds: authors,
    appId: String(APP),
  });
  assert.deepEqual(result.handed, [1]);
  assert.deepEqual(reads.filter((p) => /\/actions\/runs\/\d+$/.test(p)), ["/repos/o/r/actions/runs/125"]);
});

test("an older unmarked handed-off state is left as it is: no run or jobs read, no write", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane triage-sweep runs=11,22 filed=handed -->\nHanded off." }] },
    runs: { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "success" } },
    jobs: { 11: RAN, 22: RAN },
  });
  const reads = [];
  const call = (method, path, body) => {
    if (/\/actions\/runs\//.test(path)) reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.deepEqual(reads, []);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual([result.dispatched, result.handed], [[], []]);
});

test("after RUN_LIMIT dispatches that never reached intake the sweep hands the issue off and names why", async () => {
  const ids = [11, 22, 33, 44, 55, 66];
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: ids, filed: null, runUrl: "u" }) }] },
    runs: Object.fromEntries(ids.map((id) => [id, { status: "completed", conclusion: "success" }])),
    jobs: Object.fromEntries(ids.map((id) => [id, KILLED])),
  });
  const result = await sweep(gh);
  assert.deepEqual(result.handed, [1]);
  assert.ok(gh.writes[1].body.body.includes("- https://github.com/o/r/actions/runs/66 (success, intake did not run)"));
});

// A comment flood past the pages read would hide the state comment and force
// a dispatch every pass.
test("an issue with more comments than the sweep reads goes to a maintainer, undispatched", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1)], comments: { 1: flood } });
  const result = await sweep(gh);
  assert.deepEqual(
    gh.writes.map((w) => [w.method, w.path, w.body]),
    [["STATUS", "/repos/o/r/issues/1", { state: "needs-triage" }]],
  );
  assert.deepEqual(result.dispatched, []);
});

test("a pass stops dispatching when the budget left cannot record the run", async () => {
  const gh = fakeGitHub({ issues: [issue(1), issue(2, { created_at: "2026-10-18T09:30:00Z" })] });
  let left = 8;
  const call = async (...args) => {
    if (left === 0) throw new Error("call budget of 8 reached");
    left -= 1;
    return gh.call(...args);
  };
  // issues page 1, the two hand-off searches, comments of #1, dispatch, state
  // write: 6 calls; #2's comments leave 1, too few for a dispatch and its
  // state write.
  const result = await runSweep({
    call,
    remaining: () => left,
    repo: "o/r",
    serverUrl: "https://github.com",
    now: NOW,
    authorIds: authors,
  });
  assert.deepEqual(result.dispatched, [1]);
  assert.equal(gh.writes.filter((w) => w.path.endsWith("/dispatches")).length, 1);
  assert.match(result.truncated, /budget/);
});

test("a hand-off whose record write fails is retried on the next pass, and no pass files an issue", async () => {
  const comments = { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] };
  const runs = {
    11: { status: "completed", conclusion: "failure" },
    22: { status: "completed", conclusion: "failure" },
  };
  const failing = fakeGitHub({ issues: [issue(1)], comments, runs, failPatch: (body) => /filed=handed/.test(body.body) });
  const first = await sweep(failing);
  assert.equal(first.failed.length, 1);
  const retry = fakeGitHub({ issues: [issue(1)], comments, runs });
  const second = await sweep(retry);
  assert.deepEqual(second.handed, [1]);
  for (const gh of [failing, retry]) {
    assert.ok(!gh.writes.some((w) => w.method === "POST" && w.path === "/repos/o/r/issues"));
  }
});

test("issues the sweep already filed do not use up the per-pass check limit", async () => {
  const filed = Array.from({ length: 20 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const gh = fakeGitHub({
    issues: [...filed, issue(21, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(
      filed.map((i) => [i.number, [{ id: i.number, user: BOT, body: renderState({ runs: [1, 2], filed: 7000 + i.number }) }]]),
    ),
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [21]);
});

// Codex P2 on #9303: with needs-triage no longer excluding them, the issues
// an older sweep filed a hand-off issue for would spend the call budget on
// their comments every pass. One search for those hand-off issues skips them unread.
test("issues an older sweep filed a hand-off for are skipped without reading their comments", async () => {
  const handed = Array.from({ length: 118 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const filedIssues = [
    ...handed.map((i) => ({
      number: 6000 + i.number,
      title: `Intake triage left #${i.number} untriaged after 2 dispatches`,
      user: BOT,
    })),
    // The same title from anyone else excludes nothing.
    { number: 7000, title: "Intake triage left #119 untriaged after 2 dispatches", user: { login: "someone" } },
  ];
  const gh = fakeGitHub({
    issues: [...handed, issue(119, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(
      handed.map((i) => [i.number, [{ id: i.number, user: BOT, body: renderState({ runs: [1, 2], filed: 6000 + i.number }) }]]),
    ),
    filedIssues,
  });
  const reads = [];
  let left = 120;
  const call = async (method, path, body) => {
    if (left === 0) throw new Error("call budget of 120 reached");
    left -= 1;
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, remaining: () => left, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors });
  assert.deepEqual(result.dispatched, [119]);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 1);
});

// Review threads on #9814 (claude-review and Codex P2): work-unblock hands an
// issue back to intake after a Refs: merge or a closed lane PR, so a lifetime
// count of 2 dispatches would cut that flow off. The lanes App's hand-back
// comment, newer than the state comment's last edit, starts a new cycle.
const stateAt = (runs, filed, at) => ({
  id: 5,
  user: BOT,
  body: renderState({ runs, filed, runUrl: "u", repoUrl: "https://github.com/o/r" }),
  created_at: "2026-10-17T00:00:00Z",
  updated_at: at,
});
const handBack = (user, at) => ({ id: 6, user, body: "<!-- work-unblock handed triage #40 -->\nThe lanes App's pull request #40 merged with `Refs:`.", created_at: at });
const triaged = { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "success" } };
const LANES = { login: "melodic-automation-lanes[bot]", id: APP };

// The issue lane's intake route (a split-required skip, owner Q93) sends an
// issue back the same way, so its comment starts a new cycle too.
const intakeBack = (user, at) => ({ id: 7, user, body: "<!-- work-resolve-issue outcome=intake run=9 -->\nThe work-resolve-issue lane stopped on this issue (`split-required`).", created_at: at });
// A pushback that may name a security risk marks its intake comment `security`.
const securityBack = (user, at) => ({ id: 7, user, body: "<!-- work-resolve-issue outcome=intake security run=9 -->\nThe work-resolve-issue lane stopped on this issue (`pushback-means`).", created_at: at });

test("a lanes App hand-back newer than the state comment starts a new cycle of dispatches in the same comment", async () => {
  for (const [filed, back] of [[null, handBack], [HANDED, handBack], [null, intakeBack], [HANDED, intakeBack], [null, securityBack]]) {
    const gh = fakeGitHub({
      issues: [issue(1)],
      comments: { 1: [stateAt([11, 22], filed, "2026-10-17T06:00:00Z"), back(LANES, "2026-10-18T08:00:00Z")] },
      runs: triaged,
    });
    const result = await sweep(gh);
    assert.deepEqual(result.dispatched, [1], String(filed));
    assert.deepEqual(
      gh.writes.map((w) => [w.method, w.path]),
      [
        ["POST", "/repos/o/r/actions/workflows/intake-triage.yml/dispatches"],
        ["PATCH", "/repos/o/r/issues/comments/5"],
      ],
      String(filed),
    );
    assert.deepEqual(readState([{ id: 5, user: BOT, body: gh.writes[1].body.body }]), { commentId: 5, runs: [901], filed: null, reached: new Map() });
  }
});

test("a hand-back older than the state comment's last edit, or posted by anyone but the lanes App, keeps the count", async () => {
  for (const [name, back] of [
    ["older", handBack(LANES, "2026-10-17T05:00:00Z")],
    ["not the App", handBack({ login: "someone", id: OUTSIDER }, "2026-10-18T08:00:00Z")],
    ["a listed human", handBack({ login: "owner", id: HUMAN }, "2026-10-18T08:00:00Z")],
  ]) {
    const gh = fakeGitHub({ issues: [issue(1)], comments: { 1: [stateAt([11, 22], null, "2026-10-17T06:00:00Z"), back] }, runs: triaged });
    const result = await sweep(gh);
    assert.deepEqual(result.dispatched, [], name);
    assert.deepEqual(result.handed, [1], name);
  }
});

// Codex P2 on #9814: hand-offs now live only in a comment, so each handed
// issue would cost a comment read every pass and could use up the 120-call
// budget before a fresh issue behind them. One search for the hand-off text
// skips those still carrying needs-triage unread.
test("issues this sweep handed off in a comment are skipped without reading their comments", async () => {
  const handed = Array.from({ length: 118 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const marked = renderState({ runs: [1, 2], filed: HANDED, repoUrl: "https://github.com/o/r" });
  const gh = fakeGitHub({
    issues: [...handed, issue(119, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(handed.map((i) => [i.number, [{ id: i.number, user: BOT, body: marked }]])),
    handedIssues: handed.map((i) => ({ number: i.number })),
  });
  const reads = [];
  let left = 120;
  const call = async (method, path, body) => {
    if (left === 0) throw new Error("call budget of 120 reached");
    left -= 1;
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, remaining: () => left, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.deepEqual(result.dispatched, [119]);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 1);
});

test("a search hit without needs-triage is read, so a hand-back after its label came off starts a new cycle", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), handBack(LANES, "2026-10-18T08:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1]);
});

// Security review on #9814: the search matches the hand-off text in anyone's
// comment, so a hit is skipped only on the bot's own filed=handed state
// comment, with no newer hand-back. Each needs-triage hit below is read and
// dispatched; the control, the bot's own hand-off, is skipped unread.
test("a search hit whose hand-off text is not the bot's own hand-off is read and dispatched", async () => {
  const text = "Intake triage did not triage this issue after 2 dispatches, so the sweep no longer dispatches it.";
  const floor = [{ name: "needs-triage" }];
  for (const [name, notes] of [
    ["someone else's comment", [{ id: 7, user: { login: "someone", id: OUTSIDER }, body: text }]],
    ["a forged state comment", [{ id: 7, user: { login: "someone", id: OUTSIDER }, body: renderState({ runs: [1, 2], filed: HANDED, repoUrl: "u" }) }]],
    ["the bot's state still dispatching", [stateAt([11], null, "2026-10-17T06:00:00Z"), { id: 7, user: { login: "someone", id: OUTSIDER }, body: text }]],
  ]) {
    const gh = fakeGitHub({ issues: [issue(1, { labels: floor })], comments: { 1: notes }, runs: triaged, handedIssues: [{ number: 1 }] });
    const result = await sweep(gh);
    assert.deepEqual(result.dispatched, [1], name);
  }
  const own = fakeGitHub({
    issues: [issue(1, { labels: floor })],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
  });
  const reads = [];
  const call = (method, path, body) => {
    if (method === "GET") reads.push(path);
    return own.call(method, path, body);
  };
  const result = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.equal(result.candidates, 0);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 0);
  assert.deepEqual(own.writes, []);
});

// Review on #9814: work-unblock adds no needs-triage, so one left from an
// earlier hand-off can still be on an issue it hands back. The bot's own
// filed=handed state with a newer lanes App hand-back is read, and its new
// cycle dispatches.
test("a needs-triage search hit with the bot's hand-off and a newer lanes App hand-back is read and dispatched", async () => {
  const gh = fakeGitHub({
    issues: [issue(1, { labels: [{ name: "needs-triage" }] })],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), handBack(LANES, "2026-10-18T08:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1]);
});

// Security review on #10978: as readState counts only the lanes App's
// hand-back, so does the hand-off search, so another App's comment cannot make
// a handed-off issue cost a read every pass.
test("a needs-triage search hit with the bot's hand-off and a newer hand-back from any other App is skipped unread", async () => {
  const gh = fakeGitHub({
    issues: [issue(1, { labels: [{ name: "needs-triage" }] })],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), handBack({ login: "other-app[bot]", id: OUTSIDER }, "2026-10-18T08:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
  });
  const reads = [];
  const call = (method, path, body) => {
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.equal(result.candidates, 0);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 0);
  assert.deepEqual(gh.writes, []);
});

// Admission's re-triage over a blocker's report-delivered close (admit.mjs
// retriageNote) hands the issue back as work-unblock does, so a dependent
// that used both dispatches is judged again instead of handed to a
// maintainer. The admission comment is edited in place, so its last edit
// counts; any other admission comment hands nothing back.
const admissionAt = (user, text, at) => ({ id: 7, user, body: `${ADMIT_MARKER}\n${text}`, created_at: "2026-10-16T00:00:00Z", updated_at: at });
const retriage = retriageNote("blocker #5 was closed report-delivered", [{ number: 5, url: "u", reason: "the report" }]);

test("readState starts a new cycle on the lanes App's re-triage admission comment edited after the state", () => {
  const state = stateAt([11, 22], null, "2026-10-17T06:00:00Z");
  assert.deepEqual(readState([state, admissionAt(LANES, retriage, "2026-10-18T08:00:00Z")], String(APP)).runs, []);
  assert.deepEqual(readState([state, admissionAt(LANES, retriage, "2026-10-17T05:00:00Z")], String(APP)).runs, [11, 22], "edited before the state");
  assert.deepEqual(readState([state, admissionAt(LANES, "Not admitted to the issue lane yet: open pull request #9 is for it.", "2026-10-18T08:00:00Z")], String(APP)).runs, [11, 22], "a plain wait");
  assert.deepEqual(readState([state, admissionAt({ login: "other-app[bot]", id: OUTSIDER }, retriage, "2026-10-18T08:00:00Z")], String(APP)).runs, [11, 22], "another App");
});

// #14801: a born-triaged tracker waits in admission while a sub-issue is open,
// so the sweep leaves it; admission edits its wait comment in place and never
// clears it, so once the sub-issues close the stale comment must not hold it.
test("a born-triaged issue is dispatched once its sub-issues close, whatever admission's old wait comment says", async () => {
  const wait = admissionAt(LANES, "Not admitted to the issue lane yet: sub-issue #9 is open.", "2026-10-18T08:00:00Z");
  const born = (number, subs) => issue(number, { body: "Fix it.\n\n<!-- work-items:born-triaged -->", labels: [{ name: "status: ready" }], sub_issues_summary: subs });
  const gh = fakeGitHub({
    issues: [born(1, { total: 1, completed: 1, percent_completed: 100 }), born(2, { total: 1, completed: 0, percent_completed: 0 })],
    comments: { 1: [wait], 2: [{ ...wait, id: 8 }] },
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1], "sub-issue closed: dispatched; sub-issue open: left to admission");
  assert.ok(!gh.writes.some((w) => w.path.includes("/issues/2/")), "nothing written on the issue still waiting");
});

test("handedInComments counts the lanes App's re-triage admission comment by its last edit", () => {
  const state = { author: { __typename: "Bot", login: "github-actions" }, body: renderState({ runs: [1, 2], filed: HANDED, repoUrl: "u" }), createdAt: "2026-10-17T00:00:00Z", updatedAt: "2026-10-17T06:00:00Z" };
  const back = { author: { __typename: "Bot", login: "melodic-automation-lanes", databaseId: APP }, body: `${ADMIT_MARKER}\n${retriage}`, createdAt: "2026-10-16T00:00:00Z", updatedAt: "2026-10-18T08:00:00Z" };
  assert.equal(handedInComments([state, back], String(APP)), false);
  assert.equal(handedInComments([state, { ...back, updatedAt: "2026-10-17T05:00:00Z" }], String(APP)), true, "edited before the hand-off");
});

test("handedInComments counts a hand-back only from the lanes App's account", () => {
  const state = { author: { __typename: "Bot", login: "github-actions" }, body: renderState({ runs: [1, 2], filed: HANDED, repoUrl: "u" }), createdAt: "2026-10-17T06:00:00Z" };
  const back = (author) => ({ author, body: "<!-- work-unblock handed triage #40 -->", createdAt: "2026-10-18T08:00:00Z" });
  assert.equal(handedInComments([state, back({ __typename: "Bot", login: "melodic-automation-lanes", databaseId: APP })], String(APP)), false);
  assert.equal(handedInComments([state, back({ __typename: "Bot", login: "other-app", databaseId: OUTSIDER })], String(APP)), true);
  assert.equal(handedInComments([state, back({ __typename: "Bot", login: "melodic-automation-lanes", databaseId: APP })], null), true, "with no App id no hand-back counts");
});

test("a hand-off search that answers with GraphQL errors skips nothing: the hit is read", async () => {
  const gh = fakeGitHub({
    issues: [issue(1, { labels: [{ name: "needs-triage" }] })],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
    graphqlError: true,
  });
  const reads = [];
  const call = (method, path, body) => {
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.equal(result.candidates, 1);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 1);
  assert.deepEqual(gh.writes, []);
});

test("an issue past the comment pages that already carries needs-triage is not handed off again", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1, { labels: [{ name: "needs-triage" }] })], comments: { 1: flood } });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.handedOff, []);
});

test("an issue past the comment pages at needs-triage on the field alone is not handed off again", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1, { labels: [{ name: "status: confirmed" }] })], comments: { 1: flood } });
  const result = await sweep(gh, new Map([[1, ["needs-triage"]]]));
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.handedOff, []);
});

// work-unblock's unpark sets the field to needs-triage and posts this marker
// as the lanes App, so the sweep re-sends the issue as for its other hand-backs.
const unparked = (user, at) => ({ id: 8, user, body: "<!-- work-unblock unparked triage -->\nwork-unblock sent this issue back to intake triage.", created_at: at });

test("an issue at needs-triage with the lanes App's unpark marker is re-sent; the marker from anyone else is not", async () => {
  for (const [name, user, dispatched] of [
    ["the lanes App", LANES, [1]],
    ["an outsider", { login: "someone", id: OUTSIDER }, []],
    ["a listed human", { login: "owner", id: HUMAN }, []],
  ]) {
    const gh = fakeGitHub({
      issues: [issue(1)],
      comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), unparked(user, "2026-10-18T08:00:00Z")] },
      runs: triaged,
      handedIssues: [{ number: 1 }],
    });
    const result = await sweep(gh, new Map([[1, ["needs-triage"]]]));
    assert.deepEqual(result.dispatched, dispatched, name);
  }
  assert.deepEqual(readState([stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), unparked(LANES, "2026-10-18T08:00:00Z")], String(APP)).runs, []);
  // The marker counts only as the comment's first line.
  const quoted = { ...unparked(LANES, "2026-10-18T08:00:00Z"), body: "> <!-- work-unblock unparked triage -->" };
  assert.deepEqual(readState([stateAt([11, 22], null, "2026-10-17T06:00:00Z"), quoted], String(APP)).runs, [11, 22]);
});
