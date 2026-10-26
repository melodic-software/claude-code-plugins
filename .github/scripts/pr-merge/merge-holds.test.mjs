// Expected values come from the issue that added these holds and the gate's
// own rules: the merge gate holds a change to a cost path
// (babysit_risk.COST_PATHS) until the owner's cost decision, which
// babysit_merge_policy.cost_decision reads and test_babysit_merge_cost.py
// pins case by case. ci-status names its owner by the trusted-actor list, as
// its cost-only review hold step does, so a review approval lifts a hold path
// but never a cost hold. A decision binds to one pull request: one on the pull
// request counts as it is, one on its linked issue (closing, else `Refs:`)
// only when it names `#<number>`. It covers the head it decided, the sha of the
// newest cost hold marker github-actions[bot] posted before it, and a later
// head only when the net change against the base branch is the same at both
// (owner decisions Q17 c and Q18 d on #9436, as ci-workflows v0.65.4's hold
// step reads them).
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { BODY_WRITERS_QUERY, COMMENT_DELETED_QUERY, COMMENT_EDITED_QUERY, PULL_OPENED_QUERY, changeOf, costDecision, costHold, costMarker, deletedSince, linkHold, main, sameNetChange } from "./merge-holds.mjs";

const REPO = "owner/repo";
const LINK = "https://github.com/owner/repo/issues/40#issuecomment-7";
const PR_CREATED = "2026-10-22T10:00:00Z";
const HUMANS = new Set([5]);
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const BASE = "89abcdef0123456789abcdef0123456789abcdef";
const OLD = "fedcba9876543210fedcba9876543210fedcba98";
const LANE = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
// A review lane's cost hold comment on the pull request at `sha`.
// Its node id IC_M answers the marker's edit read.
const marker = (sha, at = "2026-10-22T11:00:00Z", { criteria = "cost", user = LANE } = {}) => ({
  user,
  node_id: "IC_M",
  created_at: at,
  body: `<!-- claude-lane-hold lane=claude-review sha=${sha} criteria=${criteria} -->\nHeld for a person.\n\nclaude-lane: claude-review`,
});
// A compare answer: the pull request's files against the base.
const TF = { filename: "infra/main.tf", status: "modified", patch: "@@ -1 +1 @@\n-a\n+b" };
const net = (...files) => ({ files });

const comment = (changes = {}) => ({
  issue_url: "https://api.github.com/repos/owner/repo/issues/40",
  user: { login: "owner-person", id: 5, type: "User" },
  performed_via_github_app: null,
  body: "**Decision recorded.** Cost: approve the larger runner for #99.",
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
  ...changes,
});

// A GitHub that answers the decision reads: the pull request's creation time
// and closing issues, the linked issue (`target`), comment 7, and its edit time; then
// the head reads: the pull request's `comments` (a cost hold marker at HEAD
// by default) and a `compares` answer per head against `base`.
// `fail` names a read that throws.
function world({
  row = comment(),
  closing = [{ number: 40, repository: { nameWithOwner: REPO } }],
  node,
  created = PR_CREATED,
  target = { number: 40 },
  fail,
  comments = [marker(HEAD)],
  compares = {},
  base = "main",
  markerNode,
  deleted = [],
} = {}) {
  const reads = [];
  const github = async (method, path, body) => {
    const compare = /^\/repos\/owner\/repo\/compare\/(.+)\.\.\.([0-9a-f]{40})$/.exec(path);
    const read =
      body?.query === PULL_OPENED_QUERY
        ? "pull"
        : body?.query === COMMENT_EDITED_QUERY
          ? body.variables.id === "IC_M"
            ? "marker edited"
            : "edited"
          : body?.query === COMMENT_DELETED_QUERY
            ? "deleted"
            : path === "/repos/owner/repo/issues/99/comments?per_page=100&page=1"
            ? "comments"
            : compare
              ? `compare ${compare[2]}`
              : `${method} ${path}`;
    reads.push(read);
    if (read === fail) {
      throw new Error(`${read} failed`);
    }
    if (read === "comments") {
      return comments;
    }
    if (compare) {
      assert.equal(compare[1], base);
      if (!(compare[2] in compares)) {
        throw new Error("no such commit");
      }
      return compares[compare[2]];
    }
    if (read === "pull") {
      assert.deepEqual(body.variables, { owner: "owner", name: "repo", number: 99 });
      return {
        data: {
          repository: {
            pullRequest: { createdAt: created, baseRefName: base, closingIssuesReferences: { totalCount: closing.length, nodes: closing } },
          },
        },
      };
    }
    if (read === "deleted") {
      assert.deepEqual(body.variables, { owner: "owner", name: "repo", number: 99 });
      const items = Array.isArray(deleted) ? { filteredCount: deleted.length, nodes: deleted.map((createdAt) => ({ createdAt })) } : deleted;
      return { data: { repository: { pullRequest: { timelineItems: items } } } };
    }
    if (read === "marker edited") {
      return { data: { node: markerNode === undefined ? { lastEditedAt: null } : markerNode } };
    }
    if (read === "edited") {
      assert.deepEqual(body.variables, { id: "IC_7" });
      return { data: { node: node === undefined ? { lastEditedAt: null } : node } };
    }
    if (read === "GET /repos/owner/repo/issues/40") {
      return target;
    }
    assert.equal(read, "GET /repos/owner/repo/issues/comments/7");
    return row;
  };
  return { github, reads };
}

