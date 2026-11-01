// Expected values come from the native-merge plan's arm-merge item and the
// owner answers on it: a lanes App pull request is armed for native auto-merge (squash, at the head
// read) with no session, and is never armed, or is disarmed, while it carries
// a `Hold:` line, do-not-merge or the human-gated label. Its issue link is
// the gate's own rule (docs/conventions/pr-pipeline/README.md, "Eligibility":
// one closing issue, or one plain `Refs: #<n>` issue), read through the gate's
// Python, as is the body hold, babysit_merge_policy.BODY_MERGE_HOLD_RE, so
// the parity tests read their verdicts from Python.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
  ARM_MUTATION,
  AUTO_MERGE_STATE_QUERY,
  BODY_HOLD,
  DETAIL_QUERY,
  DISARM_MUTATION,
  DISCUSSION_PAGE_QUERIES,
  rotated,
  HUMAN_VETO,
  PULLS_QUERY,
  THREAD_PAGE_QUERY,
  UNLABELED_QUERY,
  decide,
  describe,
  holdReason,
  unblockHold,
  liftedByPerson,
  READER_EVENTS,
  personReason,
  holdPathOnly,
  isPartial,
  refusalBody,
  refusalReasons,
  refusalWrites,
  main,
  pythonClose,
  pythonRoom,
  pythonVerify,
  pythonWholeReview,
  recordLines,
  WHOLE_REVIEW_RECORD,
  ReaderRateLimited,
  costLine,
  cacheLine,
  CACHE_ONLY_TIMEOUT_MS,
  CACHE_ONLY_WINDOW_MS,
  ghCalls,
  ghCallsLine,
  listingMissLines,
  LANE_ROOM_TIMEOUT_MS,
  VERIFY_TIMEOUT_MS,
  VERIFY_BUDGET_MS,
  readRoom,
  TRUST_REFUSALS,
  FILES_CAPPED_REASON,
  UNARMED_OUTPUT,
  verifyClears,
  verifyHold,
  SKIP_STATE_PREFIX,
} from "./enable-auto-merge.mjs";
import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { COMMENT_EDITED_QUERY, LANE_HOLD, PULL_OPENED_QUERY, VERIFY_PATH, personWrote, unblockStops, verdictHold } from "./merge-holds.mjs";
import { VERIFY_PATH as RESOLVER_VERIFY_PATH } from "../pr-verify/resolve-pr.mjs";
import { HOLD_LINE, decide as decideOutcome } from "../work-resolve-issue/report-outcome.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LANES = { __typename: "Bot", login: "melodic-automation-lanes" };
const HEAD = "b".repeat(40);
const ENV = {
  EVENT_NAME: "schedule",
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  REPORT_ONLY: "false",
  LANES_BOT_LOGIN: "melodic-automation-lanes[bot]",
  TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json",
  RESOLVED_CONFIG: fileURLToPath(new URL("./fixtures/enable-auto-merge-resolved.json", import.meta.url)),
};

const pull = (number, overrides = {}) => ({
  id: `PR_${number}`,
  number,
  isDraft: false,
  isCrossRepository: false,
  headRefOid: HEAD,
  baseRefOid: "d".repeat(40),
  body: `Closes #${number + 1000}\n\n## Summary\n\nDone.`,
  author: LANES,
  labels: { totalCount: 0, nodes: [] },
  autoMergeRequest: null,
  ...overrides,
});
// One pull request's comments, reviews, inline comments and newest
// auto-merge-disabled event, as DETAIL_QUERY returns them.
const page = (nodes = []) => ({ totalCount: nodes.length, nodes });
function detail({ comments = [], reviews = [], inline = [], disabledBy = null } = {}) {
  return {
    comments: page(comments),
    reviews: page(reviews),
    reviewThreads: page(inline.length ? [{ comments: page(inline) }] : []),
    timelineItems: { nodes: disabledBy ? [{ actor: disabledBy }] : [] },
    // The head's pr-unblock stops (merge-holds.unblockStops): none.
    unblockStops: [],
  };
}
const said = (login, body, at, association = "OWNER", typename = "User") => ({
  author: { __typename: typename, login },
  body,
  createdAt: at,
  authorAssociation: association,
});
// `evidence --lane-queue`: a head the merge queue has not removed for failed checks.
const UNEJECTED = { failedEjections: 0, limit: 2, refusal: null, comment: null };
const PASSED = { refusal: null, head: HEAD, ineligible: null, reviews: null, queue: UNEJECTED };
const COST_LINK = `https://github.com/${REPO}/issues/1040#issuecomment-7`;
const COST_COMMENT = {
  issue_url: `https://api.github.com/repos/${REPO}/issues/1040`,
  user: { login: "kyle-sexton", id: 5, type: "User" },
  performed_via_github_app: null,
  body: "**Decision recorded.** Cost: approve it for #40.",
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
};
// lane-room's answer for a lane with room: nothing in flight of five.
const ROOM = { refusal: null, unreadable: null, count: 0, cap: 5, queued: [], rung: "C2" };
const room = (answer = ROOM) => async () => answer;
const labels = (...names) => ({ totalCount: names.length, nodes: names.map((name) => ({ name })) });

// armErrors and disarmErrors: per pull request id, the errors its arm or
// disarm sends throw, in order.
// filesError: what every changed-files GET throws.
// A pull request's `after` is its auto-merge state as the read-back sees it
// (AUTO_MERGE_STATE_QUERY), else its listed state; `after: "error"` fails the read.
function world(pulls, { failArm = false, armErrors = {}, disarmErrors = {}, filesError = null, noteErrors = [], disarmError = null, pinError = null } = {}) {
  const pins = [];
  const noteThrows = [...noteErrors];
  const armThrows = Object.fromEntries(Object.entries(armErrors).map(([id, errors]) => [id, [...errors]]));
  const disarmThrows = Object.fromEntries(Object.entries(disarmErrors).map(([id, errors]) => [id, [...errors]]));
  const calls = [];
  const notes = [];
  const github = async (method, path, body, headers) => {
    calls.push({ method, path, body, headers });
    // A pull request's own REST answers (`rest`, by path), such as the
    // reads of a lift carried over base merges (merge-holds.liftersOf).
    const own = method === "GET" ? pulls.find((candidate) => candidate.rest && path in candidate.rest) : undefined;
    if (own) {
      return own.rest[path];
    }
    // A lift's reads (liftBlocked): the issue timeline (`timeline`; with none
    // the read fails), review comments (`threadComments`), reviews
    // (`restReviews`), and the head read again before the delete (`freshHead`,
    // else the head).
    const lift = /^\/repos\/melodic-software\/claude-code-plugins\/(?:issues\/([0-9]+)\/timeline\?|pulls\/([0-9]+)\/comments\?since=[^&]+&|pulls\/([0-9]+)\/reviews\?|pulls\/([0-9]+)$)/.exec(path);
    if (method === "GET" && lift) {
      const found = pulls.find((candidate) => [lift[1], lift[2], lift[3], lift[4]].includes(String(candidate.number)));
      if (lift[1] !== undefined && found?.timeline === undefined) {
        throw new Error("GET timeline failed with status 502");
      }
      return lift[1] !== undefined ? found.timeline : lift[2] !== undefined ? (found?.threadComments ?? []) : lift[3] !== undefined ? (found?.restReviews ?? []) : { head: { sha: found?.freshHead ?? found?.headRefOid } };
    }
    const listing = /^\/repos\/melodic-software\/claude-code-plugins\/pulls\/([0-9]+)\/files\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && listing && filesError) {
      throw filesError;
    }
    if (method === "GET" && listing) {
      const files = pulls.find((candidate) => candidate.number === Number(listing[1]))?.files ?? [{ filename: "plugins/work-items/README.md" }];
      return files.slice((Number(listing[2]) - 1) * 100, Number(listing[2]) * 100);
    }
    // The head's commit statuses: a pull request's `statuses`, none by
    // default; `statuses: "error"` fails the read.
    const statusPage = /^\/repos\/melodic-software\/claude-code-plugins\/commits\/([0-9a-f]{40})\/statuses\?per_page=100&page=1$/.exec(path);
    if (method === "GET" && statusPage) {
      const statuses = pulls.find((candidate) => candidate.headRefOid === statusPage[1])?.statuses ?? [];
      if (statuses === "error") {
        throw new Error("GET statuses failed with status 502");
      }
      return statuses;
    }
    // The cost decision reads (merge-holds.costDecision): the owner's comment
    // 7 on pull request 40's closing issue, and each pull request closes its own
    // number plus 1000.
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/issues/comments/7") {
      return COST_COMMENT;
    }
    // Its decided head: the code review lane's status job noticed a cost
    // hold at the head before it; the security lane has no run.
    const runs = /^\/repos\/melodic-software\/claude-code-plugins\/actions\/workflows\/([a-z-]+)\.yml\/runs\?event=pull_request&branch=fix%2Fcost&per_page=100&page=1$/.exec(path);
    if (method === "GET" && runs) {
      return { workflow_runs: runs[1] === "pr-review-hosted" ? [{ id: 9, head_sha: HEAD, head_repository: { full_name: REPO }, created_at: "2026-10-22T10:50:00Z" }] : [] };
    }
    // The head branch's push history: the head, pushed before its run.
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/activity?ref=refs%2Fheads%2Ffix%2Fcost&direction=desc&per_page=100") {
      return [{ after: HEAD, timestamp: "2026-10-22T10:45:00Z", activity_type: "push", ref: "refs/heads/fix/cost" }];
    }
    // main resolves to its tip commit, which the lane-change vet compares.
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/git/ref/heads/main") {
      return { ref: "refs/heads/main", object: { type: "commit", sha: "3".repeat(40) } };
    }
    if (method === "GET" && path === `/repos/melodic-software/claude-code-plugins/compare/${"3".repeat(40)}...${HEAD}`) {
      return { files: [{ filename: "infra/main.tf" }] };
    }
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/actions/runs/9/jobs?filter=all&per_page=100&page=1") {
      return { jobs: [{ id: 90, name: "pr-review / claude-review-status", completed_at: "2026-10-22T11:00:00Z" }] };
    }
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/check-runs/90/annotations?per_page=100&page=1") {
      return [{ annotation_level: "notice", message: `claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost label=needs-human` }];
    }
    // A pull request's whole label list, when its listing cut it.
    const labelPage = /^\/repos\/melodic-software\/claude-code-plugins\/issues\/([0-9]+)\/labels\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && labelPage) {
      // With no `allLabels`, the read fails, so the list stays cut.
      const all = pulls.find((candidate) => candidate.number === Number(labelPage[1]))?.allLabels;
      if (all === undefined) {
        throw new Error("GET labels failed with status 502");
      }
      return all.slice((Number(labelPage[2]) - 1) * 100, Number(labelPage[2]) * 100).map((name) => ({ name }));
    }
    // The read-back pin, posted before an arm.
    if (method === "POST" && String(body?.body ?? "").startsWith("<!-- babysit-merge-pin ")) {
      pins.push({ path, body: body.body });
      if (pinError) {
        throw pinError;
      }
      return {};
    }
    // The refusal note: a comment posted or edited, and the label.
    const note = /^\/repos\/melodic-software\/claude-code-plugins\/issues\/(?:([0-9]+)\/(comments|labels)|comments\/([0-9]+))$/.exec(path);
    if (note && (method === "POST" || method === "PATCH")) {
      notes.push({ method, path, body });
      if (noteThrows.length > 0) {
        throw noteThrows.shift();
      }
      return {};
    }
    // The lane lifting the human-gated label (approvalLift).
    if (method === "DELETE" && /^\/repos\/melodic-software\/claude-code-plugins\/issues\/[0-9]+\/labels\/[^/]+$/.test(path)) {
      notes.push({ method, path });
      return [];
    }
    assert.equal(`${method} ${path}`, "POST /graphql");
    if (body.query === PULL_OPENED_QUERY) {
      const nodes = [{ number: body.variables.number + 1000, repository: { nameWithOwner: REPO } }];
      return { data: { repository: { pullRequest: { createdAt: "2026-10-22T10:00:00Z", baseRefName: "main", headRefName: "fix/cost", closingIssuesReferences: { totalCount: 1, nodes } } } } };
    }
    if (body.query === COMMENT_EDITED_QUERY) {
      return { data: { node: { lastEditedAt: null } } };
    }
    if (body.query === PULLS_QUERY) {
      assert.deepEqual(body.variables, { owner: "melodic-software", name: "claude-code-plugins", after: null });
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    // The skip key's state read (SKIP_STATE_QUERY): each pull request's
    // listed head and update time, and its `rollup` (none by default).
    if (String(body.query).startsWith(SKIP_STATE_PREFIX)) {
      const repository = Object.fromEntries(
        [...body.query.matchAll(/p([0-9]+): pullRequest/g)].map(([, n]) => {
          const found = pulls.find((candidate) => candidate.number === Number(n));
          const rollup = found?.rollup ?? { contexts: { totalCount: 0, nodes: [] } };
          const none = { totalCount: 0, nodes: [] };
          return [
            `p${n}`,
            {
              number: Number(n),
              headRefOid: found?.headRefOid,
              updatedAt: found?.updatedAt,
              reviewDecision: found?.reviewDecision ?? null,
              reviews: { totalCount: found?.reviewCount ?? 0 },
              comments: found?.stateComments ?? none,
              reviewThreads: found?.stateThreads ?? none,
              commits: { nodes: [{ commit: { oid: found?.headRefOid, statusCheckRollup: rollup } }] },
            },
          ];
        }),
      );
      return { data: { repository } };
    }
    if (body.query === UNLABELED_QUERY) {
      const nodes = pulls.find((candidate) => candidate.number === body.variables.number)?.unlabeled ?? [];
      return { data: { repository: { pullRequest: { timelineItems: { totalCount: nodes.length, nodes } } } } };
    }
    if (body.query === DETAIL_QUERY) {
      const found = pulls.find((candidate) => candidate.number === body.variables.number);
      // `graphFiles`: the changed files the query lists, absent by default.
      const read = found?.cutDiscussion ?? detail(found?.discussion);
      return { data: { repository: { pullRequest: found?.graphFiles === undefined ? read : { ...read, files: found.graphFiles } } } };
    }
    // The rest of a cut comment list, two to a page.
    if (body.query === DISCUSSION_PAGE_QUERIES.comments) {
      const all = pulls.find((candidate) => candidate.number === body.variables.number)?.discussion?.comments ?? [];
      const start = body.variables.after === null ? 0 : Number(body.variables.after);
      const nodes = all.slice(start, start + 2);
      return { data: { repository: { pullRequest: { comments: { totalCount: all.length, pageInfo: { hasNextPage: start + 2 < all.length, endCursor: String(start + 2) }, nodes } } } } };
    }
    // The rest of a cut review thread's comments, by the thread's id, two to
    // a page.
    if (body.query === THREAD_PAGE_QUERY) {
      const all = pulls.flatMap((candidate) => Object.entries(candidate.threads ?? {})).find(([id]) => id === body.variables.id)?.[1] ?? [];
      const start = body.variables.after === null ? 0 : Number(body.variables.after);
      const nodes = all.slice(start, start + 2);
      return { data: { node: { comments: { totalCount: all.length, pageInfo: { hasNextPage: start + 2 < all.length, endCursor: String(start + 2) }, nodes } } } };
    }
    if (body.query === ARM_MUTATION && armThrows[body.variables.id]?.length > 0) {
      throw armThrows[body.variables.id].shift();
    }
    if (body.query === AUTO_MERGE_STATE_QUERY) {
      const found = pulls.find((candidate) => candidate.id === body.variables.id);
      if (found?.after === "error") {
        throw new GitHubError(502, "POST /graphql");
      }
      return { data: { node: found?.after ?? { state: "OPEN", headRefOid: found?.headRefOid, autoMergeRequest: found?.autoMergeRequest ?? null } } };
    }
    if (body.query === DISARM_MUTATION && disarmThrows[body.variables.id]?.length > 0) {
      throw disarmThrows[body.variables.id].shift();
    }
    if (body.query === DISARM_MUTATION && disarmError) {
      throw disarmError;
    }
    if (body.query === ARM_MUTATION && failArm) {
      throw new Error("POST /graphql (GraphQL errors) failed with status 200");
    }
    return { data: {} };
  };
  // The gate's verifier evidence: a pull request's `verdict` (a report, an
  // Error to throw, or a function of the read's options), else a pass at its
  // head.
  const verified = [];
  const verify = async ({ number, headRefOid: head }, _rung, options) => {
    verified.push(number);
    const found = pulls.find((candidate) => candidate.number === number);
    if (found?.verdict instanceof Error) {
      throw found.verdict;
    }
    if (typeof found?.verdict === "function") {
      return found.verdict(options ?? {});
    }
    return found?.verdict ?? { refusal: null, head, ineligible: null, reviews: null, queue: UNEJECTED };
  };
  const writes = () =>
    calls
      .filter(({ method, path, body }) => method === "POST" && path === "/graphql" && ![PULLS_QUERY, DETAIL_QUERY, PULL_OPENED_QUERY, COMMENT_EDITED_QUERY, UNLABELED_QUERY, DISCUSSION_PAGE_QUERIES.comments, THREAD_PAGE_QUERY, AUTO_MERGE_STATE_QUERY].includes(body.query) && !String(body.query).startsWith(SKIP_STATE_PREFIX))
      .map(({ body }) => ({ mutation: body.query === ARM_MUTATION ? "arm" : body.query === DISARM_MUTATION ? "disarm" : "?", ...body.variables }));
  return { github, writes, verify, verified, calls, notes, pins };
}

// babysit_whole_review.py stood in for: each call in order, as
// [kind, argument], with `request` answering options.request (default a skip
// at the sweep limit), `toggle` options.toggle and `recover` its drafts ready.
function wholeReview(options, notes) {
  const asked = [];
  return {
    asked,
    request: (pull, prior) => {
      asked.push(["request", pull.number, prior, notes.length]);
      if (typeof options.request === "function") {
        return options.request();
      }
      return options.request === undefined ? { toggled: false, skipped: "sweep-limit" } : options.request;
    },
    toggle: (pull, humanGated) => {
      asked.push(["toggle", pull.number, notes.length, humanGated]);
      return options.toggle ?? { toggled: true };
    },
    recover: (drafts) => {
      asked.push(["recover", drafts]);
      return drafts.map((draft) => ({ pr: draft.number, head: draft.head, ready: true }));
    },
  };
}

async function run(pulls, env = {}, options = {}, lane = ROOM) {
  const { github, writes, verify, verified, calls, notes, pins } = world(pulls, options);
  const whole = wholeReview(options, notes);
  const lines = [];
  const slept = [];
  const output = join(tempDir("enable-auto-merge-"), "output");
  writeFileSync(output, "");
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const actions = options.jobToken ? options.jobToken(github) : undefined;
    const closed = [];
    const close = async (pull, holds) => {
      closed.push({ number: pull.number, holds });
      return options.closeAnswer ? options.closeAnswer(pull) : { closed: true, restarted: [], parked: [] };
    };
    const code = await main({ env: { ...ENV, GITHUB_OUTPUT: output, ...env }, github, actions, verify, room: room(lane), close, whole, sleep: async (ms) => slept.push(ms), random: options.random, now: options.now ?? (() => Date.parse(NOW)), mainInputs: options.mainInputs });
    // The `pr-merge/unarmed` statuses the run hands the status job.
    const line = readFileSync(output, "utf8").split("\n").find((text) => text.startsWith(`${UNARMED_OUTPUT}=`));
    const statuses = line === undefined ? [] : JSON.parse(line.slice(UNARMED_OUTPUT.length + 1));
    return { code, writes: writes(), lines, verified, slept, calls, notes, pins, statuses, closed, asked: whole.asked };
  } finally {
    console.log = log;
  }
}

// The refusal note's two bodies, written out by hand: the gate's reasons
// marker on its own line, the head named on the next, the reason fenced.
// The run's clock, and so the time a lane comment first noted its head.
const NOW = "2026-10-23T10:00:00.000Z";
const laneNote = (reason, since = NOW) =>
  [
    "<!-- babysit-merge-risk -->",
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${HEAD}\`. The lanes clear this reason on their own; the next scheduled run judges it again.`,
    "",
    "```text",
    reason,
    "```",
      `<!-- pr-merge-unarmed-since head=${HEAD} at=${since} -->`,
  ].join("\n");
// `partial`: written without the verifier's answer, so its last line marks it
// for the one read that widens it.
const personNote = (reason, partial = false) =>
  [
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->",
    "<!-- babysit-merge-risk -->",
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${HEAD}\`. A person must clear this reason, so the pr-merge lane added the \`needs-human\` label: fix the reason, then remove the label, and the next scheduled run judges it again.`,
    "",
    "```text",
    reason,
    "```",
    ...(partial ? [`<!-- pr-merge-partial head=${HEAD} -->`] : []),
  ].join("\n");
const ISSUES = "/repos/melodic-software/claude-code-plugins/issues";
const lanesSaid = (body, updatedAt = "2026-10-23T10:00:00Z") => ({
  databaseId: 77,
  author: { __typename: "Bot", login: LANES.login },
  body,
  createdAt: "2026-10-23T10:00:00Z",
  updatedAt,
  authorAssociation: "NONE",
});
const HOLD_PATH_REASON = "it changes docs/held.md, a hold path";
// A real charge, a cause a person must clear (owner direction 2026-10-24).
const COST_REASON = "it changes infra/main.tf, a cost path";
const COST_FILES = [{ filename: "infra/main.tf" }];
const MISSING = { refusal: "verify:missing", needsHuman: false, head: HEAD, ineligible: null, reviews: null };
const MISSING_REASON = "pr-merge's gate refuses its verifier verdict (verify:missing)";

test("a refusal a person must clear, a cost path or a configured denied path, is commented on and labeled human-gated", async () => {
  const { code, writes, notes } = await run([pull(1, { files: COST_FILES }), pull(2, { files: [{ filename: "docs/held.md" }] })]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(COST_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: personNote(HOLD_PATH_REASON) } },
    { method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } },
  ]);
});

// GitHub Support's audit item 2: the discussion read lists the changed files
// too, so a head whose files fit one page and include no rename (whose old
// path only the REST listing names) reads no files page.
const filesPages = (calls) => calls.filter(({ path }) => /\/pulls\/[0-9]+\/files\?/.test(path)).length;
test("the discussion read's file list stands in for the files page, unless a rename or a cut list needs it", async () => {
  const listed = (...nodes) => ({ totalCount: nodes.length, nodes });
  const folded = await run([pull(1, { graphFiles: listed({ path: "infra/main.tf", changeType: "MODIFIED" }), files: [] })]);
  assert.equal(filesPages(folded.calls), 0);
  assert.deepEqual(folded.notes.slice(0, 1), [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(COST_REASON) } }]);
  // A rename away from a cost path: only the REST page names the old path.
  const renamed = await run([pull(1, { graphFiles: listed({ path: "docs/main.md", changeType: "RENAMED" }), files: [{ filename: "docs/main.md", previous_filename: "infra/main.tf" }] })]);
  assert.equal(filesPages(renamed.calls), 1);
  assert.deepEqual(renamed.notes.slice(0, 1), [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(COST_REASON) } }]);
  // A list longer than the query read.
  const cut = await run([pull(1, { graphFiles: { totalCount: 101, nodes: [{ path: "docs/a.md", changeType: "MODIFIED" }] }, files: COST_FILES })]);
  assert.equal(filesPages(cut.calls), 1);
  assert.deepEqual(cut.notes.slice(0, 1), [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(COST_REASON) } }]);
});

// Owner decision Q26 option B: the gate holds an enforcement floor path as
// `review-path:` until the security review binds clean to the head; the lanes
// run that review, so the refusal gets the comment and no label.
test("an enforcement floor path the gate holds for its security review is a lane's refusal", async () => {
  const reviews = "review-path:.github/scripts/work-resolve-issue/limits.mjs: .github/scripts/work-resolve-issue/limits.mjs; a clean claude-security-review bound to this head clears it";
  const verdict = { refusal: null, needsHuman: false, reviewsPerson: false, head: HEAD, ineligible: null, reviews };
  const { writes, notes } = await run([pull(1, { files: [{ filename: ".github/scripts/work-resolve-issue/limits.mjs" }], verdict })]);
  assert.deepEqual(writes, []);
  const wrapped = [
    "pr-merge's gate holds it on its risk score",
    "  (review-path:.github/scripts/work-resolve-issue/limits.mjs:",
    "  .github/scripts/work-resolve-issue/limits.mjs; a clean claude-security-review bound to this head",
    "  clears it)",
  ];
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(wrapped.join("\n")) } }]);
});

// #10908: a `review-path:` hold whose security findings the lanes App
// resolved clears only on a clean whole review of the head, and under
// merge.lane-prs native the merge gate, which requests one for its own
// candidates, never lists a lanes App pull request. The run makes the gate's
// request (babysit_whole_review.py): its record line goes in the lane's
// comment first, then the draft toggle starts the whole review.
const PATH_HOLD = "review-path:.github/scripts/pr-unblock/gate-source.mjs: .github/scripts/pr-unblock/gate-source.mjs; a clean claude-security-review bound to this head clears it";
const PATH_REASON = `pr-merge's gate holds it on its risk score (${PATH_HOLD})`;
// PATH_REASON as the comment wraps it at 100 columns.
const PATH_NOTE = [
  "pr-merge's gate holds it on its risk score (review-path:.github/scripts/pr-unblock/gate-source.mjs:",
  "  .github/scripts/pr-unblock/gate-source.mjs; a clean claude-security-review bound to this head",
  "  clears it)",
].join("\n");
const PATH_HELD = { refusal: null, needsHuman: false, head: HEAD, ineligible: null, reviews: PATH_HOLD, reviewsPerson: false, wholeReviewWanted: true, queue: UNEJECTED };
// babysit_whole_review.record_line's shape, checked against it below.
const recordAt = (head, at) => `Whole review requested at head \`${head}\` at ${at}: an incremental review cannot clear the findings below.`;
const RECORD = recordAt(HEAD, "2026-10-23T10:00:00Z");
const withRecords = (body, records) => body.replace(/\n(<!-- pr-merge-unarmed-since [^\n]*)$/, `\n\n${records.join("\n")}\n$1`);

test("a lane's risk hold a whole review clears gets the gate's request: the record in its comment, then the toggle", async () => {
  const { code, notes, asked } = await run([pull(1, { verdict: PATH_HELD })], {}, { request: { line: RECORD } });
  assert.equal(code, 0);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: withRecords(laneNote(PATH_NOTE), [RECORD]) } }]);
  // The prior comment (none) goes to `request`; the toggle follows the write.
  assert.deepEqual(asked, [
    ["request", 1, "", 0],
    ["toggle", 1, 1, "needs-human"],
  ]);
});

test("a whole review is requested only for a lane's risk hold the gate says one clears, and only by a writing reader run", async () => {
  const cases = {
    "not wanted": [{ ...PATH_HELD, wholeReviewWanted: false }, {}],
    "a person's hold": [{ ...PATH_HELD, reviewsPerson: true }, {}],
    "report-only": [PATH_HELD, { REPORT_ONLY: "true" }],
    "an event run": [PATH_HELD, { EVENT_NAME: "pull_request_target", EVENT_PR: "1" }],
  };
  for (const [name, [verdict, env]] of Object.entries(cases)) {
    const { asked } = await run([pull(1, { verdict })], env, { request: { line: RECORD } });
    assert.deepEqual(asked, [], name);
  }
});

