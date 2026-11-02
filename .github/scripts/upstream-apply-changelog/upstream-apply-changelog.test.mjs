import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  alreadyProcessed,
  branchFor,
  checkRawLog,
  commitNetTree,
  fileReleaseHandoffs,
  handoffMarker,
  netRawDiff,
  newestRelease,
  publishText,
  readNetChanges,
  readPlan,
  refuseBinary,
  releaseIssue,
  releaseMarker,
  releasesFromStatus,
  renderItems,
  startedInWindow,
  validatePlan,
} from "./upstream-apply-changelog.mjs";

const BASE = "a".repeat(40);
const HEAD = "b".repeat(40);
const plan = (over = {}) => ({
  schema: "changelog-ci-plan/1",
  status: "planned",
  range: "2.1.300..2.1.300",
  base_sha: BASE,
  branches: [
    {
      plugin: "hooks-kit",
      branch: "changelog/hooks-kit/v2.1.300",
      base_sha: BASE,
      head_sha: HEAD,
      pr: { title: "chore(hooks-kit): address Claude Code v2.1.300 changelog", body: "Refs: #7407" },
    },
  ],
  handoffs: [{ key: "changelog:2.1.300..2.1.300:adopt:plugins/x/a.sh", title: "t", body: "b" }],
  ...over,
});
const ctx = { release: "2.1.300", baseSha: BASE };

test("the newest release is the highest version, skipping drafts, prereleases and other tags", () => {
  const releases = [
    { tag_name: "v2.1.99" },
    { tag_name: "v2.1.300" },
    { tag_name: "v2.1.301", prerelease: true },
    { tag_name: "v9.9.9", draft: true },
    { tag_name: "nightly" },
  ];
  assert.equal(newestRelease(releases), "2.1.300");
  assert.equal(newestRelease([]), "");
});

test("the per-day cap counts only start records from the last 24 hours", () => {
  const now = Date.parse("2026-11-02T12:00:00Z");
  const artifacts = [
    { name: "upstream-apply-changelog-started-2.1.300-1", created_at: "2026-11-02T01:00:00Z" },
    { name: "upstream-apply-changelog-started-2.1.299-2", created_at: "2026-11-01T11:00:00Z" },
    { name: "upstream-apply-changelog-done-2.1.300", created_at: "2026-11-02T02:00:00Z" },
  ];
  assert.equal(startedInWindow(artifacts, now), 1);
});

test("a valid plan passes and a stopped plan acts on nothing", () => {
  assert.equal(validatePlan(plan(), ctx).branches.length, 1);
  assert.deepEqual(validatePlan(plan({ status: "stopped" }), ctx), { branches: [], handoffs: [] });
});

test("a plan for another release, base or branch name is refused", () => {
  assert.throws(() => validatePlan(plan({ range: "2.1.299..2.1.299" }), ctx), /range/);
  assert.throws(() => validatePlan(plan({ base_sha: HEAD }), ctx), /base_sha/);
  const renamed = plan();
  renamed.branches[0].branch = "main";
  assert.throws(() => validatePlan(renamed, ctx), /branches\[0\]\.branch is not changelog\/<plugin>\/v<release>/);
  const titled = plan();
  titled.branches[0].pr.title = "feat(other): x";
  assert.throws(() => validatePlan(titled, ctx), /branches\[0\]\.pr\.title/);
  assert.throws(() => validatePlan(plan({ handoffs: [{ key: "changelog:2.1.1..2.1.1:adopt:x", title: "t", body: "b" }] }), ctx), /handoffs\[0\]\.key/);
  const empty = plan();
  empty.branches[0].head_sha = BASE;
  assert.throws(() => validatePlan(empty, ctx), /branches\[0\]\.head_sha/);
  assert.equal(branchFor("hooks-kit", "2.1.300"), "changelog/hooks-kit/v2.1.300");
});

