// Expected values come from the work-unblock lane's rules: when an issue
// closes, each issue it blocked gets `agent-ready` only when every blocker is
// closed as completed, it is open, and it carries no hold label; the label
// alone admits it to resolve-issue. Every fact is
// read from the API when the run starts, never from the event payload. The kill switch and
// a close by any bot sender stop the run before any API call.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ADMIT_MARKER, loadRules, refusalText, renderSplitRecord, SIZE_SPLIT_MARKER } from "../intake-triage/admit.mjs";
import { refsHoldMarker } from "../work-resolve-issue/report-outcome.mjs";
import {
  checkCloser,
  escalationComment,
  main,
  RECURRENCE_PREFIX,
  recurrenceComment,
  refireComment,
  refsClosedComment,
  refsMergedComment,
  infraComment,
  skipText,
} from "./label-unblocked.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TRUSTED = join(HERE, "fixtures/trusted-actors.json");
const API = "https://api.github.com";
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const SECOND = { id: 2001, login: "second-maintainer" };
const LANES_APP_ID = 337595936;
const STAMP = "2026-10-16T12:00:00Z";

const CLOSED = "2026-10-16T11:30:00Z";
const issue = (
  number,
  {
    state = "open",
    reason = state === "closed" ? "completed" : null,
    labels = [],
    repo = REPO,
    closer = state === "closed" ? OWNER : null,
    at = state === "closed" ? CLOSED : null,
    graphCloser = null,
  } = {},
) => ({
  number,
  state,
  state_reason: reason,
  labels: labels.map((name) => ({ name })),
  repository_url: `${API}/repos/${repo}`,
  closed_by: closer,
  closed_at: at,
  graphCloser,
});
// A fixture's `graphCloser` is the `closer` of the issue's last ClosedEvent
// as GraphQL answers it. For an issue closed when an App merged a pull
// request, it is that pull request: { __typename: "PullRequest", merged:
// true, repository: { nameWithOwner: "melodic-software/claude-code-plugins" } }.
// A plain close has none.
const mergedPr = ({ repo = REPO, number = 900, merged = true } = {}) => ({
  __typename: "PullRequest",
  number,
  merged,
  repository: { nameWithOwner: repo },
});
const commitClose = ({ repo = REPO } = {}) => ({ __typename: "Commit", oid: "a".repeat(40), repository: { nameWithOwner: repo } });
// An owner comment, which decides nothing.
const note = () => ({ id: 9, body: "Looks good.", user: OWNER, created_at: STAMP, updated_at: STAMP });

// The closed blocker, number 10, blocks the issues in `blocking`; `issues` is what a
// fresh GET /issues/{n} answers, `blockedBy` and `comments` per issue number.
// `closedList` is what the sweep's closed-issue listing answers; `blockingOf`
// gives the blocking list of closed issues other than number 10.
// `openReady` is what the sweep's open agent-ready listing answers.
// `runs` is every work-resolve-issue run; the listing answers those created in
// the `created` range it is asked for; `jobs` are per run id. `openLanePrs` is
// how many open lanes-App PRs, none held, the search lists; null makes the
// listing fail. `mergedLanePrs` is the search's merged count in the window
// (24 by default: a WIP cap of 2), null makes it fail.
// `queuedIssues` are the numbers the open agent-ready issue search lists, and
// `deferred` what the open admission-deferred listing answers.
// `blobs` maps a path to its blob SHA on main.
// `timeline` and `closing` are per issue, `pulls` per pull request number.
function world({
  blocking,
  blockingOf = {},
  closedList = [],
  openReady = [],
  issues = {},
  blockedBy = {},
  comments = {},
  events = {},
  runs = [],
  jobs = {},
  logs = {},
  openLanePrs = 0,
  mergedLanePrs = 24,
  blobs = {},
  timeline = {},
  closing = {},
  pulls = {},
  queuedIssues = [],
  deferred = [],
  searchIncomplete = false,
  fieldValues = {},
  specs = {},
  parents = {},
  subIssues = {},
  failOn,
} = {}) {
  const calls = [];
  const base = `/repos/${REPO}/issues`;
  const github = async (method, path, body, headers, { maxBytes } = {}) => {
    calls.push(body === undefined ? `${method} ${path}` : `${method} ${path} ${JSON.stringify(body)}`);
    if (failOn && (typeof failOn === "function" ? failOn(method, path, body) : path.startsWith(failOn))) {
      throw new Error(`${method} ${path} failed with status 500`);
    }
    const route = path.replace(/\?.*$/, "");
    const page = Number(new URL(path, "https://x").searchParams.get("page") ?? "1");
    const listed = (items) => (page === 1 ? items : []);
    let match;
    if (route === base && method === "GET") {
      const params = new URL(path, "https://x").searchParams;
      if (params.get("labels") === "admission-deferred") {
        assert.equal(params.get("state"), "open");
        return listed(deferred);
      }
      return listed(params.get("state") === "open" ? openReady : closedList);
    }
    if (route === `/repos/${REPO}/actions/workflows/work-resolve-issue.yml/runs` && method === "GET") {
      const params = new URL(path, "https://x").searchParams;
      // The in-flight read asks by status alone.
      if (params.has("status")) {
        return { workflow_runs: listed(runs.filter((run) => run.status === params.get("status"))) };
      }
      assert.equal(params.get("event"), "issues");
      const [from, to] = params.get("created").split("..").map(Date.parse);
      const inRange = runs.filter((run) => Date.parse(run.created_at) >= from && Date.parse(run.created_at) <= to);
      return { workflow_runs: listed(inRange) };
    }
    if (method === "GET" && route === "/search/issues") {
      if (searchIncomplete) {
        return { total_count: 0, incomplete_results: true, items: [] };
      }
      const q = new URL(path, "https://x").searchParams.get("q");
      if (q.startsWith(`repo:${REPO} is:issue is:open label:agent-ready `)) {
        const items = queuedIssues.map((number) => ({ number }));
        return { total_count: items.length, incomplete_results: false, items: items.slice((page - 1) * 100, page * 100) };
      }
      if (q === `repo:${REPO} is:pr is:open author:app/melodic-automation-lanes`) {
        if (openLanePrs === null) {
          throw new Error(`${method} ${path} failed with status 403`);
        }
        const open = Array.from({ length: openLanePrs }, () => ({ labels: [], body: "", created_at: STAMP }));
        return { total_count: openLanePrs, incomplete_results: false, items: open.slice((page - 1) * 100, page * 100) };
      }
      assert.match(q, /^repo:\S+ is:pr (is:merged )?author:app\/melodic-automation-lanes (merged|created):>=\S+$/);
      if (q.includes("is:merged") && mergedLanePrs === null) {
        throw new Error(`${method} ${path} failed with status 403`);
      }
      return { total_count: q.includes("is:merged") ? mergedLanePrs : 0, incomplete_results: false, items: [] };
    }
    if (method === "GET" && (match = route.match(new RegExp(`^/repos/${REPO}/actions/runs/(\\d+)/jobs$`)))) {
      assert.equal(new URL(path, "https://x").searchParams.get("filter"), "latest");
      return { jobs: jobs[match[1]] ?? [] };
    }
    // A job's log is read as text under a byte cap, as createGitHub's maxBytes does.
    if (method === "GET" && (match = route.match(new RegExp(`^/repos/${REPO}/actions/jobs/(\\d+)/logs$`)))) {
      assert.equal(typeof maxBytes, "number");
      if (logs[match[1]] === undefined) {
        throw new Error(`${method} ${path} failed with status 404`);
      }
      if (logs[match[1]].length > maxBytes) {
        throw new Error(`${method} ${path} answered a body over ${maxBytes} bytes`);
      }
      return logs[match[1]];
    }
    if (method === "GET" && (match = route.match(new RegExp(`^/repos/${REPO}/pulls/(\\d+)$`))) && pulls[match[1]]) {
      return pulls[match[1]];
    }
    if (method === "GET" && (match = route.match(/\/issues\/(\d+)\/timeline$/))) {
      return listed(timeline[match[1]] ?? []);
    }
    if (method === "GET" && (match = route.match(new RegExp(`^/repos/${REPO}/contents/(.+)$`))) && blobs[match[1]]) {
      assert.equal(new URL(path, "https://x").searchParams.get("ref"), "main");
      return { sha: blobs[match[1]] };
    }
    if (route === `${base}/10/dependencies/blocking`) {
      return listed(blocking);
    }
    if ((match = route.match(/\/issues\/(\d+)\/dependencies\/blocking$/))) {
      return listed(blockingOf[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/dependencies\/blocked_by$/))) {
      return listed(blockedBy[match[1]] ?? []);
    }
    if (method === "GET" && (match = route.match(/\/issues\/(\d+)\/parent$/)) && parents[match[1]]) {
      return parents[match[1]];
    }
    if (method === "GET" && (match = route.match(/\/issues\/(\d+)\/sub_issues$/))) {
      return listed(subIssues[match[1]] ?? []);
    }
    if (method === "GET" && (match = route.match(/\/issues\/(\d+)\/issue-field-values$/))) {
      return fieldValues[match[1]] ?? [];
    }
    if ((match = route.match(/\/issues\/(\d+)\/comments$/))) {
      return listed(comments[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/events$/))) {
      return listed(events[match[1]] ?? []);
    }
    if (method === "PATCH" && route.match(/\/issues\/comments\/(\d+)$/)) {
      return {};
    }
    if (method === "POST" && (match = route.match(/\/issues\/(\d+)\/labels$/))) {
      return [];
    }
    if (method === "DELETE" && route.match(/\/issues\/(\d+)\/labels\/(agent-ready|needs-human|admission-deferred|status%3A%20ready)$/)) {
      return [];
    }
    const lookup = (number) =>
      issues[number] ??
      closedList.find((item) => String(item.number) === number) ??
      Object.values(blockedBy)
        .flat()
        .find((item) => String(item.number) === number && item.repository_url === `${API}/repos/${REPO}`);
    // The closer read: the last ClosedEvent of one issue in this repository.
    if (method === "POST" && route === "/graphql" && body.query.includes("closedByPullRequestsReferences")) {
      const refs = { nodes: closing[body.variables.number] ?? [], pageInfo: { hasNextPage: false, endCursor: null } };
      return { data: { repository: { issue: { closedByPullRequestsReferences: refs } } } };
    }
    if (method === "POST" && route === "/graphql") {
      const { owner, name, number } = body.variables;
      // admit.mjs's text read: by default a listed human wrote the body.
      if (body.query.includes("comments(first: 100)")) {
        assert.equal(`${owner}/${name}`, REPO);
        const spec = specs[String(number)] ?? {
          body: String(lookup(String(number))?.body ?? ""),
          author: { __typename: "User", databaseId: OWNER.id },
          editor: null,
          lastEditedAt: null,
          comments: [],
        };
        const comments = { totalCount: spec.totalCount ?? spec.comments?.length, nodes: spec.comments };
        return { data: { repository: { issue: spec === "bad" ? null : { ...spec, comments } } } };
      }
      const found = lookup(String(number));
      // The closer read answers for whichever repository it names, so a read
      // of another repository's blocker sees that repository's closer.
      assert.equal(`${API}/repos/${owner}/${name}`.toLowerCase(), String(found?.repository_url ?? `${API}/repos/${REPO}`).toLowerCase());
      const nodes = found?.state === "closed" ? [{ closer: found.graphCloser }] : [];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if ((match = route.match(/\/issues\/(\d+)$/)) && lookup(match[1])) {
      return lookup(match[1]);
    }
    // Another repository's blocker, read there.
    if ((match = route.match(/\/repos\/([^/]+\/[^/]+)\/issues\/(\d+)$/))) {
      const other = Object.values(blockedBy)
        .flat()
        .find((item) => String(item.number) === match[2] && item.repository_url === `${API}/repos/${match[1]}`);
      if (other) {
        return other;
      }
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

function envFor(event = {}, extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), "work-unblock-"));
  const eventPath = join(dir, "event.json");
  writeFileSync(
    eventPath,
    JSON.stringify({ action: "closed", issue: issue(10, { state: "closed" }), sender: OWNER, ...event }),
  );
  return {
    GITHUB_REPOSITORY: REPO,
    GITHUB_EVENT_NAME: "issues",
    GITHUB_EVENT_PATH: eventPath,
    KILL_SWITCH: "proceed",
    TRUSTED_ACTORS_PATH: TRUSTED,
    ACTOR_ID: String(OWNER.id),
    TRIGGERING_ACTOR: OWNER.login,
    ...extra,
  };
}

// The GraphQL closer read is a POST but writes nothing.
const writes = (calls) => calls.filter((call) => !call.startsWith("GET ") && !call.startsWith("POST /graphql "));
const closerReads = (calls, number) =>
  calls.filter((call) => call.startsWith("POST /graphql ") && call.includes(`"number":${number}`)).length;
const labeled = (n) => `POST /repos/${REPO}/issues/${n}/labels {"labels":["agent-ready"]}`;

// Number 20, blocked by number 10 alone (now closed), as world() options.
const oneDependentWorld = (labels = []) => ({
  blocking: [issue(20, { labels })],
  issues: { 20: issue(20, { labels }) },
  blockedBy: { 20: [issue(10, { state: "closed" })] },
  comments: { 20: [note()] },
});

// Number 20 is blocked by number 10 (now closed) and number 11.
function oneDependent({ sibling = "closed", labels = [], comments = [note()], state = "open" } = {}) {
  return world({
    blocking: [issue(20, { state, labels })],
    issues: { 20: issue(20, { state, labels }) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 20: comments },
  });
}

test("a closed blocker with one open sibling blocker adds nothing", async () => {
  const { github, calls } = oneDependent({ sibling: "open" });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("the last blocker closing adds agent-ready", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("an issue held by needs-owner-decision, status: needs-decision, status: needs-info, needs-human or untrusted-provenance stays unlabeled", async () => {
  for (const hold of ["needs-owner-decision", "status: needs-decision", "status: needs-info", "needs-human", "work-class: untrusted-provenance"]) {
    const { github, calls } = oneDependent({ labels: [hold] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], hold);
  }
});

test("a hold or agent-ready label in another casing still counts", async () => {
  for (const label of ["Needs-Human", "Agent-Ready"]) {
    const { github, calls } = oneDependent({ labels: [label] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], label);
  }
});

// admit.mjs decide's rule: a blocker a listed human or a merge closed counts
// whatever its close reason; one an unlisted account closed still blocks.
test("a blocker a listed human closed as not planned or duplicate counts; one an unlisted account closed blocks", async () => {
  for (const reason of ["not_planned", "duplicate"]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed", reason })] },
      comments: { 20: [note()] },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], reason);
    const outsider = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", reason, closer: { id: 3003, login: "unlisted-maintainer", type: "User" } })] },
      comments: { 20: [note()] },
    });
    assert.equal(await main({ env: envFor(), github: outsider.github }), 0);
    assert.deepEqual(writes(outsider.calls), [], `outsider ${reason}`);
  }
});

test("a pull request blocker counts once merged, and not when closed unmerged", async () => {
  const pull = (merged_at) => ({
    ...issue(15, { state: "closed", reason: null }),
    pull_request: { url: `${API}/repos/${REPO}/pulls/15`, merged_at },
  });
  for (const [mergedAt, expected] of [["2026-10-16T12:00:00Z", [labeled(20)]], [null, []]]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" }), pull(mergedAt)] },
      comments: { 20: [note()] },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), expected, String(mergedAt));
  }
});

// Owner decision 2026-10-17: the agent-ready label alone admits, so no
// comment and no work-class label decides whether the issue is labeled.
test("an unblocked issue with no comment is labeled whatever its work-class label", async () => {
  for (const labels of [[], ["work-class: mechanical"], ["work-class: scoped"], ["Work-Class: Structural"]]) {
    const { github, calls } = oneDependent({ labels, comments: [] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], JSON.stringify(labels));
  }
});

test("an issue already agent-ready, or closed, is left alone", async () => {
  for (const options of [{ labels: ["agent-ready"] }, { state: "closed" }]) {
    const { github, calls } = oneDependent(options);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(options));
  }
});

test("the kill switch set stops the run before any API call", async () => {
  for (const value of ["", "false", "stop"]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { KILL_SWITCH: value }), github }), 0);
    assert.deepEqual(calls, [], value);
  }
});

test("a close by any bot (the lanes App, a PR merge by a bot) is a clean skip before any API call", async () => {
  for (const sender of [
    { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]", type: "Bot" },
    { id: 41898282, login: "github-actions[bot]", type: "Bot" },
  ]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({ sender }), github }), 0);
    assert.deepEqual(calls, [], sender.login);
  }
});