const decide = (body = `Closes #40\n\nCost decision: ${LINK}\n`, options = {}) => {
  const { github, reads } = world(options);
  return costDecision(github, REPO, 99, body, HUMANS, options.head ?? HEAD).then((link) => ({ link, reads }));
};

test("an owner decision on the closing issue, linked from the body, clears the cost hold", async () => {
  const { link, reads } = await decide();
  assert.equal(link, LINK);
  assert.deepEqual(reads, ["pull", "GET /repos/owner/repo/issues/comments/7", "edited", "comments", "marker edited", "deleted"]);
});

test("one on the pull request itself clears with no check against the pull request's time and no #number", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-21T09:00:00Z", body: "**Decision recorded.** Cost: approve it." });
  assert.equal((await decide(own, { row, closing: [], comments: [marker(HEAD, "2026-10-21T08:00:00Z")] })).link, own);
  // With no time it decides no head, so it carries to none.
  assert.equal((await decide(own, { row: { ...row, created_at: null }, closing: [] })).link, null);
});

test("one on the linked issue clears only when its text names the pull request", async () => {
  for (const text of ["for #99.", "(#99)", "#99", "see #99, then"]) {
    assert.equal((await decide(undefined, { row: comment({ body: `**Decision recorded.** Cost: approve ${text}` }) })).link, LINK, text);
  }
  for (const text of ["for another change.", "for #98.", "for #990.", "for owner/repo#99.", "for x#99.", "for pull 99.", "for &#99;", "for ##99."]) {
    assert.equal((await decide(undefined, { row: comment({ body: `**Decision recorded.** Cost: approve ${text}` }) })).link, null, text);
  }
});

test("with no closing issue, one on the issue the Refs line names counts the same way", async () => {
  const refs = `Refs: #40\n\nCost decision: ${LINK}\n`;
  assert.equal((await decide(refs, { closing: [] })).link, LINK);
  const unnamed = comment({ body: "**Decision recorded.** Cost: approve the larger runner." });
  assert.equal((await decide(refs, { closing: [], row: unnamed })).link, null);
  for (const body of [`Refs: #41\n\n${LINK}`, `Refs: #40\nRefs: #41\n\n${LINK}`, `Refs: #40, #41\n\n${LINK}`, `\`\`\`\nRefs: #40\n\`\`\`\n\n${LINK}`, `<!-- Refs: #40 -->\n\n${LINK}`]) {
    assert.equal((await decide(body, { closing: [] })).link, null, body);
  }
  // A closing issue wins over the Refs line, as babysit's _linked_issue reads it.
  assert.equal((await decide(refs, { closing: [{ number: 12, repository: { nameWithOwner: REPO } }] })).link, null);
});

test("a Refs number that names a pull request, or cannot be read, consults no issue", async () => {
  const refs = `Refs: #40\n\nCost decision: ${LINK}\n`;
  const { link, reads } = await decide(refs, { closing: [], target: { number: 40, pull_request: { url: "x" } } });
  assert.equal(link, null);
  assert.deepEqual(reads, ["pull", "GET /repos/owner/repo/issues/40"]);
  assert.equal((await decide(refs, { closing: [], target: { number: 41 } })).link, null);
  assert.equal((await decide(refs, { closing: [], fail: "GET /repos/owner/repo/issues/40" })).link, null);
  // The pull request's own decision still counts, with no read of the Refs target.
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: "**Decision recorded.** Cost: approve it." });
  const mine = await decide(`Refs: #40\n\n${own}\n`, { closing: [], row, target: { number: 40, pull_request: {} } });
  assert.equal(mine.link, own);
  assert.ok(!mine.reads.includes("GET /repos/owner/repo/issues/40"));
});

test("a body with no covering link reads nothing", async () => {
  for (const body of ["Closes #40", LINK.replace("owner/repo", "evil/repo"), `Closes #40\n<!-- ${LINK} -->\n`, `Closes #40\n<!--\n${LINK}\n`]) {
    const { link, reads } = await decide(body);
    assert.equal(link, null, body);
    assert.deepEqual(reads, [], body);
  }
});

