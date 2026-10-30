// upsert-comment.mjs: one marked comment per pull request, edited in place on
// a re-run, found only among the bot's own comments.
import assert from "node:assert/strict";
import { test } from "node:test";

import { ownComment, upsert } from "./upsert-comment.mjs";

const BOT = { login: "github-actions[bot]" };
const MARKER = "<!-- lane-run-report activity=read/fix-ci run=7 -->";
const BODY = `${MARKER}\n## Lane run report\n`;
const args = (extra = {}) => ({ repository: "o/r", pull: "42", marker: MARKER, ...extra });

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

test("a first post adds one comment", async () => {
  const api = fakeGitHub([{ id: 1, user: { login: "someone" }, body: "hi" }]);
  assert.equal(await upsert({ github: api.github, ...args({ body: BODY }) }), "posted");
  assert.deepEqual(api.writes(), [{ method: "POST", path: "/repos/o/r/issues/42/comments", body: { body: BODY } }]);
});

test("a re-run edits the comment its marker names", async () => {
  const api = fakeGitHub([{ id: 5, user: BOT, body: `${MARKER}\nold report\n` }]);
  assert.equal(await upsert({ github: api.github, ...args({ body: BODY }) }), "edited");
  assert.deepEqual(api.writes(), [{ method: "PATCH", path: "/repos/o/r/issues/comments/5", body: { body: BODY } }]);
});

test("an unchanged body writes nothing", async () => {
  const api = fakeGitHub([{ id: 5, user: BOT, body: BODY }]);
  assert.equal(await upsert({ github: api.github, ...args({ body: BODY }) }), "left unchanged");
  assert.deepEqual(api.writes(), []);
});

test("another run's marker, a longer marker, or a person quoting the marker is not the comment", async () => {
  const api = fakeGitHub([
    { id: 1, user: { login: "someone" }, body: `${MARKER}\nquoted` },
    { id: 2, user: BOT, body: "<!-- lane-run-report activity=read/fix-ci run=70 -->\nother run" },
    { id: 3, user: BOT, body: `x${MARKER}\nnot anchored` },
    { id: 4, user: BOT, body: MARKER },
  ]);
  assert.equal(await ownComment({ github: api.github, ...args() }), null);
  assert.equal(await upsert({ github: api.github, ...args({ body: BODY }) }), "posted");
});

test("the comment is found past the first page", async () => {
  const filler = Array.from({ length: 100 }, (_, i) => ({ id: 100 + i, user: { login: "someone" }, body: "x" }));
  const api = fakeGitHub([...filler, { id: 9, user: BOT, body: `${MARKER}\nold` }]);
  assert.equal((await ownComment({ github: api.github, ...args() })).id, 9);
  assert.deepEqual(
    api.calls.map((c) => c.path),
    ["/repos/o/r/issues/42/comments?per_page=100&page=1", "/repos/o/r/issues/42/comments?per_page=100&page=2"],
  );
});

test("a marker with a newline in it is refused before any call", async () => {
  const api = fakeGitHub();
  await assert.rejects(ownComment({ github: api.github, ...args({ marker: "<!-- a -->\n<!-- b -->" }) }));
  assert.deepEqual(api.calls, []);
});
