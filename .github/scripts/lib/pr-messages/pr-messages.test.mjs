import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { MessageReadError, MessageVoided, MessageWriteError, prMessages, sectionHeading } from "./pr-messages.mjs";
import { graphqlStore, memoryStore, PR_COMMENTS_QUERY } from "./stores.mjs";

const vectors = JSON.parse(readFileSync(new URL("./message-kinds.vectors.json", import.meta.url), "utf8"));
const kinds = JSON.parse(readFileSync(new URL("./message-kinds.json", import.meta.url), "utf8"));
const recorded = JSON.parse(readFileSync(new URL("./fixtures/pr-17708-comments.json", import.meta.url), "utf8"));

const BOT = "github-actions[bot]";
const KIND = "lane-run-report";
const KEY = { activity: "read/fix-ci" };
const MARKER = "<!-- lane-run-report activity=read/fix-ci -->";
const throwing = { [KIND]: { ...kinds[KIND], void: "throw" } };

const comment = (fields) => ({ author: BOT, body: `${MARKER}\nbody`, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: null, editor: null, isMinimized: false, ...fields });
const thread = (store, more = {}) => prMessages({ store, repo: "o/r", number: 42, ...more });

for (const v of vectors.parse) {
  test(`parse vector: ${v.name} ${v.match ? "matches" : "is not a candidate"}`, async () => {
    const store = memoryStore({ comments: [comment({ body: `${v.line}\nbody` })] });
    const got = await thread(store).read(v.kind, v.key);
    assert.equal(got !== null, v.match);
    if (v.match) assert.deepEqual(got.fields, v.key);
  });
}

for (const v of vectors.render) {
  test(`render vector: ${v.line}`, async () => {
    const store = memoryStore();
    assert.equal(await thread(store).write(v.kind, v.fields, {}, "body\n"), "posted");
    assert.equal(store.comments[0].body, `${v.line}\nbody\n`);
  });
}

for (const v of vectors.badFields) {
  test(`bad fields vector: ${v.name} is refused before any call`, async () => {
    const store = memoryStore();
    await assert.rejects(thread(store).write(v.kind, v.fields, {}, "body"), MessageWriteError);
    assert.equal(store.lists, 0);
    assert.deepEqual(store.comments, []);
  });
}

for (const v of vectors.section) {
  test(`section vector: ${v.name} renders and parses back`, async () => {
    assert.equal(sectionHeading(v.kind, v.fields), v.line);
    const store = memoryStore({ comments: [comment({ body: `${MARKER}\n## Title\n${v.line}\nline one\nline two\n` })] });
    const got = await thread(store).read(v.kind, KEY);
    assert.deepEqual(got.sections, [{ fields: v.fields, text: "line one\nline two\n" }]);
  });
}

for (const v of vectors.badSection) {
  test(`bad section vector: ${v.name} is refused`, () => {
    assert.throws(() => sectionHeading(v.kind, v.fields), MessageWriteError);
  });
}

for (const v of vectors.login) {
  test(`login vector: ${v.name} maps to ${v.login} as author and as editor`, async () => {
    const node = { fullDatabaseId: "7", body: MARKER, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: "2026-11-21T00:01:00Z", isMinimized: false, author: v.actor, editor: v.actor };
    const github = async () => ({ data: { repository: { pullRequest: { comments: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: [node] } } } } });
    const [got] = await graphqlStore(github).list({ repo: "o/r", number: 42 });
    assert.equal(got.author, v.login);
    assert.equal(got.editor, v.login);
  });
}

for (const v of vectors.trust) {
  test(`trust vector: ${v.name} is ${v.trusted ? "trusted" : "not trusted"}`, async () => {
    const store = memoryStore({ comments: [comment({ author: v.author })] });
    assert.equal((await thread(store).read(v.kind, KEY)) !== null, v.trusted);
  });
}

for (const v of vectors.void) {
  test(`void vector: ${v.name} is ${v.voided ? "voided" : "current"} under both policies`, async () => {
    const skip = memoryStore({ comments: [comment(v.comment)] });
    assert.equal((await thread(skip).read(KIND, KEY)) === null, v.voided);
    const strict = thread(memoryStore({ comments: [comment(v.comment)] }), { kinds: throwing });
    if (v.voided) await assert.rejects(strict.read(KIND, KEY), MessageVoided);
    else assert.notEqual(await strict.read(KIND, KEY), null);
  });
}