test("each failing condition of the gate's rule clears nothing", async () => {
  const cases = {
    "a decision on another issue": { closing: [{ number: 12, repository: { nameWithOwner: REPO } }] },
    "two closing issues": {
      closing: [
        { number: 40, repository: { nameWithOwner: REPO } },
        { number: 41, repository: { nameWithOwner: REPO } },
      ],
    },
    "a closing issue in another repository": { closing: [{ number: 40, repository: { nameWithOwner: "evil/repo" } }] },
    "a comment not on the linked issue": { row: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/41" }) },
    "a person not on the trusted-actor list": { row: comment({ user: { login: "someone", id: 6, type: "User" } }) },
    "a bot": { row: comment({ user: { login: "owner-person", id: 5, type: "Bot" } }) },
    "posted through an App": { row: comment({ performed_via_github_app: { slug: "cursor" } }) },
    edited: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } },
    "a null node": { node: null },
    "no lastEditedAt key": { node: {} },
    "no decision line": { row: comment({ body: "Sounds fine to me." }) },
    "a quoted decision": { row: comment({ body: "> **Decision recorded.** Cost: quoted" }) },
    "no cost marker": { row: comment({ body: "**Decision recorded.** Option 2." }) },
    "a cost marker on the next line": { row: comment({ body: "**Decision recorded.**\nCost: approve it." }) },
    "a decision older than the pull request": { row: comment({ created_at: "2026-10-21T09:00:00Z" }) },
    "a decision at the pull request's creation": { row: comment({ created_at: PR_CREATED }) },
    "no comment time": { row: comment({ created_at: null }) },
    "no pull request time": { created: "" },
    "an unreadable pull request": { fail: "pull" },
    "an unreadable comment": { fail: "GET /repos/owner/repo/issues/comments/7" },
    "an unreadable edit time": { fail: "edited" },
  };
  for (const [name, options] of Object.entries(cases)) {
    assert.equal((await decide(undefined, options)).link, null, name);
  }
});

test("a decision line after leading blank lines still counts", async () => {
  assert.equal((await decide(undefined, { row: comment({ body: "\n  **Decision recorded.**\tCost: yes for #99" }) })).link, LINK);
});

test("costHold holds a cost path, case-folded, until a decision", () => {
  for (const path of ["Pulumi.yaml", "infra/pulumi.Dev.yaml", "infra/.x/main.TF", "a.tfvars", "deploy/main.bicep", "deploy/main.bicepparam"]) {
    assert.match(costHold([path], null), new RegExp(`it changes ${path.replaceAll(".", "\\.")}, a cost path`), path);
    assert.equal(costHold([path], LINK), null, path);
  }
  // Owner ruling 2026-10-24: a model or effort default is no real charge.
  assert.equal(costHold(["docs/a.md", "plugins/multi-agent/reference/defaults.yaml", "Pulumi.md"], null), null);
  assert.equal(costHold(null, null), null);
});

// ci-status: merge-holds.mjs's command line on the live files, as the
// workflow step runs it, with a GitHub for the decision reads.
// A `files` entry is a path, or a files API row; `denied` is the config's
// denied paths; `writers` answers BODY_WRITERS_QUERY, or "fail"; `list`
// maps a ref (BASE, HEAD) to the trusted-actor list's text there.
function ci(files, { reviews = [], body = "Closes #40", options, denied = [], writers = "fail", head = HEAD, list = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "merge-holds-"));
  writeFileSync(join(dir, "body"), body);
  writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
  writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "owner-person", id: 5 }] }));
  writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(typeof row === "string" ? [row] : row)).join("\n"));
  writeFileSync(join(dir, "denied"), JSON.stringify(denied));
  const argv = ["99", ...["body", "discussion", "files", "denied", "actors"].map((name) => join(dir, name)), head];
  const { github: decisions } = world(options);
  const github = async (method, path, data) => {
    const listed = /^\/repos\/owner\/repo\/contents\/\.github\/standards\/trusted-actors\/trusted-actors\.json\?ref=([0-9a-f]{40})$/.exec(path);
    if (listed) {
      assert.equal(method, "GET");
      if (!(listed[1] in list)) {
        throw new Error("not found");
      }
      return { type: "file", encoding: "base64", content: Buffer.from(list[listed[1]]).toString("base64") };
    }
    if (data?.query !== BODY_WRITERS_QUERY) {
      return decisions(method, path, data);
    }
    assert.deepEqual(data.variables, { owner: "owner", name: "repo", number: 99 });
    if (writers === "fail") {
      throw new Error("unreadable");
    }
    return { data: { repository: { pullRequest: writers } } };
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  return main(argv, { env: { GITHUB_REPOSITORY: REPO, BASE_SHA: BASE }, github }).then(
    (code) => {
      console.log = log;
      return { code, out: lines.join("\n") };
    },
    (error) => {
      console.log = log;
      throw error;
    },
  );
}
const approve = { user: { login: "owner-person", id: 5, type: "User" }, state: "APPROVED", commit_id: HEAD, submitted_at: "2026-10-23T11:00:00Z" };