test("a close by a human sender proceeds", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({ sender: { ...OWNER, type: "User" } }), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("labels are read fresh from the API, never from the blocking list or the payload", async () => {
  // The blocking list (and the payload) show number 20 open and unlabeled; the
  // issue read at run time shows a hold added since.
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20, { labels: ["needs-human"] }) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [note()] },
  });
  const event = { issue: { ...issue(10, { state: "closed" }), labels: [], blocking: [issue(20)] } };
  assert.equal(await main({ env: envFor(event), github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(calls.includes(`GET /repos/${REPO}/issues/20`));
});

test("blockers are read fresh: a payload that says closed does not outweigh a reopened blocker", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "open" })] },
    comments: { 20: [note()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("only the issues every blocker of which is closed are labeled, and other repositories are skipped", async () => {
  const { github, calls } = world({
    blocking: [issue(20), issue(21), issue(22, { repo: "melodic-software/other" })],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: {
      20: [issue(10, { state: "closed" })],
      21: [issue(10, { state: "closed" }), issue(5, { state: "open", repo: "melodic-software/other" })],
    },
    comments: { 20: [note()], 21: [note()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(!calls.some((call) => call.includes("/issues/22")));
});

test("a failed read on one issue still lets the others through, and fails the run", async () => {
  const { github, calls } = world({
    blocking: [issue(20), issue(21)],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 21: [issue(10, { state: "closed" })] },
    comments: { 21: [note()] },
    failOn: `/repos/${REPO}/issues/20/dependencies/blocked_by`,
  });
  assert.equal(await main({ env: envFor(), github }), 1);
  assert.deepEqual(writes(calls), [labeled(21)]);
});

// The broker mints only when the closer and any re-runner are each a listed
// human, so anyone else stops the run quietly, before any API call (and, in
// the workflow, before the token request, through --check-closer).
test("a closer or re-runner who is not a listed human stops the run before any API call", async () => {
  for (const [id, login] of [
    // An unlisted closer, re-run by nobody else.
    ["1234", "someone-else"],
    // An unlisted closer, re-run by a listed human.
    ["1234", OWNER.login],
    // A listed bot is not a listed human, as closer or as re-runner.
    [String(LANES_APP_ID), "melodic-automation-lanes[bot]"],
    [String(OWNER.id), "melodic-automation-lanes[bot]"],
    // An unlisted re-runner.
    [String(OWNER.id), "someone-else"],
    ["", ""],
    [String(OWNER.id), ""],
  ]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { ACTOR_ID: id, TRIGGERING_ACTOR: login }), github }), 0);
    assert.deepEqual(calls, [], `${id} ${login}`);
  }
});

test("a re-run by a different listed human labels the unblocked issues", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({}, { ACTOR_ID: String(OWNER.id), TRIGGERING_ACTOR: SECOND.login }), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("the closer check answers proceed only when the closer and the re-runner are each a listed human", () => {
  const check = (id, login) => checkCloser({ ACTOR_ID: id, TRIGGERING_ACTOR: login, TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(check(String(OWNER.id), OWNER.login), true);
  assert.equal(check(String(OWNER.id), "Kyle-Sexton"), true);
  assert.equal(check(String(OWNER.id), SECOND.login), true);
  assert.equal(check(String(SECOND.id), "Kyle-Sexton"), true);
  assert.equal(check("1234", "someone-else"), false);
  assert.equal(check("1234", OWNER.login), false);
  assert.equal(check(String(LANES_APP_ID), "melodic-automation-lanes[bot]"), false);
  assert.equal(check(String(OWNER.id), "claude[bot]"), false);
  assert.equal(check(String(OWNER.id), "someone-else"), false);
  assert.equal(check(String(OWNER.id), ""), false);
  assert.equal(check("x", OWNER.login), false);
});

test("a pull request in the blocking list is skipped", async () => {
  const pull = { ...issue(30), pull_request: { url: `${API}/repos/${REPO}/pulls/30` } };
  const { github, calls } = world({
    blocking: [pull],
    issues: { 30: pull },
    blockedBy: { 30: [issue(10, { state: "closed" })] },
    comments: { 30: [note()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(!calls.some((call) => call.includes("/issues/30")));
});

test("an event other than an issue closing changes nothing and fails red", async () => {
  for (const [event, name] of [[{ action: "reopened" }, "issues"], [{}, "workflow_dispatch"]]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor(event, { GITHUB_EVENT_NAME: name }), github }), 1, name);
    assert.deepEqual(calls, [], name);
  }
});

// The hourly sweep: an issue a bot closed (a PR merge) starts no close run, so
// a scheduled run lists the issues closed in the last LOOKBACK_HOURS (3) and
// runs the close path's rules on each one. A scheduled run has no closer: its
// actor is whoever last changed the schedule, often a bot, so it is not checked.
const NOW = Date.parse("2026-10-16T12:00:00Z");
const SINCE = "2026-10-16T09:00:00.000Z";
const LANES_BOT = { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]", type: "Bot" };
// A swept close; by default the lanes App merged a pull request that closed it.
const closedAt = (number, at, closer = LANES_BOT, graphCloser = mergedPr({ number: 900 + number })) =>
  issue(number, { state: "closed", at, closer, graphCloser });
const sweep = (args, extra = {}) =>
  main({
    now: NOW,
    env: envFor({ schedule: "47 * * * *" }, {
      GITHUB_EVENT_NAME: "schedule",
      ACTOR_ID: String(LANES_APP_ID),
      TRIGGERING_ACTOR: LANES_BOT.login,
      ...extra,
    }),
    // A job's log goes through the same fake as every other read.
    jobLog: args.actions ? (repo, id, options) => args.actions("GET", `/repos/${repo}/actions/jobs/${id}/logs`, undefined, {}, options) : undefined,
    ...args,
  });

function sweptDependent({ sibling = "closed" } = {}) {
  return world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 20: [note()] },
  });
}

test("the sweep labels an issue whose last blocker a bot closed", async () => {
  const { github, calls } = sweptDependent();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(
    calls.includes(
      `GET /repos/${REPO}/issues?state=closed&since=${encodeURIComponent(SINCE)}&sort=updated&direction=desc&per_page=100&page=1`,
    ),
  );
});

// The window starts 15 minutes before the last successful scheduled run of
// work-unblock.yml whose label-unblocked job ran its sweep step, at most 3
// hours back; anything else, or any failed read, gives the 3 hours.
const SWEEP_RUNS = `/repos/${REPO}/actions/workflows/work-unblock.yml/runs?event=schedule&status=success&per_page=2`;
const ago = (minutes) => new Date(NOW - minutes * 60_000).toISOString();
const sweptJobs = (conclusion = "success", extraSteps = []) => ({
  jobs: [
    { name: "save-wip-state", conclusion: "success", steps: [{ name: "Save the WIP cap's last known state", conclusion: "success" }] },
    {
      name: "label-unblocked",
      conclusion: "success",
      steps: [{ name: "Check the kill switch", conclusion: "success" }, ...extraSteps, { name: "Label the unblocked issues", conclusion }],
    },
  ],
});
async function windowOf(answer, extra = {}, jobs = sweptJobs()) {
  const { github, calls } = sweptDependent();
  const actionCalls = [];
  const actions = async (method, path) => {
    actionCalls.push(`${method} ${path}`);
    if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs`)) {
      if (answer instanceof Error) {
        throw answer;
      }
      return answer;
    }
    if (/^\/repos\/[^/]+\/[^/]+\/actions\/runs\/5\/jobs\b/.test(path)) {
      if (jobs instanceof Error) {
        throw jobs;
      }
      return jobs;
    }
    return { workflow_runs: [], jobs: [] };
  };
  assert.equal(await sweep({ github, actions }, extra), 0);
  const listing = calls.find((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed&since=`));
  const since = Date.parse(decodeURIComponent(/since=([^&]+)/.exec(listing)[1]));
  return { minutes: (NOW - since) / 60_000, actionCalls };
}

test("the sweep reads back to 15 minutes before the last sweep that ran its labeling step", async () => {
  const { minutes, actionCalls } = await windowOf({ workflow_runs: [{ id: 5, run_started_at: ago(60) }] });
  assert.equal(minutes, 75);
  const windowCalls = actionCalls.filter((call) => call.includes("/work-unblock.yml/") || call.includes("/actions/runs/5/"));
  assert.deepEqual(windowCalls, [`GET ${SWEEP_RUNS}`, `GET /repos/${REPO}/actions/runs/5/jobs?filter=latest&per_page=100`]);
});

test("a last sweep older than the 3-hour window is capped at 3 hours without reading its jobs", async () => {
  const { minutes, actionCalls } = await windowOf({ workflow_runs: [{ id: 5, run_started_at: ago(300) }] });
  assert.equal(minutes, 180);
  assert.ok(!actionCalls.some((call) => call.includes("/actions/runs/5/jobs")));
});

test("a failed or empty read of the last sweep falls back to 3 hours", async () => {
  for (const answer of [new Error("GET failed with status 403"), { workflow_runs: [] }, { nope: true }, { workflow_runs: [{ id: "x", run_started_at: ago(60) }] }]) {
    assert.equal((await windowOf(answer)).minutes, 180);
  }
});

// A green run proves nothing by itself: the kill switch and a lane the config
// turns off each skip the labeling step and still end the job green.
test("a last successful run that did not sweep falls back to 3 hours", async () => {
  const runs = { workflow_runs: [{ id: 5, run_started_at: ago(60) }] };
  const killed = sweptJobs("skipped", [{ name: "Report the kill switch", conclusion: "success" }]);
  const offByConfig = sweptJobs("skipped", [
    { name: "Resolve the config", conclusion: "success" },
    { name: "Report a lane the config turns off", conclusion: "success" },
  ]);
  const noSteps = { jobs: [{ name: "label-unblocked", conclusion: "success", steps: [] }] };
  const noJob = { jobs: [{ name: "save-wip-state", conclusion: "success", steps: [] }] };
  for (const jobs of [killed, offByConfig, noSteps, noJob, { jobs: [] }, { nope: true }, new Error("GET failed with status 502")]) {
    assert.equal((await windowOf(runs, {}, jobs)).minutes, 180);
  }
});

test("the current run is skipped when finding the last sweep", async () => {
  const runs = { workflow_runs: [{ id: 77, run_started_at: ago(5) }, { id: 5, run_started_at: ago(60) }] };
  assert.equal((await windowOf(runs, { GITHUB_RUN_ID: "77" })).minutes, 75);
});

test("a sweep with no Actions client reads the full 3 hours", async () => {
  const { github, calls } = sweptDependent();
  assert.equal(await sweep({ github }), 0);
  assert.ok(calls.some((call) => call.includes(`since=${encodeURIComponent(SINCE)}`)));
});

test("the sweep skips an issue with an open sibling blocker", async () => {
  const { github, calls } = sweptDependent({ sibling: "open" });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("the kill switch stops the sweep before any API call", async () => {
  for (const value of ["", "false", "stop"]) {
    const { github, calls } = sweptDependent();
    assert.equal(await sweep({ github }, { KILL_SWITCH: value }), 0);
    assert.deepEqual(calls, [], value);
  }
});

test("the sweep does not read a closed issue outside the window, or a pull request", async () => {
  const pull = { ...closedAt(13, "2026-10-16T11:00:00Z"), pull_request: { url: `${API}/repos/${REPO}/pulls/13` } };
  const { github, calls } = world({
    // The second close was updated in the window but closed four hours ago.
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(12, "2026-10-16T08:00:00Z"), pull],
    blocking: [issue(20)],
    blockingOf: { 12: [issue(21)], 13: [issue(21)] },
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 20: [issue(10, { state: "closed" })], 21: [issue(12, { state: "closed" })] },
    comments: { 20: [note()], 21: [note()] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(!calls.some((call) => /\/issues\/(12|13|21)\b/.test(call)));
});

test("the sweep reads an issue blocked by two swept closes once", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(11, "2026-10-16T10:00:00Z")],
    blocking: [issue(20)],
    blockingOf: { 11: [issue(20)] },
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed" })] },
    comments: { 20: [note()] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.equal(calls.filter((call) => call === `GET /repos/${REPO}/issues/20`).length, 1);
  // Each close is judged once per run, as a swept source and as a blocker.
  for (const closed of [10, 11]) {
    assert.equal(closerReads(calls, closed), 1, closed);
  }
});

// The close path acts only on a close by a listed human; the sweep keeps that
// and adds closes by a merged pull request. An outside author who closes their
// own blocking issue starts nothing.
test("the sweep acts on a close by a listed human or a merged pull request, never by anyone else", async () => {
  for (const [closer, graphCloser, expected] of [
    [{ ...OWNER, type: "User" }, null, [labeled(20)]],
    [LANES_BOT, mergedPr({ number: 910 }), [labeled(20)]],
    [{ id: 1234, login: "someone-else", type: "User" }, null, []],
    [null, null, []],
  ]) {
    const { github, calls } = world({
      closedList: [closedAt(10, CLOSED, closer, graphCloser)],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [note()] },
    });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), expected, JSON.stringify(closer));
    // An untrusted close is dropped before its dependents are even listed.
    const listedDependents = calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/10/dependencies/blocking`));
    assert.equal(listedDependents, expected.length > 0, JSON.stringify(closer));
  }
});

// Removing agent-ready by hand stops the lane: no later run, close or sweep,
// puts it back. A person adds it again to restart.
test("an issue whose agent-ready label was removed is not labeled again", async () => {
  const removed = [{ event: "unlabeled", label: { name: "Agent-Ready" }, actor: OWNER }];
  for (const run of [(github) => main({ env: envFor(), github }), (github) => sweep({ github })]) {
    const { github, calls } = world({
      closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [note()] },
      events: { 20: removed },
    });
    assert.equal(await run(github), 0);
    assert.deepEqual(writes(calls), []);
  }
});

// Triage or a listed human adding status: ready after the newest removal
// lifts it; anyone else's add, or one before the removal, does not.
test("an issue marked status: ready after its agent-ready was removed is labeled again", async () => {
  const removed = { event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-10-16T09:00:00Z" };
  const marked = (actor, at = "2026-10-16T10:00:00Z") => ({ event: "labeled", label: { name: "status: ready" }, actor, created_at: at });
  for (const [events, expected] of [
    [[removed, marked(OWNER)], [labeled(20)]],
    [[removed, marked(LANES_BOT)], [labeled(20)]],
    [[marked(OWNER, "2026-10-16T08:00:00Z"), removed], []],
    [[removed, marked({ id: 777, login: "triage-user" })], []],
  ]) {
    for (const run of [(github) => main({ env: envFor(), github }), (github) => sweep({ github })]) {
      const { github, calls } = world({
        closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
        blocking: [issue(20)],
        issues: { 20: issue(20) },
        blockedBy: { 20: [issue(10, { state: "closed" })] },
        comments: { 20: [note()] },
        events: { 20: events },
      });
      assert.equal(await run(github), 0);
      assert.deepEqual(writes(calls), expected, JSON.stringify(events));
    }
  }
});

test("a removed label of another name does not stop the label", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [note()] },
    events: { 20: [{ event: "unlabeled", label: { name: "needs-human" } }, { event: "labeled", label: { name: "agent-ready" } }] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("a failed read of one swept close still lets the others through, and fails the run", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(11, "2026-10-16T10:00:00Z")],
    blocking: [issue(20)],
    blockingOf: { 11: [issue(21)] },
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 21: [issue(11, { state: "closed" })] },
    comments: { 21: [note()] },
    failOn: `/repos/${REPO}/issues/10/dependencies/blocking`,
  });
  assert.equal(await sweep({ github }), 1);
  assert.deepEqual(writes(calls), [labeled(21)]);
});

// One rule for every blocker, on both paths: a blocking issue counts as done
// only when it was closed as completed by a listed human or a merge, read fresh
// per blocker. An outside author closing their own blocking issue never counts.
test("a sibling blocker closed by an unlisted user keeps the issue unlabeled, on both paths", async () => {
  for (const [name, run] of [
    ["close", (github) => main({ env: envFor(), github })],
    ["sweep", (github) => sweep({ github })],
  ]) {
    for (const closer of [{ id: 1234, login: "someone-else", type: "User" }, null]) {
      const { github, calls } = world({
        closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
        blocking: [issue(20)],
        issues: { 20: issue(20) },
        blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer })] },
        comments: { 20: [note()] },
      });
      assert.equal(await run(github), 0);
      assert.deepEqual(writes(calls), [], `${name} ${JSON.stringify(closer)}`);
      assert.ok(calls.includes(`GET /repos/${REPO}/issues/11`), name);
    }
  }
});

test("a sibling blocker closed by a listed human counts", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer: { ...SECOND, type: "User" } })] },
    comments: { 20: [note()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

// A bot close counts only when GraphQL names a merged pull request or a commit
// in this repository as the closer; a GITHUB_TOKEN close from any workflow
// (github-actions[bot]) or an App close with no merge does not.
const siblingClosed = (closer, graphCloser) =>
  world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer, graphCloser })] },
    comments: { 20: [note()] },
  });
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]", type: "Bot" };
const MAINTAINER = { id: 3003, login: "unlisted-maintainer", type: "User" };

test("a bot close with no merged-PR evidence does not count, as a sibling or as a swept close", async () => {
  for (const closer of [LANES_BOT, ACTIONS_BOT]) {
    const sibling = siblingClosed(closer, null);
    assert.equal(await main({ env: envFor(), github: sibling.github }), 0);
    assert.deepEqual(writes(sibling.calls), [], `sibling ${closer.login}`);
    const swept = world({
      closedList: [closedAt(10, CLOSED, closer, null)],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [note()] },
    });
    assert.equal(await sweep({ github: swept.github }), 0);
    assert.deepEqual(writes(swept.calls), [], `swept ${closer.login}`);
  }
});

test("a close by a merged pull request or a commit counts, whoever merged it", async () => {
  for (const [closer, graphCloser] of [
    [LANES_BOT, mergedPr()],
    [{ id: 206951365, login: "cursor[bot]", type: "Bot" }, mergedPr({ number: 6191 })],
    [MAINTAINER, mergedPr()],
    [{ id: 49699333, login: "dependabot[bot]", type: "Bot" }, mergedPr({ repo: REPO.toUpperCase() })],
    [MAINTAINER, commitClose()],
  ]) {
    const { github, calls } = siblingClosed(closer, graphCloser);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], `${closer.login} ${JSON.stringify(graphCloser)}`);
  }
});

test("a closer that is an unmerged PR, or a PR or commit in another repository, does not count", async () => {
  for (const graphCloser of [
    mergedPr({ merged: false }),
    mergedPr({ repo: "melodic-software/other" }),
    commitClose({ repo: "melodic-software/other" }),
    { __typename: "PullRequest", number: 900 },
    { __typename: "Issue", number: 900 },
  ]) {
    const { github, calls } = siblingClosed(LANES_BOT, graphCloser);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(graphCloser));
  }
});

test("the closer is read fresh: a blocked-by entry naming a listed closer does not outweigh the issue itself", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20), 11: issue(11, { state: "closed", closer: { id: 1234, login: "someone-else", type: "User" } }) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed" })] },
    comments: { 20: [note()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

// Another repository's blocker is read there: a listed human's close counts,
// and an open one, an unlisted account's close or a failed read blocks. A
// merge there counts for nothing: people this repository's list does not
// cover merge in other repositories (the security review on #9814).
test("a blocker in another repository counts once a listed human closed it there", async () => {
  const OTHER = "melodic-software/other";
  const closedThere = (closer, failOn, graphCloser = null) =>
    world({
      blocking: [issue(20)],
      issues: { 20: issue(20), 5: issue(5, { state: "closed", repo: OTHER, closer, graphCloser }) },
      blockedBy: { 20: [issue(10, { state: "closed" }), issue(5, { state: "closed", repo: OTHER })] },
      comments: { 20: [note()] },
      failOn,
    });
  const human = closedThere(OWNER);
  assert.equal(await main({ env: envFor(), github: human.github }), 0);
  assert.deepEqual(writes(human.calls), [labeled(20)]);
  assert.ok(human.calls.includes(`GET /repos/${OTHER}/issues/5`));
  for (const [name, fake] of [
    ["unlisted closer", closedThere({ id: 3003, login: "unlisted-maintainer", type: "User" })],
    ["failed read", closedThere(OWNER, `/repos/${OTHER}/issues/5`)],
    ["commit there", closedThere({ id: 3003, login: "unlisted-maintainer", type: "User" }, undefined, commitClose({ repo: OTHER }))],
    ["merged PR there", closedThere({ id: 3003, login: "unlisted-maintainer", type: "User" }, undefined, mergedPr({ repo: OTHER }))],
  ]) {
    assert.equal(await main({ env: envFor(), github: fake.github }), 0, name);
    assert.deepEqual(writes(fake.calls), [], name);
  }
  const open = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(5, { state: "open", repo: OTHER })] },
    comments: { 20: [note()] },
  });
  assert.equal(await main({ env: envFor(), github: open.github }), 0);
  assert.deepEqual(writes(open.calls), []);
  // Another repository's pull request blocker never counts, merged or not.
  for (const [mergedAt, expected] of [["2026-10-16T11:00:00Z", []], [null, []]]) {
    const pull = { ...issue(16, { state: "closed", reason: null, repo: OTHER }), pull_request: { url: `${API}/repos/${OTHER}/pulls/16`, merged_at: mergedAt } };
    const fake = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" }), pull] },
      comments: { 20: [note()] },
    });
    assert.equal(await main({ env: envFor(), github: fake.github }), 0, String(mergedAt));
    assert.deepEqual(writes(fake.calls), expected, String(mergedAt));
  }
});

// Restarts after a limit stop (FINAL-DESIGN C4): the sweep restarts an open
// agent-ready issue whose newest lanes-App marker is outcome=limited once its
// reset has passed (a marker with no reset: five hours after it was posted),
// when no agent-ready label was added since the stop and no hold label is on
// it. The restart is the App removing and adding
// agent-ready, at most five issues per run, the longest-waiting first.
const limitedNote = (resets, at, user = LANES_BOT) => ({
  id: 30,
  body: `<!-- work-resolve-issue outcome=limited${resets ? ` resets=${resets}` : ""} run=7 -->\nStopped on the usage limit.`,
  user,
  created_at: at,
});
const ready = (n, labels = []) => issue(n, { labels: ["agent-ready", "work-class: read-only", ...labels] });
const added = (at, actor = LANES_BOT) => ({ event: "labeled", label: { name: "agent-ready" }, actor, created_at: at });
const restarted = (n) => [`DELETE /repos/${REPO}/issues/${n}/labels/agent-ready`, labeled(n)];
function stopped({ resets = "2026-10-16T11:00:00Z", at = "2026-10-16T06:00:00Z", labels = [], comments, events } = {}) {
  return world({
    openReady: [ready(30, labels)],
    comments: { 30: comments ?? [note(), limitedNote(resets, at)] },
    events: { 30: events ?? [added("2026-10-16T05:00:00Z")] },
  });
}

test("a limit-stopped issue past its reset is restarted by removing and adding agent-ready", async () => {
  const { github, calls } = stopped();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("a limit-stopped issue before its reset waits", async () => {
  const { github, calls } = stopped({ resets: "2026-10-16T13:00:00Z" });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a limit stop with no reset waits five hours from its marker", async () => {
  const early = stopped({ resets: "", at: "2026-10-16T06:00:00Z" });
  assert.equal(await sweep({ github: early.github }), 0);
  assert.deepEqual(writes(early.calls), restarted(30));
  const late = stopped({ resets: "", at: "2026-10-16T08:00:00Z" });
  assert.equal(await sweep({ github: late.github }), 0);
  assert.deepEqual(writes(late.calls), []);
});

test("agent-ready added after the stop means a run started since, so no restart", async () => {
  const { github, calls } = stopped({ events: [added("2026-10-16T05:00:00Z"), added("2026-10-16T11:30:00Z", OWNER)] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("only the newest lanes-App marker counts, and only the App's", async () => {
  const later = { ...limitedNote("", "2026-10-16T07:00:00Z"), body: "<!-- work-resolve-issue outcome=stopped -->" };
  for (const comments of [
    [note(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"), later],
    [note(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z", OWNER)],
  ]) {
    const { github, calls } = stopped({ comments });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), []);
  }
});

// Hand-back markers name their run, so a reuse check can match a branch to
// its report; the run id must not change how the restart reads them.
test("a hand-back marker naming its run, newer than the limit stop, still stops the restart", async () => {
  const later = { ...limitedNote("", "2026-10-16T07:00:00Z"), body: "<!-- work-resolve-issue outcome=stopped run=9 -->" };
  const { github, calls } = stopped({ comments: [note(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"), later] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

// A run that skipped the model for earlier work posts no marker; the App's own
// agent-ready after the stop still means a run started since.
test("agent-ready the App added after the stop, by a run that left no marker, means no second restart", async () => {
  const { github, calls } = stopped({ events: [added("2026-10-16T05:00:00Z"), added("2026-10-16T11:30:00Z")] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a held limit-stopped issue is not restarted; one with no other comment is", async () => {
  for (const hold of ["needs-human", "needs-owner-decision", "status: needs-decision", "status: needs-info"]) {
    const held = stopped({ labels: [hold] });
    assert.equal(await sweep({ github: held.github }), 0);
    assert.deepEqual(writes(held.calls), [], hold);
  }
  const bare = stopped({ comments: [limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z")] });
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), restarted(30));
});

test("a run restarts at most five issues, the longest-waiting first", async () => {
  const numbers = [31, 32, 33, 34, 35, 36];
  const { github, calls } = world({
    openReady: numbers.map((n) => ready(n)),
    // Number 31's limit reset last, so it is the one left for the next run.
    comments: Object.fromEntries(
      numbers.map((n) => [n, [note(), limitedNote(`2026-10-16T${n === 31 ? "11" : String(n - 30).padStart(2, "0")}:00:00Z`, "2026-10-16T00:30:00Z")]]),
    ),
    events: Object.fromEntries(numbers.map((n) => [n, [added("2026-10-16T00:00:00Z")]])),
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [32, 33, 34, 35, 36].flatMap(restarted));
});

// A removal of agent-ready is a restart only when the App made it, the App's
// newest marker before it is `limited`, and the next agent-ready event is the
// App adding it back. A person's removal, a removal before the stop, one never
// added back, or one after a later pushback stops the lane for good.
test("only the App's remove-and-re-add right after a limit stop is a restart; any other removal stops unblocking", async () => {
  const unlabeled = (actor, at) => ({ event: "unlabeled", label: { name: "agent-ready" }, actor, created_at: at });
  const limited = limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z");
  const pushback = { id: 31, body: "<!-- work-resolve-issue outcome=pushback run=8 -->\nUnclear.", user: LANES_BOT, created_at: "2026-10-16T08:00:00Z" };
  for (const [name, notes, events, expected] of [
    ["restart", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")], [labeled(20)]],
    [
      "re-fire",
      [{ id: 32, body: refireComment(KEY), user: LANES_BOT, created_at: "2026-10-16T06:59:59Z" }],
      [added("2026-10-16T06:00:00Z", OWNER), unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")],
      [labeled(20)],
    ],
    ["never added back", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z")], []],
    ["added back by a person", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z", OWNER)], []],
    ["before the stop", [limited], [unlabeled(LANES_BOT, "2026-10-16T05:00:00Z"), added("2026-10-16T05:00:01Z")], []],
    ["by a person", [limited], [unlabeled(OWNER, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")], []],
    [
      "pushback after a restart",
      [limited, pushback],
      [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z"), unlabeled(LANES_BOT, "2026-10-16T08:00:05Z")],
      [],
    ],
  ]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [note(), ...notes] },
      events: { 20: events },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), expected, name);
  }
});

test("a stated reset in the past still waits an hour from the stop", async () => {
  const early = stopped({ resets: "2026-10-16T09:00:00Z", at: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: early.github }), 0);
  assert.deepEqual(writes(early.calls), []);
  const late = stopped({ resets: "2026-10-16T09:00:00Z", at: "2026-10-16T10:30:00Z" });
  assert.equal(await sweep({ github: late.github }), 0);
  assert.deepEqual(writes(late.calls), restarted(30));
});

// Three limit stops since a person last added agent-ready hand the issue to a
// person: needs-human and a comment, no restart.
test("a third limit stop since a person added agent-ready adds needs-human with a comment instead of restarting", async () => {
  const stops = [
    limitedNote("2026-10-16T01:00:00Z", "2026-10-16T00:30:00Z"),
    limitedNote("2026-10-16T03:00:00Z", "2026-10-16T02:30:00Z"),
    limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"),
  ];
  const third = stopped({ comments: [note(), ...stops] });
  assert.equal(await sweep({ github: third.github }), 0);
  const written = writes(third.calls);
  assert.equal(written.length, 2);
  assert.ok(written[0].startsWith(`POST /repos/${REPO}/issues/30/comments `), written[0]);
  assert.ok(written[0].includes("<!-- work-unblock escalated -->"), written[0]);
  assert.deepEqual(written.slice(1), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);
  // The comment went out but the label did not: the next sweep adds only the
  // label. The App's explanation from before a person's re-add does not count.
  const explanation = (at) => ({ id: 40, body: escalationComment(3), user: LANES_BOT, created_at: at });
  const retry = stopped({ comments: [note(), ...stops, explanation("2026-10-16T06:30:00Z")] });
  assert.equal(await sweep({ github: retry.github }), 0);
  assert.deepEqual(writes(retry.calls), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);
  const stale = stopped({
    comments: [note(), explanation("2026-10-15T23:00:00Z"), ...stops],
    events: [added("2026-10-15T22:00:00Z", OWNER), added("2026-10-15T23:30:00Z", OWNER)],
  });
  assert.equal(await sweep({ github: stale.github }), 0);
  assert.equal(writes(stale.calls).length, 2);
  // A person adding agent-ready after the first stop starts the count again.
  const reset = stopped({ comments: [note(), ...stops], events: [added("2026-10-16T00:00:00Z"), added("2026-10-16T01:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: reset.github }), 0);
  assert.deepEqual(writes(reset.calls), restarted(30));
});

// The sweep reads the resolved config's `limits` (hours and counts) from the
// file resolve-config wrote.
const withLimits = (limits) => {
  const path = join(mkdtempSync(join(tmpdir(), "work-unblock-limits-")), "resolved-config.json");
  writeFileSync(path, JSON.stringify({ limits }));
  return { RESOLVED_CONFIG: path };
};

// Restarts after a turn cap (plan: turn-cap resume, PR 2): report-outcome
// keeps agent-ready and leaves the turn-cap marker while
// limits.turn-cap-restarts allows one, and the sweep restarts the issue at
// once, the way it restarts a limit stop, with no reset to wait for. More
// turn-cap markers since a person added agent-ready than the limit allows
// (a forged or stale one) restart nothing.
const capNote = (at, run = 7) => ({
  id: 33,
  body: `<!-- work-resolve-issue outcome=turn-cap cap=75 run=${run} -->\nThe work-resolve-issue lane stopped on this issue: turn cap 75 reached.`,
  user: LANES_BOT,
  created_at: at,
});

test("an issue the turn cap stopped is restarted while the limit allows it", async () => {
  const { github, calls } = stopped({ comments: [note(), capNote("2026-10-16T11:55:00Z")] });
  assert.equal(await sweep({ github }, withLimits({ "turn-cap-restarts": 1 })), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("turn-cap stops past the limit, or any with the limit at 0, restart nothing", async () => {
  for (const [limits, comments] of [
    [{ "turn-cap-restarts": 0 }, [note(), capNote("2026-10-16T11:55:00Z")]],
    [{ "turn-cap-restarts": 1 }, [note(), capNote("2026-10-16T08:00:00Z", 6), capNote("2026-10-16T11:55:00Z")]],
  ]) {
    // An unlisted account's agent-ready between the stops resets nothing.
    const { github, calls } = stopped({ comments, events: [added("2026-10-16T05:00:00Z", OWNER), added("2026-10-16T09:00:00Z", MAINTAINER)] });
    assert.equal(await sweep({ github }, withLimits(limits)), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(limits));
  }
});

test("the App's remove-and-re-add after a turn-cap stop is a restart, not a stop", async () => {
  const unlabeled = { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T07:00:00Z" };
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [note(), capNote("2026-10-16T06:00:00Z")] },
    events: { 20: [unlabeled, added("2026-10-16T07:00:01Z")] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

// A funding stop (ci-workflows#781): report-outcome keeps agent-ready and
// leaves a funding marker with the regain date, if one was stated. The sweep
// restarts the issue after that date, never before, and never without one;
// funding stops count toward limits.limit-stops-per-issue, not turn-cap-restarts.
const fundingNote = (resets, at, run = 7) => ({
  id: 34,
  body: `<!-- work-resolve-issue outcome=funding${resets ? ` resets=${resets}` : ""} run=${run} -->\nStopped on the lane's funding.`,
  user: LANES_BOT,
  created_at: at,
});

test("a funding-stopped issue past its regain date is restarted", async () => {
  const { github, calls } = stopped({ comments: [note(), fundingNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z")] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("a funding-stopped issue before its regain date, or with none, waits", async () => {
  for (const resets of ["2026-10-17T00:00:00Z", ""]) {
    const { github, calls } = stopped({ comments: [note(), fundingNote(resets, "2026-10-16T06:00:00Z")] });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], resets);
  }
});

// Funding and limit stops share limits.limit-stops-per-issue, so an outage
// that outlasts the reset clamp hands the issue to a person, not a loop.
test("a third funding or limit stop since a person added agent-ready goes to a person", async () => {
  const comments = [
    note(),
    fundingNote("2026-10-16T02:00:00Z", "2026-10-16T01:00:00Z", 4),
    limitedNote("2026-10-16T04:00:00Z", "2026-10-16T03:00:00Z"),
    fundingNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z", 6),
  ];
  const { github, calls } = stopped({ comments, events: [added("2026-10-16T00:30:00Z", OWNER)] });
  assert.equal(await sweep({ github }), 0);
  const written = writes(calls);
  assert.ok(written[0].includes("<!-- work-unblock escalated -->"), written[0]);
  assert.deepEqual(written.slice(1), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);
});

test("a funding stop under the bound is restarted after its date", async () => {
  const comments = [note(), fundingNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z", 6)];
  const { github, calls } = stopped({ comments, events: [added("2026-10-16T00:30:00Z", OWNER)] });
  assert.equal(await sweep({ github }, withLimits({ "limit-stops-per-issue": 2 })), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("the App's remove-and-re-add after a funding stop is a restart, not a stop", async () => {
  const unlabeled = { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T07:00:00Z" };
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [note(), fundingNote("2026-10-16T06:30:00Z", "2026-10-16T06:00:00Z")] },
    events: { 20: [unlabeled, added("2026-10-16T07:00:01Z")] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("the resolved limits set the sweep's restarts per run, limit stops per issue and fallback reset", async () => {
  const numbers = [31, 32, 33, 34];
  const many = world({
    openReady: numbers.map((n) => ready(n)),
    comments: Object.fromEntries(numbers.map((n) => [n, [note(), limitedNote(`2026-10-16T0${n - 30}:00:00Z`, "2026-10-16T00:30:00Z")]])),
    events: Object.fromEntries(numbers.map((n) => [n, [added("2026-10-16T00:00:00Z")]])),
  });
  assert.equal(await sweep({ github: many.github }, withLimits({ "restarts-per-run": 2 })), 0);
  assert.deepEqual(writes(many.calls), [31, 32].flatMap(restarted));

  const stops = [limitedNote("2026-10-16T03:00:00Z", "2026-10-16T02:30:00Z"), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z")];
  const second = stopped({ comments: [note(), ...stops] });
  assert.equal(await sweep({ github: second.github }, withLimits({ "limit-stops-per-issue": 2 })), 0);
  assert.deepEqual(writes(second.calls).slice(1), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);

  // No stated reset, stopped at 06:00: five hours has passed at 12:00, seven has not.
  const bare = stopped({ resets: "" });
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), restarted(30));
  const later = stopped({ resets: "" });
  assert.equal(await sweep({ github: later.github }, withLimits({ "fallback-reset": 7 })), 0);
  assert.deepEqual(writes(later.calls), []);
});

// After the DELETE, a failed re-add is tried once more; a second failure is an
// ::error naming the issue and fails the run.
test("a failed re-add after the removal is retried once, then reported", async (t) => {
  for (const [failures, code] of [[1, 0], [2, 1]]) {
    const { github: base, calls } = stopped();
    let left = failures;
    const github = async (method, path, body) => {
      if (method === "POST" && path.endsWith("/issues/30/labels") && left > 0) {
        left -= 1;
        calls.push(`${method} ${path} ${JSON.stringify(body)}`);
        throw new Error("POST failed with status 502");
      }
      return base(method, path, body);
    };
    const log = t.mock.method(console, "log", () => {});
    assert.equal(await sweep({ github }), code, `${failures} failures`);
    assert.deepEqual(writes(calls), [...restarted(30), labeled(30)], `${failures} failures`);
    const errors = log.mock.calls.map((call) => String(call.arguments[0])).filter((line) => line.startsWith("::error"));
    assert.equal(errors.length, code, `${failures} failures`);
    if (code) {
      assert.match(errors[0], /#30: agent-ready was removed for a restart but not added back/);
    }
    log.mock.restore();
  }
});

test("a failed listing of closed issues writes nothing and fails the run", async () => {
  const { github, calls } = world({ closedList: [closedAt(10, "2026-10-16T11:30:00Z")], failOn: `/repos/${REPO}/issues?` });
  assert.equal(await sweep({ github }), 1);
  assert.deepEqual(writes(calls), []);
});

// Re-fires after a failed run: a rerun keeps its first event's
// workflow files, so the token broker refuses it as workflow-modified once
// main's pr-run-activity-write.yml or work-resolve-issue.yml has changed, and
// a run that crashed before its report leaves no marker. The sweep gives such
// an issue a fresh event: the App removes and re-adds agent-ready, when its
// newest agent-ready label (a listed human's or the App's) has no lanes-App
// marker after it and the work-resolve-issue run that label started has
// failed. It records the re-fire in a comment first, and re-fires an issue at
// most once per version of those two files on main.
const WRITE_SHA = "1".repeat(40);
const CALLER_SHA = "2".repeat(40);
const KEY = `${WRITE_SHA}-${CALLER_SHA}`;
const BLOBS = { ".github/workflows/pr-run-activity-write.yml": WRITE_SHA, ".github/workflows/work-resolve-issue.yml": CALLER_SHA };
const LABELED_AT = "2026-10-16T10:00:00Z";
const laneRun = ({ number = 30, at = "2026-10-16T10:00:03Z", status = "completed", conclusion = "failure" } = {}) => ({
  id: 5000 + number,
  display_title: `Fix the thing #${number}`,
  created_at: at,
  status,
  conclusion,
  updated_at: at,
});
const refireNote = (key, at = "2026-10-16T09:00:00Z", user = LANES_BOT) => ({ id: 50, body: refireComment(key), user, created_at: at });
const refired = (n, key = KEY) => [
  `POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body: refireComment(key) })}`,
  ...restarted(n),
];
function failedRun({ runs = [laneRun()], comments = [note()], events = [added(LABELED_AT, OWNER)], labels = [], blobs = BLOBS, blockedBy = {} } = {}) {
  const fake = world({ openReady: [ready(30, labels)], comments: { 30: comments }, events: { 30: events }, runs, blobs, blockedBy });
  return { ...fake, actions: fake.github };
}

test("a failed run with no report after a listed human's agent-ready is re-fired: the record, then remove and re-add", async () => {
  const { github, actions, calls } = failedRun();
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
  assert.ok(refireComment(KEY).startsWith(`<!-- work-unblock refired ${KEY} -->`));
});

test("a run that timed out or failed to start is re-fired too", async () => {
  for (const conclusion of ["timed_out", "startup_failure"]) {
    const { github, actions, calls } = failedRun({ runs: [laneRun({ conclusion })] });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), refired(30), conclusion);
  }
});

test("an issue is re-fired once per version of the lane workflow files: the App's re-added label failing again stops there", async () => {
  // The App re-added the label at 11:00 after recording KEY; that run failed too.
  const again = failedRun({
    comments: [note(), refireNote(KEY, "2026-10-16T10:59:59Z")],
    events: [
      added(LABELED_AT, OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:00:00Z" },
      added("2026-10-16T11:00:01Z"),
    ],
    runs: [laneRun(), laneRun({ at: "2026-10-16T11:00:04Z" })],
  });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  assert.deepEqual(writes(again.calls), []);
  // A new pr-run-activity-write.yml on main allows one more.
  const newer = "3".repeat(40);
  const changed = failedRun({
    comments: [note(), refireNote(KEY, "2026-10-16T10:59:59Z")],
    events: [added(LABELED_AT, OWNER), added("2026-10-16T11:00:01Z")],
    runs: [laneRun({ at: "2026-10-16T11:00:04Z" })],
    blobs: { ...BLOBS, ".github/workflows/pr-run-activity-write.yml": newer },
  });
  assert.equal(await sweep({ github: changed.github, actions: changed.actions }), 0);
  assert.deepEqual(writes(changed.calls), refired(30, `${newer}-${CALLER_SHA}`));
  // A record by anyone but the App does not count.
  const forged = failedRun({ comments: [note(), refireNote(KEY, "2026-10-16T09:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: forged.github, actions: forged.actions }), 0);
  assert.deepEqual(writes(forged.calls), refired(30));
});

test("a run still going, one that succeeded or was cancelled before any job ran, or no run at all, is not re-fired", async () => {
  for (const [name, runs] of [
    ["in progress", [laneRun({ status: "in_progress", conclusion: null })]],
    ["queued beside a failed one", [laneRun(), laneRun({ at: "2026-10-16T10:00:09Z", status: "queued", conclusion: null })]],
    ["success", [laneRun({ conclusion: "success" })]],
    ["cancelled before any job ran", [laneRun({ conclusion: "cancelled" })]],
    ["none", []],
    ["another issue's", [laneRun({ number: 300 })]],
    ["outside the label's window", [laneRun({ at: "2026-10-16T10:30:00Z" })]],
  ]) {
    const { github, actions, calls } = failedRun({ runs });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), [], name);
  }
});

test("agent-ready added by an account that is neither a listed human nor the App is never re-fired", async () => {
  const stranger = { id: 4242, login: "stranger" };
  const { github, actions, calls } = failedRun({ events: [added(LABELED_AT, stranger)] });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a failed run whose report posted a marker, or a held issue, is not re-fired", async () => {
  const reported = failedRun({
    comments: [note(), { id: 31, body: "<!-- work-resolve-issue outcome=pushback run=8 -->\nUnclear.", user: LANES_BOT, created_at: "2026-10-16T10:20:00Z" }],
  });
  assert.equal(await sweep({ github: reported.github, actions: reported.actions }), 0);
  assert.deepEqual(writes(reported.calls), []);
  const held = failedRun({ labels: ["needs-human"] });
  assert.equal(await sweep({ github: held.github, actions: held.actions }), 0);
  assert.deepEqual(writes(held.calls), []);
});

test("a failed record comment re-fires nothing and fails the run", async (t) => {
  const { github: base, calls } = failedRun();
  const github = async (method, path, body) => {
    if (method === "POST" && path.endsWith("/issues/30/comments")) {
      calls.push(`${method} ${path}`);
      throw new Error("POST failed with status 502");
    }
    return base(method, path, body);
  };
  t.mock.method(console, "log", () => {});
  assert.equal(await sweep({ github, actions: base }), 1);
  assert.deepEqual(writes(calls), [`POST /repos/${REPO}/issues/30/comments`]);
});

test("with no Actions token the sweep reads no run and re-fires nothing", async () => {
  const { github, calls } = failedRun();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(!calls.some((call) => call.includes("/actions/")));
});

// The record and the App's re-add can land in the same whole second; the record
// still counts as done, and a later workflow version still re-fires once more.
test("a re-fire record in the same second as the App's re-add still counts, and a new workflow version re-fires", async () => {
  const newer = "3".repeat(40);
  const { github, actions, calls } = failedRun({
    comments: [note(), refireNote(KEY, "2026-10-16T11:00:01Z")],
    events: [
      added(LABELED_AT, OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:00:01Z" },
      added("2026-10-16T11:00:01Z"),
    ],
    runs: [laneRun(), laneRun({ at: "2026-10-16T11:00:04Z" })],
    blobs: { ...BLOBS, ".github/workflows/pr-run-activity-write.yml": newer },
  });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30, `${newer}-${CALLER_SHA}`));
});

// The record posted but the label never moved (a failed DELETE): the next
// sweep moves the label without posting the record again.
test("a re-fire record with no App re-add after it is finished by the next sweep, without a second record", async () => {
  const { github, actions, calls } = failedRun({ comments: [note(), refireNote(KEY, "2026-10-16T11:00:00Z")] });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("a re-fire record and the App's re-add in the same second, on unchanged workflow files, is not re-fired again", async () => {
  const { github, actions, calls } = failedRun({
    comments: [note(), refireNote(KEY, "2026-10-16T11:00:01Z")],
    events: [
      added(LABELED_AT, OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:00:01Z" },
      added("2026-10-16T11:00:01Z"),
    ],
    runs: [laneRun(), laneRun({ at: "2026-10-16T11:00:04Z" })],
  });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

// A lane PR the newest agent-ready label's run opened ends the run without a
// marker. The owner's ruling on the issue: a PR merged with `Refs:` or one a
// person closed unmerged hands the issue to triage (needs-triage on,
// agent-ready off), and re-running is a person adding agent-ready again; an
// open one waits on the needs-human report-outcome added for a Refs PR, which
// only that PR merging lifts. Only a PR the lanes App opened from
// the issue's lane branch (report-outcome's `work-resolve-issue/issue-<n>-
// <run>-<attempt>`), with head and base in this repository, counts.
// The pump: a run that minted no lane token did no work, either because its
// `Request the lane token` step failed (GitHub's rate limit past the retry
// budget, say) or because the WIP cap skipped resolve-issue. It is re-fired
// with the usual record, past once per workflow version, an hour after the
// run ended (the broker's Retry-After is at most an hour, so the reset has
// passed) and only while the WIP cap check does not pause the issue lane.
const pickSlot = { name: "pick-slot", conclusion: "success", steps: [{ name: "Check the WIP cap", conclusion: "success" }] };
const MINT_FAILED = [
  pickSlot,
  { name: "resolve-issue / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "failure" }] },
];
const WIP_CAPPED = [pickSlot, { name: "resolve-issue", conclusion: "skipped", steps: [] }];
function stalledRun({
  number = 30,
  jobs = MINT_FAILED,
  conclusion = jobs === WIP_CAPPED ? "success" : "failure",
  ended = "2026-10-16T10:05:00Z",
  openLanePrs = 10,
  mergedLanePrs = 24,
  comments = [note()],
  events = [added(LABELED_AT, OWNER)],
  blobs = BLOBS,
  queuedIssues = [],
  blockedBy = {},
  logs = {},
} = {}) {
  const fake = world({
    blockedBy,
    queuedIssues,
    logs,
    openReady: [ready(number)],
    comments: { [number]: comments },
    events: { [number]: events },
    runs: [{ ...laneRun({ number, conclusion }), updated_at: ended }],
    jobs: { [5000 + number]: jobs },
    openLanePrs,
    mergedLanePrs,
    blobs,
  });
  return { ...fake, actions: fake.github };
}

test("a run whose lane token request failed is re-fired an hour after it ended, with no needs-human", async () => {
  const { github, actions, calls } = stalledRun();
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
  // The WIP read's queued search names needs-human; no write does.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

test("a run that did no work waits until an hour after it ended, past any rate-limit reset", async () => {
  const { github, actions, calls } = stalledRun({ ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

// The sweep reads the resolved config's `limits` and `wip`; a past pause-from
// lets the issue lane pause over its cap.
const withConfig = (config) => {
  const path = join(mkdtempSync(join(tmpdir(), "work-unblock-config-")), "resolved-config.json");
  writeFileSync(path, JSON.stringify(config));
  return { RESOLVED_CONFIG: path };
};
const PAUSING = withConfig({ wip: { "pause-from": "2026-10-01" } });

test("a run the WIP cap skipped is re-fired once the issue lane is under its cap", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, openLanePrs: 1 });
  assert.equal(await sweep({ github, actions }, PAUSING), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("while the issue lane is paused over its cap nothing is re-fired", async () => {
  for (const openLanePrs of [2, 3]) {
    for (const jobs of [WIP_CAPPED, MINT_FAILED]) {
      const { github, actions, calls } = stalledRun({ jobs, openLanePrs });
      assert.equal(await sweep({ github, actions }, PAUSING), 0);
      assert.deepEqual(writes(calls), [], `${openLanePrs} open`);
    }
  }
});

test("over the cap with no pause-from the lane only alerts, so the run is re-fired", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, openLanePrs: 60 });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("a WIP read that fails re-fires: the read error blocks no lane work", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, openLanePrs: null });
  assert.equal(await sweep({ github, actions }, PAUSING), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("with the search rate limit spent the sweep makes no WIP read and re-fires", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, openLanePrs: 3 });
  assert.equal(await sweep({ github, actions, rate: { remaining: () => 0 } }, PAUSING), 0);
  assert.ok(!calls.some((call) => call.includes("/search/issues")));
  assert.deepEqual(writes(calls), refired(30));
});

test("with no merged count the resolved limits.wip-cap sets the cap", async () => {
  const config = withConfig({ limits: { "wip-cap": 20 }, wip: { "pause-from": "2026-10-01" } });
  const at = stalledRun({ openLanePrs: 20, mergedLanePrs: null });
  assert.equal(await sweep({ github: at.github, actions: at.actions }, config), 0);
  assert.deepEqual(writes(at.calls), []);
  const under = stalledRun({ openLanePrs: 19, mergedLanePrs: null });
  assert.equal(await sweep({ github: under.github, actions: under.actions }, config), 0);
  assert.deepEqual(writes(under.calls), refired(30));
});

// Each earlier re-fire left its record and the App's remove and re-add.
const earlierPumps = (count) => {
  const comments = [note()];
  const events = [added("2026-10-16T05:00:00Z", OWNER)];
  for (let hour = 6; hour < 6 + count; hour += 1) {
    const at = `2026-10-16T0${hour}:00:00Z`;
    comments.push(refireNote(KEY, at));
    events.push({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: at });
    events.push(added(hour === 5 + count ? LABELED_AT : `2026-10-16T0${hour}:00:01Z`));
  }
  return { comments, events };
};

// limits.limit-stops-per-issue (3) bounds failed-mint re-fires per version of
// the lane workflow files; a WIP cap skip made no mint attempt and has none.
test("a failed mint is re-fired again on the same workflow files up to the bound, and never counts as a limit stop", async () => {
  const { github, actions, calls } = stalledRun(earlierPumps(2));
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
  // The WIP read's queued search names needs-human; no write does.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

// Past the bound it keeps re-firing on the backoff (3 hours doubling per
// re-fire, at most 24, from when the run ended), recorded in one comment.
test("a failed mint past limit-stops-per-issue re-fires on the same workflow files goes on a backoff, with no needs-human", async () => {
  const mintCause = "The work-resolve-issue run that `agent-ready` started could not get its lane token.";
  // Three re-fires so far: 24 hours after the run ended at 10:05.
  const { github, actions, calls } = stalledRun(earlierPumps(3));
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
  const due = stalledRun(earlierPumps(3));
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-17T10:05:00Z") }), 0);
  assert.deepEqual(writes(due.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: infraComment(KEY, mintCause, 4) })}`, ...restarted(30)]);
  assert.ok(!writes(due.calls).some((call) => call.includes("needs-human")));
  // A bound of 1: one re-fire so far, so 6 hours.
  const lower = stalledRun(earlierPumps(1));
  assert.equal(await sweep({ github: lower.github, actions: lower.actions }, withLimits({ "limit-stops-per-issue": 1 })), 0);
  assert.deepEqual(writes(lower.calls), []);
  const lowerDue = stalledRun(earlierPumps(1));
  const limits = withLimits({ "limit-stops-per-issue": 1 });
  assert.equal(await sweep({ github: lowerDue.github, actions: lowerDue.actions, now: Date.parse("2026-10-16T16:05:00Z") }, limits), 0);
  assert.deepEqual(writes(lowerDue.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: infraComment(KEY, mintCause, 2) })}`, ...restarted(30)]);
});

test("a failed mint past the bound is re-fired again once the lane workflow files change", async () => {
  const { github, actions, calls } = stalledRun({ ...earlierPumps(3), blobs: { ...BLOBS, ".github/workflows/work-resolve-issue.yml": "3".repeat(40) } });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30, `${WRITE_SHA}-${"3".repeat(40)}`));
});

test("a run the WIP cap skipped keeps re-firing past the failed-mint bound", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, ...earlierPumps(3) });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
  // The WIP read's queued search names needs-human; no write does.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

test("a run another gate stopped before its mint, with no WIP cap skip, is not re-fired", async () => {
  const jobs = [pickSlot, { name: "resolve-issue / run", conclusion: "success", steps: [{ name: "Request the lane token", conclusion: "skipped" }] }];
  const { github, actions, calls } = stalledRun({ jobs, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

// The admit job's blocker gate skipped the run: its `Wait for open blockers`
// step ran and pick-slot did not. Agent-ready stays on and no marker follows;
// the sweep re-fires the issue once no blocker is open, past any bound, and
// never hands it to a person for it.
const BLOCKER_SKIPPED = [
  { name: "admit", conclusion: "success", steps: [{ name: "Check the trigger", conclusion: "success" }, { name: "Wait for open blockers", conclusion: "success" }] },
  { name: "pick-slot", conclusion: "skipped", steps: [] },
  { name: "resolve-issue", conclusion: "skipped", steps: [] },
];

test("a run the blocker gate skipped waits, with no write, while a blocker is open", async () => {
  for (const state of ["open", "closed"]) {
    const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", blockedBy: { 30: [issue(31, { state }), issue(32)] } });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), [], state);
  }
});

test("a run the blocker gate skipped is re-fired once no blocker is open, past the per-version bound, with no needs-human", async () => {
  for (const pumps of [{}, earlierPumps(3)]) {
    const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", blockedBy: { 30: [issue(31, { state: "closed" })] }, ...pumps });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), refired(30));
    assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
  }
});

test("a run the blocker gate skipped still waits on a blocker no listed human or merge here closed", async () => {
  const unmerged = { ...issue(31, { state: "closed" }), pull_request: { merged_at: null } };
  const stranger = { id: 1234, login: "someone-else", type: "User" };
  for (const blocker of [
    unmerged,
    issue(31, { state: "closed", reason: "not_planned", closer: stranger }),
    issue(31, { state: "closed", repo: "o/other", closer: stranger }),
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", blockedBy: { 30: [blocker] } });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(blocker));
  }
});

test("a run the blocker gate skipped is re-fired once a listed human closed its blocker as not planned or in another repository", async () => {
  for (const blocker of [issue(31, { state: "closed", reason: "not_planned" }), issue(31, { state: "closed", repo: "o/other" })]) {
    const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", blockedBy: { 30: [blocker] } });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), refired(30), JSON.stringify(blocker));
  }
});

// The admit job's provenance stop is final: the sweep never re-fires it and
// adds no needs-human (admission's refusal path hands it to a person).
const UNTRUSTED_STOPPED = [
  {
    name: "admit",
    conclusion: "success",
    steps: [
      { name: "Wait for open blockers", conclusion: "success" },
      { name: "Stop on untrusted provenance", conclusion: "success" },
    ],
  },
  { name: "pick-slot", conclusion: "skipped", steps: [] },
  { name: "resolve-issue", conclusion: "skipped", steps: [] },
];

test("a run the gate stopped on untrusted provenance is never re-fired, past any wait or bound, and gets no needs-human", async () => {
  for (const ended of ["2026-10-16T10:05:00Z", "2026-10-15T00:00:00Z"]) {
    const { github, actions, calls } = stalledRun({ jobs: UNTRUSTED_STOPPED, conclusion: "success", ended });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), [], ended);
  }
});

test("an agent-ready issue whose untrusted-provenance label someone unlisted removed is never re-fired or handed to a person", async () => {
  const untrusted = { name: "work-class: untrusted-provenance" };
  const events = [
    added("2026-10-16T08:00:00Z", OWNER),
    { event: "labeled", label: untrusted, actor: LANES_BOT, created_at: "2026-10-16T08:00:01Z" },
    { event: "unlabeled", label: untrusted, actor: { id: 999999, login: "stranger" }, created_at: "2026-10-16T08:00:02Z" },
  ];
  for (const runs of [[], [laneRun()]]) {
    const { github, actions, calls } = failedRun({ runs, events });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), [], `${runs.length} run(s)`);
  }
});

test("a stranded issue with an open blocker is neither re-fired nor handed to a person", async () => {
  const { github, actions, calls } = failedRun({ runs: [], events: [added("2026-10-16T08:00:00Z", OWNER)], blockedBy: { 30: [issue(31)] } });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a run that minted its token and failed later keeps the once-per-version re-fire", async () => {
  const jobs = [pickSlot, { name: "resolve-issue / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "success" }] }];
  const { github, actions, calls } = stalledRun({ jobs, ...earlierPumps(1) });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

// #8965: a dimension skip (split-required and the rest) ran resolve-issue's
// read runner, which mints nothing, and report-skip, whose failure leaves
// agent-ready on with no marker. The sweep re-fires that run, the fresh run
// skips again, and report-skip reports it, so the issue leaves the queued count.
test("a dimension-skipped run whose report-skip failed is re-fired, so report-skip reports it again", async () => {
  const readRunner = { name: "resolve-issue / run", conclusion: "success", steps: [{ name: "Ask the broker whether the lane may run", conclusion: "success" }] };
  for (const [name, mint] of [
    ["failed after its mint", "success"],
    ["failed at its mint", "failure"],
  ]) {
    const jobs = [pickSlot, readRunner, { name: "report-skip / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: mint }] }];
    const { github, actions, calls } = stalledRun({ jobs });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
  }
});

// #9095: run 39711139895 on #8087 ended cancelled when pick-slot hit its
// timeout in the WIP cap step: admit succeeded, pick-slot was cancelled and
// every later job skipped, so no lane branch and no outcome marker exist.
const CANCELLED_AT_PICK_SLOT = [
  { name: "admit", conclusion: "success", steps: [{ name: "Check the trigger", conclusion: "success" }] },
  { name: "pick-slot", conclusion: "cancelled", steps: [{ name: "Check the WIP cap", conclusion: "cancelled" }, { name: "Pick the slot", conclusion: "skipped" }] },
  { name: "report-skip", conclusion: "skipped", steps: [] },
  { name: "resolve-issue", conclusion: "skipped", steps: [] },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];

// A resolve-issue job cancelled while it waited for its slot never got a
// runner: run 39106011628's `resolve-issue / run` has started_at set, runner_id
// 0 and no steps. resolve-issue calls pr-run-activity-read.yml, whose jobs
// are broker-check (`Ask the broker whether the lane may run`) and run.
const ADMITTED = { name: "admit", conclusion: "success", runner_id: 11, steps: [{ name: "Check the trigger", conclusion: "success" }] };
const CANCELLED_IN_SLOT_QUEUE = [
  ADMITTED,
  pickSlot,
  { name: "resolve-issue / run", conclusion: "cancelled", started_at: "2026-10-16T10:01:00Z", runner_id: 0, steps: [] },
];
const BROKER_ALLOWED = {
  name: "resolve-issue / broker-check",
  conclusion: "success",
  started_at: "2026-10-16T10:01:00Z",
  runner_id: 12,
  steps: [{ name: "Ask the broker whether the lane may run", conclusion: "success" }],
};

test("a run cancelled before resolve-issue started is re-fired like a failed run, once per version of the lane workflow files", async () => {
  for (const [name, jobs] of [
    ["at pick-slot", CANCELLED_AT_PICK_SLOT],
    ["in the slot queue", CANCELLED_IN_SLOT_QUEUE],
  ]) {
    const fresh = stalledRun({ jobs, conclusion: "cancelled" });
    assert.equal(await sweep({ github: fresh.github, actions: fresh.actions }), 0, name);
    assert.deepEqual(writes(fresh.calls), refired(30), name);
  }
  // The App's re-add on these workflow files was cancelled the same way: stop there.
  const again = stalledRun({
    jobs: CANCELLED_AT_PICK_SLOT,
    conclusion: "cancelled",
    comments: [note(), refireNote(KEY, "2026-10-16T09:59:59Z")],
    events: [
      added("2026-10-16T09:00:00Z", OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T09:59:59Z" },
      added(LABELED_AT),
    ],
  });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  assert.deepEqual(writes(again.calls), []);
});

test("a cancelled run admit did not pass, one whose resolve-issue started, or a held issue's, is not re-fired", async () => {
  // The broker allowed the run and the model started before the cancel.
  const modelRun = {
    name: "resolve-issue / run",
    conclusion: "cancelled",
    started_at: "2026-10-16T10:02:00Z",
    runner_id: 13,
    steps: [
      { name: "Set up job", conclusion: "success" },
      { name: "Run the skill activity", conclusion: "cancelled" },
    ],
  };
  // A runner took the job, but the listing carries no steps.
  const stepless = { name: "resolve-issue / run", conclusion: "cancelled", started_at: "2026-10-16T10:02:00Z", runner_id: 14 };
  for (const [name, jobs, labels] of [
    // A newer agent-ready run for the issue replaced this one while it waited
    // in the workflow's concurrency group, so none of its jobs ran.
    ["superseded before any job ran", [], []],
    ["superseded with its jobs cancelled unstarted", [{ name: "admit", conclusion: "cancelled", steps: [] }, { name: "pick-slot", conclusion: "cancelled", steps: [] }], []],
    ["cancelled after the broker allowed it and the model started", [ADMITTED, pickSlot, BROKER_ALLOWED, modelRun], []],
    ["cancelled on a runner with no steps listed", [ADMITTED, pickSlot, BROKER_ALLOWED, stepless], []],
    ["cancelled while waiting, after its broker check ran", [ADMITTED, pickSlot, BROKER_ALLOWED, CANCELLED_IN_SLOT_QUEUE[2]], []],
    ["cancelled at pick-slot on a held issue", CANCELLED_AT_PICK_SLOT, ["needs-owner-decision"]],
  ]) {
    const fake = world({
      openReady: [ready(30, labels)],
      comments: { 30: [note()] },
      events: { 30: [added(LABELED_AT, OWNER)] },
      runs: [{ ...laneRun({ conclusion: "cancelled" }), updated_at: "2026-10-16T10:05:00Z" }],
      jobs: { 5030: jobs },
      blobs: BLOBS,
    });
    assert.equal(await sweep({ github: fake.github, actions: fake.github }), 0, name);
    assert.deepEqual(writes(fake.calls), [], name);
  }
});

// A run that waited in its slot past a lane workflow change ends green
// at the read runner's `Stop on stale workflow files` step, with no model turn
// and no outcome marker, so the sweep re-fires it like a failed run.
const staleRunJob = (stop) => ({
  name: "resolve-issue / run",
  conclusion: "success",
  steps: [
    { name: "Check the run's workflow files against main", conclusion: "success" },
    { name: "Stop on stale workflow files", conclusion: stop },
  ],
});
const STOPPED_STALE = [ADMITTED, pickSlot, BROKER_ALLOWED, staleRunJob("success"), { name: "report-outcome", conclusion: "skipped", steps: [] }];

test("a run that stopped green on stale workflow files is re-fired, once per version of the lane workflow files", async () => {
  const fresh = stalledRun({ jobs: STOPPED_STALE, conclusion: "success" });
  assert.equal(await sweep({ github: fresh.github, actions: fresh.actions }), 0);
  assert.deepEqual(writes(fresh.calls), refired(30));
  // didNoWork and stoppedStale share one read of the run's job listing.
  assert.equal(fresh.calls.filter((call) => call.startsWith(`GET /repos/${REPO}/actions/runs/5030/jobs`)).length, 1);
  // The App's re-add on these workflow files stopped stale again: stop there.
  const again = stalledRun({
    jobs: STOPPED_STALE,
    conclusion: "success",
    comments: [note(), refireNote(KEY, "2026-10-16T09:59:59Z")],
    events: [
      added("2026-10-16T09:00:00Z", OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T09:59:59Z" },
      added(LABELED_AT),
    ],
  });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  assert.deepEqual(writes(again.calls), []);
  // A newer version of the lane workflow files re-fires it once more.
  const newer = "3".repeat(40);
  const changed = stalledRun({
    jobs: STOPPED_STALE,
    conclusion: "success",
    comments: [note(), refireNote(KEY, "2026-10-16T09:59:59Z")],
    events: [
      added("2026-10-16T09:00:00Z", OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T09:59:59Z" },
      added(LABELED_AT),
    ],
    blobs: { ...BLOBS, ".github/workflows/work-resolve-issue.yml": newer },
  });
  assert.equal(await sweep({ github: changed.github, actions: changed.actions }), 0);
  assert.deepEqual(writes(changed.calls), refired(30, `${WRITE_SHA}-${newer}`));
});

// A breaker trip: the token broker refused the run for the lanes kill switch,
// which only the refused job's log names. Run 40127074215 failed at
// broker-check's broker ask before any resolve-issue run job; run 40127093047
// ran the model and was refused at its write runner's mint. Each denial line
// is the failed step's last, just before `Process completed`. A broker-check
// refusal for workflow-modified fails at the same step and stays a failed run.
const denied = (mode, reason, { stamp = "2026-10-24T19:57:51.9466327Z " } = {}) =>
  [
    "2026-10-24T19:57:50.6158116Z ##[group]Run request-lane-token",
    `${stamp}##[error]lane-${mode}-denied: the broker answered 403 with reason ${reason}: not-false: the repository CLAUDE_LANES_REPO_DISABLED is set and not exactly "false"`,
    "2026-10-24T19:57:51.9468461Z ##[error]Process completed with exit code 1.",
    "2026-10-24T19:57:52.0000000Z Cleaning up orphan processes",
    "",
  ].join("\n");
const BROKER_CHECK_ID = 120970852314;
const BROKER_REFUSED = [
  ADMITTED,
  pickSlot,
  {
    id: BROKER_CHECK_ID,
    name: "resolve-issue / broker-check",
    conclusion: "failure",
    runner_id: 12,
    started_at: "2026-10-16T10:01:00Z",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Ask the broker whether the lane may run", conclusion: "failure" },
    ],
  },
  { name: "report-skip", conclusion: "skipped", steps: [] },
  { name: "resolve-issue / run", conclusion: "skipped", steps: [] },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];
const PATCH_MINT_ID = 120972368518;
const REPORT_MINT_ID = 120972137995;
const MINT_REFUSED = [
  ADMITTED,
  pickSlot,
  BROKER_ALLOWED,
  { name: "resolve-issue / run", conclusion: "success", steps: [{ name: "Run the skill activity", conclusion: "success" }] },
  { id: PATCH_MINT_ID, name: "apply-issue-patch / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "failure" }] },
  { id: REPORT_MINT_ID, name: "report-outcome / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "failure" }] },
];
const CHECK_KILLED = { [BROKER_CHECK_ID]: denied("check", "kill-switch") };
const MINT_KILLED = { [PATCH_MINT_ID]: denied("token", "kill-switch"), [REPORT_MINT_ID]: denied("token", "kill-switch") };
// The breaker's own record, by its literal marker.
const BREAKER_MARKER = `<!-- work-unblock refired ${KEY} breaker -->`;
const isBreakerRecord = (call) => call.startsWith(`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: BREAKER_MARKER }).slice(0, -2)}`);
const tripped = (calls) => {
  const done = writes(calls);
  assert.equal(done.length, 3, done.join("\n"));
  assert.ok(isBreakerRecord(done[0]), done[0]);
  assert.deepEqual(done.slice(1), restarted(30));
  assert.ok(!done.some((call) => call.includes("needs-human")));
};
const logReads = (calls) => calls.filter((call) => /^GET \/repos\/[^ ]+\/actions\/jobs\/\d+\/logs$/.test(call));
// An issue's comments and events after the App's records `bodies`, each
// followed by its remove and re-add; the last re-add starts the run checked.
const history = (bodies) => {
  if (bodies.length === 0) {
    return { comments: [note()], events: [added(LABELED_AT, OWNER)] };
  }
  const comments = [note()];
  const events = [added("2026-10-16T05:00:00Z", OWNER)];
  bodies.forEach((body, index) => {
    const at = `2026-10-16T0${6 + index}:00:00Z`;
    comments.push({ id: 70 + index, body, user: LANES_BOT, created_at: at });
    events.push({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: at });
    events.push(added(index === bodies.length - 1 ? LABELED_AT : `2026-10-16T0${6 + index}:00:01Z`));
  });
  return { comments, events };
};
// The history after `count` sweeps of runs with `jobs` and `logs`, each
// carrying the record the sweep before posted.
async function afterSweeps(count, jobs, logs) {
  const bodies = [];
  for (let index = 0; index < count; index += 1) {
    const { github, actions, calls } = stalledRun({ jobs, logs, ...history(bodies) });
    assert.equal(await sweep({ github, actions }), 0);
    const posted = writes(calls).find((call) => call.startsWith(`POST /repos/${REPO}/issues/30/comments `));
    assert.ok(posted, `sweep ${index + 1} posted no record`);
    bodies.push(JSON.parse(posted.slice(posted.indexOf(" {") + 1)).body);
  }
  return history(bodies);
}

test("a run the broker refused at broker-check for the kill switch is a breaker trip: its own record, re-fired an hour after it ended", async () => {
  const { github, actions, calls } = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`]);
  // Within the hour it waits.
  const early = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: early.github, actions: early.actions }), 0);
  assert.deepEqual(writes(early.calls), []);
});

test("a breaker trip leaves the once-per-version re-fire for a later failed run", async () => {
  // A run that minted its token and failed later, after one breaker re-fire on these workflow files.
  const failedLater = [ADMITTED, pickSlot, BROKER_ALLOWED, { name: "resolve-issue / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "success" }] }];
  const { github, actions, calls } = stalledRun({ jobs: failedLater, ...(await afterSweeps(1, BROKER_REFUSED, CHECK_KILLED)) });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("a run the broker refused at its mints for the kill switch, after the model ran, is a breaker trip read from one log", async () => {
  const { github, actions, calls } = stalledRun({ jobs: MINT_REFUSED, logs: MINT_KILLED });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.equal(logReads(calls).length, 1);
  // Past the failed-mint bound on these workflow files it still goes as a trip, with no backoff record.
  const pumped = stalledRun({ jobs: MINT_REFUSED, logs: MINT_KILLED, ...earlierPumps(3) });
  assert.equal(await sweep({ github: pumped.github, actions: pumped.actions }), 0);
  tripped(pumped.calls);
});

test("breaker trips at the mint never count toward the failed-mint bound", async () => {
  // Three trips so far, then a mint that failed for another reason: the first failed-mint re-fire.
  const { github, actions, calls } = stalledRun(await afterSweeps(3, MINT_REFUSED, MINT_KILLED));
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("breaker trips past limit-stops-per-issue since a person last added agent-ready wait on the stranded backoff", async () => {
  const under = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ...(await afterSweeps(2, BROKER_REFUSED, CHECK_KILLED)) });
  assert.equal(await sweep({ github: under.github, actions: under.actions }), 0);
  tripped(under.calls);
  // Three trips: three hours after the run ended at 10:05.
  const three = await afterSweeps(3, BROKER_REFUSED, CHECK_KILLED);
  const over = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ...three });
  assert.equal(await sweep({ github: over.github, actions: over.actions }), 0);
  assert.deepEqual(writes(over.calls), []);
  const due = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ...three });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-16T13:05:00Z") }), 0);
  tripped(due.calls);
  // A listed human's agent-ready since starts the count again.
  const reset = { comments: three.comments, events: [...three.events.slice(0, -1), added(LABELED_AT, OWNER)] };
  const fresh = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ...reset });
  assert.equal(await sweep({ github: fresh.github, actions: fresh.actions }), 0);
  tripped(fresh.calls);
});

// The backoff comment is dated by its last edit, which moves it past the
// re-adds it made earlier; a breaker record before it still claims only its
// own re-add. Three re-fires of a failed run on these workflow files (06:00,
// 08:00 and 10:00, the last two on the backoff comment, edited at 09:59)
// around one breaker trip (07:00) wait 24 hours, not 12.
test("a breaker trip's re-add is its own: the backoff counts every other re-fire after the backoff comment is edited", async () => {
  const failedLater = [ADMITTED, pickSlot, BROKER_ALLOWED, { name: "resolve-issue / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "success" }] }];
  const unlabeled = (at) => ({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: at });
  const history = {
    comments: [
      note(),
      refireNote(KEY, "2026-10-16T06:00:00Z"),
      { id: 71, body: `${BREAKER_MARKER}\nThe token broker refused the run for the lanes kill switch.`, user: LANES_BOT, created_at: "2026-10-16T07:00:00Z" },
      { id: 72, body: infraComment(KEY, "A cause.", 2), user: LANES_BOT, created_at: "2026-10-16T08:00:00Z", updated_at: "2026-10-16T09:59:59Z" },
    ],
    events: [
      added("2026-10-16T05:00:00Z", OWNER),
      unlabeled("2026-10-16T06:00:00Z"),
      added("2026-10-16T06:00:01Z"),
      unlabeled("2026-10-16T07:00:00Z"),
      added("2026-10-16T07:00:01Z"),
      unlabeled("2026-10-16T08:00:00Z"),
      added("2026-10-16T08:00:01Z"),
      unlabeled("2026-10-16T09:59:59Z"),
      added(LABELED_AT),
    ],
  };
  // The run ended at 10:05: three re-fires wait 24 hours, so nothing at 12 hours.
  const early = stalledRun({ jobs: failedLater, ...history });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-16T22:05:00Z") }), 0);
  assert.deepEqual(writes(early.calls), []);
  const due = stalledRun({ jobs: failedLater, ...history });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-17T10:05:00Z") }), 0);
  const done = writes(due.calls);
  assert.equal(done.length, 3, done.join("\n"));
  assert.ok(done[0].startsWith(`PATCH /repos/${REPO}/issues/comments/72 `), done[0]);
  assert.ok(done[0].includes("has re-fired it 4 time(s)"), done[0]);
  assert.deepEqual(done.slice(1), restarted(30));
});

test("a refusal whose log does not name the kill switch on the step's last line stays a failed run", async () => {
  const lines = (...items) => `${items.join("\n")}\n`;
  for (const [name, log] of [
    ["workflow-modified", denied("check", "workflow-modified")],
    ["a lookalike reason", denied("check", "kill-switch-x")],
    ["no timestamp", denied("check", "kill-switch", { stamp: "" })],
    ["the mint's line in the check job", denied("token", "kill-switch")],
    ["over the size cap", `${"x".repeat(2 * 1024 * 1024)}\n${denied("check", "kill-switch")}`],
    [
      "a kill-switch line before the step's real denial",
      lines(
        "2026-10-24T19:57:50.0000000Z ##[error]lane-check-denied: the broker answered 403 with reason kill-switch",
        "2026-10-24T19:57:51.0000000Z ##[error]lane-check-denied: the broker answered 403 with reason workflow-modified",
        "2026-10-24T19:57:51.1000000Z ##[error]Process completed with exit code 1.",
      ),
    ],
    ["no log", undefined],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: BROKER_REFUSED, logs: log === undefined ? {} : { [BROKER_CHECK_ID]: log } });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
  }
  // A mint refusal whose log cannot be read is a failed mint.
  const unread = stalledRun({ jobs: MINT_REFUSED });
  assert.equal(await sweep({ github: unread.github, actions: unread.actions }), 0);
  assert.deepEqual(writes(unread.calls), refired(30));
});

test("a green run whose stale stop did not run, or a stop step outside resolve-issue, is not re-fired", async () => {
  for (const [name, jobs] of [
    ["stop step skipped", [ADMITTED, pickSlot, BROKER_ALLOWED, staleRunJob("skipped")]],
    ["stop step in another job", [ADMITTED, pickSlot, { ...staleRunJob("success"), name: "report-outcome / run" }]],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), [], name);
  }
});

// The job ids and step names the sweep matches in a run's job listing. A job a
// reusable workflow runs is listed as `<caller job id> / <called job id>` when
// the called job sets no name.
test("the job ids and step names the sweep matches exist in the lane workflows", () => {
  const workflow = (name) => readFileSync(join(HERE, "../../workflows", name), "utf8");
  const jobs = (text) => {
    const body = text.split("\njobs:\n")[1];
    const ids = [...body.matchAll(/^ {2}([a-z][a-z-]*):$/gm)].map((m) => m[1]);
    return Object.fromEntries(ids.map((id, i) => [id, body.split(/^ {2}[a-z][a-z-]*:$/m)[i + 1]]));
  };
  const steps = (block) => [...block.matchAll(/^ {6}- name: (.+)$/gm)].map((m) => m[1]);
  const unblock = jobs(workflow("work-unblock.yml"));
  assert.ok(unblock["label-unblocked"] !== undefined);
  assert.doesNotMatch(unblock["label-unblocked"], /^ {4}name:/m, "label-unblocked keeps its id as its name");
  assert.ok(steps(unblock["label-unblocked"]).includes("Label the unblocked issues"));
  const caller = jobs(workflow("work-resolve-issue.yml"));
  for (const id of ["admit", "pick-slot", "resolve-issue"]) {
    assert.ok(caller[id] !== undefined, id);
  }
  assert.ok(steps(caller["pick-slot"]).includes("Check the WIP cap"));
  assert.ok(steps(caller.admit).includes("Wait for open blockers"));
  assert.ok(steps(caller.admit).includes("Stop on untrusted provenance"));
  assert.match(caller["resolve-issue"], /^ {4}uses: \.\/\.github\/workflows\/pr-run-activity-read\.yml\b/m);
  const read = jobs(workflow("pr-run-activity-read.yml"));
  assert.ok(steps(read["broker-check"]).includes("Ask the broker whether the lane may run"));
  assert.ok(read.run !== undefined);
  assert.ok(steps(read.run).includes("Stop on stale workflow files"));
  for (const id of ["broker-check", "run"]) {
    assert.doesNotMatch(read[id], /^ {4}name:/m, `read runner job ${id} keeps its id as its name`);
  }
  // The write runner mints; the read runner resolve-issue calls never does.
  assert.ok(Object.values(jobs(workflow("pr-run-activity-write.yml"))).some((block) => steps(block).includes("Request the lane token")));
  assert.ok(!Object.values(read).some((block) => steps(block).includes("Request the lane token")));
});

test("re-fires of runs that did no work share the restarts-per-run cap", async () => {
  const numbers = [31, 32, 33, 34, 35, 36];
  const fake = world({
    openReady: numbers.map((n) => ready(n)),
    comments: Object.fromEntries(numbers.map((n) => [n, [note()]])),
    events: Object.fromEntries(numbers.map((n) => [n, [added(LABELED_AT, OWNER)]])),
    runs: numbers.map((n) => ({ ...laneRun({ number: n }), updated_at: "2026-10-16T10:05:00Z" })),
    jobs: Object.fromEntries(numbers.map((n) => [5000 + n, MINT_FAILED])),
    openLanePrs: 10,
    blobs: BLOBS,
  });
  assert.equal(await sweep({ github: fake.github, actions: fake.github }), 0);
  assert.deepEqual(writes(fake.calls), numbers.slice(0, 5).flatMap((n) => refired(n)));
});

const PR_HEAD = "7f2a5812a65a663ce0b3381312e1cb94b063fd4e";
const lanePull = ({
  pr = 7805,
  state = "closed",
  merged = true,
  body = "Refs: #30\n\nHold: a human merges this\n\n## Summary\n",
  created = "2026-10-16T10:20:00Z",
  closed = "2026-10-16T11:00:00Z",
  user = LANES_BOT,
  headRepo = REPO,
  ref = "work-resolve-issue/issue-30-39070302636-1",
  head = PR_HEAD,
} = {}) => ({
  number: pr,
  state,
  user,
  body,
  created_at: created,
  closed_at: state === "closed" ? closed : null,
  merged_at: state === "closed" && merged ? closed : null,
  head: { ref, sha: head, repo: { full_name: headRepo } },
  base: { ref: "main", repo: { full_name: REPO } },
});
const crossRef = (pull, repo = REPO) => ({
  event: "cross-referenced",
  created_at: pull.created_at,
  source: {
    type: "issue",
    issue: {
      number: pull.number,
      user: pull.user,
      created_at: pull.created_at,
      repository_url: `${API}/repos/${repo}`,
      pull_request: { url: `${API}/repos/${repo}/pulls/${pull.number}`, merged_at: pull.merged_at },
    },
  },
});
function lanePr({ pulls = [lanePull()], comments = [note()], events = [added(LABELED_AT, OWNER)], labels = [], runs = [] } = {}) {
  const fake = world({
    openReady: [ready(30, labels)],
    comments: { 30: comments },
    events: { 30: events },
    timeline: { 30: pulls.map((pull) => crossRef(pull)) },
    pulls: Object.fromEntries(pulls.map((pull) => [pull.number, pull])),
    runs,
  });
  return { ...fake, actions: fake.github };
}
const triaged = (n, pr, body = refsMergedComment(pr)) => [
  `POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body })}`,
  `DELETE /repos/${REPO}/issues/${n}/labels/status%3A%20ready`,
  `DELETE /repos/${REPO}/issues/${n}/labels/agent-ready`,
];
const CLOSED_PR = () => lanePull({ pr: 7493, merged: false, body: "Closes #30\n" });

// Owner 2026-10-24: the hand-off is no dead end. needs-triage would keep
// re-triage from ready, so none is added; status: ready comes off so the
// triage sweep re-dispatches intake, whose fresh status: ready re-admits it.
test("a lane PR merged with Refs: hands the issue to triage: the comment, then status: ready and agent-ready off, no needs-triage", async () => {
  const { github, actions, calls } = lanePr();
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7805));
  assert.ok(!writes(calls).some((call) => call.includes("needs-triage")));
  // The comment went out but a label write did not: only the labels move.
  const retry = lanePr({ comments: [note(), { id: 60, body: refsMergedComment(7805), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" }] });
  assert.equal(await sweep({ github: retry.github, actions: retry.actions }), 0);
  assert.deepEqual(writes(retry.calls), triaged(30, 7805).slice(1));
  // It needs no Actions token.
  const bare = lanePr();
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), triaged(30, 7805));
});

test("a lane PR merged with Closes, or one that is not the lanes App's own lane PR, hands nothing off", async () => {
  for (const [name, pull, repo] of [
    ["Closes", lanePull({ body: "Closes #30\n\n## Summary\n" })],
    ["Refs to another issue", lanePull({ body: "Refs: #31\n" })],
    ["a person's PR", lanePull({ user: OWNER })],
    ["a fork's head", lanePull({ headRepo: "someone/claude-code-plugins" })],
    ["another issue's lane branch", lanePull({ ref: "work-resolve-issue/issue-300-39070302636-1" })],
    ["a branch that is not a lane branch", lanePull({ ref: "fix/thing" })],
    ["opened before the label", lanePull({ created: "2026-10-16T09:59:59Z" })],
    ["cross-referenced from another repository", lanePull(), "someone/other"],
  ]) {
    const fake = world({
      openReady: [ready(30)],
      comments: { 30: [note()] },
      events: { 30: [added(LABELED_AT, OWNER)] },
      timeline: { 30: [crossRef(pull, repo)] },
      pulls: { [pull.number]: pull },
    });
    assert.equal(await sweep({ github: fake.github }), 0, name);
    assert.deepEqual(writes(fake.calls), [], name);
  }
});

test("a lane PR closed unmerged hands the issue to triage and never re-runs it", async () => {
  const { github, calls } = lanePr({ pulls: [CLOSED_PR()] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7493, refsClosedComment(7493)));
  assert.ok(!writes(calls).includes(labeled(30)));
  // The comment went out but a label write did not: only the labels move.
  const record = { id: 61, body: refsClosedComment(7493), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" };
  const unfinished = lanePr({ pulls: [CLOSED_PR()], comments: [note(), record] });
  assert.equal(await sweep({ github: unfinished.github }), 0);
  assert.deepEqual(writes(unfinished.calls), triaged(30, 7493).slice(1));
  // A person adding agent-ready again starts a new run; the closed PR is
  // behind that label and hands nothing off again.
  const rerun = lanePr({
    pulls: [CLOSED_PR()],
    comments: [note(), record],
    events: [
      added(LABELED_AT, OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:47:01Z" },
      added("2026-10-16T11:50:00Z", OWNER),
    ],
  });
  assert.equal(await sweep({ github: rerun.github }), 0);
  assert.deepEqual(writes(rerun.calls), []);
});

test("hand-offs after ended lane PRs share the five-a-run cap with restarts, the earliest end first", async () => {
  const numbers = [31, 32, 33, 34, 35, 36];
  const pullOf = (n) =>
    lanePull({
      pr: 7400 + n,
      merged: false,
      body: `Closes #${n}\n`,
      ref: `work-resolve-issue/issue-${n}-39070302636-1`,
      // Number 31's PR closed last, so it is the one left for the next run.
      closed: n === 31 ? "2026-10-16T11:59:00Z" : `2026-10-16T11:0${n - 30}:00Z`,
    });
  const { github, calls } = world({
    openReady: numbers.map((n) => ready(n)),
    comments: Object.fromEntries(numbers.map((n) => [n, [note()]])),
    events: Object.fromEntries(numbers.map((n) => [n, [added(LABELED_AT, OWNER)]])),
    timeline: Object.fromEntries(numbers.map((n) => [n, [crossRef(pullOf(n))]])),
    pulls: Object.fromEntries(numbers.map((n) => [7400 + n, pullOf(n)])),
  });
  assert.equal(await sweep({ github }), 0);
  const refiredIssues = writes(calls)
    .filter((call) => call.startsWith("DELETE ") && call.endsWith("/labels/agent-ready"))
    .map((call) => Number(call.match(/issues\/(\d+)\//)[1]));
  assert.deepEqual(refiredIssues, [32, 33, 34, 35, 36]);
});

test("an open lane PR hands nothing off, whatever its body", async () => {
  for (const body of ["Refs: #30\n", "Closes #30\n"]) {
    const { github, calls } = lanePr({ pulls: [lanePull({ pr: 7793, state: "open", body })] });
    assert.equal(await sweep({ github }), 0, body);
    assert.deepEqual(writes(calls), [], body);
  }
});

// report-outcome's hold on a Refs PR: the App added needs-human just after
// opening the PR, with the refs-hold comment naming it.
const holdNote = (pr = 7805, user = LANES_BOT) => ({ id: 64, body: `${refsHoldMarker(pr)}\nThe hold report-outcome put on the issue of a Refs PR.`, user, created_at: "2026-10-16T10:20:06Z" });
const humanLabeled = (at = "2026-10-16T10:20:05Z", actor = LANES_BOT, event = "labeled") => ({
  event,
  label: { name: "needs-human" },
  actor,
  created_at: at,
});
const refsHeld = (extra = {}) =>
  lanePr({
    labels: ["needs-human"],
    comments: [note(), holdNote()],
    events: [added(LABELED_AT, OWNER), humanLabeled()],
    ...extra,
  });

test("a Refs PR merging lifts the needs-human report-outcome set for it: needs-human, status: ready and agent-ready off", async () => {
  const { github, calls } = refsHeld();
  assert.equal(await sweep({ github }), 0);
  const [comment, status, agentReady] = triaged(30, 7805);
  assert.deepEqual(writes(calls), [comment, `DELETE /repos/${REPO}/issues/30/labels/needs-human`, status, agentReady]);
});

test("a Refs PR closed unmerged lifts the needs-human report-outcome set for it and hands the issue to triage", async () => {
  const { github, calls } = refsHeld({ pulls: [lanePull({ merged: false })] });
  assert.equal(await sweep({ github }), 0);
  const [comment, status, agentReady] = triaged(30, 7805, refsClosedComment(7805));
  assert.deepEqual(writes(calls), [comment, `DELETE /repos/${REPO}/issues/30/labels/needs-human`, status, agentReady]);
});

test("a needs-human that report-outcome did not set for the ended PR, or a PR still open, keeps the hold", async () => {
  for (const [name, fake] of [
    ["the marker by a person", refsHeld({ comments: [note(), holdNote(7805, OWNER)] })],
    ["the marker names another PR", refsHeld({ comments: [note(), holdNote(7804)] })],
    ["no marker", refsHeld({ comments: [note()] })],
    ["needs-human added by a person", refsHeld({ events: [added(LABELED_AT, OWNER), humanLabeled("2026-10-16T10:20:05Z", OWNER)] })],
    [
      "a person re-added needs-human after the App",
      refsHeld({
        events: [
          added(LABELED_AT, OWNER),
          humanLabeled(),
          humanLabeled("2026-10-16T10:30:00Z", OWNER, "unlabeled"),
          humanLabeled("2026-10-16T10:31:00Z", OWNER),
        ],
      }),
    ],
    ["the PR is open", refsHeld({ pulls: [lanePull({ state: "open" })] })],
    ["another hold beside it", refsHeld({ labels: ["needs-human", "needs-owner-decision"] })],
  ]) {
    assert.equal(await sweep({ github: fake.github }), 0, name);
    assert.deepEqual(writes(fake.calls), [], name);
  }
});

// Both lane-PR hand-offs share one rule: a hold label on the issue, or a
// person's removal of agent-ready, prevents them. The control run of each
// case does write, so a refusal below is the hold or the removal, not the case.
const LANE_PR_CASES = [
  ["merged with Refs:", () => lanePull(), triaged(30, 7805)],
  ["closed unmerged", CLOSED_PR, triaged(30, 7493, refsClosedComment(7493))],
];

test("a hold label on the issue prevents both hand-offs to triage", async () => {
  for (const [name, pull, expected] of LANE_PR_CASES) {
    const control = lanePr({ pulls: [pull()] });
    assert.equal(await sweep({ github: control.github }), 0, name);
    assert.deepEqual(writes(control.calls), expected, name);
    for (const hold of ["needs-human", "needs-owner-decision", "status: needs-decision", "status: needs-info"]) {
      const held = lanePr({ pulls: [pull()], labels: [hold] });
      assert.equal(await sweep({ github: held.github }), 0, `${name}: ${hold}`);
      assert.deepEqual(writes(held.calls), [], `${name}: ${hold}`);
    }
  }
});

test("a person removing agent-ready after the lane PR prevents both hand-offs to triage", async () => {
  const removed = { event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-10-16T11:30:00Z" };
  for (const [name, pull, expected] of LANE_PR_CASES) {
    const control = lanePr({ pulls: [pull()] });
    assert.equal(await sweep({ github: control.github }), 0, name);
    assert.deepEqual(writes(control.calls), expected, name);
    // The listing can be older than the removal, so the events decide.
    const fake = lanePr({ pulls: [pull()], events: [added(LABELED_AT, OWNER), removed] });
    assert.equal(await sweep({ github: fake.github }), 0, name);
    assert.deepEqual(writes(fake.calls), [], name);
  }
});

test("a hand-off whose label write failed is finished by the next sweep with the labels only, no second comment", async (t) => {
  const first = lanePr({ pulls: [CLOSED_PR()] });
  const github = async (method, path, body) => {
    if (method === "DELETE" && path.endsWith("/issues/30/labels/status%3A%20ready")) {
      first.calls.push(`${method} ${path}`);
      throw new Error("POST failed with status 502");
    }
    return first.github(method, path, body);
  };
  const log = t.mock.method(console, "log", () => {});
  assert.equal(await sweep({ github }), 1);
  log.mock.restore();
  // agent-ready stays on, so the next sweep comes back to the issue.
  assert.deepEqual(writes(first.calls), triaged(30, 7493, refsClosedComment(7493)).slice(0, 2));
  // A status: ready already gone (404) does not stop the hand-off.
  const gone = lanePr({
    pulls: [CLOSED_PR()],
    comments: [note(), { id: 63, body: refsClosedComment(7493), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" }],
  });
  const missing = async (method, path, body) => {
    if (method === "DELETE" && path.endsWith("/labels/status%3A%20ready")) {
      gone.calls.push(`${method} ${path}`);
      throw Object.assign(new Error("DELETE failed with status 404"), { status: 404 });
    }
    return gone.github(method, path, body);
  };
  assert.equal(await sweep({ github: missing }), 0);
  assert.deepEqual(writes(gone.calls), triaged(30, 7493).slice(1));
  const next = lanePr({
    pulls: [CLOSED_PR()],
    comments: [note(), { id: 63, body: refsClosedComment(7493), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" }],
  });
  assert.equal(await sweep({ github: next.github }), 0);
  assert.deepEqual(writes(next.calls), triaged(30, 7493).slice(1));
});

// Runs from before the run name carried ` #<issue>` cannot be matched to an
// issue, so the sweep says it cannot tell instead of that no run started.
test("a run in the label's window whose title names no issue makes the sweep say it cannot tell", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, actions, calls } = failedRun({ runs: [{ ...laneRun(), display_title: "fix(review): explain-change artifact medium" }] });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.some((line) => line.includes("#30 not restarted: cannot tell whether a lane run started")), lines.join("\n"));
  assert.ok(!lines.some((line) => line.includes("no lane run since")));
  log.mock.restore();
  // With only other issues' runs in the window, it still says no run started.
  const other = t.mock.method(console, "log", () => {});
  const plain = failedRun({ runs: [laneRun({ number: 300 })] });
  assert.equal(await sweep({ github: plain.github, actions: plain.actions }), 0);
  assert.ok(other.mock.calls.some((call) => String(call.arguments[0]).includes("#30 not restarted: no lane run since agent-ready was added")));
});

// A red-main fix issue post-merge-demotion-alert.yml reopens on a repeat
// failure keeps agent-ready, but the reopen ran on that workflow's
// GITHUB_TOKEN, which starts no lane run. The sweep finds it by the issue's
// first body line and the workflow's recurrence comment, both
// github-actions[bot]'s, and has the App remove and re-add agent-ready, once
// per recurrence comment, after a record naming that comment.
const ALERT = { id: 41898282, login: "github-actions[bot]", type: "Bot" };
const fixIssue = (n, { labels = [], user = ALERT, body = "<!-- post-merge-fix check=Lint / markdown -->\n\nThe check `Lint / markdown` started failing on main." } = {}) => ({
  ...ready(n, labels),
  user,
  body,
});
const recurrenceNote = ({ id = 801, at = "2026-10-16T11:00:00Z", user = ALERT, body } = {}) => ({
  id,
  body: body ?? `${RECURRENCE_PREFIX}${"b".repeat(40)}\`. Merge range: unknown. Run: https://github.com/${REPO}/actions/runs/9/attempts/1`,
  user,
  created_at: at,
});
// The lane PR that closed the issue the first time: merged with Closes.
const closingPull = () =>
  lanePull({ body: "Closes #30\n", created: "2026-10-10T09:20:00Z", closed: "2026-10-10T10:00:00Z" });
// `closing` lists pull requests GitHub says close the issue, outside its timeline.
function reopened({ issues = [fixIssue(30)], comments = [note(), recurrenceNote()], events = [added("2026-10-10T09:00:00Z", OWNER)], pulls = [closingPull()], runs = [], closing = [] } = {}) {
  const fake = world({
    openReady: issues,
    comments: Object.fromEntries(issues.map((item) => [item.number, comments])),
    events: Object.fromEntries(issues.map((item) => [item.number, events])),
    timeline: Object.fromEntries(issues.map((item) => [item.number, pulls.map((pull) => crossRef(pull))])),
    closing: Object.fromEntries(issues.map((item) => [item.number, closing.map((pull) => ({ number: pull.number, state: "OPEN", repository: { nameWithOwner: REPO } }))])),
    pulls: Object.fromEntries([...pulls, ...closing].map((pull) => [pull.number, pull])),
    runs,
  });
  return { ...fake, actions: fake.github };
}
const relabeled = (n, id = 801) => [
  `POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body: recurrenceComment(id) })}`,
  ...restarted(n),
];

test("post-merge-demotion-alert still posts the recurrence comment and the fix-issue marker this sweep matches", () => {
  const alert = readFileSync(join(HERE, "../../workflows/post-merge-demotion-alert.yml"), "utf8");
  assert.ok(alert.includes(`note="${RECURRENCE_PREFIX.replace("`", "\\`")}`), "the recurrence comment's opening words changed");
  assert.ok(alert.includes('fix_marker="<!-- post-merge-fix check=$check -->"'), "the fix issue's first line changed");
});

test("a fix issue a repeat failure reopened is relabeled: the record, then remove and re-add, with the count logged first", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, actions, calls } = reopened();
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), relabeled(30));
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  const count = lines.findIndex((line) => line.includes("1 reopened fix issue(s) to relabel"));
  const done = lines.findIndex((line) => line.includes("#30 relabeled after its reopen on a repeat failure"));
  assert.ok(count >= 0 && done > count, lines.join("\n"));
});

test("only github-actions[bot]'s fix issue and recurrence comment match", async () => {
  for (const [name, issue, comment] of [
    ["a lookalike comment by a person", fixIssue(30), recurrenceNote({ user: OWNER })],
    ["a lookalike comment by the App", fixIssue(30), recurrenceNote({ user: LANES_BOT })],
    ["another comment by the workflow", fixIssue(30), recurrenceNote({ body: "Fix main first." })],
    ["an issue without the fix marker", fixIssue(30, { body: "The check lint fails.\n<!-- post-merge-fix check=lint -->" }), recurrenceNote()],
    ["a fix marker on a person's issue", fixIssue(30, { user: OWNER }), recurrenceNote()],
  ]) {
    const { github, actions, calls } = reopened({ issues: [issue], comments: [note(), comment] });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), [], name);
  }
});

test("a reopened fix issue with an open lane PR, a lane run in flight, a hold, or no Actions token is not relabeled", async () => {
  const openPull = lanePull({ pr: 7900, state: "open", body: "Closes #30\n", created: "2026-10-16T08:00:00Z" });
  for (const [name, setup, withActions = true] of [
    ["an open lane PR from before the reopen", { pulls: [closingPull(), openPull] }],
    ["a run in progress", { runs: [laneRun({ status: "in_progress", conclusion: null })] }],
    ["a queued run", { runs: [laneRun({ status: "queued", conclusion: null })] }],
    ["an in-flight run naming no issue", { runs: [{ ...laneRun({ status: "in_progress", conclusion: null }), display_title: "Fix the thing" }] }],
    ["a hold label", { issues: [fixIssue(30, { labels: ["needs-human"] })] }],
    ["no Actions token", {}, false],
  ]) {
    const { github, actions, calls } = reopened(setup);
    assert.equal(await sweep({ github, actions: withActions ? actions : undefined }), 0, name);
    assert.deepEqual(writes(calls), [], name);
  }
  // Another issue's run in flight, or this issue's finished run, does not hold it.
  for (const runs of [[laneRun({ number: 31, status: "in_progress", conclusion: null })], [laneRun()]]) {
    const { github, actions, calls } = reopened({ runs });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), relabeled(30));
  }
});

// A listed human's open PR for the fix issue is work running on it.
test("a reopened fix issue with a listed human's open closing PR is not relabeled; an unlisted author's PR does not hold it", async () => {
  const humanPull = (user) => ({ number: 7960, state: "open", user });
  const listed = reopened({ closing: [humanPull(OWNER)] });
  assert.equal(await sweep({ github: listed.github, actions: listed.actions }), 0);
  assert.deepEqual(writes(listed.calls), []);
  const unlisted = reopened({ closing: [humanPull({ id: 3003, login: "unlisted-maintainer", type: "User" })] });
  assert.equal(await sweep({ github: unlisted.github, actions: unlisted.actions }), 0);
  assert.deepEqual(writes(unlisted.calls), relabeled(30));
});

test("each recurrence comment relabels once; a newer one relabels again", async () => {
  const record = { id: 61, body: recurrenceComment(801), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" };
  const after = [added("2026-10-10T09:00:00Z", OWNER), { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:47:01Z" }, added("2026-10-16T11:47:02Z")];
  // Relabeled already: the next sweep leaves it to the restart and re-fire rules.
  const again = reopened({ comments: [note(), recurrenceNote(), record], events: after });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  assert.deepEqual(writes(again.calls), []);
  // A person adding agent-ready since the reopen started a run: nothing to do.
  const person = reopened({ events: [added("2026-10-10T09:00:00Z", OWNER), added("2026-10-16T11:10:00Z", OWNER)] });
  assert.equal(await sweep({ github: person.github, actions: person.actions }), 0);
  assert.ok(!writes(person.calls).some((call) => call.includes(recurrenceComment(801))));
  // The record went out but the labels did not move: only the labels move.
  const retry = reopened({ comments: [note(), recurrenceNote(), record] });
  assert.equal(await sweep({ github: retry.github, actions: retry.actions }), 0);
  assert.deepEqual(writes(retry.calls), restarted(30));
  // A second reopen after the relabel relabels again, keyed on the new comment.
  const second = reopened({ comments: [note(), recurrenceNote(), record, recurrenceNote({ id: 802, at: "2026-10-16T11:50:00Z" })], events: after });
  assert.equal(await sweep({ github: second.github, actions: second.actions }), 0);
  assert.deepEqual(writes(second.calls), relabeled(30, 802));
});

test("relabels share the restarts-per-run cap, the longest-waiting first", async () => {
  const numbers = [30, 31, 32, 33, 34, 35];
  const fake = world({
    openReady: numbers.map((n) => fixIssue(n)),
    comments: Object.fromEntries(numbers.map((n) => [n, [recurrenceNote({ at: `2026-10-16T11:${String(n).padStart(2, "0")}:00Z` })]])),
    events: Object.fromEntries(numbers.map((n) => [n, [added("2026-10-10T09:00:00Z", OWNER)]])),
  });
  assert.equal(await sweep({ github: fake.github, actions: fake.github }), 0);
  assert.deepEqual(writes(fake.calls), numbers.slice(0, 5).flatMap((n) => relabeled(n)));
});

test("a relabel record that fails, as on a locked issue, is warned about and the labels still move", async (t) => {
  const { github: base, calls } = reopened();
  const github = async (method, path, body) => {
    if (method === "POST" && path.endsWith("/issues/30/comments")) {
      calls.push(`${method} ${path} ${JSON.stringify(body)}`);
      throw new Error("POST failed with status 403");
    }
    return base(method, path, body);
  };
  const log = t.mock.method(console, "log", () => {});
  assert.equal(await sweep({ github, actions: base }), 0);
  assert.deepEqual(writes(calls), relabeled(30));
  assert.ok(log.mock.calls.some((call) => String(call.arguments[0]).startsWith("::warning title=label-unblocked::#30: the relabel record was not posted")));
});

// A label admission refused must not become a credentialed run through the
// App's re-add: the newest agent-ready must be a listed human's or the App's.
const STRANGER = { id: 777, login: "triage-user" };
const unlabeledBy = (actor, at) => ({ event: "unlabeled", label: { name: "agent-ready" }, actor, created_at: at });
for (const [name, events] of [
  ["a user who is not listed", [added("2026-10-10T09:00:00Z", STRANGER)]],
  ["github-actions[bot]", [added("2026-10-10T09:00:00Z", ALERT)]],
  ["the owner, then removed and re-added by a user who is not listed", [added("2026-10-10T09:00:00Z", OWNER), unlabeledBy(OWNER, "2026-10-12T09:00:00Z"), added("2026-10-12T10:00:00Z", STRANGER)]],
  ["no account (no label event at all)", []],
]) {
  test(`a reopened fix issue whose agent-ready was added by ${name} is never relabeled`, async (t) => {
    const log = t.mock.method(console, "log", () => {});
    const { github, actions, calls } = reopened({ events });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), []);
    const lines = log.mock.calls.map((call) => String(call.arguments[0]));
    assert.ok(lines.includes("label-unblocked: #30 not restarted: agent-ready was added by neither a listed human nor the lanes App"), lines.join("\n"));
  });
}

test("a reopened fix issue whose agent-ready the App added is relabeled like a listed human's", async () => {
  const { github, actions, calls } = reopened({ events: [added("2026-10-10T09:00:00Z")] });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), relabeled(30));
});

// The recurrence check and the restart check read the same issue's comments
// and events; a sweep reads each once and both checks decide on that read.
test("a sweep reads a fix issue's comments and events once when the recurrence check passes it on", async (t) => {
  const reads = (calls, kind) => calls.filter((call) => call.startsWith(`GET /repos/${REPO}/issues/30/${kind}`)).length;
  for (const [name, setup, line] of [
    // The lane PR that first closed it merged with Closes, which the re-fire rule ends on.
    ["no recurrence comment", { comments: [note()] }, "#30 not restarted: its lane PR #7805 merged"],
    [
      "a person's agent-ready since the reopen",
      { events: [added("2026-10-10T09:00:00Z", OWNER), added("2026-10-16T11:10:00Z", OWNER)] },
      "#30 not restarted: no lane run since agent-ready was added",
    ],
    ["an issue no alert filed", { issues: [fixIssue(30, { user: OWNER })] }, "#30 not restarted: its lane PR #7805 merged"],
  ]) {
    const log = t.mock.method(console, "log", () => {});
    const { github, actions, calls } = reopened(setup);
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), [], name);
    assert.equal(reads(calls, "comments"), 1, name);
    assert.equal(reads(calls, "events"), 1, name);
    const lines = log.mock.calls.map((call) => String(call.arguments[0]));
    assert.ok(lines.includes(`label-unblocked: ${line}`), `${name}\n${lines.join("\n")}`);
    log.mock.restore();
  }
});

// Admission pacing (owner decision 2026-10-21, #8794): at or over the queued
// cap, on or after wip.pause-from, work-unblock adds no new agent-ready. With
// the default limits (factor 0.8, floor 1/h) and window (24 h), 24 merged
// lane PRs in 24 h is 0.8/h, under the floor, so the cap is 1 x 24 = 24. A
// deferred issue carries admission-deferred, which each sweep revisits
// oldest first; restarts and re-fires of admitted issues are never paced.
const deferredLabel = (n) => `POST /repos/${REPO}/issues/${n}/labels {"labels":["admission-deferred"]}`;
const undeferred = (n) => `DELETE /repos/${REPO}/issues/${n}/labels/admission-deferred`;
// n queued issues that no lane PR names.
const queuedN = (n) => Array.from({ length: n }, (_, i) => 100 + i);

test("at the queued cap past pause-from a newly unblocked issue is deferred, not labeled", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = world({ ...oneDependentWorld(), queuedIssues: queuedN(24) });
  assert.equal(await main({ env: envFor({}, PAUSING), github }), 0);
  assert.deepEqual(writes(calls), [deferredLabel(20)]);
});

test("under the queued cap, or before pause-from, a newly unblocked issue is labeled", async () => {
  for (const [queuedIssues, config] of [[queuedN(23), PAUSING], [queuedN(25), {}]]) {
    const { github, calls } = world({ ...oneDependentWorld(), queuedIssues });
    assert.equal(await main({ env: envFor({}, config), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], JSON.stringify(queuedIssues));
  }
});

// A degraded search answers a false empty (total_count 0, incomplete_results
// true): past pause-from that admits nothing, where a failed read fails open.
test("an incomplete search answer defers a newly unblocked issue, with or without pause-from, and names why", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  for (const config of [PAUSING, {}]) {
    const { github, calls } = world({ ...oneDependentWorld(), searchIncomplete: true });
    assert.equal(await main({ env: envFor({}, config), github }), 0);
    assert.deepEqual(writes(calls), [deferredLabel(20)], JSON.stringify(config));
  }
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #20 admission deferred: GitHub search answered incomplete results"), lines.join("\n"));
  assert.ok(!lines.some((line) => line.includes("at the queued cap")), lines.join("\n"));
});

test("at the queued cap the deferral names the queued cap", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github } = world({ ...oneDependentWorld(), queuedIssues: queuedN(24) });
  assert.equal(await main({ env: envFor({}, PAUSING), github }), 0);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #20 admission deferred: queued work is at the queued cap"), lines.join("\n"));
});

test("with room for one admission the first ready issue is labeled and the next deferred", async (t) => {
  t.mock.method(console, "log", () => {});
  const blocker = [issue(10, { state: "closed" })];
  const { github, calls } = world({
    blocking: [issue(20), issue(21)],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 20: blocker, 21: blocker },
    queuedIssues: queuedN(23),
  });
  assert.equal(await main({ env: envFor({}, PAUSING), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20), deferredLabel(21)]);
});

// Owner Q95: admission takes the oldest issue first, by when it was opened,
// whatever order the closed listing and the blocking lists answer in.
test("with room for one admission the oldest issue a sweep unblocks is labeled first", async (t) => {
  t.mock.method(console, "log", () => {});
  const opened = (n, at) => ({ ...issue(n), created_at: at });
  const { github, calls } = world({
    // Updated-desc order: 12 closed last, so the listing answers it first.
    closedList: [closedAt(12, "2026-10-16T11:40:00Z"), closedAt(10, "2026-10-16T11:30:00Z")],
    blockingOf: { 12: [opened(22, "2026-10-12T00:00:00Z"), opened(21, "2026-10-05T00:00:00Z")] },
    blocking: [opened(23, "2026-10-14T00:00:00Z"), opened(20, "2026-10-01T00:00:00Z")],
    issues: { 20: issue(20), 21: issue(21), 22: issue(22), 23: issue(23) },
    blockedBy: { 20: [issue(10, { state: "closed" })], 21: [issue(12, { state: "closed" })], 22: [issue(12, { state: "closed" })], 23: [issue(10, { state: "closed" })] },
    queuedIssues: queuedN(22),
  });
  assert.equal(await sweep({ github }, PAUSING), 0);
  assert.deepEqual(writes(calls), [labeled(20), labeled(21), deferredLabel(22), deferredLabel(23)]);
});

test("an issue already deferred is not labeled admission-deferred again", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = world({ ...oneDependentWorld(["admission-deferred"]), queuedIssues: queuedN(24) });
  assert.equal(await main({ env: envFor({}, PAUSING), github }), 0);
  assert.deepEqual(writes(calls), []);
});

// A deferred issue, number 25, whose one blocker is closed; `deferredBy`
// added its admission-deferred label (the lanes App by default).
const deferredAdd = (actor, at = "2026-10-16T08:00:00Z") => ({ event: "labeled", label: { name: "admission-deferred" }, actor, created_at: at });
const deferredWorld = ({ labels = ["admission-deferred"], sibling = "closed", queuedIssues = [], events = [deferredAdd(LANES_BOT)], openLanePrs = 0, timeline = [], closing = [] } = {}) =>
  world({
    openLanePrs,
    timeline: { 25: timeline },
    closing: { 25: closing },
    deferred: [issue(25, { labels })],
    issues: { 25: issue(25, { labels }) },
    blockedBy: { 25: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 25: [note()] },
    events: { 25: events },
    queuedIssues,
  });

test("the sweep re-admits a deferred issue only when the lanes App or a listed human added admission-deferred", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(line));
  for (const actor of [LANES_BOT, OWNER]) {
    const trusted = deferredWorld({ events: [deferredAdd(actor)] });
    assert.equal(await sweep({ github: trusted.github }, PAUSING), 0);
    assert.deepEqual(writes(trusted.calls), [labeled(25), undeferred(25)], actor.login);
  }
  // A stranger's label, or a stranger's newer re-add after the App's: left
  // as is, with nothing written, and reported as a warning.
  const stranger = { id: 999999, login: "drive-by", type: "User" };
  for (const events of [[deferredAdd(stranger)], [deferredAdd(LANES_BOT), deferredAdd(stranger, "2026-10-16T09:00:00Z")], []]) {
    logs.length = 0;
    const untrusted = deferredWorld({ events });
    assert.equal(await sweep({ github: untrusted.github }, PAUSING), 0);
    assert.deepEqual(writes(untrusted.calls), [], JSON.stringify(events));
    assert.ok(
      logs.some((line) => line.startsWith("::warning title=label-unblocked::#25") && line.includes("neither the lanes App nor a listed human")),
      logs.join("\n"),
    );
  }
});

test("the sweep admits a deferred issue once under the queued cap, and keeps it deferred at the cap", async (t) => {
  t.mock.method(console, "log", () => {});
  const under = deferredWorld({ queuedIssues: queuedN(23) });
  assert.equal(await sweep({ github: under.github }, PAUSING), 0);
  assert.deepEqual(writes(under.calls), [labeled(25), undeferred(25)]);
  const at = deferredWorld({ queuedIssues: queuedN(24) });
  assert.equal(await sweep({ github: at.github }, PAUSING), 0);
  assert.deepEqual(writes(at.calls), []);
});

// A pull request in this repository that references the deferred issue, as the REST
// timeline reports it, with the issue lane's Refs line unless `body` says otherwise.
const namingPull = (state, body = "Refs: #25") => ({
  event: "cross-referenced",
  source: { issue: { number: 40, state, pull_request: {}, repository_url: `${API}/repos/${REPO}`, body } },
});

test("the sweep keeps a deferred issue deferred while an open pull request is for it, and admits it once that closes", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  for (const facts of [{ timeline: [namingPull("open")] }, { closing: [{ number: 40, state: "OPEN", repository: { nameWithOwner: REPO } }] }]) {
    log.mock.resetCalls();
    const open = deferredWorld(facts);
    assert.equal(await sweep({ github: open.github }, PAUSING), 0);
    assert.deepEqual(writes(open.calls), []);
    const lines = log.mock.calls.map((call) => String(call.arguments[0]));
    assert.ok(lines.includes("label-unblocked: #25 stays deferred: open pull request #40 is for it"), lines.join("\n"));
  }
  for (const facts of [{ timeline: [namingPull("closed")] }, { closing: [{ number: 40, state: "MERGED", repository: { nameWithOwner: REPO } }] }]) {
    const closed = deferredWorld(facts);
    assert.equal(await sweep({ github: closed.github }, PAUSING), 0);
    assert.deepEqual(writes(closed.calls), [labeled(25), undeferred(25)], JSON.stringify(facts));
  }
});

test("the sweep admits a deferred issue an open pull request only mentions", async (t) => {
  t.mock.method(console, "log", () => {});
  const mention = deferredWorld({ timeline: [namingPull("open", "Same shape as #25.")] });
  assert.equal(await sweep({ github: mention.github }, PAUSING), 0);
  assert.deepEqual(writes(mention.calls), [labeled(25), undeferred(25)]);
});

test("while the issue lane is paused over its WIP cap the sweep keeps a deferred issue deferred, with queued room", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const paused = deferredWorld({ openLanePrs: 3 });
  assert.equal(await sweep({ github: paused.github }, PAUSING), 0);
  assert.deepEqual(writes(paused.calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.some((line) => line.includes("#25") && line.includes("the issue lane is paused")), lines.join("\n"));
});

test("the sweep keeps a held deferred issue deferred and drops the deferral of one no longer ready", async (t) => {
  t.mock.method(console, "log", () => {});
  const held = deferredWorld({ labels: ["admission-deferred", "needs-owner-decision"] });
  assert.equal(await sweep({ github: held.github }, PAUSING), 0);
  assert.deepEqual(writes(held.calls), []);
  for (const options of [{ sibling: "open" }, { labels: ["admission-deferred", "agent-ready"] }]) {
    const gone = deferredWorld(options);
    assert.equal(await sweep({ github: gone.github }, PAUSING), 0);
    assert.deepEqual(writes(gone.calls), [undeferred(25)], JSON.stringify(options));
  }
});

test("at the queued cap a run the WIP cap skipped is still re-fired: runs are never paced", async () => {
  const { github, actions, calls } = stalledRun({ jobs: WIP_CAPPED, openLanePrs: 1, queuedIssues: queuedN(25) });
  assert.equal(await sweep({ github, actions }, PAUSING), 0);
  assert.deepEqual(writes(calls), refired(30));
});

// The HITL mark (owner decision Q75): a listed human adding admission-deferred
// to a decided issue with `status: ready` has the sweep run intake's admission
// rules (admit.mjs decide, on admission-rules.json) on it. The verdict is the
// Size, Complexity and Uncertainty a listed human or the App set; it is
// admitted within the room only on admit.
const DIMS = {
  fields: {
    size: { "field-id": 15462270, options: { 27053568: "small", 27053567: "medium", 27053566: "large" } },
    complexity: { "field-id": 48625720, options: { 85127651: "low", 85127652: "medium", 85127653: "high" } },
    uncertainty: { "field-id": 48625721, options: { 85127654: "known", 85127655: "knowable", 85127656: "unknown" } },
  },
};
const fieldRow = (field, option) => ({ issue_field_id: field, single_select_option: { id: option } });
const SMALL_LOW_KNOWN = [fieldRow(15462270, 27053568), fieldRow(48625720, 85127651), fieldRow(48625721, 85127654)];
const LARGE_LOW_KNOWN = [fieldRow(15462270, 27053566), fieldRow(48625720, 85127651), fieldRow(48625721, 85127654)];
const RULES_PATH = join(HERE, "../../actions/resolve-config/admission-rules.json");
const admissionFor = (setter = OWNER.id) => async () => ({
  rules: loadRules(RULES_PATH),
  dimensionsConfig: DIMS,
  webHosts: [],
  fieldSetters: async () => ({ 15462270: setter, 48625720: setter, 48625721: setter }),
});
const MARKED = ["admission-deferred", "status: ready", "work-class: mechanical"];
const markedIssue = (labels) => ({ ...issue(25, { labels }), user: OWNER, type: { name: "Task" }, body: "Fix it.\n\n## Done when\n\n- [ ] Line 3 says nineteen." });
// Who added each label: intake's App wrote the decision, a person marked it.
const labelAdd = (name, actor, at = "2026-10-16T07:00:00Z") => ({ event: "labeled", label: { name }, actor, created_at: at });
const DECIDED = [labelAdd("status: ready", LANES_BOT), labelAdd("work-class: mechanical", LANES_BOT)];
const markedWorld = ({
  labels = MARKED,
  fields = SMALL_LOW_KNOWN,
  by = OWNER,
  decided = DECIDED,
  queuedIssues = [],
  specs = {},
  timeline = [],
  closing = [],
  comments = [note()],
  extraEvents = [],
  blockers = [issue(10, { state: "closed" })],
  failOn,
} = {}) =>
  world({
    specs,
    failOn,
    closing: { 25: closing },
    deferred: [markedIssue(labels)],
    issues: { 25: markedIssue(labels) },
    blockedBy: { 25: blockers },
    comments: { 25: comments },
    events: { 25: [...decided, ...extraEvents, deferredAdd(by)] },
    timeline: { 25: timeline },
    fieldValues: { 25: fields },
    queuedIssues,
  });
const fieldReads = (calls) => calls.filter((call) => call === `GET /repos/${REPO}/issues/25/issue-field-values`).length;

test("a person's mark on an admissible decided issue runs the admission rules and admits it within the room", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, calls } = markedWorld();
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [labeled(25), undeferred(25)]);
  assert.equal(fieldReads(calls), 1);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #25, marked by a person, passes the admission rules"), lines.join("\n"));
});

test("a person's mark on an inadmissible issue is refused: the admission comment, needs-decision, admission-deferred off", async (t) => {
  t.mock.method(console, "log", () => {});
  const refusedWrites = (reasons) => [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(reasons.join("; "))}` })}`,
    `POST /repos/${REPO}/issues/25/labels {"labels":["status: needs-decision"]}`,
    `DELETE /repos/${REPO}/issues/25/labels/status%3A%20ready`,
    undeferred(25),
  ];
  // Size Large parks for the intake split (owner Q93): a wait comment, the mark off, status: ready kept.
  const large = markedWorld({ fields: LARGE_LOW_KNOWN });
  assert.equal(await sweep({ github: large.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(large.calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: Size large: the split into sub-issues at intake is pending (owner Q93).` })}`,
    undeferred(25),
  ]);
  // A value no listed human or App set counts as unset, never as a default.
  const stranger = markedWorld();
  assert.equal(await sweep({ github: stranger.github, admission: admissionFor(4242) }, PAUSING), 0);
  assert.deepEqual(
    writes(stranger.calls),
    refusedWrites(["Size unset is not one of small, medium", "Uncertainty unset is not one of known, knowable"]),
  );
  // Intake's own deferral (the App's add) keeps the room-only path: no rules read.
  const intake = markedWorld({ fields: LARGE_LOW_KNOWN, by: LANES_BOT });
  assert.equal(await sweep({ github: intake.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(intake.calls), [labeled(25), undeferred(25)]);
  assert.equal(fieldReads(intake.calls), 0);
});

test("a person's mark whose criteria only the App wrote is refused; a text read of an unexpected shape writes nothing", async (t) => {
  t.mock.method(console, "log", () => {});
  const app = { __typename: "Bot", databaseId: LANES_APP_ID };
  const appOnly = markedWorld({
    specs: { 25: { body: "- [ ] Line 3 says nineteen.", author: app, editor: null, lastEditedAt: null, comments: [{ body: "Go ahead.", author: { __typename: "User", databaseId: OWNER.id }, editor: null, lastEditedAt: null }] } },
  });
  assert.equal(await sweep({ github: appOnly.github, admission: admissionFor() }, PAUSING), 0);
  assert.ok(writes(appOnly.calls).includes(`POST /repos/${REPO}/issues/25/labels {"labels":["status: needs-decision"]}`), writes(appOnly.calls).join("\n"));
  assert.ok(writes(appOnly.calls).some((call) => call.includes("no trusted-human acceptance criteria")));
  const bad = markedWorld({ specs: { 25: "bad" } });
  assert.equal(await sweep({ github: bad.github, admission: admissionFor() }, PAUSING), 1);
  assert.deepEqual(writes(bad.calls), []);
});

test("a person's mark waits, still deferred, while an open pull request closes or Refs it; one that only mentions it does not hold it", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const waiting = `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: open pull request #40 is for it.` })}`;
  for (const facts of [{ closing: [{ number: 40, state: "OPEN", repository: { nameWithOwner: REPO } }] }, { timeline: [namingPull("open")] }]) {
    log.mock.resetCalls();
    const open = markedWorld(facts);
    assert.equal(await sweep({ github: open.github, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(open.calls), [waiting], JSON.stringify(facts));
    const lines = log.mock.calls.map((call) => String(call.arguments[0]));
    assert.ok(lines.includes("label-unblocked: #25, marked by a person, waits: open pull request #40 is for it"), lines.join("\n"));
  }
  const mention = markedWorld({ timeline: [namingPull("open", "Same shape as #25.")] });
  assert.equal(await sweep({ github: mention.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(mention.calls), [labeled(25), undeferred(25)]);
});

test("a person's admissible mark with no room stays deferred", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, calls } = markedWorld({ queuedIssues: queuedN(24) });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #25, marked by a person, passes the admission rules"), lines.join("\n"));
  assert.ok(lines.includes("label-unblocked: #25 admission deferred: queued work is at the queued cap"), lines.join("\n"));
});

const NEEDS_DECISION_WRITE = `POST /repos/${REPO}/issues/25/labels {"labels":["status: needs-decision"]}`;
// The labels a sweep's writes leave on the marked fixture, the failed write left out.
const labelsAfter = (labels, calls, failed) =>
  writes(calls)
    .filter((call) => call !== failed)
    .reduce((now, call) => {
      const add = call.match(/^POST \/repos\/\S+\/issues\/25\/labels (.+)$/);
      const removed = call.match(/^DELETE \/repos\/\S+\/issues\/25\/labels\/(.+)$/);
      if (add) {
        return [...now, ...JSON.parse(add[1]).labels.filter((name) => !now.includes(name))];
      }
      return removed ? now.filter((name) => name !== decodeURIComponent(removed[1])) : now;
    }, labels);

test("a refusal whose needs-decision write fails keeps status: ready, so the next sweep admits nothing", async (t) => {
  t.mock.method(console, "log", () => {});
  const failOn = (method, path, body) => method === "POST" && path.endsWith("/issues/25/labels") && body?.labels?.includes("status: needs-decision");
  // Fields no listed human or App set read as unset, which refuses.
  const first = markedWorld({ failOn });
  assert.equal(await sweep({ github: first.github, admission: admissionFor(4242) }, PAUSING), 1);
  assert.ok(!writes(first.calls).includes(`DELETE /repos/${REPO}/issues/25/labels/status%3A%20ready`), writes(first.calls).join("\n"));
  const left = labelsAfter(MARKED, first.calls, NEEDS_DECISION_WRITE);
  const second = markedWorld({ labels: left });
  assert.equal(await sweep({ github: second.github, admission: admissionFor(4242) }, PAUSING), 0);
  assert.ok(!writes(second.calls).includes(labeled(25)), `${left}\n${writes(second.calls).join("\n")}`);
});

test("a person's mark whose field values or field setters read in an unexpected shape writes nothing", async (t) => {
  t.mock.method(console, "log", () => {});
  const rows = markedWorld({ fields: { message: "Not Found" } });
  assert.equal(await sweep({ github: rows.github, admission: admissionFor() }, PAUSING), 1);
  assert.deepEqual(writes(rows.calls), []);
  const noSetters = async () => ({ ...(await admissionFor()()), fieldSetters: async () => { throw new Error("the issue's field events have an unexpected shape"); } });
  const setters = markedWorld();
  assert.equal(await sweep({ github: setters.github, admission: noSetters }, PAUSING), 1);
  assert.deepEqual(writes(setters.calls), []);
});

test("a person's mark admits only when a listed human or the App added status: ready", async (t) => {
  t.mock.method(console, "log", () => {});
  const outsider = { id: 999999, login: "drive-by", type: "User" };
  const human = markedWorld({ decided: [labelAdd("status: ready", OWNER), labelAdd("work-class: mechanical", OWNER)] });
  assert.equal(await sweep({ github: human.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(human.calls), [labeled(25), undeferred(25)]);
  // The newest add counts: an outsider's re-add after the App's does not.
  for (const decided of [
    [labelAdd("status: ready", outsider), labelAdd("work-class: mechanical", LANES_BOT)],
    [labelAdd("status: ready", LANES_BOT), labelAdd("status: ready", outsider, "2026-10-16T07:30:00Z")],
    [labelAdd("work-class: mechanical", LANES_BOT)],
  ]) {
    const { github, calls } = markedWorld({ decided });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    assert.ok(!writes(calls).includes(labeled(25)), `${JSON.stringify(decided)}\n${writes(calls).join("\n")}`);
    assert.ok(writes(calls).includes(undeferred(25)), JSON.stringify(decided));
  }
});

// Owner decision Q85 (#9668): the work class gates nothing, so a class an
// outsider added, a structural class or none at all still admits.
test("a person's mark admits whatever work class the issue carries, except untrusted-provenance", async (t) => {
  t.mock.method(console, "log", () => {});
  const outsider = { id: 999999, login: "drive-by", type: "User" };
  for (const [labels, decided] of [
    [MARKED, [labelAdd("status: ready", LANES_BOT), labelAdd("work-class: mechanical", outsider)]],
    [["admission-deferred", "status: ready", "work-class: structural"], [labelAdd("status: ready", LANES_BOT)]],
    [["admission-deferred", "status: ready"], [labelAdd("status: ready", LANES_BOT)]],
  ]) {
    const { github, calls } = markedWorld({ labels, decided });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(calls), [labeled(25), undeferred(25)], JSON.stringify(labels));
  }
  const held = markedWorld({ labels: ["admission-deferred", "status: ready", "work-class: untrusted-provenance"], decided: [labelAdd("status: ready", LANES_BOT)] });
  await sweep({ github: held.github, admission: admissionFor() }, PAUSING);
  assert.ok(!writes(held.calls).includes(labeled(25)), writes(held.calls).join("\n"));
});

test("a person's mark waiting on an open blocker loses admission-deferred with the admission comment", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, calls } = markedWorld({ blockers: [issue(10)] });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  const why = "blocker #10 is not closed by a listed human or a merge";
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: ${why}.` })}`,
    undeferred(25),
  ]);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes(`label-unblocked: #25, marked by a person, waits: ${why}`), lines.join("\n"));
});