test("a refusal names the field and index, never the plan's value", () => {
  const SECRET = "zzPLANTEDzz";
  const cases = [];
  const renamed = plan();
  renamed.branches[0].branch = SECRET;
  cases.push([renamed, /branches\[0\]\.branch/]);
  const twice = plan();
  twice.branches.push({ ...twice.branches[0], branch: SECRET });
  cases.push([twice, /branches\[1\]\.plugin/]);
  const titled = plan();
  titled.branches[0].pr.title = `chore(hooks-kit): ${SECRET}\n`;
  cases.push([titled, /branches\[0\]\.pr\.title/]);
  const keyed = plan({ handoffs: [{ key: `changelog:2.1.300..2.1.300:adopt:${SECRET}`, title: "t", body: "b" }, { key: `changelog:2.1.300..2.1.300:adopt:${SECRET}`, title: "t", body: "b" }] });
  cases.push([keyed, /handoffs\[1\]\.key/]);
  const handTitled = plan({ handoffs: [{ key: "changelog:2.1.300..2.1.300:adopt:x", title: `${SECRET}\n`, body: "b" }] });
  cases.push([handTitled, /handoffs\[0\]\.title/]);
  for (const [p, want] of cases) {
    assert.throws(
      () => validatePlan(p, ctx),
      (e) => want.test(e.message) && !e.message.includes(SECRET),
    );
  }
  assert.throws(() => readPlan(`{"schema": ${SECRET}}`, ctx), (e) => /not valid JSON/.test(e.message) && !e.message.includes(SECRET));
  assert.equal(readPlan(JSON.stringify(plan()), ctx).branches.length, 1);
  assert.throws(
    () => checkRawLog(`:100644 100644 1 2 M\tplugins/hooks-kit/a\n:100644 100644 1 2 M\t${SECRET}`, "hooks-kit", 3),
    (e) => /branches\[3\] raw line 2/.test(e.message) && !e.message.includes(SECRET),
  );
});

test("the publish text holds every pull request and issue string publish can post, decoded", async () => {
  const p = plan({
    handoffs: [
      { key: "changelog:2.1.300..2.1.300:adopt:a", kind: "adopt", title: "first \"quoted\"", body: "line one\nline two" },
      { key: "changelog:2.1.300..2.1.300:adopt:b", kind: "adopt", title: "second", body: "z".repeat(50000) },
      { key: "changelog:2.1.300..2.1.300:adopt:c", kind: "adopt", title: "third", body: "y".repeat(50000) },
    ],
  });
  p.branches[0].pr.body = "Refs: #7407\nwith \"quotes\" and a tab\t.";
  const v = validatePlan(p, ctx);
  const text = publishText(v, "2.1.300");
  assert.ok(text.includes(v.branches[0].pr.title));
  assert.ok(text.includes("with \"quotes\" and a tab\t."));
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: "2.1.300", handoffs: v.handoffs, api: f.api });
  const posted = f.writes()[0].body;
  assert.deepEqual(posted, releaseIssue("2.1.300", v.handoffs));
  assert.ok(text.includes(posted.title) && text.includes(posted.body));
  assert.ok(posted.body.includes("truncated proportionally"));
  assert.ok(text.includes(renderItems(v.handoffs, Number.POSITIVE_INFINITY)));
  assert.equal(publishText(validatePlan(plan({ handoffs: [] }), ctx), "2.1.300").includes(releaseMarker("2.1.300")), false);
});

test("a commit outside its plugin, or writing a link or submodule, is refused", () => {
  const ok = ":000000 100644 0000 1111 A\tplugins/hooks-kit/SKILL.md\n:000000 100644 0000 2222 A\t.changes/hooks-kit/x.md";
  assert.doesNotThrow(() => checkRawLog(ok, "hooks-kit"));
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\tplugins/other/SKILL.md", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":100644 100644 1 2 M\t.github/workflows/x.yml", "hooks-kit"), /outside/);
  assert.throws(() => checkRawLog(":000000 120000 0 2 A\tplugins/hooks-kit/link", "hooks-kit"), /mode other than a regular file/);
  assert.throws(() => checkRawLog(":000000 160000 0 2 A\tplugins/hooks-kit/sub", "hooks-kit"), /mode other than a regular file/);
});