test("a request the gate's caps refuse writes the comment with no record and toggles nothing", async () => {
  const { notes, asked, lines } = await run([pull(1, { verdict: PATH_HELD })], {}, { request: { toggled: false, skipped: "toggle-cap:2" } });
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(PATH_NOTE) } }]);
  assert.deepEqual(asked.map(([kind]) => kind), ["request"]);
  assert.ok(lines.some((line) => line.includes("#1 whole review not requested") && line.includes("toggle-cap:2")));
});

test("the lane's comment keeps its record lines on every rewrite, and a head already recorded is not toggled again", async () => {
  const older = recordAt("c".repeat(40), "2026-10-20T09:00:00Z");
  const prior = withRecords(laneNote("an earlier reason"), [older, RECORD]);
  const { notes, asked } = await run([pull(1, { verdict: PATH_HELD, discussion: { comments: [lanesSaid(prior)] } })], {}, { request: null });
  assert.deepEqual(notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: withRecords(laneNote(PATH_NOTE), [older, RECORD]) } }]);
  assert.deepEqual(asked, [["request", 1, prior, 0]]);
  // Unchanged since, the comment is not written again.
  const again = await run([pull(1, { verdict: PATH_HELD, discussion: { comments: [lanesSaid(withRecords(laneNote(PATH_REASON), [older, RECORD]))] } })], {}, { request: null });
  assert.deepEqual(again.notes, []);
  assert.deepEqual(again.asked.map(([kind]) => kind), ["request"]);
});

test("a verdict read that ends past the budget requests nothing; the next run asks", async () => {
  let clock = Date.parse(NOW);
  const verdict = () => {
    clock += VERIFY_BUDGET_MS + 1;
    return PATH_HELD;
  };
  const { notes, asked } = await run([pull(1, { verdict })], {}, { request: { line: RECORD }, now: () => clock });
  assert.deepEqual(asked, []);
  assert.equal(notes.length, 1);
});

test("a whole-review child stopped on a rate limit writes nothing more and fails the run", async () => {
  const stop = () => {
    throw new ReaderRateLimited("babysit_whole_review.py request", "");
  };
  const { code, notes, asked } = await run([pull(1, { verdict: PATH_HELD }), pull(2, { verdict: PATH_HELD })], {}, { request: stop });
  assert.equal(code, 1);
  assert.deepEqual(notes, []);
  assert.deepEqual(asked.map(([kind, number]) => [kind, number]), [["request", 1]]);
});

test("a comment write that fails toggles nothing", async () => {
  const { asked, code } = await run([pull(1, { verdict: PATH_HELD })], {}, { request: { line: RECORD }, noteErrors: [new Error("POST comments failed with status 502")] });
  assert.equal(code, 1);
  assert.deepEqual(asked.map(([kind]) => kind), ["request"]);
});

test("a lanes App draft a toggle may have left goes to recover; another author's draft and an event run's do not", async () => {
  const draft = pull(1, { isDraft: true, updatedAt: "2026-10-23T09:00:00Z", labels: labels("ci") });
  const other = pull(2, { isDraft: true, author: { __typename: "User", login: "someone" } });
  const { asked, lines } = await run([draft, other]);
  assert.deepEqual(asked, [["recover", [{ number: 1, id: "PR_1", head: HEAD, updatedAt: "2026-10-23T09:00:00Z", labels: ["ci"] }]]]);
  assert.ok(lines.includes("enable-auto-merge: #1 marked ready again: a whole-review toggle left it a draft"));
  assert.deepEqual((await run([draft], { EVENT_NAME: "pull_request_target", EVENT_PR: "1" })).asked, []);
  assert.deepEqual((await run([draft], { REPORT_ONLY: "true" })).asked, []);
});

test("a record line inside the fenced reasons is not one, so a changed path cannot plant it", () => {
  const planted = ["<!-- babysit-merge-risk -->", "held", "", "```text", `review-path:x: docs/a`, RECORD, "```", "", recordAt("c".repeat(40), "2026-10-20T09:00:00Z")].join("\r\n");
  assert.deepEqual(recordLines(planted), [recordAt("c".repeat(40), "2026-10-20T09:00:00Z")]);
});

test("a person's refusal keeps the lane comment's record lines, so the head stays recorded and its reasons still parse", () => {
  const prior = withRecords(laneNote("an earlier reason"), [RECORD]);
  for (const partial of [false, true]) {
    const writes = refusalWrites(pull(1), [lanesSaid(prior)], { clears: "person", reason: HOLD_PATH_REASON, partial }, { bot: LANES.login, label: "needs-human", now: Date.parse(NOW) });
    assert.equal(writes.commentId, null);
    assert.deepEqual(recordLines(writes.body), [RECORD]);
    assert.equal(isPartial(writes.body, HEAD), partial);
    assert.ok(holdPathOnly(writes.body, HEAD, "needs-human"));
  }
});

test("a lanes App draft carrying a hold is not handed to recover", async () => {
  const draft = (number, overrides) => pull(number, { isDraft: true, updatedAt: "2026-10-23T09:00:00Z", ...overrides });
  const held = [
    draft(1, { labels: labels("do-not-merge") }),
    draft(2, { labels: labels("needs-human") }),
    draft(3, { body: `Closes #1003\n\n${HOLD_LINE}` }),
    draft(4, { labels: { totalCount: 101, nodes: [] } }),
  ];
  assert.deepEqual((await run(held)).asked, []);
  const { asked } = await run([...held, draft(5)]);
  assert.deepEqual(asked.map(([kind, drafts]) => [kind, drafts.map(({ number }) => number)]), [["recover", [5]]]);
});

test("the record line format is babysit_whole_review.record_line's", () => {
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "from datetime import UTC, datetime\nfrom babysit_whole_review import record_line\nprint(record_line('b' * 40, datetime(2026, 10, 23, 10, tzinfo=UTC)))"],
    { cwd: scripts, encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  assert.equal(python.stdout.trim(), RECORD);
  assert.ok(WHOLE_REVIEW_RECORD.test(RECORD));
  assert.ok(!WHOLE_REVIEW_RECORD.test(RECORD.replace(HEAD, "b".repeat(39))));
});

test("pythonWholeReview runs the gate's script with the prior comment and drafts on stdin", () => {
  const spawned = [];
  const spawn = (command, args, options) => {
    spawned.push([command, args, options.input]);
    return { status: 0, stdout: '{"line": "x"}\n', stderr: "" };
  };
  const whole = pythonWholeReview({ GITHUB_REPOSITORY: REPO, LANES_BOT_LOGIN: "lanes[bot]", WHOLE_REVIEW_SCRIPT: "w.py" }, spawn);
  assert.deepEqual(whole.request({ id: "PR_1", headRefOid: HEAD }, "prior"), { line: "x" });
  whole.toggle({ id: "PR_1" }, "needs-human");
  whole.recover([{ number: 1 }]);
  assert.deepEqual(spawned, [
    ["python3", ["w.py", "request", "--repo", REPO, "--identity", "lanes[bot]", "--head", HEAD, "--node-id", "PR_1"], "prior"],
    ["python3", ["w.py", "toggle", "--node-id", "PR_1", "--human-gated", "needs-human"], undefined],
    ["python3", ["w.py", "recover", "--repo", REPO, "--identity", "lanes[bot]", "--drafts", "/dev/stdin"], '[{"number":1}]'],
  ]);
  assert.throws(() => pythonWholeReview({}, () => ({ status: 2, stdout: "", stderr: "boom" })).toggle({ id: "PR_1" }), /exited 2: boom/);
  // babysit_gh's rate guard exit (READER_RATE_LIMIT_EXIT), as the verifier's.
  assert.throws(() => pythonWholeReview({}, () => ({ status: 75, stdout: "", stderr: "" })).toggle({ id: "PR_1" }), ReaderRateLimited);
});

// Owner decisions Q-FLOOR (B) and Q-ENFORCE (A): a floor path, the files
// that enforce the floor included, holds with no configured glob naming it,
// as a cause a person must clear, so it gets the label; a trusted path off
// the floor arms. Owner decision Q26 option B: an `enforcement` floor path is
// left to the gate's verifier read, whose risk score holds it until a clean
// security review binds to the head, so it arms on a passing read.
test("a floor path no configured glob names is commented on and labeled human-gated; a trusted path off it arms", async () => {
  const floor = [
    ".github/actions/resolve-config/resolve.mjs",
    ".github/actions/request-lane-token/action.yml",
    ".github/actions/check-trusted-trigger/check-trusted-trigger.mjs",
    ".github/actions/check-kill-switch/check-kill-switch.mjs",
    ".github/actions/log-api-budget/rate-guard.mjs",
    ".github/actions/log-api-budget/rate-limits.json",
    ".github/CODEOWNERS",
    "vendor/.gitmodules",
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/enable-auto-merge.mjs",
    ".github/scripts/pr-merge/superseded.mjs",
    ".github/scripts/pr-merge/clear-escalations.mjs",
    ".github/scripts/pr-merge/gate-check.mjs",
    ".github/scripts/pr-merge/who.mjs",
    "plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py",
    "docs/conventions/pr-pipeline.yaml",
    // A workflow that mints a lane token is a gate path.
    ".github/workflows/pr-merge.yml",
    // So is ci-status, which posts the required status and runs the hold step.
    ".github/workflows/pr-require-checks.yml",
  ];
  const { code, writes, notes } = await run([
    ...floor.map((filename, index) => pull(index + 1, { files: [{ filename }] })),
    pull(98, { files: [{ filename: "plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py" }] }),
    pull(99, { files: [{ filename: ".github/scripts/pr-unblock/other.mjs" }] }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_98", head: HEAD },
    { mutation: "arm", id: "PR_99", head: HEAD },
  ]);
  assert.deepEqual(
    notes,
    floor.flatMap((filename, index) => [
      { method: "POST", path: `${ISSUES}/${index + 1}/comments`, body: { body: personNote(`it changes ${filename}, a hold path`) } },
      { method: "POST", path: `${ISSUES}/${index + 1}/labels`, body: { labels: ["needs-human"] } },
    ]),
  );
});

// Owner rules 2026-10-26 and 2026-10-27: a person only for intent, design or
// a CRITICAL security issue, trust holds kept. The gate's `needsHuman`
// (babysit_verify_evidence NEEDS_HUMAN: an untrusted spec) decides, so a
// changed spec is the lanes'. Owner decision 2026-10-29: the repeated-FAIL
// cap, which never clears for it, closes it for a fresh attempt at its
// issue, with no note and no person's label. Owner decision 2026-11-01
//: an old pull request waits for a fresh pass at its head.
test("only a verifier refusal the gate marks needsHuman is a person's; the cap closes for a fresh attempt and an old pull request waits", async () => {
  const refused = (refusal, needsHuman, detail = null) => ({ refusal, needsHuman, detail, head: HEAD, ineligible: null, reviews: null });
  const failed = `fails at 3 heads (${"1".repeat(40)}, ${"2".repeat(40)}, ${"3".repeat(40)}), the cap is 3`;
  const { notes, closed, lines } = await run([
    pull(1, { verdict: refused("verify:untrusted-spec", true) }),
    pull(2, { verdict: refused("verify:spec-changed", false) }),
    pull(3, { verdict: refused("verify:repeated-fail", false, failed) }),
    pull(4, { verdict: refused("verify:too-old", false, "created 2026-07-27T23:00:00+00:00") }),
    pull(5, { verdict: { ...MISSING, refusal: "verify:ineligible", ineligible: "it closes 2 issues" } }),
  ]);
  const refusing = (code) => `pr-merge's gate refuses its verifier verdict (${code})`;
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(refusing("verify:untrusted-spec")) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: laneNote(refusing("verify:spec-changed")) } },
    { method: "POST", path: `${ISSUES}/4/comments`, body: { body: laneNote(refusing("verify:too-old")) } },
    { method: "POST", path: `${ISSUES}/5/comments`, body: { body: laneNote("pr-merge's lane does not take its issue link (it closes 2 issues)") } },
  ]);
  assert.deepEqual(closed, [{ number: 3, holds: ["do-not-merge", "needs-human"] }]);
  assert.ok(lines.some((line) => line.includes(`#3 closed for a fresh attempt (${refusing(`verify:repeated-fail: ${failed}`)})`)));
});

// A close the reader left undone (a hold label, a head that moved) or that
// failed writes no note and no label: the next run judges it again.
// Left open, it keeps the lane's refusal note (and its pr-merge/unarmed
// status), as before the close existed; never a person's label.
test("a capped pull request the close leaves open or fails on gets the lane's note and no label", async () => {
  const capped = { refusal: "verify:repeated-fail", needsHuman: false, detail: null, head: HEAD, ineligible: null, reviews: null };
  const laneOnly = (notes) => {
    assert.equal(notes.length, 1, JSON.stringify(notes));
    assert.equal(notes[0].method, "POST");
    assert.equal(notes[0].path, `${ISSUES}/3/comments`);
    assert.ok(!notes.some(({ path }) => path.includes("/labels")));
  };
  const open = await run([pull(3, { verdict: capped })], {}, { closeAnswer: () => ({ closed: false, reason: "it carries do-not-merge" }) });
  laneOnly(open.notes);
  assert.equal(open.code, 0);
  assert.ok(open.lines.some((line) => line.includes("#3 left open: it carries do-not-merge")));
  const failing = await run([pull(3, { verdict: capped })], {}, { closeAnswer: () => { throw new Error("close: HTTP 500"); } });
  laneOnly(failing.notes);
  assert.notEqual(failing.code, 0);
  // A close that went through notes nothing.
  const closed = await run([pull(3, { verdict: capped })], {}, { closeAnswer: () => ({ closed: true, restarted: [7], parked: [] }) });
  assert.deepEqual(closed.notes, []);
  // Its lane refusal, standing merge.risk-escalation-minutes at the head,
  // gets the failing pr-merge/unarmed status either way.
  const reason = verifyHold(capped, HEAD);
  const standing = pull(3, { verdict: capped, discussion: { comments: [lanesSaid(laneNote(reason, "2026-10-23T10:00:00.000Z"))] } });
  const now = () => Date.parse("2026-10-23T11:00:00Z");
  const failingStatus = [{ sha: HEAD, state: "failure", description: reason }];
  for (const closeAnswer of [() => ({ closed: false, reason: "it carries do-not-merge" }), () => { throw new Error("close: HTTP 500"); }]) {
    assert.deepEqual((await run([standing], {}, { closeAnswer, now })).statuses, failingStatus);
  }
  assert.deepEqual((await run([standing], {}, { closeAnswer: () => ({ closed: true, restarted: [], parked: [] }), now })).statuses, []);
});

// Report-only closes nothing.
test("report-only names the close it would make and closes nothing", async () => {
  const capped = { refusal: "verify:repeated-fail", needsHuman: false, detail: "fails at 3 heads", head: HEAD, ineligible: null, reviews: null };
  const { closed, lines } = await run([pull(4, { verdict: capped })], { REPORT_ONLY: "true" });
  assert.deepEqual(closed, []);
  assert.ok(lines.some((line) => line.includes("#4 would close for a fresh attempt (report-only)")));
});

test("verifyClears reads the gate's needsHuman and reviewsPerson, not the refusal text", () => {
  const at = (fields) => verifyClears({ head: HEAD, ineligible: null, reviews: null, refusal: null, ...fields }, HEAD);
  assert.equal(at({ refusal: "verify:repeated-fail", needsHuman: true }), "person");
  assert.equal(at({ refusal: "verify:untrusted-spec", needsHuman: false }), "lane");
  assert.equal(at({ reviews: "security-finding: 1 open", reviewsPerson: false }), "lane");
  assert.equal(at({ reviews: "evidence-unbound:claude-review: not bound", reviewsPerson: true }), "person");
  // An answer without the flag holds for a person, as an unknown does.
  assert.equal(at({ refusal: "verify:fail" }), "person");
  assert.equal(at({ reviews: "evidence-unbound:claude-review: not bound" }), "person");
});

test("a refusal a lane clears is commented on, with no label", async () => {
  const { code, notes } = await run([pull(1, { verdict: MISSING })]);
  assert.equal(code, 0);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
});

// Owner rule 2026-10-26: a read that failed is never a person's; the next
// run reads it again, and nothing that failed to read arms.
// A listing past the page cap never reads whole, so its hold and cost paths
// are never checked: a person's. A page that did not read is read again.
test("a listing past the page cap is a person's refusal; one that did not read is a lane's; neither arms", async () => {
  // Exactly 300 files is not past the cap: one more page reads empty, and
  // it arms.
  const exactly = Array.from({ length: 300 }, (_, index) => ({ filename: `docs/${index}.md` }));
  const full = await run([pull(1, { files: exactly })]);
  assert.deepEqual(full.writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.deepEqual(full.notes, []);
  const files = Array.from({ length: 301 }, (_, index) => ({ filename: `docs/${index}.md` }));
  const { code, notes, writes } = await run([pull(1, { files })]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(FILES_CAPPED_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  assert.deepEqual(decide(pull(1), options, { ...detail(), files: null, filesCapped: false, verify: PASSED }), {
    action: "none",
    reason: "its changed files could not all be read",
    clears: "lane",
  });
});

test("a refusal a lane clears gets a failing pr-merge/unarmed status once it has stood merge.risk-escalation-minutes at the head, and an arm or a person's refusal a passing one", async () => {
  // Timed from the first lane refusal at the head, so a reason whose detail
  // changes every run does not restart it.
  const standing = (since, said = MISSING_REASON) => pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote(said, since))] } });
  const now = () => Date.parse("2026-10-23T11:00:00Z");
  const failing = [{ sha: HEAD, state: "failure", description: MISSING_REASON }];
  assert.deepEqual((await run([standing("2026-10-23T10:00:00.000Z")], {}, { now })).statuses, failing);
  assert.deepEqual((await run([standing("2026-10-23T10:00:00.000Z", "unreadable: RuntimeError: a detail that moves")], {}, { now })).statuses, failing);
  assert.deepEqual((await run([standing("2026-10-23T10:01:00.000Z")], {}, { now })).statuses, []);
  assert.deepEqual((await run([standing("2026-10-23T10:31:00.000Z")], { RISK_ESCALATION_MINUTES: "29" }, { now })).statuses, failing);
  // A since line for another head starts the time again.
  const moved = pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON, "2026-01-01T00:00:00.000Z").replace(`head=${HEAD}`, `head=${"c".repeat(40)}`))] } });
  assert.deepEqual((await run([moved], {}, { now })).statuses, []);
  // A lane's refusal that becomes a person's withdraws the failing status.
  const escalated = pull(2, { files: COST_FILES, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON, "2026-01-01T00:00:00.000Z"))] } });
  assert.deepEqual((await run([escalated], {}, { now })).statuses, [{ sha: HEAD, state: "success", description: "a person clears this hold: needs-human" }]);
  const armed = await run([pull(3)], {}, { now });
  assert.deepEqual(armed.writes, [{ mutation: "arm", id: "PR_3", head: HEAD }]);
  assert.deepEqual(armed.statuses, [{ sha: HEAD, state: "success", description: "armed for native auto-merge" }]);
  // A lane's refusal that cleared while something else leaves it unarmed
  // (here a member's veto) withdraws its failing status too.
  const vetoed = pull(4, {
    discussion: { comments: [lanesSaid(laneNote(MISSING_REASON, "2026-01-01T00:00:00.000Z")), said("kyle-sexton", "do not merge", "2026-10-23T10:30:00Z")] },
  });
  const held = await run([vetoed], {}, { now });
  assert.deepEqual(held.writes, []);
  assert.deepEqual(held.statuses, [{ sha: HEAD, state: "success", description: "its lanes refusal no longer stands" }]);
  // Report-only hands the status job nothing.
  assert.deepEqual((await run([standing("2026-10-23T10:00:00.000Z")], { REPORT_ONLY: "true" }, { now })).statuses, []);
});

// A run that read nothing new about a standing lane refusal leaves its
// failing status alone: no success that the next reading run turns back.
test("an unread outcome withdraws no failing pr-merge/unarmed status", async () => {
  const stood = (overrides = {}) => pull(1, { discussion: { comments: [lanesSaid(laneNote(MISSING_REASON, "2026-01-01T00:00:00.000Z"))] }, ...overrides });
  const at = Date.parse("2026-10-23T11:00:00Z");
  // No time left: the clock passes the verify budget after the room read.
  let calls = 0;
  const late = () => (calls++ === 0 ? at : at + VERIFY_BUDGET_MS + 1);
  const cases = [
    ["no time left to read the verdict", await run([stood()], {}, { now: late })],
    ["the hold paths did not read", await run([stood()], { RESOLVED_CONFIG: "/nonexistent/resolved-config.json" }, { now: () => at })],
    ["the verdict read threw", await run([stood({ verdict: new Error("boom") })], {}, { now: () => at })],
  ];
  for (const [name, result] of cases) {
    assert.deepEqual(result.writes, [], name);
    assert.deepEqual(result.statuses, [], name);
  }
});


const unlabeled = (at, typename = "User", name = "needs-human") => ({ createdAt: at, actor: { __typename: typename, login: "someone" }, label: { name } });

test("an unchanged refusal writes nothing, and a label a person removed stays off", async () => {
  const lane = pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON))] } });
  const person = pull(2, {
    files: COST_FILES,
    discussion: { comments: [lanesSaid(personNote(COST_REASON))] },
    unlabeled: [unlabeled("2026-10-23T10:30:00Z", "User", "Needs-Human")],
  });
  const { code, notes } = await run([lane, person]);
  assert.equal(code, 0);
  assert.deepEqual(notes, []);
});

test("a person's refusal comment standing without its label gets the label back", async () => {
  // An earlier run's label write failed: no removal at all, a bot's, a
  // person's before the comment last changed, or another label's.
  for (const removals of [[], [unlabeled("2026-10-23T10:30:00Z", "Bot")], [unlabeled("2026-10-23T09:59:00Z")], [unlabeled("2026-10-23T10:30:00Z", "User", "do-not-merge")]]) {
    const person = pull(2, { files: COST_FILES, discussion: { comments: [lanesSaid(personNote(COST_REASON))] }, unlabeled: removals });
    const { code, notes } = await run([person]);
    assert.equal(code, 0);
    assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } }]);
  }
});

test("a timeline not read whole puts no label back", () => {
  assert.equal(liftedByPerson({ totalCount: 101, nodes: [] }, "needs-human", "2026-10-23T10:00:00Z"), true);
  assert.equal(liftedByPerson(null, "needs-human", "2026-10-23T10:00:00Z"), true);
  assert.equal(liftedByPerson({ totalCount: 0, nodes: [] }, "needs-human", "2026-10-23T10:00:00Z"), false);
});

test("a changed refusal edits the one comment instead of posting another", async () => {
  const moved = pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote("an earlier reason"))] } });
  const { notes } = await run([moved]);
  assert.deepEqual(notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: laneNote(MISSING_REASON) } }]);
});

// #10224: the owner lifted a hold path, and the next run re-labeled it for a
// risk-score cost hold that had stood all along behind the first. Every
// reason a person clears goes in one refusal, so one lift answers them all.
const RISK = "cost-review-required: infra/main.tf changes a cost path";
const RISK_REASON = `pr-merge's gate holds it on its risk score (${RISK})`;
const RISK_HELD = { refusal: null, head: HEAD, ineligible: null, reviews: RISK, reviewsPerson: true, queue: UNEJECTED };
const BOTH = `${HOLD_PATH_REASON}\n${RISK_REASON}`;

test("a held hold path and a person's risk hold are one refusal naming both", async () => {
  const { code, writes, notes, verified } = await run([pull(1, { files: [{ filename: "docs/held.md" }], verdict: RISK_HELD })]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, [1]);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(BOTH) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  // A hold path and a cost path with a lane's verifier refusal: the two
  // person reasons, and not the lane's.
  const files = [{ filename: "infra/main.tf" }, { filename: "docs/held.md" }];
  const mixed = await run([pull(2, { files, verdict: MISSING })]);
  assert.deepEqual(mixed.notes, [
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: personNote(`${HOLD_PATH_REASON}\n${COST_REASON}`) } },
    { method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } },
  ]);
});

test("an approval that lifts only the hold path re-holds once for what remains, and nothing once that clears", async () => {
  const approved = (overrides) => pull(1, { files: [{ filename: "docs/held.md" }], ...overrides });
  const reviews = [reviewed("APPROVED")];
  const rest = await run([approved({ verdict: RISK_HELD, discussion: { reviews, comments: [lanesSaid(personNote(BOTH))] } })], trustedKyle());
  assert.deepEqual(rest.writes, []);
  assert.deepEqual(rest.notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(RISK_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  // The person removes the label again with the set unchanged: it stays off.
  const stays = await run(
    [approved({ verdict: RISK_HELD, discussion: { reviews, comments: [lanesSaid(personNote(RISK_REASON))] }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })],
    trustedKyle(),
  );
  assert.deepEqual(stays.notes, []);
  // Nothing remains: it arms, and no label goes on.
  const clear = await run([approved({ verdict: PASSED, discussion: { reviews, comments: [lanesSaid(personNote(BOTH))] } })], trustedKyle());
  assert.deepEqual(clear.writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.deepEqual(clear.notes, []);
});

test("the same reason set in another order is no change", async () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const held = (files) => decide(pull(1), options, { ...detail(), files, verify: MISSING }).reason;
  assert.equal(held(["infra/main.tf", ".github/CODEOWNERS"]), "it changes .github/CODEOWNERS, a hold path\nit changes infra/main.tf, a cost path");
  assert.equal(held([".github/CODEOWNERS", "infra/main.tf"]), held(["infra/main.tf", ".github/CODEOWNERS"]));
  assert.equal(personReason([RISK_REASON, HOLD_PATH_REASON]), personReason([HOLD_PATH_REASON, RISK_REASON, RISK_REASON]));
  const standing = [lanesSaid(personNote(BOTH))];
  const writes = refusalWrites(pull(1), standing, { clears: "person", reason: personReason([RISK_REASON, HOLD_PATH_REASON]) }, { bot: LANES.login, label: "needs-human" });
  assert.deepEqual(writes, { body: null, commentId: 77, label: "needs-human", liftedSince: "2026-10-23T10:00:00Z" });
});

test("a person's hold whose verifier read did not come is noted with what it has, and never narrows a standing comment", async () => {
  const at = Date.parse("2026-10-23T11:00:00Z");
  let calls = 0;
  const late = () => (calls++ === 0 ? at : at + VERIFY_BUDGET_MS + CACHE_ONLY_WINDOW_MS + 1);
  const files = [{ filename: "docs/held.md" }];
  const fresh = await run([pull(1, { files, verdict: RISK_HELD })], {}, { now: late });
  assert.deepEqual(fresh.verified, []);
  assert.deepEqual(fresh.notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(HOLD_PATH_REASON, true) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  // A standing comment that already names the hold path, with more, stands;
  // a person's removal of its label still holds.
  calls = 0;
  const kept = await run([pull(1, { files, verdict: RISK_HELD, discussion: { comments: [lanesSaid(personNote(BOTH))] }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })], {}, { now: late });
  assert.deepEqual(kept.notes, []);
  // A verifier read that failed is the same.
  const failed = await run([pull(1, { files, verdict: new Error("boom"), discussion: { comments: [lanesSaid(personNote(BOTH))] }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })]);
  assert.deepEqual(failed.verified, [1]);
  assert.deepEqual(failed.notes, []);
  // A verdict the lanes clear, which the gate never scores past: the risk
  // score is not in it, so the standing comment stands too.
  const unscored = await run([pull(1, { files, verdict: MISSING, discussion: { comments: [lanesSaid(personNote(BOTH))] }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })]);
  assert.deepEqual(unscored.notes, []);
  // A kept verifier answer puts the label back on a path hold's standing
  // comment that no person lifted, as a path hold always has.
  const kept2 = await run([pull(1, { files, verdict: { ...RISK_HELD, cached: true }, discussion: { comments: [lanesSaid(personNote(BOTH))] } })]);
  assert.deepEqual(kept2.notes, [{ method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } }]);
  // An armed one is disarmed at once, with no verifier read.
  const armed = await run([pull(2, { files, verdict: RISK_HELD, autoMergeRequest: {} })]);
  assert.deepEqual(armed.verified, []);
  assert.deepEqual(armed.writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(armed.notes, [
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: personNote(HOLD_PATH_REASON, true) } },
    { method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } },
  ]);
});

