// issuesByStatus over the live models.issue-status: open issues listed by
// their trusted Work status, with a field no counted account set leaving the
// labels to decide.
import assert from "node:assert/strict";
import { test } from "node:test";

import { HUMAN_ID, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "./read-status.fixtures.mjs";
import { issuesByStatus, MAX_ISSUE_PAGES, MAX_STATUS_REREADS } from "./resolve-config.mjs";

const FIELD = String(STATUS_CONFIG["field-id"]);

// One issue node: `value` the Work status option name, set by `setter`.
function issue(number, { labels = [], value, setter = HUMAN_ID } = {}) {
  const created = `2026-11-0${number % 9}T00:00:00Z`;
  return {
    number,
    createdAt: created,
    labels: { nodes: labels.map((name) => ({ name })) },
    issueFieldValues: { nodes: value === undefined ? [] : [{ name: value, field: { fullDatabaseId: FIELD } }] },
    timelineItems: {
      nodes:
        value === undefined
          ? []
          : [{ __typename: "IssueFieldAddedEvent", createdAt: created, value, actor: { __typename: "User", login: "someone", databaseId: setter }, issueField: { fullDatabaseId: FIELD } }],
    },
  };
}

// `github` answering each page in turn; the last page has no next.
function pages(...nodes) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, variables: body?.variables, query: body?.query });
    const page = calls.length - 1;
    return { data: { repository: { issues: { pageInfo: { hasNextPage: page < nodes.length - 1, endCursor: `c${page + 1}` }, nodes: nodes[page] } } } };
  };
  return { github, calls };
}
const list = (github, states, options = {}) => issuesByStatus(github, "o/r", states, { config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, ...options });
const numbers = (found) => found.map(({ number, state }) => `${number} ${state}`);

test("issuesByStatus reads every page, passing the cursor and since on", async () => {
  const { github, calls } = pages([issue(1, { value: "deferred" }), issue(2, { value: "ready" })], [issue(3, { value: "deferred", labels: ["bug"] })]);
  const found = await list(github, ["deferred"], { since: "2026-11-01T00:00:00Z" });
  assert.deepEqual(found, [
    { number: 1, created_at: "2026-11-01T00:00:00Z", labels: [], state: "deferred" },
    { number: 3, created_at: "2026-11-03T00:00:00Z", labels: ["bug"], state: "deferred" },
  ]);
  assert.deepEqual(
    calls.map(({ method, path, variables }) => [method, path, variables]),
    [
      ["POST", "/graphql", { owner: "o", name: "r", cursor: null, since: "2026-11-01T00:00:00Z" }],
      ["POST", "/graphql", { owner: "o", name: "r", cursor: "c1", since: "2026-11-01T00:00:00Z" }],
    ],
  );
  assert.match(calls[0].query, /issues\(states: OPEN, first: \d+, after: \$cursor, filterBy: \{ since: \$since \}\)/);
});

// Pages of 50 and 100 answered stale nested field events; pages of 25 and 30
// did not.
const STALE_FREE_PAGE = 30;
// The open issues a listing must reach: 210 were open when the page size was
// measured, so this leaves room to more than double.
const OPEN_ISSUES_FLOOR = 500;