test("the kinds file declares the lane run report once, skipping voided comments", () => {
  assert.deepEqual(Object.keys(kinds), [KIND]);
  assert.equal(kinds[KIND].void, "skip");
  assert.equal(kinds[KIND].history, "sections-by-run");
});

test("one current comment per kind and key across writes, in one thread or many", async () => {
  const store = memoryStore();
  const t = thread(store);
  assert.equal(await t.write(KIND, KEY, {}, "one\n"), "posted");
  assert.equal(await t.write(KIND, KEY, {}, "two\n"), "edited");
  for (const body of ["three\n", "four\n"]) assert.equal(await thread(store).write(KIND, KEY, {}, body), "edited");
  assert.equal(await thread(store).write(KIND, KEY, {}, "four\n"), "unchanged");
  assert.deepEqual(
    store.comments.map((c) => c.body),
    [`${MARKER}\nfour\n`],
  );
  assert.equal(await thread(store).write(KIND, { activity: "read/other" }, {}, "x\n"), "posted");
  assert.equal(store.comments.length, 2);
});

test("a thread lists the comments once for a read and the write after it", async () => {
  const store = memoryStore({ comments: [comment()] });
  const t = thread(store);
  await t.read(KIND, KEY);
  assert.equal(await t.write(KIND, KEY, {}, "new\n"), "edited");
  assert.equal(store.lists, 1);
});

test("a person-edited comment is skipped for good: one fresh comment, then that one is edited", async () => {
  const store = memoryStore({ comments: [comment({ id: 1, lastEditedAt: "2026-11-21T00:05:00Z", editor: "octocat", body: `${MARKER}\nperson's text` })] });
  assert.equal(await thread(store).write(KIND, KEY, {}, "run 1\n"), "posted");
  assert.equal(await thread(store).write(KIND, KEY, {}, "run 2\n"), "edited");
  assert.equal(await thread(store).write(KIND, KEY, {}, "run 3\n"), "edited");
  assert.deepEqual(
    store.comments.map((c) => [c.id, c.body]),
    [
      [1, `${MARKER}\nperson's text`],
      [2, `${MARKER}\nrun 3\n`],
    ],
  );
});

test("under skip the newest unvoided match is current, not a voided newer one", async () => {
  const store = memoryStore({
    comments: [comment({ id: 1, body: `${MARKER}\nolder` }), comment({ id: 2, body: `${MARKER}\nnewer` }), comment({ id: 3, isMinimized: true })],
  });
  assert.equal((await thread(store).read(KIND, KEY)).id, 2);
});

test("a person's comment quoting the marker is neither read nor edited", async () => {
  const store = memoryStore({ comments: [comment({ id: 1, author: "octocat" })] });
  assert.equal(await thread(store).write(KIND, KEY, {}, "x\n"), "posted");
  assert.equal(store.comments[0].body, `${MARKER}\nbody`);
});

test("a malformed section marker in a trusted comment is a read error", async () => {
  const store = memoryStore({ comments: [comment({ body: `${MARKER}\n<!-- lane-run-report-section run=1 attempt=1 rung=7 leg=base -->\nx` })] });
  await assert.rejects(thread(store).read(KIND, KEY), MessageReadError);
});

test("a body carrying a malformed section marker is refused", async () => {
  const store = memoryStore();
  await assert.rejects(thread(store).write(KIND, KEY, {}, "<!-- lane-run-report-section run=x -->\n"), MessageWriteError);
  assert.deepEqual(store.comments, []);
});

test("a failed list is a read error that keeps GitHub's answer as its cause", async () => {
  const refusal = Object.assign(new Error("refused"), { status: 403 });
  const store = { list: async () => Promise.reject(refusal) };
  const error = await thread(store).read(KIND, KEY).catch((e) => e);
  assert.ok(error instanceof MessageReadError);
  assert.equal(error.cause, refusal);
  const write = await thread(store).write(KIND, KEY, {}, "x").catch((e) => e);
  assert.ok(write instanceof MessageReadError);
});

test("a kind whose writer it does not trust refuses to write", async () => {
  const store = memoryStore();
  const t = thread(store, { kinds: { [KIND]: { ...kinds[KIND], trusted: [] } } });
  await assert.rejects(t.write(KIND, KEY, {}, "x"), MessageWriteError);
  assert.deepEqual(store.comments, []);
});