test("a person's mark the admission rules skip loses admission-deferred with a comment saying why", async (t) => {
  t.mock.method(console, "log", () => {});
  const removed = { event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-10-16T07:10:00Z" };
  const { github, calls } = markedWorld({ extraEvents: [removed] });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${skipText("agent-ready was removed and status: ready not added since")}` })}`,
    undeferred(25),
  ]);
});

// A stranded agent-ready issue: no hold, no open lane PR, no marker since its
// newest agent-ready, and no lane run for that label, or one that ended with
// no report, over 3 hours ago. It is re-fired once per version of the lane
// workflow files with the same record as a failed run; then it goes to a person.
const NO_RUN_CAUSE = "No work-resolve-issue run started in the 3 hours since `agent-ready` was last added.";
const NO_REPORT_CAUSE = "The work-resolve-issue run that `agent-ready` started ended over 3 hours ago with no report and no pull request.";
const refiredFor = (n, cause) => [`POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body: refireComment(KEY, cause) })}`, ...restarted(n)];

test("a stranded agent-ready issue with no lane run is re-fired once with the re-fire record", async () => {
  const { github, actions, calls } = failedRun({ runs: [], events: [added("2026-10-16T08:00:00Z", OWNER)] });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refiredFor(30, NO_RUN_CAUSE));
  assert.ok(refireComment(KEY, NO_RUN_CAUSE).startsWith(`<!-- work-unblock refired ${KEY} -->\n${NO_RUN_CAUSE}`));
});