test("only the done marker skips a release, so a run after a failed publish finishes the work", () => {
  assert.equal(alreadyProcessed({ total_count: 1, artifacts: [{ name: "upstream-apply-changelog-done-2.1.300" }] }), true);
  assert.equal(alreadyProcessed({ total_count: 0, artifacts: [] }), false);
  assert.equal(alreadyProcessed(null), false);
});

test("the status file gives the unread releases, none when up to date, and stops on anything else", () => {
  assert.deepEqual(releasesFromStatus("range: 2.1.299..2.1.300 (2 releases, 5 core items)\nreleases: 2.1.299 2.1.300\ncap: within budget (2 releases / 5 items)\n"), ["2.1.299", "2.1.300"]);
  assert.deepEqual(releasesFromStatus("range: up to date\n"), []);
  assert.throws(() => releasesFromStatus("range: 2.1.1..2.1.90 (90 releases, 400 core items)\ncap: exceeded (90 releases / 400 items)\n"), /cap: exceeded/);
  assert.throws(() => releasesFromStatus("range: a..b\ncap: within budget\nreleases: v2\n"), /malformed/);
});

// A fake Git Data API: each object's sha is its index in the calls made.
function fakeApi() {
  const calls = [];
  const sha = (kind) => {
    calls.push(kind);
    return `${kind}-${calls.length}`;
  };
  return {
    calls,
    createBlob: async (content) => sha(`blob:${content}`),
    createTree: async (base, entries) => sha(`tree:${base}:${entries.map((e) => `${e.path}=${e.sha}`).join(",")}`),
    createCommit: async (message, tree, parents) => sha(`commit:${message.trim()}:${tree}:${parents.join(",")}`),
  };
}

test("a branch becomes one App commit on the base, titled with its pull request title, deleting a removed file", async () => {
  const api = fakeApi();
  const changes = [
    { path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") },
    { path: "plugins/p/old.md", mode: "100644", content: null },
  ];
  const tree = "tree:t0:plugins/p/a.md=blob:YQ==-1,plugins/p/old.md=null-2";
  const head = await commitNetTree(changes, { message: "chore(p): title", baseSha: BASE, baseTree: "t0", headTree: tree, api });
  assert.equal(api.calls.length, 3);
  assert.equal(api.calls[2], `commit:chore(p): title:${tree}:${BASE}`);
  assert.equal(head, `${api.calls[2]}-3`);
});

test("a built tree that is not the planned head's, or an empty change, makes no commit", async () => {
  const changes = [{ path: "plugins/p/a.md", mode: "100644", content: Buffer.from("a") }];
  const api = fakeApi();
  await assert.rejects(commitNetTree(changes, { message: "m", baseSha: BASE, baseTree: "t0", headTree: "other", api }), /not the planned head's/);
  assert.ok(!api.calls.some((c) => c.startsWith("commit:")));
  await assert.rejects(commitNetTree([], { message: "m", baseSha: BASE, baseTree: "t0", headTree: "t0", api: fakeApi() }), /changes nothing/);
});

test("the net change reads each file once at its head content, whatever the commits in between", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "uac-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_NOSYSTEM: "1", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t" };
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { env, encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  writeFileSync(join(dir, "keep.md"), "k");
  git("add", ".");
  git("commit", "-qm", "base");
  const base = git("rev-parse", "HEAD");
  writeFileSync(join(dir, "new.md"), "n1");
  git("add", ".");
  git("commit", "-qm", "add new");
  writeFileSync(join(dir, "new.md"), "n2");
  git("add", ".");
  git("commit", "-qm", "edit new");
  git("rm", "-q", "keep.md");
  git("commit", "-qm", "drop keep");
  const changes = readNetChanges(dir, base, git("rev-parse", "HEAD"));
  assert.deepEqual(
    changes.map((e) => [e.path, e.mode, e.content === null ? null : String(e.content)]),
    [["keep.md", "100644", null], ["new.md", "100644", "n2"]],
  );
  writeFileSync(join(dir, "img.bin"), Buffer.from([0, 1, 2, 0, 255]));
  git("add", ".");
  git("commit", "-qm", "binary");
  const numstat = git("diff", "--numstat", base, "HEAD");
  assert.throws(() => refuseBinary(numstat, 2), (e) => /branches\[2\] changes a binary file/.test(e.message) && !e.message.includes("img.bin"));
  assert.doesNotThrow(() => refuseBinary(git("diff", "--numstat", base, "HEAD~1"), 2));
  // A merge commit's change shows in the net diff, so the path check sees it.
  git("checkout", "-qb", "side", base);
  git("checkout", "-q", "main", "--", "new.md");
  git("commit", "-qm", "side");
  git("merge", "-q", "--no-edit", "main");
  assert.match(netRawDiff(dir, base, git("rev-parse", "HEAD")), /\tnew\.md$/m);
});

const REPO = "o/r";
const REL = "2.1.300";
const APP = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const OUTSIDER = { login: "someone", type: "User" };
const handoff = (n, over = {}) => ({ key: `changelog:${REL}..${REL}:adopt:plugins/x/${n}.sh`, kind: "adopt", title: `adopt ${n}`, body: `body ${n}\nline two`, ...over });
// A fake API: answers the search with `items`, a comment read with the page of
// `comments` it asks for (or `comments` itself when not a list), and records every call.
const issueApi = (items = [], comments = []) => {
  const calls = [];
  const api = async (path, opts = {}) => {
    const method = opts.method ?? "GET";
    calls.push({ path, method, body: opts.body });
    if (path.startsWith("/search/issues")) return { items };
    if (method === "GET" && path.includes("/comments?")) {
      if (!Array.isArray(comments)) return comments;
      const page = Number(path.match(/page=(\d+)$/)[1]);
      return comments.slice((page - 1) * 100, page * 100);
    }
    return {};
  };
  return { api, calls, writes: () => calls.filter((c) => c.method !== "GET") };
};

test("no handoffs files nothing and makes no call", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [], api: f.api });
  assert.equal(f.calls.length, 0);
});