// Owner direction 2026-10-24: a trusted path alone holds nothing, and a
// manifest change is the security lane's finding, not a hold; a configured
// denied path still holds. Owner decision Q-FLOOR (B) keeps a narrow floor:
// resolve-config, request-lane-token, check-trusted-trigger,
// check-kill-switch, the rate guard, CODEOWNERS and .gitmodules hold with no
// configured glob, and so do the files that enforce it (owner decision
// Q-ENFORCE (A)); a trusted person's approval of the head lifts them as it
// lifts a configured one.
const FLOOR_FILES = [
  ".github/actions/resolve-config/resolve.mjs",
  ".github/actions/Resolve-Config/lane-rules.json",
  ".github/actions/request-lane-token/action.yml",
  ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
  ".github/actions/check-kill-switch/check-kill-switch.mjs",
  ".github/actions/log-api-budget/rate-guard.mjs",
  ".github/CODEOWNERS",
  "plugins/foo/codeowners",
  ".gitmodules",
  "vendor/sub/.gitmodules",
  ".github/scripts/pr-merge/merge-holds.mjs",
  ".github/scripts/pr-merge/enable-auto-merge.mjs",
  ".github/scripts/pr-merge/superseded.mjs",
  ".github/scripts/pr-merge/clear-escalations.mjs",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
  ".github/workflows/pr-require-checks.yml",
  "docs/conventions/pr-pipeline.yaml",
  ".github/scripts/pr-unblock/address-feedback.mjs",
  ".github/scripts/pr-unblock/gate-source.mjs",
  ".github/scripts/pr-unblock/thread-scope.mjs",
  ".github/scripts/work-resolve-issue/report-outcome.mjs",
  ".github/scripts/work-resolve-issue/limits.mjs",
];
test("ci-status holds each floor path with no configured glob, until a trusted person approves the head", async () => {
  for (const path of FLOOR_FILES) {
    const held = await ci([{ filename: path, status: "modified" }]);
    assert.equal(held.code, 1, `${path}: ${held.out}`);
    assert.ok(held.out.includes(`it changes ${path}, a hold path`), `${path}: ${held.out}`);
    const approved = await ci([{ filename: path, status: "modified" }], { reviews: [approve] });
    assert.equal(approved.code, 0, `${path}: ${approved.out}`);
    assert.match(approved.out, /owner-person approved this head, which lifts its hold path/);
  }
  const renamed = await ci([["docs/x.md", ".github/actions/check-kill-switch/action.yml", "renamed"]]);
  assert.equal(renamed.code, 1, renamed.out);
});

test("ci-status holds no other trusted path or manifest change, only a configured denied path", async () => {
  for (const path of [
    "plugins/foo/.claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    "docs/conventions/pr-pipeline/README.md",
    ".github/standards/trusted-actors/README.md",
    ".github/standards/trusted-actors/trusted-actors.schema.json",
    ".github/actions/log-api-budget/action.yml",
    ".github/actions/log-api-budget/rate-guard.test.mjs",
    ".github/actions/check-trusted-trigger-x/a.mjs",
    ".github/scripts/pr-merge/gate-check.mjs",
    "docs/CODEOWNERS.md",
  ]) {
    const passed = await ci([{ filename: path, status: "modified" }]);
    assert.equal(passed.code, 0, `${path}: ${passed.out}`);
    assert.match(passed.out, /no body hold, no member veto and no hold path\./);
  }
  const held = await ci([{ filename: "docs/held.md", status: "modified" }], { denied: ["docs/held.md"] });
  assert.equal(held.code, 1);
  assert.match(held.out, /it changes docs\/held\.md, a hold path/);
});

// The trust gate (babysit_risk._actors_widened, owner direction 2026-10-24):
// a change that adds or widens an entry of the trusted-actor list waits for
// the owner, and one that only removes entries does not. ci-status has no
// bypass, so the owner's approval of the head lifts it, as it lifts a hold
// path.
const ACTORS = ".github/standards/trusted-actors/trusted-actors.json";
const KYLE = { id: 1, login: "kyle", kind: "human" };
const LANES = { id: 2, login: "lanes[bot]", kind: "bot" };
const listOf = (...actors) => `${JSON.stringify({ version: 1, actors }, null, 2)}\n`;
test("ci-status holds a trusted-actor list widening until a trusted person approves the head, and passes a removal", async () => {
  const modified = [{ filename: ACTORS, status: "modified" }];
  const list = { [BASE]: listOf(KYLE), [HEAD]: listOf(KYLE, LANES) };
  const widened = await ci(modified, { list });
  assert.equal(widened.code, 1, widened.out);
  assert.match(widened.out, /it widens the trusted-actor list \(\.github\/standards\/trusted-actors\/trusted-actors\.json: entries added or changed: .*lanes\[bot\].*\); an approving review of this head/);
  const approved = await ci(modified, { list, reviews: [approve] });
  assert.equal(approved.code, 0, approved.out);
  assert.match(approved.out, /owner-person approved this head, which lifts its trusted-actor list hold/);
  const stranger = { ...approve, user: { login: "stranger", id: 9, type: "User" } };
  assert.equal((await ci(modified, { list, reviews: [stranger] })).code, 1);
  const changed = await ci(modified, { list: { [BASE]: listOf(KYLE, LANES), [HEAD]: listOf(KYLE, { ...LANES, kind: "human" }) } });
  assert.equal(changed.code, 1, changed.out);
  const removed = await ci(modified, { list: { [BASE]: listOf(KYLE, LANES), [HEAD]: listOf(KYLE) } });
  assert.equal(removed.code, 0, removed.out);
  assert.match(removed.out, /no body hold, no member veto and no hold path\./);
  // A side that does not read, a repeated key, or a rename holds.
  assert.equal((await ci(modified, { list: { [BASE]: listOf(KYLE, LANES) } })).code, 1);
  assert.equal((await ci(modified, { list: { [BASE]: listOf(KYLE, LANES), [HEAD]: listOf(KYLE).replace('"version": 1', '"version": 1, "version": 1') } })).code, 1);
  assert.equal((await ci([[ACTORS, ".github/standards/trusted-actors/old.json", "renamed"]], { list: { [BASE]: listOf(KYLE), [HEAD]: listOf(KYLE) } })).code, 1);
});

