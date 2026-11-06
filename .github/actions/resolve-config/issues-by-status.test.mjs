// issuesByStatus over the live models.issue-status: open issues listed by
// their trusted Work status, with a field no counted account set leaving the
// labels to decide.
import assert from "node:assert/strict";
import { test } from "node:test";

import { HUMAN_ID, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS } from "./read-status.fixtures.mjs";
import { issuesByStatus, MAX_ISSUE_PAGES } from "./resolve-config.mjs";

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
  assert.match(calls[0].query, /issues\(states: OPEN, first: 100, after: \$cursor, filterBy: \{ since: \$since \}\)/);
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

test("a listing past the page cap throws rather than stopping short", async () => {
  let calls = 0;
  const endless = async () => {
    calls += 1;
    return { data: { repository: { issues: { pageInfo: { hasNextPage: true, endCursor: `c${calls}` }, nodes: [issue(1, { value: "deferred" })] } } } };
  };
  await assert.rejects(() => list(endless, ["deferred"]), /run past 20 pages/);
  assert.equal(calls, MAX_ISSUE_PAGES);
});

test("a GraphQL error, a malformed answer, or a counted option name the config does not map throws", async () => {
  await assert.rejects(() => list(async () => ({ errors: [{ message: "nope" }] }), ["deferred"]), /open issues could not be read: nope/);
  await assert.rejects(() => list(async () => ({ data: { repository: { issues: null } } }), ["deferred"]), /holds no issue list/);
  await assert.rejects(
    () => list(pages([issue(1, { value: "parked" })]).github, ["deferred"]),
    (error) => error.code === "unmapped-status" && error.message.includes("parked"),
  );
});
