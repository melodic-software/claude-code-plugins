// Expected values come from the requested behavior for answered issues: a
// listed human's `**Decision recorded.**` first line on a
// `needs-owner-decision` issue, or the author's or a listed human's reply
// on a `needs-reporter-info` issue, removes that status label and sets the
// Work status field to needs-triage; it dispatches intake-triage.yml once with the issue number
// only when the issue's author is one intake admits on open (a listed human
// or the lanes App). A decision on an issue that carries `needs-human`
// changes nothing, and a listed human's removal of `needs-human` re-enters an
// issue at `needs-owner-decision` (owner decision on #10735). A decision on
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
import { mirroredStatusOf, OPTION, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../../actions/resolve-config/read-status.fixtures.mjs";
import { statusReader } from "../../actions/resolve-config/read-status.mjs";

const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton", type: "User" };
const STRANGER = { id: 5005, login: "someone", type: "User" };
const AUTHOR = { id: 6006, login: "reporter", type: "User" };
const LISTED_BOT = { id: 209825114, login: "claude[bot]", type: "Bot" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]", type: "Bot" };
const ACTIONS_BOT = { id: 41898282, login: "github-actions", type: "Bot" };
const NUMBER = 42;
const FIELD = "48484079";
// The checkout whose models.issue-status every run reads and writes by.
const ROOT = new URL("../../..", import.meta.url).pathname;
// One GraphQL Work status field event, as the API answers it.
const fieldNode = (type, actor, values = {}, field = FIELD) => ({
  __typename: type,
  createdAt: "2026-11-06T00:00:00Z",
  actor: { __typename: actor.type, login: actor.login, databaseId: actor.id },
  issueField: { fullDatabaseId: field },
  ...values,
});
// The Work status the field events leave: the newest one's value, or null.
const fieldState = (nodes) =>
  nodes.filter((node) => node.issueField.fullDatabaseId === FIELD).reduce((state, node) => (node.__typename === "IssueFieldRemovedEvent" ? null : (node.newValue ?? node.value)), null);
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
// `fieldNodes` are its Work status field events; the field holds what they
// leave, and a field write adds the job token's event.
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
    if (method === "GET" && path === `${base}/issue-field-values`) {
      const now = fieldState(fieldNodes);
      return now === null ? [] : [{ issue_field_id: Number(FIELD), single_select_option: { id: OPTION[now] } }];
    }
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
    if (method === "POST" && path === `${base}/comments`) {
      const posted = { id: 9000 + shaped.length, user: { login: "github-actions[bot]", id: ACTIONS_BOT.id, type: "Bot" }, body: body.body };
      shaped.push(posted);
      return posted;
    }
    if (method === "DELETE" && one) {
      const at = shaped.findIndex((c) => String(c.id) === one[1]);
      if (at < 0) throw new GitHubError(404, `DELETE ${path}`);
      shaped.splice(at, 1);
      return null;
    }
    if (method === "POST" && path === `${base}/issue-field-values`) {
      const value = body.issue_field_values[0].value;
      fieldNodes.push(fieldNode("IssueFieldAddedEvent", ACTIONS_BOT, { value }));
      return [{ issue_field_id: 48484079, single_select_option: { id: OPTION[value] } }];
    }
    throw new Error(`unexpected ${method} ${path}`);
  }
  const dispatches = () => writes.filter(([, path]) => path.endsWith("/dispatches"));
  return { github, writes, dispatches, labels: () => [...current].sort(), field: () => fieldState(fieldNodes), comments: () => shaped };
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
      BASE_PATH: ROOT,
      ...env,
    },
  });

const expectDispatched = (w) => {
  assert.deepEqual(w.dispatches(), [
    ["POST", `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`, { ref: "main", inputs: { "issue-number": "42" } }],
  ]);
};
// The issue went back to triage: `labels` are left and the Work status field
// reads needs-triage, with no needs-triage label added.
const expectTriage = (w, labels, why) => {
  assert.deepEqual(w.labels(), labels, why);
  assert.equal(w.field(), "needs-triage", why);
};

