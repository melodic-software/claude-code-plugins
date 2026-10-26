// Expected values come from the owner rule of 2026-10-26: a hold the lanes
// clear ends in a visible failing status, never the human-gated label, and a
// head that arms shows it passed.
import assert from "node:assert/strict";
import { test } from "node:test";

import { UNARMED_CONTEXT } from "./enable-auto-merge.mjs";
import { changes, MAX_STATUSES, main, parse } from "./post-unarmed-status.mjs";

const REPO = "melodic-software/claude-code-plugins";
const A = "a".repeat(40);
const B = "b".repeat(40);
const ENV = { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "9", GITHUB_SERVER_URL: "https://github.com" };

// `shown`: each head's statuses, newest first, as GitHub lists them.
async function run(statuses, shown = {}, { failRead = false } = {}) {
  const posts = [];
  const github = async (method, path, body) => {
    const read = /^\/repos\/melodic-software\/claude-code-plugins\/commits\/([0-9a-f]{40})\/statuses\?per_page=100$/.exec(path);
    if (method === "GET" && read) {
      if (failRead) {
        throw new Error("GET statuses failed with status 502");
      }
      return shown[read[1]] ?? [];
    }
    assert.equal(method, "POST");
    posts.push({ path, body });
    return {};
  };
  const log = console.log;
  console.log = () => {};
  try {
    const code = await main({ env: { ...ENV, STATUSES: JSON.stringify(statuses) }, github });
    return { code, posts };
  } finally {
    console.log = log;
  }
}

test("a failing status is posted on its head with the run as its target", async () => {
  const { code, posts } = await run([{ sha: A, state: "failure", description: "pr-merge's gate refuses its verifier verdict (verify:missing)" }]);
  assert.equal(code, 0);
  assert.deepEqual(posts, [
    {
      path: `/repos/${REPO}/statuses/${A}`,
      body: {
        state: "failure",
        context: UNARMED_CONTEXT,
        description: "pr-merge's gate refuses its verifier verdict (verify:missing)",
        target_url: `https://github.com/${REPO}/actions/runs/9`,
      },
    },
  ]);
});

test("an unchanged status writes nothing, and a success only replaces a status already shown", async () => {
  const failing = { context: UNARMED_CONTEXT, state: "failure", description: "x" };
  const { posts } = await run(
    [
      { sha: A, state: "failure", description: "x" },
      { sha: B, state: "success", description: "armed for native auto-merge" },
    ],
    { [A]: [failing] },
  );
  assert.deepEqual(posts, []);
  const cleared = await run([{ sha: A, state: "success", description: "armed for native auto-merge" }], { [A]: [{ context: "other", state: "success" }, failing] });
  assert.deepEqual(
    cleared.posts.map(({ body }) => body.state),
    ["success"],
  );
});

test("only well-formed statuses are read, one per head and at most MAX_STATUSES", () => {
  assert.deepEqual(parse("not json"), []);
  assert.deepEqual(parse(JSON.stringify({ sha: A })), []);
  assert.deepEqual(
    parse(
      JSON.stringify([
        { sha: "A".repeat(40), state: "failure", description: "x" },
        { sha: A, state: "pending", description: "x" },
        { sha: A, state: "failure", description: 7 },
        { sha: A, state: "failure", description: "first" },
        { sha: A, state: "success", description: "y".repeat(200) },
      ]),
    ),
    [{ sha: A, state: "success", description: "y".repeat(140) }],
  );
  const many = Array.from({ length: MAX_STATUSES + 5 }, (_, index) => ({ sha: index.toString(16).padStart(40, "0"), state: "failure", description: "x" }));
  assert.equal(parse(JSON.stringify(many)).length, MAX_STATUSES);
  assert.equal(changes({ state: "success", description: "x" }, undefined), false);
});

test("a read that fails writes nothing for that head and fails the step", async () => {
  const { code, posts } = await run([{ sha: A, state: "failure", description: "x" }], {}, { failRead: true });
  assert.equal(code, 1);
  assert.deepEqual(posts, []);
});
