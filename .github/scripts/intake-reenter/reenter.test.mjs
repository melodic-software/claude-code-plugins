// Expected values come from the requested behavior for answered issues: a
// listed human's `**Decision recorded.**` first line on a
// `status: needs-decision` issue, or the author's or a listed human's reply
// on a `status: needs-info` issue, removes that status label and adds
// `needs-triage`; it dispatches intake-triage.yml once with the issue number
// only when the issue's author is one intake admits on open (a listed human
// or the lanes App). A decision on an issue that carries `needs-human`
// changes nothing, and a listed human's removal of `needs-human` re-enters an
// issue at `status: needs-decision` (owner decision on #10735). A decision on
// a `status: confirmed` issue whose only status that is, with no
// `agent-ready`, re-enters it whether admission parked it or a person
// confirmed it (requested behavior: a person's confirmation followed by that
// person's decision must reach triage). Anything else
// changes nothing, and `agent-ready` is never added.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./reenter.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { mirroredStatusOf, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../../actions/resolve-config/read-status.fixtures.mjs";
import { statusReader } from "../../actions/resolve-config/read-status.mjs";

const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton", type: "User" };
const STRANGER = { id: 5005, login: "someone", type: "User" };
const AUTHOR = { id: 6006, login: "reporter", type: "User" };
const LISTED_BOT = { id: 209825114, login: "claude[bot]", type: "Bot" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]", type: "Bot" };
const ACTIONS_BOT = { id: 41898282, login: "github-actions", type: "Bot" };
const NUMBER = 42;
// The Work status option ids (docs/conventions/pr-pipeline.yaml models.issue-status).
const OPTION = { "needs-triage": 84879216, "needs-human": 86380005, ready: 86380003 };
// One GraphQL Work status field event, as the API answers it.
const fieldNode = (type, actor, values = {}, field = "48484079") => ({
  __typename: type,
  createdAt: "2026-11-06T00:00:00Z",
  actor: { __typename: actor.type, login: actor.login, databaseId: actor.id },
  issueField: { fullDatabaseId: field },
  ...values,
});
const DECISION = "**Decision recorded.**\n\nOption 1.";

const dir = tempDir("intake-reenter-");
const TRUSTED = join(dir, "trusted-actors.json");
writeFileSync(
  TRUSTED,
  JSON.stringify({
    version: 1,
    actors: [
      { id: OWNER.id, login: OWNER.login, kind: "human" },
      { id: LISTED_BOT.id, login: LISTED_BOT.login, kind: "bot" },
      { id: LANES_APP.id, login: LANES_APP.login, kind: "bot" },
    ],
  }),
);

// One issue with its comments. `editors` maps a comment id to its last
// editor's id; `author` opened the issue; `gone` names labels GitHub answers 404 for on removal (a run
// that already took them); `fail` names one `METHOD path` write that answers 500 once.
function world({ labels, author = OWNER, state = "open", pullRequest = false, comments = [], events = [], fieldNodes = [], editors = {}, gone = [], fail = null }) {
  let failing = fail;
  const current = new Set(labels);
  const writes = [];
  const base = `/repos/${REPO}/issues/${NUMBER}`;
  const issue = () => ({
    number: NUMBER,
    state,
    user: author,
    labels: [...current].map((name) => ({ name })),
    ...(pullRequest ? { pull_request: { url: "x" } } : {}),
  });
  const shaped = comments.map((c) => ({
    performed_via_github_app: null,
    node_id: `IC_${c.id}`,
    issue_url: `https://api.github.com${base}`,
    ...c,
  }));
  async function github(method, path, body) {
    if (method === "GET" && path === base) return issue();
    const one = /^\/repos\/[^/]+\/[^/]+\/issues\/comments\/([0-9]+)$/.exec(path);
    if (method === "GET" && one) return shaped.find((c) => String(c.id) === one[1]);
    if (method === "GET" && path.startsWith(`${base}/events?`)) return path.endsWith("page=1") ? events : [];
    if (method === "GET" && path.startsWith(`${base}/comments?`)) return path.endsWith("page=1") ? shaped : [];
    if (method === "POST" && path === "/graphql" && body.query.includes("timelineItems")) {
      return { data: { repository: { issue: { timelineItems: { nodes: fieldNodes } } } } };
    }
    if (method === "POST" && path === "/graphql") {
      return {
        data: {
          nodes: body.variables.ids.map((id) => {
            const editor = editors[Number(id.slice(3))];
            return { id, lastEditedAt: editor ? "2026-10-19T00:00:00Z" : null, editor: editor ? { databaseId: editor } : null };
          }),
        },
      };
    }
    writes.push([method, path, body]);
    if (failing === `${method} ${path}`) {
      failing = null;
      throw new GitHubError(500, `${method} ${path}`);
    }
    const label = path.startsWith(`${base}/labels/`) ? decodeURIComponent(path.slice(`${base}/labels/`.length)) : null;
    if (method === "DELETE" && label !== null) {
      if (gone.includes(label) || !current.delete(label)) throw new GitHubError(404, `DELETE ${path}`);
      return [];
    }
    if (method === "POST" && path === `${base}/labels`) {
      for (const name of body.labels) current.add(name);
      return [];
    }
    if (method === "POST" && path === `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`) return null;
    if (method === "POST" && path === `${base}/issue-field-values`) {
      const value = body.issue_field_values[0].value;
      fieldNodes.push(fieldNode("IssueFieldAddedEvent", ACTIONS_BOT, { value }));
      return [{ issue_field_id: 48484079, single_select_option: { id: OPTION[value] } }];
    }
    throw new Error(`unexpected ${method} ${path}`);
  }
  const dispatches = () => writes.filter(([, path]) => path.endsWith("/dispatches"));
  return { github, writes, dispatches, labels: () => [...current].sort() };
}