test("an unknown kind or a kinds entry with an unknown policy is refused", async () => {
  await assert.rejects(thread(memoryStore()).read("nope", KEY), MessageReadError);
  assert.throws(() => thread(memoryStore(), { kinds: { [KIND]: { ...kinds[KIND], void: "maybe" } } }), /void/);
  assert.throws(() => thread(memoryStore(), { kinds: { [KIND]: { ...kinds[KIND], marker: "<!-- lane-run-report -->" } } }), /activity/);
});

const recordedGitHub = () => {
  const calls = [];
  const github = async (method, path, body, headers, options) => {
    calls.push({ method, path, body, options });
    return recorded;
  };
  return { github, calls };
};

test("the GraphQL store reads a recorded live answer as REST-shaped comments", async () => {
  const api = recordedGitHub();
  const comments = await graphqlStore(api.github).list({ repo: "melodic-software/claude-code-plugins", number: 17708 });
  assert.equal(comments.length, 7);
  assert.deepEqual(
    { ...comments[0], body: comments[0].body.split("\n")[0] },
    {
      id: 7052774649,
      author: BOT,
      body: "<!-- claude-lane-reviewed-head lane=claude-security-review sha=bd481d27e70ce2d696c989cc91ea045a63b81eda -->",
      createdAt: "2026-11-20T23:04:37Z",
      lastEditedAt: "2026-11-20T23:27:59Z",
      editor: BOT,
      isMinimized: false,
    },
  );
  assert.equal(comments[2].author, "melodic-automation-lanes[bot]");
  assert.equal(comments[2].editor, null);
  assert.deepEqual(api.calls.map((c) => [c.method, c.path, c.body.query, c.body.variables]), [
    ["POST", "/graphql", PR_COMMENTS_QUERY, { owner: "melodic-software", name: "claude-code-plugins", number: 17708, after: null }],
  ]);
});

test("old per-run report comments on a live pull request are never candidates and never throw", async () => {
  const t = thread(graphqlStore(recordedGitHub().github), { repo: "melodic-software/claude-code-plugins", number: 17708 });
  assert.equal(await t.read(KIND, { activity: "pr-unblock/fix-ci" }), null);
  assert.equal(await t.read(KIND, { activity: "pr-unblock/apply-patch" }), null);
});

const page = (nodes, hasNextPage, endCursor = null) => ({ data: { repository: { pullRequest: { comments: { pageInfo: { hasNextPage, endCursor }, nodes } } } } });
const node = (id) => ({ fullDatabaseId: String(id), body: "x", createdAt: "2026-11-21T00:00:00Z", lastEditedAt: null, isMinimized: false, author: { __typename: "Bot", login: "github-actions" }, editor: null });

test("the GraphQL store pages by cursor, oldest first, under one time limit", async () => {
  const seen = [];
  const github = async (method, path, body, headers, options) => {
    seen.push({ after: body.variables.after, signal: options?.signal });
    return body.variables.after === null ? page([node(1)], true, "c1") : page([node(2)], false);
  };
  const comments = await graphqlStore(github, { timeoutMs: 5000 }).list({ repo: "o/r", number: 42 });
  assert.deepEqual(
    comments.map((c) => c.id),
    [1, 2],
  );
  assert.deepEqual(
    seen.map((s) => s.after),
    [null, "c1"],
  );
  assert.ok(seen[0].signal instanceof AbortSignal);
  assert.equal(seen[0].signal, seen[1].signal);
});

test("the GraphQL store stops at the page cap and on an answer with no comment list", async () => {
  let calls = 0;
  const endless = async () => {
    calls += 1;
    return page([node(calls)], true, `c${calls}`);
  };
  await assert.rejects(thread(graphqlStore(endless)).read(KIND, KEY), MessageReadError);
  assert.equal(calls, 30);
  for (const answer of [{ data: { repository: { pullRequest: null } } }, { data: null }, page(null, false), page([{ ...node(1), fullDatabaseId: "x" }], false)]) {
    await assert.rejects(thread(graphqlStore(async () => answer)).read(KIND, KEY), MessageReadError, JSON.stringify(answer));
  }
});

test("the GraphQL store posts and edits through the REST comment endpoints", async () => {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push([method, path, body]);
    return method === "POST" ? { id: 99 } : {};
  };
  const store = graphqlStore(github);
  assert.deepEqual(await store.create({ repo: "o/r", number: 42, body: "b" }), { id: 99 });
  await store.update({ repo: "o/r", id: 99, body: "c" });
  assert.deepEqual(calls, [
    ["POST", "/repos/o/r/issues/42/comments", { body: "b" }],
    ["PATCH", "/repos/o/r/issues/comments/99", { body: "c" }],
  ]);
});