// A body's hold text counts only when a person wrote some of it.
test("a body hold counts only when a person wrote or edited the body", async () => {
  const body = "Closes #40\n\nHold: wait for the release.";
  const bot = { __typename: "Bot" };
  const appOnly = await ci(["docs/a.md"], { body, writers: { author: bot, userContentEdits: { totalCount: 0, nodes: [] } } });
  assert.equal(appOnly.code, 0, appOnly.out);
  assert.match(appOnly.out, /hold text is the lanes App's own/);
  const edited = await ci(["docs/a.md"], { body, writers: { author: bot, userContentEdits: { totalCount: 1, nodes: [{ editor: { __typename: "User" } }] } } });
  assert.equal(edited.code, 1);
  assert.match(edited.out, /its body holds it/);
  // An edit list not read whole, or a failed read, counts as a person.
  const cut = await ci(["docs/a.md"], { body, writers: { author: bot, userContentEdits: { totalCount: 101, nodes: [] } } });
  assert.equal(cut.code, 1);
  const unread = await ci(["docs/a.md"], { body, writers: "fail" });
  assert.equal(unread.code, 1);
});

test("ci-status holds a cost path that an approval does not lift, and the owner's decision does", async () => {
  const held = await ci(["infra/main.tf"]);
  assert.equal(held.code, 1);
  assert.match(held.out, /it changes infra\/main\.tf, a cost path/);
  const approved = await ci(["infra/main.tf"], { reviews: [approve] });
  assert.equal(approved.code, 1);
  assert.match(approved.out, /a cost path/);
  const decided = await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}` });
  assert.equal(decided.code, 0, decided.out);
  assert.match(decided.out, /no body hold, no member veto and no hold path\./);
  assert.equal((await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } } })).code, 1);
});

test("ci-status lifts a cost hold for the head the decision decided, and re-holds a later head with a change of its own", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: "**Decision recorded.** Cost: approve it." });
  const body = `Closes #40\n\n${own}`;
  assert.equal((await ci(["infra/main.tf"], { body, options: { row } })).code, 0);
  const later = await ci(["infra/main.tf"], { body, options: { row, comments: [marker(OLD)], compares: { [OLD]: net(TF), [HEAD]: net(TF, { filename: "infra/b.tf", status: "added", patch: "@@ -0,0 +1 @@\n+c" }) } } });
  assert.equal(later.code, 1, later.out);
  assert.match(later.out, /a cost path/);
  // The same decision on the closing issue, which names no pull request, holds.
  const unnamed = await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { row: comment({ body: "**Decision recorded.** Cost: approve it." }) } });
  assert.equal(unnamed.code, 1);
  assert.match(unnamed.out, /on its linked issue naming this pull request/);
});

// The carry rule (#9436 Q18 d): the decided head is OLD, the current HEAD.
const later = (compares, options = {}) => decide(undefined, { comments: [marker(OLD)], compares, ...options });

test("a base merge after the decision carries it, and a pull request commit after it re-holds", async () => {
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) })).link, LINK);
  const commit = await later({ [OLD]: net(TF), [HEAD]: net(TF, { filename: "scripts/run.sh", status: "modified", patch: "@@ -1 +1 @@\n-x\n+y" }) });
  assert.equal(commit.link, null);
  assert.deepEqual(commit.reads.slice(-4), ["marker edited", "deleted", `compare ${OLD}`, `compare ${HEAD}`]);
});

