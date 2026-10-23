import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { keepThreads, threadAuthors, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";
import { main, noteComments, notePath, postNotes, readVerdict } from "./verify-notes.mjs";

const APP = 337595936;
const ACTIONS_BOT = 41898282;
const HEAD = "a".repeat(40);
const NAME = `pr-verify-42-${HEAD}-fail`;
const FILES = ["plugins/x/a.py", "plugins/x/b.md"];
const verdictText = (extra = {}) =>
  JSON.stringify({ verdict: "fail", pr: 42, head_sha: HEAD, summary: "Spec item 2 is unmet.", notes: ["`plugins/x/a.py:12` returns early.", "No test covers it."], ...extra });

function fakeApi({ pull = {}, reviewComments = [] } = {}) {
  const created = [];
  return {
    created,
    getPull: async () => ({ state: "open", head: { sha: HEAD }, user: { id: APP }, ...pull }),
    listReviewComments: async () => reviewComments,
    listPullFiles: async () => FILES.map((filename) => ({ filename })),
    createReviewComment: async (pr, fields) => created.push({ pr, ...fields }),
  };
}

test("a note's leading path, with backticks, quotes or a :line, names a changed file", () => {
  assert.equal(notePath("`plugins/x/a.py:12` returns early", FILES), "plugins/x/a.py");
  assert.equal(notePath("plugins/x/b.md: wording", FILES), "plugins/x/b.md");
  assert.equal(notePath("plugins/x/a.py:3-9, the loop", FILES), "plugins/x/a.py");
  assert.equal(notePath("plugins/y/c.py is untested", FILES), null);
  assert.equal(notePath("No test covers it.", FILES), null);
});

test("notes go on their files, and the summary and loose notes on the first named file", () => {
  const comments = noteComments({
    head: HEAD,
    summary: "Spec item 2 is unmet.",
    notes: ["plugins/x/b.md: wording", "No test covers it.", "`plugins/x/a.py:12` returns early."],
    files: FILES,
  });
  assert.deepEqual(
    comments.map((c) => c.path),
    ["plugins/x/a.py", "plugins/x/b.md"],
  );
  for (const { body } of comments) {
    assert.equal(body.split("\n")[0], VERIFY_NOTE_MARKER);
  }
  assert.match(comments[0].body, /```text\nSummary: Spec item 2 is unmet\.\n- No test covers it\.\n- `plugins\/x\/a\.py:12` returns early\.\n```$/);
  assert.match(comments[1].body, /```text\n- plugins\/x\/b\.md: wording\n```$/);
});

test("with no note naming a changed file, everything goes on the first changed file", () => {
  const comments = noteComments({ head: HEAD, summary: "s", notes: ["n"], files: FILES });
  assert.deepEqual(
    comments.map((c) => c.path),
    ["plugins/x/a.py"],
  );
  assert.deepEqual(noteComments({ head: HEAD, summary: "s", notes: [], files: [] }), []);
});

test("model text stays inside its fence", () => {
  const [{ body }] = noteComments({ head: HEAD, summary: "a```b\u001b", notes: [], files: FILES });
  assert.match(body, /```text\nSummary: a'''b\?\n```$/);
});

test("the verdict must be the fail its artifact name names", () => {
  assert.deepEqual(readVerdict(NAME, verdictText()), {
    pr: 42,
    head: HEAD,
    summary: "Spec item 2 is unmet.",
    notes: ["`plugins/x/a.py:12` returns early.", "No test covers it."],
  });
  for (const [name, text] of [
    [`pr-verify-42-${HEAD}-pass`, verdictText()],
    [NAME, verdictText({ verdict: "pass-notes" })],
    [NAME, verdictText({ pr: 43 })],
    [NAME, verdictText({ head_sha: "b".repeat(40) })],
    [NAME, verdictText({ notes: [1] })],
    // 79b4cc554b80dca6 is the first 16 hex digits of `printf %s feat/x | sha256sum`.
    [`${NAME}-79b4cc554b80dca6`, verdictText({ head_ref: "feat/other" })],
    [`${NAME}-79b4cc554b80dca6`, verdictText()],
  ]) {
    assert.throws(() => readVerdict(name, text), name);
  }
  assert.equal(readVerdict(`${NAME}-79b4cc554b80dca6`, verdictText({ head_ref: "feat/x" })).pr, 42);
  // a27da2afd9962004 and 8c8a071ad0e51f5e: `printf %s feat/a+b | sha256sum` and the same for fix/é.
  assert.equal(readVerdict(`${NAME}-a27da2afd9962004`, verdictText({ head_ref: "feat/a+b" })).pr, 42);
  assert.equal(readVerdict(`${NAME}-8c8a071ad0e51f5e`, verdictText({ head_ref: "fix/\u00e9" })).pr, 42);
});

test("a name that carries issue numbers must carry the ones the verdict records", () => {
  const issues = (...numbers) => numbers.map((number) => ({ number }));
  const digest = "79b4cc554b80dca6"; // feat/x, as above
  assert.equal(readVerdict(`${NAME}-i7`, verdictText({ linked_issues: issues(7) })).pr, 42);
  assert.equal(readVerdict(`${NAME}-i12.7`, verdictText({ linked_issues: issues(7, 12) })).pr, 42);
  assert.equal(readVerdict(`${NAME}-${digest}-i7`, verdictText({ head_ref: "feat/x", linked_issues: issues(7) })).pr, 42);
  for (const [name, recorded] of [
    [`${NAME}-i7`, issues(8)],
    [`${NAME}-i7`, issues(7, 8)],
    [`${NAME}-i7.8`, issues(7)],
    [`${NAME}-i7`, issues()],
    [`${NAME}-i7`, undefined],
    [`${NAME}-i07`, issues(7)],
    [`${NAME}-i`, issues()],
    [`${NAME}-i7.`, issues(7)],
    [`${NAME}-i${Array(11).fill(7).join(".")}`, issues(7)],
    [`${NAME}-i7-${digest}`, issues(7)],
  ]) {
    assert.throws(() => readVerdict(name, verdictText({ head_ref: "feat/x", linked_issues: recorded })), name);
  }
});

test("the notes are posted as file comments on the judged head, once", async () => {
  const api = fakeApi();
  const verdict = readVerdict(NAME, verdictText());
  assert.equal(await postNotes({ api, verdict, log: () => {} }), true);
  assert.deepEqual(
    api.created.map(({ pr, path, commit_id, subject_type }) => ({ pr, path, commit_id, subject_type })),
    [{ pr: 42, path: "plugins/x/a.py", commit_id: HEAD, subject_type: "file" }],
  );
  // A re-run finds its own note at that head and posts nothing.
  const again = fakeApi({ reviewComments: [{ user: { id: ACTIONS_BOT }, commit_id: HEAD, path: api.created[0].path, body: api.created[0].body }] });
  assert.equal(await postNotes({ api: again, verdict, log: () => {} }), true);
  assert.deepEqual(again.created, []);
});

test("a retry after a partial post posts only the comments still missing", async () => {
  const verdict = readVerdict(NAME, verdictText({ notes: ["plugins/x/a.py: one", "plugins/x/b.md: two"] }));
  const full = fakeApi();
  await postNotes({ api: full, verdict, log: () => {} });
  assert.deepEqual(
    full.created.map((c) => c.path),
    FILES,
  );
  // The second POST failed: only the first file's comment is on the PR.
  const [first] = full.created;
  const retry = fakeApi({ reviewComments: [{ user: { id: ACTIONS_BOT }, commit_id: HEAD, path: first.path, body: first.body }] });
  assert.equal(await postNotes({ api: retry, verdict, log: () => {} }), true);
  assert.deepEqual(
    retry.created.map((c) => c.path),
    ["plugins/x/b.md"],
  );
});

test("a posted note opens a thread address-feedback keeps", async () => {
  const api = fakeApi();
  await postNotes({ api, verdict: readVerdict(NAME, verdictText()), log: () => {} });
  const row = { id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 10, path: api.created[0].path, line: null, body: api.created[0].body };
  assert.deepEqual(threadAuthors([{ authorId: ACTIONS_BOT, body: row.body }], { reviewerId: 209825114, appId: APP }), [{ author: "verifier" }]);
  const kept = keepThreads({
    threads: [{ id: "PRRT_1", isResolved: false, comments: { totalCount: 1, nodes: [{ databaseId: 100 }] } }],
    reviewComments: [row],
    reviews: [{ id: 10, user: { id: ACTIONS_BOT }, commit_id: HEAD }],
    heads: new Set([HEAD]),
    reviewerId: 209825114,
    appId: APP,
  });
  assert.equal(kept.length, 1);
});

test("nothing is posted on a moved head or a closed PR", async () => {
  const verdict = readVerdict(NAME, verdictText());
  for (const pull of [{ head: { sha: "b".repeat(40) } }, { state: "closed" }]) {
    const api = fakeApi({ pull });
    assert.equal(await postNotes({ api, verdict, log: () => {} }), false);
    assert.deepEqual(api.created, []);
  }
});

test("an adopted PR the lanes App did not open gets the notes too, so its author sees why it is refused", async () => {
  const api = fakeApi({ pull: { user: { id: 153232337 } } });
  assert.equal(await postNotes({ api, verdict: readVerdict(NAME, verdictText()), log: () => {} }), true);
  assert.equal(api.created.length, 1);
});

test("main names the PR and head only once the notes are on the PR", async () => {
  const dir = mkdtempSync(join(tmpdir(), "verify-notes-"));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    ARTIFACT_NAME: NAME,
    VERDICT_FILE: join(dir, "verdict.json"),
  };
  writeFileSync(env.VERDICT_FILE, verdictText());
  writeFileSync(env.GITHUB_OUTPUT, "");
  await main(env, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `pr-number=42\nhead-sha=${HEAD}\n`);
  writeFileSync(env.GITHUB_OUTPUT, "");
  await main(env, { api: fakeApi({ pull: { state: "closed" } }), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "");
});