test("one handoff files one release issue with the release marker and its keyed checklist item", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const [w] = f.writes();
  assert.equal(f.writes().length, 1);
  assert.equal(w.path, `/repos/${REPO}/issues`);
  assert.equal(w.method, "POST");
  assert.equal(w.body.title, `Claude Code v${REL} changelog: 1 handoff`);
  assert.ok(w.body.body.startsWith(`${releaseMarker(REL)}\n`));
  assert.ok(w.body.body.includes("- [ ] adopt: adopt 1\n\n  body 1\n  line two\n\n  "));
  assert.ok(w.body.body.includes(handoffMarker(handoff(1).key)));
});

test("several handoffs go into one issue, one checklist item each, in plan order", async () => {
  const f = issueApi();
  const hs = [handoff(1), handoff(2, { kind: "security" }), handoff(3)];
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  assert.equal(f.writes().length, 1);
  const { title, body } = f.writes()[0].body;
  assert.equal(title, `Claude Code v${REL} changelog: 3 handoffs`);
  assert.equal(body.match(/^- \[ \] /gm).length, 3);
  assert.ok(body.includes("- [ ] security: adopt 2"));
  const at = hs.map((h) => body.indexOf(handoffMarker(h.key)));
  assert.ok(at.every((i) => i > 0) && at[0] < at[1] && at[1] < at[2]);
});

test("bodies over the issue limit are cut in proportion, every key kept, and a line says so", async () => {
  const f = issueApi();
  const hs = [handoff(1, { body: "a".repeat(50000) }), handoff(2, { body: "b".repeat(25000) })];
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  const { body } = f.writes()[0].body;
  assert.ok(body.length <= 65536);
  assert.match(body, /truncated proportionally/);
  for (const h of hs) assert.ok(body.includes(handoffMarker(h.key)));
  const a = body.match(/a+/g).reduce((m, s) => Math.max(m, s.length), 0);
  const b = body.match(/b{100,}/g)[0].length;
  assert.ok(Math.abs(a / b - 2) < 0.01);
  assert.equal(renderItems(hs.slice(0, 1).map((h) => ({ ...h, body: "x" })), 1000).includes("truncated"), false);
});