test("a rebase onto a newer base with the same net change carries, whatever order the files list in", async () => {
  const doc = { filename: "docs/a.md", status: "added", patch: "@@ -0,0 +1 @@\n+a" };
  assert.equal((await later({ [OLD]: net(TF, doc), [HEAD]: net(doc, TF) })).link, LINK);
  // A rebase that drops one of its files is a change of its own.
  assert.equal((await later({ [OLD]: net(TF, doc), [HEAD]: net(TF) })).link, null);
});

test("a conflict resolution, a rename or a status change that alters the net change re-holds", async () => {
  for (const [name, changed] of Object.entries({
    "an edited patch": { ...TF, patch: "@@ -1 +1 @@\n-a\n+c" },
    "a rename": { ...TF, status: "renamed", previous_filename: "infra/old.tf" },
    "a status": { ...TF, status: "added" },
  })) {
    assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(changed) })).link, null, name);
  }
});

test("a compare of 300 files or more, a file with no patch, a filename listed twice, an unusable base name or a failed read carries nothing", async () => {
  const many = (n) => net(...Array.from({ length: n }, (_, i) => ({ filename: `f${i}`, status: "added", patch: "+x" })));
  assert.equal((await later({ [OLD]: many(299), [HEAD]: many(299) })).link, LINK);
  assert.equal((await later({ [OLD]: many(300), [HEAD]: many(300) })).link, null);
  const binary = { filename: "a.png", status: "modified" };
  assert.equal((await later({ [OLD]: net(binary), [HEAD]: net(binary) })).link, null);
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) }, { fail: `compare ${HEAD}` })).link, null);
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: { status: "diverged" } })).link, null);
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) }, { fail: "comments" })).link, null);
  assert.equal((await later({ [OLD]: net(TF, TF), [HEAD]: net(TF, TF) })).link, null);
  // A patchless pure rename never carries.
  const moved = { filename: "b.tf", status: "renamed", previous_filename: "a.tf" };
  assert.equal((await later({ [OLD]: net(moved), [HEAD]: net(moved) })).link, null);
  for (const base of ["-main", "a..b", "a b", "", "x".repeat(256), null]) {
    const odd = await later({ [OLD]: net(TF), [HEAD]: net(TF) }, { base });
    assert.equal(odd.link, null, String(base));
    assert.ok(!odd.reads.some((read) => read.startsWith("compare")), String(base));
  }
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) }, { base: "release/2.x" })).link, LINK);
});

test("a comment deleted since the newest marker carries nothing, even at its own head", async () => {
  const same = { [OLD]: net(TF), [HEAD]: net(TF) };
  // Deleting the newer marker would make an older head the decided head.
  const promoted = await decide(undefined, { comments: [marker(OLD, "2026-10-22T10:30:00Z")], head: OLD, deleted: ["2026-10-22T11:45:00Z"] });
  assert.equal(promoted.link, null);
  assert.ok(!promoted.reads.some((read) => read.startsWith("compare")));
  assert.equal((await decide(undefined, { deleted: ["2026-10-22T11:00:00Z"] })).link, null);
  assert.equal((await later(same, { deleted: ["2026-10-22T11:30:00Z"] })).link, null);
  assert.equal((await decide(undefined, { fail: "deleted" })).link, null);
  assert.equal((await decide(undefined, { deleted: { filteredCount: 101, nodes: [{ createdAt: "2026-10-22T09:00:00Z" }] } })).link, null);
  // A deletion before the marker was posted does not stop it.
  assert.equal((await decide(undefined, { deleted: ["2026-10-22T10:59:59Z"] })).link, LINK);
  assert.equal((await later(same, { deleted: ["2026-10-22T09:00:00Z"] })).link, LINK);
  const items = (nodes, filteredCount = nodes.length) => ({ repository: { pullRequest: { timelineItems: { filteredCount, nodes } } } });
  assert.equal(deletedSince(items([]), "2026-10-22T11:00:00Z"), false);
  for (const [name, answer, at] of [
    ["no answer", undefined, "2026-10-22T11:00:00Z"],
    ["no time", items([]), null],
    ["an unparsed deletion time", items([{ createdAt: "soon" }]), "2026-10-22T11:00:00Z"],
    ["no count", { repository: { pullRequest: { timelineItems: { nodes: [] } } } }, "2026-10-22T11:00:00Z"],
  ]) {
    assert.equal(deletedSince(answer, at), true, name);
  }
});

test("an edited or unreadable newest marker carries nothing, and no older marker stands in", async () => {
  const same = { [OLD]: net(TF), [HEAD]: net(TF) };
  for (const [name, options] of Object.entries({
    edited: { markerNode: { lastEditedAt: "2026-10-22T11:05:00Z" } },
    "a null node": { markerNode: null },
    "no lastEditedAt key": { markerNode: {} },
    unreadable: { fail: "marker edited" },
  })) {
    // At the head it held, and after a base merge.
    assert.equal((await decide(undefined, options)).link, null, name);
    assert.equal((await later(same, options)).link, null, name);
  }
  // An older unedited marker at this head does not stand in for an edited newest one.
  const older = { comments: [marker(HEAD, "2026-10-22T10:00:00Z"), marker(OLD)], compares: same, markerNode: { lastEditedAt: "2026-10-22T11:05:00Z" } };
  assert.equal((await decide(undefined, older)).link, null);
});

