import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { keepThreads, staleVerifyNotes, threadAuthors, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";
import { main, noteComments, notePath, postNotes, readVerdict } from "./verify-notes.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const APP = 337595936;
const ACTIONS_BOT = 41898282;
const HEAD = "a".repeat(40);
const OLD_HEAD = "c".repeat(40);
const NAME = `pr-verify-42-${HEAD}-fail`;
const FILES = ["plugins/x/a.py", "plugins/x/b.md"];
const verdictText = (extra = {}) =>
  JSON.stringify({ verdict: "fail", pr: 42, head_sha: HEAD, summary: "Spec item 2 is unmet.", notes: ["`plugins/x/a.py:12` returns early.", "No test covers it."], ...extra });

// Each write lands in `created` (review comments) or `writes` (the PR's own
// comments and labels), so a test sees every change a run makes.
function fakeApi({ pull = {}, reviewComments = [], issueComments = [], labels = [], queued = false, dequeue } = {}) {
  const created = [];
  const writes = [];
  return {
    created,
    writes,
    getPull: async () => ({ state: "open", head: { sha: HEAD }, user: { id: APP }, ...pull }),
    listReviewComments: async () => reviewComments,
    listPullFiles: async () => FILES.map((filename) => ({ filename })),
    createReviewComment: async (pr, fields) => created.push({ pr, ...fields }),
    listIssueComments: async () => issueComments,
    createIssueComment: async (pr, body) => writes.push({ op: "comment", pr, body }),
    updateIssueComment: async (id, body) => writes.push({ op: "update", id, body }),
    listLabels: async () => labels.map((name) => ({ name })),
    addLabels: async (pr, names) => writes.push({ op: "label", pr, names }),
    removeLabel: async (pr, name) => writes.push({ op: "unlabel", pr, name }),
    readQueueEntry: async () => ({ id: "PR_node42", queued }),
    dequeuePull: dequeue ?? (async (id) => writes.push({ op: "dequeue", id })),
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
    verdict: "fail",
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
  assert.equal(readVerdict(`${NAME}-i7.12`, verdictText({ linked_issues: issues(12, 7) })).pr, 42);
  assert.equal(readVerdict(`${NAME}-${digest}-i7`, verdictText({ head_ref: "feat/x", linked_issues: issues(7) })).pr, 42);
  for (const [name, recorded] of [
    [`${NAME}-i7`, issues(8)],
    [`${NAME}-i7`, issues(7, 8)],
    [`${NAME}-i7.8`, issues(7)],
    // One verdict has one name: issues ascending, each once.
    [`${NAME}-i12.7`, issues(7, 12)],
    [`${NAME}-i7.7`, issues(7)],
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
  assert.equal(await postNotes({ api, verdict, appId: APP, log: () => {} }), true);
  assert.deepEqual(
    api.created.map(({ pr, path, commit_id, subject_type }) => ({ pr, path, commit_id, subject_type })),
    [{ pr: 42, path: "plugins/x/a.py", commit_id: HEAD, subject_type: "file" }],
  );
  // A re-run finds its own note at that head and posts nothing.
  const again = fakeApi({ reviewComments: [{ user: { id: ACTIONS_BOT }, commit_id: HEAD, path: api.created[0].path, body: api.created[0].body }] });
  assert.equal(await postNotes({ api: again, verdict, appId: APP, log: () => {} }), true);
  assert.deepEqual(again.created, []);
});

test("a retry after a partial post posts only the comments still missing", async () => {
  const verdict = readVerdict(NAME, verdictText({ notes: ["plugins/x/a.py: one", "plugins/x/b.md: two"] }));
  const full = fakeApi();
  await postNotes({ api: full, verdict, appId: APP, log: () => {} });
  assert.deepEqual(
    full.created.map((c) => c.path),
    FILES,
  );
  // The second POST failed: only the first file's comment is on the PR.
  const [first] = full.created;
  const retry = fakeApi({ reviewComments: [{ user: { id: ACTIONS_BOT }, commit_id: HEAD, path: first.path, body: first.body }] });
  assert.equal(await postNotes({ api: retry, verdict, appId: APP, log: () => {} }), true);
  assert.deepEqual(
    retry.created.map((c) => c.path),
    ["plugins/x/b.md"],
  );
});

test("a posted note opens a thread address-feedback keeps", async () => {
  const api = fakeApi();
  await postNotes({ api, verdict: readVerdict(NAME, verdictText()), appId: APP, log: () => {} });
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
    assert.equal(await postNotes({ api, verdict, appId: APP, log: () => {} }), false);
    assert.deepEqual(api.created, []);
  }
});

test("a lanes App PR's fail opens review threads, adds no label and posts no PR comment", async () => {
  const api = fakeApi();
  assert.equal(await postNotes({ api, verdict: readVerdict(NAME, verdictText()), appId: APP, log: () => {} }), true);
  assert.equal(api.created.length, 1);
  assert.deepEqual(api.writes, []);
});

// A person's PR: GitHub lets only its author or a writer resolve a thread, and
// the lanes App is neither, so the fail is one PR comment and a label that
// ci-status holds in the merge queue, never a review thread.
const PERSON = 153232337;
const personBody = (head) =>
  [
    VERIFY_NOTE_MARKER,
    `The pr-verify verifier failed head \`${head}\`. What it wrote, as data:`,
    "",
    "```text",
    "Summary: Spec item 2 is unmet.",
    "- `plugins/x/a.py:12` returns early.",
    "- No test covers it.",
    "```",
    "",
    "This pull request leaves the merge queue, and ci-status holds it out while it carries `pr-verify-failed`. A pr-verify pass at a new commit removes the label.",
  ].join("\n");

test("a fail on a PR a person opened posts one PR comment and the pr-verify-failed label, and no review thread", async () => {
  const api = fakeApi({ pull: { user: { id: PERSON } } });
  assert.equal(await postNotes({ api, verdict: readVerdict(NAME, verdictText()), appId: APP, log: () => {} }), false);
  assert.deepEqual(api.created, []);
  assert.deepEqual(api.writes, [
    { op: "comment", pr: 42, body: personBody(HEAD) },
    { op: "label", pr: 42, names: ["pr-verify-failed"] },
  ]);
  for (const pull of [{ head: { sha: OLD_HEAD } }, { state: "closed" }]) {
    const moved = fakeApi({ pull: { user: { id: PERSON }, ...pull } });
    assert.equal(await postNotes({ api: moved, verdict: readVerdict(NAME, verdictText()), appId: APP, log: () => {} }), false);
    assert.deepEqual(moved.writes, [], "a moved head or a closed PR changes nothing");
  }
});

test("a fail on a person's PR already in the merge queue dequeues it after the label; an unqueued one is not dequeued", async () => {
  const verdict = readVerdict(NAME, verdictText());
  const queued = fakeApi({ pull: { user: { id: PERSON } }, queued: true });
  await postNotes({ api: queued, verdict, appId: APP, log: () => {} });
  assert.deepEqual(queued.writes, [
    { op: "comment", pr: 42, body: personBody(HEAD) },
    { op: "label", pr: 42, names: ["pr-verify-failed"] },
    { op: "dequeue", id: "PR_node42" },
  ]);
  const labeled = fakeApi({ pull: { user: { id: PERSON } }, issueComments: [{ id: 9, user: { id: ACTIONS_BOT }, body: personBody(HEAD) }], labels: ["pr-verify-failed"], queued: true });
  await postNotes({ api: labeled, verdict, appId: APP, log: () => {} });
  assert.deepEqual(labeled.writes, [{ op: "dequeue", id: "PR_node42" }], "a re-run while still queued dequeues it");
  const idle = fakeApi({ pull: { user: { id: PERSON } } });
  await postNotes({ api: idle, verdict, appId: APP, log: () => {} });
  assert.equal(idle.writes.filter((w) => w.op === "dequeue").length, 0);
});

test("a refused dequeue fails the run with an error naming the PR, rather than letting the queued merge land", async () => {
  const lines = [];
  const api = fakeApi({
    pull: { user: { id: PERSON } },
    queued: true,
    dequeue: async () => {
      throw new Error("GraphQL: Resource not accessible by integration");
    },
  });
  await assert.rejects(postNotes({ api, verdict: readVerdict(NAME, verdictText()), appId: APP, log: (line) => lines.push(line) }), /Resource not accessible/);
  assert.ok(lines.some((line) => line.startsWith("::error::#42:") && line.includes("queued merge was not stopped")));
  assert.deepEqual(api.writes.at(-1), { op: "label", pr: 42, names: ["pr-verify-failed"] }, "the label still lands first");
});

test("a later fail on a person's PR updates its fail comment in place, and a re-run changes nothing", async () => {
  const verdict = readVerdict(NAME, verdictText());
  const old = { id: 9, user: { id: ACTIONS_BOT }, body: personBody(OLD_HEAD) };
  const strangers = [
    { id: 7, user: { id: PERSON }, body: personBody(OLD_HEAD) },
    { id: 8, user: { id: ACTIONS_BOT }, body: "A plain comment." },
  ];
  const later = fakeApi({ pull: { user: { id: PERSON } }, issueComments: [...strangers, old], labels: ["pr-verify-failed"] });
  await postNotes({ api: later, verdict, appId: APP, log: () => {} });
  assert.deepEqual(later.writes, [{ op: "update", id: 9, body: personBody(HEAD) }]);
  const rerun = fakeApi({ pull: { user: { id: PERSON } }, issueComments: [{ ...old, body: personBody(HEAD) }], labels: ["pr-verify-failed"] });
  await postNotes({ api: rerun, verdict, appId: APP, log: () => {} });
  assert.deepEqual(rerun.writes, []);
});

test("verify-notes refuses to run without the lanes App's id, rather than treat every PR as a person's", async () => {
  await assert.rejects(postNotes({ api: fakeApi(), verdict: readVerdict(NAME, verdictText()), log: () => {} }), /lanes App/);
  await assert.rejects(postNotes({ api: fakeApi(), verdict: readVerdict(NAME, verdictText()), appId: 0, log: () => {} }), /lanes App/);
});

test("main names the PR and head only once the notes are on the PR", async () => {
  const dir = tempDir("verify-notes-");
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    ARTIFACT_NAME: NAME,
    VERDICT_FILE: join(dir, "verdict.json"),
    APP_SENDER_ID: String(APP),
  };
  writeFileSync(env.VERDICT_FILE, verdictText());
  writeFileSync(env.GITHUB_OUTPUT, "");
  await main(env, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `pr-number=42\nhead-sha=${HEAD}\n`);
  writeFileSync(env.GITHUB_OUTPUT, "");
  await main(env, { api: fakeApi({ pull: { state: "closed" } }), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "");
  // A person's PR starts no round: the label holds it.
  await main(env, { api: fakeApi({ pull: { user: { id: PERSON } } }), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "");
});

// A review thread as address-feedback.mjs listThreads reads it: `root` is its
// first comment's author, body and original commit.
const OLD = "b".repeat(40);
const noteBody = (head) => noteComments({ head, summary: "s", notes: [], files: FILES })[0].body;
const thread = (id, { resolved = false, author = ACTIONS_BOT, body = noteBody(OLD), commit = OLD } = {}) => ({
  id,
  isResolved: resolved,
  isOutdated: true,
  comments: { totalCount: 1, nodes: [{ databaseId: 1 }] },
  root: { nodes: [{ author: { databaseId: author }, body, originalCommit: commit ? { oid: commit } : null }] },
});
const PASS = `pr-verify-42-${HEAD}-pass`;
const passText = (extra = {}) => JSON.stringify({ verdict: "pass", pr: 42, head_sha: HEAD, summary: "ok", notes: [], ...extra });

test("a pass or pass-notes verdict reads with the checks a fail's does, and takes no issue numbers", () => {
  assert.deepEqual(readVerdict(PASS, passText()), { pr: 42, head: HEAD, verdict: "pass" });
  assert.deepEqual(readVerdict(`${PASS}-notes`, passText({ verdict: "pass-notes" })), { pr: 42, head: HEAD, verdict: "pass-notes" });
  assert.equal(readVerdict(`${PASS}-notes-79b4cc554b80dca6`, passText({ verdict: "pass-notes", head_ref: "feat/x" })).verdict, "pass-notes");
  for (const [name, text] of [
    [PASS, passText({ verdict: "pass-notes" })],
    [`${PASS}-notes`, passText()],
    [PASS, passText({ verdict: "fail" })],
    [PASS, passText({ pr: 43 })],
    [PASS, passText({ head_sha: OLD })],
    [`${PASS}-79b4cc554b80dca6`, passText({ head_ref: "feat/other" })],
    [`${PASS}-i7`, passText({ linked_issues: [{ number: 7 }] })],
    [`pr-verify-42-${HEAD}-passed`, passText()],
    [NAME, passText()],
  ]) {
    assert.throws(() => readVerdict(name, text), name);
  }
});

test("a stale fail-note thread is an open verifier note from another head, and nothing else", () => {
  assert.deepEqual(
    staleVerifyNotes(
      [
        thread("PRRT_old"),
        thread("PRRT_resolved", { resolved: true }),
        thread("PRRT_same", { body: noteBody(HEAD), commit: HEAD }),
        thread("PRRT_other_author", { author: 209825114 }),
        thread("PRRT_no_marker", { body: "A plain comment." }),
        thread("PRRT_no_commit", { commit: null }),
      ],
      HEAD,
    ),
    ["PRRT_old"],
  );
});

test("a pass names its head only when the PR is open at it and holds a stale fail-note thread", async () => {
  const run = async ({ pull = {}, threads = [thread("PRRT_old")], name = PASS, text = passText() } = {}) => {
    const dir = tempDir("verify-notes-");
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: join(dir, "out"), ARTIFACT_NAME: name, VERDICT_FILE: join(dir, "verdict.json"), APP_SENDER_ID: String(APP) };
    writeFileSync(env.VERDICT_FILE, text);
    writeFileSync(env.GITHUB_OUTPUT, "");
    const api = { ...fakeApi({ pull, labels: ["pr-verify-failed"] }), listThreads: async () => threads, resolveThread: async () => assert.fail("post-verify-notes resolves nothing") };
    await main(env, { api, log: () => {} });
    assert.deepEqual(api.created, []);
    assert.deepEqual(api.writes, [], "a lanes App PR's label is not this job's");
    return readFileSync(env.GITHUB_OUTPUT, "utf8");
  };
  assert.equal(await run(), `pass-head-sha=${HEAD}\n`);
  assert.equal(await run({ name: `${PASS}-notes`, text: passText({ verdict: "pass-notes" }) }), `pass-head-sha=${HEAD}\n`);
  assert.equal(await run({ threads: [thread("PRRT_same", { body: noteBody(HEAD), commit: HEAD })] }), "", "a note on the passing head stays");
  assert.equal(await run({ threads: [thread("PRRT_other", { author: 209825114 }), thread("PRRT_plain", { body: "x" })] }), "", "not a verifier note");
  assert.equal(await run({ threads: [] }), "", "no thread");
  assert.equal(await run({ pull: { head: { sha: OLD } } }), "", "the PR moved past the passing head");
  assert.equal(await run({ pull: { state: "closed" } }), "", "a closed PR");
});

test("a pass on a person's PR at its head removes pr-verify-failed and names no head", async () => {
  const run = async ({ pull = {}, labels = ["ci", "pr-verify-failed"], name = PASS, text = passText() } = {}) => {
    const dir = tempDir("verify-notes-");
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_OUTPUT: join(dir, "out"), ARTIFACT_NAME: name, VERDICT_FILE: join(dir, "verdict.json"), APP_SENDER_ID: String(APP) };
    writeFileSync(env.VERDICT_FILE, text);
    writeFileSync(env.GITHUB_OUTPUT, "");
    const api = { ...fakeApi({ pull: { user: { id: PERSON }, ...pull }, labels }), listThreads: async () => [thread("PRRT_old")] };
    await main(env, { api, log: () => {} });
    assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "", "no pass-only round");
    return api.writes;
  };
  assert.deepEqual(await run(), [{ op: "unlabel", pr: 42, name: "pr-verify-failed" }]);
  assert.deepEqual(await run({ name: `${PASS}-notes`, text: passText({ verdict: "pass-notes" }) }), [{ op: "unlabel", pr: 42, name: "pr-verify-failed" }]);
  assert.deepEqual(await run({ labels: ["ci"] }), [], "no label to remove");
  assert.deepEqual(await run({ pull: { head: { sha: OLD } } }), [], "the PR moved past the passing head");
  assert.deepEqual(await run({ pull: { state: "closed" } }), [], "a closed PR");
});