test("a labeled pull request whose standing refusal lacks the verifier's answer gets one read that widens it, then none", async () => {
  const files = [{ filename: "docs/held.md" }];
  const held = (overrides) => pull(2, { files, labels: labels("needs-human"), ...overrides });
  // The next reader run, label on: one verifier read, and the comment names both.
  const widened = await run([held({ verdict: RISK_HELD, discussion: { comments: [lanesSaid(personNote(HOLD_PATH_REASON, true))] } })]);
  assert.deepEqual(widened.verified, [2]);
  assert.deepEqual(widened.writes, []);
  assert.deepEqual(widened.notes, [{ method: "POST", path: `${ISSUES}/2/comments`, body: { body: personNote(BOTH) } }]);
  // A verdict the lanes clear adds no reason, but the read came: the comment
  // loses its mark in place, so no later run reads again.
  const unscored = await run([held({ verdict: MISSING, discussion: { comments: [lanesSaid(personNote(HOLD_PATH_REASON, true))] } })]);
  assert.deepEqual(unscored.verified, [2]);
  assert.deepEqual(unscored.notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: personNote(HOLD_PATH_REASON) } }]);
  // A read that failed keeps the mark for the next run.
  const failed = await run([held({ verdict: new Error("boom"), discussion: { comments: [lanesSaid(personNote(HOLD_PATH_REASON, true))] } })]);
  assert.deepEqual(failed.verified, [2]);
  assert.deepEqual(failed.notes, []);
  // Widened: no read, no write.
  const after = await run([held({ verdict: RISK_HELD, discussion: { comments: [lanesSaid(personNote(BOTH))] } })]);
  assert.deepEqual(after.verified, []);
  assert.deepEqual(after.notes, []);
  // A hold-path-only refusal a trusted person's approval of the head lifts:
  // the lane takes the label off and judges it unlabeled, so a passing
  // verdict arms it (approvalLift; the label tests below cover each refusal).
  const lifted = await run([held({ verdict: PASSED, discussion: { reviews: [reviewed("APPROVED")], comments: [lanesSaid(personNote(HOLD_PATH_REASON, true))] }, timeline: liftTimeline(personNote(HOLD_PATH_REASON, true)) })], trustedKyle());
  assert.deepEqual(lifted.verified, [2]);
  assert.deepEqual(lifted.notes, [{ method: "DELETE", path: `${ISSUES}/2/labels/needs-human` }]);
  assert.equal(lifted.writes.at(-1)?.mutation, "arm");
  // With no partial comment and no approval, only the discussion is read: no file listing.
  const next = await run([held({ verdict: PASSED, discussion: { comments: [lanesSaid(personNote(HOLD_PATH_REASON))] } })], trustedKyle());
  assert.deepEqual(next.verified, []);
  assert.deepEqual(next.notes, []);
  const listed = (calls) => calls.filter(({ path }) => /\/pulls\/2\/files\?/.test(path)).length;
  assert.equal(listed(next.calls), 0);
  // A held lane spends no read on it, partial or not.
  const laneOff = { ...ROOM, refusal: "the gate holds the lane off" };
  const heldLane = await run([held({ verdict: RISK_HELD, discussion: { comments: [lanesSaid(personNote(HOLD_PATH_REASON, true))] } })], {}, {}, laneOff);
  assert.deepEqual(heldLane.verified, []);
  assert.deepEqual(heldLane.notes, []);
  assert.ok(!heldLane.calls.some(({ body }) => body?.query === DETAIL_QUERY));
});

test("a risk hold is a person's only for a security finding, a trusted-actor widening or a cost hold", async () => {
  // reviewsPerson as babysit_risk.person_reasons answers for each code,
  // read from the Python, the one list.
  const codes = (reviews) => reviews.split("; ").map((part) => part.slice(0, part.indexOf(": ")));
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const answer = (reviews) => {
    const python = spawnSync(
      "python3",
      ["-c", "import json,sys\nfrom babysit_risk import Reason, Risk, person_reasons\nprint(json.dumps(bool(person_reasons([Reason(c, Risk.HIGH, 'd') for c in json.load(sys.stdin)]))))"],
      { cwd: scripts, input: JSON.stringify(codes(reviews)), encoding: "utf8" },
    );
    assert.equal(python.status, 0, python.stderr);
    return JSON.parse(python.stdout);
  };
  const risk = (reviews) => ({ refusal: null, needsHuman: false, head: HEAD, ineligible: null, reviews, reviewsPerson: answer(reviews) });
  const holding = (reviews) => `pr-merge's gate holds it on its risk score (${reviews})`;
  // A high path is the lanes' (owner decision 2026-10-30, #11020).
  const lane = [
    "evidence-unbound:claude-review: no-marker",
    "manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks",
    "unreadable: RuntimeError: boom",
    "high-path:**: 'a' mode '120000' (symlink)",
    "high-path:docs/**: docs/a.md",
  ];
  const person = ["security-finding: 1 CRITICAL", "files-incomplete: x; trust-gate:trusted-actors: entries added", "cost-review-required: infra/main.tf"];
  // A new comment wraps a reason line past 100 columns at a space.
  const wrapped = {
    [lane[1]]: "pr-merge's gate holds it on its risk score (manifest-review-required:\n  plugins/a/.claude-plugin/plugin.json: hooks)",
    [person[1]]: "pr-merge's gate holds it on its risk score (files-incomplete: x; trust-gate:trusted-actors: entries\n  added)",
  };
  for (const reviews of lane) {
    // A lane's stays a lane's however long its comment has stood: past
    // merge.risk-escalation-minutes it gets a failing status, never a label.
    const stood = pull(1, { verdict: risk(reviews), discussion: { comments: [lanesSaid(laneNote(holding(reviews), "2026-01-01T00:00:00.000Z"))] } });
    const late = await run([stood]);
    assert.deepEqual(late.notes, [], reviews);
    assert.deepEqual(late.statuses, [{ sha: HEAD, state: "failure", description: holding(reviews).slice(0, 140) }], reviews);
    const fresh = await run([pull(1, { verdict: risk(reviews) })]);
    assert.deepEqual(fresh.notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(wrapped[reviews] ?? holding(reviews)) } }], reviews);
    assert.deepEqual(fresh.statuses, [], reviews);
  }
  for (const reviews of person) {
    assert.deepEqual(
      (await run([pull(1, { verdict: risk(reviews) })])).notes,
      [
        { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(wrapped[reviews] ?? holding(reviews)) } },
        { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
      ],
      reviews,
    );
  }
});

// An edit notifies no one and keeps the comment's old date, so an escalation
// edited into a lane's comment would show only a bare label event.
test("an escalation to a person posts a new comment, never an edit of the lane's", async () => {
  const held = pull(1, { files: [{ filename: "docs/held.md" }], discussion: { comments: [lanesSaid(laneNote(MISSING_REASON))] } });
  const { notes } = await run([held]);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(HOLD_PATH_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  const posted = notes[0].body.body.split("\n");
  assert.equal(posted[0], "<!-- work-items:escalation lane=pr-merge kind=escalated -->");
  assert.equal(posted[1], "<!-- babysit-merge-risk -->");
  assert.ok(posted.includes(HOLD_PATH_REASON));
});

test("a person's refusal at a new head posts a new comment too", async () => {
  const earlier = refusalBody(true, HOLD_PATH_REASON, "c".repeat(40), "needs-human");
  const held = pull(1, { files: [{ filename: "docs/held.md" }], discussion: { comments: [lanesSaid(earlier)] } });
  const { notes } = await run([held]);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(HOLD_PATH_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
});

test("an unchanged person's refusal is not posted again", () => {
  const writes = refusalWrites(
    { headRefOid: HEAD },
    [lanesSaid(personNote(HOLD_PATH_REASON))],
    { clears: "person", reason: HOLD_PATH_REASON },
    { bot: LANES.login, label: "needs-human" },
  );
  assert.deepEqual(writes, { body: null, commentId: 77, label: "needs-human", liftedSince: "2026-10-23T10:00:00Z" });
});

test("a lane's refusal over a person's comment still edits it, with no label", () => {
  const writes = refusalWrites(
    { headRefOid: HEAD },
    [lanesSaid(personNote(HOLD_PATH_REASON))],
    { clears: "lane", reason: MISSING_REASON },
    { bot: LANES.login, label: "needs-human", now: Date.parse(NOW) },
  );
  assert.deepEqual(writes, { body: laneNote(MISSING_REASON), commentId: 77, label: null });
});

// Wrapped refusal reasons. GitHub scrolls a code-block line wider than the
// page, so each reason line is broken at a space to 100 columns, its
// continuations indented two spaces, and more than 20 lines fold into
// <details>; the head line stays whole for the readers that take the head
// from it. LONG_RISK's ";" is its 99th column, so the cut falls right after
// "; " (hand-counted: the risk prefix is 44 columns, then 17 + 37 + 1).
const LONG_RISK = `pr-merge's gate holds it on its risk score (evidence-unbound:${"a".repeat(37)}; files-incomplete)`;
const LONG_RISK_WRAPPED = [`pr-merge's gate holds it on its risk score (evidence-unbound:${"a".repeat(37)};`, "  files-incomplete)"];
const LONG_PATH = `docs/${"p".repeat(115)}.md`;
const LONG_PATH_REASON = `it changes ${LONG_PATH}, a hold path`;
const MANY_PATHS = personReason(Array.from({ length: 21 }, (_, i) => `it changes docs/held-${String(i).padStart(2, "0")}.md, a hold path`));
// A fence line past 100 columns is one unbreakable token after its indent.
const fenceLines = (body) => {
  const lines = body.split("\n");
  const open = lines.indexOf("```text");
  return lines.slice(open + 1, lines.indexOf("```", open + 1));
};
const fits = (body) => fenceLines(body).every((line) => line.length <= 100 || !line.trimStart().includes(" "));

test("a refusal's reasons wrap to 100 columns and come back whole, in each reason shape", () => {
  for (const [person, reason, partial, since] of [
    [false, LONG_RISK, false, NOW],
    [true, LONG_RISK, false, null],
    [true, LONG_RISK, true, null],
    [true, personReason([LONG_PATH_REASON, HOLD_PATH_REASON]), false, null],
    [true, MANY_PATHS, false, null],
  ]) {
    const body = refusalBody(person, reason, HEAD, "needs-human", since, partial);
    assert.ok(fits(body), body);
    assert.equal(body.split("\n")[person ? 2 : 1], `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${HEAD}\`. ${person ? "A person must clear this reason, so the pr-merge lane added the `needs-human` label: fix the reason, then remove the label, and the next scheduled run judges it again." : "The lanes clear this reason on their own; the next scheduled run judges it again."}`);
    assert.deepEqual(refusalReasons(body, person, HEAD, "needs-human", { since, partial }), reason.split("\n"));
  }
  assert.deepEqual(fenceLines(refusalBody(false, LONG_RISK, HEAD, "needs-human", NOW)), LONG_RISK_WRAPPED);
  assert.deepEqual(fenceLines(refusalBody(true, LONG_PATH_REASON, HEAD, "needs-human")), ["it changes", `  ${LONG_PATH},`, "  a hold path"]);
  const folded = refusalBody(true, MANY_PATHS, HEAD, "needs-human").split("\n");
  assert.equal(folded[4], "<details><summary>Its reasons (21 lines)</summary>");
  assert.equal(folded.at(-1), "</details>");
  assert.ok(holdPathOnly(folded.join("\n"), HEAD, "needs-human"));
  assert.ok(holdPathOnly(refusalBody(true, personReason([LONG_PATH_REASON, HOLD_PATH_REASON]), HEAD, "needs-human"), HEAD, "needs-human"));
});

// A refusal comment posted before reasons wrapped: one fence line per reason,
// however long, and a person's still parses at its head.
test("a person's refusal posted before reasons wrapped still parses, at its head only", () => {
  const old = personNote(personReason([LONG_PATH_REASON, HOLD_PATH_REASON]));
  assert.deepEqual(refusalReasons(old, true, HEAD, "needs-human"), [HOLD_PATH_REASON, LONG_PATH_REASON]);
  assert.ok(holdPathOnly(old, HEAD, "needs-human"));
  assert.ok(!holdPathOnly(old.replaceAll(HEAD, "c".repeat(40)), HEAD, "needs-human"));
  assert.equal(refusalReasons(personNote(LONG_RISK).replace("A person must", "Someone must"), true, HEAD, "needs-human"), null);
  assert.deepEqual(refusalReasons(laneNote(LONG_RISK), false, HEAD, "needs-human", { since: NOW }), [LONG_RISK]);
});

test("an unchanged long refusal writes nothing new, in the old format and the wrapped one", () => {
  const wrappedPerson = [...personNote("x").split("\n").slice(0, 4), "```text", ...LONG_RISK_WRAPPED, "```"].join("\n");
  const wrappedLane = [...laneNote("x").split("\n").slice(0, 3), "```text", ...LONG_RISK_WRAPPED, "```", `<!-- pr-merge-unarmed-since head=${HEAD} at=${NOW} -->`].join("\n");
  for (const prior of [personNote(LONG_RISK), wrappedPerson]) {
    // A person took the label off: it goes back only if they removed it
    // before the comment last changed, never with a second comment.
    const writes = refusalWrites({ headRefOid: HEAD }, [lanesSaid(prior)], { clears: "person", reason: LONG_RISK }, { bot: LANES.login, label: "needs-human" });
    assert.deepEqual(writes, { body: null, commentId: 77, label: "needs-human", liftedSince: "2026-10-23T10:00:00Z" });
  }
  for (const prior of [laneNote(LONG_RISK), wrappedLane]) {
    assert.equal(refusalWrites({ headRefOid: HEAD }, [lanesSaid(prior)], { clears: "lane", reason: LONG_RISK }, { bot: LANES.login, label: "needs-human", now: Date.parse(NOW) }), null);
  }
  // A changed reason over an old comment is written in the wrapped format.
  const moved = refusalWrites({ headRefOid: HEAD }, [lanesSaid(laneNote(LONG_RISK))], { clears: "lane", reason: MISSING_REASON + LONG_RISK }, { bot: LANES.login, label: "needs-human", now: Date.parse(NOW) });
  assert.ok(fits(moved.body));
  assert.equal(moved.commentId, 77);
});

test("an armed pull request, an event run and report-only write no refusal note", async () => {
  assert.deepEqual((await run([pull(1)])).notes, []);
  const armedHeld = pull(2, { autoMergeRequest: {}, files: [{ filename: "docs/held.md" }] });
  const event = await run([armedHeld], { EVENT_NAME: "pull_request" });
  assert.deepEqual(event.writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(event.notes, []);
  const reported = await run([pull(3, { verdict: MISSING })], { REPORT_ONLY: "true" });
  assert.deepEqual(reported.notes, []);
  assert.ok(reported.lines.includes("enable-auto-merge: #3 would note its refusal (report-only)"));
});

test("a disarmed pull request gets the note after the disarm", async () => {
  const armed = pull(1, { autoMergeRequest: {}, verdict: MISSING });
  const { writes, notes } = await run([armed]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
});

test("a failed disarm writes no note, since the pull request is still armed", async () => {
  const armed = pull(1, { autoMergeRequest: {}, files: [{ filename: "docs/held.md" }] });
  const { code, writes, notes, lines } = await run([armed], {}, { disarmError: new GitHubError(200, "POST /graphql (GraphQL errors)") });
  assert.equal(code, 1);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 disarm")));
});

test("a refusal comment that fails on the network is not sent again", async () => {
  const { code, notes, slept } = await run([pull(1, { verdict: MISSING })], {}, { noteErrors: [closed()] });
  assert.equal(code, 1);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
  assert.deepEqual(slept, []);
});

test("a lanes App pull request with no hold is armed, squash, at the head it read", async () => {
  const { code, writes } = await run([pull(7)]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
  assert.match(ARM_MUTATION, /mergeMethod: SQUASH, expectedHeadOid: \$head/);
});

// babysit_postmerge.PIN_RE, written out: the read-back takes the head from the
// first line of the lanes App's newest unedited pin comment.
const PIN_LINE = `<!-- babysit-merge-pin sha=${HEAD} -->`;

test("the head is pinned in the read-back's format before the arm", async () => {
  const { code, writes, pins, calls } = await run([pull(7)]);
  assert.equal(code, 0);
  assert.deepEqual(pins.map((pin) => [pin.path, pin.body.split("\n")[0]]), [[`${ISSUES}/7/comments`, PIN_LINE]]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
  const order = calls.map((call) => (call.body?.query === ARM_MUTATION ? "arm" : String(call.body?.body ?? "").startsWith(PIN_LINE) ? "pin" : null)).filter(Boolean);
  assert.deepEqual(order, ["pin", "arm"]);
});

test("an unedited pin for the same head is not posted again", async () => {
  const pin = { ...lanesSaid(`${PIN_LINE}\nArmed.`), lastEditedAt: null };
  const { writes, pins } = await run([pull(7, { discussion: { comments: [pin] } })]);
  assert.deepEqual(pins, []);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
});

test("a pin for another head, an edited pin or another author's pin is posted again", async () => {
  const other = { ...lanesSaid(`<!-- babysit-merge-pin sha=${"c".repeat(40)} -->`), lastEditedAt: null };
  const edited = { ...lanesSaid(`${PIN_LINE}\nArmed.`), lastEditedAt: "2026-10-23T11:00:00Z" };
  const person = { ...said("kyle-sexton", PIN_LINE, "2026-10-23T10:00:00Z"), lastEditedAt: null };
  const stale = [{ ...lanesSaid(PIN_LINE), lastEditedAt: null }, { ...other, createdAt: "2026-10-23T12:00:00Z" }];
  for (const comments of [[other], [edited], [person], stale]) {
    const { pins } = await run([pull(7, { discussion: { comments } })]);
    assert.equal(pins.length, 1);
  }
});

test("a pin that fails to post leaves it unarmed and fails the run", async () => {
  const { code, writes, pins, lines } = await run([pull(7), pull(8)], {}, { pinError: new Error("POST comments failed with status 502") });
  assert.equal(code, 1);
  assert.equal(pins.length, 2);
  assert.deepEqual(writes, []);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#7 pin, so not armed")));
});

test("report-only posts no pin", async () => {
  const { pins } = await run([pull(7)], { REPORT_ONLY: "true" });
  assert.deepEqual(pins, []);
});

test("a Hold: line, do-not-merge or the human-gated label leaves it unarmed", async () => {
  const { code, writes } = await run([
    pull(1, { body: "Closes #5\n\nHold: a human merges this\n" }),
    pull(2, { body: "Closes #5\r\n  hold: wait for the canary" }),
    pull(3, { labels: labels("do-not-merge") }),
    pull(4, { labels: labels("Needs-Human") }),
    pull(5, { body: "Closes #5\n\nPlease do not merge yet." }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("the human-gated label comes from the tracker config", async () => {
  const config = fileURLToPath(new URL("./fixtures/enable-auto-merge-tracker.json", import.meta.url));
  const { writes } = await run([pull(1, { labels: labels("human-gated") }), pull(2, { labels: labels("needs-human") })], { TRACKER_CONFIG: config });
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("an armed pull request that now holds is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { code, writes } = await run([
    pull(1, { autoMergeRequest: armed, body: "Closes #5\n\nHold: a human merges this" }),
    pull(2, { autoMergeRequest: armed, labels: labels("needs-human") }),
    pull(3, { autoMergeRequest: armed }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
  ]);
});

test("a pr-verify-failed pull request is not armed, and an armed one is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const EVENT_NAME of ["schedule", "pull_request_target"]) {
    const { code, writes } = await run(
      [pull(1, { labels: labels("pr-verify-failed") }), pull(2, { autoMergeRequest: armed, labels: labels("PR-Verify-Failed") })],
      { EVENT_NAME, EVENT_PR: "2" },
    );
    assert.equal(code, 0);
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], EVENT_NAME);
  }
});

test("only the lanes App's ready pull requests from this repository are armed", async () => {
  const { writes } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { author: { __typename: "Bot", login: "dependabot" } }),
    pull(3, { author: { __typename: "User", login: "melodic-automation-lanes" } }),
    pull(4, { isDraft: true }),
    pull(5, { isCrossRepository: true }),
    pull(8, { headRefOid: "abc" }),
    pull(9, { labels: { totalCount: 101, nodes: [] } }),
  ]);
  assert.deepEqual(writes, []);
});

test("report-only arms and disarms nothing", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], { REPORT_ONLY: "true" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.ok(lines.some((line) => /#1 would arm \(report-only\)/.test(line)));
  assert.ok(lines.some((line) => /#2 would disarm \(report-only\)/.test(line)));
});

test("the kill switch stops it before any read", async () => {
  const { code, writes } = await run([pull(1)], { KILL_SWITCH: "" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("a failed arm fails the run and still reaches the next pull request", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], {}, { failArm: true });
  assert.equal(code, 1);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_2" },
  ]);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm")));
});

// undici's shape for a dropped socket: a "fetch failed" TypeError whose cause
// carries the code and the socket's message.
const reset = () => new TypeError("fetch failed", { cause: Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" }) });

// The socket GitHub closed while the connection sat idle: undici's
// UND_ERR_SOCKET "other side closed".
const closed = () => new TypeError("fetch failed", { cause: Object.assign(new Error("other side closed"), { code: "UND_ERR_SOCKET" }) });

test("an arm that fails on the network is sent again after a capped wait and arms", async () => {
  const { code, writes, lines, slept } = await run([pull(1)], {}, { armErrors: { PR_1: [reset(), closed()] } });
  assert.equal(code, 0);
  assert.deepEqual(writes, Array(3).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  // Two resends, each waiting no longer than the 8 s cap.
  assert.equal(slept.length, 2);
  assert.ok(slept.every((ms) => ms >= 0 && ms <= 8000));
  assert.ok(lines.includes(`enable-auto-merge: #1 armed at ${HEAD}`));
});

test("the resend waits are full jitter under caps of 4 s, then 8 s", async () => {
  const errors = () => ({ PR_1: [reset(), reset()] });
  assert.deepEqual((await run([pull(1)], {}, { armErrors: errors(), random: () => 1 })).slept, [4000, 8000]);
  assert.deepEqual((await run([pull(1)], {}, { armErrors: errors(), random: () => 0 })).slept, [0, 0]);
});

test("a GET that fails on the network is left to the client's own retry, not sent again here", async () => {
  const { calls, slept, writes } = await run([pull(1)], {}, { filesError: reset() });
  assert.equal(calls.filter(({ method }) => method === "GET").length, 1);
  assert.deepEqual(slept, []);
  assert.deepEqual(writes, []);
});

test("a lone arm that fails three times on the network is warned with its cause, and with no arm landing the run fails", async () => {
  const { code, writes, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [reset(), reset(), reset(), reset()] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 3);
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed (cause: ECONNRESET read ECONNRESET)"));
});

const bare = () => new TypeError("fetch failed");

test("one pull request whose arm fails on the network every attempt is skipped, the other is armed, and the run stays green", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()] } });
  assert.equal(code, 0);
  assert.deepEqual(writes.at(-1), { mutation: "arm", id: "PR_2", head: HEAD });
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed (TypeError)"));
  assert.ok(lines.includes(`enable-auto-merge: #2 armed at ${HEAD}`));
  assert.ok(!lines.includes(`enable-auto-merge: #1 armed at ${HEAD}`));
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("a causeless error is named once, a caused one keeps its cause text, and the label is scrubbed with the message", () => {
  assert.equal(describe(bare(), { label: true }), "fetch failed (TypeError)");
  assert.equal(describe(new TypeError("TypeError"), { label: true }), "TypeError");
  assert.equal(describe(reset(), { label: true }), "fetch failed (cause: ECONNRESET read ECONNRESET)");
  assert.equal(describe(reset(), { label: true }), describe(reset()));
  assert.equal(describe(bare()), "fetch failed");
  assert.equal(describe(Object.assign(new Error("lost"), { name: "ghp_abc123" }), { label: true }), "lost (***)");
});

test("every arm in the run failing on the network, after the listing read, is an outage and fails red", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()], PR_2: [bare(), bare(), bare()] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 6);
  assert.ok(lines.includes("::error title=enable-auto-merge::every arm this run failed: #1, #2"));
});

test("an arm that failed on the network keeps its slot, since it may have landed", async () => {
  const { writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()] } }, { ...ROOM, cap: 1 });
  assert.deepEqual(writes, Array(3).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  assert.ok(lines.includes("enable-auto-merge: #2 left: merge.max-in-flight is 1 and 1 merges are in flight"));
});

test("a refusal after a resend keeps the slot, since the first attempt may have landed", async () => {
  const { writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), new GitHubError(200, "POST /graphql (GraphQL errors)")] } }, { ...ROOM, cap: 1 });
  assert.deepEqual(writes, Array(2).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.includes("enable-auto-merge: #2 left: merge.max-in-flight is 1 and 1 merges are in flight"));
});