test("at the decided head the decision carries with no compare read", async () => {
  const { link, reads } = await decide(undefined, { base: "" });
  assert.equal(link, LINK);
  assert.ok(!reads.some((read) => read.startsWith("compare")));
});

test("with no cost hold marker before the decision nothing carries, even at the same head", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: "**Decision recorded.** Cost: approve it." });
  for (const options of [{ row, closing: [] }, {}]) {
    const { link, reads } = await decide(options.row ? own : undefined, { ...options, comments: [] });
    assert.equal(link, null);
    assert.deepEqual(reads.slice(-1), ["comments"]);
  }
});

test("the decision is the newest on the pull request, else the newest on its linked issue", async () => {
  const onPull = (id) => `https://github.com/owner/repo/pull/99#issuecomment-${id}`;
  const rows = {
    7: comment({ created_at: "2026-10-22T12:00:00Z" }),
    8: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-22T11:00:00Z", node_id: "IC_7" }),
    9: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-22T11:30:00Z", node_id: "IC_7" }),
  };
  const pick = async (body, comments) => {
    const { github: base } = world({ comments, compares: { [OLD]: net(TF), [HEAD]: net(TF, { filename: "b.tf", status: "added", patch: "+b" }) } });
    const github = async (method, path, data) => {
      const id = /\/issues\/comments\/([0-9]+)$/.exec(path)?.[1];
      return id ? rows[id] : base(method, path, data);
    };
    return costDecision(github, REPO, 99, body, HUMANS, HEAD);
  };
  const all = `Closes #40\n${LINK}\n${onPull(8)}\n${onPull(9)}`;
  // The pull request's newest (9, at 11:30) is the one judged, over the issue's newer one.
  assert.equal(await pick(all, [marker(HEAD, "2026-10-22T11:15:00Z")]), onPull(9));
  // Its decided head is not this head, and the older one at this head is not consulted.
  assert.equal(await pick(all, [marker(HEAD, "2026-10-22T10:00:00Z"), marker(OLD, "2026-10-22T11:15:00Z")]), null);
  assert.equal(await pick(`Closes #40\n${LINK}`, [marker(HEAD)]), LINK);
});

test("the decided head is the latest bot cost hold marker made before the decision", async () => {
  const same = { [OLD]: net(TF), [HEAD]: net(TF, { filename: "b.tf", status: "added", patch: "+b" }) };
  // An older marker at the current head does not outweigh the latest one before the decision.
  assert.equal((await decide(undefined, { comments: [marker(HEAD, "2026-10-22T10:30:00Z"), marker(OLD, "2026-10-22T11:30:00Z")], compares: same })).link, null);
  assert.equal((await decide(undefined, { comments: [marker(OLD, "2026-10-22T10:30:00Z"), marker(HEAD, "2026-10-22T11:30:00Z")], compares: same })).link, LINK);
  // A marker after the decision, by a person, or without cost decides nothing.
  for (const [name, extra] of Object.entries({
    after: marker(HEAD, "2026-10-22T12:30:00Z"),
    "a person": marker(HEAD, "2026-10-22T11:30:00Z", { user: { login: "owner-person", id: 5, type: "User" } }),
    "another bot": marker(HEAD, "2026-10-22T11:30:00Z", { user: { login: "claude[bot]", id: 9, type: "Bot" } }),
    "not on the first line": { ...marker(HEAD, "2026-10-22T11:30:00Z"), body: `Held.\n<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost -->` },
    "not cost": marker(HEAD, "2026-10-22T11:30:00Z", { criteria: "trust-gate" }),
  })) {
    assert.equal((await decide(undefined, { comments: [marker(OLD), extra], compares: same })).link, null, name);
  }
  assert.equal((await decide(undefined, { comments: [marker(OLD), marker(HEAD, "2026-10-22T11:30:00Z", { criteria: "cost,trust-gate" })], compares: same })).link, LINK);
  assert.deepEqual(costMarker([marker(OLD), marker(HEAD, "2026-10-22T11:30:00Z")], "2026-10-22T11:30:00Z"), { sha: OLD, node: "IC_M", at: "2026-10-22T11:00:00Z" });
  // Of two at one time, the first listed wins, as in the hold step.
  assert.equal(costMarker([marker(OLD), marker(HEAD)], "2026-10-22T12:00:00Z").sha, OLD);
  assert.equal(costMarker([], "2026-10-22T12:00:00Z"), null);
});

