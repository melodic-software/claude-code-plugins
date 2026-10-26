// comment.mjs: one comment per merged pull request, edited in place on a
// re-run, and no write without a pull request or a marked body.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { main, ownComment } from "./comment.mjs";
import { MARKER } from "./report.mjs";

const BOT = { login: "github-actions[bot]" };
const BODY = `${MARKER}\n## Post-merge mutation testing\n`;

// A fake client over a list of comments, recording every call.
function fakeGitHub(comments = []) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET") {
      const page = Number(new URL(path, "https://x").searchParams.get("page"));
      return comments.slice((page - 1) * 100, page * 100);
    }
    return {};
  };
  return { github, calls, writes: () => calls.filter((c) => c.method !== "GET") };
}

function run(env, github) {
  const dir = mkdtempSync(join(tmpdir(), "mutation-comment-"));
  const path = join(dir, "comment.md");
  if (env.body !== undefined) writeFileSync(path, env.body);
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  return main({ PULL: "42", REPOSITORY: "o/r", COMMENT_PATH: path, ...env }, { github })
    .then((code) => ({ code, lines }))
    .finally(() => {
      console.log = original;
    });
}

test("a first run posts one comment on the pull request", async () => {
  const api = fakeGitHub([{ id: 1, user: { login: "someone" }, body: "hi" }]);
  const out = await run({ body: BODY }, api.github);
  assert.equal(out.code, 0);
  assert.deepEqual(api.writes(), [{ method: "POST", path: "/repos/o/r/issues/42/comments", body: { body: BODY } }]);
});

test("a re-run edits the lane's comment instead of adding another", async () => {
  const api = fakeGitHub([{ id: 5, user: BOT, body: `${MARKER}\nold report\n` }]);
  const out = await run({ body: BODY }, api.github);
  assert.equal(out.code, 0);
  assert.deepEqual(api.writes(), [{ method: "PATCH", path: "/repos/o/r/issues/comments/5", body: { body: BODY } }]);
});

test("a re-run with the same body writes nothing", async () => {
  const api = fakeGitHub([{ id: 5, user: BOT, body: BODY }]);
  assert.equal((await run({ body: BODY }, api.github)).code, 0);
  assert.deepEqual(api.writes(), []);
});

test("the lane's comment is found past the first page, and a person's quoted marker is not it", async () => {
  const filler = Array.from({ length: 100 }, (_, i) => ({ id: 100 + i, user: { login: "someone" }, body: i === 0 ? `${MARKER}\nquoted` : "x" }));
  const api = fakeGitHub([...filler, { id: 9, user: BOT, body: `${MARKER}\nold` }]);
  assert.equal((await ownComment({ github: api.github, repository: "o/r", pull: "42" })).id, 9);
  assert.deepEqual(
    api.calls.map((c) => c.path),
    ["/repos/o/r/issues/42/comments?per_page=100&page=1", "/repos/o/r/issues/42/comments?per_page=100&page=2"],
  );
});

test("no pull request makes no call at all", async () => {
  for (const PULL of ["", undefined, "0", "4x"]) {
    const api = fakeGitHub();
    const out = await run({ PULL, body: BODY }, api.github);
    assert.equal(out.code, 0);
    assert.deepEqual(api.calls, [], String(PULL));
  }
});

test("a missing or unmarked body writes nothing and fails the step", async () => {
  for (const body of [undefined, "## Post-merge mutation testing\n"]) {
    const api = fakeGitHub();
    const out = await run({ body }, api.github);
    assert.equal(out.code, 1);
    assert.deepEqual(api.calls, []);
  }
});

test("a failed comment read writes nothing and fails the step", async () => {
  const calls = [];
  const github = async (method) => {
    calls.push(method);
    throw Object.assign(new Error("boom"), { status: 502 });
  };
  const out = await run({ body: BODY }, github);
  assert.equal(out.code, 1);
  assert.deepEqual(calls, ["GET"]);
  assert.ok(out.lines.some((line) => line.startsWith("::error::could not post")));
});
