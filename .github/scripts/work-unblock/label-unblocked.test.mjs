// Expected values come from the work-unblock lane's rules: when an issue
// closes, each issue it blocked gets `agent-ready` only when every blocker is
// closed as completed, it is open, and it carries no hold label; the label
// alone admits it to resolve-issue. Every fact is
// read from the API when the run starts, never from the event payload. The
// kill switch and a close by any bot sender stop the run before any API call.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ADMIT_MARKER, doneReason, loadRules, REFINE_MARKER, refusalText, renderSplitRecord, SIZE_SPLIT_DONE, SIZE_SPLIT_MARKER, SIZE_SPLIT_PENDING } from "../intake-triage/admit.mjs";
import { parseOutcomeMarker, refsHoldMarker } from "../work-resolve-issue/report-outcome.mjs";
import { createGitHub, GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { createJobLogReader } from "./job-log.mjs";
import { codeDigest } from "./verdict-carry.mjs";
import { ADMISSION_RECORD_MARKER } from "../lib/admission-record.mjs";
import {
  breakerComment,
  budgetLatch,
  checkCloser,
  failedComment,
  heldText,
  lapsedReason,
  failedFor,
  fieldListing,
  main as runMain,
  markReads,
  RECURRENCE_PREFIX,
  recurrenceComment,
  refireComment,
  refsClosedComment,
  refsMergedComment,
  infraComment,
  laneRuns,
  laneSlots,
  sharedLaneRuns,
  skipText,
  UNPARKED_MARKER,
} from "./label-unblocked.mjs";

// The admission comment of a refusal that holds for a person: the refusal,
// then the visible reason line and work-unblock's stop-reason marker.
const heldBody = (reasons, code) => `${ADMIT_MARKER}\n${refusalText(reasons)}\n\nReason: \`${code}\`\n<!-- stop-reason lane=work-unblock reason=${code} -->`;
// The reason decide() gives a security hold (an unlisted author, a gained
// security area).
const DECIDE_SECURITY = "security";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { parseReason } from "../lib/stop-reason.mjs";
import { mirroredStatusOf, OPTION, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../../actions/resolve-config/read-status.fixtures.mjs";
import { DISAGREEMENT_WAIT_MS, statusReader } from "../../actions/resolve-config/read-status.mjs";
import { FIELD_API, statusWriter } from "../../actions/resolve-config/write-status.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TRUSTED = join(HERE, "fixtures/trusted-actors.json");
const API = "https://api.github.com";
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const SECOND = { id: 2001, login: "second-maintainer" };
const LANES_APP_ID = 337595936;
const STAMP = "2026-10-16T12:00:00Z";
const RUN_ID = "39500000088";

// This run's own record, the one read a close run makes with the job token:
// who started this attempt (`rerunner`), with `record` laid over it.
function ownRun(rerunner = OWNER, record = {}) {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (method === "GET" && path === `/repos/${REPO}/actions/runs/${RUN_ID}`) {
      return { id: Number(RUN_ID), run_attempt: 1, triggering_actor: rerunner, ...record };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return Object.assign(actions, { calls });
}

// A close run reads who started it from its own record; unless a test passes
// its own `actions`, a listed human did.
// Each world records its Work status writes among its calls (world().writer),
// and a restart clears the Work status field STATUS_CONFIG names, unless a
// test passes its own.
const withWriter = (args) => ({ ...args, writer: args.writer ?? args.github?.writer, statusField: args.statusField ?? { field: STATUS_CONFIG["field-id"] } });
const main = (args) => runMain(withWriter(args.env.GITHUB_EVENT_NAME === "schedule" || "actions" in args ? args : { ...args, actions: ownRun() }));

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
// `queuedIssues` are the numbers check-wip-cap's open agent-ready listing answers,
// `deferred` what the open admission-deferred listing answers, and `ready`
// then `openIssues` what the sweep's open-issue listing answers.
// `blobs` maps a path to its blob SHA on main. `done` maps an issue to what
// admit.mjs's merged-Refs batch read answers for it.
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
  ready = [],
  openIssues = [],
  searchIncomplete = false,
  fieldValues = {},
  specs = {},
  parents = {},
  subIssues = {},
  done = {},
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
      // The sweep's one open-issue listing, for the parent rescan and readmitReady.
      if (!params.has("labels") && params.get("state") === "open") {
        assert.equal(`${params.get("sort")} ${params.get("direction")}`, "updated asc");
        return listed([...ready, ...openIssues]);
      }
      // check-wip-cap's queued read, oldest first.
      if (params.get("labels") === "agent-ready" && params.get("sort") === "created") {
        assert.equal(params.get("state"), "open");
        assert.equal(params.get("direction"), "asc");
        return queuedIssues.map((number) => ({ number })).slice((page - 1) * 100, page * 100);
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
      // The lanes App is whichever LANES_BOT_LOGIN names, so any App author.
      if (new RegExp(`^repo:${REPO} is:pr is:open author:app/[\\w-]+$`).test(q)) {
        if (openLanePrs === null) {
          throw new Error(`${method} ${path} failed with status 403`);
        }
        const open = Array.from({ length: openLanePrs }, () => ({ labels: [], body: "", created_at: STAMP }));
        return { total_count: openLanePrs, incomplete_results: false, items: open.slice((page - 1) * 100, page * 100) };
      }
      assert.match(q, /^repo:\S+ is:pr (is:merged )?author:app\/[\w-]+ (merged|created):>=\S+$/);
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
    if (method === "POST" && route.match(/\/issues\/\d+\/comments$/) && String(body?.body).startsWith(ADMISSION_RECORD_MARKER)) {
      return {};
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
    if (method === "DELETE" && route.match(/\/issues\/(\d+)\/labels\/(agent-ready|needs-human|admission-deferred|status%3A%20ready|status%3A%20confirmed|needs-owner-decision|needs-reporter-info|host-run)$/)) {
      return [];
    }
    if (method === "DELETE" && route.match(/\/issues\/(\d+)\/issue-field-values\/\d+$/)) {
      assert.deepEqual(headers, FIELD_API);
      return null;
    }
    const lookup = (number) =>
      issues[number] ??
      closedList.find((item) => String(item.number) === number) ??
      Object.values(blockedBy)
        .flat()
        .find((item) => String(item.number) === number && item.repository_url === `${API}/repos/${REPO}`);
    // admit.mjs mergedRefsPulls: one aliased issue per number asked.
    if (method === "POST" && route === "/graphql" && body.query.includes("fragment done on Issue")) {
      const asked = [...body.query.matchAll(/\bi(\d+): issue\(number: \1\)/g)].map((m) => m[1]);
      return { data: { repository: Object.fromEntries(asked.map((n) => [`i${n}`, done[n] ?? null])) } };
    }
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
    // admit()'s one read of the issue text for the admission record.
    if (method === "GET" && (match = route.match(new RegExp(`^${base}/(\\d+)$`)))) {
      return { ...issue(Number(match[1])), title: `Issue ${match[1]}`, body: "The issue text." };
    }
    // admit.mjs admissionFacts' visibility read: a private repository.
    if (method === "GET" && route === `/repos/${REPO}`) {
      return { visibility: "private" };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  // The issue's Work status reads agent-ready: its field row when the fixture
  // has one, else the agent-ready label on any fixture copy of the issue.
  const readsAgentReady = (number) => {
    const row = (fieldValues[number] ?? []).find((item) => String(item.issue_field_id) === String(STATUS_CONFIG["field-id"]));
    if (row) {
      return row.single_select_option?.id === OPTION["agent-ready"];
    }
    const copies = [issues[number], ...closedList, ...openReady, ...ready, ...openIssues, ...deferred].filter((item) => String(item?.number) === String(number));
    return copies.some((item) => (item.labels ?? []).some((label) => (label?.name ?? label) === "agent-ready"));
  };
  // A Work status writer (write-status.mjs statusWriter) that records each
  // call among the client's, in order; leaveAgentReady only for an issue
  // whose Work status reads agent-ready, as the real writer writes.
  const writer = {
    set: async (number, state) => calls.push(`SET ${number} ${state}`),
    leaveAgentReady: async (number, state) => readsAgentReady(number) && calls.push(`LEAVE ${number} ${state}`),
    restart: async (number) => calls.push(`RESTART ${number}`),
  };
  return { github: Object.assign(github, { writer }), calls, writer };
}

function envFor(event = {}, extra = {}) {
  const dir = tempDir("work-unblock-");
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
    GITHUB_RUN_ID: RUN_ID,
    GITHUB_RUN_ATTEMPT: "1",
    ...extra,
  };
}

// The GraphQL closer read is a POST but writes nothing.
const isRecordPost = (call) => /^POST \S+\/issues\/\d+\/comments /.test(call) && call.includes(`"body":${JSON.stringify(ADMISSION_RECORD_MARKER).slice(0, -1)}`);
// The admission record POST has its own test below, so it is not a write here.
const writes = (calls) => calls.filter((call) => !call.startsWith("GET ") && !call.startsWith("POST /graphql ") && !isRecordPost(call));
const closerReads = (calls, number) =>
  calls.filter((call) => call.startsWith("POST /graphql ") && call.includes(`"number":${number}`)).length;
const labeled = (n) => `SET ${n} agent-ready`;

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

test("an admission posts its record before the agent-ready write, and a failed record post admits nothing", async () => {
  const recordAt = (calls) => calls.findIndex(isRecordPost);
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.equal(calls.filter(isRecordPost).length, 1, "one record post");
  assert.ok(calls.some((call) => call === `GET /repos/${REPO}/issues/20`), "the issue text is read");
  assert.ok(recordAt(calls) >= 0 && recordAt(calls) < calls.indexOf(labeled(20)), "the record precedes the agent-ready write");

  const failOn = (method, path, body) => method === "POST" && path.endsWith("/issues/20/comments") && String(body?.body).startsWith(ADMISSION_RECORD_MARKER);
  const broken = world({ ...oneDependentWorld(), failOn });
  assert.notEqual(await main({ env: envFor(), github: broken.github }), 0, "the failed post fails the run");
  assert.ok(broken.calls.some(isRecordPost), "the record post was attempted");
  assert.ok(!broken.calls.includes(labeled(20)), "no agent-ready write after a failed record");
});

test("the last blocker closing sets the Work status field to agent-ready and writes no agent-ready label", async () => {
  const { github, calls, writer } = oneDependent();
  assert.equal(await main({ env: envFor(), github, writer }), 0);
  assert.deepEqual(writes(calls), ["SET 20 agent-ready"]);
  assert.ok(!calls.some((call) => call.includes("/labels")), "no label write");
});

test("the last blocker closing leaves an umbrella with an open sub-issue unlabeled, and labels it once none is open", async () => {
  const umbrella = (subs) =>
    world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [note()] },
      subIssues: { 20: subs },
    });
  const open = umbrella([issue(31), issue(32, { state: "closed" })]);
  assert.equal(await main({ env: envFor(), github: open.github }), 0);
  assert.deepEqual(writes(open.calls), []);
  const drained = umbrella([issue(31, { state: "closed" })]);
  assert.equal(await main({ env: envFor(), github: drained.github }), 0);
  assert.deepEqual(writes(drained.calls), [labeled(20)]);
});

// The close path strips the closed issue's host-run label, read fresh from
// the API, so a hand-closed issue leaves the host queue. Its queue and status
// labels stay: the Work status field carries that state. Number 10 blocks
// nothing here.
const closedSelf = (labels, extra = {}) => world({ blocking: [], issues: { 10: { ...issue(10, { state: "closed", labels }), ...extra } } });
const unlabeled = (name) => `DELETE /repos/${REPO}/issues/10/labels/${encodeURIComponent(name)}`;

test("a closed issue keeps its queue labels and loses host-run", async () => {
  const { github, calls } = closedSelf(["priority: high", "agent-ready", "status: ready", "work-class: scoped"]);
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), ["LEAVE 10 needs-triage"], "no queue-label write; the Work status leaves agent-ready");
  const deferred = closedSelf(["admission-deferred", "status: ready", "host-run"]);
  assert.equal(await main({ env: envFor(), github: deferred.github }), 0);
  assert.deepEqual(writes(deferred.calls), [unlabeled("host-run")]);
});

test("a closed issue loses host-run alone, and keeps its status labels and attended", async () => {
  const { github, calls } = closedSelf(["status: confirmed", "host-run", "attended", "agent-ready", "needs-owner-decision", "needs-reporter-info"]);
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [unlabeled("host-run"), "LEAVE 10 needs-triage"]);
});

test("a closed issue with no queue label gets no write", async () => {
  const { github, calls } = closedSelf(["priority: high", "bug"]);
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(calls.includes(`GET /repos/${REPO}/issues/10`));
});

test("a host-run label already gone (404) counts as removed", async () => {
  const { github: inner, calls } = closedSelf(["agent-ready", "host-run"]);
  const github = async (method, path, body) => {
    if (method === "DELETE" && path.endsWith("/issues/10/labels/host-run")) {
      calls.push(`${method} ${path}`);
      throw Object.assign(new Error("DELETE failed with status 404"), { status: 404 });
    }
    return inner(method, path, body);
  };
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [unlabeled("host-run")]);
});

test("a failed host-run removal fails the run", async (t) => {
  const { github: inner, calls } = closedSelf(["agent-ready", "host-run"]);
  const github = async (method, path, body) => {
    if (method === "DELETE" && path.endsWith("/issues/10/labels/host-run")) {
      calls.push(`${method} ${path}`);
      throw Object.assign(new Error("DELETE failed with status 502"), { status: 502 });
    }
    return inner(method, path, body);
  };
  const log = t.mock.method(console, "log", () => {});
  assert.equal(await main({ env: envFor(), github }), 1);
  log.mock.restore();
  assert.deepEqual(writes(calls), [unlabeled("host-run")]);
});

test("an issue open again when the run reads it keeps its queue labels", async () => {
  const { github, calls } = world({ blocking: [], issues: { 10: issue(10, { labels: ["agent-ready", "status: ready"] }) } });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a post-merge fix issue keeps agent-ready across its close, for its reopen on a repeat failure", async () => {
  const alert = { login: "github-actions[bot]", type: "Bot" };
  const body = "<!-- post-merge-fix check=pr-require-checks / test -->\nFix main.";
  const fix = closedSelf(["agent-ready", "status: ready", "host-run"], { user: alert, body });
  assert.equal(await main({ env: envFor(), github: fix.github }), 0);
  assert.deepEqual(writes(fix.calls), []);
  // The same body from another author, or another body from the alert, is stripped.
  for (const extra of [{ user: OWNER, body }, { user: alert, body: "Fix main." }]) {
    const other = closedSelf(["agent-ready", "host-run"], extra);
    assert.equal(await main({ env: envFor(), github: other.github }), 0);
    assert.deepEqual(writes(other.calls), [unlabeled("host-run"), "LEAVE 10 needs-triage"], JSON.stringify(extra));
  }
});

// A reopen fires no field change, so a closed issue left at Work status
// agent-ready would read as queued work with no run behind it.
test("a closed issue whose Work status is agent-ready moves to needs-triage; a reopened one and a post-merge fix issue do not", async () => {
  const agentReady = { 10: [{ issue_field_id: STATUS_CONFIG["field-id"], single_select_option: { id: OPTION["agent-ready"] } }] };
  const closed = world({ blocking: [], issues: { 10: issue(10, { state: "closed" }) }, fieldValues: agentReady });
  assert.equal(await main({ env: envFor(), github: closed.github }), 0);
  assert.deepEqual(writes(closed.calls), ["LEAVE 10 needs-triage"], "a closed agent-ready issue leaves agent-ready");
  const reopened = world({ blocking: [], issues: { 10: issue(10) }, fieldValues: agentReady });
  assert.equal(await main({ env: envFor(), github: reopened.github }), 0);
  assert.deepEqual(writes(reopened.calls), [], "an issue open again keeps its Work status");
  const alert = { login: "github-actions[bot]", type: "Bot" };
  const fix = world({
    blocking: [],
    issues: { 10: { ...issue(10, { state: "closed" }), user: alert, body: "<!-- post-merge-fix check=pr-require-checks / test -->\nFix main." } },
    fieldValues: agentReady,
  });
  assert.equal(await main({ env: envFor(), github: fix.github }), 0);
  assert.deepEqual(writes(fix.calls), [], "a post-merge fix issue keeps agent-ready for its reopen");
});

test("an issue held by needs-owner-decision, needs-reporter-info, needs-human, untrusted-provenance or attended stays unlabeled", async () => {
  for (const hold of ["needs-owner-decision", "needs-reporter-info", "needs-human", "provenance: untrusted", "attended"]) {
    const { github, calls } = oneDependent({ labels: [hold] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], hold);
  }
});

// The Work status field a trusted account set (read-status.mjs): with a status
// label on the issue it only adds a hold; with none it decides; unset, the labels decide.
const withStatus = (world, fields) => {
  const github = withFields(world.github, fields);
  return { github: Object.assign(github, { writer: world.github.writer }), statusOf: statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }) };
};

test("a field that mirrors the labels changes no promotion", async () => {
  const sets = [[], ["needs-owner-decision"], ["needs-reporter-info"], ["needs-human"], ["provenance: untrusted"], ["attended"], ["agent-ready"], ["status: ready"], ["needs-spec"], ["Needs-Human"], ["work-class: scoped"]];
  for (const labels of sets) {
    const byLabels = oneDependent({ labels });
    assert.equal(await main({ env: envFor(), github: byLabels.github }), 0);
    const mirrored = oneDependent({ labels });
    assert.equal(await main({ env: envFor(), github: mirrored.github, statusOf: mirroredStatusOf }), 0);
    assert.deepEqual(writes(mirrored.calls), writes(byLabels.calls), JSON.stringify(labels));
  }
});

test("a hold in the Work status field the labels lack stops the promotion", async () => {
  for (const labels of [[], ["status: ready"]]) {
    const held = oneDependent({ labels });
    assert.equal(await main({ env: envFor(), ...withStatus(held, { 20: { state: "needs-human" } }) }), 0);
    assert.deepEqual(writes(held.calls), [], JSON.stringify(labels));
  }
});

test("the Work status field decides an issue with no status label; a field agent-ready gets no agent-ready label re-added", async () => {
  // Parked at confirmed with no admission comment: it stays parked, unlabeled.
  const parked = oneDependent({ labels: [] });
  assert.equal(await main({ env: envFor(), ...withStatus(parked, { 20: { state: "confirmed" } }), writer: parked.writer, admission: admissionFor() }), 0);
  assert.deepEqual(writes(parked.calls), []);
  const ready = oneDependent({ labels: [] });
  assert.equal(await main({ env: envFor(), ...withStatus(ready, { 20: { state: "agent-ready" } }), writer: ready.writer }), 0);
  // The field already reads agent-ready (read-status folds it in), so the
  // issue is admitted and nothing is written again.
  assert.deepEqual(writes(ready.calls), []);
  assert.ok(!ready.calls.some((call) => call.includes("/labels")), "no agent-ready label re-add");
});

test("a Work status read that fails admits nothing for that issue: a warning, no write, a green run", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const failed = oneDependent({ labels: [] });
  assert.equal(await main({ env: envFor(), ...withStatus(failed, { 20: new Error("GET failed with status 500") }), writer: failed.writer }), 0);
  assert.deepEqual(writes(failed.calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.some((line) => line.startsWith("::warning title=label-unblocked::#20: #20's Work status could not be read") && line.endsWith("not admitted or lifted this run")), lines.join("\n"));
});

test("the labels decide a hold when the Work status field is unset, set by another account, or names a ready state", async () => {
  for (const fields of [{}, { 20: { state: "ready", setter: STRANGER_ID } }, { 20: { state: "ready" } }]) {
    const { github, calls } = oneDependent({ labels: ["needs-human"] });
    assert.equal(await main({ env: envFor(), ...withStatus({ github }, fields) }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(fields));
  }
  const free = oneDependent({ labels: [] });
  assert.equal(await main({ env: envFor(), ...withStatus(free, {}) }), 0);
  assert.deepEqual(writes(free.calls), [labeled(20)]);
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
// human, by id, so anyone else stops the run quietly, before any issue read
// (and, in the workflow, before the token request, through --check-closer).
// The re-runner's id comes from this run's own record, never a login.
const IMPOSTOR = { id: 999001, login: OWNER.login };
test("a closer or re-runner who is not a listed human stops the run before any issue read", async () => {
  for (const [id, rerunner] of [
    // An unlisted closer, re-run by nobody else.
    ["1234", { id: 1234, login: "someone-else" }],
    // An unlisted closer, re-run by a listed human.
    ["1234", OWNER],
    // A listed bot is not a listed human, as closer or as re-runner.
    [String(LANES_APP_ID), { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]" }],
    [String(OWNER.id), { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]" }],
    // An unlisted re-runner, and one holding a listed human's login.
    [String(OWNER.id), { id: 1234, login: "someone-else" }],
    [String(OWNER.id), IMPOSTOR],
    ["", OWNER],
  ]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { ACTOR_ID: id }), github, actions: ownRun(rerunner) }), 0);
    assert.deepEqual(calls, [], `${id} ${rerunner.id}`);
  }
});

test("a re-run by a different listed human labels the unblocked issues", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor(), github, actions: ownRun(SECOND) }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("the closer check answers proceed only when the closer and the re-runner are each a listed human, by id", async () => {
  const env = (id) => ({ ACTOR_ID: id, TRUSTED_ACTORS_PATH: TRUSTED, GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: RUN_ID, GITHUB_RUN_ATTEMPT: "1" });
  const check = (id, rerunner) => checkCloser(env(id), ownRun(rerunner));
  assert.equal(await check(String(OWNER.id), OWNER), true);
  assert.equal(await check(String(OWNER.id), SECOND), true);
  assert.equal(await check(String(SECOND.id), OWNER), true);
  assert.equal(await check("1234", { id: 1234, login: "someone-else" }), false);
  assert.equal(await check("1234", OWNER), false);
  assert.equal(await check(String(LANES_APP_ID), { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]" }), false);
  assert.equal(await check(String(OWNER.id), { id: 209825114, login: "claude[bot]" }), false);
  assert.equal(await check(String(OWNER.id), { id: 1234, login: "someone-else" }), false);
  assert.equal(await check("x", OWNER), false);
});

test("a listed human's login held by a different id is not that human: the closer check answers no", async () => {
  // TRIGGERING_ACTOR is the login the runner would pass; it is never read.
  const actions = ownRun(IMPOSTOR);
  const env = { ACTOR_ID: String(OWNER.id), TRIGGERING_ACTOR: OWNER.login, TRUSTED_ACTORS_PATH: TRUSTED, GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: RUN_ID, GITHUB_RUN_ATTEMPT: "1" };
  assert.equal(await checkCloser(env, actions), false);
  assert.deepEqual(actions.calls, [`GET /repos/${REPO}/actions/runs/${RUN_ID}`]);
});

test("a failed or malformed read of this run's record answers no, and a close run stops before any issue read", async () => {
  // A listed login in both triggering-actor variables: a login fallback on a failed read would admit.
  const logins = { GITHUB_TRIGGERING_ACTOR: OWNER.login, TRIGGERING_ACTOR: OWNER.login };
  const failing = Object.assign(async () => {
    throw new Error("HTTP 502");
  }, { calls: [] });
  for (const [name, actions, extra] of [
    ["failed read", failing, {}],
    ["string id", ownRun({ id: String(OWNER.id), login: OWNER.login }), {}],
    ["no triggering actor", ownRun(null), {}],
    ["another attempt's record", ownRun(OWNER, { run_attempt: 2 }), {}],
    ["another run's record", ownRun(OWNER, { id: 1 }), {}],
    ["no run attempt", ownRun(), { GITHUB_RUN_ATTEMPT: "" }],
    ["no run id", ownRun(), { GITHUB_RUN_ID: "" }],
    ["no repository", ownRun(), { GITHUB_REPOSITORY: "" }],
  ]) {
    const env = { ACTOR_ID: String(OWNER.id), TRUSTED_ACTORS_PATH: TRUSTED, GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: RUN_ID, GITHUB_RUN_ATTEMPT: "1", ...logins, ...extra };
    assert.equal(await checkCloser(env, actions), false, name);
    // main itself fails red on a malformed repository, before the check.
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { ...logins, ...extra }), github, actions }), name === "no repository" ? 1 : 0, name);
    assert.deepEqual(calls, [], name);
  }
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
  for (const [event, name] of [[{ action: "reopened" }, "issues"], [{}, "pull_request"], [{}, "repository_dispatch"]]) {
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
      ...extra,
    }),
    // A job's log goes through the same fake as every other read.
    jobLog: args.actions ? (repo, id, options) => args.actions("GET", `/repos/${repo}/actions/jobs/${id}/logs`, undefined, {}, options) : undefined,
    // A fixed 3 slots, so a SLOTS change in work-resolve-issue.yml does not move these expectations.
    slots: () => 3,
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

// A merge the App ran closes an issue with no close run, so the sweep strips
// host-run from each issue in its window a listed human or a merge closed.
test("the sweep strips host-run, not the queue labels, from a merge-closed issue, and writes nothing for one without it", async () => {
  const mergeClosed = (labels) => ({ ...closedAt(10, "2026-10-16T11:30:00Z"), labels: labels.map((name) => ({ name })) });
  const labeled = world({ closedList: [mergeClosed(["agent-ready", "status: ready", "host-run", "priority: low"])], blocking: [] });
  assert.equal(await sweep({ github: labeled.github }), 0);
  assert.deepEqual(writes(labeled.calls), [`DELETE /repos/${REPO}/issues/10/labels/host-run`, "LEAVE 10 needs-triage"]);
  // The strip reuses the close check's read: one GET of the issue in all.
  assert.equal(labeled.calls.filter((call) => call === `GET /repos/${REPO}/issues/10`).length, 1, labeled.calls.join("\n"));
  const bare = world({ closedList: [mergeClosed(["priority: low"])], blocking: [] });
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), []);
  // A close by neither a listed human nor a merge is left alone.
  const outsider = world({ closedList: [{ ...mergeClosed(["agent-ready"]), graphCloser: null }], blocking: [] });
  assert.equal(await sweep({ github: outsider.github }), 0);
  assert.deepEqual(writes(outsider.calls), []);
});

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