test("each network trigger alone is sent again, and an error with another code is not", async () => {
  const coded = (code) => Object.assign(new Error("socket"), { cause: Object.assign(new Error("x"), { code }) });
  for (const error of [new TypeError("fetch failed"), coded("ETIMEDOUT"), coded("UND_ERR_CONNECT_TIMEOUT"), Object.assign(new Error("socket"), { cause: new Error("other side closed") })]) {
    const { code, writes } = await run([pull(1)], {}, { armErrors: { PR_1: [error] } });
    assert.equal(code, 0);
    assert.equal(writes.length, 2);
  }
  const { code, writes } = await run([pull(1)], {}, { armErrors: { PR_1: [coded("EPIPE_NOT_LISTED")] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 1);
});

test("an arm GitHub answers with a rate limit is never sent again", async () => {
  // GitHub answers a primary or secondary limit with 403 or 429; sending more
  // while limited risks the integration's ban.
  for (const status of [403, 429]) {
    const { code, writes, slept } = await run([pull(1)], {}, { armErrors: { PR_1: [new GitHubError(status, "POST /graphql")] } });
    assert.equal(code, 1);
    assert.equal(writes.length, 1);
    assert.deepEqual(slept, []);
  }
});

const unanswered = () => new GitHubError(502, "POST /graphql");
const readBacks = (calls) => calls.filter(({ body }) => body?.query === AUTO_MERGE_STATE_QUERY).length;

test("a resent arm that errors with the pull request already armed at its head reads it back once and counts it armed", async () => {
  const { code, writes, lines, calls, statuses } = await run([pull(1, { after: { state: "OPEN", headRefOid: HEAD, autoMergeRequest: { enabledAt: NOW } } })], {}, { armErrors: { PR_1: [reset(), unanswered()] } });
  assert.equal(code, 0);
  assert.equal(writes.length, 2);
  assert.equal(readBacks(calls), 1);
  assert.ok(lines.includes(`enable-auto-merge: #1 arm failed after a resend (POST /graphql failed with status 502), but it is already armed at ${HEAD}, so an earlier send landed`));
  assert.ok(lines.includes(`enable-auto-merge: #1 armed at ${HEAD}`));
  assert.deepEqual(statuses, [{ sha: HEAD, state: "success", description: "armed for native auto-merge" }]);
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("a resent arm that errors while the pull request is unarmed or armed at another head still fails, naming it and the cause", async () => {
  for (const after of [undefined, { state: "OPEN", headRefOid: "c".repeat(40), autoMergeRequest: { enabledAt: NOW } }, { state: "MERGED", headRefOid: HEAD, autoMergeRequest: { enabledAt: NOW } }, "error"]) {
    const { code, lines, calls } = await run([pull(1, { after })], {}, { armErrors: { PR_1: [reset(), unanswered()] } });
    assert.equal(code, 1);
    assert.equal(readBacks(calls), 1);
    assert.ok(lines.includes("::error title=enable-auto-merge::#1 arm: POST /graphql failed with status 502"), String(after));
    assert.ok(!lines.some((line) => line.startsWith("enable-auto-merge: #1 armed")));
  }
});

test("an arm that errors on its first send, or with a rate limit, is not read back", async () => {
  const after = { state: "OPEN", headRefOid: HEAD, autoMergeRequest: { enabledAt: NOW } };
  for (const errors of [[unanswered()], [reset(), new GitHubError(403, "POST /graphql")]]) {
    const { code, calls } = await run([pull(1, { after })], {}, { armErrors: { PR_1: errors } });
    assert.equal(code, 1);
    assert.equal(readBacks(calls), 0);
  }
});

test("a resent disarm that errors with the pull request already unarmed counts it disarmed and writes the note", async () => {
  const armed = pull(1, { autoMergeRequest: {}, verdict: MISSING, after: { state: "OPEN", headRefOid: HEAD, autoMergeRequest: null } });
  const { code, writes, notes, lines, calls } = await run([armed], {}, { disarmErrors: { PR_1: [reset(), new GitHubError(200, "POST /graphql (GraphQL errors)")] } });
  assert.equal(code, 0);
  assert.deepEqual(writes, Array(2).fill({ mutation: "disarm", id: "PR_1" }));
  assert.equal(readBacks(calls), 1);
  assert.ok(lines.includes("enable-auto-merge: #1 disarm failed after a resend (POST /graphql (GraphQL errors) failed with status 200), but it is already unarmed, so an earlier send landed"));
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("a resent disarm that errors while the pull request is still armed, merged, or not read as a pull request fails, naming it and the cause, and writes no note", async () => {
  for (const after of [undefined, { state: "MERGED", headRefOid: HEAD, autoMergeRequest: null }, {}]) {
    const armed = pull(1, { autoMergeRequest: {}, verdict: MISSING, after });
    const { code, notes, lines, calls } = await run([armed], {}, { disarmErrors: { PR_1: [reset(), new GitHubError(200, "POST /graphql (GraphQL errors)")] } });
    assert.equal(code, 1, JSON.stringify(after));
    assert.equal(readBacks(calls), 1);
    assert.deepEqual(notes, []);
    assert.ok(lines.includes("::error title=enable-auto-merge::#1 disarm: POST /graphql (GraphQL errors) failed with status 200"));
  }
});

test("the resend warning names the arm and its pull request", async () => {
  const { lines } = await run([pull(1)], {}, { armErrors: { PR_1: [closed()] } });
  assert.ok(lines.some((line) => line.startsWith("::warning::enable-auto-merge: POST /graphql (arm) for PR_1 failed (TypeError UND_ERR_SOCKET)")));
});

test("every request asks GitHub to close its connection after answering", async () => {
  const { calls } = await run([pull(1)]);
  assert.ok(calls.length > 1);
  assert.ok(calls.every(({ headers }) => headers?.Connection === "close"));
});

test("an arm GitHub refuses with GraphQL errors or a 4xx is skipped with a warning, not sent again, and the run stays green", async () => {
  for (const error of [new GitHubError(200, "POST /graphql (GraphQL errors)"), new GitHubError(422, "POST /graphql"), new GitHubError(404, "POST /graphql")]) {
    const { code, writes, slept, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [error] } });
    assert.equal(code, 0);
    assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
    assert.deepEqual(slept, []);
    assert.ok(lines.includes(`::warning title=enable-auto-merge::#1 arm refused, skipped this run: ${error.message}`));
    assert.ok(!lines.some((line) => line.startsWith("::error")));
  }
});

test("a refused arm on one of two pull requests still arms the other, inside a cap of one", async () => {
  const refusal = new GitHubError(200, "POST /graphql (GraphQL errors)");
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [refusal] } }, { ...ROOM, cap: 1 });
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.includes(`enable-auto-merge: #2 armed at ${HEAD}`));
});

test("two arms each refused for their own reason (422) are warned and the run stays green", async () => {
  const refusal = () => new GitHubError(422, "POST /graphql");
  const { code, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [refusal()], PR_2: [refusal()] } });
  assert.equal(code, 0);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#2 arm refused")));
  assert.ok(lines.includes("::warning title=enable-auto-merge::every arm this run failed: #1, #2"));
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("two or more arms all answered 404 fail the run and say so", async () => {
  const missing = () => new GitHubError(404, "POST /graphql");
  const { code, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [missing()], PR_2: [missing()] } });
  assert.equal(code, 1);
  assert.ok(lines.includes("::error title=enable-auto-merge::every arm this run failed: #1, #2"));
});

test("an arm answered 401, 403, 429 or 5xx is not a refusal of that pull request: not sent again, and the run fails", async () => {
  for (const status of [401, 403, 429, 502]) {
    const { code, writes, slept, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [new GitHubError(status, "POST /graphql")] } });
    assert.equal(code, 1);
    assert.equal(writes.length, 1);
    assert.deepEqual(slept, []);
    assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm:")));
  }
});

// main's own client over a stubbed fetch, so the arm's answer carries real
// headers and body: `arm` is the Response every arm gets.
async function served(pulls, arm) {
  const { github, verify } = world(pulls);
  const saved = globalThis.fetch;
  const lines = [];
  const log = console.log;
  globalThis.fetch = async (url, init) => {
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    if (body?.query === ARM_MUTATION) {
      return arm();
    }
    const answer = await github(init.method, new URL(url).pathname + new URL(url).search, body, init.headers);
    return new Response(answer == null ? "" : JSON.stringify(answer), { status: 200, headers: { "content-type": "application/json" } });
  };
  console.log = (line) => lines.push(line);
  try {
    // Its own latch: one case's rate limit neither refuses the next case's
    // calls nor fails this process.
    const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null });
    return { code: await main({ env: { ...ENV, GH_TOKEN: "t" }, verify, room: room(), sleep: async () => {}, latch }), lines };
  } finally {
    globalThis.fetch = saved;
    console.log = log;
  }
}

test("a refused arm's warning carries GitHub's own message", async () => {
  const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ message: "Pull request is in clean status" }] }));
  assert.equal(code, 0);
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm refused, skipped this run: POST /graphql (GraphQL errors) failed with status 200: Pull request is in clean status"));
});

test("a rate-limited GraphQL answer to an arm is not a refusal, and the run fails", async () => {
  for (const headers of [{ "x-ratelimit-remaining": "0" }, { "retry-after": "60" }]) {
    const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ message: "API rate limit exceeded" }] }, { headers }));
    assert.equal(code, 1);
    assert.ok(!lines.some((line) => line.includes("arm refused")));
  }
});

test("a GraphQL answer typed RATE_LIMITED is rate-limited without its headers, and the run fails", async () => {
  const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ type: "RATE_LIMITED", message: "API rate limit exceeded" }] }));
  assert.equal(code, 1);
  assert.ok(!lines.some((line) => line.includes("arm refused")));
});

test("a GraphQL answer typed FORBIDDEN or INSUFFICIENT_SCOPES is not a refusal of that pull request, and the run fails", async () => {
  for (const type of ["FORBIDDEN", "INSUFFICIENT_SCOPES"]) {
    const { code, lines } = await served([pull(1), pull(2)], () => Response.json({ errors: [{ type, message: "Resource not accessible by integration" }] }));
    assert.equal(code, 1);
    assert.ok(!lines.some((line) => line.includes("arm refused")));
    assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm:")));
  }
});

test("a logged cause has any token in it scrubbed", async () => {
  const leak = new TypeError("fetch failed", { cause: Object.assign(new Error("bad header Bearer ghs_abc123 sent github_pat_11AB_cd"), { code: "UND_ERR_SOCKET" }) });
  const { lines } = await run([pull(1)], {}, { armErrors: { PR_1: [leak, leak, leak] } });
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed (cause: UND_ERR_SOCKET bad header *** sent ***)"));
  assert.ok(!lines.some((line) => line.includes("ghs_abc123") || line.includes("github_pat_")));
});

test("a bad bot login or repository fails red", async () => {
  assert.equal((await run([pull(1)], { LANES_BOT_LOGIN: "kyle-sexton" })).code, 1);
  assert.equal((await run([pull(1)], { GITHUB_REPOSITORY: "nope" })).code, 1);
});

test("decide leaves a pull request with no labels read alone", () => {
  assert.deepEqual(decide(pull(1, { labels: null }), { bot: LANES.login, humanGated: "needs-human" }), {
    action: "none",
    reason: "its labels could not all be read",
  });
});

test("the body hold agrees with the gate's BODY_MERGE_HOLD_RE", () => {
  const bodies = [
    "Hold: a human merges this",
    "Closes #1\n\nHold: x",
    "Closes #1\r\n   HOLD: x",
    "Closes #1\rhold: x",
    "Closes #1\n\nthe hold: is not at the line start",
    "Closes #1\n\nDon't merge",
    "Closes #1\n\ndon’t  merge this",
    "Closes #1\n\nDo NOT\nmerge",
    "Closes #1\n\ndonut merge",
    "Closes #1\n\nwhat to do: merge it",
    "Closes #1\n\nnothing here",
    "",
  ];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge_policy import BODY_MERGE_HOLD_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => BODY_HOLD.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});

test("TRUST_REFUSALS are the reasons the gate's trust_refusal returns, and each goes to a person", () => {
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    [
      "-c",
      "import ast,inspect,json\nfrom babysit_merge_policy import trust_refusal as f\n" +
        "print(json.dumps(sorted({n.value.value for n in ast.walk(ast.parse(inspect.getsource(f))) if isinstance(n, ast.Return) and isinstance(n.value, ast.Constant) and isinstance(n.value.value, str)})))",
    ],
    { cwd: scripts, encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  assert.deepEqual([...TRUST_REFUSALS].sort(), JSON.parse(python.stdout));
  for (const reason of TRUST_REFUSALS) {
    assert.equal(verifyClears({ head: "a".repeat(40), ineligible: reason }, "a".repeat(40)), "person", reason);
  }
  assert.equal(verifyClears({ head: "a".repeat(40), ineligible: "refs-issues:2" }, "a".repeat(40)), "lane");
});

// The body the issue lane opens its pull request with (report-outcome.mjs
// decide), so a change to either side that stops a clean lane pull request
// from arming, or arms a held one, fails here.
test("report-outcome's own Closes and Refs pull request bodies arm, and its hold bodies do not", () => {
  const plan = (overrides) =>
    decideOutcome({
      outcome: { exit: "done", reason: "", title: "docs(work-items): fix a typo", summary: "Fixed it." },
      issueNumber: 77,
      issueLabels: ["agent-ready"],
      branch: "work-resolve-issue/issue-77-123-1",
      changedFiles: ["plugins/work-items/README.md"],
      holdPaths: [".github/**"],
      checks: { tip: HEAD, results: [] },
      ...overrides,
    });
  const verdict = (overrides) => {
    const opened = plan(overrides);
    assert.equal(opened.action, "open-pr");
    // Files outside the hold paths, so only the body decides.
    return decide(pull(1, { body: opened.body }), { bot: "melodic-automation-lanes", humanGated: "needs-human", holdPaths: [".github/**"] }, { ...detail(), files: [], verify: PASSED });
  };
  assert.deepEqual(verdict({}), { action: "arm", reason: "no hold" });
  assert.equal(verdict({ humanMerge: true }).action, "none");
  assert.equal(verdict({ changedFiles: [".github/workflows/x.yml"] }).action, "none");
  const refs = { outcome: { exit: "done", reason: "", title: "t", summary: "s", remaining: ["Part B"] } };
  assert.ok(plan(refs).body.startsWith("Refs: #77\n"));
  assert.deepEqual(verdict(refs), { action: "arm", reason: "no hold" });
});

// The gate's human veto (babysit_merge.human_veto_logins): each member's
// newest comment, review or inline comment with text decides, so a later
// comment lifts the hold; a non-member's, a bot's or an empty one counts for
// nothing. Native auto-merge skips that gate, so the arm rule applies it.
test("a member's newest comment saying not to merge holds, and a later one lifts it", async () => {
  const veto = said("kyle-sexton", "Please don't merge this yet.", "2026-10-23T10:00:00Z");
  const { code, writes } = await run([
    pull(1, { discussion: { comments: [veto] } }),
    pull(2, { discussion: { comments: [veto, said("kyle-sexton", "Go ahead.", "2026-10-23T11:00:00Z")] } }),
    pull(3, { discussion: { comments: [said("someone", "do not merge", "2026-10-23T10:00:00Z", "CONTRIBUTOR")] } }),
    pull(4, { discussion: { comments: [said("codex", "do not merge", "2026-10-23T10:00:00Z", "NONE", "Bot")] } }),
    pull(5, { discussion: { reviews: [{ ...veto, createdAt: undefined, submittedAt: veto.createdAt }] } }),
    pull(6, { discussion: { inline: [said("kyle-sexton", "do-not merge until the canary", "2026-10-23T10:00:00Z", "MEMBER")] } }),
    pull(7, { discussion: { comments: [veto, said("kyle-sexton", "", "2026-10-23T11:00:00Z")] } }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(
    writes.map(({ id }) => id),
    ["PR_2", "PR_3", "PR_4"],
  );
});

test("an armed pull request a member now vetoes is disarmed", async () => {
  const { writes } = await run([
    pull(1, { autoMergeRequest: {}, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
});

test("a pull request whose discussion cannot all be read is not armed", async () => {
  const cut = { totalCount: 101, nodes: [] };
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  assert.equal(decide(pull(1), options, { ...detail(), files: [], verify: PASSED }).action, "arm");
  const held = (pr) => decide(pull(1), options, { ...detail(), files: [], ...pr });
  assert.equal(held({ comments: cut }).action, "none");
  assert.equal(held({ reviews: cut }).action, "none");
  assert.equal(held({ reviewThreads: cut }).action, "none");
  assert.equal(held({ reviewThreads: page([{ comments: cut }]) }).action, "none");
  // A read that failed leaves it as it is, armed or not, until the next run.
  assert.equal(decide(pull(1), options, null).action, "none");
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, null).action, "none");
});

test("auto-merge a person turned off stays off; one the lanes App turned off is armed again", async () => {
  const { writes } = await run([
    pull(1, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
    pull(2, { discussion: { disabledBy: { __typename: "Bot", login: "melodic-automation-lanes" } } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("the comment veto agrees with the gate's HUMAN_MERGE_VETO_RE", () => {
  const bodies = ["do not merge", "Don't merge", "don’t merge", "dont-merge", "do-not merge", "Do NOT\nmerge", "donut merge", "merge it", "doesn't merge", "", "do-not-merge", "ci-status, gitleaks, do-not-merge, cost holds", "the `do-not-merge` label", "removed the do-not-merge label", "Not ready, do-not-merge until Friday.", "Sorry, do-not-merge this.", "`do-not-merge` label please", "a, b, do-not-merge", "Hold on, do-not-merge, I'm still reviewing."];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge import HUMAN_MERGE_VETO_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => HUMAN_VETO.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});

// The merge lane's denied paths (report-outcome.readHoldPaths), on the head's
// files now: report-outcome's Hold: line covers only the files at opening, and
// a later push can add a held path to a pull request that is already armed.
test("a pull request whose head now changes a hold path is not armed, or is disarmed", async () => {
  const { writes } = await run([
    pull(1, { files: [{ filename: "docs/conventions/pr-pipeline.yaml" }] }),
    pull(2, {
      autoMergeRequest: {},
      files: [{ filename: "plugins/a/README.md" }, { filename: "docs/a.md", previous_filename: ".github/standards/trusted-actors/trusted-actors.json" }],
    }),
    pull(3, { files: Array.from({ length: 301 }, (_, index) => ({ filename: `docs/${index}.md` })) }),
    pull(4, { files: [{ filename: "docs/held.md" }] }),
    pull(5),
    // The rest of .github merges on the review lanes.
    pull(6, { files: [{ filename: ".github/workflows/x.yml" }, { filename: ".github/scripts/pr-unblock/other.mjs" }] }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_5", head: HEAD },
    { mutation: "arm", id: "PR_6", head: HEAD },
  ]);
});

// ci-status lifts a hold path on a trusted person's approving review of the
// head (merge-holds.pathLifters); arming reads the same rule. Kyle (id 5) is
// on the trusted-actor list, id 9 is not.
const reviewed = (state, { id = 5, login = "kyle-sexton", oid = HEAD, at = "2026-10-26T16:41:00Z" } = {}) => ({
  author: { __typename: "User", login, databaseId: id },
  state,
  commit: { oid },
  body: "",
  submittedAt: at,
  authorAssociation: "OWNER",
});
// The REST issue timeline of a hold-path escalation the lane may lift: the
// App's person refusal, the App's label a second later (refusalWrites posts
// the comment first), then Kyle's approval of the head.
const APP_USER = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const KYLE = { login: "kyle-sexton", id: 5, type: "User" };
const restSaid = (user, body, at) => ({ event: "commented", user, body, created_at: at, updated_at: at });
const labelEvent = (actor, at, { event = "labeled", name = "needs-human" } = {}) => ({ event, actor, label: { name }, created_at: at });
const liftTimeline = (note = personNote(HOLD_PATH_REASON)) => [
  restSaid(APP_USER, note, "2026-10-23T10:00:00Z"),
  labelEvent(APP_USER, "2026-10-23T10:00:01Z"),
  { event: "reviewed", user: KYLE, state: "approved", submitted_at: "2026-10-26T16:41:00Z", commit_id: HEAD },
];
function trustedKyle() {
  const dir = tempDir("enable-auto-merge-");
  writeFileSync(join(dir, "actors.json"), JSON.stringify({ actors: [{ kind: "human", login: "kyle-sexton", id: 5 }] }));
  return { TRUSTED_ACTORS: join(dir, "actors.json") };
}
const HELD = [{ filename: "docs/held.md" }];

test("a hold path a trusted person approved at the head is armed, and an armed one stays armed", async () => {
  const approved = { reviews: [reviewed("APPROVED")] };
  const { writes } = await run([pull(50, { files: HELD, discussion: approved }), pull(51, { files: HELD, discussion: approved, autoMergeRequest: {} })], trustedKyle());
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_50", head: HEAD }]);
});

test("a hold path stays held without a trusted approval of the head", async () => {
  const { writes } = await run(
    [
      pull(52, { files: HELD, discussion: { reviews: [reviewed("APPROVED", { oid: "c".repeat(40) })] } }),
      pull(53, { files: HELD, discussion: { reviews: [reviewed("APPROVED", { id: 9, login: "someone" })] } }),
      pull(54, { files: HELD, discussion: { reviews: [reviewed("APPROVED"), reviewed("CHANGES_REQUESTED", { at: "2026-10-26T17:20:00Z" })] } }),
      pull(55, { files: HELD, discussion: { reviews: [reviewed("APPROVED", { id: 9, login: "someone" })] }, autoMergeRequest: {} }),
    ],
    trustedKyle(),
  );
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_55" }]);
});

// The churn measured on #10224: Kyle approved OLD, then a lane merged the
// base. The approval carries to the merge, so it arms and is not labeled
// again; a merge that also edits the hold path is sent back to a person, and
// a label removal alone lifts nothing (the owner's decision on #10596).
test("an approval before a base merge, or its stale dismissal, lifts the hold path at the merge, and an evil merge, a dismissal with a message or a label removal does not", async () => {
  const OLD = "a".repeat(40);
  const MAIN = "5".repeat(40);
  const P = "/repos/melodic-software/claude-code-plugins";
  const held = { filename: "docs/held.md", status: "modified", patch: "@@ -1 +1 @@\n-a\n+b" };
  const approval = { id: 41, user: { login: "kyle-sexton", id: 5, type: "User" }, state: "APPROVED", commit_id: OLD, submitted_at: "2026-10-27T23:26:14Z" };
  // main resolves to TIP, its tip commit, which every compare names.
  const TIP = "3".repeat(40);
  const rest = (number, headFiles, reviews = [approval]) => ({
    [`${P}/pulls/${number}`]: { head: { sha: HEAD, ref: `fix/held-${number}`, repo: { full_name: "melodic-software/claude-code-plugins" } }, base: { ref: "main" }, changed_files: headFiles.length },
    [P]: { full_name: "melodic-software/claude-code-plugins", default_branch: "main" },
    [`${P}/git/ref/heads/main`]: { ref: "refs/heads/main", object: { type: "commit", sha: TIP } },
    [`${P}/pulls/${number}/reviews?per_page=100&page=1`]: reviews,
    [`${P}/compare/${TIP}...${OLD}`]: { files: [held], commits: [{ sha: OLD, parents: [{ sha: MAIN }] }], total_commits: 1 },
    [`${P}/compare/${MAIN}...${TIP}`]: { status: "ahead" },
    [`${P}/compare/${TIP}...${HEAD}`]: { files: headFiles, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] }], total_commits: 2 },
  });
  const lifted = await run([pull(60, { files: HELD, rest: rest(60, [held]) })], trustedKyle());
  assert.deepEqual(lifted.writes, [{ mutation: "arm", id: "PR_60", head: HEAD }]);
  assert.deepEqual(lifted.notes, []);
  const evil = await run([pull(61, { files: HELD, rest: rest(61, [{ ...held, patch: "@@ -1 +1 @@\n-a\n+evil" }]) })], trustedKyle());
  assert.deepEqual(evil.writes, []);
  assert.deepEqual(evil.notes.map(({ path }) => path), [`${ISSUES}/61/comments`, `${ISSUES}/61/labels`]);
  // The label history the earlier reader bound a removal by.
  const removal = {
    ...rest(62, [held], []),
    [`${P}/issues/62/events?per_page=100&page=1`]: [
      { event: "labeled", label: { name: "needs-human" }, actor: { id: 2, login: "lanes[bot]" }, performed_via_github_app: { slug: "lanes" }, created_at: "2026-10-27T23:05:00Z" },
      { event: "unlabeled", label: { name: "needs-human" }, actor: { id: 5, login: "kyle-sexton" }, performed_via_github_app: null, created_at: "2026-10-27T23:26:14Z" },
    ],
    [`${P}/activity?ref=refs%2Fheads%2Ffix%2Fheld-62&direction=desc&per_page=100`]: [
      { after: HEAD, timestamp: "2026-10-27T23:32:00Z" },
      { after: OLD, timestamp: "2026-10-27T23:00:00Z" },
    ],
  };
  const removed = await run([pull(62, { headRefName: "fix/held-62", files: HELD, rest: removal })], trustedKyle());
  assert.deepEqual(removed.writes, []);
  // The owner's decision of 2026-10-28: the approval GitHub dismissed as
  // stale on the merge's push (a Bot's dismissal with no message, by the
  // pushed head) still carries; one dismissed with a message does not.
  const dismissedEvent = (message) => ({
    event: "review_dismissed",
    actor: { login: "lanes[bot]", type: "Bot" },
    dismissed_review: { review_id: 41, state: "approved", dismissal_message: message, dismissal_commit_id: HEAD },
  });
  const staleRest = (number, message) => ({
    ...rest(number, [held], [{ ...approval, state: "DISMISSED" }]),
    [`${P}/issues/${number}/timeline?per_page=100&page=1`]: [dismissedEvent(message)],
  });
  const stale = await run([pull(63, { files: HELD, rest: staleRest(63, null) })], trustedKyle());
  assert.deepEqual(stale.writes, [{ mutation: "arm", id: "PR_63", head: HEAD }]);
  assert.deepEqual(stale.notes, []);
  const revoked = await run([pull(64, { files: HELD, rest: staleRest(64, "stale") })], trustedKyle());
  assert.deepEqual(revoked.writes, []);
  assert.deepEqual(revoked.notes.map(({ path }) => path), [`${ISSUES}/64/comments`, `${ISSUES}/64/labels`]);
});

test("an approval lifts no unread hold-path check and no capped file listing", () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const armed = pull(1, { autoMergeRequest: {} });
  const approved = { ...detail(), lifters: ["kyle-sexton"], verify: PASSED };
  assert.deepEqual(decide(armed, options, { ...approved, files: null }), { action: "disarm", reason: "its changed files could not all be read", clears: "lane" });
  assert.deepEqual(decide(armed, options, { ...approved, files: ["docs/a.md"], filesCapped: true }), { action: "disarm", reason: FILES_CAPPED_REASON, clears: "person" });
});

// A manifest is no hold path: the gate's reader scores it (`evidence
// --lane-reviews`, babysit_risk manifest-review-required), so a manifest
// change the gate reviews is not armed, or is disarmed, and one it does not,
// such as a plugin.json userConfig default (#9483), arms.
test("a manifest change arms only when the gate's risk score allows it", () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["docs/a.md", ".claude-plugin/marketplace.json", "plugins/a/.claude-plugin/plugin.json"];
  // Owner Q-FLOOR (B): the security lane, not a person, reviews a manifest.
  const review = { ...PASSED, reviews: "manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks", reviewsPerson: false };
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: review }), {
    action: "none",
    reason: "pr-merge's gate holds it on its risk score (manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks)",
    clears: "lane",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: review }).action, "disarm");
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), { action: "arm", reason: "no hold" });
});

// The gate holds a cost path (babysit_risk.COST_PATHS) until the body links
// the owner's cost decision (babysit_merge_policy.cost_decision).
test("a cost path holds until the body links the owner's cost decision", async () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["infra/Pulumi.prod.yaml"];
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), {
    action: "none",
    reason: "it changes infra/Pulumi.prod.yaml, a cost path",
    clears: "person",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: PASSED }).action, "disarm");
  assert.equal(decide(pull(1), options, { ...detail(), files, costDecision: COST_LINK, verify: PASSED }).action, "arm");

  const dir = tempDir("enable-auto-merge-");
  writeFileSync(join(dir, "actors.json"), JSON.stringify({ actors: [{ kind: "human", login: "kyle-sexton", id: 5 }] }));
  const cost = [{ filename: "infra/main.tf" }];
  const decided = `Closes #1040\n\nCost decision: ${COST_LINK}`;
  const { writes } = await run(
    [pull(40, { files: cost, body: decided }), pull(41, { files: cost }), pull(42, { files: cost, body: decided })],
    { TRUSTED_ACTORS: join(dir, "actors.json") },
  );
  // Pull request 41 links no decision; 42 closes a different issue, so pull
  // request 40's decision does not cover it.
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_40", head: HEAD }]);
  // A changed file's name cannot start a workflow command on its own line.
  const { lines } = await run([pull(43, { files: [{ filename: "x\n::warning::forged/main.tf" }] })]);
  assert.ok(lines.some((line) => line.includes("x ::warning::forged/main.tf, a cost path")));
  assert.ok(!lines.some((line) => /(^|\n)::warning::/.test(line)));
  // Not on the trusted-actor list, the commenter decides nothing.
  assert.deepEqual((await run([pull(40, { files: cost, body: decided })], { TRUSTED_ACTORS: "/nonexistent/actors.json" })).writes, []);
});