// Owner 2026-10-24: nothing stops an item but intent or security, so a
// stranded issue already re-fired on these workflow files is re-fired again on
// a backoff (3 hours doubling per re-fire, at most 24), with one comment
// edited in place, and never gets needs-human.
const infraNote = (body, at) => ({ id: 52, body, user: LANES_BOT, created_at: "2026-10-16T14:00:02Z", updated_at: at });
test("a stranded issue already re-fired on these workflow files is re-fired on a backoff, with one comment and no needs-human", async () => {
  const events = [
    added("2026-10-16T06:00:00Z", OWNER),
    { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T08:00:00Z" },
    added("2026-10-16T08:00:01Z"),
  ];
  const comments = [note(), refireNote(KEY, "2026-10-16T07:59:59Z")];
  // One re-fire so far: 6 hours after the App's re-add, not before.
  const early = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-16T14:00:00Z") }), 0);
  assert.deepEqual(writes(early.calls), []);
  const first = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github: first.github, actions: first.actions, now: Date.parse("2026-10-16T14:00:02Z") }), 0);
  const body = infraComment(KEY, NO_RUN_CAUSE, 2);
  assert.deepEqual(writes(first.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body })}`, ...restarted(30)]);
  assert.ok(body.includes("re-fired it 2 time(s)"));
  // The next one waits 12 hours and edits that comment.
  const later = [
    ...events,
    { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T14:00:03Z" },
    added("2026-10-16T14:00:04Z"),
  ];
  const withNote = [...comments, infraNote(body, "2026-10-16T14:00:02Z")];
  const waiting = failedRun({ runs: [], comments: withNote, events: later });
  assert.equal(await sweep({ github: waiting.github, actions: waiting.actions, now: Date.parse("2026-10-17T02:00:00Z") }), 0);
  assert.deepEqual(writes(waiting.calls), []);
  const second = failedRun({ runs: [], comments: withNote, events: later });
  assert.equal(await sweep({ github: second.github, actions: second.actions, now: Date.parse("2026-10-17T02:00:05Z") }), 0);
  assert.deepEqual(writes(second.calls), [
    `PATCH /repos/${REPO}/issues/comments/52 ${JSON.stringify({ body: infraComment(KEY, NO_RUN_CAUSE, 3) })}`,
    ...restarted(30),
  ]);
});

test("the backoff between re-fires stops growing at 24 hours", async () => {
  const events = [added("2026-10-10T06:00:00Z", OWNER)];
  for (let day = 10; day < 16; day += 1) {
    events.push({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: `2026-10-${day}T08:00:00Z` });
    events.push(added(`2026-10-${day}T08:00:01Z`));
  }
  const comments = [note(), refireNote(KEY, "2026-10-10T07:59:59Z"), infraNote(infraComment(KEY, NO_RUN_CAUSE, 6), "2026-10-15T07:59:59Z")];
  const due = Date.parse("2026-10-16T08:00:01Z");
  const early = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: due - 1000 }), 0);
  assert.deepEqual(writes(early.calls), []);
  const { github, actions, calls } = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github, actions, now: due }), 0);
  assert.deepEqual(writes(calls), [`PATCH /repos/${REPO}/issues/comments/52 ${JSON.stringify({ body: infraComment(KEY, NO_RUN_CAUSE, 7) })}`, ...restarted(30)]);
});

// A listed human's open pull request for the issue is work running on it, as
// an open lane PR is: the issue is not stranded.
test("a stranded issue with a listed human's open closing PR is left alone; an unlisted author's PR is not running work", async () => {
  const humanPr = (user) =>
    world({
      openReady: [ready(30)],
      comments: { 30: [note()] },
      events: { 30: [added("2026-10-16T08:00:00Z", OWNER)] },
      blobs: BLOBS,
      closing: { 30: [{ number: 7950, state: "OPEN", repository: { nameWithOwner: REPO } }] },
      pulls: { 7950: { number: 7950, state: "open", user } },
    });
  const listed = humanPr(OWNER);
  assert.equal(await sweep({ github: listed.github, actions: listed.github }), 0);
  assert.deepEqual(writes(listed.calls), []);
  const unlisted = humanPr({ id: 3003, login: "unlisted-maintainer", type: "User" });
  assert.equal(await sweep({ github: unlisted.github, actions: unlisted.github }), 0);
  assert.deepEqual(writes(unlisted.calls), refiredFor(30, NO_RUN_CAUSE));
});

test("an issue with a recent lane run or label is left alone; past 3 hours it counts as stranded", async () => {
  // A green run with no report, 2 h 59 min 57 s old, and a label just under 3 h old: nothing.
  for (const [runs, at] of [
    [[laneRun({ at: "2026-10-16T09:00:03Z", conclusion: "success" })], "2026-10-16T09:00:00Z"],
    [[], "2026-10-16T09:00:01Z"],
  ]) {
    const { github, actions, calls } = failedRun({ runs, events: [added(at, OWNER)] });
    assert.equal(await sweep({ github, actions }), 0, at);
    assert.deepEqual(writes(calls), [], at);
  }
  const stale = failedRun({ runs: [laneRun({ at: "2026-10-16T08:59:00Z", conclusion: "success" })], events: [added("2026-10-16T08:58:57Z", OWNER)] });
  assert.equal(await sweep({ github: stale.github, actions: stale.actions }), 0);
  assert.deepEqual(writes(stale.calls), refiredFor(30, NO_REPORT_CAUSE));
  // An open lane PR keeps a stranded issue out of the re-fire.
  const lanePr = { number: 7900, user: LANES_BOT, state: "open", created_at: "2026-10-16T05:00:00Z", head: { ref: "work-resolve-issue/issue-30-4000-1", repo: { full_name: REPO } }, base: { repo: { full_name: REPO } } };
  const withPr = world({
    openReady: [ready(30)],
    comments: { 30: [note()] },
    events: { 30: [added("2026-10-16T08:00:00Z", OWNER)] },
    blobs: BLOBS,
    timeline: { 30: [{ source: { issue: { number: 7900, pull_request: {}, user: LANES_BOT, repository_url: `${API}/repos/${REPO}` } } }] },
    pulls: { 7900: lanePr },
  });
  assert.equal(await sweep({ github: withPr.github, actions: withPr.github }), 0);
  assert.deepEqual(writes(withPr.calls), []);
});

test("a stranded issue's no-report clock starts when its run ended, not when it started", async () => {
  // A run created over 3 hours ago that ended an hour ago: left alone.
  const recent = failedRun({
    runs: [{ ...laneRun({ at: "2026-10-16T08:00:03Z", conclusion: "success" }), updated_at: "2026-10-16T11:00:00Z" }],
    events: [added("2026-10-16T08:00:00Z", OWNER)],
  });
  assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0);
  assert.deepEqual(writes(recent.calls), []);
  const ended = failedRun({
    runs: [{ ...laneRun({ at: "2026-10-16T08:00:03Z", conclusion: "success" }), updated_at: "2026-10-16T08:59:00Z" }],
    events: [added("2026-10-16T08:00:00Z", OWNER)],
  });
  assert.equal(await sweep({ github: ended.github, actions: ended.actions }), 0);
  assert.deepEqual(writes(ended.calls), refiredFor(30, NO_REPORT_CAUSE));
});

test("a stranded issue whose re-fired run failed again is re-fired on a backoff from when it ended, with no needs-human", async () => {
  const { github, actions, calls } = failedRun({
    comments: [note(), refireNote(KEY, "2026-10-16T07:59:59Z")],
    events: [
      added("2026-10-16T07:00:00Z", OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T08:00:00Z" },
      added("2026-10-16T08:00:01Z"),
    ],
    runs: [{ ...laneRun({ at: "2026-10-16T08:00:04Z" }), updated_at: "2026-10-16T08:30:00Z" }],
  });
  // 6 hours after the run ended at 08:30.
  assert.equal(await sweep({ github, actions, now: Date.parse("2026-10-16T14:30:00Z") }), 0);
  const body = infraComment(KEY, "The work-resolve-issue run that `agent-ready` started failed or was cancelled before it reported, over 3 hours ago.", 2);
  assert.deepEqual(writes(calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body })}`, ...restarted(30)]);
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