test("a listing page holds at most the measured stale-free size, and the page cap still reaches every open issue", async () => {
  let calls = 0;
  let size;
  const endless = async (method, path, body) => {
    calls += 1;
    size = Number(/issues\(states: OPEN, first: (\d+),/.exec(body.query)[1]);
    return { data: { repository: { issues: { pageInfo: { hasNextPage: true, endCursor: `c${calls}` }, nodes: [] } } } };
  };
  await assert.rejects(() => list(endless, ["deferred"]), /run past \d+ pages/);
  assert.ok(size <= STALE_FREE_PAGE, `a page of ${size} issues is larger than ${STALE_FREE_PAGE}, where GitHub answered stale field events`);
  assert.ok(size * calls >= OPEN_ISSUES_FLOOR, `${calls} pages of ${size} reach ${size * calls} issues, fewer than ${OPEN_ISSUES_FLOOR}`);
});

test("a field an untrusted account set reads as unset, so the issue's labels decide", async () => {
  const nodes = [issue(4, { value: "deferred", setter: STRANGER_ID, labels: ["status: ready"] }), issue(5, { value: "ready", setter: STRANGER_ID, labels: ["admission-deferred"] })];
  assert.deepEqual(numbers(await list(pages(nodes).github, ["deferred"])), ["5 null"]);
  assert.deepEqual(numbers(await list(pages(nodes).github, ["ready"])), ["4 null"]);
});

test("a legacy issue whose labels name the state is listed once beside the field's, and a trusted field outranks a stale label", async () => {
  const nodes = [
    issue(6, { value: "deferred", labels: ["admission-deferred"] }),
    issue(7, { labels: ["Admission-Deferred"] }),
    issue(8, { value: "ready", labels: ["admission-deferred"] }),
    issue(9, { labels: ["needs-human"] }),
  ];
  assert.deepEqual(numbers(await list(pages(nodes).github, ["deferred", "needs-human"])), ["6 deferred", "7 null", "9 null"]);
});

test("an untrusted change after a person's hold leaves the issue listed as held", async () => {
  const held = issue(11, { value: "needs-human" });
  held.issueFieldValues.nodes[0].name = "ready";
  held.timelineItems.nodes.push({ __typename: "IssueFieldChangedEvent", createdAt: "2026-11-09T00:00:00Z", previousValue: "needs-human", newValue: "ready", actor: { __typename: "User", login: "stranger", databaseId: STRANGER_ID }, issueField: { fullDatabaseId: FIELD } });
  assert.deepEqual(numbers(await list(pages([held]).github, ["needs-human"])), ["11 needs-human"]);
  assert.deepEqual(numbers(await list(pages([held]).github, ["ready"])), []);
});

test("a listing past the page cap throws rather than stopping short", async () => {
  let calls = 0;
  const endless = async () => {
    calls += 1;
    return { data: { repository: { issues: { pageInfo: { hasNextPage: true, endCursor: `c${calls}` }, nodes: [issue(1, { value: "deferred" })] } } } };
  };
  await assert.rejects(() => list(endless, ["deferred"]), new RegExp(`run past ${MAX_ISSUE_PAGES} pages`));
  assert.equal(calls, MAX_ISSUE_PAGES);
});

// Other fields' events, newest last, as GraphQL's `last:` window keeps them.
const sizeEvents = (count) =>
  Array.from({ length: count }, () => ({ __typename: "IssueFieldChangedEvent", createdAt: "2026-11-09T00:00:00Z", newValue: "Small", actor: { __typename: "User", login: "someone", databaseId: HUMAN_ID }, issueField: { fullDatabaseId: "15462270" } }));

test("the listing reads each issue's newest 100 field events, so a Work status setter behind 99 other events still counts", async () => {
  const held = issue(10, { value: "needs-human" });
  held.timelineItems.nodes.push(...sizeEvents(99));
  const { github, calls } = pages([held]);
  assert.deepEqual(numbers(await list(github, ["needs-human"])), ["10 needs-human"]);
  assert.match(calls[0].query, /timelineItems\(last: 100, /);
});

test("a Work status value whose setter is not among a full window of field events throws rather than read as unset", async () => {
  const lost = issue(11, { value: "needs-human" });
  lost.timelineItems.nodes = sizeEvents(100);
  await assert.rejects(() => list(pages([lost]).github, ["needs-human"]), /#11's Work status setter is older than its newest 100 field events/);
  const unset = issue(12, { labels: ["needs-human"] });
  unset.timelineItems.nodes = sizeEvents(100);
  assert.deepEqual(numbers(await list(pages([unset]).github, ["needs-human"])), ["12 null"], "with no Work status value there is no setter to lose");
});

test("a GraphQL error, a malformed answer, or a counted option name the config does not map throws", async () => {
  await assert.rejects(() => list(async () => ({ errors: [{ message: "nope" }] }), ["deferred"]), /open issues could not be read: nope/);
  await assert.rejects(() => list(async () => ({ data: { repository: { issues: null } } }), ["deferred"]), /holds no issue list/);
  await assert.rejects(
    () => list(pages([issue(1, { value: "parked", labels: ["admission-deferred"] })]).github, ["deferred"]),
    (error) => error.code === "unmapped-status" && error.message.includes("parked"),
  );
});

test("an unreadable issue that could not be one of the states is skipped, so the others still list", async () => {
  const lost = issue(13, { value: "needs-human" });
  lost.timelineItems.nodes = sizeEvents(100);
  const nodes = [issue(12, { value: "parked" }), lost, issue(14, { value: "deferred" })];
  assert.deepEqual(numbers(await list(pages(nodes).github, ["deferred"])), ["14 deferred"]);
  await assert.rejects(() => list(pages(nodes).github, ["needs-human"]), /#13's Work status setter is older than its newest 100 field events/);
});

// An issue the listing shows at `ready` whose newest listed event is an older
// `needs-triage`: the listing's events lag the value.
const stale = (number) => {
  const node = issue(number, { value: "ready" });
  node.timelineItems.nodes[0].value = "needs-triage";
  return node;
};
// `github` answering the listing from `nodes` and each issue's own read from
// `fields` (withFields), counting the per-issue value reads and the waits.
function rereading(nodes, fields) {
  const counts = { values: 0, sleeps: [] };
  const answer = withFields(pages(nodes).github, fields);
  const github = async (method, path, ...rest) => {
    if (path.endsWith("/issue-field-values")) {
      counts.values += 1;
    }
    return answer(method, path, ...rest);
  };
  const sleep = async (ms) => {
    counts.sleeps.push(ms);
  };
  return { github, sleep, counts };
}

test("an issue whose listed event lags its value is read again alone, and that read lists it", async () => {
  const { github, sleep, counts } = rereading([stale(20), issue(21, { value: "ready" })], { 20: { state: "ready" } });
  assert.deepEqual(numbers(await list(github, ["ready"], { sleep })), ["20 ready", "21 ready"]);
  assert.equal(counts.values, 1);
  assert.deepEqual(counts.sleeps, []);
});

// Runs `body` with console.log captured, returning what it printed.
async function logged(body) {
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(String(line));
  try {
    return { result: await body(), lines };
  } finally {
    console.log = original;
  }
}

test("an issue whose own read still disagrees is left out, named in held and a notice, and the others still list", async () => {
  const { github, sleep, counts } = rereading([stale(22), issue(23, { value: "ready" })], { 22: { state: "ready", named: "needs-triage" } });
  const { result: found, lines } = await logged(() => list(github, ["ready"], { sleep }));
  assert.deepEqual(numbers(found), ["23 ready"]);
  assert.deepEqual(
    found.held.map(({ number, created_at }) => [number, created_at]),
    [[22, "2026-11-04T00:00:00Z"]],
  );
  assert.match(found.held[0].reason, /newest field event/);
  assert.equal(Object.keys(found).includes("held"), false, "held is not enumerable, so a caller that ignores it is unchanged");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^::notice title=issuesByStatus::#22 is left out of this listing: /);
  assert.equal(counts.values, 2, "the own read waits once and reads again before the issue is left out");
  assert.equal(counts.sleeps.length, 1);
});

test("a re-read that fails with anything but a disagreement still throws", async () => {
  const { github, sleep } = rereading([stale(24), issue(25, { value: "ready" })], { 24: new Error("HTTP 500") });
  await assert.rejects(() => list(github, ["ready"], { sleep }), /HTTP 500/);
});

test("past the re-read cap, further disagreeing issues are left out with no more reads", async () => {
  const disagreeing = Array.from({ length: MAX_STATUS_REREADS + 2 }, (_, i) => 30 + i);
  const fields = Object.fromEntries(disagreeing.map((number) => [number, { state: "ready" }]));
  const { github, sleep, counts } = rereading(disagreeing.map(stale), fields);
  const { result: found, lines } = await logged(() => list(github, ["ready"], { sleep }));
  assert.deepEqual(
    found.map(({ number }) => number),
    disagreeing.slice(0, MAX_STATUS_REREADS),
  );
  assert.deepEqual(
    found.held.map(({ number }) => number),
    disagreeing.slice(MAX_STATUS_REREADS),
  );
  assert.equal(lines.length, 2);
  assert.equal(counts.values, MAX_STATUS_REREADS);
});

// An issue the listing shows at `value` with none of its Work status events.
const eventless = (number, value) => {
  const node = issue(number, { value });
  node.timelineItems.nodes = [];
  return node;
};

test("an unlabeled issue listed at a wanted state with no Work status event is read again alone, and that read lists it", async () => {
  const { github, sleep, counts } = rereading([eventless(40, "agent-ready"), issue(41, { value: "agent-ready" })], { 40: { state: "agent-ready" } });
  assert.deepEqual(numbers(await list(github, ["agent-ready"], { sleep })), ["40 agent-ready", "41 agent-ready"]);
  assert.equal(counts.values, 1, "only the issue with no listed event is read again");
});

test("an issue listed at an unwanted state with no Work status event is not read again", async () => {
  const { github, sleep, counts } = rereading([eventless(42, "deferred"), issue(43, { value: "agent-ready" })], { 42: { state: "deferred" } });
  assert.deepEqual(numbers(await list(github, ["agent-ready"], { sleep })), ["43 agent-ready"]);
  assert.equal(counts.values, 0);
});

test("past the re-read cap, an issue listed at a wanted state with no Work status event is named in held and a notice", async () => {
  const disagreeing = Array.from({ length: MAX_STATUS_REREADS }, (_, i) => 50 + i);
  const fields = Object.fromEntries(disagreeing.map((number) => [number, { state: "ready" }]));
  const { github, sleep, counts } = rereading([...disagreeing.map(stale), eventless(60, "ready")], fields);
  const { result: found, lines } = await logged(() => list(github, ["ready"], { sleep }));
  assert.deepEqual(found.held.map(({ number }) => number), [60]);
  assert.match(found.held[0].reason, /holds `ready`, but the listing shows no Work status event/);
  assert.deepEqual(lines, [`::notice title=issuesByStatus::#60 is left out of this listing: ${found.held[0].reason}`]);
  assert.equal(counts.values, MAX_STATUS_REREADS);
});

test("a listing that holds no issue still carries an empty held", async () => {
  const found = await list(pages([issue(26, { value: "ready" })]).github, ["ready"]);
  assert.deepEqual(found.held, []);
});