// ci-status runs merge-holds.mjs on the live files with the base config's
// denied paths, by the same pathHold that decides arming above.
test("merge-holds.mjs holds a changed or renamed-from hold path from the command line", () => {
  const dir = tempDir("merge-holds-");
  const head = "0123456789abcdef0123456789abcdef01234567";
  const cli = (files, denied, reviews = []) => {
    writeFileSync(join(dir, "body"), "Closes #1");
    writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "ana", id: 5 }] }));
    writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "denied"), JSON.stringify(denied));
    const args = [...["7", "body", "discussion", "files", "denied", "actors"].map((name, index) => (index ? join(dir, name) : name)), head];
    return spawnSync(process.execPath, [fileURLToPath(new URL("./merge-holds.mjs", import.meta.url)), ...args], { encoding: "utf8" });
  };
  assert.equal(cli([["docs/a.md"]], ["docs/held.md"]).status, 0);
  // A floor path holds with no configured glob (owner decision Q-FLOOR (B));
  // no other trusted path or manifest holds unless the config lists it.
  assert.match(cli([[".github/actions/resolve-config/.x.mjs"]], []).stdout, /it changes \.github\/actions\/resolve-config\/\.x\.mjs, a hold path/);
  assert.equal(cli([[".github/actions/check-wip-cap/x.mjs"]], []).status, 0);
  assert.match(cli([[".github/actions/check-wip-cap/x.mjs"]], [".github/actions/**"]).stdout, /it changes \.github\/actions\/check-wip-cap\/x\.mjs, a hold path/);
  assert.equal(cli([[".github/workflows/x.yml"]], []).status, 0);
  assert.equal(cli([{ filename: "plugins/a/.claude-plugin/plugin.json", status: "modified" }], []).status, 0);
  assert.match(cli([["plugins/a/.hidden"]], ["plugins/**"]).stdout, /it changes plugins\/a\/\.hidden, a hold path/);
  assert.equal(cli([["plugins/a/x.md"]], ["plugins/*.md"]).status, 0);
  const renamed = cli([["docs/a.md", ".github/actions/check-trusted-trigger/a.md"]], []);
  assert.equal(renamed.status, 1);
  assert.match(renamed.stdout, /it changes \.github\/actions\/check-trusted-trigger\/a\.md, a hold path/);
  assert.match(cli([["docs/held.md"]], ["docs/held.md"]).stdout, /it changes docs\/held\.md, a hold path/);
  assert.match(cli([["docs/a.md"]], "docs/held.md").stdout, /the hold paths could not be read/);
  const approve = (id, commit) => ({ user: { login: `u${id}`, id, type: "User" }, state: "APPROVED", commit_id: commit, submitted_at: "2026-10-23T11:00:00Z" });
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, head)]).status, 0);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(6, head)]).status, 1);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, "f".repeat(40))]).status, 1);
  assert.equal(cli([["docs/a.md"]], "docs/held.md", [approve(5, head)]).status, 1);
});

test("hold paths that cannot be read arm nothing and label nothing", async () => {
  const { writes, notes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {} })], { RESOLVED_CONFIG: "/nonexistent/resolved-config.json" });
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::the resolved config's hold paths did not read")));
});