// Owner Q93: a size split's parent (30) closes as completed, by the App, once
// every sub-issue (31 and 32) is closed by a listed human or a merge; the App
// posted the split record listing them. Only that close by the App counts.
const SPLIT_PARENT_URL = `${API}/repos/${REPO}/issues/30`;
const splitRecordComment = (user = LANES_BOT) => ({
  id: 77,
  user,
  body: `${SIZE_SPLIT_MARKER}\n${renderSplitRecord({ items: "a".repeat(64), parts: [[1], [2]], order: [], filed: [31, 32] })}\nSplit at intake.`,
  created_at: STAMP,
});
const subIssue = (number, overrides = {}) => ({ ...issue(number, { state: "closed" }), parent_issue_url: SPLIT_PARENT_URL, ...overrides });
const closeParentWrites = [
  `POST /repos/${REPO}/issues/30/comments`,
  `PATCH /repos/${REPO}/issues/30 {"state":"closed","state_reason":"completed"}`,
];
function splitWorld({ second = subIssue(32, { closed_by: LANES_BOT, graphCloser: mergedPr({ number: 932 }) }), record = splitRecordComment() } = {}) {
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  return world({
    closedList: [first],
    issues: { 30: issue(30), 31: first, 32: second },
    parents: { 31: issue(30) },
    subIssues: { 30: [first, second] },
    comments: { 30: record === null ? [] : [record] },
  });
}
const writtenPaths = (calls) => writes(calls).map((call) => (call.includes("/comments ") ? call.slice(0, call.indexOf(" {")) : call));