test("sameNetChange compares filename, status, previous_filename and patch", () => {
  assert.equal(sameNetChange(net(TF), net({ ...TF })), true);
  assert.equal(sameNetChange(net(), net()), true);
  assert.equal(sameNetChange(net(TF), net({ ...TF, previous_filename: "x.tf" })), false);
  assert.equal(sameNetChange(null, net(TF)), false);
});

// The live link a pass binds, by the gate's rule (README "Eligibility"): one
// closing issue in this repository, or, with none, one plain `Refs: #<n>`
// issue; a pass binds only the issue it judged, linked the same way
// (babysit_verify_evidence.py _pass_refusal: verify:spec-changed otherwise).
test("linkHold binds a pass to the issue and link kind it judged", () => {
  const closes = (...numbers) => ({ totalCount: numbers.length, nodes: numbers.map((number) => ({ number, repository: { nameWithOwner: "o/r" } })) });
  const record = (number, spec_kind) => ({ linked_issues: [{ number }], ...(spec_kind ? { spec_kind } : {}) });
  assert.equal(linkHold(record(5, "closes"), "Closes #5", closes(5), "o/r"), null);
  // A record from before the kind was written judged a closing issue.
  assert.equal(linkHold(record(5), "Closes #5", closes(5), "O/R"), null);
  assert.equal(linkHold(record(5, "refs"), "Refs: #5\n\n## Summary", closes(), "o/r"), null);
  assert.match(linkHold(record(5, "refs"), "Closes #6", closes(6), "o/r"), /link changed since pr-verify passed it: it closes #6, and the pass judged #5 \(refs\)/);
  assert.match(linkHold(record(5, "refs"), "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "closes"), "Refs: #5", closes(), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "refs"), "Refs: #6", closes(), "o/r"), /refs #6, and the pass judged #5/);
  // A link of several issues that still names the judged one binds; the
  // fix loop rewrites it. A link that drops the judged issue holds, and so
  // does one removed, a Refs: line hidden in a comment included.
  assert.equal(linkHold(record(5, "refs"), "Refs: #5\nRefs: #6", closes(), "o/r"), null);
  assert.equal(linkHold(record(5, "closes"), "Closes #5", closes(5, 6), "o/r"), null);
  assert.match(linkHold(record(5, "closes"), "Closes #6", closes(6, 7), "o/r"), /it closes #6, #7, and the pass judged #5/);
  assert.match(linkHold(record(5, "closes"), "", closes(), "o/r"), /it refs no issue, and the pass judged #5 \(closes\)/);
  assert.match(linkHold(record(5, "refs"), "## Summary", closes(), "o/r"), /it refs no issue, and the pass judged #5 \(refs\)/);
  assert.match(linkHold(record(5, "refs"), "<!-- Refs: #5 -->", closes(), "o/r"), /it refs no issue/);
  assert.match(linkHold(record(5, "refs"), "Refs: #6\nRefs: #7", closes(), "o/r"), /it refs #6, #7, and the pass judged #5/);
  assert.match(linkHold(record(5, "refs"), "Refs: x/y#5", closes(), "o/r"), /it refs no issue/);
  // A pass judged as a Refs slice never covers a body that closes the issue,
  // with other issues or alone.
  assert.match(linkHold(record(5, "refs"), "Closes #5, #6", closes(5, 6), "o/r"), /it closes #5, #6, and the pass judged #5 \(refs\)/);
  // Closing issues all in another repository drop the judged one.
  const foreign = { number: 5, repository: { nameWithOwner: "x/y" } };
  assert.match(linkHold(record(5, "closes"), "Closes x/y#5", { totalCount: 1, nodes: [foreign] }, "o/r"), /it closes x\/y#5, and the pass judged #5/);
  assert.equal(linkHold(record(5, "closes"), "Closes x/y#5\nCloses #5", { totalCount: 2, nodes: [foreign, ...closes(5).nodes] }, "o/r"), null);
  assert.match(linkHold(record(5, "pull-request"), "", closes(), "o/r"), /kind 'pull-request'/);
  assert.match(linkHold(null, "Closes #5", closes(5), "o/r"), /record could not be read/);
  assert.match(linkHold({ linked_issues: [{ number: 5 }, { number: 6 }] }, "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5), "Closes #5", { totalCount: 11, nodes: [] }, "o/r"), /closing issues could not be read/);
});

// ci-status writes [filename, previous_filename, status]; an older line has
// no status, which holds a manifest.
test("changeOf reads a files line with and without its status", () => {
  assert.deepEqual(changeOf(["a.md", null, "modified"]), { path: "a.md", previous: null, status: "modified" });
  assert.deepEqual(changeOf(["b.md", "a.md", "renamed"]), { path: "b.md", previous: "a.md", status: "renamed" });
  assert.deepEqual(changeOf(["b.md", "a.md"]), { path: "b.md", previous: "a.md", status: null });
  assert.deepEqual(changeOf(["a.md"]), { path: "a.md", previous: null, status: null });
  assert.throws(() => changeOf("a.md"), /does not read/);
});