// More than 100 labels is read whole, not refused.
test("a label list the listing cut is read whole", async () => {
  const many = Array.from({ length: 150 }, (_, index) => `area-${index}`);
  const cut = (all) => ({ totalCount: all.length, nodes: all.slice(0, 100).map((name) => ({ name })) });
  const { writes } = await run([
    pull(1, { labels: cut(many), allLabels: many }),
    pull(2, { labels: cut([...many, "do-not-merge"]), allLabels: [...many, "do-not-merge"] }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
});

// More than 100 comments is read whole, so a veto past the first page
// still holds and none there arms.
test("a comment list the detail cut is read whole", async () => {
  const chatter = Array.from({ length: 3 }, (_, index) => said("kyle-sexton", `note ${index}`, `2026-10-23T0${index}:00:00Z`));
  const veto = said("kyle-sexton", "do not merge", "2026-10-23T09:00:00Z");
  const cut = (comments) => ({ ...detail({ comments }), comments: { totalCount: comments.length, nodes: comments.slice(-1) } });
  const { writes, lines } = await run([
    pull(1, { discussion: { comments: chatter }, cutDiscussion: cut(chatter) }),
    pull(2, { discussion: { comments: [veto, ...chatter] }, cutDiscussion: cut([veto, ...chatter]) }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.ok(lines.includes("enable-auto-merge: #2 left: kyle-sexton asked not to merge it"), lines.join("\n"));
});

// A review thread whose comments the detail cut is read whole by its id, so
// a veto in its first comments still holds.
test("a review thread's comment list the detail cut is read whole, page by page", async () => {
  const chatter = Array.from({ length: 3 }, (_, index) => said("kyle-sexton", `note ${index}`, `2026-10-23T0${index}:00:00Z`));
  // Another member's only comment, the oldest, so only a whole read sees it.
  const veto = said("other-member", "do not merge", "2026-10-22T09:00:00Z", "MEMBER");
  const cut = (id, comments) => ({ ...detail(), reviewThreads: page([{ id, comments: { totalCount: comments.length, nodes: comments.slice(-1) } }]) });
  const { writes, lines, calls } = await run([
    pull(1, { cutDiscussion: cut("T1", chatter), threads: { T1: chatter } }),
    pull(2, { cutDiscussion: cut("T2", [veto, ...chatter]), threads: { T2: [veto, ...chatter] } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.ok(lines.includes("enable-auto-merge: #2 left: other-member asked not to merge it"), lines.join("\n"));
  const pages = calls.filter(({ body }) => body?.query === THREAD_PAGE_QUERY).map(({ body }) => body.variables);
  assert.deepEqual(pages, [
    { id: "T1", after: null },
    { id: "T1", after: "2" },
    { id: "T2", after: null },
    { id: "T2", after: "2" },
  ]);
});

// A list longer than the read caps (30 discussion pages, 10 label pages, by
// enable-auto-merge.mjs's MAX_DISCUSSION_PAGES and MAX_LABEL_PAGES) stops the
// read, and a pull request it stopped on is not armed.
test("a discussion or label list past its page cap arms nothing", async () => {
  const comments = (count) => Array.from({ length: count }, (_, index) => said("kyle-sexton", `note ${index}`, "2026-10-23T01:00:00Z"));
  const cutOf = (all) => ({ ...detail({ comments: all }), comments: { totalCount: all.length, nodes: all.slice(-1) } });
  const names = (count) => Array.from({ length: count }, (_, index) => `area-${index}`);
  const cutLabels = (all) => ({ totalCount: all.length, nodes: all.slice(0, 100).map((name) => ({ name })) });
  const { writes, lines } = await run([
    // 60 comments are 30 pages of two; 62 need a 31st.
    pull(1, { discussion: { comments: comments(60) }, cutDiscussion: cutOf(comments(60)) }),
    pull(2, { discussion: { comments: comments(62) }, cutDiscussion: cutOf(comments(62)) }),
    // 999 labels end on a short 10th page; 1000 fill it, so an 11th is unread.
    pull(3, { labels: cutLabels(names(999)), allLabels: names(999) }),
    pull(4, { labels: cutLabels(names(1000)), allLabels: names(1000) }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_3", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.startsWith("enable-auto-merge: #2 discussion did not read: ") && line.includes("a discussion list longer than 3000")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("enable-auto-merge: #4 labels did not read whole: ") && line.includes("more than 1000 labels")), lines.join("\n"));
});

// A deleted account reads as a null author or editor, which counts as a
// person (merge-holds.personWrote), so a hold it wrote still holds.
test("a deleted author or editor counts as a person who wrote the body", () => {
  const edits = (...editors) => ({ totalCount: editors.length, nodes: editors.map((editor) => ({ editor })) });
  const bot = { __typename: "Bot" };
  assert.equal(personWrote({ author: bot, userContentEdits: edits() }), false);
  assert.equal(personWrote({ author: bot, userContentEdits: edits(bot) }), false);
  assert.equal(personWrote({ author: null, userContentEdits: edits() }), true);
  assert.equal(personWrote({ author: bot, userContentEdits: edits(null) }), true);
  assert.equal(personWrote(null), true);
});

// The lanes App's own body text holds nothing; a person's edit does.
test("a body hold counts only when a person wrote some of the body", async () => {
  const body = "Closes #5\n\nHold: wait for the release.";
  const edits = (...typenames) => ({ totalCount: typenames.length, nodes: typenames.map((__typename) => ({ editor: { __typename } })) });
  const { writes } = await run([
    pull(1, { body, userContentEdits: edits() }),
    pull(2, { body, userContentEdits: edits("Bot") }),
    pull(3, { body, userContentEdits: edits("Bot", "User") }),
    pull(4, { body, userContentEdits: { totalCount: 101, nodes: [] } }),
    pull(5, { body }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
  ]);
});

// report-outcome's own hold line (untrusted-provenance work, a person's
// `merge: human`, a denied path) holds whoever wrote the body.
test("the lane's own hold line holds a lanes App body", async () => {
  assert.equal(`\n${HOLD_LINE}\n`.match(LANE_HOLD)?.[0].trim(), HOLD_LINE);
  const appOnly = { totalCount: 0, nodes: [] };
  const { writes } = await run([
    pull(1, { body: `Closes #5\n\n${HOLD_LINE}`, userContentEdits: appOnly }),
    pull(2, { body: `Closes #5\n\n${HOLD_LINE}\n\n## Summary`, userContentEdits: appOnly }),
    pull(3, { body: `Closes #5\n\nquoted: ${HOLD_LINE}`, userContentEdits: appOnly }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_3", head: HEAD }]);
});

// report-outcome labels a held PR human-merge-hold, so a lanes App edit of
// the body (the hold line deleted, or the Refs line rewritten to a closing
// line) leaves it unarmed while the label is on.
test("a human-merge-hold label holds a lanes App PR whose body lost its hold line or its Refs line", async () => {
  const appOnly = { totalCount: 0, nodes: [] };
  const held = labels("human-merge-hold");
  const { writes } = await run([
    // The hold line deleted from a Refs PR's body.
    pull(1, { body: "Refs: #5\n\n## Summary", labels: held, userContentEdits: appOnly }),
    // The Refs line rewritten to a closing line, the hold line gone with it.
    pull(2, { body: "Closes #5\n\n## Summary", labels: held, userContentEdits: appOnly }),
    pull(3, { body: "Closes #5\n\n## Summary", userContentEdits: appOnly }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_3", head: HEAD }]);
  assert.equal(holdReason({ labels: held, body: "Closes #5" }, "needs-human"), "it carries human-merge-hold");
  assert.equal(holdReason({ labels: labels("Human-Merge-Hold"), body: "Closes #5" }, "needs-human"), "it carries human-merge-hold");
});

// Owner decision Q-HOLDLINE: report-outcome's own hold line is a cause a
// person must clear, so a reader run comments once and adds the human-gated
// label, as for a configured denied path; it puts the label back unless a
// person removed it. A person's own hold text gets neither: they set it.
const LANE_HOLD_REASON = "its body carries the lane's own 'Hold: a human merges this' line: a person merges it by hand, or removes that line";
// LANE_HOLD_REASON as a new comment wraps it at 100 columns.
const LANE_HOLD_NOTE = "its body carries the lane's own 'Hold: a human merges this' line: a person merges it by hand, or\n  removes that line";
const APP_ONLY = { totalCount: 0, nodes: [] };
const laneHeld = (number, overrides = {}) => pull(number, { body: `Closes #5\n\n${HOLD_LINE}`, userContentEdits: APP_ONLY, ...overrides });
test("the lane's own hold line is commented on once and labeled human-gated", async () => {
  const first = await run([laneHeld(1)]);
  assert.equal(first.code, 0);
  assert.deepEqual(first.writes, []);
  assert.deepEqual(first.notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(LANE_HOLD_NOTE) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  // The next run: labeled, it reads the discussion for a partial refusal to
  // widen, finds none, and writes nothing and reads no verdict.
  const labeled = await run([laneHeld(1, { labels: labels("needs-human"), discussion: { comments: [lanesSaid(personNote(LANE_HOLD_REASON))] } })]);
  assert.deepEqual(labeled.notes, []);
  assert.deepEqual(labeled.verified, []);
  // A person removed the label after the comment: it stays off.
  const lifted = await run([laneHeld(1, { discussion: { comments: [lanesSaid(personNote(LANE_HOLD_REASON))] }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })]);
  assert.deepEqual(lifted.notes, []);
  // The label write failed earlier: it goes back on.
  const unlabeledOnce = await run([laneHeld(1, { discussion: { comments: [lanesSaid(personNote(LANE_HOLD_REASON))] } })]);
  assert.deepEqual(unlabeledOnce.notes, [{ method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } }]);
});

// An escalation posts a second comment beside the lane's earlier one, so later
// runs must read the newer one and never post it again.
test("the lane's hold line over a lane's comment posts once, then reads the posted one", async () => {
  const laneComment = lanesSaid(laneNote(MISSING_REASON));
  const first = await run([laneHeld(1, { discussion: { comments: [laneComment] } })]);
  assert.deepEqual(first.notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(LANE_HOLD_NOTE) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
  ]);
  const posted = { ...lanesSaid(personNote(LANE_HOLD_NOTE), "2026-10-23T10:05:00Z"), databaseId: 78, createdAt: "2026-10-23T10:05:00Z" };
  const both = [laneComment, posted];
  const lifted = await run([laneHeld(1, { discussion: { comments: both }, unlabeled: [unlabeled("2026-10-23T10:30:00Z")] })]);
  assert.deepEqual(lifted.notes, []);
  const relabel = await run([laneHeld(1, { discussion: { comments: both } })]);
  assert.deepEqual(relabel.notes, [{ method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } }]);
});

test("a person's own hold text and an event run write no note, and an event run disarms the lane's hold line with no read", async () => {
  const person = { totalCount: 1, nodes: [{ editor: { __typename: "User" } }] };
  const { notes, writes } = await run([pull(1, { body: "Closes #5\n\nHold: waiting on a review", userContentEdits: person })]);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, []);
  const event = await run([laneHeld(2, { autoMergeRequest: {} }), laneHeld(3)], { EVENT_NAME: "pull_request_target", EVENT_PR: "2" });
  assert.deepEqual(event.writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(event.notes, []);
  assert.ok(!event.calls.some(({ body }) => body?.query === DETAIL_QUERY));
  // A reader run disarms an armed one at once too, and notes it on its next run.
  const reader = await run([laneHeld(4, { autoMergeRequest: {} })]);
  assert.deepEqual(reader.writes, [{ mutation: "disarm", id: "PR_4" }]);
  assert.deepEqual(reader.notes, []);
});

// GitHub Support's audit item 5: a pull_request_target run handles only the
// pull request its event names (EVENT_PR), as the listing holds it; the
// scheduled run keeps the whole sweep.
test("an event run handles only its own pull request", async () => {
  const pulls = [laneHeld(2, { autoMergeRequest: {} }), laneHeld(3, { autoMergeRequest: {} })];
  const event = await run(pulls, { EVENT_NAME: "pull_request_target", EVENT_PR: "3" });
  assert.deepEqual(event.writes, [{ mutation: "disarm", id: "PR_3" }]);
  // An event naming no listed pull request handles none.
  assert.deepEqual((await run(pulls, { EVENT_NAME: "pull_request_target", EVENT_PR: "9" })).writes, []);
  // The schedule handles both, whatever EVENT_PR says.
  assert.deepEqual((await run(pulls, { EVENT_PR: "3" })).writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "disarm", id: "PR_3" },
  ]);
});

// The start moves with the run number, so the pull requests past the
// verify budget differ from run to run.
test("the run starts at an offset that moves with the run number", async () => {
  assert.deepEqual(rotated([1, 2, 3], 0), [1, 2, 3]);
  assert.deepEqual(rotated([1, 2, 3], 4), [2, 3, 1]);
  assert.deepEqual(rotated([1, 2, 3], 5), [3, 1, 2]);
  assert.deepEqual(rotated([1, 2, 3], Number.NaN), [1, 2, 3]);
  assert.deepEqual(rotated([], 7), []);
  const { verified } = await run([pull(1), pull(2), pull(3)], { GITHUB_RUN_NUMBER: "4" });
  assert.deepEqual(verified, [2, 3, 1]);
});

// pr-merge's gate merges only on a pr-verify pass at the head, FAILs at fewer
// than merge.max-verify-fails heads (babysit_verify_evidence.py), and native
// auto-merge must not merge what the gate would refuse.
test("no pass at the head, a FAIL or the repeated-FAIL cap arms nothing", async () => {
  const { code, writes, verified } = await run([
    pull(1, { verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { verdict: { refusal: "verify:fail", head: HEAD } }),
    pull(3, { verdict: { refusal: "verify:repeated-fail", head: HEAD, needsHuman: false } }),
    pull(4, { verdict: { refusal: "verify:earlier-fail", head: HEAD } }),
    pull(5, { verdict: { refusal: null, head: "c".repeat(40) } }),
    pull(6, { verdict: new Error("gh: rate limited") }),
    pull(7, { verdict: { refusal: "verify:unreadable", head: HEAD } }),
    pull(8),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(verified, [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_8", head: HEAD }]);
});

test("an armed pull request whose head lost its pass, or passed the cap, is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, lines, closed } = await run([
    // Armed on a passing head, then pushed: the gate finds no verdict at the new head.
    pull(1, { autoMergeRequest: armed, verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { autoMergeRequest: armed, verdict: { refusal: "verify:repeated-fail", head: HEAD } }),
    pull(3, { autoMergeRequest: armed, verdict: new Error("listing failed") }),
    pull(4, { autoMergeRequest: armed }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
    { mutation: "disarm", id: "PR_3" },
  ]);
  assert.ok(lines.some((line) => /#2 disarmed: pr-merge's gate refuses its verifier verdict \(verify:repeated-fail\)/.test(line)));  // Past the cap it is also closed for a fresh attempt, after the disarm.
  assert.deepEqual(closed.map((c) => c.number), [2]);
});

test("the verdict is read only for a lanes App pull request nothing else holds", async () => {
  const { writes, verified } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { labels: labels("do-not-merge") }),
    pull(3, { isDraft: true }),
    pull(4, { discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
    pull(5, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
  ]);
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

test("verifyHold allows only the reader's null refusal at the head read", () => {
  assert.equal(verifyHold(PASSED, HEAD), null);
  assert.match(verifyHold({ refusal: null, head: "c".repeat(40) }, HEAD), /another head/);
  assert.match(verifyHold(null, HEAD), /could not be read/);
  assert.match(verifyHold({ head: HEAD }, HEAD), /could not be read/);
  assert.match(verifyHold({ refusal: "verify:too-old", head: HEAD, ineligible: null }, HEAD), /verify:too-old/);
  // The link's answer: a refusal names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: "verify:ineligible", head: HEAD, ineligible: "refs-issues:2" }, HEAD), /does not take its issue link \(refs-issues:2\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD }, HEAD), /issue link could not be read/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: false }, HEAD), /issue link could not be read/);
  // The review lanes' answer: a hold names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" }, HEAD), /holds it on its risk score \(security-finding: 1 open\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null }, HEAD), /risk score could not be read/);
});

// The gate's cap on a head the merge queue keeps removing for failed checks
// (babysit_merge.unattended_enqueue, merge.max-queue-ejections, default 2):
// the count, the limit and the gate's own comment come from `evidence
// --lane-queue`, and a push resets the count, so the lanes clear it. #8051 and
// #7897 were each re-armed after an ejection and ejected again.
const EJECTION_COMMENT = [
  "<!-- babysit-merge-queue-ejections -->",
  `Unattended merge: the merge queue removed head \`${HEAD}\` 2 times for failed checks, so the pr-merge lane will not enqueue it again. A push resets the count.`,
  "",
  "Failing merge_group runs:",
  `- https://github.com/${REPO}/actions/runs/9`,
].join("\n");
const EJECTED_REFUSAL = `queue-ejected:2 failed-check removals from the merge queue at head ${HEAD}; a push resets the count`;
const EJECTED = { ...PASSED, queue: { failedEjections: 2, limit: 2, refusal: EJECTED_REFUSAL, comment: EJECTION_COMMENT } };

test("a head at the queue-ejection cap is not armed and gets the gate's ejection comment, with no label", async () => {
  const { code, writes, notes, lines } = await run([pull(1, { verdict: EJECTED }), pull(2)]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: EJECTION_COMMENT } }]);
  assert.ok(lines.includes(`enable-auto-merge: #1 left: pr-merge's gate would not enqueue it again (${EJECTED_REFUSAL})`), lines.join("\n"));
});

test("the ejection comment edits the lanes App's earlier one, is not posted again unchanged, and leaves a risk comment alone", async () => {
  const older = EJECTION_COMMENT.replace("runs/9", "runs/8");
  const edited = await run([pull(1, { verdict: EJECTED, discussion: { comments: [lanesSaid(older)] } })]);
  assert.deepEqual(edited.notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: EJECTION_COMMENT } }]);
  const unchanged = await run([pull(1, { verdict: EJECTED, discussion: { comments: [lanesSaid(EJECTION_COMMENT)] } })]);
  assert.deepEqual(unchanged.notes, []);
  const risk = await run([pull(1, { verdict: EJECTED, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON))] } })]);
  assert.deepEqual(risk.notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: EJECTION_COMMENT } }]);
});

test("an ejection count that cannot be read arms nothing and writes no note", async () => {
  const unreadable = { failedEjections: null, limit: 2, refusal: "the merge queue's removals of this head are unreadable", comment: null };
  const { code, writes, notes, lines } = await run([
    pull(1, { verdict: { ...PASSED, queue: unreadable } }),
    pull(2, { verdict: { ...PASSED, queue: undefined } }),
    pull(3, { verdict: { ...PASSED, queue: { refusal: 5 } } }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, []);
  assert.ok(lines.includes("enable-auto-merge: #1 left: pr-merge's gate would not enqueue it again (the merge queue's removals of this head are unreadable)"), lines.join("\n"));
  for (const n of [2, 3]) {
    assert.ok(lines.includes(`enable-auto-merge: #${n} left: its merge-queue ejections could not be read`), lines.join("\n"));
  }
});

// A GraphQL read that keeps failing holds every clean lane pull request, so
// the run names why on each one.
test("an unreadable ejection count is warned with the read's error", async () => {
  const unreadable = { failedEjections: null, limit: 2, refusal: "the merge queue's removals of this head are unreadable", comment: null, readError: "could not read the merge queue: gh: HTTP 502" };
  const { writes, lines } = await run([pull(1, { verdict: { ...PASSED, queue: unreadable } }), pull(2)]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 its merge-queue ejections could not be read: could not read the merge queue: gh: HTTP 502"), lines.join("\n"));
  assert.equal(lines.filter((line) => line.startsWith("::warning")).length, 1, lines.join("\n"));
});

test("report-only writes no ejection comment", async () => {
  const { notes, lines } = await run([pull(1, { verdict: EJECTED })], { REPORT_ONLY: "true" });
  assert.deepEqual(notes, []);
  assert.ok(lines.includes("enable-auto-merge: #1 would note its refusal (report-only)"), lines.join("\n"));
});

// GitHub drops the arm on an ejection, so an armed head over the cap is one a
// person armed again: the cap refuses the lane's arm and leaves that one alone.
test("an armed pull request over the ejection cap is not disarmed", async () => {
  const { writes, notes } = await run([pull(1, { autoMergeRequest: { enabledAt: "2026-10-23T10:00:00Z" }, verdict: EJECTED })]);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, []);
});

// The merge queue's check (merge-holds.mjs verdictHold): a pass counts only
// from pr-verify.yml's completed, successful workflow_run run on main here.
test("verdictHold counts a pass only from a successful pr-verify run on main", () => {
  const run = (overrides = {}) => ({
    id: 11,
    path: VERIFY_PATH,
    event: "workflow_run",
    head_branch: "main",
    status: "completed",
    conclusion: "success",
    repository: { full_name: REPO },
    head_repository: { full_name: REPO },
    ...overrides,
  });
  const hold = (records) => verdictHold(Array.isArray(records) ? records.map((record) => ({ runId: 11, ...record })) : records, REPO);
  assert.equal(hold([{ verdict: "pass", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass-notes", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass", run: run({ conclusion: "failure" }) }, { verdict: "pass-notes", run: run() }]), null);
  for (const bad of [
    { path: ".github/workflows/other.yml" },
    { event: "pull_request" },
    { head_branch: "feature" },
    { status: "in_progress", conclusion: null },
    { conclusion: "failure" },
    { repository: { full_name: "fork/claude-code-plugins" } },
    { head_repository: { full_name: "fork/claude-code-plugins" } },
  ]) {
    assert.match(hold([{ verdict: "pass", run: run(bad) }]), /has not passed this head/, JSON.stringify(bad));
  }
  assert.match(hold([{ verdict: "fail", run: run() }]), /has not passed this head/);
  // A record of another run than the one its artifact names counts nothing.
  assert.match(hold([{ verdict: "pass", runId: 12, run: run() }]), /has not passed this head/);
  assert.match(hold([{ verdict: "pass", runId: "11", run: run() }]), /has not passed this head/);
  assert.match(hold([]), /has not passed this head/);
  assert.match(hold(null), /could not be read/);
  assert.match(verdictHold([], "not a repo"), /could not be read/);
});

// test_verify_rules_sync.py ties the resolver's path to the gate's WORKFLOW_PATH.
test("verdictHold names the verifier workflow the resolver and the gate name", () => {
  assert.equal(VERIFY_PATH, RESOLVER_VERIFY_PATH);
});

// Only the gate's full reader arms, so native merge refuses what the gate
// refuses; an event run disarms on a hold and reads no verdict.
test("only the scheduled run and a hand-started one read the verdict and arm", () => {
  assert.deepEqual([...READER_EVENTS], ["schedule", "workflow_dispatch"]);
});

test("an event run arms nothing and reads neither discussion nor verdict for an unarmed pull request", async () => {
  const { code, writes, verified, lines } = await run([pull(1)], { EVENT_NAME: "pull_request_target", EVENT_PR: "1" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
  assert.ok(lines.some((line) => /#1 left: only a scheduled or hand-started run arms it/.test(line)));
});

test("an event run still disarms an armed pull request that now holds", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [
    pull(1, { autoMergeRequest: armed, labels: labels("do-not-merge") }),
    pull(2, { autoMergeRequest: armed, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
    pull(3, { autoMergeRequest: armed }),
  ];
  for (const [number, expected] of [[1, [{ mutation: "disarm", id: "PR_1" }]], [2, [{ mutation: "disarm", id: "PR_2" }]], [3, []]]) {
    const { writes, verified } = await run(pulls, { EVENT_NAME: "pull_request_target", EVENT_PR: String(number) });
    assert.deepEqual(writes, expected, String(number));
    assert.deepEqual(verified, []);
  }
});

test("a reader that fails, prints no JSON or reports another head arms nothing and disarms", async () => {
  const dir = tempDir("enable-auto-merge-");
  const scripts = {
    exits: "import sys\nsys.stderr.write('boom\\n')\nsys.exit(1)\n",
    garbage: "print('not json')\n",
    other: `import json\nprint(json.dumps({"refusal": None, "head": "${"c".repeat(40)}"}))\n`,
    unlinked: `import json, sys\nprint(json.dumps({"refusal": None, "head": sys.argv[-1]}))\n`,
    passes: `import json, sys\nassert sys.argv[2:6] == ["--lane-link", "--lane-reviews", "--lane-queue", "--shared-listing"] and sys.argv[-6:-2] == ["--base-sha", "${"d".repeat(40)}", "--rung", "C2"], sys.argv\nprint(json.dumps({"refusal": None, "head": sys.argv[-1], "ineligible": None, "reviews": None, "queue": {"failedEjections": 0, "limit": 2, "refusal": None, "comment": None}}))\n`,
  };
  for (const [name, body] of Object.entries(scripts)) {
    writeFileSync(join(dir, `${name}.py`), body);
  }
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const [name, want] of [
    ["exits", [{ mutation: "disarm", id: "PR_2" }]],
    ["garbage", [{ mutation: "disarm", id: "PR_2" }]],
    ["other", [{ mutation: "disarm", id: "PR_2" }]],
    ["unlinked", [{ mutation: "disarm", id: "PR_2" }]],
    ["passes", [{ mutation: "arm", id: "PR_1", head: HEAD }]],
  ]) {
    const { github, writes } = world([pull(1), pull(2, { autoMergeRequest: armed })]);
    const env = { ...ENV, EVENT_NAME: "schedule", PATH: process.env.PATH, VERIFY_EVIDENCE_SCRIPT: join(dir, `${name}.py`) };
    const log = console.log;
    console.log = () => {};
    try {
      await main({ env, github, room: room() });
    } finally {
      console.log = log;
    }
    assert.deepEqual(writes(), want, name);
  }
});

// The issue link through the gate's own CLI (`evidence --lane-link`) and rule
// (babysit_merge_policy._linked_issue), GitHub's answers stubbed at gh and the
// verdict a pass at the head, so only the link decides. Expected values are
// docs/conventions/pr-pipeline/README.md "Eligibility": one closing issue, or
// one plain `Refs: #<n>` issue; two `Refs:` issues refuse; a failed read refuses;
// and an issue carrying a label naming untrusted work, in any spelling, refuses
// for a person, a label added after admission included.
test("the gate's link rule arms a Closes or one plain Refs pull request, not two Refs, a failed read or an untrusted issue", async () => {
  const dir = tempDir("enable-auto-merge-link-");
  const wrapper = join(dir, "lane_link.py");
  writeFileSync(
    wrapper,
    `import json, os, subprocess, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

PULLS = json.loads(os.environ["PULLS"])
LABELS = json.loads(os.environ["LABELS"])

def labels(n):
    names = LABELS.get(str(n), [])
    return {"totalCount": len(names), "nodes": [{"name": name} for name in names]}

def gh(args, **_):
    if args[1].endswith("/timeline?per_page=100"):
        return subprocess.CompletedProcess(args, 0, "[[]]", "")
    n = next(a for a in args if a.startswith("n="))[2:]
    def ok(data):
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": {"repository": data}}), "")
    if any("issueOrPullRequest" in a for a in args):
        node = {"__typename": "Issue", "number": int(n), "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}, "labels": labels(n)}
        return ok({"issueOrPullRequest": node})
    found = PULLS[n]
    if found.get("error"):
        return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
    nodes = [{"number": c, "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}, "labels": labels(c)} for c in found["closing"]]
    return ok({"pullRequest": {"body": found["body"], "closingIssuesReferences": {"totalCount": len(nodes), "nodes": nodes}}})

def passes(self, number, head, pr=None):
    return ve.Evidence(None, head, (ve.Verdict(head, "pass", 1),), 0)

argv = sys.argv[1:]
pr = lambda repo, number: {"number": number, "head": {"sha": argv[-1]}}
with mock.patch.object(policy, "gh_capture", gh), mock.patch.object(postmerge, "gh_capture", gh), mock.patch.object(ve.Reader, "evidence", passes), mock.patch.object(policy, "pull_request", pr), mock.patch.object(ve, "lane_risk_refusal", lambda *args, **kwargs: None), mock.patch.object(policy, "read_config_at", lambda repo, sha: policy.PipelineConfig(sha, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")), mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base), mock.patch.object(babysit_merge, "read_merge_queue", lambda repo, number: {"readError": None, "failedEjections": 0}):
    sys.exit(ve.main(argv))
`,
  );
  const body = (text) => `${text}\n\n## Summary\n\nDone.`;
  const pulls = {
    1: { body: body("Closes #11"), closing: [11] },
    2: { body: body("Refs: #12"), closing: [] },
    3: { body: body("Refs: #12\nRefs: #13"), closing: [] },
    4: { body: body("Refs: #12"), closing: [], error: true },
    5: { body: body("Refs: #12\nRefs: #13"), closing: [] },
    6: { body: body("Closes #16"), closing: [16] },
    7: { body: body("Closes #17"), closing: [17] },
    8: { body: body("Refs: #18"), closing: [] },
  };
  // Labeled after admission: 16 with the label, 17 (armed) and 18 with variants.
  const issueLabels = { 11: ["agent-ready"], 16: ["agent-ready", "work-class: untrusted-provenance"], 17: ["Work-Class: Untrusted_Provenance"], 18: ["untrusted"] };
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { github, writes, notes } = world(
    [1, 2, 3, 4, 6, 8].map((n) => pull(n, { body: pulls[n].body })).concat([5, 7].map((n) => pull(n, { body: pulls[n].body, autoMergeRequest: armed }))),
  );
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, PULLS: JSON.stringify(pulls), VERIFY_EVIDENCE_SCRIPT: wrapper, LABELS: JSON.stringify(issueLabels) };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
    { mutation: "disarm", id: "PR_5" },
    { mutation: "disarm", id: "PR_7" },
  ]);
  for (const n of [6, 7, 8]) {
    assert.ok(lines.some((line) => line.endsWith(`#${n} ${n === 7 ? "disarmed" : "left"}: pr-merge's lane does not take its issue link (untrusted-provenance)`)), lines.join("\n"));
    assert.ok(
      notes.some((note) => note.path === `${ISSUES}/${n}/labels` && note.body.labels[0] === "needs-human"),
      `#${n} is labeled for a person: ${JSON.stringify(notes)}`,
    );
  }
  assert.ok(lines.some((line) => /#3 left: pr-merge's lane does not take its issue link \(refs-issues:2\)/.test(line)), lines.join("\n"));
  assert.ok(lines.some((line) => /#4 left: pr-merge's lane does not take its issue link \(unreadable: /.test(line)), lines.join("\n"));
});

// The reader's own listing rules (babysit_verify_evidence.py main and
// Reader._current_listing), each listing from the API stubbed to one call
// (`_complete_listing`, with no base to build on) and its judgment to a pass
// that reads the listing: every candidate is allowed, so a run that lists again before an
// allow on the saved listing would page once per candidate.
test("a reader run pages the artifact listing once for all its candidates", async () => {
  const dir = tempDir("enable-auto-merge-listing-");
  const wrapper = join(dir, "shared_listing.py");
  writeFileSync(
    wrapper,
    `import json, os, subprocess, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

def gh(args, **_):
    if args[1].endswith("/timeline?per_page=100"):
        return subprocess.CompletedProcess(args, 0, "[[]]", "")
    n = next(a for a in args if a.startswith("n="))[2:]
    def ok(data):
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": {"repository": data}}), "")
    nodes = [{"number": 11, "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}, "labels": {"totalCount": 0, "nodes": []}}]
    return ok({"pullRequest": {"body": "Closes #11", "closingIssuesReferences": {"totalCount": 1, "nodes": nodes}}})

def listing(self):
    with open(os.environ["LISTINGS"], "a") as log:
        log.write("listing\\n")
    return []

def passes(self, number, head, pr=None):
    self._listing()
    return ve.Evidence(None, head, (ve.Verdict(head, "pass", 1),), 0)

argv = sys.argv[1:]
pr = lambda repo, number: {"number": number, "head": {"sha": argv[-1]}}
with mock.patch.object(policy, "gh_capture", gh), mock.patch.object(postmerge, "gh_capture", gh), mock.patch.object(ve.Reader, "_incremental", lambda self, *args: None), mock.patch.object(ve.Reader, "_complete_listing", listing), mock.patch.object(ve.Reader, "_evidence", passes), mock.patch.object(policy, "pull_request", pr), mock.patch.object(ve, "lane_risk_refusal", lambda *args, **kwargs: None), mock.patch.object(policy, "read_config_at", lambda repo, sha: policy.PipelineConfig(sha, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")), mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base), mock.patch.object(babysit_merge, "read_merge_queue", lambda repo, number: {"readError": None, "failedEjections": 0}):
    sys.exit(ve.main(argv))
`,
  );
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  for (const count of [1, 3, 5]) {
    const listings = join(dir, `listings-${count}`);
    writeFileSync(listings, "");
    const numbers = Array.from({ length: count }, (_, i) => i + 1);
    const { github, writes } = world(numbers.map((n) => pull(n, { body: "Closes #11" })));
    const env = {
      ...ENV,
      PATH: process.env.PATH,
      SCRIPTS: scripts,
      LISTINGS: listings,
      BABYSIT_VERIFY_LISTING: join(dir, `verify-listing-${count}.json`),
      VERIFY_EVIDENCE_SCRIPT: wrapper,
    };
    const log = console.log;
    console.log = () => {};
    try {
      assert.equal(await main({ env, github, room: room() }), 0);
    } finally {
      console.log = log;
    }
    assert.deepEqual(
      writes().map(({ mutation, id }) => [mutation, id]),
      numbers.map((n) => ["arm", `PR_${n}`]),
      `${count} candidates`,
    );
    assert.equal(readFileSync(listings, "utf8").split("\n").filter(Boolean).length, 1, `${count} candidates`);
  }
});

// An event run reads no link and no verdict, so it never disarms an armed
// Refs pull request on its link; the scheduled run judges it.
test("an event run leaves an armed Refs pull request armed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, verified } = await run([pull(1, { autoMergeRequest: armed, body: "Refs: #12\n\n## Summary" })], { EVENT_NAME: "pull_request_target", EVENT_PR: "1" });
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

// The gate's run-level refusals, which native auto-merge would skip
// (babysit_merge_policy.lane_room): a demotion record or a rung held off
// stops the lane, and merge.max-in-flight caps what is in flight.
test("while the gate holds its lane off, nothing is armed and armed lane pull requests are disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const refusal of ["rung-off:demotion", "rung-off:rungCap", "post-merge:failure:red-main#40"]) {
    const { writes, verified, lines } = await run(
      [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" }, autoMergeRequest: armed })],
      {},
      {},
      { ...ROOM, refusal },
    );
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], refusal);
    // A held lane reads no verdict.
    assert.deepEqual(verified, [], refusal);
    assert.ok(lines.some((line) => line.includes(`#1 left: pr-merge's gate holds its lane off (${refusal})`)), refusal);
  }
});

test("at merge.max-in-flight nothing more is armed, counting armed pull requests the queue has not taken", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  // Four in flight by the gate's count, one armed and not queued: the cap of five is reached.
  let result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5 });
  assert.deepEqual(result.writes, []);
  assert.deepEqual(result.verified, [2]);
  assert.ok(result.lines.some((line) => /#1 left: merge\.max-in-flight is 5 and 5 merges are in flight/.test(line)));
  // An armed pull request already in the queue is in the gate's count, not counted twice.
  result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5, queued: [2] });
  assert.deepEqual(result.writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  // Each arm in the run counts: three in flight of five arms two of three.
  result = await run([pull(1), pull(2), pull(3)], {}, {}, { ...ROOM, count: 3, cap: 5 });
  assert.deepEqual(
    result.writes.map(({ id }) => id),
    ["PR_1", "PR_2"],
  );
});

// Unknown holds: a room that cannot be read (no post-merge report, a failed
// read) holds as the gate's refusal does, so an armed lane pull request is
// disarmed rather than left to merge while the gate refuses.
test("a room that cannot be read arms nothing and disarms every armed lane pull request", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" }, autoMergeRequest: armed })];
  for (const lane of [{ ...ROOM, unreadable: "post-merge answer missing or unreadable" }, { refusal: null }, null]) {
    const { writes, verified, lines } = await run(pulls, {}, {}, lane);
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], JSON.stringify(lane));
    assert.deepEqual(verified, [], JSON.stringify(lane));
    assert.ok(lines.some((line) => line.includes("#2 disarmed: the lane's room could not be read")), JSON.stringify(lane));
  }
  const { github, writes } = world(pulls);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: ENV,
      github,
      verify: async ({ headRefOid: head }) => ({ ...PASSED, head }),
      room: async () => {
        throw new Error("lane-room exited 1");
      },
    });
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [{ mutation: "disarm", id: "PR_2" }]);
});

// A held room that logs only to the console leaves nothing on the run
// saying why nothing armed. One annotation and one summary
// line per run, naming the reason and every lane pull request left unarmed.
test("a held room raises one warning and one step-summary line naming why and each pull request left unarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" } }), pull(4, { isDraft: true })];
  const cases = [
    [{ ...ROOM, unreadable: "post-merge answer unverified-stale" }, "the lane's room could not be read (post-merge answer unverified-stale); left unarmed: #1, #2"],
    [{ ...ROOM, refusal: "rung-off:demotion" }, "pr-merge's gate holds its lane off (rung-off:demotion); left unarmed: #1, #2"],
  ];
  for (const [lane, expected] of cases) {
    const summary = join(tempDir("enable-auto-merge-summary-"), "summary.md");
    writeFileSync(summary, "");
    const { lines } = await run(pulls, { GITHUB_STEP_SUMMARY: summary }, {}, lane);
    assert.deepEqual(
      lines.filter((line) => line.startsWith("::warning")),
      [`::warning title=enable-auto-merge::${expected}`],
    );
    assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${expected}\n`);
  }
  // A lane with room raises neither.
  const summary = join(tempDir("enable-auto-merge-summary-"), "summary.md");
  writeFileSync(summary, "");
  const { lines, writes } = await run(pulls, { GITHUB_STEP_SUMMARY: summary });
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.deepEqual(
    lines.filter((line) => line.startsWith("::warning")),
    [],
  );
  assert.equal(readFileSync(summary, "utf8"), "");
});

// A pull request whose disarm failed, or that report-only left armed, is
// still armed: naming it "left unarmed" would say the hold was enforced when
// it was not.
test("a held room names a pull request whose disarm failed as still armed, at error level", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const summary = join(tempDir("enable-auto-merge-summary-"), "summary.md");
  writeFileSync(summary, "");
  const lane = { ...ROOM, refusal: "rung-off:demotion" };
  const { lines, code } = await run([pull(1), pull(2, { autoMergeRequest: armed })], { GITHUB_STEP_SUMMARY: summary }, { disarmError: new Error("POST /graphql failed with status 502") }, lane);
  assert.equal(code, 1);
  const why = "pr-merge's gate holds its lane off (rung-off:demotion)";
  assert.deepEqual(
    lines.filter((line) => /^::(warning|error) title=enable-auto-merge::pr-merge/.test(line)),
    [`::warning title=enable-auto-merge::${why}; left unarmed: #1`, `::error title=enable-auto-merge::${why}; still armed, its disarm failed, so the hold is not enforced: #2`],
  );
  assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${why}; left unarmed: #1\nenable-auto-merge: ${why}; still armed, its disarm failed, so the hold is not enforced: #2\n`);
});

test("a held room in report-only names the armed pull request a disarm would have turned off, not as unarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const summary = join(tempDir("enable-auto-merge-summary-"), "summary.md");
  writeFileSync(summary, "");
  const lane = { ...ROOM, unreadable: "post-merge answer missing or unreadable" };
  const { lines, writes } = await run([pull(1), pull(2, { autoMergeRequest: armed })], { GITHUB_STEP_SUMMARY: summary, REPORT_ONLY: "true" }, {}, lane);
  assert.deepEqual(writes, []);
  const expected = "the lane's room could not be read (post-merge answer missing or unreadable); left unarmed: #1; report-only, a disarm would have run: #2";
  assert.deepEqual(
    lines.filter((line) => line.startsWith("::warning") || line.startsWith("::error")),
    [`::warning title=enable-auto-merge::${expected}`],
  );
  assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${expected}\n`);
});

// An event run reads no room, so it never disarms on one.
test("an event run leaves an armed lane pull request armed whatever the room", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes } = await run([pull(2, { autoMergeRequest: armed })], { EVENT_NAME: "pull_request_target", EVENT_PR: "2" }, {}, null);
  assert.deepEqual(writes, []);
});

test("an event run reads no room", async () => {
  let asked = 0;
  const { github } = world([pull(1)]);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: { ...ENV, EVENT_NAME: "pull_request_target", EVENT_PR: "1" },
      github,
      room: async () => {
        asked += 1;
        return ROOM;
      },
    });
  } finally {
    console.log = log;
  }
  assert.equal(asked, 0);
});

test("readRoom takes only lane-room's shape", () => {
  assert.deepEqual(readRoom(ROOM), ROOM);
  for (const bad of [null, "x", { ...ROOM, cap: 0 }, { ...ROOM, count: -1 }, { ...ROOM, queued: ["3"] }, { ...ROOM, refusal: 1 }, { ...ROOM, unreadable: undefined }]) {
    assert.ok(readRoom(bad).unreadable, JSON.stringify(bad));
  }
});

test("pythonRoom passes the post-merge report, its check's commit, the rung cap as read, and the reader's token", async () => {
  const dir = tempDir("enable-auto-merge-room-");
  const script = join(dir, "room.py");
  writeFileSync(
    script,
    `import json, os, sys
print(json.dumps({"argv": sys.argv[1:], "token": os.environ.get("GH_TOKEN"), "budget": os.environ.get("API_BUDGET_TOKEN")}))
`,
  );
  const sha = "d".repeat(40);
  const env = { PATH: process.env.PATH, GITHUB_REPOSITORY: REPO, VERIFY_EVIDENCE_SCRIPT: script, POSTMERGE_RESULT: "/tmp/post-merge.json", POSTMERGE_CODE_SHA: sha, GH_TOKEN: "lane", BABYSIT_VERIFY_GH_TOKEN: "job" };
  // An empty cap is no cap, so it is passed; an unset one is not, which the gate reads as off.
  assert.deepEqual(await pythonRoom({ ...env, RUNG_CAP: "" })(), {
    argv: ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json", "--code-sha", sha, "--rung-cap", ""],
    token: "job",
    budget: "github-token",
  });
  assert.deepEqual((await pythonRoom(env)()).argv, ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json", "--code-sha", sha]);
  // No commit kept is an empty one, which reads the report again.
  const { POSTMERGE_CODE_SHA: _, ...unset } = env;
  assert.deepEqual((await pythonRoom(unset)()).argv, ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json", "--code-sha", ""]);
});

// The calls line as babysit_gh.py itself prints it, for three Actions-token
// reads (the paginated artifact listing and two run records) and one
// lane-token GraphQL read: 4 in all, 3 under GITHUB_TOKEN, 1 paginated.
const BABYSIT_SCRIPTS = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
function producedCallsLine() {
  const done = spawnSync(
    "python3",
    [
      "-c",
      `import sys
sys.path.insert(0, sys.argv[1])
import babysit_gh as g
job = {"GH_TOKEN": "job"}
for args, env in (
    (["api", "repos/o/r/actions/artifacts?per_page=100", "--paginate", "--slurp"], job),
    (["api", "repos/o/r/actions/runs/1"], job),
    (["api", "repos/o/r/actions/runs/2"], job),
    (["api", "graphql", "-f", "query=q"], None),
):
    kind = g.gh_call_kind(args, env)
    g._gh_call_counts[kind] = g._gh_call_counts.get(kind, 0) + 1
print(g.gh_call_summary())
g.reset_gh_call_counts()`,
      BABYSIT_SCRIPTS,
    ],
    { encoding: "utf8" },
  );
  assert.equal(done.status, 0, done.stderr);
  return done.stdout.trim();
}

test("ghCalls reads babysit_gh.py's calls line: in all, under GITHUB_TOKEN, and paginated", () => {
  const line = producedCallsLine();
  assert.deepEqual(ghCalls(`warning: something\n${line}\n`), { total: 4, githubToken: 3, paginated: 1 });
  assert.equal(ghCalls("no calls line\n"), null);
  assert.equal(ghCalls("babysit-gh-calls {not json\n"), null);
  assert.equal(ghCallsLine("babysit-gh-calls {not json\n"), null);
  assert.equal(ghCallsLine("no calls line\n"), null);
  assert.equal(costLine({ number: 7, calls: { total: 4, githubToken: 3, paginated: 1 }, ms: 1500 }), "#7 calls=4 github-token=3 paginated=1 ms=1500");
  assert.equal(costLine({ number: 7, calls: null, ms: 20 }), "#7 calls=unknown ms=20");
});

// Two artifact reads that missed the live count, as
// babysit_verify_evidence.py prints them before falling back to the full listing.
const MISSES = [
  'babysit-listing-miss {"base_age_seconds": 40, "fresh": 3, "kept": 95, "listed": 98, "pages": 1, "stage": "incremental", "total_count": 100}',
  'babysit-listing-miss {"base_age_seconds": 52, "fresh": 104, "kept": 0, "listed": 104, "pages": 2, "stage": "top-up", "total_count": 101}',
];

test("pythonVerify logs each read's calls and time, keeps them, and names the error line, not the calls or miss line, on a failure", async () => {
  const line = producedCallsLine();
  const answers = [
    { status: 0, stdout: `${JSON.stringify(PASSED)}\n`, stderr: `${line}\n` },
    { status: 1, stdout: "", stderr: `Traceback\nRuntimeError: listing 502\n${MISSES[0]}\n${line}\n` },
  ];
  const spawn = () => answers.shift();
  let at = 1000;
  const clock = () => (at += 250);
  const verify = pythonVerify({ GITHUB_REPOSITORY: REPO }, { spawn, clock });
  const lines = [];
  const log = console.log;
  console.log = (text) => lines.push(text);
  try {
    assert.deepEqual(await verify(pull(1)), PASSED);
    await assert.rejects(verify(pull(2)), /exited 1: RuntimeError: listing 502$/);
  } finally {
    console.log = log;
  }
  // The reader's per-endpoint calls line reaches the log after each cost
  // line, in the shape the merge job's tee logs, as one line of JSON.
  const logged = `babysit-gh-calls ${JSON.stringify(JSON.parse(line.slice("babysit-gh-calls ".length)))}`;
  assert.deepEqual(lines, ["enable-auto-merge: #1 calls=4 github-token=3 paginated=1 ms=250", logged, "enable-auto-merge: #2 calls=4 github-token=3 paginated=1 ms=250", logged, MISSES[0]]);
  assert.deepEqual(JSON.parse(logged.slice("babysit-gh-calls ".length)).calls, JSON.parse(line.slice("babysit-gh-calls ".length)).calls);
  assert.deepEqual(
    verify.costs.map(({ number, ms }) => [number, ms]),
    [
      [1, 250],
      [2, 250],
    ],
  );
});

test("listingMissLines keeps each babysit-listing-miss line in order and nothing else", () => {
  assert.deepEqual(listingMissLines(`warning: something\r\n${MISSES[0]}\r\nbabysit-gh-calls {}\n${MISSES[1]}\n`), MISSES);
  assert.deepEqual(listingMissLines("warning: something\nbabysit-gh-calls {}\n"), []);
  assert.deepEqual(listingMissLines(undefined), []);
});

test("pythonVerify logs the reader's listing misses beside its calls line on a refusal that exits 0", async () => {
  const line = producedCallsLine();
  const refusal = { refusal: "verify:unreadable", head: HEAD };
  const spawn = () => ({ status: 0, stdout: `${JSON.stringify(refusal)}\n`, stderr: `${MISSES[0]}\nwarning: something\n${MISSES[1]}\n${line}\n` });
  const verify = pythonVerify({ GITHUB_REPOSITORY: REPO }, { spawn, clock: () => 0 });
  const lines = [];
  const log = console.log;
  console.log = (text) => lines.push(text);
  try {
    assert.deepEqual(await verify(pull(1)), refusal);
  } finally {
    console.log = log;
  }
  const logged = `babysit-gh-calls ${JSON.stringify(JSON.parse(line.slice("babysit-gh-calls ".length)))}`;
  assert.deepEqual(lines, ["enable-auto-merge: #1 calls=4 github-token=3 paginated=1 ms=0", logged, ...MISSES]);
});

test("the step summary carries each verifier read's cost even when the run raised nothing", async () => {
  const summary = join(tempDir("enable-auto-merge-summary-"), "summary.md");
  writeFileSync(summary, "");
  const { github, writes } = world([pull(1)]);
  const verify = async ({ headRefOid: head }) => ({ ...PASSED, head });
  verify.costs = [{ number: 1, calls: { total: 9, githubToken: 7, paginated: 1 }, ms: 46800 }];
  const log = console.log;
  console.log = () => {};
  try {
    assert.equal(await main({ env: { ...ENV, GITHUB_STEP_SUMMARY: summary }, github, verify, room: room(), sleep: async () => {} }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.equal(readFileSync(summary, "utf8"), "enable-auto-merge: #1 calls=9 github-token=7 paginated=1 ms=46800\n");
});

test("pythonRoom gives the lane-room read its own 8 minute timeout and reads a kill as unreadable", async () => {
  const seen = [];
  const killed = (_cmd, _args, options) => {
    seen.push(options.timeout);
    return { status: null, signal: "SIGTERM", stdout: "", stderr: "" };
  };
  await assert.rejects(pythonRoom({ GITHUB_REPOSITORY: REPO }, killed)(), /lane-room exited SIGTERM/);
  assert.deepEqual(seen, [8 * 60_000]);
  assert.equal(LANE_ROOM_TIMEOUT_MS, 8 * 60_000);
  assert.equal(VERIFY_TIMEOUT_MS, 4 * 60_000);
});

// A reader child that exits 75 stopped on a GitHub rate limit
// (babysit_gh.RATE_LIMIT_EXIT); a later child would call GitHub again before
// the reset, so the run sends nothing more and fails red naming the pool.

// The gate's real exhausted-pool exit: the guard's ::error, then its call count.
function stoppedReader(dir) {
  const script = join(dir, "stopped.py");
  writeFileSync(
    script,
    `import sys
sys.path.insert(0, ${JSON.stringify(BABYSIT_SCRIPTS)})
import babysit_gh as gh
raise gh.RateLimitExhausted("core", 4102444800, "x-ratelimit-reset reset, HTTP 403")
`,
  );
  return script;
}

test("a gate reader stopped on a rate limit ends the run: no later pull request is read", async () => {
  const dir = tempDir("enable-auto-merge-stopped-");
  const env = { ...ENV, PATH: process.env.PATH, RUNNER_TEMP: "", VERIFY_EVIDENCE_SCRIPT: stoppedReader(dir) };
  const pulls = [pull(1), pull(2)];
  const { github, writes, calls, notes } = world(pulls);
  const spawned = [];
  let callsAtSpawn = null;
  const spawn = (...args) => {
    spawned.push(args[1].at(-2));
    callsAtSpawn = calls.length;
    return spawnSync(...args);
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  let code;
  try {
    code = await main({ env, github, verify: pythonVerify(env, { spawn }), room: room(), sleep: async () => {} });
  } finally {
    console.log = log;
  }
  assert.equal(code, 1);
  assert.deepEqual(spawned, ["1"]);
  // Nothing after the stopped child: no detail read, verify or arm for #2.
  assert.equal(calls.length, callsAtSpawn);
  assert.deepEqual(writes(), []);
  assert.deepEqual(notes, []);
  // The stopped read's cost is still logged.
  assert.ok(lines.some((line) => /^enable-auto-merge: #1 calls=/.test(String(line))), lines.join("\n"));
  const errors = lines.filter((line) => String(line).startsWith("::error title=GitHub rate limit::"));
  assert.equal(errors.length, 1, lines.join("\n"));
  assert.match(errors[0], /the core pool is exhausted/);
  assert.match(errors[0], /2100-01-01T00:00:00Z/);
});

// A lane-room reader stopped on a rate limit: its child wrote `pool` to the
// job's stop file before exiting 75.
async function roomStoppedOn(pool, pulls) {
  const dir = tempDir("enable-auto-merge-room-stop-");
  const stopFile = join(dir, "stop");
  const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile });
  const stderr =
    `::error title=GitHub rate limit::the ${pool} pool is exhausted (x-ratelimit-reset reset, HTTP 403); no GitHub call is sent before 2100-01-01T00:00:00Z\n` +
    'babysit-gh-calls {"total": 1}';
  const stopped = () => {
    writeFileSync(stopFile, `${pool} 4102444800\n`);
    return { status: 75, signal: null, stdout: "", stderr };
  };
  const { github, writes, calls, notes, verified } = world(pulls);
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  let code;
  try {
    code = await main({ env: ENV, github, verify: world([]).verify, room: pythonRoom({ GITHUB_REPOSITORY: REPO }, stopped), sleep: async () => {}, latch });
  } finally {
    console.log = log;
    rmSync(dir, { recursive: true, force: true });
  }
  return { code, writes: writes(), calls, notes, verified, lines };
}

test("a lane-room reader stopped on the REST pool disarms each armed lanes pull request and arms nothing", async () => {
  const armed = pull(1, { autoMergeRequest: { enabledAt: "2026-10-23T10:00:00Z" } });
  const { code, writes, notes, verified, lines } = await roomStoppedOn("core", [armed, pull(2)]);
  assert.equal(code, 1);
  // An unread room holds as a refusal does: #1 is disarmed, #2 not armed.
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
  assert.deepEqual(notes, []);
  assert.deepEqual(verified, []);
  const errors = lines.filter((line) => String(line).startsWith("::error title=GitHub rate limit::"));
  assert.equal(errors.length, 1, lines.join("\n"));
  assert.match(errors[0], /the core pool is exhausted/);
  assert.match(errors[0], /each armed lanes App pull request is disarmed/);
});

test("a lane-room reader stopped on the GraphQL pool sends no disarm and fails naming each armed lanes pull request", async () => {
  const armed = pull(1, { autoMergeRequest: { enabledAt: "2026-10-23T10:00:00Z" } });
  const { code, writes, calls, notes, lines } = await roomStoppedOn("graphql", [armed, pull(2)]);
  assert.equal(code, 1);
  assert.deepEqual(writes, []);
  // Only the listing was sent.
  assert.deepEqual(
    calls.map(({ body }) => body?.query === PULLS_QUERY),
    [true],
  );
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => /^::error title=enable-auto-merge::#1 disarm not sent: GitHub's GraphQL rate limit is stopped until 2100-01-01T00:00:00/.test(String(line))), lines.join("\n"));
  assert.ok(lines.some((line) => /^::error title=enable-auto-merge::.*still armed, its disarm failed, so the hold is not enforced: #1$/.test(String(line))), lines.join("\n"));
});

test("a verifier read stopped on a rate limit disarms the armed lanes pull requests after it and arms nothing", async () => {
  const dir = tempDir("enable-auto-merge-verify-stop-");
  const stopFile = join(dir, "stop");
  const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile });
  const armed = { autoMergeRequest: { enabledAt: "2026-10-23T10:00:00Z" } };
  const { github, writes, notes } = world([pull(1), pull(2, armed), pull(3, armed)]);
  const asked = [];
  const verify = async ({ number }) => {
    asked.push(number);
    writeFileSync(stopFile, "core 4102444800\n");
    throw new ReaderRateLimited(`#${number}'s verifier read`, "");
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  let code;
  try {
    code = await main({ env: ENV, github, verify, room: room(), sleep: async () => {}, latch });
  } finally {
    console.log = log;
    rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(code, 1);
  // One verifier read; every armed lanes pull request is disarmed, none armed.
  assert.equal(asked.length, 1);
  assert.deepEqual(
    writes().sort((a, b) => a.id.localeCompare(b.id)),
    [
      { mutation: "disarm", id: "PR_2" },
      { mutation: "disarm", id: "PR_3" },
    ],
  );
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => String(line).startsWith("::error title=GitHub rate limit::")), lines.join("\n"));
});

// The gate holds on the security lane's open CRITICAL findings
// (babysit_risk LANES, security-finding) and on a review not bound to the
// head, whether or not the lane applied its hold label.
test("a review-lane hold the gate reads arms nothing and disarms an armed pull request", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const held = { refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" };
  const { writes, lines } = await run([
    pull(1, { verdict: held }),
    pull(2, { autoMergeRequest: armed, verdict: { ...held, reviews: "evidence-unbound:claude-security-review: marker-missing" } }),
    pull(3, { verdict: { refusal: null, head: HEAD, ineligible: null } }),
    pull(4),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_4", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.includes("#1 left: pr-merge's gate holds it on its risk score (security-finding: 1 open)")));
  assert.ok(lines.some((line) => line.includes("#3 left: its risk score could not be read")));
});

// The gate's whole risk score through its own CLI and scorer
// (babysit_risk.score, holding), the reads stubbed: only a regular file that
// stays regular may rate below HIGH, so a symlink or a submodule pointer a
// lane pull request adds holds, and a plain documentation change arms.
test("a lane pull request adding a symlink or a submodule pointer is not armed, or is disarmed; a doc change arms", async () => {
  const dir = tempDir("enable-auto-merge-risk-");
  const wrapper = join(dir, "risk.py");
  writeFileSync(
    wrapper,
    `import json, os, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge
import babysit_merge_policy as policy
import babysit_verify_evidence as ve
from babysit_risk import ChangedFile, LaneEvidence

KINDS = json.loads(os.environ["KINDS"])
DOC = ChangedFile("docs/guide.md", None, "modified", 1, 1, True, "100644", "100644", patch="@@ -1 +1 @@\\n-old\\n+new")
EXTRA = {
    "doc": (),
    "symlink": (ChangedFile("docs/link", None, "added", 1, 0, True, "120000", "000000"),),
    "submodule": (ChangedFile("vendor/lib", None, "modified", 1, 1, False, "160000", "160000"),),
}
number = int(sys.argv[-2])
pr = {"number": number, "head": {"sha": sys.argv[-1]}, "base": {"sha": "d" * 40, "repo": {"private": False}}}
lanes = (LaneEvidence("claude-review", True, None, 0), LaneEvidence("claude-security-review", True, None, 0, False, 0))
config = policy.PipelineConfig("c" * 40, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")
with mock.patch.object(ve.Reader, "link_refusal", lambda self, n: None), \\
    mock.patch.object(ve.Reader, "evidence", lambda self, n, h, pr=None: ve.Evidence(None, h, (), 0)), \\
    mock.patch.object(policy, "read_config_at", lambda repo, sha: config), \\
    mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base), \\
    mock.patch.object(policy, "pull_request", lambda repo, n: pr), \\
    mock.patch.object(policy, "changed_files", lambda repo, p: ((DOC, *EXTRA[KINDS[str(number)]]), True)), \\
    mock.patch.object(policy, "with_contents", lambda repo, p, f: f), \\
    mock.patch.object(policy, "pulumi_dirs_at", lambda repo, p: ()), \\
    mock.patch.object(policy, "permission_reader", lambda repo: (lambda login: None)), \\
    mock.patch.object(babysit_merge, "_lane_evidence", lambda *args: (lanes, [])), \\
    mock.patch.object(babysit_merge, "read_merge_queue", lambda repo, n: {"readError": None, "failedEjections": 0}):
    sys.exit(ve.main(sys.argv[1:]))
`,
  );
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const kinds = { 1: "doc", 2: "symlink", 3: "submodule" };
  const { github, writes } = world([pull(1), pull(2), pull(3, { autoMergeRequest: armed })]);
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, KINDS: JSON.stringify(kinds), VERIFY_EVIDENCE_SCRIPT: wrapper };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_3" },
  ]);
  assert.ok(lines.some((line) => /#2 left: pr-merge's gate holds it on its risk score \(.*docs\/link/.test(line)), lines.join("\n"));
  assert.ok(lines.some((line) => /#3 disarmed: pr-merge's gate holds it on its risk score \(.*vendor\/lib/.test(line)), lines.join("\n"));
});

// The cap through the gate's own CLI: the count from the queue's timeline
// (babysit_merge._failed_ejections, stubbed at read_merge_queue) and the limit
// from the config (merge.max-queue-ejections, default 2), so only Python
// holds either. One removal arms; two, or an unread count, do not.
test("the gate's CLI holds a head the merge queue removed merge.max-queue-ejections times, and an unread count", async () => {
  const dir = tempDir("enable-auto-merge-queue-");
  const wrapper = join(dir, "queue.py");
  writeFileSync(
    wrapper,
    `import json, os, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge
import babysit_merge_policy as policy
import babysit_verify_evidence as ve

COUNTS = json.loads(os.environ["COUNTS"])
number = int(sys.argv[-2])
pr = {"number": number, "head": {"sha": sys.argv[-1]}}
config = policy.PipelineConfig("c" * 40, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")
with mock.patch.object(ve.Reader, "link_refusal", lambda self, n: None), \\
    mock.patch.object(ve.Reader, "evidence", lambda self, n, h, pr=None: ve.Evidence(None, h, (), 0)), \\
    mock.patch.object(policy, "read_config_at", lambda repo, sha: config), \\
    mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base), \\
    mock.patch.object(policy, "pull_request", lambda repo, n: pr), \\
    mock.patch.object(ve, "lane_risk_refusal", lambda *args, **kwargs: None), \\
    mock.patch.object(babysit_merge, "read_merge_queue", lambda repo, n: {"readError": None, "failedEjections": COUNTS[str(n)]}), \\
    mock.patch.object(babysit_merge, "_failed_merge_group_runs", lambda repo, branch, n: []):
    sys.exit(ve.main(sys.argv[1:]))
`,
  );
  const { github, writes, notes } = world([pull(1), pull(2), pull(3)]);
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, COUNTS: JSON.stringify({ 1: 1, 2: 2, 3: null }), VERIFY_EVIDENCE_SCRIPT: wrapper };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.ok(lines.includes(`enable-auto-merge: #2 left: pr-merge's gate would not enqueue it again (${EJECTED_REFUSAL})`), lines.join("\n"));
  assert.ok(lines.includes("enable-auto-merge: #3 left: pr-merge's gate would not enqueue it again (the merge queue's removals of this head are unreadable)"), lines.join("\n"));
  assert.deepEqual(
    notes.map(({ path, body }) => [path, body.body.split("\n", 1)[0]]),
    [[`${ISSUES}/2/comments`, "<!-- babysit-merge-queue-ejections -->"]],
  );
});

// The verifier-read cache (babysit_verify_evidence.py --answers-*): a kept
// answer stands only for a refusal, so it can delay an arm but never cause
// one, and an armed pull request is always read in full.
const CACHED_ALLOW = { ...PASSED, cached: true };
const CACHED_MISSING = { ...MISSING, cached: true };

test("decide never arms on a kept answer, and a kept refusal on an armed pull request disarms", () => {
  const opts = { bot: "melodic-automation-lanes", humanGated: "needs-human", holdPaths: [] };
  const read = { ...detail(), files: ["plugins/work-items/README.md"], filesCapped: false, costDecision: null };
  assert.equal(decide(pull(1), opts, { ...read, verify: PASSED }).action, "arm");
  assert.equal(decide(pull(1), opts, { ...read, verify: CACHED_ALLOW }).action, "verify");
  const armed = pull(1, { autoMergeRequest: { enabledAt: "2026-10-23T09:00:00Z" } });
  assert.equal(decide(armed, opts, { ...read, verify: CACHED_ALLOW }).action, "verify");
  assert.deepEqual(decide(armed, opts, { ...read, verify: CACHED_MISSING }), { action: "disarm", reason: MISSING_REASON, clears: "lane" });
  assert.deepEqual(decide(pull(1), opts, { ...read, verify: CACHED_MISSING }), { action: "none", reason: MISSING_REASON, clears: "lane" });
});

test("a kept answer that holds nothing is read again in full: a refusal then sends no arm and no disarm, an allow arms once", async () => {
  const seen = [];
  const refusedFresh = pull(1, { verdict: (options) => (seen.push(options), options.fresh ? MISSING : CACHED_ALLOW) });
  const refused = await run([refusedFresh]);
  assert.deepEqual(seen, [{}, { fresh: true }]);
  assert.deepEqual(refused.writes, []);
  const allowed = await run([pull(2, { verdict: (options) => (options.fresh ? PASSED : CACHED_ALLOW) })]);
  assert.deepEqual(allowed.writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
  // A reader that answered kept even when asked for a fresh read sends nothing.
  const stuck = await run([pull(3, { verdict: () => CACHED_ALLOW }), pull(4, { verdict: () => CACHED_ALLOW, autoMergeRequest: { enabledAt: "2026-10-23T09:00:00Z" } })]);
  assert.deepEqual(stuck.writes, []);
});

test("a kept refusal on an armed pull request disarms it", async () => {
  const { writes } = await run([pull(1, { verdict: CACHED_MISSING, autoMergeRequest: { enabledAt: "2026-10-23T09:00:00Z" } })]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
});

test("a kept refusal writes no label back; a changed reason is still written", async () => {
  const reason = "pr-merge's gate refuses its verifier verdict (verify:untrusted-spec)";
  const untrusted = { refusal: "verify:untrusted-spec", needsHuman: true, head: HEAD, ineligible: null };
  const standing = (verdict) => pull(2, { verdict, discussion: { comments: [lanesSaid(personNote(reason))] } });
  assert.deepEqual((await run([standing(untrusted)])).notes, [{ method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } }]);
  const kept = await run([standing({ ...untrusted, cached: true })]);
  assert.deepEqual(kept.notes, []);
  assert.equal(kept.calls.filter(({ body }) => body?.query === UNLABELED_QUERY).length, 0);
  const moved = await run([pull(1, { verdict: CACHED_MISSING, discussion: { comments: [lanesSaid(laneNote("an earlier reason"))] } })]);
  assert.deepEqual(moved.notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: laneNote(MISSING_REASON) } }]);
});

test("past the verify budget, serve answers an unarmed pull request only from a kept refusal; shadow reads nothing more", async () => {
  const at = Date.parse("2026-10-23T11:00:00Z");
  const late = () => {
    let calls = 0;
    return () => (calls++ === 0 ? at : at + VERIFY_BUDGET_MS + 1);
  };
  const seen = [];
  const answer = (verdict) => (options) => (seen.push(options), verdict);
  const pulls = () => [pull(1, { verdict: answer(CACHED_MISSING) }), pull(2, { verdict: answer({ head: HEAD, cached: false }) })];
  const files = { VERIFY_ANSWERS_IN: "/tmp/in.json", VERIFY_ANSWERS_OUT: "/tmp/out.json" };
  const served = await run(pulls(), { VERIFY_CACHE: "serve", ...files }, { now: late() });
  assert.deepEqual(seen, [{ cacheOnly: true }, { cacheOnly: true }]);
  assert.deepEqual(served.writes, []);
  assert.ok(served.lines.includes(`enable-auto-merge: #1 left: ${MISSING_REASON}`), served.lines.join("\n"));
  assert.ok(served.lines.includes("enable-auto-merge: #2 left: no time left in this run to read its verifier verdict"), served.lines.join("\n"));
  // Past the window, nothing more is read.
  seen.length = 0;
  let calls = 0;
  const past = () => (calls++ === 0 ? at : at + VERIFY_BUDGET_MS + CACHE_ONLY_WINDOW_MS + 1);
  assert.deepEqual((await run(pulls(), { VERIFY_CACHE: "serve", ...files }, { now: past })).verified, []);
  seen.length = 0;
  const shadow = await run(pulls(), files, { now: late() });
  assert.deepEqual(seen, []);
  assert.deepEqual(shadow.verified, []);
});

// Without a file to keep answers in, the reader is never given
// --answers-only, so a read past the budget would be a full one, which can
// run past the step's timeout.
test("past the verify budget, serve with no answers file reads nothing", async () => {
  const at = Date.parse("2026-10-23T11:00:00Z");
  let calls = 0;
  const late = () => (calls++ === 0 ? at : at + VERIFY_BUDGET_MS + 1);
  const seen = [];
  const answer = (verdict) => (options) => (seen.push(options), verdict);
  const pulls = [pull(1, { verdict: answer(CACHED_MISSING) })];
  for (const env of [{ VERIFY_CACHE: "serve" }, { VERIFY_CACHE: "serve", VERIFY_ANSWERS_IN: "/tmp/in.json" }]) {
    calls = 0;
    const { lines, writes } = await run(pulls, env, { now: late });
    assert.deepEqual(seen, [], JSON.stringify(env));
    assert.deepEqual(writes, []);
    assert.ok(lines.includes("enable-auto-merge: #1 left: no time left in this run to read its verifier verdict"), lines.join("\n"));
  }
});

test("a cache-only read without an answers file never spawns a full read", async () => {
  const spawned = [];
  const spawn = (_cmd, args) => (spawned.push(args), { status: 0, stdout: `${JSON.stringify(MISSING)}\n`, stderr: "" });
  const verify = pythonVerify({ ...ENV, VERIFY_CACHE: "serve" }, { spawn, clock: () => 0 });
  const log = console.log;
  console.log = () => {};
  try {
    assert.deepEqual(await verify(pull(1), undefined, { cacheOnly: true }), { head: HEAD, cached: false });
  } finally {
    console.log = log;
  }
  assert.deepEqual(spawned, []);
});

test("costLine shows whether a kept answer served the read, and cacheLine the shadow comparison", () => {
  assert.equal(costLine({ number: 7, calls: { total: 1, githubToken: 0, paginated: 0 }, ms: 900, cached: true }), "#7 calls=1 github-token=0 paginated=0 ms=900 cached=1");
  assert.equal(costLine({ number: 7, calls: null, ms: 20, cached: false }), "#7 calls=unknown ms=20 cached=0");
  assert.equal(cacheLine(7, { mode: "shadow", key: "hit", stored: "verify:missing", fresh: "verify:fail", agree: "no" }), "verify-cache shadow: #7 key=hit stored=verify:missing fresh=verify:fail agree=no");
  assert.equal(cacheLine(7, { mode: "shadow", key: "miss", stored: "none", fresh: "allow", agree: "n/a" }), "verify-cache shadow: #7 key=miss stored=none fresh=allow agree=n/a");
  assert.equal(cacheLine(7, { mode: "shadow\n::error::x", key: "hit" }), "verify-cache ?: #7 key=hit stored=? fresh=? agree=?");
  assert.equal(cacheLine(7, undefined), null);
});

test("a read the cache failed on logs cache=error, in each mode", async () => {
  assert.equal(cacheLine(7, { mode: "shadow", error: true }), "verify-cache shadow: #7 cache=error");
  assert.equal(cacheLine(7, { mode: "serve", error: true }), "verify-cache serve: #7 cache=error");
  // The reader's answer reaches the log through pythonVerify.
  const files = { VERIFY_ANSWERS_IN: "/tmp/in.json", VERIFY_ANSWERS_OUT: "/tmp/out.json" };
  for (const mode of ["shadow", "serve"]) {
    const answer = { ...MISSING, head: HEAD, cache: { mode, error: true } };
    const spawn = () => ({ status: 0, stdout: `${JSON.stringify(answer)}\n`, stderr: "" });
    const verify = pythonVerify({ ...ENV, ...files, VERIFY_CACHE: mode }, { spawn, clock: () => 0 });
    const lines = [];
    const log = console.log;
    console.log = (line) => lines.push(line);
    try {
      await verify(pull(1));
    } finally {
      console.log = log;
    }
    assert.ok(lines.includes(`enable-auto-merge: verify-cache ${mode}: #1 cache=error`), lines.join("\n"));
  }
});

// A stand-in for the reader process: the same answer whatever the flags, with
// the shadow comparison added when it is given answers files.
function shadowReader(answers) {
  const spawned = [];
  const spawn = (_cmd, args) => {
    spawned.push(args);
    const number = Number(args.at(-2));
    const report = { ...answers[number], head: args.at(-1) };
    const cache = args.includes("--answers-out") ? { cache: { mode: args[args.indexOf("--answers-mode") + 1], key: "hit", stored: "verify:missing", fresh: "allow", agree: "no" } } : {};
    return { status: 0, stdout: `${JSON.stringify({ ...report, ...cache })}\n`, stderr: "" };
  };
  return { spawn, spawned };
}

test("shadow never changes a decision: the same arms, disarms and notes with and without answers files, and serve is never asked for", async () => {
  const armed = { autoMergeRequest: { enabledAt: "2026-10-23T09:00:00Z" } };
  const answers = { 1: PASSED, 2: MISSING, 3: MISSING, 4: PASSED, 5: { ...PASSED, reviews: "MED: a review not bound to the head", reviewsPerson: false } };
  const pulls = () => [pull(1), pull(2), pull(3, armed), pull(4, armed), pull(5, { discussion: { comments: [lanesSaid(laneNote("an earlier reason"))] } })];
  const outcome = async (env) => {
    const { github, writes, notes } = world(pulls());
    const { spawn, spawned } = shadowReader(answers);
    const log = console.log;
    const lines = [];
    console.log = (line) => lines.push(line);
    try {
      assert.equal(await main({ env: { ...ENV, ...env }, github, verify: pythonVerify({ ...ENV, ...env }, { spawn }), room: room(), sleep: async () => {}, now: () => Date.parse(NOW) }), 0);
    } finally {
      console.log = log;
    }
    return { writes: writes(), notes, spawned, lines };
  };
  const files = { VERIFY_ANSWERS_IN: "/tmp/in.json", VERIFY_ANSWERS_OUT: "/tmp/out.json" };
  const without = await outcome({});
  assert.deepEqual(without.writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_3" },
  ]);
  for (const env of [files, { ...files, VERIFY_CACHE: "shadow" }, { ...files, VERIFY_CACHE: "Serve" }, { ...files, VERIFY_CACHE: "" }]) {
    const shadow = await outcome(env);
    assert.deepEqual(shadow.writes, without.writes, JSON.stringify(env));
    assert.deepEqual(shadow.notes, without.notes, JSON.stringify(env));
    assert.equal(shadow.spawned.length, 5);
    for (const args of shadow.spawned) {
      assert.equal(args[args.indexOf("--answers-mode") + 1], "shadow");
      assert.ok(!args.includes("--answers-only"));
    }
    assert.ok(shadow.lines.includes("enable-auto-merge: verify-cache shadow: #2 key=hit stored=verify:missing fresh=allow agree=no"), shadow.lines.join("\n"));
  }
  assert.ok(without.spawned.every((args) => !args.some((arg) => arg.startsWith("--answers"))));
});