// A finished work-resolve-issue run sweeps as the schedule does. Its payload,
// sent by the lanes App, is never read, so the bot-close skip and the closer
// check do not apply.
test("a finished work-resolve-issue run sweeps like the schedule, past a bot sender and with no closer check", async () => {
  const { github, calls } = sweptDependent();
  const actionCalls = [];
  const actions = async (method, path) => {
    actionCalls.push(`${method} ${path}`);
    return { workflow_runs: [], jobs: [] };
  };
  const env = envFor({ action: "completed", issue: undefined, sender: LANES_BOT, workflow_run: { name: "work-resolve-issue" } }, { GITHUB_EVENT_NAME: "workflow_run" });
  assert.equal(await main({ now: NOW, env, github, actions }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(
    calls.includes(
      `GET /repos/${REPO}/issues?state=closed&since=${encodeURIComponent(SINCE)}&sort=updated&direction=desc&per_page=100&page=1`,
    ),
  );
  assert.ok(!actionCalls.includes(`GET /repos/${REPO}/actions/runs/${RUN_ID}`), actionCalls.join("\n"));
});

test("an event other than an issue close, the schedule or a work-resolve-issue run fails before any API call", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = sweptDependent();
  assert.equal(await main({ now: NOW, env: envFor({}, { GITHUB_EVENT_NAME: "push" }), github }), 1);
  assert.deepEqual(calls, []);
});

// The window starts 15 minutes before the last successful scheduled run of
// work-unblock.yml whose label-unblocked job ran its sweep step and logged that
// it read the closed-issue listing, at most 3 hours back; anything else, or any
// failed read, gives the 3 hours.
const SWEEP_RUNS = `/repos/${REPO}/actions/workflows/work-unblock.yml/runs?event=schedule&status=success&per_page=3`;
const ago = (minutes) => new Date(NOW - minutes * 60_000).toISOString();
const SWEEP_JOB_ID = 9001;
const SWEEP_LOG_PATH = `/repos/${REPO}/actions/jobs/${SWEEP_JOB_ID}/logs`;
// A raw job log's line: the runner's stamp, one space, the line as printed.
const LOG_STAMP = "2026-11-04T06:49:16.3392052Z ";
const LISTED_LOG = `${LOG_STAMP}label-unblocked: read the closed-issue listing\n`;
const sweptJobs = (conclusion = "success", extraSteps = []) => ({
  jobs: [
    { name: "save-wip-state", conclusion: "success", steps: [{ name: "Save the WIP cap's last known state", conclusion: "success" }] },
    {
      id: SWEEP_JOB_ID,
      name: "label-unblocked",
      conclusion: "success",
      steps: [{ name: "Check the kill switch", conclusion: "success" }, ...extraSteps, { name: "Label the unblocked issues", conclusion }],
    },
  ],
});
async function windowOf(answer, extra = {}, jobs = sweptJobs(), log = LISTED_LOG) {
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
    if (path === SWEEP_LOG_PATH) {
      if (log instanceof Error) {
        throw log;
      }
      return log;
    }
    return { workflow_runs: [], jobs: [] };
  };
  assert.equal(await sweep({ github, actions }, extra), 0);
  const listing = calls.find((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed&since=`));
  const since = Date.parse(decodeURIComponent(/since=([^&]+)/.exec(listing)[1]));
  return { minutes: (NOW - since) / 60_000, actionCalls };
}

test("the sweep reads back to 15 minutes before the last sweep that ran its labeling step and read its listing", async () => {
  const { minutes, actionCalls } = await windowOf({ workflow_runs: [{ id: 5, run_started_at: ago(60) }] });
  assert.equal(minutes, 75);
  const windowCalls = actionCalls.filter((call) => call.includes("/work-unblock.yml/") || call.includes("/actions/runs/5/") || call.includes("/actions/jobs/"));
  assert.deepEqual(windowCalls, [`GET ${SWEEP_RUNS}`, `GET /repos/${REPO}/actions/runs/5/jobs?filter=latest&per_page=100`, `GET ${SWEEP_LOG_PATH}`]);
});

// A hold ends green with its labeling step a success, so only the log tells a
// sweep that read its closes from one that held. Any run that is not a clean
// sweep, or a read that fails, falls back to 6 hours (PACED_LOOKBACK_HOURS):
// it may follow a paced run whose clean sweep is past 3 hours.
test("a last sweep whose log does not show the closed listing read falls back to 6 hours", async () => {
  const runs = { workflow_runs: [{ id: 5, run_started_at: ago(60) }] };
  const held = `${LOG_STAMP}##[notice]the closed-issue listing failed\n`;
  const inside = `${LOG_STAMP}said label-unblocked: read the closed-issue listing\n`;
  const unstamped = "label-unblocked: read the closed-issue listing\n";
  for (const log of [held, inside, unstamped, "", new Error("GET failed with status 410")]) {
    assert.equal((await windowOf(runs, {}, sweptJobs(), log)).minutes, 360, String(log));
  }
});

test("a last sweep whose job has no usable id falls back to 6 hours without asking for a log", async () => {
  const runs = { workflow_runs: [{ id: 5, run_started_at: ago(60) }] };
  const steps = [{ name: "Label the unblocked issues", conclusion: "success" }];
  for (const id of [undefined, "../9001"]) {
    const { minutes, actionCalls } = await windowOf(runs, {}, { jobs: [{ id, name: "label-unblocked", conclusion: "success", steps }] });
    assert.equal(minutes, 360);
    assert.deepEqual(actionCalls.filter((call) => call.includes("/actions/jobs/")), []);
  }
});

test("a sweep with an Actions client but no log reader reads the full 6 hours", async () => {
  const { github, calls } = sweptDependent();
  const actions = async (method, path) => (path.includes("/work-unblock.yml/") ? { workflow_runs: [{ id: 5, run_started_at: ago(60) }] } : sweptJobs());
  assert.equal(await sweep({ github, actions, jobLog: null }), 0);
  assert.ok(calls.some((call) => call.includes(`since=${encodeURIComponent("2026-10-16T06:00:00.000Z")}`)));
});

test("a last sweep's log past the 1 MiB read cap is left unread and gives the full 6 hours", async () => {
  // Real reader: one byte over the cap, the listed line inside it.
  const readerOf = (filler) => {
    const fetchImpl = async () => new Response(LISTED_LOG + "x".repeat(filler - LISTED_LOG.length), { status: 200 });
    return createJobLogReader({ token: "t", apiUrl: "https://api.example", fetchImpl, latch: budgetLatch("github-token") });
  };
  const since = async (jobLog) => {
    const { github, calls } = sweptDependent();
    assert.equal(await sweep({ github, actions: lastSweepActions, jobLog }), 0);
    return Date.parse(decodeURIComponent(/since=([^&]+)/.exec(calls.find((call) => call.includes("issues?state=closed&since=")))[1]));
  };
  assert.equal(await since(readerOf(1_048_576)), NOW - 75 * 60_000);
  assert.equal(await since(readerOf(1_048_577)), NOW - 360 * 60_000);
});

// What one sweep printed, as its raw job log shows it: the runner turns a
// notice command into `##[notice]`.
const rawLog = (lines) => `${lines.map((line) => LOG_STAMP + line.replace(/^::notice[^:]*::/, "##[notice]")).join("\n")}\n`;
const HOUR = 3_600_000;
// The next hourly sweep after one that started at `started` and printed
// `lines`, finding what the `world` it is given holds; its exit code, and how
// many minutes back the listing it sent reads.
async function sweepAfter(lines, { github, calls }, started = NOW) {
  const now = started + HOUR;
  const actions = async (method, path) => {
    if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs`)) {
      return { workflow_runs: [{ id: 6, run_started_at: new Date(started).toISOString() }] };
    }
    if (path.startsWith(`/repos/${REPO}/actions/runs/6/jobs`)) {
      return sweptJobs();
    }
    if (path === SWEEP_LOG_PATH) {
      return rawLog(lines);
    }
    return { workflow_runs: [], jobs: [] };
  };
  const code = await sweep({ github, actions, now });
  const listing = calls.find((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed&since=`));
  return { code, minutes: (now - Date.parse(decodeURIComponent(/since=([^&]+)/.exec(listing)[1]))) / 60_000 };
}
const printedBy = async (t, run) => {
  const log = t.mock.method(console, "log", () => {});
  const code = await run();
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  log.mock.restore();
  return { code, lines };
};
const CLOSED_LISTING = `/repos/${REPO}/issues?state=closed`;
const LAST_SWEEP = { workflow_runs: [{ id: 5, run_started_at: ago(60) }] };
const lastSweepActions = async (method, path) => {
  if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs`)) {
    return LAST_SWEEP;
  }
  if (path.startsWith(`/repos/${REPO}/actions/runs/5/jobs`)) {
    return sweptJobs();
  }
  return path === SWEEP_LOG_PATH ? LISTED_LOG : { workflow_runs: [], jobs: [] };
};

test("a failed closed listing holds green: a notice, no error, no write and no later read", async (t) => {
  const { github, calls } = world({ closedList: [closedAt(10, "2026-10-16T11:30:00Z")], failOn: CLOSED_LISTING });
  const { code, lines } = await printedBy(t, () => sweep({ github }));
  assert.equal(code, 0);
  assert.deepEqual(writes(calls), []);
  assert.deepEqual(calls.filter((call) => !call.startsWith(`GET ${CLOSED_LISTING}`)), []);
  assert.equal(lines.filter((line) => line.startsWith("::notice") && line.includes("closed-issue listing")).length, 1);
  assert.deepEqual(lines.filter((line) => line.startsWith("::error")), []);
});

test("a closed listing that answers no list, or past its page cap, holds like a failed one", async (t) => {
  const answers = [{ message: "not a list" }, Array.from({ length: 100 }, () => closedAt(10, "2026-10-16T11:30:00Z"))];
  for (const answer of answers) {
    const { github: base, calls } = world({});
    const github = async (method, path, body) => (path.startsWith(CLOSED_LISTING) ? answer : base(method, path, body));
    const { code, lines } = await printedBy(t, () => sweep({ github }));
    assert.equal(code, 0);
    assert.deepEqual(writes(calls), []);
    assert.equal(lines.filter((line) => line.startsWith("::notice") && line.includes("closed-issue listing")).length, 1);
  }
});

// The close at 11:30 is after the last good sweep's 10:45 start of window and
// before 11:45, 15 minutes before the held sweep at 12:00. A next sweep that
// started from the held one would never read it.
test("a held sweep does not advance the window: the next sweep reads the close it missed and labels what it freed", async (t) => {
  const held = world({ closedList: [closedAt(10, "2026-10-16T11:30:00Z")], failOn: CLOSED_LISTING });
  const { code, lines } = await printedBy(t, () => sweep({ github: held.github, actions: lastSweepActions }));
  assert.equal(code, 0);
  const next = sweptDependent();
  const after = await sweepAfter(lines, next);
  assert.equal(after.code, 0);
  assert.equal(after.minutes, 360);
  assert.deepEqual(writes(next.calls), [labeled(20)]);
});

test("a sweep that read its listing does advance the window: the next one reads back to 15 minutes before it", async (t) => {
  const { github } = sweptDependent();
  const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
  assert.equal(code, 0);
  const next = sweptDependent();
  const after = await sweepAfter(lines, next);
  assert.equal(after.minutes, 75);
  // The close at 11:30 is before 11:45, so this sweep does not read it.
  assert.deepEqual(writes(next.calls), []);
});

// Held at 12:00 and 13:00: the sweep at 14:00 still reads back 6 hours, to
// 08:00, which covers the close at 11:30 neither held sweep read.
test("sweeps held in a row keep the window back, up to the 6-hour limit", async (t) => {
  const first = await printedBy(t, () => sweep({ github: world({ failOn: CLOSED_LISTING }).github, actions: lastSweepActions }));
  const heldAgain = world({ failOn: CLOSED_LISTING });
  const second = await printedBy(t, () => sweepAfter(first.lines, heldAgain));
  assert.equal(second.code.code, 0);
  assert.equal(second.code.minutes, 360);
  const next = sweptDependent();
  const after = await sweepAfter(second.lines, next, NOW + HOUR);
  assert.equal(after.minutes, 360);
  assert.deepEqual(writes(next.calls), [labeled(20)]);
});

// These listings are read whole on every sweep, so a failure loses nothing:
// the closes were read, and the window advances.
test("a failed listing of the deferred, open or agent-ready issues holds with a notice while the rest of the sweep runs", async (t) => {
  const listings = [
    [`/repos/${REPO}/issues?state=open&labels=admission-deferred`, "admission-deferred"],
    [`/repos/${REPO}/issues?state=open&sort=updated`, "open"],
    [`/repos/${REPO}/issues?state=open&labels=agent-ready`, "agent-ready"],
  ];
  for (const [failOn, what] of listings) {
    const { github, calls } = world({
      closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed" })] },
      comments: { 20: [note()] },
      failOn,
    });
    const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
    assert.equal(code, 0, what);
    assert.deepEqual(writes(calls), [labeled(20)], what);
    assert.equal(lines.filter((line) => line.startsWith("::notice") && line.includes(`${what} listing`)).length, 1, what);
    assert.deepEqual(lines.filter((line) => line.startsWith("::error")), [], what);
    const next = sweptDependent();
    assert.equal((await sweepAfter(lines, next)).minutes, 75, what);
  }
});

// Numbers 20 and 21 are each blocked by number 10 alone, which a merge closed
// in the window, and decided in that order; `fault(method, path, body)` is
// what a read or write throws, or null.
function twoDependents(fault) {
  const base = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
    blocking: [issue(20), issue(21)],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 20: [issue(10, { state: "closed" })], 21: [issue(10, { state: "closed" })] },
    comments: { 20: [note()], 21: [note()] },
  });
  const github = async (method, path, body, ...rest) => {
    const error = fault(method, path, body);
    if (error) {
      base.calls.push(`${method} ${path}`);
      throw error;
    }
    return base.github(method, path, body, ...rest);
  };
  return { github: Object.assign(github, { writer: base.writer }), calls: base.calls };
}
const ISSUE_20 = `/repos/${REPO}/issues/20`;
const readOf20 = (error) => (method, path) => (method === "GET" && path === ISSUE_20 ? error : null);

// A 5xx or 429, a rate-guard stop or no answer on one issue's read is no
// verdict on that issue (outage posture element 2): it is held with a notice,
// the run stays green, and the other issues are still decided.
test("a GitHub fault on one issue's read holds that issue with a notice, labels the others and exits 0", async (t) => {
  const faults = [
    new GitHubError(503, `GET ${ISSUE_20}`),
    new GitHubError(429, `GET ${ISSUE_20}`),
    Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNRESET" } }),
  ];
  for (const fault of faults) {
    const { github, calls } = twoDependents(readOf20(fault));
    const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
    assert.equal(code, 0, fault.message);
    assert.ok(calls.includes(`GET ${ISSUE_20}`), fault.message);
    assert.deepEqual(writes(calls), [labeled(21)], fault.message);
    const notices = lines.filter((line) => line.startsWith("::notice title=label-unblocked::#20: ") && line.endsWith("holding, and the next sweep reads it again"));
    assert.equal(notices.length, 1, fault.message);
    assert.deepEqual(lines.filter((line) => line.startsWith("::error")), [], fault.message);
  }
});

test("a non-fault error on one issue's read still fails the run, and the others are still labeled", async (t) => {
  for (const error of [new GitHubError(404, `GET ${ISSUE_20}`), new GitHubError(403, `GET ${ISSUE_20}`), new Error("the issue has an unexpected shape")]) {
    const { github, calls } = twoDependents(readOf20(error));
    const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
    assert.equal(code, 1, error.message);
    assert.deepEqual(writes(calls), [labeled(21)], error.message);
    assert.equal(lines.filter((line) => line.startsWith("::error title=label-unblocked::#20: ")).length, 1, error.message);
    assert.deepEqual(lines.filter((line) => line.includes("holding")), [], error.message);
  }
});

test("a GitHub fault on one issue's write still fails the run", async (t) => {
  const { github, calls } = twoDependents(() => null);
  const writer = {
    ...github.writer,
    set: async (number, state, options) => {
      if (number === 20) {
        calls.push(`SET ${number} ${state}`);
        throw new GitHubError(503, `POST ${ISSUE_20}/issue-field-values`);
      }
      return github.writer.set(number, state, options);
    },
  };
  const { code, lines } = await printedBy(t, () => sweep({ github, writer, actions: lastSweepActions }));
  assert.equal(code, 1);
  assert.ok(calls.includes(labeled(20)));
  assert.ok(calls.includes(labeled(21)));
  assert.equal(lines.filter((line) => line.startsWith("::error title=label-unblocked::#20: ")).length, 1);
  assert.deepEqual(lines.filter((line) => line.includes("holding")), []);
});

// A GraphQL query is a read (retryServerErrors' graphqlQuery): a fault on
// check-trusted-trigger.mjs's closer query for the closed issue holds it.
test("a GitHub fault on one issue's GraphQL closer query holds that issue with a notice and exits 0", async (t) => {
  const closerOf10 = (method, path, body) =>
    method === "POST" && path === "/graphql" && String(body?.query).includes("timelineItems(itemTypes: CLOSED_EVENT") && body?.variables?.number === 10
      ? new GitHubError(503, "POST /graphql")
      : null;
  const { github, calls } = twoDependents(closerOf10);
  const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
  assert.equal(code, 0);
  // The faulted query is logged without its body.
  assert.deepEqual(writes(calls), ["POST /graphql"]);
  // The labeling pass and the split-parent pass each read the close, and a
  // failed read is not cached, so each holds #10.
  const notices = lines.filter((line) => line.startsWith("::notice title=label-unblocked::#10: ") && line.endsWith("holding, and the next sweep reads it again"));
  assert.equal(notices.length, 2);
  assert.deepEqual(lines.filter((line) => line.startsWith("::error")), []);
});

// A GraphQL mutation is a write, whatever its path, so its fault is no hold.
// No mutation goes through the sweep's injected client (the status mirror
// takes its own), so the client is wrapped here as main wraps it.
test("a GitHub fault on a GraphQL mutation is a failed write, not a hold", async (t) => {
  t.mock.method(console, "log", () => {});
  const github = markReads(async () => {
    throw new GitHubError(503, "POST /graphql");
  });
  const mutation = { query: "mutation($id: ID!) { updateProjectV2ItemFieldValue(input: { itemId: $id }) { clientMutationId } }", variables: { id: "x" } };
  const error = await github("POST", "/graphql", mutation).catch((thrown) => thrown);
  assert.equal(failedFor(github, 20, error), 1);
  assert.equal(github.held, 0);
  // The same fault on a query is a hold, so the client tells the two apart.
  const read = await github("POST", "/graphql", { query: "query { viewer { login } }" }).catch((thrown) => thrown);
  assert.equal(failedFor(github, 20, read), 0);
  assert.equal(github.held, 1);
});

// The held issue was in this sweep's closed window, so the next sweep must
// read that window again: a sweep that held one issue does not advance it.
test("a sweep that held an issue on a faulted read does not advance the window", async (t) => {
  const { github } = twoDependents(readOf20(new GitHubError(502, `GET ${ISSUE_20}`)));
  const { code, lines } = await printedBy(t, () => sweep({ github, actions: lastSweepActions }));
  assert.equal(code, 0);
  const next = sweptDependent();
  const after = await sweepAfter(lines, next);
  assert.equal(after.minutes, 360);
  assert.deepEqual(writes(next.calls), [labeled(20)]);
});

test("a last sweep older than the 3-hour window is capped at 3 hours", async () => {
  // Under 6 hours old its jobs are read once, to see whether it was paced.
  const { minutes, actionCalls } = await windowOf({ workflow_runs: [{ id: 5, run_started_at: ago(300) }] });
  assert.equal(minutes, 180);
  assert.equal(actionCalls.filter((call) => call.includes("/actions/runs/5/jobs")).length, 1);
  // Past 6 hours no paced run can widen the window, so nothing more is read.
  const old = await windowOf({ workflow_runs: [{ id: 5, run_started_at: ago(400) }] });
  assert.equal(old.minutes, 180);
  assert.ok(!old.actionCalls.some((call) => call.includes("/actions/runs/5/jobs")));
});

// A paced run (work-unblock.yml's `Mark this tick paced` step) swept nothing,
// so the next sweep starts from the clean sweep before it, up to 6 hours back.
// The drop case: sweep at -200 min, paced at -140, the -80 tick dropped, this
// one now: 215 minutes back, past the 3-hour window.
test("the sweep after a paced run reads back past it to the sweep before, up to 6 hours", async () => {
  const pacedJobs = { jobs: [{ id: 9002, name: "label-unblocked", conclusion: "success", steps: [{ name: "Mark this tick paced", conclusion: "success" }, { name: "Label the unblocked issues", conclusion: "skipped" }] }] };
  const windowAfterPaced = async (runs) => {
    const { github, calls } = sweptDependent();
    const actions = async (method, path) => {
      if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs`)) return { workflow_runs: runs };
      if (path.startsWith(`/repos/${REPO}/actions/runs/6/jobs`)) return pacedJobs;
      if (path.startsWith(`/repos/${REPO}/actions/runs/5/jobs`)) return sweptJobs();
      return path === SWEEP_LOG_PATH ? LISTED_LOG : { workflow_runs: [], jobs: [] };
    };
    assert.equal(await sweep({ github, actions }), 0);
    const listing = calls.find((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed&since=`));
    return (NOW - Date.parse(decodeURIComponent(/since=([^&]+)/.exec(listing)[1]))) / 60_000;
  };
  // Listed out of id order, as a run stamped an hour ahead lists.
  assert.equal(await windowAfterPaced([{ id: 5, run_started_at: ago(200) }, { id: 6, run_started_at: ago(140) }]), 215);
  assert.equal(await windowAfterPaced([{ id: 6, run_started_at: ago(60) }, { id: 5, run_started_at: ago(120) }]), 135);
  // A sweep before the paced run older than 6 hours is capped there.
  assert.equal(await windowAfterPaced([{ id: 6, run_started_at: ago(140) }, { id: 5, run_started_at: ago(400) }]), 360);
  assert.equal(await windowAfterPaced([{ id: 6, run_started_at: ago(140) }]), 360, "no sweep before the paced run");
});

// PRRT_kwDOTCGFQM618h6b: a held run after the paced one is the newest
// successful run, and is neither clean nor paced. The window must still reach
// the clean sweep at -200 (215 minutes back with the margin), which the
// 3-hour fallback missed.
test("a held run after a paced run still reaches back to the clean sweep before it", async () => {
  const jobsOf = {
    5: sweptJobs(),
    6: { jobs: [{ id: 9002, name: "label-unblocked", conclusion: "success", steps: [{ name: "Mark this tick paced", conclusion: "success" }, { name: "Label the unblocked issues", conclusion: "skipped" }] }] },
    7: sweptJobs(),
  };
  const windowAfter = async (held, jobsAnswer = (id) => jobsOf[id]) => {
    const { github, calls } = sweptDependent();
    const actions = async (method, path) => {
      if (path.startsWith(`/repos/${REPO}/actions/workflows/work-unblock.yml/runs`)) {
        return { workflow_runs: [{ id: 7, run_started_at: ago(60) }, { id: 6, run_started_at: ago(140) }, { id: 5, run_started_at: ago(200) }] };
      }
      const jobs = /\/actions\/runs\/([0-9]+)\/jobs/.exec(path);
      if (jobs) {
        const answer = jobsAnswer(Number(jobs[1]));
        if (answer instanceof Error) throw answer;
        return answer;
      }
      return path === SWEEP_LOG_PATH ? held : { workflow_runs: [], jobs: [] };
    };
    assert.equal(await sweep({ github, actions }), 0);
    const listing = calls.find((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed&since=`));
    return (NOW - Date.parse(decodeURIComponent(/since=([^&]+)/.exec(listing)[1]))) / 60_000;
  };
  const heldListing = `${LOG_STAMP}##[notice]the closed-issue listing failed\n`;
  const heldIssue = `${LISTED_LOG}${LOG_STAMP}label-unblocked: held an issue on a failed read\n`;
  for (const log of [heldListing, heldIssue]) {
    assert.ok((await windowAfter(log)) >= 215, JSON.stringify(log));
  }
  // The label step never ran (a held lane token): no sweep step to judge.
  const noLabel = { jobs: [{ id: 9003, name: "label-unblocked", conclusion: "success", steps: [{ name: "Request the lane token", conclusion: "success" }] }] };
  assert.ok((await windowAfter(LISTED_LOG, (id) => (id === 7 ? noLabel : jobsOf[id]))) >= 215, "no label step");
  // The paced check's own jobs read throws: the fallback is the full 6 hours.
  assert.equal(await windowAfter(LISTED_LOG, () => new Error("GET failed with status 502")), 360);
});

// The pacer paces the next tick only after work-unblock.yml's `Mark this
// tick's work done`, which waits on this output: a run sweepSince would start
// the next window from.
test("only a green sweep that read its listing and held nothing writes clean-sweep", async (t) => {
  const outputOf = async (args) => {
    const dir = tempDir("clean-sweep-");
    const output = join(dir, "output");
    writeFileSync(output, "");
    const { code } = await printedBy(t, () => sweep(args, { GITHUB_OUTPUT: output }));
    return { code, clean: readFileSync(output, "utf8").includes("clean-sweep=true\n") };
  };
  assert.deepEqual(await outputOf({ github: sweptDependent().github }), { code: 0, clean: true });
  const closedDown = world({ closedList: [closedAt(10, "2026-10-16T11:30:00Z")], failOn: CLOSED_LISTING });
  assert.deepEqual(await outputOf({ github: closedDown.github }), { code: 0, clean: false }, "a held closed listing");
  const heldIssue = twoDependents(readOf20(new GitHubError(502, `GET ${ISSUE_20}`)));
  assert.deepEqual(await outputOf({ github: heldIssue.github }), { code: 0, clean: false }, "an issue held on a faulted read");
  const broken = twoDependents(readOf20(new GitHubError(404, `GET ${ISSUE_20}`)));
  const red = await outputOf({ github: broken.github });
  assert.equal(red.clean, false, "a red run");
});

test("a failed read of the last sweep falls back to 6 hours, and no earlier run to 3", async () => {
  for (const answer of [new Error("GET failed with status 403"), { nope: true }, { workflow_runs: [{ id: "x", run_started_at: ago(60) }] }]) {
    assert.equal((await windowOf(answer)).minutes, 360);
  }
  assert.equal((await windowOf({ workflow_runs: [] })).minutes, 180, "no earlier successful run");
});