test("a listed human's decision on a needs-decision issue sends it back to triage", async () => {
  const w = world({
    labels: ["needs-owner-decision", "priority: medium"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, ["priority: medium"]);
  expectDispatched(w);
});

const PARKED = { id: 9, user: LANES_APP, body: "<!-- intake-triage admission -->\nNot admitted to the issue lane: no trusted-human acceptance criteria." };

test("a decision on an issue that carries needs-human keeps it and changes nothing", async () => {
  for (const labels of [["needs-human", "needs-owner-decision"], ["needs-human", "status: confirmed"]]) {
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
  expectTriage(w, ["priority: medium"]);
  expectDispatched(w);
});

test("a person's needs-human that lands after the read keeps a parked issue held: no field write, no dispatch", async () => {
  const fieldNodes = [];
  const w = world({ labels: ["status: confirmed", "priority: medium"], comments: [PARKED, { id: 1, user: OWNER, body: DECISION }], fieldNodes });
  const github = async (method, path, body) => {
    const answer = await w.github(method, path, body);
    if (method === "DELETE" && path.endsWith(encodeURIComponent("status: confirmed"))) fieldNodes.push(fieldNode("IssueFieldAddedEvent", OWNER, { value: "needs-human" }));
    return answer;
  };
  assert.equal(await run({ ...w, github }, 1), 0);
  assert.equal(w.field(), "needs-human", "the person's hold stands");
  assert.ok(!w.writes.some(([method, path]) => method === "POST" && path.endsWith("/issue-field-values")), "no field write");
  assert.deepEqual(w.dispatches(), []);
  assert.deepEqual(w.labels(), ["priority: medium", "status: confirmed"], "the status label the run took off is put back");
});

test("a decision releases the person's needs-owner-decision it answers, and keeps a different person's hold set after the read", async () => {
  const asked = () => [fieldNode("IssueFieldAddedEvent", OWNER, { value: "needs-owner-decision" })];
  const answered = world({ labels: ["needs-owner-decision", "priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }], fieldNodes: asked() });
  assert.equal(await run(answered, 1), 0);
  expectTriage(answered, ["priority: medium"], "the answered hold is released");
  expectDispatched(answered);
  const fieldNodes = asked();
  const raced = world({ labels: ["needs-owner-decision", "priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }], fieldNodes });
  const github = async (method, path, body) => {
    const answer = await raced.github(method, path, body);
    if (method === "DELETE" && path.endsWith(encodeURIComponent("needs-owner-decision"))) fieldNodes.push(fieldNode("IssueFieldChangedEvent", OWNER, { previousValue: "needs-owner-decision", newValue: "needs-human" }));
    return answer;
  };
  assert.equal(await run({ ...raced, github }, 1), 0);
  assert.equal(raced.field(), "needs-human", "the person's later hold stands");
  assert.ok(!raced.writes.some(([method, path]) => method === "POST" && path.endsWith("/issue-field-values")), "no field write");
  assert.deepEqual(raced.dispatches(), []);
  assert.deepEqual(raced.labels(), ["needs-owner-decision", "priority: medium"], "the status label the run took off is put back");
});

test("a listed human's decision on a status: confirmed issue admission never saw sends it back to triage", async () => {
  const w = world({
    labels: ["status: confirmed", "priority: medium"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, ["priority: medium"]);
  expectDispatched(w);
});

test("a decision on an outside author's hand-confirmed issue moves it to needs-triage without a model run", async () => {
  const w = world({ labels: ["status: confirmed"], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, []);
  assert.equal(w.dispatches().length, 0);
});

test("a hand-confirmed issue stays put for a stranger's decision, needs-human, or a second status label", async () => {
  for (const [name, labels, user] of [
    ["stranger", ["status: confirmed"], STRANGER],
    ["needs-human", ["needs-human", "status: confirmed"], OWNER],
    ["needs-info", ["status: confirmed", "needs-reporter-info"], OWNER],
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
    labels: ["needs-reporter-info", "needs-human"],
    author: AUTHOR,
    comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }],
  });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, ["needs-human"]);
  assert.equal(w.dispatches().length, 0);
});

test("a decision on an outside author's issue moves it to needs-triage without a model run", async () => {
  const w = world({ labels: ["needs-owner-decision"], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, []);
  assert.equal(w.dispatches().length, 0);
});

test("a decision on a lanes App issue sends it back to triage", async () => {
  const w = world({ labels: ["needs-owner-decision"], author: LANES_APP, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, []);
  expectDispatched(w);
});

test("a listed human's reply on a needs-info issue sends it back to triage", async () => {
  const w = world({ labels: ["needs-reporter-info"], comments: [{ id: 1, user: OWNER, body: "It is the Windows host." }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, []);
  expectDispatched(w);
});

const quiet = [
  ["a bot comment, even from the issue's author", { labels: ["needs-reporter-info"], author: LISTED_BOT, comments: [{ id: 1, user: LISTED_BOT, body: DECISION }] }],
  ["the lanes App's comment on its own issue", { labels: ["needs-reporter-info"], author: LANES_APP, comments: [{ id: 1, user: LANES_APP, body: "Reply." }] }],
  [
    "an App-posted comment",
    { labels: ["needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION, performed_via_github_app: { slug: "x" } }] },
  ],
  [
    "a decision last edited by a non-human",
    { labels: ["needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }], editors: { 1: LISTED_BOT.id } },
  ],
  [
    "the marker on a line other than the first",
    { labels: ["needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: "Thinking.\n**Decision recorded.**" }] },
  ],
  ["an unlisted person's decision", { labels: ["needs-owner-decision"], comments: [{ id: 1, user: STRANGER, body: DECISION }] }],
  ["an issue without the status label", { labels: ["needs-human"], comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a closed issue", { labels: ["needs-owner-decision"], state: "closed", comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a pull request", { labels: ["needs-owner-decision"], pullRequest: true, comments: [{ id: 1, user: OWNER, body: DECISION }] }],
  ["a stranger's reply on a needs-info issue", { labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: STRANGER, body: "Me too." }] }],
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
    labels: ["needs-owner-decision"],
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
    labels: ["needs-owner-decision", "needs-triage"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
    gone: ["needs-owner-decision"],
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
const fieldEnv = { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), COMMENT_ID: "1", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id), BASE_PATH: ROOT };
const runWithField = (w, fields) => {
  const github = withFields(w.github, fields);
  return main({
    github,
    log: () => {},
    statusOf: statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }),
    env: fieldEnv,
  });
};

test("a field that mirrors the labels changes no answer", async () => {
  const scenarios = [
    { labels: ["needs-owner-decision", "priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["needs-human", "needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed", "agent-ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["status: confirmed", "status: ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
    { labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] },
    { labels: ["needs-reporter-info"], comments: [{ id: 1, user: STRANGER, body: "me too" }] },
    { labels: ["agent-ready"], comments: [{ id: 1, user: OWNER, body: DECISION }] },
  ];
  for (const scenario of scenarios) {
    const byLabels = world(scenario);
    const mirrored = world(scenario);
    assert.equal(await run(byLabels, 1), await main({ github: mirrored.github, log: () => {}, statusOf: mirroredStatusOf, env: fieldEnv }), JSON.stringify(scenario.labels));
    assert.deepEqual(mirrored.writes, byLabels.writes, JSON.stringify(scenario.labels));
  }
});

const runWithFieldEnv = (w, fields, env) => {
  const github = withFields(w.github, fields);
  return main({ github, log: () => {}, statusOf: statusReader({ github, repository: REPO, config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }), env: { ...fieldEnv, ...env } });
};

// A reply sets needs-triage, which would overwrite a hold only the field holds.
test("a reply to a stale needs-info label leaves a person's field-only hold, and answers once no other hold stands", async () => {
  for (const state of ["needs-human", "needs-owner-decision", "needs-spec"]) {
    const w = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] });
    assert.equal(await runWithField(w, { [NUMBER]: { state } }), 0, state);
    assert.deepEqual(w.writes, [], state);
  }
  const answered = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] });
  assert.equal(await runWithField(answered, { [NUMBER]: { state: "needs-reporter-info" } }), 0);
  expectTriage(answered, []);
});

// A Work status read that fails could hide a hold, so neither path writes.
test("a failed Work status read lifts nothing on the comment path or the needs-human lift path", async () => {
  const reply = world({ labels: ["needs-reporter-info"], comments: [{ id: 1, user: OWNER, body: "It is the Windows host." }] });
  assert.equal(await runWithField(reply, { [NUMBER]: new Error("HTTP 502") }), 1);
  assert.deepEqual(reply.writes, []);
  const lifted = world({ labels: ["priority: medium"], events: [lift(OWNER)] });
  assert.equal(await runWithFieldEnv(lifted, { [NUMBER]: new Error("HTTP 502") }, { EVENT_NAME: "issues", COMMENT_ID: "" }), 1);
  assert.deepEqual(lifted.writes, []);
  assert.equal(lifted.dispatches().length, 0);
});

test("a hold in the Work status field the labels lack stops a decision", async () => {
  const w = world({ labels: ["status: confirmed"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await runWithField(w, { [NUMBER]: { state: "needs-human" } }), 0);
  assert.deepEqual(w.writes, []);
});

// With no status label, the field decides: a decision answers its
// needs-owner-decision or confirmed, and its ready awaits no answer.
test("an issue with no status label is judged by its Work status field", async () => {
  for (const state of ["needs-owner-decision", "confirmed"]) {
    const w = world({ labels: [], comments: [{ id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await runWithField(w, { [NUMBER]: { state } }), 0, state);
    expectTriage(w, [], state);
    expectDispatched(w);
  }
  const ready = world({ labels: [], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await runWithField(ready, { [NUMBER]: { state: "ready" } }), 0);
  assert.deepEqual(ready.writes, [], "ready");
});

// An issue whose hold exists only on the field: a listed human's reply or
// decision answers it; a second run reads the field at needs-triage and stops.
const heldOnField = (hold) => [fieldNode("IssueFieldAddedEvent", LANES_APP, { value: hold })];
test("a field-only hold is answered once, with no label written", async () => {
  for (const [hold, body] of [
    ["needs-reporter-info", "It is the Windows host."],
    ["needs-owner-decision", DECISION],
  ]) {
    const w = world({ labels: ["priority: medium"], comments: [{ id: 1, user: OWNER, body }], fieldNodes: heldOnField(hold) });
    assert.equal(await run(w, 1), 0, hold);
    expectTriage(w, ["priority: medium"], hold);
    expectDispatched(w);
    assert.equal(w.writes.filter(([, path]) => path.includes("/labels")).length, 0, `${hold}: no label written`);
    assert.equal(await run(w, 1), 0, `${hold}: second run`);
    expectDispatched(w);
  }
});

test("the issue author's reply on a field-only needs-reporter-info hold re-enters it", async () => {
  const w = world({ labels: [], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }], fieldNodes: heldOnField("needs-reporter-info") });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, [], "the field moves to needs-triage");
  assert.equal(w.dispatches().length, 0, "intake does not admit the author, so no model run");
  const stranger = world({ labels: [], author: AUTHOR, comments: [{ id: 1, user: STRANGER, body: "Me too." }], fieldNodes: heldOnField("needs-reporter-info") });
  assert.equal(await run(stranger, 1), 0);
  assert.deepEqual(stranger.writes, [], "a stranger's reply answers nothing");
});

// work-unblock's Refs handoff, or any other removal, can leave an open issue
// with no status label; a listed human's decision still sends it to intake.
test("a listed human's decision on an issue with no status label sends it to triage once", async () => {
  const w = world({ labels: ["priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, ["priority: medium"]);
  expectDispatched(w);
  assert.equal(await run(w, 1), 0, "the second run finds needs-triage");
  expectDispatched(w);
});

test("a decision on an outside author's issue with no status label moves it to needs-triage without a model run", async () => {
  const w = world({ labels: [], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, []);
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
    const w = world({ labels: ["needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
    assert.equal(await runWithField(w, fields), 0);
    expectTriage(w, []);
    expectDispatched(w);
  }
});

const DISPATCH = `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`;
const FIELD_WRITE = `/repos/${REPO}/issues/${NUMBER}/issue-field-values`;
const failures = [
  ["the Work status write", `POST ${FIELD_WRITE}`],
  ["the dispatch", `POST ${DISPATCH}`],
];

for (const [name, fail] of failures) {
  test(`a failed call to ${name} after the claim restores the label and the field, and a re-run dispatches once`, async () => {
    const before = ["needs-owner-decision", "priority: medium"];
    const w = world({ labels: before, comments: [{ id: 1, user: OWNER, body: DECISION }], fail });
    assert.equal(await run(w, 1), 1);
    assert.deepEqual(w.labels(), before);
    assert.equal(w.field(), "needs-owner-decision", "the answered status is set back");
    assert.equal(w.dispatches().length, name === "the dispatch" ? 1 : 0);
    assert.equal(await run(w, 1), 0);
    expectTriage(w, ["priority: medium"]);
    assert.equal(w.dispatches().length, name === "the dispatch" ? 2 : 1);
  });
}

// No status to set back: the field stays at needs-triage, the claim a re-run
// reads, and the triage sweep dispatches the issue.
test("a failed dispatch on an issue with no status label leaves it at needs-triage for the triage sweep", async () => {
  const w = world({ labels: ["priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }], fail: `POST ${DISPATCH}` });
  assert.equal(await run(w, 1), 1);
  expectTriage(w, ["priority: medium"]);
  assert.equal(await run(w, 1), 0);
  assert.equal(w.dispatches().length, 1, "only the failed call");
});

test("a failed dispatch puts the label back but keeps a person's hold set after the field write", async () => {
  const before = ["needs-owner-decision", "priority: medium"];
  const fieldNodes = [];
  const w = world({ labels: before, comments: [{ id: 1, user: OWNER, body: DECISION }], fieldNodes, fail: `POST ${DISPATCH}` });
  const github = async (method, path, body) => {
    if (method === "POST" && path === DISPATCH) fieldNodes.push(fieldNode("IssueFieldAddedEvent", OWNER, { value: "needs-human" }));
    return w.github(method, path, body);
  };
  assert.equal(await run({ ...w, github }, 1), 1);
  assert.deepEqual(w.labels(), before);
  assert.equal(w.field(), "needs-human", "the person's hold stands");
  assert.deepEqual(
    w.writes.filter(([method, path]) => method === "POST" && path === FIELD_WRITE).map(([, , body]) => body.issue_field_values[0].value),
    ["needs-triage"],
    "the restore writes no needs-owner-decision over the hold",
  );
});

test("a failed dispatch leaves the labels as they were and sets the answered status back", async () => {
  const w = world({ labels: ["needs-reporter-info", "needs-triage"], comments: [{ id: 1, user: OWNER, body: "Answer." }], fail: `POST ${DISPATCH}` });
  assert.equal(await run(w, 1), 1);
  assert.deepEqual(w.labels(), ["needs-reporter-info", "needs-triage"]);
  assert.equal(w.field(), "needs-reporter-info");
});

test("every answer waits in line instead of replacing a waiting run", () => {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  const block = /^ {4}concurrency:\n((?: {6}.*\n)+)/m.exec(workflow)?.[1] ?? "";
  assert.match(block, /^ {6}queue: max$/m);
});

test("never adds agent-ready, nor any label, on an answer", async () => {
  const w = world({ labels: ["needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  await run(w, 1);
  const added = w.writes.filter(([method, path]) => method === "POST" && path.endsWith("/labels")).flatMap(([, , body]) => body.labels);
  assert.deepEqual(added, []);
  assert.deepEqual(w.writes.filter(([, path]) => path === FIELD_WRITE).map(([, , body]) => body.issue_field_values[0].value), ["needs-triage"]);
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
  expectTriage(w, ["priority: medium"]);
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
// needs-owner-decision; the listed human's lift is the answer that sends it on.
test("a listed human lifting needs-human re-enters an issue at needs-owner-decision", async () => {
  const w = world({ labels: ["needs-human", "priority: medium", "needs-owner-decision"], comments: [{ id: 1, user: OWNER, body: DECISION }], events: [lift(OWNER)] });
  assert.equal(await run(w, 1), 0);
  assert.equal(w.dispatches().length, 0, "the decision alone dispatches nothing");
  await w.github("DELETE", `/repos/${REPO}/issues/${NUMBER}/labels/needs-human`);
  w.writes.length = 0;
  assert.equal(await runLift(w), 0);
  expectTriage(w, ["priority: medium"]);
  expectDispatched(w);
});

test("a lift whose needs-decision another run already took dispatches nothing", async () => {
  const w = world({ labels: ["needs-owner-decision"], events: [lift(OWNER)], gone: ["needs-owner-decision"] });
  assert.equal(await runLift(w), 0);
  assert.equal(w.dispatches().length, 0);
  assert.deepEqual(w.writes.map(([method]) => method), ["DELETE"]);
});

test("a failed dispatch after a lift at needs-decision restores it, and a re-run dispatches once", async () => {
  const w = world({ labels: ["needs-owner-decision"], events: [lift(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runLift(w), 1);
  assert.deepEqual(w.labels(), ["needs-owner-decision"]);
  assert.equal(w.field(), "needs-owner-decision");
  assert.equal(await runLift(w), 0);
  expectTriage(w, []);
  assert.equal(w.dispatches().length, 2);
});

// The lift reads statusEvents: a listed human's change of the field away from
// needs-human is their removal, newer than a stranger's label removal.
test("a listed human's field change away from needs-human counts as the newest removal", async () => {
  const w = world({ labels: [], events: [lift(STRANGER)], fieldNodes: [fieldNode("IssueFieldAddedEvent", LANES_APP, { value: "needs-human" }), fieldNode("IssueFieldRemovedEvent", OWNER)] });
  assert.equal(await runLift(w), 0);
  expectTriage(w, []);
  expectDispatched(w);
});

// The lanes App's unpark no longer starts this run (the triage sweep re-sends
// an unparked issue): a status: confirmed removal changes nothing, even with a
// listed human's older needs-human removal in the events.
test("a status: confirmed removal changes nothing, whoever made it", async () => {
  const CONFIRMED = "status: confirmed";
  for (const actor of [LANES_APP, OWNER]) {
    const w = world({ labels: ["priority: medium"], events: [lift(OWNER), lift(actor, CONFIRMED)] });
    assert.equal(await run(w, "", { EVENT_NAME: "issues", COMMENT_ID: "", REMOVED_LABEL: CONFIRMED }), 0, actor.login);
    assert.deepEqual(w.writes, [], actor.login);
    assert.equal(w.dispatches().length, 0, actor.login);
  }
});

const liftQuiet = [
  ["an outsider's removal", { labels: [], events: [lift(STRANGER)] }],
  ["an older listed removal followed by an outsider's", { labels: [], events: [lift(OWNER), lift(STRANGER)] }],
  ["a removal of another label", { labels: [], events: [lift(OWNER, "priority: low")] }],
  ["no removal event", { labels: [], events: [] }],
  ["a status label still present", { labels: ["needs-reporter-info"], events: [lift(OWNER)] }],
  ["status: confirmed still present", { labels: ["status: confirmed"], events: [lift(OWNER)] }],
  ["another status label beside needs-decision", { labels: ["needs-owner-decision", "needs-reporter-info"], events: [lift(OWNER)] }],
  ["an outsider's removal at needs-decision", { labels: ["needs-owner-decision"], events: [lift(STRANGER)] }],
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

test("a failed dispatch after a lift from no status leaves it at needs-triage for the triage sweep", async () => {
  const w = world({ labels: ["priority: medium"], events: [lift(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runLift(w), 1);
  expectTriage(w, ["priority: medium"]);
});

test("the workflow runs on a needs-human unlabel", () => {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  assert.match(workflow, /^ {2}issues:.*\n {4}types: \[unlabeled, field_added, field_removed\]$/m);
  assert.match(workflow, /github\.event\.label\.name == 'needs-human'/);
});

// The reenter job's folded `if:`, evaluated against one event. Covers only
// what that gate uses: &&, ||, ==, !, and contains() over the issue's labels
// and, case-insensitively as GitHub does, over the comment body.
function reenterGate({ event, labels, label = null, comment = null, sender = null, action = event === "issues" ? "unlabeled" : "created", fieldId = null, author = OWNER.id }) {
  const workflow = readFileSync(new URL("../../workflows/intake-reenter.yml", import.meta.url), "utf8");
  const block = /\n {2}reenter:\n(?: {4}#.*\n)*(?: {4}name: .*\n)? {4}if: >-\n((?: {6}.*\n)+)/.exec(workflow)?.[1];
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
    "github.event.comment.user.id": comment?.id ?? null,
    "github.event.action": action,
    "github.event.issue_field.id": fieldId,
    "github.event.issue.pull_request": null,
    "github.event.issue.state": "open",
    "github.event.issue.user.id": author,
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
  for (const status of ["needs-owner-decision", "status: confirmed"]) {
    assert.equal(comment([status], DECISION), true, status);
    assert.equal(comment([status], "  \n**Decision recorded.**\n\nOption 1."), true, `${status}, leading whitespace`);
    assert.equal(comment([status], "Thanks, looking."), false, status);
    assert.equal(comment([status], "Decision recorded."), false, `${status}, no bold`);
    assert.equal(comment([status, "needs-reporter-info"], "An answer."), true, `${status} beside needs-info`);
  }
  assert.equal(comment(["needs-reporter-info"], "An answer."), true);
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

test("a status: confirmed removal starts no job, a bot's or a person's", () => {
  for (const sender of ["Bot", "User"]) {
    assert.equal(reenterGate({ event: "issues", label: "status: confirmed", labels: ["priority: medium"], sender }), false, sender);
  }
});

// A field-only needs-reporter-info hold has no label the gate can read, so the
// issue author's comment starts the job; anyone else's plain comment does not.
test("the issue author's comment starts the job with no status label", () => {
  const reply = (id) => reenterGate({ event: "issue_comment", comment: { type: "User", body: "Here is the log.", id }, labels: [], author: AUTHOR.id });
  assert.equal(reply(AUTHOR.id), true);
  assert.equal(reply(STRANGER.id), false);
  assert.equal(reenterGate({ event: "issue_comment", comment: { type: "Bot", body: "Log.", id: AUTHOR.id }, labels: [], author: AUTHOR.id }), false, "a bot account");
});

// A Work status field change: a listed human releasing a hold that exists
// only on the field (no status label) re-enters intake once. The field events
// are the GraphQL ones; the run reads the live models.issue-status from this
// checkout.
const runField = (w, action, sender = OWNER) =>
  run(w, "", { EVENT_NAME: "issues", EVENT_ACTION: action, SENDER_ID: String(sender.id), COMMENT_ID: "", BASE_PATH: ROOT });
const heldBy = (actor = LANES_APP, value = "needs-human") => fieldNode("IssueFieldAddedEvent", actor, { value });
const changed = (actor, previousValue, newValue) => fieldNode("IssueFieldChangedEvent", actor, { previousValue, newValue });
const removed = (actor, createdAt) => fieldNode("IssueFieldRemovedEvent", actor, createdAt ? { createdAt } : {});
const fieldWrites = (w) => w.writes.filter(([, path]) => path === FIELD_WRITE);
// The release records the job token left on the issue, by their first line.
const records = (w) => w.comments().filter((c) => c.user.login === "github-actions[bot]").map((c) => c.body.split("\n")[0]);
// The record's first line names the person whose event left the hold and that event's time.
const OWNER_RELEASE = `<!-- intake-reenter:release ${OWNER.id} 2026-11-06T00:00:00Z -->`;

test("a listed human moving a field-only hold to needs-triage records the release, writes no label or field, and dispatches once", async () => {
  const w = world({ labels: ["priority: medium"], fieldNodes: [heldBy(), changed(OWNER, "needs-human", "needs-triage")] });
  assert.equal(await runField(w, "field_added"), 0);
  assert.deepEqual(w.labels(), ["priority: medium"], "no status label is written");
  assert.deepEqual(fieldWrites(w), [], "the field is already at the floor");
  assert.deepEqual(records(w), [OWNER_RELEASE]);
  expectDispatched(w);
});

test("a re-run of the same release finds its record and dispatches nothing", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await runField(w, "field_removed"), 0);
  expectDispatched(w);
  w.writes.length = 0;
  assert.equal(await runField(w, "field_removed"), 0, "the re-run walks past its own field write to the same release");
  assert.deepEqual(w.writes, [], "no record, field write or dispatch");
  assert.deepEqual(records(w), [OWNER_RELEASE]);
});

test("a removal then a needs-triage add by the same person is one release, whichever run reads it", async () => {
  const fieldNodes = [heldBy(), removed(OWNER)];
  const w = world({ labels: [], fieldNodes });
  const github = async (method, path, body) => {
    const answer = await w.github(method, path, body);
    if (method === "POST" && path.endsWith("/comments")) fieldNodes.push(fieldNode("IssueFieldAddedEvent", OWNER, { value: "needs-triage", createdAt: "2026-11-06T00:05:00Z" }));
    return answer;
  };
  assert.equal(await runField({ ...w, github }, "field_removed"), 0, "the add lands after the first run's record");
  assert.equal(await runField(w, "field_added"), 0, "the queued run for the add finds the removal's record");
  expectDispatched(w);
  assert.deepEqual(records(w), [OWNER_RELEASE]);
});

test("a later, separate release of a new hold dispatches again", async () => {
  const fieldNodes = [heldBy(), removed(OWNER)];
  const w = world({ labels: [], fieldNodes });
  assert.equal(await runField(w, "field_removed"), 0);
  fieldNodes.push(fieldNode("IssueFieldChangedEvent", LANES_APP, { previousValue: "needs-triage", newValue: "needs-human", createdAt: "2026-11-07T00:00:00Z" }));
  fieldNodes.push(removed(OWNER, "2026-11-07T01:00:00Z"));
  assert.equal(await runField(w, "field_removed"), 0);
  assert.equal(w.dispatches().length, 2, "one dispatch per release");
  assert.deepEqual(records(w), [OWNER_RELEASE, `<!-- intake-reenter:release ${OWNER.id} 2026-11-07T01:00:00Z -->`]);
  assert.deepEqual(w.labels(), []);
});

test("a release on an issue that still carries an earlier needs-triage label dispatches once", async () => {
  const w = world({ labels: ["needs-triage"], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await runField(w, "field_removed"), 0);
  expectDispatched(w);
});

test("a listed human clearing a field-only hold records it, sets the field to needs-triage, then dispatches once", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await runField(w, "field_removed"), 0);
  assert.deepEqual(w.labels(), []);
  expectDispatched(w);
  assert.deepEqual(fieldWrites(w).map(([method, , body]) => [method, body]), [["POST", { issue_field_values: [{ field_id: 48484079, value: "needs-triage" }] }]]);
  const order = w.writes.map(([method, path]) => `${method} ${path.split("/").at(-1)}`);
  assert.deepEqual(order, ["POST comments", "POST issue-field-values", "POST dispatches"], "record, field, then dispatch");
  const body = w.comments().at(-1).body;
  assert.ok(!body.includes("**Decision recorded.**"), "the record is no decision");
});

test("a person's hold set after a field release's record keeps the field, takes the record back, and dispatches nothing", async () => {
  const fieldNodes = [heldBy(), removed(OWNER)];
  const w = world({ labels: [], fieldNodes });
  const github = async (method, path, body) => {
    const answer = await w.github(method, path, body);
    if (method === "POST" && path.endsWith("/comments")) fieldNodes.push(heldBy(OWNER, "needs-owner-decision"));
    return answer;
  };
  assert.equal(await runField({ ...w, github }, "field_removed"), 0);
  assert.equal(w.field(), "needs-owner-decision", "the person's later hold stands");
  assert.deepEqual(fieldWrites(w), [], "no field write");
  assert.deepEqual(records(w), [], "the record comes back off");
  assert.deepEqual(w.labels(), []);
  assert.deepEqual(w.dispatches(), []);
});

test("every hold state released by a listed human re-enters", async () => {
  for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"]) {
    const w = world({ labels: [], fieldNodes: [heldBy(LANES_APP, hold), changed(OWNER, hold, "needs-triage")] });
    assert.equal(await runField(w, "field_added"), 0, hold);
    assert.equal(w.dispatches().length, 1, hold);
  }
});

test("a failed dispatch after a field release takes the record back, writes no status label, and a re-run dispatches once", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)], fail: `POST ${DISPATCH}` });
  assert.equal(await runField(w, "field_removed"), 1);
  assert.deepEqual(records(w), [], "the record comes back off");
  assert.deepEqual(w.labels(), [], "no status label");
  assert.equal(w.field(), "needs-triage", "the field stays as written");
  assert.equal(await runField(w, "field_removed"), 0, "the re-run walks past its own field write");
  assert.deepEqual(records(w), [OWNER_RELEASE]);
  assert.deepEqual(w.labels(), []);
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

test("a field write that fails takes the record back and fails the run, and a re-run dispatches once", async () => {
  const w = world({ labels: [], fieldNodes: [heldBy(), removed(OWNER)], fail: `POST ${FIELD_WRITE}` });
  const lines = [];
  const code = await main({
    github: w.github,
    log: (line) => lines.push(line),
    env: { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), COMMENT_ID: "", TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id), EVENT_NAME: "issues", EVENT_ACTION: "field_removed", SENDER_ID: String(OWNER.id), BASE_PATH: ROOT },
  });
  assert.equal(code, 1);
  assert.equal(w.dispatches().length, 0);
  assert.ok(lines.some((line) => line.startsWith("::error title=intake-reenter::#42's Work status field was not set")), lines.join("\n"));
  assert.deepEqual(records(w), [], "the record comes back off");
  assert.deepEqual(w.labels(), []);
  assert.equal(await runField(w, "field_removed"), 0);
  expectDispatched(w);
  assert.equal(w.field(), "needs-triage");
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
  ["a status label still on the issue", { labels: ["needs-owner-decision"], fieldNodes: [heldBy(), removed(OWNER)] }, "field_removed", OWNER],
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

// The unlabel path reads statusEvents, where the person's field removal of
// needs-human is their removal; it writes the field and adds no claim label.
test("a field change with no action reads as a label removal, whose history holds the person's field removal", async () => {
  const w = world({ labels: [], events: [], fieldNodes: [heldBy(), removed(OWNER)] });
  assert.equal(await run(w, "", { EVENT_NAME: "issues", COMMENT_ID: "", SENDER_ID: String(OWNER.id), BASE_PATH: ROOT }), 0);
  expectTriage(w, []);
  expectDispatched(w);
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

// The two holds under their new names, as the live rename leaves them: the
// issue carries `needs-owner-decision` or `needs-reporter-info`, and the same
// answers release it, by the name the issue carries.
const deletedLabels = (w) => w.writes.filter(([method]) => method === "DELETE").map(([, path]) => decodeURIComponent(path.slice(path.lastIndexOf("/") + 1)));

test("a listed human's decision removes needs-owner-decision and sends the issue back to triage", async () => {
  const w = world({ labels: ["needs-owner-decision", "priority: medium"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  expectTriage(w, ["priority: medium"]);
  assert.deepEqual(deletedLabels(w), ["needs-owner-decision"]);
  expectDispatched(w);
});

test("a reply from the author or a listed human removes needs-reporter-info; a stranger's changes nothing", async () => {
  for (const user of [AUTHOR, OWNER]) {
    const w = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user, body: "Here is the log." }] });
    assert.equal(await run(w, 1), 0, user.login);
    expectTriage(w, [], user.login);
    assert.deepEqual(deletedLabels(w), ["needs-reporter-info"], user.login);
  }
  const stranger = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: STRANGER, body: "Me too." }] });
  assert.equal(await run(stranger, 1), 0);
  assert.deepEqual(stranger.writes, []);
});

test("a decision beside needs-human changes nothing under the new name", async () => {
  const labels = ["needs-human", "needs-owner-decision"];
  const w = world({ labels, comments: [{ id: 1, user: OWNER, body: DECISION }] });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), labels);
  assert.deepEqual(w.writes, []);
});

test("a listed human lifting needs-human re-enters needs-owner-decision and leaves needs-reporter-info parked", async () => {
  const w = world({ labels: ["needs-owner-decision"], events: [lift(OWNER)] });
  assert.equal(await runLift(w), 0);
  expectTriage(w, []);
  assert.deepEqual(deletedLabels(w), ["needs-owner-decision"]);
  expectDispatched(w);
  const parked = world({ labels: ["needs-reporter-info"], events: [lift(OWNER)] });
  assert.equal(await runLift(parked), 0);
  assert.deepEqual(parked.writes, []);
});

test("a lift whose needs-owner-decision another run already took dispatches nothing", async () => {
  const w = world({ labels: ["needs-owner-decision"], events: [lift(OWNER)], gone: ["needs-owner-decision"] });
  assert.equal(await runLift(w), 0);
  assert.equal(w.dispatches().length, 0);
  assert.deepEqual(deletedLabels(w), ["needs-owner-decision"]);
});

for (const [hold, body] of [
  ["needs-owner-decision", DECISION],
  ["needs-reporter-info", "Answer."],
]) {
  test(`a failed dispatch puts ${hold} back under that name and sets its Work status back`, async () => {
    const w = world({ labels: [hold], comments: [{ id: 1, user: OWNER, body }], fail: `POST ${DISPATCH}` });
    assert.equal(await run(w, 1), 1);
    assert.deepEqual(w.labels(), [hold]);
    assert.equal(w.field(), hold);
  });
}

test("a field at the same hold still removes the label the issue carries, not the state's first label", async () => {
  const w = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] });
  assert.equal(await runWithField(w, { [NUMBER]: { state: "needs-reporter-info" } }), 0);
  expectTriage(w, []);
  assert.deepEqual(deletedLabels(w), ["needs-reporter-info"]);
});

test("a reply to needs-reporter-info leaves a person's field-only hold", async () => {
  for (const state of ["needs-human", "needs-owner-decision", "needs-spec"]) {
    const w = world({ labels: ["needs-reporter-info"], author: AUTHOR, comments: [{ id: 1, user: AUTHOR, body: "Here is the log." }] });
    assert.equal(await runWithField(w, { [NUMBER]: { state } }), 0, state);
    assert.deepEqual(w.writes, [], state);
  }
});

test("a field release changes nothing while a renamed hold label stays on the issue", async () => {
  for (const hold of ["needs-owner-decision", "needs-reporter-info"]) {
    const w = world({ labels: [hold], fieldNodes: [heldBy(), removed(OWNER)] });
    assert.equal(await runField(w, "field_removed"), 0, hold);
    assert.deepEqual(w.writes, [], hold);
  }
});

// /planning:wayfind and /work-items:decompose route an issue with a routing
// label (the binding's container label, default `work-map`, or a label
// starting with its wayfind prefix, default `wayfind:`), and intake skips it
// (check-born-triaged.mjs), so no answer, lift or release sends it to triage.
const runRouted = (w, env, { log = () => {}, routing } = {}) =>
  main({
    github: w.github,
    log,
    routing,
    env: { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, ISSUE_NUMBER: String(NUMBER), TRUSTED_ACTORS_PATH: TRUSTED, LANES_APP_ID: String(LANES_APP.id), BASE_PATH: ROOT, ...env },
  });

test("an answer, a needs-human lift or a field release on a routing-labeled issue removes no label, writes no status and dispatches nothing", async () => {
  for (const routed of ["wayfind: design", "work-map"]) {
    const lines = [];
    const runs = [
      [world({ labels: ["needs-owner-decision", routed], comments: [{ id: 1, user: OWNER, body: DECISION }] }), { COMMENT_ID: "1" }],
      [world({ labels: [routed], events: [lift(OWNER)] }), { EVENT_NAME: "issues", COMMENT_ID: "" }],
      [world({ labels: [routed], fieldNodes: [heldBy(), removed(OWNER)] }), { EVENT_NAME: "issues", EVENT_ACTION: "field_removed", SENDER_ID: String(OWNER.id), COMMENT_ID: "" }],
    ];
    for (const [w, env] of runs) {
      assert.equal(await runRouted(w, env, { log: (line) => lines.push(line) }), 0, routed);
      assert.deepEqual(w.writes, [], `${routed}: no label removal, status write, record or dispatch`);
    }
    assert.deepEqual(lines, Array(3).fill(`intake-reenter: the issue carries '${routed}', a container or wayfind label, so the skill that filed it routes it; nothing changed`));
  }
});

test("a remapped routing label stops re-entry, and the default one then re-enters", async () => {
  const routing = { container: "epic", prefix: "fog:" };
  const answer = (label) => world({ labels: ["needs-owner-decision", label], comments: [{ id: 1, user: OWNER, body: DECISION }] });
  const remapped = answer("fog: storage");
  assert.equal(await runRouted(remapped, { COMMENT_ID: "1" }, { routing }), 0);
  assert.deepEqual(remapped.writes, []);
  const plain = answer("work-map");
  assert.equal(await runRouted(plain, { COMMENT_ID: "1" }, { routing }), 0);
  expectTriage(plain, ["work-map"]);
  expectDispatched(plain);
});