test("serve asks for a kept answer only for an unarmed pull request, and never on a fresh read", async () => {
  const env = { ...ENV, VERIFY_CACHE: "serve", VERIFY_ANSWERS_IN: "/tmp/in.json", VERIFY_ANSWERS_OUT: "/tmp/out.json" };
  const reader = shadowReader({ 1: MISSING, 2: MISSING });
  const { spawned } = reader;
  const timeouts = [];
  const deadlines = [];
  const spawn = (cmd, args, options) => (timeouts.push(options.timeout), deadlines.push([options.env.BABYSIT_VERIFY_DEADLINE_SECONDS, options.env.BABYSIT_VERIFY_CALLER]), reader.spawn(cmd, args));
  const verify = pythonVerify(env, { spawn, clock: () => 0 });
  const log = console.log;
  console.log = () => {};
  try {
    await verify(pull(1));
    await verify(pull(2, { autoMergeRequest: { enabledAt: "2026-10-23T09:00:00Z" } }));
    await verify(pull(1), undefined, { fresh: true });
    await verify(pull(1), undefined, { cacheOnly: true });
  } finally {
    console.log = log;
  }
  const mode = (args) => args[args.indexOf("--answers-mode") + 1];
  assert.deepEqual(spawned.map(mode), ["serve", "shadow", "shadow", "serve"]);
  assert.deepEqual(spawned.map((args) => args.includes("--answers-only")), [false, false, false, true]);
  assert.deepEqual(timeouts, [VERIFY_TIMEOUT_MS, VERIFY_TIMEOUT_MS, VERIFY_TIMEOUT_MS, CACHE_ONLY_TIMEOUT_MS]);
  // babysit_verify_evidence.py DEADLINE_ENV and CALLER_ENV: each read is told
  // the limit it is killed at (240 s, or 30 s for a kept-answer lookup).
  const caller = "enable-auto-merge.mjs";
  assert.deepEqual(deadlines, [["240", caller], ["240", caller], ["240", caller], ["30", caller]]);
  assert.deepEqual(spawned[0].slice(spawned[0].indexOf("--answers-out"), spawned[0].indexOf("--answers-out") + 6), ["--answers-out", "/tmp/out.json", "--answers-mode", "serve", "--answers-in", "/tmp/in.json"]);
});

// ci-status's merge-queue run fails a head whose newest pr-unblock/* status by
// github-actions[bot] is failure or error (pr-require-checks.yml "Fail a head a
// pr-unblock lane stopped"), so enable-auto-merge never queues one.
const BOT = { login: "github-actions[bot]" };
const unblock = (context, state, creator = BOT, description = "stopped") => ({ context, state, creator, description });

test("unblockStops keeps each pr-unblock context's newest github-actions status that fails", () => {
  assert.deepEqual(
    unblockStops([
      unblock("pr-unblock/fix-ci", "failure", BOT, "fix-ci\tstopped"),
      unblock("pr-unblock/fix-ci", "success"),
      unblock("pr-unblock/address-feedback", "success"),
      unblock("pr-unblock/address-feedback", "failure"),
      unblock("pr-unblock/resolve-conflicts", "error"),
      unblock("pr-unblock/fix-docs", "failure", { login: "someone" }),
      unblock("ci-lanes", "failure"),
    ]),
    [
      { context: "pr-unblock/fix-ci", state: "failure", description: "fix-ci stopped" },
      { context: "pr-unblock/resolve-conflicts", state: "error", description: "stopped" },
    ],
  );
  assert.throws(() => unblockStops(null), /not a list/);
});

test("a head a pr-unblock lane stopped is not queued and is named in the summary; an unheld one still arms", async () => {
  const summary = join(tempDir("enable-auto-merge-unblock-"), "summary.md");
  writeFileSync(summary, "");
  const stopped = pull(1, { verdict: PASSED, statuses: [unblock("pr-unblock/fix-ci", "failure")] });
  const { writes, lines } = await run([stopped], { GITHUB_STEP_SUMMARY: summary });
  assert.deepEqual(writes, []);
  const reason = "a pr-unblock lane stopped its head (pr-unblock/fix-ci is failure), which ci-status fails in the merge queue";
  assert.ok(lines.some((line) => String(line).includes(reason)), lines.join("\n"));
  assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: #1 not queued: ${reason}\n`);

  const cleared = pull(1, { verdict: PASSED, statuses: [unblock("pr-unblock/fix-ci", "success"), unblock("pr-unblock/fix-ci", "failure")] });
  assert.equal((await run([cleared])).writes[0]?.mutation, "arm");
  assert.equal((await run([pull(1, { verdict: PASSED })])).writes[0]?.mutation, "arm");
});

// The lanes App holds no commit-statuses permission, so the head's statuses
// are read on the job token (statuses: read): a lanes token that cannot read
// them stops nothing when the job token can.
test("the head's statuses are read on the job token, not the lanes App token", async () => {
  const jobToken = (github) => async (method, path, ...rest) => (path.includes("/statuses?") ? [] : github(method, path, ...rest));
  const { writes } = await run([pull(1, { verdict: PASSED, statuses: "error" })], {}, { jobToken });
  assert.equal(writes[0]?.mutation, "arm");
});

