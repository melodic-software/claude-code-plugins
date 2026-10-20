// Expected values come from the requested behavior for answered issues: a
// listed human's `**Decision recorded.**` first line on a
// `status: needs-decision` issue, or the author's or a listed human's reply
// on a `status: needs-info` issue, removes that status label (and
// `needs-human` for a decision) and adds `needs-triage`; it dispatches
// intake-triage.yml once with the issue number only when the issue's author is
// one intake admits on open (a listed human or the lanes App). Anything else
// changes nothing, and `agent-ready` is never added.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./reenter.mjs";

const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton", type: "User" };
const STRANGER = { id: 5005, login: "someone", type: "User" };
const AUTHOR = { id: 6006, login: "reporter", type: "User" };
const LISTED_BOT = { id: 209825114, login: "claude[bot]", type: "Bot" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]", type: "Bot" };
const NUMBER = 42;
const DECISION = "**Decision recorded.**\n\nOption 1.";

const dir = mkdtempSync(join(tmpdir(), "intake-reenter-"));
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
function world({ labels, author = OWNER, state = "open", pullRequest = false, comments, editors = {}, gone = [], fail = null }) {
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
    if (method === "GET" && path.startsWith(`${base}/comments?`)) return path.endsWith("page=1") ? shaped : [];
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
    labels: ["status: needs-decision", "needs-human", "priority: medium"],
    comments: [{ id: 1, user: OWNER, body: DECISION }],
  });
  assert.equal(await run(w, 1), 0);
  assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
  expectDispatched(w);
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
  const w = world({ labels: ["status: needs-decision", "needs-human"], author: AUTHOR, comments: [{ id: 1, user: OWNER, body: DECISION }] });
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
    labels: ["status: needs-decision", "needs-human"],
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

const DISPATCH = `/repos/${REPO}/actions/workflows/intake-triage.yml/dispatches`;
const failures = [
  ["adding needs-triage", `POST /repos/${REPO}/issues/${NUMBER}/labels`],
  ["removing needs-human", `DELETE /repos/${REPO}/issues/${NUMBER}/labels/needs-human`],
  ["the dispatch", `POST ${DISPATCH}`],
];

for (const [name, fail] of failures) {
  test(`a failed call to ${name} after the claim restores the labels, and a re-run dispatches once`, async () => {
    const before = ["needs-human", "priority: medium", "status: needs-decision"];
    const w = world({ labels: before, comments: [{ id: 1, user: OWNER, body: DECISION }], fail });
    assert.equal(await run(w, 1), 1);
    assert.deepEqual(w.labels(), before);
    assert.equal(w.dispatches().length, name === "the dispatch" ? 1 : 0);
    assert.equal(await run(w, 1), 0);
    assert.deepEqual(w.labels(), ["needs-triage", "priority: medium"]);
    assert.equal(w.dispatches().length, name === "the dispatch" ? 2 : 1);
  });
}

test("a failed dispatch keeps a needs-triage label the issue already had", async () => {
  const w = world({ labels: ["status: needs-info", "needs-triage"], comments: [{ id: 1, user: OWNER, body: "Answer." }], fail: `POST ${DISPATCH}` });
  assert.equal(await run(w, 1), 1);
  assert.deepEqual(w.labels(), ["needs-triage", "status: needs-info"]);
});

test("never adds agent-ready", async () => {
  const w = world({ labels: ["status: needs-decision", "needs-human"], comments: [{ id: 1, user: OWNER, body: DECISION }] });
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