test("the last sub-issue closing by a listed human or a merge closes its split parent as completed, comment first", async () => {
  const { github, calls } = splitWorld();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writtenPaths(calls), closeParentWrites);
  const comment = JSON.parse(writes(calls)[0].slice(writes(calls)[0].indexOf(" {") + 1)).body;
  assert.match(comment, /^<!-- work-unblock split parent closed -->\n/);
  assert.match(comment, /#31, #32/);
});

test("a split parent stays open while a sub-issue is open, or closed by someone else, or with no split record from the App", async () => {
  const outsider = { id: 4242, login: "someone-else", type: "User" };
  for (const setup of [
    { second: subIssue(32, { state: "open", closed_by: null }) },
    { second: subIssue(32, { closed_by: outsider }) },
    { record: null },
    { record: splitRecordComment(outsider) },
  ]) {
    const { github, calls } = splitWorld(setup);
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(setup));
  }
});

test("the App's close of a split parent counts as done for what it blocks; without the split record it does not", async () => {
  for (const [record, expected] of [
    [splitRecordComment(), [labeled(20)]],
    [null, []],
  ]) {
    const parent = issue(30, { state: "closed", closer: LANES_BOT, at: "2026-10-16T11:30:00Z" });
    const { github, calls } = world({
      closedList: [parent],
      blockingOf: { 30: [issue(20)] },
      issues: { 20: issue(20), 30: parent, 31: subIssue(31), 32: subIssue(32) },
      blockedBy: { 20: [parent] },
      subIssues: { 30: [subIssue(31), subIssue(32)] },
      comments: { 20: [note()], 30: record === null ? [] : [record] },
    });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), expected);
  }
});

// main resolves the App as LANES_BOT_LOGIN; the split parent's close and its
// record count under that login, not the default one.
test("with LANES_BOT_LOGIN set, that App's close of a split parent counts as done for what it blocks", async () => {
  const app = { id: LANES_APP_ID, login: "other-lanes[bot]", type: "Bot" };
  const parent = issue(30, { state: "closed", closer: app, at: "2026-10-16T11:30:00Z" });
  const { github, calls } = world({
    closedList: [parent],
    blockingOf: { 30: [issue(20)] },
    issues: { 20: issue(20), 30: parent, 31: subIssue(31), 32: subIssue(32) },
    blockedBy: { 20: [parent] },
    subIssues: { 30: [subIssue(31), subIssue(32)] },
    comments: { 20: [note()], 30: [splitRecordComment(app)] },
  });
  assert.equal(await sweep({ github }, { LANES_BOT_LOGIN: app.login }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});