test("a head whose statuses do not read is not queued, and an armed one is disarmed", async () => {
  assert.deepEqual((await run([pull(1, { verdict: PASSED, statuses: "error" })])).writes, []);
  const armed = pull(1, { verdict: PASSED, statuses: "error", autoMergeRequest: { enabledAt: NOW } });
  assert.equal((await run([armed])).writes[0]?.mutation, "disarm");
  assert.equal(unblockHold(null), "its head's pr-unblock statuses could not be read");
  assert.equal(unblockHold([]), null);
});

// The owner's approval of the head is the documented release of a hold-path
// escalation, so the lane takes its needs-human label off itself; nothing
// else does, and the approval control is the one ci-status applies.
test("a hold-path escalation lifts its label only on a trusted person's approval of the head", async () => {
  const LIFT = { method: "DELETE", path: `${ISSUES}/2/labels/needs-human` };
  const held = (discussion, files = HELD, overrides = {}) => pull(2, { files, labels: labels("needs-human"), verdict: PASSED, discussion, timeline: liftTimeline(), ...overrides });
  const escalated = [lanesSaid(personNote(HOLD_PATH_REASON))];
  const lifted = await run([held({ reviews: [reviewed("APPROVED")], comments: escalated })], trustedKyle());
  assert.deepEqual(lifted.notes, [LIFT]);
  assert.equal(lifted.writes.at(-1)?.mutation, "arm");

  const refused = {
    "an approval of another head": held({ reviews: [reviewed("APPROVED", { oid: "e".repeat(40) })], comments: escalated }),
    "an approval later dismissed": held({ reviews: [reviewed("APPROVED"), reviewed("DISMISSED", { at: "2026-10-26T17:00:00Z" })], comments: escalated }),
    "an approval by an account off the trusted-actor list": held({ reviews: [reviewed("APPROVED", { id: 9, login: "someone" })], comments: escalated }),
    "a cost escalation": held({ reviews: [reviewed("APPROVED")], comments: [lanesSaid(personNote(COST_REASON))] }, COST_FILES),
    "a hold path beside a risk hold": held({ reviews: [reviewed("APPROVED")], comments: [lanesSaid(personNote(BOTH))] }),
    "a label with no lane escalation": held({ reviews: [reviewed("APPROVED")], comments: [] }),
    "an escalation at an earlier head": held({ reviews: [reviewed("APPROVED")], comments: [lanesSaid(personNote(HOLD_PATH_REASON).replaceAll(HEAD, "e".repeat(40)))] }),
  };
  for (const [why, pr] of Object.entries(refused)) {
    const result = await run([pr], trustedKyle());
    assert.ok(!result.notes.some(({ method }) => method === "DELETE"), `${why} lifts nothing`);
    assert.ok(!result.writes.some(({ mutation }) => mutation === "arm"), `${why} arms nothing`);
  }

  const reportOnly = await run([held({ reviews: [reviewed("APPROVED")], comments: escalated })], { ...trustedKyle(), REPORT_ONLY: "true" });
  assert.deepEqual(reportOnly.notes.filter(({ method }) => method === "DELETE"), []);
  assert.ok(reportOnly.lines.some((line) => String(line).includes("would lift (report-only) needs-human")), reportOnly.lines.join("\n"));
});

// The same label carries holds that live only in the label: a pr-unblock
// escalation adds no labeled event when the label is already on, a review
// lane's or check-signed-commits' hold, a label a person added. Each case is
// the liftable timeline with one thing changed, and keeps the label for its
// own named reason.
test("an approved hold-path escalation keeps its label while anything else stands behind it", async () => {
  const held = (overrides) => pull(2, { files: HELD, labels: labels("needs-human"), verdict: PASSED, discussion: { reviews: [reviewed("APPROVED")], comments: [lanesSaid(personNote(HOLD_PATH_REASON))] }, timeline: liftTimeline(), ...overrides });
  const [note, label, approval] = liftTimeline();
  const after = "2026-10-24T09:00:00Z";
  const OLD = "e".repeat(40);
  const escalation = ["<!-- work-items:escalation lane=pr-unblock kind=escalated -->", `<!-- pr-unblock resume-key=${"a".repeat(40)} -->`, "- Reason: `security-finding`"].join("\n");
  const claude = { login: "claude[bot]", type: "Bot" };
  const actions = { login: "github-actions[bot]", type: "Bot" };
  const cases = {
    "a label a person added": [{ timeline: [note, labelEvent(KYLE, "2026-10-23T10:00:01Z"), approval] }, "was last added by kyle-sexton, not the lanes App"],
    "a label a pr-unblock escalation set before the refusal": [
      { timeline: [restSaid(APP_USER, escalation, "2026-10-22T09:00:00Z"), labelEvent(APP_USER, "2026-10-22T09:00:01Z"), { ...note, created_at: "2026-10-23T10:00:00Z" }, approval] },
      "does not pair with enable-auto-merge's refusal",
    ],
    "a pr-unblock escalation in the same second as the refusal": [
      { timeline: [restSaid(APP_USER, escalation, "2026-10-23T10:00:00Z"), note, label, approval] },
      "does not pair with enable-auto-merge's refusal",
    ],
    "a pr-unblock escalation since the label": [{ timeline: [note, label, restSaid(APP_USER, escalation, after), approval] }, "carries another marker: <!-- work-items:escalation lane=pr-unblock"],
    "a review lane's hold on an earlier head": [{ timeline: [note, label, restSaid(claude, `<!-- claude-lane-hold lane=claude-security-review sha=${OLD} criteria=security -->`, after), approval] }, "a review lane holds it"],
    "a review lane's hold the approval came after": [{ timeline: [restSaid(claude, `<!-- claude-lane-hold lane=claude-review sha=${OLD} criteria=intent -->`, "2026-10-22T09:00:00Z"), note, label, approval] }, "a review lane holds it"],
    // The second security review's probe: a hold on this head, a bot's
    // unlabel, the lane putting the label back, then the approval.
    "a hold on the head under a bot's unlabel and the lane's relabel": [
      { timeline: [note, label, restSaid(claude, `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=security -->`, after), labelEvent(actions, "2026-10-24T09:01:00Z", { event: "unlabeled" }), labelEvent(APP_USER, "2026-10-24T09:02:00Z"), approval] },
      `a review lane holds head ${HEAD}`,
    ],
    "a hold whose marker does not parse": [{ timeline: [note, label, restSaid(claude, "<!-- claude-lane-hold lane=claude-review sha=short -->", after), approval] }, "or its hold does not parse"],
    // A bot's unlabel lifts no earlier hold, even under a newly paired label.
    "an earlier head's hold under a bot's unlabel": [
      { timeline: [restSaid(APP_USER, personNote(HOLD_PATH_REASON), "2026-10-22T08:00:00Z"), labelEvent(APP_USER, "2026-10-22T08:00:01Z"), restSaid(claude, `<!-- claude-lane-hold lane=claude-review sha=${OLD} criteria=security -->`, "2026-10-22T09:00:00Z"), labelEvent(actions, "2026-10-22T09:30:00Z", { event: "unlabeled" }), note, label, approval] },
      "a review lane holds it",
    ],
    "a refusal posted longer than PAIRED_MS before the label": [{ timeline: [note, labelEvent(APP_USER, "2026-10-23T10:01:01Z"), approval] }, "does not pair with enable-auto-merge's refusal"],
    "check-signed-commits' hold": [{ timeline: [note, label, restSaid(actions, "<!-- check-signed-commits hold -->\nA lane commit is unverified.", after), approval] }, "check-signed-commits holds it"],
    "pr-verify's credential hold": [{ timeline: [note, label, restSaid(actions, "<!-- stop-reason lane=pr-verify reason=security -->\nReason: `security`", after), approval] }, "pr-verify holds it for a credential"],
    "a person's comment since the label": [{ timeline: [note, label, restSaid(KYLE, "Wait for the design call.", after), approval] }, "kyle-sexton spoke or labeled after needs-human went on"],
    "a person's label event since the label": [{ timeline: [note, label, labelEvent(KYLE, after, { name: "question" }), approval] }, "kyle-sexton spoke or labeled after needs-human went on"],
    "a person's reply on a review thread": [{ threadComments: [{ user: KYLE, created_at: after, updated_at: after }] }, "kyle-sexton spoke or labeled after needs-human went on"],
    "a person's review that is not an approval": [{ restReviews: [{ user: KYLE, state: "COMMENTED", submitted_at: after }] }, "kyle-sexton spoke or labeled after needs-human went on"],
    "a head that moved before the delete": [{ freshHead: "e".repeat(40) }, `its head moved to ${"e".repeat(40)}`],
    "a timeline that does not read": [{ timeline: undefined }, "the label's history did not read"],
  };
  for (const [why, [overrides, reason]] of Object.entries(cases)) {
    const result = await run([held(overrides)], trustedKyle());
    assert.ok(!result.notes.some(({ method }) => method === "DELETE"), `${why} lifts nothing`);
    assert.ok(!result.writes.some(({ mutation }) => mutation === "arm"), `${why} arms nothing`);
    assert.ok(result.lines.some((line) => String(line).startsWith("enable-auto-merge: #2 keeps needs-human: ") && String(line).includes(reason)), `${why}: ${result.lines.join("\n")}`);
  }
  // The approval itself, the refusal edited after the label and a bot's
  // comment are not a reason to keep it.
  // A person who removed the label lifted an earlier head's hold under it.
  const personLifted = await run([held({ timeline: [restSaid(claude, `<!-- claude-lane-hold lane=claude-review sha=${OLD} criteria=security -->`, "2026-10-22T09:00:00Z"), labelEvent(KYLE, "2026-10-22T09:30:00Z", { event: "unlabeled" }), note, label, approval] })], trustedKyle());
  assert.deepEqual(personLifted.notes, [{ method: "DELETE", path: `${ISSUES}/2/labels/needs-human` }]);
  const edited = { ...note, updated_at: after };
  const lifted = await run([held({ timeline: [edited, label, approval, restSaid(claude, "Review done, no findings.", after)], restReviews: [{ user: KYLE, state: "APPROVED", submitted_at: after }] })], trustedKyle());
  assert.deepEqual(lifted.notes, [{ method: "DELETE", path: `${ISSUES}/2/labels/needs-human` }]);
});

test("pythonClose runs the reader's capped-close at the base with the hold labels, and throws on a failed exit", () => {
  const seen = [];
  const spawn = (cmd, args, options) => {
    seen.push({ cmd, args, token: options.env.GH_TOKEN, deadline: options.env.BABYSIT_VERIFY_DEADLINE_SECONDS, caller: options.env.BABYSIT_VERIFY_CALLER, timeout: options.timeout });
    return { status: 0, stdout: '{"closed": true, "restarted": [7], "parked": []}\n' };
  };
  const base = "b".repeat(40);
  const env = { GITHUB_REPOSITORY: "o/r", GH_TOKEN: "app" };
  const answer = pythonClose(env, spawn)({ number: 5, headRefOid: HEAD, baseRefOid: base }, ["do-not-merge", "needs-human"]);
  assert.deepEqual(answer, { closed: true, restarted: [7], parked: [] });
  assert.equal(seen[0].cmd, "python3");
  assert.deepEqual(seen[0].args.slice(1), ["capped-close", "--repo", "o/r", "--base-sha", base, "--hold-label", "do-not-merge", "--hold-label", "needs-human", "5", HEAD]);
  // Its writes keep the lanes App token.
  assert.equal(seen[0].token, "app");
  // Its reader is told the 240 s limit it is killed at (DEADLINE_ENV).
  assert.deepEqual([seen[0].timeout, seen[0].deadline, seen[0].caller], [VERIFY_TIMEOUT_MS, "240", "enable-auto-merge.mjs"]);
  const failing = () => ({ status: 1, stdout: '{"closed": false, "error": "close: HTTP 403"}\n', stderr: "" });
  assert.throws(() => pythonClose(env, failing)({ number: 5, headRefOid: HEAD, baseRefOid: base }, []), /capped-close exited 1: close: HTTP 403/);
  assert.throws(() => pythonClose(env, spawn)({ number: 5, headRefOid: HEAD, baseRefOid: "main" }, []), /not a commit SHA/);
});

// merge.diff-check.path-holds (owner decision Q15): off, a gate script or a
// workflow on the floor arms, and a refusal naming only hold paths comes off
// with no approval; a cost path and the do-not-merge label still hold.
function pathHoldsOff() {
  const dir = tempDir("enable-auto-merge-");
  writeFileSync(join(dir, "resolved.json"), JSON.stringify({ merge: { "diff-check": { "denied-paths": ["docs/held.md"], "path-holds": false } } }));
  return { RESOLVED_CONFIG: join(dir, "resolved.json") };
}
const GATE_SCRIPT = [{ filename: ".github/scripts/pr-merge/clear-escalations.mjs" }];
const REVIEW_WORKFLOW = [{ filename: ".github/workflows/pr-review-main.yml" }];

test("with path holds on, a gate script or a floor workflow change is not armed", async () => {
  const { writes } = await run([pull(60, { files: GATE_SCRIPT }), pull(61, { files: REVIEW_WORKFLOW })]);
  assert.deepEqual(writes, []);
});

test("with path holds off, a gate script or a floor workflow change is armed and the skip is logged", async () => {
  const { writes, lines } = await run([pull(60, { files: GATE_SCRIPT }), pull(61, { files: REVIEW_WORKFLOW }), pull(62, { files: HELD })], pathHoldsOff());
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_60", head: HEAD },
    { mutation: "arm", id: "PR_61", head: HEAD },
    { mutation: "arm", id: "PR_62", head: HEAD },
  ]);
  assert.ok(
    lines.some((line) => line === "enable-auto-merge: #60 path holds are off (merge.diff-check.path-holds), so nothing holds it for this: it changes .github/scripts/pr-merge/clear-escalations.mjs, a hold path"),
    lines.join("\n"),
  );
});

test("with path holds off, a cost path and the do-not-merge label still hold", async () => {
  const { writes } = await run([pull(63, { files: COST_FILES }), pull(64, { files: GATE_SCRIPT, labels: labels("do-not-merge") })], pathHoldsOff());
  assert.deepEqual(writes, []);
});

test("with path holds off, a standing hold-path refusal comes off with no approval", async () => {
  const LIFT = { method: "DELETE", path: `${ISSUES}/2/labels/needs-human` };
  const reason = "it changes .github/scripts/pr-merge/clear-escalations.mjs, a hold path";
  const held = (comments, files = GATE_SCRIPT) =>
    pull(2, { files, labels: labels("needs-human"), verdict: PASSED, discussion: { comments }, timeline: liftTimeline(personNote(reason)).slice(0, 2) });
  const lifted = await run([held([lanesSaid(personNote(reason))])], { ...trustedKyle(), ...pathHoldsOff() });
  assert.deepEqual(lifted.notes, [LIFT]);
  assert.equal(lifted.writes.at(-1)?.mutation, "arm");
  assert.ok(lifted.lines.some((line) => String(line).includes("lifted needs-human: path holds are off")), lifted.lines.join("\n"));
  // On, the same refusal waits for a person's approval.
  const kept = await run([held([lanesSaid(personNote(reason))])], trustedKyle());
  assert.ok(!kept.notes.some(({ method }) => method === "DELETE"));
  // A refusal that also names a cost path stays.
  const cost = await run([held([lanesSaid(personNote(`${reason}\n${COST_REASON}`))], [...GATE_SCRIPT, ...COST_FILES])], { ...trustedKyle(), ...pathHoldsOff() });
  assert.ok(!cost.notes.some(({ method }) => method === "DELETE"));
});

// ci-status passes the base's merge.diff-check.path-holds as PATH_HOLDS.
test("merge-holds.mjs holds no hold path from the command line with PATH_HOLDS false, and still holds a cost path or a body hold", () => {
  const dir = tempDir("merge-holds-");
  const head = "0123456789abcdef0123456789abcdef01234567";
  const cli = (files, pathHolds, body = "Closes #1") => {
    writeFileSync(join(dir, "body"), body);
    writeFileSync(join(dir, "discussion"), "");
    writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "ana", id: 5 }] }));
    writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "denied"), JSON.stringify([]));
    const args = [...["7", "body", "discussion", "files", "denied", "actors"].map((name, index) => (index ? join(dir, name) : name)), head];
    const env = { ...process.env, GITHUB_REPOSITORY: "", ...(pathHolds === undefined ? {} : { PATH_HOLDS: pathHolds }) };
    delete env.GH_TOKEN;
    return spawnSync(process.execPath, [fileURLToPath(new URL("./merge-holds.mjs", import.meta.url)), ...args], { encoding: "utf8", env });
  };
  const gate = [".github/scripts/pr-merge/clear-escalations.mjs"];
  const off = cli([gate], "false");
  assert.equal(off.status, 0, off.stdout);
  assert.ok(off.stdout.split("\n").includes("#7: no body hold, no member veto and no hold path."), off.stdout);
  assert.ok(off.stdout.includes("#7: path holds are off (merge.diff-check.path-holds), so nothing holds it for this: it changes .github/scripts/pr-merge/clear-escalations.mjs, a hold path."), off.stdout);
  for (const on of [undefined, "true"]) {
    const held = cli([gate], on);
    assert.equal(held.status, 1, `PATH_HOLDS ${on}`);
    assert.match(held.stdout, /it changes \.github\/scripts\/pr-merge\/clear-escalations\.mjs, a hold path/);
  }
  assert.equal(cli([["infra/main.tf"]], "false").status, 1);
  assert.equal(cli([gate], "false", "Closes #1\n\nHold: wait for the owner").status, 1);
});

// The babysit gate's own path holds, recorded in a risk refusal before the
// switch went off, come off the same way; an unsafe path or any other code stays.
test("with path holds off, a standing risk refusal naming only path holds comes off", async () => {
  const LIFT = { method: "DELETE", path: `${ISSUES}/2/labels/needs-human` };
  const gate = ".github/scripts/pr-merge/clear-escalations.mjs";
  const risk = (codes) => `pr-merge's gate holds it on its risk score (${codes})`;
  const held = (reason) =>
    pull(2, { files: GATE_SCRIPT, labels: labels("needs-human"), verdict: PASSED, discussion: { comments: [lanesSaid(personNote(reason))] }, timeline: liftTimeline(personNote(reason)).slice(0, 2) });
  const off = { ...trustedKyle(), ...pathHoldsOff() };
  const lifted = await run([held(risk(`high-path:${gate}: ${gate}`))], off);
  assert.deepEqual(lifted.notes, [LIFT], lifted.lines.join("\n"));
  for (const [why, reason, env] of [
    ["path holds on", risk(`high-path:${gate}: ${gate}`), trustedKyle()],
    ["an unsafe path", risk("high-path:**: 'a' mode '120000' (symlink)"), off],
    ["a path hold beside an unbound review", risk(`high-path:${gate}: ${gate}; evidence-unbound:claude-review: evidence-missing`), off],
  ]) {
    const kept = await run([held(reason)], env);
    assert.ok(!kept.notes.some(({ method }) => method === "DELETE"), `${why} lifts nothing`);
  }
});

// GitHub Support's audit item 2, as babysit_merge_skip.py keys the merge
// gate's skip: an unarmed lanes App pull request whose last reader run left it
// on a lane's risk hold or a pr-unblock stop, with nothing written, is left on
// that refusal with no read while its head, update time, labels, check and
// status rollup and main's code all match. A check or status does not change
// `updatedAt`, so the rollup is in the key on its own.
const LANE_RISK = "lines-over: 900 changed lines, over the 800 cap";
const LANE_RISK_REASON = `pr-merge's gate holds it on its risk score (${LANE_RISK})`;
const LANE_RISK_HELD = { refusal: null, needsHuman: false, head: HEAD, ineligible: null, reviews: LANE_RISK, reviewsPerson: false, queue: UNEJECTED };
const check = (conclusion) => ({ contexts: { totalCount: 2, nodes: [
  { __typename: "CheckRun", databaseId: 11, name: "ci-status", status: "COMPLETED", conclusion },
  { __typename: "StatusContext", context: "pr-merge/unarmed", state: "PENDING", createdAt: "2026-10-23T09:00:00Z" },
] } });
const riskHeld = (overrides = {}) =>
  pull(1, { updatedAt: "2026-10-23T09:30:00Z", verdict: LANE_RISK_HELD, discussion: { comments: [lanesSaid(laneNote(LANE_RISK_REASON))] }, rollup: check("SUCCESS"), ...overrides });
const at = (minutes) => () => Date.parse(NOW) + minutes * 60_000;
// One reader run that keeps its skip records at `out`, from `from` when given.
async function skipRun(pulls, { from, minutes = 0, main: inputs = "main-1", env = {}, lane = ROOM } = {}) {
  const dir = tempDir("enable-auto-merge-skip-");
  const out = join(dir, "eam-skip.json");
  const result = await run(pulls, { EAM_SKIP_IN: from ?? join(dir, "none.json"), EAM_SKIP_OUT: out, ...env }, { now: at(minutes), mainInputs: () => inputs }, lane);
  let kept = null;
  try {
    kept = readFileSync(out, "utf8");
  } catch {}
  const path = join(dir, "kept.json");
  if (kept !== null) writeFileSync(path, kept);
  return { ...result, kept: kept === null ? null : JSON.parse(kept), from: path, details: result.calls.filter(({ body }) => body?.query === DETAIL_QUERY).length };
}

test("an unchanged lane risk hold is left on its refusal with no read, and counted", async () => {
  const first = await skipRun([riskHeld()]);
  assert.deepEqual(first.verified, [1]);
  assert.deepEqual(first.notes, []);
  assert.equal(first.kept.entries["1"]?.reason, LANE_RISK_REASON, first.lines.join("\n"));
  const second = await skipRun([riskHeld()], { from: first.from, minutes: 15 });
  assert.deepEqual(second.verified, []);
  assert.equal(second.details, 0);
  assert.equal(filesPages(second.calls), 0);
  assert.deepEqual(second.writes, []);
  assert.deepEqual(second.notes, []);
  assert.ok(second.lines.includes("enable-auto-merge: skip-unchanged skipped=1 recorded=0 keyed=1 of 1"), second.lines.join("\n"));
  assert.equal(second.kept.entries["1"].skips, 1);
});

test("a changed check rollup alone, with the same updatedAt, is read again", async () => {
  const first = await skipRun([riskHeld()]);
  const second = await skipRun([riskHeld({ rollup: check("FAILURE") })], { from: first.from, minutes: 15 });
  assert.deepEqual(second.verified, [1]);
  assert.equal(second.details, 1);
  assert.ok(second.lines.some((line) => line.startsWith("enable-auto-merge: skip-unchanged skipped=0 ")));
});

// As babysit_merge_skip.py keys them: a thread resolved, a review or a
// comment edited need not move `updatedAt`.
test("a resolved review thread, a review or an edited comment alone, with the same updatedAt, is read again", async () => {
  const threads = (isResolved) => ({ stateThreads: { totalCount: 1, nodes: [{ isResolved, isOutdated: false }] } });
  const first = await skipRun([riskHeld(threads(false))]);
  assert.equal((await skipRun([riskHeld(threads(false))], { from: first.from, minutes: 15 })).details, 0);
  for (const [name, changed] of Object.entries({
    thread: threads(true),
    review: { ...threads(false), reviewCount: 1 },
    decision: { ...threads(false), reviewDecision: "APPROVED" },
    comment: { ...threads(false), stateComments: { totalCount: 1, nodes: [{ databaseId: 5, updatedAt: "2026-10-23T10:05:00Z" }] } },
  })) {
    assert.equal((await skipRun([riskHeld(changed)], { from: first.from, minutes: 15 })).details, 1, name);
  }
});

test("a changed head, update time, label set or main is read again, and an armed one always is", async () => {
  const first = await skipRun([riskHeld()]);
  const cases = {
    head: [riskHeld({ headRefOid: "c".repeat(40), verdict: { ...LANE_RISK_HELD, head: "c".repeat(40) } }), {}],
    updatedAt: [riskHeld({ updatedAt: "2026-10-23T10:05:00Z" }), {}],
    labels: [riskHeld({ labels: labels("ci") }), {}],
    main: [riskHeld(), { main: "main-2" }],
    // The rung the gate scores the risk at (pythonVerify's `rung`).
    rung: [riskHeld(), { lane: { ...ROOM, rung: "C3" } }],
    armed: [riskHeld({ autoMergeRequest: { enabledAt: "2026-10-23T10:01:00Z" } }), {}],
  };
  for (const [name, [changed, options]] of Object.entries(cases)) {
    const again = await skipRun([changed], { from: first.from, minutes: 15, ...options });
    assert.equal(again.details, 1, name);
  }
});

test("a skip record is read again past max-minutes, after max-skips, and never when either is 0", async () => {
  const first = await skipRun([riskHeld()]);
  // The lane comment escalates at 60 minutes, so 50 stays inside both bounds.
  assert.equal((await skipRun([riskHeld()], { from: first.from, minutes: 50, env: { SKIP_MAX_MINUTES: "45" } })).details, 1);
  let from = first.from;
  for (const minutes of [15, 30]) {
    from = (await skipRun([riskHeld()], { from, minutes, env: { SKIP_MAX_SKIPS: "2" } })).from;
  }
  assert.equal((await skipRun([riskHeld()], { from, minutes: 45, env: { SKIP_MAX_SKIPS: "2" } })).details, 1);
  assert.equal((await skipRun([riskHeld()], { from: first.from, minutes: 15, env: { SKIP_MAX_MINUTES: "0" } })).details, 1);
});

test("a lane hold due to escalate to a failing status is read again at its escalation", async () => {
  // max-minutes past the escalation, so only the escalation bounds the skip.
  const env = { SKIP_MAX_MINUTES: "120" };
  const first = await skipRun([riskHeld()], { env });
  assert.equal((await skipRun([riskHeld()], { from: first.from, minutes: 59, env })).details, 0);
  const late = await skipRun([riskHeld()], { from: first.from, minutes: 61, env });
  assert.equal(late.details, 1);
  assert.deepEqual(late.statuses, [{ sha: HEAD, state: "failure", description: LANE_RISK_REASON }]);
});

test("a refusal that wrote, a verdict refusal and an event run keep no skip record", async () => {
  // The first lane comment is written, or a changed reason edited in, so the
  // next run reads again.
  for (const comments of [[], [lanesSaid(laneNote("pr-merge's gate holds it on its risk score (lines-over: 850 changed lines)"))]]) {
    const wrote = await skipRun([riskHeld({ discussion: { comments } })]);
    assert.equal(wrote.notes.length, 1);
    assert.deepEqual(wrote.kept.entries, {});
  }
  // A verdict a later artifact may answer differently, with no change to the key.
  const missing = await skipRun([riskHeld({ verdict: MISSING, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON))] } })]);
  assert.deepEqual(missing.kept.entries, {});
  const event = await skipRun([riskHeld()], { env: { EVENT_NAME: "pull_request_target", EVENT_PR: "1" } });
  assert.equal(event.kept, null);
});

test("a skip record of another repository, from the future, or malformed skips nothing", async () => {
  const first = await skipRun([riskHeld()]);
  const kept = JSON.parse(readFileSync(first.from, "utf8"));
  const dir = tempDir("enable-auto-merge-skip-bad-");
  const forged = {
    repo: { ...kept, repo: "someone/else" },
    future: { ...kept, entries: { 1: { ...kept.entries["1"], at: "2026-10-23T11:00:00.000Z" } } },
    malformed: { ...kept, entries: { 1: { ...kept.entries["1"], skips: "0" } } },
  };
  for (const [name, data] of Object.entries(forged)) {
    const path = join(dir, `${name}.json`);
    writeFileSync(path, JSON.stringify(data));
    assert.equal((await skipRun([riskHeld()], { from: path, minutes: 15 })).details, 1, name);
  }
});