test("a release issue holding every key gets no write", async () => {
  const hs = [handoff(1), handoff(2)];
  const body = `${releaseMarker(REL)}\n\n${renderItems(hs, 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: f.api });
  assert.equal(f.writes().length, 0);
});

test("an open release issue missing a key gets the missing item appended in one update", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues/7`);
  assert.equal(writes[0].method, "PATCH");
  assert.equal(writes[0].body.title, `Claude Code v${REL} changelog: 2 handoffs`);
  assert.ok(writes[0].body.body.startsWith(body.trimEnd()));
  assert.equal(writes[0].body.body.split(handoffMarker(handoff(1).key)).length, 2);
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
});

test("a closed release issue gets no write, even when it lacks a key", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"closed", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  assert.equal(f.writes().length, 0);
});

test("an issue for another release does not count as this release's issue", async () => {
  const f = issueApi([{ user: APP, number: 7, state:"open", body: `${releaseMarker("2.1.30")}\n` }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  assert.equal(f.writes()[0].method, "POST");
});

test("missing items that would push the body past the limit go in one comment instead", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1, { body: "a".repeat(60000) })], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state:"open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2, { body: "b".repeat(10000) })], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues/7/comments`);
  assert.equal(writes[0].method, "POST");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
  assert.ok(!writes[0].body.body.includes(handoffMarker(handoff(1).key)));
  assert.ok(writes[0].body.body.length <= 65536);
});

test("a key already in a comment, past the first page, is not added again", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const comments = [...Array.from({ length: 100 }, () => ({ body: "noise" })), { user: APP, body: renderItems([handoff(2)], 65536) }];
  const f = issueApi([{ user: APP, number: 7, state:"open", body }], comments);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2), handoff(3)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].method, "PATCH");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(3).key)));
  assert.ok(!writes[0].body.body.includes(handoffMarker(handoff(2).key)));
  assert.equal(f.calls.filter((c) => c.path.includes("/comments?")).length, 2);
});

test("a comment read that fails, or runs past the page cap, files nothing", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const hs = [handoff(1), handoff(2)];
  const bad = issueApi([{ user: APP, number: 7, state:"open", body }], { message: "Server Error" });
  await assert.rejects(fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: bad.api }), /not come back as a list/);
  assert.equal(bad.writes().length, 0);
  const many = issueApi([{ user: APP, number: 7, state:"open", body }], Array.from({ length: 1000 }, () => ({ body: "" })));
  await assert.rejects(fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: hs, api: many.api }), /more comments/);
  assert.equal(many.writes().length, 0);
});

test("the search asks for issues the lanes App opened", async () => {
  const f = issueApi();
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const q = decodeURIComponent(f.calls[0].path.match(/q=([^&]+)/)[1]);
  assert.match(q, /(^| )author:app\/melodic-automation-lanes( |$)/);
});

test("an outsider's issue carrying the release marker is ignored and a new issue is filed", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: OUTSIDER, number: 7, state: "open", body }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `/repos/${REPO}/issues`);
  assert.equal(writes[0].method, "POST");
});

test("a key marker in an outsider's comment does not count as filed", async () => {
  const body = `${releaseMarker(REL)}\n\n${renderItems([handoff(1)], 65536)}`;
  const f = issueApi([{ user: APP, number: 7, state: "open", body }], [{ user: OUTSIDER, body: renderItems([handoff(2)], 65536) }]);
  await fileReleaseHandoffs({ repo: REPO, release: REL, handoffs: [handoff(1), handoff(2)], api: f.api });
  const writes = f.writes();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].method, "PATCH");
  assert.ok(writes[0].body.body.includes(handoffMarker(handoff(2).key)));
});