// A green run proves nothing by itself: the kill switch and a lane the config
// turns off each skip the labeling step and still end the job green.
test("a last successful run that did not sweep falls back to 6 hours", async () => {
  const runs = { workflow_runs: [{ id: 5, run_started_at: ago(60) }] };
  const killed = sweptJobs("skipped", [{ name: "Report the kill switch", conclusion: "success" }]);
  const offByConfig = sweptJobs("skipped", [
    { name: "Resolve the config", conclusion: "success" },
    { name: "Report a lane the config turns off", conclusion: "success" },
  ]);
  const noSteps = { jobs: [{ name: "label-unblocked", conclusion: "success", steps: [] }] };
  const noJob = { jobs: [{ name: "save-wip-state", conclusion: "success", steps: [] }] };
  for (const jobs of [killed, offByConfig, noSteps, noJob, { jobs: [] }, { nope: true }, new Error("GET failed with status 502")]) {
    assert.equal((await windowOf(runs, {}, jobs)).minutes, 360);
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
  // One fact read for both closes, plus admit()'s own read for the record.
  assert.equal(calls.filter((call) => call === `GET /repos/${REPO}/issues/20`).length, 2);
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
const restarted = (n) => [`RESTART ${n}`];
function stopped({ resets = "2026-10-16T11:00:00Z", at = "2026-10-16T06:00:00Z", labels = [], comments, events, pulls } = {}) {
  return world({
    openReady: [ready(30, labels)],
    pulls,
    comments: { 30: comments ?? [note(), limitedNote(resets, at)] },
    events: { 30: events ?? [added("2026-10-16T05:00:00Z")] },
  });
}

// A Work status field row (resolve-config.mjs fieldEvents) on the status field.
const statusRow = (at, from, to, { actorId = LANES_APP_ID, actorLogin = "melodic-automation-lanes", actorType = "Bot" } = {}) => ({
  field: String(STATUS_CONFIG["field-id"]),
  removed: to === null,
  actorId,
  actorLogin,
  actorType,
  at,
  from,
  to,
});

test("the App's restart on the Work status field counts as a new agent-ready, so the sweep does not restart it again", async () => {
  const rows = {
    30: [statusRow("2026-10-16T05:00:00Z", "ready", "agent-ready"), statusRow("2026-10-16T11:30:00Z", "agent-ready", null), statusRow("2026-10-16T11:30:01Z", null, "agent-ready")],
  };
  const statusField = (fieldRows) => ({ field: STATUS_CONFIG["field-id"], fieldRows });
  const restartedOnField = stopped({ events: [] });
  assert.equal(await sweep({ github: restartedOnField.github, statusField: statusField(async (n) => rows[n] ?? []) }), 0);
  assert.deepEqual(writes(restartedOnField.calls), [], "the field restart after the stop started a run");
  // A person's field write counts too; an unlisted account's does not.
  const person = { actorId: OWNER.id, actorLogin: OWNER.login, actorType: "User" };
  const stranger = { actorId: STRANGER_ID, actorLogin: "stranger", actorType: "User" };
  const byPerson = stopped({ events: [] });
  assert.equal(await sweep({ github: byPerson.github, statusField: statusField(async () => [statusRow("2026-10-16T05:00:00Z", "ready", "agent-ready"), statusRow("2026-10-16T11:30:01Z", "confirmed", "agent-ready", person)]) }), 0);
  assert.deepEqual(writes(byPerson.calls), []);
  const byStranger = stopped({ events: [] });
  assert.equal(await sweep({ github: byStranger.github, statusField: statusField(async () => [statusRow("2026-10-16T05:00:00Z", "ready", "agent-ready"), statusRow("2026-10-16T11:30:01Z", "confirmed", "agent-ready", stranger)]) }), 0);
  assert.deepEqual(writes(byStranger.calls), restarted(30));
  // Only the setting before the stop: the stop is restarted on the field.
  const onlyBefore = stopped({ events: [] });
  assert.equal(await sweep({ github: onlyBefore.github, statusField: statusField(async () => rows[30].slice(0, 1)) }), 0);
  assert.deepEqual(writes(onlyBefore.calls), restarted(30));
});

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
  for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info"]) {
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

// Three limit stops since a person last added agent-ready spend the per-issue
// cap, a safety limit, so the issue fails visibly (route `fail`): an
// outcome=failed marker, which maintenance-monitor signal 9 reports, then
// agent-ready off, and no label. No restart and no needs-human.
const unready = (n) => `LEAVE ${n} confirmed`;
test("a third limit stop since a person added agent-ready fails the issue: a failed marker, agent-ready off, no needs-human", async () => {
  const stops = [
    limitedNote("2026-10-16T01:00:00Z", "2026-10-16T00:30:00Z"),
    limitedNote("2026-10-16T03:00:00Z", "2026-10-16T02:30:00Z"),
    limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"),
  ];
  const third = stopped({ comments: [note(), ...stops] });
  assert.equal(await sweep({ github: third.github, writer: third.writer }), 0);
  const written = writes(third.calls);
  assert.equal(written.length, 2);
  assert.ok(written[0].startsWith(`POST /repos/${REPO}/issues/30/comments `), written[0]);
  assert.ok(written[0].includes("<!-- work-resolve-issue outcome=failed run=7 -->"), written[0]);
  assert.deepEqual(written.slice(1), [unready(30)], "the Work status leaves agent-ready for confirmed after the comment");
  assert.ok(!written.some((call) => call.includes("needs-human")));
  // The comment went out but the field write did not land: the next sweep,
  // whose newest marker is that failed one, writes only the field.
  const failedNote = (at) => ({ id: 40, body: failedComment({ stops: 3, run: "7" }), user: LANES_BOT, created_at: at });
  const retry = stopped({ comments: [note(), ...stops, failedNote("2026-10-16T06:30:00Z")] });
  assert.equal(await sweep({ github: retry.github }), 0);
  assert.deepEqual(writes(retry.calls), [unready(30)]);
  // A failed marker from before a person's re-add ends nothing now: the new
  // stops fail the issue again, with a new marker.
  const stale = stopped({
    comments: [note(), failedNote("2026-10-15T23:00:00Z"), ...stops],
    events: [added("2026-10-15T22:00:00Z", OWNER), added("2026-10-15T23:30:00Z", OWNER)],
  });
  assert.equal(await sweep({ github: stale.github }), 0);
  assert.equal(writes(stale.calls).length, 2);
  // A person's agent-ready after the newest marker, a failed one, starts a new
  // run: the sweep takes it to the re-fire checks, never the fail route, so
  // it never removes that agent-ready, whether the run is recent or stranded.
  for (const at of ["2026-10-16T11:00:00Z", "2026-10-16T07:00:00Z"]) {
    const readded = stopped({
      comments: [note(), ...stops, failedNote("2026-10-16T06:30:00Z")],
      events: [added("2026-10-16T05:00:00Z"), { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T06:30:01Z" }, added(at, OWNER)],
    });
    assert.equal(await sweep({ github: readded.github }), 0);
    assert.deepEqual(writes(readded.calls), [], at);
  }
  // A person adding agent-ready after the first stop starts the count again.
  const reset = stopped({ comments: [note(), ...stops], events: [added("2026-10-16T00:00:00Z"), added("2026-10-16T01:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: reset.github }), 0);
  assert.deepEqual(writes(reset.calls), restarted(30));
});

// The sweep reads the resolved config's `limits` (hours and counts) from the
// file resolve-config wrote.
const withLimits = (limits) => {
  const path = join(tempDir("work-unblock-limits-"), "resolved-config.json");
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

// A stop stop-routes.json routes to retry (a crash, an unfinished check):
// report-outcome keeps agent-ready and leaves a retry marker while
// limits.stop-retries allows one, and the sweep restarts the issue at once.
// More retry markers since a person added agent-ready than the limit allows
// restart nothing, so every retry has a hard end.
const retryNote = (at, run = 7) => ({
  id: 34,
  body: `<!-- work-resolve-issue outcome=retry run=${run} -->\nThe work-resolve-issue lane stopped on this issue (\`outcome-unread\`).`,
  user: LANES_BOT,
  created_at: at,
});

test("an issue a retry-routed stop left on agent-ready is restarted while limits.stop-retries allows it", async () => {
  for (const limits of [{}, { "stop-retries": 1 }]) {
    const { github, calls } = stopped({ comments: [note(), retryNote("2026-10-16T11:55:00Z")] });
    assert.equal(await sweep({ github }, withLimits(limits)), 0);
    assert.deepEqual(writes(calls), restarted(30), JSON.stringify(limits));
  }
});

test("retry stops past limits.stop-retries, or any with it at 0, restart nothing", async () => {
  for (const [limits, comments] of [
    [{ "stop-retries": 0 }, [note(), retryNote("2026-10-16T11:55:00Z")]],
    [{ "stop-retries": 1 }, [note(), retryNote("2026-10-16T08:00:00Z", 6), retryNote("2026-10-16T11:55:00Z")]],
  ]) {
    const { github, calls } = stopped({ comments, events: [added("2026-10-16T05:00:00Z", OWNER)] });
    assert.equal(await sweep({ github }, withLimits(limits)), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(limits));
  }
});

// A stop that waits on an open pull request (blocked-by-pr) keeps agent-ready with a wait marker naming it, and the
// sweep restarts it once that pull request merges or closes, never a person.
const waitNote = (at, run = 7, pr = 15) => ({
  id: 35,
  body: `<!-- work-resolve-issue outcome=wait pr=${pr} run=${run} -->\nThe work-resolve-issue lane stopped on this issue (\`blocked-by-pr\`).`,
  user: LANES_BOT,
  created_at: at,
});

test("a stop that waits on a pull request waits while it is open and restarts once it merges or closes", async () => {
  const open = stopped({ comments: [note(), waitNote("2026-10-16T11:55:00Z")], pulls: { 15: { number: 15, state: "open", merged_at: null } } });
  assert.equal(await sweep({ github: open.github }), 0);
  assert.deepEqual(writes(open.calls), []);
  for (const pull of [
    { number: 15, state: "closed", merged_at: "2026-10-16T11:58:00Z" },
    { number: 15, state: "closed", merged_at: null },
  ]) {
    const { github, calls } = stopped({ comments: [note(), waitNote("2026-10-16T11:55:00Z")], pulls: { 15: pull } });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), restarted(30), JSON.stringify(pull));
  }
});

test("waits are counted apart from retries, and past limits.stop-retries restart nothing", async () => {
  const merged = { 15: { number: 15, state: "closed", merged_at: "2026-10-16T11:58:00Z" } };
  const mixed = stopped({ comments: [note(), retryNote("2026-10-16T08:00:00Z", 6), waitNote("2026-10-16T11:55:00Z")], pulls: merged, events: [added("2026-10-16T05:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: mixed.github }, withLimits({ "stop-retries": 1 })), 0);
  assert.deepEqual(writes(mixed.calls), restarted(30));
  const spent = stopped({ comments: [note(), waitNote("2026-10-16T08:00:00Z", 6), waitNote("2026-10-16T11:55:00Z")], pulls: merged, events: [added("2026-10-16T05:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: spent.github }, withLimits({ "stop-retries": 1 })), 0);
  assert.deepEqual(writes(spent.calls), []);
});

test("the App's remove-and-re-add after a retry stop is a restart, not a stop", async () => {
  const unlabeled = { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T07:00:00Z" };
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [note(), retryNote("2026-10-16T06:00:00Z")] },
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

test("a funding-stopped issue before its regain date waits", async () => {
  const { github, calls } = stopped({ comments: [note(), fundingNote("2026-10-17T00:00:00Z", "2026-10-16T06:00:00Z")] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

// Funding is the lane's Claude capacity (a spend limit, no credit or a
// disabled key), not a bill a restart can raise. With no regain date the
// sweep tries again limits.fallback-reset hours after the stop, as it does a
// limit stop with no reset, instead of waiting on a person; the per-issue cap
// below bounds the tries.
test("a funding-stopped issue with no regain date is restarted limits.fallback-reset hours after the stop", async () => {
  const early = stopped({ comments: [note(), fundingNote("", "2026-10-16T08:00:00Z")] });
  assert.equal(await sweep({ github: early.github }), 0);
  assert.deepEqual(writes(early.calls), []);
  const due = stopped({ comments: [note(), fundingNote("", "2026-10-16T06:00:00Z")] });
  assert.equal(await sweep({ github: due.github }), 0);
  assert.deepEqual(writes(due.calls), restarted(30));
  assert.ok(!writes(due.calls).some((call) => call.includes("needs-human")));
});

// Funding and limit stops share limits.limit-stops-per-issue, so an outage
// that outlasts the reset clamp fails the issue visibly, not a loop and not a
// person.
test("a third funding or limit stop since a person added agent-ready fails the issue", async () => {
  const comments = [
    note(),
    fundingNote("2026-10-16T02:00:00Z", "2026-10-16T01:00:00Z", 4),
    limitedNote("2026-10-16T04:00:00Z", "2026-10-16T03:00:00Z"),
    fundingNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z", 6),
  ];
  const { github, calls } = stopped({ comments, events: [added("2026-10-16T00:30:00Z", OWNER)] });
  assert.equal(await sweep({ github }), 0);
  const written = writes(calls);
  assert.ok(written[0].includes("<!-- work-resolve-issue outcome=failed run=6 -->"), written[0]);
  assert.deepEqual(written.slice(1), [unready(30)]);
});

// The failed marker parses as the lane's outcome marker, which signal 9's
// collector and findPrior read: outcome failed, naming the stopped run (and
// its branch=resumed tag), so a person's new agent-ready resumes that run's
// branch.
test("the failed marker parses as outcome failed naming the stopped run", () => {
  assert.deepEqual(parseOutcomeMarker(failedComment({ stops: 3, run: "7" })), { outcome: "failed", resets: null, run: "7", onResumed: false });
  assert.deepEqual(parseOutcomeMarker(failedComment({ stops: 3, run: "8", onResumed: true })), { outcome: "failed", resets: null, run: "8", onResumed: true });
  assert.ok(!failedComment({ stops: 3, run: "7" }).includes("needs-human"));
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
  assert.deepEqual(writes(second.calls).slice(1), [unready(30)]);

  // No stated reset, stopped at 06:00: five hours has passed at 12:00, seven has not.
  const bare = stopped({ resets: "" });
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), restarted(30));
  const later = stopped({ resets: "" });
  assert.equal(await sweep({ github: later.github }, withLimits({ "fallback-reset": 7 })), 0);
  assert.deepEqual(writes(later.calls), []);
});

// A failed restart is tried once more; a second failure is an ::error naming
// the issue and fails the run.
test("a failed restart is retried once, then reported", async (t) => {
  for (const [failures, code] of [[1, 0], [2, 1]]) {
    const { github, calls } = stopped();
    let left = failures;
    const writer = {
      ...github.writer,
      restart: async (number) => {
        calls.push(`RESTART ${number}`);
        if (left > 0) {
          left -= 1;
          throw new Error("POST failed with status 502");
        }
      },
    };
    const log = t.mock.method(console, "log", () => {});
    assert.equal(await sweep({ github, writer }), code, `${failures} failures`);
    assert.deepEqual(writes(calls), [...restarted(30), ...restarted(30)], `${failures} failures`);
    const errors = log.mock.calls.map((call) => String(call.arguments[0])).filter((line) => line.startsWith("::error"));
    assert.equal(errors.length, code, `${failures} failures`);
    if (code) {
      assert.match(errors[0], /#30: the restart did not set the Work status to agent-ready: POST failed with status 502/);
    }
    log.mock.restore();
  }
});

// Re-fires after a failed run: a run that crashed before its report leaves no
// marker (a rerun the token broker refuses as workflow-modified, since it
// keeps its first event's workflow files, is a failed mint, below). The sweep
// gives such an issue a fresh event: the App removes and re-adds agent-ready,
// when its newest agent-ready label (a listed human's or the App's) has no
// lanes-App marker after it and the work-resolve-issue run that label started
// has failed. It records the re-fire in a comment first, and re-fires an issue
// at most once per version of main's pr-run-activity-write.yml and
// work-resolve-issue.yml.
const WRITE_SHA = "1".repeat(40);
const CALLER_SHA = "2".repeat(40);
const KEY = `${WRITE_SHA}-${CALLER_SHA}`;
const BLOBS = { ".github/workflows/pr-run-activity-write.yml": WRITE_SHA, ".github/workflows/work-resolve-issue.yml": CALLER_SHA };
const LABELED_AT = "2026-10-16T10:00:00Z";
const laneRun = ({ number = 30, at = "2026-10-16T10:00:03Z", status = "completed", conclusion = "failure" } = {}) => ({
  id: 5000 + number,
  display_title: `Fix the thing #${number}`,
  created_at: at,
  run_attempt: 1,
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
// budget, say), or broker-check's broker ask failed for any reason but the
// kill switch, or because the WIP cap skipped resolve-issue. It is re-fired
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
  summary,
  subIssues = {},
} = {}) {
  const fake = world({
    blockedBy,
    subIssues,
    queuedIssues,
    logs,
    openReady: [{ ...ready(number), ...(summary && { sub_issues_summary: summary }) }],
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
  // No write names needs-human.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

test("a hand-started run sweeps as the schedule does, reading no event payload", async () => {
  const { github, actions, calls } = stalledRun();
  assert.equal(await sweep({ github, actions }, { GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_EVENT_PATH: "/nonexistent/event.json" }), 0);
  assert.deepEqual(writes(calls), refired(30));
});

test("a run that did no work waits until an hour after it ended, past any rate-limit reset", async () => {
  const { github, actions, calls } = stalledRun({ ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

// The sweep reads the resolved config's `limits` and `wip`; a past pause-from
// lets the issue lane pause over its cap.
const withConfig = (config) => {
  const path = join(tempDir("work-unblock-config-"), "resolved-config.json");
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
  // No write names needs-human.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

// Past the bound it keeps re-firing on the backoff (3 hours doubling per
// re-fire, at most 24, from when the run ended), recorded in one comment.
test("a failed mint past limit-stops-per-issue re-fires on the same workflow files goes on a backoff, with no needs-human", async () => {
  const mintCause = "The work-resolve-issue run that `agent-ready` started could not get its lane token, or the token broker's leave to run.";
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
  // No write names needs-human.
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

// A key the key-credit gate held off skips resolve-issue alone; its
// subscription call ran, so the run is no WIP cap skip.
test("a run whose key the key-credit gate held off, with its subscription call run, is no WIP cap skip", async () => {
  const jobs = [
    pickSlot,
    { name: "resolve-issue", conclusion: "skipped", steps: [] },
    { name: "resolve-issue-subscription / broker-check", conclusion: "success", steps: [{ name: "Ask the broker whether the lane may run", conclusion: "success" }, { name: "Claim the issue with a lane lease", conclusion: "success" }] },
    { name: "resolve-issue-subscription / run", conclusion: "success", steps: [{ name: "Request the lane token", conclusion: "skipped" }] },
  ];
  const { github, actions, calls } = stalledRun({ jobs, conclusion: "success", openLanePrs: 1 });
  assert.equal(await sweep({ github, actions }, PAUSING), 0);
  assert.deepEqual(writes(calls), []);
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

// The admit job skips an umbrella with an open sub-issue the way it skips a
// blocked issue (check-blockers.mjs): agent-ready kept, no marker. The sweep
// waits while one is open, with no write and no needs-human, reading the
// listing's sub_issues_summary, and re-fires it once none is.
test("a run the gate skipped on an umbrella waits, with no write, while a sub-issue is open", async () => {
  const subIssues = { 30: [issue(9691), issue(9692, { state: "closed" })] };
  const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", summary: { total: 2, completed: 1, percent_completed: 50 }, subIssues });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a listing item with no sub_issues_summary lists the sub-issues, and an open one keeps the run waiting", async () => {
  const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", subIssues: { 30: [issue(9691)] } });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(calls.some((call) => call.includes("/sub_issues")));
});

test("a run the gate skipped on an umbrella is re-fired once every sub-issue is closed, reading no sub-issue list when the summary shows none open", async () => {
  const closed = { 30: [issue(9691, { state: "closed" }), issue(9692, { state: "closed", reason: "not_planned" })] };
  for (const summary of [{ total: 2, completed: 2, percent_completed: 100 }, { total: 2, completed: 1, percent_completed: 50 }]) {
    const { github, actions, calls } = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", summary, subIssues: closed });
    assert.equal(await sweep({ github, actions }), 0);
    assert.deepEqual(writes(calls), refired(30), JSON.stringify(summary));
    assert.equal(calls.some((call) => call.includes("/sub_issues")), summary.completed < summary.total, JSON.stringify(summary));
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
  const untrusted = { name: "provenance: untrusted" };
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

// A blocker added while the run waited for its slot: broker-check's in-slot
// re-check stops it green at `Stop on an open blocker`, after the lease, with
// no model turn and no marker. The sweep routes it as admit's blocker gate:
// it waits while a blocker is open and re-fires once none is, past any bound.
const recheckStopped = (stop, leg = "resolve-issue") => [
  ADMITTED,
  pickSlot,
  {
    ...BROKER_ALLOWED,
    name: `${leg} / broker-check`,
    steps: [
      ...BROKER_ALLOWED.steps,
      { name: "Claim the issue with a lane lease", conclusion: "success" },
      { name: "Re-check the issue's blockers in the slot", conclusion: "success" },
      { name: "Stop on an open blocker", conclusion: stop },
    ],
  },
  { name: `${leg} / run`, conclusion: "success", steps: [{ name: "Decide whether the activity runs", conclusion: "success" }] },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];

test("a run the in-slot re-check stopped waits, with no write, while a blocker is open", async () => {
  const { github, actions, calls } = stalledRun({ jobs: recheckStopped("success"), conclusion: "success", blockedBy: { 30: [issue(31)] } });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a run the in-slot re-check stopped is re-fired once no blocker is open, past the per-version bound, with no needs-human, as admit's gate is", async () => {
  for (const pumps of [{}, earlierPumps(3)]) {
    const closed = { blockedBy: { 30: [issue(31, { state: "closed" })] }, ...pumps };
    const rechecked = stalledRun({ jobs: recheckStopped("success"), conclusion: "success", ...closed });
    assert.equal(await sweep({ github: rechecked.github, actions: rechecked.actions }), 0);
    const admitted = stalledRun({ jobs: BLOCKER_SKIPPED, conclusion: "success", ...closed });
    assert.equal(await sweep({ github: admitted.github, actions: admitted.actions }), 0);
    assert.deepEqual(writes(rechecked.calls), writes(admitted.calls));
    assert.deepEqual(writes(rechecked.calls), refired(30));
    assert.ok(!writes(rechecked.calls).some((call) => call.includes("needs-human")));
  }
});

test("an in-slot re-check that let the run on is no blocker stop", async () => {
  const pumped = stalledRun({ jobs: recheckStopped("skipped"), conclusion: "success", blockedBy: { 30: [issue(31, { state: "closed" })] }, ...earlierPumps(3) });
  assert.equal(await sweep({ github: pumped.github, actions: pumped.actions }), 0);
  assert.deepEqual(writes(pumped.calls), []);
});

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

// Run 41046083087: the API key leg ran and handed off, and the subscription
// leg waited for its slot past a lane workflow change and stopped stale there.
const staleLegJob = (name, stop) => ({ ...staleRunJob(stop), name: `${name} / run` });

test("a run whose later leg stopped green on stale workflow files is re-fired", async () => {
  for (const leg of ["resolve-issue-subscription", "resolve-issue-fallback"]) {
    const jobs = [ADMITTED, pickSlot, BROKER_ALLOWED, staleRunJob("skipped"), staleLegJob(leg, "success"), { name: "report-outcome", conclusion: "skipped", steps: [] }];
    const fake = stalledRun({ jobs, conclusion: "success" });
    assert.equal(await sweep({ github: fake.github, actions: fake.actions }), 0, leg);
    assert.deepEqual(writes(fake.calls), refired(30), leg);
  }
});

// The stale run's report-outcome re-fires it at once; when that report's mint
// is refused or fails (a main change older than the broker's report window),
// the run ends red. It still ran no model, so the sweep re-fires it as a stale
// stop on its next run, not on the failed-mint clock (limits.reset-clamp-min
// after the run ended, here not yet passed).
test("a stale run whose report-outcome mint failed is re-fired at once, not as a failed mint", async () => {
  const reportMint = { name: "report-outcome / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "failure" }] };
  const red = stalledRun({ jobs: [ADMITTED, pickSlot, BROKER_ALLOWED, staleRunJob("success"), reportMint], conclusion: "failure", ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: red.github, actions: red.actions }), 0);
  assert.deepEqual(writes(red.calls), refired(30));
  // The same failed mint after a model run waits for the clock.
  const ran = stalledRun({ jobs: [ADMITTED, pickSlot, BROKER_ALLOWED, staleRunJob("skipped"), reportMint], conclusion: "failure", ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: ran.github, actions: ran.actions }), 0);
  assert.deepEqual(writes(ran.calls), []);
});

// A breaker trip: the token broker refused the run for the lanes kill switch,
// which only the refused job's log names. Run 40127074215 failed at
// broker-check's broker ask before any resolve-issue run job; run 40127093047
// ran the model and was refused at its write runner's mint. Each denial line
// is the failed step's last, just before `Process completed`. A broker-check
// refusal for workflow-modified fails at the same step and is a failed mint.
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
  assert.equal(done.length, 1 + restarted(30).length, done.join("\n"));
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

test("a run the broker refused at broker-check for the kill switch is a breaker trip: its own record, re-fired by the first sweep after it ended", async () => {
  const { github, actions, calls } = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`]);
  // No model ran and the sweep runs only with the switch off, so it does not
  // wait limits.reset-clamp-min: a run that ended half an hour ago re-fires.
  const recent = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0);
  tripped(recent.calls);
});

test("a breaker trip at a post-model mint still waits limits.reset-clamp-min after the run ended", async () => {
  // The model ran, so a re-fire runs it again: the clamp stays.
  const early = stalledRun({ jobs: MINT_REFUSED, logs: MINT_KILLED, ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: early.github, actions: early.actions }), 0);
  assert.deepEqual(writes(early.calls), []);
});

// The breaker record names the refused run and when it ended, so a reader
// hours later sees a re-fire of that refusal, not a fresh one.
const postedBody = (calls) => {
  const posted = writes(calls).find((call) => call.startsWith(`POST /repos/${REPO}/issues/30/comments `));
  assert.ok(posted, writes(calls).join("\n"));
  return JSON.parse(posted.slice(posted.indexOf(" {") + 1)).body;
};
const REFUSED_LINK = `[run 5030](https://github.com/${REPO}/actions/runs/5030)`;

test("the breaker record links the refused run and its end time, and says it re-fires that earlier refusal", () => {
  const body = breakerComment(KEY, { repo: REPO, run: 5030, ended: Date.parse("2026-10-16T10:05:00Z") });
  assert.ok(body.startsWith(`${BREAKER_MARKER}\n`), body);
  assert.ok(body.includes(REFUSED_LINK), body);
  assert.ok(body.includes("2026-10-16T10:05:00Z"), body);
  assert.ok(body.includes("not a new refusal"), body);
});

test("a breaker trip's record names the run the broker refused and when it ended", async () => {
  const { github, actions, calls } = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED });
  assert.equal(await sweep({ github, actions }), 0);
  const body = postedBody(calls);
  assert.ok(body.includes(REFUSED_LINK), body);
  assert.ok(body.includes("ended at 2026-10-16T10:05:00Z"), body);
  // With a later run the WIP cap skipped for the same label, the record still
  // names the refused run, not the newest.
  const fake = world({
    openReady: [ready(30)],
    comments: { 30: [note()] },
    events: { 30: [added(LABELED_AT, OWNER)] },
    runs: [
      { ...laneRun({ conclusion: "failure" }), updated_at: "2026-10-16T10:05:00Z" },
      { ...laneRun({ at: "2026-10-16T10:00:04Z", conclusion: "success" }), id: 5031, updated_at: "2026-10-16T10:06:00Z" },
    ],
    jobs: { 5030: BROKER_REFUSED, 5031: WIP_CAPPED },
    logs: CHECK_KILLED,
    openLanePrs: 10,
    blobs: BLOBS,
  });
  assert.equal(await sweep({ github: fake.github, actions: fake.github, now: Date.parse("2026-10-16T11:10:00Z") }), 0);
  const both = postedBody(fake.calls);
  assert.ok(both.includes(REFUSED_LINK), both);
  assert.ok(both.includes("ended at 2026-10-16T10:05:00Z"), both);
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

// With request-lane-token's kill-switch-ok, the same refusal ends the mint
// step green with no token and a `lane-token-stopped` notice: every step that
// keys on the token, `Stage the activity from the base` first, skips, and the
// run ends green. Only that shape in the job listing earns a log read. The
// log's shape is job 120970852314's: the composite's one step sits between a
// start-action and an end-action marker, and the step's own output follows
// its script group.
const stoppedJob = (id, name) => ({
  id,
  name,
  conclusion: "success",
  steps: [
    { name: "Request the lane token", conclusion: "success" },
    { name: "Select the trusted PR text", conclusion: "skipped" },
    { name: "Stage the activity from the base", conclusion: "skipped" },
    { name: "Write the verdict", conclusion: "success" },
  ],
});
const stoppedLog = ({ stamp = "2026-10-30T01:57:51.9466327Z ", line = "lane-token-stopped: the broker refused the token because a lanes kill switch is on, a designed stop; this run takes no token and skips the rest" } = {}) =>
  [
    "2026-10-30T01:57:50.6157454Z ##[group]Run ./.base/.github/actions/request-lane-token",
    "2026-10-30T01:57:50.6159328Z ##[endgroup]",
    "2026-10-30T01:57:50.6165385Z ##[start-action display=Request the lane token;id=lane-token.request]",
    "2026-10-30T01:57:50.6182178Z ##[group]Run set -euo pipefail",
    "2026-10-30T01:57:50.6340248Z ##[endgroup]",
    `${stamp}##[notice]${line}`,
    "2026-10-30T01:57:51.9483644Z ##[end-action id=lane-token.request;outcome=success;conclusion=success;duration_ms=1331]",
    "2026-10-30T01:57:52.0000000Z ##[group]Run jq -n \\",
    "",
  ].join("\n");
const MINT_STOPPED = [
  ADMITTED,
  pickSlot,
  BROKER_ALLOWED,
  { name: "resolve-issue / run", conclusion: "success", steps: [{ name: "Run the skill activity", conclusion: "success" }] },
  stoppedJob(PATCH_MINT_ID, "apply-issue-patch / run"),
  stoppedJob(REPORT_MINT_ID, "report-outcome / run"),
];
const MINT_STOPPED_LOGS = { [PATCH_MINT_ID]: stoppedLog(), [REPORT_MINT_ID]: stoppedLog() };

test("a green run whose mints the kill switch stopped is a breaker trip, read from one log", async () => {
  const { github, actions, calls } = stalledRun({ jobs: MINT_STOPPED, logs: MINT_STOPPED_LOGS, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${PATCH_MINT_ID}/logs`]);
  // Past the failed-mint bound on these workflow files it still goes as a trip.
  const pumped = stalledRun({ jobs: MINT_STOPPED, logs: MINT_STOPPED_LOGS, conclusion: "success", ...earlierPumps(3) });
  assert.equal(await sweep({ github: pumped.github, actions: pumped.actions }), 0);
  tripped(pumped.calls);
  // The model ran, so like a mint refusal it waits limits.reset-clamp-min after the run ended.
  const early = stalledRun({ jobs: MINT_STOPPED, logs: MINT_STOPPED_LOGS, conclusion: "success", ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: early.github, actions: early.actions }), 0);
  assert.deepEqual(writes(early.calls), []);
});

test("a stopped patch mint before a report the switch also stopped, or one alone, is a breaker trip", async () => {
  const alone = MINT_STOPPED.filter((job) => job.id !== REPORT_MINT_ID).concat({ name: "report-outcome", conclusion: "skipped", steps: [] });
  const { github, actions, calls } = stalledRun({ jobs: alone, logs: MINT_STOPPED_LOGS, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
});

test("a run whose stopped mint is followed by a mint that took its token did work, read with no log", async () => {
  const minted = { id: REPORT_MINT_ID, name: "report-outcome / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "success" }, { name: "Stage the activity from the base", conclusion: "success" }] };
  const jobs = [...MINT_STOPPED.slice(0, -1), minted];
  const { github, actions, calls } = stalledRun({ jobs, logs: MINT_STOPPED_LOGS, ...earlierPumps(1) });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), []);
  assert.deepEqual(logReads(calls), []);
});

// The reverse order: apply-issue-patch minted and pushed, then the switch
// stopped report-outcome green. The run never reported because of the switch,
// so it is a breaker trip, read from report-outcome's log alone.
const REPORT_STOPPED_AFTER_PATCH = [
  ...MINT_STOPPED.slice(0, -2),
  { id: PATCH_MINT_ID, name: "apply-issue-patch / run", conclusion: "success", steps: [{ name: "Request the lane token", conclusion: "success" }, { name: "Stage the activity from the base", conclusion: "success" }] },
  stoppedJob(REPORT_MINT_ID, "report-outcome / run"),
];

test("a green run whose report mint the kill switch stopped after a patch mint is a breaker trip", async () => {
  const { github, actions, calls } = stalledRun({ jobs: REPORT_STOPPED_AFTER_PATCH, logs: MINT_STOPPED_LOGS, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.equal(logReads(calls).length, 1);
  assert.ok(logReads(calls)[0].includes(String(REPORT_MINT_ID)));
});

test("a report mint stopped after a patch mint with no kill-switch notice keeps the once-per-version re-fire", async () => {
  const logs = { [REPORT_MINT_ID]: stoppedLog({ line: "lane-token-stopped: the broker refused the token because a lanes kill switch is onward" }) };
  const { github, actions, calls } = stalledRun({ jobs: REPORT_STOPPED_AFTER_PATCH, logs, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), refired(30));
  assert.equal(logReads(calls).length, 1);
});

test("a stopped mint whose log does not carry the kill-switch notice is a failed mint, never a breaker trip", async () => {
  for (const [name, log] of [
    ["a lookalike notice", stoppedLog({ line: "lane-token-stopped: the broker refused the token because a lanes kill switch is onward" })],
    ["no timestamp", stoppedLog({ stamp: "" })],
    ["a warning, not a notice", stoppedLog().replace("##[notice]", "##[warning]")],
    ["over the size cap", `${"x".repeat(2 * 1024 * 1024)}\n${stoppedLog()}`],
    ["no log", undefined],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: MINT_STOPPED, logs: log === undefined ? {} : { [PATCH_MINT_ID]: log }, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
  }
});

test("a kill-switch notice outside the mint step's section is a failed mint, never a breaker trip", async () => {
  const [head, tail] = stoppedLog().split(/^.*##\[notice\].*\n/m);
  const notice = stoppedLog().split("\n").find((line) => line.includes("##[notice]"));
  const start = head.split("\n").find((line) => line.includes("##[start-action"));
  const end = tail.split("\n").find((line) => line.includes("##[end-action"));
  for (const [name, log] of [
    ["in a later step", `${head}${tail}${notice}\n`],
    ["before the mint step", `${notice}\n${head}${tail}`],
    ["in a second mint block after the first", `${head}${tail}${start}\n${notice}\n${end}\n`],
    ["with no end-action marker", `${head}${notice}\n`],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: MINT_STOPPED, logs: { [PATCH_MINT_ID]: log }, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
  }
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

// Owner decision Q109: past limit-stops-per-issue trips, a breaker trip waits
// a flat limits.stranded-backoff-hours kill-switch after its run ended,
// never doubled, and no trip count gives the issue up. `trips` earlier breaker
// records, each with the App's remove and re-add, before the newest add at
// `lastAdd`.
const tripHistory = (trips, lastAdd = LABELED_AT) => {
  const comments = [note()];
  const events = [added("2026-10-16T05:00:00Z", OWNER)];
  for (let index = 0; index < trips; index += 1) {
    const at = `2026-10-16T05:${String(10 + index).padStart(2, "0")}:00Z`;
    comments.push({ id: 70 + index, body: breakerComment(KEY, { repo: REPO, run: 4000 + index, ended: Date.parse(at) }), user: LANES_BOT, created_at: at });
    events.push({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: at });
    events.push(added(index === trips - 1 ? lastAdd : `2026-10-16T05:${String(10 + index).padStart(2, "0")}:01Z`));
  }
  return { comments, events: trips === 0 ? [added(lastAdd, OWNER)] : events };
};
const KILL_SWITCH_HOUR = withLimits({ "stranded-backoff-hours": { "kill-switch": 1 } });
const ENDED = Date.parse("2026-10-16T10:05:00Z");
const HOUR_MS = 3_600_000;

test("a breaker trip waits a flat kill-switch hour after its run ended at trip 1, 4, 5 and 7, never doubled and never given up", async () => {
  // Trip 1 at a post-model mint: limits.reset-clamp-min, one hour.
  for (const [trip, jobs, logs] of [
    [1, MINT_REFUSED, MINT_KILLED],
    [4, BROKER_REFUSED, CHECK_KILLED],
    [5, BROKER_REFUSED, CHECK_KILLED],
    [7, BROKER_REFUSED, CHECK_KILLED],
  ]) {
    const early = stalledRun({ jobs, logs, ...tripHistory(trip - 1) });
    assert.equal(await sweep({ github: early.github, actions: early.actions, now: ENDED + HOUR_MS - 1 }, KILL_SWITCH_HOUR), 0);
    assert.deepEqual(writes(early.calls), [], `trip ${trip} re-fired before its hour`);
    const due = stalledRun({ jobs, logs, ...tripHistory(trip - 1) });
    assert.equal(await sweep({ github: due.github, actions: due.actions, now: ENDED + HOUR_MS }, KILL_SWITCH_HOUR), 0);
    // Exactly the breaker record and the restart: no outcome=failed comment, no confirmed write.
    tripped(due.calls);
  }
});

test("other stranded causes still double with kill-switch at one flat hour", async () => {
  // A failed mint past limit-stops-per-issue re-fires: 3 hours doubled three times, 24 after 10:05.
  const early = stalledRun({ jobs: BROKER_REFUSED, logs: {}, ...earlierPumps(3) });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-17T10:04:59Z") }, KILL_SWITCH_HOUR), 0);
  assert.deepEqual(writes(early.calls), [], "the failed mint re-fired before its doubled backoff");
  const due = stalledRun({ jobs: BROKER_REFUSED, logs: {}, ...earlierPumps(3) });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-17T10:05:00Z") }, KILL_SWITCH_HOUR), 0);
  assert.deepEqual(writes(due.calls).slice(-restarted(30).length), restarted(30), "the failed mint did not re-fire at its doubled backoff");
});

// Five breaker-stranded issues: each one's newest add, its run's end five
// minutes later, and its trips so far. Oldest run end first: #35 07:35, #32
// 08:05, #34 08:35, #33 09:05, #31 09:35. #36's run failed its mint at 10:05,
// a cause the queue target does not pace. `unfinished` other issues' lane runs
// are not yet finished, spread over the statuses the in-flight read lists.
const BREAKER_ISSUES = [
  [31, "2026-10-16T09:30:00Z", 0],
  [32, "2026-10-16T08:00:00Z", 3],
  [33, "2026-10-16T09:00:00Z", 0],
  [34, "2026-10-16T08:30:00Z", 6],
  [35, "2026-10-16T07:30:00Z", 1],
];
const afterClear = (unfinished, failOn, extra = []) => {
  const end = (at) => new Date(Date.parse(at) + 5 * 60_000).toISOString();
  const statuses = ["queued", "in_progress", "pending", "waiting"];
  const others = Array.from({ length: unfinished }, (_, index) => ({
    ...laneRun({ number: 900 + index, at: "2026-10-16T11:50:00Z", status: statuses[index % statuses.length], conclusion: null }),
  }));
  return world({
    openReady: [...BREAKER_ISSUES.map(([n]) => ready(n)), ready(36)],
    comments: { ...Object.fromEntries(BREAKER_ISSUES.map(([n, at, trips]) => [n, tripHistory(trips, at).comments])), 36: [note()] },
    events: { ...Object.fromEntries(BREAKER_ISSUES.map(([n, at, trips]) => [n, tripHistory(trips, at).events])), 36: [added(LABELED_AT, OWNER)] },
    runs: [
      ...BREAKER_ISSUES.map(([n, at]) => ({ ...laneRun({ number: n, at: new Date(Date.parse(at) + 3000).toISOString() }), updated_at: end(at) })),
      { ...laneRun({ number: 36 }), updated_at: "2026-10-16T10:05:00Z" },
      ...others,
      ...extra,
    ],
    jobs: { ...Object.fromEntries(BREAKER_ISSUES.map(([n]) => [5000 + n, BROKER_REFUSED])), 5036: MINT_FAILED },
    logs: CHECK_KILLED,
    openLanePrs: 10,
    blobs: BLOBS,
    failOn,
  });
};
const restarts = (calls) => writes(calls).filter((call) => call.startsWith("RESTART "));
const clearLimits = (extra = {}) => withLimits({ "stranded-backoff-hours": { "kill-switch": 1 }, "restarts-per-run": 10, ...extra });

test("the issue lane's slot count is the effective lane level: the default while shadowed, the published level once live", () => {
  const now = Date.parse("2026-11-10T23:00:00Z");
  const env = { LANE_VARS: JSON.stringify({ CLAUDE_LANE_LEVEL: `4@${now / 1000 + 600}` }) };
  const lines = [];
  const log = (line) => lines.push(line);
  assert.equal(laneSlots({ env, now, log }), 3, "shadow mode (the default) keeps the lane at 3");
  assert.deepEqual(lines, ["label-unblocked: lane level 3 (shadow; would use 4, published)"]);
  assert.equal(laneSlots({ laneLevel: { shadow: false }, env, now, log }), 4);
  assert.equal(laneSlots({ laneLevel: { shadow: false }, env, now: now + 601_000, log }), 3, "an expired value reads as the default");
});

test("after the switch clears, breaker re-fires top the unfinished lane runs up to refire-queue-per-slot x SLOTS, the oldest stranded first", async () => {
  // Target 2 x 3 = 6; 3 unfinished leaves room for 3: the three oldest run ends.
  const room = afterClear(3);
  assert.equal(await sweep({ github: room.github, actions: room.github }, clearLimits()), 0);
  assert.deepEqual(restarts(room.calls), ["RESTART 35", "RESTART 32", "RESTART 34", "RESTART 36"]);
  // At or over the target no breaker trip re-fires; the failed mint still does.
  for (const unfinished of [6, 8]) {
    const full = afterClear(unfinished);
    assert.equal(await sweep({ github: full.github, actions: full.github }, clearLimits()), 0);
    assert.deepEqual(restarts(full.calls), ["RESTART 36"], `${unfinished} unfinished`);
    assert.ok(!writes(full.calls).some((call) => call.includes("breaker")), `${unfinished} unfinished posted a breaker record`);
  }
  // The per-slot leaf sets the target: 1 x 3 with 1 unfinished leaves room for 2.
  const narrow = afterClear(1);
  assert.equal(await sweep({ github: narrow.github, actions: narrow.github }, clearLimits({ "refire-queue-per-slot": 1 })), 0);
  assert.deepEqual(restarts(narrow.calls), ["RESTART 35", "RESTART 32", "RESTART 36"]);
});

// Other issues' lane runs still unfinished at NOW (12:00), created at `at`.
const unfinishedRuns = (count, at, status = "queued", from = 800) =>
  Array.from({ length: count }, (_, index) => laneRun({ number: from + index, at, status, conclusion: null }));
const STALE_NOTICE = "::notice title=label-unblocked::12 work-resolve-issue run(s) queued 60+ minutes not counted toward the kill-switch re-fire room";

test("a run still queued stale-queued-minutes after it was created is left out of the re-fire room, with a notice naming how many", async (t) => {
  // 3 fresh unfinished plus 12 queued exactly 60 minutes: room 6 - 3 = 3, as with no lost runs.
  const lost = afterClear(3, undefined, unfinishedRuns(12, "2026-10-16T11:00:00Z"));
  const { code, lines } = await printedBy(t, () => sweep({ github: lost.github, actions: lost.github }, clearLimits()));
  assert.equal(code, 0);
  assert.deepEqual(restarts(lost.calls), ["RESTART 35", "RESTART 32", "RESTART 34", "RESTART 36"]);
  assert.ok(lines.some((line) => line.startsWith(STALE_NOTICE)), lines.join("\n"));
  assert.ok(lines.includes("label-unblocked: 3 work-resolve-issue run(s) unfinished, kill-switch re-fire room 3 of 6"), lines.join("\n"));
});

test("a queued run under stale-queued-minutes, an old run in another unfinished status, or one with no creation time still fills the re-fire room", async (t) => {
  for (const [name, extra] of [
    ["queued 59:59", unfinishedRuns(3, "2026-10-16T11:00:01Z")],
    ["in progress for four hours", unfinishedRuns(3, "2026-10-16T08:00:00Z", "in_progress")],
    ["pending for four hours", unfinishedRuns(3, "2026-10-16T08:00:00Z", "pending")],
    ["queued with no creation time", unfinishedRuns(3, undefined).map((run) => ({ ...run, created_at: "not a time" }))],
  ]) {
    const full = afterClear(3, undefined, extra);
    const { lines } = await printedBy(t, () => sweep({ github: full.github, actions: full.github }, clearLimits()));
    assert.deepEqual(restarts(full.calls), ["RESTART 36"], name);
    assert.ok(!lines.some((line) => line.includes("not counted toward the kill-switch re-fire room")), name);
  }
});

test("limits.stale-queued-minutes sets the age: at 120 a run queued an hour still fills the re-fire room", async () => {
  const full = afterClear(3, undefined, unfinishedRuns(3, "2026-10-16T11:00:00Z"));
  assert.equal(await sweep({ github: full.github, actions: full.github }, clearLimits({ "stale-queued-minutes": 120 })), 0);
  assert.deepEqual(restarts(full.calls), ["RESTART 36"]);
});

const QUEUE_HOLD = "::notice title=label-unblocked::the kill-switch re-fire queue listing failed";

test("a failed unfinished-run listing re-fires no breaker trip this sweep, with a hold notice; a failed mint still restarts", async (t) => {
  const fake = afterClear(0, `/repos/${REPO}/actions/workflows/work-resolve-issue.yml/runs?status=`);
  const { code, lines } = await printedBy(t, () => sweep({ github: fake.github, actions: fake.github }, clearLimits()));
  assert.equal(code, 0);
  assert.deepEqual(restarts(fake.calls), ["RESTART 36"]);
  assert.ok(!writes(fake.calls).some((call) => call.includes("breaker")), "a breaker record was posted");
  assert.ok(lines.some((line) => line.startsWith(QUEUE_HOLD)), lines.join("\n"));
});

test("a slot count that cannot be read re-fires no breaker trip this sweep, with a hold notice; a failed mint still restarts", async (t) => {
  const fake = afterClear(0);
  const unread = () => {
    throw new Error("the lane level is unreadable");
  };
  const { code, lines } = await printedBy(t, () => sweep({ github: fake.github, actions: fake.github, slots: unread }, clearLimits()));
  assert.equal(code, 0);
  assert.deepEqual(restarts(fake.calls), ["RESTART 36"]);
  assert.ok(lines.some((line) => line.startsWith(QUEUE_HOLD) && line.includes("the lane level is unreadable")), lines.join("\n"));
});

test("restarts-per-run still caps breaker re-fires under the queue target, the oldest stranded first", async () => {
  const fake = afterClear(0);
  assert.equal(await sweep({ github: fake.github, actions: fake.github }, clearLimits({ "restarts-per-run": 2 })), 0);
  assert.deepEqual(restarts(fake.calls), ["RESTART 35", "RESTART 32"]);
});

// The admit job's upstream-status stop (check-upstream-status) skipped the run
// while Actions listed an outage. The admit job is run 42860916094's, during
// incident hnf21m9jkl3c: `Check upstream status` green after the blocker
// gate, pick-slot and every later job skipped. No model ran, so once the
// status pages read clear (degraded=false, reason=ok, the action's outputs)
// the sweep re-fires it with no wait; until then it waits the hour after the
// run ended that a blocker-gate skip waits.
const OUTAGE_SKIPPED = [
  {
    name: "admit",
    conclusion: "success",
    steps: [
      { name: "Check the trigger", conclusion: "success" },
      { name: "Wait for open blockers", conclusion: "success" },
      { name: "Check upstream status", conclusion: "success" },
      { name: "Stop on untrusted provenance", conclusion: "skipped" },
    ],
  },
  { name: "pick-slot", conclusion: "skipped", steps: [] },
  { name: "resolve-issue", conclusion: "skipped", steps: [] },
];
// Ten minutes before NOW: inside the hour after it, which is 12:50.
const JUST_ENDED = "2026-10-16T11:50:00Z";
const HOUR_AFTER = Date.parse("2026-10-16T12:50:00Z");
const CLEAR = { degraded: "false", reason: "ok" };
const statusPages = (answer) => {
  const reads = [];
  const upstream = async () => {
    reads.push(answer);
    if (answer instanceof Error) throw answer;
    return answer;
  };
  return { reads, upstream };
};

test("a run the upstream-status stop skipped is re-fired on the next sweep once the status pages read clear, with no hour's wait", async () => {
  const { github, actions, calls } = stalledRun({ jobs: OUTAGE_SKIPPED, conclusion: "success", ended: JUST_ENDED });
  const pages = statusPages(CLEAR);
  assert.equal(await sweep({ github, actions, upstream: pages.upstream }), 0);
  assert.deepEqual(writes(calls), refired(30));
  assert.equal(pages.reads.length, 1, "the status pages are read once");
  assert.ok(!writes(calls).some((call) => call.includes("needs-human")));
});

test("a run the upstream-status stop skipped waits its hour while the status pages list an outage, read unknown, or cannot be read", async () => {
  for (const answer of [{ degraded: "true", reason: "Actions partial_outage" }, { degraded: "false", reason: "unknown" }, new Error("fetch failed")]) {
    const early = stalledRun({ jobs: OUTAGE_SKIPPED, conclusion: "success", ended: JUST_ENDED });
    assert.equal(await sweep({ github: early.github, actions: early.actions, upstream: statusPages(answer).upstream }), 0);
    assert.deepEqual(writes(early.calls), [], `re-fired inside the hour on ${answer.message ?? answer.reason}`);
    const due = stalledRun({ jobs: OUTAGE_SKIPPED, conclusion: "success", ended: JUST_ENDED });
    assert.equal(await sweep({ github: due.github, actions: due.actions, now: HOUR_AFTER, upstream: statusPages(answer).upstream }), 0);
    assert.deepEqual(writes(due.calls), refired(30), `not re-fired an hour after the run on ${answer.message ?? answer.reason}`);
  }
});

test("a clear status page re-fires no other stop early: a blocker-gate skip and a breaker trip at a mint still wait their hour", async () => {
  for (const [jobs, logs] of [
    [BLOCKER_SKIPPED, {}],
    [MINT_REFUSED, MINT_KILLED],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs, logs, conclusion: jobs === BLOCKER_SKIPPED ? "success" : "failure", ended: JUST_ENDED });
    const pages = statusPages(CLEAR);
    assert.equal(await sweep({ github, actions, upstream: pages.upstream }, KILL_SWITCH_HOUR), 0);
    assert.deepEqual(writes(calls), [], jobs === BLOCKER_SKIPPED ? "blocker-gate skip" : "breaker trip");
    assert.equal(pages.reads.length, 0, "the status pages are read only for an upstream-status skip");
  }
});

test("upstream-status re-fires share the kill-switch re-fire room: refire-queue-per-slot x SLOTS less the unfinished runs", async () => {
  const numbers = [31, 32, 33, 34, 35];
  const outageWorld = (unfinished) =>
    world({
      openReady: numbers.map((n) => ready(n)),
      comments: Object.fromEntries(numbers.map((n) => [n, [note()]])),
      events: Object.fromEntries(numbers.map((n) => [n, [added(LABELED_AT, OWNER)]])),
      runs: [
        ...numbers.map((n) => ({ ...laneRun({ number: n, conclusion: "success" }), updated_at: JUST_ENDED })),
        ...Array.from({ length: unfinished }, (_, index) => laneRun({ number: 900 + index, at: "2026-10-16T11:50:00Z", status: "queued", conclusion: null })),
      ],
      jobs: Object.fromEntries(numbers.map((n) => [5000 + n, OUTAGE_SKIPPED])),
      openLanePrs: 10,
      blobs: BLOBS,
    });
  // Target 2 x 3 = 6; 3 unfinished leaves room for 3, lowest number first at one run end.
  const room = outageWorld(3);
  assert.equal(await sweep({ github: room.github, actions: room.github, upstream: statusPages(CLEAR).upstream }, clearLimits()), 0);
  assert.deepEqual(restarts(room.calls), ["RESTART 31", "RESTART 32", "RESTART 33"]);
  const full = outageWorld(6);
  assert.equal(await sweep({ github: full.github, actions: full.github, upstream: statusPages(CLEAR).upstream }, clearLimits()), 0);
  assert.deepEqual(restarts(full.calls), [], "re-fired past the queue target");
});

test("a wait on an upstream-status skip is not carried to the next sweep; a blocker-gate skip's wait is", async () => {
  const dir = carryDir();
  const kept = async (jobs, name) => {
    // A wait is kept only for an issue whose listing has an updated time.
    const fake = world({
      openReady: [{ ...ready(30), updated_at: JUST_ENDED }],
      comments: { 30: [note()] },
      events: { 30: [added(LABELED_AT, OWNER)] },
      runs: [{ ...laneRun({ number: 30, conclusion: "success" }), updated_at: JUST_ENDED }],
      jobs: { 5030: jobs },
      openLanePrs: 10,
      blobs: BLOBS,
    });
    const to = join(dir, `${name}.json`);
    assert.equal(await sweep({ github: fake.github, actions: fake.github, upstream: statusPages({ degraded: "true", reason: "Actions major_outage" }).upstream }, { VERDICTS_OUT: to }), 0);
    assert.deepEqual(writes(fake.calls), [], name);
    return JSON.parse(readFileSync(to, "utf8")).decided["30"];
  };
  assert.equal((await kept(OUTAGE_SKIPPED, "outage")).wait, undefined);
  assert.equal((await kept(BLOCKER_SKIPPED, "blocker")).wait.due, HOUR_AFTER);
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
  assert.equal(done.length, 1 + restarted(30).length, done.join("\n"));
  assert.ok(done[0].startsWith(`PATCH /repos/${REPO}/issues/comments/72 `), done[0]);
  assert.ok(done[0].includes("has re-fired it 4 time(s)"), done[0]);
  assert.deepEqual(done.slice(1), restarted(30));
});

test("a refusal whose log does not name the kill switch on the step's last line is a failed mint", async () => {
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

// The read runner resolve-issue calls has no `Request the lane token` step, so
// a broker-check failure for any reason but the kill switch is its failed
// mint: re-fired on the same workflow files up to limits.limit-stops-per-issue,
// limits.reset-clamp-min hours after the run ended, then on the backoff.
test("a broker-check failure not for the kill switch is re-fired as a failed mint, under its bound", async () => {
  const mintCause = "The work-resolve-issue run that `agent-ready` started could not get its lane token, or the token broker's leave to run.";
  for (const [name, logs] of [
    ["workflow-modified", { [BROKER_CHECK_ID]: denied("check", "workflow-modified") }],
    ["no readable log", {}],
  ]) {
    // Two re-fires on these workflow files so far: a failed run would be stranded, a failed mint goes again.
    const again = stalledRun({ jobs: BROKER_REFUSED, logs, ...earlierPumps(2) });
    assert.equal(await sweep({ github: again.github, actions: again.actions }), 0, name);
    assert.deepEqual(writes(again.calls), refired(30), name);
    assert.ok(!writes(again.calls).some((call) => call.includes("needs-human")), name);
    // It waits limits.reset-clamp-min after the run ended, like any failed mint.
    const early = stalledRun({ jobs: BROKER_REFUSED, logs, ended: "2026-10-16T11:30:00Z" });
    assert.equal(await sweep({ github: early.github, actions: early.actions }), 0, name);
    assert.deepEqual(writes(early.calls), [], name);
    // Past the bound: the backoff, 24 hours after the run ended at 10:05.
    const over = stalledRun({ jobs: BROKER_REFUSED, logs, ...earlierPumps(3) });
    assert.equal(await sweep({ github: over.github, actions: over.actions }), 0, name);
    assert.deepEqual(writes(over.calls), [], name);
    const due = stalledRun({ jobs: BROKER_REFUSED, logs, ...earlierPumps(3) });
    assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-17T10:05:00Z") }), 0, name);
    assert.deepEqual(writes(due.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: infraComment(KEY, mintCause, 4) })}`, ...restarted(30)], name);
  }
  // A kill-switch refusal there stays a breaker trip, past the failed-mint bound too.
  const killed = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED, ...earlierPumps(3) });
  assert.equal(await sweep({ github: killed.github, actions: killed.actions }), 0);
  tripped(killed.calls);
});

// Run 40127232943: broker-check's `Check the kill switch` read
// the repository kill switch on, so its broker ask was skipped and the run
// ended green with no job failed and no log naming the reason.
const KILL_SKIPPED = [
  ADMITTED,
  pickSlot,
  {
    name: "resolve-issue / broker-check",
    conclusion: "success",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Ask the broker whether the lane may run", conclusion: "skipped" },
    ],
  },
  { name: "report-skip", conclusion: "skipped", steps: [] },
  {
    name: "resolve-issue / run",
    conclusion: "success",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Assert the broker allowed this attempt", conclusion: "skipped" },
    ],
  },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];

test("a green run whose broker ask the kill switch skipped is a breaker trip, read from the job listing alone", async () => {
  const { github, actions, calls } = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.deepEqual(logReads(calls), []);
  // Three hours on, it is still a trip, never stranded as a run with no report.
  const late = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success" });
  assert.equal(await sweep({ github: late.github, actions: late.actions, now: Date.parse("2026-10-16T14:05:00Z") }), 0);
  tripped(late.calls);
  // No model ran, so the first sweep after it ended re-fires it.
  const recent = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success", ended: "2026-10-16T11:58:00Z" });
  assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0);
  tripped(recent.calls);
});

// A later leg asks the broker again after the API key leg hands off: its
// broker-check's refusal or kill-switch skip is the run's breaker trip too.
const LEG_RAN = [ADMITTED, pickSlot, BROKER_ALLOWED, { name: "resolve-issue / run", conclusion: "success", steps: [{ name: "Run the skill on the API key", conclusion: "success" }] }];
const legCheck = (leg, job) => ({ ...job, name: `${leg} / broker-check` });

test("a later leg's broker-check refused or skipped for the kill switch is a breaker trip", async () => {
  for (const leg of ["resolve-issue-subscription", "resolve-issue-fallback"]) {
    const refused = stalledRun({ jobs: [...LEG_RAN, legCheck(leg, BROKER_REFUSED[2]), { name: "report-outcome", conclusion: "skipped", steps: [] }], logs: CHECK_KILLED });
    assert.equal(await sweep({ github: refused.github, actions: refused.actions }), 0, leg);
    tripped(refused.calls);
    assert.deepEqual(logReads(refused.calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`], leg);
    const skipped = stalledRun({ jobs: [...LEG_RAN, legCheck(leg, KILL_SKIPPED[2]), { name: "report-outcome", conclusion: "skipped", steps: [] }], conclusion: "success" });
    assert.equal(await sweep({ github: skipped.github, actions: skipped.actions }), 0, leg);
    tripped(skipped.calls);
  }
});

// The run a start-gate budget stop leaves (pr-run-activity-read.yml): the
// first call's broker-check ran its kill-switch step, its `Stop on a low
// GITHUB_TOKEN budget until <reset>` step (named with the gate's reset
// output), and skipped the broker ask and the lease, ending green with
// skip-reason budget. That skip-reason skips the call's run job, so its
// issue-fields, scan and summary jobs skip too, and report skips with no lease
// held. No handoff, no scan output: work-resolve-issue's later calls,
// apply-issue-patch and report-outcome all skip, and the run ends green.
const epoch = (at) => Date.parse(at) / 1000;
const budgetStep = (name = `Stop on a low GITHUB_TOKEN budget until ${epoch("2026-10-16T10:30:00Z")}`) => ({ name, conclusion: "success" });
const skippedJob = (name) => ({ name, conclusion: "skipped", steps: [] });
const budgetStopped = (step = budgetStep()) => [
  ADMITTED,
  pickSlot,
  {
    name: "resolve-issue / broker-check",
    conclusion: "success",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      step,
      { name: "Ask the broker whether the lane may run", conclusion: "skipped" },
      { name: "Claim the issue with a lane lease", conclusion: "skipped" },
    ],
  },
  skippedJob("resolve-issue / broker-allowed"),
  skippedJob("resolve-issue / run"),
  skippedJob("resolve-issue / issue-fields"),
  skippedJob("resolve-issue / scan"),
  skippedJob("resolve-issue / summary"),
  skippedJob("resolve-issue / report"),
  { name: "resolve-issue-handoff", conclusion: "success", steps: [{ name: "Read whether the call handed off", conclusion: "success" }] },
  skippedJob("resolve-issue-subscription"),
  skippedJob("resolve-issue-fallback"),
  skippedJob("apply-issue-patch"),
  skippedJob("report-skip"),
  skippedJob("report-outcome"),
];
const BUDGET_STOPPED = budgetStopped();
const BUDGET_RECORD = `${BREAKER_MARKER}\n<!-- work-unblock cause=budget -->\n`;
const budgeted = (calls) => {
  tripped(calls);
  assert.ok(postedBody(calls).startsWith(BUDGET_RECORD), postedBody(calls));
};
const switched = (calls) => {
  tripped(calls);
  assert.ok(!postedBody(calls).includes("cause=budget"), postedBody(calls));
};

test("a run its start gate stopped on the GITHUB_TOKEN budget re-fires once its window has reset, with a budget record, read from the job listing alone", async () => {
  // The sweep runs at 12:00; the run ended at 11:58.
  const ended = "2026-10-16T11:58:00Z";
  const reset = budgetStopped(budgetStep(`Stop on a low GITHUB_TOKEN budget until ${epoch("2026-10-16T12:30:00Z")}`));
  const before = stalledRun({ jobs: reset, conclusion: "success", ended });
  assert.equal(await sweep({ github: before.github, actions: before.actions }), 0);
  assert.deepEqual(writes(before.calls), [], "no record and no re-fire before the reset");
  for (const now of ["2026-10-16T12:30:00Z", "2026-10-16T12:45:00Z"]) {
    const after = stalledRun({ jobs: reset, conclusion: "success", ended });
    assert.equal(await sweep({ github: after.github, actions: after.actions, now: Date.parse(now) }), 0);
    budgeted(after.calls);
    assert.deepEqual(logReads(after.calls), []);
  }
  // A step name with no readable reset, bare or with its expression left
  // unevaluated, is still a budget stop and waits an hour after the run ended.
  for (const name of ["Stop on a low GITHUB_TOKEN budget", "Stop on a low GITHUB_TOKEN budget until ${{ steps.kill.outputs.reset }}"]) {
    const unnamed = budgetStopped(budgetStep(name));
    const early = stalledRun({ jobs: unnamed, conclusion: "success", ended });
    assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-16T12:57:59Z") }), 0);
    assert.deepEqual(writes(early.calls), [], name);
    const due = stalledRun({ jobs: unnamed, conclusion: "success", ended });
    assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-16T12:58:00Z") }), 0);
    budgeted(due.calls);
  }
  // The same listing without the budget step is a switch trip, re-fired at once.
  const plain = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success", ended });
  assert.equal(await sweep({ github: plain.github, actions: plain.actions }), 0);
  switched(plain.calls);
});

test("a budget stop step that skipped is no budget stop", async () => {
  const skipped = { ...budgetStep(), conclusion: "skipped" };
  const jobs = [ADMITTED, pickSlot, { ...KILL_SKIPPED[2], steps: [KILL_SKIPPED[2].steps[0], skipped, KILL_SKIPPED[2].steps[1]] }, ...KILL_SKIPPED.slice(3)];
  const { github, actions, calls } = stalledRun({ jobs, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  switched(calls);
});

// limits.limit-stops-per-issue is 3: three switch trips make the fourth wait
// the flat kill-switch hours; three budget stops do not.
test("budget stops never count toward limits.limit-stops-per-issue or wait the kill-switch hours", async () => {
  const switchTrips = await afterSweeps(3, KILL_SKIPPED);
  const fourthSwitch = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success", ...switchTrips });
  assert.equal(await sweep({ github: fourthSwitch.github, actions: fourthSwitch.actions }), 0);
  assert.deepEqual(writes(fourthSwitch.calls), [], "a fourth switch trip waits");

  // Five budget records, as separate comments, each followed by its re-add.
  const budgetStops = history(Array.from({ length: 5 }, (_, index) => breakerComment(KEY, { repo: REPO, run: 4100 + index, ended: Date.parse("2026-10-16T05:00:00Z"), budget: true })));
  const afterBudget = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success", ...budgetStops });
  assert.equal(await sweep({ github: afterBudget.github, actions: afterBudget.actions }), 0);
  switched(afterBudget.calls);

  const budgetAfterSwitch = stalledRun({ jobs: BUDGET_STOPPED, conclusion: "success", ...switchTrips });
  assert.equal(await sweep({ github: budgetAfterSwitch.github, actions: budgetAfterSwitch.actions }), 0);
  budgeted(budgetAfterSwitch.calls);
});

test("a later budget stop edits the issue's one budget record in place, never posting a second", async () => {
  const once = await afterSweeps(1, BUDGET_STOPPED);
  const recordId = once.comments.at(-1).id;
  const again = stalledRun({ jobs: budgetStopped(budgetStep(`Stop on a low GITHUB_TOKEN budget until ${epoch("2026-10-16T11:30:00Z")}`)), conclusion: "success", ...once });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  const done = writes(again.calls);
  assert.ok(done[0].startsWith(`PATCH /repos/${REPO}/issues/comments/${recordId} `), done[0]);
  assert.ok(done[0].includes("cause=budget"), done[0]);
  assert.ok(!done.some((call) => call.startsWith(`POST /repos/${REPO}/issues/30/comments `)), done.join("\n"));
  assert.deepEqual(done.slice(1), restarted(30));
  // A switch trip after it posts its own record: only budget records are edited.
  const switchAfter = stalledRun({ jobs: KILL_SKIPPED, conclusion: "success", ...once });
  assert.equal(await sweep({ github: switchAfter.github, actions: switchAfter.actions }), 0);
  switched(switchAfter.calls);
});

// One re-fire of a failed run on these workflow files (06:00), then two budget
// stops on the one budget record (re-added 07:00 and 10:00), then a failed run
// ending at 10:05: the backoff counts one re-fire, so it waits 6 hours, not 12.
test("an edited budget record keeps each budget re-fire its own, so none counts toward a later backoff", async () => {
  const failedLater = [ADMITTED, pickSlot, BROKER_ALLOWED, { name: "resolve-issue / run", conclusion: "failure", steps: [{ name: "Request the lane token", conclusion: "success" }] }];
  const unlabeled = (at) => ({ event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: at });
  const first = { id: 71, body: breakerComment(KEY, { repo: REPO, run: 4100, ended: Date.parse("2026-10-16T06:50:00Z"), budget: true }), user: LANES_BOT, created_at: "2026-10-16T07:00:00Z" };
  const before = [added("2026-10-16T05:00:00Z", OWNER), unlabeled("2026-10-16T06:00:00Z"), added("2026-10-16T06:00:01Z"), unlabeled("2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")];
  const second = stalledRun({ jobs: BUDGET_STOPPED, conclusion: "success", comments: [note(), refireNote(KEY, "2026-10-16T06:00:00Z"), first], events: [...before.slice(0, -1), added(LABELED_AT)] });
  assert.equal(await sweep({ github: second.github, actions: second.actions }), 0);
  const patch = writes(second.calls)[0];
  assert.ok(patch.startsWith(`PATCH /repos/${REPO}/issues/comments/71 `), patch);
  const edited = { ...first, body: JSON.parse(patch.slice(patch.indexOf(" {") + 1)).body, updated_at: "2026-10-16T09:59:59Z" };
  const history = {
    comments: [note(), refireNote(KEY, "2026-10-16T06:00:00Z"), edited],
    events: [...before, unlabeled("2026-10-16T09:59:59Z"), added(LABELED_AT)],
  };
  const early = stalledRun({ jobs: failedLater, ...history });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-16T16:04:59Z") }), 0);
  assert.deepEqual(writes(early.calls), [], "one re-fire waits 6 hours");
  const due = stalledRun({ jobs: failedLater, ...history });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-16T16:05:00Z") }), 0);
  const done = writes(due.calls);
  assert.ok(done[0].startsWith(`POST /repos/${REPO}/issues/30/comments `), done.join("\n"));
  assert.ok(done[0].includes("has re-fired it 2 time(s)"), done[0]);
  assert.deepEqual(done.slice(1), restarted(30));
});

test("the budget record says it never counts toward the per-issue bound", () => {
  const body = breakerComment(KEY, { repo: REPO, run: 5030, ended: Date.parse("2026-10-16T10:05:00Z"), budget: true });
  assert.ok(body.startsWith(BUDGET_RECORD), body);
  assert.ok(body.includes(REFUSED_LINK), body);
  assert.ok(body.includes("never counts toward limits.limit-stops-per-issue"), body);
  assert.ok(!breakerComment(KEY, { repo: REPO, run: 5030, ended: 0 }).includes("cause=budget"));
});

test("a green run whose kill-switch check did not run, or whose broker ask ran, is no breaker trip", async () => {
  const [kill, ask] = KILL_SKIPPED[2].steps;
  const check = (steps) => ({ ...KILL_SKIPPED[2], steps });
  for (const [name, broker] of [
    ["kill-switch check skipped", check([{ ...kill, conclusion: "skipped" }, ask])],
    ["no kill-switch check listed", check([ask])],
    ["broker ask ran", check([kill, { ...ask, conclusion: "success" }])],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: [ADMITTED, pickSlot, broker, KILL_SKIPPED[4]], conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), [], name);
  }
});

// broker-check passes kill-switch-ok, so a broker kill-switch refusal ends its
// broker ask green with a `lane-check-stopped` notice, no allow, and the lease
// step skipped; the run job skips and the run ends green. The log's shape is
// saved run 41576258964's broker-check job, its composite step with id
// broker.request.
const checkStoppedLog = (line = "lane-check-stopped: the broker refused the check because a lanes kill switch is on, a designed stop; this run runs no lane and skips the rest") =>
  [
    "2026-11-03T04:35:21.1799019Z ##[group]Run ./.base/.github/actions/request-lane-token",
    "2026-11-03T04:35:21.1800000Z ##[endgroup]",
    "2026-11-03T04:35:21.2126706Z ##[start-action display=Request the lane token;id=broker.request]",
    "2026-11-03T04:35:21.2130000Z ##[group]Run set -euo pipefail",
    "2026-11-03T04:35:21.2140000Z ##[endgroup]",
    `2026-11-03T04:35:22.4470871Z ##[notice]${line}`,
    "2026-11-03T04:35:22.4521682Z ##[end-action id=broker.request;outcome=success;conclusion=success;duration_ms=1239]",
    "",
  ].join("\n");
const CHECK_STOPPED = [
  ADMITTED,
  pickSlot,
  {
    id: BROKER_CHECK_ID,
    name: "resolve-issue / broker-check",
    conclusion: "success",
    runner_id: 12,
    started_at: "2026-10-16T10:01:00Z",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Ask the broker whether the lane may run", conclusion: "success" },
      { name: "Claim the issue with a lane lease", conclusion: "skipped" },
    ],
  },
  { name: "resolve-issue / run", conclusion: "skipped", steps: [] },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];

test("a green run whose broker ask the kill switch stopped is a breaker trip at broker-check, read from one log", async () => {
  const logs = { [BROKER_CHECK_ID]: checkStoppedLog() };
  const { github, actions, calls } = stalledRun({ jobs: CHECK_STOPPED, logs, conclusion: "success" });
  assert.equal(await sweep({ github, actions }), 0);
  tripped(calls);
  assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`]);
  // No model ran, so the first sweep after it ended re-fires it, as a check-stage trip.
  const recent = stalledRun({ jobs: CHECK_STOPPED, logs, conclusion: "success", ended: "2026-10-16T11:58:00Z" });
  assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0);
  tripped(recent.calls);
  // Past the failed-mint bound it still goes as a trip.
  const pumped = stalledRun({ jobs: CHECK_STOPPED, logs, conclusion: "success", ...earlierPumps(3) });
  assert.equal(await sweep({ github: pumped.github, actions: pumped.actions }), 0);
  tripped(pumped.calls);
});

test("a green broker ask whose log does not carry the check-stop notice is a failed mint, never a breaker trip", async () => {
  for (const [name, log] of [
    ["a lookalike notice", checkStoppedLog("lane-check-stopped: the broker refused the check because a lanes kill switch is onward")],
    ["the mint's notice text with the check's prefix", checkStoppedLog("lane-check-stopped: the broker refused the token because a lanes kill switch is on")],
    ["a warning, not a notice", checkStoppedLog().replace("##[notice]", "##[warning]")],
    ["no log", undefined],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: CHECK_STOPPED, logs: log === undefined ? {} : { [BROKER_CHECK_ID]: log }, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
  }
});

test("a broker ask that allowed, so its lease step ran, is no check stop and reads no log", async () => {
  const [admit, slot, check, ...rest] = CHECK_STOPPED;
  for (const conclusion of ["success", "failure"]) {
    const ran = { ...check, steps: check.steps.map((step) => (step.name === "Claim the issue with a lane lease" ? { ...step, conclusion } : step)) };
    const { github, actions, calls } = stalledRun({ jobs: [admit, slot, ran, ...rest], logs: { [BROKER_CHECK_ID]: checkStoppedLog() }, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, conclusion);
    assert.deepEqual(logReads(calls), [], conclusion);
    assert.ok(!writes(calls).some(isBreakerRecord), conclusion);
  }
});

test("a broker-check breaker trip is not re-fired while the issue lane is paused over its cap", async () => {
  for (const jobs of [BROKER_REFUSED, KILL_SKIPPED]) {
    const { github, actions, calls } = stalledRun({
      jobs,
      logs: CHECK_KILLED,
      conclusion: jobs === KILL_SKIPPED ? "success" : "failure",
      ended: "2026-10-16T11:30:00Z",
      openLanePrs: 2,
    });
    assert.equal(await sweep({ github, actions }, PAUSING), 0);
    assert.deepEqual(writes(calls), []);
  }
});

// A GitHub API rate-limit stop before any model turn. Each line is a stop
// line's shape as its writer prints it: rate-guard.mjs's hit-the-limit line
// (run 42976925201's run-checks line, its reset moved to this test's day),
// rate-guard.mjs's stop-floor line (rate-guard.test.mjs's stop-floor
// expectation), and api-budget.bash's api_budget_refuse line, each the failed
// step's last line.
const LIMIT_ID = 120990000001;
const RESET = "2026-10-16T12:30:00Z";
const STOP_LINES = {
  "hit the limit": `GET https://api.github.com/repos/${REPO}/issues/30 hit GitHub's core API rate limit (status 403): no call to it before ${RESET} (x-ratelimit-reset); this step fails`,
  "stop floor": `GET https://api.github.com/repos/${REPO}/issues/30 left GitHub's core API 97 of 5000 requests, at or under its stop-floor share 0.02 (status 200): no call to it before ${RESET} (x-ratelimit-reset); this step fails`,
  "api-budget.bash": `'gh api repos/${REPO}/issues/30' hit GitHub's core API rate limit: no call to it before ${RESET} (x-ratelimit-reset); the call returns 1`,
};
const limitLog = (line) =>
  ["2026-10-16T10:02:00.0000000Z ##[group]Run node .base/.github/scripts/work-resolve-issue/check-blockers.mjs", `2026-10-16T10:02:01.0000000Z ##[error]${line}`, "2026-10-16T10:02:01.1000000Z ##[error]Process completed with exit code 1.", ""].join("\n");
const failedAt = (name, steps) => ({ id: LIMIT_ID, name, conclusion: "failure", runner_id: 13, started_at: "2026-10-16T10:01:00Z", steps });
const SKIPPED_REST = [
  { name: "resolve-issue", conclusion: "skipped", steps: [] },
  { name: "report-outcome", conclusion: "skipped", steps: [] },
];
const PRE_MODEL_LIMITED = {
  admit: [failedAt("admit", [{ name: "Check the kill switch", conclusion: "success" }, { name: "Check the trigger", conclusion: "success" }, { name: "Wait for open blockers", conclusion: "failure" }]), { name: "pick-slot", conclusion: "skipped", steps: [] }, ...SKIPPED_REST],
  "pick-slot": [ADMITTED, failedAt("pick-slot", [{ name: "Check the WIP cap", conclusion: "success" }, { name: "Resolve the issue dimensions' timeout", conclusion: "failure" }]), ...SKIPPED_REST],
  "broker-check": [
    ADMITTED,
    pickSlot,
    failedAt("resolve-issue / broker-check", [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Ask the broker whether the lane may run", conclusion: "success" },
      { name: "Claim the issue with a lane lease", conclusion: "failure" },
    ]),
    { name: "resolve-issue / run", conclusion: "skipped", steps: [] },
    { name: "report-outcome", conclusion: "skipped", steps: [] },
  ],
  "a call's run job": [
    ADMITTED,
    pickSlot,
    BROKER_ALLOWED,
    failedAt("resolve-issue / run", [{ name: "Resolve the config", conclusion: "failure" }, { name: "Run the skill on the API key", conclusion: "skipped" }]),
    { name: "report-outcome", conclusion: "skipped", steps: [] },
  ],
};
const AFTER_RESET = Date.parse("2026-10-16T12:31:00Z");
// A rate-limit stop's records name the GitHub API rate limit and the reset, never the broker.
const limitCause = (reset) => `The work-resolve-issue run that \`agent-ready\` started stopped on GitHub's API rate limit before any model turn; the limit reset at ${reset}.`;
const limitRefired = (reset) => [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: refireComment(KEY, limitCause(reset)) })}`, ...restarted(30)];

test("a run a GitHub rate-limit stop failed before any model turn is re-fired as a failed mint once the reset it names has passed, from one log", async () => {
  for (const [job, jobs] of Object.entries(PRE_MODEL_LIMITED)) {
    for (const [wording, line] of Object.entries(STOP_LINES)) {
      const name = `${job}, ${wording}`;
      const logs = { [LIMIT_ID]: limitLog(line) };
      // 12:00 is past the hour after the 10:05 end, but before the 12:30 reset.
      const early = stalledRun({ jobs, logs });
      assert.equal(await sweep({ github: early.github, actions: early.actions }), 0, name);
      assert.deepEqual(writes(early.calls), [], `${name}: re-fired before the reset`);
      assert.deepEqual(logReads(early.calls), [`GET /repos/${REPO}/actions/jobs/${LIMIT_ID}/logs`], name);
      const due = stalledRun({ jobs, logs });
      assert.equal(await sweep({ github: due.github, actions: due.actions, now: AFTER_RESET }), 0, name);
      assert.deepEqual(writes(due.calls), limitRefired(RESET), `${name}: not re-fired after the reset`);
      assert.ok(!writes(due.calls).some((call) => call.includes("needs-human")), name);
    }
  }
});

test("a rate-limit stop before any model turn is on the failed-mint bound and backoff, not the failed-run one", async () => {
  const jobs = PRE_MODEL_LIMITED.admit;
  const logs = { [LIMIT_ID]: limitLog(STOP_LINES["hit the limit"].replace(RESET, "2026-10-16T10:51:58Z")) };
  // Two re-fires on these workflow files: a failed run waits 3 hours, a failed mint goes again.
  const again = stalledRun({ jobs, logs, ...earlierPumps(2) });
  assert.equal(await sweep({ github: again.github, actions: again.actions }), 0);
  assert.deepEqual(writes(again.calls), limitRefired("2026-10-16T10:51:58Z"));
  // Past the bound: the failed-mint backoff, 24 hours after the run ended at 10:05, its record naming the rate limit.
  const over = stalledRun({ jobs, logs, ...earlierPumps(3) });
  assert.equal(await sweep({ github: over.github, actions: over.actions }), 0);
  assert.deepEqual(writes(over.calls), []);
  const due = stalledRun({ jobs, logs, ...earlierPumps(3) });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-17T10:05:00Z") }), 0);
  const backoffRecord = writes(due.calls);
  assert.deepEqual(backoffRecord, [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: infraComment(KEY, limitCause("2026-10-16T10:51:58Z"), 4) })}`, ...restarted(30)]);
  assert.ok(!backoffRecord[0].includes("broker"), backoffRecord[0]);
  // An early reset still waits limits.reset-clamp-min after the run ended.
  const recent = stalledRun({ jobs, logs, ended: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0);
  assert.deepEqual(writes(recent.calls), []);
});

// Run 42976995398: the subscription leg ran the model, then
// run-checks and apply-issue-patch's trigger check failed. The same stop line
// in a pre-model job of a run where a model step ran is no rate-limit stop.
test("a rate-limit stop line in a run where a model step ran is not did-no-work: no log is read and the failed-run re-fire is unchanged", async () => {
  const modelRan = [
    ADMITTED,
    pickSlot,
    { ...BROKER_ALLOWED, name: "resolve-issue-subscription / broker-check" },
    { name: "resolve-issue-subscription / run", conclusion: "success", steps: [{ name: "Run the skill on the OAuth token", conclusion: "success" }] },
    { ...failedAt("resolve-issue-fallback / broker-check", [{ name: "Claim the issue with a lane lease", conclusion: "failure" }]), id: LIMIT_ID + 1 },
    { name: "apply-issue-patch / run", conclusion: "failure", steps: [{ name: "Check the trigger", conclusion: "failure" }, { name: "Request the lane token", conclusion: "skipped" }] },
    failedAt("run-checks", [{ name: "Resolve the config", conclusion: "failure" }]),
  ];
  const summarized = [
    ...PRE_MODEL_LIMITED["broker-check"].slice(0, 3),
    { name: "resolve-issue-subscription / summary", conclusion: "success", steps: [{ name: "Summarize the reused branch on the OAuth token", conclusion: "success" }] },
  ];
  for (const [name, jobs] of [
    ["the model ran", modelRan],
    ["the summary pass ran", summarized],
  ]) {
    const line = limitLog(STOP_LINES["hit the limit"]);
    const { github, actions, calls } = stalledRun({ jobs, logs: { [LIMIT_ID]: line, [LIMIT_ID + 1]: line } });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(logReads(calls), [], name);
    // The failed-run path re-fires it at once, inside the reset.
    assert.deepEqual(writes(calls), refired(30), name);
  }
});

test("a pre-model failure whose log cannot be read, or whose last line is no rate-limit stop, keeps the failed-run re-fire", async () => {
  const notStop = limitLog("GET https://api.github.com/repos/o/r/issues/30 failed with status 502");
  const earlierLine = ["2026-10-16T10:02:00.0000000Z ##[error]" + STOP_LINES["hit the limit"], notStop].join("\n");
  for (const [name, logs] of [
    ["no log", {}],
    ["another error", { [LIMIT_ID]: notStop }],
    ["a stop line before the step's last line", { [LIMIT_ID]: earlierLine }],
    ["over the size cap", { [LIMIT_ID]: `${"x".repeat(2 * 1024 * 1024)}\n${limitLog(STOP_LINES["hit the limit"])}` }],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs: PRE_MODEL_LIMITED.admit, logs });
    assert.equal(await sweep({ github, actions }), 0, name);
    assert.deepEqual(writes(calls), refired(30), name);
    // Past the per-version re-fire it waits the failed-again hours, as a failed run does.
    const again = stalledRun({ jobs: PRE_MODEL_LIMITED.admit, logs, ...earlierPumps(2) });
    assert.equal(await sweep({ github: again.github, actions: again.actions }), 0, name);
    assert.deepEqual(writes(again.calls), [], name);
  }
});

// admit and pick-slot check the kill switch first; a switch that is on skips
// their first API step and ends the run green with every later job skipped.
const ADMIT_KILLED = [
  {
    name: "admit",
    conclusion: "success",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Install resolve-config's packages", conclusion: "skipped" },
      { name: "Check the trigger", conclusion: "skipped" },
      { name: "Wait for open blockers", conclusion: "skipped" },
    ],
  },
  { name: "pick-slot", conclusion: "skipped", steps: [] },
  ...SKIPPED_REST,
];
const PICK_SLOT_KILLED = [
  ADMITTED,
  {
    name: "pick-slot",
    conclusion: "success",
    steps: [
      { name: "Check the kill switch", conclusion: "success" },
      { name: "Check the WIP cap", conclusion: "skipped" },
      { name: "Hold on an unknown WIP cap", conclusion: "skipped" },
    ],
  },
  { name: "report-skip", conclusion: "skipped", steps: [] },
  ...SKIPPED_REST,
];

test("an admit or pick-slot kill-switch skip is a breaker trip at broker-check, read from the job listing alone and re-fired at the first sweep", async () => {
  for (const [name, jobs] of [
    ["admit", ADMIT_KILLED],
    ["pick-slot", PICK_SLOT_KILLED],
  ]) {
    const { github, actions, calls } = stalledRun({ jobs, conclusion: "success" });
    assert.equal(await sweep({ github, actions }), 0, name);
    tripped(calls);
    assert.deepEqual(logReads(calls), [], name);
    const recent = stalledRun({ jobs, conclusion: "success", ended: "2026-10-16T11:58:00Z" });
    assert.equal(await sweep({ github: recent.github, actions: recent.actions }), 0, name);
    tripped(recent.calls);
  }
  // The same jobs with their API steps run are no trip: pick-slot's is a WIP
  // cap skip, re-fired with a plain record, and admit's a blocker-gate skip,
  // which waits while its blocker is open.
  const ran = (jobs, job) => jobs.map((item) => (item.name === job ? { ...item, steps: item.steps.map((step) => ({ ...step, conclusion: "success" })) } : item));
  const capped = stalledRun({ jobs: ran(PICK_SLOT_KILLED, "pick-slot"), conclusion: "success" });
  assert.equal(await sweep({ github: capped.github, actions: capped.actions }), 0);
  assert.deepEqual(writes(capped.calls), refired(30));
  const admitted = stalledRun({ jobs: ran(ADMIT_KILLED, "admit"), conclusion: "success", blockedBy: { 30: [issue(31)] } });
  assert.equal(await sweep({ github: admitted.github, actions: admitted.actions }), 0);
  assert.deepEqual(writes(admitted.calls), []);
});

// With the switch off, a failed admit install also leaves `Check the trigger`
// skipped, and a failed pick-slot can leave `Check the WIP cap` skipped: each
// job ends red, so the run is a failed run, never a kill-switch trip.
test("an admit whose install failed, or a pick-slot that failed, with its gated step skipped is a failed run, not a breaker trip", async () => {
  const failedJob = (jobs, name, edit) => jobs.map((item) => (item.name === name ? { ...item, conclusion: "failure", steps: item.steps.map(edit) } : item));
  for (const [name, jobs] of [
    ["admit install failed", failedJob(ADMIT_KILLED, "admit", (step) => (step.name === "Install resolve-config's packages" ? { ...step, conclusion: "failure" } : step))],
    ["pick-slot failed", failedJob(PICK_SLOT_KILLED, "pick-slot", (step) => step)],
  ]) {
    // The failed-run path: re-fired at once with its plain record, no breaker record.
    const fresh = stalledRun({ jobs, conclusion: "failure" });
    assert.equal(await sweep({ github: fresh.github, actions: fresh.actions }), 0, name);
    assert.deepEqual(writes(fresh.calls), refired(30), name);
    // Re-fired twice on these workflow files already: a failed run waits the failed-again hours, a breaker trip would not.
    const again = stalledRun({ jobs, conclusion: "failure", ...earlierPumps(2) });
    assert.equal(await sweep({ github: again.github, actions: again.actions }), 0, name);
    assert.deepEqual(writes(again.calls), [], name);
  }
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
  // A kill-switch skip in admit or pick-slot is read as its first API step skipped after the check.
  for (const [id, step] of [
    ["admit", "Check the trigger"],
    ["pick-slot", "Check the WIP cap"],
  ]) {
    const names = steps(caller[id]);
    assert.ok(names.indexOf("Check the kill switch") >= 0 && names.indexOf("Check the kill switch") < names.indexOf(step), id);
    assert.match(caller[id], new RegExp(String.raw`^ {6}- name: ${step}\n(?: {8}.*\n)*? {8}if: steps\.kill\.outputs\.proceed (?:== 'true'|!= 'false')\n`, "m"), id);
  }
  // Every call of the read runner is a leg stoppedStale reads.
  const calls = Object.keys(caller).filter((id) => /^ {4}uses: \.\/\.github\/workflows\/pr-run-activity-read\.yml\b/m.test(caller[id]));
  assert.deepEqual(calls, ["resolve-issue", "resolve-issue-subscription", "resolve-issue-fallback"]);
  const read = jobs(workflow("pr-run-activity-read.yml"));
  assert.ok(steps(read["broker-check"]).includes("Ask the broker whether the lane may run"));
  assert.ok(steps(read["broker-check"]).includes("Check the kill switch"));
  // A green broker ask is a stop exactly when the lease step after it, which runs only on an allow, skipped.
  const checkSteps = steps(read["broker-check"]);
  assert.ok(checkSteps.indexOf("Claim the issue with a lane lease") > checkSteps.indexOf("Ask the broker whether the lane may run"));
  assert.match(read["broker-check"], /^ {6}- name: Claim the issue with a lane lease\n {8}id: lease\n {8}if: inputs\.issue-number != '' && steps\.broker\.outcome == 'success' && steps\.broker\.outputs\.allowed == 'true'\n/m);
  // The in-slot blocker stop runs after the lease, so a green check with it is no check stop.
  assert.ok(checkSteps.indexOf("Stop on an open blocker") > checkSteps.indexOf("Claim the issue with a lane lease"));
  assert.ok(read.run !== undefined);
  assert.ok(steps(read.run).includes("Stop on stale workflow files"));
  // broker-check's budget step follows its kill-switch step, runs exactly on a
  // budget stop, and carries the gate's reset in its name; its gate reads the
  // budget. The model job's gate checks the switches only.
  const budgetName = "Stop on a low GITHUB_TOKEN budget until ${{ steps.kill.outputs.reset }}";
  const checkNamed = steps(read["broker-check"]);
  assert.equal(checkNamed.indexOf(budgetName), checkNamed.indexOf("Check the kill switch") + 1);
  assert.match(read["broker-check"], /^ {6}- name: Stop on a low GITHUB_TOKEN budget until \$\{\{ steps\.kill\.outputs\.reset \}\}\n {8}if: steps\.kill\.outputs\.cause == 'budget'\n/m);
  // Its gate reads the budget on a starting caller's first call, and a budget
  // stop sets skip-reason budget, which skips the run job.
  assert.match(read["broker-check"], /^ {10}budget: \$\{\{ inputs\.start-gate && \(inputs\.fallback == '' \|\| inputs\.fallback == 'credit-stop'\) && 'true' \|\| 'false' \}\}$/m);
  assert.match(read["broker-check"], /^ {6}skip-reason: \$\{\{ steps\.kill\.outputs\.cause == 'budget' && 'budget' \|\| steps\.broker\.outputs\.skip-reason \}\}$/m);
  assert.match(read.run, /^ {6}&& needs\.broker-check\.outputs\.skip-reason == ''$/m);
  assert.match(caller["resolve-issue"], /^ {6}start-gate: true$/m);
  assert.ok(!steps(read.run).some((name) => name.startsWith("Stop on a low GITHUB_TOKEN budget")));
  assert.doesNotMatch(read.run, /^ {10}budget:/m);
  for (const id of ["broker-check", "run"]) {
    assert.doesNotMatch(read[id], /^ {4}name:/m, `read runner job ${id} keeps its id as its name`);
  }
  // The write runner mints; the read runner resolve-issue calls never does.
  assert.ok(Object.values(jobs(workflow("pr-run-activity-write.yml"))).some((block) => steps(block).includes("Request the lane token")));
  assert.ok(!Object.values(read).some((block) => steps(block).includes("Request the lane token")));
  // A stopped mint is read from the stage step after it, which runs exactly when the token is set.
  const write = jobs(workflow("pr-run-activity-write.yml")).run;
  const named = steps(write);
  assert.ok(named.indexOf("Stage the activity from the base") > named.indexOf("Request the lane token"));
  assert.match(write, /^ {6}- name: Stage the activity from the base\n {8}id: stage\n {8}if: steps\.lane-token\.outputs\.token != ''\n/m);
});

// Each re-runner check matches by id. The dispatch lane cannot read its run's
// record, so it refuses every re-run; work-unblock's who step reads the record
// with the job token.
test("the workflows match a re-runner by id: the dispatch lane refuses a re-run, and the who step reads this run's record", () => {
  const step = (file, name) => {
    const text = readFileSync(join(HERE, "../../workflows", file), "utf8");
    const start = text.indexOf(`      - name: ${name}\n`);
    assert.ok(start >= 0, `${file}: ${name}`);
    const end = text.indexOf("\n      - name: ", start + 1);
    return text.slice(start, end < 0 ? undefined : end);
  };
  const dispatch = step("eval-browser-dispatch.yml", "Check the dispatcher is a trusted human");
  assert.match(dispatch, /^ {10}if \[ "\$GITHUB_RUN_ATTEMPT" != 1 \]; then\n {12}echo "::error::rerun-refused: [^\n]*"\n {12}exit 1\n {10}fi$/m);
  assert.ok(dispatch.indexOf("GITHUB_RUN_ATTEMPT") < dispatch.indexOf("jq -e"), "the re-run refusal comes before the list check");
  assert.doesNotMatch(dispatch, /triggering_actor|TRIGGERING_ACTOR/);
  const who = step("work-unblock.yml", "Check who closed the issue");
  assert.match(who, /^ {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}$/m);
  assert.match(who, /label-unblocked\.mjs --check-closer$/m);
  assert.doesNotMatch(who, /triggering_actor|TRIGGERING_ACTOR/);
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
// The issue carries `status: ready`, as admission left it.
function lanePr({ pulls = [lanePull()], comments = [note()], events = [added(LABELED_AT, OWNER)], labels = ["status: ready"], runs = [] } = {}) {
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
  `SET ${n} needs-triage`,
];
const CLOSED_PR = () => lanePull({ pr: 7493, merged: false, body: "Closes #30\n" });

// Owner 2026-10-24: the hand-off is no dead end. The Work status moves to
// needs-triage, off ready and agent-ready, so the triage sweep re-dispatches
// intake, whose fresh ready re-admits it; no label is written.
test("a lane PR merged with Refs: hands the issue to triage: the comment, then the Work status at needs-triage, no label write", async () => {
  const { github, actions, calls } = lanePr();
  assert.equal(await sweep({ github, actions }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7805));
  assert.ok(!writes(calls).some((call) => call.includes("/labels")));
  // The comment went out but the field write did not: only the field moves.
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
  // The comment went out but the field write did not: only the field moves.
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

// The pr-merge lane closed the PR at the verify cap and restarted or parked
// the issue itself (babysit_verify_evidence capped_close): no hand-off. Only
// the lanes App's record counts; anyone can write the marker.
test("a lane PR the pr-merge lane closed at the verify cap hands nothing off", async () => {
  const capped = { id: 62, body: `<!-- verify-capped-close pr=7493 heads=${"1".repeat(40)} attempt=1 of=1 -->\nPull request #7493: closed.`, user: LANES_BOT, created_at: "2026-10-16T11:46:00Z" };
  const { github, calls, lines } = lanePr({ pulls: [CLOSED_PR()], comments: [note(), capped] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
  const forged = lanePr({ pulls: [CLOSED_PR()], comments: [note(), { ...capped, user: OWNER }] });
  assert.equal(await sweep({ github: forged.github }), 0);
  assert.deepEqual(writes(forged.calls), triaged(30, 7493, refsClosedComment(7493)));
});

// A record with no attempt: the issue did not carry agent-ready when the
// pr-merge lane read it, so that lane started nothing, and the closed PR is
// handed to triage as any other.
test("a verify-cap record that started no attempt still hands the issue off", async () => {
  const unstarted = { id: 63, body: `<!-- verify-capped-close pr=7493 heads=${"1".repeat(40)} -->\nPull request #7493: closed.`, user: LANES_BOT, created_at: "2026-10-16T11:46:00Z" };
  const { github, calls } = lanePr({ pulls: [CLOSED_PR()], comments: [note(), unstarted] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7493, refsClosedComment(7493)));
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
    .filter((call) => /^SET \d+ needs-triage$/.test(call))
    .map((call) => Number(call.split(" ")[1]));
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
    labels: ["needs-human", "status: ready"],
    comments: [note(), holdNote()],
    events: [added(LABELED_AT, OWNER), humanLabeled()],
    ...extra,
  });

test("a Refs PR merging lifts the needs-human report-outcome set for it: the Work status at needs-triage, no label write", async () => {
  const { github, calls } = refsHeld();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7805));
});

test("a hand-off that lifts needs-human sets the Work status to needs-triage after the comment, and removes no label", async () => {
  const { github, calls, writer } = refsHeld();
  assert.equal(await sweep({ github, writer }), 0);
  const [comment] = triaged(30, 7805);
  assert.deepEqual(writes(calls), [comment, "SET 30 needs-triage"]);
});

test("a Refs PR closed unmerged lifts the needs-human report-outcome set for it and hands the issue to triage", async () => {
  const { github, calls } = refsHeld({ pulls: [lanePull({ merged: false })] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), triaged(30, 7805, refsClosedComment(7805)));
});

test("an issue carrying security: outside-actor is never handed to triage when its Refs PR ends, and keeps needs-human", async () => {
  for (const merged of [true, false]) {
    const { github, calls } = refsHeld({ labels: ["needs-human", "security: outside-actor"], pulls: [lanePull({ merged })] });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], `merged: ${merged}`);
  }
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
    for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info"]) {
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

test("a hand-off whose field write failed is finished by the next sweep with the field only, no second comment", async (t) => {
  const first = lanePr({ pulls: [CLOSED_PR()] });
  const writer = {
    ...first.writer,
    set: async (number, state) => {
      first.calls.push(`SET ${number} ${state}`);
      throw new Error("POST failed with status 502");
    },
  };
  const log = t.mock.method(console, "log", () => {});
  assert.equal(await sweep({ github: first.github, writer }), 1);
  log.mock.restore();
  // The field stays at agent-ready, so the next sweep comes back to the issue.
  assert.deepEqual(writes(first.calls), triaged(30, 7493, refsClosedComment(7493)));
  const next = lanePr({
    pulls: [CLOSED_PR()],
    comments: [note(), { id: 63, body: refsClosedComment(7493), user: LANES_BOT, created_at: "2026-10-16T11:47:00Z" }],
  });
  assert.equal(await sweep({ github: next.github }), 0);
  assert.deepEqual(writes(next.calls), triaged(30, 7493).slice(1));
});

// The hand-off removes no queue label, whichever the issue carries: the Work
// status field write alone moves it.
test("a hand-off removes no queue label, admission-deferred included, and sets the Work status alone", async () => {
  const bare = lanePr({ pulls: [CLOSED_PR()], labels: [] });
  assert.equal(await sweep({ github: bare.github }), 0);
  assert.deepEqual(writes(bare.calls), triaged(30, 7493, refsClosedComment(7493)));
  const deferred = lanePr({ pulls: [CLOSED_PR()], labels: ["status: ready", "admission-deferred"] });
  assert.equal(await sweep({ github: deferred.github }), 0);
  assert.deepEqual(writes(deferred.calls), triaged(30, 7493, refsClosedComment(7493)));
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

// The workflow run listing as GitHub documents it: `created=a..b` keeps runs
// created from a through b, both ends included (search syntax: `n..*` is
// `>=n`), newest first in pages of `per_page`, with `total_count`.
function runListing(runs) {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(path);
    const params = new URL(path, "https://x").searchParams;
    const [from, to] = params.get("created").split("..").map(Date.parse);
    const page = Number(params.get("page"));
    const size = Number(params.get("per_page"));
    const kept = runs
      .filter((run) => Date.parse(run.created_at) >= from && Date.parse(run.created_at) <= to)
      .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.id - a.id);
    return { total_count: kept.length, workflow_runs: kept.slice((page - 1) * size, page * size) };
  };
  return { actions, calls };
}
const runAt = (id, title, at) => ({ id, display_title: title, created_at: at, status: "completed", updated_at: at });
const T0 = Date.parse("2026-10-16T10:00:00Z");
// #30's window is 10:00:00..10:10:00 (its label at 10:00:00.500 cut to the
// second), #31's 10:05:00..10:15:00, overlapping it, and #32's three hours on.
const ADDED = { 30: T0 + 500, 31: T0 + 5 * 60_000, 32: T0 + 3 * 3_600_000 };
const WINDOW_RUNS = [
  runAt(1, "Fix #30", "2026-10-16T10:00:00Z"),
  runAt(2, "Fix #30", "2026-10-16T10:10:00Z"),
  runAt(3, "Fix #30", "2026-10-16T10:10:01Z"),
  runAt(4, "fix(review): explain-change artifact medium", "2026-10-16T10:02:00Z"),
  runAt(5, "Fix #31", "2026-10-16T10:15:00Z"),
  runAt(6, "Fix #31", "2026-10-16T10:04:59Z"),
  runAt(7, "Fix #32", "2026-10-16T13:00:30Z"),
  ...Array.from({ length: 150 }, (_, i) => runAt(100 + i, "Fix #999", new Date(T0 + 5 * 60_000 + i * 1000).toISOString().replace(/\.\d{3}Z$/, "Z"))),
];
const picked = ({ mine, untitled }) => ({ mine: mine.map((run) => run.id), untitled });

test("the shared run listing gives each issue the runs its own window lists, boundary seconds included", async () => {
  const shared = runListing(WINDOW_RUNS);
  const runsOf = sharedLaneRuns(shared.actions, REPO);
  const got = {};
  for (const [number, addedAt] of Object.entries(ADDED)) {
    got[number] = picked(await runsOf(Number(number), addedAt));
  }
  // #30 keeps its runs at the window's first and last second and not the one
  // a second past it; the untitled run counts for #30's window only.
  assert.deepEqual(got, {
    30: { mine: [2, 1], untitled: 1 },
    31: { mine: [5], untitled: 0 },
    32: { mine: [7], untitled: 0 },
  });
  // The per-issue listing, the old path, answers the same for each issue.
  const own = runListing(WINDOW_RUNS);
  for (const [number, addedAt] of Object.entries(ADDED)) {
    assert.deepEqual(picked(await laneRuns(own.actions, REPO, Number(number), addedAt)), got[number], `#${number}`);
  }
  // One listing of 156 runs (two pages) for #30 and #31, whose labels fall in
  // the 10:00 hour, and one page for #32's 13:00 hour, where each issue on its
  // own took 2, 2 and 1.
  assert.equal(shared.calls.length, 3, shared.calls.join("\n"));
  assert.equal(own.calls.length, 5, own.calls.join("\n"));
  assert.ok(shared.calls[0].includes(`created=${encodeURIComponent("2026-10-16T10:00:00Z..2026-10-16T11:10:00Z")}&per_page=100&page=1`), shared.calls[0]);
  assert.ok(shared.calls[2].includes(`created=${encodeURIComponent("2026-10-16T13:00:00Z..2026-10-16T14:10:00Z")}&per_page=100&page=1`), shared.calls[2]);
});

test("a span over the listing's 1,000-run cap lists each of its issues on its own", async () => {
  const many = Array.from({ length: 1001 }, (_, i) => runAt(10_000 + i, "Fix #999", new Date(T0 + (i % 300) * 1000).toISOString().replace(/\.\d{3}Z$/, "Z")));
  const { actions, calls } = runListing([...WINDOW_RUNS, ...many]);
  const runsOf = sharedLaneRuns(actions, REPO);
  assert.deepEqual(picked(await runsOf(31, ADDED[31])), { mine: [5], untitled: 0 });
  const range = (from, to) => `created=${encodeURIComponent(`${from}..${to}`)}`;
  assert.equal(calls.filter((call) => call.includes(range("2026-10-16T10:00:00Z", "2026-10-16T11:10:00Z"))).length, 1, calls.join("\n"));
  assert.ok(calls.some((call) => call.includes(range("2026-10-16T10:05:00Z", "2026-10-16T10:15:00Z"))), calls.join("\n"));
});

test("a failed shared listing fails the issue that asked and is read again for the next", async () => {
  const { actions: listing } = runListing(WINDOW_RUNS);
  let fail = true;
  const actions = async (method, path) => {
    if (fail) {
      fail = false;
      throw new Error(`${method} ${path} failed with status 502`);
    }
    return listing(method, path);
  };
  const runsOf = sharedLaneRuns(actions, REPO);
  await assert.rejects(runsOf(30, ADDED[30]), /status 502/);
  assert.deepEqual(picked(await runsOf(31, ADDED[31])), { mine: [5], untitled: 0 });
});

test("a sweep lists the lane runs of two failed issues with near labels once, and re-fires both", async () => {
  const fake = world({
    openReady: [ready(30), ready(31)],
    comments: { 30: [note()], 31: [note()] },
    events: { 30: [added(LABELED_AT, OWNER)], 31: [added("2026-10-16T10:04:00Z", OWNER)] },
    runs: [laneRun(), laneRun({ number: 31, at: "2026-10-16T10:04:05Z" })],
    blobs: BLOBS,
  });
  assert.equal(await sweep({ github: fake.github, actions: fake.github }), 0);
  assert.deepEqual(writes(fake.calls), [...refired(30), ...refired(31)]);
  const listings = fake.calls.filter((call) => call.includes("/work-resolve-issue.yml/runs?event=issues"));
  assert.deepEqual(listings, [`GET /repos/${REPO}/actions/workflows/work-resolve-issue.yml/runs?event=issues&created=${encodeURIComponent("2026-10-16T10:00:00Z..2026-10-16T11:10:00Z")}&per_page=100&page=1`]);
});

test("a label in a span's last second has its whole window from that span's one listing", async () => {
  const late = [runAt(8, "Fix #33", "2026-10-16T10:59:59Z"), runAt(9, "Fix #33", "2026-10-16T11:09:59Z"), runAt(10, "Fix #33", "2026-10-16T11:10:00Z")];
  const addedAt = Date.parse("2026-10-16T10:59:59Z");
  const shared = runListing([...WINDOW_RUNS, ...late]);
  const got = picked(await sharedLaneRuns(shared.actions, REPO)(33, addedAt));
  // The per-issue listing, the old path, is the expected answer.
  assert.deepEqual(got, picked(await laneRuns(runListing([...WINDOW_RUNS, ...late]).actions, REPO, 33, addedAt)));
  assert.deepEqual(got, { mine: [9, 8], untitled: 0 });
  assert.ok(shared.calls.every((call) => call.includes(`created=${encodeURIComponent("2026-10-16T10:00:00Z..2026-10-16T11:10:00Z")}`)), shared.calls.join("\n"));
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
    // Created at 10:00:03, two hours before NOW: past stale-queued-minutes, which only the re-fire room ignores.
    ["a queued run, one queued past stale-queued-minutes included", { runs: [laneRun({ status: "queued", conclusion: null })] }],
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

test("a stale queued run naming no issue does not refuse a reopened fix issue's relabel; a fresh one does, and a stale one naming the issue still holds it", async () => {
  const untitled = (at, number) => ({ ...laneRun({ number, at, status: "queued", conclusion: null }), display_title: "Fix the thing" });
  // Twelve runs queued since 10:00, two hours before NOW: lost, so not unsure.
  const lost = reopened({ runs: Array.from({ length: 12 }, (_, index) => untitled("2026-10-16T10:00:00Z", 800 + index)) });
  assert.equal(await sweep({ github: lost.github, actions: lost.actions }), 0);
  assert.deepEqual(writes(lost.calls), relabeled(30));
  // One queued at 11:50, ten minutes before NOW, may still start.
  const fresh = reopened({ runs: [untitled("2026-10-16T11:50:00Z", 800)] });
  assert.equal(await sweep({ github: fresh.github, actions: fresh.actions }), 0);
  assert.deepEqual(writes(fresh.calls), [], "a fresh untitled queued run");
  // This issue's own run, queued two hours, still counts as in flight.
  const own = reopened({ runs: [laneRun({ number: 30, at: "2026-10-16T10:00:00Z", status: "queued", conclusion: null })] });
  assert.equal(await sweep({ github: own.github, actions: own.actions }), 0);
  assert.deepEqual(writes(own.calls), [], "a stale queued run naming the issue");
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
  assert.equal(await sweep({ github, actions: base, writer: base.writer }), 0);
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
// deferred issue's Work status is deferred, which each sweep revisits
// oldest first; restarts and re-fires of admitted issues are never paced.
const deferredLabel = (n) => `SET ${n} deferred`;
const readied = (n) => [labeled(n)];
// A dropped deferral: the Work status back to ready, or to needs-triage when
// the issue lost ready or no trusted account set it.
const undeferred = (n, state = "ready") => `SET ${n} ${state}`;
// n queued issues that no lane PR names.
const queuedN = (n) => Array.from({ length: n }, (_, i) => 100 + i);

test("at the queued cap past pause-from a newly unblocked issue is deferred, not labeled", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = world({ ...oneDependentWorld(), queuedIssues: queuedN(24) });
  assert.equal(await main({ env: envFor({}, PAUSING), github, writer }), 0);
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
// true): that admits nothing, with or without pause-from.
test("an incomplete search answer defers a newly unblocked issue, with or without pause-from, and names why", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  for (const config of [PAUSING, {}]) {
    const { github, calls, writer } = world({ ...oneDependentWorld(), searchIncomplete: true });
    assert.equal(await main({ env: envFor({}, config), github, writer }), 0);
    assert.deepEqual(writes(calls), [deferredLabel(20)], JSON.stringify(config));
  }
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #20 admission deferred: GitHub search answered incomplete results"), lines.join("\n"));
  assert.ok(!lines.some((line) => line.includes("at the queued cap")), lines.join("\n"));
});

// A queued count check-wip-cap could not read (admission_basis fail-open)
// admits nothing either, as intake's admission defers on it.
test("a queued count that could not be read defers a newly unblocked issue, with or without pause-from, and names why", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  for (const config of [PAUSING, {}]) {
    const { github, calls, writer } = world({ ...oneDependentWorld(), openLanePrs: null });
    assert.equal(await main({ env: envFor({}, config), github, writer }), 0);
    assert.deepEqual(writes(calls), [deferredLabel(20)], JSON.stringify(config));
  }
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #20 admission deferred: the issue lane's queued count could not be read"), lines.join("\n"));
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
  const { github, calls, writer } = world({
    blocking: [issue(20), issue(21)],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 20: blocker, 21: blocker },
    queuedIssues: queuedN(23),
  });
  assert.equal(await main({ env: envFor({}, PAUSING), github, writer }), 0);
  assert.deepEqual(writes(calls), [...readied(20), deferredLabel(21)]);
});

// Owner Q95: admission takes the oldest issue first, by when it was opened,
// whatever order the closed listing and the blocking lists answer in.
test("with room for one admission the oldest issue a sweep unblocks is labeled first", async (t) => {
  t.mock.method(console, "log", () => {});
  const opened = (n, at) => ({ ...issue(n), created_at: at });
  const { github, calls, writer } = world({
    // Updated-desc order: 12 closed last, so the listing answers it first.
    closedList: [closedAt(12, "2026-10-16T11:40:00Z"), closedAt(10, "2026-10-16T11:30:00Z")],
    blockingOf: { 12: [opened(22, "2026-10-12T00:00:00Z"), opened(21, "2026-10-05T00:00:00Z")] },
    blocking: [opened(23, "2026-10-14T00:00:00Z"), opened(20, "2026-10-01T00:00:00Z")],
    issues: { 20: issue(20), 21: issue(21), 22: issue(22), 23: issue(23) },
    blockedBy: { 20: [issue(10, { state: "closed" })], 21: [issue(12, { state: "closed" })], 22: [issue(12, { state: "closed" })], 23: [issue(10, { state: "closed" })] },
    queuedIssues: queuedN(22),
  });
  assert.equal(await sweep({ github, writer }, PAUSING), 0);
  assert.deepEqual(writes(calls), [...readied(20), ...readied(21), deferredLabel(22), deferredLabel(23)]);
});

test("an issue already deferred is not labeled admission-deferred again", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = world({ ...oneDependentWorld(["admission-deferred"]), queuedIssues: queuedN(24) });
  assert.equal(await main({ env: envFor({}, PAUSING), github }), 0);
  assert.deepEqual(writes(calls), []);
});

// A deferred issue, number 25, whose one blocker is closed; `deferredBy`
// added its admission-deferred label (the lanes App by default), and
// `readyBy` its status: ready before that (the lanes App's intake by
// default; null for none).
const deferredAdd = (actor, at = "2026-10-16T08:00:00Z") => ({ event: "labeled", label: { name: "admission-deferred" }, actor, created_at: at });
const readyAdd = (actor, at = "2026-10-01T00:00:00Z") => ({ event: "labeled", label: { name: "status: ready" }, actor, created_at: at });
const deferredWorld = ({ labels = ["admission-deferred", "status: ready"], sibling = "closed", queuedIssues = [], readyBy = LANES_BOT, events: own = [deferredAdd(LANES_BOT)], openLanePrs = 0, timeline = [], closing = [], specs = {}, comments = [note()] } = {}) => {
  const events = readyBy ? [readyAdd(readyBy), ...own] : own;
  return world({
    specs,
    openLanePrs,
    timeline: { 25: timeline },
    closing: { 25: closing },
    deferred: [issue(25, { labels })],
    issues: { 25: issue(25, { labels }) },
    blockedBy: { 25: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 25: comments },
    events: { 25: events },
    queuedIssues,
  });
};

test("the sweep re-admits a deferred issue only when the lanes App or a listed human added admission-deferred", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(line));
  // A listed human's add is a person's mark, which the markedWorld tests cover.
  const trusted = deferredWorld({ events: [deferredAdd(LANES_BOT)] });
  assert.equal(await sweep({ github: trusted.github }, PAUSING), 0);
  assert.deepEqual(writes(trusted.calls), [labeled(25)]);
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
  assert.deepEqual(writes(under.calls), [labeled(25)]);
  const at = deferredWorld({ queuedIssues: queuedN(24) });
  assert.equal(await sweep({ github: at.github }, PAUSING), 0);
  assert.deepEqual(writes(at.calls), []);
});

// A manual intake re-dispatch skips intake-reenter, so a deferred issue can
// carry the parked status: confirmed beside status: ready; admission's
// agent-ready field write replaces it, with no label write.
test("the sweep lifts a parked status: confirmed beside status: ready when it admits a deferred issue", async (t) => {
  t.mock.method(console, "log", () => {});
  const parked = deferredWorld({ labels: ["admission-deferred", "status: ready", "status: confirmed"] });
  assert.equal(await sweep({ github: parked.github }, PAUSING), 0);
  assert.deepEqual(writes(parked.calls), [labeled(25)]);
  const ready = deferredWorld({ labels: ["admission-deferred", "status: ready"] });
  assert.equal(await sweep({ github: ready.github }, PAUSING), 0);
  assert.deepEqual(writes(ready.calls), [labeled(25)]);
});

// Three deferred issues, 25 to 27, each ready with no blocker; `done` is what
// the merged-Refs read answers per issue.
const doneNode = (pulls = [], refs = 26) => ({ createdAt: "2026-10-01T00:00:00Z", comments: { nodes: [] }, timelineItems: { nodes: pulls.map((number) => ({ source: { number, merged: true, mergedAt: "2026-10-16T07:00:00Z", body: `Refs: #${refs}`, repository: { nameWithOwner: REPO } } })) } });
const threeDeferred = (extra = {}) => {
  const labels = ["admission-deferred", "status: ready"];
  const numbers = [25, 26, 27];
  return world({
    deferred: numbers.map((n) => issue(n, { labels })),
    issues: Object.fromEntries(numbers.map((n) => [n, issue(n, { labels })])),
    comments: Object.fromEntries(numbers.map((n) => [n, [note()]])),
    events: Object.fromEntries(numbers.map((n) => [n, [readyAdd(LANES_BOT), deferredAdd(LANES_BOT)]])),
    done: { 25: doneNode(), 26: doneNode([41]), 27: doneNode() },
    ...extra,
  });
};
const doneReads = (calls) => calls.filter((call) => call.startsWith("POST /graphql ") && call.includes("fragment done on Issue"));

test("the sweep parks a deferred issue a merged Refs pull request may have done, reading the pass's issues in one call", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = threeDeferred();
  assert.equal(await sweep({ github, writer }, PAUSING), 0);
  assert.equal(doneReads(calls).length, 1);
  assert.deepEqual(writes(calls), [
    ...readied(25),
    `POST /repos/${REPO}/issues/26/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(doneReason([41]))}` })}`,
    "SET 26 confirmed",
    ...readied(27),
  ]);
});

// intake-reenter lifts status: confirmed only beside the admission comment.
test("a failed done-check comment leaves the deferred issue queued for the next sweep, not parked", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = threeDeferred({ failOn: (method, path) => method === "POST" && path === `/repos/${REPO}/issues/26/comments` });
  assert.equal(await sweep({ github, writer }, PAUSING), 1);
  assert.ok(!writes(calls).some((call) => call.startsWith("SET 26 ") || call.startsWith(`DELETE /repos/${REPO}/issues/26/`)), writes(calls).join("\n"));
});

test("an issue whose last blocker closed is parked, not labeled, when a merged Refs pull request may have done it", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = world({ ...oneDependentWorld(["status: ready"]), events: { 20: [readyAdd(LANES_BOT)] }, done: { 20: doneNode([41], 20) } });
  assert.equal(await main({ env: envFor(), github, writer }), 0);
  assert.equal(doneReads(calls).length, 1);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/20/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(doneReason([41]))}` })}`,
    "SET 20 confirmed",
  ]);
});

test("the sweep admits deferred issues as before when the merged-Refs read fails", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = threeDeferred({ failOn: (method, path, body) => path === "/graphql" && String(body?.query).includes("fragment done on Issue") });
  assert.equal(await sweep({ github }, PAUSING), 0);
  assert.deepEqual(writes(calls), [labeled(25), labeled(26), labeled(27)]);
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
    assert.deepEqual(writes(closed.calls), [labeled(25)], JSON.stringify(facts));
  }
});

test("the sweep admits a deferred issue an open pull request only mentions", async (t) => {
  t.mock.method(console, "log", () => {});
  const mention = deferredWorld({ timeline: [namingPull("open", "Same shape as #25.")] });
  assert.equal(await sweep({ github: mention.github }, PAUSING), 0);
  assert.deepEqual(writes(mention.calls), [labeled(25)]);
});

test("while the issue lane is paused over its WIP cap the sweep keeps a deferred issue deferred, with queued room", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const paused = deferredWorld({ openLanePrs: 3 });
  assert.equal(await sweep({ github: paused.github }, PAUSING), 0);
  assert.deepEqual(writes(paused.calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.some((line) => line.includes("#25") && line.includes("the issue lane is paused")), lines.join("\n"));
});

// Owner decision 2026-10-28: `attended` holds an issue the App deferred, as
// the label or as a newest removal by anyone but a listed human.
test("the sweep keeps a deferred issue attended holds deferred; a listed human's removal of attended re-admits it", async (t) => {
  t.mock.method(console, "log", () => {});
  const attendedEvent = (event, actor, at) => ({ event, label: { name: "attended" }, actor, created_at: at });
  const labeledHold = deferredWorld({ labels: ["admission-deferred", "attended"] });
  assert.equal(await sweep({ github: labeledHold.github }, PAUSING), 0);
  assert.deepEqual(writes(labeledHold.calls), []);
  const removedBy = (actor) => [deferredAdd(LANES_BOT), attendedEvent("labeled", LANES_BOT, "2026-10-16T08:30:00Z"), attendedEvent("unlabeled", actor, "2026-10-16T09:00:00Z")];
  for (const actor of [LANES_BOT, { id: 999999, login: "drive-by", type: "User" }]) {
    const removed = deferredWorld({ events: removedBy(actor) });
    assert.equal(await sweep({ github: removed.github }, PAUSING), 0);
    assert.deepEqual(writes(removed.calls), [], actor.login);
  }
  const lifted = deferredWorld({ events: removedBy(OWNER) });
  assert.equal(await sweep({ github: lifted.github }, PAUSING), 0);
  assert.deepEqual(writes(lifted.calls), [labeled(25)]);
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

// A deferred issue is re-admitted on its deferral only while nothing it was
// deferred without has changed since (admit.mjs deferralLapsed).
const editedSpec = (lastEditedAt) => ({ body: "", author: { __typename: "User", databaseId: OWNER.id }, editor: { __typename: "User", databaseId: OWNER.id }, lastEditedAt, comments: [] });
const SECURITY_REASON = "area: security was added after it was deferred, so the admission it was deferred from did not judge it";
const EDITED_REASON = "its body was edited after it was deferred, so the admission it was deferred from judged an older body";
const staleWrites = (reason, status, code = null) => [
  `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: code === null ? `${ADMIT_MARKER}\n${refusalText(reason)}` : heldBody(reason, code) })}`,
  `SET 25 ${status === "needs-owner-decision" ? "needs-owner-decision" : "confirmed"}`,
];

test("the sweep keeps a deferred issue deferred while do-not-merge, needs-human or the untrusted-provenance hold is on it", async (t) => {
  t.mock.method(console, "log", () => {});
  for (const label of ["do-not-merge", "needs-human", "provenance: untrusted"]) {
    const held = deferredWorld({ labels: ["admission-deferred", "status: ready", label] });
    assert.equal(await sweep({ github: held.github }, PAUSING), 0);
    assert.deepEqual(writes(held.calls), [], label);
  }
  // The hold class stands when someone unlisted took its label off.
  const stranger = { id: 999999, login: "drive-by", type: "User" };
  const removed = { event: "unlabeled", label: { name: "provenance: untrusted" }, actor: stranger, created_at: "2026-10-16T09:00:00Z" };
  const unheld = deferredWorld({ events: [deferredAdd(LANES_BOT), removed] });
  assert.equal(await sweep({ github: unheld.github }, PAUSING), 0);
  assert.deepEqual(writes(unheld.calls), []);
});

test("the sweep drops the deferral of a deferred issue that lost status: ready, without labeling it", async (t) => {
  t.mock.method(console, "log", () => {});
  const lost = deferredWorld({ labels: ["admission-deferred"] });
  assert.equal(await sweep({ github: lost.github }, PAUSING), 0);
  assert.deepEqual(writes(lost.calls), [undeferred(25, "needs-triage")]);
});

test("a deferred issue already agent-ready only loses admission-deferred, whatever changed since", async (t) => {
  t.mock.method(console, "log", () => {});
  const running = deferredWorld({ labels: ["admission-deferred", "status: ready", "agent-ready"], specs: { 25: editedSpec("2026-10-16T09:00:00Z") } });
  assert.equal(await sweep({ github: running.github }, PAUSING), 0);
  assert.deepEqual(writes(running.calls), [undeferred(25)]);
});

test("the sweep refuses a deferred issue that gained area: security since its deferral, at needs-owner-decision, marked security", async (t) => {
  t.mock.method(console, "log", () => {});
  const labels = ["admission-deferred", "status: ready", "area: security"];
  const added = (at) => ({ event: "labeled", label: { name: "area: security" }, actor: OWNER, created_at: at });
  const after = deferredWorld({ labels, events: [deferredAdd(LANES_BOT), added("2026-10-16T09:00:00Z")] });
  assert.equal(await sweep({ github: after.github, writer: after.writer }, PAUSING), 0);
  assert.deepEqual(writes(after.calls), staleWrites(SECURITY_REASON, "needs-owner-decision", "security"));
  // On it before the deferral, the admission it was deferred from judged it.
  const before = deferredWorld({ labels, events: [added("2026-10-16T07:00:00Z"), deferredAdd(LANES_BOT)] });
  assert.equal(await sweep({ github: before.github }, PAUSING), 0);
  assert.deepEqual(writes(before.calls), [labeled(25)]);
});

test("work-unblock's held refusal names its owner reason as a stop-reason marker the hub reads; a park carries none", () => {
  const held = heldText("it carries do-not-merge", "cost");
  assert.equal(held, `${refusalText("it carries do-not-merge")}\n\nReason: \`cost\`\n<!-- stop-reason lane=work-unblock reason=cost -->`);
  assert.deepEqual(parseReason(held), { lane: "work-unblock", reason: "cost" });
  assert.equal(heldText("Size unset is not one of small, medium", null), refusalText("Size unset is not one of small, medium"));
  assert.throws(() => heldText("x", "none"), /never hands work to a person/);
});

test("a lapsed deferral's holds stop for security on the untrusted-provenance hold or a gained security area, else intent; no hold is a park", () => {
  const item = (reason, hold, kind = "stale") => ({ reason, hold, kind });
  assert.equal(lapsedReason([]), null);
  assert.equal(lapsedReason([item(EDITED_REASON, false)]), null);
  assert.equal(lapsedReason([item(EDITED_REASON, false), item(SECURITY_REASON, true)]), "security");
  assert.equal(lapsedReason([item("provenance: untrusted work needs a person", true, "held")]), "security");
  assert.equal(lapsedReason([item("it carries do-not-merge", true, "held")]), "intent");
  assert.equal(lapsedReason([item("it carries do-not-merge", true, "held"), item(SECURITY_REASON, true)]), "security");
});

test("the sweep never rewrites admission's marked comment on a deferred issue a hold still holds", async (t) => {
  t.mock.method(console, "log", () => {});
  const marked = {
    id: 12,
    body: `${ADMIT_MARKER}\n${refusalText("it carries do-not-merge")}\n\nReason: \`intent\`\n<!-- stop-reason lane=intake-triage reason=intent -->`,
    user: LANES_BOT,
    created_at: STAMP,
    updated_at: STAMP,
  };
  const labels = ["admission-deferred", "status: ready", "needs-owner-decision", "area: security"];
  const added = { event: "labeled", label: { name: "area: security" }, actor: OWNER, created_at: "2026-10-16T09:00:00Z" };
  // Intake's deferral and a person's mark alike: the hold keeps it, unwritten.
  for (const by of [LANES_BOT, OWNER]) {
    const { github, calls } = deferredWorld({ labels, events: [deferredAdd(by), added], comments: [note(), marked] });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(calls), [], by.login);
  }
});

// The one Work status field write replaces a parked confirmed; no label moves.
test("a deferred issue refused at needs-owner-decision takes a parked status: confirmed off; one refused at status: confirmed keeps it", async (t) => {
  t.mock.method(console, "log", () => {});
  const added = { event: "labeled", label: { name: "area: security" }, actor: OWNER, created_at: "2026-10-16T09:00:00Z" };
  const hold = deferredWorld({ labels: ["admission-deferred", "status: ready", "area: security", "status: confirmed"], events: [deferredAdd(LANES_BOT), added] });
  assert.equal(await sweep({ github: hold.github, writer: hold.writer }, PAUSING), 0);
  assert.deepEqual(writes(hold.calls), staleWrites(SECURITY_REASON, "needs-owner-decision", "security"));
  const edited = deferredWorld({ labels: ["admission-deferred", "status: ready", "status: confirmed"], specs: { 25: editedSpec("2026-10-16T09:00:00Z") } });
  assert.equal(await sweep({ github: edited.github, writer: edited.writer }, PAUSING), 0);
  assert.deepEqual(writes(edited.calls), staleWrites(EDITED_REASON, "status: confirmed"));
});

test("the sweep refuses a deferred issue whose body was edited since its deferral, at status: confirmed", async (t) => {
  t.mock.method(console, "log", () => {});
  const after = deferredWorld({ specs: { 25: editedSpec("2026-10-16T09:00:00Z") } });
  assert.equal(await sweep({ github: after.github, writer: after.writer }, PAUSING), 0);
  assert.deepEqual(writes(after.calls), staleWrites(EDITED_REASON, "status: confirmed"));
  const before = deferredWorld({ specs: { 25: editedSpec("2026-10-16T07:00:00Z") } });
  assert.equal(await sweep({ github: before.github }, PAUSING), 0);
  assert.deepEqual(writes(before.calls), [labeled(25)]);
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
// A body a person holds (admit.mjs BODY_HOLD): an intent hold, whichever way decide names reasons.
const HELD_BODY = "Fix it.\n\nHold: the owner picks the wording first.\n\n## Done when\n\n- [ ] Line 3 says nineteen.";
const BODY_HOLD_REASON = "a line of its body opens with `Hold:`, a person's hold; removing that line lifts it";
const markedIssue = (labels, body = "Fix it.\n\n## Done when\n\n- [ ] Line 3 says nineteen.") => ({ ...issue(25, { labels }), user: OWNER, type: { name: "Task" }, body });
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
  done = {},
  failOn,
  body,
} = {}) =>
  world({
    specs,
    done,
    failOn,
    closing: { 25: closing },
    deferred: [markedIssue(labels, body)],
    issues: { 25: markedIssue(labels, body) },
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
  assert.deepEqual(writes(calls), [labeled(25)]);
  assert.equal(fieldReads(calls), 1);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #25, marked by a person, passes the admission rules"), lines.join("\n"));
});

test("a person's mark admitted with a parked status: confirmed beside status: ready lifts it", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = markedWorld({ labels: [...MARKED, "status: confirmed"] });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [labeled(25)], "the agent-ready field write replaces confirmed; no label write");
});

test("a person's mark on an issue a merged Refs pull request may have done parks it at status: confirmed, not needs-decision", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = markedWorld({ done: { 25: doneNode([41], 25) } });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(doneReason([41]))}` })}`,
    "SET 25 confirmed",
  ]);
});

// Number 20 parked at status: confirmed, blocked by number 10 alone, closed at
// CLOSED. `parkedAt` is when status: confirmed was added.
const PARKED_AT = "2026-10-16T11:00:00Z";
const parkedIssue = ({ labels = ["status: confirmed"], ...rest } = {}) => ({ ...issue(20, { labels }), user: OWNER, ...rest });
const parkedWorld = ({ labels, parkedAt = PARKED_AT, comments = [{ id: 9, body: `${ADMIT_MARKER}\nNot admitted.`, user: LANES_BOT, created_at: STAMP, updated_at: STAMP }], siblings = [], rest = {}, extra = {} } = {}) =>
  world({
    blocking: [parkedIssue({ labels })],
    issues: { 20: parkedIssue({ labels, ...rest }) },
    blockedBy: { 20: [issue(10, { state: "closed" }), ...siblings] },
    comments: { 20: comments },
    events: { 20: [{ event: "labeled", label: { name: "status: confirmed" }, actor: LANES_BOT, created_at: parkedAt }] },
    ...extra,
  });
const unparkedBody = `${UNPARKED_MARKER}\nA blocker of this issue closed after admission parked it at \`status: confirmed\`, so work-unblock set its Work status to needs-triage, and the hourly triage sweep sends it back to intake triage.`;
const unparkedWrites = [
  `POST /repos/${REPO}/issues/20/comments ${JSON.stringify({ body: unparkedBody })}`,
  "SET 20 needs-triage",
];
const onClose = (world_) => main({ env: envFor(), github: world_.github, writer: world_.writer, admission: admissionFor() });

test("the last blocker closing hands an issue admission parked back to intake: the marker comment, needs-triage, status: confirmed off, never agent-ready", async (t) => {
  t.mock.method(console, "log", () => {});
  const parked = parkedWorld();
  assert.equal(await onClose(parked), 0);
  assert.deepEqual(writes(parked.calls), unparkedWrites);
  assert.match(unparkedBody, /^<!-- work-unblock unparked triage -->\n/);
});

test("an unpark whose marker already follows the park writes no second comment", async (t) => {
  t.mock.method(console, "log", () => {});
  const marker = { id: 70, body: unparkedBody, user: LANES_BOT, created_at: "2026-10-16T11:40:00Z", updated_at: "2026-10-16T11:40:00Z" };
  const admitted = { id: 9, body: `${ADMIT_MARKER}\nNot admitted.`, user: LANES_BOT, created_at: STAMP, updated_at: STAMP };
  const again = parkedWorld({ comments: [admitted, marker] });
  assert.equal(await onClose(again), 0);
  assert.deepEqual(writes(again.calls), unparkedWrites.slice(1));
  // A marker from before this park belongs to an earlier unpark.
  const older = parkedWorld({ comments: [admitted, { ...marker, created_at: "2026-10-16T10:00:00Z" }] });
  assert.equal(await onClose(older), 0);
  assert.deepEqual(writes(older.calls), unparkedWrites);
});

test("a parked issue stays parked for each reason the close does not send it to intake", async (t) => {
  t.mock.method(console, "log", () => {});
  const cases = {
    "an open sibling blocker": { siblings: [issue(11)] },
    "a re-park after the close": { parkedAt: "2026-10-16T11:45:00Z" },
    "no admission comment": { comments: [note()] },
    "the cordoned milestone": { rest: { milestone: { title: "After zero" } } },
    "an author intake does not admit": { rest: { user: { id: 4242, login: "drive-by" } } },
    "a refuse label": { labels: ["status: confirmed", "host-run"] },
    "a hold": { labels: ["status: confirmed", "needs-human"] },
    "needs-decision beside it": { labels: ["status: confirmed", "needs-owner-decision"] },
  };
  for (const [name, options] of Object.entries(cases)) {
    const parked = parkedWorld(options);
    assert.equal(await onClose(parked), 0, name);
    assert.deepEqual(writes(parked.calls), [], name);
  }
});

test("another milestone does not cordon a parked issue", async (t) => {
  t.mock.method(console, "log", () => {});
  const parked = parkedWorld({ rest: { milestone: { title: "Next" } } });
  assert.equal(await onClose(parked), 0);
  assert.deepEqual(writes(parked.calls), unparkedWrites);
});

test("the sweep reads only issues a closed blocker blocked, and logs the count before the removal", async (t) => {
  const lines = [];
  t.mock.method(console, "log", (line) => lines.push(line));
  const parked = parkedWorld({ extra: { closedList: [issue(10, { state: "closed" })], blockingOf: { 10: [parkedIssue()] } } });
  assert.equal(await sweep({ github: parked.github, writer: parked.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(parked.calls), unparkedWrites);
  const count = lines.findIndex((line) => String(line).includes("1 of 1 parked issue(s) go back to intake"));
  const removal = lines.findIndex((line) => String(line).includes("set to needs-triage; the triage sweep sends it to intake"));
  assert.ok(count >= 0 && count < removal, lines.join("\n"));
});

// Sweep windows overlap, so a sweep reads the same close while intake runs.
test("an issue sent to intake is not labeled until a status: ready follows the removal", async (t) => {
  t.mock.method(console, "log", () => {});
  const removal = { event: "unlabeled", label: { name: "status: confirmed" }, actor: LANES_BOT, created_at: CLOSED };
  const sent = (labels, events) => parkedWorld({ labels, extra: { closedList: [issue(10, { state: "closed" })], blockingOf: { 10: [parkedIssue({ labels })] }, events: { 20: events } } });
  for (const labels of [["needs-triage"], []]) {
    const waiting = sent(labels, [removal]);
    assert.equal(await sweep({ github: waiting.github, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(waiting.calls), [], String(labels));
  }
  const decided = sent(["status: ready"], [removal, { event: "labeled", label: { name: "status: ready" }, actor: LANES_BOT, created_at: STAMP }]);
  assert.equal(await sweep({ github: decided.github, admission: admissionFor() }, PAUSING), 0);
  assert.ok(writes(decided.calls).includes(labeled(20)), writes(decided.calls).join("\n"));
});

test("an issue intake parked again after an unpark goes back to intake when a later blocker closes", async (t) => {
  t.mock.method(console, "log", () => {});
  const events = [
    { event: "labeled", label: { name: "status: confirmed" }, actor: LANES_BOT, created_at: PARKED_AT },
    { event: "unlabeled", label: { name: "status: confirmed" }, actor: LANES_BOT, created_at: "2026-10-16T11:05:00Z" },
    { event: "labeled", label: { name: "status: confirmed" }, actor: LANES_BOT, created_at: "2026-10-16T11:10:00Z" },
  ];
  const parked = parkedWorld({ extra: { events: { 20: events } } });
  assert.equal(await onClose(parked), 0);
  assert.deepEqual(writes(parked.calls), unparkedWrites);
});

test("a failed needs-triage write fails the run", async (t) => {
  t.mock.method(console, "log", () => {});
  const parked = parkedWorld();
  const writer = {
    ...parked.writer,
    set: async (number, state) => {
      parked.calls.push(`SET ${number} ${state}`);
      throw new Error("POST failed with status 502");
    },
  };
  assert.equal(await main({ env: envFor(), github: parked.github, writer, admission: admissionFor() }), 1);
  assert.deepEqual(writes(parked.calls), unparkedWrites);
});

test("a person's mark refused for a person takes a parked status: confirmed off, after the hold", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = markedWorld({ labels: [...MARKED, "status: confirmed"], body: HELD_BODY });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  const posted = writes(calls);
  assert.ok(posted.includes("SET 25 needs-owner-decision"), posted.join("\n"));
  assert.ok(!posted.some((call) => call.includes("/labels")), posted.join("\n"));
});

test("a person's mark refused for a merged Refs pull request and a person's hold keeps needs-decision, marked; with a reason no person settles it parks", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = markedWorld({ done: { 25: doneNode([41], 25) }, body: HELD_BODY });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  const posted = writes(calls);
  assert.ok(posted.includes("SET 25 needs-owner-decision"), posted.join("\n"));
  assert.ok(!posted.some((call) => call.includes("status: confirmed") || call === "SET 25 confirmed"), posted.join("\n"));
  assert.match(posted[0], /merged pull request #41 names it/);
  assert.match(posted[0], /Reason: `intent`\\n<!-- stop-reason lane=work-unblock reason=intent -->"}$/);
  // Unset fields beside the merged pull request ask no person: status: confirmed, no marker.
  const unset = markedWorld({ done: { 25: doneNode([41], 25) } });
  assert.equal(await sweep({ github: unset.github, writer: unset.writer, admission: admissionFor(4242) }, PAUSING), 0);
  const parked = writes(unset.calls);
  assert.ok(parked.includes("SET 25 confirmed"), parked.join("\n"));
  assert.ok(!parked.some((call) => call.includes("needs-decision") || call.includes("stop-reason")), parked.join("\n"));
});

test("a person's mark on an inadmissible issue is refused: the admission comment, status: confirmed when no person settles it, admission-deferred off", async (t) => {
  t.mock.method(console, "log", () => {});
  const refusedWrites = (reasons) => [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(reasons.join("; "))}` })}`,
    "SET 25 confirmed",
  ];
  // Size Large parks for the intake split (owner Q93): a wait comment, the mark off, back to ready.
  const large = markedWorld({ fields: LARGE_LOW_KNOWN });
  assert.equal(await sweep({ github: large.github, writer: large.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(large.calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: Size large: the split into sub-issues at intake is pending (owner Q93).` })}`,
    "SET 25 ready",
  ]);
  // A value no listed human or App set counts as unset, never as a default.
  const stranger = markedWorld();
  assert.equal(await sweep({ github: stranger.github, writer: stranger.writer, admission: admissionFor(4242) }, PAUSING), 0);
  assert.deepEqual(
    writes(stranger.calls),
    refusedWrites(["Size unset is not one of small, medium", "Uncertainty unset is not one of known, knowable"]),
  );
  // Intake's own deferral (the App's add) keeps the room-only path: no rules read.
  const intake = markedWorld({ fields: LARGE_LOW_KNOWN, by: LANES_BOT });
  assert.equal(await sweep({ github: intake.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(intake.calls), [labeled(25)]);
  assert.equal(fieldReads(intake.calls), 0);
});

test("a person's mark whose criteria only the App wrote is refused; a text read of an unexpected shape writes nothing", async (t) => {
  t.mock.method(console, "log", () => {});
  const app = { __typename: "Bot", databaseId: LANES_APP_ID };
  const appOnly = markedWorld({
    specs: { 25: { body: "- [ ] Line 3 says nineteen.", author: app, editor: null, lastEditedAt: null, comments: [{ body: "Go ahead.", author: { __typename: "User", databaseId: OWNER.id }, editor: null, lastEditedAt: null }] } },
  });
  assert.equal(await sweep({ github: appOnly.github, writer: appOnly.writer, admission: admissionFor() }, PAUSING), 0);
  assert.ok(writes(appOnly.calls).includes("SET 25 confirmed"), writes(appOnly.calls).join("\n"));
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
  assert.deepEqual(writes(mention.calls), [labeled(25)]);
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

// Owner decision 2026-10-28: a refinement recording a manual external step
// needs the owner present, which asks no decision.
const manualSpec = (body) => ({
  body,
  author: { __typename: "User", databaseId: OWNER.id },
  editor: null,
  lastEditedAt: null,
  comments: [
    {
      body: `${REFINE_MARKER}\n**Refinement.**\n\n**Acceptance criteria**\n\n- [ ] Line 3 says nineteen.\n\nExternal state: manual (dns: a CNAME for docs at the registrar)\n`,
      author: { __typename: "Bot", databaseId: LANES_APP_ID },
      editor: null,
      lastEditedAt: null,
      createdAt: "2026-10-16T06:30:00Z",
    },
  ],
});
const ATTENDED_REASON = "its refinement records External state: manual (dns: a CNAME for docs at the registrar), a step that needs the owner present (attended)";

test("a person's mark refused only for a manual external step parks at status: confirmed with attended, never needs-decision", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = markedWorld({ specs: { 25: manualSpec(markedIssue(MARKED).body) } });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(ATTENDED_REASON)}` })}`,
    "SET 25 confirmed",
    `POST /repos/${REPO}/issues/25/labels {"labels":["attended"]}`,
  ]);
});

const NEEDS_DECISION_WRITE = "SET 25 needs-owner-decision";
// The labels a sweep's writes leave on the marked fixture, the failed write left out.
const labelsLeft = (labels, calls, failed) =>
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
  // A person's `Hold:` line refuses for a person; its field write fails.
  const first = markedWorld({ body: HELD_BODY });
  const failing = {
    set: async (number, state) => {
      first.calls.push(`SET ${number} ${state}`);
      if (state === "needs-owner-decision") {
        throw new Error("POST failed with status 502");
      }
    },
    leaveAgentReady: first.writer.leaveAgentReady,
    restart: first.writer.restart,
  };
  assert.equal(await sweep({ github: first.github, writer: failing, admission: admissionFor() }, PAUSING), 1);
  assert.ok(!writes(first.calls).includes(`DELETE /repos/${REPO}/issues/25/labels/status%3A%20ready`), writes(first.calls).join("\n"));
  const left = labelsLeft(MARKED, first.calls, NEEDS_DECISION_WRITE);
  const second = markedWorld({ labels: left, body: HELD_BODY });
  assert.equal(await sweep({ github: second.github, admission: admissionFor() }, PAUSING), 0);
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
  assert.deepEqual(writes(human.calls), [labeled(25)]);
  // The newest add counts: an outsider's re-add after the App's does not.
  for (const decided of [
    [labelAdd("status: ready", outsider), labelAdd("work-class: mechanical", LANES_BOT)],
    [labelAdd("status: ready", LANES_BOT), labelAdd("status: ready", outsider, "2026-10-16T07:30:00Z")],
    [labelAdd("work-class: mechanical", LANES_BOT)],
  ]) {
    const { github, calls } = markedWorld({ decided });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    assert.ok(!writes(calls).includes(labeled(25)), `${JSON.stringify(decided)}\n${writes(calls).join("\n")}`);
    assert.ok(writes(calls).includes(undeferred(25, "needs-triage")), JSON.stringify(decided));
  }
});

// A deferred issue that exists only in its Work status field: no status label
// and no label event, its field history `nodes` (GraphQL field events, all
// after models.issue-status field-events-since so a bot's count), listed by
// the field listing (`byStatus`), and read through the field-first reader
// over the trusted-actor fixture.
const FIELD_AT = (hour) => `2026-11-08T0${hour}:00:00Z`;
const fieldEvent = (actor, to, from, hour) => ({
  __typename: from ? "IssueFieldChangedEvent" : "IssueFieldAddedEvent",
  ...(from ? { previousValue: from, newValue: to } : { value: to }),
  createdAt: typeof hour === "number" ? FIELD_AT(hour) : hour,
  actor,
  issueField: { fullDatabaseId: String(STATUS_CONFIG["field-id"]) },
});
const GRAPH_OWNER = { __typename: "User", login: OWNER.login, databaseId: OWNER.id };
const GRAPH_APP = { __typename: "Bot", login: "melodic-automation-lanes", databaseId: LANES_APP_ID };
const GRAPH_ACTIONS = { __typename: "Bot", login: "github-actions", databaseId: 41898282 };
// The Work status row a field read answers for `state`.
const workRow = (state) => fieldRow(STATUS_CONFIG["field-id"], OPTION[state]);
// `fake` (a world) whose field event reads answer `histories` (issue number ->
// GraphQL field event nodes), with the field-first reader over it.
function withFieldHistory(fake, histories) {
  const github = async (method, path, body, ...rest) => {
    const nodes = histories[body?.variables?.number];
    return method === "POST" && path === "/graphql" && /IssueFieldAddedEvent/.test(body?.query ?? "") && nodes
      ? { data: { repository: { issue: { timelineItems: { nodes } } } } }
      : fake.github(method, path, body, ...rest);
  };
  const trustedActors = JSON.parse(readFileSync(TRUSTED, "utf8"));
  return { ...fake, github, statusOf: statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors, log: () => {} }) };
}
function fieldOnlyDeferred(nodes, { state = "deferred", labels = [], events = [] } = {}) {
  const fake = world({
    issues: { 25: markedIssue(labels) },
    blockedBy: { 25: [issue(10, { state: "closed" })] },
    comments: { 25: [note()] },
    events: { 25: events },
    fieldValues: { 25: [...SMALL_LOW_KNOWN, workRow(state)] },
  });
  return {
    ...withFieldHistory(fake, { 25: nodes }),
    byStatus: async (states) => (states ? [{ number: 25, created_at: "2026-10-01T00:00:00Z", labels: [DEFERRED], state }] : null),
  };
}
const DEFERRED = "admission-deferred";
const fieldSweep = (fake) =>
  sweep({ github: fake.github, writer: fake.writer, statusOf: fake.statusOf, byStatus: fake.byStatus, admission: admissionFor(), now: Date.parse("2026-11-08T12:00:00Z") }, PAUSING);

test("a field-only ready a listed human or the App set is admitted by admitDeferred after a person's field deferral", async (t) => {
  t.mock.method(console, "log", () => {});
  for (const setter of [GRAPH_OWNER, GRAPH_APP]) {
    const fake = fieldOnlyDeferred([fieldEvent(setter, "ready", null, 7), fieldEvent(GRAPH_OWNER, "deferred", "ready", 8)]);
    assert.equal(await fieldSweep(fake), 0, setter.login);
    assert.deepEqual(writes(fake.calls), [labeled(25)], setter.login);
    assert.ok(fake.calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/25/events`)), "the REST events are read beside the field's");
  }
});

test("a field-only ready github-actions set is never admitted, and the App never writes ready in its place", async (t) => {
  t.mock.method(console, "log", () => {});
  const fake = fieldOnlyDeferred([fieldEvent(GRAPH_ACTIONS, "ready", null, 7), fieldEvent(GRAPH_OWNER, "deferred", "ready", 8)]);
  assert.equal(await fieldSweep(fake), 0);
  const written = writes(fake.calls);
  assert.ok(!written.includes(labeled(25)) && !written.includes("SET 25 ready"), written.join("\n"));
  assert.deepEqual(written.slice(-1), ["SET 25 needs-triage"]);
  assert.match(written[0], /status: ready was added by neither a listed human nor the lanes App/);
});

// The App's own deferral carries no person's judgment of the ready it
// deferred, so readiness checks that ready's setter as the person-mark path does.
test("after the App's deferral, a field-only ready a listed human or the App set is admitted, and github-actions' is refused", async (t) => {
  t.mock.method(console, "log", () => {});
  for (const setter of [GRAPH_OWNER, GRAPH_APP]) {
    const fake = fieldOnlyDeferred([fieldEvent(setter, "ready", null, 7), fieldEvent(GRAPH_APP, "deferred", "ready", 8)]);
    assert.equal(await fieldSweep(fake), 0, setter.login);
    assert.ok(writes(fake.calls).includes(labeled(25)), `${setter.login}\n${writes(fake.calls).join("\n")}`);
  }
  const fake = fieldOnlyDeferred([fieldEvent(GRAPH_ACTIONS, "ready", null, 7), fieldEvent(GRAPH_APP, "deferred", "ready", 8)]);
  assert.equal(await fieldSweep(fake), 0);
  const written = writes(fake.calls);
  assert.ok(!written.includes(labeled(25)) && !written.includes("SET 25 ready"), written.join("\n"));
  assert.deepEqual(written.slice(-1), ["SET 25 needs-triage"]);
});

test("a blocker's close admits a field-only ready a listed human or the App set, and leaves github-actions' as is", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  const closeWorld = (setter) =>
    withFieldHistory(world({ ...oneDependentWorld([]), fieldValues: { 20: [...SMALL_LOW_KNOWN, workRow("ready")] } }), { 20: [fieldEvent(setter, "ready", null, 7)] });
  for (const setter of [GRAPH_OWNER, GRAPH_APP]) {
    const fake = closeWorld(setter);
    assert.equal(await main({ env: envFor(), github: fake.github, writer: fake.writer, statusOf: fake.statusOf, admission: admissionFor() }), 0, setter.login);
    assert.ok(writes(fake.calls).includes(labeled(20)), `${setter.login}\n${writes(fake.calls).join("\n")}`);
  }
  const fake = closeWorld(GRAPH_ACTIONS);
  assert.equal(await main({ env: envFor(), github: fake.github, writer: fake.writer, statusOf: fake.statusOf, admission: admissionFor() }), 0);
  assert.deepEqual(writes(fake.calls), []);
  assert.ok(logs.some((line) => line === "label-unblocked: #20 not labeled: status: ready was added by neither a listed human nor the lanes App"), logs.join("\n"));
});

// The App's unpark is a field change off confirmed with no REST label event,
// so only the field-merged history shows it.
test("a blocker's close leaves an issue the App unparked on the field for intake, until ready is set again", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  const unparked = (nodes, state) => withFieldHistory(world({ ...oneDependentWorld([]), fieldValues: { 20: [...SMALL_LOW_KNOWN, workRow(state)] } }), { 20: nodes });
  const parkedThenSent = [fieldEvent(GRAPH_APP, "ready", null, 5), fieldEvent(GRAPH_APP, "confirmed", "ready", 6), fieldEvent(GRAPH_APP, "needs-triage", "confirmed", 7)];
  const sent = unparked(parkedThenSent, "needs-triage");
  assert.equal(await main({ env: envFor(), github: sent.github, writer: sent.writer, statusOf: sent.statusOf, admission: admissionFor() }), 0);
  assert.deepEqual(writes(sent.calls), []);
  assert.ok(logs.includes("label-unblocked: #20 not labeled: status: confirmed was removed for intake and status: ready not added since"), logs.join("\n"));
  const readied = unparked([...parkedThenSent, fieldEvent(GRAPH_APP, "ready", "needs-triage", 8)], "ready");
  assert.equal(await main({ env: envFor(), github: readied.github, writer: readied.writer, statusOf: readied.statusOf, admission: admissionFor() }), 0);
  assert.ok(writes(readied.calls).includes(labeled(20)), writes(readied.calls).join("\n"));
});

// sync-status writes a person's label edit into the field as the lanes App,
// seconds after the person's label event.
test("a person's admission-deferred label that sync-status wrote into the field is still the person's mark, judged by the rules", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const personAdd = { id: 501, event: "labeled", label: { name: DEFERRED }, actor: OWNER, created_at: "2026-11-08T02:00:00Z" };
  const fake = fieldOnlyDeferred([fieldEvent(GRAPH_OWNER, "ready", null, 1), fieldEvent(GRAPH_APP, "deferred", "ready", "2026-11-08T02:00:30Z")], { labels: [DEFERRED], events: [personAdd] });
  assert.equal(await fieldSweep(fake), 0);
  assert.deepEqual(writes(fake.calls), [labeled(25)]);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #25, marked by a person, passes the admission rules"), lines.join("\n"));
});

test("a legacy admission-deferred label without status: ready costs no second field read while the field reads deferred", async (t) => {
  t.mock.method(console, "log", () => {});
  const fieldReads = (labels) => {
    const fake = fieldOnlyDeferred([fieldEvent(GRAPH_OWNER, "ready", null, 1), fieldEvent(GRAPH_APP, "deferred", "ready", "2026-11-08T02:00:30Z")], { labels });
    return fieldSweep(fake).then((code) => {
      assert.equal(code, 0);
      assert.ok(writes(fake.calls).includes("SET 25 agent-ready"), "the field's deferred keeps status: ready, so the issue is admitted");
      return fake.calls.filter((call) => call === `GET /repos/${REPO}/issues/25/issue-field-values`).length;
    });
  };
  assert.equal(await fieldReads([DEFERRED]), await fieldReads([]));
});

test("a person's agent-ready removal stands after sync-status leaves the field at confirmed", async (t) => {
  t.mock.method(console, "log", () => {});
  const removed = { id: 502, event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-11-08T02:00:00Z" };
  const stopped = withFieldHistory(
    world({ ...oneDependentWorld([]), events: { 20: [added("2026-11-08T00:30:00Z", OWNER), removed] }, fieldValues: { 20: [workRow("confirmed")] } }),
    { 20: [fieldEvent(GRAPH_APP, "agent-ready", "ready", 1), fieldEvent(GRAPH_APP, "confirmed", "agent-ready", "2026-11-08T02:00:30Z")] },
  );
  assert.equal(await main({ env: envFor(), github: stopped.github, writer: stopped.writer, statusOf: stopped.statusOf, admission: admissionFor() }), 0);
  assert.deepEqual(writes(stopped.calls), []);
});

test("a field-only deferral github-actions set is left as is and not re-admitted", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(line));
  const fake = fieldOnlyDeferred([fieldEvent(GRAPH_OWNER, "ready", null, 7), fieldEvent(GRAPH_ACTIONS, "deferred", "ready", 8)]);
  assert.equal(await fieldSweep(fake), 0);
  assert.deepEqual(writes(fake.calls), []);
  assert.ok(logs.some((line) => String(line).startsWith("::warning title=label-unblocked::#25: admission-deferred was added by neither")), logs.join("\n"));
});

test("an issue parked only in its Work status goes back to intake when a blocker closes after the App parked it", async (t) => {
  t.mock.method(console, "log", () => {});
  const admitted = { id: 9, body: `${ADMIT_MARKER}\nNot admitted.`, user: LANES_BOT, created_at: STAMP, updated_at: STAMP };
  const parkedAt = (hour) =>
    withFieldHistory(
      world({
        blocking: [parkedIssue({ labels: [] })],
        issues: { 20: parkedIssue({ labels: [] }) },
        blockedBy: { 20: [{ ...issue(10, { state: "closed" }), closed_at: FIELD_AT(5) }] },
        comments: { 20: [admitted] },
        fieldValues: { 20: [workRow("confirmed")] },
      }),
      { 20: [fieldEvent(GRAPH_APP, "confirmed", "ready", hour)] },
    );
  const parked = parkedAt(4);
  assert.equal(await main({ env: envFor(), github: parked.github, writer: parked.writer, statusOf: parked.statusOf, admission: admissionFor() }), 0);
  assert.deepEqual(writes(parked.calls), unparkedWrites.slice(0, 2));
  // Parked again after the close: no news, it stays.
  const again = parkedAt(6);
  assert.equal(await main({ env: envFor(), github: again.github, writer: again.writer, statusOf: again.statusOf, admission: admissionFor() }), 0);
  assert.deepEqual(writes(again.calls), []);
});

test("a needs-human only in the Work status lifts on the Refs PR's end only when the App set it there", async (t) => {
  t.mock.method(console, "log", () => {});
  const held = (setter) => {
    const pull = lanePull();
    const fake = world({
      openReady: [ready(30)],
      comments: { 30: [note(), holdNote()] },
      events: { 30: [added(LABELED_AT, OWNER)] },
      timeline: { 30: [crossRef(pull)] },
      pulls: { [pull.number]: pull },
      fieldValues: { 30: [workRow("needs-human")] },
    });
    return withFieldHistory(fake, { 30: [fieldEvent(setter, "needs-human", "agent-ready", 1)] });
  };
  const app = held(GRAPH_APP);
  assert.equal(await sweep({ github: app.github, actions: app.github, writer: app.writer, statusOf: app.statusOf, now: Date.parse(FIELD_AT(3)) }), 0);
  assert.deepEqual(writes(app.calls), [
    `POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: refsMergedComment(7805) })}`,
    "SET 30 needs-triage",
  ]);
  const person = held(GRAPH_OWNER);
  assert.equal(await sweep({ github: person.github, actions: person.github, writer: person.writer, statusOf: person.statusOf, now: Date.parse(FIELD_AT(3)) }), 0);
  assert.deepEqual(writes(person.calls), []);
});

test("a person's hold set after the sweep read the App's needs-human stops the Refs hand-off at the field write", async (t) => {
  t.mock.method(console, "log", () => {});
  const pull = lanePull();
  const fieldValues = { 30: [workRow("needs-human")] };
  const nodes = [fieldEvent(GRAPH_APP, "needs-human", "agent-ready", 1)];
  const fake = withFieldHistory(
    world({ openReady: [ready(30)], comments: { 30: [note(), holdNote()] }, events: { 30: [added(LABELED_AT, OWNER)] }, timeline: { 30: [crossRef(pull)] }, pulls: { [pull.number]: pull }, fieldValues }),
    { 30: nodes },
  );
  const github = async (method, path, body, ...rest) => {
    if (method === "POST" && path === `/repos/${REPO}/issues/30/issue-field-values`) {
      fake.calls.push(`${method} ${path} ${JSON.stringify(body)}`);
      return [fieldRow(STATUS_CONFIG["field-id"], OPTION[body.issue_field_values[0].value])];
    }
    const answer = await fake.github(method, path, body, ...rest);
    if (method === "POST" && path === `/repos/${REPO}/issues/30/comments`) {
      fieldValues[30] = [workRow("needs-owner-decision")];
      nodes.push(fieldEvent(GRAPH_OWNER, "needs-owner-decision", "needs-human", 2));
    }
    return answer;
  };
  const writer = await statusWriter({ env: { BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED }, github, repository: REPO });
  assert.equal(await sweep({ github, actions: github, writer, statusOf: fake.statusOf, now: Date.parse(FIELD_AT(3)) }), 0);
  assert.deepEqual(writes(fake.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: refsMergedComment(7805) })}`], "no field write and agent-ready stays");
});

test("a person's hold set after the read of a ready issue stops its admission at the field write, and without one it is admitted", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  const admitted = async (raced) => {
    const fieldValues = { 20: [...SMALL_LOW_KNOWN, workRow("ready")] };
    const nodes = [fieldEvent(GRAPH_OWNER, "ready", null, 7)];
    const fake = withFieldHistory(world({ ...oneDependentWorld([]), fieldValues }), { 20: nodes });
    const github = async (method, path, body, ...rest) => {
      if (method === "POST" && path === `/repos/${REPO}/issues/20/issue-field-values`) {
        fake.calls.push(`${method} ${path} ${JSON.stringify(body)}`);
        return [fieldRow(STATUS_CONFIG["field-id"], OPTION[body.issue_field_values[0].value])];
      }
      return fake.github(method, path, body, ...rest);
    };
    const statusOf = Object.assign(async (...args) => {
      const names = await fake.statusOf(...args);
      if (raced) {
        fieldValues[20] = [...SMALL_LOW_KNOWN, workRow("needs-owner-decision")];
        nodes.push(fieldEvent(GRAPH_OWNER, "needs-owner-decision", "ready", 8));
      }
      return names;
    }, fake.statusOf);
    const writer = await statusWriter({ env: { BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED }, github, repository: REPO });
    assert.equal(await main({ env: envFor(), github, writer, statusOf, admission: admissionFor() }), 0);
    return writes(fake.calls);
  };
  const fieldWrite = `POST /repos/${REPO}/issues/20/issue-field-values ${JSON.stringify({ issue_field_values: [{ field_id: STATUS_CONFIG["field-id"], value: "agent-ready" }] })}`;
  assert.deepEqual(await admitted(false), [fieldWrite], "the field is set to agent-ready, and no label is written");
  assert.deepEqual(await admitted(true), [], "no agent-ready label and no field write");
  assert.ok(logs.includes("label-unblocked: #20 held by a person, not admitted"), logs.join("\n"));
});

// A set to agent-ready over agent-ready changes nothing, so GitHub sends no
// field_added and no run starts: a restart clears the field first.
test("a limit-stopped issue's restart through the Work status writer clears the field, then sets agent-ready; a person's hold stops it", async (t) => {
  const logs = [];
  t.mock.method(console, "log", (line) => logs.push(String(line)));
  const restartOf = async (state, nodes) => {
    const fake = withFieldHistory(
      world({ openReady: [ready(30)], comments: { 30: [note(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z")] }, events: { 30: [added("2026-10-16T05:00:00Z")] }, fieldValues: { 30: [workRow(state)] } }),
      { 30: nodes },
    );
    const github = async (method, path, body, ...rest) => {
      if (method === "POST" && path === `/repos/${REPO}/issues/30/issue-field-values`) {
        fake.calls.push(`${method} ${path} ${JSON.stringify(body)}`);
        return [fieldRow(STATUS_CONFIG["field-id"], OPTION[body.issue_field_values[0].value])];
      }
      return fake.github(method, path, body, ...rest);
    };
    const writer = await statusWriter({ env: { BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED }, github, repository: REPO });
    assert.equal(await sweep({ github, writer }), 0, state);
    return writes(fake.calls);
  };
  const cleared = `DELETE /repos/${REPO}/issues/30/issue-field-values/${STATUS_CONFIG["field-id"]}`;
  const set = `POST /repos/${REPO}/issues/30/issue-field-values ${JSON.stringify({ issue_field_values: [{ field_id: STATUS_CONFIG["field-id"], value: "agent-ready" }] })}`;
  assert.deepEqual(await restartOf("agent-ready", [fieldEvent(GRAPH_APP, "agent-ready", null, 1)]), [cleared, set], "the field is cleared, then set to agent-ready");
  assert.deepEqual(await restartOf("needs-owner-decision", [fieldEvent(GRAPH_OWNER, "needs-owner-decision", null, 1)]), [], "a person's hold: no clear and no set");
  assert.ok(logs.includes("label-unblocked: #30 left as is: its Work status is now needs-owner-decision"), logs.join("\n"));
  // A person moved it off agent-ready (not a hold) after the listing: still no clear and no set.
  assert.deepEqual(await restartOf("confirmed", [fieldEvent(GRAPH_OWNER, "confirmed", null, 1)]), [], "moved off agent-ready: no clear and no set");
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
    assert.deepEqual(writes(calls), [labeled(25)], JSON.stringify(labels));
  }
  const held = markedWorld({ labels: ["admission-deferred", "status: ready", "provenance: untrusted"], decided: [labelAdd("status: ready", LANES_BOT)] });
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

test("a person's mark on an issue whose body was edited or that gained area: security after the mark is refused", async (t) => {
  t.mock.method(console, "log", () => {});
  const edited = markedWorld({ specs: { 25: { ...editedSpec("2026-10-16T09:00:00Z"), body: markedIssue(MARKED).body } } });
  assert.equal(await sweep({ github: edited.github, writer: edited.writer, admission: admissionFor() }, PAUSING), 0);
  // A body edit asks no person: admission judges it again from status: confirmed.
  assert.deepEqual(writes(edited.calls), staleWrites(EDITED_REASON, "status: confirmed"));
  const security = markedWorld({ labels: [...MARKED, "area: security"], extraEvents: [labelAdd("area: security", OWNER, "2026-10-16T09:00:00Z")] });
  assert.equal(await sweep({ github: security.github, writer: security.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(security.calls), staleWrites(SECURITY_REASON, "needs-owner-decision", DECIDE_SECURITY));
  // A hold decide refuses on gets the person the admission comment, with its reason.
  const held = markedWorld({ labels: [...MARKED, "do-not-merge"] });
  assert.equal(await sweep({ github: held.github, writer: held.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(held.calls), staleWrites("it carries do-not-merge", "needs-owner-decision", "intent"));
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

// limits.stranded-backoff-hours sets each cause's wait: a shorter no-run
// re-fires a label with no run after 1 hour, doubling from there, while a run
// that ended with no report keeps the 3-hour default.
test("a cause's stranded-backoff-hours shortens its wait and backoff; other causes keep 3 hours", async () => {
  const limits = withLimits({ "stranded-backoff-hours": { "no-run": 1 } });
  const oneHourCause = "No work-resolve-issue run started in the 1 hour since `agent-ready` was last added.";
  // NOW is 2026-10-16T12:00:00Z: a label 1 h 0 min 1 s old with no run is re-fired.
  const quick = failedRun({ runs: [], events: [added("2026-10-16T10:59:59Z", OWNER)] });
  assert.equal(await sweep({ github: quick.github, actions: quick.actions }, limits), 0);
  assert.deepEqual(writes(quick.calls), refiredFor(30, oneHourCause));
  // The same label under the default waits.
  const plain = failedRun({ runs: [], events: [added("2026-10-16T10:59:59Z", OWNER)] });
  assert.equal(await sweep({ github: plain.github, actions: plain.actions }), 0);
  assert.deepEqual(writes(plain.calls), []);
  // A green run with no report that ended 2 hours ago still waits 3 hours.
  const report = failedRun({ runs: [laneRun({ at: "2026-10-16T10:00:00Z", conclusion: "success" })], events: [added("2026-10-16T09:59:57Z", OWNER)] });
  assert.equal(await sweep({ github: report.github, actions: report.actions }, limits), 0);
  assert.deepEqual(writes(report.calls), []);
  // After one re-fire the backoff doubles from 1 hour: 2 hours after the App's re-add.
  const events = [
    added("2026-10-16T06:00:00Z", OWNER),
    { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T08:00:00Z" },
    added("2026-10-16T08:00:01Z"),
  ];
  const comments = [note(), refireNote(KEY, "2026-10-16T07:59:59Z")];
  const early = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github: early.github, actions: early.actions, now: Date.parse("2026-10-16T10:00:00Z") }, limits), 0);
  assert.deepEqual(writes(early.calls), []);
  const due = failedRun({ runs: [], comments, events });
  assert.equal(await sweep({ github: due.github, actions: due.actions, now: Date.parse("2026-10-16T10:00:02Z") }, limits), 0);
  const body = infraComment(KEY, oneHourCause, 2);
  assert.deepEqual(writes(due.calls), [`POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body })}`, ...restarted(30)]);
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

// #13483's shape: a host-run session's own pull request, on no lane branch,
// merged with `Refs:` on its body's second line under a session marker. The
// work moved off the lane, so a stranded or failed run is not re-fired until a
// listed human's `**Decision recorded.**` comment after that merge says what is left.
const SESSION_REFS = (number) => `<!-- session: lane-3 -->\nRefs: #${number}\n\n## Summary`;
const mergedRefsNode = ({ mergedAt = "2026-10-16T08:30:00Z", body = SESSION_REFS(30), comments = [] } = {}) => ({
  createdAt: "2026-10-01T00:00:00Z",
  comments: { nodes: comments },
  timelineItems: { nodes: [{ source: { number: 7960, merged: true, mergedAt, body, repository: { nameWithOwner: REPO } } }] },
});
const decisionAt = (createdAt) => ({ createdAt, body: "**Decision recorded.** The conformance run is left.", lastEditedAt: null, author: { __typename: "User", databaseId: OWNER.id }, editor: null });
const mergedRefsWorld = ({ runs, node = mergedRefsNode(), failOn } = {}) => {
  const fake = world({ openReady: [ready(30, ["status: ready"])], comments: { 30: [note()] }, events: { 30: [added("2026-10-16T08:58:57Z", OWNER)] }, runs, blobs: BLOBS, done: { 30: node }, failOn });
  return { ...fake, actions: fake.github };
};

test("a merged Refs pull request under a session marker hands a stranded or failed issue to triage instead of a re-fire", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const handedOff = [
    `POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: refsMergedComment(7960) })}`,
    "SET 30 needs-triage",
  ];
  for (const conclusion of ["success", "failure"]) {
    const { github, actions, calls } = mergedRefsWorld({ runs: [laneRun({ at: "2026-10-16T08:59:00Z", conclusion })] });
    assert.equal(await sweep({ github, actions }), 0, conclusion);
    assert.deepEqual(writes(calls), handedOff, conclusion);
  }
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes(`label-unblocked: #30 not re-fired: ${doneReason([7960])}`), lines.join("\n"));
  // The comment went out but a label write did not: only the labels move.
  const fake = world({
    openReady: [ready(30, ["status: ready"])],
    comments: { 30: [note(), { id: 61, body: refsMergedComment(7960), user: LANES_BOT, created_at: "2026-10-16T11:30:00Z" }] },
    events: { 30: [added("2026-10-16T08:58:57Z", OWNER)] },
    runs: [laneRun({ at: "2026-10-16T08:59:00Z", conclusion: "success" })],
    blobs: BLOBS,
    done: { 30: mergedRefsNode() },
  });
  assert.equal(await sweep({ github: fake.github, actions: fake.github }), 0);
  assert.deepEqual(writes(fake.calls), handedOff.slice(1));
});

test("a merged Refs pull request a later decision comment answered, one naming another issue, or a failed read leaves the re-fire", async (t) => {
  t.mock.method(console, "log", () => {});
  const runs = [laneRun({ at: "2026-10-16T08:59:00Z", conclusion: "success" })];
  for (const [what, options] of [
    ["decided", { node: mergedRefsNode({ comments: [decisionAt("2026-10-16T08:45:00Z")] }) }],
    ["another issue", { node: mergedRefsNode({ body: SESSION_REFS(31) }) }],
    ["read failed", { failOn: (method, path, body) => path === "/graphql" && String(body?.query).includes("fragment done on Issue") }],
  ]) {
    const { github, actions, calls } = mergedRefsWorld({ runs, ...options });
    assert.equal(await sweep({ github, actions }), 0, what);
    assert.deepEqual(writes(calls), refiredFor(30, NO_REPORT_CAUSE), what);
  }
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
const splitRecordComment = (user = LANES_BOT, { parts = [[1], [2]], filed = [31, 32] } = {}) => ({
  id: 77,
  user,
  body: `${SIZE_SPLIT_MARKER}\n${renderSplitRecord({ items: "a".repeat(64), parts, order: [], filed })}\nSplit at intake.`,
  created_at: STAMP,
});
const subIssue = (number, overrides = {}) => ({ ...issue(number, { state: "closed" }), parent_issue_url: SPLIT_PARENT_URL, ...overrides });
const closeParentWrites = [
  `POST /repos/${REPO}/issues/30/comments`,
  `PATCH /repos/${REPO}/issues/30 {"state":"closed","state_reason":"completed"}`,
];
const mergedSecond = (overrides = {}) => subIssue(32, { closed_by: LANES_BOT, graphCloser: mergedPr({ number: 932 }), ...overrides });
function splitWorld({ second = mergedSecond(), record = splitRecordComment(), parent = issue(30), comments = [] } = {}) {
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  return world({
    closedList: [first],
    issues: { 30: parent, 31: first, 32: second },
    parents: { 31: parent },
    subIssues: { 30: [first, second] },
    comments: { 30: [...(record === null ? [] : [record]), ...comments] },
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

// The split parent's queue labels stay: the Work status field carries that state.
test("closing a split parent removes no queue label it carries", async () => {
  const { github, calls } = splitWorld({ parent: issue(30, { labels: ["agent-ready", "status: ready", "priority: high"] }) });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writtenPaths(calls), [
    closeParentWrites[0],
    closeParentWrites[1],
    "LEAVE 30 needs-triage",
  ]);
});

// A parked parent carries status: confirmed; its state labels come off only
// after the close, and attended stays.
test("closing a split parent removes its state labels after the close and keeps attended", async () => {
  const { github, calls } = splitWorld({ parent: issue(30, { labels: ["agent-ready", "status: confirmed", "host-run", "attended"] }) });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writtenPaths(calls), [
    closeParentWrites[0],
    closeParentWrites[1],
    `DELETE /repos/${REPO}/issues/30/labels/host-run`,
    "LEAVE 30 needs-triage",
  ]);
});

test("a failed host-run removal after a split parent's close fails the run", async (t) => {
  const { github: inner, calls } = splitWorld({ parent: issue(30, { labels: ["agent-ready", "host-run"] }) });
  const github = async (method, path, body) => {
    if (method === "DELETE" && path.endsWith("/issues/30/labels/host-run")) {
      calls.push(`${method} ${path}`);
      throw Object.assign(new Error("DELETE failed with status 502"), { status: 502 });
    }
    return inner(method, path, body);
  };
  const log = t.mock.method(console, "log", () => {});
  assert.equal(await sweep({ github }), 1);
  log.mock.restore();
  assert.deepEqual(writtenPaths(calls), [...closeParentWrites, `DELETE /repos/${REPO}/issues/30/labels/host-run`]);
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

test("a split parent stays open, and a later sweep writes nothing, when a sub-issue closed as not planned, as a duplicate or with no close reason", async () => {
  for (const reason of ["not_planned", "duplicate", null]) {
    const { github, calls } = splitWorld({ second: mergedSecond({ state_reason: reason }) });
    assert.equal(await sweep({ github }), 0);
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], String(reason));
  }
});

// #12456 class A: a parent split by hand whose own task list is its
// done-when (no split record, so no split parent), parked by admission on
// SIZE_SPLIT_DONE. Once every sub-issue is closed as completed by a trusted
// close, status: confirmed comes off, so intake admits it for one
// verified-done run. A not_planned sub-issue (class B) or any other park
// keeps it parked.
const ownCriteria = { ...issue(30, { labels: ["status: confirmed"] }), body: "## Done when\n\n- [ ] The guide names every flag.\n- [ ] The tests cover each flag." };
const parkedOn = (reason) => ({ id: 88, user: LANES_BOT, body: `${ADMIT_MARKER}\n${refusalText(reason)}`, created_at: STAMP });
const reenterWrites = [
  `POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: `${UNPARKED_MARKER}\nEvery sub-issue of this split closed as completed, so work-unblock set its Work status to needs-triage, and the hourly triage sweep sends it back to intake triage.` })}`,
  "SET 30 needs-triage",
];

test("a parent parked on split-done goes back to intake once its last sub-issue closes as completed: the marker comment, needs-triage, status: confirmed off", async () => {
  const { github, calls, writer } = splitWorld({ record: null, parent: ownCriteria, comments: [parkedOn(SIZE_SPLIT_DONE)] });
  assert.equal(await sweep({ github, writer }), 0);
  assert.deepEqual(writes(calls), reenterWrites);
});

test("a parent parked on split-done only on its Work status field goes back to intake once its last sub-issue closes", async () => {
  const parent = { ...ownCriteria, labels: [] };
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  const fake = withFieldHistory(
    world({
      closedList: [first],
      issues: { 30: parent, 31: first, 32: mergedSecond() },
      parents: { 31: parent },
      subIssues: { 30: [first, mergedSecond()] },
      comments: { 30: [parkedOn(SIZE_SPLIT_DONE)] },
      fieldValues: { 30: [workRow("confirmed")] },
    }),
    { 30: [fieldEvent(GRAPH_APP, "ready", null, 5), fieldEvent(GRAPH_APP, "confirmed", "ready", 6)] },
  );
  assert.equal(await sweep({ github: fake.github, writer: fake.writer, statusOf: fake.statusOf }), 0);
  assert.deepEqual(writes(fake.calls), reenterWrites.slice(0, 2), "the marker comment and needs-triage; no label to remove");
});

test("a parent stays parked with a not_planned or open sub-issue, an untrusted close, or another park reason", async () => {
  const outsider = { id: 4242, login: "someone-else", type: "User" };
  for (const setup of [
    { second: mergedSecond({ state_reason: "not_planned" }) },
    { second: subIssue(32, { state: "open", closed_by: null }) },
    { second: subIssue(32, { closed_by: outsider }) },
    { comments: [parkedOn("the work-resolve-issue lane stopped on it (`verify-unmet`); the guide does not name --dry-run")] },
    { parent: { ...ownCriteria, labels: [{ name: "status: confirmed" }, { name: "agent-ready" }] } },
  ]) {
    const { github, calls } = splitWorld({ record: null, parent: ownCriteria, comments: [parkedOn(SIZE_SPLIT_DONE)], ...setup });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(setup));
  }
});

const EARLIER = "2026-10-01T00:00:00Z";
const LATER = "2026-10-16T13:00:00Z";
test("a split record stays open when it leaves an item out or does not match the sub-issues", async () => {
  const threeItems = { ...issue(30), body: "- [ ] One\n- [ ] Two\n- [ ] Three" };
  for (const setup of [
    { record: splitRecordComment(LANES_BOT, { parts: [[1], [3]] }) },
    { parent: threeItems },
    { record: splitRecordComment(LANES_BOT, { parts: [[1], [2], [3]] }), parent: threeItems },
    { record: splitRecordComment(LANES_BOT, { filed: [31, 33] }) },
  ]) {
    const { github, calls } = splitWorld(setup);
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(setup));
  }
});

test("an open task item a listed human left in a comment on the parent keeps it open", async () => {
  const stays = { id: 78, user: OWNER, body: "Staying here, not in any part:\n\n- [ ] The broker change.", created_at: LATER };
  const { github, calls } = splitWorld({ comments: [stays] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
  const edited = splitWorld({ comments: [{ ...stays, created_at: EARLIER, updated_at: LATER }] });
  assert.equal(await sweep({ github: edited.github }), 0);
  assert.deepEqual(writes(edited.calls), []);
});

test("a split parent still closes when every sub-issue completed and every item is covered", async () => {
  for (const setup of [
    { parent: { ...issue(30), body: "## Done when\n\n- [ ] One\n- [ ] Two" } },
    { record: splitRecordComment(LANES_BOT, { parts: [[1, 2], [1, 2]] }), parent: { ...issue(30), body: "- [ ] One\n- [ ] Two" } },
    { comments: [{ id: 78, user: OWNER, body: "- [ ] #32\n- [x] Settled.", created_at: LATER }] },
    // The split took a listed human's lines from a comment written before it.
    { comments: [{ id: 78, user: OWNER, body: "- [ ] A line a part holds.", created_at: EARLIER }] },
    { comments: [{ id: 78, user: LANES_BOT, body: "- [ ] A refinement line a part holds.", created_at: STAMP }] },
  ]) {
    const { github, calls } = splitWorld(setup);
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writtenPaths(calls), closeParentWrites, JSON.stringify(setup));
  }
});

test("the App's close of a split parent does not count for what it blocks when a sub-issue closed any way but completed", async () => {
  for (const reason of ["not_planned", "duplicate", null]) {
    const parent = issue(30, { state: "closed", closer: LANES_BOT, at: "2026-10-16T11:30:00Z" });
    const { github, calls } = world({
      closedList: [parent],
      blockingOf: { 30: [issue(20)] },
      issues: { 20: issue(20), 30: parent, 31: subIssue(31), 32: subIssue(32, { state_reason: reason }) },
      blockedBy: { 20: [parent] },
      subIssues: { 30: [subIssue(31), subIssue(32, { state_reason: reason })] },
      comments: { 20: [note()], 30: [splitRecordComment()] },
    });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], String(reason));
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

// A split made by hand (#5901): no split record, but a listed human or the
// App linked every sub-issue (the newest sub_issue_added naming it), the
// parent is not `recurring`, and its body holds no open task-list item (the
// admission rules' `- [ ] `), so its work is its sub-issues'.
const linked = (number, actor = OWNER, repo = REPO) => ({
  event: "sub_issue_added",
  actor,
  created_at: "2026-10-15T00:00:00Z",
  sub_issue: { number, repository: { full_name: repo } },
});
const HAND_PARENT = { ...issue(30), body: "- [ ] #31\n- [ ] #32" };
function handSplitWorld({ parent = HAND_PARENT, links = [linked(31), linked(32)], comments = [], failOn } = {}) {
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  const second = subIssue(32, { closed_by: LANES_BOT, graphCloser: mergedPr({ number: 932 }) });
  return world({
    closedList: [first],
    issues: { 30: parent, 31: first, 32: second },
    parents: { 31: parent },
    subIssues: { 30: [first, second] },
    comments: { 30: comments },
    events: { 30: links },
    failOn,
  });
}

test("a split made by hand closes once every sub-issue a listed human or the App linked is closed", async () => {
  for (const links of [
    [linked(31), linked(32)],
    [linked(31, LANES_BOT), linked(32)],
  ]) {
    const { github, calls } = handSplitWorld({ links });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writtenPaths(calls), closeParentWrites, JSON.stringify(links));
  }
});

test("a split made by hand stays open on an untrusted or missing link, an open task item, recurring, or a failed read", async () => {
  const outsider = { id: 4242, login: "someone-else", type: "User" };
  for (const [setup, code] of [
    [{ links: [linked(31), linked(32, outsider)] }, 0],
    // The newest link of 32 is the outsider's re-add.
    [{ links: [linked(31), linked(32), { ...linked(32, outsider), created_at: "2026-10-15T01:00:00Z" }] }, 0],
    [{ links: [linked(31)] }, 0],
    [{ links: [linked(31), linked(32, OWNER, "melodic-software/other")] }, 0],
    [{ parent: { ...issue(30), body: "Split by hand.\n\n- [ ] One item left here." } }, 0],
    [{ parent: { ...HAND_PARENT, labels: [{ name: "recurring" }] } }, 0],
    // No task list at all: nothing shows a sub-issue carried the done-when.
    [{ parent: { ...issue(30), body: "## Acceptance\n\n- A dispatched run opens one pull request." } }, 0],
    [{ parent: issue(30) }, 0],
    [{ comments: [{ id: 78, user: OWNER, body: "- [ ] The broker change stays here.", created_at: STAMP }] }, 0],
    [{ failOn: (method, path) => method === "GET" && path.startsWith(`/repos/${REPO}/issues/30/events`) }, 1],
  ]) {
    const { github, calls } = handSplitWorld(setup);
    assert.equal(await sweep({ github }), code, JSON.stringify(setup));
    assert.deepEqual(writes(calls), [], JSON.stringify(setup));
  }
});

test("a split made by hand whose every box is ticked closes", async () => {
  const { github, calls } = handSplitWorld({ parent: { ...issue(30), body: "- [x] The parser\n- [X] The writer" } });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writtenPaths(calls), closeParentWrites);
});

test("the App's close of a split made by hand counts as done for what it blocks", async () => {
  for (const [links, expected, body = HAND_PARENT.body] of [
    [[linked(31), linked(32)], [labeled(20)]],
    [[linked(31)], []],
    [[linked(31), linked(32)], [], "## Acceptance\n\n- Prose only."],
  ]) {
    const parent = { ...issue(30, { state: "closed", closer: LANES_BOT, at: "2026-10-16T11:30:00Z" }), body };
    const { github, calls } = world({
      closedList: [parent],
      blockingOf: { 30: [issue(20)] },
      issues: { 20: issue(20), 30: parent, 31: subIssue(31), 32: subIssue(32) },
      blockedBy: { 20: [parent] },
      subIssues: { 30: [subIssue(31), subIssue(32)] },
      comments: { 20: [note()], 30: [] },
      events: { 30: links },
    });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), expected);
  }
});

// The sweep's parent rescan: an open issue whose sub_issues_summary shows every
// sub-issue completed, on its hour (its number modulo 24), closes under the
// same rules as on a sub-issue close, however long ago that close was.
const RESCAN_AT = Date.parse("2026-10-16T06:00:00Z");
const LONG_AGO = "2026-09-01T00:00:00Z";
const rescanParent = (number, body = `- [ ] #${number + 1}\n- [ ] #${number + 2}`) => ({ ...issue(number), body, sub_issues_summary: { total: 2, completed: 2 }, updated_at: LONG_AGO });
function rescanWorld(parents, extra = {}) {
  const kids = (n) => [n + 1, n + 2].map((c) => ({ ...issue(c, { state: "closed", at: LONG_AGO }), parent_issue_url: `${API}/repos/${REPO}/issues/${n}` }));
  return world({
    openIssues: parents,
    issues: Object.fromEntries(parents.flatMap((p) => [[p.number, p], ...kids(p.number).map((k) => [k.number, k])])),
    subIssues: Object.fromEntries(parents.map((p) => [p.number, kids(p.number)])),
    events: Object.fromEntries(parents.map((p) => [p.number, [linked(p.number + 1), linked(p.number + 2)]])),
    ...extra,
  });
}
const parentClosed = (n) => [`POST /repos/${REPO}/issues/${n}/comments`, `PATCH /repos/${REPO}/issues/${n} {"state":"closed","state_reason":"completed"}`];
const OPEN_LISTING = `GET /repos/${REPO}/issues?state=open&sort=updated&direction=asc`;

test("the parent rescan closes a finished split parent whose last sub-issue closed outside the sweep window", async () => {
  const { github, calls } = rescanWorld([rescanParent(30)]);
  assert.equal(await sweep({ github, now: RESCAN_AT }), 0);
  assert.deepEqual(writtenPaths(calls), parentClosed(30));
  // A record-split parent closes the same way.
  const recorded = rescanWorld([{ ...rescanParent(30, "- [ ] One\n- [ ] Two"), body: "- [ ] One\n- [ ] Two" }], { comments: { 30: [splitRecordComment()] } });
  assert.equal(await sweep({ github: recorded.github, now: RESCAN_AT }), 0);
  assert.deepEqual(writtenPaths(recorded.calls), parentClosed(30));
});

test("the parent rescan leaves a finished parent outside this hour's rotation unread", async () => {
  for (const [parents, now] of [
    [[rescanParent(31)], RESCAN_AT],
    [[rescanParent(30)], NOW],
  ]) {
    const { github, calls } = rescanWorld(parents);
    assert.equal(await sweep({ github, now }), 0);
    assert.deepEqual(writes(calls), []);
    assert.ok(!calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/${parents[0].number}`)), calls.join("\n"));
  }
});

test("the parent rescan reads at most limits.parent-rescan-per-run parents, in listing order", async () => {
  const numbers = [30, 54, 78, 102, 126, 150];
  const all = rescanWorld(numbers.map((n) => rescanParent(n)));
  assert.equal(await sweep({ github: all.github, now: RESCAN_AT }), 0);
  assert.deepEqual(writtenPaths(all.calls), numbers.slice(0, 5).flatMap(parentClosed));
  const two = rescanWorld(numbers.map((n) => rescanParent(n)));
  assert.equal(await sweep({ github: two.github, now: RESCAN_AT }, withLimits({ "parent-rescan-per-run": 2 })), 0);
  assert.deepEqual(writtenPaths(two.calls), numbers.slice(0, 2).flatMap(parentClosed));
  assert.ok(!two.calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/78`)));
});

test("the parent rescan leaves a refused parent open and logs why", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { github, calls } = rescanWorld([rescanParent(30, "Split by hand.\n\n- [ ] One item left here.")]);
  assert.equal(await sweep({ github, now: RESCAN_AT }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(log.mock.calls.some((call) => call.arguments[0] === "label-unblocked: #30 stays open: it is not a split parent"));
});

test("with no finished parent in the listing, the rescan makes no read beyond the one open-issue listing", async () => {
  const waiting = { ...issue(30), sub_issues_summary: { total: 2, completed: 1 } };
  const none = { ...issue(54), sub_issues_summary: { total: 0, completed: 0 } };
  const { github, calls } = rescanWorld([waiting, none]);
  assert.equal(await sweep({ github, now: RESCAN_AT }), 0);
  assert.equal(calls.filter((call) => call.startsWith(OPEN_LISTING)).length, 1);
  assert.ok(!calls.some((call) => /\/issues\/(30|54)(\/|$)/.test(call.split(" ")[1])), calls.join("\n"));
  assert.deepEqual(writes(calls), []);
});

// A split by hand whose sub-issues all completed by trusted closes still stays
// open while its body holds an unticked item that cites no sub-issue: its own
// done-when, which no sub-issue carried (owner Q93).
test("an unticked done-when item in a hand-split parent's body keeps it open on a sub-issue close and on the rescan", async (t) => {
  const own = "- [ ] #31\n- [ ] #32\n- [ ] The parent's own done-when line.";
  const log = t.mock.method(console, "log", () => {});
  const refused = (n) => log.mock.calls.some((call) => call.arguments[0] === `label-unblocked: #${n} stays open: it is not a split parent`);
  const closing = handSplitWorld({ parent: { ...issue(30), body: own } });
  assert.equal(await sweep({ github: closing.github }), 0);
  assert.deepEqual(writes(closing.calls), []);
  assert.ok(refused(30));
  log.mock.resetCalls();
  const rescanned = rescanWorld([rescanParent(30, own)]);
  assert.equal(await sweep({ github: rescanned.github, now: RESCAN_AT }), 0);
  assert.deepEqual(writes(rescanned.calls), []);
  assert.ok(refused(30));
  // The control: that line ticked, the rescan closes it.
  const ticked = rescanWorld([rescanParent(30, own.replace("- [ ] The", "- [x] The"))]);
  assert.equal(await sweep({ github: ticked.github, now: RESCAN_AT }), 0);
  assert.deepEqual(writtenPaths(ticked.calls), parentClosed(30));
});

test("the ACTIONS_TOKEN clients' readings land under github-token, the App client's under API_BUDGET_TOKEN", async () => {
  const dir = tempDir("label-unblocked-budget-");
  const saved = { token: process.env.API_BUDGET_TOKEN, temp: process.env.RUNNER_TEMP };
  process.env.API_BUDGET_TOKEN = "lanes-app";
  process.env.RUNNER_TEMP = dir;
  try {
    const headers = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4999", "x-ratelimit-used": "1", "x-ratelimit-reset": "1792378942", "x-ratelimit-resource": "core" };
    const fetchImpl = async () => new Response("{}", { status: 200, headers });
    const latch = createRateLimitLatch();
    const actions = budgetLatch("github-token", latch);
    await createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl, latch: actions })("GET", "/repos/o/r/actions/runs");
    await createJobLogReader({ token: "t", apiUrl: "https://api.example", fetchImpl, latch: actions })("o/r", 1, { maxBytes: 10 });
    await createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl, latch })("GET", "/repos/o/r/issues");
    const line = (route) => `200 5000 4999 1 1792378942 core ${route}\n`;
    assert.equal(readFileSync(join(dir, "api-budget", "github-token"), "utf8"), line("other") + line("other"));
    assert.equal(readFileSync(join(dir, "api-budget", "lanes-app"), "utf8"), line("other"));
  } finally {
    for (const [key, value] of [["API_BUDGET_TOKEN", saved.token], ["RUNNER_TEMP", saved.temp]]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

// An open `status: ready` issue with neither agent-ready nor admission-deferred
// sits in no queue: a deferral whose label was lost, or a `status: ready` set
// by hand. Each sweep runs intake's admission (admit.mjs decide) on at most
// limits.readmit-per-run (default 20) of them, oldest updated first, and
// writes as intake does: agent-ready within the room, admission-deferred past
// it, a refusal parked at status: confirmed, or at needs-owner-decision when
// it holds for a person.
const READY_LABELS = ["status: ready", "work-class: mechanical"];
const readyIssue = (number, { labels = READY_LABELS, updated = "2026-10-16T06:00:00Z", user = OWNER, ...rest } = {}) => ({
  ...issue(number, { labels }),
  user,
  type: { name: "Task" },
  body: "Fix it.\n\n## Done when\n\n- [ ] Line 3 says nineteen.",
  created_at: "2026-10-10T00:00:00Z",
  updated_at: updated,
  ...rest,
});
const readyWorld = ({ items = [readyIssue(26)], events = {}, fields = SMALL_LOW_KNOWN, queuedIssues = [], deferred = [], extra = {} } = {}) =>
  world({
    ready: items,
    deferred,
    issues: Object.fromEntries(items.map((item) => [item.number, item])),
    comments: Object.fromEntries(items.map((item) => [item.number, [note()]])),
    events: Object.fromEntries(items.map((item) => [item.number, events[item.number] ?? [labelAdd("status: ready", LANES_BOT)]])),
    fieldValues: Object.fromEntries(items.map((item) => [item.number, fields])),
    queuedIssues,
    ...extra,
  });
const fieldReadsOf = (calls, n) => calls.filter((call) => call === `GET /repos/${REPO}/issues/${n}/issue-field-values`).length;
const eventReads = (calls, n) => calls.filter((call) => call.startsWith(`GET /repos/${REPO}/issues/${n}/events`)).length;

test("an admissible status: ready issue in no queue is labeled agent-ready within the room", async (t) => {
  t.mock.method(console, "log", () => {});
  for (const by of [LANES_BOT, OWNER]) {
    const { github, calls } = readyWorld({ events: { 26: [labelAdd("status: ready", by)] } });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(calls), [labeled(26)], by.login);
  }
});

test("a status: ready only in the Work status puts an issue in no queue through admission, from the one field listing", async (t) => {
  t.mock.method(console, "log", () => {});
  const field = withFieldHistory(readyWorld({ items: [readyIssue(26, { labels: [] })], events: { 26: [] }, fields: [...SMALL_LOW_KNOWN, workRow("ready")] }), {
    26: [fieldEvent(GRAPH_OWNER, "ready", null, 1)],
  });
  const listings = [];
  const byStatus = async (states) => {
    listings.push(states);
    return states ? [] : [{ number: 26, created_at: "2026-10-10T00:00:00Z", labels: ["status: ready"], state: "ready" }];
  };
  assert.equal(await sweep({ github: field.github, writer: field.writer, statusOf: field.statusOf, byStatus, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(field.calls), [labeled(26)]);
  // Admission's deferred and all-state listings, then the restart rules' agent-ready one.
  assert.deepEqual(listings, [["deferred"], undefined, ["agent-ready"]]);
  // Without the field listing the same issue reads as in no state and is not decided.
  const bare = readyWorld({ items: [readyIssue(26, { labels: [] })], events: { 26: [] } });
  assert.equal(await sweep({ github: bare.github, writer: bare.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(bare.calls), []);
});

// issuesByStatus leaves an issue whose Work status is mid-write out and names
// it in `held`; its labels could miss a field hold, so readmitReady skips it.
test("an issue the field listing holds mid-write is not decided this sweep, though its labels read status: ready", async (t) => {
  t.mock.method(console, "log", () => {});
  const listingOf = (held) => async (states) => (states ? [] : Object.defineProperty([], "held", { value: held }));
  const holding = readyWorld();
  assert.equal(await sweep({ github: holding.github, byStatus: listingOf([{ number: 26, created_at: "2026-10-10T00:00:00Z", reason: "mid-write" }]), admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(holding.calls), []);
  const free = readyWorld();
  assert.equal(await sweep({ github: free.github, byStatus: listingOf([]), admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(free.calls), [labeled(26)], "left out without being held, its labels decide");
});

// The production listing (fieldListing over resolve-config.mjs issuesByStatus)
// must carry issuesByStatus' non-enumerable `held` through its relabeling map.
test("fieldListing carries a mid-write issue's hold to readmitReady, which leaves it undecided and admits the settled one", async (t) => {
  t.mock.method(console, "log", () => {});
  // The per-issue re-read waits DISAGREEMENT_WAIT_MS; ticked below.
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const field = { fullDatabaseId: String(STATUS_CONFIG["field-id"]) };
  // #26's value and newest event disagree, in the listing and on its own re-read.
  const fields = { 26: { state: "needs-triage", named: "ready", setter: OWNER.id }, 27: { state: "ready", setter: OWNER.id } };
  const listed = async (method, path, body) => {
    assert.ok(method === "POST" && path === "/graphql" && /issues\(states: OPEN/.test(body.query), `unexpected ${method} ${path}`);
    const nodes = [26, 27].map((number) => {
      const entry = fields[number];
      return {
        number,
        createdAt: "2026-10-10T00:00:00Z",
        labels: { nodes: READY_LABELS.map((name) => ({ name })) },
        issueFieldValues: { nodes: [{ name: entry.state, field }] },
        timelineItems: { nodes: [{ __typename: "IssueFieldChangedEvent", newValue: entry.named ?? entry.state, actor: { databaseId: entry.setter }, issueField: field }] },
      };
    });
    return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
  };
  const byStatus = fieldListing({ BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED }, withFields(listed, fields), REPO);
  const { github, calls } = readyWorld({ items: [readyIssue(26), readyIssue(27)] });
  let done = false;
  const run = sweep({ github, byStatus, admission: admissionFor() }, PAUSING).finally(() => {
    done = true;
  });
  for (let ticks = 0; !done && ticks < 100; ticks += 1) {
    await new Promise((resolve) => setImmediate(resolve));
    t.mock.timers.tick(DISAGREEMENT_WAIT_MS);
  }
  assert.equal(await run, 0);
  assert.deepEqual(writes(calls), [labeled(27)], "#26's status: ready label must not readmit it while its Work status is mid-write");
});

test("an admissible status: ready issue in no queue with no room gets admission-deferred", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = readyWorld({ queuedIssues: queuedN(24) });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [deferredLabel(26)]);
});

test("a status: ready issue whose agent-ready a person removed is left alone until status: ready is added again", async (t) => {
  t.mock.method(console, "log", () => {});
  const removed = { event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-10-16T08:00:00Z" };
  const stands = readyWorld({ events: { 26: [labelAdd("status: ready", LANES_BOT), removed] } });
  assert.equal(await sweep({ github: stands.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(stands.calls), []);
  assert.equal(fieldReadsOf(stands.calls, 26), 0);
  const marked = readyWorld({ events: { 26: [labelAdd("status: ready", LANES_BOT), removed, labelAdd("status: ready", OWNER, "2026-10-16T09:00:00Z")] } });
  assert.equal(await sweep({ github: marked.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(marked.calls), [labeled(26)]);
});

test("a status: ready issue added by neither a listed human nor the lanes App is left alone", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = readyWorld({
    items: [readyIssue(27), readyIssue(26)],
    events: { 27: [labelAdd("status: ready", { id: 4242, login: "drive-by" })] },
  });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  // #26, the App's status: ready, is admitted in the same sweep.
  assert.deepEqual(writes(calls), [labeled(26)]);
  assert.equal(fieldReadsOf(calls, 27), 0);
});

test("a status: ready issue with a hold or refuse label, an open blocker or an open sub-issue is not read", async (t) => {
  t.mock.method(console, "log", () => {});
  const skipped = [
    ...["needs-human", "needs-owner-decision", "needs-reporter-info", "provenance: untrusted", "host-run", "duplicate", "do-not-merge"].map((hold, i) =>
      readyIssue(40 + i, { labels: [...READY_LABELS, hold] }),
    ),
    readyIssue(60, { issue_dependencies_summary: { blocked_by: 1, total_blocked_by: 1 } }),
    readyIssue(61, { sub_issues_summary: { total: 2, completed: 1 } }),
  ];
  const { github, calls } = readyWorld({ items: [...skipped, readyIssue(26)] });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [labeled(26)]);
  for (const item of skipped) {
    assert.equal(eventReads(calls, item.number), 0, String(item.number));
    assert.ok(!calls.includes(`GET /repos/${REPO}/issues/${item.number}`), String(item.number));
  }
});

test("a sweep decides at most limits.readmit-per-run status: ready issues, oldest updated first, and skipped ones do not count", async (t) => {
  t.mock.method(console, "log", () => {});
  const removed = { event: "unlabeled", label: { name: "agent-ready" }, actor: OWNER, created_at: "2026-10-16T08:00:00Z" };
  // #29 is held and #33's agent-ready removal stands: neither is decided, and
  // each skip writes nothing, so it stays oldest updated on every sweep.
  const items = [
    readyIssue(29, { labels: [...READY_LABELS, "needs-human"], updated: "2026-10-16T05:00:00Z" }),
    readyIssue(33, { updated: "2026-10-16T05:30:00Z" }),
    readyIssue(27, { updated: "2026-10-16T06:00:00Z" }),
    readyIssue(28, { updated: "2026-10-16T07:00:00Z" }),
    readyIssue(26, { updated: "2026-10-16T08:00:00Z" }),
  ];
  const { github, calls } = readyWorld({ items, events: { 33: [labelAdd("status: ready", LANES_BOT), removed] } });
  assert.equal(await sweep({ github, admission: admissionFor() }, withConfig({ wip: { "pause-from": "2026-10-01" }, limits: { "readmit-per-run": 2 } })), 0);
  assert.deepEqual(writes(calls), [labeled(27), labeled(28)]);
  assert.equal(fieldReadsOf(calls, 33), 0);
  assert.equal(eventReads(calls, 26), 0);
});

test("a wait that writes nothing durable (a Size large split pending) does not use up readmit-per-run", async (t) => {
  t.mock.method(console, "log", () => {});
  // #30 is oldest and waits on its split; with the cap at 1 it must not stop
  // #26 from being admitted, or the same wait would take the cap every sweep.
  const items = [readyIssue(30, { updated: "2026-10-16T05:00:00Z" }), readyIssue(26, { updated: "2026-10-16T06:00:00Z" })];
  const { github, calls } = readyWorld({ items, extra: { fieldValues: { 30: LARGE_LOW_KNOWN, 26: SMALL_LOW_KNOWN } } });
  assert.equal(await sweep({ github, admission: admissionFor() }, withConfig({ wip: { "pause-from": "2026-10-01" }, limits: { "readmit-per-run": 1 } })), 0);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/30/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: Size large: the split into sub-issues at intake is pending (owner Q93).` })}`,
    labeled(26),
  ]);
});

test("a status: ready issue already agent-ready or deferred is not run through admission a second time", async (t) => {
  t.mock.method(console, "log", () => {});
  const queued = readyIssue(31, { labels: [...READY_LABELS, "agent-ready"] });
  const waiting = readyIssue(32, { labels: [...READY_LABELS, "admission-deferred"] });
  const { github, calls } = readyWorld({
    items: [queued, waiting, readyIssue(26)],
    deferred: [waiting],
    events: { 32: [labelAdd("status: ready", LANES_BOT), deferredAdd(LANES_BOT)] },
    extra: { blockedBy: { 32: [] } },
  });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  // The deferred path alone admits #32, once; #31 is left as it is, and #26,
  // in no queue, is admitted.
  assert.deepEqual(writes(calls), [labeled(32), labeled(26)]);
  assert.equal(eventReads(calls, 31), 0);
  assert.equal(fieldReadsOf(calls, 32), 0);
});

test("a status: ready issue in no queue that admission refuses parks at status: confirmed, or at needs-owner-decision for a person", async (t) => {
  t.mock.method(console, "log", () => {});
  const refused = (n, status, reasons, code = null) => [
    `SET ${n} ${status === "needs-owner-decision" ? "needs-owner-decision" : "confirmed"}`,
    `POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body: code === null ? `${ADMIT_MARKER}\n${refusalText(reasons.join("; "))}` : heldBody(reasons.join("; "), code) })}`,
  ];
  // Field values no listed human or App set are unset: a mechanical refusal.
  const unset = readyWorld();
  assert.equal(await sweep({ github: unset.github, writer: unset.writer, admission: admissionFor(4242) }, PAUSING), 0);
  assert.deepEqual(writes(unset.calls), refused(26, "status: confirmed", ["Size unset is not one of small, medium", "Uncertainty unset is not one of known, knowable"]));
  // An author who is not listed is a refusal a person settles.
  const stranger = readyWorld({ items: [readyIssue(26, { user: { id: 4242, login: "drive-by" } })] });
  assert.equal(await sweep({ github: stranger.github, writer: stranger.writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(stranger.calls), refused(26, "needs-owner-decision", ["the author is neither a listed human nor the lanes App"], DECIDE_SECURITY));
});

// A born-triaged issue (check-born-triaged notBornTriaged) whose filer has not
// set its Size and Uncertainty yet waits: no label, no comment, no share of
// readmit-per-run. A set value the rules refuse, or a marker the trust check
// does not accept, still refuses.
const BORN = `${readyIssue(26).body}\n\n<!-- work-items:born-triaged -->\n`;
const UNSET_REASONS = ["Size unset is not one of small, medium", "Uncertainty unset is not one of known, knowable"];
const parkedFor = (n, status, reasons, code = null) => [
  `SET ${n} ${status === "needs-owner-decision" ? "needs-owner-decision" : "confirmed"}`,
  `POST /repos/${REPO}/issues/${n}/comments ${JSON.stringify({ body: code === null ? `${ADMIT_MARKER}\n${refusalText(reasons.join("; "))}` : heldBody(reasons.join("; "), code) })}`,
];

test("a born-triaged status: ready issue whose fields are not set yet waits with no write, and is admitted once they are", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const early = readyWorld({ items: [readyIssue(26, { body: BORN })], fields: [] });
  assert.equal(await sweep({ github: early.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(early.calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #26 waits: born triaged, size and uncertainty not set yet"), lines.join("\n"));
  const later = readyWorld({ items: [readyIssue(26, { body: BORN })], fields: SMALL_LOW_KNOWN });
  assert.equal(await sweep({ github: later.github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(later.calls), [labeled(26)]);
});

test("an issue with unset fields is still refused when it is not born triaged, or its marker or author fails the trust check", async (t) => {
  t.mock.method(console, "log", () => {});
  const stranger = { id: 4242, login: "drive-by" };
  const cases = [
    // No marker: as today.
    [readyIssue(26), "status: confirmed", UNSET_REASONS],
    // The marker quoted mid-body, not the body's last line.
    [readyIssue(26, { body: `<!-- work-items:born-triaged -->\n\n${readyIssue(26).body}` }), "status: confirmed", UNSET_REASONS],
    // An author who is not listed.
    [readyIssue(26, { body: BORN, user: stranger }), "needs-owner-decision", ["the author is neither a listed human nor the lanes App", ...UNSET_REASONS], DECIDE_SECURITY],
  ];
  for (const [item, status, reasons, code] of cases) {
    const { github, calls, writer } = readyWorld({ items: [item], fields: [] });
    assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
    assert.deepEqual(writes(calls), parkedFor(26, status, reasons, code), item.body);
  }
});

test("a born-triaged issue with a field set to a refused value is refused, its unset field named too", async (t) => {
  t.mock.method(console, "log", () => {});
  const unknown = [fieldRow(48625721, 85127656)];
  const { github, calls, writer } = readyWorld({ items: [readyIssue(26, { body: BORN })], fields: unknown });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), parkedFor(26, "status: confirmed", ["Size unset is not one of small, medium", "Uncertainty unknown is not one of known, knowable"]));
});

test("a born-triaged issue waiting on its fields does not use up readmit-per-run", async (t) => {
  t.mock.method(console, "log", () => {});
  const items = [readyIssue(30, { body: BORN, updated: "2026-10-16T05:00:00Z" }), readyIssue(26, { updated: "2026-10-16T06:00:00Z" })];
  const { github, calls } = readyWorld({ items, extra: { fieldValues: { 30: [], 26: SMALL_LOW_KNOWN } } });
  assert.equal(await sweep({ github, admission: admissionFor() }, withConfig({ wip: { "pause-from": "2026-10-01" }, limits: { "readmit-per-run": 1 } })), 0);
  assert.deepEqual(writes(calls), [labeled(26)]);
});

// A person's deferral of a born-triaged issue whose fields are not set yet says
// why and comes off, so the readmit path admits it once they land and the
// triage sweep still sees it if they never do; it never waits silently.
test("a person's mark on a born-triaged issue whose fields are not set yet says why and drops the deferral", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = markedWorld({ fields: [], body: BORN });
  assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    `POST /repos/${REPO}/issues/25/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: born triaged, size and uncertainty not set yet.` })}`,
    undeferred(25),
  ]);
});

test("a status: ready issue in no queue refused for a person takes a parked status: confirmed off, after the hold", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = readyWorld({ items: [readyIssue(26, { labels: ["status: ready", "status: confirmed"], user: { id: 4242, login: "drive-by" } })] });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  const posted = writes(calls);
  assert.ok(posted.includes("SET 26 needs-owner-decision"), posted.join("\n"));
  assert.ok(!posted.some((call) => call.includes("/labels")), posted.join("\n"));
});

test("a status: ready issue in no queue refused for a manual external step parks at status: confirmed with attended", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = readyWorld({ extra: { specs: { 26: manualSpec(readyIssue(26).body) } } });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    "SET 26 confirmed",
    `POST /repos/${REPO}/issues/26/labels {"labels":["attended"]}`,
    `POST /repos/${REPO}/issues/26/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(ATTENDED_REASON)}` })}`,
  ]);
});

test("a status: ready issue in no queue an open pull request is for gets admission-deferred and the wait comment", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls, writer } = readyWorld({ extra: { timeline: { 26: [{ ...namingPull("open"), source: { issue: { ...namingPull("open").source.issue, body: "Refs: #26" } } }] } } });
  assert.equal(await sweep({ github, writer, admission: admissionFor() }, PAUSING), 0);
  assert.deepEqual(writes(calls), [
    deferredLabel(26),
    `POST /repos/${REPO}/issues/26/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: open pull request #40 is for it.` })}`,
  ]);
});

// A blocker the lanes App closed report-delivered is no completed work (owner
// Q9); it stops holding its dependent once a status: ready or agent-ready add
// by the App or a listed human postdates the close (admit.mjs reportCleared).
const reportDeliveredClose = (user, at) => ({
  user,
  created_at: at,
  html_url: "https://github.com/o/r/issues/7#issuecomment-1",
  body: ["<!-- work-resolve-issue outcome=closed run=555 -->", "The work-resolve-issue lane stopped on this issue (`report-delivered`): the run posted the report.", "", "In the run's words:", "", "> the report"].join("\n"),
});

test("a status: ready issue whose blocker the App closed report-delivered is admitted only once a verdict postdates the close", async (t) => {
  const closedAt = "2026-10-16T06:30:00Z";
  for (const [comments, readyAt, expected, closer = LANES_BOT] of [
    [[reportDeliveredClose(LANES_BOT, closedAt)], "2026-10-16T07:00:00Z", "admit"],
    [[reportDeliveredClose(LANES_BOT, closedAt)], "2026-10-16T06:00:00Z", "retriage"],
    [[reportDeliveredClose(OWNER, closedAt)], "2026-10-16T07:00:00Z", "wait"],
    [[], "2026-10-16T07:00:00Z", "wait"],
    // Reopened and closed again by someone else: the App's older report
    // speaks for no close the App made.
    [[reportDeliveredClose(LANES_BOT, closedAt)], "2026-10-16T07:00:00Z", "wait", { id: 777, login: "triage-user" }],
    [[reportDeliveredClose(LANES_BOT, closedAt)], "2026-10-16T06:00:00Z", "wait", { id: 777, login: "triage-user" }],
  ]) {
    const item = readyIssue(26);
    const blocker = issue(30, { state: "closed", closer, at: closedAt });
    const { github, calls } = readyWorld({
      items: [item],
      events: { 26: [labelAdd("status: ready", LANES_BOT, readyAt)] },
      extra: { issues: { 26: item, 30: blocker }, comments: { 26: [note()], 30: comments }, blockedBy: { 26: [blocker] } },
    });
    assert.equal(await sweep({ github, admission: admissionFor() }, PAUSING), 0);
    const written = writes(calls);
    assert.equal(written.includes(labeled(26)), expected === "admit", readyAt);
    assert.equal(written.includes("SET 26 needs-triage"), expected === "retriage", readyAt);
  }
});

// A parent parked as "split pending" and then split by hand waits on its open
// sub-issues, and readmitReady leaves it out unread, so its admission comment
// is rewritten to name them: on a sub-issue close (closeSplitParent's reads),
// and on the sweep for the parents whose number is the UTC hour modulo 24.
const admissionNote = (reasons, id = 88) => ({ id, user: LANES_BOT, body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: ${reasons}.`, created_at: STAMP });
const refreshed = (text, id = 88) => `PATCH /repos/${REPO}/issues/comments/${id} ${JSON.stringify({ body: `${ADMIT_MARKER}\nNot admitted to the issue lane yet: ${text}.` })}`;
function splitWaitWorld({ labels = ["status: ready"], blockedBy = 0, note = admissionNote(SIZE_SPLIT_PENDING) } = {}) {
  const parent = { ...issue(30, { labels }), issue_dependencies_summary: { blocked_by: blockedBy } };
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  const second = subIssue(32, { state: "open", closed_by: null });
  return world({
    closedList: [first],
    issues: { 30: parent, 31: first, 32: second },
    parents: { 31: parent },
    subIssues: { 30: [first, second] },
    comments: { 30: [note] },
  });
}

test("a sub-issue closing rewrites its parent's split-pending admission comment to name the open sub-issues", async () => {
  const { github, calls } = splitWaitWorld();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [refreshed("sub-issue #32 is open")]);
  const stale = splitWaitWorld({ note: admissionNote("sub-issue #31 is open; sub-issue #32 is open") });
  assert.equal(await sweep({ github: stale.github }), 0);
  assert.deepEqual(writes(stale.calls), [refreshed("sub-issue #32 is open")]);
});

test("a parent's admission comment stays when it gives another reason, the parent is blocked, or it is not status: ready in no queue", async () => {
  for (const setup of [
    { note: admissionNote("sub-issue #32 is open") },
    { note: { ...admissionNote(SIZE_SPLIT_PENDING), body: `${ADMIT_MARKER}\n${refusalText("Size huge is not one of small")}` } },
    { note: admissionNote(`${SIZE_SPLIT_PENDING}; blocker #12 is open`) },
    { blockedBy: 1 },
    { labels: [] },
    { labels: ["status: ready", "needs-owner-decision"] },
  ]) {
    const { github, calls } = splitWaitWorld(setup);
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(setup));
  }
});

test("a failed admission-comment refresh on a sub-issue close is a warning, not a failed sweep", async () => {
  const parent = { ...issue(30, { labels: ["status: ready"] }), issue_dependencies_summary: { blocked_by: 0 } };
  const first = subIssue(31, { closed_at: "2026-10-16T11:30:00Z" });
  const second = subIssue(32, { state: "open", closed_by: null });
  const { github, calls } = world({
    closedList: [first],
    issues: { 30: parent, 31: first, 32: second },
    parents: { 31: parent },
    subIssues: { 30: [first, second] },
    comments: { 30: [admissionNote(SIZE_SPLIT_PENDING)] },
    failOn: (method, path) => method === "PATCH" && path.startsWith(`/repos/${REPO}/issues/comments/`),
  });
  assert.equal(await sweep({ github }), 0);
  assert.ok(calls.some((call) => call.startsWith(`PATCH /repos/${REPO}/issues/comments/88 `)), "the refresh was tried");
});

// GitHub's sub_issues_summary leaves a duplicate close out of `completed`, so
// the summary alone would keep this parent waiting with nothing open.
test("a Size large parent whose every sub-issue is closed, one as a duplicate, is refused once by the rotation, with the split-done reason", async (t) => {
  t.mock.method(console, "log", () => {});
  const parent = (number) => readyIssue(number, { sub_issues_summary: { total: 2, completed: 1 }, issue_dependencies_summary: { blocked_by: 0 } });
  const subs = [subIssue(41), subIssue(42, { state_reason: "duplicate" })];
  const refusal = `${ADMIT_MARKER}\n${refusalText(SIZE_SPLIT_DONE)}`;
  const first = readyWorld({ items: [parent(36)], fields: LARGE_LOW_KNOWN, extra: { comments: { 36: [admissionNote("sub-issue #42 is open")] }, subIssues: { 36: subs } } });
  assert.equal(await sweep({ github: first.github, admission: admissionFor() }, PAUSING), 0);
  assert.ok(writes(first.calls).includes(`PATCH /repos/${REPO}/issues/comments/88 ${JSON.stringify({ body: refusal })}`), writes(first.calls).join("\n"));
  assert.ok(writes(first.calls).includes("SET 36 confirmed"), writes(first.calls).join("\n"));
  const again = readyWorld({ items: [parent(36)], fields: LARGE_LOW_KNOWN, extra: { comments: { 36: [{ ...admissionNote("x"), body: refusal }] }, subIssues: { 36: subs } } });
  assert.equal(await sweep({ github: again.github, admission: admissionFor() }, PAUSING), 0);
  assert.ok(!writes(again.calls).some((call) => call.includes("/comments")));
});

test("the sweep's rotation reads no comments of a held or queued parent", async () => {
  // NOW is 12:00 UTC, so 36 is in the rotation slot.
  for (const label of ["agent-ready", "needs-owner-decision"]) {
    const parent = readyIssue(36, { labels: [...READY_LABELS, label], sub_issues_summary: { total: 2, completed: 1 }, issue_dependencies_summary: { blocked_by: 0 } });
    const { github, calls } = readyWorld({
      items: [parent],
      extra: { comments: { 36: [admissionNote(SIZE_SPLIT_PENDING)] }, subIssues: { 36: [subIssue(41, { state: "open", closed_by: null })] } },
    });
    await sweep({ github });
    assert.ok(!calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/36/comments`)), label);
  }
});

test("the sweep rewrites the split-pending comment of an open-sub-issue parent whose number is the UTC hour modulo 24, and reads no other", async () => {
  // NOW is 12:00 UTC: 36 is read, 37 is not.
  const parent = (number) => readyIssue(number, { sub_issues_summary: { total: 2, completed: 1 }, issue_dependencies_summary: { blocked_by: 0 } });
  const { github, calls } = readyWorld({
    items: [parent(36), parent(37)],
    extra: {
      comments: { 36: [admissionNote(SIZE_SPLIT_PENDING)], 37: [admissionNote(SIZE_SPLIT_PENDING, 89)] },
      subIssues: { 36: [subIssue(41, { state: "open", closed_by: null }), subIssue(42)], 37: [subIssue(43, { state: "open", closed_by: null })] },
    },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [refreshed("sub-issue #41 is open")]);
  assert.ok(!calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/37/`)));
});

test("a close runs the close path and lists no closed issues", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ now: NOW, env: envFor({ issue: issue(10, { state: "closed", labels: ["bug"] }) }), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(!calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues?state=closed`)));
});

// A sweep waiting behind another (one pending run in the job's concurrency
// group) sees what the first left.
test("two back-to-back sweeps re-fire the issue the kill switch stopped at broker-check once", async () => {
  // The first sweep re-fires the stopped issue: its breaker record, then the
  // App's remove and re-add.
  const first = stalledRun({ jobs: BROKER_REFUSED, logs: CHECK_KILLED });
  assert.equal(await sweep({ github: first.github, actions: first.actions }), 0);
  tripped(first.calls);
  const posted = writes(first.calls)[0];
  const record = JSON.parse(posted.slice(posted.indexOf(" {") + 1)).body;
  // The second sees the record and the re-add, with no lane run since. It
  // writes nothing.
  const second = stalledRun({
    jobs: BROKER_REFUSED,
    logs: CHECK_KILLED,
    comments: [note(), { id: 71, body: record, user: LANES_BOT, created_at: "2026-10-16T11:59:30Z" }],
    events: [
      added(LABELED_AT, OWNER),
      { event: "unlabeled", label: { name: "agent-ready" }, actor: LANES_BOT, created_at: "2026-10-16T11:59:30Z" },
      added("2026-10-16T11:59:31Z"),
    ],
  });
  assert.equal(await sweep({ github: second.github, actions: second.actions }), 0);
  assert.ok(second.calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues?state=open&labels=agent-ready`)));
  assert.deepEqual(writes(second.calls), []);
});

// The carried verdicts (verdict-carry.mjs): a completed run's job listing and
// a read log's refusal never change, so the next sweep takes them from the
// file the last one kept instead of GitHub, and reads GitHub for anything the
// file does not answer.
const jobReads = (calls) => calls.filter((call) => /^GET \/repos\/[^ ]+\/actions\/runs\/\d+\/jobs/.test(call));
const carryDir = () => tempDir("verdict-carry-");
// One sweep of the broker-check breaker trip, reading the carry at `from` and
// keeping it at `to`; `run` changes the lane run's listing.
async function carriedSweep({ from, to, run = {}, logs = CHECK_KILLED }) {
  const fake = stalledRun({ jobs: BROKER_REFUSED, logs });
  const listed = fake.github;
  const actions = async (method, path, ...rest) => {
    const answer = await listed(method, path, ...rest);
    return Array.isArray(answer?.workflow_runs) ? { ...answer, workflow_runs: answer.workflow_runs.map((item) => ({ ...item, ...run })) } : answer;
  };
  assert.equal(await sweep({ github: fake.github, actions }, { ...(from && { VERDICTS_IN: from }), VERDICTS_OUT: to }), 0);
  return fake.calls;
}

test("a sweep keeps a completed run's job listing and its read log's refusal, and the next sweep reads neither again", async () => {
  const dir = carryDir();
  const first = await carriedSweep({ to: join(dir, "1.json") });
  tripped(first);
  assert.equal(jobReads(first).length, 1);
  assert.deepEqual(logReads(first), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`]);
  const kept = JSON.parse(readFileSync(join(dir, "1.json"), "utf8"));
  assert.deepEqual(Object.keys(kept.jobs), ["5030|1"]);
  assert.deepEqual(kept.refusals, { [`${BROKER_CHECK_ID}|check`]: { at: new Date(NOW).toISOString(), value: "kill-switch" } });
  // The second sweep decides the same from the file alone, and keeps it again.
  const second = await carriedSweep({ from: join(dir, "1.json"), to: join(dir, "2.json") });
  tripped(second);
  assert.deepEqual(jobReads(second), []);
  assert.deepEqual(logReads(second), []);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "2.json"), "utf8")), kept);
});

test("a run re-run or updated since the carry was kept has its jobs and log read again", async () => {
  const dir = carryDir();
  await carriedSweep({ to: join(dir, "1.json") });
  for (const run of [{ run_attempt: 2 }, { updated_at: "2026-10-16T10:06:00Z" }]) {
    const calls = await carriedSweep({ from: join(dir, "1.json"), to: join(dir, "2.json"), run });
    tripped(calls);
    assert.equal(jobReads(calls).length, 1, JSON.stringify(run));
  }
  // An unfinished run's listing is never carried.
  const going = await carriedSweep({ to: join(dir, "3.json"), run: { status: "in_progress" } });
  assert.deepEqual(writes(going), []);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "3.json"), "utf8")).jobs, {});
});

test("a corrupt or missing carry, one of other code, or an entry of the wrong shape, reads GitHub as a sweep with none does", async () => {
  const dir = carryDir();
  await carriedSweep({ to: join(dir, "kept.json") });
  const kept = JSON.parse(readFileSync(join(dir, "kept.json"), "utf8"));
  const code = codeDigest();
  assert.equal(kept.code, code);
  const files = {
    garbled: "{not json",
    array: "[]",
    otherCode: JSON.stringify({ ...kept, code: "0".repeat(64) }),
    noCode: JSON.stringify({ jobs: kept.jobs, refusals: kept.refusals }),
    wrongShape: JSON.stringify({
      code,
      jobs: { "5030|1": { at: new Date(NOW).toISOString(), updated_at: "2026-10-16T10:05:00Z", jobs: "none" } },
      refusals: { [`${BROKER_CHECK_ID}|check`]: { at: new Date(NOW).toISOString(), value: "Kill switch!" } },
    }),
    future: JSON.stringify({ code, refusals: { [`${BROKER_CHECK_ID}|check`]: { at: "2026-10-17T00:00:00Z", value: null } } }),
    stale: JSON.stringify({ code, refusals: { [`${BROKER_CHECK_ID}|check`]: { at: "2026-09-01T00:00:00Z", value: null } } }),
  };
  for (const [name, text] of [...Object.entries(files), ["missing", undefined]]) {
    const from = join(dir, `${name}.json`);
    if (text !== undefined) writeFileSync(from, text);
    const calls = await carriedSweep({ from, to: join(dir, `${name}-out.json`) });
    tripped(calls);
    assert.equal(jobReads(calls).length, 1, name);
    assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`], name);
  }
});

test("a log that could not be read is not carried, so the next sweep reads it again", async () => {
  const dir = carryDir();
  await carriedSweep({ to: join(dir, "1.json"), logs: {} });
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "1.json"), "utf8")).refusals, {});
  const calls = await carriedSweep({ from: join(dir, "1.json"), to: join(dir, "2.json") });
  tripped(calls);
  assert.deepEqual(jobReads(calls), []);
  assert.deepEqual(logReads(calls), [`GET /repos/${REPO}/actions/jobs/${BROKER_CHECK_ID}/logs`]);
});

// The sweep's one Work status listing (fieldListing): the deferred pass, the
// readiness pass and the restart pass each ask for their states, and all of
// them are answered from one listing of every state.
test("fieldListing lists every state once a sweep and answers each caller's states from it", async () => {
  const field = { fullDatabaseId: String(STATUS_CONFIG["field-id"]) };
  const states = { 40: "agent-ready", 41: "deferred", 42: "ready" };
  let listings = 0;
  let fail = false;
  const github = async (method, path, body) => {
    assert.ok(method === "POST" && path === "/graphql" && /issues\(states: OPEN/.test(body.query), `unexpected ${method} ${path}`);
    listings += 1;
    if (fail) {
      fail = false;
      throw new Error("POST /graphql failed with status 502");
    }
    const nodes = Object.entries(states).map(([number, state]) => ({
      number: Number(number),
      createdAt: "2026-10-10T00:00:00Z",
      labels: { nodes: [] },
      issueFieldValues: { nodes: [{ name: state, field }] },
      timelineItems: { nodes: [{ __typename: "IssueFieldChangedEvent", newValue: state, actor: { databaseId: OWNER.id }, issueField: field }] },
    }));
    return { data: { repository: { issues: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } };
  };
  const env = { BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED };
  const byStatus = fieldListing(env, github, REPO);
  const numbers = (found) => found.map((item) => item.number);
  assert.deepEqual(numbers(await byStatus(["deferred"])), [41]);
  assert.deepEqual(numbers(await byStatus()), [40, 41, 42]);
  assert.deepEqual(numbers(await byStatus(["agent-ready"])), [40]);
  assert.equal(listings, 1, "three callers, one listing");
  // A failed shared listing hands each caller its own states' listing.
  const retried = fieldListing(env, github, REPO);
  fail = true;
  assert.deepEqual(numbers(await retried(["deferred"])), [41]);
  assert.deepEqual(numbers(await retried(["agent-ready"])), [40]);
  assert.equal(listings, 4, "the failed shared listing, then one per caller");
});

test("fieldListing: an unreadable Work status on an issue in another state never stops the agent-ready listing", async (t) => {
  t.mock.method(console, "log", () => {});
  const field = { fullDatabaseId: String(STATUS_CONFIG["field-id"]) };
  const other = { fullDatabaseId: "999999" };
  const statusEvent = (state) => ({ __typename: "IssueFieldChangedEvent", newValue: state, actor: { databaseId: OWNER.id }, issueField: field });
  // #42 is `ready` with 100 newer events on another field and no Work status
  // event in view, so its setter cannot be read (resolve-config.mjs:264-265).
  const timelines = {
    40: [statusEvent("agent-ready")],
    41: [statusEvent("deferred")],
    42: Array.from({ length: 100 }, () => ({ __typename: "IssueFieldChangedEvent", newValue: "x", actor: { databaseId: OWNER.id }, issueField: other })),
  };
  const states = { 40: "agent-ready", 41: "deferred", 42: "ready" };
  const github = async () => ({
    data: {
      repository: {
        issues: {
          pageInfo: { hasNextPage: false, endCursor: null },
          nodes: Object.entries(states).map(([number, state]) => ({
            number: Number(number),
            createdAt: "2026-10-10T00:00:00Z",
            labels: { nodes: [] },
            issueFieldValues: { nodes: [{ name: state, field }] },
            timelineItems: { nodes: timelines[number] },
          })),
        },
      },
    },
  });
  const env = { BASE_PATH: fileURLToPath(new URL("../../..", import.meta.url)), TRUSTED_ACTORS_PATH: TRUSTED };
  const byStatus = fieldListing(env, github, REPO);
  assert.deepEqual((await byStatus(["agent-ready"])).map((item) => item.number), [40]);
  assert.deepEqual((await byStatus(["deferred"])).map((item) => item.number), [41]);
});

// The restart pass's time budget (SWEEP_BUDGET_MINUTES): a sweep decides no
// further agent-ready issue once the budget has run out, writes what it
// decided, and the next sweep decides the ones it left first.
const BUDGET_NUMBERS = [30, 31, 32, 33, 34, 35, 36, 37, 38, 39];
const limitWorld = (extra = {}) =>
  world({
    ...extra,
    openReady: BUDGET_NUMBERS.map((n) => ready(n)),
    comments: Object.fromEntries(BUDGET_NUMBERS.map((n) => [n, [note(), limitedNote("2026-10-16T01:30:00Z", "2026-10-16T01:00:00Z")]])),
    events: Object.fromEntries(BUDGET_NUMBERS.map((n) => [n, [added("2026-10-16T00:00:00Z")]])),
  });
// The issues whose comments a sweep read, in order: one read per decision.
const decided = (calls) =>
  calls
    .map((call) => /^GET \/repos\/[^/]+\/[^/]+\/issues\/(\d+)\/comments/.exec(call)?.[1])
    .filter(Boolean)
    .map(Number);
// A clock one minute on for each issue whose decision has started.
const minutePerDecision = (fake) => {
  let ticks = 0;
  const github = async (method, path, ...rest) => {
    if (method === "GET" && /\/issues\/\d+\/comments/.test(path)) {
      ticks += 1;
    }
    return fake.github(method, path, ...rest);
  };
  return { github: Object.assign(github, { writer: fake.writer }), clock: () => NOW + ticks * 60_000 };
};

test("a sweep with every agent-ready issue visible decides them all inside its budget and re-fires up to its cap", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const fake = limitWorld();
  assert.equal(await sweep({ github: fake.github }, { ...withLimits({ "restarts-per-run": 4 }), SWEEP_BUDGET_MINUTES: "6" }), 0);
  assert.deepEqual(decided(fake.calls), BUDGET_NUMBERS);
  assert.deepEqual(writes(fake.calls), [30, 31, 32, 33].flatMap(restarted));
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.equal(lines.filter((line) => line.includes("restart deferred: 4 restarts this run")).length, 6);
  assert.ok(!lines.some((line) => line.includes("time budget ran out")), lines.join("\n"));
});

test("past its budget a sweep decides no further issue, writes the ones it decided, and names how many it left", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const fake = limitWorld();
  const { github, clock } = minutePerDecision(fake);
  // Six minutes at a minute a decision: the decisions started at minutes 0 to 5.
  assert.equal(await sweep({ github, clock }, { ...withLimits({ "restarts-per-run": 10 }), SWEEP_BUDGET_MINUTES: "6" }), 0);
  assert.deepEqual(decided(fake.calls), [30, 31, 32, 33, 34, 35]);
  assert.deepEqual(writes(fake.calls), [30, 31, 32, 33, 34, 35].flatMap(restarted));
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("::notice title=label-unblocked::the sweep's time budget ran out: 4 of 10 agent-ready issue(s) left for the next sweep, which decides them first"), lines.join("\n"));
  // With no budget named, SWEEP_BUDGET_MIN's 6 minutes apply.
  const unnamed = limitWorld();
  const ticking = minutePerDecision(unnamed);
  assert.equal(await sweep({ github: ticking.github, clock: ticking.clock }, withLimits({ "restarts-per-run": 10 })), 0);
  assert.deepEqual(decided(unnamed.calls), [30, 31, 32, 33, 34, 35]);
});

test("the next sweep decides the issues the last one's budget left first, so none waits behind the rest", async (t) => {
  t.mock.method(console, "log", () => {});
  const dir = tempDir("verdict-carry-budget-");
  const first = limitWorld();
  const one = minutePerDecision(first);
  assert.equal(await sweep({ github: one.github, clock: one.clock }, { SWEEP_BUDGET_MINUTES: "6", VERDICTS_OUT: join(dir, "1.json") }), 0);
  assert.deepEqual(decided(first.calls), [30, 31, 32, 33, 34, 35]);
  const second = limitWorld();
  const two = minutePerDecision(second);
  assert.equal(await sweep({ github: two.github, clock: two.clock }, { SWEEP_BUDGET_MINUTES: "6", VERDICTS_IN: join(dir, "1.json"), VERDICTS_OUT: join(dir, "2.json") }), 0);
  // The four never decided first, then the least recently decided, by listing order.
  assert.deepEqual(decided(second.calls), [36, 37, 38, 39, 30, 31]);
});

test("a sweep reads each agent-ready issue's field events once, for its holds, its history and its field restarts", async (t) => {
  t.mock.method(console, "log", () => {});
  const { fieldEvents } = await import("../../actions/resolve-config/resolve-config.mjs");
  const fake = withFieldHistory(limitWorld({ fieldValues: Object.fromEntries(BUDGET_NUMBERS.map((n) => [n, [workRow("agent-ready")]])) }), Object.fromEntries(BUDGET_NUMBERS.map((n) => [n, [fieldEvent(GRAPH_OWNER, "agent-ready", "ready", "2026-10-16T00:00:00Z")]])));
  const reads = [];
  const github = Object.assign(
    async (method, path, body, ...rest) => {
      if (method === "POST" && path === "/graphql" && /IssueFieldAddedEvent/.test(body?.query ?? "")) {
        reads.push(body.variables.number);
      }
      return fake.github(method, path, body, ...rest);
    },
    { writer: fake.writer },
  );
  const statusOf = statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors: JSON.parse(readFileSync(TRUSTED, "utf8")), log: () => {} });
  const statusField = { field: STATUS_CONFIG["field-id"], fieldRows: (n) => fieldEvents(github, REPO, n) };
  assert.equal(await sweep({ github, statusOf, statusField }, withLimits({ "restarts-per-run": 10 })), 0);
  assert.deepEqual(decided(fake.calls), BUDGET_NUMBERS);
  assert.deepEqual(reads, BUDGET_NUMBERS, "one field-events read per issue");
});

// A wait carried between sweeps (verdict-carry.mjs `decided` wait): an issue
// unchanged since a sweep decided it waits until a known time is not read
// again before that time; a changed or due issue, or new lane workflow files,
// are read fresh, and a carried wait never restarts or writes anything.
const UPDATED = "2026-10-16T05:00:00Z";
// #30 and #31 stopped on the limit at 06:00, resetting at `resets` (13:00, an
// hour after NOW, by default), both last updated at `updated`.
const waitWorld = ({ updated = {}, resets = "2026-10-16T13:00:00Z", blobs = BLOBS } = {}) =>
  world({
    openReady: [30, 31].map((n) => ({ ...ready(n), updated_at: updated[n] ?? UPDATED })),
    comments: { 30: [note(), limitedNote(resets, "2026-10-16T06:00:00Z")], 31: [note(), limitedNote(resets, "2026-10-16T06:00:00Z")] },
    events: { 30: [added("2026-10-16T05:00:00Z")], 31: [added("2026-10-16T05:00:00Z")] },
    blobs,
  });
const issueReads = (calls) => calls.filter((call) => /^GET \/repos\/[^/]+\/[^/]+\/issues\/\d+\/(comments|events|timeline)/.test(call));
async function waitSweeps(second, { now = NOW, from } = {}) {
  const dir = tempDir("verdict-carry-wait-");
  if (from) {
    writeFileSync(join(dir, "1.json"), JSON.stringify(from));
  } else {
    const first = waitWorld();
    assert.equal(await sweep({ github: first.github }, { VERDICTS_OUT: join(dir, "1.json") }), 0);
    assert.deepEqual(decided(first.calls), [30, 31]);
    assert.deepEqual(writes(first.calls), []);
  }
  assert.equal(await sweep({ github: second.github, now }, { VERDICTS_IN: join(dir, "1.json"), VERDICTS_OUT: join(dir, "2.json") }), 0);
  return JSON.parse(readFileSync(join(dir, "2.json"), "utf8"));
}

test("an issue unchanged since a sweep decided its wait is not read again before the wait ends", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const second = waitWorld();
  const kept = await waitSweeps(second);
  assert.deepEqual(issueReads(second.calls), []);
  assert.deepEqual(writes(second.calls), []);
  const lines = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(lines.includes("label-unblocked: #30 not restarted: waiting for the limit to reset at 2026-10-16T13:00:00.000Z (carried: unchanged since it was decided)"), lines.join("\n"));
  assert.ok(lines.includes("::notice title=label-unblocked::0 agent-ready issue(s) to decide, 2 carried waiting from an earlier sweep"), lines.join("\n"));
  // The wait is kept again for the sweep after.
  assert.deepEqual(kept.decided[30].wait, { reason: "waiting for the limit to reset at 2026-10-16T13:00:00.000Z", due: Date.parse("2026-10-16T13:00:00Z"), updated: UPDATED, key: KEY });
});

test("a changed issue, a wait that ended, or new lane workflow files are read and decided fresh", async (t) => {
  t.mock.method(console, "log", () => {});
  const changed = waitWorld({ updated: { 30: "2026-10-16T11:00:00Z" } });
  await waitSweeps(changed);
  assert.deepEqual(decided(changed.calls), [30], "only the changed issue is read");
  // At 13:30 the limit has reset: both are read, and restarted.
  const due = waitWorld();
  await waitSweeps(due, { now: Date.parse("2026-10-16T13:30:00Z") });
  assert.deepEqual(decided(due.calls), [30, 31]);
  assert.deepEqual(writes(due.calls), [30, 31].flatMap(restarted));
  const deployed = waitWorld({ blobs: { ...BLOBS, ".github/workflows/work-resolve-issue.yml": "3".repeat(40) } });
  await waitSweeps(deployed);
  assert.deepEqual(decided(deployed.calls), [30, 31], "a new workflow key reads both");
});

test("a carried wait only holds: a malformed or overlong one is read fresh, and one that holds an issue due a restart writes nothing", async (t) => {
  t.mock.method(console, "log", () => {});
  const at = new Date(NOW - 60_000).toISOString();
  const wait = { reason: "waiting for the limit to reset at 2026-10-16T13:00:00.000Z", due: Date.parse("2026-10-16T13:00:00Z"), updated: UPDATED, key: KEY };
  const file = (decided) => ({ code: codeDigest(), jobs: {}, refusals: {}, decided });
  // An empty reason and a wait past WAIT_MAX_HOURS carry nothing.
  const forged = waitWorld();
  await waitSweeps(forged, { from: file({ 30: { at, wait: { ...wait, reason: "" } }, 31: { at, wait: { ...wait, due: NOW + 25 * 3_600_000 } } }) });
  assert.deepEqual(decided(forged.calls), [30, 31]);
  // A well-formed wait on issues whose limit already reset holds them this
  // sweep: neither is read or restarted.
  const reset = waitWorld({ resets: "2026-10-16T11:00:00Z" });
  await waitSweeps(reset, { from: file({ 30: { at, wait }, 31: { at, wait } }) });
  assert.deepEqual(issueReads(reset.calls), []);
  assert.deepEqual(writes(reset.calls), []);
  // Without the carry, the same issues restart.
  const fresh = waitWorld({ resets: "2026-10-16T11:00:00Z" });
  assert.equal(await sweep({ github: fresh.github }), 0);
  assert.deepEqual(writes(fresh.calls), [30, 31].flatMap(restarted));
});