const run = (w, commentId, env = {}) =>
  main({
    github: w.github,
    log: () => {},
    env: {
      KILL_SWITCH: "proceed",
      GITHUB_REPOSITORY: REPO,
      ISSUE_NUMBER: String(NUMBER),
      COMMENT_ID: String(commentId),
      TRUSTED_ACTORS_PATH: TRUSTED,
      LANES_APP_ID: String(LANES_APP.id),
      ...env,
    },
  });

const expectDispatched = (w) => {
  assert.deepEqual(w.dispatches(), [
    ["POST", `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`, { ref: "main", inputs: { "issue-number": "42" } }],
  ]);
};

test("a listed human's decision on a needs-decision issue sends it back to triage", async () => {
  const w = world({
    labels: ["status: needs-decision", "priority: medium"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
});

const PARKED = { id: 9, user: LANES_APP, body: "<!-- intake-triage admission -->\nNot admitted to the issue lane: no trusted-human acceptance criteria." };

test("a decision on an issue that carries needs-human keeps it and changes nothing", async () => {
  for (const labels of [["needs-human", "status: needs-decision"], ["needs-human", "status: confirmed"]]) {
    const w = world({ labels, comments: [PARKED, { id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await run(w, 1), 0);
    assert.deepEqual(w.labels(), labels, labels.join());
    assert.deepEqual(w.writes, [], labels.join());
  }
});

test("a listed human's decision on an issue admission parked at status: confirmed sends it back to triage", async () => {
  const w = world({
    labels: ["status: confirmed", "priority: medium"],
    comments: [PARKED, { id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
});

test("a listed human's decision on a status: confirmed issue admission never saw sends it back to triage", async () => {
  const w = world({
    labels: ["status: confirmed", "priority: medium"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
});

test("a decision on an outside author's hand-confirmed issue moves it to needs-triage without a model run", async () => {
  const w = world({ labels: ["status: confirmed"], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 0);
});

test("a hand-confirmed issue stays put for a stranger's decision, needs-human, or a second status label", async () => {
  for (const [name, labels, user] of [
    ["stranger", ["status: confirmed"], STRANGER],
    ["needs-human", ["needs-human", "status: confirmed"], OWNER],
    ["needs-info", ["status: confirmed", "status: needs-info"], OWNER],
  ]) {
    const w = world({ labels, comments: [{ id: 1, user, body: DECISION }] });
    assert.equal(await run(w, 1), 0);
    // With needs-info also on, the reply answers needs-info instead; the
    // confirmed path leaves status: confirmed on either way.
    assert.ok(w.labels().includes("status: confirmed"), name);
    if (name !== "needs-info") {
      assert.deepEqual([...w.labels()].sort(), [...labels].sort(), name);
      assert.equal(w.dispatches().length, 0, name);
    }
  }
});

test("a decision on a status: confirmed issue that is admitted or ready changes nothing", async () => {
  for (const labels of [["status: confirmed", "agent-ready"], ["status: confirmed", "status: ready"]]) {
    const w = world({ labels, comments: [PARKED, { id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await run(w, 1), 0);
    assert.deepEqual([...w.labels()].sort(), [...labels].sort(), labels.join());
    assert.equal(w.dispatches().length, 0, labels.join());
  }
});

test("a plain comment on a status: confirmed issue changes nothing", async () => {
  const w = world({
    labels: ["status: confirmed"],
    comments: [{ id: 1, user: OWNER, body: "Looking at this." }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["status: confirmed"]);
  assert.equal(w.dispatches().length, 0);
});

test("the outside author's reply on a needs-info issue moves it to needs-triage without a model run", async () => {
  const w = world({
    labels: ["status: needs-info", "needs-human"],
    author: AUTHOR,
    comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-human", "needs-triage"]);
  assert.equal(w.dispatches().length, 0);
});

test("a decision on an outside author's issue moves it to needs-triage without a model run", async () => {
  const w = world({ labels: ["status: needs-decision"], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 0);
});

test("a decision on a lanes App issue sends it back to triage", async () => {
  const w = world({ labels: ["status: needs-decision"], author: LANES_APP, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  expectDispatched(w);
});

test("a listed human's reply on a needs-info issue sends it back to triage", async () => {
  const w = world({ labels: ["status: needs-info"], comments: [{ id: 1, user: OWNER, body: "It is the Windows host." }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  expectDispatched(w);
});

const quiet = [
  ["a bot comment, even from the issue's author", { labels: ["status: needs-info"], author: LISTED_BOT, comments: [{ id: 1, user: LISTED_BOT, body: DECISION }] }],
  ["the lanes App's comment on its own issue", { labels: ["status: needs-info"], author: LANES_APP, comments: [{ id: 1, user: LANES_APP, body: "Reply." }] }],
  [
    "an App-posted comment",
    { labels: ["status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION, performed_via_github_app: { slug: "x" } }] },
  ],
  [
    "a decision last edited by a non-human",
    { labels: ["status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }], editors: { 1: LISTED_BOT.id } },
  ],
  [
    "the marker on a line other than the first",
    { labels: ["status: needs-decision"], comments: [{ id: 1, user: OWNER, body: "Thinking.\n**Decision recorded.**" }] },
  ],
  ["an unlisted person's decision", { labels: ["status: needs-decision"], comments: [{ id: 1, user: STRANGER, body: DECISION }] }],
  ["an issue without the status label", { labels: ["needs-human"], comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a closed issue", { labels: ["status: needs-decision"], state: "closed", comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a pull request", { labels: ["status: needs-decision"], pullRequest: true, comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a stranger's reply on a needs-info issue", { labels: ["status: needs-info"], author: AUTHOR, comments: [{ id: 1, user: STRANGER, body: "Me too." }] }],
];

for (const [name, setup] of quiet) {
  test(`changes nothing for ${name}`, async () => {
    const w = world(setup);
    assert.equal(await run(w, 1), 0);
    assert.deepEqual(w.writes, []);
  });
}

test("a second decision after the first dispatches nothing more", async () => {
  const w = world({
    labels: ["status: needs-decision"],
    comments: [
      { id: 1, user: OWNER, body: DECISION },
      { id: 2, user: OWNER, body: "**Decision recorded.** Also option 2." },
    ],
  });
  assert.equal(await run(w, 1), 0);
  assert.equal(await run(w, 2), 0);
  assert.equal(w.dispatches().length, 1);
});

test("a run that loses the status label to another run dispatches nothing", async () => {
  const w = world({
    labels: ["status: needs-decision", "needs-triage"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
    gone: ["status: needs-decision"],
  });
  assert.equal(await run(w, 1), 0);
  assert.equal(w.dispatches().length, 0);
  assert.deepEqual(
    w.writes.map(([method]) => method),
    ["DELETE"],
  );
});

// The Work status field a trusted account set (read-status.mjs): with a status
// label on the issue it only adds a hold; with none it decides; unset, the labels decide.
const fieldEnv = { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), COMMENT_ID: "1", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id) };
const runWithField = (w, fields) => {
  const github = withFields(w.github, fields);
  return main({
    github,
    log: () => {},
    statusOf: statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }),
    env: { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), COMMENT_ID: "1", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id) },
  });
};

test("a field that mirrors the labels changes no answer", async () => {
  const scenarios = [
    { labels: ["status: needs-decision", "priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["needs-human", "status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed", "agent-ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed", "status: ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: needs-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] },
    { labels: ["status: needs-info"], comments: [{ id: 1, user: STRANGER, body: "me too" }] },
    { labels: ["agent-ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
  ];
  for (const scenario of scenarios) {
    const byLabels = world(scenario);
    const mirrored = world(scenario);
    assert.equal(await run(byLabels, 1), await main({ github: mirrored.github, log: () => {}, statusOf: mirroredStatusOf, env: fieldEnv }), JSON.stringify(scenario.labels));
    assert.deepEqual(mirrored.writes, byLabels.writes, JSON.stringify(scenario.labels));
  }
});

test("a hold in the Work status field the labels lack stops a decision", async () => {
  const w = world({ labels: ["status: confirmed"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await runWithField(w, { [NUMBER]: { state: "needs-human" } }), 0);
  assert.deepEqual(w.writes, []);
});

// The field mirrors the removal that left an issue without a status in a later
// run, so for such an issue the labels decide: the field is not read.
test("an issue with no status label is judged by its labels, whatever its Work status field holds", async () => {
  for (const state of ["needs-owner-decision", "confirmed", "ready"]) {
    const w = world({ labels: [], comments: [{ id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await runWithField(w, { [NUMBER]: { state } }), 0, state);
    assert.deepEqual(w.labels(), ["needs-triage"], state);
    expectDispatched(w);
  }
});

// work-unblock's Refs handoff, or any other removal, can leave an open issue
// with no status label; a listed human's decision still sends it to intake.
test("a listed human's decision on an issue with no status label sends it to triage once", async () => {
  const w = world({ labels: ["priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
  assert.equal(await run(w, 1), 0, "the second run finds needs-triage");
  expectDispatched(w);
});

test("a decision on an outside author's issue with no status label moves it to needs-triage without a model run", async () => {
  const w = world({ labels: [], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 0);
});

const statuslessQuiet = [
  ["agent-ready", ["agent-ready"], OWNER, DECISION],
  ["status: ready with agent-ready", ["status: ready", "agent-ready"], OWNER, DECISION],
  ["status: ready", ["status: ready"], OWNER, DECISION],
  ["needs-human", ["needs-human"], OWNER, DECISION],
  ["needs-triage", ["needs-triage"], OWNER, DECISION],
  ["admission-deferred", ["admission-deferred"], OWNER, DECISION],
  ["an unlisted person's decision", [], STRANGER, DECISION],
  ["the author's decision when unlisted", [], AUTHOR, DECISION],
  ["a listed human's comment without the marker", [], OWNER, "Option 1, I think."],
];
for (const [name, labels, user, body] of statuslessQuiet) {
  test(`a comment on an issue with no parked status changes nothing: ${name}`, async () => {
    const w = world({ labels, author: user === AUTHOR ? AUTHOR : OWNER, comments: [{ id: 1, user, body }] });
    assert.equal(await run(w, 1), 0);
    assert.deepEqual(w.writes, []);
  });
}

test("a bot's decision on an issue with no status label changes nothing", async () => {
  const w = world({ labels: [], comments: [{ id: 1, user: LISTED_BOT, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.writes, []);
});

test("a decision is judged by the labels when the Work status field is unset, set by another account, or names a ready state", async () => {
  for (const fields of [{}, { [NUMBER]: { state: "needs-human", setter: STRANGER_ID } }, { [NUMBER]: { state: "agent-ready" } }]) {
    const w = world({ labels: ["status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await runWithField(w, fields), 0);
    assert.deepEqual(w.labels(), ["needs-triage"]);
    expectDispatched(w);
  }
});

const DISPATCH = `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`;
const failures = [
  ["adding needs-triage", `POST /repos/${REPO}/issues/${NUMBER}/labels`],
  ["the dispatch", `POST ${DISPATCH}`],
];

for (const [name, fail] of failures) {
  test(`a failed call to ${name} after the claim restores the labels, and a re-run dispatches once`, async () => {
    const before = ["priority: medium", "status: needs-decision"];
    const w = world({ labels: before, comments: [{ id: 1, user: OWNER, body: DECISION }], fail });
    assert.equal(await run(w, 1), 1);
    assert.deepEqual(w.labels(), before);
    assert.equal(w.dispatches().length, name === "the dispatch" ? 1 : 0);
    assert.equal(await run(w, 1), 0);
    assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
    assert.equal(w.dispatches().length, name === "the dispatch" ? 2 : 1);
  });
}

test("a failed dispatch on an issue with no status label takes needs-triage back, puts no status on, and a re-run dispatches once", async () => {
  const w = world({ labels: ["priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }], fail: `POST ${DISPATCH}` });
  assert.equal(await run(w, 1), 1);
  assert.deepEqual(w.labels(), ["priority: medium"]);
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  assert.equal(w.dispatches().length, 2, "the failed call and the re-run's");
});

test("a failed dispatch keeps a needs-triage label the issue already had", async () => {
  const w = world({ labels: ["status: needs-info", "needs-triage"], comments: [{ id: 1, user: OWNER, body: "Answer." }], fail: `POST ${DISPATCH}` });
  assert.equal(await run(w, 1), 1);
  assert.deepEqual(w.labels(), ["needs-triage", "status: needs-info"]);
});

test("every answer waits in line instead of replacing a waiting run", () => {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  const block = /^ {4}concurrency:\n((?: {6}.*\n)+)/m.exec(workflow)?.[1] ?? "";
  assert.match(block, /^ {6}queue: max$/m);
});

test("never adds agent-ready", async () => {
  const w = world({ labels: ["status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  await run(w, 1);
  const added = w.writes.filter(([method, path]) => method === "POST" && path.endsWith("/labels")).flatMap(([, , body]) => body.labels);
  assert.deepEqual(added, ["needs-triage"]);
});

test("the kill switch stops the run before any API call", async () => {
  let calls = 0;
  const code = await main({ github: async () => (calls += 1), log: () => {}, env: { KILL_SWITCH: "" } });
  assert.equal(code, 0);
  assert.equal(calls, 0);
});

// A listed human lifting `needs-human` (an `issues: unlabeled` run) re-enters
// intake with no comment. The newest unlabeled needs-human event names who.
const lift = (actor, name = "needs-human") => ({ event: "unlabeled", actor, label: { name }, created_at: "2026-10-24T00:00:00Z" });
const runLift = (w) => run(w, "", { EVENT_NAME: "issues", COMMENT_ID: "" });

test("a listed human lifting needs-human sends the issue back to triage", async () => {
  const w = world({ labels: ["priority: medium"], events: [lift(OWNER)] });
  assert.equal(await runLift(w), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
});

test("the newest needs-human removal decides who lifted it", async () => {
  const w = world({ labels: [], events: [lift(STRANGER), lift(OWNER)] });
  assert.equal(await runLift(w), 0);
  expectDispatched(w);
});

test("a lift on a lanes App issue sends it back to triage", async () => {
  const w = world({ labels: [], author: LANES_APP, events: [lift(OWNER)] });
  assert.equal(await runLift(w), 0);
  expectDispatched(w);
});

// A decision the needs-human hold kept from re-entering leaves the issue at
// status: needs-decision; the listed human's lift is the answer that sends it on.
test("a listed human lifting needs-human re-enters an issue at status: needs-decision", async () => {
  const w = world({ labels: ["needs-human", "priority: medium", "status: needs-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }], events: [lift(OWNER)] });
  assert.equal(await run(w, 1), 0);
  assert.equal(w.dispatches().length, 0, "the decision alone dispatches nothing");
  await w.github("DELETE", `/repos/${REPO}/issues/${NUMBER}/labels/needs-human`);
  w.writes.length = 0;
  assert.equal(await runLift(w), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
});

test("a lift whose needs-decision another run already took dispatches nothing", async () => {
  const w = world({ labels: ["status: needs-decision"], events: [lift(OWNER)], gone: ["status: needs-decision"] });
  assert.equal(await runLift(w), 0);
  assert.equal(w.dispatches().length, 0);
  assert.deepEqual(w.writes.map(([method]) => method), ["DELETE"]);
});

test("a failed dispatch after a lift at needs-decision restores it, and a re-run dispatches once", async () => {
  const w = world({ labels: ["status: needs-decision"], events: [lift(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runLift(w), 1);
  assert.deepEqual(w.labels(), ["status: needs-decision"]);
  assert.equal(await runLift(w), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 2);
});

// work-unblock's removal of status: confirmed, with the lanes App's token, when
// a blocker closed: that token's event is what starts this run.
const CONFIRMED = "status: confirmed";
const strip = (actor = LANES_APP) => lift(actor, CONFIRMED);
const runStrip = (w) => run(w, "", { EVENT_NAME: "issues", COMMENT_ID: "", REMOVED_LABEL: CONFIRMED });

test("the lanes App's removal of status: confirmed sends the issue to triage once", async () => {
  const w = world({ labels: ["priority: medium"], events: [strip()] });
  assert.equal(await runStrip(w), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
  assert.equal(await runStrip(w), 0, "the second run finds needs-triage");
  expectDispatched(w);
});

test("a failed dispatch after the App's removal takes needs-triage back, puts no status on, and a re-run dispatches once", async () => {
  const w = world({ labels: [], events: [strip()], fail: `POST ${DISPATCH}` });
  assert.equal(await runStrip(w), 1);
  assert.deepEqual(w.labels(), []);
  assert.equal(await runStrip(w), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 2, "the failed call and the re-run's");
});

// Each row is the state another App removal, or a person's, leaves. admit.mjs
// and label-unblocked's admit add agent-ready first, refine's exact path adds
// needs-triage first, and the single-status writes add the hold first.
const stripQuiet = [
  ["admission's lift beside agent-ready", { labels: ["agent-ready", "status: ready"], events: [strip()] }],
  ["refine's lift, needs-triage first", { labels: ["needs-triage"], events: [strip()] }],
  ["a hold that replaced it", { labels: ["status: needs-decision"], events: [strip()] }],
  ["a verdict that landed", { labels: ["status: ready"], events: [strip()] }],
  ["a person's removal", { labels: [], events: [strip(OWNER)] }],
  ["an App removal followed by a person's", { labels: [], events: [strip(), strip(OWNER)] }],
  ["needs-human on the issue", { labels: ["needs-human"], events: [strip()] }],
  ["a deferral on the issue", { labels: ["admission-deferred"], events: [strip()] }],
  ["an author intake does not admit", { labels: [], author: AUTHOR, events: [strip()] }],
  ["a closed issue", { labels: [], state: "closed", events: [strip()] }],
];
for (const [name, options] of stripQuiet) {
  test(`a status: confirmed removal changes nothing: ${name}`, async () => {
    const w = world(options);
    assert.equal(await runStrip(w), 0);
    assert.deepEqual(w.writes, []);
  });
}

const liftQuiet = [
  ["an outsider's removal", { labels: [], events: [lift(STRANGER)] }],
  ["an older listed removal followed by an outsider's", { labels: [], events: [lift(OWNER), lift(STRANGER)] }],
  ["a removal of another label", { labels: [], events: [lift(OWNER, "priority: low")] }],
  ["no removal event", { labels: [], events: [] }],
  ["a status label still present", { labels: ["status: needs-info"], events: [lift(OWNER)] }],
  ["status: confirmed still present", { labels: ["status: confirmed"], events: [lift(OWNER)] }],
  ["another status label beside needs-decision", { labels: ["status: needs-decision", "status: needs-info"], events: [lift(OWNER)] }],
  ["an outsider's removal at needs-decision", { labels: ["status: needs-decision"], events: [lift(STRANGER)] }],
  ["an issue already agent-ready", { labels: ["agent-ready"], events: [lift(OWNER)] }],
  ["an issue that carries needs-human again", { labels: ["needs-human"], events: [lift(OWNER)] }],
  ["an issue already in needs-triage", { labels: ["needs-triage"], events: [lift(OWNER)] }],
  ["an untrusted author", { labels: [], author: AUTHOR, events: [lift(OWNER)] }],
  ["a closed issue", { labels: [], state: "closed", events: [lift(OWNER)] }],
  ["a pull request", { labels: [], pullRequest: true, events: [lift(OWNER)] }],
];

for (const [name, setup] of liftQuiet) {
  test(`a needs-human lift changes nothing for ${name}`, async () => {
    const w = world(setup);
    assert.equal(await runLift(w), 0);
    assert.deepEqual(w.writes, []);
  });
}

test("a failed dispatch after a lift takes needs-triage back off", async () => {
  const w = world({ labels: ["priority: medium"], events: [lift(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runLift(w), 1);
  assert.deepEqual(w.labels(), ["priority: medium"]);
});

test("the workflow runs on a needs-human unlabel", () => {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  assert.match(workflow, /^ {2}issues:.*\n {4}types: \[unlabeled, field_added, field_removed\]$/m);
  assert.match(workflow, /github\.event\.label\.name == 'needs-human'/);
});

// The reenter job's folded `if:`, evaluated against one event. Covers only
// what that gate uses: &&, ||, ==, !, and contains() over the issue's labels
// and, case-insensitively as GitHub does, over the comment body.
function reenterGate({ event, labels, label = null, comment = null, sender = null, action = event === "issues" ? "unlabeled" : "created", fieldId = null }) {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  const block = /\n {2}reenter:\n(?: {4}#.*\n)* {4}if: >-\n((?: {6}.*\n)+)/.exec(workflow)?.[1];
  assert.ok(block, "the reenter job has a folded if:");
  let body = block
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ");
  body = body.replace(/contains\(github\.event\.issue\.labels\.\*\.name, ('[^']*')\)/g, (_, name) => `${JSON.stringify(labels)}.includes(${name})`);
  body = body.replace(
    /contains\(github\.event\.comment\.body, ('[^']*')\)/g,
    (_, text) => `${JSON.stringify(String(comment?.body ?? "").toLowerCase())}.includes(${text}.toLowerCase())`,
  );
  const context = {
    "github.event.comment.performed_via_github_app": null,
    "github.event.comment.user.type": comment?.type ?? null,
    "github.event.action": action,
    "github.event.issue_field.id": fieldId,
    "github.event.issue.pull_request": null,
    "github.event.issue.state": "open",
    "github.event.label.name": label,
    "github.event.sender.type": sender,
    github_event_name: event,
  };
  body = body.replaceAll("github.event_name", "github_event_name");
  for (const name of Object.keys(context).sort((a, b) => b.length - a.length)) {
    body = body.replaceAll(name, JSON.stringify(context[name]));
  }
  assert.doesNotMatch(body.replace(/'[^']*'|"[^"]*"/g, "''"), /github[._]/, `an unresolved reference in ${body}`);
  return Function(`return (${body});`)();
}

test("a parked swap that lifts needs-human and adds status: confirmed starts no runner", () => {
  assert.equal(reenterGate({ event: "issues", label: "needs-human", labels: ["host-run", "status: confirmed", "priority: medium"] }), false);
});

test("a plain needs-human lift and a comment on a parked issue still start the job", () => {
  assert.equal(reenterGate({ event: "issues", label: "needs-human", labels: ["priority: medium"] }), true);
  assert.equal(reenterGate({ event: "issues", label: "needs-human", labels: ["host-run"] }), true);
  assert.equal(reenterGate({ event: "issue_comment", comment: { type: "User", body: DECISION }, labels: ["status: confirmed"] }), true);
  assert.equal(reenterGate({ event: "issues", label: "priority: low", labels: [] }), false);
});

// The script takes a comment at needs-decision or confirmed only when its first
// line, leading whitespace trimmed, starts `**Decision recorded.**`; any other
// comment there starts no runner. needs-info takes any comment.
test("a comment at needs-decision or confirmed starts the job only with the decision marker", () => {
  const comment = (labels, body) => reenterGate({ event: "issue_comment", comment: { type: "User", body }, labels });
  for (const status of ["status: needs-decision", "status: confirmed"]) {
    assert.equal(comment([status], DECISION), true, status);
    assert.equal(comment([status], "  \n**Decision recorded.**\n\nOption 1."), true, `${status}, leading whitespace`);
    assert.equal(comment([status], "Thanks, looking."), false, status);
    assert.equal(comment([status], "Decision recorded."), false, `${status}, no bold`);
    assert.equal(comment([status, "status: needs-info"], "An answer."), true, `${status} beside needs-info`);
  }
  assert.equal(comment(["status: needs-info"], "An answer."), true);
});

test("a decision on an issue with no parked status starts the job unless it is ready or held", () => {
  const comment = (labels, body = DECISION) => reenterGate({ event: "issue_comment", comment: { type: "User", body }, labels });
  assert.equal(comment([]), true);
  assert.equal(comment(["priority: medium", "host-run"]), true);
  assert.equal(comment([], "Thanks, looking."), false, "no marker");
  assert.equal(comment([], "Decision recorded."), false, "no bold");
  assert.equal(reenterGate({ event: "issue_comment", comment: { type: "Bot", body: DECISION }, labels: [] }), false, "a bot");
  for (const label of ["status: ready", "agent-ready", "needs-human", "needs-triage", "admission-deferred"]) {
    assert.equal(comment([label]), false, label);
  }
  assert.equal(comment(["status: ready", "agent-ready"]), false, "status: ready with agent-ready");
});

test("only a bot's status: confirmed removal with nothing else to move the issue starts the job", () => {
  const removal = (labels, sender = "Bot") => reenterGate({ event: "issues", label: CONFIRMED, labels, sender });
  assert.equal(removal(["priority: medium"]), true);
  assert.equal(removal([], "User"), false);
  for (const label of ["status: ready", "status: needs-decision", "status: needs-info", "agent-ready", "needs-triage"]) {
    assert.equal(removal([label]), false, label);
  }
});

// A Work status field change: a listed human releasing a hold that exists
// only on the field (no status label) re-enters intake once. The field events
// are the GraphQL ones; the run reads the live models.issue-status from this
// checkout.
const ROOT = new URL("../../..", import.meta.url).pathname;
const FIELD_WRITE = `/repos/${REPO}/issues/${NUMBER}/issue-field-values`;
const runField = (w, action, sender = OWNER) =>
  run(w, "", { EVENT_NAME: "issues", EVENT_ACTION: action, SENDER_ID: String(sender.id), COMMENT_ID: "", BASE_PATH: ROOT });
const heldBy = (actor = LANES_APP, value = "needs-human") => fieldNode("IssueFieldAddedEvent", actor, { value });
const changed = (actor, previousValue, newValue) => fieldNode("IssueFieldChangedEvent", actor, { previousValue, newValue });
const removed = (actor) => fieldNode("IssueFieldRemovedEvent", actor);
const fieldWrites = (w) => w.writes.filter(([, path]) => path === FIELD_WRITE);

test("a listed human moving a field-only hold to needs-triage adds the needs-triage claim, writes no field, and dispatches once", async () => {
  const w = world({ labels: ["priority: medium"], fieldNodes: [heldBy(), changed(OWNER, "needs-human", "needs-triage")] });
  assert.equal(await runField(w, "field_added"), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  assert.deepEqual(fieldWrites(w), [], "the field is already at the floor");
  expectDispatched(w);
  assert.equal(await runField(w, "field_added"), 0, "a queued second run finds the claim");
  expectDispatched(w);
});

test("a listed human clearing a field-only hold dispatches once, then sets the field to needs-triage", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await runField(w, "field_removed"), 0);
  assert.deepEqual(w.labels(), ["needs-triage"]);
  expectDispatched(w);
  assert.deepEqual(fieldWrites(w).map(([method, , body]) => [method, body]), [["POST", { issue_field_values: [{ field_id: 48484079, value: "needs-triage" }] }]]);
  const order = w.writes.map(([method, path]) => `${method} ${path.split("/").at(-1)}`);
  assert.deepEqual(order, ["POST labels", "POST issue-field-values", "POST dispatches"], "claim, field, then dispatch");
  w.writes.length = 0;
  assert.equal(await runField(w, "field_removed"), 0, "a queued second run stops");
  assert.deepEqual(w.writes, []);
});

test("every hold state released by a listed human re-enters", async () => {
  for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"]) {
    const w = world({ labels: [], fieldNodes: [heldBy(LANES_APP, hold), changed(OWNER, hold, "needs-triage")] });
    assert.equal(await runField(w, "field_added"), 0, hold);
    assert.equal(w.dispatches().length, 1, hold);
  }
});

test("a failed dispatch after a field release takes the claim back, and a re-run dispatches once", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runField(w, "field_removed"), 1);
  assert.deepEqual(w.labels(), [], "the claim comes back off");
  assert.equal(fieldWrites(w).length, 1, "the field was set before the dispatch");
  assert.equal(await runField(w, "field_removed"), 0, "the re-run walks past its own field write");
  assert.deepEqual(w.labels(), ["needs-triage"]);
  assert.equal(w.dispatches().length, 2, "the failed call and the re-run's");
  assert.equal(fieldWrites(w).length, 1, "the field already reads needs-triage");
});

test("a re-run that sees the job token's or the lanes App's own needs-triage write still finds the release", async () => {
  for (const bot of [ACTIONS_BOT, LANES_APP]) {
    const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER), heldBy(bot, "needs-triage")] });
    assert.equal(await runField(w, "field_removed"), 0, bot.login);
    expectDispatched(w);
    assert.deepEqual(fieldWrites(w), [], bot.login);
  }
});

test("a listed human who set the hold and then clears it releases it", async () => {
  for (const fieldNodes of [
    [heldBy(OWNER, "needs-human"), removed(OWNER)],
    [heldBy(LANES_APP, "ready"), changed(OWNER, "ready", "needs-human"), removed(OWNER)],
  ]) {
    const w = world({ labels: [], fieldNodes });
    assert.equal(await runField(w, "field_removed"), 0);
    expectDispatched(w);
  }
});

test("a listed human who removes a hold and then sets needs-triage releases it", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER), heldBy(OWNER, "needs-triage")] });
  assert.equal(await runField(w, "field_added"), 0);
  expectDispatched(w);
  assert.deepEqual(fieldWrites(w), []);
});

test("a field write that fails warns, still dispatches, and the claim stops a queued second run", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)], fail: `POST ${FIELD_WRITE}` });
  const lines = [];
  const code = await main({
    github: w.github,
    log: (line) => lines.push(line),
    env: { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), COMMENT_ID: "", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id), EVENT_NAME: "issues", EVENT_ACTION: "field_removed", SENDER_ID: String(OWNER.id), BASE_PATH: ROOT },
  });
  assert.equal(code, 0);
  expectDispatched(w);
  assert.ok(lines.some((line) => line.startsWith("::warning title=intake-reenter::#42's Work status field was not set")), lines.join("\n"));
  assert.deepEqual(w.labels(), ["needs-triage"]);
  w.writes.length = 0;
  assert.equal(await runField(w, "field_removed"), 0);
  assert.deepEqual(w.writes, [], "the needs-triage claim stops it");
});

test("an option name models.issue-status does not map fails the run", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(LANES_APP, "on-hold"), removed(OWNER)] });
  assert.equal(await runField(w, "field_removed"), 1);
  assert.deepEqual(w.writes, []);
});

const fieldQuiet = [
  ["a third-party bot's release", { labels: [], fieldNodes: [heldBy(), changed(LISTED_BOT, "needs-human", "needs-triage")] }, "field_added", LISTED_BOT],
  ["an unlisted person's release", { labels: [], fieldNodes: [heldBy(), changed(STRANGER, "needs-human", "needs-triage")] }, "field_added", STRANGER],
  ["a listed human moving a hold to ready", { labels: [], fieldNodes: [heldBy(), changed(OWNER, "needs-human", "ready")] }, "field_added", OWNER],
  ["a listed human moving a hold to agent-ready", { labels: [], fieldNodes: [heldBy(), changed(OWNER, "needs-human", "agent-ready")] }, "field_added", OWNER],
  ["a newest event that is not the sender's", { labels: [], fieldNodes: [heldBy(), changed(STRANGER, "needs-human", "needs-triage")] }, "field_added", OWNER],
  ["a hold set again after the release", { labels: [], fieldNodes: [heldBy(), removed(OWNER), heldBy(LANES_APP)] }, "field_added", OWNER],
  ["another person between the hold and the sender", { labels: [], fieldNodes: [heldBy(), changed(STRANGER, "needs-human", "ready"), changed(OWNER, "ready", "needs-triage")] }, "field_added", OWNER],
  ["a third-party bot's needs-triage after the release", { labels: [], fieldNodes: [heldBy(), removed(OWNER), heldBy(LISTED_BOT, "needs-triage")] }, "field_added", OWNER],
  ["a change from a state that is no hold", { labels: [], fieldNodes: [heldBy(LANES_APP, "confirmed"), removed(OWNER)] }, "field_removed", OWNER],
  ["another field's release", { labels: [], fieldNodes: [heldBy(), fieldNode("IssueFieldRemovedEvent", OWNER, {}, "15462270")] }, "field_removed", OWNER],
  ["a status label still on the issue", { labels: ["status: needs-decision"], fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["a hold label still on the issue", { labels: ["needs-human"], fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["agent-ready on the issue", { labels: ["agent-ready"], fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["an author intake does not admit", { labels: [], author: AUTHOR, fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["a closed issue", { labels: [], state: "closed", fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["a pull request", { labels: [], pullRequest: true, fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
  ["no field event", { labels: [], fieldNodes: [] }, "field_added", OWNER],
];
for (const [name, options, action, sender] of fieldQuiet) {
  test(`a Work status field change changes nothing: ${name}`, async () => {
    const w = world(options);
    assert.equal(await runField(w, action, sender), 0);
    assert.deepEqual(w.writes, []);
  });
}

test("a field change with no action reads as a label removal, so a stale needs-human removal still needs the unlabel path", async () => {
  const w = world({ labels: [], events: [], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await run(w, "", { EVENT_NAME: "issues", COMMENT_ID: "", SENDER_ID: String(OWNER.id), BASE_PATH: ROOT }), 0);
  assert.deepEqual(w.writes, []);
});

test("the job starts on a person's Work status field change only, on that field only", () => {
  const field = (action, fieldId, sender) => reenterGate({ event: "issues", action, fieldId, sender, labels: [] });
  assert.equal(field("field_added", 48484079, "User"), true);
  assert.equal(field("field_removed", 48484079, "User"), true);
  assert.equal(field("field_added", 48484079, "Bot"), false, "a bot's field write");
  assert.equal(field("field_removed", 48484079, "Bot"), false, "a bot's field removal");
  assert.equal(field("field_added", 15462270, "User"), false, "another field");
  assert.equal(field("unlabeled", 48484079, "User"), false, "an unlabel of no watched label");
  assert.equal(reenterGate({ event: "issues", action: "field_added", fieldId: 48484079, sender: "User", labels: [], comment: null, label: null }), true);
});

test("the job hands the script the field change's action and sender", () => {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  assert.match(workflow, /^ {10}EVENT_ACTION: \$\{\{ github\.event\.action \}\}$/m);
  assert.match(workflow, /^ {10}SENDER_ID: \$\{\{ github\.event\.sender\.id \}\}$/m);
});
